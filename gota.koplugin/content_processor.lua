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

    -- Limpiar espacios en blanco excesivos (MEJORADO)
    -- 1. Eliminar espacios al final de cada línea
    content = content:gsub(" +\n", "\n")

    -- 2. Eliminar espacios múltiples dentro de líneas
    content = content:gsub("  +", " ")

    -- 3. Eliminar líneas vacías con solo espacios
    content = content:gsub("\n%s*\n%s*\n+", "\n\n")

    -- 4. Limitar máximo 2 saltos de línea consecutivos
    content = content:gsub("\n\n\n+", "\n\n")

    -- 5. Trim inicio y final
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

-- Asegura que el string sea UTF-8 válido
function ContentProcessor:ensureUTF8(str)
    if not str then return "" end

    -- Detectar y remover BOM si existe
    if str:sub(1, 3) == "\239\187\191" then  -- UTF-8 BOM (EF BB BF)
        logger.dbg("ContentProcessor: Removed UTF-8 BOM")
        str = str:sub(4)
    end

    -- Reemplazar secuencias inválidas con carácter de reemplazo
    -- Patrón simple: bytes fuera del rango UTF-8 válido
    local cleaned = str:gsub(
        "[^\9\10\13\32-\126\194-\244][\128-\191]*",
        "�"  -- Carácter de reemplazo Unicode
    )

    if cleaned ~= str then
        logger.warn("ContentProcessor: Invalid UTF-8 sequences replaced with �")
    end

    return cleaned
end

