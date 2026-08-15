--[[
    Gota Content Processor Module
    Handles HTML processing, cleaning, and conversion
]]

local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local ContentProcessor = {}

local UTF8_REPLACEMENT = "\239\191\189"

local function isContinuationByte(byte)
    return byte and byte >= 0x80 and byte <= 0xBF
end

-- Validate complete UTF-8 sequences without depending on Lua 5.3's utf8 module.
-- KOReader uses LuaJIT/Lua 5.1, so this intentionally works at the byte level.
local function validSequenceLength(str, index)
    local first = str:byte(index)
    if not first then
        return nil
    end

    if first <= 0x7F then
        return 1
    end

    local second = str:byte(index + 1)
    if first >= 0xC2 and first <= 0xDF then
        return isContinuationByte(second) and 2 or nil
    end

    local third = str:byte(index + 2)
    if first == 0xE0 then
        return second and second >= 0xA0 and second <= 0xBF
            and isContinuationByte(third) and 3 or nil
    elseif (first >= 0xE1 and first <= 0xEC) or
           (first >= 0xEE and first <= 0xEF) then
        return isContinuationByte(second) and isContinuationByte(third) and 3 or nil
    elseif first == 0xED then
        -- UTF-16 surrogate code points (U+D800-U+DFFF) are not valid UTF-8.
        return second and second >= 0x80 and second <= 0x9F
            and isContinuationByte(third) and 3 or nil
    end

    local fourth = str:byte(index + 3)
    if first == 0xF0 then
        return second and second >= 0x90 and second <= 0xBF
            and isContinuationByte(third) and isContinuationByte(fourth) and 4 or nil
    elseif first >= 0xF1 and first <= 0xF3 then
        return isContinuationByte(second) and isContinuationByte(third)
            and isContinuationByte(fourth) and 4 or nil
    elseif first == 0xF4 then
        -- Unicode ends at U+10FFFF.
        return second and second >= 0x80 and second <= 0x8F
            and isContinuationByte(third) and isContinuationByte(fourth) and 4 or nil
    end

    return nil
end

local function invalidSequenceLength(str, index)
    local first = str:byte(index)
    local expected = 1

    if first and first >= 0xC0 and first <= 0xDF then
        expected = 2
    elseif first and first >= 0xE0 and first <= 0xEF then
        expected = 3
    elseif first and first >= 0xF0 and first <= 0xF7 then
        expected = 4
    elseif isContinuationByte(first) then
        -- Treat a run of orphaned continuation bytes as one malformed sequence.
        local length = 1
        while isContinuationByte(str:byte(index + length)) do
            length = length + 1
        end
        return length
    end

    local length = 1
    while length < expected and isContinuationByte(str:byte(index + length)) do
        length = length + 1
    end
    return length
end

