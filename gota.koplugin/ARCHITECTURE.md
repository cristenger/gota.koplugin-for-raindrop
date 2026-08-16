# Arquitectura de Gota

Este documento describe la arquitectura vigente de Gota 2.3.0. La versión de referencia es KOReader 2026.07 o posterior. El código se contrastó con KOReader 2026.07/master y con la API REST v1 de Raindrop.io el 15 de agosto de 2026.

## Alcance

Gota es un plugin de KOReader para una cuenta personal de Raindrop.io. Permite navegar grupos y colecciones, buscar por alcance, revisar resaltados globales, consultar metadatos, editar campos reversibles y abrir o exportar la copia permanente de un artículo.

La autenticación implementada es mediante un token pegado por el usuario. No existe flujo OAuth ni renovación de tokens. La copia permanente de artículos requiere Raindrop PRO; las notas y los resaltados no.

## Componentes

```mermaid
flowchart LR
    K["KOReader<br/>menú y Dispatcher"] --> M["main.lua<br/>coordinación"]
    M --> S["gota_settings.lua<br/>configuración"]
    M --> D["gota_dialogs.lua<br/>diálogos"]
    M --> U["gota_ui_builder.lua<br/>menús y paginación"]
    M --> A["gota_article_manager.lua<br/>casos de uso de artículo"]
    A --> C["gota_content_processor.lua<br/>texto y HTML"]
    A --> R["gota_reader.lua<br/>ReaderUI"]
    R --> Y["gota_reader_styles.lua<br/>política CSS pura"]
    A --> P["gota_api.lua<br/>Raindrop REST v1"]
    P --> Z["gota_compression.lua<br/>gzip acotado"]
    P --> X["api.raindrop.io"]
    S --> F["settings/gota.lua"]
    A --> H["DataStorage/<download_path>/*.html"]
    A --> T["DataStorage/cache/gota/*.html<br/>lectura temporal"]
```

| Módulo | Responsabilidad | No debe hacer |
|---|---|---|
| `main.lua` | Componer dependencias, registrar menú/Dispatcher y coordinar pantallas | Interpretar HTTP o transformar HTML |
| `gota_api.lua` | Transporte HTTPS, autenticación, redirects, reintentos, caché de respuestas y endpoints | Construir widgets |
| `gota_compression.lua` | Descomprimir gzip mediante el zlib incluido en KOReader y limitar la salida | Hacer red o ejecutar comandos externos |
| `gota_article_manager.lua` | Cargar, recargar, exportar y abrir artículos | Conocer internals de `ReaderUI` |
| `gota_content_processor.lua` | Sanear UTF-8, convertir HTML a texto y generar documentos locales | Hacer red |
| `gota_reader.lua` | Abrir/cambiar documento, volver a Gota mediante APIs públicas de KOReader y aplicar la hoja transitoria en pre-render | Preabrir documentos, modificar tablas internas del menú o mutar ajustes persistentes |
| `gota_reader_styles.lua` | Componer el CSS de presentación y detectar los tweaks oficiales de tamaño | Requerir módulos de KOReader, tocar disco o guardar estado |
| `gota_ui_builder.lua` | Crear items, jerarquías de colecciones y paginación | Hacer red o persistir configuración |
| `gota_dialogs.lua` | Construir diálogos y recoger entradas | Guardar directamente ajustes |
| `gota_settings.lua` | Leer y escribir `gota.lua` mediante `LuaSettings` | Registrar UI |
| `gota_version.lua` | Versión, User-Agent y objetivo KOReader | Contener lógica de ejecución |

## Navegación y coherencia de pantalla

Cada detalle de artículo recibe un `SourceContext` pequeño con `kind`, página remota y una función `reload(focus_raindrop_id)`. La closure captura solo IDs, nombre, término, filtros normalizados y alcance; no conserva envelopes, HTML ni widgets. Tras editar favorito, nota, etiquetas o colección, el proceso padre adopta la respuesta, cierra el detalle y reconstruye la lista autoritativa. Las filas llevan `gota_raindrop_id`, y `Menu:switchItemTable` localiza su página sin escribir campos internos de KOReader. Mover a Papelera recarga sin foco porque el elemento ya no debe aparecer en el origen.

