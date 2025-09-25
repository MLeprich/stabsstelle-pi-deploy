#!/bin/bash
#
# Einfaches Bundle für Stabsstelle Pi
# Kopiert nur die notwendigen Dateien
#

set -e

echo "============================================"
echo "  Stabsstelle Simple Bundle Creator"
echo "============================================"
echo ""

# Variablen
BUNDLE_DIR="/tmp/stabsstelle-bundle"
OUTPUT_FILE="/root/stabsstelle-bundle-$(date +%Y%m%d-%H%M%S).tar.gz"

# Cleanup
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# 1. App kopieren
echo "→ Kopiere Anwendung..."
cp -r /root/projects/Stabsstelle "$BUNDLE_DIR/app"
rm -rf "$BUNDLE_DIR/app/.git"
rm -rf "$BUNDLE_DIR/app/venv"
rm -rf "$BUNDLE_DIR/app/__pycache__"
rm -rf "$BUNDLE_DIR/app/**/__pycache__"

# 2. Requirements erstellen
echo "→ Erstelle Requirements..."
cd "$BUNDLE_DIR/app"
grep -v "psycopg2\|pg8000\|postgresql\|stress-ng" requirements.txt > requirements-pi.txt || {
    # Fallback: Minimale Requirements
    cat > requirements-pi.txt << 'REQUIREMENTS'
Flask==3.0.0
Flask-Login==0.6.3
Flask-SQLAlchemy==3.1.1
Flask-Migrate==4.0.5
Flask-WTF==1.2.1
Flask-CORS==4.0.0
SQLAlchemy==2.0.23
WTForms==3.1.1
python-dotenv==1.0.0
gunicorn==21.2.0
requests==2.31.0
Werkzeug==3.0.1
Jinja2==3.1.2
click==8.1.7
cryptography==41.0.7
python-dateutil==2.8.2
pytz==2023.3
redis==5.0.1
Flask-Caching==2.1.0
Flask-Mail==0.9.1
Flask-SocketIO==5.3.5
python-socketio==5.11.0
eventlet==0.33.3
pillow==10.1.0
qrcode==7.4.2
markdown==3.5.1
bleach==6.1.0
REQUIREMENTS
}

# 3. Installer erstellen
echo "→ Erstelle Installer..."
cat > "$BUNDLE_DIR/install.sh" << 'INSTALLER'
#!/bin/bash

set -e

echo "============================================"
echo "  Stabsstelle Pi Installation"
echo "============================================"
echo ""

# Prüfe Root
if [ "$EUID" -ne 0 ]; then
    echo "Bitte als root ausführen: sudo ./install.sh"
    exit 1
fi

# Variablen
INSTALL_DIR="/opt/stabsstelle"
DATA_DIR="/var/lib/stabsstelle"
LOG_DIR="/var/log/stabsstelle"

echo "→ Installiere System-Pakete..."
apt-get update
apt-get install -y \
    python3-pip python3-venv python3-dev \
    build-essential libssl-dev libffi-dev \
    nginx sqlite3 \
    libxml2-dev libxslt1-dev \
    libjpeg-dev zlib1g-dev

echo "→ Erstelle Verzeichnisse..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR"/{uploads,backups,tiles}
mkdir -p "$LOG_DIR"

echo "→ Kopiere Anwendung..."
cp -r app/* "$INSTALL_DIR/"

echo "→ Erstelle Python-Umgebung..."
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate

echo "→ Installiere Python-Pakete..."
pip install --upgrade pip setuptools wheel

# Installiere mit Fehlertoleranz
while IFS= read -r package; do
    if [ ! -z "$package" ] && [[ ! "$package" == "#"* ]]; then
        echo "  Installing: $package"
        pip install "$package" || echo "  Warning: Failed to install $package"
    fi
done < requirements-pi.txt

echo "→ Erstelle Konfiguration..."
cat > "$INSTALL_DIR/.env" << EOF
FLASK_APP=run.py
FLASK_ENV=production
SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
DATABASE_URL=sqlite:///${DATA_DIR}/stabsstelle.db
SERVER_NAME=stabsstelle.local
UPLOAD_FOLDER=${DATA_DIR}/uploads
EOF

echo "→ Initialisiere Datenbank..."
export DATABASE_URL="sqlite:///${DATA_DIR}/stabsstelle.db"
python3 -c "from app import create_app, db; app = create_app(); app.app_context().push(); db.create_all()" || {
    echo "  Datenbank-Init fehlgeschlagen, versuche Migration..."
    flask db init
    flask db migrate -m "Initial"
    flask db upgrade
}

echo "→ Konfiguriere Nginx..."
cat > /etc/nginx/sites-available/stabsstelle << 'NGINX'
server {
    listen 80;
    server_name _;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8004;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300;
    }

    location /static {
        alias /opt/stabsstelle/app/static;
        expires 30d;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/stabsstelle /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

echo "→ Erstelle Systemd-Service..."
cat > /etc/systemd/system/stabsstelle.service << SERVICE
[Unit]
Description=Stabsstelle Application
After=network.target

[Service]
User=root
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${INSTALL_DIR}/venv/bin"
ExecStart=${INSTALL_DIR}/venv/bin/gunicorn --workers 2 --bind 127.0.0.1:8004 --timeout 120 run:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable stabsstelle
systemctl start stabsstelle

echo ""
echo "============================================"
echo "  Installation abgeschlossen!"
echo "============================================"
echo ""
echo "Zugriff: http://$(hostname -I | cut -d' ' -f1)"
echo ""
echo "Services:"
echo "  systemctl status stabsstelle"
echo "  systemctl restart stabsstelle"
echo "  journalctl -u stabsstelle -f"
echo ""
INSTALLER

chmod +x "$BUNDLE_DIR/install.sh"

# 4. README
cat > "$BUNDLE_DIR/README.txt" << 'README'
Stabsstelle Pi Bundle
=====================

Installation:
1. Bundle entpacken: tar xzf stabsstelle-bundle-*.tar.gz
2. In Verzeichnis wechseln: cd stabsstelle-bundle
3. Installieren: sudo ./install.sh

Nach Installation:
- Web-Interface: http://[PI-IP]
- Standard-Login: admin / admin (bitte ändern!)

Bei Problemen:
- Logs: sudo journalctl -u stabsstelle -f
- Neustart: sudo systemctl restart stabsstelle
README

# 5. Bundle erstellen
echo "→ Erstelle Bundle-Archiv..."
cd /tmp
tar czf "$OUTPUT_FILE" stabsstelle-bundle/

# Cleanup
rm -rf "$BUNDLE_DIR"

echo ""
echo "============================================"
echo "  Bundle erstellt!"
echo "============================================"
echo ""
echo "Datei: $OUTPUT_FILE"
echo "Größe: $(du -h $OUTPUT_FILE | cut -f1)"
echo ""
echo "Transfer zum Pi:"
echo "  scp $OUTPUT_FILE pi@[PI-IP]:~/"
echo ""
echo "Installation auf Pi:"
echo "  tar xzf $(basename $OUTPUT_FILE)"
echo "  cd stabsstelle-bundle"
echo "  sudo ./install.sh"
echo ""