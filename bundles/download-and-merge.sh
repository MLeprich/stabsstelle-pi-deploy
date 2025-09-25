#!/bin/bash
#
# Download und Zusammenfügen des Stabsstelle Bundles
#

echo "============================================"
echo "  Stabsstelle Bundle Download"
echo "============================================"
echo ""

# GitHub Raw URLs
BASE_URL="https://github.com/MLeprich/stabsstelle-pi-deploy/raw/main/bundles"

echo "→ Lade Bundle-Teile herunter..."
echo ""

# Download alle Teile
for part in aa ab ac ad; do
    echo "  Downloading part $part..."
    wget -q --show-progress "${BASE_URL}/bundle-part-${part}" || {
        echo "Fehler beim Download von Teil $part"
        exit 1
    }
done

echo ""
echo "→ Füge Teile zusammen..."
cat bundle-part-* > stabsstelle-bundle.tar.gz

echo "→ Aufräumen..."
rm bundle-part-*

echo ""
echo "✓ Bundle erfolgreich heruntergeladen!"
echo ""
echo "Datei: stabsstelle-bundle.tar.gz"
echo "Größe: $(du -h stabsstelle-bundle.tar.gz | cut -f1)"
echo ""
echo "Nächste Schritte:"
echo "  1. tar xzf stabsstelle-bundle.tar.gz"
echo "  2. cd stabsstelle-bundle"
echo "  3. sudo ./install.sh"
echo ""