local InputDialog = require("ui/widget/inputdialog")
local Menu        = require("ui/widget/menu")
local UIManager   = require("ui/uimanager")
local BD          = require("ui/bidi")
local Device      = require("device")
local _           = require("gettext")

local Search = {}

--------------------------------------------------
-- inicialización
--------------------------------------------------
function Search:init(state, api, ui)
    self.state, self.api, self.ui = state, api, ui
end

--------------------------------------------------
-- diálogo para introducir la búsqueda
--------------------------------------------------
function Search:showDialog()
    self.dlg = InputDialog:new{
        title       = _("Buscar en Raindrop.io"),
        description = _("Introduce palabras clave"),
        input       = "",
        buttons     = {
            {
                text = _("Cancelar"),
                callback = function() UIManager:close(self.dlg) end,
            },
            {
                text = _("Buscar"),
                is_enter_default = true,
                callback = function()
                    local q = (self.dlg:getInputText() or ""):gsub("^%s+",""):gsub("%s+$","")
                    UIManager:close(self.dlg)
                    if q == "" then return end
                    self:perform(q)
                end,
            },
        },
    }
    UIManager:show(self.dlg)
    self.dlg:onShowKeyboard()
end

--------------------------------------------------
-- realiza la consulta usando el endpoint de búsqueda
--------------------------------------------------
function Search:perform(query)
    self.ui:showProgress(_("Buscando…"))
    -- Raindrop.io permite buscar en la colección 0 (todos)
    local ep = string.format("/raindrops/0?search=%s", Device.urlencode(query))
    local data, err = self.api:cachedRequest(ep, "GET", nil, 0)
    self.ui:hideProgress()

    if not data then
        self.ui:notify(_("Error: ") .. (err or ""))
        return
    end

    self:showResults(query, data.items or {})
end

--------------------------------------------------
-- muestra resultados en un menú
--------------------------------------------------
function Search:showResults(query, items)
    if #items == 0 then
        self.ui:notify(_("Sin resultados"))
        return
    end

    local menu_items, sep = {}, Menu.separator
    for _, rd in ipairs(items) do
        table.insert(menu_items, {
            text     = BD.col(rd.title or rd.link),
            callback = function() self.state.content:view(rd) end,
        })
    end
    table.insert(menu_items, sep)
    table.insert(menu_items, { text = _("Atrás") })

    UIManager:show(Menu:new{
        title         = string.format(_("Resultados: «%s»"), query),
        menu_items    = menu_items,
        parent_widget = self.state,
    })
end

return Search