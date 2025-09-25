#!/bin/bash
#
# Fix Pip Network Issues on Raspberry Pi
#

echo "============================================"
echo "  Pip Network Fix für Raspberry Pi"
echo "============================================"
echo ""

# 1. Teste Netzwerk
echo "1. Teste Internet-Verbindung..."
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "✓ Internet funktioniert"
else
    echo "✗ Keine Internet-Verbindung!"
    echo "Bitte Netzwerk prüfen und erneut versuchen."
    exit 1
fi

# 2. Teste DNS
echo "2. Teste DNS..."
if nslookup pypi.org >/dev/null 2>&1; then
    echo "✓ DNS funktioniert"
else
    echo "✗ DNS Problem erkannt"
    echo "Setze Google DNS..."
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
    echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf
fi

# 3. Update pip
echo "3. Update pip..."
python3 -m pip install --upgrade pip

# 4. Setze pip config
echo "4. Konfiguriere pip..."
mkdir -p ~/.config/pip
cat > ~/.config/pip/pip.conf << EOF
[global]
timeout = 120
index-url = https://pypi.org/simple/
trusted-host = pypi.org
               pypi.python.org
               files.pythonhosted.org
retries = 5
EOF

# 5. Teste pip
echo "5. Teste pip Installation..."
pip install --upgrade pip setuptools wheel

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Pip funktioniert jetzt!"
    echo ""
    echo "Du kannst jetzt die Installation fortsetzen:"
    echo "cd /opt/stabsstelle"
    echo "source venv/bin/activate"
    echo "pip install -r requirements-pi.txt"
else
    echo ""
    echo "✗ Pip hat weiterhin Probleme"
    echo ""
    echo "Alternative Lösung:"
    echo "1. Verwende einen Proxy wenn verfügbar"
    echo "2. Oder lade Pakete manuell herunter"
fi