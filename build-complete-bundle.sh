#!/bin/bash
#
# Build Complete Offline Bundle for Stabsstelle Pi
# Dieses Script läuft auf dem SERVER und erstellt ein komplettes Bundle
#

set -e

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

echo "============================================"
echo "  Stabsstelle Complete Bundle Builder"
echo "============================================"
echo ""

# Konfiguration
WORK_DIR="/tmp/stabsstelle-bundle-$(date +%Y%m%d-%H%M%S)"
BUNDLE_NAME="stabsstelle-pi-complete-$(date +%Y%m%d).tar.gz"
OUTPUT_DIR="/root/bundles"

mkdir -p "$OUTPUT_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# 1. Repository vorbereiten
print_status "Kopiere lokales Repository..."
cd "$WORK_DIR"
# Verwende das lokale Repository statt zu klonen
cp -r /root/projects/Stabsstelle app
# Entferne .git um Platz zu sparen
rm -rf app/.git

# 2. Python-Dependencies herunterladen
print_status "Lade Python-Pakete..."
cd "$WORK_DIR"
mkdir -p packages

# Erstelle temporäre venv für Download
python3 -m venv temp_venv
source temp_venv/bin/activate

# Upgrade pip
pip install --upgrade pip wheel setuptools

# Download ALLE Pakete (für offline Installation)
cd "$WORK_DIR/app"

# Bereinigte Requirements ohne PostgreSQL
grep -v "psycopg2\|pg8000\|postgresql" requirements.txt > requirements-pi.txt

# Download alle Pakete UND deren Dependencies
pip download -r requirements-pi.txt -d "$WORK_DIR/packages" \
    --platform linux_armv7l --python-version 3.11 --no-deps 2>/dev/null || \
pip download -r requirements-pi.txt -d "$WORK_DIR/packages"

deactivate

# 3. Installer-Script erstellen
print_status "Erstelle Installer..."
cat > "$WORK_DIR/install.sh" << 'INSTALLER_SCRIPT'
#!/bin/bash
#
# Stabsstelle Pi - Offline Installer
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

echo "============================================"
echo "  Stabsstelle Offline Installation"
echo "============================================"
echo ""

# Root check
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# Variablen
INSTALL_DIR="/opt/stabsstelle"
DATA_DIR="/var/lib/stabsstelle"
LOG_DIR="/var/log/stabsstelle"
BUNDLE_DIR="$(dirname "$0")"

# System vorbereiten
print_status "Installiere System-Abhängigkeiten..."
apt-get update
apt-get install -y \
    python3-pip python3-venv python3-dev \
    build-essential libssl-dev libffi-dev \
    nginx redis-server sqlite3 \
    git curl wget

# Verzeichnisse erstellen
print_status "Erstelle Verzeichnisse..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR"/{uploads,backups,tiles}
mkdir -p "$LOG_DIR"

# App kopieren
print_status "Kopiere Anwendung..."
cp -r "$BUNDLE_DIR/app/"* "$INSTALL_DIR/"

# Virtual Environment
print_status "Erstelle Python-Umgebung..."
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate

# Pip upgrade
pip install --upgrade pip setuptools wheel

# Installiere Pakete aus lokalem Verzeichnis
print_status "Installiere Python-Pakete (Offline)..."
pip install --no-index --find-links="$BUNDLE_DIR/packages" -r requirements-pi.txt

# Environment-Datei
print_status "Erstelle Konfiguration..."
cat > "$INSTALL_DIR/.env" << EOF
FLASK_APP=run.py
FLASK_ENV=production
SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
DATABASE_URL=sqlite:///${DATA_DIR}/stabsstelle.db
SYNC_SERVER_URL=https://stab.digitmi.de
UPLOAD_FOLDER=${DATA_DIR}/uploads
BACKUP_FOLDER=${DATA_DIR}/backups
LOG_FOLDER=${LOG_DIR}
OFFLINE_MODE=true
EOF

# Datenbank initialisieren
print_status "Initialisiere Datenbank..."
export DATABASE_URL="sqlite:///${DATA_DIR}/stabsstelle.db"
flask db upgrade || {
    flask db init
    flask db migrate -m "Initial migration"
    flask db upgrade
}

# Nginx konfigurieren
print_status "Konfiguriere Nginx..."
cat > /etc/nginx/sites-available/stabsstelle << 'NGINX_CONF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8004;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /static {
        alias /opt/stabsstelle/app/static;
        expires 1d;
    }
}
NGINX_CONF

ln -sf /etc/nginx/sites-available/stabsstelle /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx

# Systemd Service
print_status "Erstelle Systemd-Service..."
cat > /etc/systemd/system/stabsstelle.service << SERVICE
[Unit]
Description=Stabsstelle Flask Application
After=network.target

[Service]
User=root
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${INSTALL_DIR}/venv/bin"
ExecStart=${INSTALL_DIR}/venv/bin/gunicorn --workers 2 --bind 127.0.0.1:8004 run:app
Restart=always

[Install]
WantedBy=multi-user.target
SERVICE

# Services starten
print_status "Starte Services..."
systemctl daemon-reload
systemctl enable stabsstelle
systemctl start stabsstelle

# Status
sleep 2
if systemctl is-active --quiet stabsstelle; then
    print_status "Installation erfolgreich!"
    echo ""
    echo "Zugriff unter: http://$(hostname -I | cut -d' ' -f1)"
    echo ""
else
    print_error "Service konnte nicht gestartet werden"
fi
INSTALLER_SCRIPT

chmod +x "$WORK_DIR/install.sh"

# 4. README erstellen
print_status "Erstelle Dokumentation..."
cat > "$WORK_DIR/README.md" << 'README'
# Stabsstelle Pi - Offline Installation Bundle

## Inhalt
- Komplette Stabsstelle-Anwendung
- Alle Python-Dependencies (offline)
- Installer-Script
- Nginx-Konfiguration
- Systemd-Services

## Installation

1. Bundle auf Pi übertragen:
```bash
scp stabsstelle-pi-complete-*.tar.gz pi@raspberry:
```

2. Auf dem Pi entpacken:
```bash
tar xzf stabsstelle-pi-complete-*.tar.gz
cd stabsstelle-bundle
```

3. Installation starten:
```bash
sudo ./install.sh
```

## Nach der Installation

- Web-Interface: http://[PI-IP-ADRESSE]
- Logs: /var/log/stabsstelle/
- Daten: /var/lib/stabsstelle/

## Services

```bash
# Status prüfen
sudo systemctl status stabsstelle

# Neustart
sudo systemctl restart stabsstelle

# Logs
sudo journalctl -u stabsstelle -f
```
README

# 5. Bundle erstellen
print_status "Erstelle Bundle..."
cd "$WORK_DIR/.."
tar czf "$OUTPUT_DIR/$BUNDLE_NAME" "$(basename $WORK_DIR)"

# Cleanup
rm -rf "$WORK_DIR"

# Info
echo ""
echo "============================================"
echo "  Bundle erfolgreich erstellt!"
echo "============================================"
echo ""
echo "Datei: $OUTPUT_DIR/$BUNDLE_NAME"
echo "Größe: $(du -h $OUTPUT_DIR/$BUNDLE_NAME | cut -f1)"
echo ""
echo "Transfer zum Pi:"
echo "  scp $OUTPUT_DIR/$BUNDLE_NAME stabadmin@[PI-IP]:"
echo ""
echo "Installation auf dem Pi:"
echo "  tar xzf $BUNDLE_NAME"
echo "  cd stabsstelle-bundle-*"
echo "  sudo ./install.sh"
echo ""