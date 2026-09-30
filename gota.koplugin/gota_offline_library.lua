--[[
    Locating Gota's offline article copies in the export folder.

    KOReader stores reading position in a sidecar whose key depends on the
    document_metadata_folder setting: the document path under the default "doc"
    and "dir" locations, a partialMD5 of the contents under "hash". Offline
    copies therefore use a deterministic name instead of the collision counter
    that ArticleManager:getUniqueFilename applies to other exports, so the path
    stays put across downloads.

    The filesystem is the single source of truth: no index is persisted, so
    nothing can go stale when the user moves or deletes a file from KOReader's
    file browser. Callers inject lfs and docsettings, which keeps this module
    testable outside KOReader.

    This module never writes, renames or deletes. Reading progress goes through
    KOReader's read-only sidecar API for that reason.
]]

local OfflineLibrary = {}

local HTML_EXTENSION = ".html"
local HEADER_BYTES = 16 * 1024

-- Callers pass components already sanitized by ArticleManager so the result
-- matches the names downloadHTML has produced since before this module
-- existed, and previously saved copies keep being recognized.
function OfflineLibrary.canonicalName(safe_id, safe_title)
    if safe_id == nil or safe_title == nil then return nil end
    local id = tostring(safe_id)
    local title = tostring(safe_title)
    if id == "" or title == "" then return nil end
    return id .. "_" .. title .. HTML_EXTENSION
end

local function joinPath(dir, name)
    return (tostring(dir):gsub("/+$", "")) .. "/" .. name
end

local function isFile(lfs, path)
    local ok, mode = pcall(lfs.attributes, path, "mode")
    return ok and mode == "file"
end

-- Annotated exports are written as "<id>_<title>_notes.html" and share the id
-- prefix. The suffix is only a hint, not proof: a title that sanitizes to
-- something ending in "_notes" ("Release notes") produces the same shape. So
-- this ranks candidates rather than discarding them outright.
local function isAnnotatedExport(name)
    return name:match("_notes%.html$") ~= nil
        or name:match("_notes_%d+%.html$") ~= nil
end

