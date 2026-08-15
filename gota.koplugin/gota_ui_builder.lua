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
function UIBuilder:buildCollectionItems(collections, on_select_callback)
    local items = {}

    local flattened = flattenCollections(collections)
    if #flattened == 0 then
        table.insert(items, {
            text = _("You have no collections created"),
            enabled = false,
            select_enabled = false,
        })
        return items
    end
    
    for _, entry in ipairs(flattened) do
        local collection = entry.collection
        local title = tostring(collection.title or _("Untitled"))
        local prefix = entry.depth > 0 and
            (string.rep("  ", entry.depth) .. "↳ ") or ""
        table.insert(items, {
            text = string.format("%s%s (%d)", prefix, title, tonumber(collection.count) or 0),
            callback = function()
                on_select_callback(collection._id, title)
            end,
        })
    end
    
    return items
end

-- Construye items de menú para un artículo individual
function UIBuilder:buildArticleMenu(raindrop, has_cache, callbacks)
    -- Metadata saying status=ready is not enough: reader/text actions require
    -- the HTML returned by the separate permanent-cache endpoint.
    local has_loaded_html = (has_cache == true and raindrop and raindrop.cache and
        type(raindrop.cache.text) == "string" and
        raindrop.cache.text:find("%S") ~= nil) or false
    local items = {
        {
            text = _("Open in full reader"),
            enabled = has_loaded_html,
            select_enabled = has_loaded_html,
            callback = callbacks.open_reader,
        },
        {
            text = _("View content as plain text"),
            enabled = has_loaded_html,
            select_enabled = has_loaded_html,
            callback = callbacks.show_text,
        },
        {
            text = _("View article information"),
            callback = callbacks.show_info,
        },
    }

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
    if not has_loaded_html and raindrop.cache then
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
        elseif raindrop.cache.status == "ready" then
            cache_message = _("Cached content is available; try reloading the article")
        else
            cache_message = status_names[raindrop.cache.status] or _("Cache is not available")
        end
        
        table.insert(items, 1, {
            text = cache_message,
            enabled = false,
            select_enabled = false,
        })
        
        table.insert(items, {
            text = _("Try reloading full article"),
            callback = callbacks.reload,
        })
    elseif not has_loaded_html then
        table.insert(items, 1, {
            text = _("This article has no cached content available"),
            enabled = false,
            select_enabled = false,
        })
    end
    
    return items
end

-- ========== PAGINACIÓN ==========

-- Añade items de paginación a un menú existente
function UIBuilder:addPagination(menu_items, data, page, perpage, callback)
    local total_count = data.count or 0
    if total_count <= perpage then
        return
    end
    
    local total_pages = math.ceil(total_count / perpage)
    local current_page = page + 1
    
    table.insert(menu_items, {
        text = "──────────────────",
        enabled = false,
        select_enabled = false,
    })
    
    -- Primera página
    if current_page > 3 then
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
    if current_page < total_pages then
        table.insert(menu_items, {
            text = _("Next page →"),
            callback = function() callback(page + 1) end,
        })
    end
    
    -- Última página
    if current_page < total_pages - 2 then
        table.insert(menu_items, {
            text = _("» Last page"),
            callback = function() callback(total_pages - 1) end,
        })
    end
    
    table.insert(menu_items, {
        text = string.format(_("Showing %d-%d of %d articles"),
            page * perpage + 1,
            math.min((page + 1) * perpage, total_count),
            total_count),
        enabled = false,
        select_enabled = false,
    })
end

-- Paginación simple para búsqueda
function UIBuilder:addSimplePagination(menu_items, total_count, page, perpage, callback)
    if total_count <= perpage then
        return
    end
    
    local total_pages = math.ceil(total_count / perpage)
    local current_page = page + 1
    
    table.insert(menu_items, {
        text = "──────────────────",
        enabled = false,
        select_enabled = false,
    })
    
    if page > 0 then
        table.insert(menu_items, {
            text = _("← Previous page"),
            callback = function() callback(page - 1) end,
        })
    end
    
    table.insert(menu_items, {
        text = string.format(_("Page %d of %d"), current_page, total_pages),
        enabled = false,
        select_enabled = false,
    })
    
    if current_page < total_pages then
        table.insert(menu_items, {
            text = _("Next page →"),
            callback = function() callback(page + 1) end,
        })
    end
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
