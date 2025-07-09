local WidgetContainer = require("ui/widget/container/widgetcontainer")

-- sub-módulos
local UI          = require("core.ui")
local Auth        = require("core.auth")
local Api         = require("core.api")
local Collections = require("core.collections")
local Content     = require("core.content")
local Search      = require("core.search")
local Debug       = require("core.debug")   -- ← nuevo módulo

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