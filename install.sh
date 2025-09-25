#!/bin/bash
#
# Stabsstelle Pi Deployment - Installation Script
# Version: 1.0.0
# Author: Stabsstelle DevTeam
#
# Dieses Script installiert die Stabsstelle-Software auf einem Raspberry Pi
# und konfiguriert die automatische Synchronisation mit dem Hauptserver.
#

set -e  # Beende bei Fehler

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Konfiguration
INSTALL_DIR="/opt/stabsstelle"
DATA_DIR="/var/lib/stabsstelle"
LOG_DIR="/var/log/stabsstelle"
CONFIG_DIR="/etc/stabsstelle"
MAIN_REPO="https://github.com/MLeprich/Stabsstelle.git"
SERVER_URL="https://stab.digitmi.de"

# Funktionen
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

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Bitte als root ausführen (sudo ./install.sh)"
    fi
}

check_pi() {
    if ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        print_warning "Dies scheint kein Raspberry Pi zu sein. Fortfahren? (y/n)"
        # Prüfe ob wir von einer Pipe kommen
        if [ -t 0 ]; then
            read -r response
        else
            read -r response < /dev/tty
        fi
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

get_device_id() {
    # Generiere eindeutige Device-ID aus CPU-Serial und MAC
    if [ -f /proc/cpuinfo ]; then
        cpu_serial=$(grep Serial /proc/cpuinfo | cut -d ':' -f 2 | xargs)
    else
        cpu_serial="unknown"
    fi

    mac_address=$(ip link show | awk '/ether/ {print $2}' | head -1 | tr -d ':')
    echo "${cpu_serial}-${mac_address}" | sha256sum | cut -d ' ' -f 1 | head -c 16
}

# Header
clear
echo "============================================"
echo "  Stabsstelle Pi Deployment - Installation"
echo "============================================"
echo ""
echo "Dieses Script installiert:"
echo "  - Python 3.11+ Umgebung"
echo "  - Flask Anwendung (Offline-Modus)"
echo "  - SQLite Datenbank"
echo "  - Nginx Webserver"
echo "  - Automatische Synchronisation"
echo ""
echo "Server: ${SERVER_URL}"
echo "Device ID: $(get_device_id)"
echo ""

# Prüfungen
check_root
check_pi

# Lizenz-Abfrage
echo ""
echo "Bitte geben Sie Ihren Lizenzschlüssel ein:"
echo "(Format: XXXX-XXXX-XXXX-XXXX)"

# Prüfe ob wir von einer Pipe kommen (curl | bash)
if [ -t 0 ]; then
    # Interaktive Shell - normale Eingabe
    read -r LICENSE_KEY
else
    # Von Pipe - verwende /dev/tty für direkte Eingabe
    read -r LICENSE_KEY < /dev/tty
fi

if [ -z "$LICENSE_KEY" ]; then
    print_error "Kein Lizenzschlüssel eingegeben"
fi

print_status "Prüfe Lizenz..."

# Lizenz validieren (Python-Script wird später aufgerufen)
DEVICE_ID=$(get_device_id)
HOSTNAME=$(hostname)

# System-Updates
print_status "Aktualisiere System-Pakete..."
apt-get update >/dev/null 2>&1

# Installiere Abhängigkeiten
print_status "Installiere System-Abhängigkeiten..."
apt-get install -y \
    python3-pip \
    python3-venv \
    python3-dev \
    git \
    nginx \
    sqlite3 \
    redis-server \
    curl \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-setuptools \
    supervisor \
    htop \
    >/dev/null 2>&1

# Erstelle Verzeichnisse
print_status "Erstelle Verzeichnisstruktur..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$DATA_DIR/uploads"
mkdir -p "$DATA_DIR/backups"
mkdir -p "$DATA_DIR/tiles"

# Clone Hauptrepository
print_status "Lade Anwendung herunter..."
if [ -d "$INSTALL_DIR/.git" ]; then
    cd "$INSTALL_DIR"
    git pull origin main
else
    git clone "$MAIN_REPO" "$INSTALL_DIR"
fi

# Python Virtual Environment
print_status "Erstelle Python-Umgebung..."
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate

# Installiere Python-Pakete
print_status "Installiere Python-Abhängigkeiten..."
pip install --upgrade pip >/dev/null 2>&1

# Erstelle requirements-pi.txt wenn nicht vorhanden
if [ ! -f "$INSTALL_DIR/requirements-pi.txt" ]; then
    # Filtere PostgreSQL-spezifische Pakete aus
    grep -v "psycopg2\|pg8000" "$INSTALL_DIR/requirements.txt" > "$INSTALL_DIR/requirements-pi.txt"
    echo "python-dotenv" >> "$INSTALL_DIR/requirements-pi.txt"
    echo "requests" >> "$INSTALL_DIR/requirements-pi.txt"
fi

pip install -r requirements-pi.txt >/dev/null 2>&1

# Lizenz-Validierung mit Python
print_status "Validiere Lizenz mit Server..."
cat > /tmp/validate_license.py << 'EOF'
import sys
import json
import requests
import hashlib
from datetime import datetime

def validate_license(license_key, device_id, hostname):
    try:
        response = requests.post(
            'https://stab.digitmi.de/api/pi/licenses/validate',
            json={
                'license_key': license_key,
                'device_id': device_id,
                'hostname': hostname,
                'pi_version': '1.0.0',
                'registration_type': 'initial'
            },
            timeout=10
        )

        if response.status_code == 200:
            data = response.json()
            # Speichere Lizenz-Info
            with open('/etc/stabsstelle/license.json', 'w') as f:
                json.dump(data, f, indent=2)
            return True, data.get('message', 'Lizenz validiert')
        else:
            return False, response.json().get('error', 'Validierung fehlgeschlagen')
    except Exception as e:
        return False, str(e)

if __name__ == "__main__":
    license_key = sys.argv[1]
    device_id = sys.argv[2]
    hostname = sys.argv[3]

    success, message = validate_license(license_key, device_id, hostname)
    if success:
        print(f"SUCCESS:{message}")
    else:
        print(f"ERROR:{message}")
        sys.exit(1)
EOF

python3 /tmp/validate_license.py "$LICENSE_KEY" "$DEVICE_ID" "$HOSTNAME" || print_error "Lizenz-Validierung fehlgeschlagen"

# Speichere Konfiguration
print_status "Erstelle Konfigurationsdateien..."

# .env Datei
cat > "$INSTALL_DIR/.env" << EOF
# Stabsstelle Pi Configuration
FLASK_APP=run.py
FLASK_ENV=production
SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')

# Datenbank
DATABASE_URL=sqlite:///${DATA_DIR}/stabsstelle.db

# Server-Sync
SYNC_SERVER_URL=${SERVER_URL}
SYNC_DEVICE_ID=${DEVICE_ID}
SYNC_LICENSE_KEY=${LICENSE_KEY}
SYNC_INTERVAL=900  # 15 Minuten

# Pfade
UPLOAD_FOLDER=${DATA_DIR}/uploads
BACKUP_FOLDER=${DATA_DIR}/backups
TILES_FOLDER=${DATA_DIR}/tiles
LOG_FOLDER=${LOG_DIR}

# Features (werden von Lizenz überschrieben)
OFFLINE_MODE=true
ENABLE_SYNC=true
EOF

# Datenbank initialisieren
print_status "Initialisiere Datenbank..."
cd "$INSTALL_DIR"
source venv/bin/activate
export DATABASE_URL="sqlite:///${DATA_DIR}/stabsstelle.db"
flask db upgrade

# Nginx-Konfiguration
print_status "Konfiguriere Nginx..."
cat > /etc/nginx/sites-available/stabsstelle << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name stabsstelle.local _;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8004;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeouts
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
    }

    location /static {
        alias /opt/stabsstelle/app/static;
        expires 1d;
        add_header Cache-Control "public, immutable";
    }

    location /uploads {
        alias /var/lib/stabsstelle/uploads;
        expires 1h;
    }
}
EOF

