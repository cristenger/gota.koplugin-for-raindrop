#!/usr/bin/env python3
"""
Script para reemplazar strings en español por inglés en archivos Lua
"""

import re
import os
import shutil

# Mapeo completo español → inglés (mismo que extract_strings.py)
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

def replace_strings_in_file(filepath, dry_run=False):
    """Reemplaza strings en español por inglés en un archivo"""
    print(f"\n{'[DRY RUN] ' if dry_run else ''}Processing {os.path.basename(filepath)}...")
    
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    replacements_count = 0
    
    # Ordenar por longitud (más largo primero) para evitar reemplazos parciales
    sorted_translations = sorted(TRANSLATIONS.items(), key=lambda x: len(x[0]), reverse=True)
    
    for spanish, english in sorted_translations:
        # Escapar caracteres especiales para regex
        spanish_escaped = re.escape(spanish)
        
        # Buscar patrón _("spanish") o _('spanish')
        pattern = f'_\\(["\']({spanish_escaped})["\']\\)'
        
        # Contar ocurrencias
        matches = re.findall(pattern, content)
        if matches:
            replacements_count += len(matches)
            # Reemplazar
            content = re.sub(pattern, f'_("{english}")', content)
            print(f"  ✓ Replaced {len(matches)}x: '{spanish[:50]}...' → '{english[:50]}...'")
    
    if not dry_run and content != original_content:
        # Crear backup
        backup_path = filepath + '.bak'
        shutil.copy2(filepath, backup_path)
        print(f"  📋 Backup created: {os.path.basename(backup_path)}")
        
        # Escribir cambios
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"  ✅ File updated with {replacements_count} replacements")
    elif dry_run and replacements_count > 0:
        print(f"  [DRY RUN] Would replace {replacements_count} strings")
    else:
        print(f"  → No changes needed")
    
    return replacements_count

def main():
    import sys
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Check for dry-run flag
    dry_run = '--dry-run' in sys.argv or '-n' in sys.argv
    
    if dry_run:
        print("🔍 DRY RUN MODE - No files will be modified\n")
    
    # Archivos a procesar (excluyendo backups)
    lua_files = [
        'gota_api.lua',
        'gota_article_manager.lua',
        'gota_content_processor.lua',
        'gota_dialogs.lua',
        'gota_reader.lua',
        'main.lua',
        'gota_ui_builder.lua',
        '_meta.lua',
    ]
    
    total_replacements = 0
    
    for lua_file in lua_files:
        filepath = os.path.join(script_dir, lua_file)
        if os.path.exists(filepath):
            count = replace_strings_in_file(filepath, dry_run)
            total_replacements += count
    
    print(f"\n{'=' * 60}")
    print(f"{'[DRY RUN] ' if dry_run else ''}Total replacements: {total_replacements}")
    
    if dry_run:
        print("\nTo apply changes, run: python3 replace_strings.py")
    else:
        print(f"\n✅ All files updated!")
        print(f"Backups created with .bak extension")
        print(f"\nNext steps:")
        print(f"  1. Test the plugin in KOReader")
        print(f"  2. Verify syntax: luac -p *.lua")
        print(f"  3. If everything works, remove .bak files")

if __name__ == '__main__':
    main()
