#!/bin/bash
#
# Stabsstelle Pi - Update Script
# Aktualisiert die Stabsstelle-Software auf dem Pi
#

set -e

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Konfiguration
INSTALL_DIR="/opt/stabsstelle"
MAIN_REPO="https://github.com/MLeprich/Stabsstelle.git"
BACKUP_DIR="/var/lib/stabsstelle/backups"

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
    print_error "Bitte als root ausführen (sudo ./update.sh)"
fi

echo "============================================"
echo "  Stabsstelle Pi - Software Update"
echo "============================================"
echo ""

# Backup erstellen
print_status "Erstelle Backup..."
BACKUP_FILE="${BACKUP_DIR}/backup_$(date +%Y%m%d_%H%M%S).tar.gz"
mkdir -p "$BACKUP_DIR"
tar -czf "$BACKUP_FILE" \
    "$INSTALL_DIR" \
    /etc/stabsstelle \
    /var/lib/stabsstelle/stabsstelle.db \
    2>/dev/null || true

print_status "Backup erstellt: $BACKUP_FILE"

# Service stoppen
print_status "Stoppe Stabsstelle-Service..."
systemctl stop stabsstelle || true
systemctl stop stabsstelle-sync.timer || true

# Git Pull
print_status "Lade Updates herunter..."
cd "$INSTALL_DIR"

# Speichere lokale Änderungen
git stash save "Local changes before update $(date)" || true

# Pull Updates
git pull origin main || print_error "Git Pull fehlgeschlagen"

# Python-Abhängigkeiten aktualisieren
print_status "Aktualisiere Python-Pakete..."
source venv/bin/activate
pip install --upgrade -r requirements-pi.txt || pip install --upgrade -r requirements.txt

# Datenbank-Migrationen
print_status "Führe Datenbank-Migrationen aus..."
export DATABASE_URL="sqlite:///var/lib/stabsstelle/stabsstelle.db"
flask db upgrade || print_warning "Keine neuen Migrationen"

# Services neu starten
print_status "Starte Services..."
systemctl daemon-reload
systemctl start stabsstelle
systemctl start stabsstelle-sync.timer

# Status prüfen
sleep 2
if systemctl is-active --quiet stabsstelle; then
    print_status "Update erfolgreich abgeschlossen!"
else
    print_error "Service konnte nicht gestartet werden. Prüfe die Logs: journalctl -u stabsstelle -n 50"
fi

echo ""
echo "Update abgeschlossen. Version:"
git describe --tags --always
echo ""