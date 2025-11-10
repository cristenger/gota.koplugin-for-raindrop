# Gota Plugin for KOReader

A KOReader plugin to access and read your [Raindrop.io](https://raindrop.io) bookmarks directly on your e-reader.

<p align="center">
  <img src="https://img.shields.io/badge/KOReader-Plugin-blue" alt="KOReader Plugin">
  <img src="https://img.shields.io/badge/version-2.1.0-green" alt="Version 2.1.0">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License">
</p>

## Features

- **Browse Collections**: Navigate your Raindrop collections with full pagination
- **Simple Search**: Quick text-based article search
- **Advanced Search**: Filter by tags and content types (article/image/video/document)
- **Read Articles**: View content as plain text or open in full HTML reader
- **Personal Notes**: View your personal notes attached to bookmarks
- **Highlights**: Access your article highlights
- **Save Offline**: Download HTML articles for offline reading
- **Internationalization**: Automatic language detection (English/Spanish supported)
- **Configurable**: Customizable download folder with visual folder picker
- **Multi-Device**: Works on any device that supports KOReader

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

**Why Test Tokens?** No setup required, never expires, secure, and perfect for e-readers.

**Note:** OAuth tokens are not supported (require web browser).

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

## Usage Guide

### Browse Collections

```
Menu → Gota → View collections
```
Shows all your Raindrop collections with article counts and pagination.

### Search Articles

**Simple Search:** `Menu → Gota → Search articles`
- Enter any search term to find matching articles

**Advanced Search:** `Menu → Gota → Advanced search`
- Filter by tags (e.g., `#programming`) or content type (article/image/video/document)

### Read an Article

Tap any article to see options:
- **Open in full reader**: HTML with formatting (requires Raindrop PRO)
- **View as plain text**: Simple text view (requires Raindrop PRO)
- **View information**: Metadata, tags, URL, cache status, notes, and highlights
- **Copy URL**: Copy article link

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
- **Spanish** (Español)

Change language in: `KOReader Settings → Language`

Want to add your language? See [l10n/README.md](gota.koplugin/l10n/README.md) for translation guide.

## Configuration

- **Access Token**: Configuration → Configure access token (required)
- **Download Folder**: Configuration → Configure download folder (default: `gota_articles/`)
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

### SSL Certificate Issues

**Important:** SSL verification is disabled by default to prevent certificate errors on e-ink devices.

This is necessary because many e-readers have outdated certificate stores and cannot verify modern SSL certificates. The plugin disables SSL verification to ensure reliable connections to Raindrop.io API.

**Security note:** While this reduces security slightly, it's a necessary compromise for e-reader compatibility. Your access token is still transmitted over HTTPS encryption.

## Development

```bash
# Clone and setup
git clone https://github.com/cristenger/gota.koplugin-for-raindrop.git
cd gota.koplugin-for-raindrop/gota.koplugin

# Check syntax
luac -p *.lua

# Update translations
python3 extract_strings.py
./compile_translations.sh
```

## Architecture

```
gota.koplugin/
├── main.lua                  # Plugin coordinator
├── api.lua                   # Raindrop.io API client
├── settings.lua              # Configuration management
├── dialogs.lua               # UI dialogs
├── ui_builder.lua            # Menu construction
├── content_processor.lua     # HTML processing
├── article_manager.lua       # Article operations
├── gota_reader.lua           # Reader integration
├── l10n/                     # Translations
│   ├── templates/gota.pot    # Translation template
│   └── es/gota.po           # Spanish translation
└── _meta.lua                 # Plugin metadata
```

## Disclaimer

**This plugin is not affiliated with, endorsed by, or connected to Raindrop.io in any way.** This is an independent, unofficial plugin developed by the community.

**No Warranty:** This software is provided "as is", without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose and noninfringement. The authors and contributors are not responsible for any issues, data loss, or service interruptions that may occur from using this plugin.

**Third-Party Services:** This plugin relies on the Raindrop.io API and services, which are subject to their own terms of service, availability, and changes. The plugin developers have no control over Raindrop.io's services, API changes, or service availability.

**Use at Your Own Risk:** By using this plugin, you acknowledge that you are using it at your own risk and that the developers assume no liability for any damages or losses resulting from its use.

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
