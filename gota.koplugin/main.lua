local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

logger.info("Gota: Loading plugin with UI nil protection")

local Gota = WidgetContainer:extend{
    name = "gota",
    is_doc_only = false,
}

function Gota:init()
    logger.info("Gota: init() called")
    logger.info("Gota: self.ui exists:", self.ui and "YES" or "NO")
    logger.info("Gota: self.ui type:", type(self.ui))
    
    if self.ui then
        logger.info("Gota: self.ui.name:", self.ui.name or "nil")
        logger.info("Gota: self.ui.menu exists:", self.ui.menu and "YES" or "NO")
        
        -- Solo registrar si tenemos UI y menú
        if self.ui.menu and self.ui.menu.registerToMainMenu then
            logger.info("Gota: Registering to main menu")
            self.ui.menu:registerToMainMenu(self)
        else
            logger.warn("Gota: No menu found, cannot register")
        end
    else
        logger.warn("Gota: self.ui is nil, cannot register to menu")
    end
    
    self.token = ""
    logger.info("Gota: init() completed")
end

function Gota:notify(text, timeout)
    timeout = timeout or 3
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout,
    })
end

-- ESTE MÉTODO ES LLAMADO POR KOREADER AUTOMÁTICAMENTE
function Gota:addToMainMenu(menu_items)
    logger.info("Gota: ========== addToMainMenu CALLED! ==========")
    logger.info("Gota: menu_items type:", type(menu_items))
    
    if not menu_items then
        logger.err("Gota: menu_items is nil!")
        return
    end
    
    menu_items.gota = {
        text = _("Gota (Fixed UI)"),
        sorting_hint = "search",
        callback = function()
            logger.info("Gota: Menu callback executed!")
            UIManager:show(InfoMessage:new{
                text = "¡Gota funciona! Error de UI corregido.",
                timeout = 5,
            })
        end
    }
    
    logger.info("Gota: Menu added successfully")
    logger.info("Gota: menu_items.gota exists:", menu_items.gota and "YES" or "NO")
end

logger.info("Gota: Plugin definition complete, returning new instance")
return Gota:new{}