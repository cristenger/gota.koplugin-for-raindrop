local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

logger.info("Gota: Loading complete functional plugin")

local Gota = WidgetContainer:extend{
    name = "gota",
    is_doc_only = false,
    server_url = "https://api.raindrop.io/rest/v1",
}

-- Función para obtener la ruta del plugin
function Gota:getPluginDir()
    local path = debug.getinfo(2, "S").source:sub(2)
    return path:match("(.+)/[^/]+$")
end

function Gota:notify(text, timeout)
    timeout = timeout or 3
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout,
    })
end

function Gota:init()
    logger.info("Gota: init() - initializing complete plugin")
    
    -- Verificar UI context
    logger.info("Gota: self.ui exists:", self.ui and "YES" or "NO")
    
    if self.ui then
        logger.info("Gota: self.ui.name:", self.ui.name or "nil")
        if self.ui.menu and self.ui.menu.registerToMainMenu then
            logger.info("Gota: Registering to main menu")
            self.ui.menu:registerToMainMenu(self)
        end
    end
    
    -- Inicializar caché para respuestas
    self.response_cache = {}
    self.cache_ttl = 300  -- 5 minutos de vida para el caché
    
    -- Cargar módulos desde el directorio del plugin
    local plugin_dir = self:getPluginDir()
    logger.info("Gota: Loading modules from:", plugin_dir)
    
    -- Función helper para cargar módulos con error handling
    local function loadModule(name, path)
        logger.info("Gota: Loading module", name)
        local success, module = pcall(dofile, path)
        if not success then
            logger.err("Gota: Failed to load module", name, "error:", module)
            return nil
        end
        logger.info("Gota: Module", name, "loaded successfully")
        return module
    end
    
    -- Cargar todos los módulos necesarios
    self.api = loadModule("api", plugin_dir .. "/api.lua")
    self.auth = loadModule("auth", plugin_dir .. "/auth.lua")
    self.ui_module = loadModule("ui_module", plugin_dir .. "/ui.lua")
    self.content = loadModule("content", plugin_dir .. "/content.lua")
    self.collections = loadModule("collections", plugin_dir .. "/collections.lua")
    self.search = loadModule("search", plugin_dir .. "/search.lua")
    
    -- Inicializar módulos que se cargaron exitosamente
    if self.api then self.api:init(self) end
    if self.auth then self.auth:init(self) end
    if self.ui_module then self.ui_module:init(self) end
    if self.content then self.content:init(self, self.api, self.ui_module) end
    if self.collections then self.collections:init(self, self.api, self.ui_module) end
    if self.search then self.search:init(self, self.api, self.ui_module) end
    
    -- Cargar token si existe
    self.token = self.token or ""
    logger.info("Gota: Complete initialization finished")
end

-- ESTE MÉTODO ES LLAMADO POR KOREADER AUTOMÁTICAMENTE
function Gota:addToMainMenu(menu_items)
    logger.info("Gota: ========== addToMainMenu CALLED! ==========")
    logger.info("Gota: Building complete menu structure")
    
    if not menu_items then
        logger.err("Gota: menu_items is nil!")
        return
    end
    
    -- Construir menú completo
    local sub_items = {}
    
    -- Item 1: Configurar token
    table.insert(sub_items, {
        text = _("Configurar token"),
        callback = function()
            logger.info("Gota: 'Configurar token' selected")
            if self.auth then
                self.auth:showDialog()
            else
                self:notify(_("Error: módulo de autenticación no disponible"))
            end
        end,
    })
    
    -- Item 2: Ver colecciones (solo si hay token)
    table.insert(sub_items, {
        text = _("Ver colecciones"),
        enabled_func = function()
            local has_token = self.token and self.token ~= ""
            logger.dbg("Gota: Check token for collections:", has_token)
            return has_token
        end,
        callback = function()
            logger.info("Gota: 'Ver colecciones' selected")
            if self.collections then
                self.collections:show()
            else
                self:notify(_("Error: módulo de colecciones no disponible"))
            end
        end,
    })
    
    -- Item 3: Buscar artículos (solo si hay token)
    table.insert(sub_items, {
        text = _("Buscar artículos"),
        enabled_func = function()
            local has_token = self.token and self.token ~= ""
            logger.dbg("Gota: Check token for search:", has_token)
            return has_token
        end,
        callback = function()
            logger.info("Gota: 'Buscar artículos' selected")
            if self.search then
                self.search:showDialog()
            else
                self:notify(_("Error: módulo de búsqueda no disponible"))
            end
        end,
    })
    
    -- Crear entrada principal del menú
    menu_items.gota = {
        text = _("Gota (Raindrop.io)"),
        sorting_hint = "search",
        sub_item_table = sub_items
    }
    
    logger.info("Gota: Complete menu added successfully")
    logger.info("Gota: Sub-items count:", #sub_items)
    logger.info("Gota: menu_items.gota exists:", menu_items.gota and "YES" or "NO")
end

logger.info("Gota: Complete plugin definition ready")
return Gota:new{}