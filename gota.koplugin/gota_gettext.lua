-- KOReader's loadMO appends to its shared dictionaries. Load the plugin's
-- catalog into temporary dictionaries and restore core gettext immediately,
-- so strings such as "Source" cannot change translations elsewhere.
local core = require("gettext")
if type(core) ~= "table" or type(core.loadMO) ~= "function" then
    return core
end

local logger = require("logger")
local source = debug.getinfo(1, "S").source
local plugin_dir = source:match("^@(.+)/gota_gettext%.lua$") or "."
local loaded_lang
local translations = {}

local function loadCatalog()
    local lang = core.current_lang or "C"
    if lang == loaded_lang then return end
    loaded_lang = lang
    translations = {}
    if lang == "C" or lang == "" or not lang:match("^[%w_@%-]+$") then return end

    local original_translation, original_context, original_plural =
        core.translation, core.context, core.getPlural
    core.translation, core.context = {}, {}
    local ok, found = pcall(core.loadMO, plugin_dir .. "/l10n/" .. lang .. "/gota.mo")
    if ok and not found then
        -- A regional UI language may share a base-language plugin catalog.
        local base_lang = lang:match("^([%a]+)[_@%-]")
        if base_lang then
            core.translation, core.context = {}, {}
            ok, found = pcall(core.loadMO, plugin_dir .. "/l10n/" .. base_lang .. "/gota.mo")
        end
    end
    if ok and found then translations = core.translation end
    core.translation, core.context, core.getPlural =
        original_translation, original_context, original_plural
    if not ok then logger.warn("Gota: could not load plugin translations") end
end

-- Load before importing modules that build translated lookup tables.
loadCatalog()

return function(msgid)
    loadCatalog()
    local translation = translations[msgid]
    if type(translation) == "table" then translation = translation[0] end
    return translation or core(msgid)
end
