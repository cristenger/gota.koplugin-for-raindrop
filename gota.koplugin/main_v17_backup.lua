--[[
    Gota: Lector para Raindrop.io en KOReader
    Permite leer artículos guardados en Raindrop.io directamente en tu dispositivo.
    
    Versión: 1.7 (Refactorizado y modularizado)
    
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
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

-- MÓDULOS DEL PLUGIN
local Settings = require("settings")
local API = require("api")
local ContentProcessor = require("content_processor")
local GotaReader = require("gota_reader")

local Gota = WidgetContainer:extend{
    name = "gota",
    is_doc_only = false,
}

function Gota:notify(text, timeout)
    timeout = timeout or 3
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout,
    })
end

function Gota:init()
    -- Inicializar módulos
    self.settings = Settings:new()
    self.settings:load()
    
    self.api = API:new(self.settings)
    self.content_processor = ContentProcessor:new()
    
    -- Referencias para widgets
    self.widgets = {}
    
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

-- ========== GESTIÓN DE UI ==========

function Gota:showProgress(text)
    if self.widgets.progress then
        UIManager:close(self.widgets.progress)
    end
    self.widgets.progress = InfoMessage:new{text = text, timeout = 1}
    UIManager:show(self.widgets.progress)
    UIManager:forceRePaint()
end

function Gota:hideProgress()
    if self.widgets.progress then 
        UIManager:close(self.widgets.progress) 
        self.widgets.progress = nil
    end
end

function Gota:closeWidget(name)
    if self.widgets[name] then
        local success, err = pcall(function()
            UIManager:close(self.widgets[name])
        end)
        if success then
            self.widgets[name] = nil
            logger.dbg("Gota: Widget cerrado exitosamente:", name)
        else
            logger.dbg("Gota: Error cerrando widget", name, ":", err)
            self.widgets[name] = nil
        end
    end
end

function Gota:closeAllWidgets()
    local widget_names = {"progress", "token_dialog", "collections_menu", "raindrops_menu", 
                          "article_menu", "search_dialog", "search_menu", "download_menu", 
                          "text_viewer"}
    
    for _, name in ipairs(widget_names) do
        self:closeWidget(name)
    end
    logger.dbg("Gota: Todas las ventanas cerradas")
end

-- ========== DIÁLOGOS ==========

