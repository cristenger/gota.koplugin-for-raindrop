local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")
local _ = require("gettext")

local Settings = {}
local DEFAULT_DOWNLOAD_PATH = "gota_articles"
local DEFAULT_SORT_ORDER = "-created"
local MIB = 1024 * 1024
local DEFAULT_CACHE_MEMORY_BYTES = 16 * MIB
local DEFAULT_CACHE_FILE_BYTES = 128 * MIB
local CACHE_MEMORY_PRESETS = {
    [2 * MIB] = true,
    [4 * MIB] = true,
    [8 * MIB] = true,
    [16 * MIB] = true,
    [32 * MIB] = true,
    [64 * MIB] = true,
}
local CACHE_FILE_PRESETS = {
    [16 * MIB] = true,
    [32 * MIB] = true,
    [64 * MIB] = true,
    [128 * MIB] = true,
    [256 * MIB] = true,
    [512 * MIB] = true,
}
local ALLOWED_SORT_ORDERS = {
    ["-created"] = true,
    created = true,
    title = true,
    ["-title"] = true,
    ["-sort"] = true,
    domain = true,
    ["-domain"] = true,
}

local function normalizeSortOrder(value)
    return ALLOWED_SORT_ORDERS[value] and value or DEFAULT_SORT_ORDER
end

local function normalizePreset(value, allowed, default_value)
    value = tonumber(value)
    return value and allowed[value] and value or default_value
end

