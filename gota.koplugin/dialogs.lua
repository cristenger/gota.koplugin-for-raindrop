--[[
    Dialogs Module for Gota Plugin
    Handles all dialog creation and management
]]

local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local Dialogs = {}

function Dialogs:new(parent)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    
    o.parent = parent  -- Referencia al plugin principal
    
    return o
end

-- ========== TOKEN DIALOG ==========

function Dialogs:showTokenDialog(current_token, callbacks)
    local token_dialog  -- Declarar antes para que los callbacks puedan acceder
    token_dialog = InputDialog:new{
        title = _("Raindrop.io Access Token"),
        description = _("OPTION 1 - Test Token (Recommended):\n• Go to: https://app.raindrop.io/settings/integrations\n• Create a new application\n• Copy the 'Test token'\n\nOPTION 2 - Personal Token:\n• Use a personal access token\n\nPaste the token here:"),
        input = current_token,
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(token_dialog)
                    end,
                },
                {
                    text = _("Test"),
                    callback = function()
                        local test_token = token_dialog:getInputText()
                        if test_token and test_token ~= "" then
                            test_token = test_token:gsub("^%s+", ""):gsub("%s+$", "")
                            if test_token ~= "" then
                                NetworkMgr:runWhenOnline(function()
                                    callbacks.test(test_token)
                                end)
                            else
                                callbacks.notify(_("Please enter a token to test"))
                            end
                        else
                            callbacks.notify(_("Please enter a token to test"))
                        end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_token = token_dialog:getInputText()
                        if new_token and new_token ~= "" then
                            new_token = new_token:gsub("^%s+", ""):gsub("%s+$", "")
                            
                            if new_token == "" then
                                callbacks.notify(_("Please enter a valid token"), 2)
                                return
                            end
                            
                            if #new_token < 10 then
                                callbacks.notify(_("Warning: Token seems very short, but it will be saved anyway"), 3)
                            end
                            
                            local success, err = callbacks.save(new_token)
                            UIManager:close(token_dialog)
                            
                            if success then
                                callbacks.notify(_("Token saved successfully\nUse 'Test' to verify functionality"), 3)
                            else
                                callbacks.notify("Error: No se pudo guardar la configuración - " .. (err or "desconocido"))
                            end
                        else
                            callbacks.notify(_("Please enter a valid token"), 2)
                        end
                    end,
                }
            }
        },
    }
    
    UIManager:show(token_dialog)
    token_dialog:onShowKeyboard()
    
    return token_dialog
end

-- ========== DOWNLOAD PATH DIALOG ==========

function Dialogs:showDownloadPathDialog(current_path, callbacks)
    local ButtonDialog = require("ui/widget/buttondialog")
    
    local full_path = callbacks.get_data_dir() .. "/" .. current_path .. "/"
    
    local button_dialog
    button_dialog = ButtonDialog:new{
        title = _("Download folder") .. "\n\n" .. 
                _("Current folder") .. ":\n" .. current_path .. "\n\n" ..
                _("Full path") .. ":\n" .. full_path,
        buttons = {
            {
                {
                    text = _("Browse folders"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:showFolderPicker(callbacks)
                    end,
                },
            },
            {
                {
                    text = _("Enter folder name manually"),
                    callback = function()
                        UIManager:close(button_dialog)
                        self:showDownloadPathInputDialog(current_path, callbacks)
                    end,
                },
            },
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(button_dialog)
                    end,
                },
            },
        },
    }
    
    UIManager:show(button_dialog)
    return button_dialog
end

function Dialogs:showFolderPicker(callbacks)
    local PathChooser = require("ui/widget/pathchooser")
    local data_dir = callbacks.get_data_dir()
    
    local path_chooser
    path_chooser = PathChooser:new{
        title = _("Select download folder"),
        path = data_dir,
        select_directory = true,
        select_file = false,
        show_hidden = false,
        onConfirm = function(folder_path)
            -- Convertir ruta absoluta a relativa
            local relative_path = folder_path:gsub("^" .. data_dir .. "/?", "")
            
            if relative_path == "" or relative_path == folder_path then
                -- Si no es relativa al data_dir, usar el nombre de la carpeta
                relative_path = folder_path:match("([^/]+)/?$") or "gota_articles"
            end
            
            local success, err = callbacks.save(relative_path)
            
            if success then
                callbacks.notify(_("Folder configured: ") .. relative_path, 3)
            else
                callbacks.notify(_("Error saving: ") .. (err or "unknown"))
            end
            
            UIManager:close(path_chooser)
        end,
    }
    
    UIManager:show(path_chooser)
    return path_chooser
