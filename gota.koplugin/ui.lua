local InfoMessage = require("ui/widget/infomessage")
local UIManager   = require("ui/uimanager")
local Menu        = require("ui/widget/menu")
local _           = require("gettext")
local logger      = require("logger")  -- Add this line

local UI = {}

--------------------------------------------------
-- inicialización
--------------------------------------------------
function UI:init(parent)
    self.parent   = parent          -- objeto Gota
    self.progress = nil             -- widget de progreso
    self.menu     = Menu            -- alias para usar desde init.lua
end

--------------------------------------------------
-- utilidades de notificación
--------------------------------------------------
function UI:showProgress(text)
    self:hideProgress()
    self.progress = InfoMessage:new{ text = text or _("Cargando…"), timeout = 0 }
    UIManager:show(self.progress)
    UIManager:forceRePaint()
end

function UI:hideProgress()
    if self.progress then UIManager:close(self.progress) end
    self.progress = nil
end

function UI:notify(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 3 })
end

--------------------------------------------------
-- menú principal de KOReader
--------------------------------------------------
function UI:addToMainMenu(widget)
    -- Remove the call to registerToMainMenu which doesn't exist
    -- Instead, just set a flag so we know the menu should be registered
    self.parent_widget = widget
    logger.info("UI: addToMainMenu called - parent widget stored")
end

function UI:populateMainMenu(menu_items)
    -- This is where you define the actual menu items
    if not self.parent_widget then return end
    
    logger.info("UI: populateMainMenu called")
    menu_items.gota = {
        text = _("Gota (Raindrop.io)"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Configurar token"),
                callback = function()
                    if self.parent_widget.auth then
                        self.parent_widget.auth:showDialog()
                    else
                        self:notify(_("Error: módulo de autenticación no disponible"))
                    end
                end,
            },
        }
    }
    logger.info("UI: Menu items added: " .. tostring(menu_items.gota ~= nil))
end

return UI