local function pathIsInside(base_path, candidate_path)
    base_path = base_path:gsub("/+$", "")
    candidate_path = candidate_path:gsub("/+$", "")
    return candidate_path == base_path or
        candidate_path:sub(1, #base_path + 1) == base_path .. "/"
end

local function validateDownloadPath(path)
    if type(path) ~= "string" then return nil, _("Download path must be text") end
    if path == "" then return nil, _("Download path cannot be empty") end
    if path:find("%c") then return nil, _("Download path cannot contain control characters") end

    path = path:gsub("\\", "/")
    if path:sub(1, 1) == "/" or path:match("^%a:/") then
        return nil, _("Download path must be relative to the KOReader data folder")
    end

    local util_ok, util = pcall(require, "util")
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            return nil, _("Download path cannot contain '..'")
        elseif part == "." then
            return nil, _("Download path cannot contain '.'")
        elseif part ~= "" then
            local safe = util_ok and util.replaceAllInvalidChars and
                util.replaceAllInvalidChars(part) or part:gsub('[\\:*?"<>|]', "_")
            if safe == "" then return nil, _("Download path contains an empty folder name") end
            table.insert(parts, safe)
        end
    end

    if #parts == 0 then return nil, _("Download path cannot be empty") end
    return table.concat(parts, "/")
end

local function normalizeDownloadPath(path)
    return validateDownloadPath(path) or DEFAULT_DOWNLOAD_PATH
end

function Settings:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self

    -- Ensure settings directory exists
    local settings_dir = DataStorage:getSettingsDir()
    local lfs = require("libs/libkoreader-lfs")
    if not lfs.attributes(settings_dir, "mode") then
        local util = require("util")
        util.makePath(settings_dir)
    end

    local settings_path = settings_dir .. "/gota.lua"
    o.settings_path = settings_path
    o.config = LuaSettings:open(settings_path)

    if o.config then
        o.token = o.config:readSetting("token") or ""
        o.download_path = normalizeDownloadPath(o.config:readSetting("download_path"))
        o.sort_order = normalizeSortOrder(o.config:readSetting("sort_order"))
        o.max_cache_memory_bytes = normalizePreset(o.config:readSetting("max_cache_memory_bytes"),
            CACHE_MEMORY_PRESETS, DEFAULT_CACHE_MEMORY_BYTES)
        o.max_cache_file_bytes = normalizePreset(o.config:readSetting("max_cache_file_bytes"),
            CACHE_FILE_PRESETS, DEFAULT_CACHE_FILE_BYTES)
    else
        logger.warn("Gota Settings: could not open config, using defaults")
        o.token = ""
        o.download_path = DEFAULT_DOWNLOAD_PATH
        o.sort_order = DEFAULT_SORT_ORDER
        o.max_cache_memory_bytes = DEFAULT_CACHE_MEMORY_BYTES
        o.max_cache_file_bytes = DEFAULT_CACHE_FILE_BYTES
    end

    logger.dbg("Gota Settings: loaded, token:", o.token ~= "" and "present" or "empty")
    return o
end

function Settings:save()
    if not self.config then
        logger.err("Gota Settings: cannot save, config not initialized")
        return false, "configuration is not initialized"
    end

    local saved, save_error = pcall(function()
        self.download_path = normalizeDownloadPath(self.download_path)
        self.config:saveSetting("token", self.token)
        self.config:saveSetting("download_path", self.download_path)
        self.sort_order = normalizeSortOrder(self.sort_order)
        self.config:saveSetting("sort_order", self.sort_order)
        self.max_cache_memory_bytes = normalizePreset(self.max_cache_memory_bytes,
            CACHE_MEMORY_PRESETS, DEFAULT_CACHE_MEMORY_BYTES)
        self.max_cache_file_bytes = normalizePreset(self.max_cache_file_bytes,
            CACHE_FILE_PRESETS, DEFAULT_CACHE_FILE_BYTES)
        self.config:saveSetting("max_cache_memory_bytes", self.max_cache_memory_bytes)
        self.config:saveSetting("max_cache_file_bytes", self.max_cache_file_bytes)
        -- LuaSettings:flush() returns self, not an I/O success boolean. Treat
        -- exceptions as failures without claiming stronger durability guarantees.
        self.config:flush()
    end)
    if not saved then
        logger.err("Gota Settings: could not save configuration:", save_error)
        return false, tostring(save_error)
    end
    return true
end

function Settings:getToken()
    return self.token
end

function Settings:setToken(token)
    self.token = token or ""
end

function Settings:clearToken()
    local previous_token = self.token
    self.token = ""
    local saved, save_error = self:save()
    if not saved then
        self.token = previous_token
        return false, save_error
    end
    return true
end

function Settings:isTokenValid()
    return self.token and self.token ~= ""
end

function Settings:getDownloadPath()
    return normalizeDownloadPath(self.download_path)
end

function Settings:validateDownloadPath(path)
    return validateDownloadPath(path)
end

function Settings:setDownloadPath(path)
    local normalized, validation_error = validateDownloadPath(path)
    if not normalized then return nil, validation_error end
    self.download_path = normalized
    return normalized, nil
end

function Settings:getFullDownloadPath()
    local data_dir = DataStorage:getDataDir():gsub("/+$", "")
    local candidate = data_dir .. "/" .. self:getDownloadPath()
    local ffi_ok, ffiUtil = pcall(require, "ffi/util")

    if ffi_ok and ffiUtil and ffiUtil.realpath then
        local canonical_data = ffiUtil.realpath(data_dir)
        local probe = candidate
        local canonical_probe = ffiUtil.realpath(probe)
        while not canonical_probe and probe ~= data_dir do
            local parent = probe:match("^(.*)/[^/]+$")
            if not parent or parent == "" or parent == probe then break end
            probe = parent
            canonical_probe = ffiUtil.realpath(probe)
        end

        -- A pre-existing symlink must not redirect downloads outside DataStorage.
        if canonical_data and canonical_probe and
            not pathIsInside(canonical_data, canonical_probe) then
            logger.warn("Gota Settings: download path escapes DataStorage through a symlink")
            self.download_path = DEFAULT_DOWNLOAD_PATH
            candidate = data_dir .. "/" .. DEFAULT_DOWNLOAD_PATH
        end
    end

    return candidate .. "/"
end

function Settings:getSettingsPath()
    return self.settings_path
end

function Settings:getSortOrder()
    return normalizeSortOrder(self.sort_order)
end

function Settings:setSortOrder(sort)
    self.sort_order = normalizeSortOrder(sort)
end

function Settings:getMaxCacheMemoryBytes()
    return normalizePreset(self.max_cache_memory_bytes, CACHE_MEMORY_PRESETS, DEFAULT_CACHE_MEMORY_BYTES)
end

function Settings:setMaxCacheMemoryBytes(value)
    local normalized = normalizePreset(value, CACHE_MEMORY_PRESETS, nil)
    if not normalized then return nil end
    self.max_cache_memory_bytes = normalized
    return normalized
end


function Settings:getMaxCacheFileBytes()
    return normalizePreset(self.max_cache_file_bytes, CACHE_FILE_PRESETS, DEFAULT_CACHE_FILE_BYTES)
end

function Settings:setMaxCacheFileBytes(value)
    local normalized = normalizePreset(value, CACHE_FILE_PRESETS, nil)
    if not normalized then return nil end
    self.max_cache_file_bytes = normalized
    return normalized
end

function Settings:getDebugInfo()
    local settings_path = self.settings_path
    local lfs = require("libs/libkoreader-lfs")
    local attr = lfs.attributes(settings_path)
    return {
        token_status = self.token ~= "" and "configured" or "not configured",
        settings_file = settings_path,
        file_exists = attr ~= nil,
        file_size = attr and attr.size or 0,
        sort_order = self.sort_order,
        download_path = self.download_path,
        max_cache_memory_bytes = self:getMaxCacheMemoryBytes(),
        max_cache_file_bytes = self:getMaxCacheFileBytes(),
        max_cache_memory_mib = self:getMaxCacheMemoryBytes() / MIB,
        max_cache_file_mib = self:getMaxCacheFileBytes() / MIB,
    }
end

return Settings
