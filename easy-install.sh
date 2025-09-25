#!/bin/bash
#
# Stabsstelle Pi - Easy Install
# Der einfachste Weg zur Installation
#

echo "============================================"
echo "  Stabsstelle Pi - Easy Installer"
echo "============================================"
echo ""

# Prüfe ob wir Schreibrechte haben
if [ -w "$HOME" ]; then
    cd "$HOME"
elif [ -w "/tmp" ]; then
    cd /tmp
else
    echo "Fehler: Kein schreibbares Verzeichnis gefunden"
    exit 1
fi

# Download des Setup-Scripts
echo "→ Lade Setup-Script herunter..."
wget -q https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/setup.sh -O stabsstelle-setup.sh || {
    echo "Fehler beim Download. Prüfen Sie Ihre Internetverbindung."
    exit 1
}

# Ausführbar machen
chmod +x stabsstelle-setup.sh

echo "→ Starte Installation..."
echo ""

# Ausführen - wird automatisch zu sudo wechseln wenn nötig
bash ./stabsstelle-setup.sh

# Aufräumen
rm -f stabsstelle-setup.sh