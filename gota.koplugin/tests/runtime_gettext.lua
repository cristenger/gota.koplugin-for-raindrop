-- Native gettext regression; run from a built KOReader runtime directory:
--
--   KO_HOME="$(mktemp -d)" ./luajit /absolute/path/gota.koplugin/tests/runtime_gettext.lua
--
-- The plugin directory is derived from this script's path. An optional first
-- argument supplies it explicitly. Always use a fresh KO_HOME so setupkoenv
-- cannot reach the user's normal runtime state. No account settings are read.

assert(os.getenv("KO_HOME") and os.getenv("KO_HOME") ~= "",
    "Run with a fresh, isolated KO_HOME directory")

local script_path = debug.getinfo(1, "S").source:match("^@(.*)$") or arg[0]
local plugin_dir = arg[1] or script_path:match("^(.*)/tests/runtime_gettext%.lua$")
assert(plugin_dir and plugin_dir ~= "", "Cannot derive the Gota plugin directory")

require("setupkoenv")
package.path = plugin_dir .. "/?.lua;" .. package.path

local core = require("gettext")
local original = {
    translation = core.translation,
    context = core.context,
    plural = core.getPlural,
    language = core.current_lang,
    textdomain = core.textdomain,
    dirname = core.dirname,
}

local ok, failure = pcall(function()
    assert(core.changeLang("es"), "KOReader's Spanish catalog is unavailable")
    local translation, context, plural = core.translation, core.context, core.getPlural
    local cancel = core("Cancel")
    local configure = core("Configure access token")
    local domain, dirname = core.textdomain, core.dirname

    local function assertCoreUnchanged()
        assert(core.translation == translation, "Plugin replaced the core translation table")
        assert(core.context == context, "Plugin replaced the core context table")
        assert(core.getPlural == plural, "Plugin changed the core plural function")
        assert(core.textdomain == domain and core.dirname == dirname,
            "Plugin changed the core catalog location")
        assert(core("Cancel") == cancel, "Plugin changed a core translation")
        assert(core("Configure access token") == configure,
            "Plugin translations leaked into core gettext")
    end

    local translate = require("gota_gettext")
    assert(translate("Configure access token") == "Configurar token de acceso",
        "Gota's Spanish catalog was not loaded")
    assertCoreUnchanged()

    -- ContentProcessor builds its color-name lookup table when imported. This
    -- proves the catalog was available before that module initialized.
    local processor = require("gota_content_processor"):new()
    assert(processor:formatHighlightInfo({ color = "blue" }):find("Azul", 1, true),
        "Module-level translated strings were initialized before the catalog")
    assertCoreUnchanged()

    -- Simulate a regional UI locale in memory. Gota must load l10n/es/gota.mo
    -- when l10n/es_ES/gota.mo is absent; the core Spanish catalog stays intact.
    core.current_lang = "es_ES"
    assert(translate("Configure access token") == "Configurar token de acceso",
        "Gota's regional Spanish fallback failed")
    assertCoreUnchanged()

    core.current_lang = "C"
    assert(translate("Configure access token") == configure,
        "Gota retained a stale plugin catalog after changing the locale")
    assertCoreUnchanged()
end)

core.translation, core.context, core.getPlural =
    original.translation, original.context, original.plural
core.current_lang, core.textdomain, core.dirname =
    original.language, original.textdomain, original.dirname

assert(ok, failure)
print("PASS native gettext: Spanish, regional fallback, module initialization, core isolation")