Las listas remotas mantienen 25 elementos por petición. Sus controles aparecen arriba y abajo para no confundirse con la paginación interna de `Menu`; el subtítulo muestra alcance, filtros, rango y página de Raindrop. La búsqueda avanzada conserva su último estado únicamente durante el proceso (`last_advanced_search`) y no lo escribe en `gota.lua`.

## Ciclo de vida en KOReader

`Gota:init()` registra primero las acciones de Dispatcher, instancia las dependencias, declara su archivo de ajustes y se registra en el menú principal. `is_doc_only = false` permite que el mismo plugin esté disponible en FileManager y ReaderUI.

Las tres acciones de Dispatcher son:

- `gota_show_articles` → `GotaShowArticles`;
- `gota_search` → `GotaSearch`;
- `gota_collections` → `GotaShowCollections`.

El menú usa `registerToMainMenu`/`addToMainMenu` y `sorting_hint = "more_tools"`. Gota no escribe en `reader.menu.menu_table`.

### Apertura y retorno del lector

```mermaid
sequenceDiagram
    participant UI as main.lua
    participant AM as ArticleManager
    participant GR as GotaReader
    participant RU as ReaderUI

    UI->>AM: openInReader(raindrop)
    AM->>AM: comprueba cache.size y límite de archivo
    AM->>AM: transmite /cache a un .part acotado
    AM->>GR: show(path, callback, normalize_styles)
    GR->>GR: DocumentRegistry:getProvider(path)
    alt ReaderUI ya existe
        GR->>RU: switchDocument(path, nil, callback, provider, forced)
    else FileManager activo
        GR->>RU: showReader(path, provider, nil, forced, callback)
    end
    RU->>RU: ReadSettings y loadDocument
    RU-->>UI: PreRenderDocument
    UI->>GR: applyStyleNormalization(ui)
    GR->>RU: setStyleSheet(misma hoja base, CSS añadido)
    RU->>RU: primer y único render
    RU-->>GR: after_open_callback
    Note over GR: activa “Back to Gota” solo para ese path
    GR->>RU: onHome()
    GR-->>UI: callback de retorno
    RU-->>UI: CloseDocument
    UI->>AM: cleanupManagedReaderPath(path)
```

`DocumentRegistry:getProvider` solo selecciona el proveedor. `ReaderUI` conserva la propiedad exclusiva de abrir y cerrar el documento; Gota no llama `DocumentRegistry:openDocument` por anticipado. La limpieza se centraliza en `CloseDocument`, por lo que volver con «Back to Gota» y salir por Home siguen el mismo ciclo.

### Normalización tipográfica del full reader

Las copias web conservan el CSS editorial del sitio, y la hoja base de KOReader asigna 150 %–100 % a `h1`–`h6`, 80 % a `table` y 70 % a `sub`/`sup`. Una página que marca sus citas como `h5` acaba mostrándolas mucho mayores que su propia prosa. Gota acota esa jerarquía con una hoja de presentación transitoria.

`ReaderUI` emite `PreRenderDocument` después de `loadDocument()` y antes de `document:render()`. En ese punto `ReaderTypeset:onReadSettings` ya resolvió la hoja base y los tweaks activos, así que instalar CSS no provoca un segundo render. `CreDocument:setStyleSheet(hoja_base, css_añadido)` recarga la misma hoja base y concatena el string después de ella; el binding de CREngine hace esa concatenación sin copiar el HTML.

Contratos de esta etapa:

| Contrato | Comportamiento |
|---|---|
| Archivo | El HTML temporal sigue siendo el recibido de Raindrop. No se genera una copia normalizada ni se reescribe el original. |
| Memoria | Un string CSS de pocos KiB, independiente del tamaño del documento. La ruta no lee el archivo ni usa `read("*all")`. |
| Persistencia | Nada se guarda en `doc_settings`, `configurable` ni `G_reader_settings`. La intención vive en el singleton de proceso y `reset()` la borra. |
| Alcance | Solo el documento cuyo path coincide con la petición activa de Gota. Libros ajenos, el documento saliente de `switchDocument` y el HTML reabierto desde historial quedan intactos. |
| Estilos incrustados | `embedded_css` no se toca; Gota nunca llama `setEmbeddedStyleSheet`. |
| Fallo | Un API ausente o que lanza deja abrir el artículo con un warning técnico sin contenido del artículo. |

