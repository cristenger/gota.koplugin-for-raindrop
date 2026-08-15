--[[
    Gota: Raindrop.io reader for KOReader
    Read and manage your Raindrop.io bookmarks on e-ink devices.
    Version: 2.2.0
]]

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local logger = require("logger")
local _ = require("gettext")

local Settings = require("gota_settings")
local API = require("gota_api")
local ContentProcessor = require("gota_content_processor")
local GotaReader = require("gota_reader")
local UIBuilder = require("gota_ui_builder")
local Dialogs = require("gota_dialogs")
local ArticleManager = require("gota_article_manager")
local Version = require("gota_version")

local Gota = WidgetContainer:extend{
    name = "gota",
    is_doc_only = false,
    version = Version.version,
}

-- ========== INITIALIZATION ==========

function Gota:init()
    self:onDispatcherRegisterActions()
    self.settings = Settings:new()
    -- Lets KOReader's plugin manager offer "disable and delete settings".
    self.settings_file = self.settings:getSettingsPath()
    self.api = API:new(self.settings)
    self.content_processor = ContentProcessor:new()
    self.ui_builder = UIBuilder:new()
    self.dialogs = Dialogs:new(self)
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
    self.widgets = {}
    self.ui.menu:registerToMainMenu(self)
    logger.dbg("Gota: initialized, token:", self.settings:isTokenValid() and "valid" or "missing")
end

-- ========== DISPATCHER ACTIONS ==========

function Gota:onDispatcherRegisterActions()
    Dispatcher:registerAction("gota_show_articles", {
        category = "none",
        event = "GotaShowArticles",
        title = _("Gota: all articles"),
        general = true,
    })
    Dispatcher:registerAction("gota_search", {
        category = "none",
        event = "GotaSearch",
        title = _("Gota: search articles"),
        general = true,
    })
    Dispatcher:registerAction("gota_collections", {
        category = "none",
        event = "GotaShowCollections",
        title = _("Gota: view collections"),
        general = true,
    })
end

function Gota:onGotaShowArticles()
    if not self.settings:isTokenValid() then
        self:notify(_("Please configure your Raindrop.io token first"), 3)
        return
    end
    NetworkMgr:runWhenOnline(function()
        self:showRaindrops(0, _("All articles"))
    end)
end

function Gota:onGotaSearch()
    if not self.settings:isTokenValid() then
        self:notify(_("Please configure your Raindrop.io token first"), 3)
        return
    end
    self:showSearchDialog()
end

function Gota:onGotaShowCollections()
    if not self.settings:isTokenValid() then
        self:notify(_("Please configure your Raindrop.io token first"), 3)
        return
    end
    NetworkMgr:runWhenOnline(function()
        self:showCollections()
    end)
end

-- ========== UTILITIES ==========

function Gota:notify(text, timeout)
    timeout = timeout or 3
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout,
    })
end

-- Non-blocking toast for confirmations (less screen disruption on e-ink)
function Gota:toast(text)
    Notification:notify(text)
end

function Gota:showProgress(text)
    if self.widgets.progress then
        UIManager:close(self.widgets.progress)
    end
    self.widgets.progress = InfoMessage:new{
        text = text,
    }
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
                          "article_menu", "search_dialog", "search_menu", "advanced_search_dialog",
                          "text_viewer", "sort_dialog"}
    for _, name in ipairs(widget_names) do
        self:closeWidget(name)
    end
end

-- ========== MAIN MENU ==========

function Gota:getSubMenuItems()
    local token_valid = function()
        return self.settings and self.settings:isTokenValid()
    end

    local items = {
        {
            text = _("All articles"),
            enabled_func = token_valid,
            callback = function()
                NetworkMgr:runWhenOnline(function()
                    self:showRaindrops(0, _("All articles"))
                end)
            end,
        },
        {
            text = _("View collections"),
            enabled_func = token_valid,
            callback = function()
                NetworkMgr:runWhenOnline(function()
                    self:showCollections()
                end)
            end,
        },
        {
            text = _("Search articles"),
            enabled_func = token_valid,
            callback = function() self:showSearchDialog() end,
        },
        {
            text = _("Advanced search"),
            enabled_func = token_valid,
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
                    text_func = function()
                        local sort_labels = {
                            ["-created"] = _("newest first"),
                            ["created"]  = _("oldest first"),
                            ["title"]    = _("title A-Z"),
                            ["-title"]   = _("title Z-A"),
                            ["-sort"]    = _("custom order"),
                        }
                        local label = sort_labels[self.settings:getSortOrder()] or _("newest first")
                        return _("Sort order") .. ": " .. label
                    end,
                    callback = function() self:showSortPicker() end,
                },
                {
                    text = _("Debug Raindrop API connection"),
                    callback = function() self:showDebugInfo() end,
                },
            },
        },
    }

    if GotaReader:canReturn() then
        table.insert(items, 1, {
            text = _("< Back to Gota"),
            callback = function()
                GotaReader:onReturn()
            end,
        })
    end

    return items
