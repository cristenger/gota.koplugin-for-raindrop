local UIManager   = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer  = require("ui/widget/textviewer")
local Device      = require("device")
local _           = require("gettext")
local DataStorage = require("datastorage")
local Menu        = require("ui/widget/menu")
local JSON        = require("json")
local logger      = require("logger")

local Content = {}

--------------------------------------------------
-- inicialización
--------------------------------------------------
function Content:init(state, api, ui)
    self.state, self.api, self.ui = state, api, ui
end

--------------------------------------------------
-- descarga el artículo y devuelve la tabla JSON
-- (no lanza diálogos, sólo devuelve datos o nil + err)
--------------------------------------------------
function Content:fetch(rd)
    if not rd or not rd.link then
        return nil, _("Raindrop vacío")
    end
    local url = "/article?url=" .. Device.urlencode(rd.link)
    return self.api:cachedRequest(url, "GET", nil, 0)
end

--------------------------------------------------
-- muestra el artículo en un TextViewer
--------------------------------------------------
function Content:view(rd)
    self.ui:showProgress(_("Descargando artículo…"))
    local data, err = self:fetch(rd)
    self.ui:hideProgress()

    if not data then
        self.ui:notify(_("Error: ") .. (err or ""))
        return
    end

    local html = data.article or data.content or ""
    UIManager:show(TextViewer:new{
        text  = html ~= "" and html or _("(vacío)"),
        title = rd.title or rd.link,
    })
end

--------------------------------------------------
-- recarga un raindrop concreto (ignora caché)
--------------------------------------------------
function Content:reloadRaindrop(id)
    if not id then return nil, _("ID vacío") end
    self.ui:showProgress(_("Actualizando…"))
    local data, err = self.api:cachedRequest("/raindrop/" .. id, "GET", nil, 0)
    self.ui:hideProgress()
    return data, err
end

--------------------------------------------------
-- muestra información JSON cruda del raindrop
--------------------------------------------------
function Content:showRaindropInfo(rd)
    local txt = JSON.encode(rd, { indent = true })
    UIManager:show(TextViewer:new{
        text  = txt,
        title = rd.title or _("Información"),
    })
end

--------------------------------------------------
-- muestra info resumida del enlace
--------------------------------------------------
function Content:showLinkInfo(rd)
    local txt = string.format("ID: %s\nURL: %s\nTags: %s",
        rd._id or "?", rd.link or "?", table.concat(rd.tags or {}, ", "))
    UIManager:show(TextViewer:new{
        text  = txt,
        title = rd.title or _("Enlace"),
    })
end

--------------------------------------------------
-- descarga el HTML a disco y ofrece abrirlo
--------------------------------------------------
function Content:downloadRaindropHTML(rd)
    self.ui:showProgress(_("Descargando…"))
    local data, err = self:fetch(rd)
    self.ui:hideProgress()
    if not data then
        self.ui:notify(_("Error: ") .. (err or ""))
        return
    end

    local html = data.article or data.content or ""
    local filename = string.format("raindrop_%s.html", rd._id or os.time())
    local path = DataStorage:getDownloadDir() .. "/" .. filename
    local f, ferr = io.open(path, "w")
    if not f then
        self.ui:notify(_("No se pudo guardar: ") .. tostring(ferr))
        return
    end
    f:write(html); f:close()
    self:showDownloadOptions(path, rd.title or _("Artículo"))
end

function Content:showDownloadOptions(path, title)
    UIManager:show(Menu:new{
        title      = title,
        menu_items = {
            {
                text     = _("Abrir"),
                callback = function() self:openHTMLFile(path) end,
            },
            { text = _("Cerrar") },
        },
        parent_widget = self.state,
    })
end

function Content:openHTMLFile(path)
    local file, err = io.open(path, "r")
    if not file then
        self.ui:notify(_("Error al abrir: ") .. tostring(err))
        return
    end
    local txt = file:read("*all"); file:close()
    UIManager:show(TextViewer:new{
        text  = txt,
        title = path:match("([^/]+)$"),
    })
end

return Content