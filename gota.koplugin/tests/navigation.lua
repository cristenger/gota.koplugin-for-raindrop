return function(test, equal, truthy, contains)
    local Gota = require("main")
    local Raindrop = dofile("gota_raindrop.lua")
    local UIBuilder = dofile("gota_ui_builder.lua")

    test("documented numeric highlight references open their bookmark", function()
        local opened, items
        local fake = {
            widgets = {}, closeWidget = function() end,
            ui_builder = {createMenu=function(_, _, rows) items=rows;return {} end},
            showRaindropContent = function(_, reference) opened=reference end,
        }
        Gota.showHighlightActions(fake, {title="Documented response", raindropRef=123}, {})
        equal(#items, 2, "related article action")
        items[2].callback()
        equal(opened._id, 123, "numeric related bookmark")
        local builder = UIBuilder:new()
        local rows = builder:buildHighlightItems({items={{text="Quote", raindropRef=123}}}, function() end)
        equal(rows[1].gota_raindrop_id, "123", "focus identity")
        equal(Raindrop.highlightReference({raindropRef=-1}), nil, "invalid reference rejected")
        equal(Raindrop.highlightReference({raindropRef="nan"}), nil, "malformed reference rejected")
    end)

    test("search subtitle and request share the effective sort", function()
        local requested, subtitle
        local fake = setmetatable({
            widgets={}, showProgress=function() end, hideProgress=function() end, closeWidget=function() end,
            settings={getSortOrder=function() return "title" end},
            api={searchRaindrops=function(_, _, _, _, _, _, options)
                requested=options;return {items={}}
            end},
            ui_builder={buildRaindropItems=function() return {} end,
                addPagination=function() return "page 1" end,
                buildActiveFilterSummary=UIBuilder.buildActiveFilterSummary,
                createMenu=function(_, _, _, options) subtitle=options.subtitle; return {} end},
        }, {__index=Gota})
        fake:searchRaindrops("word", 0, nil, {filter_summary="obsolete sort"})
        equal(requested.sort, "score", "text uses relevance")
        contains(subtitle, "Sort: relevance", "subtitle shows relevance")
        fake:searchRaindrops("", 0, {tag="tag"})
        equal(requested.sort, "title", "filters use selected order")
        contains(subtitle, "Sort: title A-Z", "subtitle shows actual selected order")
    end)

    test("account reset clears the rate-limit cooldown", function()
        local cleared = false
        local fake = { widgets = {}, closeWidget = function() end,
            settings = { getSessionGeneration = function() return 1 end },
            api = { clearCache = function() end, clearRateLimit = function() cleared = true end } }
        Gota.resetAuthenticatedNavigation(fake)
        equal(cleared, true, "new account starts without the old cooldown")
    end)

    test("saved library opens and returns without account or network calls", function()
        local items, opened, reloaded= nil, nil, 0
        local fake = setmetatable({widgets={}, closeWidget=function() end, closeAllWidgets=function() end,
            article_manager={listOfflineCopies=function()
                return {{path="/tmp/saved.html", title="Saved title", percent=42, annotated=false}}
            end, openSavedFile=function(_, path, options) opened={path=path,options=options}; return true end},
            ui_builder={createMenu=function(_, _, rows) items=rows; return {} end},
            showOfflineLibrary=function() reloaded=reloaded+1 end,
        }, {__index=Gota})
        Gota.showOfflineLibrary(fake)
        contains(items[1].text, "42%", "reading progress")
        items[1].callback()
        equal(opened.path, "/tmp/saved.html", "local file opened")
        truthy(opened.options.normalize_styles, "original presentation")
        equal(opened.options.return_target.view, "offline_library", "local library returns")
        equal(opened.options.on_return_callback, nil, "no closure over this instance")
    end)

    test("callbacks capturing an old account are rejected before touching its article", function()
        local generation, executed, reset, notice = 1, 0, 0
        local fake = {settings={getSessionGeneration=function() return generation end},
            resetAuthenticatedNavigation=function() reset=reset+1 end,
            notify=function(_, text) notice=text end}
        local callback = Gota.networkCallback(fake, function() executed=executed+1 end)
        generation=2
        callback()
        equal(executed, 0, "old action rejected")
        equal(reset, 1, "navigation reset")
        contains(notice, "account changed", "session explanation")
    end)

    test("saving a changed token clears account state after persistence succeeds", function()
        local current, generation, reset="first",1,0
        local callbacks
        local fake = {widgets={},
            settings={getToken=function() return current end,
                setToken=function(_, token) current=token;generation=generation+1 end,
                save=function() return true end},
            dialogs={showTokenDialog=function(_, _, value) callbacks=value; return {} end},
            resetAuthenticatedNavigation=function() reset=reset+1 end,
            notify=function() end,
        }
        Gota.showTokenDialog(fake)
        truthy(callbacks.save("second"), "token saved")
        equal(reset, 1, "authenticated state reset")
        equal(current, "second", "new token")
    end)

    test("old article and highlight rows stay rejected after another entry resets navigation", function()
        local generation, executed, notices = 1, 0, {}
        local captured_rows
        local article = { _id=123, title="Previous account article", type="article" }
        local highlight = { text="Previous account quote", title="Old article", raindropRef=123 }
        local builder = UIBuilder:new()
        builder.createMenu = function(_, _, rows) captured_rows=rows; return {} end
        local fake = setmetatable({
            widgets={}, session_generation=1,
            settings={getSessionGeneration=function() return generation end,
                getSortOrder=function() return "title" end},
            api={getRaindrops=function() return {items={article},count=1} end,
                searchRaindrops=function() return {items={article},count=1} end,
                getHighlights=function() return {items={highlight},count=1} end,
                clearCache=function() end},
            ui_builder=builder,
            showProgress=function() end, hideProgress=function() end, closeWidget=function() end,
            showRaindropContent=function() executed=executed+1 end,
            showHighlightActions=function() executed=executed+1 end,
            formatRaindropQuickInfo=function() executed=executed+1; return "old data" end,
            dialogs={showArticleInfo=function() executed=executed+1 end},
            content_processor={formatHighlightInfo=function() executed=executed+1; return "old data" end},
            notify=function(_, message) notices[#notices+1]=message end,
        }, {__index=Gota})
        local retained = {}
        Gota.showRaindrops(fake, 0, "Previous account list", 0)
        retained[#retained+1] = captured_rows[1].callback
        retained[#retained+1] = captured_rows[1].hold_callback
        Gota.searchRaindrops(fake, "previous account query", 0)
        retained[#retained+1] = captured_rows[1].callback
        retained[#retained+1] = captured_rows[1].hold_callback
        Gota.showHighlights(fake, nil, "Previous account highlights", 0)
        retained[#retained+1] = captured_rows[1].callback
        Gota.showHighlightActions(fake, highlight, {})
        retained[#retained+1] = captured_rows[1].callback
        retained[#retained+1] = captured_rows[2].callback

        generation=2
        -- Another entry point already reset this instance. Comparing only
        -- self.session_generation at tap time would now accept these old rows.
        Gota.resetAuthenticatedNavigation(fake)
        equal(fake.session_generation, 2, "instance already belongs to the new account")
        for _, callback in ipairs(retained) do callback() end
        equal(executed, 0, "no stale article quote or quick-info data used")
        equal(#notices, 7, "each captured action rejects its old generation")
        contains(notices[1], "account changed", "session explanation")
    end)

    local function sessionFixture()
        local state = { generation=1, executed=0, rows=nil }
        state.article = { _id=123, title="Old article", type="article", collection={ ["$id"]=44 } }
        state.structure = { roots={{_id=44,title="Old destination"}}, groups={}, children={} }
        local builder = UIBuilder:new()
        builder.createMenu = function(_, _, rows) state.rows=rows; return {} end
        builder.buildArticleMenu = function(_, _, _, callbacks) state.article_callbacks=callbacks; return {} end
        state.fake = setmetatable({
            widgets={}, session_generation=1, collapsed_collection_groups={},
            settings={getSessionGeneration=function() return state.generation end,
                getSortOrder=function() return "title" end},
            api={getCollectionStructure=function() return state.structure end,
                getRaindrops=function() return {items={state.article},count=100} end,
                searchRaindrops=function() return {items={state.article},count=100} end,
                getHighlights=function() return {items={{text="Quote",raindropRef=123}},count=100} end,
                getFilters=function() return {tags={},types={}} end,
                clearCache=function() end,
                clearCacheFor=function() state.executed=state.executed+1 end,
                trashRaindrop=function() state.executed=state.executed+1; return {result=true} end},
            article_manager={loadFullArticle=function(_, article) return article end,
                getOfflineState=function() return nil end},
            ui_builder=builder,
            dialogs={confirmMoveToTrash=function(_, _, callback) state.confirm=callback end,
                showEditNoteDialog=function(_, _, callbacks) state.note=callbacks end,
                showEditTagsDialog=function(_, _, callbacks) state.tags=callbacks end,
                showSearchDialog=function(_, callback) state.search=callback end,
                showAdvancedSearchDialog=function(_, _, _, callbacks) state.advanced=callbacks end},
            showProgress=function() end, hideProgress=function() end, closeWidget=function() end,
            notify=function() end,
            updateCurrentRaindrop=function() state.executed=state.executed+1 end,
            showRaindrops=function() state.executed=state.executed+1 end,
            searchRaindrops=function() state.executed=state.executed+1 end,
            showHighlights=function() state.executed=state.executed+1 end,
            showCollectionActions=function() state.executed=state.executed+1 end,
            showRaindropContent=function() state.executed=state.executed+1 end,
            showHighlightActions=function() state.executed=state.executed+1 end,
        }, {__index=Gota})
        return state
    end

    test("an emptied last page recovers the last page that still has items", function()
        equal(Raindrop.recoverEmptyPage({ items = {}, count = 25 }, 1, 25), 0, "back to page 1")
        equal(Raindrop.recoverEmptyPage({ items = {}, count = 60 }, 4, 25), 2, "last valid page")
        equal(Raindrop.recoverEmptyPage({ items = {}, count = 0 }, 2, 25), 0, "everything gone")
        equal(Raindrop.recoverEmptyPage({ items = { {} }, count = 26 }, 1, 25), nil, "page still has items")
        equal(Raindrop.recoverEmptyPage({ items = {}, count = 25 }, 0, 25), nil, "first page stays")
        equal(Raindrop.recoverEmptyPage({ items = {} }, 3, 25), nil, "unknown total is not guessed")
    end)

    test("moving the last item of the last page lands on the previous valid page", function()
        local state = sessionFixture()
        local pages = {}
        state.fake.showRaindrops = Gota.showRaindrops
        state.fake.api.getRaindrops = function(_, _, page)
            pages[#pages + 1] = page
            if page == 1 then return { items = {}, count = 25 } end
            return { items = { state.article }, count = 25 }
        end
        state.fake.api.clearCacheFor = function() end
        Gota.showRaindrops(state.fake, 44, "Inbox", 1, 123)
        equal(table.concat(pages, ","), "1,0", "reloaded the last valid page")
    end)

    test("subtitle never shows an inverted range", function()
        local _, subtitle = UIBuilder:new():buildRemotePagination({ items = {}, count = 25 }, 1, 25, function() end)
        local first, last = subtitle:match("(%d+)–(%d+)")
        truthy(first and tonumber(first) <= tonumber(last), "range in order: " .. tostring(subtitle))
    end)

    test("list builders label missing titles and notes without crashing", function()
        local builder = UIBuilder:new()
        local ok, rows = pcall(builder.buildHighlightItems, builder,
            { items = { { note = "A thought", raindropRef = 7 } } }, function() end)
        truthy(ok, "highlight with a note and no text: " .. tostring(rows))
        contains(ok and rows[1].text or "", "Highlight without text", "missing text labelled")
        contains(ok and rows[1].text or "", "Note", "note marker")
        local raindrop_ok, raindrop_rows = pcall(builder.buildRaindropItems, builder,
            { items = { { _id = 7 } } }, function() end, function() end)
        truthy(raindrop_ok, "untitled article: " .. tostring(raindrop_rows))
        contains(raindrop_ok and raindrop_rows[1].text or "", "Untitled", "missing title labelled")
        local group_ok, group_rows = pcall(builder.buildCollectionItems, builder,
            { groups = { { collections = { 44 } } }, roots = { { _id = 44, title = "A" } }, children = {} },
            function() end)
        truthy(group_ok, "untitled group: " .. tostring(group_rows))
    end)

    local function rowsWithText(rows, text)
        for _, row in ipairs(rows or {}) do
            if tostring(row.text):find(text, 1, true) then return row end
        end
    end

    test("read-only shared collections hide edit actions", function()
        local state = sessionFixture()
        Gota.rememberCollectionAccess(state.fake, { roots = {
            { _id = 44, title = "Shared", access = { level = 2, draggable = false } } } })
        Gota.showRaindropContent(state.fake, state.article)
        local callbacks = state.article_callbacks
        for _, name in ipairs({ "toggle_favorite", "edit_note", "edit_tags", "move_collection", "move_to_trash" }) do
            equal(callbacks[name], nil, name .. " hidden")
        end
        equal(callbacks.read_only, true, "read-only flag")
        local rows = UIBuilder:new():buildArticleMenu(state.article, false, callbacks, nil)
        local notice = rowsWithText(rows, "Read-only shared collection")
        truthy(notice, "read-only row shown")
        equal(notice and notice.select_enabled, false, "row is informational")
        Gota.resetAuthenticatedNavigation(state.fake)
    end)

    test("unknown or writable access keeps edit actions", function()
        local state = sessionFixture()
        Gota.resetAuthenticatedNavigation(state.fake)
        Gota.showRaindropContent(state.fake, state.article)
        truthy(state.article_callbacks.edit_note, "unknown access keeps actions")
        Gota.rememberCollectionAccess(state.fake, { children = { { _id = 44, access = { level = 3 } } } })
        Gota.showRaindropContent(state.fake, state.article)
        truthy(state.article_callbacks.move_collection, "collaborator with write access keeps actions")
        equal(Gota.collectionAccessLevel(state.fake, -1), 4, "Unsorted is the user's own")
        equal(Gota.collectionAccessLevel(state.fake, -99), 4, "Trash is the user's own")
        Gota.resetAuthenticatedNavigation(state.fake)
    end)

    test("account reset forgets collection permissions", function()
        local state = sessionFixture()
        Gota.rememberCollectionAccess(state.fake, { roots = { { _id = 44, access = { level = 1 } } } })
        Gota.resetAuthenticatedNavigation(state.fake)
        equal(Gota.collectionAccessLevel(state.fake, 44), nil, "old account level dropped")
    end)

    test("move destinations disable read-only collections", function()
        local state = sessionFixture()
        state.structure = { groups = {}, children = {}, roots = {
            { _id = 45, title = "Viewer only", access = { level = 1 } },
            { _id = 46, title = "Mine", access = { level = 4 } },
        } }
        Gota.chooseRaindropCollection(state.fake, state.article)
        local blocked, allowed = rowsWithText(state.rows, "Viewer only"), rowsWithText(state.rows, "Mine")
        truthy(blocked, "read-only destination listed")
        equal(blocked and blocked.select_enabled, false, "read-only destination disabled")
        equal(blocked and blocked.dim, true, "rendered dimmed by Menu")
        contains(blocked and blocked.text or "", "read-only", "reason shown")
        truthy(allowed and allowed.select_enabled ~= false, "owned destination enabled")
        Gota.resetAuthenticatedNavigation(state.fake)
    end)

    local function withNetworkCallback(callback, body)
        local manager = require("ui/network/manager")
        local previous = manager.runWhenOnline
        manager.runWhenOnline = callback
        local ok, failure = pcall(body)
        manager.runWhenOnline = previous
        if not ok then error(failure, 0) end
    end

    local function collectionDestination(rows)
        for index, row in ipairs(rows) do
            if index > 1 and row.callback then return row.callback end
        end
        error("missing collection destination")
    end

    test("old Trash confirmation and collection destinations reject before requesting connectivity", function()
        local state = sessionFixture()
        local fake, online_calls = state.fake, 0
        Gota.chooseRaindropCollection(fake, state.article, {})
        local unsorted, destination = state.rows[1].callback, collectionDestination(state.rows)
        Gota.confirmTrashRaindrop(fake, state.article, 44, {})
        local confirmation = state.confirm
        state.generation=2
        Gota.resetAuthenticatedNavigation(fake)
        withNetworkCallback(function(_, callback) online_calls=online_calls+1; callback() end, function()
            unsorted()
            destination()
            confirmation()
        end)
        equal(online_calls, 0, "old callbacks never enable Wi-Fi")
        equal(state.executed, 0, "old bookmark is never moved or trashed")
    end)

    test("mutation callbacks recheck their session after delayed connectivity", function()
        local state = sessionFixture()
        local fake, pending = state.fake, {}
        withNetworkCallback(function(_, callback) pending[#pending+1]=callback end, function()
            Gota.chooseRaindropCollection(fake, state.article, {})
            state.rows[1].callback()
            collectionDestination(state.rows)()
            Gota.confirmTrashRaindrop(fake, state.article, 44, {})
            state.confirm()
            Gota.editRaindropNote(fake, state.article, {})
            state.note.save("new note", {})
            Gota.editRaindropTags(fake, state.article, {})
            state.tags.save({"new tag"}, {})
            Gota.showRaindropContent(fake, state.article, {})
            state.article_callbacks.toggle_favorite()
        end)
        equal(#pending, 6, "all mutations wait for connectivity")
        state.generation=2
        Gota.resetAuthenticatedNavigation(fake)
        for _, callback in ipairs(pending) do callback() end
        equal(state.executed, 0, "no stale mutation reaches Raindrop after Wi-Fi returns")
    end)

    test("old collection actions pagination and search contexts stay rejected after session reset", function()
        local state = sessionFixture()
        local fake, retained, online_calls = state.fake, {}, 0
        local function captureRows()
            for _, row in ipairs(state.rows) do
                if row.callback then retained[#retained+1]=row.callback end
            end
        end
        Gota.renderCollections(fake, state.structure)
        captureRows()
        Gota.showCollectionActions(fake, 44, "Old collection")
        captureRows()
        Gota.showRaindrops(fake, 44, "Old collection", 0)
        captureRows()
        Gota.searchRaindrops(fake, "old query", 0, nil, {collection_id=44})
        captureRows()
        Gota.showHighlights(fake, 44, "Old collection", 0)
        captureRows()
        Gota.showSearchDialog(fake, {collection_id=44})
        local search = state.search
        Gota.showAdvancedSearchDialog(fake, {collection_id=44})
        local advanced = state.advanced
        state.generation=2
        Gota.resetAuthenticatedNavigation(fake)
        withNetworkCallback(function(_, callback) online_calls=online_calls+1; callback() end, function()
            for _, callback in ipairs(retained) do callback() end
            search("old query")
            advanced.on_state_change({term="old query"})
            advanced.on_search({term="old query"}, {})
        end)
        equal(online_calls, 0, "old navigation never enables Wi-Fi")
        equal(state.executed, 0, "old collection and page contexts never execute")
        equal(fake.last_advanced_search, nil, "old filters never return to the new session")
    end)
end
