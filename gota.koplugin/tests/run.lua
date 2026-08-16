-- Dependency-free regression tests for the parts of Gota that can run outside
-- KOReader. Run from gota.koplugin with: lua tests/run.lua

package.path = "./?.lua;" .. package.path

local function noop() end
local logger = setmetatable({}, { __index = function() return noop end })

package.preload["logger"] = function() return logger end
package.preload["gettext"] = function() return function(value) return value end end
package.preload["util"] = function()
    local html_entities = {
        amp = "&",
        apos = "'",
        gt = ">",
        lt = "<",
        quot = '"',
    }

    local function decodeNumericEntity(number, base, original)
        local value = tonumber(number, base)
        if value and value >= 0 and value <= 127 then
            return string.char(value)
        end
        return original
    end

    return {
        makePath = function() return true end,
        htmlEscape = function(value)
            return tostring(value or "")
                :gsub("&", "&amp;")
                :gsub("<", "&lt;")
                :gsub(">", "&gt;")
                :gsub('"', "&quot;")
        end,
        htmlEntitiesToUtf8 = function(value)
            value = tostring(value or "")
            value = value:gsub("&#[xX]([%x]+);", function(number)
                return decodeNumericEntity(number, 16, "&#x" .. number .. ";")
            end)
            value = value:gsub("&#(%d+);", function(number)
                return decodeNumericEntity(number, 10, "&#" .. number .. ";")
            end)
            return (value:gsub("&([%a]+);", function(name)
                return html_entities[name] or "&" .. name .. ";"
            end))
        end,
        htmlToPlainTextIfHtml = function(value) return value end,
        stringLower = function(value)
            return value:gsub("É", "é"):lower()
        end,
    }
end
package.preload["datastorage"] = function()
    return {
        getDataDir = function() return "/tmp" end,
        getSettingsDir = function() return "/tmp" end,
    }
end
package.preload["libs/libkoreader-lfs"] = function()
    return { attributes = function() return nil end }
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
    return { new = function(_, options)
        options.switchItemTable = function(self, new_title, new_items, itemnumber, itemmatch)
            self.switch_call = { new_title, new_items, itemnumber, itemmatch }
        end
        return options
    end }
end
package.preload["ui/widget/inputdialog"] = function() return { new = function(_, value) return value end } end
package.preload["ui/widget/textviewer"] = function() return { new = function(_, value) return value end } end
package.preload["ui/network/manager"] = function()
    return { runWhenOnline = function(_, callback) callback() end }
end
package.preload["device"] = function()
    return { screen = { getWidth = function() return 600 end, getHeight = function() return 800 end } }
end
local http = { PROXY = nil }
package.preload["socket.http"] = function() return http end
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
        file_sink = function(file)
            return function(chunk)
                if chunk then return file:write(chunk) end
                return 1
            end
        end,
    }
