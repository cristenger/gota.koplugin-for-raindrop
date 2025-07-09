local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")  -- Carga el util de KOReader, no el de tu plugin

-- Obtener la ruta absoluta correcta usando el ID del plugin
local _, dirname = util.splitFilePathName(debug.getinfo(1, "S").source:sub(2))
dirname = dirname:match("(.+)/[^/]+$") or dirname
local plugin_path = DataStorage:getDataDir() .. "/plugins/" .. dirname

-- Registrar la ruta para depuración
logger.info("Ruta absoluta del plugin:", plugin_path)

-- Precargar los módulos core con rutas absolutas
package.loaded["core.ui"] = dofile(plugin_path .. "/core/ui.lua")
package.loaded["core.auth"] = dofile(plugin_path .. "/core/auth.lua") 
package.loaded["core.api"] = dofile(plugin_path .. "/core/api.lua")
package.loaded["core.collections"] = dofile(plugin_path .. "/core/collections.lua")
package.loaded["core.content"] = dofile(plugin_path .. "/core/content.lua")
package.loaded["core.search"] = dofile(plugin_path .. "/core/search.lua")
package.loaded["core.debug"] = dofile(plugin_path .. "/core/debug.lua")
package.loaded["util"] = dofile(plugin_path .. "/util.lua")  -- Aquí sobreescribes el módulo util con tu versión

-- Cargar init.lua y crear instancia
local Gota = dofile(plugin_path .. "/init.lua")
return Gota:new{}