end

function Dialogs:showDownloadPathInputDialog(current_path, callbacks)
    local path_dialog
    path_dialog = InputDialog:new{
        title = _("Download folder"),
        description = _("Enter the folder name where downloaded articles will be saved") .. "\n\n" ..
                     _("Full path") .. ": " .. (callbacks.get_data_dir() .. "/" .. current_path .. "/"),
        input = current_path,
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(path_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_path = path_dialog:getInputText()
                        if new_path and new_path ~= "" then
                            new_path = new_path:gsub("^%s+", ""):gsub("%s+$", "")
                            new_path = new_path:gsub("[%c%p%s]+", "_")  -- Sanitizar
                            
                            if new_path == "" then
                                callbacks.notify(_("Invalid folder name"), 2)
                                return
                            end
                            
                            local success, err = callbacks.save(new_path)
                            UIManager:close(path_dialog)
                            
                            if success then
                                callbacks.notify(_("Folder configured: ") .. new_path, 3)
                            else
                                callbacks.notify(_("Error saving: ") .. (err or "unknown"))
                            end
                        else
                            callbacks.notify(_("Please enter a folder name"), 2)
                        end
                    end,
                }
            }
        },
    }
    
    UIManager:show(path_dialog)
    path_dialog:onShowKeyboard()
    
    return path_dialog
end

-- ========== SEARCH DIALOG ==========

function Dialogs:showSearchDialog(on_search_callback, on_cancel_callback)
    local search_dialog  -- Declarar antes para que los callbacks puedan acceder
    search_dialog = InputDialog:new{
        title = _("Search articles"),
        input = "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(search_dialog)
                        if on_cancel_callback then
                            on_cancel_callback()
                        end
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local search_term = search_dialog:getInputText()
                        if search_term and search_term ~= "" then
                            UIManager:close(search_dialog)
                            NetworkMgr:runWhenOnline(function()
                                on_search_callback(search_term)
                            end)
                        else
                            if on_cancel_callback then
                                on_cancel_callback(_("Please enter a search term"))
                            end
                        end
                    end,
                }
            }
        },
    }
    
    UIManager:show(search_dialog)
    search_dialog:onShowKeyboard()
    
    return search_dialog
end

-- ========== DEBUG INFO VIEWER ==========

