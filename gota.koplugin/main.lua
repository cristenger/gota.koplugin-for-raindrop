local DataStorage = require("datastorage")
local logger = require("logger")

-- Función simple para determinar la ruta del plugin
local function getPluginDir()
    local path = debug.getinfo(1, "S").source:sub(2)  -- Quita el @ inicial
    return path:match("(.+)/[^/]+$")
end

local plugin_dir = getPluginDir()
logger.info("Ruta del plugin:", plugin_dir)

-- Precargar los módulos (ahora en la raíz)
package.loaded["ui"] = dofile(plugin_dir .. "/ui.lua")
package.loaded["auth"] = dofile(plugin_dir .. "/auth.lua") 
package.loaded["api"] = dofile(plugin_dir .. "/api.lua")
package.loaded["collections"] = dofile(plugin_dir .. "/collections.lua")
package.loaded["content"] = dofile(plugin_dir .. "/content.lua")
package.loaded["search"] = dofile(plugin_dir .. "/search.lua")
package.loaded["util"] = dofile(plugin_dir .. "/util.lua")

-- Cargar init.lua y crear instancia
local Gota = dofile(plugin_dir .. "/init.lua")
return Gota:new{}