La precedencia inicial es: hoja base de KOReader → CSS transitorio de Gota → Style tweaks del usuario → cascada del CSS editorial. Hay dos excepciones deliberadas. Si `font_size_all_inherit` o `font_size_most_reset` ya están activos, Gota omite su bloque tipográfico y solo conserva limpieza y ajuste de imágenes: el usuario ya eligió una política de tamaños. Y si durante la lectura cambia los Style tweaks, `ReaderTypeset:onApplyStyleSheet` reconstruye la hoja con sus ajustes; Gota no intercepta ese evento ni reimpone su escala.

La escala usa `rem` como los tweaks oficiales, de modo que cuerpo, títulos, tabla y código escalan juntos al cambiar el tamaño base.

Esta etapa **no es un saneamiento**. `display:none` solo evita que CREngine presente etiquetas interactivas o no presentables; el HTML remoto sigue en el archivo y sigue siendo contenido no confiable. `header`, `footer`, `aside`, `figure`, `svg`, tablas, listas, `pre` y `code` permanecen visibles porque suelen contener texto editorial. El chrome basado en `div` y clases del sitio no se detecta: para extracción real, la vista de texto plano es la ruta prevista. La copia original y la vista de texto plano no pasan por esta política.

## Transporte y contrato Raindrop

La URL base es `https://api.raindrop.io/rest/v1`. El constructor rechaza HTTP, credenciales embebidas, query o fragmento en la URL base. Raindrop no ofrece un endpoint HTTP, por lo que HTTPS sigue siendo obligatorio como transporte.

En Kindle, la autenticación del certificado remoto no está implementada en el flujo soportado. Gota no modifica el estado global `ssl.https.cert_verify` ni fuerza `verify = "peer"`; hereda el comportamiento de LuaSec 1.3.2 incluido por KOReader, cuyo cliente HTTPS usa `verify = "none"` por defecto. El tráfico se cifra, pero el servidor no queda autenticado: un atacante activo en la red podría interceptar el Bearer token. El dispositivo debe usarse en una red de confianza. Esta es una limitación aceptada por compatibilidad, no una garantía de seguridad TLS.

Cada llamada inicial incluye `Authorization: Bearer <token>`. Gota solicita `Accept-Encoding: identity`, pero algunos hosts de almacenamiento devuelven gzip de todos modos. En ese caso usa el zlib incluido en KOReader: no ejecuta binarios externos y aplica el límite configurado a los bytes ya descomprimidos. Una codificación diferente, como Brotli, se rechaza por nombre.

### Copia permanente y redirect

`GET /raindrop/{id}/cache` puede responder 307. Gota desactiva el seguimiento automático y aplica este flujo:

1. acepta redirects solo durante la descarga de caché;
2. exige una URL absoluta HTTPS sin credenciales;
3. limita la cadena a tres redirects;
4. no reenvía `Authorization` al host de almacenamiento;
5. acepta el HTML únicamente tras una respuesta 2xx final.

### Errores y reintentos

`JSON.decode` está protegido con `pcall`. Los bodies JSON de error aportan `errorMessage`, `message` o `error.message` cuando existen. Los timeouts de `socketutil` se restauran incluso si LuaSec lanza una excepción.

Solo las lecturas `GET`/`HEAD` reintentan errores de transporte, 429 y 5xx, hasta tres intentos. `POST`, `PUT`, `PATCH` y `DELETE` hacen exactamente un intento. El retraso es exponencial y, para 429, calcula `Retry-After` o las variantes documentadas de la cabecera de reset. Como este bucle corre en el hilo de UI, Gota solo duerme hasta tres segundos; si el servidor pide una espera mayor, devuelve el control y solicita reintentar más tarde. Los demás 4xx no se reintentan sin modificar la petición.

