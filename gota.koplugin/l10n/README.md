# 🌍 Internationalization Guide

This directory contains translation files for the Gota plugin.

## Structure

```
l10n/
├── templates/
│   └── gota.pot          # Translation template (source: English)
└── <language_code>/
    ├── gota.po           # Human-readable translations
    └── gota.mo           # Compiled binary (used by KOReader)
```

## Supported Languages

- **English** (en) - Default source language
- **Español** (es) - Spanish translation

## Adding a New Translation

### 1. Create Language Directory

```bash
mkdir -p l10n/<language_code>
```

Use ISO 639-1 codes:
- `fr` - French
- `de` - German
- `it` - Italian
- `pt` - Portuguese
- `ru` - Russian
- `zh` - Chinese
- `ja` - Japanese
- etc.

### 2. Copy Template

```bash
cp l10n/templates/gota.pot l10n/<language_code>/gota.po
```

### 3. Translate Strings

Edit `l10n/<language_code>/gota.po` and translate the `msgstr` fields:

```po
# English (source)
msgid "Configure access token"

# Your translation
msgstr "Votre traduction ici"
```

**Important Notes**:
- Keep placeholders like `%s`, `%d` in the same position
- Preserve newlines (`\n`) and special characters
- Use UTF-8 encoding
- Translate contextually (consider UI space constraints)

### 4. Update Header Information

In your `.po` file, update:
- `Language` field
- `Last-Translator` with your name/email
- `Language-Team` if applicable

Example:
```po
"Language: fr\n"
"Last-Translator: Your Name <your.email@example.com>\n"
```

### 5. Compile Translation

```bash
# Compile specific language
./compile_translations.sh <language_code>

# Or compile all languages
./compile_translations.sh
```

This creates the `.mo` binary file that KOReader uses at runtime.

## Translation Statistics

Total unique strings: **126**

Distribution by module:
- `main.lua`: 37 strings
- `dialogs.lua`: 27 strings
- `ui_builder.lua`: 26 strings
- `content_processor.lua`: 26 strings
- `article_manager.lua`: 16 strings
- `api.lua`: 7 strings
- `gota_reader.lua`: 5 strings
- `_meta.lua`: 2 strings

## Testing Translations

1. Install the plugin in KOReader
2. Change KOReader's language to your target language:
   - Settings → Language → Select your language
3. Restart KOReader
4. Open the Gota plugin and verify translations

## Updating Existing Translations

If new strings are added to the code:

1. **Extract new strings**:
   ```bash
   python3 extract_strings.py
   ```
   This updates `gota.pot` and all `.po` files with new strings.

2. **Translate new strings**:
   Open your `.po` file and look for empty `msgstr ""` fields.

3. **Recompile**:
   ```bash
   ./compile_translations.sh <language_code>
   ```

## Developer Tools

### `extract_strings.py`
Scans all `.lua` files for translatable strings wrapped in `_("...")` and generates:
- `l10n/templates/gota.pot` - Translation template
- Updates all `l10n/<lang>/gota.po` files with new strings

### `compile_translations.sh`
Compiles `.po` → `.mo` files using `msgfmt`.

**Usage**:
```bash
# Compile all languages
./compile_translations.sh

# Compile specific language
./compile_translations.sh es
```

### `replace_strings.py`
One-time migration script that replaced Spanish strings with English in the source code. Not needed for regular translation work.

## Best Practices

1. **Context Matters**: Some strings appear in different UI contexts. Consider available space.

2. **Test on Device**: Test translations on actual KOReader to ensure:
   - Text fits in buttons/dialogs
   - Special characters display correctly
   - Line breaks work as expected

3. **Preserve Formatting**: 
   - Keep `\n` for newlines
   - Maintain indentation with spaces (•)
   - Preserve punctuation patterns

4. **Placeholders**: 
   - `%s` - String placeholder
   - `%d` - Number placeholder
   - Keep them in logical positions for your language

5. **Character Encoding**: Always use UTF-8

## Translation Examples

### Simple String
```po
msgid "Cancel"
msgstr "Cancelar"
```

### String with Placeholder
```po
msgid "Page %d of %d"
msgstr "Página %d de %d"
```

### Multi-line String
```po
msgid "Valid token!\nUser: "
msgstr "Token válido!\nUsuario: "
```

### Complex Dialog
```po
msgid "OPTION 1 - Test Token (Recommended):\n• Go to: https://app.raindrop.io/settings/integrations\n• Create a new application\n• Copy the 'Test token'\n\nOPTION 2 - Personal Token:\n• Use a personal access token\n\nPaste the token here:"
msgstr "OPCIÓN 1 - Test Token (Recomendado):\n• Ve a: https://app.raindrop.io/settings/integrations\n• Crea una nueva aplicación\n• Copia el 'Test token'\n\nOPCIÓN 2 - Token Personal:\n• Usa un token de acceso personal\n\nPega el token aquí:"
```

## Contributing

To contribute a translation:

1. Fork the repository
2. Create your translation following this guide
3. Test thoroughly
4. Submit a pull request with:
   - Your `.po` file
   - Compiled `.mo` file
   - Brief description of testing done

## Questions?

Open an issue on the repository with the tag `[i18n]`.
