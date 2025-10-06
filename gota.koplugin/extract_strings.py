#!/usr/bin/env python3
"""
Script para extraer strings traducibles del plugin Gota y generar archivos .pot y .po
"""

import re
import os
from collections import OrderedDict
from datetime import datetime

# Mapeo de strings español → inglés
TRANSLATIONS = {
    # _meta.lua
    "Gota": "Gota",
    "Con Gota lee y gestiona tus marcadores de Raindrop.io desde KOReader!": "Read and manage your Raindrop.io bookmarks with Gota from KOReader!",
    
    # API errors
    "Respuesta vacía del servidor": "Empty server response",
    "Error: No se pudo descomprimir la respuesta del servidor": "Error: Could not decompress server response",
    "Error al procesar respuesta del servidor": "Error processing server response",
    "Error del servidor: ": "Server error: ",
    "Error HTTP ": "HTTP error ",
    "Falló después de ": "Failed after ",
    " intentos": " attempts",
    
    # Content processor
    "Sin título": "Untitled",
    "Fuente: ": "Source: ",
    "URL: ": "URL: ",
    "Dominio: ": "Domain: ",
    "Guardado: ": "Saved: ",
    "Enlace": "Link",
    "Artículo": "Article",
    "Imagen": "Image",
    "Video": "Video",
    "Documento": "Document",
    "Audio": "Audio",
    "Tipo: ": "Type: ",
    "Extracto:": "Excerpt:",
    "Notas:": "Notes:",
    "Etiquetas: ": "Tags: ",
    "Caché: ": "Cache: ",
    "Disponible": "Available",
    "Tamaño: ": "Size: ",
    "Listo": "Ready",
    "Reintentando": "Retrying",
    "Falló": "Failed",
    "Origen inválido": "Invalid origin",
    "Tiempo agotado": "Timeout",
    "Tamaño inválido": "Invalid size",
    "Estado del caché: ": "Cache status: ",
    
    # UI Builder
    "No hay artículos disponibles": "No articles available",
    "No tienes colecciones creadas": "You have no collections created",
    "Abrir en lector completo": "Open in full reader",
    "Ver contenido en texto simple": "View content as plain text",
    "Descargar HTML": "Download HTML",
    "Ver información del artículo": "View article information",
    "Copiar URL": "Copy URL",
    "La caché está siendo generada, intenta más tarde": "Cache is being generated, try again later",
    "La generación de caché ha fallado": "Cache generation has failed",
    "No se pudo generar caché por origen inválido": "Could not generate cache due to invalid origin",
    "No se pudo generar caché por timeout": "Could not generate cache due to timeout",
    "No se pudo generar caché por tamaño excesivo": "Could not generate cache due to excessive size",
    "La caché no está disponible": "Cache is not available",
    "Intentar recargar artículo completo": "Try reloading full article",
    "Este artículo no tiene contenido en caché disponible": "This article has no cached content available",
    "« Primera página": "« First page",
    "← Página anterior": "← Previous page",
    "Página siguiente →": "Next page →",
    "» Última página": "» Last page",
    "Página %d de %d": "Page %d of %d",
    "Cerrar": "Close",
    "Abrir en lector": "Open in reader",
    "Compartir enlace": "Share link",
    "Guardar HTML": "Save HTML",
    
    # Dialogs
    "Token de acceso de Raindrop.io": "Raindrop.io Access Token",
    "OPCIÓN 1 - Test Token (Recomendado):\\n• Ve a: https://app.raindrop.io/settings/integrations\\n• Crea una nueva aplicación\\n• Copia el 'Test token'\\n\\nOPCIÓN 2 - Token Personal:\\n• Usa un token de acceso personal\\n\\nPega el token aquí:": "OPTION 1 - Test Token (Recommended):\\n• Go to: https://app.raindrop.io/settings/integrations\\n• Create a new application\\n• Copy the 'Test token'\\n\\nOPTION 2 - Personal Token:\\n• Use a personal access token\\n\\nPaste the token here:",
    "Cancelar": "Cancel",
    "Probar": "Test",
    "Por favor ingresa un token para probar": "Please enter a token to test",
    "Guardar": "Save",
    "Por favor ingresa un token válido": "Please enter a valid token",
    "Aviso: Token parece muy corto, pero se guardará de todos modos": "Warning: Token seems very short, but it will be saved anyway",
    "Token guardado correctamente\\nUsa 'Probar' para verificar funcionalidad": "Token saved successfully\\nUse 'Test' to verify functionality",
    "Carpeta de descargas": "Download folder",
    "Nombre de carpeta inválido": "Invalid folder name",
    "Carpeta configurada: ": "Folder configured: ",
    "Error al guardar: ": "Error saving: ",
    "Por favor ingresa un nombre de carpeta": "Please enter a folder name",
    "Buscar artículos": "Search articles",
    "Buscar": "Search",
    "Por favor ingresa un término de búsqueda": "Please enter a search term",
    "URL del artículo:": "Article URL:",
    "No se puede abrir directamente en KOReader.": "Cannot be opened directly in KOReader.",
    "Puedes copiar esta URL para abrirla en otro dispositivo.": "You can copy this URL to open it on another device.",
    "Enlace del artículo": "Article link",
    "Información del artículo": "Article information",
    
    # Article Manager
    "Cargando contenido completo...": "Loading full content...",
    "Cargando contenido en caché...": "Loading cached content...",
    "Recargando artículo...": "Reloading article...",
    "El artículo aún no tiene contenido en caché disponible": "The article does not yet have cached content available",
    "Error al recargar artículo: ": "Error reloading article: ",
    "Error desconocido": "Unknown error",
    "No se puede descargar: ID no encontrado": "Cannot download: ID not found",
    "No hay contenido en caché disponible para descargar": "No cached content available for download",
    "Error al crear directorio para guardar HTML": "Error creating directory to save HTML",
    "Descargando HTML...": "Downloading HTML...",
    "Error al descargar HTML: ": "Error downloading HTML: ",
    "El contenido descargado parece incompleto": "Downloaded content appears incomplete",
    "Error al crear archivo: ": "Error creating file: ",
    "HTML guardado en: %s": "HTML saved to: %s",
    "No hay contenido disponible": "No content available",
    "Error al crear archivo temporal": "Error creating temporary file",
    
    # Main menu
    "Gota (Raindrop.io)": "Gota (Raindrop.io)",
    "Configurar token de acceso": "Configure access token",
    "Configurar carpeta de descargas": "Configure download folder",
    "Debug: Ver configuración": "Debug: View configuration",
    "Ver colecciones": "View collections",
    "Todos los artículos": "All articles",
    "Carpeta de descargas actualizada: ": "Download folder updated: ",
    "Error al guardar configuración": "Error saving configuration",
    "Cargando colecciones...": "Loading collections...",
    "Error al obtener colecciones:": "Error retrieving collections:",
    "Colecciones de Raindrop": "Raindrop Collections",
    "Cargando artículos...": "Loading articles...",
    "Error al obtener artículos: ": "Error retrieving articles: ",
    "Artículos": "Articles",
    "El contenido no está disponible aún": "Content is not available yet",
    "No hay contenido en caché disponible": "No cached content available",
    "Contenido en caché": "Cached content",
    "Buscando artículos...": "Searching articles...",
    "Error en la búsqueda: ": "Search error: ",
    "Resultados: '": "Results: '",
    "Ir a carpeta de descarga": "Go to download folder",
    "Volver": "Back",
    "HTML descargado": "HTML downloaded",
    "Aviso: Token vacío, no se puede probar": "Warning: Empty token, cannot test",
    "Aviso: Token parece muy corto, pero se probará de todos modos": "Warning: Token seems very short, but it will be tested anyway",
    "Probando token...": "Testing token...",
    " (PRO)": " (PRO)",
    "Token válido!\\nUsuario: ": "Valid token!\\nUser: ",
    "Error con el token:\\n": "Error with token:\\n",
    
    # Gota Reader
    "Error: No se pudo encontrar el archivo HTML": "Error: Could not find HTML file",
    "Error: No se pudo abrir el archivo HTML": "Error: Could not open HTML file",
    "< Volver a Gota": "< Back to Gota",
    "Copiar URL del artículo": "Copy article URL",
}

