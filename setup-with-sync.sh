#!/bin/bash
# Komplettes Setup mit Sync-Funktionalität

set -e

echo "🚀 Stabsstelle Pi-Deployment mit Server-Sync"
echo "============================================"
echo ""

# Lizenzschlüssel abfragen
echo "📝 Möchten Sie einen Lizenzschlüssel eingeben? (optional)"
echo "   Mit Lizenz: Erweiterte Features, Prioritäts-Sync"
echo "   Ohne Lizenz: Basis-Sync alle 5 Minuten"
echo ""
read -p "Lizenzschlüssel (Enter zum Überspringen): " LICENSE_KEY

# Hostname setzen
echo "📝 Hostname auf 'stab' setzen..."
sudo hostnamectl set-hostname stab
sudo sed -i 's/127.0.1.1.*/127.0.1.1\tstab stab.local/' /etc/hosts

# SSL-Zertifikat erstellen
echo "🔐 SSL-Zertifikat erstellen..."
sudo mkdir -p /etc/ssl/stab
if [ ! -f /etc/ssl/stab/stab.crt ]; then
    sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/ssl/stab/stab.key \
      -out /etc/ssl/stab/stab.crt \
      -subj "/C=DE/ST=Bayern/L=Muenchen/O=Stabsstelle/CN=stab.local" \
      -addext "subjectAltName=DNS:stab.local,DNS:stab,DNS:localhost,IP:$(hostname -I | awk '{print $1}'),IP:127.0.0.1"

    sudo chmod 644 /etc/ssl/stab/stab.crt
    sudo chmod 600 /etc/ssl/stab/stab.key
fi

# Nginx installieren
echo "📦 Nginx installieren..."
if ! command -v nginx &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y nginx
fi

# Nginx konfigurieren
echo "⚙️ Nginx konfigurieren..."
sudo cp nginx/stabsstelle.conf /etc/nginx/sites-available/stabsstelle
sudo ln -sf /etc/nginx/sites-available/stabsstelle /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl enable nginx
sudo systemctl restart nginx

# Docker prüfen
if ! command -v docker &> /dev/null; then
    echo "🐳 Docker installieren..."
    curl -fsSL https://get.docker.com | bash
    sudo usermod -aG docker $USER
fi

# Environment-Datei erstellen
echo "📝 Erstelle Environment-Datei..."
cat > .env << EOF
LICENSE_KEY=$LICENSE_KEY
SYNC_SERVER_URL=https://stab.digitmi.de
SYNC_INTERVAL=300
EOF

# Docker-Images bauen
echo "🐳 Docker-Images bauen..."
docker build -t stabsstelle-sqlite:latest .

# Container mit Sync starten
echo "▶️ Starte Container mit Sync..."
docker-compose -f docker-compose-with-sync.yml up -d

# Warte auf Container-Start
echo "⏳ Warte auf Container-Start..."
sleep 10

# Datenbank initialisieren
echo "💾 Initialisiere Datenbank..."
docker exec stabsstelle-sqlite python /app/init_db.py

# Registriere Gerät beim Server
if [ ! -z "$LICENSE_KEY" ]; then
    echo "📡 Registriere Gerät beim Server..."
    docker exec stabsstelle-sync python3 /app/sync_manager.py register
fi

# Erstelle Verwaltungsskript
echo "📝 Erstelle Verwaltungsskript..."
sudo tee /usr/local/bin/stabsstelle > /dev/null << 'EOF'
#!/bin/bash

case "$1" in
    status)
        echo "📊 System-Status:"
        docker-compose -f /opt/stabsstelle-pi-deploy/docker-compose-with-sync.yml ps
        echo ""
        echo "🔄 Sync-Status:"
        docker logs --tail 10 stabsstelle-sync 2>/dev/null | grep -E "Sync|Registr" || echo "Keine Sync-Logs"
        ;;

    sync)
        echo "🔄 Manueller Sync..."
        docker exec stabsstelle-sync python3 /app/sync_manager.py sync
        ;;

    logs)
        case "$2" in
            app)
                docker logs --tail 50 stabsstelle-sqlite
                ;;
            sync)
                docker logs --tail 50 stabsstelle-sync
                ;;
            *)
                echo "Logs für: app, sync"
                ;;
        esac
        ;;

    restart)
        cd /opt/stabsstelle-pi-deploy
        docker-compose -f docker-compose-with-sync.yml restart
        ;;

    update)
        cd /opt/stabsstelle-pi-deploy
        git pull
        docker-compose -f docker-compose-with-sync.yml down
        docker-compose -f docker-compose-with-sync.yml build --no-cache
        docker-compose -f docker-compose-with-sync.yml up -d
        ;;

    *)
        echo "Verwendung: $0 {status|sync|logs|restart|update}"
        exit 1
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/stabsstelle

# Avahi neustarten für mDNS
echo "🔄 mDNS (Avahi) neustarten..."
sudo systemctl restart avahi-daemon

# Finale Tests
echo "🧪 Teste Installation..."
echo -n "  Container läuft: "
docker ps | grep -q stabsstelle-sqlite && echo "✅" || echo "❌"
echo -n "  Sync läuft: "
docker ps | grep -q stabsstelle-sync && echo "✅" || echo "❌"
echo -n "  Webserver erreichbar: "
curl -s -k https://localhost > /dev/null && echo "✅" || echo "❌"
echo -n "  Server-Verbindung: "
curl -s https://stab.digitmi.de/api/health > /dev/null && echo "✅" || echo "⚠️ Offline-Modus"

echo ""
echo "✅ Installation abgeschlossen!"
echo ""
echo "📍 Zugriff über:"
echo "   - https://stab.local"
echo "   - https://$(hostname -I | awk '{print $1}')"
echo ""
echo "🔑 Login:"
echo "   - Benutzername: admin"
echo "   - Passwort: admin123"
echo ""
echo "🔄 Sync-Status:"
if [ ! -z "$LICENSE_KEY" ]; then
    echo "   - Lizenziert: ✅"
    echo "   - Sync-Intervall: 5 Minuten (Priorität)"
else
    echo "   - Unlizenziert: Basis-Sync"
    echo "   - Sync-Intervall: 5 Minuten"
fi
echo ""
echo "🛠️ Verwaltung mit:"
echo "   stabsstelle status  - Status anzeigen"
echo "   stabsstelle sync    - Manueller Sync"
echo "   stabsstelle logs    - Logs anzeigen"
echo "   stabsstelle update  - System updaten"