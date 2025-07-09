local InfoMessage = require("ui/widget/infomessage")
local UIManager   = require("ui/uimanager")
local Menu        = require("ui/widget/menu")
local _           = require("gettext")
local logger      = require("logger")

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

return UI