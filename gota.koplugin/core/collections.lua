local Menu        = require("ui/widget/menu")
local UIManager   = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer  = require("ui/widget/textviewer")
local Device      = require("device")
local BD          = require("ui/bidi")
local _           = require("gettext")
local logger      = require("logger")

local Collections = {}

--------------------------------------------------
-- inicialización
--------------------------------------------------
function Collections:init(state, api, ui)
    self.state, self.api, self.ui = state, api, ui
end

--------------------------------------------------
-- menú de colecciones
--------------------------------------------------
function Collections:show()
    self.ui:showProgress(_("Cargando colecciones…"))
    local data, err = self.api:cachedRequest("/collections")
    self.ui:hideProgress()

    if not data then
        self.ui:notify(_("Error obteniendo colecciones: ") .. (err or ""))
        return
    end

    local items, sep = {}, Menu.separator
    for _, col in ipairs(data.items or {}) do
        table.insert(items, {
            text     = BD.col(col.title or ("#" .. col._id)),
            callback = function() self:showRaindrops(col) end,
        })
    end
    table.insert(items, sep)
    table.insert(items, { text = _("Cerrar") })

    UIManager:show(Menu:new{
        title          = _("Colecciones"),
        menu_items     = items,
        parent_widget  = self.state,
    })
end

--------------------------------------------------
-- menú de raindrops dentro de una colección
--------------------------------------------------
function Collections:showRaindrops(col)
    self.ui:showProgress(_("Cargando…"))
    local endpoint = string.format("/raindrops/%d", col._id)
    local data, err = self.api:cachedRequest(endpoint)
    self.ui:hideProgress()

    if not data then
        self.ui:notify(_("Error: ") .. (err or ""))
        return
    end

    local items, sep = {}, Menu.separator
    for _, rd in ipairs(data.items or {}) do
        table.insert(items, {
            text     = BD.col(rd.title or rd.link),
            callback = function() self:openRaindrop(rd) end,
        })
    end
    table.insert(items, sep)
    table.insert(items, { text = _("Atrás") })

    UIManager:show(Menu:new{
        title          = col.title or _("Raindrops"),
        menu_items     = items,
        parent_widget  = self.state,
    })
end

--------------------------------------------------
-- visor sencillo del contenido (usa módulo Content)
--------------------------------------------------
function Collections:openRaindrop(rd)
    -- delegamos al módulo Content para reutilizar toda la lógica común
    self.state.content:view(rd)
end

return Collections