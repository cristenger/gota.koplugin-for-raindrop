local logger = require("logger")

--------------------------------------------------
-- codifica una cadena para usarla en una URL
--------------------------------------------------
local function urlEncode(str)
    if type(str) ~= "string" then return "" end
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

--------------------------------------------------
-- devuelve las claves de una tabla en un array
--------------------------------------------------
local function table_keys(t)
    if type(t) ~= "table" then return {} end
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    return keys
end

-- NUEVO: tamaño de una tabla (nº de pares k-v)
local function table_len(t)
    return #table_keys(t)
end

--------------------------------------------------
-- parsea un archivo de configuración Lua y devuelve una tabla
--------------------------------------------------
local function parseSettings(content)
    if not content or content == "" then
        return {}
    end

    -- 1) intentar evaluar tal cual (esperamos `return { … }`)
    local chunk, err = loadstring(content)
    if chunk then
        local ok, res = pcall(chunk)
        if ok and type(res) == "table" then
            return res
        end
    end

    -- 2) si no empezaba por return, envolvemos
    chunk, err = loadstring("return " .. content)
    if chunk then
        local ok, res = pcall(chunk)
        if ok and type(res) == "table" then
            return res
        end
    end

    -- 3) sandbox: asignamos un ambiente vacío y buscamos pares k=v
    local env = {}
    chunk, err = loadstring(content)
    if chunk then
        setfenv(chunk, env)
        local ok = pcall(chunk)
        if ok and next(env) then
            return env
        end
    end

    logger.warn("Gota: no se pudo parsear configuración:", err)
    return {}
end

return {
    urlEncode     = urlEncode,
    table_keys    = table_keys,
    table_len     = table_len,   -- ← exportamos la función nueva
    parseSettings = parseSettings,
}