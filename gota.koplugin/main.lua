--[[
    Gota: Lector para Raindrop.io en KOReader
    Permite leer artículos guardados en Raindrop.io directamente en tu dispositivo.
    
    Versión: 1.8 (Modularizado Ultra - main.lua minimalista)
    
    IMPORTANTE: SSL está desactivado para evitar problemas de certificados
    en dispositivos Kindle. Esto es necesario para que funcione correctamente.
]]

local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local logger = require("logger")
local _ = require("gettext")

-- MÓDULOS DEL PLUGIN
local Settings = require("settings")
local API = require("api")
local ContentProcessor = require("content_processor")
local GotaReader = require("gota_reader")
local UIBuilder = require("ui_builder")
local Dialogs = require("dialogs")
local ArticleManager = require("article_manager")

local Gota = WidgetContainer:extend{
    name = "gota",
    is_doc_only = false,
}

-- ========== INICIALIZACIÓN ==========

function Gota:init()
    -- Inicializar módulos core
    self.settings = Settings:new()
    self.settings:load()
    
    self.api = API:new(self.settings)
    self.content_processor = ContentProcessor:new()
    
    -- Inicializar módulos UI
    self.ui_builder = UIBuilder:new()
    self.dialogs = Dialogs:new(self)
    
    -- Inicializar gestor de artículos
    self.article_manager = ArticleManager:new(
        self.api,
        self.content_processor,
        GotaReader,
        {
            notify = function(...) self:notify(...) end,
            showProgress = function(...) self:showProgress(...) end,
            hideProgress = function(...) self:hideProgress(...) end,
        }
    )
    self.article_manager:setSettings(self.settings)
    
    -- Referencias para widgets
    self.widgets = {}
    
    self.ui.menu:registerToMainMenu(self)
end

-- ========== UTILIDADES BÁSICAS ==========

function Gota:notify(text, timeout)
    timeout = timeout or 3
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout,
    })
end

function Gota:showProgress(text)
    if self.widgets.progress then
        UIManager:close(self.widgets.progress)
    end
    self.widgets.progress = InfoMessage:new{text = text, timeout = 1}
    UIManager:show(self.widgets.progress)
    UIManager:forceRePaint()
end

function Gota:hideProgress()
    if self.widgets.progress then 
        UIManager:close(self.widgets.progress) 
        self.widgets.progress = nil
    end
end

function Gota:closeWidget(name)
    if self.widgets[name] then
        local success, err = pcall(function()
            UIManager:close(self.widgets[name])
        end)
        if success then
            self.widgets[name] = nil
        else
            logger.dbg("Gota: Error cerrando widget", name, ":", err)
            self.widgets[name] = nil
        end
    end
end

function Gota:closeAllWidgets()
    local widget_names = {"progress", "token_dialog", "collections_menu", "raindrops_menu", 
                          "article_menu", "search_dialog", "search_menu", "download_menu", 
                          "text_viewer"}
    
    for _, name in ipairs(widget_names) do
        self:closeWidget(name)
    end
    logger.dbg("Gota: Todas las ventanas cerradas")
end

-- ========== MENÚ PRINCIPAL ==========

function Gota:addToMainMenu(menu_items)
    menu_items.gota = {
        text = _("Gota (Raindrop.io)"),
        sorting_hint = "search",
        sub_item_table = {
            {
                text = _("All articles"),
                enabled_func = function() return self.settings:isTokenValid() end,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        self:showRaindrops(0, _("All articles"))
                    end)
                end,
            },
            {
                text = _("View collections"),
                enabled_func = function() return self.settings:isTokenValid() end,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        self:showCollections()
                    end)
                end,
            },
            {
                text = _("Search articles"),
                enabled_func = function() return self.settings:isTokenValid() end,
                callback = function() self:showSearchDialog() end,
            },
            {
                text = _("Advanced search"),
                enabled_func = function() return self.settings:isTokenValid() end,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        self:showAdvancedSearchDialog()
                    end)
                end,
            },
            {
                text = _("Configuration"),
                sub_item_table = {
                    {
                        text = _("Configure access token"),
                        callback = function() self:showTokenDialog() end,
                    },
                    {
                        text = _("Configure download folder"),
                        callback = function() self:showDownloadPathDialog() end,
                    },
                    {
                        text = _("Debug Raindrop API connection"),
                        callback = function() self:showDebugInfo() end,
                    },
                },
            },
        }
    }
end

-- ========== DIÁLOGOS ==========

function Gota:showTokenDialog()
    self.widgets.token_dialog = self.dialogs:showTokenDialog(
        self.settings:getToken(),
        {
            test = function(token) self:testToken(token) end,
            save = function(token)
                self.settings:setToken(token)
                return self.settings:save()
            end,
            notify = function(...) self:notify(...) end,
        }
    )
