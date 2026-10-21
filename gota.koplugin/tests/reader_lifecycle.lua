-- Reader session lifecycle across KOReader's native transitions: reload
-- (CloseDocument, then a new ReaderUI on the same path), Home, document
-- switch, and folder navigation. Registered by run.lua.
return function(test, equal, truthy, contains)
    local ReaderUI = require("apps/reader/readerui")
    local GotaReader = require("gota_reader")
    local Gota = require("main")
    local ArticleManager = dofile("gota_article_manager.lua")

    local function callbacks()
        return { notify = function() end, showProgress = function() end, hideProgress = function() end }
    end

    -- Simulated reader cache: a set of file names inside the canonical dir.
    local function withReaderCache(names, body)
        local manager = ArticleManager:new({}, {}, {}, callbacks())
        local cache_dir = manager:getReaderCacheDir()
        local files = {}
        for _, name in ipairs(names) do files[cache_dir .. "/" .. name] = true end
        local replacements = {
            ["ffi/util"] = { realpath = function(path) return path end },
            ["readhistory"] = { removeItemByPath = function() end },
            ["libs/libkoreader-lfs"] = {
                attributes = function(path)
                    if path == cache_dir then return "directory" end
                    return files[path] and "file" or nil
                end,
                dir = function()
                    local listed = {}
                    for path in pairs(files) do listed[#listed + 1] = path:match("([^/]+)$") end
                    table.sort(listed)
                    local index = 0
                    return function() index = index + 1; return listed[index] end
                end,
            },
        }
        local previous = {}
        for name, value in pairs(replacements) do
            previous[name] = package.loaded[name]
            package.loaded[name] = value
        end
        local old_remove, old_instance = os.remove, ReaderUI.instance
        os.remove = function(path) files[path] = nil; return true end
        GotaReader:reset()
        local ok, failure = pcall(body, manager, cache_dir, files)
        os.remove = old_remove
        ReaderUI.instance = old_instance
        GotaReader:reset()
        for name in pairs(replacements) do package.loaded[name] = previous[name] end
        if not ok then error(failure, 0) end
    end

    -- What a freshly created Gota instance does for its owner at init.
    local function ownerInit(manager, active_path)
        GotaReader:onOwnerInit(active_path)
        local owner = { ui = { document = active_path and { file = active_path } or nil } }
        return manager:cleanupOrphanReaderFiles(Gota.readerPathsToKeep(owner))
    end

    local function armReader(path)
        ReaderUI.instance = nil
        ReaderUI.showReader = function(self, file, _, _, _, after_open)
            self.instance = { document = { file = file } }
            after_open()
        end
        truthy(GotaReader:show({
            path = path,
            normalize_styles = true,
            return_target = { view = "offline_library" },
        }), "reader opened")
    end

    test("CloseDocument never removes the document KOReader may reopen", function()
        withReaderCache({ "raindrop_7.html" }, function(manager, cache_dir, files)
            local path = cache_dir .. "/raindrop_7.html"
            armReader(path)
            if Gota.onCloseDocument then
                Gota.onCloseDocument({ ui = { document = { file = path } }, article_manager = manager })
            end
            truthy(files[path], "temporary article kept through CloseDocument")
        end)
    end)

    test("native reload keeps the temporary article, normalization and return", function()
        withReaderCache({ "raindrop_7.html" }, function(manager, cache_dir, files)
            local path = cache_dir .. "/raindrop_7.html"
            armReader(path)
            ReaderUI.instance = nil -- reloadDocument closed the old ReaderUI
            ownerInit(manager, path) -- the new ReaderUI reopens the same path
            ReaderUI.instance = { document = { file = path } }
            truthy(files[path], "temporary article kept")
            equal(GotaReader.current_path, path, "pending path kept")
            equal(GotaReader:shouldNormalize(path), true, "normalization kept")
            equal(GotaReader:canReturn(), true, "Back to Gota kept")
        end)
    end)

    test("reloading an offline copy keeps Back to Gota", function()
        withReaderCache({}, function(manager)
            local path = "/exports/7_Item.html"
            armReader(path)
            ReaderUI.instance = nil
            ownerInit(manager, path)
            ReaderUI.instance = { document = { file = path } }
            equal(GotaReader:canReturn(), true, "Back to Gota kept")
            equal(GotaReader:shouldNormalize(path), true, "normalization kept")
        end)
    end)

    test("returning to FileManager releases the session and removes its temporary file", function()
        withReaderCache({ "raindrop_7.html" }, function(manager, cache_dir, files)
            local path = cache_dir .. "/raindrop_7.html"
            armReader(path)
            ReaderUI.instance = nil
            ownerInit(manager, nil)
            equal(GotaReader.current_path, nil, "session released")
            equal(GotaReader:shouldNormalize(path), false, "normalization released")
            equal(files[path], nil, "temporary article removed")
        end)
    end)

    test("switching to another document releases the previous temporary file", function()
        withReaderCache({ "raindrop_7.html" }, function(manager, cache_dir, files)
            local path = cache_dir .. "/raindrop_7.html"
            armReader(path)
            ReaderUI.instance = { document = { file = "/books/other.epub" } }
            ownerInit(manager, "/books/other.epub")
            equal(GotaReader.current_path, nil, "session released")
            equal(files[path], nil, "previous temporary article removed")
        end)
    end)

    test("startup with a temporary article as last document keeps it until FileManager", function()
        withReaderCache({ "raindrop_7.html" }, function(manager, cache_dir, files)
            local path = cache_dir .. "/raindrop_7.html"
            ReaderUI.instance = { document = { file = path } }
            ownerInit(manager, path)
            truthy(files[path], "last document kept while open")
            equal(GotaReader:canReturn(), false, "no Back to Gota without a Gota request")
            ReaderUI.instance = nil
            ownerInit(manager, nil)
            equal(files[path], nil, "removed once the reader is gone")
        end)
    end)

    test("orphan cleanup keeps every protected path", function()
        withReaderCache({ "raindrop_1.html", "raindrop_2.html", "raindrop_3.html" },
            function(manager, cache_dir, files)
                local _, warnings = manager:cleanupOrphanReaderFiles({
                    cache_dir .. "/raindrop_1.html", cache_dir .. "/raindrop_2.html",
                })
                equal(#warnings, 0, "cleanup warnings")
                truthy(files[cache_dir .. "/raindrop_1.html"], "first kept")
                truthy(files[cache_dir .. "/raindrop_2.html"], "second kept")
                equal(files[cache_dir .. "/raindrop_3.html"], nil, "orphan removed")
            end)
    end)

    test("a FileManager owner keeps the article still open in ReaderUI", function()
        withReaderCache({ "raindrop_7.html" }, function(manager, cache_dir, files)
            local path = cache_dir .. "/raindrop_7.html"
            armReader(path)
            -- ReaderUI is still active underneath a new FileManager.
            ownerInit(manager, nil)
            truthy(files[path], "open document kept")
            equal(GotaReader.current_path, path, "session kept while open")
        end)
    end)

    local function withFileManager(file_manager, body)
        local previous = package.loaded["apps/filemanager/filemanager"]
        local old_instance = ReaderUI.instance
        package.loaded["apps/filemanager/filemanager"] = file_manager
        local ok, failure = pcall(body)
        package.loaded["apps/filemanager/filemanager"] = previous
        ReaderUI.instance = old_instance
        GotaReader:reset()
        if not ok then error(failure, 0) end
    end

    test("open folder from the reader closes ReaderUI before FileManager", function()
        local order, shown = {}, nil
        withFileManager({ showFiles = function() order[#order + 1] = "showFiles" end }, function()
            armReader("/exports/7_Item.html")
            ReaderUI.instance = {
                document = { file = "/exports/7_Item.html" },
                onClose = function() order[#order + 1] = "close" end,
                showFileManager = function(_, file) order[#order + 1] = "filemanager"; shown = file end,
            }
            truthy(GotaReader:showFolder("/exports/7_Item.html"), "folder shown")
            equal(table.concat(order, ","), "close,filemanager", "reader closed first")
            equal(shown, "/exports/7_Item.html", "export focused")
            equal(GotaReader.current_path, nil, "Gota request released")
        end)
    end)

    test("open folder from FileManager focuses the export", function()
        local changed
        local file_manager = {
            instance = { file_chooser = { changeToPath = function(_, dir, file) changed = { dir, file } end } },
        }
        withFileManager(file_manager, function()
            ReaderUI.instance = nil
            truthy(GotaReader:showFolder("/exports/7_Item.html"), "folder shown")
            equal(changed[1], "/exports", "export directory")
            equal(changed[2], "/exports/7_Item.html", "export focused")
        end)
    end)

    test("open folder without any FileManager starts one on the export", function()
        local started
        withFileManager({ showFiles = function(_, dir, file) started = { dir, file } end }, function()
            ReaderUI.instance = nil
            truthy(GotaReader:showFolder("/exports/7_Item.html"), "folder shown")
            equal(started[1], "/exports", "export directory")
            equal(started[2], "/exports/7_Item.html", "export focused")
        end)
    end)

    test("saved-file Open folder goes through the reader adapter", function()
        local requested
        local previous = GotaReader.showFolder
        GotaReader.showFolder = function(_, path) requested = path; return true end
        local ok, failure = pcall(function()
            package.loaded["ui/widget/buttondialog"] = { new = function(_, opts) return opts end }
            local fake = { widgets = {}, closeWidget = function() end, closeAllWidgets = function() end }
            Gota.showSavedFileActions(fake, "/exports/7_Item.html", {})
            for _, row in ipairs(fake.widgets.saved_file_dialog.buttons) do
                for _, button in ipairs(row) do
                    if button.text == "Open folder" then button.callback() end
                end
            end
        end)
        GotaReader.showFolder = previous
        if not ok then error(failure, 0) end
        equal(requested, "/exports/7_Item.html", "adapter receives the export")
    end)

    local function withPluginInstance(instance, body)
        local previous = package.loaded["pluginloader"]
        package.loaded["pluginloader"] = {
            getPluginInstance = function(_, name) return name == "gota" and instance or nil end,
        }
        local old_instance = ReaderUI.instance
        local ok, failure = pcall(body)
        package.loaded["pluginloader"] = previous
        ReaderUI.instance = old_instance
        GotaReader:reset()
        if not ok then error(failure, 0) end
    end

    local function openForReturn(target)
        GotaReader:reset()
        ReaderUI.instance = nil
        ReaderUI.showReader = function(self, file, _, _, _, after_open)
            self.instance = { document = { file = file }, onHome = function() end }
            after_open()
        end
        return GotaReader:show({ path = "/exports/7_Item.html", return_target = target })
    end

    test("return resumes on the active Gota instance, not the opener", function()
        local old, new = {}, {}
        old.resumeFromReader = function(_, target) old.resumed = target end
        new.resumeFromReader = function(_, target) new.resumed = target end
        withPluginInstance(new, function()
            truthy(openForReturn({
                view = "article", raindrop = { _id = 7, title = "Item" },
                source = { kind = "collection", collection_id = 5, collection_name = "Inbox", page = 2 },
            }), "reader opened")
            equal(GotaReader:canReturn(), true, "Back to Gota offered")
            equal(GotaReader:onReturn(), true, "return started")
            equal(new.resumed and new.resumed.raindrop._id, 7, "article resumed")
            equal(new.resumed and new.resumed.source.page, 2, "source page kept")
            equal(old.resumed, nil, "stale opener untouched")
        end)
    end)

    test("return finds Gota under the folder name KOReader registered", function()
        -- PluginLoader names a plugin after its folder (raindrop.koplugin ->
        -- "raindrop"), overriding the name declared in main.lua.
        local resumed
        local renamed = { resumeFromReader = function(_, target) resumed = target end }
        local previous = package.loaded["pluginloader"]
        package.loaded["pluginloader"] = {
            getPluginInstance = function(_, name) return name == "raindrop" and renamed or nil end,
        }
        local ok, failure = pcall(function()
            GotaReader:setPluginName("raindrop")
            openForReturn({ view = "offline_library" })
            GotaReader:onReturn()
        end)
        GotaReader:setPluginName(nil)
        package.loaded["pluginloader"] = previous
        GotaReader:reset()
        if not ok then error(failure, 0) end
        equal(resumed and resumed.view, "offline_library", "renamed install resumes")
    end)

    test("return target keeps only plain data", function()
        withPluginInstance(nil, function()
            openForReturn({
                view = "article",
                raindrop = { _id = 7, title = "Item", cache = { status = "ready", text = "large body" } },
                source = { kind = "collection", collection_id = 5, page = 0, reload = function() end },
            })
            local target = GotaReader.return_target
            equal(target.source.reload, nil, "closure dropped")
            equal(target.raindrop.cache.text, nil, "loaded text not retained")
            equal(target.raindrop.cache.status, "ready", "metadata kept")
        end)
    end)

    test("a malformed return target disables Back to Gota", function()
        withPluginInstance(nil, function()
            openForReturn({ view = "article", raindrop = { _id = "x" } })
            equal(GotaReader:canReturn(), false, "invalid article id")
            openForReturn({ view = "elsewhere" })
            equal(GotaReader:canReturn(), false, "unknown view")
            openForReturn(function() end)
            equal(GotaReader:canReturn(), false, "callbacks are not accepted")
        end)
    end)

    test("return without a live Gota instance does not fail", function()
        withPluginInstance(nil, function()
            openForReturn({ view = "offline_library" })
            equal(GotaReader:onReturn(), true, "reader still closed")
        end)
    end)

    local function fakeGota(generation)
        local calls = {}
        local fake = setmetatable({
            calls = calls, widgets = {},
            settings = { getSessionGeneration = function() return generation end },
            showRaindrops = function(_, ...) calls.raindrops = { ... } end,
            searchRaindrops = function(_, ...) calls.search = { ... } end,
            showHighlights = function(_, ...) calls.highlights = { ... } end,
            showRaindropContent = function(_, raindrop, context) calls.content = { raindrop, context } end,
            showOfflineLibrary = function() calls.library = true end,
            notify = function(_, text) calls.notice = text end,
            resetAuthenticatedNavigation = function() end,
        }, { __index = Gota })
        return fake, calls
    end

    test("source descriptors rebuild an equivalent context", function()
        local fake, calls = fakeGota(1)
        local collection = fake:buildCollectionSourceContext(5, "Inbox", 2)
        local rebuilt = fake:sourceContextFromDescriptor(collection.descriptor)
        equal(rebuilt.kind, "collection", "collection kind")
        equal(rebuilt.page, 2, "collection page")
        rebuilt.reload(7)
        equal(table.concat({ tostring(calls.raindrops[1]), calls.raindrops[2],
            tostring(calls.raindrops[3]), tostring(calls.raindrops[4]) }, "|"), "5|Inbox|2|7", "collection reload")

        local search = fake:buildSearchSourceContext("word", 1, { tag = "t" }, { sort = "title" })
        local rebuilt_search = fake:sourceContextFromDescriptor(search.descriptor)
        rebuilt_search.reload(9)
        equal(calls.search[1], "word", "search term")
        equal(calls.search[2], 1, "search page")
        equal(calls.search[3].tag, "t", "search filters")
        equal(calls.search[4].sort, "title", "search context")
        equal(calls.search[5], 9, "search focus")

        local highlights = fake:buildHighlightsSourceContext(nil, "All highlights", 3)
        local rebuilt_highlights = fake:sourceContextFromDescriptor(highlights.descriptor)
        rebuilt_highlights.reload(4)
        equal(calls.highlights[2], "All highlights", "highlights name")
        equal(calls.highlights[3], 3, "highlights page")
        equal(fake:sourceContextFromDescriptor({ kind = "other" }), nil, "unknown kind")
        equal(fake:sourceContextFromDescriptor(nil), nil, "no descriptor")
    end)

    test("resume opens the article snapshot with a rebuilt source", function()
        local fake, calls = fakeGota(1)
        fake:resumeFromReader({
            view = "article", generation = 1, raindrop = { _id = 7, title = "Item" },
            source = { kind = "collection", collection_id = 5, collection_name = "Inbox", page = 2 },
        })
        equal(calls.content and calls.content[1].title, "Item", "article snapshot shown")
        equal(calls.content and calls.content[2].page, 2, "source context rebuilt")
    end)

    test("resume after an account change does not reopen the old article", function()
        local fake, calls = fakeGota(2)
        fake:resumeFromReader({ view = "article", generation = 1, raindrop = { _id = 7 } })
        equal(calls.content, nil, "old account article not shown")
        truthy(calls.notice, "user told why")
    end)

    test("offline library return reopens the library", function()
        local fake, calls = fakeGota(1)
        fake:resumeFromReader({ view = "offline_library" })
        equal(calls.library, true, "library shown")
    end)

    test("article reader actions hand over a return target, not a closure", function()
        local fake = fakeGota(3)
        local target = fake:readerReturnTarget({ _id = 7, title = "Item" },
            fake:buildCollectionSourceContext(5, "Inbox", 2))
        equal(target.view, "article", "article view")
        equal(target.raindrop._id, 7, "article snapshot")
        equal(target.source.collection_id, 5, "source descriptor")
        equal(target.generation, 3, "account generation")
    end)
end
