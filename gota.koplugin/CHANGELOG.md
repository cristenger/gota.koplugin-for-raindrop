# 📋 Changelog - Gota Plugin para KOReader

## v2.0.0 - Full Internationalization (5 de octubre de 2025)

### 🌍 Internacionalización Completa

**BREAKING CHANGE**: El idioma fuente del plugin cambió de español a inglés.

#### Sistema de i18n con gettext

El plugin ahora implementa el sistema estándar de internacionalización de KOReader usando archivos `.po`/`.mo`:

**Estructura**:
```
l10n/
├── templates/
│   └── gota.pot          # Template de traducción (126 strings únicos)
└── es/
    ├── gota.po           # Traducción al español
    └── gota.mo           # Binario compilado
```

**Características**:
- ✅ Detección automática del idioma de KOReader
- ✅ Inglés como idioma predeterminado (source language)
- ✅ Traducción completa al español (126 strings)
- ✅ Listo para agregar más idiomas fácilmente

**Archivos modificados** (146 strings reemplazados):
- `api.lua`: 7 strings
- `article_manager.lua`: 16 strings
- `content_processor.lua`: 26 strings
- `dialogs.lua`: 27 strings
- `gota_reader.lua`: 5 strings
- `main.lua`: 37 strings
- `ui_builder.lua`: 26 strings
- `_meta.lua`: 2 strings

**Herramientas de traducción**:
- `extract_strings.py`: Extrae strings del código y genera .pot/.po
- `compile_translations.sh`: Compila archivos .po → .mo
- `replace_strings.py`: Script de migración español → inglés

**Cómo contribuir traducciones**:
1. Copiar `l10n/templates/gota.pot` a `l10n/<idioma>/gota.po`
2. Traducir los strings en el archivo .po
3. Compilar con `./compile_translations.sh <idioma>`

**Ejemplo de traducción**:
```po
msgid "Configure access token"
msgstr "Configurar token de acceso"  # Para español
```

---

## v1.9.0 - UX Improvements (5 de octubre de 2025)

### ✨ Mejoras

#### Unificación de Carpetas de Descarga

**Problema**: Las dos opciones para ver artículos guardaban archivos en ubicaciones diferentes:
- "Abrir en lector completo" → Creaba archivo temporal en `/cache/gota/`
- "Descargar HTML" → Guardaba archivo en `/gota_articles/`

**Solución**: 
1. **Carpeta unificada**: Ambas opciones ahora usan la **misma carpeta configurable**
2. **Nueva configuración**: Se agregó campo `download_path` en settings.lua (default: "gota_articles")
3. **UI de configuración**: Nueva opción en menú principal "Configurar carpeta de descargas"
4. **Persistencia**: La configuración se guarda automáticamente en el archivo de settings

**Cambios técnicos**:
- `settings.lua`: Agregados `download_path`, `getDownloadPath()`, `setDownloadPath()`, `getFullDownloadPath()`
- `article_manager.lua`: Modificados `downloadHTML()` y `openInReader()` para usar ruta configurable
- `article_manager.lua`: Agregado `setSettings()` para recibir referencia a settings
- `dialogs.lua`: Agregado `showDownloadPathDialog()` con validación de ruta y sanitización
- `main.lua`: Agregado menú "Configurar carpeta de descargas" y método `showDownloadPathDialog()`

**Beneficios para el usuario**:
- ✅ Todos los artículos se guardan en la misma carpeta
- ✅ Carpeta configurable según preferencias del usuario
- ✅ Ruta relativa a DataDir (típicamente `koreader/`)
- ✅ Configuración persistente entre sesiones

#### Revisión de Internacionalización (i18n)

**Verificación**: Se revisó que todos los strings de UI usen correctamente la función `_()` de gettext
- ✅ `dialogs.lua`: Todos los botones y textos usan `_()` 
- ✅ `menu_builder.lua`: Todos los ítems de menú usan `_()`
- ✅ `main.lua`: Todas las notificaciones y mensajes usan `_()`

**Idioma por defecto**: Español (source language)
**Soporte futuro**: El plugin está listo para traducciones a otros idiomas mediante archivos `.po` de KOReader

