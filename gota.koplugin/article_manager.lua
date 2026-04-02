--[[
    Article Manager Module for Gota Plugin
    Handles all article-related operations: viewing, downloading, opening in reader
]]

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local ArticleManager = {}

function ArticleManager:new(api, content_processor, gota_reader, callbacks)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    
    o.api = api
    o.content_processor = content_processor
    o.gota_reader = gota_reader
    o.callbacks = callbacks  -- notify, showProgress, hideProgress
    o.settings = nil  -- Se establecerá después
    
    return o
end

function ArticleManager:setSettings(settings)
    self.settings = settings
end

-- ========== ARTICLE CONTENT LOADING ==========

-- Carga el contenido completo de un artículo con caché
function ArticleManager:loadFullArticle(raindrop)
    if raindrop.cache then
        return raindrop, nil
    end
    
    self.callbacks.showProgress(_("Loading full content..."))
    local full_raindrop, err = self.api:getRaindrop(raindrop._id)
    self.callbacks.hideProgress()
    
    if full_raindrop and full_raindrop.item then
        return full_raindrop.item, nil
    end
    
    return raindrop, err
end

-- Carga el contenido del caché si no está presente
function ArticleManager:loadCacheContent(raindrop)
    -- Si ya tiene texto o no hay caché, no hacer nada
    if not raindrop.cache or raindrop.cache.text then
        return raindrop
    end
    
    -- Si el caché no está listo, no intentar cargarlo
    if raindrop.cache.status ~= "ready" then
        logger.dbg("ArticleManager: Caché no está listo, status:", raindrop.cache.status)
        return raindrop
    end
    
    self.callbacks.showProgress(_("Loading cached content..."))
    local cache_content, err = self.api:getRaindropCache(raindrop._id)
    self.callbacks.hideProgress()
    
    if cache_content and type(cache_content) == "string" and #cache_content > 0 then
        raindrop.cache.text = cache_content
        logger.dbg("ArticleManager: Contenido HTML cargado, longitud:", #cache_content)
    else
        -- Si falla la carga, registrar el error
        logger.warn("ArticleManager: No se pudo cargar caché:", err or "contenido vacío")
        -- NO establecer texto por defecto, dejar que hasValidCache retorne false
    end
    
    return raindrop
end

-- Verifica si un artículo tiene caché disponible
function ArticleManager:hasValidCache(raindrop)
    -- Primero verificar que existe el objeto cache
    if not raindrop.cache then
        return false
    end
    
    -- El caché solo es válido si status == "ready"
    if raindrop.cache.status ~= "ready" then
        return false
    end
    
    -- Si ya tenemos el texto cargado, verificar que tenga contenido útil
    if raindrop.cache.text then
        return #raindrop.cache.text >= 50
    end
    
    -- Si no tenemos texto pero status == "ready" y size > 0, 
    -- significa que está disponible para descarga
    return raindrop.cache.size and raindrop.cache.size > 0
end

-- ========== ARTICLE RELOADING ==========

function ArticleManager:reloadArticle(raindrop_id, on_success_callback)
    self.callbacks.showProgress(_("Reloading article..."))
    local full_raindrop, err = self.api:getRaindrop(raindrop_id)
    self.callbacks.hideProgress()
    
    if full_raindrop and full_raindrop.item then
        if full_raindrop.item.cache and 
           full_raindrop.item.cache.status == "ready" and 
           full_raindrop.item.cache.text then
            on_success_callback(full_raindrop.item)
        else
            self.callbacks.notify(_("The article does not yet have cached content available"))
            on_success_callback(full_raindrop.item)
        end
    else
        self.callbacks.notify(_("Error reloading article: ") .. (err or _("Unknown error")))
    end
end

-- ========== OPEN IN READER ==========

function ArticleManager:openInReader(raindrop, close_all_callback, on_return_callback)
    -- Cerrar todos los widgets antes de abrir
    close_all_callback()
    
    if not raindrop or not raindrop.cache or not raindrop.cache.text then
        self.callbacks.notify(_("No content available"))
        return false
    end
    
    -- Usar el mismo directorio configurado que para descargas
    local html_dir = self.settings:getFullDownloadPath()
    local lfs = require("libs/libkoreader-lfs")
    if not lfs.attributes(html_dir, "mode") then
        util.makePath(html_dir)
    end

    -- Crear archivo HTML permanente (mismo formato que downloadHTML) - MEJORADO
    local safe_title = self:sanitizeFilename(raindrop.title or "article", 30)
    local safe_id = self:sanitizeID(raindrop._id)

    -- Asegurar que dir termine en /
    if not html_dir:match("/$") then
        html_dir = html_dir .. "/"
    end

    local filename = html_dir .. safe_id .. "_" .. safe_title .. ".html"
    local html = self.content_processor:createReaderHTML(raindrop)
    
    local file = io.open(filename, "w")
    if not file then
        self.callbacks.notify(_("Error creating temporary file"))
        return false
    end
    
    file:write(html)
    file:close()
    
    -- Usar GotaReader para abrir
    self.gota_reader:show({
        path = filename,
        raindrop = raindrop,
        on_return_callback = function()
            logger.dbg("ArticleManager: Usuario volvió del lector")
            UIManager:scheduleIn(0.2, function()
                on_return_callback(raindrop)
            end)
        end,
    })
    
    return true
end

-- ========== FILENAME SANITIZATION ==========

-- Sanitiza el nombre de archivo preservando legibilidad
function ArticleManager:sanitizeFilename(title, max_length)
    max_length = max_length or 80

    if not title or title == "" then
        return "untitled"
    end

    -- 1. Normalizar espacios
    title = title:gsub("%s+", " ")
    title = title:gsub("^%s+", "")
    title = title:gsub("%s+$", "")

    -- 2. Permitir caracteres seguros: letras, números, espacios, algunos símbolos
    -- PRESERVAR: punto, guión, paréntesis, corchetes
    title = title:gsub("[^%w%s%.%(%)%[%]%-_]", "")

    -- 3. Convertir espacios a guión bajo
    title = title:gsub(" ", "_")

    -- 4. Reducir símbolos consecutivos
    title = title:gsub("%.%.+", ".")
    title = title:gsub("%-%-+", "-")
    title = title:gsub("__+", "_")

    -- 5. Remover símbolos al inicio/final
    title = title:gsub("^[%.%-_]+", "")
    title = title:gsub("[%.%-_]+$", "")

    -- 6. Truncar respetando palabras
    if #title > max_length then
        title = title:sub(1, max_length)
        -- Buscar último separador para no cortar en medio de palabra
        local last_sep = title:match(".*[_%-]")
        if last_sep and #last_sep > max_length * 0.7 then
            title = last_sep:sub(1, -2)
        end
    end

    return title ~= "" and title or "untitled"
end

-- Sanitiza el ID del raindrop
function ArticleManager:sanitizeID(id)
    if not id then return "unknown" end

    -- Convertir a string si es número
    id = tostring(id)

    -- Remover caracteres de path traversal
    id = id:gsub("%.%.", "")
    id = id:gsub("/", "_")
    id = id:gsub("\\", "_")

    -- Solo alfanuméricos y guiones
    id = id:gsub("[^%w%-]", "")

    return id ~= "" and id or "unknown"
end

-- Genera un nombre de archivo único para evitar colisiones
function ArticleManager:getUniqueFilename(dir, id, title, extension)
    extension = extension or ".html"

    -- Asegurar que dir termine en /
    if not dir:match("/$") then
        dir = dir .. "/"
    end

    local base = dir .. id .. "_" .. title
    local filename = base .. extension
    local counter = 1

    local lfs = require("libs/libkoreader-lfs")
    while lfs.attributes(filename, "mode") == "file" do
        filename = string.format("%s_%d%s", base, counter, extension)
        counter = counter + 1

        -- Prevenir bucle infinito
        if counter > 999 then
            filename = string.format("%s_%d%s", base, os.time(), extension)
            logger.warn("ArticleManager: Demasiadas colisiones, usando timestamp")
            break
        end
    end

    return filename
end

-- ========== DOWNLOAD HTML ==========

function ArticleManager:downloadHTML(raindrop)
    if not raindrop or not raindrop.cache or not raindrop.cache.text then
        self.callbacks.notify(_("No content available to download"))
        return nil
    end

    -- Usar el mismo directorio configurado
    local html_dir = self.settings:getFullDownloadPath()
    local lfs = require("libs/libkoreader-lfs")

    -- Crear directorio si no existe
    if not lfs.attributes(html_dir, "mode") then
        local success = util.makePath(html_dir)
        if not success then
            self.callbacks.notify(_("Error creating download directory"))
            return nil
        end
    end

    -- Sanitizar nombre de archivo de forma segura (MEJORADO)
    local safe_title = self:sanitizeFilename(raindrop.title or "article", 80)
    local safe_id = self:sanitizeID(raindrop._id)

    -- Generar nombre único para evitar colisiones (NUEVO)
    local filename = self:getUniqueFilename(html_dir, safe_id, safe_title, ".html")

    -- Generar HTML usando el mismo procesador que openInReader
    local html = self.content_processor:createReaderHTML(raindrop)

    -- Guardar archivo con manejo de errores
    local file, err = io.open(filename, "w")
    if not file then
        self.callbacks.notify(_("Error saving file: ") .. (err or _("unknown error")))
        return nil
    end

    local write_ok, write_err = pcall(function()
        file:write(html)
    end)
    file:close()

    if not write_ok then
        self.callbacks.notify(_("Error writing file: ") .. (write_err or _("unknown error")))
        return nil
    end

    logger.dbg("ArticleManager: HTML saved successfully:", filename)
    return filename
end

-- ========== DOWNLOAD HTML WITH NOTES & HIGHLIGHTS ==========

function ArticleManager:downloadHTMLWithNotes(raindrop)
    -- Verificar que existan notes o highlights para descargar
    local has_notes = raindrop and raindrop.note and raindrop.note ~= ""
    local has_highlights = raindrop and raindrop.highlights and #raindrop.highlights > 0

    if not raindrop or (not has_notes and not has_highlights) then
        self.callbacks.notify(_("No notes or highlights available to download"))
        return nil
    end

    -- Usar el mismo directorio configurado
    local html_dir = self.settings:getFullDownloadPath()
    local lfs = require("libs/libkoreader-lfs")

    -- Crear directorio si no existe
    if not lfs.attributes(html_dir, "mode") then
        local success = util.makePath(html_dir)
        if not success then
            self.callbacks.notify(_("Error creating download directory"))
            return nil
        end
    end

    -- Sanitizar nombre de archivo de forma segura
    local safe_title = self:sanitizeFilename(raindrop.title or "article", 80)
    local safe_id = self:sanitizeID(raindrop._id)

    -- Generar nombre único con sufijo "_notes" para distinguir
    local filename = self:getUniqueFilename(html_dir, safe_id, safe_title .. "_notes", ".html")

    -- Generar HTML usando el procesador con notas y highlights
    local html = self.content_processor:createReaderHTMLWithNotes(raindrop)

    -- Guardar archivo con manejo de errores
    local file, err = io.open(filename, "w")
    if not file then
        self.callbacks.notify(_("Error saving file: ") .. (err or _("unknown error")))
        return nil
    end

    local write_ok, write_err = pcall(function()
        file:write(html)
    end)
    file:close()

    if not write_ok then
        self.callbacks.notify(_("Error writing file: ") .. (write_err or _("unknown error")))
        return nil
    end

    logger.dbg("ArticleManager: HTML with notes saved successfully:", filename)
    return filename
end

return ArticleManager
