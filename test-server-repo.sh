#!/bin/bash
#
# Test Server Repository Access
#

echo "Testing Server Repository Access..."
echo ""

# Test credentials
USER="pi-deploy"
PASS="$1"

if [ -z "$PASS" ]; then
    echo "Usage: $0 <password>"
    echo ""
    echo "Test with: git ls-remote http://pi-deploy:PASSWORD@91.99.228.2:8090/git/stabsstelle.git"
    exit 1
fi

echo "Testing connection to: http://91.99.228.2:8090/git/stabsstelle.git"
echo "Username: $USER"
echo ""

# Test git ls-remote
git ls-remote "http://${USER}:${PASS}@91.99.228.2:8090/git/stabsstelle.git" HEAD

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Server-Repository ist erreichbar!"
    echo ""
    echo "Verwende beim pi-install.sh:"
    echo "  Option: 2 (Server-Repository)"
    echo "  Username: pi-deploy"
    echo "  Password: $PASS"
else
    echo ""
    echo "✗ Verbindung fehlgeschlagen"
    echo ""
    echo "Prüfe:"
    echo "1. Ist Port 8090 offen?"
    echo "2. Läuft nginx?"
    echo "3. Stimmt das Passwort?"
fi