-- Pure helper kept public for lightweight tests that do not load KOReader.
local function sanitizeUTF8(str)
    if str == nil then
        return "", false, false
    end
    if type(str) ~= "string" then
        str = tostring(str)
    end

    local had_bom = str:sub(1, 3) == "\239\187\191"
    if had_bom then
        str = str:sub(4)
    end

    local parts = {}
    local index = 1
    local replaced = false
    while index <= #str do
        local length = validSequenceLength(str, index)
        if length then
            parts[#parts + 1] = str:sub(index, index + length - 1)
            index = index + length
        else
            parts[#parts + 1] = UTF8_REPLACEMENT
            index = index + invalidSequenceLength(str, index)
            replaced = true
        end
    end

    return table.concat(parts), replaced, had_bom
end

ContentProcessor.sanitizeUTF8 = sanitizeUTF8

local function escapeHTMLValue(value)
    local cleaned = sanitizeUTF8(value == nil and "" or tostring(value))
    return util.htmlEscape(cleaned)
end

local function escapeHTMLMultiline(value)
    local escaped = escapeHTMLValue(value):gsub("\r\n", "\n"):gsub("\r", "\n")
    return escaped:gsub("\n", "<br/>")
end

local function caseInsensitiveTag(tag)
    return (tag:gsub("%a", function(letter)
        return "[" .. letter:lower() .. letter:upper() .. "]"
    end))
end

local function removePairedElement(content, tag)
    local pattern = caseInsensitiveTag(tag)
    return (content:gsub("<%s*" .. pattern .. "[^>]*>.-</%s*" .. pattern .. "%s*>", ""))
end

local function removeOpenTag(content, tag)
    local pattern = caseInsensitiveTag(tag)
    return (content:gsub("<%s*/?%s*" .. pattern .. "[^>]*>", ""))
end

local function extractHTMLBody(content)
    return content:match("<[Bb][Oo][Dd][Yy][^>]*>(.-)</%s*[Bb][Oo][Dd][Yy]%s*>") or content
end

local HIGHLIGHT_COLORS = {
    blue = true,
    brown = true,
    cyan = true,
    gray = true,
    green = true,
    indigo = true,
    orange = true,
    pink = true,
    purple = true,
    red = true,
    teal = true,
    yellow = true,
}

local HIGHLIGHT_COLOR_NAMES = {
    blue = _("Blue"),
    brown = _("Brown"),
    cyan = _("Cyan"),
    gray = _("Gray"),
    green = _("Green"),
    indigo = _("Indigo"),
    orange = _("Orange"),
    pink = _("Pink"),
    purple = _("Purple"),
    red = _("Red"),
    teal = _("Teal"),
    yellow = _("Yellow"),
}

local function highlightColorText(highlight)
    local name = type(highlight) == "table" and
        HIGHLIGHT_COLOR_NAMES[highlight.color] or nil
    return name and ("[" .. name .. "] ") or ""
end

local function hasHighlights(raindrop)
    return raindrop and type(raindrop.highlights) == "table" and
        #raindrop.highlights > 0
end

function ContentProcessor:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Limpia y convierte HTML a texto plano mejorado
function ContentProcessor:htmlToText(html_content)
    if type(html_content) ~= "string" or html_content == "" then
        return ""
    end
    html_content = self:ensureUTF8(html_content)
    local content = html_content
    local original_length = #content
    logger.dbg("Gota ContentProcessor: Procesando contenido HTML, longitud original:", original_length)

    -- Remover elementos no deseados
    content = removePairedElement(content, "nav")
    content = removePairedElement(content, "header")
    content = removePairedElement(content, "footer")

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
    content = content:gsub("<[Bb][Rr][^>]*>", "\n")
    content = content:gsub("<[Pp][^>]*>", "\n")
    content = content:gsub("</[Pp]%s*>", "\n")
    content = content:gsub("<[Hh]%d[^>]*>", "\n\n")
    content = content:gsub("</[Hh]%d%s*>", "\n")
    content = content:gsub("<[Dd][Ii][Vv][^>]*>", "\n")
    content = content:gsub("</[Dd][Ii][Vv]%s*>", "\n")
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
    content = removePairedElement(content, "script")
    content = removePairedElement(content, "style")
    content = content:gsub("<[Bb][Rr][^>]*>", "\n")
    content = content:gsub("<[Pp][^>]*>", "\n")
    content = content:gsub("</[Pp]%s*>", "\n")
    content = content:gsub("<[Dd][Ii][Vv][^>]*>", "\n")
    content = content:gsub("</[Dd][Ii][Vv]%s*>", "\n")
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
    local cleaned, replaced, had_bom = sanitizeUTF8(str)

    if had_bom then
        logger.dbg("ContentProcessor: Removed UTF-8 BOM")
    end
    if replaced then
        logger.warn("ContentProcessor: Invalid UTF-8 sequences replaced with �")
    end

    return cleaned
end

-- Limpia HTML eliminando elementos no renderizables en e-ink
function ContentProcessor:cleanHTMLForEink(html_content)
    if type(html_content) ~= "string" or html_content == "" then
        return ""
    end
    local content = html_content
    local original_size = #content

    -- 1. Remover elementos no renderizables en e-ink
    content = removePairedElement(content, "script")
    content = removePairedElement(content, "style")
    -- Keep useful fallback content from <noscript>, only remove its wrapper.
    content = removeOpenTag(content, "noscript")

    -- 2. Remover elementos multimedia no soportados
    content = removePairedElement(content, "video")
    content = removePairedElement(content, "audio")
    content = removePairedElement(content, "iframe")
    content = removeOpenTag(content, "embed")
    content = removePairedElement(content, "object")

    -- 3. Remover formularios (no funcionales)
    content = removePairedElement(content, "form")
    content = removeOpenTag(content, "input")
    content = removePairedElement(content, "button")
    content = removePairedElement(content, "select")
    content = removePairedElement(content, "textarea")

    -- 4. Remover CSS externo (no se carga en archivos locales)
    content = removeOpenTag(content, "link")

    -- 5. Remover atributos style inline (conflicto con CSS del reader)
    content = content:gsub('%s+[Ss][Tt][Yy][Ll][Ee]%s*=%s*"[^"]*"', "")
    content = content:gsub("%s+[Ss][Tt][Yy][Ll][Ee]%s*=%s*'[^']*'", "")

    -- 6. Remover comentarios HTML (innecesarios)
    content = content:gsub("<!%-%-.-%-%->", "")

    -- 7. Remove whitespace only between tags. Global %s+ collapsing corrupts
    -- preformatted code, poetry, and other whitespace-sensitive content.
    content = content:gsub(">%s+<", "><")

    -- 8. Limpiar data URLs muy grandes (>10KB)
    content = content:gsub(
        '([Ss][Rr][Cc]%s*=%s*)"([Dd][Aa][Tt][Aa]:[Ii][Mm][Aa][Gg][Ee]/[^"]+)"',
        function(prefix, data_url)
            if #data_url > 10000 then
                logger.dbg("ContentProcessor: Removed large data URL (", #data_url, "bytes)")
                return prefix .. '"" alt="[Image too large]"'
            end
            return prefix .. '"' .. data_url .. '"'
        end
    )
    content = content:gsub(
        "([Ss][Rr][Cc]%s*=%s*)'([Dd][Aa][Tt][Aa]:[Ii][Mm][Aa][Gg][Ee]/[^']+)'",
        function(prefix, data_url)
            if #data_url > 10000 then
                logger.dbg("ContentProcessor: Removed large data URL (", #data_url, "bytes)")
                return prefix .. "'' alt='[Image too large]'"
            end
            return prefix .. "'" .. data_url .. "'"
        end
    )

    local final_size = #content
    local reduction = original_size > 0 and
        math.floor((1 - final_size/original_size) * 100) or 0

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
    local body = extractHTMLBody(content)

    -- Limpiar HTML para e-ink
    body = self:cleanHTMLForEink(body)

    -- Escapar metadatos (MEJORADO: ahora escapa todo)
    local safe_title = escapeHTMLValue(raindrop.title)
    local safe_domain = escapeHTMLValue(raindrop.domain)
    local safe_date = escapeHTMLValue(raindrop.created and raindrop.created:sub(1,10) or "")

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
            font-family: serif;
            font-size: 1em;
            line-height: 1.7;
            margin: 0;
            padding: 0.5em;
            color: #000;
            background: #fff;
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
        }

        /* Imágenes optimizadas para e-ink */
        img {
            max-width: 100%%;
            height: auto;
            display: block;
            margin: 1.5em auto;
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
            white-space: pre-wrap;
            word-wrap: break-word;
            margin: 1.5em 0;
            border: 2px solid #000;
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
        body = extractHTMLBody(content)

        -- Limpiar HTML para e-ink
        body = self:cleanHTMLForEink(body)
    else
        -- Si no hay contenido del artículo, mostrar mensaje traducido
        local msg = escapeHTMLValue(_("Article content not yet available. The full article cache is still being generated or is not available."))
        body = '<div style="padding: 1.5em; background: #f0f0f0; border: 2px solid #999; margin: 2em 0;">' ..
               '<p style="font-style: italic; color: #333;">' .. msg .. '</p></div>'
    end

    -- Escapar metadatos
    local safe_title = escapeHTMLValue(raindrop.title)
    local safe_domain = escapeHTMLValue(raindrop.domain)
    local safe_date = escapeHTMLValue(raindrop.created and raindrop.created:sub(1,10) or "")

    -- Generar sección de Notes (si existen)
    local notes_section = ""
    if raindrop.note and raindrop.note ~= "" then
        local safe_note = escapeHTMLMultiline(raindrop.note)
        notes_section = string.format([[
    <div class="notes-section">
        <h2>%s</h2>
        <div class="note-content">%s</div>
    </div>
]], escapeHTMLValue(_("Notes:")), safe_note)
    end

    -- Generar sección de Highlights (si existen)
    local highlights_section = ""
    if hasHighlights(raindrop) then
        local highlights_parts = {
            '<div class="highlights-section">\n',
            string.format('        <h2>%s (%d)</h2>\n',
                escapeHTMLValue(_("Highlights:")), #raindrop.highlights),
            '        <div class="highlights-list">\n',
        }

        for i, highlight in ipairs(raindrop.highlights) do
            if type(highlight) == "table" then
                local safe_text = escapeHTMLMultiline(highlight.text)
                local safe_note_h = highlight.note and highlight.note ~= "" and
                    escapeHTMLMultiline(highlight.note) or nil

                -- Raindrop documents a closed enum; never interpolate an
                -- unexpected remote value into an HTML attribute.
                local color_class = HIGHLIGHT_COLORS[highlight.color] and
                    highlight.color or "yellow"

                highlights_parts[#highlights_parts + 1] = string.format(
                    '            <div class="highlight highlight-%s">\n                <div class="highlight-number">[%d]</div>\n                <div class="highlight-text">%s</div>\n',
                    color_class, i, safe_text
                )

                if safe_note_h then
                    highlights_parts[#highlights_parts + 1] = string.format(
                        '                <div class="highlight-note">%s %s</div>\n',
                        escapeHTMLValue(_("Notes:")), safe_note_h
                    )
                end

                highlights_parts[#highlights_parts + 1] = '            </div>\n'
            end
        end

        highlights_parts[#highlights_parts + 1] = '        </div>\n    </div>\n'
        highlights_section = table.concat(highlights_parts)
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
            font-family: serif;
            font-size: 1em;
            line-height: 1.7;
            margin: 0;
            padding: 0.5em;
            color: #000;
            background: #fff;
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
        }

        /* Imágenes optimizadas para e-ink */
        img {
            max-width: 100%%;
            height: auto;
            display: block;
            margin: 1.5em auto;
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
            white-space: pre-wrap;
            word-wrap: break-word;
            margin: 1.5em 0;
            border: 2px solid #000;
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

    if hasHighlights(raindrop) then
        content = content .. _("Highlights:") .. " (" .. #raindrop.highlights .. ")\n"
        content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

        for i, highlight in ipairs(raindrop.highlights) do
            if type(highlight) == "table" then
                content = content .. highlightColorText(highlight) .. "[" .. i .. "] "
                if highlight.text ~= nil then
                    content = content .. tostring(highlight.text) .. "\n"
                end
                if highlight.note and highlight.note ~= "" then
                    content = content .. "   " .. _("Note: ") ..
                        tostring(highlight.note) .. "\n"
                end
                content = content .. "\n"
            end
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

    if hasHighlights(raindrop) then
        content = content .. _("Highlights:") .. " (" .. #raindrop.highlights .. ")\n"
        content = content .. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

        for i, highlight in ipairs(raindrop.highlights) do
            if type(highlight) == "table" then
                content = content .. highlightColorText(highlight) .. "[" .. i .. "] "
                if highlight.text ~= nil then
                    content = content .. tostring(highlight.text) .. "\n"
                end
                if highlight.note and highlight.note ~= "" then
                    content = content .. "   " .. _("Note: ") ..
                        tostring(highlight.note) .. "\n"
                end
                content = content .. "\n"
            end
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
