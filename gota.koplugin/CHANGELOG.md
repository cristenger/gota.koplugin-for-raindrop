# 📋 Changelog - Gota Plugin for KOReader

## v2.0.0 - Full Internationalization (October 5, 2025)


#### i18n System with gettext

The plugin now implements KOReader's standard internationalization system using `.po`/`.mo` files:

**Structure**:
```
l10n/
├── templates/
│   └── gota.pot          # Translation template (126 unique strings)
└── es/
    ├── gota.po           # Spanish translation
    └── gota.mo           # Compiled binary
```

**Features**:
- ✅ Automatic detection of KOReader's language
- ✅ English as the default language (source language)
- ✅ Full Spanish translation (126 strings)
- ✅ Ready to easily add more languages

**Modified files** (146 strings replaced):
- `api.lua`: 7 strings
- `article_manager.lua`: 16 strings
- `content_processor.lua`: 26 strings
- `dialogs.lua`: 27 strings
- `gota_reader.lua`: 5 strings
- `main.lua`: 37 strings
- `ui_builder.lua`: 26 strings
- `_meta.lua`: 2 strings

**Translation Tools**:
- `extract_strings.py`: Extracts strings from the code and generates .pot/.po
- `compile_translations.sh`: Compiles .po → .mo files
- `replace_strings.py`: Spanish → English migration script

**How to contribute translations**:
1. Copy `l10n/templates/gota.pot` to `l10n/<language>/gota.po`
2. Translate the strings in the .po file
3. Compile with `./compile_translations.sh <language>`

**Translation Example**:
```po
msgid "Configure access token"
msgstr "Configurar token de acceso"  # For Spanish
```

### 🎯 UI Simplification

**Change**: The redundant "Download HTML" option has been removed from the article menu.

**Before**:
- "Open in full reader" → Saved a temporary file and opened it in the reader
- "Download HTML" → Saved a permanent file and showed options

**Now**:
- "Open in full reader" → Saves a permanent file and opens it in the reader
- Same functionality, simpler interface

**Benefits**:
- ✅ Cleaner menu (3 options instead of 4)
- ✅ More intuitive behavior
- ✅ Files are always saved permanently
- ✅ Code reduction (~60 lines removed)

**Affected Files**:
- `article_manager.lua`: Removed `downloadHTML()` and `openDownloadFolder()` functions
- `ui_builder.lua`: Removed "Download HTML" option from the menu
- `main.lua`: Removed `download_html` callback and `showDownloadOptions()` function

**Updated Statistics**:
- Total unique strings: **127** (+2 vs advanced search)
- Total occurrences: **151** (+2 vs advanced search)

### 🎨 UX Improvements

**Main Menu Reorganization**:

**Before**:
```
├── Configure access token
├── Configure download folder
├── Debug: View configuration
├── View collections
├── Search articles
├── Advanced search
└── All articles
```

**Now**:
```
├── All articles
├── View collections
├── Search articles
├── Advanced search
└── Configuration
    ├── Configure access token
    ├── Configure download folder
    └── Debug Raindrop API connection
```

**Benefits**:
- ✅ Frequently used options at the top
- ✅ Configuration grouped in a submenu
- ✅ Logical order: view → search → configure
- ✅ More descriptive name for debug

**Full Screen in Searches**:
- Search results now take up the full screen
- Consistent with collections and "All articles"
- Better reading experience

### 🔍 Advanced Search with Filters

**New Feature**: Advanced search system with contextual filters.

**Features**:
- ✅ New "Advanced search" option in the main menu
- ✅ Filtering by **tags** (user tags)
- ✅ Filtering by **type** (article, image, video, document)
- ✅ Combination of text search + filters
- ✅ Shows popular tags with a counter
- ✅ Shows available types with a counter
- ✅ Results title indicates active filters

**Before** (v1.9.0):
- Only simple text search

**Now** (v2.0.0):
- "Search articles" → Simple search (text only)
- "Advanced search" → Search with filters (tags, types, optional text)

**Usage Example**:
1. User selects "Advanced search"
2. Plugin loads available filters from the API
3. Shows popular tags: `guides (9)`, `performance (19)`, etc.
4. Shows types: `article (313)`, `image (143)`, `video (26)`, etc.
5. User enters criteria: tag="guides", type="article"
6. Results are filtered: `Results: '' (42) [#guides] [article]`

**Technical Implementation**:
- `api.lua`:
  - New `getFilters(collectionId)` method → gets available filters
  - `searchRaindrops()` method extended with `filters` parameter