---

## v1.8.2 - Bugfix Release (5 de octubre de 2025)

### 🐛 Bug Corregido

#### Inconsistencia en Detección de Caché de Artículos

**Síntoma**: El menú de artículo mostraba "La caché no está disponible" pero al ver la información del artículo indicaba que SÍ había caché disponible (status: ready, size > 0).

**Causa Raíz**: 
1. La función `hasValidCache()` consideraba que había caché válido si `cache.status == "ready"` Y `cache.size > 0`, incluso sin tener el contenido HTML (`cache.text`) cargado
2. El flujo en `main.lua` era confuso: verificaba `hasValidCache()` antes de intentar cargar el contenido
3. Según la API de Raindrop.io, el objeto `raindrop` incluye metadata del caché (`status`, `size`) pero NO el contenido HTML. El contenido requiere una llamada separada a `/raindrop/{id}/cache`

**Solución**:

1. **Mejorada `hasValidCache()` en article_manager.lua**:
```lua
// Lógica más clara y explícita
- Primero verifica que existe cache
- Luego verifica que status == "ready"
- Si ya hay texto cargado, verifica que tenga >50 caracteres
- Si no hay texto pero size > 0, retorna true (disponible para descarga)
```

2. **Mejorada `loadCacheContent()` en article_manager.lua**:
```lua
// Manejo de errores más robusto
- Verifica que status == "ready" antes de intentar cargar
- Si falla la carga, NO establece texto por defecto
- Logs más descriptivos para debugging
```

3. **Mejorado flujo en `showRaindropContent()` en main.lua**:
```lua
// Separación clara de conceptos
1. cache_available: ¿Está disponible? (status == "ready")
2. Si disponible pero sin texto → intentar cargar
3. has_cache: ¿Realmente tenemos contenido? (texto cargado y válido)
```

**Archivos modificados**:
- `article_manager.lua`: Funciones `hasValidCache()` y `loadCacheContent()`
- `main.lua`: Función `showRaindropContent()`

**Resultado**: 
- Ahora el menú refleja correctamente si el contenido está disponible para uso inmediato
- Los mensajes son consistentes con el estado real del caché
- Mejor manejo de errores cuando falla la carga del contenido

### ✅ Verificación
- Todos los módulos con sintaxis correcta
- Lógica de caché más robusta y clara

---

## v1.8.1 - Bugfix Release (5 de octubre de 2025)

### 🐛 Bugs Corregidos

#### 1. Error en Closures de Diálogos (dialogs.lua)
**Síntoma**: Crash al hacer clic en cualquier botón de los diálogos
```
attempt to index global 'token_dialog' (a nil value)
```

**Causa**: Variables locales declaradas y asignadas en la misma línea no están disponibles para closures internos.

**Solución**: Declarar variables antes de asignarlas
```lua
-- ANTES
local token_dialog = InputDialog:new{...}

-- DESPUÉS  
local token_dialog
token_dialog = InputDialog:new{...}
```

**Archivos modificados**:
- `dialogs.lua` líneas 28, 103
- Funciones: `showTokenDialog()`, `showSearchDialog()`

#### 2. Error de Sobrescritura de Función de Traducción (main.lua)
**Síntoma**: Crash al ver contenido de artículos
```
attempt to call upvalue '_' (a nil value)
```

**Causa**: Usar `_` como nombre de variable descartada sobrescribe la función `_()` de gettext.

**Solución**: Usar nombre diferente para variable descartada
```lua
-- ANTES
raindrop, _ = self.article_manager:loadFullArticle(raindrop)

-- DESPUÉS
local err
raindrop, err = self.article_manager:loadFullArticle(raindrop)
```

**Archivos modificados**:
- `main.lua` línea 248
- Función: `showRaindropContent()`

### ✅ Verificación
- Todos los módulos (8/8) con sintaxis correcta
- Bugs conocidos: 0

---

## v1.8 - Ultra Modularización (5 de octubre de 2025)

### 🎯 Objetivo
Reducir `main.lua` de forma ultra agresiva para facilitar el trabajo con LLMs.

### ✨ Cambios Principales

