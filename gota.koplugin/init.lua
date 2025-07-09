local WidgetContainer = require("ui/widget/container/widgetcontainer")

-- Actualizar las rutas de los submódulos (quitar "core.")
local UI          = require("ui")
local Auth        = require("auth")
local Api         = require("api")
local Collections = require("collections")
local Content     = require("content")
local Search      = require("search")
local Debug       = require("debug_utils")   -- Renombrado para evitar conflicto

local Gota = WidgetContainer:extend{
    name = "gota",
    is_doc_only = false,
}

function Gota:init()
    -- estado global
    self.server_url      = "https://api.raindrop.io/rest/v1"
    self.response_cache  = {}
    self.cache_ttl       = 300

    -- sub-módulos principales
    self.ui   = setmetatable({}, { __index = UI   }); self.ui:init(self)
    self.api  = setmetatable({}, { __index = Api  }); self.api:init(self)
    self.auth = setmetatable({}, { __index = Auth }); self.auth:init(self)

    self.collections = setmetatable({}, { __index = Collections })
    self.collections:init(self, self.api, self.ui)

    self.content = setmetatable({}, { __index = Content })
    self.content:init(self, self.api, self.ui)

    self.search = setmetatable({}, { __index = Search })
    self.search:init(self, self.api, self.ui)

    -- módulo de depuración
    self.debug = setmetatable({}, { __index = Debug })
    self.debug:init(self, self.api)

    -- registrar entrada en menú principal
    self.ui:addToMainMenu(self)
end

return Gota