--[[
    Gota: Lector para Raindrop.io en KOReader
    Permite leer artículos guardados en Raindrop.io directamente en tu dispositivo.
    
    Versión: 1.6 (Modularizado con settings.lua)
    
    IMPORTANTE: SSL está desactivado para evitar problemas de certificados
    en dispositivos Kindle. Esto es necesario para que funcione correctamente.
]]

local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local JSON = require("json")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

-- MÓDULO DE SETTINGS
local Settings = require("settings")

local Gota = WidgetContainer:extend{
    name = "gota",
    is_doc_only = false,
}

-- Función auxiliar para codificar URLs
local function urlEncode(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("([^%w%-%.%_%~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = str:gsub(" ", "+")
    return str
end

-- Función auxiliar para obtener keys de tabla
local function table_keys(t)
    local keys = {}
    if type(t) == "table" then
        for k, _ in pairs(t) do
            table.insert(keys, tostring(k))
        end
    end
    return keys
end

function Gota:notify(text, timeout)
    timeout = timeout or 3
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout,
    })
end

function Gota:init()
    -- SISTEMA MODULARIZADO: Inicializar el módulo de settings
    self.settings = Settings:new()
    self.settings:load()
    
    self.server_url = "https://api.raindrop.io/rest/v1"
    
    -- Configurar SSL una sola vez al inicio
    https.cert_verify = false
    logger.dbg("Gota: SSL verificación desactivada para compatibilidad")
    
    -- Inicializar caché para respuestas
    self.response_cache = {}
    self.cache_ttl = 300  -- 5 minutos de vida para el caché
    
    self.ui.menu:registerToMainMenu(self)
end

function Gota:addToMainMenu(menu_items)
    menu_items.gota = {
        text = _("Gota (Raindrop.io)"),
        sorting_hint = "search",
        sub_item_table = {
            {
                text = _("Configurar token de acceso"),
                callback = function()
                    self:showTokenDialog()
                end,
            },
            {
                text = _("Debug: Ver configuración"),
                callback = function()
                    self:showDebugInfo()
                end,
            },
            {
                text = _("Ver colecciones"),
                enabled_func = function()
                    return self.settings:isTokenValid()
                end,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        self:showCollections()
                    end)
                end,
            },
            {
                text = _("Buscar artículos"),
                enabled_func = function()
                    return self.settings:isTokenValid()
                end,
                callback = function()
                    self:showSearchDialog()
                end,
            },
            {
                text = _("Todos los artículos"),
                enabled_func = function()
                    return self.settings:isTokenValid()
                end,
                callback = function()
                    NetworkMgr:runWhenOnline(function()
                        self:showRaindrops(0, _("Todos los artículos"))
                    end)
                end,
            },
        }
    }
end

function Gota:showTokenDialog()
    self.token_dialog = InputDialog:new{
        title = _("Token de acceso de Raindrop.io"),
        description = _("OPCIÓN 1 - Test Token (Recomendado):\n• Ve a: https://app.raindrop.io/settings/integrations\n• Crea una nueva aplicación\n• Copia el 'Test token'\n\nOPCIÓN 2 - Token Personal:\n• Usa un token de acceso personal\n\nPega el token aquí:"),
        input = self.settings:getToken(),
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancelar"),
                    callback = function()
                        UIManager:close(self.token_dialog)
                    end,
                },
                {
                    text = _("Probar"),
                    callback = function()
                        local test_token = self.token_dialog:getInputText()
                        if test_token and test_token ~= "" then
                            test_token = test_token:gsub("^%s+", ""):gsub("%s+$", "")
                            if test_token ~= "" then
                                NetworkMgr:runWhenOnline(function()
                                    self:testToken(test_token)
                                end)
                            else
                                self:notify(_("Por favor ingresa un token para probar"))
                            end
                        else
                            self:notify(_("Por favor ingresa un token para probar"))
                        end
                    end,
                },
                {
                    text = _("Guardar"),
                    is_enter_default = true,
                    callback = function()
                        local new_token = self.token_dialog:getInputText()
                        if new_token and new_token ~= "" then
                            new_token = new_token:gsub("^%s+", ""):gsub("%s+$", "")
                            
                            logger.dbg("Gota: Token recibido, longitud:", #new_token)
                            
                            if new_token == "" then
                                self:notify(_("Por favor ingresa un token válido"), 2)
                                return
                            end
                            
                            if #new_token < 10 then
                                self:notify(_("⚠️ Token parece muy corto, pero se guardará de todos modos"), 3)
                            end
                            
                            self.settings:setToken(new_token)
                            local success, err = self.settings:save()
                            UIManager:close(self.token_dialog)
                            
                            if success then
                                self:notify(_("Token guardado correctamente\nUsa 'Probar' para verificar funcionalidad"), 3)
                            else
                                self:notify("Error: No se pudo guardar la configuración - " .. (err or "desconocido"))
                            end
                        else
                            self:notify(_("Por favor ingresa un token válido"), 2)
                        end
                    end,
                }
            }
        },
    }
    UIManager:show(self.token_dialog)
    self.token_dialog:onShowKeyboard()
end