end

function Gota:showSearchDialog()
    self.widgets.search_dialog = self.dialogs:showSearchDialog(
        function(term) self:searchRaindrops(term, 0, nil) end,
        function(msg) if msg then self:notify(msg) end end
    )
end

function Gota:showAdvancedSearchDialog()
    -- Primero obtener los tags disponibles (más confiable que filters)
    self:showProgress(_("Loading filters..."))
    local tags_data, tags_err = self.api:getTags(0)
    local filters_data, filters_err = self.api:getFilters(0)
    self:hideProgress()
    
    if not tags_data and not filters_data then
        self:notify(_("Error loading filters: ") .. (tags_err or filters_err or _("Unknown error")), 4)
        return
    end
    
    -- Combinar tags de ambos endpoints
    local combined_data = filters_data or {}
    if tags_data and tags_data.items then
        combined_data.tags = tags_data.items
    end
    
    self.widgets.advanced_search_dialog = self.dialogs:showAdvancedSearchDialog(
        combined_data,
        {
            on_search = function(search_term, filters)
                self:searchRaindrops(search_term, 0, filters)
            end,
            notify = function(...) self:notify(...) end,
        }
    )
end

function Gota:showDebugInfo()
    self.dialogs:showDebugInfo(
        self.settings:getDebugInfo(),
        self.api.server_url
    )
end

function Gota:showDownloadPathDialog()
    self.dialogs:showDownloadPathDialog(
        self.settings:getDownloadPath(),
        {
            save = function(new_path)
                self.settings:setDownloadPath(new_path)
                local success = self.settings:save()
                if success then
                    self:notify(_("Download folder updated: ") .. new_path)
                else
                    self:notify(_("Error saving configuration"))
                end
                return success
            end,
            notify = function(...) self:notify(...) end,
            get_data_dir = function() return DataStorage:getDataDir() end,
        }
    )
end

-- ========== COLECCIONES ==========

function Gota:showCollections()
    self:showProgress(_("Loading collections..."))
    local collections, err = self.api:getCollections()
    self:hideProgress()
    
    if not collections then
        self:notify(_("Error retrieving collections:") .. "\n" .. (err or _("Unknown error")), 4)
        return
    end
    
    local items = self.ui_builder:buildCollectionItems(
        collections,
        function(id, title) self:showRaindrops(id, title) end
    )
    
    self:closeWidget("collections_menu")
    self.widgets.collections_menu = self.ui_builder:createMenu(_("Raindrop Collections"), items)
    UIManager:show(self.widgets.collections_menu)
end

-- ========== RAINDROPS (ARTÍCULOS) ==========

function Gota:showRaindrops(collection_id, collection_name, page)
    page = page or 0
    local perpage = 25
    
    self:showProgress(_("Loading articles..."))
    local raindrops, err = self.api:getRaindrops(collection_id, page, perpage)
    self:hideProgress()
    
    if not raindrops then
        self:notify(_("Error retrieving articles: ") .. (err or _("Unknown error")), 4)
        return
    end
    
    local items = self.ui_builder:buildRaindropItems(
        raindrops,
        function(raindrop) self:showRaindropContent(raindrop) end
    )
    
    -- Añadir paginación
    self.ui_builder:addPagination(
        items,
        raindrops,
        page,
        perpage,
        function(new_page) self:showRaindrops(collection_id, collection_name, new_page) end
    )
    
    self:closeWidget("raindrops_menu")
    self.widgets.raindrops_menu = self.ui_builder:createMenu(
        string.format("%s (%d)", collection_name or _("Articles"), raindrops.count or 0),
        items
    )
    UIManager:show(self.widgets.raindrops_menu)
end

-- ========== CONTENIDO DE ARTÍCULO ==========

