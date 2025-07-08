-- Archivo de configuración manual para Raindrop.io
-- Este archivo es opcional, el plugin creará uno automáticamente
-- Ubicación: koreader/settings/raindrop.lua

return {
	-- Token de test obtenido desde https://app.raindrop.io/settings/integrations
	token = "TOKEN",
	
	-- Configuraciones adicionales (v2.0+)
	items_per_page = 20,        -- Número de artículos por página (1-100)
	use_cache = true,           -- Habilitar sistema de caché
	
	-- Configuraciones futuras
	-- cache_ttl = 300,         -- Tiempo de vida del caché en segundos (5 minutos por defecto)
	-- auto_clean_cache = true, -- Limpiar caché automáticamente después de X días
	-- offline_mode = false,    -- Modo offline (futura implementación)
}