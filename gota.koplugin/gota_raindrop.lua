-- Normalize the two public shapes of Raindrop highlight references at the
-- boundary, before widgets or navigation depend on the related bookmark.
local Raindrop = {}

function Raindrop.highlightReference(highlight)
    if type(highlight) ~= "table" then return nil end
    local raw = highlight.raindropRef
    local id = type(raw) == "table" and raw._id or raw
    if type(id) ~= "number" and type(id) ~= "string" then return nil end
    id = tonumber(id)
    if not id or id ~= id or id <= 0 or id >= 2 ^ 53 or id ~= math.floor(id) then
        return nil
    end
    local reference = {}
    if type(raw) == "table" then
        for key, value in pairs(raw) do reference[key] = value end
    end
    reference._id = id
    reference.title = reference.title or highlight.title
    reference.link = reference.link or highlight.link
    return reference
end

return Raindrop