- `dialogs.lua`:
  - New `showAdvancedSearchDialog()` function → dialog with 3 fields
  - Uses `MultiInputDialog` for multiple inputs
- `main.lua`:
  - New `showAdvancedSearchDialog()` function → loads filters and shows dialog
  - `searchRaindrops()` function extended with `filters` parameter
  - Results title shows active filters

**Raindrop API Used**:
```
GET /filters/{collectionId}
GET /raindrops/0?search=X&tag=Y&type=Z
```

**Benefits**:
- ✅ More precise and contextual search
- ✅ Content discovery by tags
- ✅ Filtering by content type
- ✅ Experience similar to the official Raindrop app
- ✅ Keeps simple search for quick cases

---

## v1.9.0 - UX Improvements (October 5, 2025)

### ✨ Improvements

#### Unification of Download Folders

**Problem**: The two options for viewing articles saved files in different locations:
- "Open in full reader" → Created a temporary file in `/cache/gota/`
- "Download HTML" → Saved a file in `/gota_articles/`

**Solution**:
1. **Unified folder**: Both options now use the **same configurable folder**
2. **New setting**: Added `download_path` field in settings.lua (default: "gota_articles")
3. **Configuration UI**: New option in the main menu "Configure download folder"
4. **Persistence**: The configuration is automatically saved in the settings file

**Technical Changes**:
- `settings.lua`: Added `download_path`, `getDownloadPath()`, `setDownloadPath()`, `getFullDownloadPath()`
- `article_manager.lua`: Modified `downloadHTML()` and `openInReader()` to use the configurable path
- `article_manager.lua`: Added `setSettings()` to receive a reference to settings
- `dialogs.lua`: Added `showDownloadPathDialog()` with path validation and sanitization
- `main.lua`: Added "Configure download folder" menu and `showDownloadPathDialog()` method

**User Benefits**:
- ✅ All articles are saved in the same folder
- ✅ Configurable folder according to user preferences
- ✅ Path relative to DataDir (typically `koreader/`)
- ✅ Persistent settings between sessions

#### Internationalization (i18n) Review

**Verification**: Checked that all UI strings correctly use the gettext `_()` function
- ✅ `dialogs.lua`: All buttons and texts use `_()`
- ✅ `menu_builder.lua`: All menu items use `_()`
- ✅ `main.lua`: All notifications and messages use `_()`

**Default language**: Spanish (source language)
**Future support**: The plugin is ready for translations into other languages using KOReader's `.po` files

---

## v1.8.2 - Bugfix Release (October 5, 2025)

### 🐛 Bug Fixed

#### Inconsistency in Article Cache Detection

**Symptom**: The article menu showed "Cache is not available" but viewing the article information indicated that the cache WAS available (status: ready, size > 0).

**Root Cause**:
1. The `hasValidCache()` function considered the cache valid if `cache.status == "ready"` AND `cache.size > 0`, even without the HTML content (`cache.text`) being loaded.
2. The flow in `main.lua` was confusing: it checked `hasValidCache()` before attempting to load the content.
3. According to the Raindrop.io API, the `raindrop` object includes cache metadata (`status`, `size`) but NOT the HTML content. The content requires a separate call to `/raindrop/{id}/cache`.

**Solution**:

1. **Improved `hasValidCache()` in article_manager.lua**:
```lua
// Clearer and more explicit logic
- First, it checks if the cache exists
- Then, it checks if status == "ready"
- If text is already loaded, it verifies that it has >50 characters
- If there is no text but size > 0, it returns true (available for download)
```

2. **Improved `loadCacheContent()` in article_manager.lua**:
```lua
// More robust error handling
- Checks that status == "ready" before attempting to load
- If the load fails, it does NOT set default text
- More descriptive logs for debugging
```

3. **Improved flow in `showRaindropContent()` in main.lua**:
```lua
// Clear separation of concepts
1. cache_available: Is it available? (status == "ready")
2. If available but without text → try to load
3. has_cache: Do we really have content? (text loaded and valid)
```

**Modified files**:
- `article_manager.lua`: `hasValidCache()` and `loadCacheContent()` functions
- `main.lua`: `showRaindropContent()` function

**Result**:
- The menu now correctly reflects if the content is available for immediate use
- Messages are consistent with the actual state of the cache
- Better error handling when content loading fails

### ✅ Verification
- All modules have correct syntax
- More robust and clear cache logic