function Gota:makeRequest(endpoint, method, body)
    local url = self.server_url .. endpoint
    logger.dbg("Gota: Iniciando solicitud a", url)

    local loading_msg = InfoMessage:new{ text = _("Conectando…"), timeout = 0 }
    UIManager:show(loading_msg)
    UIManager:forceRePaint()

    local sink = {}
    local request = {
        url     = url,
        method  = method or "GET",
        headers = {
            ["Authorization"] = "Bearer " .. self.settings:getToken(),
            ["Content-Type"]  = "application/json",
            ["User-Agent"]    = "KOReader-Gota-Plugin/1.6",
            ["Accept-Encoding"] = "gzip, identity",
        },
        sink    = ltn12.sink.table(sink),
        protocol = "any",
        timeout = 30,
    }

    if body then
        request.headers["Content-Length"] = tostring(#body)
        request.source = ltn12.source.string(body)
    end

    local protocol = url:match("^https://") and https or http
    local ok, actual_status, headers = protocol.request(request)

    UIManager:close(loading_msg)

    if ok and actual_status == 200 then
        local resp = table.concat(sink)
        logger.dbg("Gota: Respuesta exitosa, tamaño:", #resp)
        
        if #resp == 0 then
            logger.warn("Gota: Respuesta vacía del servidor")
            return nil, _("Respuesta vacía del servidor")
        end

        -- INICIO: Añadir código para manejo de Gzip y HTML
        local is_gzipped = false
        if headers and headers["content-encoding"] then
            local encoding = headers["content-encoding"]:lower()
            is_gzipped = encoding:find("gzip") ~= nil
        end
        
        local might_be_gzipped = resp:byte(1) == 31 and resp:byte(2) == 139
        
        if is_gzipped or might_be_gzipped then
            logger.dbg("Gota: Detectada respuesta comprimida con Gzip")
            local temp_in = "/tmp/gota_gzip_" .. os.time() .. ".gz"
            local temp_out = "/tmp/gota_out_" .. os.time() .. ".txt"
            
            local file = io.open(temp_in, "wb")
            if file then
                file:write(resp)
                file:close()
                
                local ok = os.execute("gunzip -c " .. temp_in .. " > " .. temp_out .. " 2>/dev/null")
                if ok ~= 0 then
                    ok = os.execute("gzip -dc " .. temp_in .. " > " .. temp_out .. " 2>/dev/null")
                end
                
                if ok == 0 then
                    file = io.open(temp_out, "rb")
                    if file then
                        resp = file:read("*all")
                        file:close()
                        logger.dbg("Gota: Descompresión exitosa con comando del sistema")
                    end
                end
                
                os.remove(temp_in)
                os.remove(temp_out)
            else
                logger.err("Gota: No se pudo crear archivo temporal para descompresión")
            end
            
            if resp:byte(1) == 31 and resp:byte(2) == 139 then
                return nil, _("Error: No se pudo descomprimir la respuesta del servidor")
            end
        end
        
        -- Verificar si es HTML directo (endpoint /cache)
        if endpoint:match("/cache$") then
            logger.dbg("Gota: Respuesta de caché detectada como HTML directo")
            return resp  -- Devolver HTML sin procesar como JSON
        end
        -- FIN: Código añadido para Gzip y HTML

        local data, parse_err = JSON.decode(resp)
        if data then
            logger.dbg("Gota: JSON parseado exitosamente")
            return data, nil
        else
            logger.err("Gota: Error al parsear JSON:", parse_err)
            logger.dbg("Gota: Respuesta raw:", resp:sub(1, 200))
            return nil, _("Error al procesar respuesta del servidor")
        end
    elseif ok and actual_status ~= 200 then
        local msg = _("Error del servidor: ") .. tostring(actual_status)
        if headers then
            local R = headers["x-ratelimit-remaining"]
            if R and tonumber(R) and tonumber(R) < 5 then
                msg = msg .. " Restantes:" .. (R or "?")
            end
        end
        return nil, msg
    else
        local resp = table.concat(sink)
        logger.err("Gota: HTTP error", actual_status, resp:sub(1,200))
        return nil, _("Error HTTP ") .. tostring(actual_status)
    end
end

function Gota:makeRequestWithRetry(endpoint, method, body, max_retries)
    max_retries = max_retries or 3
    local attempts = 0
    
    while attempts < max_retries do
        attempts = attempts + 1
        
        if attempts > 1 then
            local progress_message = InfoMessage:new{text = _("Reintentando conexión (") .. attempts .. "/" .. max_retries .. ")...", timeout = 1}
            UIManager:show(progress_message)
            UIManager:forceRePaint()
            os.execute("sleep 1")
        end
        
        local result, err = self:makeRequest(endpoint, method, body)
        
        if result or (err and not err:match("conexión") and not err:match("timeout")) then
            return result, err
        end
        
        logger.warn("Gota: Reintentando solicitud después de error:", err)
    end
    
    return nil, _("Falló después de ") .. max_retries .. _(" intentos")
end

function Gota:showProgress(text)
    if self.progress_message then
        UIManager:close(self.progress_message)
    end
    self.progress_message = InfoMessage:new{text = text, timeout = 1}
    UIManager:show(self.progress_message)
    UIManager:forceRePaint()
end

function Gota:hideProgress()
    if self.progress_message then 
        UIManager:close(self.progress_message) 
    end
    self.progress_message = nil
end

function Gota:cachedRequest(endpoint, method, body, use_cache)
    use_cache = (use_cache == nil) and (method == "GET" or method == nil) or use_cache
    
    if use_cache and method == "GET" then
        local cache_key = endpoint
        local cached = self.response_cache[cache_key]
        
        if cached and os.time() - cached.timestamp < self.cache_ttl then
            logger.dbg("Gota: Usando respuesta en caché para", endpoint)
            return cached.data, nil
        end
    end
    
    local result, err = self:makeRequestWithRetry(endpoint, method, body)
    
    if result and method == "GET" and use_cache then
        local cache_key = endpoint
        self.response_cache[cache_key] = {
            data = result,
            timestamp = os.time()
        }
    end
    
    return result, err
end

function Gota:showCollections()
    self:showProgress(_("Cargando colecciones..."))
    local collections, err = self:cachedRequest("/collections")
    self:hideProgress()
    
    if not collections then
        self:notify(_("Error al obtener colecciones:") .. "\n" .. (err or _("Error desconocido")), 4)
        return
    end
    
    local menu_items = {}
    
    if not collections.items or #collections.items == 0 then
        table.insert(menu_items, {
            text = _("No tienes colecciones creadas"),
            enabled = false,
        })
    else
        for _, collection in ipairs(collections.items) do
            table.insert(menu_items, {
                text = string.format("%s (%d)", collection.title, collection.count or 0),
                callback = function()
                    self:showRaindrops(collection._id, collection.title)
                end,
            })
        end
    end
    
    if self.collections_menu then
        UIManager:close(self.collections_menu)
        self.collections_menu = nil
    end
    
    self.collections_menu = Menu:new{
        title = _("Colecciones de Raindrop"),
        item_table = menu_items,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(self.collections_menu)
end

function Gota:showRaindrops(collection_id, collection_name, page)
    page = page or 0
    local perpage = 25
    local endpoint = string.format("/raindrops/%s?perpage=%d&page=%d", collection_id, perpage, page)
    
    self:showProgress(_("Cargando artículos..."))
    local raindrops, err = self:cachedRequest(endpoint)
    self:hideProgress()
    
    if not raindrops then
        self:notify(_("Error al obtener artículos: ") .. (err or _("Error desconocido")), 4)
        return
    end
    
    local menu_items = {}
    
    if raindrops.items and #raindrops.items > 0 then
        -- Store translation function before loop to prevent shadowing
        local translation_func = _
        for _, raindrop in ipairs(raindrops.items) do
            local title = raindrop.title or translation_func("Sin título")
            local domain = raindrop.domain or ""
            local excerpt = ""
            if raindrop.excerpt then
                excerpt = "\n" .. raindrop.excerpt:sub(1, 50) .. "..."
            end
            
            -- Add a submenu with options for each article
            table.insert(menu_items, {
                text = title .. "\n" .. domain .. excerpt,
                sub_item_table = {
                    {
                        text = translation_func("Ver contenido"),
                        callback = function()
                            self:showRaindropContent(raindrop)
                        end,
                    },
                    {
                        text = translation_func("Descargar HTML"),
                        enabled = raindrop.cache and raindrop.cache.status == "ready",
                        callback = function()
                            self:downloadRaindropHTML(raindrop)
                        end,
                    }
                }
            })
        end
        
        local total_count = raindrops.count or 0
        if total_count > perpage then
            local total_pages = math.ceil(total_count / perpage)
            local current_page = page + 1
            
            table.insert(menu_items, {text = "──────────────────", enabled = false})
            
            -- Paginación mejorada
            -- Añadir navegación a primera página si no estamos cerca
            if current_page > 3 then
                table.insert(menu_items, {
                    text = _("« Primera página"),
                    callback = function()
                        self:showRaindrops(collection_id, collection_name, 0)
                    end,
                })
            end
            
            -- Salto hacia atrás (5 páginas)
            if current_page > 6 then
                local translation_func = _  -- Store reference to translation function
                table.insert(menu_items, {
                    text = string.format(translation_func("« -%d páginas"), 5),
                    callback = function()
                        self:showRaindrops(collection_id, collection_name, page - 5)
                    end,
                })
            end
            
            -- Página anterior
            if page > 0 then
                table.insert(menu_items, {
                    text = _("← Página anterior"),
                    callback = function()
                        self:showRaindrops(collection_id, collection_name, page - 1)
                    end,
                })
            end
            
            -- Mostrar números de páginas cercanas
            local start_page = math.max(0, current_page - 2)
            local end_page = math.min(total_pages, current_page + 2)
            local translation_func = _  -- Store reference to avoid shadowing
            
            for i = start_page, end_page do
                if i == 0 then
                    -- Ignorar página 0 (usamos índice 1-based para mostrar)
                else
                    table.insert(menu_items, {
                        text = i == current_page 
                              and string.format(translation_func("[Página %d]"), i) 
                              or string.format(translation_func("Página %d"), i),
                        enabled = i ~= current_page,
                        callback = function()
                            self:showRaindrops(collection_id, collection_name, i - 1)
                        end,
                    })
                end
            end
            
            -- Página siguiente
            if current_page < total_pages then
                table.insert(menu_items, {
                    text = _("Página siguiente →"),
                    callback = function()
                        self:showRaindrops(collection_id, collection_name, page + 1)
                    end,
                })
            end
            
            -- Salto hacia adelante (5 páginas)
            if current_page < total_pages - 5 then
                local translation_func = _  -- Store reference to translation function
                table.insert(menu_items, {
                    text = string.format(translation_func("» +%d páginas"), 5),
                    callback = function()
                        self:showRaindrops(collection_id, collection_name, page + 5)
                    end,
                })
            end
            
            -- Última página
            if current_page < total_pages - 2 then
                table.insert(menu_items, {
                    text = _("» Última página"),
                    callback = function()
                        self:showRaindrops(collection_id, collection_name, total_pages - 1)
                    end,
                })
            end
            
            -- Información sobre la paginación
            local translation_func = _  -- Store reference to translation function
            table.insert(menu_items, {
                text = string.format(translation_func("Mostrando %d-%d de %d artículos"), 
                    page * perpage + 1,
                    math.min((page + 1) * perpage, total_count),
                    total_count),
                enabled = false,
            })
        end
    else
        table.insert(menu_items, {
            text = _("No hay artículos en esta colección"),
            enabled = false,
        })
    end
    
    local total_count = raindrops.count or 0
    
    if self.raindrops_menu then
        UIManager:close(self.raindrops_menu)
        self.raindrops_menu = nil
    end
    
    self.raindrops_menu = Menu:new{
        title = string.format("%s (%d)", collection_name or _("Artículos"), total_count),
        item_table = menu_items,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(self.raindrops_menu)
end

function Gota:showRaindropContent(raindrop)
    if not raindrop.cache then
        self:showProgress(_("Cargando contenido completo..."))
        local full_raindrop, err = self:cachedRequest("/raindrop/" .. raindrop._id)
        self:hideProgress()
        
        if full_raindrop and full_raindrop.item then
            raindrop = full_raindrop.item
        end
    end
    
    logger.dbg("Gota: Datos completos del caché:", 
               "cache:", raindrop.cache and "presente" or "nil",
               "status:", raindrop.cache and raindrop.cache.status or "n/a",
               "size:", raindrop.cache and raindrop.cache.size or 0,
               "texto presente:", raindrop.cache and raindrop.cache.text and "SÍ" or "NO",
               "texto longitud:", raindrop.cache and raindrop.cache.text and #raindrop.cache.text or 0)
    
    local has_cache = raindrop.cache and 
                     raindrop.cache.status == "ready" and 
                     (raindrop.cache.text or (raindrop.cache.size and raindrop.cache.size > 0))
    
    if has_cache and not raindrop.cache.text then
        self:showProgress(_("Cargando contenido en caché..."))
        local cache_content, err = self:makeRequestWithRetry("/raindrop/" .. raindrop._id .. "/cache")
        self:hideProgress()
        
        if cache_content and type(cache_content) == "string" and #cache_content > 0 then
            raindrop.cache.text = cache_content
            logger.dbg("Gota: Contenido HTML recibido correctamente, longitud:", #cache_content)
        elseif not raindrop.cache.text then
            raindrop.cache.text = _("Contenido disponible para descarga. Usa el botón 'Descargar HTML'.")
        end
    end
    
    if has_cache and (not raindrop.cache.text or #raindrop.cache.text < 50) then
        has_cache = false
    end
    
   --[[  if has_cache then
        self:showRaindropCachedContent(raindrop)
        return
    end ]]
    
    local view_options = {
        {
            text = _("📖 Abrir en lector completo"),
            enabled = has_cache,
            callback = function()
                if has_cache then
                    self:openInReader(raindrop)
                else
                    self:notify(_("El contenido no está disponible aún"))
                end
            end
        },
        {
            text = _("Ver información del artículo"),
            callback = function()
                self:showRaindropInfo(raindrop)
            end
        },
    }
    
    if raindrop.link then
        table.insert(view_options, {
            text = _("Copiar URL"),
            callback = function()
                self:showLinkInfo(raindrop)
            end
        })
    end
    
    local cache_message = ""
    if not has_cache and raindrop.cache then
        local status_names = {
            retry = _("La caché está siendo generada, intenta más tarde"),
            failed = _("La generación de caché ha fallado"),
            ["invalid-origin"] = _("No se pudo generar caché por origen inválido"),
            ["invalid-timeout"] = _("No se pudo generar caché por timeout"),
            ["invalid-size"] = _("No se pudo generar caché por tamaño excesivo")
        }
        cache_message = status_names[raindrop.cache.status] or _("La caché no está disponible")
        
        table.insert(view_options, {
            text = _("Intentar recargar artículo completo"),
            callback = function()
                self:reloadRaindrop(raindrop._id)
            end
        })
    elseif not has_cache then
        cache_message = _("Este artículo no tiene contenido en caché disponible")
    end
    
    if cache_message ~= "" then
        table.insert(view_options, 1, {
            text = cache_message,
            enabled = false,
        })
    end
    
    if self.article_menu then
        UIManager:close(self.article_menu)
        self.article_menu = nil
    end
    
    self.article_menu = Menu:new{
        title = raindrop.title or _("Artículo"),
        item_table = view_options,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(self.article_menu)
end

function Gota:reloadRaindrop(raindrop_id)
    self:showProgress(_("Recargando artículo..."))
    local full_raindrop, err = self:cachedRequest("/raindrop/" .. raindrop_id, "GET", nil, false)
    self:hideProgress()
    
    if full_raindrop and full_raindrop.item then
        if full_raindrop.item.cache and 
           full_raindrop.item.cache.status == "ready" and 
           full_raindrop.item.cache.text then
            self:showRaindropCachedContent(full_raindrop.item)
        else
            self:notify(_("El artículo aún no tiene contenido en caché disponible"))
            self:showRaindropInfo(full_raindrop.item)
        end
    else
        self:notify(_("Error al recargar artículo: ") .. (err or _("Error desconocido")))
    end
end

function Gota:showRaindropInfo(raindrop)
    local content = ""
    
    content = content .. (raindrop.title or _("Sin título")) .. "\n"
    content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    
    if raindrop.link then
        content = content .. _("URL: ") .. raindrop.link .. "\n\n"
    end
    
    if raindrop.domain then
        content = content .. _("Dominio: ") .. raindrop.domain .. "\n"
    end
    
    if raindrop.created then
        local date = raindrop.created:sub(1, 10)
        local time = raindrop.created:sub(12, 19)
        content = content .. _("Guardado: ") .. date .. " " .. time .. "\n\n"
    end
    
    if raindrop.type then
        local type_names = {
            link = _("Enlace"),
            article = _("Artículo"),
            image = _("Imagen"),
            video = _("Video"),
            document = _("Documento"),
            audio = _("Audio")
        }
        content = content .. _("Tipo: ") .. (type_names[raindrop.type] or raindrop.type) .. "\n\n"
    end
    
    if raindrop.excerpt and raindrop.excerpt ~= "" then
        content = content .. _("Extracto:") .. "\n"
        content = content .. raindrop.excerpt .. "\n\n"
    end
    
    if raindrop.note and raindrop.note ~= "" then
        content = content .. _("Notas:") .. "\n"
        content = content .. raindrop.note .. "\n\n"
    end
    
    if raindrop.tags and #raindrop.tags > 0 then
        content = content .. _("Etiquetas: ") .. table.concat(raindrop.tags, ", ") .. "\n\n"
    end
    
    if raindrop.cache then
        if raindrop.cache.status == "ready" then
            content = content .. _("Caché: ") .. _("Disponible") .. "\n"
            if raindrop.cache.size then
                content = content .. _("Tamaño: ") .. math.floor(raindrop.cache.size/1024) .. " KB\n"
            end
        elseif raindrop.cache.status then
            local status_names = {
                ready = _("Listo"),
                retry = _("Reintentando"),
                failed = _("Falló"),
                ["invalid-origin"] = _("Origen inválido"),
                ["invalid-timeout"] = _("Tiempo agotado"),
                ["invalid-size"] = _("Tamaño inválido")
            }
            content = content .. _("Estado del caché: ") .. (status_names[raindrop.cache.status] or raindrop.cache.status) .. "\n"
        end
        content = content .. "\n"
    end
    
    local text_viewer = TextViewer:new{
        title = raindrop.title or _("Información del artículo"),
        text = content,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(text_viewer)
end

function Gota:showDebugInfo()
    local debug_info_table = self.settings:getDebugInfo()
    
    local debug_info = "DEBUG GOTA PLUGIN\n"
    debug_info = debug_info .. "══════════════════════\n\n"
    debug_info = debug_info .. "Token actual: " .. debug_info_table.token_status .. "\n"
    debug_info = debug_info .. "Archivo config: " .. debug_info_table.settings_file .. "\n\n"
    
    if debug_info_table.file_exists then
        debug_info = debug_info .. "Archivo existe: SÍ\n"
        debug_info = debug_info .. "Tamaño archivo: " .. debug_info_table.file_size .. " bytes\n"
        debug_info = debug_info .. "Contenido (primeros 200 chars):\n" .. debug_info_table.file_content .. "\n\n"
    else
        debug_info = debug_info .. "Archivo existe: NO\n\n"
    end
    
    debug_info = debug_info .. "\nServer URL: " .. (self.server_url or "NO SET")
    debug_info = debug_info .. "\nTamaño de caché: " .. (table_keys(self.response_cache) and #table_keys(self.response_cache) or 0) .. " entradas"
    debug_info = debug_info .. "\nTTL de caché: " .. self.cache_ttl .. " segundos"
    debug_info = debug_info .. "\nSistema: MODULARIZADO"
    
    local text_viewer = TextViewer:new{
        title = "Debug Info - Gota Plugin",
        text = debug_info,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(text_viewer)
end

function Gota:searchRaindrops(search_term, page)  -- ✅ CORREGIDO: Agregada la "f"
    page = page or 0
    local perpage = 25
    
    local endpoint = string.format("/raindrops/0?search=%s&perpage=%d&page=%d", 
                                   urlEncode(search_term), perpage, page)
    
    logger.dbg("Gota: Buscando con endpoint:", endpoint)
    
    self:showProgress(_("Buscando artículos..."))
    local results, err = self:cachedRequest(endpoint)
    self:hideProgress()
    
    if not results then
        self:notify(_("Error en la búsqueda: ") .. (err or _("Error desconocido")), 4)
        return
    end
    
    local menu_items = {}
    
    if results.items and #results.items > 0 then
        for _, raindrop in ipairs(results.items) do
            local title = raindrop.title or _("Sin título")
            local domain = raindrop.domain or ""
            local excerpt = ""
            if raindrop.excerpt then
                excerpt = "\n" .. raindrop.excerpt:sub(1, 50) .. "..."
            end
            
            table.insert(menu_items, {
                text = title .. "\n" .. domain .. excerpt,
                callback = function()
                    self:showRaindropContent(raindrop)
                end,
            })
        end
        
        local total_count = results.count or 0
        if total_count > perpage then
            local total_pages = math.ceil(total_count / perpage)
            local current_page = page + 1
            
            table.insert(menu_items, {text = "──────────────────", enabled = false})
            
            if page > 0 then
                table.insert(menu_items, {
                    text = _("← Página anterior"),
                    callback = function()
                        self:searchRaindrops(search_term, page - 1)
                    end,
                })
            end
            
            table.insert(menu_items, {
                text = string.format(_("Página %d de %d"), current_page, total_pages),
                enabled = false,
            })
            
            if current_page < total_pages then
                table.insert(menu_items, {
                    text = _("Página siguiente →"),
                    callback = function()
                        self:searchRaindrops(search_term, page + 1)
                    end,
                })
            end
        end
        
    else
        table.insert(menu_items, {
            text = _("No se encontraron resultados para: ") .. search_term,
            enabled = false,
        })
    end
    
    -- ✅ MEJORADO: Limpiar menú anterior si existe
    if self.search_menu then
        UIManager:close(self.search_menu)
        self.search_menu = nil
    end
    
    self.search_menu = Menu:new{  -- ✅ MEJORADO: Guardar referencia
        title = _("Resultados: '") .. search_term .. "' (" .. (results.count or 0) .. ")",
        item_table = menu_items,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(self.search_menu)
end

function Gota:showLinkInfo(raindrop)
    if not raindrop.link then
        self:notify(_("No hay enlace disponible para este artículo"))
        return
    end
    
    local content = _("URL del artículo:") .. "\n\n"
    content = content .. raindrop.link .. "\n\n"
    content = content .. _("No se puede abrir directamente en KOReader.") .. "\n"
    content = content .. _("Puedes copiar esta URL para abrirla en otro dispositivo.")
    
    -- ✅ MEJORADO: Cerrar text_viewer anterior si existe
    if self.text_viewer then
        UIManager:close(self.text_viewer)
        self.text_viewer = nil
    end
    
    self.text_viewer = TextViewer:new{  -- ✅ MEJORADO: Guardar referencia
        title = _("Enlace del artículo"),
        text = content,
        width = Device.screen:getWidth() * 0.95,
        height = Device.screen:getHeight() * 0.95,
    }
    
    UIManager:show(self.text_viewer)
end

function Gota:downloadRaindropHTML(raindrop)
    if not raindrop._id then
        self:notify(_("No se puede descargar: ID no encontrado"))
        return
    end
    
    if not raindrop.cache or raindrop.cache.status ~= "ready" then
        self:notify(_("No hay contenido en caché disponible para descargar"))
        return
    end
    
    local html_dir = DataStorage:getDataDir() .. "/gota_articles/"
    local util = require("util")
    if not util.makePath(html_dir) then
        self:notify(_("Error al crear directorio para guardar HTML"))
        return
    end
    
    local safe_title = (raindrop.title or "article"):gsub("[%c%p%s]", "_"):sub(1, 30)
    local filename = html_dir .. raindrop._id .. "_" .. safe_title .. ".html"
    
    self:showProgress(_("Descargando HTML..."))
    
    local html_content, err = self:makeRequestWithRetry("/raindrop/" .. raindrop._id .. "/cache")
    self:hideProgress()

    if not html_content or type(html_content) ~= "string" then
        self:notify(_("Error al descargar HTML: ") .. (err or "Respuesta inválida"))
        return
    end
        
    if #html_content < 100 then
        self:notify(_("El contenido descargado parece incompleto"))
        return
    end
    
    local file, file_err = io.open(filename, "wb")
    if not file then
        self:notify(_("Error al crear archivo: ") .. tostring(file_err))
        return
    end
    
    file:write(html_content)
    file:close()
    
    self:notify(string.format(_("HTML guardado en: %s"), filename), 5)
    self:showDownloadOptions(filename, raindrop.title or _("Artículo"))
end

function Gota:showDownloadOptions(filename, title)
    -- ✅ MEJORADO: Cerrar menú anterior si existe
    if self.download_menu then
        UIManager:close(self.download_menu)
        self.download_menu = nil
    end
    
    self.download_menu = Menu:new{  -- ✅ MEJORADO: Guardar referencia
        title = _("HTML descargado"),
        item_table = {
            {
                text = _("Ir a carpeta de descarga"),
                callback = function()
                    UIManager:nextTick(function()
                        self:openDownloadFolder(filename)
                    end)
                end
            },
            {
                text = _("Volver"),
                callback = function()
                    UIManager:nextTick(function()
                        UIManager:close(self.download_menu)
                        self.download_menu = nil  -- ✅ MEJORADO: Limpiar referencia
                    end)
                end
            }
        },
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(self.download_menu)
end

function Gota:openDownloadFolder(filename)
    self:closeAllWidgets()
    
    local FileManager = require("apps/filemanager/filemanager")
    local folder_path = filename:match("(.+)/[^/]+$")
    
    if FileManager.instance then
        FileManager.instance:reinit(folder_path)
    else
        FileManager:showFiles(folder_path)
    end
end

function Gota:openHTMLFile(filename)
    local ReaderUI = require("apps/reader/readerui")
    local DocumentRegistry = require("document/documentregistry")
    
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(filename, "mode") ~= "file" then
        self:notify(_("No se encontró el archivo HTML"))
        return
    end
    
    -- Función auxiliar para cerrar widgets de manera segura
    local function safeCloseWidget(widget)
        if widget and type(widget) == "table" and widget.onClose then
            -- Verificar si el widget tiene el método onClose (indicador de widget válido)
            UIManager:close(widget)
            return true
        elseif widget and type(widget) == "table" then
            -- Intentar cerrar, pero con manejo de errores
            local success, err = pcall(function()
                UIManager:close(widget)
            end)
            if not success then
                logger.dbg("Gota: No se pudo cerrar widget:", err)
            end
            return success
        end
        return false
    end
    
    -- Cerrar widgets específicos que puedan estar abiertos
    if self.progress_message then
        UIManager:close(self.progress_message)
        self.progress_message = nil
    end
    
    -- Cerrar otros widgets de manera robusta
    if self.menu then
        if safeCloseWidget(self.menu) then
            self.menu = nil
        end
    end
    
    if self.dialog then
        if safeCloseWidget(self.dialog) then
            self.dialog = nil
        end
    end
    
    if self.text_viewer then
        if safeCloseWidget(self.text_viewer) then
            self.text_viewer = nil
        end
    end
    
    if self.search_dialog then
        if safeCloseWidget(self.search_dialog) then
            self.search_dialog = nil
        end
    end
    
    -- ✅ MEJORADO: Cerrar widgets adicionales
    if self.search_menu then
        if safeCloseWidget(self.search_menu) then
            self.search_menu = nil
        end
    end
    
    if self.download_menu then
        if safeCloseWidget(self.download_menu) then
            self.download_menu = nil
        end
    end
    
    -- Then open the document
    local document = DocumentRegistry:openDocument(filename)
    if document then
        local reader = ReaderUI:new{
            document = document,
            dithered = true,
        }
        UIManager:show(reader)
    else
        self:notify(_("No se pudo abrir el archivo HTML"))
    end
end

function Gota:closeAllWidgets()
    local widgets = {
        {ref = "progress_message", widget = self.progress_message},
        {ref = "token_dialog", widget = self.token_dialog},
        {ref = "collections_menu", widget = self.collections_menu},
        {ref = "raindrops_menu", widget = self.raindrops_menu},
        {ref = "article_menu", widget = self.article_menu},
        {ref = "search_dialog", widget = self.search_dialog},
        {ref = "search_menu", widget = self.search_menu},
        {ref = "download_menu", widget = self.download_menu},
        {ref = "text_viewer", widget = self.text_viewer},
        -- Generic fallbacks, less used now but safe to keep
        {ref = "menu", widget = self.menu},
        {ref = "dialog", widget = self.dialog}
    }
    
    for _, w in ipairs(widgets) do
        if w.widget then
            local success, err = pcall(function()
                UIManager:close(w.widget)
            end)
            if success then
                self[w.ref] = nil
                logger.dbg("Gota: Widget cerrado exitosamente:", w.ref)
            else
                logger.dbg("Gota: Error cerrando widget", w.ref, ":", err)
                -- Force cleanup of reference even if close fails
                self[w.ref] = nil
            end
        end
    end
    logger.dbg("Gota: Todas las ventanas cerradas")
end

function Gota:showRaindropCachedContent(raindrop)
    if not raindrop.cache or not raindrop.cache.text then
        self:notify(_("No hay contenido en caché disponible"))
        return
    end
    
    local buttons_table = {
        {
            {
                text = _("Cerrar"),
                callback = function()
                    UIManager:close(text_viewer)
                end,
            },
            {
                text = _("📖 Abrir en lector"),  -- NUEVO BOTÓN
                callback = function()
                    UIManager:close(text_viewer)
                    self:openInReader(raindrop)
                end,
            },
        },
        {
            {
                text = _("Compartir enlace"),
                callback = function()
                    UIManager:close(text_viewer)
                    self:showLinkInfo(raindrop)
                end,
            },
            {
                text = _("Guardar HTML"),
                callback = function()
                    UIManager:close(text_viewer)
                    self:downloadRaindropHTML(raindrop)
                end,
            },
        },
    }
    
    local content = raindrop.cache.text
    local original_length = #content
    logger.dbg("Gota: Procesando contenido HTML, longitud original:", original_length)
    
    -- First remove only the most obvious non-content elements
    content = content:gsub("<nav[^>]*>.-</nav>", "")
    content = content:gsub("<header[^>]*>.-</header>", "")
    content = content:gsub("<footer[^>]*>.-</footer>", "")
    
    -- More conservative removal of non-content patterns
    local non_content_patterns = {
        -- Only exact navigation matches
        "<div[^>]*class=['\"]nav['\"].->.-(</div>)",
        "<div[^>]*class=['\"]navbar['\"].->.-(</div>)",
        "<div[^>]*class=['\"]navigation['\"].->.-(</div>)",
        "<div[^>]*id=['\"]nav['\"].->.-(</div>)",
        "<div[^>]*id=['\"]navbar['\"].->.-(</div>)",
        "<div[^>]*id=['\"]navigation['\"].->.-(</div>)",
        
        -- Common advertisement elements
        "<div[^>]*class=['\"]ad['\"].->.-(</div>)",
        "<div[^>]*class=['\"]ads['\"].->.-(</div>)",
        "<div[^>]*class=['\"]advertisement['\"].->.-(</div>)",
        "<div[^>]*id=['\"]ad['\"].->.-(</div>)",
        "<div[^>]*id=['\"]ads['\"].->.-(</div>)",
    }
    
    -- Apply non-content pattern removals more carefully
    for _, pattern in ipairs(non_content_patterns) do
        local success, result = pcall(function() 
            return content:gsub(pattern, "") 
        end)
        if success then
            content = result
        end
    end
    
    -- Try to identify main content with high confidence
    local main_content = nil
    local main_content_length = 0
    
    -- Look for article tag first (most reliable)
    local article_match = content:match("<article[^>]*>(.-)</article>")
    if article_match and #article_match > original_length * 0.4 then  -- Must be substantial
        main_content = article_match
        main_content_length = #main_content
        logger.dbg("Gota: Encontrada etiqueta <article> con contenido significativo")
    end
    
    -- If no article tag, try main tag
    if not main_content then
        local main_match = content:match("<main[^>]*>(.-)</main>")
        if main_match and #main_match > original_length * 0.4 then
            main_content = main_match
            main_content_length = #main_content
            logger.dbg("Gota: Encontrada etiqueta <main> con contenido significativo")
        end
    end
    
    -- Only use extracted content if we're confident it has most of the article
    if main_content and main_content_length > 1000 and main_content_length > original_length * 0.4 then
        logger.dbg("Gota: Usando contenido principal extraído, longitud:", main_content_length)
        content = main_content
    else
        logger.dbg("Gota: No se identificó un área de contenido principal clara, usando contenido completo limpio")
    end
    
    -- Continue with HTML-to-text conversion
    content = content:gsub("\n%s*\n%s*\n", "\n\n")
    content = content:gsub("<br[^>]*>", "\n")
    content = content:gsub("<p[^>]*>", "\n")
    content = content:gsub("</p>", "\n")
    content = content:gsub("<h%d[^>]*>", "\n\n")
    content = content:gsub("</h%d>", "\n")
    content = content:gsub("<div[^>]*>", "\n")
    content = content:gsub("</div>", "\n")
    content = content:gsub("<[^>]+>", "")
    content = content:gsub("&nbsp;", " ")
    content = content:gsub("&lt;", "<")
    content = content:gsub("&gt;", ">")
    content = content:gsub("&quot;", "\"")
    content = content:gsub("&apos;", "'")
    content = content:gsub("&amp;", "&")
    content = content:gsub("\n\n+", "\n\n")
    
    -- Remove excessive whitespace
    content = content:gsub("^%s+", "")
    content = content:gsub("%s+$", "")
    
    -- Safety check - if we lost too much content, use a simpler conversion of the original
    if #content < original_length * 0.3 then
        logger.dbg("Gota: La limpieza eliminó demasiado contenido, usando conversión más simple")
        content = raindrop.cache.text
        content = content:gsub("<script[^>]*>.-</script>", "")
        content = content:gsub("<style[^>]*>.-</style>", "")
        content = content:gsub("<br[^>]*>", "\n")
        content = content:gsub("<p[^>]*>", "\n")
        content = content:gsub("</p>", "\n")
        content = content:gsub("<div[^>]*>", "\n")
        content = content:gsub("</div>", "\n")
        content = content:gsub("<[^>]+>", "")
        content = content:gsub("&nbsp;", " ")
        content = content:gsub("&lt;", "<")
        content = content:gsub("&gt;", ">")
        content = content:gsub("&quot;", "\"")
        content = content:gsub("&apos;", "'")
        content = content:gsub("&amp;", "&")
        content = content:gsub("\n\n+", "\n\n")
        content = content:gsub("^%s+", "")
        content = content:gsub("%s+$", "")
    end
    
    logger.dbg("Gota: Contenido final procesado, longitud:", #content, 
               "Proporción retenida:", math.floor(#content/original_length*100), "%")
    
    -- Create more compact header with fewer newlines
    local formatted_content = (raindrop.title or _("Sin título")) .. "\n"
    formatted_content = formatted_content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if raindrop.domain then
        formatted_content = formatted_content .. _("Fuente: ") .. raindrop.domain .. "\n"
    end
    
    -- Remove any leading whitespace from the content before appending
    content = content:gsub("^%s+", "")
    formatted_content = formatted_content .. content
    
    local text_viewer = TextViewer:new{
        title = _("Contenido en caché") .. " [↓]",
        text = formatted_content,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
        buttons = buttons_table,
    }
    
    -- Add a tap handler for the title region to download HTML
    text_viewer.onTapHeader = function()
        self:downloadRaindropHTML(raindrop)
    end
    
    UIManager:show(text_viewer)
end

function Gota:testToken(test_token)
    logger.dbg("Gota: Iniciando test de token, longitud:", #test_token)
    
    if not test_token or test_token == "" then
        self:notify(_("⚠️ Token vacío, no se puede probar"), 3)
        return
    end
    
    if #test_token < 10 then
        self:notify(_("⚠️ Token parece muy corto, pero se probará de todos modos"), 2)
    end
    
    local old_token = self.settings:getToken()
    self.settings:setToken(test_token)
    
    self:showProgress(_("Probando token..."))
    
    local user_data, err = self:makeRequestWithRetry("/user")
    
    self:hideProgress()
    self.settings:setToken(old_token)
    
    if user_data and user_data.user then
        logger.dbg("Gota: Test de token exitoso")
        local user_name = user_data.user.fullName or user_data.user.email or "Usuario verificado"
        local pro_status = user_data.user.pro and _(" (PRO)") or ""
        
        self:notify(_("✓ Token válido!\nUsuario: ") .. user_name .. pro_status, 4)
    else
        logger.err("Gota: Test de token falló:", err)
        self:notify(_("✗ Error con el token:\n") .. (err or "Token inválido"), 5)
    end
end

function Gota:showSearchDialog()
    self.search_dialog = InputDialog:new{
        title = _("Buscar artículos"),
        input = "",
        buttons = {
            {
                {
                    text = _("Cancelar"),
                    callback = function()
                        UIManager:close(self.search_dialog)
                    end,
                },
                {
                    text = _("Buscar"),
                    is_enter_default = true,
                    callback = function()
                        local search_term = self.search_dialog:getInputText()
                        if search_term and search_term ~= "" then
                            UIManager:close(self.search_dialog)
                            NetworkMgr:runWhenOnline(function()
                                self:searchRaindrops(search_term)
                            end)
                        else
                            self:notify(_("Por favor ingresa un término de búsqueda"))
                        end
                    end,
                }
            }
        },
    }
    UIManager:show(self.search_dialog)
    self.search_dialog:onShowKeyboard()
end

-- Función principal para abrir en ReaderUI
function Gota:openInReader(raindrop)
    if not raindrop or not raindrop.cache or not raindrop.cache.text then
        self:notify(_("No hay contenido disponible"))
        return
    end
    
    -- Crear directorio temporal
    local temp_dir = DataStorage:getDataDir() .. "/cache/gota/"
    local lfs = require("libs/libkoreader-lfs")
    if not lfs.attributes(temp_dir, "mode") then
        util.makePath(temp_dir)
    end
    
    -- Crear archivo HTML
    local filename = temp_dir .. raindrop._id .. "_" .. os.time() .. ".html"
    local html = self:createReaderHTML(raindrop)
    
    local file = io.open(filename, "w")
    if file then
        file:write(html)
        file:close()
        
        -- Cerrar menús
        if self.article_menu then UIManager:close(self.article_menu) end
        if self.raindrops_menu then UIManager:close(self.raindrops_menu) end
        
        -- Abrir en lector
        local ReaderUI = require("apps/reader/readerui")
        local DocumentRegistry = require("document/documentregistry")
        
        -- Then open the document
        local document = DocumentRegistry:openDocument(filename)
        if document then
            local reader = ReaderUI:new{
                document = document,
                dithered = true,
                delete_on_close = true,  -- Para borrar el archivo temporal cuando se cierra
            }
            UIManager:show(reader)
        else
            self:notify(_("No se pudo abrir el archivo HTML"))
        end
    else
        self:notify(_("Error al crear archivo temporal"))
    end
end

-- Crear HTML para el lector
function Gota:createReaderHTML(raindrop)
    local content = raindrop.cache.text or ""
    
    -- Extraer body si existe
    local body = content:match("<body[^>]*>(.-)</body>") or content
    
    return string.format([[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>%s</title>
    <style>
        body { 
            font-family: Georgia, serif; 
            line-height: 1.6; 
            margin: 20px;
            max-width: 45em;
            margin: 0 auto;
            padding: 20px;
        }
        h1 { font-size: 1.8em; margin-bottom: 0.5em; }
        .meta { 
            color: #666; 
            font-size: 0.9em; 
            margin-bottom: 2em; 
            padding-bottom: 1em;
            border-bottom: 1px solid #ddd;
        }
        img { max-width: 100%%; height: auto; }
        blockquote { 
            margin: 1em 0; 
            padding-left: 1em; 
            border-left: 3px solid #ccc; 
        }
        pre { 
            background: #f4f4f4; 
            padding: 1em; 
            overflow-x: auto; 
        }
    </style>
</head>
<body>
    <h1>%s</h1>
    <div class="meta">
        <div>%s</div>
        <div>%s</div>
    </div>
    %s
</body>
</html>
]], 
    util.htmlEscape(raindrop.title or ""),
    util.htmlEscape(raindrop.title or ""),
    util.htmlEscape(raindrop.domain or ""),
    raindrop.created and raindrop.created:sub(1,10) or "",
    body)
end

return Gota