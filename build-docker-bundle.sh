#!/bin/bash
#
# Build Docker Bundle for Raspberry Pi
# Erstellt ein Docker-Image für ARM-Architektur
#

set -e

echo "============================================"
echo "  Docker Bundle Builder für Raspberry Pi"
echo "============================================"
echo ""

# Variablen
IMAGE_NAME="stabsstelle-pi"
IMAGE_TAG="latest"
OUTPUT_DIR="/root/bundles"
BUNDLE_NAME="stabsstelle-docker-$(date +%Y%m%d).tar"

mkdir -p "$OUTPUT_DIR"

# 1. Docker Image bauen (Multi-Arch)
echo "→ Baue Docker Image für ARM..."

# Für ARM-Architektur (Raspberry Pi)
docker buildx create --name pibuilder --use 2>/dev/null || docker buildx use pibuilder
docker buildx build \
    --platform linux/arm64,linux/arm/v7 \
    -t $IMAGE_NAME:$IMAGE_TAG \
    -f Dockerfile \
    --load \
    . || {
    # Fallback für normale Build
    echo "Buildx fehlgeschlagen, verwende normalen Build..."
    docker build -t $IMAGE_NAME:$IMAGE_TAG .
}

# 2. Image exportieren
echo "→ Exportiere Docker Image..."
docker save $IMAGE_NAME:$IMAGE_TAG | gzip > "$OUTPUT_DIR/$BUNDLE_NAME.gz"

# 3. Installer-Script erstellen
cat > "$OUTPUT_DIR/install-docker.sh" << 'DOCKER_INSTALLER'
#!/bin/bash
#
# Docker Installation für Stabsstelle
#

set -e

echo "============================================"
echo "  Stabsstelle Docker Installation"
echo "============================================"
echo ""

# Docker installieren falls nicht vorhanden
if ! command -v docker &> /dev/null; then
    echo "→ Installiere Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
    echo "Docker installiert. Bitte neu einloggen für Gruppenzugehörigkeit."
fi

# Image laden
echo "→ Lade Docker Image..."
docker load < stabsstelle-docker-*.tar.gz

# Container starten
echo "→ Starte Container..."
docker run -d \
    --name stabsstelle \
    --restart unless-stopped \
    -p 80:80 \
    -v stabsstelle-data:/var/lib/stabsstelle \
    -v stabsstelle-logs:/var/log/stabsstelle \
    stabsstelle-pi:latest

# Status prüfen
sleep 5
if docker ps | grep -q stabsstelle; then
    echo ""
    echo "✓ Container läuft!"
    echo ""
    echo "Zugriff unter: http://$(hostname -I | cut -d' ' -f1)"
    echo ""
    echo "Container-Befehle:"
    echo "  docker logs stabsstelle     # Logs anzeigen"
    echo "  docker stop stabsstelle     # Stoppen"
    echo "  docker start stabsstelle    # Starten"
    echo "  docker restart stabsstelle  # Neustart"
else
    echo "✗ Container konnte nicht gestartet werden"
    docker logs stabsstelle
fi
DOCKER_INSTALLER

chmod +x "$OUTPUT_DIR/install-docker.sh"

# 4. docker-compose.yml erstellen
cat > "$OUTPUT_DIR/docker-compose.yml" << 'COMPOSE'
version: '3.8'

services:
  stabsstelle:
    image: stabsstelle-pi:latest
    container_name: stabsstelle
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - data:/var/lib/stabsstelle
      - logs:/var/log/stabsstelle
    environment:
      - FLASK_ENV=production
      - DATABASE_URL=sqlite:///var/lib/stabsstelle/stabsstelle.db

volumes:
  data:
  logs:
COMPOSE

# Info ausgeben
echo ""
echo "============================================"
echo "  Docker Bundle erstellt!"
echo "============================================"
echo ""
echo "Dateien in $OUTPUT_DIR:"
echo "  - $BUNDLE_NAME.gz (Docker Image)"
echo "  - install-docker.sh (Installer)"
echo "  - docker-compose.yml (Compose-Datei)"
echo ""
echo "Größe: $(du -h $OUTPUT_DIR/$BUNDLE_NAME.gz | cut -f1)"
echo ""
echo "Transfer zum Pi:"
echo "  scp $OUTPUT_DIR/$BUNDLE_NAME.gz pi@raspberry:"
echo "  scp $OUTPUT_DIR/install-docker.sh pi@raspberry:"
echo ""
echo "Installation:"
echo "  ./install-docker.sh"
echo ""