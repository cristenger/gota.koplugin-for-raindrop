local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

-- This module is shared by the FileManager and ReaderUI plugin instances. It
-- only keeps the state needed to offer a canonical "Back to Gota" menu item.
local GotaReader = {
    current_path = nil,
    is_showing = false,
    on_return_callback = nil,
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
