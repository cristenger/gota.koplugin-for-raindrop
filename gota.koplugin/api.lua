--[[
    API Module for Gota Plugin
    Handles all HTTP communication with Raindrop.io API
]]

local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("json")
local logger = require("logger")
local _ = require("gettext")

local API = {}

-- Función auxiliar para codificar URLs
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
    o.cache_ttl = 300  -- 5 minutos
    
    -- Configurar SSL una sola vez al inicio (desactivado para compatibilidad con dispositivos e-ink)
    https.cert_verify = false
    logger.dbg("Gota API: SSL verificación desactivada para compatibilidad con dispositivos e-ink")
    
    return o
end

function API:makeRequest(endpoint, method, body)
    local url = self.server_url .. endpoint
    logger.dbg("Gota API: Iniciando solicitud a", url)

    local sink = {}
    local request = {
        url     = url,
        method  = method or "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.settings:getToken(),
            ["Content-Type"]  = "application/json",
            ["User-Agent"]    = "KOReader-Gota-Plugin/1.9",
            ["Accept-Encoding"] = "gzip, identity",
        },
        sink    = ltn12.sink.table(sink),
        protocol = "any",
        timeout = 30,
    }

    if body then
        request.headers["Content-Length"] = tostring(#body)
        request.source = ltn12.source.string(body)
    end

    local protocol = url:match("^https://") and https or http
    local ok, actual_status, headers = protocol.request(request)

    if ok and actual_status == 200 then
        local resp = table.concat(sink)
        logger.dbg("Gota API: Respuesta exitosa, tamaño:", #resp)
        
        if #resp == 0 then
            logger.warn("Gota API: Respuesta vacía del servidor")
            return nil, _("Empty server response")
        end

        -- Manejo de Gzip
        local is_gzipped = false
        if headers and headers["content-encoding"] then
            local encoding = headers["content-encoding"]:lower()
            is_gzipped = encoding:find("gzip") ~= nil
        end
        
        local might_be_gzipped = resp:byte(1) == 31 and resp:byte(2) == 139
        
        if is_gzipped or might_be_gzipped then
            logger.dbg("Gota API: Detectada respuesta comprimida con Gzip")
            resp = self:decompressGzip(resp)
            if not resp then
                return nil, _("Error: Could not decompress server response")
            end
        end
        
        -- Verificar si es HTML directo (endpoint /cache)
        if endpoint:match("/cache$") then
            logger.dbg("Gota API: Respuesta de caché detectada como HTML directo")
            return resp  -- Devolver HTML sin procesar como JSON
        end

        local data, parse_err = JSON.decode(resp)
        if data then
            logger.dbg("Gota API: JSON parseado exitosamente")
            return data, nil
        else
            logger.err("Gota API: Error al parsear JSON:", parse_err)
            logger.dbg("Gota API: Respuesta raw:", resp:sub(1, 200))
            return nil, _("Error processing server response")
        end
    elseif ok and actual_status ~= 200 then
        local msg = _("Server error: ") .. tostring(actual_status)
        if headers then
            local R = headers["x-ratelimit-remaining"]
            if R and tonumber(R) and tonumber(R) < 5 then
                msg = msg .. " Restantes:" .. (R or "?")
            end
        end
        return nil, msg
    else
        local resp = table.concat(sink)
        logger.err("Gota API: HTTP error", actual_status, resp:sub(1,200))
        return nil, _("HTTP error ") .. tostring(actual_status)
    end
end

function API:decompressGzip(resp)
    local temp_in = "/tmp/gota_gzip_" .. os.time() .. ".gz"
    local temp_out = "/tmp/gota_out_" .. os.time() .. ".txt"
    
    local file = io.open(temp_in, "wb")
    if file then
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
                logger.dbg("Gota API: Descompresión exitosa con comando del sistema")
            end
        end
        
        os.remove(temp_in)
        os.remove(temp_out)
        
        -- Verificar si sigue comprimido
        if resp:byte(1) == 31 and resp:byte(2) == 139 then
            return nil
        end
        
        return resp
    else
        logger.err("Gota API: No se pudo crear archivo temporal para descompresión")
        return nil
    end
end

function API:makeRequestWithRetry(endpoint, method, body, max_retries)
    max_retries = max_retries or 3
    local attempts = 0
    
    while attempts < max_retries do
        attempts = attempts + 1
        
        if attempts > 1 then
            logger.warn("Gota API: Reintento", attempts, "de", max_retries)
            os.execute("sleep 1")
        end
        
        local result, err = self:makeRequest(endpoint, method, body)
        
        if result or (err and not err:match("conexión") and not err:match("timeout")) then
            return result, err
        end
        
        logger.warn("Gota API: Reintentando solicitud después de error:", err)
    end
    
    return nil, _("Failed after ") .. max_retries .. _(" attempts")
end

function API:cachedRequest(endpoint, method, body, use_cache)
    use_cache = (use_cache == nil) and (method == "GET" or method == nil) or use_cache
    
    if use_cache and method == "GET" then
        local cache_key = endpoint
        local cached = self.response_cache[cache_key]
        
        if cached and os.time() - cached.timestamp < self.cache_ttl then
            logger.dbg("Gota API: Usando respuesta en caché para", endpoint)
            return cached.data, nil
        end
    end
    
    local result, err = self:makeRequestWithRetry(endpoint, method, body)
    
    if result and method == "GET" and use_cache then
        local cache_key = endpoint
        self.response_cache[cache_key] = {
            data = result,
            timestamp = os.time()
        }
    end
    
    return result, err
end

-- API methods específicos para Raindrop.io

function API:getUser()
    return self:cachedRequest("/user")
end

function API:getCollections()
    return self:cachedRequest("/collections")
end

function API:getRaindrops(collection_id, page, perpage)
    page = page or 0
    perpage = perpage or 25
    local endpoint = string.format("/raindrops/%s?perpage=%d&page=%d", collection_id, perpage, page)
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
    
    -- Construir término de búsqueda combinado (texto + tag)
    local combined_search = search_term or ""
    
    -- Agregar filtros opcionales
    if filters then
        if filters.tag then
            -- Usar formato de búsqueda con # para tags (más confiable en Raindrop)
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
    
    -- Agregar término de búsqueda combinado si existe
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
    
    local endpoint = string.format("/filters/%s%s", collection_id, params)
    return self:cachedRequest(endpoint)
end

function API:getTags(collection_id)
    collection_id = collection_id or 0
    local endpoint = string.format("/tags/%s", collection_id)
    return self:cachedRequest(endpoint)
end

function API:testToken(token)
    local old_token = self.settings:getToken()
    self.settings:setToken(token)
    
    local user_data, err = self:makeRequestWithRetry("/user")
    
    self.settings:setToken(old_token)
    
    return user_data, err
end

return API
