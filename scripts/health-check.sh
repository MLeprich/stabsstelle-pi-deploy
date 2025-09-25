#!/bin/bash
#
# Stabsstelle Pi - Health Check Script
# Prüft den Systemzustand und die Synchronisation
#

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_ok() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

echo "============================================"
echo "  Stabsstelle Pi - System Health Check"
echo "============================================"
echo ""

# System-Info
echo "System-Informationen:"
echo "  Hostname: $(hostname)"
echo "  IP: $(hostname -I | cut -d' ' -f1)"
echo "  Uptime: $(uptime -p)"
echo "  CPU: $(grep -c processor /proc/cpuinfo) Cores"
echo "  RAM: $(free -h | awk '/^Mem:/ {print $3 " / " $2}')"
echo "  Disk: $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 " belegt)"}')"
echo ""

# Service-Status
echo "Service-Status:"

# Stabsstelle Service
if systemctl is-active --quiet stabsstelle; then
    print_ok "Stabsstelle Service läuft"

    # Prüfe ob Port erreichbar
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8004/ | grep -q "302\|200"; then
        print_ok "Webinterface erreichbar"
    else
        print_warning "Webinterface nicht erreichbar"
    fi
else
    print_error "Stabsstelle Service läuft nicht"
fi

# Sync Timer
if systemctl is-active --quiet stabsstelle-sync.timer; then
    print_ok "Sync-Timer aktiv"

    # Nächste Ausführung
    next_run=$(systemctl status stabsstelle-sync.timer | grep "Trigger:" | cut -d':' -f2-)
    echo "    Nächster Sync:$next_run"
else
    print_warning "Sync-Timer nicht aktiv"
fi

# Nginx
if systemctl is-active --quiet nginx; then
    print_ok "Nginx läuft"
else
    print_error "Nginx läuft nicht"
fi

echo ""

# Datenbank-Check
echo "Datenbank-Status:"
DB_PATH="/var/lib/stabsstelle/stabsstelle.db"
if [ -f "$DB_PATH" ]; then
    DB_SIZE=$(du -h "$DB_PATH" | cut -f1)
    print_ok "Datenbank vorhanden ($DB_SIZE)"

    # Prüfe Integrität
    if sqlite3 "$DB_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
        print_ok "Datenbank-Integrität OK"
    else
        print_error "Datenbank-Integrität fehlerhaft!"
    fi
else
    print_error "Datenbank nicht gefunden"
fi

echo ""

# Lizenz-Check
echo "Lizenz-Status:"
python3 /opt/stabsstelle/tools/license_validator.py check 2>/dev/null || print_error "Lizenz-Check fehlgeschlagen"

echo ""

# Sync-Status
echo "Sync-Historie:"
if [ -f "/var/lib/stabsstelle/sync_meta.db" ]; then
    sqlite3 /var/lib/stabsstelle/sync_meta.db "
        SELECT
            datetime(completed_at, 'localtime') as Zeit,
            status as Status,
            records_sent as Gesendet,
            records_received as Empfangen,
            conflicts as Konflikte
        FROM sync_history
        ORDER BY completed_at DESC
        LIMIT 5;
    " 2>/dev/null || echo "  Keine Sync-Historie verfügbar"
else
    echo "  Keine Sync-Datenbank gefunden"
fi

echo ""

# Log-Analyse
echo "Letzte Fehler (falls vorhanden):"
journalctl -u stabsstelle -p err -n 5 --no-pager 2>/dev/null | tail -n +2 || echo "  Keine Fehler gefunden"

echo ""

# Netzwerk-Verbindung
echo "Netzwerk-Status:"
if ping -c 1 -W 2 stab.digitmi.de >/dev/null 2>&1; then
    print_ok "Server erreichbar (stab.digitmi.de)"
else
    print_warning "Server nicht erreichbar"
fi

if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    print_ok "Internet-Verbindung aktiv"
else
    print_error "Keine Internet-Verbindung"
fi

echo ""
echo "============================================"
echo "  Health Check abgeschlossen"
echo "============================================"