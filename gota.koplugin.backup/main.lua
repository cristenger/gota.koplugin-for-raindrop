--[[
    Gota: Lector para Raindrop.io en KOReader
    Permite leer artículos guardados en Raindrop.io directamente en tu dispositivo.
    
    Versión: 2.0 (Versión simplificada y robusta)
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
local ButtonDialog = require("ui/widget/buttondialog")
local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("json")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Gota = WidgetContainer:extend{
    name = "gota",
    is_doc_only = false,
    server_url = "https://api.raindrop.io/rest/v1",
}

logger.info("Gota: Loading plugin...")

function Gota:init()
    logger.info("Gota: Initializing...")
    
    -- Configurar SSL
    https.cert_verify = false
    logger.dbg("Gota: SSL verification disabled for compatibility")
    
    -- Configurar archivos
    self.settings_file = DataStorage:getSettingsDir() .. "/gota.lua"
    
    -- Cargar configuración
    self:loadSettings()
    
    -- Inicializar caché
    self.cache = {}
    self.cache_ttl = 300 -- 5 minutos
    
    -- Registrar en el menú principal
    if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end
    
    logger.info("Gota: Initialization complete")
end

-- ============================
-- GESTIÓN DE CONFIGURACIÓN
-- ============================

function Gota:loadSettings()
    logger.dbg("Gota: Loading settings from", self.settings_file)
    local settings = {}
    
    if util.pathExists(self.settings_file) then
        local chunk, err = loadfile(self.settings_file)
        if chunk then
            local ok, result = pcall(chunk)
            if ok and type(result) == "table" then
                settings = result
                logger.dbg("Gota: Settings loaded successfully")
            else
                logger.warn("Gota: Failed to parse settings:", result)
            end
        else
            logger.warn("Gota: Failed to load settings file:", err)
        end
    else
        logger.dbg("Gota: Settings file doesn't exist, using defaults")
    end
    
    self.token = settings.token or ""
    logger.dbg("Gota: Token loaded, length:", #self.token)
end

function Gota:saveSettings()
    logger.dbg("Gota: Saving settings...")
    
    local settings = {
        token = self.token or "",
    }
    
    -- Crear directorio si no existe
    local settings_dir = DataStorage:getSettingsDir()
    local lfs = require("libs/libkoreader-lfs")
    if not lfs.attributes(settings_dir, "mode") then
        lfs.mkdir(settings_dir)
    end
    
    local file, err = io.open(self.settings_file, "w")
    if file then
        local content = string.format("return {\n  token = %q,\n}\n", settings.token)
        file:write(content)
        file:close()
        logger.dbg("Gota: Settings saved successfully")
        return true
    else
        logger.err("Gota: Failed to save settings:", err)
        self:notify(_("Error al guardar configuración: ") .. (err or "desconocido"))
        return false
    end
end

-- ============================
-- FUNCIONES DE UTILIDAD
-- ============================

function Gota:notify(text, timeout)
    timeout = timeout or 3
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout,
    })
end

function Gota:showProgress(text)
    self:hideProgress()
    self.progress_widget = InfoMessage:new{
        text = text or _("Cargando..."),
        timeout = 0,
    }
    UIManager:show(self.progress_widget)
    UIManager:forceRePaint()
end

function Gota:hideProgress()
    if self.progress_widget then
        UIManager:close(self.progress_widget)
        self.progress_widget = nil
    end
end

-- ============================
-- FUNCIONES DE RED Y API
-- ============================

function Gota:makeRequest(endpoint, method, body_data)
    method = method or "GET"
    local url = self.server_url .. endpoint
    
    logger.dbg("Gota/API:", method, url)
    
    local response_body = {}
    local request_body = body_data and JSON.encode(body_data) or nil
    
    local request = {
        url = url,
        method = method,
        sink = ltn12.sink.table(response_body),
        headers = {
            ["Accept"] = "application/json",
            ["Accept-Encoding"] = "identity", -- No compression
            ["User-Agent"] = "KOReader-Gota/2.0",
        },
    }
    
    -- Agregar token si está disponible
    if self.token and self.token ~= "" then
        request.headers["Authorization"] = "Bearer " .. self.token
    end
    
    -- Agregar body si es necesario
    if request_body then
        request.headers["Content-Type"] = "application/json"
        request.headers["Content-Length"] = tostring(#request_body)
        request.source = ltn12.source.string(request_body)
    end
    
    -- Intentar HTTPS primero, luego HTTP como fallback
    local ok, status_or_err, headers, status_code
    
    ok, status_or_err, headers, status_code = pcall(https.request, request)
    
    if not ok then
        logger.warn("Gota: HTTPS failed, trying HTTP fallback:", status_or_err)
        -- Cambiar URL a HTTP
        request.url = request.url:gsub("^https://", "http://")
        ok, status_or_err, headers, status_code = pcall(http.request, request)
    end
    
    if not ok then
        local error_msg = "Connection failed: " .. tostring(status_or_err)
        logger.err("Gota/API:", error_msg)
        return nil, error_msg
    end
    
    local response_text = table.concat(response_body)
    
    if status_code ~= 200 then
        local error_msg = string.format("HTTP %d: %s", status_code, response_text)
        logger.err("Gota/API:", error_msg)
        return nil, error_msg
    end
    
    -- Parsear JSON
    local success, data = pcall(JSON.decode, response_text)
    if not success then
        logger.err("Gota/API: JSON parse error:", data)
        return nil, "Invalid JSON response"
    end
    
    return data, nil
end

function Gota:makeRequestWithRetry(endpoint, method, body_data, max_retries)
    max_retries = max_retries or 2
    
    for attempt = 1, max_retries do
        logger.dbg("Gota/API: Attempt", attempt, "for", endpoint)
        
        local data, err = self:makeRequest(endpoint, method, body_data)
        
        if data then
            return data, nil
        end
        
        logger.warn("Gota/API: Attempt", attempt, "failed:", err)
        
        if attempt < max_retries then
            -- Esperar un poco antes del siguiente intento
            logger.dbg("Gota/API: Waiting before retry...")
        end
    end
    
    return nil, "Failed after " .. max_retries .. " attempts"
end

-- ============================
-- FUNCIONES DE UI - DIÁLOGOS
-- ============================

function Gota:showTokenDialog()
    local dialog
    
    dialog = InputDialog:new{
        title = _("Token de Raindrop.io"),
        description = _("Ingresa tu token de acceso:\n\n1. Ve a: https://app.raindrop.io/settings/integrations\n2. Crea una nueva app\n3. Copia el 'Test token'"),
        input = self.token or "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancelar"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Probar"),
                    callback = function()
                        local test_token = dialog:getInputText()
                        if test_token and test_token:match("%S") then
                            test_token = test_token:gsub("^%s+", ""):gsub("%s+$", "")
                            self:testToken(test_token)
                        else
                            self:notify(_("Por favor ingresa un token válido"))
                        end
                    end,
                },
                {
                    text = _("Guardar"),
                    is_enter_default = true,
                    callback = function()
                        local new_token = dialog:getInputText()
                        if new_token and new_token:match("%S") then
                            new_token = new_token:gsub("^%s+", ""):gsub("%s+$", "")
                            self.token = new_token
                            if self:saveSettings() then
                                UIManager:close(dialog)
                                self:notify(_("Token guardado correctamente"))
                            end
                        else
                            self:notify(_("Por favor ingresa un token válido"))
                        end
                    end,
                }
            }
        },
    }
    
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Gota:showSearchDialog()
    local dialog
    
    dialog = InputDialog:new{
        title = _("Buscar artículos"),
        description = _("Ingresa términos de búsqueda:"),
        input = "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancelar"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Buscar"),
                    is_enter_default = true,
                    callback = function()
                        local search_term = dialog:getInputText()
                        if search_term and search_term:match("%S") then
                            UIManager:close(dialog)
                            NetworkMgr:runWhenOnline(function()
                                self:searchRaindrops(search_term:gsub("^%s+", ""):gsub("%s+$", ""))
                            end)
                        else
                            self:notify(_("Por favor ingresa un término de búsqueda"))
                        end
                    end,
                }
            }
        },
    }
    
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ============================
-- FUNCIONES DE NEGOCIO
-- ============================

