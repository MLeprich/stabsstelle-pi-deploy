# Stabsstelle Pi-Deployment 🚀

Vollständiges Docker-Deployment der Stabsstelle-Anwendung für Raspberry Pi mit SQLite-Datenbank und HTTPS-Zugang.

## 📋 Übersicht

Dieses Repository enthält alle notwendigen Dateien für das Deployment der Stabsstelle auf einem Raspberry Pi:
- SQLite-Datenbank (kompatibel mit dem Hauptserver)
- HTTPS über Nginx Reverse Proxy
- mDNS-Support (stab.local)
- Vollständige Rollenverwaltung (27 Rollen)
- Admin-Bereich mit Rollenwechsel

## 🔧 Voraussetzungen

- Raspberry Pi (getestet auf Pi 4/5)
- Raspbian OS oder Ubuntu Server
- Docker & Docker Compose installiert
- Git installiert
- Mindestens 2GB RAM empfohlen

## 🚀 Schnellstart

### Option 1: Mit Server-Synchronisation (EMPFOHLEN)
```bash
# Repository klonen
git clone https://github.com/MLeprich/stabsstelle-pi-deploy.git
cd stabsstelle-pi-deploy

# Setup mit Sync ausführen
chmod +x setup-with-sync.sh
./setup-with-sync.sh
```

### Option 2: Standalone (ohne Sync)
```bash
# Repository klonen
git clone https://github.com/MLeprich/stabsstelle-pi-deploy.git
cd stabsstelle-pi-deploy

# Basis-Setup ausführen
chmod +x setup.sh
./setup.sh
```

### Option 3: Sync zu bestehendem Docker hinzufügen
```bash
# Wenn bereits installiert, Sync nachträglich hinzufügen
chmod +x add-sync-to-existing.sh
./add-sync-to-existing.sh
```

## 📁 Struktur

```
stabsstelle-pi-deploy/
├── docker-compose.yml           # Basis Docker Compose
├── docker-compose-with-sync.yml # Docker Compose mit Sync
├── Dockerfile                   # Docker Image Definition
├── config.py                   # Flask-Konfiguration
├── init_db.py                  # Datenbank-Initialisierung
├── sync_manager.py             # Server-Synchronisation
├── setup.sh                    # Basis Setup-Skript
├── setup-with-sync.sh          # Setup mit Sync
├── add-sync-to-existing.sh    # Sync nachträglich hinzufügen
├── test-sync.sh               # Sync-Funktionalität testen
├── nginx/
│   └── stabsstelle.conf       # Nginx HTTPS-Konfiguration
└── README.md                  # Diese Datei
```

## 🔑 Zugang

Nach erfolgreicher Installation:

**URLs:**
- https://stab.local (mDNS)
- https://[IP-ADRESSE]

**Login:**
- Benutzername: `admin`
- Passwort: `admin123`

## 👥 Verfügbare Rollen

Der Admin-User hat Zugriff auf alle 27 Systemrollen:

### Führungsebene
- Administrator (ADMIN)
- Verwaltungsadministrator
- Systemverwalter
- Einsatzleiter (EL)
- Leiter des Stabs (LdS)

### S-Funktionen (Leiter)
- S1 - Personal/Innerer Dienst
- S2 - Lage
- S3 - Einsatz
- S4 - Versorgung
- S5 - Presse/Medienarbeit
- S6 - IuK

### S-Funktionen (Assistenten)
- S1 bis S6 Assistenten

### Weitere Rollen
- Übungsleiter
- Einsatzabschnittsleiter
- Bereitschaftsraumleiter
- Katastrophenschutz-Leitung
- VIP/Oberbürgermeister/Landrat
- Beobachter

## 🛠️ Manuelle Installation

Falls das Setup-Skript nicht verwendet werden soll:

### 1. SSL-Zertifikat erstellen

```bash
sudo mkdir -p /etc/ssl/stab
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/ssl/stab/stab.key \
  -out /etc/ssl/stab/stab.crt \
  -subj "/C=DE/ST=Bayern/L=Muenchen/O=Stabsstelle/CN=stab.local"
```

### 2. Docker-Container starten

```bash
docker-compose up -d
```

### 3. Datenbank initialisieren

```bash
docker exec stabsstelle-sqlite python /app/init_db.py
```

## 🔄 Updates

```bash
git pull
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

## 🐛 Fehlerbehebung

### Container-Logs anzeigen
```bash
docker logs stabsstelle-sqlite
```

### Datenbank zurücksetzen
```bash
docker-compose down
docker volume rm stabsstelle-pi-deploy_stabsstelle_data
docker-compose up -d
docker exec stabsstelle-sqlite python /app/init_db.py
```

### HTTPS-Zertifikatsfehler
Bei der ersten Verbindung erscheint eine Browserwarnung. Das ist normal bei selbstsignierten Zertifikaten. Klicken Sie auf "Erweitert" und dann "Weiter zu stab.local".

## 📊 Systemanforderungen

- **RAM:** Mindestens 2GB (4GB empfohlen)
- **Speicher:** Mindestens 8GB frei
- **CPU:** Raspberry Pi 3B+ oder neuer
- **Netzwerk:** LAN-Verbindung empfohlen

## 🔒 Sicherheit

- Ändern Sie das Admin-Passwort nach der Installation
- Das SSL-Zertifikat ist selbstsigniert und 10 Jahre gültig
- Für Produktivumgebungen wird ein offizielles Zertifikat empfohlen

## 📝 Lizenz

Siehe Hauptprojekt-Repository für Lizenzinformationen.

## 🔄 Server-Synchronisation

Die Synchronisation mit dem Hauptserver (stab.digitmi.de) bietet:

### Features
- **Automatische Registrierung:** Gerät meldet sich beim Server an
- **Bidirektionale Synchronisation:** Daten-Austausch alle 5 Minuten
- **Lizenz-Support:** Erweiterte Features mit Lizenzschlüssel
- **Offline-Fähig:** Funktioniert auch ohne Server-Verbindung
- **System-Monitoring:** Übertragung von System-Metriken

### Sync-Verwaltung
```bash
stabsstelle status   # System- und Sync-Status
stabsstelle sync     # Manueller Sync
stabsstelle logs app # App-Logs anzeigen
stabsstelle logs sync # Sync-Logs anzeigen
stabsstelle restart  # System neustarten
stabsstelle update   # System updaten
```

### Test der Sync-Funktionalität
```bash
./test-sync.sh       # Testet alle Sync-Komponenten
```

## 🤝 Support

Bei Problemen bitte ein Issue im Repository erstellen:
https://github.com/MLeprich/stabsstelle-pi-deploy/issues

---

**Version:** 2.0.0
**Stand:** September 2025
**Getestet auf:** Raspberry Pi 4/5 mit Raspbian OS
**Neu:** Server-Synchronisation mit stab.digitmi.de