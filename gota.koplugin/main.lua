local logger = require("logger")

-- Función simple para determinar la ruta del plugin
local function getPluginDir()
    local path = debug.getinfo(1, "S").source:sub(2)  -- Quita el @ inicial
    return path:match("(.+)/[^/]+$")
end

local plugin_dir = getPluginDir()
logger.info("Ruta del plugin:", plugin_dir)

-- Cargar solo init.lua y crear instancia
local Gota = dofile(plugin_dir .. "/init.lua")
return Gota:new{}