local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gota_gettext")

local ReaderStyles = require("gota_reader_styles")

-- This module is shared by the FileManager and ReaderUI plugin instances. It
-- only keeps the state needed to offer a canonical "Back to Gota" menu item
-- and to know whether the pending document was requested by Gota's full
-- reader action.
local GotaReader = {
    current_path = nil,
    is_showing = false,
    return_target = nil,
    normalize_styles = false,
}

-- PluginLoader registers each instance under the plugin's folder name
-- ("gota.koplugin" -> "gota"), overriding the name declared in main.lua, so
-- Gota:init reports the name it was actually registered under.
local DEFAULT_PLUGIN_NAME = "gota"
local MAX_TARGET_DEPTH = 16

local function showError(text)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 3,
    })
end

function GotaReader:setPluginName(name)
    self.plugin_name = type(name) == "string" and name ~= "" and name or nil
end

function GotaReader:reset()
    self.current_path = nil
    self.is_showing = false
    self.return_target = nil
    self.normalize_styles = false
end

-- Copy decoded JSON-like data only: closures, userdata and metatables would
-- pin the plugin instance that opened the reader, which KOReader replaces.
local function plainCopy(value, depth)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    if kind ~= "table" or depth > MAX_TARGET_DEPTH then return nil end
    local copy = {}
    for key, item in pairs(value) do
        local key_kind = type(key)
        if key_kind == "string" or key_kind == "number" then
            copy[key] = plainCopy(item, depth + 1)
        end
    end
    return copy
end

local function positiveInteger(value)
    local number = tonumber(value)
    if not number or number ~= number or number <= 0 or number >= 2 ^ 53 or
       number ~= math.floor(number) then
        return nil
    end
    return number
end

--[[
    A return target describes where "Back to Gota" lands, as data resolved
    against whichever Gota instance is alive after the reader closes:
      { view = "offline_library" }
      { view = "article", raindrop = <item>, source = <descriptor>, generation = <n> }
    The article snapshot keeps returning possible without a network request;
    loaded web-copy text is dropped so the reader does not retain it.
]]
local function sanitizeReturnTarget(target)
    if type(target) ~= "table" then return nil end
    if target.view == "offline_library" then return { view = "offline_library" } end
    if target.view ~= "article" or type(target.raindrop) ~= "table" or
       not positiveInteger(target.raindrop._id) then
        return nil
    end
    local raindrop = plainCopy(target.raindrop, 1)
    if type(raindrop.cache) == "table" then raindrop.cache.text = nil end
    return {
        view = "article",
        raindrop = raindrop,
        source = type(target.source) == "table" and plainCopy(target.source, 1) or nil,
        generation = tonumber(target.generation),
    }
end

function GotaReader:show(options)
    if type(options) ~= "table" or type(options.path) ~= "string" then
        logger.err("GotaReader: missing document path")
        showError(_("Error: Could not find HTML file"))
        return false
    end

    if lfs.attributes(options.path, "mode") ~= "file" then
        logger.err("GotaReader: file does not exist:", options.path)
        showError(_("Error: Could not find HTML file"))
        return false
    end

    -- Querying the registry is sufficient. ReaderUI owns opening and closing
    -- the document, so no DocumentRegistry:openDocument reference is leaked.
    local provider, is_provider_forced = DocumentRegistry:getProvider(options.path)
    if not provider then
        logger.err("GotaReader: no document provider for:", options.path)
        showError(_("Error: Could not open HTML file"))
        return false
    end

    if options.before_open_callback then
        local before_ok, before_error = pcall(options.before_open_callback)
        if not before_ok then
            logger.err("GotaReader: could not close Gota navigation:", before_error)
            showError(_("Error: Could not open HTML file"))
            return false
        end
    end

    self.current_path = options.path
    self.is_showing = false
    self.return_target = sanitizeReturnTarget(options.return_target)
    -- Callers opt in explicitly; the path or extension is never used to infer
    -- the policy, so this module stays reusable and the intent stays visible.
    self.normalize_styles = options.normalize_styles == true

    local function after_open_callback()
        self.is_showing = true
        logger.dbg("GotaReader: document opened:", options.path)
    end

    local ok, err = pcall(function()
        if ReaderUI.instance then
            ReaderUI.instance:switchDocument(
                options.path,
                nil,
                after_open_callback,
                provider,
                is_provider_forced
            )
        else
            ReaderUI:showReader(
                options.path,
                provider,
                nil,
                is_provider_forced,
                after_open_callback
            )
        end
    end)

    if not ok then
        logger.err("GotaReader: could not open document:", err)
        self:reset()
        showError(_("Error: Could not open HTML file"))
        return false
    end

    return true
end

-- Whether ReaderUI currently holds this exact document open. Used before
-- replacing a file on disk that the user may be reading right now.
function GotaReader:isDocumentOpen(path)
    if type(path) ~= "string" or path == "" then return false end
    local reader = ReaderUI.instance
    return reader ~= nil and reader.document ~= nil and reader.document.file == path
end

function GotaReader:shouldNormalize(path)
    return self.normalize_styles == true
        and type(path) == "string"
        and path == self.current_path
end

