--[[
    Gota Article Manager Module
    Handles all article-related operations: viewing, downloading, opening in reader
]]

local UIManager = require("ui/uimanager")
local DataStorage = require("datastorage")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local ArticleManager = {}

local CACHE_STATE_FIELD = "_gota_cache_state"
local DETACHED_FIELD = "_gota_detached_item"
local FULL_ITEM_FIELD = "_gota_full_item"

local function hasContent(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

-- API responses are cached as mutable Lua tables. Never attach downloaded HTML
-- or local state to those shared tables: a permanent copy can be several MB.
local function copyRaindrop(source)
    if type(source) ~= "table" then
        return source
    end

    local copy = {}
    for key, value in pairs(source) do
        if key ~= CACHE_STATE_FIELD then
            copy[key] = value
        end
    end
    if type(source.cache) == "table" then
        copy.cache = {}
        for key, value in pairs(source.cache) do
            copy.cache[key] = value
        end
    end
    copy[DETACHED_FIELD] = true
    return copy
end

local function truncateUTF8ByBytes(value, limit)
    if #value <= limit then
        return value
    end

    local index = 1
    local last_complete = 0
    while index <= #value and index <= limit do
        local first = value:byte(index)
        local length = 1
        if first and first >= 0xC2 and first <= 0xDF then
            length = 2
        elseif first and first >= 0xE0 and first <= 0xEF then
            length = 3
        elseif first and first >= 0xF0 and first <= 0xF4 then
            length = 4
        end
        if index + length - 1 > limit then
            break
        end
        last_complete = index + length - 1
        index = index + length
    end
    return value:sub(1, last_complete)
end

local function writeFileAtomically(filename, contents)
    local temporary = filename .. ".part"
    local file, open_error = io.open(temporary, "wb")
    if not file then
        return nil, open_error
    end

    local call_ok, write_result, write_error = pcall(file.write, file, contents)
    local close_call_ok, close_result, close_error = pcall(file.close, file)
    if not call_ok or not write_result or not close_call_ok or not close_result then
        os.remove(temporary)
        local failure = (not call_ok and write_result) or write_error or
            (not close_call_ok and close_result) or close_error or "write failed"
        return nil, tostring(failure)
    end

    local rename_ok, rename_error = os.rename(temporary, filename)
    if not rename_ok then
        os.remove(temporary)
        return nil, rename_error
    end
    return true
end

local function ensureDirectory(path, lfs)
    local mode = lfs.attributes(path, "mode")
    if mode == "directory" then
        return true
    elseif mode ~= nil then
        return nil, "download path is not a directory"
    end
    return util.makePath(path)
end

ArticleManager.copyRaindrop = copyRaindrop

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

function ArticleManager:getReaderCachePath(raindrop_id)
    return DataStorage:getDataDir() .. "/cache/gota/raindrop_" ..
        self:sanitizeID(raindrop_id) .. ".html"
end

-- Keep Raindrop's cache metadata separate from the result of downloading the
-- permanent-copy HTML. The API returns those through different endpoints.
function ArticleManager:getCacheState(raindrop)
    local cache = raindrop and raindrop.cache or nil
    local tracked = raindrop and raindrop[CACHE_STATE_FIELD] or nil
    return {
        metadata_available = cache ~= nil and cache.status == "ready",
        html_loaded = cache ~= nil and hasContent(cache.text),
        download_error = tracked and tracked.download_error or nil,
    }
end

function ArticleManager:setCacheDownloadState(raindrop, download_error)
    if not raindrop then
        return
    end
    local state = self:getCacheState(raindrop)
    state.download_error = download_error
    raindrop[CACHE_STATE_FIELD] = state
end

-- ========== ARTICLE CONTENT LOADING ==========

-- Carga el contenido completo de un artículo con caché
function ArticleManager:loadFullArticle(raindrop)
    if type(raindrop) ~= "table" then
        return raindrop, _("Invalid article data")
    end
    if raindrop[FULL_ITEM_FIELD] then
        return raindrop, nil
    end

    -- Detach even on an API failure so subsequent cache loading cannot mutate a
    -- list response held by gota_api's five-minute response cache.
    local detached_fallback = raindrop[DETACHED_FIELD] and raindrop or copyRaindrop(raindrop)

    self.callbacks.showProgress(_("Loading full content..."))
    local full_raindrop, err = self.api:getRaindrop(raindrop._id)
    self.callbacks.hideProgress()

    if full_raindrop and full_raindrop.item then
        local detached = copyRaindrop(full_raindrop.item)
        detached[FULL_ITEM_FIELD] = true
        self:setCacheDownloadState(detached, nil)
        return detached, nil
    end

    return detached_fallback, err
end

-- Carga el contenido del caché si no está presente
function ArticleManager:loadCacheContent(raindrop)
    if type(raindrop) ~= "table" then
        return raindrop
    end
    if not raindrop[DETACHED_FIELD] then
        raindrop = copyRaindrop(raindrop)
    end
    local state = self:getCacheState(raindrop)

    -- Si ya tiene HTML cargado o no hay metadatos disponibles, no descargar.
    if state.html_loaded then
        self:setCacheDownloadState(raindrop, nil)
        return raindrop
    end
    if state.download_error then
        logger.dbg("ArticleManager: Caché no reintentado automáticamente tras un error")
        return raindrop
    end
    if not state.metadata_available then
        local status = raindrop and raindrop.cache and raindrop.cache.status or "missing"
        logger.dbg("ArticleManager: Caché no está listo, status:", status)
        self:setCacheDownloadState(raindrop, nil)
        return raindrop
    end

    self.callbacks.showProgress(_("Loading cached content..."))
    local cache_content, err = self.api:getRaindropCache(raindrop._id)
    self.callbacks.hideProgress()

    if hasContent(cache_content) then
        raindrop.cache.text = cache_content
        self:setCacheDownloadState(raindrop, nil)
        logger.dbg("ArticleManager: Contenido HTML cargado, longitud:", #cache_content)
    else
        local load_error = err or "contenido vacío"
        raindrop.cache.text = nil
        self:setCacheDownloadState(raindrop, load_error)
        logger.warn("ArticleManager: No se pudo cargar caché:", load_error)
    end

    return raindrop
end

-- Verifica si un artículo tiene caché disponible
function ArticleManager:hasValidCache(raindrop)
    return self:getCacheState(raindrop).html_loaded
end

-- ========== ARTICLE RELOADING ==========

function ArticleManager:reloadArticle(raindrop_id, on_success_callback)
    self.callbacks.showProgress(_("Reloading article..."))
    -- Reload is explicit user intent: bypass the API metadata cache.
    local full_raindrop, err = self.api:getRaindrop(raindrop_id, true)

    local raindrop = full_raindrop and full_raindrop.item and
        copyRaindrop(full_raindrop.item) or nil
    local cache_err
    if raindrop then
        raindrop[FULL_ITEM_FIELD] = true
        self:setCacheDownloadState(raindrop, nil)
        if self:getCacheState(raindrop).metadata_available then
            local cache_content
            cache_content, cache_err = self.api:getRaindropCache(raindrop_id)
            if hasContent(cache_content) then
                raindrop.cache.text = cache_content
                self:setCacheDownloadState(raindrop, nil)
            else
                cache_err = cache_err or _("empty cached content")
                raindrop.cache.text = nil
                self:setCacheDownloadState(raindrop, cache_err)
            end
        end
    end
    self.callbacks.hideProgress()

    if raindrop then
        local state = self:getCacheState(raindrop)
        if state.html_loaded then
            on_success_callback(raindrop)
        elseif state.metadata_available then
            self.callbacks.notify(_("Cached content could not be downloaded: ") ..
                (cache_err or _("Unknown error")))
            on_success_callback(raindrop)
        else
            self.callbacks.notify(_("The article does not yet have cached content available"))
            on_success_callback(raindrop)
        end
    else
        self.callbacks.notify(_("Error reloading article: ") .. (err or _("Unknown error")))
    end
end

-- ========== OPEN IN READER ==========

function ArticleManager:openInReader(raindrop, close_all_callback, on_return_callback)
    if not self:hasValidCache(raindrop) then
        self.callbacks.notify(_("No content available"))
        return false
    end

    -- Reader documents are transient cache files. Keeping them out of the
    -- export directory prevents an open action from overwriting a saved HTML.
    local html_dir = DataStorage:getDataDir() .. "/cache/gota"
    local lfs = require("libs/libkoreader-lfs")
    local path_ok, path_error = ensureDirectory(html_dir, lfs)
    if not path_ok then
        self.callbacks.notify(_("Error creating reader cache directory") ..
            (path_error and (": " .. tostring(path_error)) or ""))
        return false
    end

    local filename = self:getReaderCachePath(raindrop._id)
    local html = self.content_processor:createReaderHTML(raindrop)

    local write_ok, write_error = writeFileAtomically(filename, html)
    if not write_ok then
        self.callbacks.notify(_("Error writing file: ") .. (write_error or _("unknown error")))
        return false
    end

    -- Usar GotaReader para abrir
    local opened = self.gota_reader:show({
        path = filename,
        before_open_callback = close_all_callback,
        on_return_callback = function()
            logger.dbg("ArticleManager: Usuario volvió del lector")
            UIManager:scheduleIn(0.2, function()
                local history_path = filename
                local ffi_ok, ffiUtil = pcall(require, "ffi/util")
                if ffi_ok and ffiUtil and ffiUtil.realpath then
                    history_path = ffiUtil.realpath(filename) or filename
                end
                local removed, remove_error = os.remove(filename)
                if not removed and lfs.attributes(filename, "mode") then
                    logger.warn("ArticleManager: could not remove reader cache file:", remove_error)
                end
                local history_ok, history_error = pcall(function()
                    require("readhistory"):removeItemByPath(history_path)
                end)
                if not history_ok then
                    logger.warn("ArticleManager: could not clean reader history:", history_error)
                end
                on_return_callback(raindrop)
            end)
        end,
    }) == true

    if opened then
        -- CREngine reads from disk. Keeping the multi-megabyte source HTML in a
        -- return callback wastes scarce RAM on older Kindle/Kobo devices.
        raindrop.cache.text = nil
    else
        os.remove(filename)
    end
    return opened
end

-- ========== FILENAME SANITIZATION ==========

-- Sanitiza el nombre de archivo preservando legibilidad
function ArticleManager:sanitizeFilename(title, max_length)
    max_length = max_length or 80

    if not title or title == "" then
        return "untitled"
    end

    if self.content_processor and self.content_processor.ensureUTF8 then
        title = self.content_processor:ensureUTF8(title)
    else
        title = tostring(title)
    end

    -- Prefer KOReader's filesystem-aware sanitizer when available. It keeps
    -- valid UTF-8 and avoids VFAT/Windows-reserved filename characters.
    if util.getSafeFilename then
        local path = self.settings and self.settings:getFullDownloadPath() or nil
        local safe = util.getSafeFilename(title, path, max_length)
        safe = safe and safe:gsub("^[%.%s]+", ""):gsub("[%.%s]+$", "") or ""
        return safe ~= "" and safe or "untitled"
    end

    -- Compatibility fallback for older KOReader releases.
    title = title:gsub("%s+", " ")
    title = title:gsub("^%s+", "")
    title = title:gsub("%s+$", "")

    title = title:gsub("[%z\1-\31\127]", "")
    title = title:gsub("[\\/:*?\"<>|]", "_")

    -- 3. Convertir espacios a guión bajo
    title = title:gsub(" ", "_")

    -- 4. Reducir símbolos consecutivos
    title = title:gsub("%.%.+", ".")
    title = title:gsub("%-%-+", "-")
    title = title:gsub("__+", "_")

    -- 5. Remover símbolos al inicio/final
    title = title:gsub("^[%.%-_]+", "")
    title = title:gsub("[%.%-_]+$", "")

    -- 6. Truncar sin cortar una secuencia UTF-8
    if #title > max_length then
        title = truncateUTF8ByBytes(title, max_length)
        -- Buscar último separador para no cortar en medio de palabra
        local last_sep = title:match(".*[_%-]")
        if last_sep and #last_sep > max_length * 0.7 then
            title = last_sep:sub(1, -2)
        end
    end

    title = title:gsub("^[%.%-_]+", ""):gsub("[%.%-_]+$", "")

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
    while lfs.attributes(filename, "mode") ~= nil do
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
    if not self:hasValidCache(raindrop) then
        self.callbacks.notify(_("No content available to download"))
        return nil
    end

    -- Usar el mismo directorio configurado
    local html_dir = self.settings:getFullDownloadPath()
    local lfs = require("libs/libkoreader-lfs")

    -- Crear directorio si no existe
    local path_ok = ensureDirectory(html_dir, lfs)
    if not path_ok then
        self.callbacks.notify(_("Error creating download directory"))
        return nil
    end

    -- Sanitizar nombre de archivo de forma segura (MEJORADO)
    local safe_title = self:sanitizeFilename(raindrop.title or "article", 80)
    local safe_id = self:sanitizeID(raindrop._id)

    -- Generar nombre único para evitar colisiones (NUEVO)
    local filename = self:getUniqueFilename(html_dir, safe_id, safe_title, ".html")

    -- Generar HTML usando el mismo procesador que openInReader
    local html = self.content_processor:createReaderHTML(raindrop)

    -- Guardar archivo sin dejar una copia parcial ante un error de escritura
    local write_ok, write_err = writeFileAtomically(filename, html)
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
    local has_highlights = raindrop and type(raindrop.highlights) == "table" and
        #raindrop.highlights > 0

    if not raindrop or (not has_notes and not has_highlights) then
        self.callbacks.notify(_("No notes or highlights available to download"))
        return nil
    end

    -- Usar el mismo directorio configurado
    local html_dir = self.settings:getFullDownloadPath()
    local lfs = require("libs/libkoreader-lfs")

    -- Crear directorio si no existe
    local path_ok = ensureDirectory(html_dir, lfs)
    if not path_ok then
        self.callbacks.notify(_("Error creating download directory"))
        return nil
    end

    -- Sanitizar nombre de archivo de forma segura
    local safe_title = self:sanitizeFilename(raindrop.title or "article", 80)
    local safe_id = self:sanitizeID(raindrop._id)

    -- Generar nombre único con sufijo "_notes" para distinguir
    local filename = self:getUniqueFilename(html_dir, safe_id, safe_title .. "_notes", ".html")

    -- Generar HTML usando el procesador con notas y highlights
    local html = self.content_processor:createReaderHTMLWithNotes(raindrop)

    -- Guardar archivo sin dejar una copia parcial ante un error de escritura
    local write_ok, write_err = writeFileAtomically(filename, html)
    if not write_ok then
        self.callbacks.notify(_("Error writing file: ") .. (write_err or _("unknown error")))
        return nil
    end

    logger.dbg("ArticleManager: HTML with notes saved successfully:", filename)
    return filename
end

return ArticleManager
