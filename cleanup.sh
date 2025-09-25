#!/bin/bash
#
# Stabsstelle Pi - Cleanup Script
# Entfernt alte/fehlgeschlagene Installationen
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
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Header
clear
echo "============================================"
echo "  Stabsstelle Pi - Cleanup Tool"
echo "============================================"
echo ""
echo "Dieses Script entfernt alle Spuren einer"
echo "vorherigen Stabsstelle-Installation."
echo ""
print_warning "ACHTUNG: Alle Daten werden gelöscht!"
echo ""

# Root-Check
if [ "$EUID" -ne 0 ]; then
    print_info "Benötige Root-Rechte..."
    exec sudo bash "$0" "$@"
fi

# Bestätigung
echo "Möchten Sie wirklich ALLE Stabsstelle-Daten löschen? (j/N)"
read -r response
if [[ ! "$response" =~ ^[Jj]$ ]]; then
    print_info "Cleanup abgebrochen."
    exit 0
fi

echo ""
print_status "Starte Cleanup..."
echo ""

# 1. Services stoppen
print_info "Stoppe Services..."
systemctl stop stabsstelle 2>/dev/null || true
systemctl stop stabsstelle-gunicorn 2>/dev/null || true
systemctl stop stabsstelle-sync.timer 2>/dev/null || true
systemctl stop stabsstelle-sync 2>/dev/null || true

# 2. Services deaktivieren
print_info "Deaktiviere Services..."
systemctl disable stabsstelle 2>/dev/null || true
systemctl disable stabsstelle-gunicorn 2>/dev/null || true
systemctl disable stabsstelle-sync.timer 2>/dev/null || true
systemctl disable stabsstelle-sync 2>/dev/null || true

# 3. Systemd-Units entfernen
print_info "Entferne Systemd-Units..."
rm -f /etc/systemd/system/stabsstelle.service
rm -f /etc/systemd/system/stabsstelle-gunicorn.service
rm -f /etc/systemd/system/stabsstelle-sync.service
rm -f /etc/systemd/system/stabsstelle-sync.timer
systemctl daemon-reload

# 4. Nginx-Konfiguration entfernen
print_info "Entferne Nginx-Konfiguration..."
rm -f /etc/nginx/sites-enabled/stabsstelle
rm -f /etc/nginx/sites-available/stabsstelle
rm -f /etc/nginx/sites-enabled/stab
rm -f /etc/nginx/sites-available/stab
nginx -t 2>/dev/null && systemctl reload nginx || true

# 5. Anwendungsverzeichnisse entfernen
print_info "Entferne Anwendungsverzeichnisse..."
rm -rf /opt/stabsstelle
rm -rf /opt/Stabsstelle

# 6. Datenverzeichnisse entfernen
print_info "Entferne Datenverzeichnisse..."
rm -rf /var/lib/stabsstelle
rm -rf /var/log/stabsstelle

# 7. Konfigurationsdateien entfernen
print_info "Entferne Konfigurationsdateien..."
rm -rf /etc/stabsstelle

# 8. Temporäre Dateien entfernen
print_info "Entferne temporäre Dateien..."
rm -rf /tmp/stabsstelle*
rm -rf /tmp/.stabsstelle*
rm -rf /root/stabsstelle*
rm -rf /home/*/stabsstelle*

# 9. Python Virtual Environments entfernen
print_info "Suche und entferne Virtual Environments..."
find /opt -name "venv" -type d -path "*/stabsstelle/*" -exec rm -rf {} + 2>/dev/null || true

# 10. User entfernen (falls angelegt)
if id "pi" &>/dev/null; then
    print_info "Entferne User 'pi'..."
    userdel pi 2>/dev/null || true
fi

# 11. Cron-Jobs entfernen
print_info "Entferne Cron-Jobs..."
crontab -l 2>/dev/null | grep -v stabsstelle | crontab - 2>/dev/null || true

# 12. Firewall-Regeln zurücksetzen (optional)
print_info "Prüfe Firewall-Regeln..."
if command -v ufw &> /dev/null; then
    # Regeln bleiben erhalten, da sie auch für andere Dienste nützlich sein können
    print_info "Firewall-Regeln bleiben erhalten (Port 80/443)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
print_status "Cleanup abgeschlossen!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Das System ist jetzt bereit für eine"
echo "Neuinstallation der Stabsstelle-Software."
echo ""
echo "Installationsbefehl:"
echo "  wget -qO- https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/pi-install.sh | bash"
echo ""

# Optional: System-Info
print_info "System-Info:"
echo "  Freier Speicher: $(df -h / | awk 'NR==2 {print $4}')"
echo "  Freier RAM: $(free -h | awk '/^Mem:/ {print $4}')"
echo "