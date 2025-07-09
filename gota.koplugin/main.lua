--[[
    Gota: Lector para Raindrop.io en KOReader
    Permite leer artículos guardados en Raindrop.io directamente en tu dispositivo.
    
    Versión: 1.6 (Sin compresión gzip para mejor compatibilidad)
    
    IMPORTANTE: SSL está desactivado para evitar problemas de certificados
    en dispositivos Kindle. Esto es necesario para que funcione correctamente.
]]

local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("json")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template
local ffi = require("ffi")

-- El plugin no necesita zlib ya que pedimos respuestas sin comprimir
local zlib = nil
local zlib_loaded = false

local Gota = WidgetContainer:extend{
    name = "gota",
    is_doc_only = false,
}

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

-- Función auxiliar para obtener keys de tabla
local function table_keys(t)
    local keys = {}
    if type(t) == "table" then
        for k, _ in pairs(t) do
            table.insert(keys, tostring(k))
        end
    end
    return keys
end

-- Función auxiliar para parsear contenido de configuración
local function parseSettings(content)
    -- Método más robusto para parsear configuración Lua
    if not content or content == "" then
        return {}
    end
    
    -- Método 1: Intentar como función que retorna tabla
    local wrapped_content = "return " .. content
    local chunk, err = loadstring(wrapped_content)
    if chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" then
            return result
        end
    end
    
    -- Método 2: Intentar evaluar directamente
    local env = {}
    chunk, err = loadstring(content)
    if chunk then
        setfenv(chunk, env)
        local ok = pcall(chunk)
        if ok and next(env) then
            return env
        end
    end
    
    logger.warn("Gota: No se pudo parsear configuración:", err)
    return {}
end

-- Función mejorada para descomprimir contenido Gzip
function Gota:decompressGzip(compressed_data)
    -- Esta función ya no se usa, pero la mantenemos por compatibilidad
    logger.warn("Gota: decompressGzip llamada pero no debería usarse")
    return nil
end

function Gota:notify(text, timeout)
    timeout = timeout or 3
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout,
    })
end

function Gota:init()
    self.settings_file = DataStorage:getSettingsDir() .. "/gota.lua"
    self:loadSettings()
    
    -- CORRECCIÓN: configurar SSL una sola vez al inicio
    https.cert_verify = false
    logger.dbg("Gota: SSL verificación desactivada para compatibilidad")
    
    -- Inicializar caché para respuestas
    self.response_cache = {}
    self.cache_ttl = 300  -- 5 minutos de vida para el caché
    
    self.ui.menu:registerToMainMenu(self)
end

function Gota:loadSettings()
    local settings = {}
    
    if self.settings_file then
        local file = io.open(self.settings_file, "r")
        if file then
            local content = file:read("*all")
            file:close()
            
            logger.dbg("Gota: Contenido leído del archivo:", content and #content or "nil")
            
            if content and content ~= "" then
                -- CORRECCIÓN: usar función de parsing robusta
                settings = parseSettings(content)
                if next(settings) then
                    logger.dbg("Gota: Configuración cargada exitosamente")
                else
                    logger.warn("Gota: No se pudo parsear configuración, usando defaults")
                end
            end
        else
            logger.dbg("Gota: Archivo de configuración no existe, usando defaults")
        end
    end
    
    self.token = settings.token or ""
    self.server_url = "https://api.raindrop.io/rest/v1"
    
    logger.dbg("Gota: Token cargado, longitud:", #self.token)
end

function Gota:saveSettings()
    local settings = {
        token = self.token,
    }
    
    logger.dbg("Gota: Intentando guardar token, longitud:", #self.token)
    
    local file, err = io.open(self.settings_file, "w")
    if file then
        -- CORRECCIÓN: serialización más robusta con escape completo
        local serialized = string.format("return {\n  token = %q,\n}\n", settings.token)
        file:write(serialized)
        file:close()
        logger.dbg("Gota: Configuración guardada exitosamente")
    else
        logger.err("Gota: No se pudo abrir archivo para escritura:", err)
        self:notify("Error: No se pudo guardar la configuración")
    end
end

function Gota:addToMainMenu(menu_items)
    menu_items.gota = {
        text = _("Gota (Raindrop.io)"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Configurar token de acceso"),
                callback = function()
                    self:showTokenDialog()
                end,
            },
            {
                text = _("Debug: Ver configuración"),
                callback = function()
                    self:showDebugInfo()
                end,
            },
            {
                text = _("Ver colecciones"),
                enabled_func = function()
                    return self.token ~= ""
                end,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        self:showCollections()
                    end)
                end,
            },
            {
                text = _("Buscar artículos"),
                enabled_func = function()
                    return self.token ~= ""
                end,
                callback = function()
                    self:showSearchDialog()
                end,
            },
            {
                text = _("Todos los artículos"),
                enabled_func = function()
                    return self.token ~= ""
                end,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        self:showRaindrops(0, _("Todos los artículos"))
                    end)
                end,
            },
        }
    }
