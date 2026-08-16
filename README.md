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
- **Read Articles**: View cleaned plain text or use the full HTML reader; gzip responses are handled automatically
- **Personal Notes**: View your personal notes attached to bookmarks
- **Highlights**: Review highlights globally or by collection without requiring PRO
- **Bookmark Editing**: Update favorite, note, tags and collection; move safely to/from Trash
- **Content Limits**: Separate presets up to 64 MiB for text-in-RAM and 512 MiB for reader-file downloads
- **Read Offline**: Download an article to your folder and resume it later at the page where you stopped, or create a safer text-based annotated export
- **Internationalization**: Automatic language detection with English source strings and a Spanish catalog
- **Configurable**: Customizable export folder with visual folder picker
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
- **Open in full reader**: HTML with formatting, keeping structure, images, lists, tables and code (requires Raindrop PRO). Gota bounds extreme publisher font sizes so headings stay slightly larger than body text instead of several times larger, and hides interactive page elements such as navigation bars and forms. The downloaded file itself is not modified.
- **View as plain text**: Removes scripts, styles and page chrome while keeping article prose and code examples (requires Raindrop PRO)
- **View information**: Metadata, tags, URL, web-copy status, notes, and highlights
- **Show article URL**: Display the article link for manual use
- **Edit bookmark**: Change favorite, note, tags or collection; Trash is guarded against permanent deletion
- **Continue reading**: Reopen an article you already downloaded, at the page where you stopped. Shown with the percentage read, and available even when Raindrop no longer serves the web copy
- **Download to read offline**: Stream Raindrop's byte-faithful web copy directly to disk without first loading it into RAM, and keep it in your export folder. Becomes **Update offline copy** once a copy exists
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

### Configure Export Folder

`Menu → Gota → Configuration → Configure export folder`

This folder holds the files Gota keeps: **Download to read offline** and **Export with notes & highlights**. It is not used by **Open in full reader**, which streams the article to a temporary file and removes it when you close the document.

Choose between the visual picker—long-press a folder name to select it—or manual relative-path entry. Manual paths may contain spaces and nested segments; Gota shows sanitizer changes before saving and confines the result to KOReader's data directory.

### Save Articles Offline

Open an article and select **Download to read offline** to download Raindrop's permanent web copy into your export folder. If it has a note or highlights, **Export with notes & highlights** creates an annotated file directly from the same menu. After saving you can choose **Read now**, **Stay in Gota** or **Open folder**.

Once downloaded, the article's menu shows **Continue reading** with how far you got. Selecting it reopens the saved file at that position, so you can put the device down mid-article and pick it up later without downloading anything again. Downloading the same article a second time updates that file in place, which is what keeps your position.

Original-copy downloads require Raindrop PRO and are limited by the configured reader-file size. They preserve remote HTML and may therefore contain code or resources from the source site. Annotated exports convert the article body to escaped plain text and prioritize safety/readability over visual fidelity; notes-only and highlights-only exports remain available without PRO content.

## Language Support

The plugin auto-detects your KOReader language:
- **English** (default)
- **Spanish** (Español; legacy entries still need linguistic review)

Change language in: `KOReader Settings → Language`

Want to add your language? See [l10n/README.md](gota.koplugin/l10n/README.md) for translation guide.

## Configuration

- **Access Token**: Configuration → Configure access token (required)
- **Export Folder**: Configuration → Configure export folder (default: `gota_articles/`); used by saved copies and annotated exports, not by the full reader
- **Sort Order**: Newest, oldest, title, domain or Raindrop custom order
- **Content Limits**: 2–64 MiB for in-memory text and 16–512 MiB for reader/file downloads (new-install default: 16 MiB / 128 MiB; existing selections are preserved)
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

### A web copy exceeds the text limit

The plain-text action keeps the complete HTML in RAM, so it uses the smaller text limit. Gota now reports the exact cause and size instead of a combined unavailable/size message. Use **Open in full reader** for a larger streamed file, or raise the text limit under **Configuration → Content limits**. Tapping the plain-text action again is an explicit retry after a previous download error.

The limit applies to the downloaded, decompressed HTML before scripts, styles and page chrome are removed. Sanitization therefore does not allow a response larger than the selected 2–64 MiB cap.

Gota asks Raindrop for an identity response but also decodes gzip in-process when a storage server returns it anyway. The configured limit applies to decompressed bytes. Other encodings are rejected with their name and leave no partial reader file behind.

### An article I opened in the full reader is not in my export folder

That is expected. **Open in full reader** is a quick look: it writes a temporary file under `cache/gota/` and deletes it when you close the document, so opening an article never overwrites a copy you saved on purpose and large web copies do not accumulate silently. It also does not remember your position, because the file is gone.

Use **Download to read offline** when you want to keep the article and finish it later. That writes to your export folder, and afterwards the menu offers **Continue reading** with your progress. **Export with notes & highlights** also writes there, as an annotated text export.

### Text in the full reader looks too big, too small or uneven

Gota applies a readability policy before the article is first rendered: body text follows KOReader's base font size, headings stay within a bounded range above it, and code, tables and sub/superscripts have explicit floors. Everything is expressed relative to your base size, so raising or lowering it in Typesetting scales the whole document together.

Two things deliberately override that policy:

- If you already enabled **Ignore publisher font sizes** or **Reset main text font size** under Style tweaks, Gota detects it and does not add a second sizing policy.
- If you change any Style tweak while reading, KOReader rebuilds the stylesheet with your settings and Gota does not reapply its own. Use Style tweaks whenever you want full editorial control.

If a site still shows menus, banners or other page chrome, that is an accepted limit: the policy only hides interactive elements such as navigation and forms, not layout built from generic `div` containers. Use **View as plain text** when you want extraction rather than fidelity.

This is a presentation policy, not sanitization. The remote HTML stays in the downloaded file and remains untrusted content.

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
├── gota_compression.lua      # Bounded in-process gzip decoding
├── gota_settings.lua         # Configuration management
├── gota_dialogs.lua          # UI dialogs
├── gota_ui_builder.lua       # Menu construction
├── gota_content_processor.lua # HTML processing
├── gota_article_manager.lua  # Article operations
├── gota_reader.lua           # Reader integration
├── gota_reader_styles.lua    # Full-reader presentation stylesheet
├── gota_offline_library.lua  # Locating downloaded offline copies
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