function Gota:showTokenDialog()
    self.widgets.token_dialog = InputDialog:new{
        title = _("Token de acceso de Raindrop.io"),
        description = _("OPCIÓN 1 - Test Token (Recomendado):\n• Ve a: https://app.raindrop.io/settings/integrations\n• Crea una nueva aplicación\n• Copia el 'Test token'\n\nOPCIÓN 2 - Token Personal:\n• Usa un token de acceso personal\n\nPega el token aquí:"),
        input = self.settings:getToken(),
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancelar"),
                    callback = function()
                        self:closeWidget("token_dialog")
                    end,
                },
                {
                    text = _("Probar"),
                    callback = function()
                        local test_token = self.widgets.token_dialog:getInputText()
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
                        local new_token = self.widgets.token_dialog:getInputText()
                        if new_token and new_token ~= "" then
                            new_token = new_token:gsub("^%s+", ""):gsub("%s+$", "")
                            
                            if new_token == "" then
                                self:notify(_("Por favor ingresa un token válido"), 2)
                                return
                            end
                            
                            if #new_token < 10 then
                                self:notify(_("Aviso: Token parece muy corto, pero se guardará de todos modos"), 3)
                            end
                            
                            self.settings:setToken(new_token)
                            local success, err = self.settings:save()
                            self:closeWidget("token_dialog")
                            
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
    UIManager:show(self.widgets.token_dialog)
    self.widgets.token_dialog:onShowKeyboard()
end

function Gota:showSearchDialog()
    self.widgets.search_dialog = InputDialog:new{
        title = _("Buscar artículos"),
        input = "",
        buttons = {
            {
                {
                    text = _("Cancelar"),
                    callback = function()
                        self:closeWidget("search_dialog")
                    end,
                },
                {
                    text = _("Buscar"),
                    is_enter_default = true,
                    callback = function()
                        local search_term = self.widgets.search_dialog:getInputText()
                        if search_term and search_term ~= "" then
                            self:closeWidget("search_dialog")
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
    UIManager:show(self.widgets.search_dialog)
    self.widgets.search_dialog:onShowKeyboard()
end

function Gota:showDebugInfo()
    local debug_info_table = self.settings:getDebugInfo()
    
    local debug_info = "DEBUG GOTA PLUGIN v1.7\n"
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
    
    debug_info = debug_info .. "\nServer URL: " .. self.api.server_url
    debug_info = debug_info .. "\nSistema: REFACTORIZADO v1.7"
    debug_info = debug_info .. "\nMódulos: API, Settings, ContentProcessor, GotaReader"
    
    local text_viewer = TextViewer:new{
        title = "Debug Info - Gota Plugin",
        text = debug_info,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(text_viewer)
end

-- ========== COLECCIONES Y RAINDROPS ==========

function Gota:showCollections()
    self:showProgress(_("Cargando colecciones..."))
    local collections, err = self.api:getCollections()
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
    
    self:closeWidget("collections_menu")
    
    self.widgets.collections_menu = Menu:new{
        title = _("Colecciones de Raindrop"),
        item_table = menu_items,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(self.widgets.collections_menu)
end

function Gota:showRaindrops(collection_id, collection_name, page)
    page = page or 0
    local perpage = 25
    
    self:showProgress(_("Cargando artículos..."))
    local raindrops, err = self.api:getRaindrops(collection_id, page, perpage)
    self:hideProgress()
    
    if not raindrops then
        self:notify(_("Error al obtener artículos: ") .. (err or _("Error desconocido")), 4)
        return
    end
    
    local menu_items = self:buildRaindropsMenu(raindrops, collection_id, collection_name, page, perpage)
    local total_count = raindrops.count or 0
    
    self:closeWidget("raindrops_menu")
    
    self.widgets.raindrops_menu = Menu:new{
        title = string.format("%s (%d)", collection_name or _("Artículos"), total_count),
        item_table = menu_items,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(self.widgets.raindrops_menu)
end

function Gota:buildRaindropsMenu(raindrops, collection_id, collection_name, page, perpage)
    local menu_items = {}
    
    if raindrops.items and #raindrops.items > 0 then
        local translation_func = _
        for _, raindrop in ipairs(raindrops.items) do
            local title = raindrop.title or translation_func("Sin título")
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
        
        -- Añadir paginación
        self:addPagination(menu_items, raindrops, page, perpage, function(new_page)
            self:showRaindrops(collection_id, collection_name, new_page)
        end)
    else
        table.insert(menu_items, {
            text = _("No hay artículos en esta colección"),
            enabled = false,
        })
    end
    
    return menu_items
end

function Gota:addPagination(menu_items, data, page, perpage, callback)
    local total_count = data.count or 0
    if total_count <= perpage then
        return
    end
    
    local total_pages = math.ceil(total_count / perpage)
    local current_page = page + 1
    
    table.insert(menu_items, {text = "──────────────────", enabled = false})
    
    -- Primera página
    if current_page > 3 then
        table.insert(menu_items, {
            text = _("« Primera página"),
            callback = function() callback(0) end,
        })
    end
    
    -- Página anterior
    if page > 0 then
        table.insert(menu_items, {
            text = _("← Página anterior"),
            callback = function() callback(page - 1) end,
        })
    end
    
    -- Página siguiente
    if current_page < total_pages then
        table.insert(menu_items, {
            text = _("Página siguiente →"),
            callback = function() callback(page + 1) end,
        })
    end
    
    -- Última página
    if current_page < total_pages - 2 then
        table.insert(menu_items, {
            text = _("» Última página"),
            callback = function() callback(total_pages - 1) end,
        })
    end
    
    -- Información
    local translation_func = _
    table.insert(menu_items, {
        text = string.format(translation_func("Mostrando %d-%d de %d artículos"), 
            page * perpage + 1,
            math.min((page + 1) * perpage, total_count),
            total_count),
        enabled = false,
    })
end

-- ========== CONTENIDO DE ARTÍCULOS ==========

function Gota:showRaindropContent(raindrop)
    -- Cargar datos completos si es necesario
    if not raindrop.cache then
        self:showProgress(_("Cargando contenido completo..."))
        local full_raindrop, err = self.api:getRaindrop(raindrop._id)
        self:hideProgress()
        
        if full_raindrop and full_raindrop.item then
            raindrop = full_raindrop.item
        end
    end
    
    -- Verificar disponibilidad de caché
    local has_cache = raindrop.cache and 
                     raindrop.cache.status == "ready" and 
                     (raindrop.cache.text or (raindrop.cache.size and raindrop.cache.size > 0))
    
    -- Cargar contenido del caché si es necesario
    if has_cache and not raindrop.cache.text then
        self:showProgress(_("Cargando contenido en caché..."))
        local cache_content, err = self.api:getRaindropCache(raindrop._id)
        self:hideProgress()
        
        if cache_content and type(cache_content) == "string" and #cache_content > 0 then
            raindrop.cache.text = cache_content
        elseif not raindrop.cache.text then
            raindrop.cache.text = _("Contenido disponible para descarga. Usa el botón 'Descargar HTML'.")
        end
    end
    
    if has_cache and (not raindrop.cache.text or #raindrop.cache.text < 50) then
        has_cache = false
    end
    
    -- Construir menú de opciones
    local view_options = self:buildArticleMenu(raindrop, has_cache)
    
    self:closeWidget("article_menu")
    
    self.widgets.article_menu = Menu:new{
        title = raindrop.title or _("Artículo"),
        item_table = view_options,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(self.widgets.article_menu)
end

function Gota:buildArticleMenu(raindrop, has_cache)
    local view_options = {
        {
            text = _("Abrir en lector completo"),
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
            text = _("Ver contenido en texto simple"),
            enabled = has_cache,
            callback = function()
                if has_cache then
                    self:showRaindropCachedContent(raindrop)
                else
                    self:notify(_("El contenido no está disponible aún"))
                end
            end
        },
        {
            text = _("Descargar HTML"),
            enabled = has_cache,
            callback = function()
                if has_cache then
                    self:downloadRaindropHTML(raindrop)
                else
                    self:notify(_("No hay contenido en caché disponible para descargar"))
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
    
    -- Mensaje de estado del caché
    if not has_cache and raindrop.cache then
        local status_names = {
            retry = _("La caché está siendo generada, intenta más tarde"),
            failed = _("La generación de caché ha fallado"),
            ["invalid-origin"] = _("No se pudo generar caché por origen inválido"),
            ["invalid-timeout"] = _("No se pudo generar caché por timeout"),
            ["invalid-size"] = _("No se pudo generar caché por tamaño excesivo")
        }
        local cache_message = status_names[raindrop.cache.status] or _("La caché no está disponible")
        
        table.insert(view_options, 1, {
            text = cache_message,
            enabled = false,
        })
        
        table.insert(view_options, {
            text = _("Intentar recargar artículo completo"),
            callback = function()
                self:reloadRaindrop(raindrop._id)
            end
        })
    elseif not has_cache then
        table.insert(view_options, 1, {
            text = _("Este artículo no tiene contenido en caché disponible"),
            enabled = false,
        })
    end
    
    return view_options
end

function Gota:reloadRaindrop(raindrop_id)
    self:showProgress(_("Recargando artículo..."))
    local full_raindrop, err = self.api:getRaindrop(raindrop_id)
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
    local content = self.content_processor:formatArticleInfo(raindrop)
    
    local text_viewer = TextViewer:new{
        title = raindrop.title or _("Información del artículo"),
        text = content,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(text_viewer)
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
                text = _("Abrir en lector"),
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
    
    local formatted_content = self.content_processor:formatArticleText(raindrop)
    
    local text_viewer = TextViewer:new{
        title = _("Contenido en caché"),
        text = formatted_content,
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
        buttons = buttons_table,
    }
    
    UIManager:show(text_viewer)
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
    
    self:closeWidget("text_viewer")
    
    self.widgets.text_viewer = TextViewer:new{
        title = _("Enlace del artículo"),
        text = content,
        width = Device.screen:getWidth() * 0.95,
        height = Device.screen:getHeight() * 0.95,
    }
    
    UIManager:show(self.widgets.text_viewer)
end

-- ========== BÚSQUEDA ==========

function Gota:searchRaindrops(search_term, page)
    page = page or 0
    local perpage = 25
    
    self:showProgress(_("Buscando artículos..."))
    local results, err = self.api:searchRaindrops(search_term, page, perpage)
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
        
        -- Añadir paginación simple
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
    
    self:closeWidget("search_menu")
    
    self.widgets.search_menu = Menu:new{
        title = _("Resultados: '") .. search_term .. "' (" .. (results.count or 0) .. ")",
        item_table = menu_items,
        width = Device.screen:getWidth() * 0.9,
        height = Device.screen:getHeight() * 0.8,
    }
    
    UIManager:show(self.widgets.search_menu)
end

-- ========== DESCARGA Y LECTURA ==========

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
    if not util.makePath(html_dir) then
        self:notify(_("Error al crear directorio para guardar HTML"))
        return
    end
    
    local safe_title = (raindrop.title or "article"):gsub("[%c%p%s]", "_"):sub(1, 30)
    local filename = html_dir .. raindrop._id .. "_" .. safe_title .. ".html"
    
    self:showProgress(_("Descargando HTML..."))
    
    local html_content, err = self.api:getRaindropCache(raindrop._id)
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
    self:closeWidget("download_menu")
    
    self.widgets.download_menu = Menu:new{
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
                        self:closeWidget("download_menu")
                    end)
                end
            }
        },
        width = Device.screen:getWidth(),
        height = Device.screen:getHeight(),
    }
    
    UIManager:show(self.widgets.download_menu)
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

function Gota:openInReader(raindrop)
    self:closeAllWidgets()
    
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
    local html = self.content_processor:createReaderHTML(raindrop)
    
    local file = io.open(filename, "w")
    if file then
        file:write(html)
        file:close()
        
        -- Usar GotaReader para abrir
        GotaReader:show({
            path = filename,
            raindrop = raindrop,
            on_return_callback = function()
                logger.dbg("Gota: Usuario volvió del lector")
                UIManager:scheduleIn(0.2, function()
                    self:showRaindropContent(raindrop)
                end)
            end,
        })
    else
        self:notify(_("Error al crear archivo temporal"))
    end
end

-- ========== PRUEBA DE TOKEN ==========

function Gota:testToken(test_token)
    logger.dbg("Gota: Iniciando test de token, longitud:", #test_token)
    
    if not test_token or test_token == "" then
        self:notify(_("Aviso: Token vacío, no se puede probar"), 3)
        return
    end
    
    if #test_token < 10 then
        self:notify(_("Aviso: Token parece muy corto, pero se probará de todos modos"), 2)
    end
    
    self:showProgress(_("Probando token..."))
    
    local user_data, err = self.api:testToken(test_token)
    
    self:hideProgress()
    
    if user_data and user_data.user then
        logger.dbg("Gota: Test de token exitoso")
        local user_name = user_data.user.fullName or user_data.user.email or "Usuario verificado"
        local pro_status = user_data.user.pro and _(" (PRO)") or ""
        
        self:notify(_("Token válido!\nUsuario: ") .. user_name .. pro_status, 4)
    else
        logger.err("Gota: Test de token falló:", err)
        self:notify(_("Error con el token:\n") .. (err or "Token inválido"), 5)
    end
end

return Gota