-- Limpia HTML eliminando elementos no renderizables en e-ink
function ContentProcessor:cleanHTMLForEink(html_content)
    local content = html_content
    local original_size = #content

    -- 1. Remover elementos no renderizables en e-ink
    content = content:gsub("<script[^>]*>.-</script>", "")
    content = content:gsub("<noscript[^>]*>.-</noscript>", "")
    content = content:gsub("<style[^>]*>.-</style>", "")

    -- 2. Remover elementos multimedia no soportados
    content = content:gsub("<video[^>]*>.-</video>", "")
    content = content:gsub("<audio[^>]*>.-</audio>", "")
    content = content:gsub("<iframe[^>]*>.-</iframe>", "")
    content = content:gsub("<embed[^>]*>", "")
    content = content:gsub("<object[^>]*>.-</object>", "")

    -- 3. Remover formularios (no funcionales)
    content = content:gsub("<form[^>]*>.-</form>", "")
    content = content:gsub("<input[^>]*>", "")
    content = content:gsub("<button[^>]*>.-</button>", "")
    content = content:gsub("<select[^>]*>.-</select>", "")
    content = content:gsub("<textarea[^>]*>.-</textarea>", "")

    -- 4. Remover CSS externo (no se carga en archivos locales)
    content = content:gsub('<link[^>]*rel=["\']stylesheet["\'][^>]*>', "")

    -- 5. Remover atributos style inline (conflicto con CSS del reader)
    content = content:gsub(' style="[^"]*"', "")
    content = content:gsub(" style='[^']*'", "")

    -- 6. Remover comentarios HTML (innecesarios)
    content = content:gsub("<!%-%-.-%-%->", "")

    -- 7. Normalizar whitespace (reducir tamaño)
    content = content:gsub("%s+", " ")     -- Múltiples espacios → uno
    content = content:gsub(" ?<", "<")     -- Espacio antes de tag
    content = content:gsub("> ?", ">")     -- Espacio después de tag
    content = content:gsub("\n+", "\n")    -- Múltiples saltos → uno

    -- 8. Limpiar data URLs muy grandes (>10KB)
    content = content:gsub(
        'src="(data:image/[^"]+)"',
        function(data_url)
            if #data_url > 10000 then
                logger.dbg("ContentProcessor: Removed large data URL (", #data_url, "bytes)")
                return 'src="" alt="[Image too large]"'
            end
            return 'src="' .. data_url .. '"'
        end
    )

    local final_size = #content
    local reduction = math.floor((1 - final_size/original_size) * 100)

    logger.dbg("ContentProcessor: HTML cleaned for e-ink")
    logger.dbg("  Original size:", original_size, "bytes")
    logger.dbg("  Final size:", final_size, "bytes")
    logger.dbg("  Reduction:", reduction, "%")

    return content
end

-- Crea HTML completo para el Reader con estilos
function ContentProcessor:createReaderHTML(raindrop)
    local content = raindrop.cache.text or ""

    -- Validar UTF-8 y remover BOM (NUEVO)
    content = self:ensureUTF8(content)

    -- Extraer body si existe
    local body = content:match("<body[^>]*>(.-)</body>") or content

    -- Limpiar HTML para e-ink
    body = self:cleanHTMLForEink(body)
    
    -- Escapar metadatos (MEJORADO: ahora escapa todo)
    local safe_title = util.htmlEscape(raindrop.title or "")
    local safe_domain = util.htmlEscape(raindrop.domain or "")
    local safe_date = util.htmlEscape(raindrop.created and raindrop.created:sub(1,10) or "")

    return string.format([[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <style>
        /* Reset completo */
        * { margin: 0; padding: 0; box-sizing: border-box; }

        /* Base optimizada para e-ink */
        body {
            font-family: Georgia, "Palatino Linotype", "Book Antiqua", Palatino, serif;
            font-size: 1em;
            line-height: 1.7;
            margin: 0;
            padding: 0.5em;
            color: #000;
            background: #fff;
            text-rendering: optimizeLegibility;
            -webkit-font-smoothing: antialiased;
        }

        /* Headings con contraste alto */
        h1, h2, h3, h4, h5, h6 {
            margin-top: 1.5em;
            margin-bottom: 0.5em;
            line-height: 1.3;
            font-weight: bold;
            color: #000;
            page-break-after: avoid;
        }

        h1 {
            font-size: 1.8em;
            margin-top: 0;
            border-bottom: 2px solid #000;
            padding-bottom: 0.3em;
        }
        h2 { font-size: 1.5em; }
        h3 { font-size: 1.2em; }

        /* Metadata con contraste moderado */
        .meta {
            color: #333;
            font-size: 0.85em;
            margin-bottom: 2em;
            padding-bottom: 1em;
            border-bottom: 2px solid #000;
        }

        .meta div { margin: 0.4em 0; }

        /* Párrafos con espaciado para e-ink */
        p {
            margin-bottom: 1em;
            text-align: justify;
            hyphens: auto;
            page-break-inside: avoid;
        }

        /* Imágenes optimizadas para e-ink */
        img {
            max-width: 100%%;
            height: auto;
            display: block;
            margin: 1.5em auto;
            image-rendering: crisp-edges;
            filter: grayscale(100%%) contrast(1.2);
            page-break-before: auto;
            page-break-after: auto;
            page-break-inside: avoid;
        }

        /* Links sin color (monocromo) */
        a {
            color: #000;
            text-decoration: underline;
            font-weight: bold;
        }

        /* Blockquotes con borde negro */
        blockquote {
            margin: 1.5em 0;
            padding-left: 1.5em;
            border-left: 4px solid #000;
            font-style: italic;
            color: #333;
            page-break-inside: avoid;
        }

        /* Code optimizado para monocromo */
        pre, code {
            font-family: "Courier New", Courier, "Lucida Console", monospace;
            font-size: 0.85em;
        }

        pre {
            background: #f0f0f0;
            padding: 1em;
            overflow-x: auto;
            margin: 1.5em 0;
            border: 2px solid #000;
            page-break-inside: avoid;
        }

        code {
            background: #f0f0f0;
            padding: 0.2em 0.4em;
            border: 1px solid #999;
        }

        pre code {
            background: none;
            padding: 0;
            border: none;
        }

        /* Listas con espaciado para e-ink */
        ul, ol {
            margin: 1em 0;
            padding-left: 2em;
        }

        li {
            margin-bottom: 0.5em;
            page-break-inside: avoid;
        }

        /* Tables con bordes negros */
        table {
            width: 100%%;
            border-collapse: collapse;
            margin: 1.5em 0;
            border: 2px solid #000;
        }

        th, td {
            padding: 0.75em;
            text-align: left;
            border: 1px solid #000;
        }

        th {
            font-weight: bold;
            background: #e0e0e0;
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
    safe_title,
    safe_title,
    safe_domain,
    safe_date,
    body)
end

-- Crea HTML completo con Notes y Highlights incluidos (NUEVO)
function ContentProcessor:createReaderHTMLWithNotes(raindrop)
    local body = ""

    -- Solo procesar contenido si existe y el cache está listo
    if raindrop.cache and raindrop.cache.text and raindrop.cache.text ~= "" then
        local content = raindrop.cache.text

        -- Validar UTF-8 y remover BOM
        content = self:ensureUTF8(content)

        -- Extraer body si existe
        body = content:match("<body[^>]*>(.-)</body>") or content

        -- Limpiar HTML para e-ink
        body = self:cleanHTMLForEink(body)
    else
        -- Si no hay contenido del artículo, mostrar mensaje traducido
        local util = require("util")
        local msg = util.htmlEscape(_("Article content not yet available. The full article cache is still being generated or is not available."))
        body = '<div style="padding: 1.5em; background: #f0f0f0; border: 2px solid #999; margin: 2em 0;">' ..
               '<p style="font-style: italic; color: #333;">' .. msg .. '</p></div>'
    end

    -- Escapar metadatos
    local safe_title = util.htmlEscape(raindrop.title or "")
    local safe_domain = util.htmlEscape(raindrop.domain or "")
    local safe_date = util.htmlEscape(raindrop.created and raindrop.created:sub(1,10) or "")

    -- Generar sección de Notes (si existen)
    local notes_section = ""
    if raindrop.note and raindrop.note ~= "" then
        local safe_note = util.htmlEscape(raindrop.note)
        notes_section = string.format([[
    <div class="notes-section">
        <h2>📝 Notes</h2>
        <div class="note-content">%s</div>
    </div>
]], safe_note)
    end

    -- Generar sección de Highlights (si existen)
    local highlights_section = ""
    if raindrop.highlights and #raindrop.highlights > 0 then
        highlights_section = '<div class="highlights-section">\n'
        highlights_section = highlights_section .. string.format('        <h2>✨ Highlights (%d)</h2>\n', #raindrop.highlights)
        highlights_section = highlights_section .. '        <div class="highlights-list">\n'

        for i, highlight in ipairs(raindrop.highlights) do
            local safe_text = util.htmlEscape(highlight.text or "")
            local safe_note_h = highlight.note and highlight.note ~= "" and util.htmlEscape(highlight.note) or nil

            -- Color class
            local color_class = highlight.color or "yellow"

            highlights_section = highlights_section .. string.format(
                '            <div class="highlight highlight-%s">\n                <div class="highlight-number">[%d]</div>\n                <div class="highlight-text">%s</div>\n',
                color_class, i, safe_text
            )

            if safe_note_h then
                highlights_section = highlights_section .. string.format(
                    '                <div class="highlight-note">Note: %s</div>\n',
                    safe_note_h
                )
            end

            highlights_section = highlights_section .. '            </div>\n'
        end

        highlights_section = highlights_section .. '        </div>\n    </div>\n'
    end

    return string.format([[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>%s</title>
    <style>
        /* Reset completo */
        * { margin: 0; padding: 0; box-sizing: border-box; }

        /* Base optimizada para e-ink */
        body {
            font-family: Georgia, "Palatino Linotype", "Book Antiqua", Palatino, serif;
            font-size: 1em;
            line-height: 1.7;
            margin: 0;
            padding: 0.5em;
            color: #000;
            background: #fff;
            text-rendering: optimizeLegibility;
            -webkit-font-smoothing: antialiased;
        }

        /* Headings con contraste alto */
        h1, h2, h3, h4, h5, h6 {
            margin-top: 1.5em;
            margin-bottom: 0.5em;
            line-height: 1.3;
            font-weight: bold;
            color: #000;
            page-break-after: avoid;
        }

        h1 {
            font-size: 1.8em;
            margin-top: 0;
            border-bottom: 2px solid #000;
            padding-bottom: 0.3em;
        }
        h2 { font-size: 1.5em; margin-top: 2em; }
        h3 { font-size: 1.2em; }

        /* Metadata con contraste moderado */
        .meta {
            color: #333;
            font-size: 0.85em;
            margin-bottom: 2em;
            padding-bottom: 1em;
            border-bottom: 2px solid #000;
        }

        .meta div { margin: 0.4em 0; }

        /* Párrafos con espaciado para e-ink */
        p {
            margin-bottom: 1em;
            text-align: justify;
            hyphens: auto;
            page-break-inside: avoid;
        }

        /* Imágenes optimizadas para e-ink */
        img {
            max-width: 100%%;
            height: auto;
            display: block;
            margin: 1.5em auto;
            image-rendering: crisp-edges;
            filter: grayscale(100%%) contrast(1.2);
            page-break-before: auto;
            page-break-after: auto;
            page-break-inside: avoid;
        }

        /* Links sin color (monocromo) */
        a {
            color: #000;
            text-decoration: underline;
            font-weight: bold;
        }

        /* Blockquotes con borde negro */
        blockquote {
            margin: 1.5em 0;
            padding-left: 1.5em;
            border-left: 4px solid #000;
            font-style: italic;
            color: #333;
            page-break-inside: avoid;
        }

        /* Code optimizado para monocromo */
        pre, code {
            font-family: "Courier New", Courier, "Lucida Console", monospace;
            font-size: 0.85em;
        }

        pre {
            background: #f0f0f0;
            padding: 1em;
            overflow-x: auto;
            margin: 1.5em 0;
            border: 2px solid #000;
            page-break-inside: avoid;
        }

        code {
            background: #f0f0f0;
            padding: 0.2em 0.4em;
            border: 1px solid #999;
        }

        pre code {
            background: none;
            padding: 0;
            border: none;
        }

        /* Listas con espaciado para e-ink */
        ul, ol {
            margin: 1em 0;
            padding-left: 2em;
        }

        li {
            margin-bottom: 0.5em;
            page-break-inside: avoid;
        }

        /* Tables con bordes negros */
        table {
            width: 100%%;
            border-collapse: collapse;
            margin: 1.5em 0;
            border: 2px solid #000;
        }

        th, td {
            padding: 0.75em;
            text-align: left;
            border: 1px solid #000;
        }

        th {
            font-weight: bold;
            background: #e0e0e0;
        }

        /* === ESTILOS PARA NOTES Y HIGHLIGHTS === */

        /* Notes section */
        .notes-section {
            margin: 2em 0;
            padding: 1.5em;
            background: #f5f5f5;
            border: 2px solid #000;
            page-break-inside: avoid;
        }

        .notes-section h2 {
            margin-top: 0;
            margin-bottom: 1em;
            font-size: 1.3em;
        }

        .note-content {
            white-space: pre-wrap;
            line-height: 1.6;
        }

        /* Highlights section */
        .highlights-section {
            margin: 2em 0;
            padding: 1.5em;
            background: #fafafa;
            border: 2px solid #000;
        }

        .highlights-section h2 {
            margin-top: 0;
            margin-bottom: 1em;
            font-size: 1.3em;
        }

        .highlights-list {
            display: block;
        }

        .highlight {
            margin-bottom: 1.5em;
            padding: 1em;
            background: #fff;
            border-left: 4px solid #000;
            page-break-inside: avoid;
        }

        /* Color borders para highlights */
        .highlight-yellow { border-left-color: #000; }
        .highlight-blue { border-left-color: #000; background: #f0f0f0; }
        .highlight-red { border-left-color: #000; background: #f8f8f8; }
        .highlight-green { border-left-color: #000; background: #f5f5f5; }
        .highlight-cyan { border-left-color: #000; background: #fafafa; }
        .highlight-pink { border-left-color: #000; }
        .highlight-purple { border-left-color: #000; }
        .highlight-orange { border-left-color: #000; }

        .highlight-number {
            display: inline-block;
            font-weight: bold;
            margin-right: 0.5em;
            font-size: 0.9em;
        }

        .highlight-text {
            display: inline;
            line-height: 1.6;
        }

        .highlight-note {
            margin-top: 0.5em;
            padding-left: 2em;
            font-style: italic;
            color: #333;
            font-size: 0.9em;
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
    %s
    %s
</body>
</html>
]],
    safe_title,
    safe_title,
    safe_domain,
    safe_date,
    notes_section,
    highlights_section,
    body)
end

-- Formatea solo las notas del artículo (NUEVO)
function ContentProcessor:formatNotes(raindrop)
    local content = ""

    content = content .. (raindrop.title or _("Untitled")) .. "\n"
    content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

    if raindrop.note and raindrop.note ~= "" then
        content = content .. _("Notes:") .. "\n\n"
        content = content .. raindrop.note .. "\n\n"
    else
        content = content .. _("This article has no notes") .. "\n\n"
    end

    -- Información adicional del artículo
    if raindrop.domain then
        content = content .. _("Source: ") .. raindrop.domain .. "\n"
    end

    if raindrop.created then
        local date = raindrop.created:sub(1, 10)
        content = content .. _("Saved: ") .. date .. "\n"
    end

    return content
end

-- Formatea solo los highlights del artículo (NUEVO)
function ContentProcessor:formatHighlights(raindrop)
    local content = ""

    content = content .. (raindrop.title or _("Untitled")) .. "\n"
    content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

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
            elseif highlight.color == "cyan" then
                color_text = "[Cyan] "
            elseif highlight.color == "pink" then
                color_text = "[Pink] "
            elseif highlight.color == "purple" then
                color_text = "[Purple] "
            elseif highlight.color == "orange" then
                color_text = "[Orange] "
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
    else
        content = content .. _("This article has no highlights") .. "\n\n"
    end

    -- Información adicional del artículo
    if raindrop.domain then
        content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        content = content .. _("Source: ") .. raindrop.domain .. "\n"
    end

    if raindrop.created then
        local date = raindrop.created:sub(1, 10)
        content = content .. _("Saved: ") .. date .. "\n"
    end

    return content
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
