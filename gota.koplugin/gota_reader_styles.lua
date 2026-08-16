--[[
    Presentation-only stylesheet policy for Gota's transient full reader.

    Raindrop web copies keep the publisher's editorial CSS, so CREngine renders
    whatever font sizes the source site declared. Combined with the base sheet
    (data/epub.css assigns 150%-100% to h1-h6, 80% to table and 70% to sub/sup)
    a page that marks pull quotes as <h5> ends up with headings several times
    larger than its own prose.

    This module only composes the CSS string. It never touches KOReader
    modules, the filesystem or global state, so it stays testable outside the
    emulator and adds no per-document memory cost. Applying the result is
    gota_reader.lua's job.
]]

local ReaderStyles = {}

-- Official KOReader tweak IDs whose universal rule already implements a
-- font-size policy. They are mutually exclusive in css_tweaks.lua; when either
-- is active the user has already chosen how publisher sizes are handled and
-- Gota must not layer a second policy on top.
local FONT_SIZE_TWEAK_IDS = {
    "font_size_all_inherit",
    "font_size_most_reset",
}

-- Hidden elements are limited to interactive or non-presentational tags.
-- header, footer, aside, figure, svg and tables stay visible because they
-- routinely carry editorial content. display:none only stops CREngine from
-- presenting the markup; it does not remove it from the downloaded file.
local STRUCTURE_CSS = [[
/* Gota: presentation-only cleanup for the transient full reader. */
script, style, template, nav, form, input, button, select, textarea,
iframe, object, embed, video, audio {
    display: none !important;
}

img {
    max-width: 100% !important;
    height: auto !important;
}
]]

-- The universal rule mirrors the official font_size_all_inherit tweak so
-- inherited editorial sizes collapse first; element selectors then win on
-- specificity and assign a bounded scale. rem keeps everything tied to the
-- base font size chosen in KOReader, exactly like font_size_most_reset.
local FONT_SCALE_CSS = [[
/* Neutralize descendant sizes before assigning a bounded semantic scale. */
* {
    font-size: inherit !important;
}

html, body, p, li, dt, dd, blockquote, figcaption {
    font-size: 1rem !important;
}

h1 { font-size: 1.6rem !important; }
h2 { font-size: 1.4rem !important; }
h3 { font-size: 1.25rem !important; }
h4, h5, h6 { font-size: 1.1rem !important; }

small, table, pre, code, kbd, samp {
    font-size: 0.9rem !important;
}

sub, sup {
    font-size: 0.8rem !important;
}
]]

local function hasContent(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

-- ReaderStyleTweak:isTweakEnabled returns (enabled, globally_enabled) and reads
-- tables that may not exist yet, so every lookup is contained.
function ReaderStyles.hasActiveFontSizeTweak(styletweak)
    if type(styletweak) ~= "table" then return false end
    -- self.enabled is the global "apply style tweaks" switch; when it is off
    -- KOReader appends no tweak CSS at all.
    if styletweak.enabled == false then return false end
    if type(styletweak.isTweakEnabled) ~= "function" then return false end

    for _, tweak_id in ipairs(FONT_SIZE_TWEAK_IDS) do
        local ok, enabled = pcall(styletweak.isTweakEnabled, styletweak, tweak_id)
        if ok and enabled then return true end
    end
    return false
end

-- The user's tweak CSS is appended last so its cascade position is preserved:
-- CREngine concatenates this string after the base sheet, and within the
-- string later rules win ties. Gota therefore sets a starting point without
-- outranking an explicit user choice of equal specificity.
function ReaderStyles.build(user_css, options)
    if type(options) ~= "table" then options = {} end

    local parts = { STRUCTURE_CSS }
    if options.skip_font_normalization ~= true then
        parts[#parts + 1] = FONT_SCALE_CSS
    end
    if hasContent(user_css) then
        parts[#parts + 1] = user_css
    end

    return table.concat(parts, "\n")
end

return ReaderStyles
