--[[
    Gota API Module
    Handles all HTTP communication with Raindrop.io API
]]

local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local JSON = require("json")
local logger = require("logger")
local _ = require("gettext")
local Compression = require("gota_compression")
local Version = require("gota_version")

local API = {}

local MAX_REDIRECTS = 3
local MAX_RETRY_DELAY = 30
local MAX_BLOCKING_RETRY_DELAY = 3
local MAX_PER_PAGE = 50
local DEFAULT_DECOMPRESSED_RESPONSE_BYTES = 16 * 1024 * 1024
local RESPONSE_TOO_LARGE = "gota_response_too_large"

local CONTENT_TYPES = {
    -- Raindrop documents six types; "link" was missing, so selecting it
    -- silently dropped the filter and returned unfiltered results.
    link = true,
    article = true,
    image = true,
    video = true,
    audio = true,
    document = true,
}

local RAINDROP_SORTS = {
    ["-created"] = true,
    created = true,
    score = true,
    ["-sort"] = true,
    title = true,
    ["-title"] = true,
    domain = true,
    ["-domain"] = true,
}

local MUTABLE_RAINDROP_FIELDS = {
    important = true,
    note = true,
    tags = true,
    collection = true,
}

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

-- LuaSec 1.3.2 refuses HTTPS whenever LuaSocket's global HTTP proxy is set.
-- Gota requests are synchronous, so temporarily clearing and restoring that
-- global lets LuaSec establish end-to-end TLS without exposing the Raindrop
-- bearer token to a plaintext forward proxy.
local function requestHttpsDirectly(request)
    local configured_proxy = http.PROXY
    if not configured_proxy then
        return https.request(request)
    end

    http.PROXY = nil
    local ok, result, status, headers, status_line = pcall(https.request, request)
    http.PROXY = configured_proxy

    if not ok then
        error(result, 0)
    end
    return result, status, headers, status_line
end

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

local function normalizedTag(value)
    local tag = trim(value):gsub("^%-?#", "")
    return tag ~= "" and tag or nil
end

local function normalizedContentType(value)
    local content_type = trim(value):lower()
    if content_type == "" then return nil end
    return CONTENT_TYPES[content_type] and content_type or nil
end

local function normalizeDateExpression(value)
    value = trim(value)
    if value == "" then return nil end
    local operator = value:sub(1, 1)
    local date = value
    if operator == "<" or operator == ">" then
        date = value:sub(2)
    else
        operator = ""
    end
    if date:match("^%d%d%d%d$") or
       date:match("^%d%d%d%d%-%d%d$") or
       date:match("^%d%d%d%d%-%d%d%-%d%d$") then
        return operator .. date
    end
    return nil
end