end

function Gota:showTokenDialog()
    self.token_dialog = InputDialog:new{
        title = _("Token de acceso de Raindrop.io"),
        description = _("OPCIÓN 1 - Test Token (Recomendado):\n• Ve a: https://app.raindrop.io/settings/integrations\n• Crea una nueva aplicación\n• Copia el 'Test token'\n\nOPCIÓN 2 - Token Personal:\n• Usa un token de acceso personal\n\nPega el token aquí:"),
        input = self.token,
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancelar"),
                    callback = function()
                        UIManager:close(self.token_dialog)
                    end,
                },
                {
                    text = _("Probar"),
                    callback = function()
                        local test_token = self.token_dialog:getInputText()
                        if test_token and test_token ~= "" then
                            test_token = test_token:gsub("^%s+", ""):gsub("%s+$", "")
                            NetworkMgr:runWhenOnline(function()
                                self:testToken(test_token)
                            end)
                        else
                            self:notify(_("Por favor ingresa un token para probar"))
                        end
                    end,
                },
                {
                    text = _("Guardar"),
                    is_enter_default = true,
                    callback = function()
                        local new_token = self.token_dialog:getInputText()
                        if new_token and new_token ~= "" then
                            new_token = new_token:gsub("^%s+", ""):gsub("%s+$", "")
                            
                            logger.dbg("Gota: Token recibido, longitud:", #new_token)
                            
                            if #new_token < 20 then
                                self:notify(_("⚠️ Token muy corto, verifica que sea correcto"))
                                return
                            end
                            
                            self.token = new_token
                            self:saveSettings()
                            UIManager:close(self.token_dialog)
                            self:notify(_("Token guardado correctamente\nUsa 'Probar' para verificar funcionalidad"), 3)
                        else
                            self:notify(_("Por favor ingresa un token válido"), 2)
                        end
                    end,
                }
            }
        },
    }
    UIManager:show(self.token_dialog)
    self.token_dialog:onShowKeyboard()
end

