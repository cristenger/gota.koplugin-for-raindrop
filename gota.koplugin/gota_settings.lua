local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")

local Settings = {}

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
    o.config = LuaSettings:open(settings_path)

    if o.config then
        o.token = o.config:readSetting("token") or ""
        o.download_path = o.config:readSetting("download_path") or "gota_articles"
        o.sort_order = o.config:readSetting("sort_order") or "-created"
    else
        logger.warn("Gota Settings: could not open config, using defaults")
        o.token = ""
        o.download_path = "gota_articles"
        o.sort_order = "-created"
    end

    logger.dbg("Gota Settings: loaded, token:", o.token ~= "" and "present" or "empty")
    return o
end

function Settings:save()
    if not self.config then
        logger.err("Gota Settings: cannot save, config not initialized")
        return false
    end

    self.config:saveSetting("token", self.token)
    self.config:saveSetting("download_path", self.download_path)
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
    return self.download_path or "gota_articles"
end

function Settings:setDownloadPath(path)
    self.download_path = path or "gota_articles"
end

function Settings:getFullDownloadPath()
    return DataStorage:getDataDir() .. "/" .. self:getDownloadPath() .. "/"
end

function Settings:getSortOrder()
    return self.sort_order or "-created"
end

function Settings:setSortOrder(sort)
    self.sort_order = sort or "-created"
end

function Settings:getDebugInfo()
    local settings_path = DataStorage:getSettingsDir() .. "/gota.lua"
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
