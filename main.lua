--[[
    Raindrop.io plugin para KOReader - Versión Optimizada
    Permite leer artículos guardados en Raindrop.io directamente en tu Kindle
    
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

local Raindrop = WidgetContainer:extend{
    name = "raindrop",
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
    local chunk, err = loadstring(content)
    if chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" then
            return result
        end
    end
    
    -- Método 2: Intentar envolver en return si no funciona
    local wrapped_content = "return " .. content
    chunk, err = loadstring(wrapped_content)
    if chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" then
            return result
        end
    end
    
    -- Método 3: Intentar evaluar directamente
    local env = {}
    chunk, err = loadstring(content)
    if chunk then
        setfenv(chunk, env)
        local ok = pcall(chunk)
        if ok and next(env) then
            return env
        end
    end
    
    logger.warn("Raindrop: No se pudo parsear configuración:", err)
    return {}
end

-- Función mejorada para descomprimir contenido Gzip
function Raindrop:decompressGzip(compressed_data)
    -- Esta función ya no se usa, pero la mantenemos por compatibilidad
    logger.warn("Raindrop: decompressGzip llamada pero no debería usarse")
    return nil
end

function Raindrop:notify(text, timeout)
    timeout = timeout or 3
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout,
    })
end

function Raindrop:init()
    self.settings_file = DataStorage:getSettingsDir() .. "/raindrop.lua"
    self:loadSettings()
    
    -- CORRECCIÓN: configurar SSL una sola vez al inicio
    https.cert_verify = false
    logger.dbg("Raindrop: SSL verificación desactivada para compatibilidad")
    
    -- Inicializar caché para respuestas
    self.response_cache = {}
    self.cache_ttl = 300  -- 5 minutos de vida para el caché
    
    self.ui.menu:registerToMainMenu(self)
end

function Raindrop:loadSettings()
    local settings = {}
    
    if self.settings_file then
        local file = io.open(self.settings_file, "r")
        if file then
            local content = file:read("*all")
            file:close()
            
            logger.dbg("Raindrop: Contenido leído del archivo:", content and #content or "nil")
            
            if content and content ~= "" then
                -- CORRECCIÓN: usar función de parsing robusta
                settings = parseSettings(content)
                if next(settings) then
                    logger.dbg("Raindrop: Configuración cargada exitosamente")
                else
                    logger.warn("Raindrop: No se pudo parsear configuración, usando defaults")
                end
            end
        else
            logger.dbg("Raindrop: Archivo de configuración no existe, usando defaults")
        end
    end
    
    self.token = settings.token or ""
    self.server_url = "https://api.raindrop.io/rest/v1"
    
    logger.dbg("Raindrop: Token cargado, longitud:", #self.token)
end

function Raindrop:saveSettings()
    local settings = {
        token = self.token,
    }
    
    logger.dbg("Raindrop: Intentando guardar token, longitud:", #self.token)
    
    local file, err = io.open(self.settings_file, "w")
    if file then
        -- CORRECCIÓN: serialización más robusta con escape completo
        local serialized = string.format("return {\n  token = %q,\n}\n", settings.token)
        file:write(serialized)
        file:close()
        logger.dbg("Raindrop: Configuración guardada exitosamente")
    else
        logger.err("Raindrop: No se pudo abrir archivo para escritura:", err)
        self:notify("Error: No se pudo guardar la configuración")
    end
end

function Raindrop:addToMainMenu(menu_items)
    menu_items.raindrop = {
        text = _("Raindrop.io"),
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

function Raindrop:showTokenDialog()
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
                            
                            logger.dbg("Raindrop: Token recibido, longitud:", #new_token)
                            
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

function Raindrop:makeRequest(endpoint, method, body)
    local url = self.server_url .. endpoint
    logger.dbg("Raindrop: Iniciando solicitud a", url)
    logger.dbg("Raindrop: Solicitando respuesta sin comprimir (Accept-Encoding: identity)")

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
            ["User-Agent"]    = "KOReader-Raindrop-Plugin/1.6",
            -- IMPORTANTE: Pedimos respuestas sin comprimir para evitar problemas
            -- La API de Raindrop envía gzip por defecto, pero KOReader tiene problemas
            -- para descomprimirlo correctamente. "identity" = sin compresión
            ["Accept-Encoding"] = "identity",
        },
        sink    = ltn12.sink.table(sink),
        -- Opciones para mejorar compatibilidad
        protocol = "any", -- Aceptar cualquier protocolo en lugar de TLS específico
        options = "all", -- Usar todas las opciones disponibles
        timeout = 30,    -- Reducir el timeout para evitar esperas largas
    }

    -- si hay body (POST/PUT), lo serializamos desde el argumento
    if (method == "POST" or method == "PUT") then
        local payload = JSON.encode(body or {})
        request.source         = ltn12.source.string(payload)
        request.headers["Content-Length"] = #payload
    end

    -- Establecer timeouts más sofisticados antes de la petición
    local socketutil = require("socketutil")
    socketutil:set_timeout(10, 30)  -- Reducido de 45 a 30s total para respuestas más rápidas
    
    -- HTTPS
    local ok, r1, r2, r3, r4 = pcall(https.request, request)
    
    -- Si falla HTTPS, intentar con HTTP como fallback
    if not ok and r1:match("unreachable") then
        logger.warn("Raindrop: HTTPS falló, intentando con HTTP como fallback")
        -- Cambiar a HTTP y reintentar
        request.url = request.url:gsub("^https:", "http:")
        ok, r1, r2, r3, r4 = pcall(http.request, request)
    end
    
    -- Restaurar timeouts por defecto
    socketutil:reset_timeout()
    
    -- cerramos siempre el loading
    UIManager:close(loading_msg)

    if not ok then
        logger.err("Raindrop: request falló:", r1)
        return nil, _("Error de conexión: ") .. tostring(r1)
    end

    local result, status_code, response_headers, status_line = r1, r2, r3, r4
    -- determino el status real
    local actual_status = (result ~= 1 and type(result)=="number") and result or status_code

    -- Debug para diagnóstico
    logger.dbg("Raindrop: Debug raw result:", result, "status_code:", status_code)
    logger.dbg("Raindrop: Status determinado:", actual_status)

    -- Manejo de respuestas con mejor estructura
    if actual_status == 200 then
        local resp = table.concat(sink)
        
        if #resp > 0 then
            -- Verificar si la respuesta está comprimida con Gzip
            local is_gzipped = false
            if response_headers and response_headers["content-encoding"] then
                local encoding = response_headers["content-encoding"]:lower()
                is_gzipped = encoding:find("gzip") ~= nil
                if is_gzipped then
                    logger.warn("Raindrop: Servidor envió gzip a pesar de Accept-Encoding: identity")
                end
            end
            
            -- Características de datos comprimidos (útil para detectar gzip aunque no lo indique)
            local might_be_gzipped = resp:byte(1) == 31 and resp:byte(2) == 139
            
            -- Descomprimir si es necesario
            if is_gzipped or might_be_gzipped then
                logger.dbg("Raindrop: Detectada respuesta comprimida con Gzip")
                -- Si recibimos gzip a pesar de pedir identity, es un problema
                logger.err("Raindrop: El servidor envió gzip cuando pedimos sin comprimir")
                -- Intentar usar comando del sistema como fallback
                local temp_in = "/tmp/raindrop_gzip_" .. os.time() .. ".gz"
                local temp_out = "/tmp/raindrop_out_" .. os.time() .. ".txt"
                
                local file = io.open(temp_in, "wb")
                if file then
                    file:write(resp)
                    file:close()
                    
                    -- Intentar con gunzip o gzip -d
                    local ok = os.execute("gunzip -c " .. temp_in .. " > " .. temp_out .. " 2>/dev/null")
                    if ok ~= 0 then
                        ok = os.execute("gzip -dc " .. temp_in .. " > " .. temp_out .. " 2>/dev/null")
                    end
                    
                    if ok == 0 then
                        file = io.open(temp_out, "rb")
                        if file then
                            resp = file:read("*all")
                            file:close()
                            logger.dbg("Raindrop: Descompresión exitosa con comando del sistema")
                        end
                    end
                    
                    -- Limpiar archivos temporales
                    os.remove(temp_in)
                    os.remove(temp_out)
                else
                    logger.err("Raindrop: No se pudo crear archivo temporal para descompresión")
                end
                
                -- Si aún tenemos datos comprimidos, no podemos continuar
                if resp:byte(1) == 31 and resp:byte(2) == 139 then
                    return nil, _("Error: No se pudo descomprimir la respuesta del servidor")
                end
            end
            
            -- Verificar si es HTML directo (endpoint /cache)
            if endpoint:match("/cache$") then
                logger.dbg("Raindrop: Respuesta de caché detectada como HTML directo")
                return resp  -- Devolver HTML sin procesar como JSON
            end
            
            -- Intentar decodificar como JSON
            local dec_ok, data = pcall(function() return JSON.decode(resp) end)
            if dec_ok then
                return data
            else
                -- Añadir más información de diagnóstico
                logger.err("Raindrop: JSON.decode error:", data)
                logger.err("Raindrop: JSON contenido (primeros 200 chars):", resp:sub(1,200))
                -- Verificar si los datos siguen comprimidos
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
        logger.err("Raindrop: HTTP error", actual_status, resp:sub(1,200))
        return nil, _("Error HTTP ") .. tostring(actual_status)
    end
end

function Raindrop:makeRequestWithRetry(endpoint, method, body, max_retries)
    max_retries = max_retries or 3
    local attempts = 0
    
    while attempts < max_retries do
        attempts = attempts + 1
        
        if attempts > 1 then
            self:showProgress(_("Reintentando conexión (") .. attempts .. "/" .. max_retries .. ")...")
            -- Pequeña pausa entre intentos
            os.execute("sleep 1")
        end
        
        local result, err = self:makeRequest(endpoint, method, body)
        
        if result or (err and not err:match("conexión") and not err:match("timeout")) then
            -- Si tenemos resultado o es un error que no es de conexión
            return result, err
        end
        
        logger.warn("Raindrop: Reintentando solicitud después de error:", err)
    end
    
    return nil, _("Falló después de ") .. max_retries .. _(" intentos")
end

function Raindrop:showProgress(text)
    if self.progress_message then
        UIManager:close(self.progress_message)
    end
    self.progress_message = InfoMessage:new{text = text, timeout = 1}
    UIManager:show(self.progress_message)
    UIManager:forceRePaint()
end

function Raindrop:hideProgress()
    if self.progress_message then 
        UIManager:close(self.progress_message) 
    end
    self.progress_message = nil
end

function Raindrop:cachedRequest(endpoint, method, body, use_cache)
    -- Por defecto usamos caché solo para solicitudes GET
    use_cache = (use_cache == nil) and (method == "GET" or method == nil) or use_cache
    
    if use_cache and method == "GET" then
        local cache_key = endpoint
        local cached = self.response_cache[cache_key]
        
        if cached and os.time() - cached.timestamp < self.cache_ttl then
            logger.dbg("Raindrop: Usando respuesta en caché para", endpoint)
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

function Raindrop:showCollections()
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

function Raindrop:showRaindrops(collection_id, collection_name, page)
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
    
    -- Navegación de páginas con fallback para count
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

function Raindrop:showRaindropContent(raindrop)
    -- Verificar si necesitamos obtener el contenido completo
    if not raindrop.cache then
        -- Intentar obtener el artículo completo
        self:showProgress(_("Cargando contenido completo..."))
        local full_raindrop, err = self:cachedRequest("/raindrop/" .. raindrop._id)
        self:hideProgress()
        
        if full_raindrop and full_raindrop.item then
            raindrop = full_raindrop.item
        end
    end
    
    -- Registro de diagnóstico completo para ver la estructura del objeto
    logger.dbg("Raindrop: Datos completos del caché:", 
               "cache:", raindrop.cache and "presente" or "nil",
               "status:", raindrop.cache and raindrop.cache.status or "n/a",
               "size:", raindrop.cache and raindrop.cache.size or 0,
               "texto presente:", raindrop.cache and raindrop.cache.text and "SÍ" or "NO",
               "texto longitud:", raindrop.cache and raindrop.cache.text and #raindrop.cache.text or 0)
    
    -- SOLUCIÓN: Mejorar la detección de caché disponible
    -- Un artículo tiene caché si: tiene estado "ready" Y (tiene texto O tiene tamaño > 0)
    local has_cache = raindrop.cache and 
                     raindrop.cache.status == "ready" and 
                     (raindrop.cache.text or (raindrop.cache.size and raindrop.cache.size > 0))
    
    -- Si detectamos que hay caché pero falta el texto, intentar cargarlo
    if has_cache and not raindrop.cache.text then
        self:showProgress(_("Cargando contenido en caché..."))
        -- Intentar obtener el texto del caché
        local cache_content, err = self:makeRequestWithRetry("/raindrop/" .. raindrop._id .. "/cache")
        self:hideProgress()
        
        -- SOLUCIÓN: Manejar correctamente las respuestas HTML directas
        if cache_content and type(cache_content) == "string" and #cache_content > 0 then
            -- Si recibimos HTML directamente, guardarlo en la estructura
            raindrop.cache.text = cache_content
            logger.dbg("Raindrop: Contenido HTML recibido correctamente, longitud:", #cache_content)
        elseif not raindrop.cache.text then
            -- Si aún no tenemos texto, crear un texto mínimo
            raindrop.cache.text = _("Contenido disponible para descarga. Usa el botón 'Descargar HTML'.")
        end
    end
    
    -- Verificar nuevamente si realmente tenemos texto útil
    if has_cache and (not raindrop.cache.text or #raindrop.cache.text < 50) then
        -- Si el texto es muy corto o inexistente, no considerarlo como caché válida
        has_cache = false
    end
    
    -- Si hay caché disponible, mostrar directamente el contenido
    if has_cache then
        self:showRaindropCachedContent(raindrop)
        return
    end
    
    -- Si no hay caché, mostrar menú de opciones alternativas
    local view_options = {
        {
            text = _("Ver información del artículo"),
            callback = function()
                self:showRaindropInfo(raindrop)
            end
        },
    }
    
    -- Opción de URL siempre disponible
    if raindrop.link then
        table.insert(view_options, {
            text = _("Copiar URL"),
            callback = function()
                self:showLinkInfo(raindrop)
            end
        })
    end
    
    -- Mensaje de estado de la caché
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
        
        -- Añadir opción para forzar la recarga
        table.insert(view_options, {
            text = _("Intentar recargar artículo completo"),
            callback = function()
                self:reloadRaindrop(raindrop._id)
            end
        })
    elseif not has_cache then
        cache_message = _("Este artículo no tiene contenido en caché disponible")
    end
    
    -- Si hay mensaje de caché, mostrarlo como opción deshabilitada
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

-- Nueva función para recargar un artículo específico
function Raindrop:reloadRaindrop(raindrop_id)
    self:showProgress(_("Recargando artículo..."))
    -- Forzar recarga sin usar caché
    local full_raindrop, err = self:cachedRequest("/raindrop/" .. raindrop_id, "GET", nil, false)
    self:hideProgress()
    
    if full_raindrop and full_raindrop.item then
        -- Si el artículo tiene caché ahora, mostrarlo
        if full_raindrop.item.cache and 
           full_raindrop.item.cache.status == "ready" and 
           full_raindrop.item.cache.text then
            self:showRaindropCachedContent(full_raindrop.item)
        else
            -- Si sigue sin caché, mostrar información
            self:notify(_("El artículo aún no tiene contenido en caché disponible"))
            self:showRaindropInfo(full_raindrop.item)
        end
    else
        self:notify(_("Error al recargar artículo: ") .. (err or _("Error desconocido")))
    end
end

function Raindrop:showRaindropInfo(raindrop)
    local content = ""
    
    -- Información básica
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
    
    -- Tipo de contenido
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
    
    -- Extracto/descripción
    if raindrop.excerpt and raindrop.excerpt ~= "" then
        content = content .. _("Extracto:") .. "\n"
        content = content .. raindrop.excerpt .. "\n\n"
    end
    
    -- Notas del usuario
    if raindrop.note and raindrop.note ~= "" then
        content = content .. _("Notas:") .. "\n"
        content = content .. raindrop.note .. "\n\n"
    end
    
    -- Tags
    if raindrop.tags and #raindrop.tags > 0 then
        content = content .. _("Etiquetas: ") .. table.concat(raindrop.tags, ", ") .. "\n\n"
    end
    
    -- Información de caché
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

function Raindrop:showDebugInfo()
    local debug_info = "DEBUG RAINDROP PLUGIN\n"
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
        title = "Debug Info - Raindrop Plugin",
        text = debug_info,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(text_viewer)
end

function Raindrop:searchRaindrops(search_term, page)
    page = page or 0
    local perpage = 25
    
    local endpoint = string.format("/raindrops/0?search=%s&perpage=%d&page=%d", 
                                   urlEncode(search_term), perpage, page)
    
    logger.dbg("Raindrop: Buscando con endpoint:", endpoint)
    
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
        
        -- Agregar navegación de páginas para búsquedas
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

-- Reemplazar la función de navegador con una para mostrar la URL
function Raindrop:showLinkInfo(raindrop)
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

-- Función para descargar el HTML en caché
function Raindrop:downloadRaindropHTML(raindrop)
    -- Verificar que el raindrop tiene una ID válida
    if not raindrop._id then
        self:notify(_("No se puede descargar: ID no encontrado"))
        return
    end
    
    -- Verificar que el usuario tiene una suscripción PRO (necesaria para esta función)
    if not raindrop.cache or raindrop.cache.status ~= "ready" then
        self:notify(_("No hay contenido en caché disponible para descargar"))
        return
    end
    
    -- Crear directorio para archivos HTML si no existe
    local html_dir = DataStorage:getDataDir() .. "/raindrop_articles/"
    local util = require("util")
    local success = util.makePath(html_dir)
    if not success then
        self:notify(_("Error al crear directorio para guardar HTML"))
        return
    end
    
    -- Generar un nombre de archivo basado en el ID y título
    local safe_title = (raindrop.title or "article"):gsub("[%c%p%s]", "_"):sub(1, 30)
    local filename = html_dir .. raindrop._id .. "_" .. safe_title .. ".html"
    
    -- Mostrar mensaje de progreso
    self:showProgress(_("Descargando HTML..."))
    
    -- Preparar la solicitud al endpoint de caché
    local endpoint = "/raindrop/" .. raindrop._id .. "/cache"
    local url = self.server_url .. endpoint
    
    logger.dbg("Raindrop: Descargando HTML desde", url)
    
    -- Configurar la solicitud para recibir el HTML directamente
    local sink = {}
    local request = {
        url = url,
        method = "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.token,
            ["Accept-Encoding"] = "identity", -- No aceptar gzip
            ["User-Agent"] = "KOReader-Raindrop-Plugin/1.6",
        },
        sink = ltn12.sink.table(sink),
        protocol = "any",
        timeout = 30,
    }
    
    -- Realizar la solicitud
    local socketutil = require("socketutil")
    socketutil:set_timeout(15, 60)  -- Tiempo más largo para descargas
    local ok, r1, r2, r3, r4 = pcall(https.request, request)
    socketutil:reset_timeout()
    
    self:hideProgress()
    
    -- Verificar si la solicitud fue exitosa
    if not ok then
        self:notify(_("Error al descargar HTML: ") .. tostring(r1))
        return
    end
    
    local status_code = r2
    local response_headers = r3
    
    -- Si recibimos un código 200, guardamos el archivo
    if status_code == 200 then
        local html_content = table.concat(sink)
        
        -- Verificar si la respuesta está comprimida con Gzip
        local is_gzipped = false
        if response_headers and response_headers["content-encoding"] then
            is_gzipped = response_headers["content-encoding"]:find("gzip") ~= nil
        end
        
        -- Características de datos comprimidos (útil para detectar gzip aunque no lo indique)
        local might_be_gzipped = html_content:byte(1) == 31 and html_content:byte(2) == 139
        
        -- Descomprimir si es necesario
        if is_gzipped or might_be_gzipped then
            logger.dbg("Raindrop: Detectada respuesta comprimida con Gzip al descargar")
            -- Usar el mismo método que en makeRequest
            local temp_in = "/tmp/raindrop_download_" .. os.time() .. ".gz"
            local temp_out = "/tmp/raindrop_download_out_" .. os.time() .. ".html"
            
            local temp_file = io.open(temp_in, "wb")
            if temp_file then
                temp_file:write(html_content)
                temp_file:close()
                
                local ok = os.execute("gunzip -c " .. temp_in .. " > " .. temp_out .. " 2>/dev/null")
                if ok ~= 0 then
                    ok = os.execute("gzip -dc " .. temp_in .. " > " .. temp_out .. " 2>/dev/null")
                end
                
                if ok == 0 then
                    temp_file = io.open(temp_out, "rb")
                    if temp_file then
                        html_content = temp_file:read("*all")
                        temp_file:close()
                        logger.dbg("Raindrop: Descompresión exitosa al descargar")
                    end
                end
                
                os.remove(temp_in)
                os.remove(temp_out)
            end
        end
        
        -- Verificar que hay contenido
        if #html_content < 100 then
            self:notify(_("El contenido descargado parece incompleto"))
            return
        end
        
        -- Guardar el archivo HTML
        local file, err = io.open(filename, "wb")
        if not file then
            self:notify(_("Error al crear archivo: ") .. tostring(err))
            return
        end
        
        file:write(html_content)
        file:close()
        
        -- Mostrar opciones para el archivo descargado
        self:showDownloadOptions(filename, raindrop.title or _("Artículo"))
    elseif status_code == 307 or status_code == 302 or status_code == 301 then
        -- Redireccionamiento - común para archivos grandes
        -- Intentar seguir la redirección manualmente
        local redirect_url = response_headers and response_headers.location
        if redirect_url then
            self:notify(_("Redirección a: ") .. redirect_url .. "\n" .. _("Esta funcionalidad requiere plan PRO de Raindrop.io"), 5)
        else
            self:notify(_("Redirección sin URL. Código: ") .. status_code)
        end
    else
        self:notify(_("Error al descargar. Código: ") .. status_code)
    end
end

-- Función para mostrar opciones después de la descarga
function Raindrop:showDownloadOptions(filename, title)
    -- Preparar menú de opciones
    local options = {
        {
            text = _("Abrir HTML descargado"),
            callback = function()
                self:openHTMLFile(filename)
            end
        },
        {
            text = _("Volver"),
            callback = function() end  -- No hace nada, simplemente cierra este menú
        }
    }
    
    -- Mostrar mensaje con opciones
    local menu = Menu:new{
        title = _("HTML descargado"),
        item_table = options,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.7,
    }
    
    UIManager:show(menu)
end

-- Función para abrir el archivo HTML con KOReader
function Raindrop:openHTMLFile(filename)
    -- Intentar abrir el archivo HTML con el lector de documentos de KOReader
    local ReaderUI = require("apps/reader/readerui")
    local DocumentRegistry = require("document/documentregistry")
    
    -- Verificar si el archivo existe
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(filename, "mode") ~= "file" then
        self:notify(_("No se encontró el archivo HTML"))
        return
    end
    
    -- Crear un nuevo ReaderUI para abrir el archivo
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

-- Función para mostrar el contenido en caché con botón de descarga
function Raindrop:showRaindropCachedContent(raindrop)
    if not raindrop.cache or not raindrop.cache.text then
        self:notify(_("No hay contenido en caché disponible"))
        return
    end
    
    -- SOLUCIÓN: Estructura correcta para botones en TextViewer
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
    
    -- Mejorar el formato del texto en caché
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
    
    -- Añadir título del artículo al principio
    local formatted_content = (raindrop.title or _("Sin título")) .. "\n"
    formatted_content = formatted_content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    
    -- Añadir el dominio como información de fuente
    if raindrop.domain then
        formatted_content = formatted_content .. _("Fuente: ") .. raindrop.domain .. "\n\n"
    end
    
    formatted_content = formatted_content .. content
    
    -- Mostrar en visor de texto con botón de descarga
    local text_viewer = TextViewer:new{
        title = _("Contenido en caché"),
        text = formatted_content,
        width = Device.screen:getWidth() * 0.95,
        height = Device.screen:getHeight() * 0.95,
        buttons = buttons_table,  -- Estructura de botones corregida
    }
    
    UIManager:show(text_viewer)
end

function Raindrop:testToken(test_token)
    logger.dbg("Raindrop: Iniciando test de token, longitud:", #test_token)
    
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
        logger.dbg("Raindrop: Test de token exitoso")
        local user_name = user_data.user.fullName or user_data.user.email or "Usuario verificado"
        local pro_status = user_data.user.pro and _(" (PRO)") or ""
        
        self:notify(_("✓ Token válido!\nUsuario: ") .. user_name .. pro_status, 4)
    else
        logger.err("Raindrop: Test de token falló:", err)
        self:notify(_("✗ Error con el token:\n") .. (err or "Token inválido"), 5)
    end
end

function Raindrop:showSearchDialog()
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

-- Necesario para que KOReader registre el plugin
return Raindrop