end

function Gota:addToMainMenu(menu_items)
    menu_items.gota = {
        text = _("Gota"),
        sorting_hint = "more_tools",
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

-- ReaderUI emits CloseDocument before releasing the active document. Keep the
-- singleton return state in sync without coupling GotaReader to ReaderUI internals.
function Gota:onCloseDocument()
    local path = self.ui and self.ui.document and self.ui.document.file
    GotaReader:onReaderUIClose(path)
end

-- ========== DIALOGS ==========

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
    local tags_data, tags_err = self.api:getTags()
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
                local stored_path = self.settings:setDownloadPath(new_path)
                local success = self.settings:save()
                if not success then
                    self:notify(_("Error saving configuration"))
                end
                return success, nil, stored_path
            end,
            notify = function(...) self:notify(...) end,
            get_data_dir = function() return DataStorage:getDataDir() end,
        }
    )
end

-- ========== COLLECTIONS ==========

function Gota:showCollections()
    self:showProgress(_("Loading collections..."))
    local collections, err = self.api:getCollections()
    self:hideProgress()

    if not collections then
        self:notify(_("Error retrieving collections:") .. "\n" .. (err or _("Unknown error")), 4)
        return
    end

    local items = {}

    -- System collections at the top
    table.insert(items, {
        text = _("Unsorted (inbox)"),
        callback = function() self:showRaindrops(-1, _("Unsorted")) end,
    })

    -- User collections
    local collection_items = self.ui_builder:buildCollectionItems(
        collections,
        function(id, title) self:showRaindrops(id, title) end
    )
    for _, item in ipairs(collection_items) do
        table.insert(items, item)
    end

    -- Trash at the bottom
    table.insert(items, {
        text = "──────────────────",
        enabled = false,
        select_enabled = false,
    })
    table.insert(items, {
        text = _("Trash"),
        callback = function() self:showRaindrops(-99, _("Trash")) end,
    })

    -- Reload option
    table.insert(items, {
        text = "──────────────────",
        enabled = false,
        select_enabled = false,
    })
    table.insert(items, {
        text = _("Reload collections"),
        callback = function()
            self:closeWidget("collections_menu")
            self.api:clearCacheFor("/collections")
            NetworkMgr:runWhenOnline(function()
                self:showCollections()
            end)
        end,
    })

    self:closeWidget("collections_menu")
    self.widgets.collections_menu = self.ui_builder:createMenu(_("Raindrop Collections"), items)
    UIManager:show(self.widgets.collections_menu)
end

-- ========== RAINDROPS (ARTICLES) ==========

function Gota:showRaindrops(collection_id, collection_name, page)
    page = page or 0
    local perpage = 25
    local sort = self.settings:getSortOrder()

    self:showProgress(_("Loading articles..."))
    local raindrops, err = self.api:getRaindrops(collection_id, page, perpage, sort)
    self:hideProgress()

    if not raindrops then
        self:notify(_("Error retrieving articles: ") .. (err or _("Unknown error")), 4)
        return
    end

    local items = self.ui_builder:buildRaindropItems(
        raindrops,
        function(raindrop) self:showRaindropContent(raindrop) end,
        -- Hold callback: quick info popup (no API calls, data already in list item)
        function(raindrop)
            local info = (raindrop.title or _("Untitled")) .. "\n\n"
            info = info .. (raindrop.domain or "") .. "\n"
            info = info .. (_("Type") .. ": " .. (raindrop.type or "link")) .. "\n"
            if raindrop.tags and #raindrop.tags > 0 then
                info = info .. (_("Tags") .. ": " .. table.concat(raindrop.tags, ", ")) .. "\n"
            end
            if raindrop.cache then
                info = info .. (_("Cache") .. ": " .. (raindrop.cache.status or "unknown"))
            end
            self:notify(info, 5)
        end
    )

    -- Pagination
    self.ui_builder:addPagination(
        items,
        raindrops,
        page,
        perpage,
        function(new_page) self:showRaindrops(collection_id, collection_name, new_page) end
    )

    -- Reload option at the bottom
    table.insert(items, {
        text = _("Reload"),
        callback = function()
            self:closeWidget("raindrops_menu")
            self.api:clearCacheFor("/raindrops/" .. tostring(collection_id))
            NetworkMgr:runWhenOnline(function()
                self:showRaindrops(collection_id, collection_name, page)
            end)
        end,
    })

    self:closeWidget("raindrops_menu")
    self.widgets.raindrops_menu = self.ui_builder:createMenu(
        string.format("%s (%d)", collection_name or _("Articles"), raindrops.count or 0),
        items
    )
    UIManager:show(self.widgets.raindrops_menu)
