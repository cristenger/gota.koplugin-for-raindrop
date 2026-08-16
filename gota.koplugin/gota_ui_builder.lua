--[[
    UI Builder Module for Gota Plugin
    Handles menu construction, pagination, and UI item builders
]]

local Menu = require("ui/widget/menu")
local Device = require("device")
local logger = require("logger")
local _ = require("gettext")

local UIBuilder = {}

function UIBuilder:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function UIBuilder.buildActiveFilterSummary(state, context, sort)
    state = state or {}
    context = context or {}
    local parts = {}
    local scope = context.collection_name and
        string.format(_("Scope: %s"), tostring(context.collection_name)) or _("Scope: all articles")
    if context.nested == true then scope = scope .. " + " .. _("subcollections") end
    parts[#parts + 1] = scope

    local sort_names = {
        ["-created"] = _("newest first"), created = _("oldest first"),
        title = _("title A-Z"), ["-title"] = _("title Z-A"),
        domain = _("domain A-Z"), ["-domain"] = _("domain Z-A"),
        ["-sort"] = _("custom order"),
    }
    parts[#parts + 1] = string.format(_("Sort: %s"), sort_names[sort] or tostring(sort or "-created"))

    local filters = {}
    local function add(label, value)
        if value ~= nil and tostring(value) ~= "" then
            filters[#filters + 1] = label .. ": " .. tostring(value)
        end
    end
    add(_("Text"), state.term)
    add(_("Tag"), state.tag)
    add(_("Type"), state.type)
    local quick = type(state.quick) == "table" and state.quick or {}
    if quick.important then filters[#filters + 1] = _("Favorites") end
    if quick.notag then filters[#filters + 1] = _("No tags") end
    if quick.file then filters[#filters + 1] = _("Uploaded files") end
    if quick.reminder then filters[#filters + 1] = _("Has reminder") end
    if quick.cache_ready then filters[#filters + 1] = _("Web copy ready") end
    local more = type(state.more) == "table" and state.more or {}
    add(_("Exclude tag"), more.exclude_tag)
    add(_("Exclude type"), more.exclude_type)
    add(_("Created"), more.created)
    add(_("Updated"), more.last_update)
    if #filters == 0 then filters[1] = _("No active filters")
    elseif #filters > 1 then
        filters[#filters + 1] = state.match == "any" and _("Match: any") or _("Match: all")
    end
    for _, filter in ipairs(filters) do parts[#parts + 1] = filter end
    return table.concat(parts, " · ")
end

-- ========== MENU BUILDERS ==========

-- Type abbreviations for the mandatory field
local TYPE_ABBREV = {
    article  = _("Art."),
    link     = _("Link"),
    image    = _("Img."),
    video    = _("Vid."),
    document = _("Doc."),
    audio    = _("Aud."),
}

local HIGHLIGHT_COLORS = {
    blue=_("Blue"), brown=_("Brown"), cyan=_("Cyan"), gray=_("Gray"),
    green=_("Green"), indigo=_("Indigo"), orange=_("Orange"), pink=_("Pink"),
    purple=_("Purple"), red=_("Red"), teal=_("Teal"), yellow=_("Yellow"),
}

local function hasHighlights(raindrop)
    return raindrop and type(raindrop.highlights) == "table" and
        #raindrop.highlights > 0
end

local function truncateUTF8ByCharacters(value, max_characters)
    if type(value) ~= "string" then
        value = value == nil and "" or tostring(value)
    end

    local index = 1
    local characters = 0
    local last_complete = 0
    while index <= #value and characters < max_characters do
        local first = value:byte(index)
        local length = 1
        if first and first >= 0xC2 and first <= 0xDF then
            length = 2
        elseif first and first >= 0xE0 and first <= 0xEF then
            length = 3
        elseif first and first >= 0xF0 and first <= 0xF4 then
            length = 4
        end
        if index + length - 1 > #value then
            break
        end
        last_complete = index + length - 1
        index = index + length
        characters = characters + 1
    end
    return value:sub(1, last_complete), index <= #value
end

UIBuilder.truncateUTF8ByCharacters = truncateUTF8ByCharacters

local function handleMenuHold(_, item)
    if item and item.hold_callback then
        item.hold_callback()
    end
    return true
end

local function normalizeMenuText(value)
    return tostring(value or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function buildRowStatuses(raindrop)
    local statuses = {}
    if raindrop.important then statuses[#statuses + 1] = _("Favorite") end
    if raindrop.note and raindrop.note ~= "" then statuses[#statuses + 1] = _("Note") end
    if hasHighlights(raindrop) then
        statuses[#statuses + 1] = string.format(_("%d highlights"), #raindrop.highlights)
    end
    if raindrop.file and raindrop.file.name then statuses[#statuses + 1] = _("File") end
    if raindrop.reminder and raindrop.reminder.data then statuses[#statuses + 1] = _("Reminder") end
    if raindrop.broken then statuses[#statuses + 1] = _("Broken link") end
    if raindrop.cache and raindrop.cache.status == "ready" then
        statuses[#statuses + 1] = _("Web copy")
    end
    return statuses
end

local function collectionParentID(collection)
    local parent = collection and collection.parent or nil
    if type(parent) == "table" then
        return parent["$id"] or parent._id or parent.id
    elseif type(parent) == "number" or type(parent) == "string" then
        return parent
    end
    return nil
end

-- Turn a combined root + child collection response into a stable pre-order
-- hierarchy. Input order is preserved for roots and for siblings.
local function flattenCollections(collections)
    local source = collections and collections.items or collections or {}
    local ordered = {}
    local by_id = {}

    for _, collection in ipairs(source) do
        local id = collection and collection._id
        local key = id ~= nil and tostring(id) or nil
        if not key or not by_id[key] then
            ordered[#ordered + 1] = collection
            if key then
                by_id[key] = collection
            end
        end
    end

    local roots = {}
    local children = {}
    for _, collection in ipairs(ordered) do
        local id = collection and collection._id
        local id_key = id ~= nil and tostring(id) or nil
        local parent_id = collectionParentID(collection)
        local parent_key = parent_id ~= nil and tostring(parent_id) or nil
        if parent_key and by_id[parent_key] and parent_key ~= id_key then
            children[parent_key] = children[parent_key] or {}
            children[parent_key][#children[parent_key] + 1] = collection
        else
            roots[#roots + 1] = collection
        end
    end

    local flattened = {}
    local visited = {}
    local function appendBranch(collection, depth)
        local id = collection and collection._id
        local key = id ~= nil and tostring(id) or tostring(collection)
        if visited[key] then
            return
        end
        visited[key] = true
        flattened[#flattened + 1] = {
            collection = collection,
            depth = depth,
        }
        for _, child in ipairs(children[key] or {}) do
            appendBranch(child, depth + 1)
        end
    end

    for _, root in ipairs(roots) do
        appendBranch(root, 0)
    end
    -- Cycles or incomplete parent data should not make a collection disappear.
    for _, collection in ipairs(ordered) do
        appendBranch(collection, 0)
    end

    return flattened
end

UIBuilder.flattenCollections = flattenCollections

local function collectionID(value)
    if type(value) == "table" then
        return value["$id"] or value._id or value.id
    end
    return value
end

local function flattenCollectionStructure(structure, collapsed_groups, expand_all_groups)
    structure = type(structure) == "table" and structure or {}
    collapsed_groups = type(collapsed_groups) == "table" and collapsed_groups or {}
    local roots = type(structure.roots) == "table" and structure.roots or {}
    local children_source = type(structure.children) == "table" and structure.children or {}
    local groups_source = type(structure.groups) == "table" and structure.groups or {}
    local by_id, source_index, children_by_parent = {}, {}, {}

    local function register(collection, index)
        local id = collection and collection._id
        if id == nil then return end
        local key = tostring(id)
        if not by_id[key] then
            by_id[key] = collection
            source_index[key] = index
        end
    end
    for index, collection in ipairs(roots) do register(collection, index) end
    for index, collection in ipairs(children_source) do register(collection, #roots + index) end
    for _, collection in ipairs(children_source) do
        local parent_id = collectionParentID(collection)
        if parent_id ~= nil then
            local key = tostring(parent_id)
            children_by_parent[key] = children_by_parent[key] or {}
            children_by_parent[key][#children_by_parent[key] + 1] = collection
        end
    end
    for _, siblings in pairs(children_by_parent) do
        table.sort(siblings, function(left, right)
            local left_sort, right_sort = tonumber(left.sort) or 0, tonumber(right.sort) or 0
            if left_sort == right_sort then
                return (source_index[tostring(left._id)] or 0) <
                    (source_index[tostring(right._id)] or 0)
            end
            return left_sort > right_sort
        end)
    end

    local groups = {}
    for index, group in ipairs(groups_source) do
        if type(group) == "table" then groups[#groups + 1] = { group = group, index = index } end
    end
    table.sort(groups, function(left, right)
        local left_sort, right_sort = tonumber(left.group.sort) or 0, tonumber(right.group.sort) or 0
        if left_sort == right_sort then return left.index < right.index end
        return left_sort < right_sort
    end)

    local entries, visited, visiting, grouped = {}, {}, {}, {}
    local function appendBranch(collection, depth, group_key)
        local id = collection and collection._id
        local key = id ~= nil and tostring(id) or tostring(collection)
        if visited[key] or visiting[key] then return end
        visiting[key] = true
        visited[key] = true
        entries[#entries + 1] = {
            kind = "collection",
            collection = collection,
            depth = depth,
            group_key = group_key,
        }
        for _, child in ipairs(children_by_parent[key] or {}) do
            appendBranch(child, depth + 1, group_key)
        end
        visiting[key] = nil
    end
    local function markGroupedBranch(collection)
        local id = collection and collection._id
        local key = id ~= nil and tostring(id) or nil
        if not key or grouped[key] then return end
        grouped[key] = true
        for _, child in ipairs(children_by_parent[key] or {}) do markGroupedBranch(child) end
    end

    for _, wrapped in ipairs(groups) do
        local group = wrapped.group
        local key = tostring(group._id or group.title or wrapped.index)
        local collapsed = false
        if not expand_all_groups then
            collapsed = collapsed_groups[key]
            if collapsed == nil then collapsed = group.hidden == true end
        end
        entries[#entries + 1] = {
            kind = "group",
            key = key,
            title = tostring(group.title or _("Collections")),
            collapsed = collapsed,
        }
        for _, reference in ipairs(type(group.collections) == "table" and group.collections or {}) do
            local root = by_id[tostring(collectionID(reference))]
            if root then
                markGroupedBranch(root)
                if not collapsed then appendBranch(root, 0, key) end
            end
        end
    end

    local other_start = #entries + 1
    for _, root in ipairs(roots) do
        local key = root and root._id ~= nil and tostring(root._id) or nil
        if not key or not grouped[key] then appendBranch(root, 0, "other") end
    end
    for _, child in ipairs(children_source) do
        local key = child and child._id ~= nil and tostring(child._id) or nil
        if not key or (not grouped[key] and not visited[key]) then appendBranch(child, 0, "other") end
    end
    if #entries >= other_start then
        table.insert(entries, other_start, {
            kind = "group",
            key = "other",
            title = _("Other collections"),
            collapsed = false,
            informational = true,
        })
    end
    return entries
end

UIBuilder.flattenCollectionStructure = flattenCollectionStructure

function UIBuilder:buildRaindropItems(raindrops, on_select_callback, on_hold_callback)
    local items = {}

    if not raindrops or not raindrops.items or #raindrops.items == 0 then
        table.insert(items, {
            text = _("No articles available"),
            enabled = false,
            select_enabled = false,
        })
        return items
    end

    for _, raindrop in ipairs(raindrops.items) do
        local title = normalizeMenuText(raindrop.title or _("Untitled"))
        local domain = normalizeMenuText(raindrop.domain)
        local excerpt = ""
        if type(raindrop.excerpt) == "string" and raindrop.excerpt ~= "" then
            local normalized = normalizeMenuText(raindrop.excerpt)
            local preview, truncated = truncateUTF8ByCharacters(normalized, 50)
            if preview ~= "" then
                excerpt = preview .. (truncated and "..." or "")
            end
        end

        local text = title
        if domain ~= "" then text = text .. " — " .. domain end
        if excerpt ~= "" then text = text .. " · " .. excerpt end
        local statuses = buildRowStatuses(raindrop)
        if #statuses > 0 then text = text .. " · " .. table.concat(statuses, " · ") end

        local item = {
            text = text,
            mandatory = TYPE_ABBREV[raindrop.type] or "",
            gota_raindrop_id = tostring(raindrop._id),
            callback = function()
                on_select_callback(raindrop)
            end,
        }

        -- Hold callback for quick info popup (no API calls)
        if on_hold_callback then
            item.hold_callback = function()
                on_hold_callback(raindrop)
            end
        end

        table.insert(items, item)
    end

    return items
end

-- Construye items de menú para colecciones
function UIBuilder:buildCollectionItems(collections, on_select_callback, options)
    local items = {}
    options = options or {}
    local flattened
    if collections and (collections.roots or collections.groups or collections.children) then
        flattened = flattenCollectionStructure(collections, options.collapsed_groups,
            options.expand_all_groups == true)
    else
        flattened = flattenCollections(collections)
        for _, entry in ipairs(flattened) do entry.kind = "collection" end
    end
    if #flattened == 0 then
        table.insert(items, {
            text = _("You have no collections created"),
            enabled = false,
            select_enabled = false,
        })
        return items
    end
    
    for _, entry in ipairs(flattened) do
        if entry.kind == "group" then
            local indicator = entry.informational and "• " or
                (entry.collapsed and "▸ " or "▾ ")
            table.insert(items, {
                text = indicator .. entry.title,
                enabled = not entry.informational,
                select_enabled = not entry.informational,
                callback = not entry.informational and options.on_toggle_group and function()
                    options.on_toggle_group(entry.key, not entry.collapsed)
                end or nil,
            })
        else
            local collection = entry.collection
            local title = tostring(collection.title or _("Untitled"))
            local prefix = entry.depth > 0 and
                (string.rep("  ", entry.depth) .. "↳ ") or ""
            local count = tonumber(collection.count)
            table.insert(items, {
                text = prefix .. title .. (count and string.format(" (%d)", count) or ""),
                callback = function()
                    on_select_callback(collection._id, title, collection)
                end,
            })
        end
    end
    
    return items
end

-- Construye items de menú para un artículo individual
function UIBuilder:buildArticleMenu(raindrop, cache_available, callbacks)
    local items = {
        {
            text = _("Open in full reader"),
            enabled = cache_available,
            select_enabled = cache_available,
            callback = callbacks.open_reader,
        },
        {
            text = _("View content as plain text"),
            enabled = cache_available,
            select_enabled = cache_available,
            callback = callbacks.show_text,
        },
        {
            text = _("Save original copy"),
            enabled = cache_available,
            select_enabled = cache_available,
            callback = callbacks.save_html,
        },
        {
            text = _("View article information"),
            callback = callbacks.show_info,
        },
    }
    if not cache_available or not callbacks.save_html then
        table.remove(items, 3)
    end

    if callbacks.toggle_favorite then
        table.insert(items, { text = raindrop.important and _("Remove from favorites") or
            _("Add to favorites"), callback = callbacks.toggle_favorite })
    end
    if callbacks.edit_note then table.insert(items, { text = _("Edit note"), callback = callbacks.edit_note }) end
    if callbacks.edit_tags then table.insert(items, { text = _("Edit tags"), callback = callbacks.edit_tags }) end
    if callbacks.move_collection then
        table.insert(items, { text = callbacks.in_trash and _("Restore / move to collection") or
            _("Move to collection"), callback = callbacks.move_collection })
    end
    if callbacks.move_to_trash and not callbacks.in_trash then
        table.insert(items, { text = _("Move to Trash"), callback = callbacks.move_to_trash })
    end

    -- Agregar opción de Notes si existen (NUEVO)
    if raindrop.note and raindrop.note ~= "" then
        table.insert(items, {
            text = _("View notes"),
            callback = callbacks.show_notes,
        })
    end

    -- Agregar opción de Highlights si existen (NUEVO)
    if hasHighlights(raindrop) then
        table.insert(items, {
            text = string.format(_("View highlights (%d)"), #raindrop.highlights),
            callback = callbacks.show_highlights,
        })
    end

    -- Agregar opción de descarga HTML con notes/highlights si hay contenido
    if (raindrop.note and raindrop.note ~= "") or
       hasHighlights(raindrop) then
        table.insert(items, {
            text = _("Export with notes & highlights"),
            enabled = true,
            select_enabled = true,
            callback = callbacks.save_html_with_notes,
        })
    end

    if raindrop.link then
        table.insert(items, {
            text = _("Show article URL"),
            callback = callbacks.show_link,
        })
    end
    
    -- Mensaje de estado del caché
    if not cache_available and raindrop.cache then
        local status_names = {
            retry = _("Cache is being generated, try again later"),
            failed = _("Cache generation has failed"),
            ["invalid-origin"] = _("Could not generate cache due to invalid origin"),
            ["invalid-timeout"] = _("Could not generate cache due to timeout"),
            ["invalid-size"] = _("Could not generate cache due to excessive size")
        }
        local tracked_state = raindrop._gota_cache_state
        local cache_message
        if tracked_state and tracked_state.download_error then
            cache_message = _("Cached content could not be downloaded; try again")
        else cache_message = status_names[raindrop.cache.status] or _("Cache is not available") end
        
        table.insert(items, 1, {
            text = cache_message,
            enabled = false,
            select_enabled = false,
        })
        
        table.insert(items, {
            text = _("Try reloading full article"),
            callback = callbacks.reload,
        })
    elseif not cache_available then
        table.insert(items, 1, {
            text = _("This article has no cached content available"),
            enabled = false,
            select_enabled = false,
        })
    end
    if cache_available and callbacks.reload then
        table.insert(items, {
            text = _("Reload article metadata"),
            callback = callbacks.reload,
        })
    end
    
    return items
end

-- ========== PAGINACIÓN ==========

-- Añade items de paginación a un menú existente
function UIBuilder:buildRemotePagination(data, page, perpage, callback)
    local total_count = data.count
    local item_count = type(data.items) == "table" and #data.items or 0
    local has_previous = page > 0
    local has_next = total_count ~= nil and ((page + 1) * perpage < total_count)
        or (total_count == nil and item_count == perpage)
    local total_pages = total_count and math.ceil(total_count / perpage) or nil
    local current_page = page + 1
    local controls = {}
    local status_text = total_pages and string.format(_("Raindrop page %d of %d"), current_page,
        math.max(total_pages, 1)) or string.format(_("Raindrop page %d"), current_page)
    controls[#controls + 1] = {
        text = status_text,
        enabled = false,
        select_enabled = false,
    }

    if total_pages and current_page > 3 then
        controls[#controls + 1] = {
            text = _("Raindrop: first page"),
            callback = function() callback(0) end,
        }
    end

    if has_previous then
        controls[#controls + 1] = {
            text = _("Raindrop: previous page"),
            callback = function() callback(page - 1) end,
        }
    end

    if has_next then
        controls[#controls + 1] = {
            text = _("Raindrop: next page"),
            callback = function() callback(page + 1) end,
        }
    end

    if total_pages and current_page < total_pages - 2 then
        controls[#controls + 1] = {
            text = _("Raindrop: last page"),
            callback = function() callback(total_pages - 1) end,
        }
    end

    local subtitle
    if total_count ~= nil then
        local first = total_count == 0 and 0 or page * perpage + 1
        local last = math.min((page + 1) * perpage, total_count)
        subtitle = string.format(_("%d–%d of %d articles · Raindrop page %d/%d"),
            first, last, total_count, current_page, math.max(total_pages, 1))
    else
        subtitle = string.format(_("%d articles · Raindrop page %d"), item_count, current_page)
    end
    return controls, subtitle, has_previous or has_next
end

function UIBuilder:addPagination(menu_items, data, page, perpage, callback)
    local top, subtitle, navigable = self:buildRemotePagination(data, page, perpage, callback)
    if not navigable then return subtitle end

    for index = #top, 1, -1 do table.insert(menu_items, 1, top[index]) end
    table.insert(menu_items, #top + 1, {
        text = "──────────────────", enabled = false, select_enabled = false,
    })
    menu_items[#menu_items + 1] = {
        text = "──────────────────", enabled = false, select_enabled = false,
    }
    local bottom = self:buildRemotePagination(data, page, perpage, callback)
    for _, item in ipairs(bottom) do menu_items[#menu_items + 1] = item end
    return subtitle
end

-- Paginación simple para búsqueda
function UIBuilder:addSimplePagination(menu_items, total_count, page, perpage, callback)
    self:addPagination(menu_items, {
        count = total_count,
        items = total_count == nil and {} or nil,
    }, page, perpage, callback)
end

function UIBuilder:buildHighlightItems(response, on_select_callback)
    local items = {}
    for _, highlight in ipairs(response and response.items or {}) do
        local preview, truncated = truncateUTF8ByCharacters(
            normalizeMenuText(highlight.text or _("Highlight without text")), 90)
        local details = {}
        local reference = type(highlight.raindropRef) == "table" and highlight.raindropRef or {}
        local source_title = highlight.title or reference.title
        if source_title and source_title ~= "" then
            local title_preview, title_truncated = truncateUTF8ByCharacters(
                normalizeMenuText(source_title), 45)
            details[#details + 1] = title_preview .. (title_truncated and "..." or "")
        end
        if highlight.note and highlight.note ~= "" then details[#details + 1] = _("Note") end
        if HIGHLIGHT_COLORS[highlight.color] then
            details[#details + 1] = HIGHLIGHT_COLORS[highlight.color]
        end
        items[#items + 1] = {
            text = preview .. (truncated and "..." or "") ..
                (#details > 0 and (" — " .. table.concat(details, " · ")) or ""),
            gota_raindrop_id = reference._id and tostring(reference._id) or nil,
            callback = function() on_select_callback(highlight) end,
        }
    end
    if #items == 0 then
        items[1] = { text = _("No highlights available"), enabled = false, select_enabled = false }
    end
    return items
end

-- ========== MENU CREATION ==========

-- Crea un menú completo con items
function UIBuilder:createMenu(title, items, options)
    options = options or {}
    local menu = Menu:new{
        title = title,
        subtitle = options.subtitle,
        item_table = items,
        onMenuHold = handleMenuHold,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
        items_max_lines = options.items_max_lines,
        multilines_forced = options.multilines_forced,
    }
    if options.focus_raindrop_id ~= nil and type(menu.switchItemTable) == "function" then
        menu:switchItemTable(nil, nil, 0, {
            gota_raindrop_id = tostring(options.focus_raindrop_id),
        })
    end
    return menu
end

-- Crea menú con ancho/alto personalizado
function UIBuilder:createCustomMenu(title, items, width_factor, height_factor)
    width_factor = width_factor or 0.9
    height_factor = height_factor or 0.8
    
    return Menu:new{
        title = title,
        item_table = items,
        onMenuHold = handleMenuHold,
        width = Device.screen:getWidth() * width_factor,
        height = Device.screen:getHeight() * height_factor,
    }
end

-- ========== BOTONES PARA TEXT VIEWER ==========

-- Construye tabla de botones para visor de contenido
function UIBuilder:buildContentViewerButtons(callbacks, raindrop)
    local buttons = {
        {
            {
                text = _("Close"),
                callback = callbacks.close,
            },
            {
                text = _("Open in reader"),
                callback = callbacks.open_reader,
            },
        },
        {
            {
                text = _("Show article URL"),
                callback = callbacks.show_link,
            },
            {
                text = _("Save original copy"),
                callback = callbacks.save_html,
            },
        },
    }

    -- Solo agregar botón de notes/highlights si hay contenido disponible
    if raindrop and
       ((raindrop.note and raindrop.note ~= "") or hasHighlights(raindrop)) then
        table.insert(buttons, {
            {
                text = _("Export with notes & highlights"),
                callback = callbacks.save_html_with_notes,
            },
        })
    end

    return buttons
end

return UIBuilder