end
package.preload["json"] = function()
    local function encode(value)
        if type(value) == "boolean" or type(value) == "number" then return tostring(value) end
        if type(value) == "string" then return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' end
        if type(value) == "table" then
            local is_array = #value > 0 or next(value) == nil
            local parts = {}
            if is_array then
                for _, item in ipairs(value) do parts[#parts + 1] = encode(item) end
                return "[" .. table.concat(parts, ",") .. "]"
            end
            for key, item in pairs(value) do parts[#parts + 1] = encode(key) .. ":" .. encode(item) end
            table.sort(parts)
            return "{" .. table.concat(parts, ",") .. "}"
        end
        error("unsupported JSON value")
    end
    return {
        encode = encode,
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

local function hexBytes(value)
    return (value:gsub("%x%x", function(pair)
        return string.char(tonumber(pair, 16))
    end))
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

test("plain text removes hidden page code inside an article", function()
    local processor = ContentProcessor:new()
    local plain = processor:htmlToText([[
        <article>
            <h1>VISIBLE_TITLE</h1>
            <ScRiPt type="module">GOTA_SCRIPT_JUNK</sCrIpT>
            <STYLE media="screen">GOTA_STYLE_JUNK</STYLE>
            <template>GOTA_TEMPLATE_JUNK</template>
            <svg><text>GOTA_SVG_JUNK</text></svg>
            <iframe>GOTA_IFRAME_JUNK</iframe>
            <object>GOTA_OBJECT_JUNK</object>
            <!-- GOTA_COMMENT_JUNK -->
            <p>VISIBLE_BODY</p>
        </article>
    ]])

    contains(plain, "VISIBLE_TITLE", "article title")
    contains(plain, "VISIBLE_BODY", "article body")
    for _, marker in ipairs({
        "GOTA_SCRIPT_JUNK",
        "GOTA_STYLE_JUNK",
        "GOTA_TEMPLATE_JUNK",
        "GOTA_SVG_JUNK",
        "GOTA_IFRAME_JUNK",
        "GOTA_OBJECT_JUNK",
        "GOTA_COMMENT_JUNK",
    }) do
        equal(plain:find(marker, 1, true), nil, marker)
    end
end)

test("plain text preserves code and escaped tag examples", function()
    local processor = ContentProcessor:new()
    local plain = processor:htmlToText([[
        <article>
            <pre><code>if (x &lt; 2) { return "&lt;style&gt;"; }</code></pre>
            <p>VISIBLE_PROSE</p>
        </article>
    ]])

    contains(plain, "if (x < 2)", "code content")
    contains(plain, "<style>", "escaped tag example")
    contains(plain, "VISIBLE_PROSE", "article prose")
end)

test("plain text sanitizes documents without article or main", function()
    local processor = ContentProcessor:new()
    local plain = processor:htmlToText([[
        <body>
            <script>GOTA_SCRIPT_JUNK</script>
            <style>GOTA_STYLE_JUNK</style>
            <template>GOTA_TEMPLATE_JUNK</template>
            <p>VISIBLE_DOCUMENT_BODY</p>
        </body>
    ]])

    contains(plain, "VISIBLE_DOCUMENT_BODY", "document body")
    equal(plain:find("GOTA_SCRIPT_JUNK", 1, true), nil, "script content")
    equal(plain:find("GOTA_STYLE_JUNK", 1, true), nil, "style content")
    equal(plain:find("GOTA_TEMPLATE_JUNK", 1, true), nil, "template content")
end)

test("plain text selects an article smaller than the page shell", function()
    local processor = ContentProcessor:new()
    local shell = string.rep("<p>SHELL_CHROME_WITH_VISIBLE_TEXT</p>", 150)
    local plain = processor:htmlToText(
        "<body><section>" .. shell .. "</section>" ..
        "<ARTICLE><p>ARTICLE_BODY</p></ARTICLE></body>"
    )

    contains(plain, "ARTICLE_BODY", "article body")
    equal(plain:find("SHELL_CHROME_WITH_VISIBLE_TEXT", 1, true), nil, "page shell")
end)

test("plain text chooses the largest visible article", function()
    local processor = ContentProcessor:new()
    local plain = processor:htmlToText([[
        <article><p>SHORT_TEASER</p></article>
        <article><h1>FULL_ARTICLE_TITLE</h1><p>FULL_ARTICLE_BODY_WITH_MORE_TEXT</p></article>
    ]])

    contains(plain, "FULL_ARTICLE_TITLE", "selected article title")
    contains(plain, "FULL_ARTICLE_BODY_WITH_MORE_TEXT", "selected article body")
    equal(plain:find("SHORT_TEASER", 1, true), nil, "short article")
end)

test("plain text falls back to main when no article exists", function()
    local processor = ContentProcessor:new()
    local plain = processor:htmlToText([[
        <body>
            <aside>OUTSIDE_MAIN_CHROME_WITH_VISIBLE_TEXT</aside>
            <MaIn><p>MAIN_ARTICLE_BODY</p></MaIn>
        </body>
    ]])

    contains(plain, "MAIN_ARTICLE_BODY", "main body")
    equal(plain:find("OUTSIDE_MAIN_CHROME_WITH_VISIBLE_TEXT", 1, true), nil, "outside main")
end)

test("plain text decodes numeric HTML entities after stripping tags", function()
    local processor = ContentProcessor:new()
    local plain = processor:htmlToText(
        "<article><p>It&#39;s &#x27;safe&#x27; to show &lt;style&gt;.</p></article>"
    )

    contains(plain, "It's 'safe' to show <style>.", "decoded entities")
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

test("annotated export turns adversarial remote markup into escaped text", function()
    local processor = ContentProcessor:new()
    local malformed = "safe \192\175 RTL مرحبا"
    local html = processor:createReaderHTMLWithNotes({
        title = "Title <unsafe>",
        domain = "example.test",
        link = "javascript:alert(1)\nnext",
        note = '<note & "quoted">',
        cache = { text = [[
            <body onclick="bad"><script>alert(1)</script><style>.x{display:none}</style>
            <iframe src="data:text/html,bad">frame</iframe><object>object</object>
            <svg onload="bad"><text>svg</text></svg><math><mi>x</mi></math>
            <p>Hello <img src=x onerror=bad> &amp; goodbye</p><!-- comment -->
        ]] .. malformed .. "</body>" },
        highlights = {{ text = "<mark>&", note = "one\ntwo", color = "blue" }},
    })
    equal(html:find("<script", 1, true), nil, "remote script tag")
    equal(html:find("<iframe", 1, true), nil, "remote iframe tag")
    equal(html:find("<svg", 1, true), nil, "remote SVG tag")
    equal(html:find("onerror", 1, true), nil, "remote attribute")
    equal(html:find('href="javascript:', 1, true), nil, "unsafe href")
    contains(html, "Hello", "article text")
    contains(html, "&amp; goodbye", "escaped article text")
    contains(html, "&lt;note &amp; &quot;quoted&quot;&gt;", "escaped note")
    contains(html, "&lt;mark&gt;&amp;", "escaped highlight")
    contains(html, "javascript:alert(1)", "URL rendered as text")
    contains(html, "\239\191\189", "malformed UTF-8 replaced")
    contains(html, "</body>", "closed body")
    contains(html, "</html>", "closed document")
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

local ReaderStyles = require("gota_reader_styles")

test("full-reader CSS uses a bounded rem scale", function()
    local css = ReaderStyles.build(nil, {})
    contains(css, "font-size: 1rem !important", "body scale")
    contains(css, "h1 { font-size: 1.6rem !important; }", "h1 scale")
    contains(css, "h2 { font-size: 1.4rem !important; }", "h2 scale")
    contains(css, "h3 { font-size: 1.25rem !important; }", "h3 scale")
    contains(css, "h4, h5, h6 { font-size: 1.1rem !important; }", "h4-h6 scale")
    contains(css, "font-size: 0.9rem !important", "small/table/code scale")
    contains(css, "font-size: 0.8rem !important", "sub/sup scale")
    -- KOReader owns absolute sizing, typeface and colors; Gota only scales.
    equal(css:find("px", 1, true), nil, "absolute pixel size")
    equal(css:find("font-family", 1, true), nil, "typeface override")
    equal(css:find("http", 1, true), nil, "remote reference")
    equal(css:find("color:", 1, true), nil, "color override")
end)

test("full-reader CSS neutralizes inherited sizes before the semantic scale", function()
    local css = ReaderStyles.build(nil, {})
    local universal = css:find("* {\n    font-size: inherit !important;\n}", 1, true)
    truthy(universal, "universal reset present")
    truthy(css:find("h1 { font-size", 1, true) > universal, "reset precedes headings")
end)

test("full-reader CSS preserves code and media presentation", function()
    local css = ReaderStyles.build(nil, {})
    -- Compare exact tag names: a substring check would match "pre" inside the
    -- word "presentation" in the leading comment.
    local selector = css:match("%*/%s*\n([^{]+)%s*{%s*\n?%s*display: none !important;")
    truthy(selector, "hidden element list")
    local hidden = {}
    local hidden_count = 0
    for tag in selector:gmatch("%a+") do
        hidden[tag] = true
        hidden_count = hidden_count + 1
    end
    equal(hidden_count, 14, "hidden element count")

    for _, tag in ipairs({ "nav", "form", "iframe", "object", "script", "button" }) do
        equal(hidden[tag], true, "hidden " .. tag)
    end
    -- Editorial containers must survive: hiding them would lose article text.
    for _, tag in ipairs({ "pre", "code", "table", "img", "header", "footer",
                           "aside", "figure", "svg", "blockquote" }) do
        equal(hidden[tag], nil, "visible " .. tag)
    end
    -- Exactly one display:none rule, so nothing else can hide content.
    local _, rules = css:gsub("display: none", "")
    equal(rules, 1, "single hiding rule")
    contains(css, "max-width: 100% !important", "image fit")
end)

test("full-reader CSS appends user tweaks last", function()
    local css = ReaderStyles.build("p { -gota-user-marker: 1; }", {})
    local user = css:find("-gota-user-marker", 1, true)
    truthy(user, "user CSS present")
    truthy(user > css:find("font-size: 0.8rem", 1, true), "user CSS after Gota CSS")
    -- Whitespace-only tweak text must not append an empty trailing block.
    equal(ReaderStyles.build("   \n\t ", {}), ReaderStyles.build(nil, {}), "blank user CSS")
    equal(ReaderStyles.build({}, {}), ReaderStyles.build(nil, {}), "non-string user CSS")
end)

test("active KOReader font-size tweaks suppress Gota font sizing", function()
    for _, tweak_id in ipairs({ "font_size_all_inherit", "font_size_most_reset" }) do
        local styletweak = {
            enabled = true,
            isTweakEnabled = function(_, id)
                -- Mirrors KOReader's two return values (enabled, globally_enabled).
                return id == tweak_id, false
            end,
        }
        equal(ReaderStyles.hasActiveFontSizeTweak(styletweak), true, "detected " .. tweak_id)
    end

    local skipped = ReaderStyles.build("p { -gota-user-marker: 1; }",
        { skip_font_normalization = true })
    equal(skipped:find("h1 { font-size", 1, true), nil, "no heading scale")
    equal(skipped:find("font-size: 1rem", 1, true), nil, "no body scale")
    -- Cleanup and media rules are independent of the font-size policy.
    contains(skipped, "display: none !important", "cleanup retained")
    contains(skipped, "max-width: 100% !important", "image fit retained")
    contains(skipped, "-gota-user-marker", "user CSS retained")
end)

test("disabled or broken style-tweak objects are contained", function()
    equal(ReaderStyles.hasActiveFontSizeTweak(nil), false, "missing object")
    equal(ReaderStyles.hasActiveFontSizeTweak("styletweak"), false, "non-table object")
    equal(ReaderStyles.hasActiveFontSizeTweak({}), false, "missing method")
    equal(ReaderStyles.hasActiveFontSizeTweak({
        enabled = false,
        isTweakEnabled = function() return true end,
    }), false, "globally disabled tweaks")
    equal(ReaderStyles.hasActiveFontSizeTweak({
        enabled = true,
        isTweakEnabled = function() error("no tweak table") end,
    }), false, "throwing lookup")
    equal(ReaderStyles.hasActiveFontSizeTweak({
        enabled = true,
        isTweakEnabled = function() return false end,
    }), false, "no font-size tweak active")
end)

local OfflineLibrary = require("gota_offline_library")

-- Doubles for the offline library. `entries` maps a file name to its
-- modification time; the iterator also yields "." and ".." like real lfs.dir.
local function offlineLfs(dir, entries)
    return {
        attributes = function(path, field)
            local parent, name = path:match("^(.*)/([^/]+)$")
            if parent ~= dir or entries[name] == nil then return nil end
            if field == "mode" then return "file" end
            if field == "modification" then return entries[name] end
            return nil
        end,
        dir = function(target)
            if target ~= dir then error("unexpected directory: " .. tostring(target)) end
            local names = { ".", ".." }
            for name in pairs(entries) do names[#names + 1] = name end
            table.sort(names)
            local index = 0
            return function()
                index = index + 1
                return names[index]
            end
        end,
    }
end

local function offlineDocSettings(percent, options)
    options = options or {}
    return {
        hasSidecarFile = function()
            if options.throws_has then error("no sidecar access") end
            return not options.no_sidecar
        end,
        open = function()
            if options.throws_open then error("cannot open settings") end
            return {
                readSetting = function(_, key)
                    if options.throws_read then error("cannot read setting") end
                    if key == "percent_finished" then return percent end
                    return nil
                end,
            }
        end,
    }
end

test("offline copies use a deterministic name", function()
    -- Callers pass components already sanitized by ArticleManager, so the name
    -- matches what downloadHTML has always produced and legacy copies are
    -- still recognized.
    equal(OfflineLibrary.canonicalName("123", "Aristotle Quotes"),
        "123_Aristotle Quotes.html", "canonical name")
    -- No collision counter: the path must stay stable so KOReader keeps the
    -- reading position across downloads.
    equal(OfflineLibrary.canonicalName("123", "Aristotle Quotes"),
        OfflineLibrary.canonicalName("123", "Aristotle Quotes"), "stable across calls")
    equal(OfflineLibrary.canonicalName(123, "Title"), "123_Title.html", "numeric id accepted")
    equal(OfflineLibrary.canonicalName("123", nil), nil, "title required")
    equal(OfflineLibrary.canonicalName(nil, "Title"), nil, "id required")
end)

test("offline lookup prefers the canonical path", function()
    local dir = "/tmp/exports"
    local lfs = offlineLfs(dir, { ["123_Title.html"] = 10, ["123_Title_1.html"] = 20 })
    equal(OfflineLibrary.find(dir, 123, "Title", lfs), dir .. "/123_Title.html",
        "canonical wins over a newer legacy copy")
end)

test("offline lookup falls back to legacy numbered copies", function()
    local dir = "/tmp/exports"
    local lfs = offlineLfs(dir, { ["123_Old Title_1.html"] = 10 })
    equal(OfflineLibrary.find(dir, 123, "New Title", lfs), dir .. "/123_Old Title_1.html",
        "legacy copy found after a title change")
    equal(OfflineLibrary.find(dir, 999, "Missing", offlineLfs(dir, {})), nil, "no copy")
end)

test("offline lookup ignores annotated exports", function()
    local dir = "/tmp/exports"
    local lfs = offlineLfs(dir, {
        ["123_Title_notes.html"] = 30,
        ["123_Title_notes_1.html"] = 40,
    })
    equal(OfflineLibrary.find(dir, 123, "Title", lfs), nil,
        "annotated exports are not offline copies")
end)

test("offline lookup does not confuse id prefixes", function()
    local dir = "/tmp/exports"
    local lfs = offlineLfs(dir, { ["123_Other.html"] = 10, ["12_Wanted.html"] = 5 })
    equal(OfflineLibrary.find(dir, 12, "Wanted", lfs), dir .. "/12_Wanted.html", "exact id")
    equal(OfflineLibrary.find(dir, 1, "None", lfs), nil, "shorter id does not match")
end)

test("offline lookup picks the most recently modified candidate", function()
    local dir = "/tmp/exports"
    local lfs = offlineLfs(dir, {
        ["123_A_1.html"] = 10,
        ["123_B_2.html"] = 99,
        ["123_C_3.html"] = 50,
    })
    equal(OfflineLibrary.find(dir, 123, "Absent", lfs), dir .. "/123_B_2.html", "newest copy")
end)

test("offline progress reports a whole percentage", function()
    -- KOReader stores percent_finished as a 0..1 fraction.
    equal(OfflineLibrary.progress("/tmp/a.html", offlineDocSettings(0.4321)), 43, "fraction to percent")
    equal(OfflineLibrary.progress("/tmp/a.html", offlineDocSettings(1)), 100, "finished")
    equal(OfflineLibrary.progress("/tmp/a.html", offlineDocSettings(0)), 0, "just started")
    -- Never overstate progress by rounding up.
    equal(OfflineLibrary.progress("/tmp/a.html", offlineDocSettings(0.999)), 99, "floored")
end)

test("offline progress degrades when document settings fail", function()
    local path = "/tmp/a.html"
    equal(OfflineLibrary.progress(path, nil), nil, "missing module")
    equal(OfflineLibrary.progress(path, offlineDocSettings(nil)), nil, "no stored progress")
    equal(OfflineLibrary.progress(path, offlineDocSettings(0.5, { no_sidecar = true })), nil, "no sidecar")
    equal(OfflineLibrary.progress(path, offlineDocSettings(0.5, { throws_has = true })), nil, "throwing check")
    equal(OfflineLibrary.progress(path, offlineDocSettings(0.5, { throws_open = true })), nil, "throwing open")
    equal(OfflineLibrary.progress(path, offlineDocSettings(0.5, { throws_read = true })), nil, "throwing read")
    equal(OfflineLibrary.progress(path, offlineDocSettings(1.5)), nil, "out of range")
    equal(OfflineLibrary.progress(path, offlineDocSettings(-0.1)), nil, "negative")
end)

local API = require("gota_api")

test("Raindrop search expression quotes tags and embeds type", function()
    equal(
        API.buildSearchExpression("swift", { tag = "coffee beans", type = "Article" }),
        'swift #"coffee beans" type:article'
    )
    equal(API.buildSearchExpression("", { tag = 'a"b\\c' }), [=[#"a\"b\\c"]=])
end)

test("structured search operators are allowlisted and deterministic", function()
    equal(API.buildSearchExpression("", {
        match_or = true,
        important = true,
        exclude_tag = "later",
        exclude_type = "video",
        notag = true,
        file = true,
        reminder = true,
        cache_ready = true,
        created = ">2026-08",
        last_update = "<2026-08-15",
    }), "match:OR -#later -type:video ❤️ notag:true file:true reminder:true " ..
        "cache.status:ready created:>2026-08 lastUpdate:<2026-08-15")
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

test("HTTPS requests bypass and restore KOReader's unsupported HTTP proxy", function()
    local https = require("ssl.https")
    local original_request = https.request
    local configured_proxy = "http://proxy.example:3128"
    local request_saw_proxy
    http.PROXY = configured_proxy
    https.request = function(request)
        request_saw_proxy = http.PROXY
        request.sink('{"ok":true}')
        request.sink(nil)
        return 1, 200, {}, "HTTP/1.1 200 OK"
    end

    local api = API:new({ getToken = function() return "secret" end })
    local result, err = api:makeRequestWithRetry("/user")

    https.request = original_request
    equal(err, nil, "request error")
    equal(result.ok, true, "request result")
    equal(request_saw_proxy, nil, "proxy during HTTPS request")
    equal(http.PROXY, configured_proxy, "restored proxy")
    http.PROXY = nil
end)

test("HTTPS request exceptions still restore KOReader's HTTP proxy", function()
    local https = require("ssl.https")
    local original_request = https.request
    local configured_proxy = "http://proxy.example:3128"
    http.PROXY = configured_proxy
    https.request = function()
        error("simulated TLS failure")
    end

    local api = API:new({ getToken = function() return "secret" end })
    local result, err = api:makeRequestWithRetry("/user", "GET", nil, 1)

    https.request = original_request
    equal(result, nil, "request result")
    contains(err, "simulated TLS failure", "request error")
    equal(http.PROXY, configured_proxy, "restored proxy")
    http.PROXY = nil
end)

test("bounded sink aborts only after crossing the configured limit", function()
    local chunks = {}
    local sink, state = API.boundedSink(function(chunk)
        if chunk then chunks[#chunks + 1] = chunk end
        return 1
    end, 5)
    equal(sink("12"), 1, "first chunk")
    equal(sink("345"), 1, "exact limit")
    local ok, err = sink("6")
    equal(ok, nil, "oversized result")
    equal(err, API.RESPONSE_TOO_LARGE, "oversized error")
    equal(state.received, 6, "received bytes")
    equal(table.concat(chunks), "12345", "forwarded content")
end)

test("permanent copy file mode streams atomically and cleans oversized parts", function()
    local https = require("ssl.https")
    local original_request = https.request
    local target = "/tmp/gota_test_cache_download.html"
    os.remove(target)
    os.remove(target .. ".part")
    https.request = function(request)
        request.sink("12")
        request.sink("345")
        request.sink(nil)
        return 1, 200, { ["Content-Encoding"] = "identity" }, "HTTP/1.1 200 OK"
    end
    local api = API:new({ getToken = function() return "secret" end })
    local result, err = api:downloadRaindropCache(7, target, 5)
    equal(err, nil, "download error")
    equal(result, target, "download path")
    local file = assert(io.open(target, "rb"))
    equal(file:read("*a"), "12345", "download contents")
    file:close()
    os.remove(target)

    https.request = function(request)
        local ok, sink_error = request.sink("123456")
        return ok, sink_error, {}, ""
    end
    local oversized, oversized_error = api:downloadRaindropCache(7, target, 5)
    https.request = original_request
    equal(oversized, nil, "oversized result")
    contains(oversized_error, "size limit", "oversized error")
    equal(io.open(target .. ".part", "rb"), nil, "temporary cleanup")
end)

test("gzip cache responses are decoded for text and atomic file modes", function()
    local https = require("ssl.https")
    local original_request = https.request
    local expected = "<html><body>compressed copy</body></html>"
    local compressed = hexBytes(
        "1f8b0800000000000003b3c928c9cdb1b349ca4fa9b44bcecf2d284a2d2e4e4d" ..
        "5148ce2fa8b4d1078bdae883950000c741952029000000"
    )
    https.request = function(request)
        request.sink(compressed)
        request.sink(nil)
        return 1, 200, { ["Content-Encoding"] = "gzip" }, "HTTP/1.1 200 OK"
    end

    local api = API:new({ getToken = function() return "secret" end })
    local text_result, text_error = api:getRaindropCache(7, 1024)
    equal(text_error, nil, "text error")
    equal(text_result, expected, "decoded text")

    local target = "/tmp/gota_test_gzip_download.html"
    os.remove(target)
    os.remove(target .. ".part")
    os.remove(target .. ".part.decoded")
    local file_result, file_error = api:downloadRaindropCache(7, target, 1024)
    https.request = original_request
    equal(file_error, nil, "file error")
    equal(file_result, target, "file result")
    local file = assert(io.open(target, "rb"))
    equal(file:read("*a"), expected, "decoded file")
    file:close()
    os.remove(target)
    equal(io.open(target .. ".part", "rb"), nil, "compressed part cleanup")
    equal(io.open(target .. ".part.decoded", "rb"), nil, "decoded part cleanup")
end)

test("gzip expansion respects the decompressed limit and cleans partial files", function()
    local https = require("ssl.https")
    local original_request = https.request
    local compressed = hexBytes("1f8b08000000000000034b4ca43d0000647a70af64000000")
    https.request = function(request)
        request.sink(compressed)
        request.sink(nil)
        return 1, 200, { ["content-encoding"] = "gzip" }, "HTTP/1.1 200 OK"
    end

    local target = "/tmp/gota_test_gzip_limit.html"
    os.remove(target)
    os.remove(target .. ".part")
    os.remove(target .. ".part.decoded")
    local api = API:new({ getToken = function() return "secret" end })
    local result, err = api:downloadRaindropCache(7, target, 30)
    https.request = original_request
    equal(result, nil, "oversized decoded result")
    contains(err, "Decompressed response exceeds", "decoded limit error")
    equal(io.open(target, "rb"), nil, "target cleanup")
    equal(io.open(target .. ".part", "rb"), nil, "compressed cleanup")
    equal(io.open(target .. ".part.decoded", "rb"), nil, "decoded cleanup")
end)

test("unsupported cache encodings report the received value", function()
    local https = require("ssl.https")
    local original_request = https.request
    https.request = function(request)
        request.sink("encoded payload")
        request.sink(nil)
        return 1, 200, { ["Content-Encoding"] = "br" }, "HTTP/1.1 200 OK"
    end
    local api = API:new({ getToken = function() return "secret" end })
    local result, err = api:getRaindropCache(7, 1024)
    https.request = original_request
    equal(result, nil, "unsupported result")
    contains(err, "Unsupported server content encoding: br", "unsupported error")
end)

test("gzip signatures are decoded when a CDN omits the encoding header", function()
    local https = require("ssl.https")
    local original_request = https.request
    local expected = "<html><body>compressed copy</body></html>"
    local compressed = hexBytes(
        "1f8b0800000000000003b3c928c9cdb1b349ca4fa9b44bcecf2d284a2d2e4e4d" ..
        "5148ce2fa8b4d1078bdae883950000c741952029000000"
    )
    https.request = function(request)
        request.sink(compressed)
        request.sink(nil)
        return 1, 200, {}, "HTTP/1.1 200 OK"
    end
    local api = API:new({ getToken = function() return "secret" end })
    local result, err = api:getRaindropCache(7, 1024)
    https.request = original_request
    equal(err, nil, "signature decode error")
    equal(result, expected, "signature decoded response")
end)

test("mutating requests never retry automatically", function()
    local api = API:new({ getToken = function() return "secret" end })
    local attempts = 0
    function api:makeRequest()
        attempts = attempts + 1
        return nil, "temporary", 503, {}
    end
    local result = api:makeRequestWithRetry("/raindrop/7", "PUT", "{}", 3)
    equal(result, nil, "result")
    equal(attempts, 1, "attempt count")
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

test("collection structure degrades optional sources without mutating roots", function()
    local root_items = { { _id = 1 } }
    local api = API:new({ getToken = function() return "secret" end })
    function api:getRootCollections() return { items = root_items } end
    function api:getUser() return nil, "user unavailable" end
    function api:getChildCollections() return nil, "children unavailable" end
    local structure, err = api:getCollectionStructure()
    equal(err, nil, "error")
    equal(structure.roots, root_items, "root array")
    equal(#structure.groups, 0, "groups")
    equal(#structure.children, 0, "children")
    equal(#structure.warnings, 2, "warnings")
end)

test("search scopes collection and ranks only textual queries", function()
    local api = API:new({ getToken = function() return "secret" end })
    local endpoints = {}
    function api:cachedRequest(endpoint)
        endpoints[#endpoints + 1] = endpoint
        return { items = {} }
    end
    api:searchRaindrops("kindle", 0, 25, nil, nil,
        { collection_id = 42, nested = true })
    contains(endpoints[1], "/raindrops/42?", "collection endpoint")
    contains(endpoints[1], "nested=true", "nested")
    contains(endpoints[1], "sort=score", "relevance")
    api:searchRaindrops("", 0, 25, { notag = true })
    contains(endpoints[2], "search=notag%3Atrue", "filter expression")
    contains(endpoints[2], "sort=-created", "filter sort")
    equal(endpoints[2]:find("sort=score", 1, true), nil, "no relevance sort")
end)

test("filters use one popularity-sorted endpoint", function()
    local api = API:new({ getToken = function() return "secret" end })
    local endpoint
    function api:cachedRequest(value) endpoint = value return { tags = {}, types = {} } end
    local response = api:getFilters(12)
    truthy(response, "response")
    equal(endpoint, "/filters/12?tagsSort=-count", "filters endpoint")
end)

test("highlights use open pagination endpoints without count", function()
    local api = API:new({ getToken = function() return "secret" end })
    local endpoint
    function api:cachedRequest(value) endpoint = value return { items = {} } end
    truthy(api:getHighlights(nil, 0, 25), "global highlights")
    equal(endpoint, "/highlights?perpage=25&page=0", "global endpoint")
    truthy(api:getHighlights(42, 1, 25), "collection highlights")
    equal(endpoint, "/highlights/42?perpage=25&page=1", "collection endpoint")
end)

test("bookmark updates are allowlisted and Trash refuses permanent deletion", function()
    local api = API:new({ getToken = function() return "secret" end })
    local calls = {}
    function api:makeRequestWithRetry(endpoint, method, body)
        calls[#calls + 1] = { endpoint = endpoint, method = method, body = body }
        if method == "DELETE" then return { result = true } end
        return { result = true, item = { _id = 7, important = true } }
    end
    local updated = api:updateRaindrop(7, { important = true })
    truthy(updated and updated.item, "updated item")
    equal(calls[1].method, "PUT", "update method")
    contains(calls[1].body, '"important":true', "update body")
    truthy(api:updateRaindrop(7, { tags = {} }), "clear tags")
    contains(calls[2].body, '"tags":[]', "empty tags array")
    local rejected = api:updateRaindrop(7, { title = "not allowed" })
    equal(rejected, nil, "unknown field")
    equal(api:updateRaindrop(7, { tags = { unexpected = "tag" } }), nil, "non-list tags")
    equal(#calls, 2, "no rejected request")
    equal(api:trashRaindrop(7, -99), nil, "Trash safety")
    equal(#calls, 2, "no permanent DELETE")
    truthy(api:trashRaindrop(7, 42), "move to Trash")
    equal(calls[3].method, "DELETE", "Trash method")
end)

test("raindrop list accepts an undocumented missing count", function()
    local api = API:new({ getToken = function() return "secret" end })
    function api:cachedRequest()
        return { result = true, items = {} }
    end
    local result, err = api:getRaindrops(0, 0, 25, "-created")
    equal(err, nil, "error")
    truthy(result and result.items, "result")
    equal(result.count, nil, "optional count")
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

test("cache metadata preflight prevents oversized memory requests", function()
    local calls = 0
    local notifications = 0
    local manager = ArticleManager:new({
        getRaindropCache = function() calls = calls + 1 return "unexpected" end,
    }, {}, {}, {
        showProgress = noop,
        hideProgress = noop,
        notify = function() notifications = notifications + 1 end,
    })
    manager:setSettings({ getMaxCacheMemoryBytes = function() return 1024 end })
    local item, err = manager:loadCacheContent(
        { _id = 7, cache = { status = "ready", size = 1025 } })
    equal(calls, 0, "network calls")
    equal(item.cache.text, nil, "HTML")
    contains(err, "configured limit", "specific size error")
    equal(notifications, 0, "manager notifications")
end)

test("explicit cache retries bypass a remembered download error", function()
    local calls = 0
    local manager = ArticleManager:new({
        getRaindropCache = function()
            calls = calls + 1
            if calls == 1 then return nil, "temporary cache failure" end
            return "<html>recovered</html>"
        end,
    }, {}, {}, { showProgress = noop, hideProgress = noop, notify = noop })
    manager:setSettings({ getMaxCacheMemoryBytes = function() return 1024 end })

    local item, first_error = manager:loadCacheContent(
        { _id = 7, cache = { status = "ready", size = 42 } })
    equal(first_error, "temporary cache failure", "first error")
    equal(calls, 1, "first attempt")

    local unchanged, remembered_error = manager:loadCacheContent(item)
    equal(unchanged, item, "remembered item")
    equal(remembered_error, "temporary cache failure", "remembered error")
    equal(calls, 1, "automatic retry suppressed")

    local recovered, retry_error = manager:loadCacheContent(item, { retry = true })
    equal(retry_error, nil, "retry error")
    equal(recovered.cache.text, "<html>recovered</html>", "retry content")
    equal(calls, 2, "explicit retry")
end)

test("reader precondition failure keeps the current menu open", function()
    local closed = false
    local notifications = 0
    local manager = ArticleManager:new({
        downloadRaindropCache = function() return nil, "download failed" end,
    }, {}, {}, {
        showProgress = noop,
        hideProgress = noop,
        notify = function() notifications = notifications + 1 end,
    })
    local opened = manager:openInReader(
        { _id = 7, cache = { status = "ready", size = 42 } },
        function() closed = true end,
        noop
    )
    equal(opened, false, "reader result")
    equal(closed, false, "menu close")
    equal(notifications, 1, "notification count")
end)

test("ArticleManager requests style normalization for full reader", function()
    local shown, requested_bytes, requested_path
    local manager = ArticleManager:new({
        downloadRaindropCache = function(_, _, path, max_bytes)
            requested_path = path
            requested_bytes = max_bytes
            return path
        end,
    }, {}, {
        show = function(_, options) shown = options; return true end,
    }, {
        showProgress = noop,
        hideProgress = noop,
        notify = noop,
    })
    manager:setSettings({
        getMaxCacheFileBytes = function() return 512 * 1024 * 1024 end,
    })
    local raindrop = { _id = 7, cache = { status = "ready", size = 42, text = "<html>" } }
    equal(manager:openInReader(raindrop, nil, noop), true, "reader result")
    equal(shown.normalize_styles, true, "normalization requested")
    equal(shown.path, requested_path, "reader opens the downloaded file")
    equal(shown.path, manager:getReaderCachePath(7), "managed reader path")
    -- The presentation policy must not disturb the streaming download budget.
    equal(requested_bytes, 512 * 1024 * 1024, "configured file limit unchanged")
    equal(raindrop.cache.text, nil, "in-memory copy released")
end)

test("reader cache files are isolated from permanent exports", function()
    local manager = ArticleManager:new({}, {}, {}, {
        showProgress = noop,
        hideProgress = noop,
        notify = noop,
    })
    equal(manager:getReaderCachePath(42), "/tmp/cache/gota/raindrop_42.html")
end)

test("reader cleanup is confined, idempotent, and preserves sidecars", function()
    local manager = ArticleManager:new({}, {}, {}, {
        showProgress = noop, hideProgress = noop, notify = noop,
    })
    local cache_dir = "/tmp/cache/gota"
    local active = cache_dir .. "/raindrop_2.html"
    local files = {
        [cache_dir .. "/raindrop_1.html"] = true,
        [cache_dir .. "/raindrop_1.html.part"] = true,
        [active] = true,
        [cache_dir .. "/raindrop_3.html.part"] = true,
        [cache_dir .. "/raindrop_1.sdr"] = true,
        [cache_dir .. "/other.html"] = true,
    }
    local names = { ".", "..", "raindrop_1.html", "raindrop_1.html.part",
        "raindrop_2.html", "raindrop_3.html.part", "raindrop_1.sdr", "other.html" }
    local history, removed = {}, {}
    local old_lfs = package.loaded["libs/libkoreader-lfs"]
    local old_ffi = package.loaded["ffi/util"]
    local old_history = package.loaded["readhistory"]
    local old_remove = os.remove
    package.loaded["ffi/util"] = { realpath = function(path) return path end }
    package.loaded["readhistory"] = {
        removeItemByPath = function(_, path) history[#history + 1] = path end,
    }
    package.loaded["libs/libkoreader-lfs"] = {
        attributes = function(path, attribute)
            if path == cache_dir and attribute == "mode" then return "directory" end
            if files[path] then return "file" end
            return nil
        end,
        dir = function(path)
            equal(path, cache_dir, "cleanup directory")
            local index = 0
            return function()
                index = index + 1
                return names[index]
            end
        end,
    }
    os.remove = function(path)
        removed[#removed + 1] = path
        files[path] = nil
        return true
    end

    local ok, err = pcall(function()
        truthy(manager:isManagedReaderPath(cache_dir .. "/raindrop_1.html"), "managed html")
        truthy(manager:isManagedReaderPath(cache_dir .. "/raindrop_1.html.part"), "managed part")
        equal(manager:isManagedReaderPath(cache_dir .. "/raindrop_bad.html"), false, "invalid id")
        equal(manager:isManagedReaderPath("/tmp/gota_articles/raindrop_1.html"), false, "export")
        equal(manager:isManagedReaderPath(cache_dir .. "/raindrop_1.sdr"), false, "sidecar")

        local removed_count, warnings = manager:cleanupOrphanReaderFiles(active)
        equal(removed_count, 3, "orphan entries")
        equal(#warnings, 0, "cleanup warnings")
        equal(files[active], true, "active document preserved")
        equal(files[cache_dir .. "/raindrop_1.sdr"], true, "sidecar preserved")
        equal(files[cache_dir .. "/other.html"], true, "foreign file preserved")
        equal(history[1], cache_dir .. "/raindrop_1.html", "history path")

        truthy(manager:cleanupManagedReaderPath(cache_dir .. "/raindrop_1.html"), "idempotent cleanup")
    end)
    os.remove = old_remove
    package.loaded["libs/libkoreader-lfs"] = old_lfs
    package.loaded["ffi/util"] = old_ffi
    package.loaded["readhistory"] = old_history
    if not ok then error(err, 0) end
end)

test("article reload forces metadata without downloading permanent HTML", function()
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
    equal(cache_calls, 0, "cache calls")
    equal(reloaded.cache.text, nil, "deferred HTML")
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

test("collection structure follows group roots and descending child sort", function()
    local flattened = UIBuilder.flattenCollectionStructure({
        groups = {
            { _id = 2, title = "Later", sort = 20, collections = { 2 } },
            { _id = 1, title = "First", sort = 10, collections = { 1 } },
        },
        roots = { { _id = 1, title = "Root A" }, { _id = 2, title = "Root B" },
            { _id = 9, title = "Ungrouped" } },
        children = {
            { _id = 12, title = "Low", sort = 1, parent = { ["$id"] = 1 } },
            { _id = 11, title = "High", sort = 9, parent = { ["$id"] = 1 } },
        },
    }, {})
    equal(flattened[1].title, "First", "first group")
    equal(flattened[2].collection.title, "Root A", "first root")
    equal(flattened[3].collection.title, "High", "high child")
    equal(flattened[4].collection.title, "Low", "low child")
    equal(flattened[5].title, "Later", "second group")
    equal(flattened[#flattened].collection.title, "Ungrouped", "ungrouped root")
end)

test("collection destination mode expands remotely hidden groups", function()
    local structure = {
        groups = { { _id = 1, title = "Hidden", hidden = true, collections = { 10 } } },
        roots = { { _id = 10, title = "Destination" } }, children = {},
    }
    local collapsed = UIBuilder.flattenCollectionStructure(structure, {})
    equal(#collapsed, 1, "collapsed entries")
    local expanded = UIBuilder.flattenCollectionStructure(structure, {}, true)
    equal(expanded[2].collection.title, "Destination", "expanded destination")
end)

test("open pagination works without a documented total", function()
    local builder = UIBuilder:new()
    local items = {}
    local page_items = {}
    for index = 1, 25 do page_items[index] = { _id = index } end
    builder:addPagination(items, { items = page_items }, 0, 25, noop)
    local found_next, found_last = false, false
    for _, item in ipairs(items) do
        if item.text == "Raindrop: next page" then found_next = true end
        if item.text == "Raindrop: last page" then found_last = true end
    end
    equal(found_next, true, "next page")
    equal(found_last, false, "no last page")
end)

test("article rows are linear, descriptive, and carry stable identity", function()
    local builder = UIBuilder:new()
    local items = builder:buildRaindropItems({ items = {{
        _id = 42,
        title = "A\nlong title",
        domain = "example.test",
        excerpt = "first\nsecond",
        type = "article",
        important = true,
        note = "note",
        highlights = {{ text = "one" }},
        cache = { status = "ready" },
    }}}, noop)
    equal(items[1].text:find("\n", 1, true), nil, "no forced line break")
    contains(items[1].text, "A long title — example.test · first second", "linear content")
    contains(items[1].text, "Favorite · Note · 1 highlights · Web copy", "full statuses")
    equal(items[1].mandatory, "Art.", "type only")
    equal(items[1].gota_raindrop_id, "42", "stable identity")
end)

test("remote pagination is repeated above and below with zero-based callbacks", function()
    local builder = UIBuilder:new()
    local pages = {}
    local rows = {{ text = "row" }}
    local subtitle = builder:addPagination(rows, { count = 200, items = {{}} }, 4, 25,
        function(page) pages[#pages + 1] = page end)
    equal(rows[1].text, "Raindrop page 5 of 8", "top status")
    contains(subtitle, "101–125 of 200 articles", "range subtitle")
    local first, previous, next_page, last
    local next_count = 0
    for _, item in ipairs(rows) do
        if item.text == "Raindrop: first page" then first = item end
        if item.text == "Raindrop: previous page" then previous = item end
        if item.text == "Raindrop: next page" then
            next_page = item
            next_count = next_count + 1
        end
        if item.text == "Raindrop: last page" then last = item end
    end
    equal(next_count, 2, "top and bottom next")
    first.callback()
    previous.callback()
    next_page.callback()
    last.callback()
    equal(table.concat(pages, ","), "0,3,5,7", "remote indices")
end)

test("menu focus uses public item matching and tolerates absent IDs", function()
    local builder = UIBuilder:new()
    local menu = builder:createMenu("Articles", {{ gota_raindrop_id = "7" }}, {
        subtitle = "1–1 of 1 articles",
        focus_raindrop_id = 7,
        items_max_lines = 2,
        multilines_forced = true,
    })
    equal(menu.subtitle, "1–1 of 1 articles", "subtitle")
    equal(menu.items_max_lines, 2, "line limit")
    equal(menu.switch_call[3], 0, "public focus start")
    equal(menu.switch_call[4].gota_raindrop_id, "7", "focus match")
    local absent = builder:createMenu("Articles", {}, { focus_raindrop_id = 99 })
    equal(absent.switch_call[4].gota_raindrop_id, "99", "absent match remains safe")
end)

test("original-copy action exists only for ready cache metadata", function()
    local builder = UIBuilder:new()
    local callback = noop
    local ready = builder:buildArticleMenu({ cache = { status = "ready" } }, true, {
        save_html = callback,
    })
    local unavailable = builder:buildArticleMenu({}, false, { save_html = callback })
    local ready_action, unavailable_action
    for _, item in ipairs(ready) do if item.text == "Save original copy" then ready_action = item end end
    for _, item in ipairs(unavailable) do
        if item.text == "Save original copy" then unavailable_action = item end
    end
    equal(ready_action.callback, callback, "direct callback")
    equal(unavailable_action, nil, "unavailable action")
end)

test("active search summary covers scope, mode, and every operator", function()
    local summary = UIBuilder.buildActiveFilterSummary({
        term = "swift", tag = "reading", type = "article", match = "any",
        quick = { important = true, notag = true, file = true, reminder = true, cache_ready = true },
        more = { exclude_tag = "later", exclude_type = "video",
            created = ">2026-01", last_update = "<2026-08-15" },
    }, { collection_name = "Research", nested = true }, "-created")
    contains(summary, "Scope: Research + subcollections", "scope")
    contains(summary, "Sort: newest first", "sort")
    contains(summary, "Text: swift", "term")
    contains(summary, "Favorites", "favorite")
    contains(summary, "Web copy ready", "web copy")
    contains(summary, "Exclude tag: later", "exclusion")
    contains(summary, "Created: >2026-01", "created")
    contains(summary, "Match: any", "mode")
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
        if item.text == "Export with notes & highlights" then export_item = item end
    end
    truthy(export_item, "export item")
    equal(export_item.enabled, true, "export enabled")
end)

test("ready cache keeps an explicit metadata reload after a bounded-download error", function()
    local menu = UIBuilder:new():buildArticleMenu(
        { cache = { status = "ready" } }, true, { reload = noop })
    local reload_item
    for _, item in ipairs(menu) do
        if item.text == "Reload article metadata" then reload_item = item end
    end
    truthy(reload_item and reload_item.callback, "reload action")
end)

local Dialogs = require("gota_dialogs")

test("debug information reports TLS limits without exposing token material", function()
    local viewer = Dialogs:new():showDebugInfo({
        token_status = "configured",
        settings_file = "/tmp/gota.lua",
        file_exists = true,
        file_size = 12,
        secret = "do-not-show",
        max_cache_memory_mib = 4,
        max_cache_file_mib = 32,
    }, "https://api.raindrop.io/rest/v1", {
        encrypted = true,
        peer_authenticated = false,
        hostname_verified = false,
    })
    equal(viewer.text:find("do-not-show", 1, true), nil, "secret hidden")
    contains(viewer.text, "TLS encryption: available", "encryption status")
    contains(viewer.text, "Remote TLS authentication: not available", "authentication limit")
end)

test("token removal confirmation explains revocation and Cancel is inert", function()
    package.loaded["ui/widget/buttondialog"] = {
        new = function(_, options) return options end,
    }
    local removed = 0
    local dialog = Dialogs:new():confirmRemoveToken(function() removed = removed + 1 end)
    contains(dialog.title, "does not revoke", "remote revocation warning")
    dialog.buttons[1][1].callback()
    equal(removed, 0, "cancel")
end)

test("tag editing trims and de-duplicates Unicode tags case-insensitively", function()
    local tags = Dialogs.normalizeTagsInput("  Lectura  \nlectura\nCAFÉ\ncafé\n漢字\n\n")
    equal(#tags, 3, "tag count")
    equal(tags[1], "Lectura", "first spelling")
    equal(tags[2], "CAFÉ", "Unicode spelling")
    equal(tags[3], "漢字", "CJK tag")
end)

test("article information exposes documented e-reader metadata safely", function()
    local info = ContentProcessor:new():formatArticleInfo({
        title = "Metadata", important = true, broken = true,
        lastUpdate = "2026-08-15T12:34:56.000Z",
        reminder = { data = "2026-08-16T10:00:00.000Z" },
        file = { name = "book.epub", type = "application/epub+zip", size = 0 },
        creatorRef = { fullName = "Reader" },
        cache = { status = "ready", created = "2026-08-14T01:02:03.000Z" },
    })
    contains(info, "Warning: this link is marked as broken", "broken")
    contains(info, "Favorite: Yes", "favorite")
    contains(info, "Updated: 2026-08-15 12:34:56", "updated")
    contains(info, "Reminder: 2026-08-16 10:00:00", "reminder")
    contains(info, "File: book.epub", "file")
    contains(info, "File size: 0 B", "zero size")
    contains(info, "Permanent copy created: 2026-08-14 01:02:03", "cache date")
end)

test("settings normalize manipulated paths and unsupported sort values", function()
    local stored = {
        token = "secret",
        download_path = "/outside/data",
        sort_order = "score",
    }
    local saved = {}
    local fail_flush = false
    package.loaded["luasettings"] = {
        open = function()
            return {
                readSetting = function(_, key) return stored[key] end,
                saveSetting = function(_, key, value) saved[key] = value end,
                flush = function()
                    if fail_flush then error("simulated flush failure") end
                end,
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
    equal(settings:setDownloadPath("articles/long reads"), "articles/long reads", "spaces preserved")
    local rejected_path, rejected_error = settings:setDownloadPath("../outside")
    equal(rejected_path, nil, "traversal rejected")
    contains(rejected_error, "cannot contain '..'", "traversal reason")
    equal(settings:getDownloadPath(), "articles/long reads", "invalid input does not replace current path")
    equal(settings:setDownloadPath("articles/./inside"), nil, "dot segment rejected")
    equal(settings:setDownloadPath("articles\\reader:notes"), "articles/reader_notes",
        "sanitizer result returned")
    settings:setDownloadPath("articles/raindrop")
    settings:setSortOrder("title")
    truthy(settings:save(), "settings save")
    equal(saved.download_path, "articles/raindrop", "saved path")
    equal(saved.sort_order, "title", "saved sort")
    settings:setSortOrder("score")
    equal(settings:getSortOrder(), "-created", "rejected search-only sort")
    settings:setSortOrder("domain")
    equal(settings:getSortOrder(), "domain", "domain sort")
    equal(settings:getMaxCacheMemoryBytes(), 16 * 1024 * 1024, "memory default")
    equal(settings:getMaxCacheFileBytes(), 128 * 1024 * 1024, "file default")
    equal(settings:setMaxCacheMemoryBytes(64 * 1024 * 1024),
        64 * 1024 * 1024, "modern memory preset")
    equal(settings:setMaxCacheFileBytes(512 * 1024 * 1024),
        512 * 1024 * 1024, "modern file preset")
    equal(settings:setMaxCacheMemoryBytes(3 * 1024 * 1024), nil, "invalid memory preset")
    truthy(settings:clearToken(), "clear token")
    equal(settings:getToken(), "", "cleared token")
    equal(saved.token, "", "saved empty token")
    settings:setToken("restored-secret")
    fail_flush = true
    local cleared, clear_error = settings:clearToken()
    equal(cleared, false, "failed clear")
    contains(clear_error, "simulated flush failure", "clear error")
    equal(settings:getToken(), "restored-secret", "token restored in memory")
    fail_flush = false

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

-- Doubles for the pre-render stage. ReaderUI is never instantiated: the
-- contract under test is which fields Gota reads and which it must not touch.
local function styleReaderDouble(path, options)
    options = options or {}
    local calls = { style = {} }
    local document = {
        file = path,
        default_css = "./data/fallback.css",
        setStyleSheet = function(_, base, appended)
            calls.style[#calls.style + 1] = { base = base, appended = appended }
        end,
        setEmbeddedStyleSheet = function()
            error("normalization must not change embedded style settings")
        end,
    }
    if options.no_style_api then
        document.setStyleSheet = nil
    elseif options.throwing_style then
        document.setStyleSheet = function() error("crengine failure") end
    end
    return {
        document = document,
        typeset = options.typeset ~= false
            and { css = options.base_css or "./data/epub.css" } or nil,
        styletweak = options.styletweak,
    }, calls
end

-- Arms the singleton through the public entry point instead of writing fields.
local function armGotaReader(path, normalize, defer_after_open)
    local pending
    GotaReader:reset()
    ReaderUI.instance = nil
    ReaderUI.showReader = function(self, file, _, _, _, after_open)
        self.instance = { document = { file = file } }
        if defer_after_open then pending = after_open else after_open() end
    end
    local opened = GotaReader:show({
        path = path,
        normalize_styles = normalize,
        on_return_callback = noop,
    })
    return opened, pending
end

test("GotaReader applies normalization to the pending matching path", function()
    truthy(armGotaReader("/tmp/article.html", true), "reader open")
    equal(GotaReader:shouldNormalize("/tmp/article.html"), true, "pending normalization")

    local reader_ui, calls = styleReaderDouble("/tmp/article.html", {
        styletweak = {
            enabled = true,
            getCssText = function() return "p { -gota-user-marker: 1; }" end,
            isTweakEnabled = function() return false, false end,
        },
    })
    equal(GotaReader:applyStyleNormalization(reader_ui), true, "normalization applied")
    equal(#calls.style, 1, "single stylesheet call")
    contains(calls.style[1].appended, "h4, h5, h6 { font-size: 1.1rem !important; }",
        "bounded heading scale")
    contains(calls.style[1].appended, "-gota-user-marker", "user tweaks appended last")
end)

test("GotaReader keeps the current base stylesheet", function()
    armGotaReader("/tmp/article.html", true)
    local reader_ui, calls = styleReaderDouble("/tmp/article.html",
        { base_css = "./data/html5.css" })
    equal(GotaReader:applyStyleNormalization(reader_ui), true, "normalization applied")
    equal(calls.style[1].base, "./data/html5.css", "user-selected base sheet reused")

    -- default_css is only a fallback for a ReaderTypeset without a sheet.
    local fallback_ui, fallback_calls = styleReaderDouble("/tmp/article.html",
        { typeset = false })
    equal(GotaReader:applyStyleNormalization(fallback_ui), true, "fallback applied")
    equal(fallback_calls.style[1].base, "./data/fallback.css", "document default sheet")
end)

test("GotaReader does not change embedded stylesheet settings", function()
    armGotaReader("/tmp/article.html", true)
    local reader_ui, calls = styleReaderDouble("/tmp/article.html")
    local original_open, original_remove, original_rename = io.open, os.remove, os.rename
    io.open = function() error("normalization must not open files") end
    os.remove = function() error("normalization must not remove files") end
    os.rename = function() error("normalization must not rename files") end
    local ok, applied = pcall(GotaReader.applyStyleNormalization, GotaReader, reader_ui)
    io.open, os.remove, os.rename = original_open, original_remove, original_rename
    truthy(ok, "no filesystem access during normalization")
    equal(applied, true, "normalization applied")
    equal(#calls.style, 1, "stylesheet installed once")
end)

test("GotaReader ignores unrelated documents", function()
    armGotaReader("/tmp/article.html", true)
    local other_ui, other_calls = styleReaderDouble("/tmp/library-book.epub")
    local applied, reason = GotaReader:applyStyleNormalization(other_ui)
    equal(applied, false, "unrelated document result")
    contains(reason, "not the pending", "unrelated document reason")
    equal(#other_calls.style, 0, "no stylesheet call")

    -- Opening a Gota path without the explicit request stays untouched.
    armGotaReader("/tmp/article.html", nil)
    equal(GotaReader:shouldNormalize("/tmp/article.html"), false, "opt-in required")
    local plain_ui, plain_calls = styleReaderDouble("/tmp/article.html")
    equal(GotaReader:applyStyleNormalization(plain_ui), false, "no normalization")
    equal(#plain_calls.style, 0, "no stylesheet call")

    -- Closing the document retires the pending request.
    armGotaReader("/tmp/article.html", true)
    GotaReader:onReaderUIClose("/tmp/article.html")
    equal(GotaReader:shouldNormalize("/tmp/article.html"), false, "cleared on close")
end)

test("GotaReader contains missing or throwing CREngine style APIs", function()
    armGotaReader("/tmp/article.html", true)
    local applied, reason = GotaReader:applyStyleNormalization(
        styleReaderDouble("/tmp/article.html", { no_style_api = true }))
    equal(applied, nil, "missing API result")
    contains(reason, "stylesheet API is unavailable", "missing API reason")

    applied, reason = GotaReader:applyStyleNormalization(
        styleReaderDouble("/tmp/article.html", { throwing_style = true }))
    equal(applied, nil, "throwing API result")
    contains(reason, "crengine failure", "throwing API reason")

    local bare_ui = styleReaderDouble("/tmp/article.html", { typeset = false })
    bare_ui.document.default_css = nil
    applied, reason = GotaReader:applyStyleNormalization(bare_ui)
    equal(applied, nil, "missing base sheet result")
    contains(reason, "base stylesheet is unavailable", "missing base sheet reason")

    -- A failing tweak lookup still installs Gota's own policy.
    local tweak_ui, tweak_calls = styleReaderDouble("/tmp/article.html", {
        styletweak = {
            enabled = true,
            getCssText = function() error("no tweak text") end,
            isTweakEnabled = function() error("no tweak table") end,
        },
    })
    equal(GotaReader:applyStyleNormalization(tweak_ui), true, "applied without user CSS")
    contains(tweak_calls.style[1].appended, "1.6rem", "Gota policy present")
end)

test("an active KOReader size tweak keeps Gota from adding a second policy", function()
    armGotaReader("/tmp/article.html", true)
    local reader_ui, calls = styleReaderDouble("/tmp/article.html", {
        styletweak = {
            enabled = true,
            getCssText = function() return "* { font-size: inherit !important; }" end,
            isTweakEnabled = function(_, id) return id == "font_size_all_inherit", true end,
        },
    })
    equal(GotaReader:applyStyleNormalization(reader_ui), true, "normalization applied")
    local appended = calls.style[1].appended
    equal(appended:find("1.6rem", 1, true), nil, "no Gota heading scale")
    contains(appended, "display: none !important", "cleanup still applied")
    contains(appended, "font-size: inherit !important", "user tweak preserved")
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
            return {
                setSettings = noop,
                cleanupOrphanReaderFiles = function() return 0, {} end,
            }
        end,
    }
    package.loaded["main"] = nil

    local Gota = require("main")
    local registered
    Gota.ui = { menu = { registerToMainMenu = function(_, plugin) registered = plugin end } }
    Gota:init()
    equal(registered, Gota, "menu registration")
    equal(Gota.settings_file, "/settings/gota.lua", "settings path")
    equal(Gota.version, "2.3.0", "plugin version")
    truthy(actions.gota_show_articles, "all articles action")
    truthy(actions.gota_search, "search action")
    truthy(actions.gota_collections, "collections action")

    local menu = {}
    Gota:addToMainMenu(menu)
    equal(menu.gota.sorting_hint, nil, "legacy top-level menu placement")
end)

test("PreRenderDocument applies styles before the after-open state", function()
    local Gota = require("main")
    local opened, pending_after_open = armGotaReader("/tmp/article.html", true, true)
    truthy(opened, "reader open")
    -- ReaderUI emits PreRenderDocument before the after-open callback runs.
    equal(GotaReader.is_showing, false, "document not opened yet")

    local reader_ui, calls = styleReaderDouble("/tmp/article.html")
    Gota.onPreRenderDocument({ ui = reader_ui })
    equal(#calls.style, 1, "stylesheet installed before the first render")
    equal(calls.style[1].base, "./data/epub.css", "base sheet preserved")

    pending_after_open()
    equal(GotaReader.is_showing, true, "after-open state")
    equal(#calls.style, 1, "no second stylesheet call after opening")

    -- Books opened outside Gota, and incomplete UI states, stay inert.
    local other_ui, other_calls = styleReaderDouble("/tmp/library-book.epub")
    Gota.onPreRenderDocument({ ui = other_ui })
    equal(#other_calls.style, 0, "unrelated document untouched")
    Gota.onPreRenderDocument({})
    Gota.onPreRenderDocument({ ui = {} })
    Gota.onPreRenderDocument({ ui = { document = {} } })
end)

test("source contexts preserve page and copied search criteria", function()
    local Gota = require("main")
    local captured
    local fake = {
        showRaindrops = function(_, id, name, page, focus)
            captured = { id = id, name = name, page = page, focus = focus }
        end,
        searchRaindrops = function(_, term, page, filters, context, focus)
            captured = { term = term, page = page, filters = filters, context = context, focus = focus }
        end,
    }
    local collection = Gota.buildCollectionSourceContext(fake, 4, "Inbox", 2)
    collection.reload(19)
    equal(captured.page, 2, "collection page")
    equal(captured.focus, 19, "collection focus")

    local filters = { tag = "original" }
    local context = { collection_id = 4, nested = true }
    local search = Gota.buildSearchSourceContext(fake, "term", 3, filters, context)
    filters.tag = "mutated"
    context.collection_id = 99
    search.reload(21)
    equal(captured.filters.tag, "original", "copied filter")
    equal(captured.context.collection_id, 4, "copied scope")
    equal(captured.page, 3, "search page")
end)

test("confirmed token removal clears API cache and closes authenticated navigation", function()
    local Gota = require("main")
    local cache_clears, closes, notice = 0, 0
    local fake = {
        widgets = {},
        dialogs = { confirmRemoveToken = function(_, callback) callback() return {} end },
        settings = { clearToken = function() return true end },
        api = { clearCache = function() cache_clears = cache_clears + 1 end },
        closeAllWidgets = function() closes = closes + 1 end,
        notify = function(_, text) notice = text end,
    }
    Gota.confirmRemoveToken(fake)
    equal(cache_clears, 1, "cache cleared")
    equal(closes, 1, "authenticated widgets closed")
    equal(notice, "Local access token removed", "success notice")
end)

test("advanced search state survives reopening only in the plugin session", function()
    local Gota = require("main")
    local seen_initial
    local fake = {
        api = { getFilters = function() return { tags = {}, types = {} } end },
        settings = { getSortOrder = function() return "-created" end },
        ui_builder = { buildActiveFilterSummary = UIBuilder.buildActiveFilterSummary },
        dialogs = { showAdvancedSearchDialog = function(_, _, initial, callbacks)
            seen_initial = initial
            callbacks.on_state_change({
                term = "saved in memory", tag = "", type = "", quick = {}, match = "all", more = {},
            })
            return {}
        end },
        widgets = {},
        showProgress = noop,
        hideProgress = noop,
        notify = noop,
    }
    Gota.showAdvancedSearchDialog(fake, {})
    equal(seen_initial.term, "", "first opening")
    Gota.showAdvancedSearchDialog(fake, {})
    equal(seen_initial.term, "saved in memory", "session state")
end)

test("successful mutation reloads source once while failure preserves detail", function()
    local Gota = require("main")
    local reload_count, reload_id, closed, notified = 0, nil, 0, 0
    local fake = {
        api = { updateRaindrop = function() return { item = { _id = 77 } } end },
        article_manager = { adoptFullArticle = function(_, item) return item end },
        showProgress = noop,
        hideProgress = noop,
        toast = noop,
        notify = function() notified = notified + 1 end,
        closeWidget = function(_, name) if name == "article_menu" then closed = closed + 1 end end,
        showRaindropContent = function() error("detail should not reopen") end,
    }
    local source = { reload = function(id) reload_count, reload_id = reload_count + 1, id end }
    truthy(Gota.updateCurrentRaindrop(fake, { _id = 77 }, { important = true }, "updated",
        nil, source), "mutation")
    equal(reload_count, 1, "single reload")
    equal(reload_id, 77, "updated focus")
    equal(closed, 1, "detail closed")

    fake.api.updateRaindrop = function() return nil, "offline" end
    equal(Gota.updateCurrentRaindrop(fake, { _id = 77 }, { important = false }, "updated",
        nil, source), false, "failed mutation")
    equal(reload_count, 1, "no failed reload")
    equal(closed, 1, "detail kept on failure")
    equal(notified, 1, "failure notice")
end)

test("Trash closes stale navigation and reloads without reopening the item", function()
    local Gota = require("main")
    local reload_called, reload_id = false, "not-called"
    local closed = {}
    local fake = {
        dialogs = { confirmMoveToTrash = function(_, _, callback) callback() end },
        api = { trashRaindrop = function() return { result = true } end },
        showProgress = noop,
        hideProgress = noop,
        toast = noop,
        notify = noop,
        closeWidget = function(_, name) closed[name] = true end,
    }
    Gota.confirmTrashRaindrop(fake, { _id = 9, title = "Item", collection = { ["$id"] = 4 } },
        4, { reload = function(id) reload_called, reload_id = true, id end })
    equal(reload_called, true, "source reloaded")
    equal(reload_id, nil, "no deleted focus")
    equal(closed.article_menu, true, "detail closed")
    equal(closed.collections_menu, true, "collection counts closed")
    equal(closed.collection_actions_menu, true, "collection actions closed")
end)

test("saved-file result uses one shared action entry point", function()
    local Gota = require("main")
    local shown
    local fake = { showSavedFileActions = function(_, filename) shown = filename end }
    equal(Gota.handleSavedFile(fake, nil), false, "cancelled save")
    truthy(Gota.handleSavedFile(fake, "/tmp/articles/item.html"), "successful save")
    equal(shown, "/tmp/articles/item.html", "shared filename")
end)

test("collection screen reads documented nested user statistics counts", function()
    local Gota = require("main")
    local rendered
    local fake = {
        widgets = {}, collapsed_collection_groups = {},
        closeWidget = noop, notify = noop,
        ui_builder = {
            buildCollectionItems = function() return {} end,
            createMenu = function(_, title, items)
                rendered = { title = title, item_table = items }
                return rendered
            end,
        },
    }
    Gota.renderCollections(fake, { roots = {}, children = {}, groups = {}, warnings = {} }, {
        items = { { _id = 0, count = 10 }, { _id = -1, count = 1 }, { _id = -99, count = 4 } },
        meta = { broken = { count = 3 }, duplicates = { count = 2 } },
    })
    equal(rendered.item_table[1].text, "All articles (10)", "All count")
    equal(rendered.item_table[2].text, "Unsorted (inbox) (1)", "Unsorted count")
    local combined = ""
    for _, item in ipairs(rendered.item_table) do combined = combined .. tostring(item.text) .. "\n" end
    contains(combined, "Broken links: 3", "broken count")
    contains(combined, "Duplicate links: 2", "duplicate count")
    contains(combined, "Trash (4)", "Trash count")
end)

io.write(string.format("1..%d\n", total))
if failed > 0 then
    io.write(string.format("%d test(s) failed\n", failed))
    os.exit(1)
end
io.write(string.format("%d tests passed\n", total))
