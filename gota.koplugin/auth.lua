local DataStorage  = require("datastorage")
local InputDialog  = require("ui/widget/inputdialog")
local InfoMessage  = require("ui/widget/infomessage")
local UIManager    = require("ui/uimanager")
local logger       = require("logger")
local util         = require("util")
local _            = require("gettext")

local Auth = {}

-- estado: referencia al objeto Gota principal
function Auth:init(state)
    self.state         = state
    self.settings_file = DataStorage:getSettingsDir() .. "/gota.lua"
    self:load()
end

-- ------------------------------------------------
-- persistencia
-- ------------------------------------------------
function Auth:load()
    local settings = {}
    local f = io.open(self.settings_file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        settings = util.parseSettings(content)
    end
    self.state.token = settings.token or ""
    logger.dbg("Gota: token cargado, longitud:", #self.state.token)
end

function Auth:save()
    local file, err = io.open(self.settings_file, "w")
    if not file then
        logger.err("Gota: no se pudo guardar settings:", err)
        return
    end
    file:write(string.format("return {\n  token = %q,\n}\n", self.state.token))
    file:close()
    logger.dbg("Gota: configuración guardada")
end

-- ------------------------------------------------
-- diálogo de configuración
-- ------------------------------------------------
function Auth:showDialog()
    self.dialog = InputDialog:new{
        title       = _("Token de acceso de Raindrop.io"),
        description = _("Pega aquí tu token (Test Token o Personal Token)"),
        input       = self.state.token or "",
        input_type  = "text",
        buttons     = {
            {
                text = _("Cancelar"),
                callback = function() UIManager:close(self.dialog) end,
            },
            {
                text = _("Guardar"),
                is_enter_default = true,
                callback = function()
                    local tok = (self.dialog:getInputText() or ""):gsub("^%s+",""):gsub("%s+$","")
                    if tok == "" then
                        UIManager:show(InfoMessage:new{ text = _("Token vacío"), timeout = 2 })
                        return
                    end
                    self.state.token = tok
                    self:save()
                    UIManager:close(self.dialog)
                    UIManager:show(InfoMessage:new{ text = _("Token guardado"), timeout = 2 })
                end,
            },
        },
    }
    UIManager:show(self.dialog)
    self.dialog:onShowKeyboard()
end

return Auth