#!/usr/bin/env lua

--[[
    Script de prueba para la API de Raindrop.io
    Ejecutar desde terminal: lua test.lua
    
    Funciones de prueba:
    1. Verificar autenticación de usuario
    2. Obtener colecciones
    3. Obtener artículos (raindrops)
    4. Buscar artículos
    5. Obtener artículo específico
]]

local http = require("socket.http")
local https = require("ssl.https")
https.cert_verify = false    -- DESACTIVA verificación SSL para experimentar
print("🔒 SSL verification disabled for test script")
local ltn12 = require("ltn12")
local json = require("json")

-- Configuración
local CONFIG = {
    -- CAMBIAR ESTE TOKEN POR EL TUYO
    token = "e82d2495-c42d-40dd-bbf7-5082c1408ac9", -- Obtener de https://app.raindrop.io/settings/integrations
    server_url = "https://api.raindrop.io/rest/v1",
    timeout = 15
}

-- Función auxiliar para hacer requests HTTP CORREGIDA
local function makeRequest(endpoint, method, body)
    local url = CONFIG.server_url .. endpoint
    print(string.format("📡 Request: %s %s", method or "GET", url))
    
    if not CONFIG.token or CONFIG.token == "" or CONFIG.token == "TU_TEST_TOKEN_AQUI" then
        print("❌ ERROR: Token no configurado. Edita la variable CONFIG.token")
        return nil, "Token no configurado"
    end
    
    local sink = {}
    
    local request = {
        url = url,
        method = method or "GET",
        headers = {
            ["Authorization"] = "Bearer " .. CONFIG.token,
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "Raindrop-Test-Script/1.0"
        },
        sink = ltn12.sink.table(sink),
        timeout = CONFIG.timeout,
    }
    
    -- Agregar body si es POST/PUT
    if body and (method == "POST" or method == "PUT") then
        local body_encoded = json:encode(body)
        request.source = ltn12.source.string(body_encoded)
        request.headers["Content-Length"] = #body_encoded
    end
    
    -- Realizar request - CORREGIDO
    local result, status_code, response_headers, status_line = https.request(request)
    
    -- Debug: mostrar qué devolvió la función
    print("📊 Debug - result:", result)
    print("📊 Debug - status_code:", status_code)
    print("📊 Debug - status_line:", status_line)
    
    -- CORRECCIÓN: usar status_code directamente cuando result=1 (éxito)
    local actual_status = status_code
    if result ~= 1 then
        -- Si result no es 1, entonces result contiene el código de error
        actual_status = result
    end
    
    print(string.format("📊 Response: %s", actual_status))
    
    -- Procesar respuesta según código de estado
    if actual_status == 200 then
        local response = table.concat(sink)
        print(string.format("📦 Response size: %d bytes", #response))
        
        if #response > 0 then
            -- CORRECCIÓN: usar json:decode() en lugar de json.decode()
            local decode_ok, data = pcall(function()
                return json:decode(response)
            end)
            if decode_ok then
                return data
            else
                print("📄 Raw response:", response:sub(1, 200) .. "...")
                return nil, "Error al decodificar JSON: " .. tostring(data)
            end
        else
            return {}
        end
        
    elseif actual_status == 204 then
        print("✅ Respuesta exitosa sin contenido")
        return {}
        
    elseif actual_status == 401 then
        return nil, "Token inválido o expirado (401)"
        
    elseif actual_status == 403 then
        return nil, "Acceso denegado - verificar permisos (403)"
        
    elseif actual_status == 429 then
        local error_msg = "Rate limit excedido (429)"
        if response_headers then
            local limit = response_headers["X-RateLimit-Limit"]
            local remaining = response_headers["X-RateLimit-Remaining"]
            if limit or remaining then
                error_msg = error_msg .. string.format(" - Límite: %s, Restantes: %s", 
                                                      limit or "?", remaining or "?")
            end
        end
        return nil, error_msg
        
    else
        -- Mostrar respuesta para debug
        local response = table.concat(sink)
        if #response > 0 then
            print("📄 Response body:", response:sub(1, 500))
        end
        return nil, string.format("Error HTTP %s: %s", actual_status, status_line or "Desconocido")
    end
end

-- Función para mostrar JSON de forma legible
local function prettyPrint(data, indent)
    indent = indent or 0
    local spaces = string.rep("  ", indent)
    
    if type(data) == "table" then
        if #data > 0 then
            -- Array
            print(spaces .. "[")
            for i, v in ipairs(data) do
                if type(v) == "table" then
                    print(spaces .. "  {")
                    prettyPrint(v, indent + 2)
                    print(spaces .. "  }" .. (i < #data and "," or ""))
                else
                    print(spaces .. "  " .. tostring(v) .. (i < #data and "," or ""))
                end
            end
            print(spaces .. "]")
        else
            -- Object
            local first = true
            for k, v in pairs(data) do
                if not first then print(spaces .. ",") end
                first = false
                
                if type(v) == "table" then
                    print(spaces .. k .. ": {")
                    prettyPrint(v, indent + 1)
                    print(spaces .. "}")
                else
                    print(spaces .. k .. ": " .. tostring(v))
                end
            end
        end
    else
        print(spaces .. tostring(data))
    end
end

-- PRUEBAS DE LA API

-- 1. Verificar autenticación
local function testAuthentication()
    print("\n🔐 === PRUEBA 1: Autenticación ===")
    local user_data, err = makeRequest("/user")
    
    if user_data then
        print("✅ Autenticación exitosa!")
        print("👤 Usuario:", user_data.user.fullName or user_data.user.email or "Sin nombre")
        print("📧 Email:", user_data.user.email or "No disponible")
        print("⭐ PRO:", user_data.user.pro and "Sí" or "No")
        print("📊 Colecciones en grupos:", #(user_data.user.groups or {}))
        return true
    else
        print("❌ Error de autenticación:", err)
        return false
    end
end

-- 2. Obtener colecciones
local function testCollections()
    print("\n📁 === PRUEBA 2: Colecciones ===")
    local collections, err = makeRequest("/collections")
    
    if collections then
        print(string.format("✅ Se encontraron %d colecciones:", #(collections.items or {})))
        
        for i, collection in ipairs(collections.items or {}) do
            print(string.format("  %d. %s (%d artículos) - ID: %s", 
                               i, collection.title, collection.count or 0, collection._id))
        end
        
        return collections.items and #collections.items > 0 and collections.items[1]._id or nil
    else
        print("❌ Error obteniendo colecciones:", err)
        return nil
    end
end

-- 3. Obtener artículos de una colección
local function testRaindrops(collection_id)
    collection_id = collection_id or 0 -- 0 = todos los artículos
    
    print(string.format("\n💧 === PRUEBA 3: Artículos (Colección %s) ===", collection_id))
    local endpoint = string.format("/raindrops/%s?perpage=5", collection_id)
    local raindrops, err = makeRequest(endpoint)
    
    if raindrops then
        print(string.format("✅ Se encontraron %d artículos (mostrando primeros 5):", 
                           raindrops.count or 0))
        
        for i, raindrop in ipairs(raindrops.items or {}) do
            print(string.format("  %d. %s", i, raindrop.title or "Sin título"))
            print(string.format("     🔗 %s", raindrop.link or "Sin URL"))
            print(string.format("     📅 %s", raindrop.created or "Sin fecha"))
            print(string.format("     🏷️  %s", table.concat(raindrop.tags or {}, ", ")))
            print()
        end
        
        return raindrops.items and #raindrops.items > 0 and raindrops.items[1]._id or nil
    else
        print("❌ Error obteniendo artículos:", err)
        return nil
    end
end

-- 4. Buscar artículos
local function testSearch()
    print("\n🔍 === PRUEBA 4: Búsqueda ===")
    local search_term = "test" -- Cambiar por término de búsqueda
    local endpoint = "/raindrops/0?search=" .. search_term .. "&perpage=3"
    local results, err = makeRequest(endpoint)
    
    if results then
        print(string.format("✅ Búsqueda '%s' encontró %d resultados:", 
                           search_term, results.count or 0))
        
        for i, raindrop in ipairs(results.items or {}) do
            print(string.format("  %d. %s", i, raindrop.title or "Sin título"))
            print(string.format("     🔗 %s", raindrop.link or "Sin URL"))
        end
    else
        print("❌ Error en búsqueda:", err)
    end
end

-- 5. Obtener artículo específico
local function testSingleRaindrop(raindrop_id)
    if not raindrop_id then
        print("\n⚠️  === PRUEBA 5: Artículo específico (SALTADA - Sin ID) ===")
        return
    end
    
    print(string.format("\n📄 === PRUEBA 5: Artículo específico (ID: %s) ===", raindrop_id))
    local endpoint = "/raindrop/" .. raindrop_id
    local raindrop, err = makeRequest(endpoint)
    
    if raindrop then
        print("✅ Artículo obtenido:")
        local item = raindrop.item
        print("  Título:", item.title or "Sin título")
        print("  URL:", item.link or "Sin URL")
        print("  Extracto:", item.excerpt or "Sin extracto")
        print("  Tipo:", item.type or "Desconocido")
        print("  Tags:", table.concat(item.tags or {}, ", "))
        
        -- Mostrar contenido en caché si existe
        if item.cache and item.cache.status == "ready" then
            print("  📄 Contenido en caché disponible")
            if item.cache.text then
                local preview = item.cache.text:sub(1, 200) .. "..."
                print("  Preview:", preview)
            end
        end
    else
        print("❌ Error obteniendo artículo:", err)
    end
end

-- 6. Prueba de rate limiting
local function testRateLimit()
    print("\n⏱️  === PRUEBA 6: Rate Limiting ===")
    print("Haciendo 5 requests rápidos para probar rate limiting...")
    
    for i = 1, 5 do
        print(string.format("Request %d/5...", i))
        local data, err = makeRequest("/user")
        if data then
            print("  ✅ OK")
        else
            print("  ❌ Error:", err)
            if err and err:find("429") then
                print("  ⚠️  Rate limit detectado!")
                break
            end
        end
        -- Pequeña pausa entre requests
        os.execute("sleep 0.5")
    end
end

-- FUNCIÓN PRINCIPAL
local function main()
    print("🌟 === SCRIPT DE PRUEBA RAINDROP.IO API ===")
    print("Token configurado:", CONFIG.token ~= "TU_TEST_TOKEN_AQUI" and "✅ Sí" or "❌ No")
    
    if CONFIG.token == "TU_TEST_TOKEN_AQUI" then
        print("\n⚠️  IMPORTANTE: Configura tu token antes de continuar!")
        print("1. Ve a: https://app.raindrop.io/settings/integrations")
        print("2. Crea una nueva aplicación")
        print("3. Copia el 'Test token'")
        print("4. Reemplaza CONFIG.token en este script")
        return
    end
    
    -- Ejecutar pruebas secuencialmente
    local auth_ok = testAuthentication()
    if not auth_ok then
        print("\n❌ Falló la autenticación. Verifica tu token.")
        return
    end
    
    local first_collection_id = testCollections()
    local first_raindrop_id = testRaindrops(first_collection_id)
    
    testSearch()
    testSingleRaindrop(first_raindrop_id)
    testRateLimit()
    
    print("\n🎉 === PRUEBAS COMPLETADAS ===")
    print("Revisa los resultados arriba para entender el comportamiento de la API.")
end

-- Ejecutar
main()