return function(test, equal, truthy, contains)
    local ContentProcessor = dofile("gota_content_processor.lua")
    local processor = ContentProcessor:new()

    test("UTF-8 validation keeps large valid documents without per-byte tables", function()
        local document = string.rep("a", 4 * 1024 * 1024) .. "café"
        collectgarbage("collect")
        local before = collectgarbage("count")
        local cleaned, replaced = ContentProcessor.sanitizeUTF8(document)
        equal(cleaned, document)
        equal(replaced, false)
        -- A per-byte table for 4 MiB grows by tens of MiB. Allow room for
        -- interpreter/JIT bookkeeping without tying the check to exact sizes.
        truthy(collectgarbage("count") - before < 1024)
        local damaged = string.rep("a\192", 1000)
        equal(ContentProcessor.sanitizeUTF8(damaged), string.rep("a\239\191\189", 1000))
    end)

    test("plain text keeps editorial headers and removes site navigation", function()
        local plain = processor:htmlToText([[
            <header>SITE_NAVIGATION</header>
            <article><header><h1>Article title</h1><p>By Ana</p></header>
            <nav>ARTICLE_NAVIGATION</nav><p>Article body</p></article>
        ]])
        contains(plain, "Article title")
        contains(plain, "By Ana")
        contains(plain, "Article body")
        equal(plain:find("NAVIGATION", 1, true), nil)
    end)

    test("plain text separates list items and honors ordered counters", function()
        local plain = processor:htmlToText([[
            <article><ul><li>uno</li><li>dos</li></ul>
            <ol start="3"><li>tres</li><li value='8'>ocho</li><li>nueve</li></ol></article>
        ]])
        contains(plain, "• uno\n• dos")
        contains(plain, "3. tres\n8. ocho\n9. nueve")
    end)

    test("plain text uses row and cell boundaries in tables", function()
        equal(processor:htmlToText([[
            <table><tr><th>Nombre</th><th>Valor</th></tr>
            <tr><td>uno</td><td>dos</td></tr></table>
        ]]), "Nombre | Valor\nuno | dos")
    end)

    test("plain text keeps pre indentation blank lines and inline code spacing", function()
        local plain = processor:htmlToText([[
            <article><p>Prose   words <code>x  +  y</code>.</p>
            <pre><code>if (x &lt; 2) {
    first();


    second();
}</code></pre><p>After</p></article>
        ]])
        contains(plain, "Prose words x  +  y.")
        contains(plain, "if (x < 2) {\n    first();\n\n\n    second();\n}")
        contains(plain, "After")
    end)

    test("HTML cleaning keeps spaces between syntax highlighted code spans", function()
        local html = '<pre><span>one</span>   <span>two</span>\n  <span>three</span></pre>'
        equal(processor:cleanHTMLForEink(html), html)
        equal(processor:htmlToText(html), "one   two\n  three")
    end)

    test("HTML scanner handles quoted tag delimiters and exact tag names", function()
        local plain = processor:htmlToText([[
            <article data-info="a > b"><p title='x > y'>Visible</p>
            <scripture>Editorial text</scripture><picture>Caption</picture></article>
        ]])
        contains(plain, "Visible")
        contains(plain, "Editorial text")
        contains(plain, "Caption")
        equal(plain:find("a > b", 1, true), nil)
        equal(plain:find("x > y", 1, true), nil)
    end)

    test("literal angle comparisons do not swallow following HTML elements", function()
        equal(processor:htmlToText('<article><p>x < 2</p><script>HIDDEN</script><p>After</p></article>'),
            "x < 2\nAfter")
        contains(processor:htmlToText('<ul><li><p>First paragraph</p><p>Second paragraph</p></li></ul>'),
            "• First paragraph\nSecond paragraph")
    end)

    test("nested hidden elements and unterminated scripts do not leak into text", function()
        local plain = processor:htmlToText([[
            <article><template>JUNK_A<template>JUNK_B</template>JUNK_C</template>
            <p>Visible</p><script>const example = "<script>"; JUNK_D</script>
            <p>After</p></article><script>JUNK_E
        ]])
        contains(plain, "Visible")
        contains(plain, "After")
        equal(plain:find("JUNK", 1, true), nil)
    end)

    test("article extraction supports nested semantic containers", function()
        local plain = processor:htmlToText([[
            <header>Chrome</header><article><h1>Outer title</h1>
            <article><p>Inner body</p></article><p>Outer tail</p></article>
        ]])
        contains(plain, "Outer title")
        contains(plain, "Inner body")
        contains(plain, "Outer tail")
        equal(plain:find("Chrome", 1, true), nil)
    end)

    test("deep HTML lists remain bounded and keep their text", function()
        local html = "<article>" .. string.rep("<ol><li>", 2000) .. "Deep text" ..
            string.rep("</li></ol>", 2000) .. "</article>"
        local plain = processor:htmlToText(html)
        contains(plain, "Deep text")
        truthy(#plain < #html)
    end)

    test("code placeholder cannot be forged by remote text or decoded entities", function()
        local html = '<article><p>&#30;GOTA_CODE_1&#31;</p><pre>safe  code</pre></article>'
        local plain = processor:htmlToText(html)
        contains(plain, "\30GOTA_CODE_1\31")
        contains(plain, "safe  code")
    end)

    test("annotated exports carry a deterministic generator marker", function()
        local html = processor:createReaderHTMLWithNotes({ title = "Example" })
        contains(html, '<meta name="generator" content="Gota annotated export">')
        local original = processor:createReaderHTML({ title = "Example", cache = { text = "<p>Body</p>" } })
        equal(original:find('content="Gota annotated export"', 1, true), nil)
    end)

    test("plugin gettext isolates core dictionaries and handles regional fallback", function()
        local original_core = package.loaded["gettext"]
        local old_translation, old_context = { Cancel = "Core cancel" }, { Core = {} }
        local old_plural = function() return 7 end
        local calls = {}
        local fake = setmetatable({
            current_lang = "es_MX", translation = old_translation,
            context = old_context, getPlural = old_plural, textdomain = "koreader",
        }, { __call = function(self, text) return self.translation[text] or text end })
        fake.loadMO = function(path)
            calls[#calls + 1] = path
            if not path:match("/es/gota%.mo$") then return false end
            fake.translation["Configure access token"] = "Configurar token"
            fake.translation.Cancel = "Plugin cancel"
            fake.context.Plugin = { Example = "Ejemplo" }
            fake.getPlural = function() return 0 end
            return true
        end
        package.loaded["gettext"] = fake
        local ok, failure = pcall(function()
            local translate = dofile("gota_gettext.lua")
            equal(translate("Configure access token"), "Configurar token")
            equal(translate("Cancel"), "Plugin cancel")
            equal(fake("Cancel"), "Core cancel")
            equal(fake.translation, old_translation)
            equal(fake.context, old_context)
            equal(fake.getPlural, old_plural)
            equal(fake.textdomain, "koreader")
            equal(#calls, 2)
            fake.current_lang = "C"
            equal(translate("Configure access token"), "Configure access token")
        end)
        package.loaded["gettext"] = original_core
        if not ok then error(failure) end
    end)

    test("plugin gettext restores core state after a corrupt catalog", function()
        local original_core = package.loaded["gettext"]
        local translation, context = {}, {}
        local plural = function() return 1 end
        local fake = setmetatable({ current_lang = "es", translation = translation,
            context = context, getPlural = plural }, { __call = function(_, text) return text end })
        fake.loadMO = function()
            fake.translation.Bad = "Partial value"
            fake.getPlural = function() return 0 end
            error("corrupt catalog")
        end
        package.loaded["gettext"] = fake
        local ok, failure = pcall(function()
            local translate = dofile("gota_gettext.lua")
            equal(translate("Bad"), "Bad")
            equal(fake.translation, translation)
            equal(fake.context, context)
            equal(fake.getPlural, plural)
        end)
        package.loaded["gettext"] = original_core
        if not ok then error(failure) end
    end)

    test("settings share credentials across reader and file manager instances", function()
        local original_luasettings = package.loaded["luasettings"]
        local stored = { token = "account A" }
        local fail_flush = false
        package.loaded["luasettings"] = { open = function()
            local snapshot = {}
            for key, value in pairs(stored) do snapshot[key] = value end
            return {
                readSetting = function(_, key) return snapshot[key] end,
                saveSetting = function(_, key, value) snapshot[key] = value end,
                flush = function()
                    if fail_flush then error("flush failed") end
                    stored = {}
                    for key, value in pairs(snapshot) do stored[key] = value end
                end,
            }
        end }
        local ok, failure = pcall(function()
            local Settings = dofile("gota_settings.lua")
            local manager, reader = Settings:new(), Settings:new()
            local generation = manager:getSessionGeneration()
            reader:setToken("account B")
            equal(manager:getToken(), "account B")
            equal(manager:getSessionGeneration(), generation + 1)
            truthy(manager:save())
            equal(stored.token, "account B")
            reader:setToken("account B")
            equal(reader:getSessionGeneration(), generation + 1)
            truthy(manager:clearToken())
            equal(reader:getToken(), "")
            equal(reader:isTokenValid(), false)
            equal(reader:getDebugInfo().token_status, "not configured")
            reader:setToken("account C")
            fail_flush = true
            equal(manager:clearToken(), false)
            equal(reader:getToken(), "account C")
            equal(manager:getToken(), "account C")
            truthy(manager:isTLSVerificationEnabled())
            manager:setTLSVerificationEnabled(false)
            equal(manager:isTLSVerificationEnabled(), false)
            equal(reader:isTLSVerificationEnabled(), false)
            manager:setTLSCAFile("/tmp/test-ca.pem")
            equal(manager:getTLSCAFile(), "/tmp/test-ca.pem")
            equal(reader:getTLSCAFile(), "/tmp/test-ca.pem")
            fail_flush = false
            reader:setTLSVerificationEnabled(true)
            truthy(manager:save())
            equal(stored.tls_verify, true, "stale instances preserve the current security preference")
        end)
        package.loaded["luasettings"] = original_luasettings
        if not ok then error(failure) end
    end)
end