local function buildSearchExpression(search_term, filters)
    local parts = {}
    if filters and filters.match_or == true then
        parts[#parts + 1] = "match:OR"
    end
    appendSearchPart(parts, search_term)

    if filters then
        if filters.tag ~= nil then
            local tag = normalizedTag(filters.tag)
            if tag then
                parts[#parts + 1] = "#" .. searchValue(tag)
            end
        end

        if filters.exclude_tag ~= nil then
            local tag = normalizedTag(filters.exclude_tag)
            if tag then
                parts[#parts + 1] = "-#" .. searchValue(tag)
            end
        end

        if filters.type ~= nil then
            local content_type = normalizedContentType(filters.type)
            if content_type then
                parts[#parts + 1] = "type:" .. searchValue(content_type)
            end
        end

        if filters.exclude_type ~= nil then
            local content_type = normalizedContentType(filters.exclude_type)
            if content_type then
                parts[#parts + 1] = "-type:" .. searchValue(content_type)
            end
        end

        -- Raindrop documents the heart operator for Favorites and the generic
        -- leading-minus syntax for excluding a filter.
        if filters.important ~= nil then
            parts[#parts + 1] = filters.important and "❤️" or "-❤️"
        end

        if filters.notag == true then parts[#parts + 1] = "notag:true" end
        if filters.file == true then parts[#parts + 1] = "file:true" end
        if filters.reminder == true then parts[#parts + 1] = "reminder:true" end
        if filters.cache_ready == true then parts[#parts + 1] = "cache.status:ready" end

        local created = normalizeDateExpression(filters.created)
        if created then parts[#parts + 1] = "created:" .. created end
        local last_update = normalizeDateExpression(filters.last_update)
        if last_update then parts[#parts + 1] = "lastUpdate:" .. last_update end
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

local function normalizeSort(sort, allow_score)
    sort = trim(sort)
    if sort == "" then return nil, nil end
    if not RAINDROP_SORTS[sort] or (sort == "score" and not allow_score) then
        return nil, _("Invalid sort order")
    end
    return sort, nil
end

local function validateOptionalCount(data, endpoint)
    if data and data.count ~= nil and normalizeInteger(data.count, nil, 0) == nil then
        return nil, _("Invalid API response envelope for ") .. endpoint
    end
    return data, nil
end

local function validateSearchFilters(filters)
    if filters == nil then return true, nil end
    if type(filters) ~= "table" then return nil, _("Invalid search filters") end
    for _, key in ipairs({ "type", "exclude_type" }) do
        if filters[key] ~= nil and trim(filters[key]) ~= "" and
           not normalizedContentType(filters[key]) then
            return nil, _("Invalid content type")
        end
    end
    for _, key in ipairs({ "created", "last_update" }) do
        if filters[key] ~= nil and trim(filters[key]) ~= "" and
           not normalizeDateExpression(filters[key]) then
            return nil, _("Invalid date filter; use YYYY, YYYY-MM, or YYYY-MM-DD")
        end
    end
    return true, nil
end

local function utf8CharacterCount(value)
    local count, index = 0, 1
    while index <= #value do
        local byte = value:byte(index)
        if byte and byte >= 0xF0 and byte <= 0xF4 then index = index + 4
        elseif byte and byte >= 0xE0 and byte <= 0xEF then index = index + 3
        elseif byte and byte >= 0xC2 and byte <= 0xDF then index = index + 2
        else index = index + 1 end
        count = count + 1
    end
    return count
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

local function safeJsonEncode(value)
    local ok, encoded = pcall(JSON.encode, value)
    if not ok or type(encoded) ~= "string" then
        return nil, tostring(encoded or "JSON encode failed")
    end
    return encoded, nil
end

local function boundedSink(inner_sink, max_bytes, state)
    state = state or {}
    state.received = 0
    return function(chunk, err)
        if chunk then
            state.received = state.received + #chunk
            if max_bytes and state.received > max_bytes then
                state.too_large = true
                return nil, RESPONSE_TOO_LARGE
            end
        end
        return inner_sink(chunk, err)
    end, state
end

local function fileHasGzipSignature(path)
    local file = io.open(path, "rb")
    if not file then return false end
    local signature = file:read(2)
    file:close()
    return signature and signature:byte(1) == 31 and signature:byte(2) == 139 or false
end

local function normalizedContentEncoding(headers, has_gzip_signature)
    local encoding = trim(getHeader(headers, "Content-Encoding")):lower()
    if encoding == "" or encoding == "identity" then
        return has_gzip_signature and "gzip" or nil
    end
    if encoding == "gzip" or encoding == "x-gzip" then
        return "gzip"
    end
    return nil, encoding:gsub("[%c]", "?"):sub(1, 64)
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
API.normalizeDateExpression = normalizeDateExpression
API.boundedSink = boundedSink
API.RESPONSE_TOO_LARGE = RESPONSE_TOO_LARGE

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

function API:getTransportSecurityInfo()
    return {
        encrypted = true,
        peer_authenticated = false,
        hostname_verified = false,
        limitation = "LuaSec 1.3.2 verify=none",
    }
end

function API:_performRequest(url, method, body, include_authorization, is_file_download, request_options)
    request_options = request_options or {}
    local response_mode = request_options.response_mode or
        (is_file_download and "text" or "json")
    local max_response_bytes = request_options.max_response_bytes
    local chunks = {}
    local transfer = { response_mode = response_mode }
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

    local inner_sink
    local file_handle
    if response_mode == "file" then
        local target_path = request_options.target_path
        if type(target_path) ~= "string" or target_path == "" or target_path:find("%c") then
            return nil, _("Invalid download target"), nil, nil, nil, false
        end
        transfer.target_path = target_path
        transfer.temporary_path = target_path .. ".part"
        os.remove(transfer.temporary_path)
        local open_error
        file_handle, open_error = io.open(transfer.temporary_path, "wb")
        if not file_handle then
            return nil, _("Could not create temporary download file: ") ..
                tostring(open_error), nil, nil, nil, false
        end
        inner_sink = socketutil.file_sink(file_handle)
    else
        inner_sink = socketutil.table_sink(chunks)
    end

    local sink_state = {}
    local request_sink = boundedSink(inner_sink, max_response_bytes, sink_state)
    local request = {
        url = url,
        method = method,
        headers = headers,
        sink = request_sink,
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
        call_ok, request_result, actual_status, response_headers, status_line =
            pcall(requestHttpsDirectly, request)
    end)

    local reset_ok, reset_error = pcall(function() socketutil:reset_timeout() end)
    if not reset_ok then
        logger.err("Gota API: failed to reset socket timeout:", reset_error)
    end

    if file_handle then
        -- socketutil.file_sink closes on the final nil chunk. If the transfer
        -- aborted before that, this closes the still-open handle.
        pcall(function() file_handle:close() end)
    end
    transfer.received = sink_state.received or 0

    if sink_state.too_large then
        return nil, _("Response exceeds the configured size limit"),
            nil, nil, nil, false, transfer
    end
    if not wrapper_ok then
        logger.err("Gota API: request setup error:", wrapper_error)
        return nil, _("HTTP error: ") .. tostring(wrapper_error),
            nil, nil, nil, true, transfer
    end
    if not call_ok then
        logger.err("Gota API: request exception:", request_result)
        return nil, _("HTTP error: ") .. tostring(request_result),
            nil, nil, nil, true, transfer
    end
    if not request_result then
        logger.err("Gota API: HTTP transport error:", actual_status)
        return nil, _("HTTP error: ") .. tostring(actual_status),
            nil, nil, nil, true, transfer
    end

    local payload = response_mode == "file" and true or table.concat(chunks)
    return payload, nil, tonumber(actual_status), response_headers or {},
        status_line, nil, transfer
end

local function cleanupTransfer(transfer)
    if transfer and transfer.temporary_path then
        os.remove(transfer.temporary_path)
    end
    if transfer and transfer.decoded_path then
        os.remove(transfer.decoded_path)
    end
end

local function readFilePrefix(path, max_bytes)
    if not path then return nil end
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read(max_bytes or 4096)
    file:close()
    return content
end

function API:makeRequest(endpoint, method, body, request_options)
    if type(endpoint) ~= "string" or endpoint:sub(1, 1) ~= "/"
        or endpoint:find("[%c%s\\]") then
        return nil, _("Invalid API endpoint")
    end

    method = tostring(method or "GET"):upper()
    if not HTTP_METHODS[method] then
        return nil, _("Unsupported HTTP method: ") .. method
    end
    request_options = request_options or {}
    local response_mode = request_options.response_mode
    if response_mode ~= nil and response_mode ~= "json" and
       response_mode ~= "text" and response_mode ~= "file" then
        return nil, _("Unsupported response mode")
    end
    if request_options.max_response_bytes ~= nil then
        local normalized_limit = normalizeInteger(request_options.max_response_bytes, nil, 1)
        if not normalized_limit then return nil, _("Invalid response size limit") end
        request_options.max_response_bytes = normalized_limit
    end
    local is_file_download = endpoint:match("/cache$") ~= nil
        or endpoint:match("/cache%?[^/]*$") ~= nil
    if response_mode == "file" and not is_file_download then
        return nil, _("File response mode is only supported for permanent copies")
    end
    local url = self.server_url .. endpoint
    local include_authorization = true
    local redirect_count = 0

    logger.dbg("Gota API: request", method, endpoint)

    while true do
        local payload, transport_error, status, headers, status_line,
            transient_transport_error, transfer = self:_performRequest(
                url,
                method,
                body,
                include_authorization,
                is_file_download,
                request_options
            )
        if not payload then
            cleanupTransfer(transfer)
            return nil, transport_error, status, headers, transient_transport_error
        end

        if status and status >= 300 and status < 400 then
            cleanupTransfer(transfer)
            local location = getHeader(headers, "Location")
            if not REDIRECT_STATUSES[status] or not is_file_download or not location then
                return nil, _("Unexpected redirect from server: ") .. tostring(status), status, headers
            end
            if redirect_count >= MAX_REDIRECTS then
                return nil, _("Too many redirects while downloading the web copy"), status, headers
            end
            if not isSafeHttpsUrl(location) then
                return nil, _("Refused an unsafe web-copy redirect"), status, headers
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
                cleanupTransfer(transfer)
                return nil, _("HTTP response did not include a status code"), nil, headers
            end

            if status >= 200 and status < 300 then
                local declared_length = tonumber(getHeader(headers, "Content-Length"))
                if request_options.max_response_bytes and declared_length and
                   declared_length > request_options.max_response_bytes then
                    cleanupTransfer(transfer)
                    return nil, _("Response exceeds the configured size limit"), status, headers, false
                end
                if status == 204 and not is_file_download then
                    cleanupTransfer(transfer)
                    return true, nil, status, headers
                end
                local payload_size = transfer and transfer.received or #payload
                if payload_size == 0 then
                    cleanupTransfer(transfer)
                    return nil, _("Empty server response"), status, headers
                end

                local has_gzip_signature
                if transfer and transfer.response_mode == "file" then
                    has_gzip_signature = fileHasGzipSignature(transfer.temporary_path)
                else
                    has_gzip_signature = payload:byte(1) == 31 and payload:byte(2) == 139
                end
                local content_encoding, unsupported_encoding =
                    normalizedContentEncoding(headers, has_gzip_signature)
                if unsupported_encoding then
                    cleanupTransfer(transfer)
                    return nil, _("Unsupported server content encoding: ") ..
                        unsupported_encoding, status, headers
                end
                if content_encoding == "gzip" then
                    local decompressed_limit = request_options.max_response_bytes or
                        DEFAULT_DECOMPRESSED_RESPONSE_BYTES
                    if transfer and transfer.response_mode == "file" then
                        transfer.decoded_path = transfer.temporary_path .. ".decoded"
                        local decoded_path, decode_error, limit_exceeded, decoded_size =
                            Compression.inflateGzipFile(
                                transfer.temporary_path,
                                transfer.decoded_path,
                                decompressed_limit
                            )
                        if not decoded_path then
                            cleanupTransfer(transfer)
                            if limit_exceeded then
                                return nil, _("Decompressed response exceeds the configured size limit"),
                                    status, headers
                            end
                            return nil, _("Could not decode gzip response: ") ..
                                tostring(decode_error), status, headers
                        end
                        os.remove(transfer.temporary_path)
                        local replace_ok, replace_error = os.rename(
                            decoded_path,
                            transfer.temporary_path
                        )
                        if not replace_ok then
                            cleanupTransfer(transfer)
                            return nil, _("Could not finalize decompressed response: ") ..
                                tostring(replace_error), status, headers
                        end
                        transfer.decoded_path = nil
                        payload_size = decoded_size or 0
                    else
                        local decoded, decode_error, limit_exceeded =
                            Compression.inflateGzipString(
                                payload,
                                decompressed_limit
                            )
                        if not decoded then
                            cleanupTransfer(transfer)
                            if limit_exceeded then
                                return nil, _("Decompressed response exceeds the configured size limit"),
                                    status, headers
                            end
                            return nil, _("Could not decode gzip response: ") ..
                                tostring(decode_error), status, headers
                        end
                        payload = decoded
                        payload_size = #payload
                    end
                end
                if payload_size == 0 then
                    cleanupTransfer(transfer)
                    return nil, _("Empty server response"), status, headers
                end

                if is_file_download then
                    if transfer and transfer.response_mode == "file" then
                        local renamed, rename_error = os.rename(
                            transfer.temporary_path,
                            transfer.target_path
                        )
                        if not renamed then
                            cleanupTransfer(transfer)
                            return nil, _("Could not finalize downloaded file: ") ..
                                tostring(rename_error), status, headers
                        end
                        return transfer.target_path, nil, status, headers
                    end
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

            local error_payload = payload
            if transfer and transfer.response_mode == "file" then
                error_payload = readFilePrefix(transfer.temporary_path)
                cleanupTransfer(transfer)
            end
            local message = _("Server error: ") .. tostring(status)
            local detail = responseErrorMessage(error_payload)
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

function API:makeRequestWithRetry(endpoint, method, body, max_retries, request_options)
    method = tostring(method or "GET"):upper()
    request_options = request_options or {}
    local is_read = method == "GET" or method == "HEAD"
    if request_options.retry_policy == "none" or not is_read then
        max_retries = 1
    else
        max_retries = math.max(1, math.floor(tonumber(max_retries) or 3))
    end
    local last_error

    for attempt = 1, max_retries do
        if attempt > 1 then
            logger.warn("Gota API: retry", attempt, "of", max_retries)
        end

        local result, err, status, headers, transient_transport_error =
            self:makeRequest(endpoint, method, body, request_options)
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

-- Deprecated compatibility envelope. New UI code must use
-- getCollectionStructure() to preserve groups and source ordering.
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

-- Returns a normalized, read-only view of the three sources Raindrop requires
-- to reproduce its collection sidebar. Roots are required; user/groups and
-- children degrade independently so an e-reader never loses all navigation.
function API:getCollectionStructure(use_cache)
    local roots, roots_error = self:getRootCollections(use_cache)
    if not roots then return nil, roots_error end

    local structure = {
        groups = {},
        roots = roots.items,
        children = {},
        warnings = {},
    }

    local user, user_error = self:getUser(use_cache)
    if user and type(user.user) == "table" and type(user.user.groups) == "table" then
        for _, group in ipairs(user.user.groups) do
            if type(group) == "table" then
                structure.groups[#structure.groups + 1] = group
            end
        end
    else
        structure.warnings[#structure.warnings + 1] =
            user_error or _("Collection groups are unavailable")
    end

    local children, children_error = self:getChildCollections(use_cache)
    if children and type(children.items) == "table" then
        for _, child in ipairs(children.items) do
            structure.children[#structure.children + 1] = child
        end
    else
        structure.warnings[#structure.warnings + 1] =
            children_error or _("Child collections are unavailable")
    end

    return structure, nil
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
    local normalized_sort, sort_error = normalizeSort(sort, false)
    if sort_error then return nil, sort_error end
    if normalized_sort then
        endpoint = endpoint .. "&sort=" .. urlEncode(normalized_sort)
    end
    local data, err = self:_cachedEnvelope(endpoint, use_cache, "items", "table")
    if not data then return nil, err end
    return validateOptionalCount(data, endpoint)
end

function API:getRaindrop(raindrop_id, force_refresh)
    local id, id_error = normalizeRaindropId(raindrop_id)
    if not id then return nil, id_error end
    local use_cache
    if force_refresh then use_cache = false end
    return self:_cachedEnvelope("/raindrop/" .. id, use_cache, "item", "table")
end

function API:getRaindropCache(raindrop_id, max_bytes)
    local id, id_error = normalizeRaindropId(raindrop_id)
    if not id then return nil, id_error end
    return self:makeRequestWithRetry(
        "/raindrop/" .. id .. "/cache",
        "GET",
        nil,
        3,
        { response_mode = "text", max_response_bytes = max_bytes }
    )
end

function API:downloadRaindropCache(raindrop_id, target_path, max_bytes)
    local id, id_error = normalizeRaindropId(raindrop_id)
    if not id then return nil, id_error end
    return self:makeRequestWithRetry(
        "/raindrop/" .. id .. "/cache",
        "GET",
        nil,
        3,
        {
            response_mode = "file",
            target_path = target_path,
            max_response_bytes = max_bytes,
        }
    )
end

function API:searchRaindrops(search_term, page, perpage, filters, use_cache, options)
    local normalized_page, normalized_perpage, pagination_error = normalizePagination(page, perpage)
    if not normalized_page then return nil, pagination_error end

    local filters_ok, filters_error = validateSearchFilters(filters)
    if not filters_ok then return nil, filters_error end
    options = options or {}
    if type(options) ~= "table" then return nil, _("Invalid search options") end
    local collection_id, id_error = normalizeCollectionId(options.collection_id, 0)
    if not collection_id then return nil, id_error end

    local params = string.format("perpage=%d&page=%d", normalized_perpage, normalized_page)
    local combined_search = buildSearchExpression(search_term, filters)
    local has_text = trim(search_term) ~= ""
    if combined_search ~= "" then
        params = params .. "&search=" .. urlEncode(combined_search)
    end

    if options.nested == true then params = params .. "&nested=true" end
    local requested_sort = options.sort
    if trim(requested_sort) == "" then
        requested_sort = has_text and "score" or "-created"
    end
    local normalized_sort, sort_error = normalizeSort(requested_sort, has_text)
    if sort_error then return nil, sort_error end
    if normalized_sort then params = params .. "&sort=" .. urlEncode(normalized_sort) end

    local endpoint = "/raindrops/" .. collection_id .. "?" .. params
    local data, err = self:_cachedEnvelope(endpoint, use_cache, "items", "table")
    if not data then return nil, err end
    return validateOptionalCount(data, endpoint)
end

function API:getFilters(collection_id, search_term, use_cache, options)
    local id, id_error = normalizeCollectionId(collection_id, 0)
    if not id then return nil, id_error end
    options = options or {}
    if type(options) ~= "table" then return nil, _("Invalid filter options") end
    local tags_sort = options.tags_sort or "-count"
    if tags_sort ~= "-count" and tags_sort ~= "_id" then
        return nil, _("Invalid tag sort order")
    end
    local params = { "tagsSort=" .. urlEncode(tags_sort) }
    if trim(search_term) ~= "" then
        params[#params + 1] = "search=" .. urlEncode(trim(search_term))
    end
    local endpoint = string.format("/filters/%s?%s", id, table.concat(params, "&"))
    local data, err = self:_cachedEnvelope(endpoint, use_cache)
    if not data then return nil, err end
    if type(data) ~= "table" then return nil, _("Invalid filters response") end
    return data, nil
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

function API:getHighlights(collection_id, page, perpage, use_cache)
    local normalized_page, normalized_perpage, pagination_error = normalizePagination(page, perpage)
    if not normalized_page then return nil, pagination_error end
    local endpoint = "/highlights"
    if collection_id ~= nil then
        local id, id_error = normalizeCollectionId(collection_id)
        if not id then return nil, id_error end
        endpoint = endpoint .. "/" .. id
    end
    endpoint = endpoint .. string.format("?perpage=%d&page=%d", normalized_perpage, normalized_page)
    return self:_cachedEnvelope(endpoint, use_cache, "items", "table")
end

function API:getUserStats(use_cache)
    local data, err = self:_cachedEnvelope("/user/stats", use_cache, "items", "table")
    if not data then return nil, err end
    if data.meta ~= nil and type(data.meta) ~= "table" then
        self.response_cache["/user/stats"] = nil
        return nil, _("Invalid user statistics response")
    end
    return data, nil
end

local function normalizedRaindropPatch(patch)
    if type(patch) ~= "table" then return nil, _("Invalid bookmark update") end
    local normalized = {}
    local field_count = 0
    for key, value in pairs(patch) do
        if not MUTABLE_RAINDROP_FIELDS[key] then
            return nil, _("Unsupported bookmark field: ") .. tostring(key)
        end
        field_count = field_count + 1
        if key == "important" then
            if type(value) ~= "boolean" then return nil, _("Favorite must be true or false") end
            normalized.important = value
        elseif key == "note" then
            if type(value) ~= "string" or utf8CharacterCount(value) > 10000 then
                return nil, _("Note must contain at most 10,000 characters")
            end
            normalized.note = value
        elseif key == "tags" then
            if type(value) ~= "table" then return nil, _("Tags must be a list") end
            normalized.tags = {}
            local tag_count = 0
            for tag_index in pairs(value) do
                if type(tag_index) ~= "number" or tag_index < 1 or
                   tag_index ~= math.floor(tag_index) then
                    return nil, _("Tags must be a list")
                end
                tag_count = tag_count + 1
            end
            if tag_count ~= #value then return nil, _("Tags must be a list") end
            for index, tag in ipairs(value) do
                if type(tag) ~= "string" or trim(tag) == "" then
                    return nil, _("Tags must be non-empty text values")
                end
                normalized.tags[index] = trim(tag)
            end
        elseif key == "collection" then
            local collection_id = type(value) == "table" and value["$id"] or value
            local id, id_error = normalizeCollectionId(collection_id)
            if not id then return nil, id_error end
            normalized.collection = { ["$id"] = tonumber(id) }
        end
    end
    if field_count == 0 then return nil, _("Bookmark update cannot be empty") end
    return normalized, nil
end

function API:updateRaindrop(raindrop_id, patch)
    local id, id_error = normalizeRaindropId(raindrop_id)
    if not id then return nil, id_error end
    local normalized, patch_error = normalizedRaindropPatch(patch)
    if not normalized then return nil, patch_error end
    local body, encode_error = safeJsonEncode(normalized)
    if not body then return nil, _("Could not encode bookmark update: ") .. encode_error end
    local data, err = self:makeRequestWithRetry(
        "/raindrop/" .. id,
        "PUT",
        body,
        1,
        { retry_policy = "none" }
    )
    if not data then return nil, err end
    if type(data) ~= "table" or data.result ~= true or type(data.item) ~= "table" then
        return nil, _("Invalid bookmark update response")
    end
    self:clearCache()
    return data, nil
end

function API:trashRaindrop(raindrop_id, current_collection_id)
    local id, id_error = normalizeRaindropId(raindrop_id)
    if not id then return nil, id_error end
    if current_collection_id == nil then
        return nil, _("Current collection is required before moving to Trash")
    end
    local collection_id, collection_error = normalizeCollectionId(current_collection_id)
    if not collection_id then return nil, collection_error end
    if tonumber(collection_id) == -99 then
        return nil, _("Refusing to permanently delete an item already in Trash")
    end
    local data, err = self:makeRequestWithRetry(
        "/raindrop/" .. id,
        "DELETE",
        nil,
        1,
        { retry_policy = "none" }
    )
    if not data then return nil, err end
    if type(data) ~= "table" or data.result ~= true then
        return nil, _("Invalid Trash response")
    end
    self:clearCache()
    return data, nil
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
