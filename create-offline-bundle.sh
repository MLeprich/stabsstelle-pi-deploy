#!/bin/bash
#
# Create Offline Bundle for Stabsstelle Docker Deployment
#

set -e

echo "============================================"
echo "  Creating Offline Bundle"
echo "============================================"
echo ""

BUNDLE_NAME="stabsstelle-docker-bundle"
BUNDLE_DIR="/tmp/$BUNDLE_NAME"
OUTPUT_FILE="$BUNDLE_NAME-$(date +%Y%m%d).tar.gz"

# Cleanup
rm -rf $BUNDLE_DIR
mkdir -p $BUNDLE_DIR

# 1. Docker Image exportieren
echo "→ Exporting Docker image..."
docker pull ghcr.io/mleprich/stabsstelle:latest || {
    echo "Building local image..."
    cd docker
    docker build -t ghcr.io/mleprich/stabsstelle:latest -f Dockerfile.production .
    cd ..
}
docker save ghcr.io/mleprich/stabsstelle:latest | gzip > $BUNDLE_DIR/stabsstelle.tar.gz

# 2. Docker Compose kopieren
echo "→ Copying Docker Compose files..."
cp docker/docker-compose.yml $BUNDLE_DIR/
cp docker/install-docker.sh $BUNDLE_DIR/

# 3. Offline Installer erstellen
cat > $BUNDLE_DIR/install-offline.sh << 'INSTALLER'
#!/bin/bash
#
# Offline Installer for Stabsstelle Docker
#

set -e

echo "============================================"
echo "  Stabsstelle Offline Installation"
echo "============================================"
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker ist nicht installiert!"
    echo "Bitte installieren Sie Docker zuerst:"
    echo "  curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# Load Docker image
echo "→ Loading Docker image..."
docker load < stabsstelle.tar.gz

# Create installation directory
INSTALL_DIR="/opt/stabsstelle-docker"
mkdir -p $INSTALL_DIR
cp docker-compose.yml $INSTALL_DIR/

# Start container
cd $INSTALL_DIR
docker-compose down 2>/dev/null || true
docker-compose up -d

# Wait for startup
sleep 10

# Check status
if docker ps | grep -q stabsstelle; then
    IP=$(hostname -I | cut -d' ' -f1)
    echo ""
    echo "✓ Installation erfolgreich!"
    echo ""
    echo "Zugriff: http://$IP"
    echo ""
else
    echo "ERROR: Container konnte nicht gestartet werden"
    docker logs stabsstelle
fi
INSTALLER

chmod +x $BUNDLE_DIR/install-offline.sh

# 4. README hinzufügen
cat > $BUNDLE_DIR/README.txt << 'README'
Stabsstelle Docker Offline Bundle
==================================

Dieses Bundle enthält alles für eine Offline-Installation:

1. Docker Image (stabsstelle.tar.gz)
2. Docker Compose Konfiguration
3. Installer-Scripts

Installation:
-------------
1. Bundle entpacken: tar xzf stabsstelle-docker-bundle-*.tar.gz
2. In Verzeichnis wechseln: cd stabsstelle-docker-bundle
3. Installer ausführen: sudo ./install-offline.sh

Voraussetzungen:
---------------
- Docker muss installiert sein
- Port 80 muss frei sein

Nach der Installation:
---------------------
- Web-Interface: http://[PI-IP]
- Standard-Login: admin / admin
- Logs: docker logs stabsstelle

Support:
--------
https://github.com/MLeprich/stabsstelle-pi-deploy/issues
README

# 5. Bundle erstellen
echo "→ Creating bundle archive..."
cd /tmp
tar czf $OUTPUT_FILE $BUNDLE_NAME/

# Größe für GitHub prüfen (100MB Limit)
SIZE=$(du -m $OUTPUT_FILE | cut -f1)
if [ $SIZE -gt 95 ]; then
    echo "→ Bundle zu groß für GitHub ($SIZE MB), teile auf..."

    # In 95MB Teile splitten
    split -b 95M $OUTPUT_FILE $OUTPUT_FILE.part-
    rm $OUTPUT_FILE

    # Merge-Script erstellen
    cat > merge-bundle.sh << 'MERGE'
#!/bin/bash
cat stabsstelle-docker-bundle-*.part-* > stabsstelle-docker-bundle.tar.gz
rm stabsstelle-docker-bundle-*.part-*
echo "Bundle zusammengefügt: stabsstelle-docker-bundle.tar.gz"
MERGE
    chmod +x merge-bundle.sh

    echo ""
    echo "Bundle aufgeteilt in:"
    ls -lh $OUTPUT_FILE.part-*
    echo ""
    echo "Zum Zusammenfügen: ./merge-bundle.sh"
else
    echo ""
    echo "✓ Bundle erstellt: $OUTPUT_FILE"
    echo "  Größe: $SIZE MB"
fi

# Cleanup
rm -rf $BUNDLE_DIR

echo ""
echo "Nächste Schritte:"
echo "1. Bundle zu GitHub Releases hochladen"
echo "2. README.md mit Download-Links aktualisieren"
echo ""