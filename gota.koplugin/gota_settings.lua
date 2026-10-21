local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")
local _ = require("gota_gettext")

local Settings = {}
-- FileManager and ReaderUI create separate settings instances. Credentials
-- belong to the running session, so a stale instance must not restore a token.
local session_token
local session_generation = 0
local session_security_initialized = false
local session_tls_verify = true
local session_ca_file
-- Folder, sort and limits are shared the same way: save() writes every key,
-- so a per-instance copy would let an older instance roll back newer values.
local session_preferences
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
    if type(path) ~= "string" then return nil, _("Export path must be text") end
    if path == "" then return nil, _("Export path cannot be empty") end
    if path:find("%c") then return nil, _("Export path cannot contain control characters") end

    path = path:gsub("\\", "/")
    if path:sub(1, 1) == "/" or path:match("^%a:/") then
        return nil, _("Export path must be relative to the KOReader data folder")
    end

    local util_ok, util = pcall(require, "util")
    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            return nil, _("Export path cannot contain '..'")
        elseif part == "." then
            return nil, _("Export path cannot contain '.'")
        elseif part ~= "" then
            local safe = util_ok and util.replaceAllInvalidChars and
                util.replaceAllInvalidChars(part) or part:gsub('[\\:*?"<>|]', "_")
            if safe == "" then return nil, _("Export path contains an empty folder name") end
            table.insert(parts, safe)
        end
    end

    if #parts == 0 then return nil, _("Export path cannot be empty") end
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
        if session_token == nil then session_token = o.config:readSetting("token") or "" end
        if not session_security_initialized then
            session_tls_verify = o.config:readSetting("tls_verify") ~= false
            session_ca_file = o.config:readSetting("tls_ca_file")
            session_security_initialized = true
        end
        if not session_preferences then
            session_preferences = {
                download_path = normalizeDownloadPath(o.config:readSetting("download_path")),
                sort_order = normalizeSortOrder(o.config:readSetting("sort_order")),
                max_cache_memory_bytes = normalizePreset(o.config:readSetting("max_cache_memory_bytes"),
                    CACHE_MEMORY_PRESETS, DEFAULT_CACHE_MEMORY_BYTES),
                max_cache_file_bytes = normalizePreset(o.config:readSetting("max_cache_file_bytes"),
                    CACHE_FILE_PRESETS, DEFAULT_CACHE_FILE_BYTES),
            }
        end
    else
        logger.warn("Gota Settings: could not open config, using defaults")
        if session_token == nil then session_token = "" end
        session_security_initialized = true
    end
    if not session_preferences then
        session_preferences = {
            download_path = DEFAULT_DOWNLOAD_PATH,
            sort_order = DEFAULT_SORT_ORDER,
            max_cache_memory_bytes = DEFAULT_CACHE_MEMORY_BYTES,
            max_cache_file_bytes = DEFAULT_CACHE_FILE_BYTES,
        }
    end

    logger.dbg("Gota Settings: loaded, token:", o:getToken() ~= "" and "present" or "empty")
    return o
end

-- The values save() writes, read from the shared session state.
function Settings:persistedValues()
    return {
        token = self:getToken(),
        tls_verify = self:isTLSVerificationEnabled(),
        tls_ca_file = self:getTLSCAFile(),
        download_path = self:getDownloadPath(),
        sort_order = self:getSortOrder(),
        max_cache_memory_bytes = self:getMaxCacheMemoryBytes(),
        max_cache_file_bytes = self:getMaxCacheFileBytes(),
    }
end

function Settings:save()
    if not self.config then
        logger.err("Gota Settings: cannot save, config not initialized")
        return false, "configuration is not initialized"
    end

    local values = self:persistedValues()
    local saved, save_error = pcall(function()
        for key, value in pairs(values) do self.config:saveSetting(key, value) end
        self.config:saveSetting("tls_ca_file", values.tls_ca_file)
        self.config:flush()
    end)
    if not saved then
        logger.err("Gota Settings: could not save configuration:", save_error)
        return false, tostring(save_error)
    end

    -- LuaSettings:flush() ignores util.writeToFile's result and returns self,
    -- so a failed open is silent. Read the file back before reporting success.
    local reread_ok, written = pcall(LuaSettings.open, LuaSettings, self.settings_path)
    if not reread_ok or not written then
        logger.err("Gota Settings: could not verify saved configuration")
        return false, "settings file was not written"
    end
    for key, value in pairs(values) do
        if written:readSetting(key) ~= value then
            logger.err("Gota Settings: saved configuration does not match:", key)
            return false, "settings file was not written"
        end
    end
    if written:readSetting("tls_ca_file") ~= values.tls_ca_file then
        return false, "settings file was not written"
    end
    return true