La caché de respuestas GET vive en memoria durante cinco minutos. `getRaindrop(id, true)` significa recarga forzada: invalida y omite la entrada almacenada.

### Endpoints usados

| Caso de uso | Endpoint |
|---|---|
| Usuario autenticado | `GET /user` |
| Estadísticas del usuario | `GET /user/stats` |
| Colecciones raíz | `GET /collections` |
| Colecciones hijas | `GET /collections/childrens` |
| Marcadores | `GET /raindrops/{collectionId}` |
| Marcador completo | `GET /raindrop/{id}` |
| HTML permanente | `GET /raindrop/{id}/cache` |
| Filtros | `GET /filters/{collectionId}` |
| Resaltados globales/por colección | `GET /highlights[/{collectionId}]` |
| Favorito, nota, tags y colección | `PUT /raindrop/{id}` |
| Mover a Trash, solo fuera de Trash | `DELETE /raindrop/{id}` |
| Todos los tags | `GET /tags` |
| Tags de una colección | `GET /tags/{collectionId}` |

La búsqueda avanzada construye un único parámetro `search`. Por ejemplo, texto `swift`, tag `coffee beans` y tipo `article` producen `swift #"coffee beans" type:article` antes del URL encoding. La búsqueda textual usa `sort=score`; una consulta que solo contiene filtros usa `-created`. El alcance puede ser global, una colección o una colección con `nested=true`. `/filters/{id}?tagsSort=-count` es la única fuente de los filtros populares.

## Modelo de caché de artículo

Raindrop separa los metadatos de caché del HTML. Gota refleja esa separación:

| Estado local | Significado | Acciones de lectura |
|---|---|---|
| `metadata_available` | `cache.status == "ready"` | habilita acciones que descargan bajo demanda |
| `html_loaded` | existe `cache.text` no vacío y acotado | permite transformar a texto o HTML enriquecido |
| `download_error` | falló, excedió el límite o llegó vacío | exige recarga/acción explícita |

Abrir el menú o recargar obtiene solo metadatos. La vista de texto descarga en memoria con presets de 2–64 MiB; una instalación nueva comienza en 16 MiB. El lector y «Guardar copia original» transmiten directamente a archivo con presets de 16–512 MiB y un valor inicial de 128 MiB, sin cargar antes el cuerpo completo en RAM. Los valores guardados de versiones anteriores siguen siendo válidos. `cache.size` permite rechazo anticipado y el sink LTN12 aborta si el cuerpo recibido cruza el límite. Cuando la respuesta es gzip, el mismo límite vuelve a comprobarse contra la salida descomprimida. Cada archivo usa `.part`; la variante comprimida y la decodificada se eliminan ante cualquier error, y el archivo final solo aparece después del 2xx y del renombrado atómico. «Exportar con notas y resaltados» no depende del HTML PRO.

### Pipeline de texto plano

La vista de texto valida UTF-8 y elimina `script`, `style`, `template`, `svg`, `iframe`, `object` y comentarios antes de interpretar la estructura. Después retira `nav`, `header`, `footer` y los elementos de navegación conocidos, elige el `article` con más texto visible o, si no existe, el `main` con más texto visible. Solo entonces quita las etiquetas restantes, decodifica entidades HTML y normaliza espacios y saltos de línea. La selección no depende del porcentaje que ocupe el artículo dentro del documento.

El saneamiento ocurre antes de decodificar entidades. Por eso un ejemplo editorial escrito como `&lt;style&gt;` permanece como texto y el contenido de `pre` y `code` no se descarta. El lector HTML y la copia original no pasan por este pipeline. Los límites de 2–64 MiB tampoco cambian: se aplican al HTML descargado y descomprimido antes de convertirlo.

### Frontera de confianza de los exports

La copia original conserva byte a byte el HTML servido por Raindrop y puede contener código o recursos del sitio; se guarda para fidelidad y debe tratarse como contenido web no confiable. El export anotado pertenece a Gota: elimina elementos activos conocidos, convierte el cuerpo remoto a texto, valida UTF-8 y escapa el resultado antes de insertarlo en una plantilla controlada. Notas, resaltados, metadatos y URL también se insertan como texto escapado; la URL no se convierte en `href`. Este segundo formato prioriza seguridad y legibilidad sobre fidelidad visual.

