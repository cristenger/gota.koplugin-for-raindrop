--[[
    Content Processor Module for Gota Plugin
    Handles HTML processing, cleaning, and conversion
]]

local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local ContentProcessor = {}

function ContentProcessor:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Limpia y convierte HTML a texto plano mejorado
function ContentProcessor:htmlToText(html_content)
    local content = html_content
    local original_length = #content
    logger.dbg("Gota ContentProcessor: Procesando contenido HTML, longitud original:", original_length)
    
    -- Remover elementos no deseados
    content = content:gsub("<nav[^>]*>.-</nav>", "")
    content = content:gsub("<header[^>]*>.-</header>", "")
    content = content:gsub("<footer[^>]*>.-</footer>", "")
    
    -- Remover patrones de navegación y publicidad
    local non_content_patterns = {
        "<div[^>]*class=['\"]nav['\"].->.-(</div>)",
        "<div[^>]*class=['\"]navbar['\"].->.-(</div>)",
        "<div[^>]*class=['\"]navigation['\"].->.-(</div>)",
        "<div[^>]*id=['\"]nav['\"].->.-(</div>)",
        "<div[^>]*id=['\"]navbar['\"].->.-(</div>)",
        "<div[^>]*id=['\"]navigation['\"].->.-(</div>)",
        "<div[^>]*class=['\"]ad['\"].->.-(</div>)",
        "<div[^>]*class=['\"]ads['\"].->.-(</div>)",
        "<div[^>]*class=['\"]advertisement['\"].->.-(</div>)",
        "<div[^>]*id=['\"]ad['\"].->.-(</div>)",
        "<div[^>]*id=['\"]ads['\"].->.-(</div>)",
    }
    
    for _, pattern in ipairs(non_content_patterns) do
        local success, result = pcall(function() 
            return content:gsub(pattern, "") 
        end)
        if success then
            content = result
        end
    end
    
    -- Intentar identificar el contenido principal
    local main_content = self:extractMainContent(content, original_length)
    if main_content then
        content = main_content
    end
    
    -- Convertir HTML a texto
    content = self:convertHtmlTags(content)
    
    -- Limpiar entidades HTML
    content = self:decodeHtmlEntities(content)
    
    -- Limpiar espacios en blanco excesivos
    content = content:gsub("\n\n+", "\n\n")
    content = content:gsub("^%s+", "")
    content = content:gsub("%s+$", "")
    
    -- Verificación de seguridad
    if #content < original_length * 0.3 then
        logger.dbg("Gota ContentProcessor: La limpieza eliminó demasiado contenido, usando conversión más simple")
        return self:simpleHtmlToText(html_content)
    end
    
    logger.dbg("Gota ContentProcessor: Contenido final procesado, longitud:", #content, 
               "Proporción retenida:", math.floor(#content/original_length*100), "%")
    
    return content
end

-- Extrae el contenido principal del HTML
function ContentProcessor:extractMainContent(content, original_length)
    -- Buscar etiqueta article
    local article_match = content:match("<article[^>]*>(.-)</article>")
    if article_match and #article_match > original_length * 0.4 then
        logger.dbg("Gota ContentProcessor: Encontrada etiqueta <article> con contenido significativo")
        return article_match
    end
    
    -- Buscar etiqueta main
    local main_match = content:match("<main[^>]*>(.-)</main>")
    if main_match and #main_match > original_length * 0.4 then
        logger.dbg("Gota ContentProcessor: Encontrada etiqueta <main> con contenido significativo")
        return main_match
    end
    
    return nil
end

-- Convierte etiquetas HTML a formato de texto
function ContentProcessor:convertHtmlTags(content)
    content = content:gsub("\n%s*\n%s*\n", "\n\n")
    content = content:gsub("<br[^>]*>", "\n")
    content = content:gsub("<p[^>]*>", "\n")
    content = content:gsub("</p>", "\n")
    content = content:gsub("<h%d[^>]*>", "\n\n")
    content = content:gsub("</h%d>", "\n")
    content = content:gsub("<div[^>]*>", "\n")
    content = content:gsub("</div>", "\n")
    content = content:gsub("<[^>]+>", "")
    return content
end

-- Decodifica entidades HTML
function ContentProcessor:decodeHtmlEntities(content)
    content = content:gsub("&nbsp;", " ")
    content = content:gsub("&lt;", "<")
    content = content:gsub("&gt;", ">")
    content = content:gsub("&quot;", "\"")
    content = content:gsub("&apos;", "'")
    content = content:gsub("&amp;", "&")
    return content
end

-- Conversión simple de HTML a texto (fallback)
function ContentProcessor:simpleHtmlToText(html_content)
    local content = html_content
    content = content:gsub("<script[^>]*>.-</script>", "")
    content = content:gsub("<style[^>]*>.-</style>", "")
    content = content:gsub("<br[^>]*>", "\n")
    content = content:gsub("<p[^>]*>", "\n")
    content = content:gsub("</p>", "\n")
    content = content:gsub("<div[^>]*>", "\n")
    content = content:gsub("</div>", "\n")
    content = content:gsub("<[^>]+>", "")
    content = self:decodeHtmlEntities(content)
    content = content:gsub("\n\n+", "\n\n")
    content = content:gsub("^%s+", "")
    content = content:gsub("%s+$", "")
    return content
end

-- Formatea el contenido con metadatos del artículo
function ContentProcessor:formatArticleText(raindrop)
    local formatted_content = (raindrop.title or _("Untitled")) .. "\n"
    formatted_content = formatted_content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if raindrop.domain then
        formatted_content = formatted_content .. _("Source: ") .. raindrop.domain .. "\n"
    end
    
    if raindrop.cache and raindrop.cache.text then
        local content = self:htmlToText(raindrop.cache.text)
        content = content:gsub("^%s+", "")
        formatted_content = formatted_content .. content
    end
    
    return formatted_content
end

-- Crea HTML completo para el Reader con estilos
function ContentProcessor:createReaderHTML(raindrop)
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

-- Genera información formateada del artículo
function ContentProcessor:formatArticleInfo(raindrop)
    local content = ""
    
    content = content .. (raindrop.title or _("Untitled")) .. "\n"
    content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
    
    if raindrop.link then
        content = content .. _("URL: ") .. raindrop.link .. "\n\n"
    end
    
    if raindrop.domain then
        content = content .. _("Domain: ") .. raindrop.domain .. "\n"
    end
    
    if raindrop.created then
        local date = raindrop.created:sub(1, 10)
        local time = raindrop.created:sub(12, 19)
        content = content .. _("Saved: ") .. date .. " " .. time .. "\n\n"
    end
    
    if raindrop.type then
        local type_names = {
            link = _("Link"),
            article = _("Article"),
            image = _("Image"),
            video = _("Video"),
            document = _("Document"),
            audio = _("Audio")
        }
        content = content .. _("Type: ") .. (type_names[raindrop.type] or raindrop.type) .. "\n\n"
    end
    
    if raindrop.excerpt and raindrop.excerpt ~= "" then
        content = content .. _("Excerpt:") .. "\n"
        content = content .. raindrop.excerpt .. "\n\n"
    end
    
    if raindrop.note and raindrop.note ~= "" then
        content = content .. _("Notes:") .. "\n"
        content = content .. raindrop.note .. "\n\n"
    end
    
    if raindrop.highlights and #raindrop.highlights > 0 then
        content = content .. _("Highlights:") .. " (" .. #raindrop.highlights .. ")\n"
        content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        
        for i, highlight in ipairs(raindrop.highlights) do
            -- Color indicator as text
            local color_text = ""
            if highlight.color == "yellow" then
                color_text = "[Yellow] "
            elseif highlight.color == "blue" then
                color_text = "[Blue] "
            elseif highlight.color == "red" then
                color_text = "[Red] "
            elseif highlight.color == "green" then
                color_text = "[Green] "
            end
            
            -- Highlight number and text
            content = content .. color_text .. "[" .. i .. "] "
            if highlight.text then
                content = content .. highlight.text .. "\n"
            end
            
            -- Highlight-specific note (if exists)
            if highlight.note and highlight.note ~= "" then
                content = content .. "   Note: " .. highlight.note .. "\n"
            end
            
            -- Add spacing between highlights
            content = content .. "\n"
        end
    end
    
    if raindrop.tags and #raindrop.tags > 0 then
        content = content .. _("Tags: ") .. table.concat(raindrop.tags, ", ") .. "\n\n"
    end
    
    if raindrop.cache then
        if raindrop.cache.status == "ready" then
            content = content .. _("Cache: ") .. _("Available") .. "\n"
            if raindrop.cache.size then
                content = content .. _("Size: ") .. math.floor(raindrop.cache.size/1024) .. " KB\n"
            end
        elseif raindrop.cache.status then
            local status_names = {
                ready = _("Ready"),
                retry = _("Retrying"),
                failed = _("Failed"),
                ["invalid-origin"] = _("Invalid origin"),
                ["invalid-timeout"] = _("Timeout"),
                ["invalid-size"] = _("Invalid size")
            }
            content = content .. _("Cache status: ") .. (status_names[raindrop.cache.status] or raindrop.cache.status) .. "\n"
        end
        content = content .. "\n"
    end
    
    return content
end

return ContentProcessor
