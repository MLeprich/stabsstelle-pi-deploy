#!/bin/bash
#
# Stabsstelle Pi - Setup Script
# Robuste Installation mit Eingabe-Unterstützung
#

set -e

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

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Banner
clear
echo "============================================"
echo "  Stabsstelle Pi - Setup Wizard"
echo "============================================"
echo ""

# Root-Check
if [ "$EUID" -ne 0 ]; then
    print_warning "Script läuft nicht als root."
    print_info "Starte mit sudo neu..."
    exec sudo bash "$0" "$@"
fi

# Arbeitsverzeichnis
WORK_DIR="/tmp/stabsstelle-setup-$$"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

print_status "Arbeitsverzeichnis: $WORK_DIR"

# Repository klonen
print_status "Lade Stabsstelle Pi Deploy Repository..."
git clone https://github.com/MLeprich/stabsstelle-pi-deploy.git 2>/dev/null || {
    print_error "Fehler beim Klonen des Repositories. Prüfen Sie Ihre Internetverbindung."
}

cd stabsstelle-pi-deploy

# Lizenzschlüssel abfragen
echo ""
print_info "Für die Installation wird ein gültiger Lizenzschlüssel benötigt."
print_info "Kontaktieren Sie support@digitmi.de falls Sie noch keinen haben."
echo ""
echo "Bitte geben Sie Ihren Lizenzschlüssel ein:"
echo "(Format: XXXX-XXXX-XXXX-XXXX)"
echo -n "> "
read LICENSE_KEY

if [ -z "$LICENSE_KEY" ]; then
    print_error "Kein Lizenzschlüssel eingegeben. Installation abgebrochen."
fi

# Lizenz in Environment-Variable speichern für Install-Script
export STABSSTELLE_LICENSE_KEY="$LICENSE_KEY"

# Device-ID anzeigen
DEVICE_ID=$(./install.sh --get-device-id 2>/dev/null || echo "unbekannt")
print_info "Device ID: $DEVICE_ID"

# Installation starten
print_status "Starte Hauptinstallation..."
echo ""

# Modifiziertes Install-Script ausführen
chmod +x install.sh

# Temporäre Datei mit Lizenz erstellen
echo "$LICENSE_KEY" > /tmp/.stabsstelle_license

# Install-Script mit Lizenz aus Datei ausführen
./install.sh --license-file /tmp/.stabsstelle_license

# Aufräumen
rm -f /tmp/.stabsstelle_license
cd /
rm -rf "$WORK_DIR"

print_status "Setup abgeschlossen!"
echo ""
echo "Die Stabsstelle-Anwendung sollte jetzt unter folgender Adresse erreichbar sein:"
echo "  → http://$(hostname -I | cut -d' ' -f1)"
echo ""
echo "Bei Problemen prüfen Sie die Logs:"
echo "  sudo journalctl -u stabsstelle -f"
echo ""