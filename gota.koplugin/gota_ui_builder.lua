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

-- ========== MENU BUILDERS ==========

-- Type abbreviations for the mandatory field
local TYPE_ABBREV = {
    article  = "Art",
    link     = "Lnk",
    image    = "Img",
    video    = "Vid",
    document = "Doc",
    audio    = "Aud",
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

-- Build status badge string for a raindrop (right-aligned in menu)
local function buildBadge(raindrop)
    local parts = {}
    -- Type indicator
    local type_abbr = TYPE_ABBREV[raindrop.type] or ""
    if type_abbr ~= "" then
        table.insert(parts, type_abbr)
    end
    if raindrop.broken then
        table.insert(parts, _("Broken"))
    elseif raindrop.reminder and raindrop.reminder.data then
        table.insert(parts, _("Reminder"))
    elseif raindrop.file and raindrop.file.name then
        table.insert(parts, _("File"))
    elseif raindrop.cache and raindrop.cache.status == "ready" then
        table.insert(parts, _("Cached"))
    end
    -- Favorite
    if raindrop.important then
        table.insert(parts, "*")
    end
    -- Has note
    if raindrop.note and raindrop.note ~= "" then
        table.insert(parts, "N")
    end
    -- Raindrop documents highlights as an array.
    if hasHighlights(raindrop) then
        table.insert(parts, "H")
    end
    return table.concat(parts, " ")
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
        local title = tostring(raindrop.title or _("Untitled"))
        local domain = tostring(raindrop.domain or "")
        local excerpt = ""
        if type(raindrop.excerpt) == "string" and raindrop.excerpt ~= "" then
            local normalized = raindrop.excerpt:gsub("%s+", " ")
                :gsub("^%s+", ""):gsub("%s+$", "")
            local preview, truncated = truncateUTF8ByCharacters(normalized, 50)
            if preview ~= "" then
                excerpt = "\n" .. preview .. (truncated and "..." or "")
            end
        end

        local item = {
            text = title .. "\n" .. domain .. excerpt,
            mandatory = buildBadge(raindrop),
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
            text = _("View article information"),
            callback = callbacks.show_info,
        },
    }

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
            text = _("Save HTML with notes & highlights"),
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
function UIBuilder:addPagination(menu_items, data, page, perpage, callback)
    local total_count = data.count
    local item_count = type(data.items) == "table" and #data.items or 0
    local has_previous = page > 0
    local has_next = total_count ~= nil and ((page + 1) * perpage < total_count)
        or (total_count == nil and item_count == perpage)
    if not has_previous and not has_next and total_count ~= nil and total_count <= perpage then
        return
    end
    local total_pages = total_count and math.ceil(total_count / perpage) or nil
    local current_page = page + 1
    
    table.insert(menu_items, {
        text = "──────────────────",
        enabled = false,
        select_enabled = false,
    })
    
    -- Primera página
    if total_pages and current_page > 3 then
        table.insert(menu_items, {
            text = _("« First page"),
            callback = function() callback(0) end,
        })
    end
    
    -- Página anterior
    if page > 0 then
        table.insert(menu_items, {
            text = _("← Previous page"),
            callback = function() callback(page - 1) end,
        })
    end
    
    -- Página siguiente
    if has_next then
        table.insert(menu_items, {
            text = _("Next page →"),
            callback = function() callback(page + 1) end,
        })
    end
    
    -- Última página
    if total_pages and current_page < total_pages - 2 then
        table.insert(menu_items, {
            text = _("» Last page"),
            callback = function() callback(total_pages - 1) end,
        })
    end
    
    local status_text = total_count and string.format(_("Showing %d-%d of %d articles"),
        page * perpage + 1, math.min((page + 1) * perpage, total_count), total_count)
        or string.format(_("Page %d (%d items)"), current_page, item_count)
    table.insert(menu_items, {
        text = status_text,
        enabled = false,
        select_enabled = false,
    })
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
            tostring(highlight.text or _("Highlight without text")):gsub("%s+", " "), 90)
        local details = {}
        local reference = type(highlight.raindropRef) == "table" and highlight.raindropRef or {}
        local source_title = highlight.title or reference.title
        if source_title and source_title ~= "" then
            local title_preview, title_truncated = truncateUTF8ByCharacters(
                tostring(source_title):gsub("%s+", " "), 45)
            details[#details + 1] = title_preview .. (title_truncated and "..." or "")
        end
        if highlight.note and highlight.note ~= "" then details[#details + 1] = _("Note") end
        if HIGHLIGHT_COLORS[highlight.color] then
            details[#details + 1] = HIGHLIGHT_COLORS[highlight.color]
        end
        items[#items + 1] = {
            text = preview .. (truncated and "..." or "") ..
                (#details > 0 and ("\n" .. table.concat(details, " · ")) or ""),
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
function UIBuilder:createMenu(title, items)
    return Menu:new{
        title = title,
        item_table = items,
        onMenuHold = handleMenuHold,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
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
                text = _("Save HTML"),
                callback = callbacks.save_html,
            },
        },
    }

    -- Solo agregar botón de notes/highlights si hay contenido disponible
    if raindrop and
       ((raindrop.note and raindrop.note ~= "") or hasHighlights(raindrop)) then
        table.insert(buttons, {
            {
                text = _("Save HTML with notes & highlights"),
                callback = callbacks.save_html_with_notes,
            },
        })
    end

    return buttons
end

return UIBuilder
