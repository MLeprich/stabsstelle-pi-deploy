#!/bin/bash
#
# Stabsstelle Pi - Easy Install
# Der einfachste Weg zur Installation
#

# Wechsel in Home-Verzeichnis des Users
cd ~ || cd /tmp

# Download des Setup-Scripts
echo "Lade Setup-Script herunter..."
wget -q https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/setup.sh -O stabsstelle-setup.sh

# Ausführbar machen
chmod +x stabsstelle-setup.sh

# Ausführen
./stabsstelle-setup.sh

# Aufräumen
rm -f stabsstelle-setup.sh