end

function Settings:getToken()
    return session_token or ""
end

function Settings:setToken(token)
    token = type(token) == "string" and token or ""
    if token ~= session_token then
        session_token = token
        session_generation = session_generation + 1
    end
end

function Settings:getSessionGeneration()
    return session_generation
end

function Settings:isTLSVerificationEnabled()
    return session_tls_verify
end

function Settings:setTLSVerificationEnabled(enabled)
    session_tls_verify = enabled ~= false
end

function Settings:getTLSCAFile()
    return type(session_ca_file) == "string" and session_ca_file ~= "" and session_ca_file or nil
end

function Settings:setTLSCAFile(path)
    session_ca_file = type(path) == "string" and path ~= "" and path or nil
end

function Settings:clearToken()
    local previous_token = self:getToken()
    self:setToken("")
    local saved, save_error = self:save()
    if not saved then
        self:setToken(previous_token)
        return false, save_error
    end
    return true
end

function Settings:isTokenValid()
    return self:getToken() ~= ""
end

function Settings:getDownloadPath()
    return normalizeDownloadPath(session_preferences and session_preferences.download_path)
end

function Settings:validateDownloadPath(path)
    return validateDownloadPath(path)
end

function Settings:setDownloadPath(path)
    local normalized, validation_error = validateDownloadPath(path)
    if not normalized then return nil, validation_error end
    session_preferences.download_path = normalized
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
            session_preferences.download_path = DEFAULT_DOWNLOAD_PATH
            candidate = data_dir .. "/" .. DEFAULT_DOWNLOAD_PATH
        end
    end

    return candidate .. "/"
end

function Settings:getSettingsPath()
    return self.settings_path
end

function Settings:getSortOrder()
    return normalizeSortOrder(session_preferences and session_preferences.sort_order)
end

function Settings:setSortOrder(sort)
    session_preferences.sort_order = normalizeSortOrder(sort)
end

function Settings:getMaxCacheMemoryBytes()
    return normalizePreset(session_preferences and session_preferences.max_cache_memory_bytes,
        CACHE_MEMORY_PRESETS, DEFAULT_CACHE_MEMORY_BYTES)
end

function Settings:setMaxCacheMemoryBytes(value)
    local normalized = normalizePreset(value, CACHE_MEMORY_PRESETS, nil)
    if not normalized then return nil end
    session_preferences.max_cache_memory_bytes = normalized
    return normalized
end


function Settings:getMaxCacheFileBytes()
    return normalizePreset(session_preferences and session_preferences.max_cache_file_bytes,
        CACHE_FILE_PRESETS, DEFAULT_CACHE_FILE_BYTES)
end

function Settings:setMaxCacheFileBytes(value)
    local normalized = normalizePreset(value, CACHE_FILE_PRESETS, nil)
    if not normalized then return nil end
    session_preferences.max_cache_file_bytes = normalized
    return normalized
end

function Settings:getDebugInfo()
    local settings_path = self.settings_path
    local lfs = require("libs/libkoreader-lfs")
    local attr = lfs.attributes(settings_path)
    return {
        token_status = self:getToken() ~= "" and "configured" or "not configured",
        settings_file = settings_path,
        file_exists = attr ~= nil,
        file_size = attr and attr.size or 0,
        sort_order = self:getSortOrder(),
        download_path = self:getDownloadPath(),
        max_cache_memory_bytes = self:getMaxCacheMemoryBytes(),
        max_cache_file_bytes = self:getMaxCacheFileBytes(),
        max_cache_memory_mib = self:getMaxCacheMemoryBytes() / MIB,
        max_cache_file_mib = self:getMaxCacheFileBytes() / MIB,
    }
end

return Settings
