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
local util = require("util")
local _ = require("gettext")
local Version = require("gota_version")

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
        description = _("TEST TOKEN (Recommended and currently supported):\n• Go to: https://app.raindrop.io/settings/integrations\n• Create a new application\n• Copy the 'Test token'\n\nGota is intended for personal integrations. OAuth sign-in and token refresh are not implemented.\n\nSecurity warning: this KOReader TLS flow encrypts traffic but does not authenticate the remote server. Use a trusted network and treat the token as a password.\n\nPaste the token here:"),
        input = current_token,
        text_type = "password",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
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
                            if success then
                                UIManager:close(token_dialog)
                                callbacks.notify(_("Token saved successfully"), 3)
                            else
                                callbacks.notify(_("Error saving configuration: ") .. (err or _("Unknown error")))
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

function Dialogs:confirmRemoveToken(callback)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    dialog = ButtonDialog:new{
        title = _("Remove the local access token?") .. "\n\n" ..
            _("This removes Gota's local copy. It does not revoke the token in Raindrop.io."),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Remove token"),
                callback = function()
                    UIManager:close(dialog)
                    callback()
                end,
            },
        }},
    }
    UIManager:show(dialog)
    return dialog
end

-- ========== DOWNLOAD PATH DIALOG ==========

function Dialogs:showDownloadPathDialog(current_path, callbacks)
    local ButtonDialog = require("ui/widget/buttondialog")
    
    local full_path = callbacks.get_data_dir() .. "/" .. current_path .. "/"
    
    local button_dialog
    button_dialog = ButtonDialog:new{
        title = _("Export folder") .. "\n\n" ..
                _("Saved copies and annotated exports are written here. The full reader uses a temporary file instead.") .. "\n\n" ..
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
                    id = "close",
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
    local ffiUtil = require("ffi/util")
    local PathChooser = require("ui/widget/pathchooser")
    local configured_data_dir = callbacks.get_data_dir():gsub("/+$", "")
    local data_dir = ffiUtil.realpath(configured_data_dir) or configured_data_dir
    
    local path_chooser
    path_chooser = PathChooser:new{
        title = _("Long-press a folder to choose it"),
        path = data_dir,
        select_directory = true,
        select_file = false,
        show_files = false,
        show_hidden = false,
        onConfirm = function(folder_path)
            local canonical_folder = ffiUtil.realpath(folder_path) or folder_path
            local relative_path
            if canonical_folder == data_dir then
                relative_path = "gota_articles"
            elseif canonical_folder:sub(1, #data_dir + 1) == data_dir .. "/" then
                relative_path = canonical_folder:sub(#data_dir + 2):gsub("/+$", "")
            else
                callbacks.notify(_("Please select a folder inside the KOReader data folder"), 3)
                UIManager:nextTick(function() self:showFolderPicker(callbacks) end)
                return
            end

            local success, err, stored_path = callbacks.save(relative_path)

            if success then
                callbacks.notify(_("Folder configured: ") .. (stored_path or relative_path), 3)
            else
                callbacks.notify(_("Error saving: ") .. (err or _("Unknown error")))
                UIManager:nextTick(function() self:showFolderPicker(callbacks) end)
            end
        end,
    }
    
    UIManager:show(path_chooser)
    return path_chooser
end

function Dialogs:showDownloadPathInputDialog(current_path, callbacks)
    local ButtonDialog = require("ui/widget/buttondialog")
    local path_dialog
    local function savePath(path)
        local success, err, stored_path = callbacks.save(path)
        if success then
            UIManager:close(path_dialog)
            callbacks.notify(_("Folder configured: ") .. (stored_path or path), 3)
        else
            callbacks.notify(_("Error saving: ") .. (err or _("Unknown error")))
        end
    end
    path_dialog = InputDialog:new{
        title = _("Export folder"),
        description = _("Enter the folder name for saved copies and annotated exports") .. "\n\n" ..
                     _("Full path") .. ": " .. (callbacks.get_data_dir() .. "/" .. current_path .. "/"),
        input = current_path,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
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
                            local normalized, validation_error = callbacks.validate(new_path)
                            if not normalized then
                                callbacks.notify(_("Invalid export folder: ") ..
                                    (validation_error or _("Unknown error")), 3)
                                return
                            end
                            if normalized ~= new_path then
                                local confirm_dialog
                                confirm_dialog = ButtonDialog:new{
                                    title = _("The folder will be saved as:") .. "\n\n" .. normalized,
                                    buttons = {{
                                        { text = _("Cancel"), callback = function()
                                            UIManager:close(confirm_dialog)
                                        end },
                                        { text = _("Use this folder"), callback = function()
                                            UIManager:close(confirm_dialog)
                                            savePath(normalized)
                                        end },
                                    }},
                                }
                                UIManager:show(confirm_dialog)
                            else
                                savePath(normalized)
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
                    id = "close",
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
                        if search_term then
                            search_term = search_term:gsub("^%s*(.-)%s*$", "%1")
                        end
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

function Dialogs:showDebugInfo(debug_info_table, server_url, transport_security)
    local debug_info = _("GOTA PLUGIN DEBUG v") .. Version.version .. "\n"
    debug_info = debug_info .. "══════════════════════\n\n"
    local token_status = debug_info_table.token_status == "configured" and
        _("configured") or _("not configured")
    debug_info = debug_info .. _("Token status: ") .. token_status .. "\n"
    debug_info = debug_info .. _("Configuration file: ") .. debug_info_table.settings_file .. "\n\n"
    
    if debug_info_table.file_exists then
        debug_info = debug_info .. _("File exists: yes") .. "\n"
        debug_info = debug_info .. _("File size: ") .. debug_info_table.file_size .. " " .. _("bytes") .. "\n"
        debug_info = debug_info .. _("(Content hidden for security)") .. "\n\n"
    else
        debug_info = debug_info .. _("File exists: no") .. "\n\n"
    end
    
    debug_info = debug_info .. "\n" .. _("Server URL: ") .. server_url
    debug_info = debug_info .. "\n" .. _("KOReader target: ") .. Version.target_koreader
    if transport_security then
        debug_info = debug_info .. "\n" .. _("TLS encryption: ") ..
            (transport_security.encrypted and _("available") or _("not available"))
        debug_info = debug_info .. "\n" .. _("Remote TLS authentication: ") ..
            (transport_security.peer_authenticated and
                transport_security.hostname_verified and _("available") or _("not available"))
    end
    if debug_info_table.max_cache_memory_mib then
        debug_info = debug_info .. "\n" .. _("Text memory limit: ") ..
            tostring(debug_info_table.max_cache_memory_mib) .. " MiB"
    end
    if debug_info_table.max_cache_file_mib then
        debug_info = debug_info .. "\n" .. _("Reader file limit: ") ..
            tostring(debug_info_table.max_cache_file_mib) .. " MiB"
    end
    debug_info = debug_info .. "\n" ..
        _("Modules: API, Compression, Settings, ContentProcessor, GotaReader, UIBuilder, Dialogs, ArticleManager")
    
    local text_viewer = TextViewer:new{
        title = _("Debug information — Gota"),
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
    content = content .. _("Use this URL to open the article on another device.")
    
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

function Dialogs:showAdvancedSearchDialog(filters_data, initial_state, callbacks)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local ButtonDialog = require("ui/widget/buttondialog")
    initial_state = initial_state or {}
    local function copyTable(value)
        local copy = {}
        for key, item in pairs(type(value) == "table" and value or {}) do copy[key] = item end
        return copy
    end
    local function countEnabled(values)
        local count = 0
        for _, value in pairs(values) do
            if value == true or (type(value) == "string" and value ~= "") then count = count + 1 end
        end
        return count
    end
    
    -- Construir lista de tags para mostrar
    local tags_text = _("Available tags") .. " (" .. _("case-insensitive") .. "):\n"
    if filters_data and filters_data.tags and #filters_data.tags > 0 then
        for i, tag in ipairs(filters_data.tags) do
            if i <= 10 then  -- Mostrar solo los 10 más populares
                tags_text = tags_text .. string.format(
                    "• %s (%d)\n",
                    tostring(tag._id or ""),
                    tonumber(tag.count) or 0
                )
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
        audio = _("Audio"),
        document = _("Document"),
    }
    if filters_data and filters_data.types and #filters_data.types > 0 then
        for _, type_info in ipairs(filters_data.types) do
            local display_name = type_names[type_info._id]
            if display_name then
                types_text = types_text .. string.format(
                    "• %s (%d)\n",
                    display_name,
                    tonumber(type_info.count) or 0
                )
            end
        end
    end
    
    local state = {
        term = tostring(initial_state.term or ""),
        tag = tostring(initial_state.tag or ""),
        type = tostring(initial_state.type or ""),
        quick = copyTable(initial_state.quick),
        match = initial_state.match == "any" and "any" or "all",
        more = copyTable(initial_state.more),
    }
    local summary = callbacks.build_summary and callbacks.build_summary(state) or _("No active filters")
    local description = summary .. "\n\n" .. tags_text .. types_text .. "\n" ..
                       _("Enter search criteria") .. ":"
    
    local selected = state.quick
    local more_filters = state.more
    local advanced_dialog
    local function capturePrimaryFields()
        if not advanced_dialog or not advanced_dialog.getFields then return end
        local values = advanced_dialog:getFields()
        local function trim(value) return (value or ""):gsub("^%s*(.-)%s*$", "%1") end
        state.term = trim(values[1])
        state.tag = trim(values[2])
        state.type = trim(values[3]):lower()
        state.quick = selected
        state.more = more_filters
    end
    local function showQuickFilters()
        capturePrimaryFields()
        local quick_dialog
        local choices = {
            { "important", _("Favorites") },
            { "notag", _("No tags") },
            { "file", _("Uploaded files") },
            { "reminder", _("Has reminder") },
            { "cache_ready", _("Web archive ready") },
        }
        local buttons = {}
        for _, choice in ipairs(choices) do
            local key, label = choice[1], choice[2]
            buttons[#buttons + 1] = {{
                text = label .. (selected[key] and " [x]" or " [ ]"),
                callback = function()
                    selected[key] = not selected[key]
                    UIManager:close(quick_dialog)
                    showQuickFilters()
                end,
            }}
        end
        buttons[#buttons + 1] = {{
            text = state.match == "any" and _("Match mode: any") or _("Match mode: all"),
            callback = function()
                state.match = state.match == "any" and "all" or "any"
                UIManager:close(quick_dialog)
                showQuickFilters()
            end,
        }}
        buttons[#buttons + 1] = {{ text = _("Close"), id = "close", callback = function()
            UIManager:close(quick_dialog)
        end }}
        quick_dialog = ButtonDialog:new{
            title = string.format(_("Quick filters (%d)"), countEnabled(selected)),
            buttons = buttons,
        }
        UIManager:show(quick_dialog)
    end

    local function showMoreFilters()
        capturePrimaryFields()
        local more_dialog
        more_dialog = MultiInputDialog:new{
            title = string.format(_("More filters (%d)"), countEnabled(more_filters)),
            fields = {
                { text = more_filters.exclude_tag or "", hint = _("Exclude tag") },
                { text = more_filters.exclude_type or "", hint = _("Exclude type") },
                { text = more_filters.created or "", hint = _("Created date: >YYYY-MM-DD") },
                { text = more_filters.last_update or "", hint = _("Updated date: <YYYY-MM-DD") },
            },
            buttons = {{
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(more_dialog) end },
                { text = _("Save"), callback = function()
                    local values = more_dialog:getFields()
                    local candidate = {
                        exclude_tag = (values[1] or ""):gsub("^%s*(.-)%s*$", "%1"),
                        exclude_type = (values[2] or ""):gsub("^%s*(.-)%s*$", "%1"):lower(),
                        created = (values[3] or ""):gsub("^%s*(.-)%s*$", "%1"),
                        last_update = (values[4] or ""):gsub("^%s*(.-)%s*$", "%1"),
                    }
                    local allowed = { article=true, image=true, video=true, audio=true, document=true }
                    if candidate.exclude_type ~= "" and not allowed[candidate.exclude_type] then
                        callbacks.notify(_("Unsupported type filter"), 2) return
                    end
                    local function validDate(value)
                        if value == "" then return true end
                        value = value:gsub("^[<>]", "")
                        return value:match("^%d%d%d%d$") or value:match("^%d%d%d%d%-%d%d$") or
                            value:match("^%d%d%d%d%-%d%d%-%d%d$")
                    end
                    if not validDate(candidate.created) or not validDate(candidate.last_update) then
                        callbacks.notify(_("Invalid date filter; use YYYY, YYYY-MM, or YYYY-MM-DD"), 3) return
                    end
                    more_filters = candidate
                    UIManager:close(more_dialog)
                end },
            }},
        }
        UIManager:show(more_dialog)
        more_dialog:onShowKeyboard()
    end

    advanced_dialog = MultiInputDialog:new{
        title = _("Advanced Search"),
        fields = {
            {
                description = description,
                text = state.term,
                hint = _("Search term (optional)"),
            },
            {
                text = state.tag,
                hint = _("Tag (e.g., 'guides')"),
            },
            {
                text = state.type,
                hint = _("Type (link/article/image/video/audio/document)"),
            },
        },
        buttons = {
            {
                { text = _("Quick filters"), callback = showQuickFilters },
                { text = _("More filters"), callback = showMoreFilters },
            },
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        capturePrimaryFields()
                        if callbacks.on_state_change then callbacks.on_state_change(state) end
                        UIManager:close(advanced_dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local fields = advanced_dialog:getFields()
                        local function trim(value)
                            return (value or ""):gsub("^%s*(.-)%s*$", "%1")
                        end
                        local search_term = trim(fields[1])
                        local tag = trim(fields[2])
                        local type_filter = trim(fields[3]):lower()
                        state.term, state.tag, state.type = search_term, tag, type_filter
                        state.quick, state.more = selected, more_filters
                        
                        -- Validar que al menos haya un criterio
                        local has_quick = false
                        for _, value in pairs(selected) do if value then has_quick = true break end end
                        local has_more = false
                        for _, value in pairs(more_filters) do if value ~= "" then has_more = true break end end
                        if (not search_term or search_term == "") and 
                           (not tag or tag == "") and 
                           (not type_filter or type_filter == "") and not has_quick and not has_more then
                            callbacks.notify(_("Please enter at least one search criterion"), 2)
                            return
                        end
                        
                        -- Construir objeto de filtros
                        local filters = {}
                        if tag ~= "" then
                            filters.tag = tag:lower()
                        end
                        if type_filter ~= "" then
                            local allowed_types = {
                                article = true,
                                image = true,
                                video = true,
                                audio = true,
                                document = true,
                            }
                            if not allowed_types[type_filter] then
                                callbacks.notify(_("Unsupported type filter"), 2)
                                return
                            end
                            filters.type = type_filter
                        end
                        local active_filter_count = (search_term ~= "" and 1 or 0) +
                            (tag ~= "" and 1 or 0) + (type_filter ~= "" and 1 or 0)
                        for key, value in pairs(selected) do
                            if value then
                                filters[key] = true
                                active_filter_count = active_filter_count + 1
                            end
                        end
                        for key, value in pairs(more_filters) do if value ~= "" then filters[key] = value end end
                        for _, value in pairs(more_filters) do
                            if value ~= "" then active_filter_count = active_filter_count + 1 end
                        end
                        if state.match == "any" and active_filter_count > 1 then filters.match_or = true end
                        
                        UIManager:close(advanced_dialog)
                        if callbacks.on_state_change then callbacks.on_state_change(state) end
                        callbacks.on_search(state, filters)
                    end,
                },
            },
        },
    }
    
    UIManager:show(advanced_dialog)
    advanced_dialog:onShowKeyboard()
    
    return advanced_dialog
