#!/bin/bash
#
# Docker-basierte Pi Deployment Lösung für Stabsstelle
# Robuste, production-ready Lösung für Endanwender
#

set -e

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "  Stabsstelle Docker Pi Deployment"
echo "============================================"
echo ""
echo "Diese Lösung stellt eine komplette Docker-basierte"
echo "Installation für Raspberry Pi bereit."
echo ""

# 1. Erstelle Docker Compose Setup
cat > docker-compose.yml << 'COMPOSE'
version: '3.8'

services:
  stabsstelle:
    image: stabsstelle:latest
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
  db_data:
  log_data:

networks:
  stabsstelle_net:
    driver: bridge
COMPOSE

# 2. Erstelle minimales Dockerfile für Pi
cat > Dockerfile.pi << 'DOCKERFILE'
# Stabsstelle Pi - Minimal Production Image
FROM python:3.11-slim

# System dependencies
RUN apt-get update && apt-get install -y \
    nginx supervisor sqlite3 curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies (pre-compiled)
COPY wheels/ /wheels/
RUN pip install --no-cache-dir /wheels/*.whl && rm -rf /wheels

# Application
COPY app/ /app/
WORKDIR /app

# Configuration
COPY configs/nginx.conf /etc/nginx/sites-enabled/default
COPY configs/supervisor.conf /etc/supervisor/conf.d/supervisord.conf
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Volumes
VOLUME ["/var/lib/stabsstelle", "/var/log/stabsstelle"]

# Ports
EXPOSE 80

# Health check
HEALTHCHECK CMD curl -f http://localhost/ || exit 1

# Start
ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

# 3. Erstelle Bundle-Builder
cat > create-pi-bundle.sh << 'BUNDLE_SCRIPT'
#!/bin/bash
#
# Erstellt komplettes Deployment-Bundle für Pi
#

set -e

echo "Creating Stabsstelle Pi Bundle..."

BUNDLE_DIR="stabsstelle-pi-bundle"
rm -rf $BUNDLE_DIR
mkdir -p $BUNDLE_DIR/{app,wheels,configs,scripts}

# 1. Kopiere Anwendung
echo "→ Copying application..."
cp -r /root/projects/Stabsstelle/* $BUNDLE_DIR/app/
rm -rf $BUNDLE_DIR/app/{.git,venv,__pycache__}

# 2. Download wheels für ARM
echo "→ Downloading Python wheels..."
cd $BUNDLE_DIR
cat > requirements.txt << 'REQS'
Flask==3.0.0
Flask-Login==0.6.3
Flask-SQLAlchemy==3.1.1
Flask-Migrate==4.0.5
Flask-WTF==1.2.1
Flask-CORS==4.0.0
Flask-SocketIO==5.3.5
SQLAlchemy==2.0.23
gunicorn==21.2.0
eventlet==0.33.3
python-dotenv==1.0.0
redis==5.0.1
requests==2.31.0
Pillow==10.1.0
psutil==5.9.6
alembic==1.13.1
REQS

pip download -r requirements.txt -d wheels/ \
    --platform linux_armv7l --python-version 3.11 --no-deps || \
pip download -r requirements.txt -d wheels/

# 3. Nginx config
cat > configs/nginx.conf << 'NGINX'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8004;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /static {
        alias /app/app/static;
    }
}
NGINX

# 4. Supervisor config
cat > configs/supervisor.conf << 'SUPERVISOR'
[supervisord]
nodaemon=true

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"

[program:gunicorn]
command=gunicorn --bind 127.0.0.1:8004 run:app
directory=/app
SUPERVISOR

# 5. Entrypoint
cat > scripts/entrypoint.sh << 'ENTRYPOINT'
#!/bin/bash
if [ ! -f /var/lib/stabsstelle/stabsstelle.db ]; then
    cd /app && flask db upgrade || flask db init && flask db upgrade
fi
exec supervisord -c /etc/supervisor/conf.d/supervisord.conf
ENTRYPOINT

# 6. Install script für Pi
cat > install.sh << 'INSTALLER'
#!/bin/bash
echo "Installing Stabsstelle on Pi..."

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker $USER
fi

# Build image
docker build -t stabsstelle:latest -f Dockerfile.pi .

# Start with docker-compose
docker-compose up -d

echo "Installation complete!"
echo "Access at: http://$(hostname -I | cut -d' ' -f1)"
INSTALLER

chmod +x install.sh
cd ..

# Create archive
tar czf stabsstelle-pi-docker-bundle.tar.gz $BUNDLE_DIR/

echo "Bundle created: stabsstelle-pi-docker-bundle.tar.gz"
echo "Size: $(du -h stabsstelle-pi-docker-bundle.tar.gz | cut -f1)"
BUNDLE_SCRIPT

chmod +x create-pi-bundle.sh

# 4. Erstelle ARM-kompatibles Image mit buildx
cat > build-arm.sh << 'ARM_BUILD'
#!/bin/bash
#
# Build ARM-compatible Docker image
#

echo "Building ARM Docker image..."

# Setup buildx if not exists
docker buildx create --name pibuilder --use || docker buildx use pibuilder

# Build for ARM platforms
docker buildx build \
    --platform linux/arm64,linux/arm/v7 \
    -t stabsstelle:arm \
    -f Dockerfile.pi \
    --push \
    .

echo "ARM image built and pushed!"
ARM_BUILD

chmod +x build-arm.sh

echo ""
echo -e "${GREEN}✓${NC} Docker Pi Deployment Solution erstellt!"
echo ""
echo "Verfügbare Optionen:"
echo ""
echo "1. Bundle für Offline-Installation erstellen:"
echo "   ${YELLOW}./create-pi-bundle.sh${NC}"
echo ""
echo "2. ARM-Image bauen (benötigt Docker Hub Account):"
echo "   ${YELLOW}./build-arm.sh${NC}"
echo ""
echo "3. Direkte Installation auf Pi mit Docker:"
echo "   ${YELLOW}docker-compose up -d${NC}"
echo ""
echo "Für Endanwender:"
echo "- Bundle herunterladen"
echo "- Entpacken: tar xzf stabsstelle-pi-docker-bundle.tar.gz"
echo "- Installieren: cd stabsstelle-pi-bundle && ./install.sh"
echo ""