local function isOfflineCopyName(name, id)
    if type(name) ~= "string" then return false end
    -- The underscore delimits the id, so "12_" never matches "123_...".
    if name:sub(1, #id + 1) ~= id .. "_" then return false end
    return name:sub(-#HTML_EXTENSION) == HTML_EXTENSION
end

-- Modification times are whole seconds, so sibling copies tie routinely. Fall
-- back to name order, which keeps the answer independent of readdir order.
local function isBetterCandidate(path, modified, best_path, best_time)
    if not best_path then return true end
    if modified ~= best_time then return modified > best_time end
    return path > best_path
end

--[[
    Resolve the offline copy for a raindrop, or nil.

    1. Prefer the canonical path, which is what a current download produces.
    2. Otherwise scan for "<id>_*.html", which recovers copies saved before
       this module existed (they carry a collision counter) and copies whose
       title changed in Raindrop afterwards.

    Returns the path plus whether it looks like one of Gota's own annotated
    exports, so callers can avoid forcing publisher styling on a document Gota
    wrote itself. An annotated export is only offered when nothing else
    matches, which keeps a legitimate copy whose title ends in "_notes"
    reachable instead of invisible.
]]
function OfflineLibrary.find(dir, safe_id, safe_title, lfs)
    if type(dir) ~= "string" or dir == "" or safe_id == nil then return nil end
    if type(lfs) ~= "table" or type(lfs.attributes) ~= "function" then return nil end

    local id = tostring(safe_id)
    if id == "" then return nil end

    local canonical_name = OfflineLibrary.canonicalName(id, safe_title)
    if canonical_name then
        local canonical_path = joinPath(dir, canonical_name)
        -- Never annotated by construction: this is the exact name downloadHTML
        -- writes, even when the article's own title ends in "_notes".
        if isFile(lfs, canonical_path) then return canonical_path, false end
    end

    if type(lfs.dir) ~= "function" then return nil end
    local iterator_ok, iterator, directory_state = pcall(lfs.dir, dir)
    if not iterator_ok or type(iterator) ~= "function" then return nil end

    local best = { [true] = {}, [false] = {} }
    local scan_ok = pcall(function()
        for name in iterator, directory_state do
            if isOfflineCopyName(name, id) then
                local path = joinPath(dir, name)
                if isFile(lfs, path) then
                    local time_ok, modified = pcall(lfs.attributes, path, "modification")
                    modified = (time_ok and tonumber(modified)) or 0
                    local bucket = best[isAnnotatedExport(name)]
                    if isBetterCandidate(path, modified, bucket.path, bucket.time) then
                        bucket.path, bucket.time = path, modified
                    end
                end
            end
        end
    end)
    if not scan_ok then return nil end

    if best[false].path then return best[false].path, false end
    if best[true].path then return best[true].path, true end
    return nil
end

local function readHeader(path, limit)
    local file = io.open(path, "rb")
    if not file then return nil end
    local ok, header = pcall(file.read, file, limit)
    pcall(file.close, file)
    return ok and header or nil
end

local function parseCopyName(name)
    if type(name) ~= "string" or name:find("%c") then return nil end
    local id, title = name:match("^(%d+)_(.+)%.html$")
    if not id or not title:find("%S") or title == "." or title == ".." then return nil end
    local numeric_id = tonumber(id)
    if not numeric_id or numeric_id >= 2 ^ 53 or numeric_id ~= math.floor(numeric_id) then
        return nil
    end
    return numeric_id, title
end

local function isAnnotatedHeader(header)
    if type(header) ~= "string" then return nil end
    -- Current exports carry an explicit marker. The stylesheet also identifies
    -- Gota's older exports, whose filename alone is ambiguous (Release_notes).
    return header:find('content="Gota annotated export"', 1, true) ~= nil or
        (header:find(".notes-section", 1, true) ~= nil and
         header:find(".highlights-section", 1, true) ~= nil and
         header:find(".source-url", 1, true) ~= nil)
end

local function titleFromHeader(header, decode_entities)
    if type(header) ~= "string" then return nil end
    local title = header:match("<[Tt][Ii][Tt][Ll][Ee]%s*>(.-)</[Tt][Ii][Tt][Ll][Ee]%s*>") or
        header:match("<[Tt][Ii][Tt][Ll][Ee]%s+[^>]*>(.-)</[Tt][Ii][Tt][Ll][Ee]%s*>")
    if not title then return nil end
    title = title:gsub("<[^>]*>", "")
    if type(decode_entities) == "function" then
        local ok, decoded = pcall(decode_entities, title)
        if ok and type(decoded) == "string" then title = decoded end
    end
    title = title:gsub("%c", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return title ~= "" and title or nil
end

-- List only Gota-named HTML files in the configured export directory. Each
-- path remains independent, so legacy numbered files and annotated exports
-- retain their own reading position. No network, index, or directory creation
-- is involved. The header read is bounded even for large permanent copies.
-- options.read_header is an injectable reader for the dependency-free suite.
function OfflineLibrary.list(dir, lfs, docsettings, options)
    if type(dir) ~= "string" or dir == "" then return nil, "export directory is not configured" end
    if type(lfs) ~= "table" or type(lfs.attributes) ~= "function" or
       type(lfs.dir) ~= "function" then return nil, "could not enumerate saved articles" end
    options = options or {}

    local mode_ok, mode = pcall(lfs.attributes, dir, "mode")
    if not mode_ok then return nil, tostring(mode) end
    if mode == nil then return {}, nil end
    if mode ~= "directory" then return nil, "export path is not a directory" end

    local iterator_ok, iterator, directory_state = pcall(lfs.dir, dir)
    if not iterator_ok then return nil, tostring(iterator) end
    if type(iterator) ~= "function" then return nil, "could not enumerate saved articles" end
    local copies = {}
    local scan_ok, scan_error = pcall(function()
        for name in iterator, directory_state do
            local id, fallback_title = parseCopyName(name)
            if id then
                local path = joinPath(dir, name)
                if isFile(lfs, path) then
                    local header_ok, header = pcall(options.read_header or readHeader, path, HEADER_BYTES)
                    header = header_ok and header or nil
                    local annotated = isAnnotatedHeader(header)
                    -- An unreadable old file can still be listed from its name.
                    if annotated == nil then annotated = isAnnotatedExport(name) end
                    if annotated then
                        local article_title = fallback_title:gsub("_notes_%d+$", ""):gsub("_notes$", "")
                        if article_title:find("%S") then fallback_title = article_title end
                    end
                    fallback_title = fallback_title:gsub("_", " ")
                    copies[#copies + 1] = {
                        path = path,
                        title = titleFromHeader(header, options.decode_entities) or fallback_title,
                        raindrop_id = id,
                        annotated = annotated == true,
                        percent = OfflineLibrary.progress(path, docsettings),
                    }
                end
            end
        end
    end)
    if not scan_ok then return nil, tostring(scan_error) end
    table.sort(copies, function(a, b)
        local a_title, b_title = a.title:lower(), b.title:lower()
        if a_title ~= b_title then return a_title < b_title end
        if a.annotated ~= b.annotated then return not a.annotated end
        return a.path < b.path
    end)
    return copies, nil
end

--[[
    percent_finished is stored as a 0..1 fraction. Flooring keeps the reported
    value from ever overstating how much of the article has been read.

    Uses the read-only pair findSidecarFile + openSettingsFile rather than
    DocSettings:open(), which dofile()s every candidate location and
    os.remove()s the ones it judges invalid. This runs on the article-menu path
    for documents the user may never have opened, so it must not delete
    anything.
]]
function OfflineLibrary.progress(path, docsettings)
    if type(path) ~= "string" or path == "" then return nil end
    if type(docsettings) ~= "table" then return nil end
    if type(docsettings.findSidecarFile) ~= "function" or
       type(docsettings.openSettingsFile) ~= "function" then
        return nil
    end

    local found_ok, sidecar = pcall(docsettings.findSidecarFile, docsettings, path)
    if not found_ok or type(sidecar) ~= "string" or sidecar == "" then return nil end

    -- openSettingsFile is a plain function, not a method.
    local open_ok, settings = pcall(docsettings.openSettingsFile, sidecar)
    if not open_ok or type(settings) ~= "table" or
       type(settings.readSetting) ~= "function" then
        return nil
    end

    local read_ok, fraction = pcall(settings.readSetting, settings, "percent_finished")
    if not read_ok then return nil end

    fraction = tonumber(fraction)
    if not fraction or fraction ~= fraction or fraction < 0 or fraction > 1 then return nil end
    return math.floor(fraction * 100)
end

return OfflineLibrary