end

local function utf8CharacterCount(value)
    local count, index = 0, 1
    while index <= #value do
        local byte = value:byte(index)
        if byte and byte >= 0xF0 then index = index + 4
        elseif byte and byte >= 0xE0 then index = index + 3
        elseif byte and byte >= 0xC2 then index = index + 2
        else index = index + 1 end
        count = count + 1
    end
    return count
end

local function normalizeTagsInput(value)
    local tags, seen = {}, {}
    for line in tostring(value or ""):gmatch("[^\r\n]+") do
        local tag = line:gsub("^%s+", ""):gsub("%s+$", "")
        local key = util.stringLower and util.stringLower(tag) or tag:lower()
        if tag ~= "" and not seen[key] then
            seen[key] = true
            tags[#tags + 1] = tag
        end
    end
    return tags
end

Dialogs.normalizeTagsInput = normalizeTagsInput

function Dialogs:showEditNoteDialog(current_note, callbacks)
    local dialog
    dialog = InputDialog:new{
        title = _("Edit note"), input = current_note or "", allow_newline = true,
        use_available_height = true,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), callback = function()
                local note = dialog:getInputText() or ""
                if utf8CharacterCount(note) > 10000 then
                    callbacks.notify(_("Note must contain at most 10,000 characters"), 3) return
                end
                callbacks.save(note, dialog)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

function Dialogs:showEditTagsDialog(tags, callbacks)
    local dialog
    dialog = InputDialog:new{
        title = _("Edit tags"),
        description = _("Enter one tag per line"),
        input = table.concat(type(tags) == "table" and tags or {}, "\n"), allow_newline = true,
        use_available_height = true,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), callback = function()
                callbacks.save(normalizeTagsInput(dialog:getInputText()), dialog)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

function Dialogs:confirmMoveToTrash(title, callback)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    dialog = ButtonDialog:new{
        title = _("Move to Trash?") .. "\n\n" .. tostring(title or _("Untitled")),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Move to Trash"), callback = function()
                UIManager:close(dialog)
                callback()
            end },
        }},
    }
    UIManager:show(dialog)
    return dialog
end

return Dialogs
