#!/bin/bash
#
# Stabsstelle Pi - Download and Install Script
# Alternative zum direkten curl | bash
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

echo "============================================"
echo "  Stabsstelle Pi - Download & Install"
echo "============================================"
echo ""

# Root-Check
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte als root ausführen (sudo $0)"
fi

# Download in temporäres Verzeichnis
TEMP_DIR="/tmp/stabsstelle-install-$$"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

print_status "Lade Installations-Script herunter..."

# Download des Scripts
curl -sSL https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/install.sh -o install.sh

# Ausführbar machen
chmod +x install.sh

print_status "Starte Installation..."
echo ""

# Ausführen (jetzt mit funktionierendem stdin)
./install.sh

# Aufräumen
cd /
rm -rf "$TEMP_DIR"

print_status "Download-Script beendet."