function Dialogs:showDebugInfo(debug_info_table, server_url)
    local debug_info = "DEBUG GOTA PLUGIN v1.8\n"
    debug_info = debug_info .. "══════════════════════\n\n"
    debug_info = debug_info .. "Token status: " .. debug_info_table.token_status .. "\n"
    debug_info = debug_info .. "Config file: " .. debug_info_table.settings_file .. "\n\n"
    
    if debug_info_table.file_exists then
        debug_info = debug_info .. "File exists: YES\n"
        debug_info = debug_info .. "File size: " .. debug_info_table.file_size .. " bytes\n"
        debug_info = debug_info .. "(Content hidden for security)\n\n"
    else
        debug_info = debug_info .. "File exists: NO\n\n"
    end
    
    debug_info = debug_info .. "\nServer URL: " .. server_url
    debug_info = debug_info .. "\nSystem: REFACTORED v1.8"
    debug_info = debug_info .. "\nModules: API, Settings, ContentProcessor, GotaReader, UIBuilder, Dialogs, ArticleManager"
    
    local text_viewer = TextViewer:new{
        title = "Debug Info - Gota Plugin",
        text = debug_info,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(text_viewer)
    
    return text_viewer
end

-- ========== LINK INFO VIEWER ==========

function Dialogs:showLinkInfo(raindrop)
    if not raindrop or not raindrop.link then
        return nil
    end
    
    local content = _("Article URL:") .. "\n\n"
    content = content .. raindrop.link .. "\n\n"
    content = content .. _("Cannot be opened directly in KOReader.") .. "\n"
    content = content .. _("You can copy this URL to open it on another device.")
    
    local text_viewer = TextViewer:new{
        title = _("Article link"),
        text = content,
        width = Device.screen:getWidth() * 0.95,
        height = Device.screen:getHeight() * 0.95,
    }
    
    UIManager:show(text_viewer)
    
    return text_viewer
end

-- ========== ARTICLE INFO VIEWER ==========

function Dialogs:showArticleInfo(raindrop, formatted_info)
    local text_viewer = TextViewer:new{
        title = raindrop.title or _("Article information"),
        text = formatted_info,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(text_viewer)
    
    return text_viewer
end

-- ========== CONTENT VIEWER (with buttons) ==========

function Dialogs:showContentViewer(title, content, buttons_table)
    local text_viewer = TextViewer:new{
        title = title,
        text = content,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
        buttons = buttons_table,
    }
    
    UIManager:show(text_viewer)
    
    return text_viewer
end

-- ========== ADVANCED SEARCH DIALOG ==========

function Dialogs:showAdvancedSearchDialog(filters_data, callbacks)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    
    -- Construir lista de tags para mostrar
    local tags_text = _("Available tags") .. " (" .. _("case-insensitive") .. "):\n"
    if filters_data and filters_data.tags and #filters_data.tags > 0 then
        for i, tag in ipairs(filters_data.tags) do
            if i <= 10 then  -- Mostrar solo los 10 más populares
                tags_text = tags_text .. string.format("• %s (%d)\n", tag._id, tag.count)
            end
        end
    else
        tags_text = tags_text .. _("No tags available")
    end
    
    -- Construir lista de tipos
    local types_text = "\n" .. _("Available types") .. ":\n"
    local type_names = {
        article = _("Article"),
        image = _("Image"),
        video = _("Video"),
        document = _("Document"),
        link = _("Link")
    }
    if filters_data and filters_data.types and #filters_data.types > 0 then
        for _, type_info in ipairs(filters_data.types) do
            local display_name = type_names[type_info._id] or type_info._id
            types_text = types_text .. string.format("• %s (%d)\n", display_name, type_info.count)
        end
    end
    
    local description = tags_text .. types_text .. "\n" .. 
                       _("Enter search criteria") .. ":"
    
    local advanced_dialog
    advanced_dialog = MultiInputDialog:new{
        title = _("Advanced Search"),
        fields = {
            {
                text = "",
                hint = _("Search term (optional)"),
                input_type = "string",
            },
            {
                text = "",
                hint = _("Tag (e.g., 'guides')"),
                input_type = "string",
            },
            {
                text = "",
                hint = _("Type (article/image/video/document)"),
                input_type = "string",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(advanced_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local fields = advanced_dialog:getFields()
                        local search_term = fields[1]
                        local tag = fields[2]
                        local type_filter = fields[3]
                        
                        -- Validar que al menos haya un criterio
                        if (not search_term or search_term == "") and 
                           (not tag or tag == "") and 
                           (not type_filter or type_filter == "") then
                            callbacks.notify(_("Please enter at least one search criterion"), 2)
                            return
                        end
                        
                        -- Construir objeto de filtros
                        local filters = {}
                        if tag and tag ~= "" then
                            -- Convertir a minúsculas y quitar espacios
                            filters.tag = tag:lower():gsub("^%s*(.-)%s*$", "%1")
                        end
                        if type_filter and type_filter ~= "" then
                            filters.type = type_filter:lower()
                        end
                        
                        UIManager:close(advanced_dialog)
                        callbacks.on_search(search_term, filters)
                    end,
                },
            },
        },
    }
    
    UIManager:show(advanced_dialog)
    advanced_dialog:onShowKeyboard()
    
    return advanced_dialog
end

return Dialogs