---

## v1.8.1 - Bugfix Release (October 5, 2025)

### 🐛 Bugs Fixed

#### 1. Error in Dialog Closures (dialogs.lua)
**Symptom**: Crash when clicking any button in the dialogs
```
attempt to index global 'token_dialog' (a nil value)
```

**Cause**: Local variables declared and assigned on the same line are not available to inner closures.

**Solution**: Declare variables before assigning them
```lua
-- BEFORE
local token_dialog = InputDialog:new{...}

-- AFTER
local token_dialog
token_dialog = InputDialog:new{...}
```

**Modified files**:
- `dialogs.lua` lines 28, 103
- Functions: `showTokenDialog()`, `showSearchDialog()`

#### 2. Translation Function Overwrite Error (main.lua)
**Symptom**: Crash when viewing article content
```
attempt to call upvalue '_' (a nil value)
```

**Cause**: Using `_` as a discarded variable name overwrites the gettext `_()` function.

**Solution**: Use a different name for the discarded variable
```lua
-- BEFORE
raindrop, _ = self.article_manager:loadFullArticle(raindrop)

-- AFTER
local err
raindrop, err = self.article_manager:loadFullArticle(raindrop)
```

**Modified files**:
- `main.lua` line 248
- Function: `showRaindropContent()`

### ✅ Verification
- All modules (8/8) have correct syntax
- Known bugs: 0

---

## v1.8 - Ultra Modularization (October 5, 2025)

### 🎯 Objective
To ultra-aggressively reduce `main.lua` to make it easier to work with LLMs.

### ✨ Main Changes

#### Reduction of main.lua
- **v1.6 (original)**: 1571 lines
- **v1.7**: 940 lines (-40%)
- **v1.8**: 455 lines (-71% total, -51% vs v1.7)

#### New Modules Created

**1. ui_builder.lua (280 lines)**
- Construction of all menus
- Collection and article items
- Simple and advanced pagination
- Buttons for viewers

Main functions:
```lua
UIBuilder:buildRaindropItems(raindrops, callback)
UIBuilder:buildCollectionItems(collections, callback)
UIBuilder:buildArticleMenu(raindrop, has_cache, callbacks)
UIBuilder:addPagination(items, data, page, perpage, callback)
UIBuilder:createMenu(title, items)
UIBuilder:buildContentViewerButtons(callbacks)
```

**2. dialogs.lua (231 lines)**
- Management of all dialogs
- Input dialogs (token, search)
- Text viewers (debug, info, content)

Main functions:
```lua
Dialogs:showTokenDialog(current_token, callbacks)
Dialogs:showSearchDialog(on_search, on_cancel)
Dialogs:showDebugInfo(debug_info, server_url)
Dialogs:showArticleInfo(raindrop, formatted_info)
Dialogs:showContentViewer(title, content, buttons)
Dialogs:showLinkInfo(raindrop)
```

**3. article_manager.lua (216 lines)**
- Complete management of article operations
- Loading of full content and cache
- HTML download
- Opening in reader

Main functions:
```lua
ArticleManager:loadFullArticle(raindrop)
ArticleManager:loadCacheContent(raindrop)
ArticleManager:hasValidCache(raindrop)
ArticleManager:reloadArticle(raindrop_id, callback)
ArticleManager:downloadHTML(raindrop)
ArticleManager:openInReader(raindrop, close_callback, return_callback)
ArticleManager:openDownloadFolder(filename, close_callback)
```

### 🏗️ New Architecture

```
main.lua (455L) - PURE COORDINATOR
├── settings.lua (153L) - Configuration
├── api.lua (259L) - Raindrop.io Communication
├── content_processor.lua (293L) - HTML Processing
├── ui_builder.lua (280L) - UI Construction
├── dialogs.lua (231L) - Dialog Management
├── article_manager.lua (216L) - Article Management
└── gota_reader.lua (156L) - ReaderUI Integration
```

### 📊 Benefits for LLM

| Task | Lines v1.6 | Lines v1.8 | Improvement |
|---|---|---|---|
| Modify UI | 1571 | 280 | -82% |
| Change dialogs | 1571 | 231 | -85% |
| Manage articles | 1571 | 216 | -86% |
| Modify API | 1571 | 259 | -84% |
| Process HTML | 1571 | 293 | -81% |
| General coordination | 1571 | 455 | -71% |

### 🎭 Separation of Responsibilities

