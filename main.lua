
--[[
    Raindrop.io plugin para KOReader - Versión Simplificada
    Permite leer artículos guardados en Raindrop.io directamente en tu Kindle
    
    Versión: 1.1 (Simplificada)
    
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
    str = str:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

-- Manejo centralizado de notificaciones
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
    
    -- Deshabilitar verificación SSL globalmente para evitar problemas en Kindle
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
            local ok, data = pcall(loadstring("return " .. content))
            if ok and type(data) == "table" then
                settings = data
            end
        end
    end
    
    self.token = settings.token or ""
    self.server_url = "https://api.raindrop.io/rest/v1"
end

function Raindrop:saveSettings()
    local settings = {
        token = self.token,
    }
    
    local file = io.open(self.settings_file, "w")
    if file then
        -- Serialización simple sin dependencias externas
        file:write("return {\n")
        file:write(string.format('  token = %q,\n', settings.token))
        file:write("}\n")
        file:close()
        logger.dbg("Raindrop: Configuración guardada")
    else
        logger.warn("Raindrop: No se pudo guardar configuración")
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

-- Función simplificada para el diálogo de token
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
                            self:testToken(test_token)
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
                            -- Limpiar espacios en blanco al inicio y final
                            new_token = new_token:gsub("^%s+", ""):gsub("%s+$", "")
                            
                            -- Debug: mostrar el token recibido (sin logging sensible)
                            logger.dbg("Raindrop: Token recibido, longitud:", #new_token, "primeros 10 chars:", new_token:sub(1, 10))
                            
                            -- Validación básica de longitud
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

-- Función para probar el token sin guardarlo
function Raindrop:testToken(test_token)
    local old_token = self.token
    self.token = test_token -- Temporalmente usar el token de prueba
    
    local user_data, err = self:makeRequest("/user")
    
    self.token = old_token -- Restaurar token original
    
    if user_data then
        local user_name = "Usuario verificado"
        if user_data.user and user_data.user.fullName then
            user_name = user_data.user.fullName
        elseif user_data.user and user_data.user.email then
            user_name = user_data.user.email
        end
        
        self:notify(_("✓ Token válido!\nUsuario: ") .. user_name)
    else
        self:notify(_("✗ Error con el token:\n") .. (err or "Token inválido"), 4)
    end
end

-- Función simplificada para hacer requests HTTP
function Raindrop:makeRequest(endpoint, method)
    local url = self.server_url .. endpoint
    logger.dbg("Raindrop: Realizando solicitud a", url)
    
    if not self.token or self.token == "" then
        logger.err("Raindrop: Token no configurado")
        return nil, "Token de acceso no configurado"
    end
    
    local sink = {}
    
    -- CRÍTICO: Deshabilitar verificación SSL para pruebas
    https.cert_verify = false
    
    -- Configuración HTTP simplificada
    local request = {
        url = url,
        method = method or "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.token,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "KOReader-Raindrop-Plugin/1.1"
        },
        sink = ltn12.sink.table(sink),
        timeout = 15,
        -- Configuración SSL sin verificación para evitar errores de certificados
        protocol = "tlsv1_2",
        mode = "client",
        verify = "none",
    }
    
    -- CORRECCIÓN: Capturar valores correctamente de https.request
    local ok, body, status_code, headers, status = pcall(function()
        return https.request(request)
    end)
    
    if not ok then
        logger.err("Raindrop: Error en conexión HTTPS:", body)
        return nil, "Error de conexión: " .. tostring(body)
    end
    
    -- body contiene la respuesta, status_code es el código HTTP
    if status_code ~= 200 then
        logger.err("Raindrop: Error HTTP", status_code, status)
        
        if status_code == 401 then
            return nil, "Token de acceso inválido o expirado"
        elseif status_code == 403 then
            return nil, "Acceso denegado - verificar permisos del token"
        elseif status_code == 429 then
            return nil, "Demasiadas solicitudes - intenta más tarde"
        else
            return nil, string.format("Error HTTP %d: %s", status_code, status or "Sin respuesta")
        end
    end
    
    local response = table.concat(sink)
    if #response == 0 then
        return nil, "Respuesta vacía del servidor"
    end
    
    local decode_ok, data = pcall(JSON.decode, response)
    if not decode_ok then
        logger.err("Raindrop: Error al parsear JSON:", data)
        return nil, "Error al procesar respuesta del servidor"
    end
    
    return data
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
    local content = ""
    
    -- Información básica
    content = content .. raindrop.title .. "\n"
    content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    
    if raindrop.link then
        content = content .. _("URL: ") .. raindrop.link .. "\n\n"
    end
    
    if raindrop.created then
        content = content .. _("Guardado: ") .. raindrop.created .. "\n\n"
    end
    
    -- Extracto/descripción
    if raindrop.excerpt then
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
    
    -- Contenido completo si está disponible
    if raindrop.cache and raindrop.cache.text then
        content = content .. "\n" .. _("Contenido completo:") .. "\n"
        content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        content = content .. raindrop.cache.text
    end
    
    local text_viewer = TextViewer:new{
        title = raindrop.title,
        text = content,
        width = Device.screen:getWidth() * 0.95,
        height = Device.screen:getHeight() * 0.95,
    }
    
    UIManager:show(text_viewer)
end

-- Función simplificada para búsqueda
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

function Raindrop:searchRaindrops(search_term)
    local endpoint = "/raindrops/0?search=" .. urlEncode(search_term)
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
    else
        table.insert(menu_items, {
            text = T(_("No se encontraron resultados para: %1"), search_term),
            enabled = false,
        })
    end
    
    local search_menu = Menu:new{
        title = T(_("Resultados de búsqueda (%1)"), results.count or #results.items or 0),
        item_table = menu_items,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(search_menu)
end

return Raindrop