#### Reducción de main.lua
- **v1.6 (original)**: 1571 líneas
- **v1.7**: 940 líneas (-40%)
- **v1.8**: 455 líneas (-71% total, -51% vs v1.7)

#### Nuevos Módulos Creados

**1. ui_builder.lua (280 líneas)**
- Construcción de todos los menús
- Items de colecciones y artículos
- Paginación simple y avanzada
- Botones para viewers

Funciones principales:
```lua
UIBuilder:buildRaindropItems(raindrops, callback)
UIBuilder:buildCollectionItems(collections, callback)
UIBuilder:buildArticleMenu(raindrop, has_cache, callbacks)
UIBuilder:addPagination(items, data, page, perpage, callback)
UIBuilder:createMenu(title, items)
UIBuilder:buildContentViewerButtons(callbacks)
```

**2. dialogs.lua (231 líneas)**
- Gestión de todos los diálogos
- Input dialogs (token, búsqueda)
- Text viewers (debug, info, contenido)

Funciones principales:
```lua
Dialogs:showTokenDialog(current_token, callbacks)
Dialogs:showSearchDialog(on_search, on_cancel)
Dialogs:showDebugInfo(debug_info, server_url)
Dialogs:showArticleInfo(raindrop, formatted_info)
Dialogs:showContentViewer(title, content, buttons)
Dialogs:showLinkInfo(raindrop)
```

**3. article_manager.lua (216 líneas)**
- Gestión completa de operaciones con artículos
- Carga de contenido completo y caché
- Descarga de HTML
- Apertura en reader

Funciones principales:
```lua
ArticleManager:loadFullArticle(raindrop)
ArticleManager:loadCacheContent(raindrop)
ArticleManager:hasValidCache(raindrop)
ArticleManager:reloadArticle(raindrop_id, callback)
ArticleManager:downloadHTML(raindrop)
ArticleManager:openInReader(raindrop, close_callback, return_callback)
ArticleManager:openDownloadFolder(filename, close_callback)
```

### 🏗️ Nueva Arquitectura

```
main.lua (455L) - COORDINADOR PURO
├── settings.lua (153L) - Configuración
├── api.lua (259L) - Comunicación Raindrop.io
├── content_processor.lua (293L) - Procesamiento HTML
├── ui_builder.lua (280L) - Construcción UI
├── dialogs.lua (231L) - Gestión diálogos
├── article_manager.lua (216L) - Gestión artículos
└── gota_reader.lua (156L) - Integración ReaderUI
```

### 📊 Beneficios para LLM

| Tarea | Líneas v1.6 | Líneas v1.8 | Mejora |
|-------|-------------|-------------|--------|
| Modificar UI | 1571 | 280 | -82% |
| Cambiar diálogos | 1571 | 231 | -85% |
| Gestionar artículos | 1571 | 216 | -86% |
| Modificar API | 1571 | 259 | -84% |
| Procesar HTML | 1571 | 293 | -81% |
| Coordinación general | 1571 | 455 | -71% |

### 🎭 Separación de Responsabilidades

**main.lua**: Solo coordinación, delegación y callbacks de alto nivel
**ui_builder.lua**: Solo construcción de menús e items
**dialogs.lua**: Solo creación y gestión de diálogos
**article_manager.lua**: Solo operaciones con artículos
**api.lua**: Solo comunicación HTTP
**content_processor.lua**: Solo procesamiento de contenido
**settings.lua**: Solo persistencia de configuración
**gota_reader.lua**: Solo integración con ReaderUI

---

## v1.7 - Primera Refactorización (anterior)

### 🎯 Objetivo
Modularizar el código monolítico para mejorar mantenibilidad.

### ✨ Cambios Principales

#### Reducción de main.lua
- **v1.6 (original)**: 1571 líneas
- **v1.7**: 940 líneas (-40%)

#### Nuevos Módulos Creados

**1. api.lua (259 líneas)**
- Toda la comunicación con Raindrop.io API
- Caché de respuestas (TTL 5 minutos)
- Reintentos automáticos
- Descompresión Gzip
- Manejo de SSL sin verificación (para Kindle)

