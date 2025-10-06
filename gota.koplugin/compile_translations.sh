#!/bin/bash
#
# Script para compilar traducciones del plugin Gota
# 
# Uso:
#   ./compile_translations.sh      # Compila todas las traducciones
#   ./compile_translations.sh es   # Compila solo español
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -z "$1" ]; then
    # Compilar todos los idiomas
    echo "🌍 Compilando todas las traducciones..."
    for po_file in l10n/*/gota.po; do
        if [ -f "$po_file" ]; then
            lang=$(basename $(dirname "$po_file"))
            mo_file="l10n/$lang/gota.mo"
            echo "  📝 Compilando $lang..."
            msgfmt -o "$mo_file" "$po_file"
            echo "  ✅ $mo_file"
        fi
    done
else
    # Compilar idioma específico
    lang="$1"
    po_file="l10n/$lang/gota.po"
    mo_file="l10n/$lang/gota.mo"
    
    if [ ! -f "$po_file" ]; then
        echo "❌ Error: No existe $po_file"
        exit 1
    fi
    
    echo "📝 Compilando traducción $lang..."
    msgfmt -o "$mo_file" "$po_file"
    echo "✅ $mo_file"
fi

echo ""
echo "🎉 ¡Compilación completada!"
echo ""
echo "Los archivos .mo están listos para ser usados por KOReader."
echo "Reinicia KOReader para ver los cambios."
