local DataStorage = require("datastorage")
local logger = require("logger")

local Settings = {}

-- Función robusta para parsear configuración
local function parseSettings(content)
    local env = {}
    local chunk, err = loadstring(content)
    if chunk then
        -- Usar pcall con manejo de errores más detallado
        local ok, result = pcall(function()
            setfenv(chunk, env)
            return chunk()
        end)
        
        if ok then
            -- Verificar específicamente si token existe en env
            if env and env.token then
                logger.dbg("Gota: Token encontrado en configuración")
                return env
            elseif result and type(result) == "table" and result.token then
                logger.dbg("Gota: Token encontrado en resultado de chunk")
                return result
            else
                logger.warn("Gota: Configuración cargada pero no contiene token")
            end
        else
            logger.warn("Gota: Error ejecutando chunk:", result)
        end
    else
        logger.warn("Gota: No se pudo parsear configuración:", err)
    end
    
    return {}
end

function Settings:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    
    o.settings_file = DataStorage:getSettingsDir() .. "/gota.lua"
    o.token = ""
    o.download_path = "gota_articles"  -- Carpeta por defecto para descargas
    
    return o
end

function Settings:load()
    logger.dbg("Gota DEBUG: Intentando cargar configuración desde: " .. self.settings_file)
    
    local settings = {}
    
    if self.settings_file then
        local file = io.open(self.settings_file, "r")
        if file then
            local content = file:read("*all")
            file:close()
            
            logger.dbg("Gota: Contenido leído del archivo:", content and #content or "nil")
            
            if content and content ~= "" then
                -- Usar función de parsing robusta
                settings = parseSettings(content)
                if next(settings) then
                    logger.dbg("Gota: Configuración cargada exitosamente")
                    logger.dbg("Gota: Token cargado con longitud:", settings.token and #settings.token or "nil")
                else
                    logger.warn("Gota: No se pudo parsear configuración, usando defaults")
                end
            else
                logger.dbg("Gota: Archivo vacío o no legible")
            end
        else
            logger.dbg("Gota: Archivo de configuración no existe, usando defaults")
        end
    end
    
    self.token = settings.token or ""
    self.download_path = settings.download_path or "gota_articles"
    
    logger.dbg("Gota: Token final cargado, longitud:", #self.token)
    logger.dbg("Gota: Carpeta de descargas:", self.download_path)
end

function Settings:save()
    local settings = {
        token = self.token,
        download_path = self.download_path,
    }
    
    logger.dbg("Gota: Intentando guardar token, longitud:", #self.token)
    logger.dbg("Gota: Carpeta de descargas:", self.download_path)
    
    -- Crear directorio si no existe
    local settings_dir = DataStorage:getSettingsDir()
    local lfs = require("libs/libkoreader-lfs")
    if not lfs.attributes(settings_dir, "mode") then
        lfs.mkdir(settings_dir)
    end
    
    local file, err = io.open(self.settings_file, "w")
    if file then
        -- Serialización más robusta con escape completo
        local serialized = string.format("return {\n  token = %q,\n  download_path = %q,\n}\n", 
                                        settings.token, settings.download_path)
        file:write(serialized)
        file:close()
        logger.dbg("Gota: Configuración guardada exitosamente")
        
        -- Verificar que se guardó correctamente
        local verify_file = io.open(self.settings_file, "r")
        if verify_file then
            local saved_content = verify_file:read("*all")
            verify_file:close()
            logger.dbg("Gota: Contenido verificado guardado:", saved_content and #saved_content or "nil")
        end
        
        return true
    else
        logger.err("Gota: No se pudo abrir archivo para escritura:", err)
        return false, err
    end
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
    local debug_info = {}
    debug_info.token_status = self.token ~= "" and ("SET (" .. #self.token .. " chars)") or "NO SET"
    debug_info.settings_file = self.settings_file or "NO SET"
    
    if self.settings_file then
        local file = io.open(self.settings_file, "r")
        if file then
            local content = file:read("*all")
            file:close()
            debug_info.file_exists = true
            debug_info.file_size = content and #content or 0
            debug_info.file_content = content and content:sub(1, 200) or "VACÍO"
        else
            debug_info.file_exists = false
        end
    end
    
    return debug_info
end

return Settings