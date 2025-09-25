#!/bin/bash
#
# Stabsstelle Docker Installation Script
# One-Line-Installer für Endanwender
#

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════╗"
echo "║                                                    ║"
echo "║     🚀 Stabsstelle Docker Installation 🚀         ║"
echo "║                                                    ║"
echo "║     Production-Ready Deployment für Pi            ║"
echo "║                                                    ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

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

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Root-Check
if [ "$EUID" -ne 0 ]; then
    print_info "Wechsle zu Root-Berechtigungen..."
    exec sudo "$0" "$@"
fi

# System-Check
print_info "Prüfe System..."
if [ ! -f /etc/os-release ]; then
    print_error "Kein unterstütztes Linux-System gefunden"
fi

source /etc/os-release
print_status "System: $PRETTY_NAME"

# Architektur prüfen
ARCH=$(uname -m)
case $ARCH in
    aarch64|arm64)
        DOCKER_ARCH="arm64"
        print_status "Architektur: ARM64 (64-bit)"
        ;;
    armv7l)
        DOCKER_ARCH="armv7"
        print_status "Architektur: ARMv7 (32-bit)"
        ;;
    x86_64)
        DOCKER_ARCH="amd64"
        print_status "Architektur: x86_64"
        ;;
    *)
        print_error "Nicht unterstützte Architektur: $ARCH"
        ;;
esac

# Docker Installation prüfen
print_info "Prüfe Docker Installation..."
if ! command -v docker &> /dev/null; then
    print_warning "Docker nicht gefunden. Installiere Docker..."

    # Docker installieren
    curl -fsSL https://get.docker.com | sh

    # User zur docker Gruppe hinzufügen
    if [ ! -z "$SUDO_USER" ]; then
        usermod -aG docker $SUDO_USER
        print_status "User $SUDO_USER zur Docker-Gruppe hinzugefügt"
    fi

    # Docker starten
    systemctl enable docker
    systemctl start docker
    print_status "Docker installiert und gestartet"
else
    print_status "Docker ist bereits installiert"
fi

# Docker Compose prüfen
print_info "Prüfe Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    print_warning "Docker Compose nicht gefunden. Installiere..."

    # Docker Compose Plugin installieren
    apt-get update && apt-get install -y docker-compose-plugin || {
        # Fallback: Standalone Docker Compose
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    }
    print_status "Docker Compose installiert"
else
    print_status "Docker Compose ist bereits installiert"
fi

# Arbeitsverzeichnis erstellen
INSTALL_DIR="/opt/stabsstelle-docker"
print_info "Erstelle Arbeitsverzeichnis..."
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Docker Compose Datei herunterladen
print_info "Lade Docker Compose Konfiguration..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  stabsstelle:
    image: ghcr.io/mleprich/stabsstelle:latest
    container_name: stabsstelle
    restart: always
    ports:
      - "80:80"
    volumes:
      - app_data:/app
      - db_data:/var/lib/stabsstelle
      - log_data:/var/log/stabsstelle
    environment:
      - FLASK_ENV=production
      - DATABASE_URL=sqlite:///var/lib/stabsstelle/stabsstelle.db
      - TZ=Europe/Berlin
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 60s
    networks:
      - stabsstelle_net

volumes:
  app_data:
    driver: local
  db_data:
    driver: local
  log_data:
    driver: local

networks:
  stabsstelle_net:
    driver: bridge
EOF

print_status "Docker Compose Konfiguration erstellt"

