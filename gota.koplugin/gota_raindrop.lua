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

-- Raindrop's documented collection access.level: 1 public read-only,
-- 2 collaborator read-only, 3 collaborator with write access, 4 owner.
-- Returns nil when the level is unknown so the server stays the authority.
function Raindrop.canWrite(level)
    level = tonumber(level)
    if not level then return nil end
    return level >= 3
end

return Raindrop
