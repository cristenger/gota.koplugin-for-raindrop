# Checklist de Testing - Gota Plugin v1.7 (Refactorizado)

## ✅ Verificaciones Pre-Deployment

### 1. Sintaxis y Estructura
- [x] ✅ Sintaxis Lua válida en todos los archivos
- [x] ✅ No hay errores de compilación con `luac -p`
- [x] ✅ Estructura de archivos correcta
- [x] ✅ Backup del código original creado

### 2. Archivos Requeridos
```
[x] _meta.lua             (sin cambios)
[x] settings.lua          (sin cambios)
[x] gota_reader.lua       (sin cambios)
[x] main.lua              (refactorizado)
[x] api.lua               (nuevo)
[x] content_processor.lua (nuevo)
[x] main_backup.lua       (backup)
```

### 3. Módulos y Dependencias
- [x] ✅ `api.lua` puede ser requerido por `main.lua`
- [x] ✅ `content_processor.lua` puede ser requerido por `main.lua`
- [x] ✅ `settings.lua` puede ser requerido por `main.lua`
- [x] ✅ `gota_reader.lua` puede ser requerido por `main.lua`

## 🧪 Tests Funcionales (A realizar en dispositivo)

### Configuración Inicial
- [ ] Plugin aparece en el menú principal
- [ ] Se puede abrir el menú de Gota
- [ ] Botón "Configurar token" funciona
- [ ] Diálogo de token se muestra correctamente
- [ ] Se puede escribir en el campo de token

### Gestión de Token
- [ ] Botón "Guardar" guarda el token correctamente
- [ ] Botón "Probar" verifica el token con la API
- [ ] Token válido muestra mensaje de éxito
- [ ] Token inválido muestra mensaje de error
- [ ] Token se persiste después de reiniciar

### Navegación de Colecciones
- [ ] "Ver colecciones" muestra la lista
- [ ] Colecciones muestran conteo correcto
- [ ] Se puede entrar a una colección
- [ ] Lista de artículos se carga correctamente
- [ ] Paginación funciona (siguiente/anterior)

### Visualización de Artículos
- [ ] Se puede abrir un artículo
- [ ] Menú de opciones del artículo aparece
- [ ] "Ver información" muestra metadatos
- [ ] "Ver contenido" muestra texto procesado
- [ ] "Copiar URL" muestra el enlace

### Lectura de Artículos
- [ ] "Abrir en lector completo" funciona
- [ ] HTML se renderiza correctamente
- [ ] Se puede navegar por el contenido
- [ ] Botón "Volver a Gota" funciona
- [ ] Cerrar el lector retorna a Gota

### Búsqueda
- [ ] Diálogo de búsqueda se abre
- [ ] Se puede escribir término de búsqueda
- [ ] Resultados se muestran correctamente
- [ ] Se puede abrir artículo desde resultados
- [ ] Paginación de búsqueda funciona

### Descarga de HTML
- [ ] "Descargar HTML" crea el archivo
- [ ] Archivo se guarda en ubicación correcta
- [ ] Contenido del archivo es válido
- [ ] Menú post-descarga aparece
- [ ] "Ir a carpeta" abre FileManager

### Gestión de Caché
- [ ] Artículos sin caché muestran mensaje apropiado
- [ ] Artículos con caché en proceso muestran estado
- [ ] Artículos con caché listo se pueden ver
- [ ] Recarga de artículo funciona
- [ ] Caché de API funciona (requests repetidos son rápidos)

### UI y UX
- [ ] Notificaciones se muestran correctamente
- [ ] Mensajes de progreso aparecen y desaparecen
- [ ] No hay memory leaks de widgets
- [ ] Todos los widgets se cierran apropiadamente
- [ ] Navegación entre pantallas es fluida

### Manejo de Errores
- [ ] Error de red muestra mensaje apropiado
- [ ] Token inválido se maneja correctamente
- [ ] Artículo no disponible muestra error claro
- [ ] Timeout de API se maneja con reintentos
- [ ] Errores de descarga se reportan

### Debug y Logging
- [ ] "Debug: Ver configuración" funciona
- [ ] Muestra información del token
- [ ] Muestra estado del archivo de configuración
- [ ] Logs se escriben correctamente
- [ ] Información de módulos aparece