**main.lua**: Only coordination, delegation, and high-level callbacks
**ui_builder.lua**: Only construction of menus and items
**dialogs.lua**: Only creation and management of dialogs
**article_manager.lua**: Only article operations
**api.lua**: Only HTTP communication
**content_processor.lua**: Only content processing
**settings.lua**: Only configuration persistence
**gota_reader.lua**: Only integration with ReaderUI

---

## v1.7 - First Refactoring (previous)

### 🎯 Objective
To modularize the monolithic code to improve maintainability.

### ✨ Main Changes

#### Reduction of main.lua
- **v1.6 (original)**: 1571 lines
- **v1.7**: 940 lines (-40%)

#### New Modules Created

**1. api.lua (259 lines)**
- All communication with the Raindrop.io API
- Response caching (5-minute TTL)
- Automatic retries
- Gzip decompression
- SSL handling without verification (for e-ink device compatibility)

Main functions:
```lua
API:getUser()
API:getCollections()
API:getRaindrops(collection_id, page, perpage)
API:getRaindrop(raindrop_id)
API:getRaindropCache(raindrop_id)
API:searchRaindrops(search_term, page, perpage)
API:testToken(token)
```

**2. content_processor.lua (293 lines)**
- HTML → Plain text conversion
- Content cleaning (ads, nav, etc.)
- Main content extraction
- HTML generation for the reader
- Formatting of article information

Main functions:
```lua
ContentProcessor:htmlToText(html_content)
ContentProcessor:createReaderHTML(raindrop)
ContentProcessor:formatArticleText(raindrop)
ContentProcessor:formatArticleInfo(raindrop)
```

### 🏗️ Architecture

```
main.lua (940L) - Main orchestrator
├── settings.lua (153L) - Configuration
├── api.lua (259L) - API Communication (NEW)
├── content_processor.lua (293L) - Processing (NEW)
└── gota_reader.lua (156L) - ReaderUI Integration
```

---

## v1.6 and earlier

Original monolithic version with all functionality in `main.lua` (1571 lines).

### Features
- ✅ Raindrop.io token configuration
- ✅ Listing of collections
- ✅ Viewing articles with pagination
- ✅ Searching for articles
- ✅ Viewing content in plain text
- ✅ Opening articles in full reader (HTML)
- ✅ Downloading HTML for offline reading
- ✅ Cache management
- ✅ Article information
- ✅ Copying URLs
- ✅ Debug info

---

## 📊 Evolution Summary

| Version | main.lua | Modules | Features |
|---|---|---|---|
| v1.6 | 1571 L | 4 | Monolithic |
| v1.7 | 940 L (-40%) | 6 | API + Processing separated |
| v1.8 | 455 L (-71%) | 9 | Ultra modular |
| v1.8.1 | 455 L | 9 | Runtime bugfixes |

### Final Metrics v1.8.1

- **Total lines of code**: ~2,049 (not counting backups)
- **Modules**: 9
- **Largest module**: content_processor.lua (293 lines)
- **Smallest module**: _meta.lua (6 lines)
- **All modules**: <300 lines (optimal for LLM)
- **Known bugs**: 0
- **Test coverage**: Manual (automation pending)

---

## 🎓 Lessons Learned

### v1.8.1
1. **Closures and local variables**: Declare variables before using them in callbacks
2. **Reserved names**: Never use `_` as a variable in KOReader (it is the gettext function)
3. **Runtime testing**: Syntax checking is not enough, always test in an emulator

### v1.8
1. **Modules <300 lines**: Ideal size for LLM context
2. **Single Responsibility**: One module, one responsibility
3. **Dependency Injection**: Modules receive what they need in the constructor
4. **Composition**: main.lua composes modules instead of implementing everything

### v1.7
1. **Separation of concerns**: API and processing are independent responsibilities
2. **Smart caching**: 5-minute TTL improves user experience
3. **Error handling**: Retries and clear messages are essential

---

## 🔮 Future Roadmap

### v1.9 (Planned)
- [ ] Automated unit tests
- [ ] CI/CD with GitHub Actions
- [ ] Improvements in persistent cache
- [ ] Support for nested collections
- [ ] Reading status synchronization

### v2.0 (Vision)
- [ ] Support for multiple services (Pocket, Instapaper)
- [ ] Synchronized annotations
- [ ] Improved offline mode
- [ ] Exporting highlights

---

**Maintainer**: Christian Stenger
**License**: MIT
**Last updated**: October 5, 2025

