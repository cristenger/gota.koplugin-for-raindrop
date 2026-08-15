-- Dependency-free regression tests for the parts of Gota that can run outside
-- KOReader. Run from gota.koplugin with: lua tests/run.lua

package.path = "./?.lua;" .. package.path

local function noop() end
local logger = setmetatable({}, { __index = function() return noop end })

package.preload["logger"] = function() return logger end
package.preload["gettext"] = function() return function(value) return value end end
package.preload["util"] = function()
    return {
        makePath = function() return true end,
        htmlEscape = function(value)
            return tostring(value or "")
                :gsub("&", "&amp;")
                :gsub("<", "&lt;")
                :gsub(">", "&gt;")
                :gsub('"', "&quot;")
        end,
        htmlToPlainTextIfHtml = function(value) return value end,
    }
end
package.preload["datastorage"] = function()
    return {
        getDataDir = function() return "/tmp" end,
        getSettingsDir = function() return "/tmp" end,
    }
end
package.preload["ui/uimanager"] = function()
    return {
        close = noop,
        forceRePaint = noop,
        nextTick = function(_, callback) callback() end,
        scheduleIn = function(_, _, callback) callback() end,
        show = noop,
    }
end
package.preload["ui/widget/menu"] = function()
    return { new = function(_, options) return options end }
end
package.preload["device"] = function() return {} end
package.preload["ssl.https"] = function() return { request = noop } end
package.preload["ltn12"] = function()
    return { source = { string = function(value) return value end } }
