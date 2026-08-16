local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local ReaderStyles = require("gota_reader_styles")

-- This module is shared by the FileManager and ReaderUI plugin instances. It
-- only keeps the state needed to offer a canonical "Back to Gota" menu item
-- and to know whether the pending document was requested by Gota's full
-- reader action.
local GotaReader = {
    current_path = nil,
    is_showing = false,
    on_return_callback = nil,
    normalize_styles = false,
}

local function showError(text)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = 3,
    })
end

function GotaReader:reset()
    self.current_path = nil
    self.is_showing = false
    self.on_return_callback = nil
    self.normalize_styles = false
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
    self.on_return_callback = options.on_return_callback
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
        and self.on_return_callback ~= nil
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
    local done_callback = self.on_return_callback
    self:reset()

    -- onHome is ReaderUI's supported path for closing the document and
    -- restoring FileManager. Run the Gota callback on the following UI tick,
    -- once the FileManager plugin instance has been restored.
    UIManager:nextTick(function()
        local ok, err = pcall(function()
            reader:onHome()
        end)
        if not ok then
            logger.err("GotaReader: could not return to FileManager:", err)
            return
        end

        UIManager:nextTick(function()
            local callback_ok, callback_err = pcall(done_callback)
            if not callback_ok then
                logger.err("GotaReader: return callback failed:", callback_err)
            end
        end)
    end)

    return true
end

function GotaReader:onReaderUIClose(path)
    if path and path == self.current_path then
        self:reset()
    end
end

return GotaReader