--[[
    Append Gota's presentation stylesheet to the base sheet KOReader already
    resolved. Must run on PreRenderDocument: ReaderTypeset:onReadSettings has
    set typeset.css by then, and CREngine has not rendered yet, so no second
    render is triggered.

    CreDocument:setStyleSheet(base_css_file, appended_css) reloads the base
    file and concatenates the appended string after it, so the same base sheet
    is preserved and nothing is written to doc_settings. Returns false when the
    document is not ours (silent), nil plus a reason when the expected API is
    unavailable or fails, and true when the sheet was installed.
]]
function GotaReader:applyStyleNormalization(reader_ui)
    local document = reader_ui and reader_ui.document
    local path = document and document.file
    if not self:shouldNormalize(path) then
        return false, "document is not the pending Gota reader document"
    end
    if type(document.setStyleSheet) ~= "function" then
        return nil, "CREngine stylesheet API is unavailable"
    end

    -- typeset.css is the sheet the user selected; default_css only covers the
    -- case where ReaderTypeset has not resolved one.
    local typeset = reader_ui.typeset
    local base_css = typeset and typeset.css or document.default_css
    if type(base_css) ~= "string" or base_css == "" then
        return nil, "KOReader base stylesheet is unavailable"
    end

    -- Read the active tweaks without mutating them. getCssText returns nil
    -- when no tweak is enabled, which build() treats as absent.
    local styletweak = reader_ui.styletweak
    local user_css
    if styletweak and type(styletweak.getCssText) == "function" then
        local css_ok, css_or_error = pcall(styletweak.getCssText, styletweak)
        if css_ok then
            user_css = css_or_error
        else
            logger.warn("Gota: could not read active style tweaks")
        end
    end

    local combined = ReaderStyles.build(user_css, {
        skip_font_normalization = ReaderStyles.hasActiveFontSizeTweak(styletweak),
    })
    local ok, err = pcall(document.setStyleSheet, document, base_css, combined)
    if not ok then
        return nil, tostring(err)
    end
    return true
end

function GotaReader:canReturn()
    local reader = ReaderUI.instance
    return self.is_showing
        and self.return_target ~= nil
        and self.current_path ~= nil
        and reader ~= nil
        and reader.document ~= nil
        and reader.document.file == self.current_path
end

function GotaReader:onReturn()
    if not self:canReturn() then
        return false
    end

    local reader = ReaderUI.instance
    local target = self.return_target
    self:reset()

    -- onHome is ReaderUI's supported path for closing the document and
    -- restoring FileManager, which creates a new Gota instance. Resolve that
    -- instance on the following tick instead of the one that opened the
    -- reader: its widgets, settings snapshot and article manager are gone.
    UIManager:nextTick(function()
        local ok, err = pcall(function()
            reader:onHome()
        end)
        if not ok then
            logger.err("GotaReader: could not return to FileManager:", err)
            return
        end

        UIManager:nextTick(function()
            local loader_ok, PluginLoader = pcall(require, "pluginloader")
            local owner = loader_ok and PluginLoader and
                PluginLoader:getPluginInstance(self.plugin_name or DEFAULT_PLUGIN_NAME)
            if not owner or type(owner.resumeFromReader) ~= "function" then
                logger.warn("GotaReader: no active Gota instance to return to")
                return
            end
            local resume_ok, resume_err = pcall(owner.resumeFromReader, owner, target)
            if not resume_ok then
                logger.err("GotaReader: return failed:", resume_err)
            end
        end)
    end)

    return true
end

--[[
    Show the folder that holds file_path in KOReader's file browser, with the
    file focused. From the reader this follows ReaderUI:onHome: close the
    reader through its own lifecycle first, so no ReaderUI is left alive under
    the FileManager (and no FileManager-side cleanup races an open document).
]]
function GotaReader:showFolder(file_path)
    if type(file_path) ~= "string" or file_path == "" then return false end
    local directory = file_path:match("^(.*)/[^/]+$")
    if not directory or directory == "" then return false end

    local ok, err = pcall(function()
        local reader = ReaderUI.instance
        if reader then
            self:reset()
            reader:onClose()
            reader:showFileManager(file_path)
            return
        end
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance then
            FileManager.instance.file_chooser:changeToPath(directory, file_path)
        else
            FileManager:showFiles(directory, file_path)
        end
    end)
    if not ok then
        logger.err("GotaReader: could not open folder:", err)
        return false
    end
    return true
end

--[[
    KOReader creates a plugin instance for every FileManager and ReaderUI.
    CloseDocument cannot tell a native reload (ReaderUI:reloadDocument closes
    and then reopens the same path in a new ReaderUI) from leaving the
    article, so the request is released here instead: when the next owner is
    initialized with another document, or with none, and ReaderUI no longer
    holds the requested path.
]]
function GotaReader:onOwnerInit(active_path)
    if self.current_path == nil then return end
    if active_path == self.current_path or self:isDocumentOpen(self.current_path) then
        return
    end
    self:reset()
end

-- Documents a reader-cache cleanup must keep: the pending or active Gota
-- request and whatever ReaderUI currently holds open, even when the caller
-- is a FileManager instance that has no document of its own.
function GotaReader:getProtectedPaths()
    local paths = {}
    if type(self.current_path) == "string" then paths[#paths + 1] = self.current_path end
    local reader = ReaderUI.instance
    local open_path = reader and reader.document and reader.document.file
    if type(open_path) == "string" and open_path ~= self.current_path then
        paths[#paths + 1] = open_path
    end
    return paths
end

return GotaReader
