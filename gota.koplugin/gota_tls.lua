-- Per-request TLS policy. LuaSec verifies certificate chains, but its HTTPS
-- client does not check the hostname. Check the leaf certificate's SAN before
-- LuaSocket sends the request line or any Authorization header.
local http = require("socket.http")
local https = require("ssl.https")
local _ = require("gota_gettext")

local TLS = {}
local SAN_OID = "2.5.29.17"
local CA_FILES = {
    "./data/ca-bundle.crt", -- KOReader's bundled certifi store (also used by curl).
    "/etc/ssl/certs/ca-certificates.crt",
    "/etc/ssl/cert.pem",
    "/etc/pki/tls/certs/ca-bundle.crt",
}

local function readableFile(path)
    if type(path) ~= "string" or path == "" or path:find("%c") then return false end
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function dnsName(value)
    if type(value) ~= "string" or #value > 253 or value:find("[^%w%.%-]") then return nil end
    value = value:lower():gsub("%.$", "")
    if value == "" or value:find("..", 1, true) then return nil end
    for label in value:gmatch("[^.]+") do
        if #label > 63 or label:sub(1, 1) == "-" or label:sub(-1) == "-" then return nil end
    end
    return value
end

local function matchesDNSName(host, certificate_name)
    host = dnsName(host)
    if not host or type(certificate_name) ~= "string" then return false end
    if certificate_name:sub(1, 2) ~= "*." then
        return host == dnsName(certificate_name)
    end
    local suffix = dnsName(certificate_name:sub(3))
    -- Permit a whole leftmost label only. Never accept a wildcard for a TLD,
    -- multiple labels, embedded wildcards, or control/NUL characters.
    if not suffix or not suffix:find(".", 1, true) then return false end
    local first_label, host_suffix = host:match("^([^.]+)%.(.+)$")
    return first_label ~= nil and host_suffix == suffix
end

local function certificateMatchesHost(certificate, host)
    if not certificate or type(certificate.extensions) ~= "function" then return false end
    local ok, extensions = pcall(certificate.extensions, certificate)
    local san = ok and type(extensions) == "table" and extensions[SAN_OID]
    if type(san) ~= "table" then return false end
    -- Raindrop and its copy storage use DNS names. IPv4 literals require an IP
    -- SAN; IPv6 literals are deliberately unsupported instead of comparing
    -- differently formatted addresses. No obsolete common-name fallback.
    if host:match("^%d+%.%d+%.%d+%.%d+$") then
        for _, address in ipairs(san.iPAddress or {}) do
            if address == host then return true end
        end
    else
        for _, name in ipairs(san.dNSName or {}) do
            if matchesDNSName(host, name) then return true end
        end
    end
    return false
end

TLS.matchesDNSName = matchesDNSName
TLS.certificateMatchesHost = certificateMatchesHost

function TLS:new(settings)
    local instance = { settings = settings, validation_observed = false }
    self.__index = self
    return setmetatable(instance, self)
end

function TLS:isVerificationEnabled()
    return not (self.settings.isTLSVerificationEnabled and
        self.settings:isTLSVerificationEnabled() == false)
end

function TLS:getCAFile()
    if self.settings.getTLSCAFile then
        local configured = self.settings:getTLSCAFile()
        if configured and configured ~= "" then
            return readableFile(configured) and configured or nil
        end
    end
    for _, path in ipairs(CA_FILES) do
        if readableFile(path) then return path end
    end
end

function TLS:getSecurityInfo()
    local enabled = self:isVerificationEnabled()
    local capable = type(https.tcp) == "function" and type(http.request) == "function"
        and self:getCAFile() ~= nil
    return {
        encrypted = true,
        verification_enabled = enabled,
        peer_authenticated = enabled and capable,
        hostname_verified = enabled and capable,
        validation_observed = enabled and self.validation_observed,
        limitation = not enabled and "Certificate verification explicitly disabled"
            or (not capable and "TLS verification or CA store unavailable" or nil),
    }
end

function TLS:request(request)
    self.validation_observed = false
    self.last_error_was_verification = false
    if not self:isVerificationEnabled() then
        request.verify = "none"
        return https.request(request)
    end
    local cafile = self:getCAFile()
    if not cafile then
        self.last_error_was_verification = true
        return nil, _("TLS certificate store is unavailable")
    end
    if type(https.tcp) ~= "function" or type(http.request) ~= "function" then
        self.last_error_was_verification = true
        return nil, _("This KOReader runtime cannot verify HTTPS connections")
    end
    request.verify = "peer"
    request.cafile = cafile
    request.options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1", "no_tlsv1_1" }
    local create = https.tcp(request)
    request.create = function()
        local connection = create()
        local connect = connection.connect
        connection.connect = function(conn, host, port)
            local connected, connection_error = connect(conn, host, port)
            if not connected then return nil, connection_error end
            local certificate = conn.getpeercertificate and conn:getpeercertificate()
            if not certificateMatchesHost(certificate, host) then
                self.last_error_was_verification = true
                if conn.close then pcall(conn.close, conn) end
                return nil, _("TLS certificate does not match the server hostname")
            end
            self.validation_observed = true
            return connected
        end
        return connection
    end
    -- LuaSec's https.request forbids create; LuaSocket accepts it and waits for
    -- connect to succeed before sending HTTP. The factory retains LuaSec SNI,
    -- chain verification, and KOReader's socketutil timeout patches.
    local result, status, headers, status_line = http.request(request)
    if not result and tostring(status):lower():find("certificate", 1, true) then
        self.last_error_was_verification = true
    end
    return result, status, headers, status_line
end

return TLS
