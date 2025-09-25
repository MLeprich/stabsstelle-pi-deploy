#!/bin/bash
#
# Stabsstelle Pi - Direct Installer
# Direkte Installation ohne Umwege
#

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    exit 1
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Header
echo ""
echo "============================================"
echo "  Stabsstelle Pi - Installation"
echo "============================================"
echo ""

# Prüfe ob sudo verfügbar ist
if ! command -v sudo &> /dev/null; then
    if [ "$EUID" -ne 0 ]; then
        print_error "Bitte als root ausführen (sudo nicht verfügbar)"
    fi
else
    if [ "$EUID" -ne 0 ]; then
        print_info "Benötige Root-Rechte. Starte mit sudo neu..."
        exec sudo bash "$0" "$@"
    fi
fi

print_status "Läuft mit Root-Rechten"

# Arbeitsverzeichnis
WORK_DIR="/root/stabsstelle-install"
if [ ! -w "/root" ]; then
    WORK_DIR="/tmp/stabsstelle-install"
fi

print_status "Arbeitsverzeichnis: $WORK_DIR"

# Cleanup alte Installation
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Repository klonen
print_status "Lade Stabsstelle Pi Deploy..."
git clone https://github.com/MLeprich/stabsstelle-pi-deploy.git deploy 2>/dev/null || {
    print_error "Git Clone fehlgeschlagen. Prüfen Sie die Internetverbindung."
}

cd deploy

# Lizenzschlüssel abfragen
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "LIZENZSCHLÜSSEL BENÖTIGT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Bitte geben Sie Ihren Lizenzschlüssel ein:"
echo "(Format: XXXX-XXXX-XXXX-XXXX)"
echo ""
printf "Lizenzschlüssel: "
read -r LICENSE_KEY

if [ -z "$LICENSE_KEY" ]; then
    print_error "Kein Lizenzschlüssel eingegeben"
fi

print_status "Lizenzschlüssel erhalten"

# Device ID anzeigen
chmod +x install.sh
DEVICE_ID=$(bash install.sh --get-device-id 2>/dev/null || echo "unknown")
print_info "Device ID: $DEVICE_ID"

# Installation mit Lizenz
echo ""
print_status "Starte Hauptinstallation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Führe Installation aus
bash install.sh --license "$LICENSE_KEY"

# Status prüfen
if [ $? -eq 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_status "Installation erfolgreich abgeschlossen!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Zugriff auf die Stabsstelle-Anwendung:"
    echo "  → http://$(hostname -I | cut -d' ' -f1)"
    echo "  → http://stabsstelle.local"
    echo ""
    echo "Device ID: $DEVICE_ID"
    echo ""
else
    print_error "Installation fehlgeschlagen. Prüfen Sie die Logs."
fi

# Cleanup
cd /
rm -rf "$WORK_DIR"