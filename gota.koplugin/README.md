# 📚 Gota Plugin para KOReader

Plugin para leer y gestionar tus marcadores de [Raindrop.io](https://raindrop.io) directamente en KOReader.

## 🚀 Características

- ✅ Navegación por colecciones
- ✅ Visualización de artículos con paginación
- ✅ Búsqueda de artículos
- ✅ Lectura en modo texto simple
- ✅ Apertura en lector completo (HTML)
- ✅ Descarga de HTML para lectura offline
- ✅ Gestión automática de caché
- ✅ Soporte para Kindle, Kobo, Android

## 📦 Instalación

1. Copia la carpeta `gota.koplugin` a tu directorio de plugins de KOReader:
   - Kindle: `/mnt/us/koreader/plugins/`
   - Kobo: `/.adds/koreader/plugins/`
   - Android: `/sdcard/koreader/plugins/`

2. Reinicia KOReader

3. Accede al menú → Herramientas → Gota

## ⚙️ Configuración

1. Obtén tu token de Raindrop.io:
   - **Opción 1 (Recomendada)**: Test Token
     - Ve a https://app.raindrop.io/settings/integrations
     - Crea una nueva aplicación
     - Copia el "Test token"
   
   - **Opción 2**: Token Personal de Acceso
     - Usa tu token personal de la API

2. En KOReader:
   - Menú → Herramientas → Gota → Configurar token
   - Pega tu token
   - Click en "Guardar" o "Probar"

## 📖 Uso

### Ver Colecciones
Menú → Herramientas → Gota → Ver colecciones

### Buscar Artículos
Menú → Herramientas → Gota → Buscar artículos

### Leer un Artículo
1. Selecciona una colección
2. Selecciona un artículo
3. Opciones disponibles:
   - **Ver contenido**: Texto simple
   - **Abrir en lector completo**: HTML con formato
   - **Descargar HTML**: Guardar para offline
   - **Ver información**: Metadatos del artículo

## 🏗️ Arquitectura (v2.0.0)

Plugin modularizado en 9 módulos especializados:

```
gota.koplugin/
├── main.lua (455 líneas) - Coordinador principal
├── settings.lua - Gestión de configuración
├── api.lua - Comunicación con Raindrop.io
├── content_processor.lua - Procesamiento HTML
├── ui_builder.lua - Construcción de menús
├── dialogs.lua - Gestión de diálogos
├── article_manager.lua - Operaciones con artículos
├── gota_reader.lua - Integración con ReaderUI
└── l10n/ - Archivos de internacionalización
    ├── templates/gota.pot - Template de traducción
    └── es/gota.po - Traducción al español
```

**Total**: ~2,000 líneas de código distribuidas en módulos <300 líneas cada uno (óptimo para mantenimiento con LLM).

## 🌍 Internacionalización

El plugin detecta automáticamente el idioma de KOReader y muestra la interfaz en ese idioma.

### Idiomas Soportados
- **English** (predeterminado)
- **Español** (Spanish)

### Contribuir Traducciones

Para agregar un nuevo idioma:

1. Crea un directorio para tu idioma:
   ```bash
   mkdir -p l10n/<código_idioma>
   ```

2. Copia el template de traducción:
   ```bash
   cp l10n/templates/gota.pot l10n/<código_idioma>/gota.po
   ```

3. Edita `l10n/<código_idioma>/gota.po` y traduce los strings:
   ```po
   msgid "Configure access token"
   msgstr "Tu traducción aquí"
   ```

4. Compila la traducción:
   ```bash
   ./compile_translations.sh <código_idioma>
   ```
   O para compilar todos:
   ```bash
   ./compile_translations.sh
   ```

### Códigos de Idioma

Usa códigos ISO 639-1:
- `es` - Español
- `fr` - Français
- `de` - Deutsch
- `it` - Italiano
- `pt` - Português
- `ru` - Русский
- `zh` - 中文
- etc.

## 📋 Versiones

- **v2.0.0** (actual): Sistema completo de i18n
- **v1.9.0**: Carpetas unificadas + UI de configuración
- **v1.8.1**: Bugfixes de runtime
- **v1.8**: Ultra modularización (-71% en main.lua)
- **v1.7**: Primera refactorización (API y procesamiento separados)
- **v1.6**: Versión monolítica original

Ver [CHANGELOG.md](CHANGELOG.md) para detalles completos de cada versión.

## 🐛 Reportar Problemas

Si encuentras un bug, comparte:
1. El mensaje de error completo (stack trace)
2. Qué estabas haciendo cuando ocurrió
3. Versión de KOReader y dispositivo

## 📄 Licencia

MIT

## 👨‍💻 Autor

Christian Stenger

---

**Documentación completa**: [CHANGELOG.md](CHANGELOG.md)  
**Testing**: [TESTING_CHECKLIST.md](TESTING_CHECKLIST.md)
