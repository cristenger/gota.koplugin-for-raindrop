local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")

local Settings = {}

function Settings:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    
    -- Usar LuaSettings de KOReader (más robusto)
    local settings_path = DataStorage:getSettingsDir() .. "/gota.lua"
    o.config = LuaSettings:open(settings_path)
    
    -- Valores por defecto
    o.token = o.config:readSetting("token") or ""
    o.download_path = o.config:readSetting("download_path") or "gota_articles"
    
    logger.dbg("Gota Settings: Loaded - Token:", o.token ~= "" and "present" or "empty")
    
    return o
end

function Settings:save()
    logger.dbg("Gota Settings: Saving token:", self.token ~= "" and "present" or "empty")
    
    self.config:saveSetting("token", self.token)
    self.config:saveSetting("download_path", self.download_path)
    self.config:flush()
    
    logger.dbg("Gota Settings: Configuration saved and flushed")
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
    local DataStorage = require("datastorage")
    return DataStorage:getDataDir() .. "/" .. self:getDownloadPath() .. "/"
end

function Settings:getDebugInfo()
    local settings_path = DataStorage:getSettingsDir() .. "/gota.lua"
    local debug_info = {}
    debug_info.token_status = self.token ~= "" and "configured" or "not configured"
    debug_info.settings_file = settings_path
    
    local lfs = require("libs/libkoreader-lfs")
    local attr = lfs.attributes(settings_path)
    if attr then
        debug_info.file_exists = true
        debug_info.file_size = attr.size
    else
        debug_info.file_exists = false
    end
    
    return debug_info
end

return Settings