--[[
    Raindrop.io plugin para KOReader - Versión Corregida
    Permite leer artículos guardados en Raindrop.io directamente en tu Kindle
    
    Versión: 1.2 (Corregida)
    
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
    -- CORRECCIÓN: método más robusto para parsear configuración Lua
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

-- CORRECCIÓN CRÍTICA: función makeRequest completamente reescrita
function Raindrop:makeRequest(endpoint, method)
    local url = self.server_url .. endpoint
    logger.dbg("Raindrop: Iniciando solicitud a", url)
    
    if not self.token or self.token == "" then
        logger.err("Raindrop: Token no configurado")
        return nil, "Token de acceso no configurado"
    end
    
    -- Mostrar mensaje de carga
    local loading_msg = InfoMessage:new{
        text = _("Conectando con Raindrop.io..."),
        timeout = 0,
    }
    UIManager:show(loading_msg)
    UIManager:forceRePaint()
    
    local sink = {}
    
    -- Request según documentación Raindrop.io
    local request = {
        url = url,
        method = method or "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.token,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "KOReader-Raindrop-Plugin/1.2"
        },
        sink = ltn12.sink.table(sink),
        timeout = 15,
    }
    
    logger.dbg("Raindrop: Enviando request con método:", method or "GET")
    logger.dbg("Raindrop: Headers:", JSON.encode(request.headers))
    
    -- CORRECCIÓN CRÍTICA: manejo correcto de https.request con pcall
    local success, result, status_code, response_headers, status_line = pcall(https.request, request)
    
    -- Cerrar mensaje de carga
    UIManager:close(loading_msg)
    
    -- CORRECCIÓN: verificar primero si pcall fue exitoso
    if not success then
        logger.err("Raindrop: Error en pcall https.request:", result)
        return nil, "Error de conexión SSL: " .. tostring(result)
    end
    
    -- Debug: mostrar qué devolvió https.request
    logger.dbg("Raindrop: https.request result:", result, "type:", type(result))
    logger.dbg("Raindrop: https.request status_code:", status_code, "type:", type(status_code))
    logger.dbg("Raindrop: https.request status_line:", status_line)
    
    -- CORRECCIÓN: lógica simplificada para determinar status
    local actual_status
    
    if result == 1 then
        -- Caso exitoso: result=1, status en status_code
        if type(status_code) == "number" then
            actual_status = status_code
        else
            logger.warn("Raindrop: result=1 pero status_code no es número, asumiendo 200")
            actual_status = 200
        end
    elseif type(result) == "number" then
        -- Caso de error: result contiene el código de error
        actual_status = result
    else
        logger.err("Raindrop: Respuesta inesperada de https.request")
        return nil, "Respuesta inesperada del servidor"
    end
    
    logger.dbg("Raindrop: Status determinado:", actual_status)
    
    -- Procesar respuesta según código de estado
    if actual_status == 200 then
        local response = table.concat(sink)
        logger.dbg("Raindrop: Respuesta exitosa, longitud:", #response)
        
        if #response > 0 then
            local decode_ok, data = pcall(JSON.decode, response)
            if decode_ok then
                logger.dbg("Raindrop: JSON parseado exitosamente")
                return data
            else
                logger.err("Raindrop: Error JSON:", tostring(data))
                logger.err("Raindrop: Response raw (200 chars):", response:sub(1, 200))
                return nil, "Error al decodificar JSON"
            end
        else
            logger.warn("Raindrop: Respuesta vacía con status 200")
            return {}
        end
        
    elseif actual_status == 204 then
        logger.dbg("Raindrop: Respuesta exitosa sin contenido (204)")
        return {}
        
    elseif actual_status == 401 then
        logger.err("Raindrop: Error de autenticación (401)")
        return nil, "Token de acceso inválido o expirado (401)"
        
    elseif actual_status == 403 then
        logger.err("Raindrop: Error de permisos (403)")
        return nil, "Acceso denegado - verificar permisos del token (403)"
        
    elseif actual_status == 429 then
        logger.err("Raindrop: Rate limit alcanzado (429)")
        local error_msg = "Rate limit excedido - intenta más tarde (429)"
        
        if type(response_headers) == "table" then
            local rate_limit = response_headers["X-RateLimit-Limit"]
            local rate_remaining = response_headers["X-RateLimit-Remaining"]
            if rate_limit or rate_remaining then
                error_msg = error_msg .. string.format("\nLímite: %s req/min, Restantes: %s", 
                                                      rate_limit or "?", rate_remaining or "?")
            end
        end
        return nil, error_msg
        
    else
        -- Error desconocido
        local response = table.concat(sink)
        if #response > 0 then
            logger.err("Raindrop: Response body (500 chars):", response:sub(1, 500))
        end
        
        logger.err("Raindrop: Status code inesperado:", actual_status)
        return nil, string.format("Error HTTP %s: %s", actual_status, status_line or "Desconocido")
    end
end

function Raindrop:showCollections()
    local collections, err = self:makeRequest("/collections")
    
    if not collections then
        self:notify(T(_("Error al obtener colecciones:\n%1"), err or "Error desconocido"), 4)
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
    
    local raindrops, err = self:makeRequest(endpoint)
    
    if not raindrops then
        self:notify(T(_("Error al obtener artículos: %1"), err), 4)
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
    if not raindrop.cache or not raindrop.cache.text then
        -- Intentar obtener el artículo completo
        local full_raindrop, err = self:makeRequest("/raindrop/" .. raindrop._id)
        if full_raindrop and full_raindrop.item then
            raindrop = full_raindrop.item
        end
    end
    
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
        if raindrop.cache.status == "ready" and raindrop.cache.text then
            content = content .. "\n" .. _("Contenido completo:") .. "\n"
            content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
            content = content .. raindrop.cache.text
        elseif raindrop.cache.status then
            local status_names = {
                ready = _("Listo"),
                retry = _("Reintentando"),
                failed = _("Falló"),
                ["invalid-origin"] = _("Origen inválido"),
                ["invalid-timeout"] = _("Tiempo agotado"),
                ["invalid-size"] = _("Tamaño inválido")
            }
            content = content .. _("Estado del caché: ") .. (status_names[raindrop.cache.status] or raindrop.cache.status) .. "\n\n"
        end
    end
    
    local text_viewer = TextViewer:new{
        title = raindrop.title or _("Artículo"),
        text = content,
        width = Device.screen:getWidth() * 0.95,
        height = Device.screen:getHeight() * 0.95,
    }
    
    UIManager:show(text_viewer)
end

function Raindrop:showSearchDialog()
    self.search_dialog = InputDialog:new{
        title = _("Buscar en Raindrop"),
        input_hint = _("Término de búsqueda..."),
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
                        end
                    end,
                }
            }
        },
    }
    UIManager:show(self.search_dialog)
    self.search_dialog:onShowKeyboard()
end

function Raindrop:testToken(test_token)
    logger.dbg("Raindrop: Iniciando test de token, longitud:", #test_token)
    
    if #test_token < 20 then
        self:notify(_("⚠️ Token muy corto, verifica que sea correcto"), 3)
        return
    end
    
    local old_token = self.token
    self.token = test_token
    
    self:notify(_("Probando token..."), 1)
    
    local user_data, err = self:makeRequest("/user")
    
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
    
    local results, err = self:makeRequest(endpoint)
    
    if not results then
        self:notify(T(_("Error en la búsqueda: %1"), err), 4)
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
            text = T(_("No se encontraron resultados para: %1"), search_term),
            enabled = false,
        })
    end
    
    local search_menu = Menu:new{
        title = T(_("Resultados: '%1' (%2)"), search_term, results.count or 0),
        item_table = menu_items,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(search_menu)
end

-- Necesario para que KOReader registre el plugin
return Raindrop