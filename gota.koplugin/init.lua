local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

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

function Gota:new(o)
    o = o or {}
    o = WidgetContainer.new(self, o)
    return o
end

function Gota:init()
    -- Inicializar caché para respuestas
    self.response_cache = {}
    self.cache_ttl = 300  -- 5 minutos de vida para el caché
    
    -- Cargar módulos desde el directorio del plugin
    local plugin_dir = self:getPluginDir()
    
    -- Cargar todos los módulos necesarios
    self.api = dofile(plugin_dir .. "/api.lua")
    self.auth = dofile(plugin_dir .. "/auth.lua")
    self.ui = dofile(plugin_dir .. "/ui.lua")
    self.content = dofile(plugin_dir .. "/content.lua")
    self.collections = dofile(plugin_dir .. "/collections.lua")
    self.search = dofile(plugin_dir .. "/search.lua")
    
    -- Inicializar módulos
    self.api:init(self)
    self.auth:init(self)
    self.ui:init(self)
    self.content:init(self, self.api, self.ui)
    self.collections:init(self, self.api, self.ui)
    self.search:init(self, self.api, self.ui)
    
    -- Usar el método de UI para registrar en el menú principal
    self.ui:addToMainMenu(self)
    
    -- Cargar token si existe
    self.token = self.token or ""
    logger.info("Gota: Inicializado correctamente")
end

function Gota:addToMainMenu(menu_items)
    logger.info("Gota: addToMainMenu called")
    menu_items.gota = {
        text = _("Gota (Raindrop.io)"),
        sub_item_table = {
            {
                text = _("Configurar token"),
                callback = function()
                    if self.auth then
                        self.auth:showDialog()
                    else
                        self:notify(_("Error: módulo de autenticación no disponible"))
                    end
                end,
            },
        }
    }
    logger.info("Gota: Menu items added: " .. tostring(menu_items.gota ~= nil))
end

return Gota