Funciones principales:
```lua
API:getUser()
API:getCollections()
API:getRaindrops(collection_id, page, perpage)
API:getRaindrop(raindrop_id)
API:getRaindropCache(raindrop_id)
API:searchRaindrops(search_term, page, perpage)
API:testToken(token)
```

**2. content_processor.lua (293 líneas)**
- Conversión HTML → Texto plano
- Limpieza de contenido (ads, nav, etc.)
- Extracción de contenido principal
- Generación de HTML para reader
- Formateo de información de artículos

Funciones principales:
```lua
ContentProcessor:htmlToText(html_content)
ContentProcessor:createReaderHTML(raindrop)
ContentProcessor:formatArticleText(raindrop)
ContentProcessor:formatArticleInfo(raindrop)
```

### 🏗️ Arquitectura

```
main.lua (940L) - Orquestador principal
├── settings.lua (153L) - Configuración
├── api.lua (259L) - Comunicación API (NUEVO)
├── content_processor.lua (293L) - Procesamiento (NUEVO)
└── gota_reader.lua (156L) - Integración ReaderUI
```

---

## v1.6 y anteriores

Versión monolítica original con toda la funcionalidad en `main.lua` (1571 líneas).

### Funcionalidades
- ✅ Configuración de token Raindrop.io
- ✅ Listado de colecciones
- ✅ Visualización de artículos con paginación
- ✅ Búsqueda de artículos
- ✅ Ver contenido en texto simple
- ✅ Abrir artículos en lector completo (HTML)
- ✅ Descargar HTML para lectura offline
- ✅ Gestión de caché
- ✅ Información de artículos
- ✅ Copiar URLs
- ✅ Debug info

---

## 📊 Resumen de Evolución

| Versión | main.lua | Módulos | Características |
|---------|----------|---------|-----------------|
| v1.6 | 1571 L | 4 | Monolítico |
| v1.7 | 940 L (-40%) | 6 | API + Procesamiento separados |
| v1.8 | 455 L (-71%) | 9 | Ultra modular |
| v1.8.1 | 455 L | 9 | Bugfixes de runtime |

### Métricas Finales v1.8.1

- **Total líneas de código**: ~2,049 (sin contar backups)
- **Módulos**: 9
- **Módulo más grande**: content_processor.lua (293 líneas)
- **Módulo más pequeño**: _meta.lua (6 líneas)
- **Todos los módulos**: <300 líneas (óptimo para LLM)
- **Bugs conocidos**: 0
- **Cobertura de tests**: Manual (pendiente automatización)

---

## 🎓 Lecciones Aprendidas

### v1.8.1
1. **Closures y variables locales**: Declarar variables antes de usarlas en callbacks
2. **Nombres reservados**: Nunca usar `_` como variable en KOReader (es la función gettext)
3. **Testing de runtime**: Verificación de sintaxis no es suficiente, siempre probar en emulador

### v1.8
1. **Módulos <300 líneas**: Tamaño ideal para contexto de LLM
2. **Single Responsibility**: Un módulo, una responsabilidad
3. **Dependency Injection**: Los módulos reciben lo que necesitan en el constructor
4. **Composición**: main.lua compone módulos en lugar de implementar todo

### v1.7
1. **Separación de concerns**: API y procesamiento son responsabilidades independientes
2. **Caché inteligente**: TTL de 5 minutos mejora experiencia de usuario
3. **Manejo de errores**: Reintentos y mensajes claros son esenciales

---

## 🔮 Roadmap Futuro

### v1.9 (Planeado)
- [ ] Unit tests automatizados
- [ ] CI/CD con GitHub Actions
- [ ] Mejoras en caché persistente
- [ ] Soporte para colecciones anidadas
- [ ] Sincronización de estado de lectura

### v2.0 (Visión)
- [ ] Soporte para múltiples servicios (Pocket, Instapaper)
- [ ] Anotaciones sincronizadas
- [ ] Modo offline mejorado
- [ ] Exportación de highlights

---

**Mantenedor**: Christian Stenger  
**Licencia**: MIT  
**Última actualización**: 5 de octubre de 2025
