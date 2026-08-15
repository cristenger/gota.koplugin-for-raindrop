# Gota Plugin for KOReader

A KOReader plugin to access and read your [Raindrop.io](https://raindrop.io) bookmarks directly on your e-reader.

<p align="center">
  <img src="https://img.shields.io/badge/KOReader-Plugin-blue" alt="KOReader Plugin">
  <img src="https://img.shields.io/badge/version-2.3.0-green" alt="Version 2.3.0">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License">
</p>

Important: Notes and highlights work with both free and PRO accounts. However, viewing cached article content (full text/HTML) requires a Raindrop.io PRO subscription.

## Features

- **Browse Collections**: Follow Raindrop groups, root order and nested collections
- **Scoped Search**: Search globally, within a collection, or through its descendants
- **Advanced Search**: E-ink-friendly quick filters, exclusions, dates and content types
- **Read Articles**: View content as plain text or open in full HTML reader
- **Personal Notes**: View your personal notes attached to bookmarks
- **Highlights**: Review highlights globally or by collection without requiring PRO
- **Bookmark Editing**: Update favorite, note, tags and collection; move safely to/from Trash
- **Memory Limits**: Separate configurable limits for text-in-RAM and reader-file downloads
- **Save Offline**: Download HTML articles for offline reading
- **Internationalization**: Automatic language detection with English source strings and a Spanish catalog
- **Configurable**: Customizable download folder with visual folder picker
- **KOReader Compatibility**: Targets KOReader 2026.07 and later

## Installation

### Method 1: Manual Installation

1. Download the latest release or clone this repository
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
4. Tap **Save** (or **Test** to verify first)

*First time shows "NEW: Gota" - this disappears after opening it once.*

### 3. Start Reading!

Once configured, you can:

- **All articles**: Browse all your bookmarks
- **View collections**: Navigate your organized collections
- **Search articles**: Quick text search
- **Advanced search**: Filter by tags and content type
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
- Filter by tags and content type, then use quick filters for favorites, no tags, uploaded files, reminders and available web archives

### Read an Article

Tap any article to see options:
- **Open in full reader**: HTML with formatting (requires Raindrop PRO)
- **View as plain text**: Simple text view (requires Raindrop PRO)
- **View information**: Metadata, tags, URL, cache status, notes, and highlights
- **Show article URL**: Display the article link for manual use
- **Edit bookmark**: Change favorite, note, tags or collection; Trash is guarded against permanent deletion

### Notes and Highlights

When viewing article information, you'll see:
- **Personal Notes**: Your notes about the article
- **Highlights**: Text you've highlighted with color indicators
  - [Yellow] [Blue] [Red] [Green] color tags
  - Highlight-specific notes when available
  
**Important:** Notes and highlights work with both free and PRO accounts. However, viewing cached article content (full text/HTML) requires a **Raindrop.io PRO subscription**.

### Configure Download Folder

`Menu → Gota → Configuration → Configure download folder`

Choose between visual folder picker or manual folder name entry.

## Language Support

The plugin auto-detects your KOReader language:
- **English** (default)
- **Spanish** (Español; legacy entries still need linguistic review)

Change language in: `KOReader Settings → Language`

Want to add your language? See [l10n/README.md](gota.koplugin/l10n/README.md) for translation guide.

## Configuration

- **Access Token**: Configuration → Configure access token (required)
- **Download Folder**: Configuration → Configure download folder (default: `gota_articles/`)
- **Cache Limits**: Configuration → Cache size limits (default: 4 MiB text / 32 MiB reader)
- **Debug**: Configuration → Debug Raindrop API connection (troubleshooting)

## Troubleshooting

### Articles not showing?
1. Check you have articles in Raindrop.io
2. Verify token with "Test" button
3. Try "All articles" to see everything

### "No cached content available"
This means the article's permanent cache is not available. This can happen if:
- You're using a free Raindrop.io account (cache requires PRO)
- The article hasn't been cached yet (PRO users: wait a moment and try "reload")
- The article source doesn't allow caching

### TLS Certificate Limitation on Kindle

Raindrop only provides an HTTPS API. On the supported Kindle runtime, however, remote certificate authentication is not implemented in this flow. Gota inherits KOReader's LuaSec behavior (`verify = "none"` in LuaSec 1.3.2) and does not mutate process-wide TLS state.

Traffic is encrypted but the server is not authenticated, so an active attacker could intercept the Bearer token. Use Gota only on a trusted network. HTTPS URLs remain mandatory, and cache redirects never receive the Raindrop token.

The token field is masked, but the credential is stored as plaintext in KOReader's `settings/gota.lua`. Treat that file as sensitive and do not attach it to public bug reports.

## Development

```bash
# Clone and setup
git clone https://github.com/cristenger/gota.koplugin-for-raindrop.git
cd gota.koplugin-for-raindrop/gota.koplugin

# Check syntax
luac -p *.lua tests/run.lua

# Run the dependency-free regression suite
lua tests/run.lua

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