def extract_strings_from_file(filepath):
    """Extrae strings traducibles de un archivo Lua"""
    strings = []
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Buscar patrones _("string") o _('string')
    pattern = r'_\(["\']([^"\']+)["\']\)'
    matches = re.finditer(pattern, content)
    
    for match in matches:
        string = match.group(1)
        # Desescapar caracteres
        string = string.replace('\\n', '\n').replace('\\t', '\t')
        strings.append(string)
    
    return strings

def create_pot_file(strings, output_path):
    """Crea archivo .pot (template)"""
    header = f'''# SOME DESCRIPTIVE TITLE.
# Copyright (C) YEAR THE PACKAGE'S COPYRIGHT HOLDER
# This file is distributed under the same license as the PACKAGE package.
# FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.
#
msgid ""
msgstr ""
"Project-Id-Version: Gota Plugin 1.9.0\\n"
"Report-Msgid-Bugs-To: \\n"
"POT-Creation-Date: {datetime.now().strftime('%Y-%m-%d %H:%M%z')}\\n"
"PO-Revision-Date: YEAR-MO-DA HO:MI+ZONE\\n"
"Last-Translator: FULL NAME <EMAIL@ADDRESS>\\n"
"Language-Team: LANGUAGE <LL@li.org>\\n"
"Language: \\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"

'''
    
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(header)
        
        # Escribir strings únicas
        unique_strings = list(OrderedDict.fromkeys(strings))
        for string in unique_strings:
            # Convertir a inglés para el msgid
            english = TRANSLATIONS.get(string, string)
            # Escapar saltos de línea y comillas
            english_escaped = english.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')
            f.write(f'msgid "{english_escaped}"\n')
            f.write(f'msgstr ""\n\n')

