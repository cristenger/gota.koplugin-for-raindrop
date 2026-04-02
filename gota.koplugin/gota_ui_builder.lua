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
    -- Has highlights (available in list endpoint as count or array)
    if raindrop.highlights and #raindrop.highlights > 0 then
        table.insert(parts, "H")
    end
    return table.concat(parts, " ")
end

function UIBuilder:buildRaindropItems(raindrops, on_select_callback, on_hold_callback)
    local items = {}

    if not raindrops or not raindrops.items or #raindrops.items == 0 then
        table.insert(items, {
            text = _("No articles available"),
            enabled = false,
        })
        return items
    end

    for _, raindrop in ipairs(raindrops.items) do
        local title = raindrop.title or _("Untitled")
        local domain = raindrop.domain or ""
        local excerpt = ""
        if raindrop.excerpt then
            excerpt = "\n" .. raindrop.excerpt:sub(1, 50) .. "..."
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
    
    if not collections or not collections.items or #collections.items == 0 then
        table.insert(items, {
            text = _("You have no collections created"),
            enabled = false,
        })
        return items
    end
    
    for _, collection in ipairs(collections.items) do
        table.insert(items, {
            text = string.format("%s (%d)", collection.title, collection.count or 0),
            callback = function()
                on_select_callback(collection._id, collection.title)
            end,
        })
    end
    
    return items
end

-- Construye items de menú para un artículo individual
function UIBuilder:buildArticleMenu(raindrop, has_cache, callbacks)
    local items = {
        {
            text = _("Open in full reader"),
            enabled = has_cache,
            callback = callbacks.open_reader,
        },
        {
            text = _("View content as plain text"),
            enabled = has_cache,
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
    if raindrop.highlights and #raindrop.highlights > 0 then
        table.insert(items, {
            text = string.format(_("View highlights (%d)"), #raindrop.highlights),
            callback = callbacks.show_highlights,
        })
    end

    -- Agregar opción de descarga HTML con notes/highlights si hay contenido
    if (raindrop.note and raindrop.note ~= "") or
       (raindrop.highlights and #raindrop.highlights > 0) then
        table.insert(items, {
            text = _("Save HTML with notes & highlights"),
            enabled = has_cache,
            callback = callbacks.save_html_with_notes,
        })
    end

    if raindrop.link then
        table.insert(items, {
            text = _("Copy URL"),
            callback = callbacks.show_link,
        })
    end
    
    -- Mensaje de estado del caché
    if not has_cache and raindrop.cache then
        local status_names = {
            retry = _("Cache is being generated, try again later"),
            failed = _("Cache generation has failed"),
            ["invalid-origin"] = _("Could not generate cache due to invalid origin"),
            ["invalid-timeout"] = _("Could not generate cache due to timeout"),
            ["invalid-size"] = _("Could not generate cache due to excessive size")
        }
        local cache_message = status_names[raindrop.cache.status] or _("Cache is not available")
        
        table.insert(items, 1, {
            text = cache_message,
            enabled = false,
        })
        
        table.insert(items, {
            text = _("Try reloading full article"),
            callback = callbacks.reload,
        })
    elseif not has_cache then
        table.insert(items, 1, {
            text = _("This article has no cached content available"),
            enabled = false,
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
    
    table.insert(menu_items, {text = "──────────────────", enabled = false})
    
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
    })
end

-- Paginación simple para búsqueda
function UIBuilder:addSimplePagination(menu_items, total_count, page, perpage, callback)
    if total_count <= perpage then
        return
    end
    
    local total_pages = math.ceil(total_count / perpage)
    local current_page = page + 1
    
    table.insert(menu_items, {text = "──────────────────", enabled = false})
    
    if page > 0 then
        table.insert(menu_items, {
            text = _("← Previous page"),
            callback = function() callback(page - 1) end,
        })
    end
    
    table.insert(menu_items, {
        text = string.format(_("Page %d of %d"), current_page, total_pages),
        enabled = false,
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
                text = _("Share link"),
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
       ((raindrop.note and raindrop.note ~= "") or
        (raindrop.highlights and #raindrop.highlights > 0)) then
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
