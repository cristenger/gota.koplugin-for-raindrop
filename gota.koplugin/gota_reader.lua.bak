-- gota_reader.lua
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local DocumentRegistry = require("document/documentregistry")
local logger = require("logger")
local _ = require("gettext")

-- Singleton para manejar el ciclo de vida del lector
local GotaReader = {
    on_return_callback = nil,
    is_showing = false,
    original_raindrop = nil,
}

function GotaReader:show(options)
    self.on_return_callback = options.on_return_callback
    self.original_raindrop = options.raindrop
    logger.dbg("GotaReader: Mostrando documento:", options.path)
    
    -- Verificar que el archivo existe
    local lfs = require("libs/libkoreader-lfs")
    local file_mode = lfs.attributes(options.path, "mode")
    if not file_mode or file_mode ~= "file" then
        logger.err("GotaReader: El archivo no existe o no es válido:", options.path)
        UIManager:show(require("ui/widget/infomessage"):new{
            text = _("Error: No se pudo encontrar el archivo HTML"),
            timeout = 3,
        })
        return
    end
    
    -- Verificar que DocumentRegistry puede manejar HTML
    local provider = DocumentRegistry:getProvider(options.path)
    if not provider then
        logger.err("GotaReader: No hay proveedor para archivos HTML")
        -- Intentar forzar el uso de CREngine para HTML
        provider = DocumentRegistry:getProvider("dummy.epub") -- CREngine maneja HTML
    end
    
    logger.dbg("GotaReader: Provider para el documento:", provider and provider.provider_name or "ninguno")

    -- Si ya hay una instancia del reader, cambiar documento
    if self.is_showing and ReaderUI.instance then
        ReaderUI.instance:switchDocument(options.path, { delete_on_close = true })
    else
        -- Broadcast del evento antes de abrir el reader
        local Event = require("ui/event")
        UIManager:broadcastEvent(Event:new("SetupShowReader"))
        
        -- Usar el enfoque documentado de FileManager para abrir archivos
        UIManager:nextTick(function()
            local FileManager = require("apps/filemanager/filemanager")
            
            -- Si hay una instancia de FileManager, cerrarla primero
            if FileManager.instance then
                FileManager.instance:onClose()
            end
            
            -- Abrir el documento usando el método apropiado
            local document = DocumentRegistry:openDocument(options.path, provider)
            if document then
                ReaderUI:showReader(options.path, { delete_on_close = true })
                self.is_showing = true
                
                -- Esperar a que el reader esté listo y añadir nuestro menú
                UIManager:scheduleIn(0.5, function()
                    if ReaderUI.instance and ReaderUI.instance.menu then
                        self:addGotaMenu(ReaderUI.instance)
                    end
                end)
            else
                logger.err("GotaReader: No se pudo abrir el documento")
                UIManager:show(require("ui/widget/infomessage"):new{
                    text = _("Error: No se pudo abrir el archivo HTML"),
                    timeout = 3,
                })
            end
        end)
    end
end

-- Añadir menú de Gota al reader
function GotaReader:addGotaMenu(reader_instance)
    if not reader_instance or not reader_instance.menu then
        logger.warn("GotaReader: No se pudo acceder al menú del reader")
        return
    end
    
    -- Añadir entrada al menú principal del reader
    local menu_items = reader_instance.menu.menu_table
    
    -- Buscar la sección de herramientas o crear una nueva entrada
    local gota_menu = {
        text = _("Gota"),
        sub_item_table = {
            {
                text = _("< Volver a Gota"),
                callback = function()
                    self:onReturn()
                end,
            },
        }
    }
    
    -- Si tenemos información del artículo original, añadir más opciones
    if self.original_raindrop then
        if self.original_raindrop.link then
            table.insert(gota_menu.sub_item_table, {
                text = _("Copiar URL del artículo"),
                callback = function()
                    -- Aquí podrías implementar la copia al portapapeles
                    -- o mostrar la URL en un diálogo
                    UIManager:show(require("ui/widget/infomessage"):new{
                        text = self.original_raindrop.link,
                        timeout = 5,
                    })
                end,
            })
        end
    end
    
    -- Insertar en el menú
    table.insert(menu_items, gota_menu)
    reader_instance.menu:updateItems()
    
    logger.dbg("GotaReader: Menú de Gota añadido al reader")
end

-- Manejar el retorno desde el reader a Gota
function GotaReader:onReturn()
    logger.dbg("GotaReader: Cerrando reader y volviendo a Gota")
    self:closeReader(self.on_return_callback)
end

function GotaReader:closeReader(done_callback)
    UIManager:nextTick(function()
        if ReaderUI.instance then
            ReaderUI.instance:onClose()
        end
        
        -- Resetear estado
        self.is_showing = false
        self.original_raindrop = nil
        
        -- Ejecutar callback si existe
        if done_callback then
            UIManager:scheduleIn(0.1, done_callback)
        end
    end)
end

function GotaReader:onReaderUIClose()
    self.is_showing = false
    self.original_raindrop = nil
end

return GotaReader