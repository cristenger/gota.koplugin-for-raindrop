# Changelog - Gota Plugin for KOReader

## Unreleased - UX and lifecycle hardening

### Added

- Local access-token removal with confirmation and rollback if settings cannot be flushed.
- Direct «Save original copy» from article details and one post-save choice to remain in Gota or open the destination folder.
- Session-only advanced-search state with a visible summary of scope, sort, match mode and active filters.
- Stable article-row identity and source-aware refresh after favorite, note, tag, collection and Trash mutations.
- Spanish catalog audit for missing/fuzzy entries, printf placeholders and unexplained source-equal translations.

### Changed

- Article and highlight rows now use natural wrapping instead of forced newlines; status badges are written out and remote pagination is available above and below the list.
- Manual download paths preserve valid spaces and nested folders, reject unsafe input without replacing it with a default, and ask before applying sanitizer changes.
- Annotated exports convert remote article markup to escaped plain text. Original copies remain byte-faithful web content and are identified separately.
- Spanish UI terminology now consistently distinguishes copia web, copia original, archivo temporal and resaltados.

### Fixed

- Temporary ReaderUI files are cleaned through `CloseDocument` and startup recovery with an exact canonical-path/name allowlist; `.sdr` sidecars and permanent exports are preserved.
- Successful bookmark edits close stale detail/collection screens and reload their authoritative source page; failures keep the current detail open.
- The token dialog and debug view state the actual TLS limitation: encryption is available, remote certificate/hostname authentication is not.

### Validation and open gates

- Expanded the dependency-free suite from 51 to 66 cases and validated plugin startup with the isolated KOReader 2026.07 macOS runtime.
- Cancellable `Trapper` migration remains gated on live-account cancellation and physical Kindle/Kobo memory tests; bounded synchronous networking remains the documented fallback.
- No release version bump is included until live Raindrop and physical-device gates pass.

---

## v2.3.0 - Raindrop capabilities for e-readers (August 15, 2026)

### Added

- Raindrop collection groups, remote root ordering, child ordering and session-only collapse state.
- Global and per-collection highlight views with open pagination and related-article navigation.
- Collection-scoped and nested search, relevance sorting for text, chronological filter-only search, and domain sorting.
- E-ink-friendly quick filters for favorites, untagged items, uploaded files, reminders, ready web archives, exclusions, dates and OR matching.
- User statistics for All, Unsorted and Trash, plus informational broken/duplicate counts.
- Article metadata for broken links, favorites, update/reminder dates, files, creators and permanent-copy creation.
- Reversible editing of favorite, note, tags and collection, plus guarded move-to-Trash and restore/move flows.
- Configurable text-memory (2–16 MiB) and reader-file (16–128 MiB) cache limits.

### Fixed

- Permanent-copy HTML is no longer downloaded when opening an article menu or refreshing metadata.
- Reader HTML streams to an atomic temporary file with both `cache.size` preflight and a hard chunk-level limit.
- Mutating requests are never retried automatically; reads retain bounded retry behavior.
- List/search pagination accepts Raindrop responses without the undocumented `count` field.
- Advanced search uses one popularity-sorted `/filters` request and no longer mutates cached response tables.
- Trash code refuses a `DELETE` when the current item is already in Trash, preventing accidental permanent deletion.

### Validation

- Expanded the dependency-free regression suite from 34 to 51 cases.
- Revalidated endpoints, shapes and operators against Raindrop REST v1 and KOReader 2026.07 sources.

### Known limitations

- Network calls remain synchronous while online and can block until the bounded timeout.
- Direct raw-HTML opening still needs smoke testing on physical Kindle/Kobo/PocketBook devices.
- Uploaded-file downloading and bookmark creation remain gated for a later release.

---

## v2.2.0 - Architecture and Compatibility (August 14, 2026)

### Security

- Preserved Kindle-compatible LuaSec HTTPS behavior while removing the ineffective process-wide `cert_verify` assignment; certificate authentication remains unavailable and is documented as an accepted risk.
- API base URLs and permanent-cache redirects now require HTTPS.
- Cache redirects are followed explicitly without forwarding the Raindrop Bearer token to storage hosts.
- The access-token field now uses KOReader's password input mode. The token is still stored as plaintext in `settings/gota.lua`.

### Fixed

- Preserved valid UTF-8, including accented text, CJK, emoji and combining marks; malformed sequences are replaced safely.
- Updated `ReaderUI:showReader` and `switchDocument` calls to their current signatures.
- Removed the leaked `DocumentRegistry:openDocument` preflight and direct reader-menu injection.
- Registered Dispatcher actions during plugin initialization.
- Moved type/favorite filters into Raindrop's `search` expression and quoted tags containing spaces.
- Separated cache metadata, downloaded HTML and download errors; reload now bypasses stale metadata and fetches `/cache` explicitly.
- Enabled notes/highlights export without Raindrop PRO article HTML.
- Added nested collections using `/collections` plus `/collections/childrens`.
- Added explicit 307 handling, safe JSON decoding, remote error details, and retries for transport failures, 429 and 5xx.
- Replaced external gzip commands with `Accept-Encoding: identity`.
- Validated pagination, identifiers and response envelopes; rejected empty cache downloads and non-redirect 304 responses.
- Avoided long 429 sleeps on KOReader's UI thread while retaining short bounded retries.
- Detached permanent HTML from the API response cache and released it after CREngine opened the local file.
- Added atomic HTML writes, DataStorage path confinement, UTF-8-safe filenames/excerpts and preserved `<pre>` whitespace.
- Separated transient ReaderUI files under `DataStorage/cache/gota` so opening an article cannot overwrite an exported HTML.
- Added D-pad-safe disabled rows, Cancel controls and long-press handling, plus the documented `audio` search type.

