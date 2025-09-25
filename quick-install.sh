#!/bin/bash
#
# Stabsstelle Pi - Quick Install Helper
# Dieses Script klont das Repository und startet die Installation
#

set -e

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Root-Check
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte als root ausführen (sudo ./quick-install.sh)"
fi

echo "============================================"
echo "  Stabsstelle Pi - Quick Installer"
echo "============================================"
echo ""

# Temporäres Verzeichnis
TEMP_DIR="/tmp/stabsstelle-pi-deploy-$$"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

print_status "Lade Installations-Dateien herunter..."

# Wenn das Repository privat ist, brauchen wir Credentials
echo ""
echo "Ist das GitHub Repository privat? (j/n)"
read -r IS_PRIVATE

if [[ "$IS_PRIVATE" =~ ^[Jj]$ ]]; then
    echo "Bitte GitHub Benutzername eingeben:"
    read -r GH_USER

    echo "Bitte GitHub Personal Access Token eingeben:"
    echo "(Erstelle einen unter: https://github.com/settings/tokens)"
    read -s GH_TOKEN

    # Clone mit Authentifizierung
    git clone https://${GH_USER}:${GH_TOKEN}@github.com/MLeprich/stabsstelle-pi-deploy.git
else
    # Public clone
    git clone https://github.com/MLeprich/stabsstelle-pi-deploy.git
fi

# Wechsel ins Verzeichnis
cd stabsstelle-pi-deploy

# Mache Scripts ausführbar
chmod +x install.sh
chmod +x scripts/*.sh

# Starte Installation
print_status "Starte Hauptinstallation..."
./install.sh

# Aufräumen
cd /
rm -rf "$TEMP_DIR"

print_status "Installation abgeschlossen!"