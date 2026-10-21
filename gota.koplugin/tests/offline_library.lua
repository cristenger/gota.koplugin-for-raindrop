-- Real modules with isolated filesystem/reader doubles. Registered by run.lua.
return function(test, equal, truthy, contains)
    local OfflineLibrary = dofile("gota_offline_library.lua")
    local ArticleManager = dofile("gota_article_manager.lua")
    local dir = "/tmp/gota-library-tests"

    local function filesystem(entries, names)
        return {
            attributes = function(path, field)
                if path == dir then return field == "mode" and "directory" or nil end
                local name = path:match("([^/]+)$")
                local entry = entries[name]
                if not entry then return nil end
                if field == "mode" then return entry.mode or "file" end
                return nil
            end,
            dir = function(path)
                equal(path, dir, "configured export directory")
                local ordered = names or { ".", ".." }
                if not names then
                    for name in pairs(entries) do ordered[#ordered + 1] = name end
                    table.sort(ordered)
                end
                local index = 0
                return function() index = index + 1; return ordered[index] end
            end,
        }
    end

    local function withModules(replacements, body)
        local previous = {}
        for name, value in pairs(replacements) do
            previous[name] = package.loaded[name]
            package.loaded[name] = value
        end
        local ok, failure = pcall(body)
        for name in pairs(replacements) do package.loaded[name] = previous[name] end
        if not ok then error(failure, 0) end
    end

    local function callbacks()
        return { notify = function() end, showProgress = function() end, hideProgress = function() end }
    end

    test("local library lists original and annotated exports with separate progress", function()
        local entries = {
            ["7_Old_Title_1.html"] = { header = "<TITLE>Actual &amp; complete title</TITLE>" },
            ["7_Old_Title_notes.html"] = {
                header = '<meta name="generator" content="Gota annotated export"><title>Actual &amp; complete title</title>',
            },
            ["8_Legacy_notes_2.html"] = {
                header = "<style>.notes-section {} .highlights-section {} .source-url {}</style>",
            },
            ["9_Release_notes.html"] = { header = "<title>Release notes</title>" },
        }
        local queried = {}
        local docsettings = {
            findSidecarFile = function(_, path) queried[#queried + 1] = path; return path .. ".sdr" end,
            openSettingsFile = function(path)
                return { readSetting = function()
                    return path:find("_notes.html", 1, true) and 0.75 or 0.40
                end }
            end,
        }
        local copies, err = OfflineLibrary.list(dir, filesystem(entries), docsettings, {
            read_header = function(path, limit)
                equal(limit, 16384, "bounded header read")
                return entries[path:match("([^/]+)$")].header
            end,
            decode_entities = function(title) return title:gsub("&amp;", "&") end,
        })
        equal(err, nil, "listing error")
        equal(#copies, 4, "all independent copies")
        equal(copies[1].title, "Actual & complete title", "unsanitized HTML title")
        equal(copies[1].raindrop_id, 7, "documented integer id")
        equal(copies[1].path, dir .. "/7_Old_Title_1.html", "legacy path preserved")
        equal(copies[1].annotated, false, "original")
        equal(copies[1].percent, 40, "original progress")
        equal(copies[2].annotated, true, "annotated marker")
        equal(copies[2].percent, 75, "annotated copy progress")
        equal(copies[3].title, "Legacy", "old export fallback title")
        equal(copies[3].annotated, true, "historical stylesheet")
        equal(copies[4].annotated, false, "notes in the article title")
        equal(#queried, 4, "each existing document's sidecar")
    end)

    test("local library ignores incomplete malformed and non-document entries", function()
        local entries = {
            ["42_Valid.html"] = {},
            ["42_Valid.html.part"] = {},
            ["42_Valid.html.part.decoded"] = {},
            ["42_Directory.html"] = { mode = "directory" },
            ["42_.html"] = {},
            ["42_ .html"] = {},
            ["42_..html"] = {},
            ["42_Bad\nTitle.html"] = {},
            ["9007199254740992_Huge.html"] = {},
            ["invalid_Article.html"] = {},
            ["index.html"] = {},
        }
        local reads = 0
        local copies = OfflineLibrary.list(dir, filesystem(entries), nil, {
            read_header = function() reads = reads + 1; return nil end,
        })
        equal(#copies, 1, "only Gota article documents")
        equal(copies[1].title, "Valid", "filename fallback")
        equal(reads, 1, "unrelated files are never opened")
    end)

    test("local library survives unreadable metadata and sorts independently of readdir", function()
        local entries = { ["2_Title.html"] = {}, ["1_Title.html"] = {}, ["3_Fallback_notes.html"] = {} }
        local options = { read_header = function() error("file disappeared") end }
        local first = OfflineLibrary.list(dir, filesystem(entries,
            { "2_Title.html", "1_Title.html", "3_Fallback_notes.html" }), {}, options)
        local second = OfflineLibrary.list(dir, filesystem(entries,
            { "3_Fallback_notes.html", "1_Title.html", "2_Title.html" }), {}, options)
        equal(#first, 3, "read failures keep filename entries")
        equal(first[1].annotated, true, "unreadable annotated suffix")
        equal(first[1].title, "Fallback", "annotated filename title")
        for i = 1, #first do equal(first[i].path, second[i].path, "stable ordering") end
        equal(first[2].percent, nil, "missing progress")
    end)

    test("local library returns no files for a missing folder and reports enumeration errors", function()
        local copies, err = OfflineLibrary.list(dir, {
            attributes = function() return nil end,
            dir = function() error("must not scan absent folder") end,
        })
        equal(#copies, 0, "first-use library")
        equal(err, nil, "absence is normal")
        copies, err = OfflineLibrary.list(dir, {
            attributes = function() return "directory" end,
            dir = function() error("permission denied") end,
        })
        equal(copies, nil, "failed listing")
        contains(err, "permission denied", "directory error")
        copies, err = OfflineLibrary.list(dir, {
            attributes = function() return "directory" end,
            dir = function() return function() error("directory vanished") end end,
        })
        equal(copies, nil, "failed iteration")
        contains(err, "directory vanished", "iteration error")
    end)

    test("article manager local listing requires no API or connectivity", function()
        withModules({ ["libs/libkoreader-lfs"] = filesystem({ ["19_Kept.html"] = {} }) }, function()
            local api = setmetatable({}, { __index = function() error("unexpected network access") end })
            local manager = ArticleManager:new(api, {}, {}, callbacks())
            manager:setSettings({ getFullDownloadPath = function() return dir end })
            manager:setDocSettings({})
            local copies, err = manager:listOfflineCopies()
            equal(err, nil, "local listing")
            equal(#copies, 1, "kept file")
            equal(copies[1].raindrop_id, 19, "kept article")
        end)
    end)

    test("reader preparation cannot overwrite the currently open temporary document", function()
        local notices, downloads = {}, 0
        local manager = ArticleManager:new({
            downloadRaindropCache = function() downloads = downloads + 1 end,
        }, {}, {
            isDocumentOpen = function(_, path) return path:match("/raindrop_19%.html$") ~= nil end,
            show = function() error("reader should not reopen") end,
        }, {
            notify = function(message) notices[#notices + 1] = message end,
            showProgress = function() error("no transfer should start") end,
            hideProgress = function() end,
        })
        local old_remove, removed = os.remove, 0
        os.remove = function() removed = removed + 1; return true end
        local ok, failure = pcall(function()
            equal(manager:openInReader({ _id = 19, cache = { status = "ready" } }), false, "active document guard")
            equal(downloads, 0, "no transfer")
            equal(removed, 0, "active file is untouched")
            contains(notices[1], "already open", "actionable message")
        end)
        os.remove = old_remove
        if not ok then error(failure, 0) end
    end)

    test("managed reader cleanup handles cancelled decoded parts and preserves active siblings", function()
        local manager = ArticleManager:new({}, {}, {}, callbacks())
        local cache_dir = manager:getReaderCacheDir()
        local active = cache_dir .. "/raindrop_2.html"
        local names = { "raindrop_1.html.part.decoded", "raindrop_2.html", "raindrop_2.html.part",
            "raindrop_2.html.part.decoded", "raindrop_3.html", "raindrop_3.html.part.decoded", "foreign.part.decoded" }
        local files = {}
        for _, name in ipairs(names) do files[cache_dir .. "/" .. name] = true end
        local old_remove, history = os.remove, {}
        os.remove = function(path) files[path] = nil; return true end
        local ok, failure = pcall(function()
            withModules({
                ["ffi/util"] = { realpath = function(path) return path end },
                ["readhistory"] = { removeItemByPath = function(_, path) history[#history + 1] = path end },
                ["libs/libkoreader-lfs"] = {
                    attributes = function(path)
                        if path == cache_dir then return "directory" end
                        return files[path] and "file" or nil
                    end,
                    dir = function()
                        local index = 0
                        return function() index = index + 1; return names[index] end
                    end,
                },
            }, function()
                truthy(manager:isManagedReaderPath(cache_dir .. "/raindrop_1.html.part.decoded"), "owned decoded part")
                local _, warnings = manager:cleanupOrphanReaderFiles({ active })
                equal(#warnings, 0, "cleanup warnings")
                equal(files[cache_dir .. "/raindrop_1.html.part.decoded"], nil, "cancelled inflation removed")
                equal(files[cache_dir .. "/raindrop_3.html"], nil, "orphan document removed")
                equal(files[cache_dir .. "/raindrop_3.html.part.decoded"], nil, "orphan sibling removed")
                truthy(files[active], "active document")
                truthy(files[active .. ".part"], "active transfer part")
                truthy(files[active .. ".part.decoded"], "active decoded part")
                truthy(files[cache_dir .. "/foreign.part.decoded"], "foreign file")
                equal(#history, 1, "only completed document affects history")
            end)
        end)
        os.remove = old_remove
        if not ok then error(failure, 0) end
    end)

    test("offline progress rejects NaN sidecar values", function()
        local progress = OfflineLibrary.progress("/tmp/nan.html", {
            findSidecarFile = function() return "/tmp/nan.sdr" end,
            openSettingsFile = function() return { readSetting = function() return 0 / 0 end } end,
        })
        equal(progress, nil, "invalid numeric progress")
    end)
end