end

-- ========== SORT PICKER ==========

function Gota:showSortPicker()
    local ButtonDialog = require("ui/widget/buttondialog")
    local current = self.settings:getSortOrder()

    local function makeSortButton(label, value)
        local display = label
        if value == current then
            display = display .. " *"
        end
        return {
            text = display,
            callback = function()
                UIManager:close(self.widgets.sort_dialog)
                self.widgets.sort_dialog = nil
                self.settings:setSortOrder(value)
                self.settings:save()
                self:toast(_("Sort order: ") .. label)
            end,
        }
    end

    self.widgets.sort_dialog = ButtonDialog:new{
        title = _("Sort articles by"),
        title_align = "center",
        buttons = {
            { makeSortButton(_("Newest first"), "-created") },
            { makeSortButton(_("Oldest first"), "created") },
            { makeSortButton(_("Title A-Z"), "title") },
            { makeSortButton(_("Title Z-A"), "-title") },
            { makeSortButton(_("Custom order"), "-sort") },
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(self.widgets.sort_dialog)
                        self.widgets.sort_dialog = nil
                    end,
                },
            },
        },
    }
    UIManager:show(self.widgets.sort_dialog)
end

-- ========== ARTICLE CONTENT ==========

function Gota:showRaindropContent(raindrop)
    if not raindrop then
        self:notify(_("Error loading article: ") .. _("Unknown error"), 4)
        return
    end

    -- Cargar datos completos
    local err
    raindrop, err = self.article_manager:loadFullArticle(raindrop)

    if not raindrop then
        self:notify(_("Error loading article: ") .. (err or _("Unknown error")), 4)
        return
    end
    
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
        show_notes = function()
            self:showRaindropNotes(raindrop)
        end,
        show_highlights = function()
            self:showRaindropHighlights(raindrop)
        end,
        save_html_with_notes = function()
            local filename = self.article_manager:downloadHTMLWithNotes(raindrop)
            if filename then
                self:closeAllWidgets()
                -- Extraer el directorio del archivo
                local directory = filename:match("(.*/)")
                if directory then
                    -- Abrir FileManager mostrando el directorio de descarga
                    UIManager:nextTick(function()
                        local FileManager = require("apps/filemanager/filemanager")
                        if FileManager.instance then
                            FileManager.instance:reinit(directory)
                        else
                            FileManager:showFiles(directory)
                        end
                    end)
                end
            end
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

function Gota:showRaindropNotes(raindrop)
    local content = self.content_processor:formatNotes(raindrop)
    self.dialogs:showArticleInfo(raindrop, content)
end

function Gota:showRaindropHighlights(raindrop)
    local content = self.content_processor:formatHighlights(raindrop)
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
            local filename = self.article_manager:downloadHTML(raindrop)
            if filename then
                self:closeWidget("text_viewer")
                local display_name = filename:match("([^/]+)$") or filename
                self:toast(_("Article saved: ") .. display_name)
            end
        end,
        save_html_with_notes = function()
            local filename = self.article_manager:downloadHTMLWithNotes(raindrop)
            if filename then
                self:closeAllWidgets()
                -- Extraer el directorio del archivo
                local directory = filename:match("(.*/)")
                if directory then
                    -- Abrir FileManager mostrando el directorio de descarga
                    UIManager:nextTick(function()
                        local FileManager = require("apps/filemanager/filemanager")
                        if FileManager.instance then
                            FileManager.instance:reinit(directory)
                        else
                            FileManager:showFiles(directory)
                        end
                    end)
                end
            end
        end,
    }, raindrop)
    
    self.widgets.text_viewer = self.dialogs:showContentViewer(
        _("Cached content"),
        formatted_content,
        buttons
    )
end

-- ========== SEARCH ==========

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
        function(raindrop) self:showRaindropContent(raindrop) end,
        -- Hold callback: quick info (same as showRaindrops)
        function(raindrop)
            local info = (raindrop.title or _("Untitled")) .. "\n\n"
            info = info .. (raindrop.domain or "") .. "\n"
            info = info .. (_("Type") .. ": " .. (raindrop.type or "link")) .. "\n"
            if raindrop.tags and #raindrop.tags > 0 then
                info = info .. (_("Tags") .. ": " .. table.concat(raindrop.tags, ", ")) .. "\n"
            end
            self:notify(info, 5)
        end
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

-- ========== TOKEN TEST ==========

function Gota:testToken(test_token)
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
        local user_name = user_data.user.fullName or user_data.user.email or _("Verified user")
        local pro_status = user_data.user.pro and _(" (PRO)") or ""
        self:notify(_("Valid token!\nUser: ") .. user_name .. pro_status, 4)
    else
        self:notify(_("Error with token:\n") .. (err or _("Invalid token")), 5)
    end
end

return Gota
