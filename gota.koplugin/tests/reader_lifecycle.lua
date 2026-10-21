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
            on_return_callback = function() end,
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
end