## Colecciones

`API:getCollectionStructure()` conserva por separado `user.groups`, raíces e hijas. El builder ordena grupos por `sort` ascendente, respeta el orden exacto de raíces de cada grupo y ordena hermanos hijos por `sort` descendente. Los nodos no agrupados, huérfanos o involucrados en ciclos se conservan en “Other collections”. El colapso de grupo es local a la sesión. Si usuario o hijos fallan, las raíces siguen disponibles. `/user/stats` añade recuentos de All, Unsorted y Trash e información no accionable de enlaces rotos/duplicados.

Los IDs de sistema usados por la UI son `0` para todos los marcadores, `-1` para Unsorted y `-99` para Trash.

## Persistencia y seguridad

| Dato | Ubicación | Duración |
|---|---|---|
| Token, carpeta, orden y límites de caché | `DataStorage:getSettingsDir()/gota.lua` | persistente; el token puede borrarse desde Gota |
| HTML exportado | `DataStorage:getDataDir()/<download_path>/` | persistente |
| HTML usado por ReaderUI | `DataStorage:getDataDir()/cache/gota/` | temporal; `CloseDocument` y el siguiente arranque retiran solo `raindrop_<id>.html[.part]` |
| Respuestas API | tabla de `API.response_cache` | proceso, TTL 5 min |
| Estado de retorno del lector | singleton `GotaReader` | proceso y documento actual |

El diálogo muestra el token como contraseña, pero `LuaSettings` lo guarda en texto claro. El archivo debe tratarse como una credencial y no compartirse en informes, respaldos públicos o issues. El alcance soportado es una integración personal mediante test token; OAuth multiusuario queda fuera del diseño actual.

La allowlist de limpieza exige el directorio canónico y el nombre exacto. Nunca borra exports, otros archivos de caché ni directorios `.sdr`; los sidecars de lectura se conservan. La carpeta de exportación siempre queda bajo `DataStorage`, acepta espacios y segmentos anidados y rechaza rutas absolutas, `.`/`..`, controles y escapes mediante symlink.

El ajuste `download_path` conserva su clave en `gota.lua` por compatibilidad, pero la UI lo llama «carpeta de exportación» porque solo gobierna «Guardar copia original» y «Exportar con notas y resaltados». El lector completo escribe en `cache/gota/` y borra su archivo al cerrar, de modo que abrir un artículo nunca sobrescribe una copia guardada a propósito. La UI evita el verbo «descargar» en esa acción para no prometer un archivo persistente.

## Pruebas y validación

La suite autocontenida no necesita KOReader ni una cuenta real:

```bash
lua tests/run.lua
luac -p *.lua tests/run.lua
git diff --check
```

Cubre 94 casos: UTF-8 y export anotado adversarial, búsqueda por alcance/estado, foco y paginación remota, URLs HTTPS, redirects sin fuga del Bearer, streaming, gzip y límites antes y después de descomprimir, reintentos explícitos, envelopes/JSON, reintentos automáticos solo de lectura, grupos y orden de colecciones, resaltados, mutaciones allowlisted, protección de Papelera, cleanup confinado, rutas, firmas de `ReaderUI`, normalización de estilos en pre-render y Dispatcher. El audit separado valida cobertura española, placeholders y la allowlist de traducciones idénticas.

Los tres casos de gzip requieren el FFI de LuaJIT. Un intérprete sin JIT los falla con `LuaJIT FFI is unavailable`; esa es una limitación del intérprete, no del plugin.

Antes de publicar una release se requiere además un smoke test en KOReader 2026.07.1 o posterior y una prueba real contra Raindrop para 200/307/401/429. Esas pruebas verifican la integración real de LuaSec en Kindle, el renderizado e-ink y el servicio externo; no pueden sustituirse por mocks.

## Deuda conocida

