--[[
    Gota: Raindrop.io reader for KOReader
    Read and manage your Raindrop.io bookmarks on e-ink devices.
    Version: 2.3.0
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
    self.collapsed_collection_groups = {}
    local active_path = self.ui and self.ui.document and self.ui.document.file
    local removed_count, cleanup_warnings =
        self.article_manager:cleanupOrphanReaderFiles(active_path)
    if removed_count > 0 then
        logger.dbg("Gota: removed orphan reader cache files:", removed_count)
    end
    for _, warning in ipairs(cleanup_warnings) do
        logger.warn("Gota: reader cache cleanup warning:", warning)
    end
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
    local widget_names = {"progress", "token_dialog", "collections_menu", "collection_actions_menu", "raindrops_menu",
                          "article_menu", "search_dialog", "search_menu", "advanced_search_dialog",
                          "text_viewer", "sort_dialog", "highlights_menu", "highlight_actions_menu",
                          "collection_picker", "remove_token_dialog"}
    for _, name in ipairs(widget_names) do
        self:closeWidget(name)
    end
end

-- ========== MAIN MENU ==========

function Gota:getSubMenuItems()
    local token_valid = function()
        return self.settings and self.settings:isTokenValid()
    end

    local configuration_items = {
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
                    ["domain"]   = _("domain A-Z"),
                    ["-domain"]  = _("domain Z-A"),
                }
                local label = sort_labels[self.settings:getSortOrder()] or _("newest first")
                return _("Sort order") .. ": " .. label
            end,
            callback = function() self:showSortPicker() end,
        },
        {
            text_func = function()
                return string.format(_("Cache limits: %d MiB text / %d MiB reader"),
                    self.settings:getMaxCacheMemoryBytes() / 1048576,
                    self.settings:getMaxCacheFileBytes() / 1048576)
            end,
            callback = function() self:showCacheLimitPicker() end,
        },
        {
            text = _("Debug Raindrop API connection"),
            callback = function() self:showDebugInfo() end,
        },
    }
    if token_valid() then
        table.insert(configuration_items, 2, {
            text = _("Remove access token"),
            callback = function() self:confirmRemoveToken() end,
        })
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
            text = _("All highlights"),
            enabled_func = token_valid,
            callback = function()
                NetworkMgr:runWhenOnline(function() self:showHighlights(nil, _("All highlights"), 0) end)
            end,
        },
        {
            text = _("Configuration"),
            sub_item_table = configuration_items,
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
    if self.article_manager and self.article_manager:isManagedReaderPath(path) then
        UIManager:nextTick(function()
            local cleaned, cleanup_error = self.article_manager:cleanupManagedReaderPath(path)
            if not cleaned then
                logger.warn("Gota: could not clean closed reader document:", cleanup_error)
            end
        end)
    end
end

-- ========== DIALOGS ==========

function Gota:showTokenDialog()
    self.widgets.token_dialog = self.dialogs:showTokenDialog(
        self.settings:getToken(),
        {
            test = function(token) self:testToken(token) end,
            save = function(token)
                local previous_token = self.settings:getToken()
                self.settings:setToken(token)
                local saved, save_error = self.settings:save()
                if not saved then self.settings:setToken(previous_token) end
                return saved, save_error
            end,
            notify = function(...) self:notify(...) end,
        }
    )
end

function Gota:confirmRemoveToken()
    self.widgets.remove_token_dialog = self.dialogs:confirmRemoveToken(function()
        self.widgets.remove_token_dialog = nil
        local removed, remove_error = self.settings:clearToken()
        if not removed then
            self:notify(_("Could not remove the local access token: ") ..
                (remove_error or _("Unknown error")), 4)
            return
        end
        self.api:clearCache()
        self:closeAllWidgets()
        self:notify(_("Local access token removed"), 3)
    end)
end

function Gota:showSearchDialog(context)
    self.widgets.search_dialog = self.dialogs:showSearchDialog(
        function(term) self:searchRaindrops(term, 0, nil, context) end,
        function(msg) if msg then self:notify(msg) end end
    )
end

function Gota:showAdvancedSearchDialog(context)
    context = context or {}
    self:showProgress(_("Loading filters..."))
    local filters_data, filters_err = self.api:getFilters(context.collection_id or 0, nil, nil,
        { tags_sort = "-count" })
    self:hideProgress()

    if not filters_data then
        self:notify(_("Error loading filters: ") .. (filters_err or _("Unknown error")), 4)
        return
    end

    self.widgets.advanced_search_dialog = self.dialogs:showAdvancedSearchDialog(
        filters_data,
        {
            on_search = function(search_term, filters)
                self:searchRaindrops(search_term, 0, filters, context)
            end,
            notify = function(...) self:notify(...) end,
        }
    )
end

function Gota:showCacheLimitPicker()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local function presetButton(kind, mib)
        local current = kind == "memory" and self.settings:getMaxCacheMemoryBytes()
            or self.settings:getMaxCacheFileBytes()
        return {
            text = string.format("%s: %d MiB%s", kind == "memory" and _("Text") or _("Reader"),
                mib, current == mib * 1048576 and " *" or ""),
            callback = function()
                if kind == "memory" then self.settings:setMaxCacheMemoryBytes(mib * 1048576)
                else self.settings:setMaxCacheFileBytes(mib * 1048576) end
                self.settings:save()
                UIManager:close(dialog)
                self:showCacheLimitPicker()
            end,
        }
    end
    dialog = ButtonDialog:new{
        title = _("Cache size limits") .. "\n" ..
            _("Text uses the smaller RAM limit; direct reader downloads use the larger file limit."),
        buttons = {
            { presetButton("memory", 2), presetButton("memory", 4) },
            { presetButton("memory", 8), presetButton("memory", 16) },
            { presetButton("file", 16), presetButton("file", 32) },
            { presetButton("file", 64), presetButton("file", 128) },
            {{ text = _("Close"), id = "close", callback = function() UIManager:close(dialog) end }},
        },
    }
    UIManager:show(dialog)
end

function Gota:showDebugInfo()
    self.dialogs:showDebugInfo(
        self.settings:getDebugInfo(),
        self.api.server_url,
        self.api:getTransportSecurityInfo()
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
    local structure, err = self.api:getCollectionStructure()
    local stats = structure and self.api:getUserStats() or nil
    self:hideProgress()

    if not structure then
        self:notify(_("Error retrieving collections:") .. "\n" .. (err or _("Unknown error")), 4)
        return
    end

    self:renderCollections(structure, stats)
end

function Gota:renderCollections(structure, stats)
    local items, stats_by_id = {}, {}
    for _, item in ipairs(stats and stats.items or {}) do
        if item._id ~= nil then stats_by_id[tostring(item._id)] = tonumber(item.count) end
    end
    local function systemText(label, id)
        local count = stats_by_id[tostring(id)]
        return count and string.format("%s (%d)", label, count) or label
    end

    table.insert(items, {
        text = systemText(_("All articles"), 0),
        callback = function() self:showRaindrops(0, _("All articles")) end,
    })
    table.insert(items, {
        text = systemText(_("Unsorted (inbox)"), -1),
        callback = function() self:showRaindrops(-1, _("Unsorted")) end,
    })

    -- User collections
    local collection_items = self.ui_builder:buildCollectionItems(
        structure,
        function(id, title) self:showCollectionActions(id, title) end,
        {
            collapsed_groups = self.collapsed_collection_groups,
            on_toggle_group = function(key, collapsed)
                self.collapsed_collection_groups[key] = collapsed
                self:renderCollections(structure, stats)
            end,
        }
    )
    for _, item in ipairs(collection_items) do
        table.insert(items, item)
    end

    local meta = stats and stats.meta or nil
    for _, statistic in ipairs({
        { key = "broken", label = _("Broken links") },
        { key = "duplicates", label = _("Duplicate links") },
    }) do
        local raw_value = meta and meta[statistic.key] or nil
        local value = type(raw_value) == "table" and tonumber(raw_value.count)
            or tonumber(raw_value)
        if value then
            items[#items + 1] = {
                text = string.format("%s: %d", statistic.label, value),
                enabled = false,
                select_enabled = false,
            }
        end
    end

    -- Trash at the bottom
    table.insert(items, {
        text = "──────────────────",
        enabled = false,
        select_enabled = false,
    })
    table.insert(items, {
        text = systemText(_("Trash"), -99),
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
            self.api:clearCacheFor("/user")
            NetworkMgr:runWhenOnline(function()
                self:showCollections()
            end)
        end,
    })

    self:closeWidget("collections_menu")
    self.widgets.collections_menu = self.ui_builder:createMenu(_("Raindrop Collections"), items)
    UIManager:show(self.widgets.collections_menu)
    if structure.warnings and #structure.warnings > 0 and not structure._warnings_shown then
        structure._warnings_shown = true
        self:notify(_("Some collection information could not be loaded."), 4)
    end
end

function Gota:showCollectionActions(collection_id, collection_name)
    local items = {
        { text = _("View articles"), callback = function()
            self:showRaindrops(collection_id, collection_name)
        end },
        { text = _("Search this collection"), callback = function()
            self:showSearchDialog({ collection_id = collection_id, collection_name = collection_name })
        end },
        { text = _("Search this collection and subcollections"), callback = function()
            self:showSearchDialog({ collection_id = collection_id, collection_name = collection_name, nested = true })
        end },
        { text = _("Advanced search"), callback = function()
            NetworkMgr:runWhenOnline(function()
                self:showAdvancedSearchDialog({ collection_id = collection_id, collection_name = collection_name })
            end)
        end },
        { text = _("Highlights in this collection"), callback = function()
            NetworkMgr:runWhenOnline(function() self:showHighlights(collection_id, collection_name, 0) end)
        end },
    }
    self:closeWidget("collection_actions_menu")
    self.widgets.collection_actions_menu = self.ui_builder:createMenu(collection_name, items)
    UIManager:show(self.widgets.collection_actions_menu)
end

-- ========== RAINDROPS (ARTICLES) ==========

function Gota:formatRaindropQuickInfo(raindrop)
    local info = (raindrop.title or _("Untitled")) .. "\n\n"
    info = info .. (raindrop.domain or "") .. "\n"
    info = info .. (_("Type") .. ": " .. (raindrop.type or "link")) .. "\n"
    if raindrop.tags and #raindrop.tags > 0 then
        info = info .. (_("Tags") .. ": " .. table.concat(raindrop.tags, ", ")) .. "\n"
    end
    if raindrop.broken then info = info .. _("Broken link") .. "\n" end
    if raindrop.important then info = info .. _("Favorite") .. "\n" end
    if raindrop.reminder and raindrop.reminder.data then
        info = info .. (_("Reminder") .. ": " .. tostring(raindrop.reminder.data)) .. "\n"
    end
    if raindrop.file and raindrop.file.name then
        info = info .. (_("File") .. ": " .. tostring(raindrop.file.name)) .. "\n"
    end
    if raindrop.cache then
        info = info .. (_("Cache") .. ": " .. (raindrop.cache.status or "unknown"))
    end
    return info
end

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
            self:notify(self:formatRaindropQuickInfo(raindrop), 5)
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
    local menu_title = collection_name or _("Articles")
    if raindrops.count ~= nil then menu_title = string.format("%s (%d)", menu_title, raindrops.count) end
    self.widgets.raindrops_menu = self.ui_builder:createMenu(menu_title, items)
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
            { makeSortButton(_("Domain A-Z"), "domain") },
            { makeSortButton(_("Domain Z-A"), "-domain") },
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
    
    local cache_available = raindrop.cache and raindrop.cache.status == "ready"
    
    -- Construir menú con callbacks
    local current_collection_id = raindrop.collection and raindrop.collection["$id"]
    local in_trash = tonumber(current_collection_id) == -99
    local items = self.ui_builder:buildArticleMenu(raindrop, cache_available, {
        open_reader = function()
            if cache_available then
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
            local loaded = self.article_manager:loadCacheContent(raindrop)
            if self.article_manager:hasValidCache(loaded) then self:showRaindropCachedContent(loaded)
            else self:notify(_("Content exceeds the text limit or is unavailable")) end
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
        in_trash = in_trash,
        toggle_favorite = function()
            NetworkMgr:runWhenOnline(function()
                self:updateCurrentRaindrop(raindrop, { important = not raindrop.important },
                    _("Favorite updated"))
            end)
        end,
        edit_note = function() self:editRaindropNote(raindrop) end,
        edit_tags = function() self:editRaindropTags(raindrop) end,
        move_collection = function() self:chooseRaindropCollection(raindrop) end,
        move_to_trash = function() self:confirmTrashRaindrop(raindrop, current_collection_id) end,
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

function Gota:searchRaindrops(search_term, page, filters, context)
    page = page or 0
    local perpage = 25
    context = context or {}
    
    self:showProgress(_("Searching articles..."))
    local results, err = self.api:searchRaindrops(search_term, page, perpage, filters, nil, {
        collection_id = context.collection_id or 0,
        nested = context.nested == true,
    })
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
            self:notify(self:formatRaindropQuickInfo(raindrop), 5)
        end
    )
    
    -- Añadir paginación simple
    self.ui_builder:addPagination(
        items,
        results,
        page,
        perpage,
        function(new_page) self:searchRaindrops(search_term, new_page, filters, context) end
    )
    
    -- Construir título con información de filtros
    local title = _("Results: '") .. (search_term or "") .. "'"
    if results.count ~= nil then title = title .. " (" .. results.count .. ")" end
    if context.collection_name then
        title = title .. " — " .. context.collection_name .. (context.nested and " + " .. _("subcollections") or "")
    end
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

-- ========== GLOBAL HIGHLIGHTS ==========

function Gota:showHighlights(collection_id, collection_name, page)
    page = page or 0
    local perpage = 25
    self:showProgress(_("Loading highlights..."))
    local response, err = self.api:getHighlights(collection_id, page, perpage)
    self:hideProgress()
    if not response then
        self:notify(_("Error loading highlights: ") .. (err or _("Unknown error")), 4)
        return
    end
    local items = self.ui_builder:buildHighlightItems(response, function(highlight)
        self:showHighlightActions(highlight)
    end)
    self.ui_builder:addPagination(items, response, page, perpage, function(new_page)
        self:showHighlights(collection_id, collection_name, new_page)
    end)
    self:closeWidget("highlights_menu")
    self.widgets.highlights_menu = self.ui_builder:createMenu(
        collection_id and (_("Highlights") .. " — " .. tostring(collection_name)) or _("All highlights"), items)
    UIManager:show(self.widgets.highlights_menu)
end

function Gota:showHighlightActions(highlight)
    local reference = type(highlight.raindropRef) == "table" and highlight.raindropRef or nil
    local items = {{
        text = _("View highlight details"),
        callback = function()
            self.dialogs:showArticleInfo({ title = highlight.title or _("Highlight") },
                self.content_processor:formatHighlightInfo(highlight))
        end,
    }}
    if reference and reference._id then
        items[#items + 1] = {
            text = _("Open related article"),
            callback = function() self:showRaindropContent(reference) end,
        }
    end
    self:closeWidget("highlight_actions_menu")
    self.widgets.highlight_actions_menu = self.ui_builder:createMenu(
        highlight.title or _("Highlight"), items)
    UIManager:show(self.widgets.highlight_actions_menu)
end

-- ========== REVERSIBLE BOOKMARK EDITING ==========

function Gota:updateCurrentRaindrop(raindrop, patch, success_message, dialog_to_close)
    self:showProgress(_("Updating bookmark..."))
    local response, err = self.api:updateRaindrop(raindrop._id, patch)
    self:hideProgress()
    if not response then
        self:notify(_("Could not update bookmark: ") .. (err or _("Unknown error")), 4)
        return false
    end
    if dialog_to_close then UIManager:close(dialog_to_close) end
    self:toast(success_message or _("Bookmark updated"))
    self:showRaindropContent(self.article_manager:adoptFullArticle(response.item))
    return true
end

function Gota:editRaindropNote(raindrop)
    self.dialogs:showEditNoteDialog(raindrop.note, {
        notify = function(...) self:notify(...) end,
        save = function(note, dialog)
            NetworkMgr:runWhenOnline(function()
                self:updateCurrentRaindrop(raindrop, { note = note }, _("Note updated"), dialog)
            end)
        end,
    })
end

function Gota:editRaindropTags(raindrop)
    self.dialogs:showEditTagsDialog(raindrop.tags, {
        save = function(tags, dialog)
            NetworkMgr:runWhenOnline(function()
                self:updateCurrentRaindrop(raindrop, { tags = tags }, _("Tags updated"), dialog)
            end)
        end,
    })
end

function Gota:chooseRaindropCollection(raindrop)
    self:showProgress(_("Loading collections..."))
    local structure, err = self.api:getCollectionStructure()
    self:hideProgress()
    if not structure then
        self:notify(_("Error retrieving collections:") .. "\n" .. (err or _("Unknown error")), 4)
        return
    end
    local items = {{
        text = _("Unsorted (inbox)"),
        callback = function()
            NetworkMgr:runWhenOnline(function()
                self:updateCurrentRaindrop(raindrop, { collection = { ["$id"] = -1 } },
                    _("Bookmark moved"), self.widgets.collection_picker)
            end)
        end,
    }}
    local collection_items = self.ui_builder:buildCollectionItems(structure, function(id)
        NetworkMgr:runWhenOnline(function()
            self:updateCurrentRaindrop(raindrop, { collection = { ["$id"] = id } },
                _("Bookmark moved"), self.widgets.collection_picker)
        end)
    end, { collapsed_groups = {}, expand_all_groups = true })
    for _, item in ipairs(collection_items) do items[#items + 1] = item end
    self:closeWidget("collection_picker")
    self.widgets.collection_picker = self.ui_builder:createMenu(_("Move to collection"), items)
    UIManager:show(self.widgets.collection_picker)
end

function Gota:confirmTrashRaindrop(raindrop, context_collection_id)
    local item_collection_id = raindrop.collection and raindrop.collection["$id"]
    if tonumber(context_collection_id) == -99 or tonumber(item_collection_id) == -99 then
        self:notify(_("This item is already in Trash; permanent deletion is not supported."), 4)
        return
    end
    self.dialogs:confirmMoveToTrash(raindrop.title, function()
        NetworkMgr:runWhenOnline(function()
            self:showProgress(_("Moving bookmark to Trash..."))
            local response, err = self.api:trashRaindrop(raindrop._id,
                item_collection_id or context_collection_id)
            self:hideProgress()
            if response then
                self:toast(_("Bookmark moved to Trash"))
                self:closeWidget("article_menu")
            else
                self:notify(_("Could not move bookmark to Trash: ") .. (err or _("Unknown error")), 4)
            end
        end)
    end)
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
