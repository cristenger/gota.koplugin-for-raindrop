--[[
    API Module for Gota Plugin
    Handles all HTTP communication with Raindrop.io API
]]

local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local JSON = require("json")
local logger = require("logger")
local _ = require("gettext")

local API = {}

local function urlEncode(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("([^%w%-%.%_%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = str:gsub(" ", "+")
    return str
end

function API:new(settings, server_url)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o.settings = settings
    o.server_url = server_url or "https://api.raindrop.io/rest/v1"
    o.response_cache = {}
    o.cache_ttl = 300 -- 5 minutes

    -- Disable SSL verification for e-ink device compatibility
    https.cert_verify = false

    return o
end

function API:makeRequest(endpoint, method, body)
    local url = self.server_url .. endpoint
    logger.dbg("Gota API: request", method or "GET", endpoint)

    -- Use longer timeouts for cache/file downloads
    local is_file_download = endpoint:match("/cache$")
    if is_file_download then
        socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    else
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    end

    local sink = {}
    local request = {
        url     = url,
        method  = method or "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.settings:getToken(),
            ["Content-Type"]  = "application/json",
            ["User-Agent"]    = "KOReader-Gota-Plugin/2.2",
            ["Accept-Encoding"] = "gzip, identity",
        },
        sink    = socketutil.table_sink(sink),
        protocol = "any",
    }

    if body then
        request.headers["Content-Length"] = tostring(#body)
        request.source = ltn12.source.string(body)
    end

    local protocol_mod = url:match("^https://") and https or http
    local pcall_ok, ok, actual_status, headers = pcall(protocol_mod.request, request)
    socketutil:reset_timeout()

    if not pcall_ok then
        -- protocol_mod.request threw an error (rare but possible)
        logger.err("Gota API: request error:", ok) -- ok contains the error message here
        return nil, _("HTTP error ") .. tostring(ok)
    end

    if ok and actual_status == 200 then
        local resp = table.concat(sink)

        if #resp == 0 then
            return nil, _("Empty server response")
        end

        -- Gzip handling
        local is_gzipped = false
        if headers and headers["content-encoding"] then
            is_gzipped = headers["content-encoding"]:lower():find("gzip") ~= nil
        end
        local might_be_gzipped = resp:byte(1) == 31 and resp:byte(2) == 139

        if is_gzipped or might_be_gzipped then
            resp = self:decompressGzip(resp)
            if not resp then
                return nil, _("Error: Could not decompress server response")
            end
        end

        -- Cache endpoint returns raw HTML, not JSON
        if is_file_download then
            return resp
        end

        local data, parse_err = JSON.decode(resp)
        if data then
            return data, nil
        else
            logger.err("Gota API: JSON parse error:", parse_err)
            return nil, _("Error processing server response")
        end
    elseif ok and actual_status ~= 200 then
        local msg = _("Server error: ") .. tostring(actual_status)
        if headers then
            local R = headers["x-ratelimit-remaining"]
            if R and tonumber(R) and tonumber(R) < 5 then
                msg = msg .. _(" (rate limit remaining: ") .. R .. ")"
            end
        end
        return nil, msg
    else
        logger.err("Gota API: HTTP error", actual_status)
        return nil, _("HTTP error ") .. tostring(actual_status)
    end
end

function API:decompressGzip(resp)
    local temp_in = "/tmp/gota_gzip_" .. os.time() .. ".gz"
    local temp_out = "/tmp/gota_out_" .. os.time() .. ".txt"

    local file = io.open(temp_in, "wb")
    if not file then
        logger.err("Gota API: could not create temp file for decompression")
        return nil
    end

    file:write(resp)
    file:close()

    local ok = os.execute("gunzip -c " .. temp_in .. " > " .. temp_out .. " 2>/dev/null")
    if ok ~= 0 then
        ok = os.execute("gzip -dc " .. temp_in .. " > " .. temp_out .. " 2>/dev/null")
    end

    if ok == 0 then
        file = io.open(temp_out, "rb")
        if file then
            resp = file:read("*all")
            file:close()
        end
    end

    os.remove(temp_in)
    os.remove(temp_out)

    -- Verify decompression succeeded
    if resp:byte(1) == 31 and resp:byte(2) == 139 then
        return nil
    end

    return resp
end

function API:makeRequestWithRetry(endpoint, method, body, max_retries)
    max_retries = max_retries or 3

    for attempt = 1, max_retries do
        if attempt > 1 then
            logger.warn("Gota API: retry", attempt, "of", max_retries)
        end

        local result, err = self:makeRequest(endpoint, method, body)

        -- Return on success or non-transient errors
        if result then
            return result, nil
        end
        if err and not err:match("timeout") and not err:match(socketutil.TIMEOUT_CODE or "timeout") then
            return nil, err
        end

        logger.warn("Gota API: transient error, will retry:", err)
    end

    return nil, _("Failed after ") .. max_retries .. _(" attempts")
end

function API:cachedRequest(endpoint, method, body, use_cache)
    method = method or "GET"
    use_cache = (use_cache == nil) and (method == "GET") or use_cache

    if use_cache and method == "GET" then
        local cached = self.response_cache[endpoint]
        if cached and os.time() - cached.timestamp < self.cache_ttl then
            return cached.data, nil
        end
    end

    local result, err = self:makeRequestWithRetry(endpoint, method, body)

    if result and method == "GET" and use_cache then
        self.response_cache[endpoint] = {
            data = result,
            timestamp = os.time(),
        }
    end

    return result, err
end

-- Cache management

function API:clearCache()
    self.response_cache = {}
end

function API:clearCacheFor(endpoint_prefix)
    -- Collect keys first, then delete (safe table mutation)
    local to_remove = {}
    for key in pairs(self.response_cache) do
        -- Use plain string find (not pattern) to handle special chars like "-"
        if key:find(endpoint_prefix, 1, true) then
            to_remove[#to_remove + 1] = key
        end
    end
    for _, key in ipairs(to_remove) do
        self.response_cache[key] = nil
    end
end

-- Raindrop.io API endpoints

function API:getUser()
    return self:cachedRequest("/user")
end

function API:getCollections()
    return self:cachedRequest("/collections")
end

function API:getRaindrops(collection_id, page, perpage, sort)
    page = page or 0
    perpage = perpage or 25
    local endpoint = string.format("/raindrops/%s?perpage=%d&page=%d", collection_id, perpage, page)
    if sort and sort ~= "" then
        endpoint = endpoint .. "&sort=" .. urlEncode(sort)
    end
    return self:cachedRequest(endpoint)
end

function API:getRaindrop(raindrop_id)
    return self:cachedRequest("/raindrop/" .. raindrop_id)
end

function API:getRaindropCache(raindrop_id)
    return self:makeRequestWithRetry("/raindrop/" .. raindrop_id .. "/cache")
end

function API:searchRaindrops(search_term, page, perpage, filters)
    page = page or 0
    perpage = perpage or 25

    local params = string.format("perpage=%d&page=%d", perpage, page)
    local combined_search = search_term or ""

    if filters then
        if filters.tag then
            local tag_search = "#" .. filters.tag
            if combined_search ~= "" then
                combined_search = combined_search .. " " .. tag_search
            else
                combined_search = tag_search
            end
        end
        if filters.type then
            params = params .. "&type=" .. urlEncode(filters.type)
        end
        if filters.important ~= nil then
            params = params .. "&important=" .. (filters.important and "true" or "false")
        end
    end

    if combined_search ~= "" then
        params = params .. "&search=" .. urlEncode(combined_search)
    end

    local endpoint = "/raindrops/0?" .. params
    return self:cachedRequest(endpoint)
end

function API:getFilters(collection_id, search_term)
    collection_id = collection_id or 0
    local params = ""
    if search_term and search_term ~= "" then
        params = "?search=" .. urlEncode(search_term)
    end
    return self:cachedRequest(string.format("/filters/%s%s", collection_id, params))
end

function API:getTags(collection_id)
    collection_id = collection_id or 0
    return self:cachedRequest(string.format("/tags/%s", collection_id))
end

function API:testToken(token)
    local old_token = self.settings:getToken()
    self.settings:setToken(token)
    local user_data, err = self:makeRequestWithRetry("/user")
    self.settings:setToken(old_token)
    return user_data, err
end

return API
