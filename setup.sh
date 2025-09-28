#!/bin/bash
# Setup-Skript für Stabsstelle Pi-Deployment

set -e

echo "🚀 Stabsstelle Pi-Deployment Setup"
echo "=================================="

# Hostname setzen
echo "📝 Hostname auf 'stab' setzen..."
sudo hostnamectl set-hostname stab
sudo sed -i 's/127.0.1.1.*/127.0.1.1\tstab stab.local/' /etc/hosts

# SSL-Zertifikat erstellen
echo "🔐 SSL-Zertifikat erstellen..."
sudo mkdir -p /etc/ssl/stab
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/ssl/stab/stab.key \
  -out /etc/ssl/stab/stab.crt \
  -subj "/C=DE/ST=Bayern/L=Muenchen/O=Stabsstelle/CN=stab.local" \
  -addext "subjectAltName=DNS:stab.local,DNS:stab,DNS:localhost,IP:$(hostname -I | awk '{print $1}'),IP:127.0.0.1"

sudo chmod 644 /etc/ssl/stab/stab.crt
sudo chmod 600 /etc/ssl/stab/stab.key

# Nginx installieren
echo "📦 Nginx installieren..."
sudo apt-get update
sudo apt-get install -y nginx

# Nginx konfigurieren
echo "⚙️ Nginx konfigurieren..."
sudo cp nginx/stabsstelle.conf /etc/nginx/sites-available/stabsstelle
sudo ln -sf /etc/nginx/sites-available/stabsstelle /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl enable nginx
sudo systemctl restart nginx

# Docker-Images bauen
echo "🐳 Docker-Images bauen..."
docker build -t stabsstelle-base:latest .

# Bestehende Container stoppen
echo "🛑 Alte Container stoppen..."
docker stop stabsstelle-sqlite 2>/dev/null || true
docker stop stabsstelle-postgres 2>/dev/null || true
docker stop stabsstelle-redis 2>/dev/null || true
docker rm stabsstelle-sqlite 2>/dev/null || true

# SQLite-Container starten
echo "▶️ SQLite-Container starten..."
docker run -d \
  --name stabsstelle-sqlite \
  -p 5000:5000 \
  -v stabsstelle_data:/app/data \
  -v $(pwd)/config.py:/app/config.py:ro \
  -v $(pwd)/init_db.py:/app/init_db.py:ro \
  --restart unless-stopped \
  stabsstelle-base:latest

# Datenbank initialisieren
echo "💾 Datenbank initialisieren..."
sleep 5
docker exec stabsstelle-sqlite python /app/init_db.py

# Avahi neustarten für mDNS
echo "🔄 mDNS (Avahi) neustarten..."
sudo systemctl restart avahi-daemon

echo ""
echo "✅ Setup abgeschlossen!"
echo ""
echo "📍 Zugriff über:"
echo "   - https://stab.local"
echo "   - https://$(hostname -I | awk '{print $1}')"
echo ""
echo "🔑 Login:"
echo "   - Benutzername: admin"
echo "   - Passwort: admin123"
echo ""
echo "⚠️ Beim ersten HTTPS-Zugriff erscheint eine Zertifikatswarnung."
echo "   Dies ist normal bei selbstsignierten Zertifikaten."