def create_po_file(strings, output_path, language_code, language_name):
    """Crea archivo .po con traducciones"""
    header = f'''# Gota Plugin Spanish Translation
# Copyright (C) 2025
# This file is distributed under the same license as the Gota package.
#
msgid ""
msgstr ""
"Project-Id-Version: Gota Plugin 1.9.0\\n"
"Report-Msgid-Bugs-To: \\n"
"POT-Creation-Date: {datetime.now().strftime('%Y-%m-%d %H:%M%z')}\\n"
"PO-Revision-Date: {datetime.now().strftime('%Y-%m-%d %H:%M%z')}\\n"
"Last-Translator: Christian Stenger\\n"
"Language-Team: Spanish\\n"
"Language: {language_code}\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Plural-Forms: nplurals=2; plural=(n != 1);\\n"

'''
    
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(header)
        
        # Escribir traducciones
        unique_strings = list(OrderedDict.fromkeys(strings))
        for spanish_string in unique_strings:
            english = TRANSLATIONS.get(spanish_string, spanish_string)
            # Escapar saltos de línea y comillas
            english_escaped = english.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')
            spanish_escaped = spanish_string.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')
            f.write(f'msgid "{english_escaped}"\n')
            f.write(f'msgstr "{spanish_escaped}"\n\n')

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Archivos a procesar (excluyendo backups)
    lua_files = [
        'api.lua',
        'article_manager.lua',
        'content_processor.lua',
        'dialogs.lua',
        'gota_reader.lua',
        'main.lua',
        'menu_builder.lua',
        'ui_builder.lua',
        '_meta.lua',
    ]
    
    all_strings = []
    for lua_file in lua_files:
        filepath = os.path.join(script_dir, lua_file)
        if os.path.exists(filepath):
            print(f"Extracting from {lua_file}...")
            strings = extract_strings_from_file(filepath)
            all_strings.extend(strings)
    
    print(f"\nTotal strings found: {len(all_strings)}")
    print(f"Unique strings: {len(set(all_strings))}")
    
    # Crear archivos
    pot_path = os.path.join(script_dir, 'l10n', 'templates', 'gota.pot')
    po_es_path = os.path.join(script_dir, 'l10n', 'es', 'gota.po')
    
    print(f"\nCreating {pot_path}...")
    create_pot_file(all_strings, pot_path)
    
    print(f"Creating {po_es_path}...")
    create_po_file(all_strings, po_es_path, 'es', 'Spanish')
    
    print("\n✅ Done! Files created:")
    print(f"  - {pot_path}")
    print(f"  - {po_es_path}")
    print("\nNext steps:")
    print("  1. Run: msgfmt -o l10n/es/gota.mo l10n/es/gota.po")
    print("  2. Update Lua files to use English strings")

if __name__ == '__main__':
    main()