function Gota:testToken(test_token)
    self:showProgress(_("Probando token..."))
    
    local old_token = self.token
    self.token = test_token
    
    local user_data, err = self:makeRequestWithRetry("/user")
    
    self:hideProgress()
    self.token = old_token  -- Restaurar token original
    
    if user_data and user_data.user then
        local user_name = user_data.user.fullName or user_data.user.email or "Usuario"
        local pro_status = user_data.user.pro and " (PRO)" or ""
        self:notify(_("✓ Token válido!\nUsuario: ") .. user_name .. pro_status, 4)
    else
        self:notify(_("✗ Token inválido\nError: ") .. (err or "Desconocido"), 4)
    end
end

function Gota:showCollections()
    self:showProgress(_("Cargando colecciones..."))
    
    local data, err = self:makeRequestWithRetry("/collections")
    
    self:hideProgress()
    
    if not data then
        self:notify(_("Error al cargar colecciones: ") .. (err or "Desconocido"))
        return
    end
    
    local collections = data.items or {}
    if #collections == 0 then
        self:notify(_("No se encontraron colecciones"))
        return
    end
    
    local menu_items = {}
    
    for _, collection in ipairs(collections) do
        table.insert(menu_items, {
            text = BD.ltr(collection.title or ("ID: " .. tostring(collection._id))),
            callback = function()
                self:showRaindrops(collection._id, collection.title)
            end,
        })
    end
    
    -- Agregar separador y opción de cerrar
    table.insert(menu_items, Menu.separator)
    table.insert(menu_items, {
        text = _("Cerrar"),
        callback = function() end, -- Se cierra automáticamente
    })
    
    UIManager:show(Menu:new{
        title = _("Colecciones"),
        item_table = menu_items,
        width_ratio = 0.8,
        height_ratio = 0.8,
    })
