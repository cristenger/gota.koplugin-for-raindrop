local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")

local Settings = {}
local DEFAULT_DOWNLOAD_PATH = "gota_articles"
local DEFAULT_SORT_ORDER = "-created"
local ALLOWED_SORT_ORDERS = {
    ["-created"] = true,
    created = true,
    title = true,
    ["-title"] = true,
    ["-sort"] = true,
}

local function normalizeSortOrder(value)
    return ALLOWED_SORT_ORDERS[value] and value or DEFAULT_SORT_ORDER
end

local function pathIsInside(base_path, candidate_path)
    base_path = base_path:gsub("/+$", "")
    candidate_path = candidate_path:gsub("/+$", "")
    return candidate_path == base_path or
        candidate_path:sub(1, #base_path + 1) == base_path .. "/"
end

local function normalizeDownloadPath(path)
    if type(path) ~= "string" then
        return DEFAULT_DOWNLOAD_PATH
    end

    path = path:gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    if path == "" or path:sub(1, 1) == "/" or path:find("%c") then
        return DEFAULT_DOWNLOAD_PATH
    end

    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            return DEFAULT_DOWNLOAD_PATH
        elseif part ~= "." and part ~= "" then
            table.insert(parts, part)
        end
    end

    if #parts == 0 then
        return DEFAULT_DOWNLOAD_PATH
    end
    return table.concat(parts, "/")
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
    else
        logger.warn("Gota Settings: could not open config, using defaults")
        o.token = ""
        o.download_path = DEFAULT_DOWNLOAD_PATH
        o.sort_order = DEFAULT_SORT_ORDER
    end

    logger.dbg("Gota Settings: loaded, token:", o.token ~= "" and "present" or "empty")
    return o
end

function Settings:save()
    if not self.config then
        logger.err("Gota Settings: cannot save, config not initialized")
        return false
    end

    self.download_path = normalizeDownloadPath(self.download_path)
    self.config:saveSetting("token", self.token)
    self.config:saveSetting("download_path", self.download_path)
    self.sort_order = normalizeSortOrder(self.sort_order)
    self.config:saveSetting("sort_order", self.sort_order)
    self.config:flush()
    return true
end

function Settings:getToken()
    return self.token
end

function Settings:setToken(token)
    self.token = token or ""
end

function Settings:isTokenValid()
    return self.token and self.token ~= ""
end

function Settings:getDownloadPath()
    return normalizeDownloadPath(self.download_path)
end

function Settings:setDownloadPath(path)
    self.download_path = normalizeDownloadPath(path)
    return self.download_path
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
    }
end

return Settings