ln -sf /etc/nginx/sites-available/stabsstelle /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Systemd Services
print_status "Erstelle Systemd-Services..."

# Gunicorn Service
cat > /etc/systemd/system/stabsstelle.service << EOF
[Unit]
Description=Stabsstelle Flask Application
After=network.target

[Service]
Type=notify
User=pi
Group=pi
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${INSTALL_DIR}/venv/bin"
ExecStart=${INSTALL_DIR}/venv/bin/gunicorn \
    --workers 2 \
    --bind 127.0.0.1:8004 \
    --timeout 120 \
    --log-level info \
    --access-logfile ${LOG_DIR}/access.log \
    --error-logfile ${LOG_DIR}/error.log \
    run:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Sync Service
cat > /etc/systemd/system/stabsstelle-sync.service << EOF
[Unit]
Description=Stabsstelle Sync Service
After=network.target stabsstelle.service

[Service]
Type=oneshot
User=pi
Group=pi
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${INSTALL_DIR}/venv/bin"
ExecStart=${INSTALL_DIR}/venv/bin/python scripts/sync.py

[Install]
WantedBy=multi-user.target
EOF

# Sync Timer (alle 15 Minuten)
cat > /etc/systemd/system/stabsstelle-sync.timer << EOF
[Unit]
Description=Stabsstelle Sync Timer
Requires=stabsstelle-sync.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
EOF

# Berechtigungen setzen
print_status "Setze Berechtigungen..."
useradd -r -s /bin/false pi 2>/dev/null || true
chown -R pi:pi "$INSTALL_DIR"
chown -R pi:pi "$DATA_DIR"
chown -R pi:pi "$LOG_DIR"
chown -R pi:pi "$CONFIG_DIR"

# Services aktivieren
print_status "Aktiviere Services..."
systemctl daemon-reload
systemctl enable stabsstelle.service
systemctl enable stabsstelle-sync.timer
systemctl start stabsstelle.service
systemctl start stabsstelle-sync.timer

# Initial-Sync
print_status "Führe initialen Sync durch..."
cd "$INSTALL_DIR"
source venv/bin/activate
python scripts/sync.py --initial || print_warning "Initial-Sync fehlgeschlagen - wird beim nächsten Timer-Lauf wiederholt"

# Firewall
print_status "Konfiguriere Firewall..."
ufw allow 80/tcp 2>/dev/null || true
ufw allow 443/tcp 2>/dev/null || true
ufw allow 22/tcp 2>/dev/null || true

# Abschluss
print_status "Installation abgeschlossen!"
echo ""
echo "============================================"
echo "  Installation erfolgreich!"
echo "============================================"
echo ""
echo "Die Stabsstelle-Anwendung läuft jetzt unter:"
echo "  → http://$(hostname -I | cut -d' ' -f1)"
echo "  → http://stabsstelle.local (mDNS)"
echo ""
echo "Device ID: ${DEVICE_ID}"
echo "Lizenz: ${LICENSE_KEY}"
echo ""
echo "Nächste Schritte:"
echo "  1. Browser öffnen und URL aufrufen"
echo "  2. Mit Server-Zugangsdaten anmelden"
echo "  3. Sync-Status prüfen unter: Einstellungen → Pi-Status"
echo ""
echo "Logs anzeigen:"
echo "  sudo journalctl -u stabsstelle -f"
echo "  sudo journalctl -u stabsstelle-sync -f"
echo ""
echo "Bei Problemen:"
echo "  Support: support@digitmi.de"
echo ""