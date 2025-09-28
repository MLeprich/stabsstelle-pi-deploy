#!/bin/bash
# Fügt Sync-Funktionalität zu existierendem Stabsstelle-Docker hinzu

set -e

echo "🔄 Stabsstelle Pi-Server Sync Integration"
echo "========================================="
echo ""

# Prüfe ob Container läuft
if ! docker ps | grep -q "stabsstelle-sqlite"; then
    echo "❌ Container 'stabsstelle-sqlite' läuft nicht!"
    echo "   Bitte starten Sie erst den Container mit:"
    echo "   docker start stabsstelle-sqlite"
    exit 1
fi

# Lizenzschlüssel abfragen (optional)
echo "📝 Lizenzschlüssel (optional - Enter zum Überspringen):"
read -p "Lizenz: " LICENSE_KEY

# Sync-Manager in Container kopieren
echo "📦 Kopiere Sync-Manager in Container..."
docker cp sync_manager.py stabsstelle-sqlite:/app/sync_manager.py

# Sync-Konfiguration erstellen
echo "⚙️ Erstelle Sync-Konfiguration..."
cat > /tmp/sync_config.sh << 'EOF'
#!/bin/bash
export SYNC_SERVER_URL="https://stab.digitmi.de"
export LICENSE_KEY="$1"
export SYNC_INTERVAL="${SYNC_INTERVAL:-300}"

# Python-Pfad setzen
export PYTHONPATH=/app:$PYTHONPATH

# Sync-Manager starten
echo "🚀 Starte Sync-Manager..."
python3 /app/sync_manager.py continuous $SYNC_INTERVAL
EOF

chmod +x /tmp/sync_config.sh
docker cp /tmp/sync_config.sh stabsstelle-sqlite:/app/sync_config.sh

# Sync als Hintergrundprozess im Container starten
echo "🚀 Starte Sync-Prozess im Container..."
docker exec -d stabsstelle-sqlite bash -c "LICENSE_KEY='$LICENSE_KEY' /app/sync_config.sh"

# Erstelle Verwaltungsskript
echo "📝 Erstelle Verwaltungsskript..."
cat > /usr/local/bin/stabsstelle-sync << 'EOF'
#!/bin/bash

case "$1" in
    status)
        echo "📊 Sync-Status:"
        docker exec stabsstelle-sqlite ps aux | grep sync_manager || echo "Sync läuft nicht"
        ;;

    start)
        echo "▶️ Starte Sync..."
        docker exec -d stabsstelle-sqlite bash -c "/app/sync_config.sh"
        ;;

    stop)
        echo "⏹️ Stoppe Sync..."
        docker exec stabsstelle-sqlite pkill -f sync_manager
        ;;

    restart)
        $0 stop
        sleep 2
        $0 start
        ;;

    logs)
        echo "📜 Sync-Logs:"
        docker exec stabsstelle-sqlite tail -n 50 /app/data/sync.log 2>/dev/null || echo "Keine Logs verfügbar"
        ;;

    sync)
        echo "🔄 Manueller Sync..."
        docker exec stabsstelle-sqlite python3 /app/sync_manager.py sync
        ;;

    register)
        echo "📡 Neu registrieren..."
        read -p "Lizenzschlüssel: " LICENSE_KEY
        docker exec -e LICENSE_KEY="$LICENSE_KEY" stabsstelle-sqlite python3 /app/sync_manager.py register
        ;;

    *)
        echo "Verwendung: $0 {status|start|stop|restart|logs|sync|register}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/stabsstelle-sync

# Test Sync-Verbindung
echo "🧪 Teste Server-Verbindung..."
if curl -s https://stab.digitmi.de/api/health > /dev/null; then
    echo "✅ Server erreichbar!"
else
    echo "⚠️ Server nicht erreichbar - Sync wird im Offline-Modus laufen"
fi

# Sync-Status anzeigen
echo ""
echo "✅ Sync-Integration erfolgreich!"
echo ""
echo "📊 Status:"
stabsstelle-sync status
echo ""
echo "🛠️ Verwaltung mit:"
echo "   stabsstelle-sync status   - Status anzeigen"
echo "   stabsstelle-sync sync     - Manueller Sync"
echo "   stabsstelle-sync logs     - Logs anzeigen"
echo "   stabsstelle-sync restart  - Sync neustarten"
echo ""
echo "Der Sync läuft jetzt automatisch alle 5 Minuten im Hintergrund."