function Gota:makeRequest(endpoint, method, body)
    local url = self.server_url .. endpoint
    logger.dbg("Gota: Iniciando solicitud a", url)
    logger.dbg("Gota: Solicitando respuesta sin comprimir (Accept-Encoding: identity)")

    -- mostrar "Conectando…" mientras dura la petición
    local loading_msg = InfoMessage:new{ text = _("Conectando…"), timeout = 0 }
    UIManager:show(loading_msg)
    UIManager:forceRePaint()

    local sink = {}
    local request = {
        url     = url,
        method  = method or "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.token,
            ["Content-Type"]  = "application/json",
            ["User-Agent"]    = "KOReader-Gota-Plugin/1.6",
            ["Accept-Encoding"] = "identity",
        },
        sink    = ltn12.sink.table(sink),
        protocol = "any",
        options = "all",
        timeout = 30,
    }

    if (method == "POST" or method == "PUT") and body then
        local payload = JSON.encode(body)
        request.source = ltn12.source.string(payload)
        request.headers["Content-Length"] = #payload
    end

    local socketutil = require("socketutil")
    socketutil:set_timeout(10, 30)
    
    local ok, r1, r2, r3 = pcall(https.request, request)
    
    -- Si falla HTTPS, intentar con HTTP como fallback
    if not ok and r1:match("unreachable") then
        logger.warn("Gota: HTTPS falló, intentando con HTTP como fallback")
        request.url = request.url:gsub("^https:", "http:")
        ok, r1, r2, r3 = pcall(http.request, request)
    end
    
    socketutil:reset_timeout()
    UIManager:close(loading_msg)

    if not ok then
        logger.err("Gota: request falló:", r1)
        return nil, _("Error de conexión: ") .. tostring(r1)
    end

    local result, status_code, response_headers = r1, r2, r3
    local actual_status = (result ~= 1 and type(result)=="number") and result or status_code

    logger.dbg("Gota: Status determinado:", actual_status)

    if actual_status == 200 then
        local resp = table.concat(sink)
        if #resp > 0 then
            -- Verificar si la respuesta está comprimida con Gzip
            local is_gzipped = false
            if response_headers and response_headers["content-encoding"] then
                local encoding = response_headers["content-encoding"]:lower()
                is_gzipped = encoding:find("gzip") ~= nil
                if is_gzipped then
                    logger.warn("Gota: Servidor envió gzip a pesar de Accept-Encoding: identity")
                end
            end
            
            local might_be_gzipped = resp:byte(1) == 31 and resp:byte(2) == 139
            
            if is_gzipped or might_be_gzipped then
                logger.dbg("Gota: Detectada respuesta comprimida con Gzip")
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
                            logger.dbg("Gota: Descompresión exitosa con comando del sistema")
                        end
                    end
                    
                    os.remove(temp_in)
                    os.remove(temp_out)
                else
                    logger.err("Gota: No se pudo crear archivo temporal para descompresión")
                end
                
                if resp:byte(1) == 31 and resp:byte(2) == 139 then
                    return nil, _("Error: No se pudo descomprimir la respuesta del servidor")
                end
            end
            
            -- Verificar si es HTML directo (endpoint /cache)
            if endpoint:match("/cache$") then
                logger.dbg("Gota: Respuesta de caché detectada como HTML directo")
                return resp  -- Devolver HTML sin procesar como JSON
            end
            
            local dec_ok, data = pcall(function() return JSON.decode(resp) end)
            if dec_ok then
                return data
            else
                logger.err("Gota: JSON.decode error:", data, resp:sub(1,200))
                if resp:byte(1) == 31 and resp:byte(2) == 139 then
                    return nil, _("Error: La respuesta sigue comprimida, no se pudo procesar")
                else
                    return nil, _("Error decodificando JSON: ") .. tostring(data)
                end
            end
        end
        return {}
    elseif actual_status == 204 then
        return {}
    elseif actual_status == 401 then
        return nil, _("Token inválido o expirado (401)")
    elseif actual_status == 403 then
        return nil, _("Acceso denegado (403)")
    elseif actual_status == 429 then
        local msg = _("Rate limit excedido (429)")
        if response_headers then
            local L = response_headers["X-RateLimit-Limit"]
            local R = response_headers["X-RateLimit-Remaining"]
            if L or R then
                msg = msg .. " Límite:" .. (L or "?") .. " Restantes:" .. (R or "?")
            end
        end
        return nil, msg
    else
        local resp = table.concat(sink)
        logger.err("Gota: HTTP error", actual_status, resp:sub(1,200))
        return nil, _("Error HTTP ") .. tostring(actual_status)
    end
end

function Gota:makeRequestWithRetry(endpoint, method, body, max_retries)
    max_retries = max_retries or 3
    local attempts = 0
    
    while attempts < max_retries do
        attempts = attempts + 1
        
        if attempts > 1 then
            local progress_message = InfoMessage:new{text = _("Reintentando conexión (") .. attempts .. "/" .. max_retries .. ")...", timeout = 1}
            UIManager:show(progress_message)
            UIManager:forceRePaint()
            os.execute("sleep 1")
        end
        
        local result, err = self:makeRequest(endpoint, method, body)
        
        if result or (err and not err:match("conexión") and not err:match("timeout")) then
            return result, err
        end
        
        logger.warn("Gota: Reintentando solicitud después de error:", err)
    end
    
    return nil, _("Falló después de ") .. max_retries .. _(" intentos")
end

function Gota:showProgress(text)
    if self.progress_message then
        UIManager:close(self.progress_message)
    end
    self.progress_message = InfoMessage:new{text = text, timeout = 1}
    UIManager:show(self.progress_message)
    UIManager:forceRePaint()
