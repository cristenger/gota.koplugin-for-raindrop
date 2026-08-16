--[[
    Locating Gota's offline article copies in the export folder.

    KOReader stores reading position in a sidecar keyed to the document path,
    so resuming an article only needs a stable path. Offline copies therefore
    use a deterministic name instead of the collision counter that
    ArticleManager:getUniqueFilename applies to other exports.

    The filesystem is the single source of truth: no index is persisted, so
    nothing can go stale when the user moves or deletes a file from KOReader's
    file browser. Callers inject lfs and docsettings, which keeps this module
    testable outside KOReader.

    This module never writes, renames or deletes. Reading progress goes through
    KOReader's read-only sidecar API for that reason.
]]

local OfflineLibrary = {}

local HTML_EXTENSION = ".html"

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
        if isFile(lfs, canonical_path) then
            return canonical_path, isAnnotatedExport(canonical_name)
        end
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
    if not fraction or fraction < 0 or fraction > 1 then return nil end
    return math.floor(fraction * 100)
end

return OfflineLibrary
