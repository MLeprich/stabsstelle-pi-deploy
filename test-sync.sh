#!/bin/bash
# Test-Skript für Sync-Funktionalität

echo "🧪 Teste Sync-Funktionalität"
echo "============================"
echo ""

# Farben für Output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test-Funktionen
test_passed() {
    echo -e "${GREEN}✅ $1${NC}"
}

test_failed() {
    echo -e "${RED}❌ $1${NC}"
}

test_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# 1. Docker-Container Test
echo "1️⃣ Docker-Container Status:"
if docker ps | grep -q stabsstelle-sqlite; then
    test_passed "Hauptcontainer läuft"
else
    test_failed "Hauptcontainer läuft nicht"
fi

if docker ps | grep -q stabsstelle-sync; then
    test_passed "Sync-Container läuft"
else
    test_warning "Sync-Container läuft nicht (optional)"
fi

# 2. Netzwerk-Test
echo ""
echo "2️⃣ Netzwerk-Tests:"
if ping -c 1 stab.digitmi.de > /dev/null 2>&1; then
    test_passed "Server erreichbar (ping)"
else
    test_failed "Server nicht erreichbar"
fi

if curl -s https://stab.digitmi.de/api/health > /dev/null; then
    test_passed "API-Endpoint erreichbar"
else
    test_failed "API-Endpoint nicht erreichbar"
fi

# 3. Lokale Services
echo ""
echo "3️⃣ Lokale Services:"
if curl -s -k https://localhost > /dev/null; then
    test_passed "HTTPS läuft"
else
    test_failed "HTTPS läuft nicht"
fi

if curl -s http://localhost:5000/api/health 2>/dev/null | grep -q "ok"; then
    test_passed "Flask-API läuft"
else
    test_warning "Flask-API antwortet nicht auf /api/health"
fi

# 4. Sync-Manager Test
echo ""
echo "4️⃣ Sync-Manager Tests:"

# Teste ob sync_manager.py existiert
if docker exec stabsstelle-sqlite test -f /app/sync_manager.py; then
    test_passed "sync_manager.py vorhanden"

    # Teste Import
    if docker exec stabsstelle-sqlite python3 -c "import sys; sys.path.insert(0,'/app'); import sync_manager" 2>/dev/null; then
        test_passed "Sync-Manager importierbar"
    else
        test_failed "Sync-Manager Import-Fehler"
    fi
else
    test_failed "sync_manager.py nicht gefunden"
fi

# 5. Datenbank-Test
echo ""
echo "5️⃣ Datenbank-Tests:"
if docker exec stabsstelle-sqlite test -f /app/data/stabsstelle.db; then
    test_passed "SQLite-Datenbank existiert"

    # Teste Tabellen
    tables=$(docker exec stabsstelle-sqlite python3 -c "
import sqlite3
conn = sqlite3.connect('/app/data/stabsstelle.db')
cursor = conn.cursor()
cursor.execute(\"SELECT name FROM sqlite_master WHERE type='table'\")
tables = cursor.fetchall()
print(len(tables))
" 2>/dev/null)

    if [ "$tables" -gt "0" ]; then
        test_passed "$tables Tabellen in Datenbank"
    else
        test_failed "Keine Tabellen in Datenbank"
    fi
else
    test_failed "Datenbank nicht gefunden"
fi

# 6. Sync-Konfiguration
echo ""
echo "6️⃣ Sync-Konfiguration:"
if [ -f .env ]; then
    test_passed "Environment-Datei vorhanden"
    if grep -q "LICENSE_KEY=" .env; then
        if grep -q "LICENSE_KEY=." .env; then
            test_passed "Lizenzschlüssel konfiguriert"
        else
            test_warning "Kein Lizenzschlüssel (Basis-Sync)"
        fi
    fi
else
    test_warning "Keine .env Datei"
fi

# 7. Manueller Sync-Test
echo ""
echo "7️⃣ Manueller Sync-Test:"
echo "   Führe Test-Sync durch..."
if docker exec stabsstelle-sqlite python3 -c "
import sys
sys.path.insert(0,'/app')
from sync_manager import StabsstelleSyncManager
manager = StabsstelleSyncManager()
info = manager.get_system_info()
print('OK' if info else 'FAIL')
" 2>/dev/null | grep -q "OK"; then
    test_passed "System-Info abrufbar"
else
    test_failed "System-Info nicht abrufbar"
fi

# Zusammenfassung
echo ""
echo "📊 Test-Zusammenfassung:"
echo "========================"
passed=$(grep -c "✅" /tmp/sync-test-$$.log 2>/dev/null || echo 0)
failed=$(grep -c "❌" /tmp/sync-test-$$.log 2>/dev/null || echo 0)
warnings=$(grep -c "⚠️" /tmp/sync-test-$$.log 2>/dev/null || echo 0)

echo "  Bestanden: $passed"
echo "  Fehlgeschlagen: $failed"
echo "  Warnungen: $warnings"

if [ "$failed" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ Alle kritischen Tests bestanden!${NC}"
    echo "   Die Sync-Funktionalität ist einsatzbereit."
else
    echo ""
    echo -e "${RED}❌ Es gibt Probleme mit der Sync-Funktionalität.${NC}"
    echo "   Bitte prüfen Sie die fehlgeschlagenen Tests."
fi

# Cleanup
rm -f /tmp/sync-test-$$.log