--[[
    Gota API Module
    Handles all HTTP communication with Raindrop.io API
]]

local https = require("ssl.https")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local JSON = require("json")
local logger = require("logger")
local _ = require("gettext")
local Version = require("gota_version")

local API = {}

local MAX_REDIRECTS = 3
local MAX_RETRY_DELAY = 30
local MAX_BLOCKING_RETRY_DELAY = 3
local MAX_PER_PAGE = 50

local REDIRECT_STATUSES = {
    [301] = true,
    [302] = true,
    [303] = true,
    [307] = true,
    [308] = true,
}

local HTTP_METHODS = {
    GET = true,
    POST = true,
    PUT = true,
    PATCH = true,
    DELETE = true,
    HEAD = true,
}

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function urlEncode(str)
    if str == nil then return "" end
    str = tostring(str)
    str = str:gsub("([^%w%-%.%_%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str:gsub(" ", "+")
end

local function quoteSearchValue(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\"):gsub('"', '\\"')
    return '"' .. value .. '"'
end

local function searchValue(value)
    value = trim(value)
    if value:match("^[%w%-%._]+$") then
        return value
    end
    return quoteSearchValue(value)
end

local function appendSearchPart(parts, value)
    value = trim(value)
    if value ~= "" then
        parts[#parts + 1] = value
    end
end

local function buildSearchExpression(search_term, filters)
    local parts = {}
    appendSearchPart(parts, search_term)

    if filters then
        if filters.tag ~= nil then
            local tag = trim(filters.tag):gsub("^#", "")
            if tag ~= "" then
                parts[#parts + 1] = "#" .. searchValue(tag)
            end
        end

        if filters.type ~= nil then
            local content_type = trim(filters.type):lower()
            if content_type ~= "" then
                parts[#parts + 1] = "type:" .. searchValue(content_type)
            end
        end

        -- Raindrop documents the heart operator for Favorites and the generic
        -- leading-minus syntax for excluding a filter.
        if filters.important ~= nil then
            parts[#parts + 1] = filters.important and "❤️" or "-❤️"
        end
    end

    return table.concat(parts, " ")
end

local function normalizeInteger(value, default_value, minimum, maximum)
    if value == nil then value = default_value end
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge
        or number ~= math.floor(number) then
        return nil
    end
    if minimum ~= nil and number < minimum then return nil end
    if maximum ~= nil and number > maximum then return nil end
    return number
end

local function normalizePagination(page, perpage)
    local normalized_page = normalizeInteger(page, 0, 0)
    if normalized_page == nil then
        return nil, nil, _("Page must be a non-negative integer")
    end

    local normalized_perpage = normalizeInteger(perpage, 25, 1, MAX_PER_PAGE)
    if normalized_perpage == nil then
        return nil, nil, _("Items per page must be between 1 and 50")
    end
    return normalized_page, normalized_perpage, nil
end

local function normalizeCollectionId(collection_id, default_value)
    local id = normalizeInteger(collection_id, default_value)
    if id == nil or (id < 0 and id ~= -1 and id ~= -99) then
        return nil, _("Invalid collection ID")
    end
    return tostring(id), nil
end

local function normalizeRaindropId(raindrop_id)
    local id = normalizeInteger(raindrop_id, nil, 1)
    if id == nil then
        return nil, _("Invalid raindrop ID")
    end
    return tostring(id), nil
end

local function isSafeHttpsUrl(url)
    if type(url) ~= "string" or url:find("[%c%s\\]") then
        return false
    end
    local authority = url:match("^https://([^/%?#]+)")
    return authority ~= nil and authority ~= "" and not authority:find("@", 1, true)
end

local function getHeader(headers, name)
    if type(headers) ~= "table" then return nil end
    local wanted = name:lower()
    for key, value in pairs(headers) do
        if type(key) == "string" and key:lower() == wanted then
            return value
        end
    end
    return nil
end

local function safeJsonDecode(payload)
    local ok, data, decode_error = pcall(JSON.decode, payload)
    if not ok then
        return nil, tostring(data)
    end
    if data == nil then
        return nil, tostring(decode_error or "unknown JSON error")
    end
    return data, nil
end

local function compactText(value, max_length)
    value = trim(value):gsub("[%c]+", " ")
    max_length = max_length or 180
    if #value > max_length then
        return value:sub(1, max_length) .. "..."
    end
    return value
end

local function responseErrorMessage(payload)
    if not payload or payload == "" then return nil end

    local data = safeJsonDecode(payload)
    if type(data) == "table" then
        local candidates = {}
        candidates[#candidates + 1] = data.errorMessage
        candidates[#candidates + 1] = data.message
        candidates[#candidates + 1] = data.errorDetails
        local nested_error = type(data.error) == "table"
            and (data.error.message or data.error.errorMessage) or data.error
        candidates[#candidates + 1] = nested_error
        for _, candidate in ipairs(candidates) do
            if candidate ~= nil and trim(candidate) ~= "" then
                return compactText(candidate)
            end
        end
    end

    if not payload:match("^%s*<") then
        return compactText(payload)
    end
    return nil
end

local function rateLimitRemaining(headers)
    return getHeader(headers, "X-RateLimit-Remaining")
        or getHeader(headers, "RateLimit-Remaining")
end

local function retryDelay(attempt, status, headers)
    local base_delay = math.min(0.5 * (2 ^ math.max(0, attempt - 1)), 4)
    if status ~= 429 then
        return base_delay
    end

    local retry_after = tonumber(getHeader(headers, "Retry-After"))
    if retry_after and retry_after >= 0 then
        return math.min(math.max(retry_after, 0.25), MAX_RETRY_DELAY)
    end

    local reset_at = tonumber(getHeader(headers, "X-RateLimit-Reset")
        or getHeader(headers, "RateLimit-Reset"))
    if reset_at then
        local until_reset = reset_at - os.time()
        if until_reset > 0 then
            return math.min(until_reset, MAX_RETRY_DELAY)
        end
    end

    return math.min(math.max(base_delay, 1), MAX_RETRY_DELAY)
end

-- Pure helpers are public so they can be unit-tested without a KOReader runtime.
API.urlEncode = urlEncode
API.buildSearchExpression = buildSearchExpression
API.isSafeHttpsUrl = isSafeHttpsUrl
API.getHeader = getHeader
API.retryDelay = retryDelay
API.normalizePagination = normalizePagination

function API:new(settings, server_url)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o.settings = settings
    o.server_url = (server_url or "https://api.raindrop.io/rest/v1"):gsub("/+$", "")
    if not isSafeHttpsUrl(o.server_url) or o.server_url:find("[?#]") then
        error("Gota API server URL must be a valid HTTPS URL without embedded credentials", 2)
    end
    o.response_cache = {}
    o.cache_ttl = 300 -- 5 minutes
    o.sleep = socket.sleep

    -- Do not mutate ssl.https.cert_verify: it is shared by all plugins.
    -- KOReader currently bundles LuaSec 1.3.2, whose HTTPS client defaults to
    -- verify="none"; retaining that runtime default preserves Kindle support.
    return o
end

function API:_performRequest(url, method, body, include_authorization, is_file_download)
    local sink = {}
    local headers = {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = Version.user_agent,
        ["Accept-Encoding"] = "identity",
    }

    if include_authorization then
        local token = self.settings:getToken()
        if not token or token == "" then
            return nil, _("Authentication token is missing")
        end
        headers["Authorization"] = "Bearer " .. token
    end

    local request = {
        url = url,
        method = method,
        headers = headers,
        sink = socketutil.table_sink(sink),
        protocol = "any",
        -- Redirects are followed explicitly so Authorization never crosses hosts.
        redirect = false,
    }

    if body then
        headers["Content-Length"] = tostring(#body)
        request.source = ltn12.source.string(body)
    end

    local call_ok, request_result, actual_status, response_headers, status_line
    local wrapper_ok, wrapper_error = pcall(function()
        if is_file_download then
            socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
        else
            socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
        end
        call_ok, request_result, actual_status, response_headers, status_line = pcall(https.request, request)
    end)

    local reset_ok, reset_error = pcall(function() socketutil:reset_timeout() end)
    if not reset_ok then
        logger.err("Gota API: failed to reset socket timeout:", reset_error)
    end

    if not wrapper_ok then
        logger.err("Gota API: request setup error:", wrapper_error)
        return nil, _("HTTP error: ") .. tostring(wrapper_error), nil, nil, nil, true
    end
    if not call_ok then
        logger.err("Gota API: request exception:", request_result)
        return nil, _("HTTP error: ") .. tostring(request_result), nil, nil, nil, true
    end
    if not request_result then
        logger.err("Gota API: HTTP transport error:", actual_status)
        return nil, _("HTTP error: ") .. tostring(actual_status), nil, nil, nil, true
    end

    return table.concat(sink), nil, tonumber(actual_status), response_headers or {}, status_line
end

function API:makeRequest(endpoint, method, body)
    if type(endpoint) ~= "string" or endpoint:sub(1, 1) ~= "/"
        or endpoint:find("[%c%s\\]") then
        return nil, _("Invalid API endpoint")
    end

    method = tostring(method or "GET"):upper()
    if not HTTP_METHODS[method] then
        return nil, _("Unsupported HTTP method: ") .. method
    end
    local is_file_download = endpoint:match("/cache$") ~= nil
        or endpoint:match("/cache%?[^/]*$") ~= nil
    local url = self.server_url .. endpoint
    local include_authorization = true
    local redirect_count = 0

    logger.dbg("Gota API: request", method, endpoint)

    while true do
        local payload, transport_error, status, headers, status_line, transient_transport_error =
            self:_performRequest(url, method, body, include_authorization, is_file_download)
        if not payload then
            return nil, transport_error, status, headers, transient_transport_error
        end

        if status and status >= 300 and status < 400 then
            local location = getHeader(headers, "Location")
            if not REDIRECT_STATUSES[status] or not is_file_download or not location then
                return nil, _("Unexpected redirect from server: ") .. tostring(status), status, headers
            end
            if redirect_count >= MAX_REDIRECTS then
                return nil, _("Too many redirects while downloading cached article"), status, headers
            end
            if not isSafeHttpsUrl(location) then
                return nil, _("Refused an unsafe cache redirect"), status, headers
            end

            redirect_count = redirect_count + 1
            url = location
            if status ~= 307 and status ~= 308 then
                method = "GET"
                body = nil
            end
            include_authorization = false
            logger.dbg("Gota API: following safe cache redirect", redirect_count)
        else
            if not status then
                return nil, _("HTTP response did not include a status code"), nil, headers
            end

            if status >= 200 and status < 300 then
                if status == 204 and not is_file_download then
                    return true, nil, status, headers
                end
                if #payload == 0 then
                    return nil, _("Empty server response"), status, headers
                end

                local content_encoding = trim(getHeader(headers, "Content-Encoding")):lower()
                local has_gzip_signature = payload:byte(1) == 31 and payload:byte(2) == 139
                if (content_encoding ~= "" and content_encoding ~= "identity") or has_gzip_signature then
                    return nil, _("Server ignored the requested identity content encoding"), status, headers
                end

                if is_file_download then
                    return payload, nil, status, headers
                end

                local data, parse_error = safeJsonDecode(payload)
                if data ~= nil then
                    if type(data) == "table" and data.result == false then
                        local detail = responseErrorMessage(payload)
                            or _("Raindrop rejected the request")
                        return nil, _("API error: ") .. detail, status, headers
                    end
                    return data, nil, status, headers
                end
                logger.err("Gota API: JSON parse error:", parse_error)
                return nil, _("Invalid JSON response: ") .. compactText(parse_error), status, headers
            end

            local message = _("Server error: ") .. tostring(status)
            local detail = responseErrorMessage(payload)
            if detail then
                message = message .. " - " .. detail
            elseif status_line and status_line ~= "" then
                message = message .. " - " .. compactText(status_line)
            end
            local remaining = rateLimitRemaining(headers)
            if remaining then
                message = message .. _(" (rate limit remaining: ") .. tostring(remaining) .. ")"
            end
            if status == 429 then
                message = message .. _(" (retry after ") ..
                    tostring(math.ceil(retryDelay(1, status, headers))) .. _(" seconds)")
            end
            return nil, message, status, headers
        end
    end
end

function API:makeRequestWithRetry(endpoint, method, body, max_retries)
    max_retries = math.max(1, math.floor(tonumber(max_retries) or 3))
    local last_error

    for attempt = 1, max_retries do
        if attempt > 1 then
            logger.warn("Gota API: retry", attempt, "of", max_retries)
        end

        local result, err, status, headers, transient_transport_error =
            self:makeRequest(endpoint, method, body)
        if result ~= nil then
            return result, nil
        end
        last_error = err

        local transient = transient_transport_error == true or status == 429
            or (status and status >= 500 and status <= 599)
        if not transient then
            return nil, err
        end
        if attempt == max_retries then
            break
        end

        local delay = retryDelay(attempt, status, headers)
        -- NetworkMgr does not move this loop off KOReader's UI thread. Respect a
        -- long rate-limit window by returning control to the user instead of
        -- freezing an e-ink device for tens of seconds.
        if delay > MAX_BLOCKING_RETRY_DELAY then
            return nil, tostring(err) .. _("; please retry later")
        end
        logger.warn("Gota API: transient error; retrying in", delay, "seconds:", err)
        local sleep_ok, sleep_error = pcall(self.sleep, delay)
        if not sleep_ok then
            logger.warn("Gota API: retry delay failed:", sleep_error)
        end
    end

    return nil, _("Failed after ") .. tostring(max_retries) .. _(" attempts: ") .. tostring(last_error)
end

function API:cachedRequest(endpoint, method, body, use_cache)
    method = tostring(method or "GET"):upper()
    use_cache = (use_cache == nil) and (method == "GET") or use_cache

    if method == "GET" then
        if use_cache then
            local cached = self.response_cache[endpoint]
            if cached and os.time() - cached.timestamp < self.cache_ttl then
                return cached.data, nil
            end
            if cached then self.response_cache[endpoint] = nil end
        else
            -- A bypass also invalidates stale data, so a later normal read cannot
            -- resurrect the pre-reload response.
            self.response_cache[endpoint] = nil
        end
    end

    local result, err = self:makeRequestWithRetry(endpoint, method, body)

    if result ~= nil and method == "GET" and use_cache then
        self.response_cache[endpoint] = {
            data = result,
            timestamp = os.time(),
        }
    end

    return result, err
end

function API:_cachedEnvelope(
    endpoint,
    use_cache,
    required_field,
    required_type,
    second_required_field,
    second_required_type
)
    local data, err = self:cachedRequest(endpoint, nil, nil, use_cache)
    if data == nil then return nil, err end

    local valid = type(data) == "table"
    if valid and data.result ~= nil and data.result ~= true then valid = false end
    if valid and required_field then
        valid = type(data[required_field]) == required_type
    end
    if valid and required_field == "items" then
        for _, item in ipairs(data.items) do
            if type(item) ~= "table" then
                valid = false
                break
            end
        end
    end
    if valid and second_required_field then
        valid = type(data[second_required_field]) == second_required_type
    end
    if valid and second_required_field == "count" then
        valid = normalizeInteger(data.count, nil, 0) ~= nil
    end
    if valid then return data, nil end

    -- Never retain a structurally invalid or explicitly failed API envelope.
    self.response_cache[endpoint] = nil
    local detail = type(data) == "table"
        and (data.errorMessage or data.message or data.error) or nil
    local message = _("Invalid API response envelope for ") .. endpoint
    if detail ~= nil and trim(detail) ~= "" then
        message = message .. ": " .. compactText(detail)
    end
    return nil, message
end

-- Cache management

function API:clearCache()
    self.response_cache = {}
end

function API:clearCacheFor(endpoint_prefix)
    local to_remove = {}
    for key in pairs(self.response_cache) do
        if key:sub(1, #endpoint_prefix) == endpoint_prefix then
            to_remove[#to_remove + 1] = key
        end
    end
    for _, key in ipairs(to_remove) do
        self.response_cache[key] = nil
    end
end

-- Raindrop.io API endpoints

function API:getUser(use_cache)
    return self:_cachedEnvelope("/user", use_cache, "user", "table")
end

function API:getRootCollections(use_cache)
    return self:_cachedEnvelope("/collections", use_cache, "items", "table")
end

function API:getChildCollections(use_cache)
    return self:_cachedEnvelope("/collections/childrens", use_cache, "items", "table")
end

function API:getCollections(include_children, use_cache)
    if include_children == false then
        return self:getRootCollections(use_cache)
    end

    local roots, roots_error = self:getRootCollections(use_cache)
    if not roots then return nil, roots_error end
    local children, children_error = self:getChildCollections(use_cache)
    if not children then return nil, children_error end

    if type(roots) ~= "table" or type(roots.items) ~= "table"
        or type(children) ~= "table" or type(children.items) ~= "table" then
        return nil, _("Invalid collections response envelope")
    end

    local combined = {}
    for key, value in pairs(roots) do
        if key ~= "items" then combined[key] = value end
    end
    combined.items = {}

    local seen = {}
    local function appendItems(envelope)
        for _, item in ipairs(envelope.items or {}) do
            local id = item._id
            if id == nil or not seen[id] then
                combined.items[#combined.items + 1] = item
                if id ~= nil then seen[id] = true end
            end
        end
    end
    appendItems(roots)
    appendItems(children)
    combined.count = #combined.items
    return combined, nil
end

function API:getRaindrops(collection_id, page, perpage, sort, use_cache)
    local id, id_error = normalizeCollectionId(collection_id)
    if not id then return nil, id_error end
    local normalized_page, normalized_perpage, pagination_error = normalizePagination(page, perpage)
    if not normalized_page then return nil, pagination_error end

    local endpoint = string.format(
        "/raindrops/%s?perpage=%d&page=%d",
        id,
        normalized_perpage,
        normalized_page
    )
    if sort and sort ~= "" then
        endpoint = endpoint .. "&sort=" .. urlEncode(sort)
    end
    return self:_cachedEnvelope(endpoint, use_cache, "items", "table", "count", "number")
end

function API:getRaindrop(raindrop_id, force_refresh)
    local id, id_error = normalizeRaindropId(raindrop_id)
    if not id then return nil, id_error end
    local use_cache
    if force_refresh then use_cache = false end
    return self:_cachedEnvelope("/raindrop/" .. id, use_cache, "item", "table")
end

function API:getRaindropCache(raindrop_id)
    local id, id_error = normalizeRaindropId(raindrop_id)
    if not id then return nil, id_error end
    return self:makeRequestWithRetry("/raindrop/" .. id .. "/cache")
end

function API:searchRaindrops(search_term, page, perpage, filters, use_cache)
    local normalized_page, normalized_perpage, pagination_error = normalizePagination(page, perpage)
    if not normalized_page then return nil, pagination_error end

    local params = string.format("perpage=%d&page=%d", normalized_perpage, normalized_page)
    local combined_search = buildSearchExpression(search_term, filters)
    if combined_search ~= "" then
        params = params .. "&search=" .. urlEncode(combined_search)
    end

    local endpoint = "/raindrops/0?" .. params
    return self:_cachedEnvelope(endpoint, use_cache, "items", "table", "count", "number")
end

function API:getFilters(collection_id, search_term, use_cache)
    local id, id_error = normalizeCollectionId(collection_id, 0)
    if not id then return nil, id_error end
    local params = ""
    if search_term and search_term ~= "" then
        params = "?search=" .. urlEncode(search_term)
    end
    local endpoint = string.format("/filters/%s%s", id, params)
    return self:_cachedEnvelope(endpoint, use_cache)
end

function API:getTags(collection_id, use_cache)
    local endpoint = "/tags"
    if collection_id ~= nil then
        local id, id_error = normalizeCollectionId(collection_id)
        if not id then return nil, id_error end
        endpoint = endpoint .. "/" .. id
    end
    return self:_cachedEnvelope(endpoint, use_cache, "items", "table")
end

function API:testToken(token)
    local old_token = self.settings:getToken()
    self.settings:setToken(token)
    local call_ok, user_data, err = pcall(function()
        return self:getUser(false)
    end)
    local restore_ok, restore_error = pcall(function() self.settings:setToken(old_token) end)
    if not restore_ok then
        logger.err("Gota API: failed to restore token after validation:", restore_error)
    end
    if not call_ok then
        return nil, _("HTTP error: ") .. tostring(user_data)
    end
    return user_data, err
end

return API