end
package.preload["socket"] = function() return { sleep = noop } end
package.preload["socketutil"] = function()
    return {
        FILE_BLOCK_TIMEOUT = 1,
        FILE_TOTAL_TIMEOUT = 1,
        LARGE_BLOCK_TIMEOUT = 1,
        LARGE_TOTAL_TIMEOUT = 1,
        reset_timeout = noop,
        set_timeout = noop,
        table_sink = function(target)
            return function(chunk)
                if chunk then target[#target + 1] = chunk end
                return 1
            end
        end,
    }
end
package.preload["json"] = function()
    return {
        decode = function(payload)
            if payload == '{"ok":true}' then return { ok = true } end
            if payload == '{"errorMessage":"bad token"}' then
                return { errorMessage = "bad token" }
            end
            if payload == '{"result":false,"errorMessage":"rejected"}' then
                return { result = false, errorMessage = "rejected" }
            end
            error("malformed JSON")
        end,
    }
end

local total = 0
local failed = 0

local function test(name, callback)
    total = total + 1
    local ok, err = pcall(callback)
    if ok then
        io.write("ok ", total, " - ", name, "\n")
    else
        failed = failed + 1
        io.write("not ok ", total, " - ", name, "\n  ", tostring(err), "\n")
    end
end

local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %q, got %q", label or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(value, label)
    if not value then error((label or "value") .. " should be truthy", 2) end
end

local function contains(value, expected, label)
    if type(value) ~= "string" or not value:find(expected, 1, true) then
        error(string.format("%s: %q not found in %q", label or "value", expected, tostring(value)), 2)
    end
end

local ContentProcessor = require("gota_content_processor")

test("UTF-8 sanitizer preserves valid multilingual text", function()
    local source = "café, español, 漢字, 😀, e\204\129"
    local cleaned, replaced, had_bom = ContentProcessor.sanitizeUTF8(source)
    equal(cleaned, source, "cleaned text")
    equal(replaced, false, "replacement flag")
    equal(had_bom, false, "BOM flag")
end)

test("UTF-8 sanitizer removes BOM", function()
    local cleaned, replaced, had_bom = ContentProcessor.sanitizeUTF8("\239\187\191hola")
    equal(cleaned, "hola", "cleaned text")
    equal(replaced, false, "replacement flag")
    equal(had_bom, true, "BOM flag")
end)

test("UTF-8 sanitizer replaces malformed scalar sequences", function()
    local replacement = "\239\191\189"
    local source = "A\192\175B\237\160\128C\244\144\128\128D\226\130"
    local cleaned, replaced = ContentProcessor.sanitizeUTF8(source)
    equal(cleaned, "A" .. replacement .. "B" .. replacement .. "C" .. replacement .. "D" .. replacement)
    equal(replaced, true, "replacement flag")
end)

test("e-ink HTML cleaning removes active elements and preserves preformatted text", function()
    local processor = ContentProcessor:new()
    local cleaned = processor:cleanHTMLForEink(
        "<SCRIPT>alert(1)</SCRIPT><PRE>line 1\n    line 2</PRE>"
    )
    equal(cleaned:find("alert", 1, true), nil, "script content")
    contains(cleaned, "<PRE>line 1\n    line 2</PRE>", "preformatted content")
end)

test("generated notes HTML escapes metadata and constrains highlight colors", function()
    local processor = ContentProcessor:new()
    local html = processor:createReaderHTMLWithNotes({
        title = "<unsafe>",
        note = "one\ntwo",
        highlights = {
            { text = "<mark>", color = 'yellow\" onclick=\"bad' },
        },
    })
    contains(html, "&lt;unsafe&gt;", "escaped title")
    contains(html, "one<br/>two", "multiline note")
    contains(html, 'class="highlight highlight-yellow"', "safe color class")
    equal(html:find("onclick", 1, true), nil, "injected attribute")
end)

test("plain-text highlights cover every documented Raindrop color", function()
    local processor = ContentProcessor:new()
    local content = processor:formatHighlights({
        title = "Colors",
        highlights = {
            { text = "brown", color = "brown" },
            { text = "gray", color = "gray" },
            { text = "indigo", color = "indigo" },
            { text = "teal", color = "teal" },
        },
    })
    contains(content, "[Brown]", "brown")
    contains(content, "[Gray]", "gray")
    contains(content, "[Indigo]", "indigo")
    contains(content, "[Teal]", "teal")
end)

local API = require("gota_api")

test("Raindrop search expression quotes tags and embeds type", function()
    equal(
        API.buildSearchExpression("swift", { tag = "coffee beans", type = "Article" }),
        'swift #"coffee beans" type:article'
    )
    equal(API.buildSearchExpression("", { tag = 'a"b\\c' }), [=[#"a\"b\\c"]=])
end)

test("Raindrop pagination enforces documented zero-based limits", function()
    local page, perpage = API.normalizePagination(0, 50)
    equal(page, 0, "page")
    equal(perpage, 50, "perpage")
    equal(API.normalizePagination(-1, 25), nil, "negative page")
    equal(API.normalizePagination(0, 51), nil, "oversized page")
    equal(API.normalizePagination(1.5, 25), nil, "fractional page")
end)

test("API rejects insecure or credential-bearing server URLs", function()
    local settings = { getToken = function() return "token" end }
    local ok_http = pcall(function() API:new(settings, "http://api.raindrop.io/rest/v1") end)
    local ok_creds = pcall(function() API:new(settings, "https://user@example.com/rest/v1") end)
    equal(ok_http, false, "HTTP URL")
    equal(ok_creds, false, "credential-bearing URL")
    truthy(API:new(settings, "https://api.raindrop.io/rest/v1"), "HTTPS API")
end)

test("cache redirect strips Authorization and requires HTTPS", function()
    local api = API:new({ getToken = function() return "secret" end })
    local calls = {}
    function api:_performRequest(url, method, body, include_authorization)
        calls[#calls + 1] = { url = url, auth = include_authorization }
        if #calls == 1 then
            return "", nil, 307, { Location = "https://storage.example/cache.html" }
        end
        return "<html>cached</html>", nil, 200, {}
    end

    local result, err = api:makeRequest("/raindrop/7/cache")
    equal(err, nil, "redirect error")
    equal(result, "<html>cached</html>", "cache body")
    equal(calls[1].auth, true, "API authorization")
    equal(calls[2].auth, false, "redirect authorization")
    equal(calls[2].url, "https://storage.example/cache.html", "redirect URL")
end)

test("cache redirect refuses downgrade to HTTP", function()
    local api = API:new({ getToken = function() return "secret" end })
    function api:_performRequest()
        return "", nil, 307, { Location = "http://storage.example/cache.html" }
    end
    local result, err = api:makeRequest("/raindrop/7/cache")
    equal(result, nil, "result")
    truthy(err and err:find("unsafe", 1, true), "unsafe redirect error")
end)

test("invalid JSON is contained and returned as an error", function()
    local api = API:new({ getToken = function() return "secret" end })
    function api:_performRequest() return "invalid-json", nil, 200, {} end
    local result, err = api:makeRequest("/user")
    equal(result, nil, "result")
    truthy(err and err:find("Invalid JSON", 1, true), "JSON error")
end)

test("successful HTTP responses with result=false are rejected", function()
    local api = API:new({ getToken = function() return "secret" end })
    function api:_performRequest()
        return '{"result":false,"errorMessage":"rejected"}', nil, 200, {}
    end
    local result, err = api:makeRequest("/user")
    equal(result, nil, "result")
    contains(err, "rejected", "API error detail")
end)

test("cache downloads reject empty 204 and non-redirect 304 responses", function()
    local api = API:new({ getToken = function() return "secret" end })
    function api:_performRequest()
        return "", nil, 204, {}
    end
    local result_204, err_204 = api:makeRequest("/raindrop/7/cache")
    equal(result_204, nil, "204 result")
    contains(err_204, "Empty server response", "204 error")

    function api:_performRequest()
        return "", nil, 304, { Location = "https://storage.example/cache.html" }
    end
    local result_304, err_304 = api:makeRequest("/raindrop/7/cache")
    equal(result_304, nil, "304 result")
    contains(err_304, "Unexpected redirect", "304 error")
end)

test("transient server errors retry with bounded delay", function()
    local api = API:new({ getToken = function() return "secret" end })
    local attempts = 0
    local delays = {}
    function api:makeRequest()
        attempts = attempts + 1
        if attempts == 1 then return nil, "temporary", 503, {} end
        return { ok = true }, nil, 200, {}
    end
    api.sleep = function(delay) delays[#delays + 1] = delay end

    local result, err = api:makeRequestWithRetry("/user")
    equal(err, nil, "retry error")
    equal(result.ok, true, "retry result")
    equal(attempts, 2, "attempt count")
    equal(delays[1], 0.5, "first retry delay")
end)

test("rate limiting honors Retry-After before retrying", function()
    local api = API:new({ getToken = function() return "secret" end })
    local attempts = 0
    local delay
    function api:makeRequest()
        attempts = attempts + 1
        if attempts == 1 then
            return nil, "rate limited", 429, { ["Retry-After"] = "2" }
        end
        return { ok = true }, nil, 200, {}
    end
    api.sleep = function(value) delay = value end
    local result, err = api:makeRequestWithRetry("/user")
    equal(err, nil, "retry error")
    equal(result.ok, true, "retry result")
    equal(delay, 2, "Retry-After delay")
end)

test("long rate-limit windows do not freeze the UI thread", function()
    local api = API:new({ getToken = function() return "secret" end })
    local attempts = 0
    local slept = false
    function api:makeRequest()
        attempts = attempts + 1
        return nil, "rate limited", 429, { ["Retry-After"] = "20" }
    end
    api.sleep = function() slept = true end
    local result, err = api:makeRequestWithRetry("/user")
    equal(result, nil, "result")
    equal(attempts, 1, "attempt count")
    equal(slept, false, "sleep")
    contains(err, "retry later", "retry guidance")
end)

test("forced raindrop reload bypasses the response cache", function()
    local api = API:new({ getToken = function() return "secret" end })
    local observed = {}
    function api:cachedRequest(endpoint, method, body, use_cache)
        observed[#observed + 1] = use_cache == nil and "default" or use_cache
        return { item = { _id = 7 } }
    end
    api:getRaindrop(7)
    api:getRaindrop(7, true)
    equal(#observed, 2, "call count")
    equal(observed[1], "default", "normal cache mode")
    equal(observed[2], false, "forced cache mode")
end)

test("all-tags request uses the documented endpoint without collection ID", function()
    local api = API:new({ getToken = function() return "secret" end })
    local endpoint
    function api:cachedRequest(value)
        endpoint = value
        return { items = {} }
    end
    api:getTags()
    equal(endpoint, "/tags", "all-tags endpoint")
    api:getTags(42)
    equal(endpoint, "/tags/42", "collection-tags endpoint")
end)

test("root and child collection envelopes merge without duplicate IDs", function()
    local api = API:new({ getToken = function() return "secret" end })
    function api:getRootCollections()
        return { count = 2, items = { { _id = 1 }, { _id = 2 } } }
    end
    function api:getChildCollections()
        return { items = { { _id = 2 }, { _id = 3, parent = { ["$id"] = 1 } } } }
    end
    local collections, err = api:getCollections()
    equal(err, nil, "collections error")
    equal(#collections.items, 3, "collection count")
    equal(collections.count, 3, "envelope count")
    equal(collections.items[3]._id, 3, "child ID")
end)

test("raindrop list rejects a structurally incomplete envelope", function()
    local api = API:new({ getToken = function() return "secret" end })
    function api:cachedRequest()
        return { result = true, items = {} }
    end
    local result, err = api:getRaindrops(0, 0, 25, "-created")
    equal(result, nil, "result")
    contains(err, "Invalid API response envelope", "envelope error")
end)

local ArticleManager = require("gota_article_manager")

test("article cache state requires downloaded HTML", function()
    local manager = ArticleManager:new({}, {}, {}, {
        showProgress = noop,
        hideProgress = noop,
        notify = noop,
    })
    equal(manager:hasValidCache({ cache = { status = "ready", size = 42 } }), false)
    equal(manager:hasValidCache({ cache = { status = "ready", text = "  " } }), false)
    equal(manager:hasValidCache({ cache = { status = "ready", text = "<p>x</p>" } }), true)
end)

test("reader precondition failure keeps the current menu open", function()
    local closed = false
    local notifications = 0
    local manager = ArticleManager:new({}, {}, {}, {
        showProgress = noop,
        hideProgress = noop,
        notify = function() notifications = notifications + 1 end,
    })
    local opened = manager:openInReader(
        { cache = { status = "ready", size = 42 } },
        function() closed = true end,
        noop
    )
    equal(opened, false, "reader result")
    equal(closed, false, "menu close")
    equal(notifications, 1, "notification count")
end)

test("reader cache files are isolated from permanent exports", function()
    local manager = ArticleManager:new({}, {}, {}, {
        showProgress = noop,
        hideProgress = noop,
        notify = noop,
    })
    equal(manager:getReaderCachePath(42), "/tmp/cache/gota/raindrop_42.html")
end)

test("article reload forces metadata and downloads cache endpoint", function()
    local force_refresh
    local cache_calls = 0
    local api = {
        getRaindrop = function(_, id, force)
            equal(id, 9, "raindrop id")
            force_refresh = force
            return { item = { _id = id, cache = { status = "ready", size = 10 } } }
        end,
        getRaindropCache = function(_, id)
            equal(id, 9, "cache id")
            cache_calls = cache_calls + 1
            return "<html>ready</html>"
        end,
    }
    local manager = ArticleManager:new(api, {}, {}, {
        showProgress = noop,
        hideProgress = noop,
        notify = noop,
    })
    local reloaded
    manager:reloadArticle(9, function(item) reloaded = item end)
    equal(force_refresh, true, "force refresh")
    equal(cache_calls, 1, "cache calls")
    equal(reloaded.cache.text, "<html>ready</html>", "downloaded HTML")
end)

test("article loading detaches downloaded HTML from the API response cache", function()
    local list_item = {
        _id = 9,
        cache = { status = "ready", size = 10 },
    }
    local detail_item = {
        _id = 9,
        title = "Detail",
        cache = { status = "ready", size = 10 },
    }
    local detail_calls = 0
    local api = {
        getRaindrop = function()
            detail_calls = detail_calls + 1
            return { item = detail_item }
        end,
        getRaindropCache = function()
            return "<html>ready</html>"
        end,
    }
    local manager = ArticleManager:new(api, {}, {}, {
        showProgress = noop,
        hideProgress = noop,
        notify = noop,
    })
    local loaded = manager:loadFullArticle(list_item)
    loaded = manager:loadCacheContent(loaded)
    equal(detail_calls, 1, "detail calls")
    equal(loaded.title, "Detail", "detail title")
    equal(loaded.cache.text, "<html>ready</html>", "local HTML")
    equal(list_item.cache.text, nil, "list cache mutation")
    equal(detail_item.cache.text, nil, "detail cache mutation")
end)

local UIBuilder = require("gota_ui_builder")

test("nested collections flatten in stable parent-first order", function()
    local flattened = UIBuilder.flattenCollections({ items = {
        { _id = 1, title = "Root A" },
        { _id = 3, title = "Child", parent = { ["$id"] = 1 } },
        { _id = 2, title = "Root B" },
    } })
    equal(#flattened, 3, "collection count")
    equal(flattened[1].collection.title, "Root A")
    equal(flattened[1].depth, 0)
    equal(flattened[2].collection.title, "Child")
    equal(flattened[2].depth, 1)
    equal(flattened[3].collection.title, "Root B")
end)

test("article excerpts remain valid UTF-8 and only show ellipsis when truncated", function()
    local builder = UIBuilder:new()
    local short = builder:buildRaindropItems({ items = {
        { title = "Short", excerpt = "café 😀" },
    } }, noop)
    contains(short[1].text, "café 😀", "short excerpt")
    equal(short[1].text:sub(-3) == "...", false, "no short ellipsis")

    local long_excerpt = string.rep("😀", 51)
    local long = builder:buildRaindropItems({ items = {
        { title = "Long", excerpt = long_excerpt },
    } }, noop)
    equal(long[1].text:sub(-3), "...", "long ellipsis")
end)

test("notes export remains enabled without Raindrop PRO HTML", function()
    local builder = UIBuilder:new()
    local menu = builder:buildArticleMenu({ note = "local note" }, false, {})
    local export_item
    for _, item in ipairs(menu) do
        if item.text == "Save HTML with notes & highlights" then export_item = item end
    end
    truthy(export_item, "export item")
    equal(export_item.enabled, true, "export enabled")
end)

test("settings normalize manipulated paths and unsupported sort values", function()
    local stored = {
        token = "secret",
        download_path = "/outside/data",
        sort_order = "score",
    }
    local saved = {}
    package.loaded["luasettings"] = {
        open = function()
            return {
                readSetting = function(_, key) return stored[key] end,
                saveSetting = function(_, key, value) saved[key] = value end,
                flush = noop,
            }
        end,
    }
    package.loaded["libs/libkoreader-lfs"] = {
        attributes = function(path, attribute)
            if path == "/tmp" and attribute == "mode" then return "directory" end
            return nil
        end,
    }
    package.loaded["gota_settings"] = nil
    local Settings = require("gota_settings")
    local settings = Settings:new()
    equal(settings:getDownloadPath(), "gota_articles", "absolute path fallback")
    equal(settings:getSortOrder(), "-created", "invalid sort fallback")
    equal(settings:setDownloadPath("articles\\raindrop"), "articles/raindrop", "nested path")
    settings:setSortOrder("title")
    truthy(settings:save(), "settings save")
    equal(saved.download_path, "articles/raindrop", "saved path")
    equal(saved.sort_order, "title", "saved sort")
    settings:setSortOrder("score")
    equal(settings:getSortOrder(), "-created", "rejected search-only sort")

    package.loaded["ffi/util"] = {
        realpath = function(path)
            if path == "/tmp" then return "/tmp" end
            if path == "/tmp/link" then return "/outside" end
            return nil
        end,
    }
    settings:setDownloadPath("link/folder")
    equal(settings:getFullDownloadPath(), "/tmp/gota_articles/", "symlink escape fallback")
end)

local reader_calls = {}
local ReaderUI = {}
local UIManager = require("ui/uimanager")
package.loaded["document/documentregistry"] = {
    getProvider = function(_, file, include_aux)
        equal(include_aux, nil, "auxiliary provider mode")
        return { provider_name = "CRE" }, false
    end,
}
package.loaded["ui/widget/infomessage"] = {
    new = function(_, options) return options end,
}
package.loaded["apps/reader/readerui"] = ReaderUI
package.loaded["libs/libkoreader-lfs"] = {
    attributes = function() return "file" end,
}
package.loaded["gota_reader"] = nil
local GotaReader = require("gota_reader")

test("ReaderUI open uses the current positional signature", function()
    GotaReader:reset()
    ReaderUI.instance = nil
    ReaderUI.showReader = function(self, file, provider, seamless, forced, after_open)
        reader_calls.show = { file, provider, seamless, forced, after_open }
        self.instance = {
            document = { file = file },
            onHome = function() reader_calls.home = true end,
        }
        after_open()
    end
    local returned = false
    truthy(GotaReader:show({
        path = "/tmp/article.html",
        on_return_callback = function() returned = true end,
    }), "reader open")
    equal(reader_calls.show[1], "/tmp/article.html", "file argument")
    equal(reader_calls.show[3], nil, "seamless argument")
    equal(reader_calls.show[4], false, "forced-provider argument")
    equal(type(reader_calls.show[5]), "function", "after-open argument")
    equal(GotaReader:canReturn(), true, "return availability")
    equal(GotaReader:onReturn(), true, "return action")
    equal(reader_calls.home, true, "ReaderUI:onHome")
    equal(returned, true, "return callback")
end)

test("ReaderUI switch uses the current positional signature", function()
    GotaReader:reset()
    local instance = {
        document = { file = "/tmp/old.html" },
        switchDocument = function(self, file, seamless, after_open, provider, forced)
            reader_calls.switch = { file, seamless, after_open, provider, forced }
            self.document.file = file
            after_open()
        end,
    }
    ReaderUI.instance = instance
    truthy(GotaReader:show({ path = "/tmp/article.html", on_return_callback = noop }))
    equal(reader_calls.switch[1], "/tmp/article.html", "file argument")
    equal(reader_calls.switch[2], nil, "seamless argument")
    equal(type(reader_calls.switch[3]), "function", "after-open argument")
    equal(reader_calls.switch[5], false, "forced-provider argument")
end)

test("ReaderUI provider failure leaves Gota navigation open", function()
    GotaReader:reset()
    ReaderUI.instance = nil
    local registry = package.loaded["document/documentregistry"]
    local original_get_provider = registry.getProvider
    registry.getProvider = function() return nil end
    local closed = false
    local opened = GotaReader:show({
        path = "/tmp/article.html",
        before_open_callback = function() closed = true end,
        on_return_callback = noop,
    })
    registry.getProvider = original_get_provider
    equal(opened, false, "reader result")
    equal(closed, false, "navigation close")
end)

test("plugin init registers Dispatcher actions and settings ownership", function()
    local actions = {}
    package.loaded["dispatcher"] = {
        registerAction = function(_, name, definition) actions[name] = definition end,
    }
    package.loaded["ui/widget/notification"] = { notify = noop }
    package.loaded["ui/network/manager"] = { runWhenOnline = function(_, callback) callback() end }
    package.loaded["ui/widget/container/widgetcontainer"] = {
        extend = function(_, definition) return definition end,
    }
    package.loaded["gota_settings"] = {
        new = function()
            return {
                getSettingsPath = function() return "/settings/gota.lua" end,
                isTokenValid = function() return true end,
            }
        end,
    }
    package.loaded["gota_api"] = { new = function() return {} end }
    package.loaded["gota_content_processor"] = { new = function() return {} end }
    package.loaded["gota_ui_builder"] = { new = function() return {} end }
    package.loaded["gota_dialogs"] = { new = function() return {} end }
    package.loaded["gota_article_manager"] = {
        new = function()
            return { setSettings = noop }
        end,
    }
    package.loaded["main"] = nil

    local Gota = require("main")
    local registered
    Gota.ui = { menu = { registerToMainMenu = function(_, plugin) registered = plugin end } }
    Gota:init()
    equal(registered, Gota, "menu registration")
    equal(Gota.settings_file, "/settings/gota.lua", "settings path")
    equal(Gota.version, "2.2.0", "plugin version")
    truthy(actions.gota_show_articles, "all articles action")
    truthy(actions.gota_search, "search action")
    truthy(actions.gota_collections, "collections action")

    local menu = {}
    Gota:addToMainMenu(menu)
    equal(menu.gota.sorting_hint, "more_tools", "sorting hint")
end)

io.write(string.format("1..%d\n", total))
if failed > 0 then
    io.write(string.format("%d test(s) failed\n", failed))
    os.exit(1)
end
io.write(string.format("%d tests passed\n", total))