end

function Gota:hideProgress()
    if self.progress_message then 
        UIManager:close(self.progress_message) 
    end
    self.progress_message = nil
end

function Gota:cachedRequest(endpoint, method, body, use_cache)
    use_cache = (use_cache == nil) and (method == "GET" or method == nil) or use_cache
    
    if use_cache and method == "GET" then
        local cache_key = endpoint
        local cached = self.response_cache[cache_key]
        
        if cached and os.time() - cached.timestamp < self.cache_ttl then
            logger.dbg("Gota: Usando respuesta en caché para", endpoint)
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

function Gota:showCollections()
    self:showProgress(_("Cargando colecciones..."))
    local collections, err = self:cachedRequest("/collections")
    self:hideProgress()
    
    if not collections then
        self:notify(_("Error al obtener colecciones:") .. "\n" .. (err or _("Error desconocido")), 4)
        return
    end
    
    local menu_items = {}
    
    if not collections.items or #collections.items == 0 then
        table.insert(menu_items, {
            text = _("No tienes colecciones creadas"),
            enabled = false,
        })
    else
        for _, collection in ipairs(collections.items) do
            table.insert(menu_items, {
                text = string.format("%s (%d)", collection.title, collection.count or 0),
                callback = function()
                    self:showRaindrops(collection._id, collection.title)
                end,
            })
        end
    end
    
    local collections_menu = Menu:new{
        title = _("Colecciones de Raindrop"),
        item_table = menu_items,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(collections_menu)
end

function Gota:showRaindrops(collection_id, collection_name, page)
    page = page or 0
    local perpage = 25
    local endpoint = string.format("/raindrops/%s?perpage=%d&page=%d", collection_id, perpage, page)
    
    self:showProgress(_("Cargando artículos..."))
    local raindrops, err = self:cachedRequest(endpoint)
    self:hideProgress()
    
    if not raindrops then
        self:notify(_("Error al obtener artículos: ") .. (err or _("Error desconocido")), 4)
        return
    end
    
    local menu_items = {}
    
    if raindrops.items then
        for _, raindrop in ipairs(raindrops.items) do
            local title = raindrop.title or _("Sin título")
            local domain = raindrop.domain or ""
            local date = ""
            if raindrop.created then
                date = " • " .. raindrop.created:sub(1, 10)
            end
            
            table.insert(menu_items, {
                text = title .. "\n" .. domain .. date,
                callback = function()
                    self:showRaindropContent(raindrop)
                end,
            })
        end
    end
    
    local total_count = raindrops.count or (#raindrops.items + page * perpage)
    if total_count > perpage then
        local total_pages = math.ceil(total_count / perpage)
        local current_page = page + 1
        
        if #menu_items > 0 then
            table.insert(menu_items, {text = "──────────────────", enabled = false})
        end
        
        if page > 0 then
            table.insert(menu_items, {
                text = _("← Página anterior"),
                callback = function()
                    self:showRaindrops(collection_id, collection_name, page - 1)
                end,
            })
        end
        
        if current_page < total_pages then
            table.insert(menu_items, {
                text = _("Página siguiente →"),
                callback = function()
                    self:showRaindrops(collection_id, collection_name, page + 1)
                end,
            })
        end
    end
    
    if #menu_items == 0 then
        table.insert(menu_items, {
            text = _("No hay artículos en esta colección"),
            enabled = false,
        })
    end
    
    local raindrops_menu = Menu:new{
        title = string.format("%s (%d)", collection_name or _("Artículos"), total_count),
        item_table = menu_items,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(raindrops_menu)
end

function Gota:showRaindropContent(raindrop)
    if not raindrop.cache then
        self:showProgress(_("Cargando contenido completo..."))
        local full_raindrop, err = self:cachedRequest("/raindrop/" .. raindrop._id)
        self:hideProgress()
        
        if full_raindrop and full_raindrop.item then
            raindrop = full_raindrop.item
        end
    end
    
    logger.dbg("Gota: Datos completos del caché:", 
               "cache:", raindrop.cache and "presente" or "nil",
               "status:", raindrop.cache and raindrop.cache.status or "n/a",
               "size:", raindrop.cache and raindrop.cache.size or 0,
               "texto presente:", raindrop.cache and raindrop.cache.text and "SÍ" or "NO",
               "texto longitud:", raindrop.cache and raindrop.cache.text and #raindrop.cache.text or 0)
    
    local has_cache = raindrop.cache and 
                     raindrop.cache.status == "ready" and 
                     (raindrop.cache.text or (raindrop.cache.size and raindrop.cache.size > 0))
    
    if has_cache and not raindrop.cache.text then
        self:showProgress(_("Cargando contenido en caché..."))
        local cache_content, err = self:makeRequestWithRetry("/raindrop/" .. raindrop._id .. "/cache")
        self:hideProgress()
        
        if cache_content and type(cache_content) == "string" and #cache_content > 0 then
            raindrop.cache.text = cache_content
            logger.dbg("Gota: Contenido HTML recibido correctamente, longitud:", #cache_content)
        elseif not raindrop.cache.text then
            raindrop.cache.text = _("Contenido disponible para descarga. Usa el botón 'Descargar HTML'.")
        end
    end
    
    if has_cache and (not raindrop.cache.text or #raindrop.cache.text < 50) then
        has_cache = false
    end
    
    if has_cache then
        self:showRaindropCachedContent(raindrop)
        return
    end
    
    local view_options = {
        {
            text = _("Ver información del artículo"),
            callback = function()
                self:showRaindropInfo(raindrop)
            end
        },
    }
    
    if raindrop.link then
        table.insert(view_options, {
            text = _("Copiar URL"),
            callback = function()
                self:showLinkInfo(raindrop)
            end
        })
    end
    
    local cache_message = ""
    if not has_cache and raindrop.cache then
        local status_names = {
            retry = _("La caché está siendo generada, intenta más tarde"),
            failed = _("La generación de caché ha fallado"),
            ["invalid-origin"] = _("No se pudo generar caché por origen inválido"),
            ["invalid-timeout"] = _("No se pudo generar caché por timeout"),
            ["invalid-size"] = _("No se pudo generar caché por tamaño excesivo")
        }
        cache_message = status_names[raindrop.cache.status] or _("La caché no está disponible")
        
        -- **INICIO DEL CAMBIO**
        table.insert(view_options, {
            text = _("Intentar recargar artículo completo"),
            callback = function()
                self:reloadRaindrop(raindrop._id)
            end
        })
        -- **FIN DEL CAMBIO**
    elseif not has_cache then
        cache_message = _("Este artículo no tiene contenido en caché disponible")
    end
    
    if cache_message ~= "" then
        table.insert(view_options, 1, {
            text = cache_message,
            enabled = false,
        })
    end
    
    local menu = Menu:new{
        title = raindrop.title or _("Artículo"),
        item_table = view_options,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.9,
    }
    
    UIManager:show(menu)
end

function Gota:reloadRaindrop(raindrop_id)
    self:showProgress(_("Recargando artículo..."))
    local full_raindrop, err = self:cachedRequest("/raindrop/" .. raindrop_id, "GET", nil, false)
    self:hideProgress()
    
    if full_raindrop and full_raindrop.item then
        if full_raindrop.item.cache and 
           full_raindrop.item.cache.status == "ready" and 
           full_raindrop.item.cache.text then
            self:showRaindropCachedContent(full_raindrop.item)
        else
            self:notify(_("El artículo aún no tiene contenido en caché disponible"))
            self:showRaindropInfo(full_raindrop.item)
        end
    else
        self:notify(_("Error al recargar artículo: ") .. (err or _("Error desconocido")))
    end
end

function Gota:showRaindropInfo(raindrop)
    local content = ""
    
    content = content .. (raindrop.title or _("Sin título")) .. "\n"
    content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    
    if raindrop.link then
        content = content .. _("URL: ") .. raindrop.link .. "\n\n"
    end
    
    if raindrop.domain then
        content = content .. _("Dominio: ") .. raindrop.domain .. "\n"
    end
    
    if raindrop.created then
        local date = raindrop.created:sub(1, 10)
        local time = raindrop.created:sub(12, 19)
        content = content .. _("Guardado: ") .. date .. " " .. time .. "\n\n"
    end
    
    if raindrop.type then
        local type_names = {
            link = _("Enlace"),
            article = _("Artículo"),
            image = _("Imagen"),
            video = _("Video"),
            document = _("Documento"),
            audio = _("Audio")
        }
        content = content .. _("Tipo: ") .. (type_names[raindrop.type] or raindrop.type) .. "\n\n"
    end
    
    if raindrop.excerpt and raindrop.excerpt ~= "" then
        content = content .. _("Extracto:") .. "\n"
        content = content .. raindrop.excerpt .. "\n\n"
    end
    
    if raindrop.note and raindrop.note ~= "" then
        content = content .. _("Notas:") .. "\n"
        content = content .. raindrop.note .. "\n\n"
    end
    
    if raindrop.tags and #raindrop.tags > 0 then
        content = content .. _("Etiquetas: ") .. table.concat(raindrop.tags, ", ") .. "\n\n"
    end
    
    if raindrop.cache then
        if raindrop.cache.status == "ready" then
            content = content .. _("Caché: ") .. _("Disponible") .. "\n"
            if raindrop.cache.size then
                content = content .. _("Tamaño: ") .. math.floor(raindrop.cache.size/1024) .. " KB\n"
            end
        elseif raindrop.cache.status then
            local status_names = {
                ready = _("Listo"),
                retry = _("Reintentando"),
                failed = _("Falló"),
                ["invalid-origin"] = _("Origen inválido"),
                ["invalid-timeout"] = _("Tiempo agotado"),
                ["invalid-size"] = _("Tamaño inválido")
            }
            content = content .. _("Estado del caché: ") .. (status_names[raindrop.cache.status] or raindrop.cache.status) .. "\n"
        end
        content = content .. "\n"
    end
    
    local text_viewer = TextViewer:new{
        title = raindrop.title or _("Información del artículo"),
        text = content,
        width = Device.screen:getWidth() * 0.95,
        height = Device.screen:getHeight() * 0.95,
    }
    
    UIManager:show(text_viewer)
end

function Gota:showDebugInfo()
    local debug_info = "DEBUG GOTA PLUGIN\n"
    debug_info = debug_info .. "══════════════════════\n\n"
    debug_info = debug_info .. "Token actual: " .. (self.token ~= "" and ("SET (" .. #self.token .. " chars)") or "NO SET") .. "\n"
    debug_info = debug_info .. "Archivo config: " .. (self.settings_file or "NO SET") .. "\n\n"
    
    if self.settings_file then
        local file = io.open(self.settings_file, "r")
        if file then
            local content = file:read("*all")
            file:close()
            debug_info = debug_info .. "Archivo existe: SÍ\n"
            debug_info = debug_info .. "Contenido (" .. #content .. " chars):\n"
            debug_info = debug_info .. content .. "\n"
        else
            debug_info = debug_info .. "Archivo existe: NO\n"
        end
    end
    
    debug_info = debug_info .. "\nServer URL: " .. (self.server_url or "NO SET")
    debug_info = debug_info .. "\nTamaño de caché: " .. (table_keys(self.response_cache) and #table_keys(self.response_cache) or 0) .. " entradas"
    debug_info = debug_info .. "\nTTL de caché: " .. self.cache_ttl .. " segundos"
    debug_info = debug_info .. "\nSoporte para Gzip: Usando descompresión del sistema"
    
    local text_viewer = TextViewer:new{
        title = "Debug Info - Gota Plugin",
        text = debug_info,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(text_viewer)
end

function Gota:searchRaindrops(search_term, page)
    page = page or 0
    local perpage = 25
    
    local endpoint = string.format("/raindrops/0?search=%s&perpage=%d&page=%d", 
                                   urlEncode(search_term), perpage, page)
    
    logger.dbg("Gota: Buscando con endpoint:", endpoint)
    
    self:showProgress(_("Buscando artículos..."))
    local results, err = self:cachedRequest(endpoint)
    self:hideProgress()
    
    if not results then
        self:notify(_("Error en la búsqueda: ") .. (err or _("Error desconocido")), 4)
        return
    end
    
    local menu_items = {}
    
    if results.items and #results.items > 0 then
        for _, raindrop in ipairs(results.items) do
            local title = raindrop.title or _("Sin título")
            local domain = raindrop.domain or ""
            local excerpt = ""
            if raindrop.excerpt then
                excerpt = "\n" .. raindrop.excerpt:sub(1, 50) .. "..."
            end
            
            table.insert(menu_items, {
                text = title .. "\n" .. domain .. excerpt,
                callback = function()
                    self:showRaindropContent(raindrop)
                end,
            })
        end
        
        local total_count = results.count or 0
        if total_count > perpage then
            local total_pages = math.ceil(total_count / perpage)
            local current_page = page + 1
            
            table.insert(menu_items, {text = "──────────────────", enabled = false})
            
            if page > 0 then
                table.insert(menu_items, {
                    text = _("← Página anterior"),
                    callback = function()
                        self:searchRaindrops(search_term, page - 1)
                    end,
                })
            end
            
            table.insert(menu_items, {
                text = string.format(_("Página %d de %d"), current_page, total_pages),
                enabled = false,
            })
            
            if current_page < total_pages then
                table.insert(menu_items, {
                    text = _("Página siguiente →"),
                    callback = function()
                        self:searchRaindrops(search_term, page + 1)
                    end,
                })
            end
        end
        
    else
        table.insert(menu_items, {
            text = _("No se encontraron resultados para: ") .. search_term,
            enabled = false,
        })
    end
    
    local search_menu = Menu:new{
        title = _("Resultados: '") .. search_term .. "' (" .. (results.count or 0) .. ")",
        item_table = menu_items,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(search_menu)
end

function Gota:showLinkInfo(raindrop)
    if not raindrop.link then
        self:notify(_("No hay enlace disponible para este artículo"))
        return
    end
    
    local content = _("URL del artículo:") .. "\n\n"
    content = content .. raindrop.link .. "\n\n"
    content = content .. _("No se puede abrir directamente en KOReader.") .. "\n"
    content = content .. _("Puedes copiar esta URL para abrirla en otro dispositivo.")
    
    local text_viewer = TextViewer:new{
        title = _("Enlace del artículo"),
        text = content,
        width = Device.screen:getWidth() * 0.95,
        height = Device.screen:getHeight() * 0.95,
    }
    
    UIManager:show(text_viewer)
end

function Gota:downloadRaindropHTML(raindrop)
    if not raindrop._id then
        self:notify(_("No se puede descargar: ID no encontrado"))
        return
    end
    
    if not raindrop.cache or raindrop.cache.status ~= "ready" then
        self:notify(_("No hay contenido en caché disponible para descargar"))
        return
    end
    
    local html_dir = DataStorage:getDataDir() .. "/gota_articles/"
    local util = require("util")
    if not util.makePath(html_dir) then
        self:notify(_("Error al crear directorio para guardar HTML"))
        return
    end
    
    local safe_title = (raindrop.title or "article"):gsub("[%c%p%s]", "_"):sub(1, 30)
    local filename = html_dir .. raindrop._id .. "_" .. safe_title .. ".html"
    
    self:showProgress(_("Descargando HTML..."))
    
    local html_content, err = self:makeRequestWithRetry("/raindrop/" .. raindrop._id .. "/cache")
    self:hideProgress()

    if not html_content or type(html_content) ~= "string" then
        self:notify(_("Error al descargar HTML: ") .. (err or "Respuesta inválida"))
        return
    end
        
    if #html_content < 100 then
        self:notify(_("El contenido descargado parece incompleto"))
        return
    end
    
    local file, file_err = io.open(filename, "wb")
    if not file then
        self:notify(_("Error al crear archivo: ") .. tostring(file_err))
        return
    end
    
    file:write(html_content)
    file:close()
    
    self:showDownloadOptions(filename, raindrop.title or _("Artículo"))
end

function Gota:showDownloadOptions(filename, title)
    local options = {
        {
            text = _("Abrir HTML descargado"),
            callback = function()
                self:openHTMLFile(filename)
            end
        },
        {
            text = _("Volver"),
            callback = function() end
        }
    }
    
    local menu = Menu:new{
        title = _("HTML descargado"),
        item_table = options,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.7,
    }
    
    UIManager:show(menu)
end

function Gota:openHTMLFile(filename)
    local ReaderUI = require("apps/reader/readerui")
    local DocumentRegistry = require("document/documentregistry")
    
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(filename, "mode") ~= "file" then
        self:notify(_("No se encontró el archivo HTML"))
        return
    end
    
    local document = DocumentRegistry:openDocument(filename)
    if document then
        local reader = ReaderUI:new{
            document = document,
            dithered = true,
        }
        UIManager:show(reader)
    else
        self:notify(_("No se pudo abrir el archivo HTML"))
    end
end

function Gota:showRaindropCachedContent(raindrop)
    if not raindrop.cache or not raindrop.cache.text then
        self:notify(_("No hay contenido en caché disponible"))
        return
    end
    
    local buttons_table = {
        {
            {
                text = _("Descargar HTML"),
                callback = function()
                    self:downloadRaindropHTML(raindrop)
                end
            }
        }
    }
    
    local content = raindrop.cache.text
    
    content = content:gsub("\n%s*\n%s*\n", "\n\n")
    content = content:gsub("<br[^>]*>", "\n")
    content = content:gsub("<p[^>]*>", "\n")
    content = content:gsub("</p>", "\n")
    content = content:gsub("<div[^>]*>", "\n")
    content = content:gsub("</div>", "\n")
    content = content:gsub("<[^>]+>", "")
    content = content:gsub("&nbsp;", " ")
    content = content:gsub("&lt;", "<")
    content = content:gsub("&gt;", ">")
    content = content:gsub("&quot;", "\"")
    content = content:gsub("&apos;", "'")
    content = content:gsub("&amp;", "&")
    content = content:gsub("\n\n+", "\n\n")
    
    local formatted_content = (raindrop.title or _("Sin título")) .. "\n"
    formatted_content = formatted_content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    
    if raindrop.domain then
        formatted_content = formatted_content .. _("Fuente: ") .. raindrop.domain .. "\n\n"
    end
    
    formatted_content = formatted_content .. content
    
    local text_viewer = TextViewer:new{
        title = _("Contenido en caché"),
        text = formatted_content,
        width = Device.screen:getWidth() * 0.95,
        height = Device.screen:getHeight() * 0.95,
        buttons = buttons_table,
    }
    
    UIManager:show(text_viewer)
end

function Gota:testToken(test_token)
    logger.dbg("Gota: Iniciando test de token, longitud:", #test_token)
    
    if #test_token < 20 then
        self:notify(_("⚠️ Token muy corto, verifica que sea correcto"), 3)
        return
    end
    
    local old_token = self.token
    self.token = test_token
    
    self:showProgress(_("Probando token..."))
    
    local user_data, err = self:makeRequestWithRetry("/user")
    
    self:hideProgress()
    self.token = old_token
    
    if user_data and user_data.user then
        logger.dbg("Gota: Test de token exitoso")
        local user_name = user_data.user.fullName or user_data.user.email or "Usuario verificado"
        local pro_status = user_data.user.pro and _(" (PRO)") or ""
        
        self:notify(_("✓ Token válido!\nUsuario: ") .. user_name .. pro_status, 4)
    else
        logger.err("Gota: Test de token falló:", err)
        self:notify(_("✗ Error con el token:\n") .. (err or "Token inválido"), 5)
    end
end

function Gota:showSearchDialog()
    self.search_dialog = InputDialog:new{
        title = _("Buscar artículos"),
        input = "",
        buttons = {
            {
                {
                    text = _("Cancelar"),
                    callback = function()
                        UIManager:close(self.search_dialog)
                    end,
                },
                {
                    text = _("Buscar"),
                    is_enter_default = true,
                    callback = function()
                        local search_term = self.search_dialog:getInputText()
                        if search_term and search_term ~= "" then
                            UIManager:close(self.search_dialog)
                            NetworkMgr:runWhenOnline(function()
                                self:searchRaindrops(search_term)
                            end)
                        else
                            self:notify(_("Por favor ingresa un término de búsqueda"))
                        end
                    end,
                }
            }
        },
    }
    UIManager:show(self.search_dialog)
    self.search_dialog:onShowKeyboard()
end

return Gota