### Architecture and Validation

- Added `ARCHITECTURE.md` and implementation status to the architecture review.
- Centralized version and compatibility metadata in `gota_version.lua`.
- Prefixed internal module filenames with `gota_` to avoid collisions in KOReader's global `package.loaded` table.
- Declared KOReader 2026.07+ as the compatibility target.
- Added `tests/run.lua`, a 34-case suite runnable without a KOReader checkout.
- Added GitHub Actions validation with Lua 5.1 syntax/tests and gettext catalog checks.
- Declared `settings_file` for KOReader's plugin-management lifecycle.

### Known Limitations

- Network calls remain synchronous and may block the UI until their timeout or retry delay.
- OAuth/refresh tokens and real-device testing remain future work.
- Very large permanent-cache HTML still has no hard memory cap; Raindrop collection groups are not rendered.
- The Spanish catalog is structurally valid, but legacy entries that still match English need linguistic review.

---

## v2.1.0 - Highlights Display (November 5, 2025)

### Added
- **Highlights Display**: View all your Raindrop.io highlights directly in article information
  - Shows highlight text with color indicators ([Yellow], [Blue], [Red], [Green])
  - Displays highlight-specific notes when available
  - Automatic numbering of highlights for easy reference
  - Separator line for clear visual organization

### Fixed
- **Spanish Translations**: Fixed missing translations for "Notes:", "Excerpt:", "Tags:", and "Cache:"
  - `Notes:` → `Notas:`
  - `Excerpt:` → `Extracto:`
  - `Tags:` → `Etiquetas:`
  - `Cache:` → `Caché:`

### Technical
- Modified `content_processor.lua`: Added highlight formatting logic (~35 lines)
- Updated translation files with new string "Highlights:" / "Resaltados:"
- Total strings: 133 unique (was 132)
- No breaking changes - purely additive feature
- Graceful degradation when no highlights exist

---

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
- Automatic detection of KOReader's language
- English as the default language (source language)
- Full Spanish translation (126 strings)
- Ready to easily add more languages

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

### UI Simplification

**Change**: The redundant "Download HTML" option has been removed from the article menu.

**Before**:
- "Open in full reader" → Saved a temporary file and opened it in the reader
- "Download HTML" → Saved a permanent file and showed options

**Now**:
- "Open in full reader" → Saves a permanent file and opens it in the reader
- Same functionality, simpler interface

**Benefits**:
- Cleaner menu (3 options instead of 4)
- More intuitive behavior
- Files are always saved permanently
- Code reduction (~60 lines removed)

**Affected Files**:
- `article_manager.lua`: Removed `downloadHTML()` and `openDownloadFolder()` functions
- `ui_builder.lua`: Removed "Download HTML" option from the menu
- `main.lua`: Removed `download_html` callback and `showDownloadOptions()` function

**Updated Statistics**:
- Total unique strings: **127** (+2 vs advanced search)
- Total occurrences: **151** (+2 vs advanced search)

### UX Improvements

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
- Frequently used options at the top
- Configuration grouped in a submenu
- Logical order: view → search → configure
- More descriptive name for debug

**Full Screen in Searches**:
- Search results now take up the full screen
- Consistent with collections and "All articles"
- Better reading experience

### Advanced Search with Filters

**New Feature**: Advanced search system with contextual filters.

**Features**:
- New "Advanced search" option in the main menu
- Filtering by **tags** (user tags)
- Filtering by **type** (article, image, video, document)
- Combination of text search + filters
- Shows popular tags with a counter
- Shows available types with a counter
- Results title indicates active filters

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
GET /raindrops/0?search=X%20%23tag%20type%3AZ
```

**Benefits**:
- More precise and contextual search
- Content discovery by tags
- Filtering by content type
- Experience similar to the official Raindrop app
- Keeps simple search for quick cases

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
- All articles are saved in the same folder
- Configurable folder according to user preferences
- Path relative to DataDir (typically `koreader/`)
- Persistent settings between sessions

#### Internationalization (i18n) Review

**Verification**: Checked that all UI strings correctly use the gettext `_()` function
- `dialogs.lua`: All buttons and texts use `_()`
- `menu_builder.lua`: All menu items use `_()`
- `main.lua`: All notifications and messages use `_()`

**Default language**: Spanish (source language)
**Future support**: The plugin is ready for translations into other languages using KOReader's `.po` files

---

## v1.8.2 - Bugfix Release (October 5, 2025)

### Bug Fixed

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

### Verification
- All modules have correct syntax
- More robust and clear cache logic

---

## v1.8.1 - Bugfix Release (October 5, 2025)

### Bugs Fixed

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

### Verification
- All modules (8/8) have correct syntax
- Known bugs: 0

---

## v1.8 - Ultra Modularization (October 5, 2025)

### Objective
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

### Benefits for LLM

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

### Objective
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
- Raindrop.io token configuration
- Listing of collections
- Viewing articles with pagination
- Searching for articles
- Viewing content in plain text
- Opening articles in full reader (HTML)
- Downloading HTML for offline reading
- Cache management
- Article information
- Copying URLs
- Debug info

---

## Evolution Summary

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