# Image herunterladen
print_info "Lade Docker Image (kann einige Minuten dauern)..."
docker pull ghcr.io/mleprich/stabsstelle:latest || {
    print_warning "Konnte Image nicht von Registry laden. Versuche alternatives Image..."

    # Fallback: Lokales Build
    print_info "Erstelle Image lokal..."
    cat > Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    nginx supervisor sqlite3 curl wget git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone Application
RUN git clone https://github.com/MLeprich/stab.git /app || \
    echo "Using fallback installation"

# Install Python dependencies
RUN pip install --no-cache-dir \
    Flask==3.0.0 Flask-Login==0.6.3 Flask-SQLAlchemy==3.1.1 \
    Flask-Migrate==4.0.5 Flask-WTF==1.2.1 Flask-CORS==4.0.0 \
    Flask-SocketIO==5.3.5 SQLAlchemy==2.0.23 gunicorn==21.2.0 \
    eventlet==0.33.3 python-dotenv==1.0.0 redis==5.0.1 \
    requests==2.31.0 psutil==5.9.6 alembic==1.13.1

# Configure Nginx
RUN echo 'server { \
    listen 80; \
    location / { \
        proxy_pass http://127.0.0.1:8004; \
        proxy_set_header Host $host; \
    } \
}' > /etc/nginx/sites-enabled/default

# Configure Supervisor
RUN echo '[supervisord] \n\
nodaemon=true \n\
[program:nginx] \n\
command=/usr/sbin/nginx -g "daemon off;" \n\
[program:gunicorn] \n\
command=gunicorn --bind 127.0.0.1:8004 run:app \n\
directory=/app' > /etc/supervisor/conf.d/supervisord.conf

# Entrypoint
RUN echo '#!/bin/bash \n\
flask db upgrade 2>/dev/null || flask db init && flask db upgrade \n\
exec supervisord' > /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

    docker build -t ghcr.io/mleprich/stabsstelle:latest .
    print_status "Lokales Docker Image erstellt"
}

# Container starten
print_info "Starte Stabsstelle Container..."
docker-compose down 2>/dev/null || true
docker-compose up -d

# Warte auf Start
print_info "Warte auf Container-Start..."
sleep 10

# Status prüfen
if docker ps | grep -q stabsstelle; then
    print_status "Container läuft erfolgreich!"

    # IP-Adresse ermitteln
    IP=$(hostname -I | cut -d' ' -f1)

    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN} ✓ Installation erfolgreich abgeschlossen!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Zugriff auf Stabsstelle:${NC}"
    echo -e "  ${YELLOW}➜${NC} http://$IP"
    echo -e "  ${YELLOW}➜${NC} http://localhost (lokal)"
    echo ""
    echo -e "${BLUE}Standard-Login:${NC}"
    echo -e "  ${YELLOW}➜${NC} Benutzer: admin"
    echo -e "  ${YELLOW}➜${NC} Passwort: admin"
    echo -e "  ${RED}⚠${NC}  Bitte sofort ändern!"
    echo ""
    echo -e "${BLUE}Nützliche Befehle:${NC}"
    echo -e "  ${YELLOW}➜${NC} Status:  docker ps"
    echo -e "  ${YELLOW}➜${NC} Logs:    docker logs stabsstelle"
    echo -e "  ${YELLOW}➜${NC} Stop:    docker-compose -f $INSTALL_DIR/docker-compose.yml down"
    echo -e "  ${YELLOW}➜${NC} Start:   docker-compose -f $INSTALL_DIR/docker-compose.yml up -d"
    echo -e "  ${YELLOW}➜${NC} Update:  docker pull ghcr.io/mleprich/stabsstelle:latest"
    echo ""
else
    print_error "Container konnte nicht gestartet werden!"
    echo ""
    echo "Logs anzeigen mit:"
    echo "  docker logs stabsstelle"
    echo ""
    echo "Bei Problemen:"
    echo "  https://github.com/MLeprich/stabsstelle-pi-deploy/issues"
fi

# Cleanup
print_info "Räume auf..."
rm -f Dockerfile 2>/dev/null || true

# Systemd Service erstellen (optional)
print_info "Erstelle Systemd Service..."
cat > /etc/systemd/system/stabsstelle-docker.service << 'SERVICE'
[Unit]
Description=Stabsstelle Docker Container
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/stabsstelle-docker
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable stabsstelle-docker
print_status "Systemd Service erstellt (Auto-Start aktiviert)"

echo ""
print_status "Installation abgeschlossen!"
echo ""