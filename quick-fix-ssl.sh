#!/bin/bash
#
# Quick SSL Fix for Raspberry Pi
#

echo "============================================"
echo "  Quick SSL/Time Fix"
echo "============================================"

# 1. Fix time
echo "1. Fixing system time..."
sudo date -s "$(curl -s http://worldtimeapi.org/api/timezone/Europe/Berlin | grep -oP '"datetime":"\K[^"]+' | cut -d'.' -f1 | tr 'T' ' ')" 2>/dev/null || {
    echo "Setting manual time..."
    sudo date -s "2025-01-25 12:00:00"
}

echo "Current time: $(date)"

# 2. Update CA certificates
echo "2. Updating CA certificates..."
sudo apt-get update
sudo apt-get install -y ca-certificates
sudo update-ca-certificates

# 3. Create pip config without SSL verify (TEMPORARY!)
echo "3. Configuring pip..."
mkdir -p ~/.config/pip
cat > ~/.config/pip/pip.conf << EOF
[global]
index-url = https://pypi.org/simple/
trusted-host = pypi.org
               files.pythonhosted.org
               pypi.python.org
timeout = 120
retries = 5
cert = /etc/ssl/certs/ca-certificates.crt
EOF

echo ""
echo "✓ Fixes applied!"
echo ""
echo "Now try installing again:"
echo "cd /opt/stabsstelle"
echo "source venv/bin/activate"
echo "pip install pytz flask-cors flask-migrate"