- Las llamadas HTTP siguen siendo síncronas dentro del callback de `NetworkMgr`; una red lenta puede bloquear la UI durante el timeout. `NetworkMgr:runWhenOnline` comprueba conectividad, no crea un hilo. KOReader 2026.07 expone `Trapper`, pero la migración queda detenida hasta demostrar cancelación, memoria y coherencia padre/hijo en Kindle y Kobo con una cuenta de prueba; no se presenta un spinner como asincronía.
- El proyecto soporta test tokens personales, no OAuth con refresh.
- La descarga cruda a CREngine necesita smoke test en Kindle/Kobo reales; si un port no abre el HTML, se mantendrá el límite y se diseñará una transformación acotada a archivo.
- Raindrop no documenta `count` en el ejemplo de listas; Gota acepta su ausencia y pagina de forma abierta.
- `main.lua` y `gota_content_processor.lua` siguen concentrando demasiada lógica; separar controladores de pantalla y plantillas HTML reducirá el coste de cambio.
- CI valida Lua 5.1, la suite local y el catálogo; aún no cubre una instancia real de KOReader ni una cuenta Raindrop.
- El catálogo español pasa `msgfmt` y el audit de cobertura/placeholder; las pocas igualdades restantes están justificadas en `tests/check_translations.py`.

## Fuentes canónicas

KOReader:

- [plugin Hello 2026.07](https://raw.githubusercontent.com/koreader/koreader/v2026.07/plugins/hello.koplugin/main.lua)
- [Dispatcher](https://koreader.rocks/doc/modules/dispatcher.html)
- [ReaderUI 2026.07](https://raw.githubusercontent.com/koreader/koreader/v2026.07/frontend/apps/reader/readerui.lua)
- [DocumentRegistry 2026.07](https://raw.githubusercontent.com/koreader/koreader/v2026.07/frontend/document/documentregistry.lua)
- [PluginLoader 2026.07](https://raw.githubusercontent.com/koreader/koreader/v2026.07/frontend/pluginloader.lua)
- [Network manager 2026.07](https://raw.githubusercontent.com/koreader/koreader/v2026.07/frontend/ui/network/manager.lua)
- [InputDialog 2026.07](https://raw.githubusercontent.com/koreader/koreader/v2026.07/frontend/ui/widget/inputdialog.lua)
- [Menu 2026.07](https://raw.githubusercontent.com/koreader/koreader/v2026.07/frontend/ui/widget/menu.lua)
- [PathChooser 2026.07](https://raw.githubusercontent.com/koreader/koreader/v2026.07/frontend/ui/widget/pathchooser.lua)
- [ReadHistory 2026.07](https://raw.githubusercontent.com/koreader/koreader/v2026.07/frontend/readhistory.lua)
- [util 2026.07](https://raw.githubusercontent.com/koreader/koreader/v2026.07/frontend/util.lua)
- [pruebas de KOReader](https://koreader.rocks/doc/topics/Unit_tests.md.html)
- [releases de KOReader](https://github.com/koreader/koreader/releases)
- [LuaSec 1.3.2 usado por KOReader](https://raw.githubusercontent.com/brunoos/luasec/v1.3.2/src/https.lua)
- [bundle CA incluido en KOReader](https://raw.githubusercontent.com/koreader/koreader-base/master/thirdparty/certifi/CMakeLists.txt)

Raindrop.io:

- [autenticación](https://developer.raindrop.io/v1/authentication/calls.md)
- [tokens](https://developer.raindrop.io/v1/authentication/token.md)
- [listar y buscar raindrops](https://developer.raindrop.io/v1/raindrops/multiple.md)
- [raindrop y caché permanente](https://developer.raindrop.io/v1/raindrops/single.md)
- [colecciones](https://developer.raindrop.io/v1/collections/methods.md)
- [estructura anidada](https://developer.raindrop.io/v1/collections/nested-structure.md)
- [tags](https://developer.raindrop.io/v1/tags.md)
- [filtros agregados](https://developer.raindrop.io/v1/filters.md)
- [resaltados](https://developer.raindrop.io/v1/highlights.md)
- [modelo de raindrop](https://developer.raindrop.io/v1/raindrops.md)
- [operadores de búsqueda](https://help.raindrop.io/filters#need-more-precise-filtering)
- [errores y rate limits](https://developer.raindrop.io/readme.md)