end

function Gota:showRaindrops(collection_id, collection_title)
    self:showProgress(_("Cargando artículos..."))
    
    local endpoint = collection_id == 0 and "/raindrops/0" or "/raindrops/" .. tostring(collection_id)
    local data, err = self:makeRequestWithRetry(endpoint)
    
    self:hideProgress()
    
    if not data then
        self:notify(_("Error al cargar artículos: ") .. (err or "Desconocido"))
        return
    end
    
    local raindrops = data.items or {}
    if #raindrops == 0 then
        self:notify(_("No se encontraron artículos"))
        return
    end
    
    local menu_items = {}
    
    for _, raindrop in ipairs(raindrops) do
        table.insert(menu_items, {
            text = BD.ltr(raindrop.title or raindrop.link or "Sin título"),
            callback = function()
                self:openRaindrop(raindrop)
            end,
        })
    end
    
    -- Agregar separador y opción de volver
    table.insert(menu_items, Menu.separator)
    table.insert(menu_items, {
        text = _("Volver"),
        callback = function() end,
    })
    
    UIManager:show(Menu:new{
        title = collection_title or _("Artículos"),
        item_table = menu_items,
        width_ratio = 0.8,
        height_ratio = 0.8,
    })
end

function Gota:searchRaindrops(search_term)
    self:showProgress(_("Buscando..."))
    
    local endpoint = "/raindrops/0?search=" .. self:urlEncode(search_term)
    local data, err = self:makeRequestWithRetry(endpoint)
    
    self:hideProgress()
    
    if not data then
        self:notify(_("Error en la búsqueda: ") .. (err or "Desconocido"))
        return
    end
    
    local raindrops = data.items or {}
    if #raindrops == 0 then
        self:notify(_("No se encontraron resultados para: ") .. search_term)
        return
    end
    
    local menu_items = {}
    
    for _, raindrop in ipairs(raindrops) do
        table.insert(menu_items, {
            text = BD.ltr(raindrop.title or raindrop.link or "Sin título"),
            callback = function()
                self:openRaindrop(raindrop)
            end,
        })
    end
    
    -- Agregar separador y opción de cerrar
    table.insert(menu_items, Menu.separator)
    table.insert(menu_items, {
        text = _("Cerrar"),
        callback = function() end,
    })
    
    UIManager:show(Menu:new{
        title = _("Resultados: ") .. search_term,
        item_table = menu_items,
        width_ratio = 0.8,
        height_ratio = 0.8,
    })
end

function Gota:openRaindrop(raindrop)
    local content = raindrop.excerpt or raindrop.note or ""
    local title = raindrop.title or raindrop.link or "Sin título"
    
    if content == "" then
        content = _("Enlace: ") .. (raindrop.link or "N/A") .. "\n\n" ..
                 _("Descripción: ") .. (raindrop.excerpt or "Sin descripción")
    end
    
    UIManager:show(TextViewer:new{
        title = title,
        text = content,
        buttons_table = {
            {
                {
                    text = _("Cerrar"),
                    callback = function()
                        UIManager:close()
                    end,
                }
            }
        }
    })
end

-- ============================
-- UTILIDADES
-- ============================

function Gota:urlEncode(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

-- ============================
-- MENÚ PRINCIPAL
-- ============================

function Gota:addToMainMenu(menu_items)
    logger.info("Gota: Adding to main menu...")
    
    menu_items.gota = {
        text = _("Gota (Raindrop.io)"),
        sorting_hint = "search",
        sub_item_table = {
            {
                text = _("Configurar token"),
                callback = function()
                    self:showTokenDialog()
                end,
            },
            {
                text = _("Ver colecciones"),
                enabled_func = function()
                    return self.token and self.token ~= ""
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
                    return self.token and self.token ~= ""
                end,
                callback = function()
                    self:showSearchDialog()
                end,
            },
            {
                text = _("Todos los artículos"),
                enabled_func = function()
                    return self.token and self.token ~= ""
                end,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        self:showRaindrops(0, _("Todos los artículos"))
                    end)
                end,
            },
        }
    }
    
    logger.info("Gota: Menu added successfully")
end

return Gota