## 🔍 Tests de Integración

### Flujo Completo 1: Primera Vez
```
1. Instalar plugin
2. Abrir menú de Gota
3. Configurar token
4. Probar token
5. Ver colecciones
6. Entrar a una colección
7. Abrir un artículo
8. Leer en lector completo
```
- [ ] Flujo completo sin errores

### Flujo Completo 2: Usuario Existente
```
1. Abrir Gota (token ya configurado)
2. Buscar artículos
3. Abrir resultado
4. Ver en texto simple
5. Descargar HTML
6. Ir a carpeta de descargas
```
- [ ] Flujo completo sin errores

### Flujo Completo 3: Navegación Compleja
```
1. Ver colecciones
2. Entrar a colección con muchos artículos
3. Navegar múltiples páginas
4. Abrir varios artículos
5. Usar botones de volver
6. Cerrar todo apropiadamente
```
- [ ] Flujo completo sin errores
- [ ] No hay widgets huérfanos

## 🐛 Tests de Regresión

### Funcionalidades Críticas
- [ ] SSL desactivado sigue funcionando
- [ ] Descompresión Gzip funciona
- [ ] Procesamiento HTML mantiene contenido
- [ ] Paginación calcula páginas correctamente
- [ ] Cache TTL respeta el timeout

### Compatibilidad
- [ ] Archivos de configuración antiguos funcionan
- [ ] Tokens guardados previamente se leen
- [ ] No hay conflictos con otros plugins

## 📱 Tests por Dispositivo

### Kindle
- [ ] Plugin carga correctamente
- [ ] Red WiFi funciona
- [ ] Lectura de artículos fluida
- [ ] Memoria suficiente para operación

### Kobo
- [ ] Plugin carga correctamente
- [ ] Red WiFi funciona
- [ ] Lectura de artículos fluida
- [ ] Memoria suficiente para operación

### Android (KOReader app)
- [ ] Plugin carga correctamente
- [ ] Red funciona
- [ ] Lectura de artículos fluida

## 🔧 Tests de Desarrollo

### Code Review
- [x] ✅ Código sigue convenciones de KOReader
- [x] ✅ Nombres de variables son descriptivos
- [x] ✅ Funciones tienen propósito único
- [x] ✅ Logging apropiado en lugares clave
- [x] ✅ Manejo de errores consistente

### Performance
- [ ] Tiempo de carga del plugin es aceptable
- [ ] Requests a API no bloquean UI
- [ ] Procesamiento HTML es rápido
- [ ] Memoria no crece indefinidamente
- [ ] Cache ayuda a velocidad

### Mantenibilidad
- [x] ✅ Módulos son independientes
- [x] ✅ Funciones tienen un propósito claro
- [x] ✅ Tamaño de archivos es manejable
- [x] ✅ Comentarios explican secciones complejas
- [x] ✅ Estructura facilita extensión futura

## 📝 Notas de Testing

### Prioridad Alta
```
✓ Configuración de token
✓ Ver y navegar colecciones
✓ Abrir artículos
✓ Leer en reader
```

### Prioridad Media
```
- Búsqueda de artículos
- Descargar HTML
- Paginación compleja
```

### Prioridad Baja
```
- Debug info
- Casos edge de error
- Performance extremo
```

## 🚨 Criterios de Aceptación

**MÍNIMO para considerar exitosa la refactorización:**
- [x] ✅ Sintaxis válida en todos los archivos
- [ ] Plugin carga sin errores
- [ ] Se puede configurar token
- [ ] Se pueden ver colecciones
- [ ] Se pueden leer artículos
- [ ] No hay regresión en funcionalidades principales

**IDEAL:**
- [ ] Todos los tests funcionales pasan
- [ ] Performance es igual o mejor
- [ ] No hay memory leaks
- [ ] Código es más mantenible

## 📞 Plan de Rollback

Si los tests fallan:
```bash
cd gota.koplugin
mv main.lua main_refactored.lua
mv main_backup.lua main.lua
rm api.lua content_processor.lua
# Reiniciar KOReader
```

---

**Estado**: ✅ Refactorización completada y verificada sintácticamente
**Próximo Paso**: Testing funcional en dispositivo real
**Fecha**: Octubre 2025
