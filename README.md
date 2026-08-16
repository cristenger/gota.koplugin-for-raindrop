# Gota Plugin for KOReader

A KOReader plugin to access and read your [Raindrop.io](https://raindrop.io) bookmarks directly on your e-reader.

<p align="center">
  <img src="https://img.shields.io/badge/KOReader-Plugin-blue" alt="KOReader Plugin">
  <img src="https://img.shields.io/badge/version-2.3.0-green" alt="Version 2.3.0">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License">
</p>

Important: Notes and highlights work with both free and PRO accounts. However, viewing Raindrop's web copy (full text/HTML) requires a Raindrop.io PRO subscription.

## Features

- **Browse Collections**: Follow Raindrop groups, root order and nested collections
- **Scoped Search**: Search globally, within a collection, or through its descendants
- **Advanced Search**: Session-preserved filters with a visible scope, sort and match summary
- **Read Articles**: View content as plain text or open in full HTML reader
- **Personal Notes**: View your personal notes attached to bookmarks
- **Highlights**: Review highlights globally or by collection without requiring PRO
- **Bookmark Editing**: Update favorite, note, tags and collection; move safely to/from Trash
- **Memory Limits**: Separate configurable limits for text-in-RAM and reader-file downloads
- **Save Offline**: Save a byte-faithful original copy or a safer text-based annotated export
- **Internationalization**: Automatic language detection with English source strings and a Spanish catalog
- **Configurable**: Customizable download folder with visual folder picker
- **KOReader Compatibility**: Targets KOReader 2026.07 and later

## Installation

### Method 1: Manual Installation

1. Download the repository as a ZIP from GitHub, or clone it
2. Copy the `gota.koplugin` folder to your KOReader plugins directory
3. Restart KOReader

### Method 2: From Source

```bash
git clone https://github.com/cristenger/gota.koplugin-for-raindrop.git
cd gota.koplugin-for-raindrop
cp -r gota.koplugin /path/to/koreader/plugins/
```

## Quick Start

### 1. Get Your Raindrop.io Test Token

1. Go to [Raindrop.io App Management Console](https://app.raindrop.io/settings/integrations)
2. Click **"Create new app"** (or open an existing app)
3. Give it a name (e.g., "KOReader")
4. Copy the **"Test token"** from your app settings

**Why Test Tokens?** They need no OAuth callback flow and do not expire. Treat them as long-lived passwords.

**Note:** The OAuth access/refresh flow is not implemented. Gota currently supports the personal test-token workflow above.

### 2. Configure the Plugin

1. Open KOReader
2. Go to: **Menu → Gota → Configuration → Configure access token**
3. Paste your token
4. Select **Save** (or **Test** to verify first)

The token remains plaintext in KOReader's local `settings/gota.lua`. Use **Configuration → Remove access token** to erase Gota's local copy; revocation must still be done in Raindrop.io.

### 3. Start Reading!

Once configured, you can:

- **All articles**: Browse all your bookmarks
- **View collections**: Navigate your organized collections
- **Search articles**: Quick text search
- **Advanced search**: Combine tags, types, quick filters, exclusions and dates
- **All highlights**: Review highlights across the library

## Usage Guide

### Browse Collections

```
Menu → Gota → View collections
```
Shows Raindrop groups, ordered roots and nested collections. All, Unsorted and Trash include counts when statistics are available. Selecting a user collection also offers scoped search and highlights.

### Search Articles

**Simple Search:** `Menu → Gota → Search articles`
- Enter any search term to find matching articles

**Advanced Search:** `Menu → Gota → Advanced search`
- Search by text, tag or content type (`article`, `image`, `video`, `audio` or `document`)
- **Quick filters** includes favorites, items without tags, uploaded files, reminders and available web archives; filters can be combined with OR
- **More filters** can exclude a tag or type and filter by creation or update date

### Read an Article

Select any article to see its available actions:
- **Open in full reader**: HTML with formatting (requires Raindrop PRO)
- **View as plain text**: Simple text view (requires Raindrop PRO)
- **View information**: Metadata, tags, URL, web-copy status, notes, and highlights
- **Show article URL**: Display the article link for manual use
- **Edit bookmark**: Change favorite, note, tags or collection; Trash is guarded against permanent deletion
- **Save original copy**: Stream Raindrop's byte-faithful web copy directly to disk without first loading it into RAM
- **Export with notes & highlights**: Create a Gota-owned text-based HTML export when the bookmark has a note or highlights
- **Reload article metadata**: Refresh web-copy state and bookmark details without downloading the full HTML

### Notes and Highlights

When viewing article information, you'll see:
- **Personal Notes**: Your notes about the article
- **Highlights**: Text you've highlighted with color indicators
  - Color labels for all 12 colors supported by Raindrop
  - Highlight-specific notes when available

Use **All highlights** to review the whole library. A collection's action menu also provides a highlights-only view. When Raindrop includes the related bookmark, Gota can open it directly from the highlight menu.
  
**Important:** Notes and highlights work with both free and PRO accounts. However, viewing Raindrop's web copy (full text/HTML) requires a **Raindrop.io PRO subscription**.

### Configure Download Folder

`Menu → Gota → Configuration → Configure download folder`

Choose between the visual picker—long-press a folder name to select it—or manual relative-path entry. Manual paths may contain spaces and nested segments; Gota shows sanitizer changes before saving and confines the result to KOReader's data directory.

### Save Articles Offline

Open an article and select **Save original copy** to download Raindrop's permanent web copy. If it has a note or highlights, **Export with notes & highlights** creates an annotated file directly from the same menu. A successful save stays in Gota unless you explicitly choose **Open folder**.

Original-copy downloads require Raindrop PRO and are limited by the configured reader-file size. They preserve remote HTML and may therefore contain code or resources from the source site. Annotated exports convert the article body to escaped plain text and prioritize safety/readability over visual fidelity; notes-only and highlights-only exports remain available without PRO content.

## Language Support

The plugin auto-detects your KOReader language:
- **English** (default)
- **Spanish** (Español; legacy entries still need linguistic review)

Change language in: `KOReader Settings → Language`

Want to add your language? See [l10n/README.md](gota.koplugin/l10n/README.md) for translation guide.

## Configuration

- **Access Token**: Configuration → Configure access token (required)
- **Download Folder**: Configuration → Configure download folder (default: `gota_articles/`)
- **Sort Order**: Newest, oldest, title, domain or Raindrop custom order
- **Content Limits**: 2–16 MiB for in-memory text and 16–128 MiB for reader/file downloads (default: 4 MiB / 32 MiB)
- **Debug**: Configuration → Debug Raindrop API connection (troubleshooting)

## Troubleshooting

### Articles not showing?
1. Check you have articles in Raindrop.io
2. Verify token with "Test" button
3. Try "All articles" to see everything

### "No web copy text is loaded"
This means Raindrop's web copy is unavailable or has not been loaded into Gota's bounded text memory. This can happen if:
- You're using a free Raindrop.io account (web copies require PRO)
- Raindrop has not generated the web copy yet (PRO users: wait a moment and reload the metadata)
- The article source doesn't allow caching

### TLS Certificate Limitation on Kindle

Raindrop only provides an HTTPS API. On the supported Kindle runtime, however, remote certificate authentication is not implemented in this flow. Gota inherits KOReader's LuaSec behavior (`verify = "none"` in LuaSec 1.3.2) and does not mutate process-wide TLS state.

Traffic is encrypted but the server is not authenticated, so an active attacker could intercept the Bearer token. Use Gota only on a trusted network. HTTPS URLs remain mandatory, and web-copy redirects never receive the Raindrop token.

The token field is masked, but the credential is stored as plaintext in KOReader's `settings/gota.lua`. Treat that file as sensitive and do not attach it to public bug reports.

## Development

```bash
# Clone and setup
git clone https://github.com/cristenger/gota.koplugin-for-raindrop.git
cd gota.koplugin-for-raindrop/gota.koplugin

# Check Lua 5.1 syntax
luac5.1 -p *.lua tests/run.lua

# Run the dependency-free regression suite
lua5.1 tests/run.lua
luajit tests/run.lua

# Validate localization scripts and the Spanish catalog
python3 -m py_compile extract_strings.py replace_strings.py tests/check_translations.py
msgfmt --check -o /dev/null l10n/es/gota.po
python3 tests/check_translations.py
git diff --check

# Update translations
python3 extract_strings.py
./compile_translations.sh
```

## Architecture

```
gota.koplugin/
├── main.lua                  # Plugin coordinator
├── gota_api.lua              # Raindrop.io API client
├── gota_settings.lua         # Configuration management
├── gota_dialogs.lua          # UI dialogs
├── gota_ui_builder.lua       # Menu construction
├── gota_content_processor.lua # HTML processing
├── gota_article_manager.lua  # Article operations
├── gota_reader.lua           # Reader integration
├── gota_version.lua          # Version and compatibility metadata
├── ARCHITECTURE.md           # Maintained architecture and contracts
├── tests/run.lua             # Dependency-free regression tests
├── l10n/                     # Translations
│   ├── templates/gota.pot    # Translation template
│   └── es/gota.po           # Spanish translation
└── _meta.lua                 # Plugin metadata
```

See [ARCHITECTURE.md](gota.koplugin/ARCHITECTURE.md) for lifecycle, data flows, security boundaries, Raindrop contracts, validation and known limitations.

## Disclaimer

**This plugin is not affiliated with, endorsed by, or connected to Raindrop.io in any way.** This is an independent, unofficial plugin developed by the community.

**No Warranty:** This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose and noninfringement. The authors and contributors are not responsible for any issues, data loss, or service interruptions that may occur from using this plugin.

**Third-Party Services:** This plugin relies on the Raindrop.io API and services, which are subject to their own terms of service, availability, and changes. The plugin developers have no control over Raindrop.io's services, API changes, or service availability.

**Use at Your Own Risk:** By using this plugin, you acknowledge that you are using it at your own risk and that the developers assume no liability for any damages or losses resulting from its use.

## License

MIT License - see [LICENSE](gota.koplugin/LICENSE) file

## Acknowledgments

- [KOReader](https://github.com/koreader/koreader) - The amazing e-reader software
- [Raindrop.io](https://raindrop.io) - Excellent bookmark management service
- All contributors and testers

---

<p align="center">
  <a href="https://raindrop.io">
    <img src="https://img.shields.io/badge/Powered%20by-Raindrop.io-5340ff" alt="Powered by Raindrop.io">
  </a>
  <a href="https://koreader.rocks">
    <img src="https://img.shields.io/badge/Built%20for-KOReader-orange" alt="Built for KOReader">
  </a>
</p>
