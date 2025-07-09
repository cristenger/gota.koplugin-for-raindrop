local http    = require("socket.http")
local https   = require("ssl.https")
local ltn12   = require("ltn12")
local JSON    = require("json")
local logger  = require("logger")

local Api = {}

--------------------------------------------------
-- inicialización
--------------------------------------------------
function Api:init(state)
    self.state       = state              -- objeto Gota
    self.cache       = {}                 -- { key = { ts=epoch, data=table } }
    self.cache_ttl   = state.cache_ttl or 300
    https.cert_verify = false             -- ya se hacía en init.lua, repetimos por si acaso
end

--------------------------------------------------
-- utilidades internas
--------------------------------------------------
local function _cacheKey(method, url, body)
    return table.concat({ method or "GET", url, body or "" }, "#")
end

local function _decode(str)
    if not str or str == "" then return nil, "vacío" end
    local ok, t = pcall(JSON.decode, str)
    if ok then return t end
    return nil, "JSON inválido"
end

--------------------------------------------------
-- solicitud HTTP cruda
--------------------------------------------------
function Api:makeRequest(endpoint, method, body)
    method = method or "GET"
    local url = self.state.server_url .. endpoint
    logger.dbg("Gota/API:", method, url)

    local payload = body and JSON.encode(body) or nil
    local sink, resp = {}, {}
    local req = {
        url     = url,
        method  = method,
        source  = payload and ltn12.source.string(payload) or nil,
        sink    = ltn12.sink.table(resp),
        headers = {
            ["Accept"]          = "application/json",
            ["Accept-Encoding"] = "identity",
        },
    }
    if self.state.token and self.state.token ~= "" then
        req.headers["Authorization"] = "Bearer " .. self.state.token
    end
    if payload then
        req.headers["Content-Type"]   = "application/json"
        req.headers["Content-Length"] = #payload
    end

    local ok, status, hdrs, code
    ok, status, hdrs, code = pcall(https.request, req)
    if not ok then
        -- algunos Kindles no aceptan SSL → reintentar con http
        logger.warn("Gota/API: HTTPS error, fallback a HTTP:", status)
        ok, status, hdrs, code = pcall(http.request, req)
    end
    if not ok then
        return nil, "Conexión fallida: " .. tostring(status)
    end
    local body_str = table.concat(resp)
    if code ~= 200 then
        return nil, "HTTP " .. tostring(code)
    end
    return body_str
end

--------------------------------------------------
-- con reintentos simples
--------------------------------------------------
function Api:makeRequestWithRetry(endpoint, method, body, retries)
    retries = retries or 1
    local data, err
    for i = 1, retries + 1 do
        data, err = self:makeRequest(endpoint, method, body)
        if data then return data end
        logger.warn("Gota/API: intento", i, "falló:", err)
    end
    return nil, err
end

--------------------------------------------------
-- con caché en memoria
--------------------------------------------------
function Api:cachedRequest(endpoint, method, body, ttl)
    ttl = ttl or self.cache_ttl
    local url = self.state.server_url .. endpoint
    local key = _cacheKey(method, url, body and JSON.encode(body) or "")
    local entry = self.cache[key]
    if entry and (os.time() - entry.ts) < ttl then
        return entry.data
    end

    local raw, err = self:makeRequestWithRetry(endpoint, method, body, 1)
    if not raw then return nil, err end
    local data, jerr = _decode(raw)
    if not data then return nil, jerr end

    self.cache[key] = { ts = os.time(), data = data }
    return data
end

return Api