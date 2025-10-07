# 📚 Gota Plugin for KOReader

A KOReader plugin to access and read your [Raindrop.io](https://raindrop.io) bookmarks directly on your e-reader.

<p align="center">
  <img src="https://img.shields.io/badge/KOReader-Plugin-blue" alt="KOReader Plugin">
  <img src="https://img.shields.io/badge/version-2.0.0-green" alt="Version 2.0.0">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License">
</p>

## ✨ Features

- 📖 **Browse Collections**: Navigate your Raindrop collections with full pagination
- 🔍 **Simple Search**: Quick text-based article search
- 🎯 **Advanced Search**: Filter by tags and content types (article/image/document)
- 📄 **Read Articles**: View content as plain text or open in full HTML reader
- 💾 **Save Offline**: Download HTML articles for offline reading
- 🌍 **Internationalization**: Automatic language detection (English/Spanish supported)
- ⚙️ **Configurable**: Customizable download folder with visual folder picker
- 📱 **Multi-Device**: Works on any device that supports KOReader

## 📦 Installation

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

## 🚀 Quick Start

### 1. Get Your Raindrop.io Test Token

1. Go to [Raindrop.io App Management Console](https://app.raindrop.io/settings/integrations)
2. Click **"Create new app"** (or open an existing app)
3. Give it a name (e.g., "KOReader")
4. Copy the **"Test token"** from your app settings

✅ **Why Test Tokens?** No setup required, never expires, secure, and perfect for e-readers.

⚠️ OAuth tokens are not supported (require web browser).

### 2. Configure the Plugin

1. Open KOReader
2. Go to: **☰ Menu → Gota → Configuration → Configure access token**
3. Paste your token
4. Tap **Save** (or **Test** to verify first)

*Note: First time shows "NEW: Gota" - this disappears after opening it once.*

### 3. Start Reading!

Once configured, you can:

- **All articles**: Browse all your bookmarks
- **View collections**: Navigate your organized collections
- **Search articles**: Quick text search
- **Advanced search**: Filter by tags and content type

## 📖 Usage Guide

### Browse Collections

```
Menu → Gota → View collections
```
Shows all your Raindrop collections with article counts and pagination.

### Search Articles

**Simple Search:** `Menu → Gota → Search articles`
- Enter any search term to find matching articles

**Advanced Search:** `Menu → Gota → Advanced search`
- Filter by tags (e.g., `#programming`) or content type (article/image/document)

### Read an Article

Tap any article to see options:
- **Open in full reader**: HTML with formatting
- **View as plain text**: Simple text view
- **View information**: Metadata, tags, URL, cache status
- **Copy URL**: Copy article link

### Configure Download Folder

`Menu → Gota → Configuration → Configure download folder`

Choose between visual folder picker or manual folder name entry.

## 🌍 Language Support

The plugin auto-detects your KOReader language:
- **English** (default)
- **Español** (Spanish)

Change language in: `KOReader Settings → Language`

Want to add your language? See [l10n/README.md](l10n/README.md) for translation guide.

## ⚙️ Configuration

- **Access Token**: Configuration → Configure access token (required)
- **Download Folder**: Configuration → Configure download folder (default: `gota_articles/`)
- **Debug**: Configuration → Debug Raindrop API connection (troubleshooting)

## 🔧 Troubleshooting

**Articles not showing?**
1. Check you have articles in Raindrop.io
2. Verify token with "Test" button
3. Try "All articles" to see everything

**SSL Note**: SSL verification is disabled for e-reader compatibility.

## 🏗️ Development

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

## 📄 License

MIT License - see [LICENSE](LICENSE) file

## 🙏 Acknowledgments

- [KOReader](https://github.com/koreader/koreader) - The amazing e-reader software
- [Raindrop.io](https://raindrop.io) - Excellent bookmark management service
- All contributors and testers

---

<p align="center">
  Made with ❤️ for KOReader users
</p>

<p align="center">
  <a href="https://raindrop.io">
    <img src="https://img.shields.io/badge/Powered%20by-Raindrop.io-5340ff" alt="Powered by Raindrop.io">
  </a>
  <a href="https://koreader.rocks">
    <img src="https://img.shields.io/badge/Built%20for-KOReader-orange" alt="Built for KOReader">
  </a>
</p>
