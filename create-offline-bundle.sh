#!/bin/bash
#
# Create Offline Installation Bundle for Raspberry Pi
# Läuft auf dem SERVER, nicht auf dem Pi!
#

set -e

echo "============================================"
echo "  Creating Offline Bundle for Pi"
echo "============================================"

BUNDLE_DIR="/tmp/stabsstelle-bundle"
OUTPUT_FILE="/root/stabsstelle-pi-bundle.tar.gz"

# Cleanup old bundle
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# Clone repository
echo "1. Cloning repository..."
cd "$BUNDLE_DIR"
git clone https://github.com/MLeprich/stab.git stabsstelle

# Create virtual environment
echo "2. Creating virtual environment..."
cd stabsstelle
python3 -m venv venv
source venv/bin/activate

# Download all packages
echo "3. Downloading all packages..."
pip download -r requirements.txt -d "$BUNDLE_DIR/packages"

# Create installer script
cat > "$BUNDLE_DIR/install-offline.sh" << 'INSTALLER'
#!/bin/bash
#
# Offline Installer for Stabsstelle
#

echo "Installing Stabsstelle (Offline Mode)..."

# Install from local packages
cd /opt/stabsstelle
source venv/bin/activate

# Install all packages from local directory
pip install --no-index --find-links=/tmp/stabsstelle-bundle/packages -r requirements-sqlite.txt

echo "Installation complete!"
INSTALLER

chmod +x "$BUNDLE_DIR/install-offline.sh"

# Create requirements without PostgreSQL
grep -v "psycopg2\|pg8000" stabsstelle/requirements.txt > "$BUNDLE_DIR/requirements-sqlite.txt"

# Create bundle
echo "4. Creating bundle..."
cd /tmp
tar czf "$OUTPUT_FILE" stabsstelle-bundle/

echo ""
echo "Bundle created: $OUTPUT_FILE"
echo "Size: $(du -h $OUTPUT_FILE | cut -f1)"
echo ""
echo "Transfer to Pi and extract with:"
echo "  scp $OUTPUT_FILE pi@raspberry:"
echo "  tar xzf stabsstelle-pi-bundle.tar.gz"
echo "  cd stabsstelle-bundle"
echo "  ./install-offline.sh"