function Gota:showRaindropContent(raindrop)
    -- Cargar datos completos
    local err
    raindrop, err = self.article_manager:loadFullArticle(raindrop)
    
    -- Verificar si el caché está disponible (status == "ready")
    local cache_available = raindrop.cache and raindrop.cache.status == "ready"
    
    -- Si el caché está disponible pero no tenemos el texto, intentar cargarlo
    if cache_available and not raindrop.cache.text then
        raindrop = self.article_manager:loadCacheContent(raindrop)
    end
    
    -- Ahora verificar si realmente tenemos caché válido (con texto cargado)
    local has_cache = self.article_manager:hasValidCache(raindrop)
    
    -- Construir menú con callbacks
    local items = self.ui_builder:buildArticleMenu(raindrop, has_cache, {
        open_reader = function()
            if has_cache then
                self.article_manager:openInReader(
                    raindrop,
                    function() self:closeAllWidgets() end,
                    function(rd) self:showRaindropContent(rd) end
                )
            else
                self:notify(_("Content is not available yet"))
            end
        end,
        show_text = function()
            if has_cache then
                self:showRaindropCachedContent(raindrop)
            else
                self:notify(_("Content is not available yet"))
            end
        end,
        show_info = function()
            self:showRaindropInfo(raindrop)
        end,
        show_link = function()
            self.dialogs:showLinkInfo(raindrop)
        end,
        reload = function()
            self.article_manager:reloadArticle(
                raindrop._id,
                function(rd) self:showRaindropContent(rd) end
            )
        end,
    })
    
    self:closeWidget("article_menu")
    self.widgets.article_menu = self.ui_builder:createMenu(
        raindrop.title or _("Article"),
        items
    )
    UIManager:show(self.widgets.article_menu)
end

function Gota:showRaindropInfo(raindrop)
    local content = self.content_processor:formatArticleInfo(raindrop)
    self.dialogs:showArticleInfo(raindrop, content)
end

function Gota:showRaindropCachedContent(raindrop)
    if not raindrop.cache or not raindrop.cache.text then
        self:notify(_("No cached content available"))
        return
    end
    
    local formatted_content = self.content_processor:formatArticleText(raindrop)
    
    local buttons = self.ui_builder:buildContentViewerButtons({
        close = function()
            self:closeWidget("text_viewer")
        end,
        open_reader = function()
            self:closeWidget("text_viewer")
            self.article_manager:openInReader(
                raindrop,
                function() self:closeAllWidgets() end,
                function(rd) self:showRaindropContent(rd) end
            )
        end,
        show_link = function()
            self:closeWidget("text_viewer")
            self.dialogs:showLinkInfo(raindrop)
        end,
        save_html = function()
            self:closeWidget("text_viewer")
            local filename = self.article_manager:downloadHTML(raindrop)
            if filename then
                self:showDownloadOptions(filename, raindrop.title)
            end
        end,
    })
    
    self.widgets.text_viewer = self.dialogs:showContentViewer(
        _("Cached content"),
        formatted_content,
        buttons
    )
end

-- ========== BÚSQUEDA ==========

function Gota:searchRaindrops(search_term, page, filters)
    page = page or 0
    local perpage = 25
    
    self:showProgress(_("Searching articles..."))
    local results, err = self.api:searchRaindrops(search_term, page, perpage, filters)
    self:hideProgress()
    
    if not results then
        self:notify(_("Search error: ") .. (err or _("Unknown error")), 4)
        return
    end
    
    local items = self.ui_builder:buildRaindropItems(
        results,
        function(raindrop) self:showRaindropContent(raindrop) end
    )
    
    -- Añadir paginación simple
    self.ui_builder:addSimplePagination(
        items,
        results.count or 0,
        page,
        perpage,
        function(new_page) self:searchRaindrops(search_term, new_page, filters) end
    )
    
    -- Construir título con información de filtros
    local title = _("Results: '") .. (search_term or "") .. "' (" .. (results.count or 0) .. ")"
    if filters then
        if filters.tag then
            title = title .. " [#" .. filters.tag .. "]"
        end
        if filters.type then
            title = title .. " [" .. filters.type .. "]"
        end
    end
    
    self:closeWidget("search_menu")
    self.widgets.search_menu = self.ui_builder:createMenu(
        title,
        items
    )
    UIManager:show(self.widgets.search_menu)
end

-- ========== TEST TOKEN ==========

function Gota:testToken(test_token)
    logger.dbg("Gota: Iniciando test de token, longitud:", #test_token)
    
    if not test_token or test_token == "" then
        self:notify(_("Warning: Empty token, cannot test"), 3)
        return
    end
    
    if #test_token < 10 then
        self:notify(_("Warning: Token seems very short, but it will be tested anyway"), 2)
    end
    
    self:showProgress(_("Testing token..."))
    local user_data, err = self.api:testToken(test_token)
    self:hideProgress()
    
    if user_data and user_data.user then
        logger.dbg("Gota: Test de token exitoso")
        local user_name = user_data.user.fullName or user_data.user.email or "Usuario verificado"
        local pro_status = user_data.user.pro and _(" (PRO)") or ""
        self:notify(_("Valid token!\nUser: ") .. user_name .. pro_status, 4)
    else
        logger.err("Gota: Test de token falló:", err)
        self:notify(_("Error with token:\n") .. (err or "Token inválido"), 5)
    end
end

return Gota
