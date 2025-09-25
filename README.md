# Stabsstelle Pi Deployment

Automatisiertes Deployment-System für die Stabsstelle-Software auf Raspberry Pi Geräten mit Offline-Funktionalität und bidirektionaler Synchronisation.

## 🎯 Übersicht

Dieses Repository enthält alle notwendigen Scripts und Konfigurationen, um die Stabsstelle-Software auf einem Raspberry Pi zu installieren und zu betreiben. Das System bietet:

- **Vollständige Offline-Funktionalität** - Arbeitet autark ohne Internetverbindung
- **Automatische Synchronisation** - Bidirektionaler Datenabgleich alle 15 Minuten
- **Lizenz-Management** - Kontrolle über Features und Deployments
- **Einfache Installation** - One-Line-Installer mit automatischer Konfiguration

## 📋 Voraussetzungen

### Hardware
- Raspberry Pi 4/5 (empfohlen: 4GB+ RAM)
- 128GB SSD oder SD-Karte (empfohlen: SSD für bessere Performance)
- Stabile Stromversorgung (empfohlen: Original Netzteil)
- Optional: USV für kritische Einsätze

### Software
- Raspberry Pi OS Lite (64-bit) - Bullseye oder neuer
- Internetverbindung für Installation und Updates
- Gültige Stabsstelle-Lizenz

## 🚀 Installation

### Methode 1: Interaktive Installation (Empfohlen) ✅

```bash
# Lädt und führt den Setup-Wizard aus
wget -qO- https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/easy-install.sh | bash
```

### Methode 2: Mit Lizenzschlüssel als Parameter

```bash
# Ersetzen Sie XXXX-XXXX-XXXX-XXXX mit Ihrem Lizenzschlüssel
export STABSSTELLE_LICENSE_KEY="XXXX-XXXX-XXXX-XXXX"
curl -sSL https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/install.sh | sudo bash
```

### Methode 3: Setup-Wizard

```bash
# Download und Ausführung
wget https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/setup.sh
chmod +x setup.sh
./setup.sh
```

### Methode 4: Manuelle Installation

```bash
# Repository klonen
git clone https://github.com/MLeprich/stabsstelle-pi-deploy.git
cd stabsstelle-pi-deploy

# Mit Lizenz als Parameter
sudo ./install.sh --license "XXXX-XXXX-XXXX-XXXX"

# Oder interaktiv
sudo ./install.sh
```

Der Setup-Wizard führt Sie durch alle Schritte und fragt interaktiv nach dem Lizenzschlüssel.

## 🔑 Lizenzierung

### Lizenz-Tiers

| Tier | Features | Max. Geräte | Sync-Intervall | Preis |
|------|----------|-------------|----------------|-------|
| **Trial** | Basis-Features | 2 | 30 Min | Kostenlos (30 Tage) |
| **Basic** | Core + Offline | 2 | 15 Min | auf Anfrage |
| **Professional** | + Szenarien, API | 10 | 5 Min | auf Anfrage |
| **Hub** | + Multi-Site | ∞ Worker | 1 Min | auf Anfrage |
| **Enterprise** | Alle Features | ∞ | Echtzeit | auf Anfrage |

### Lizenz validieren

```bash
python3 /opt/stabsstelle/tools/license_validator.py check
```

## 🔄 Synchronisation

Die Synchronisation läuft automatisch alle 15 Minuten (konfigurierbar je nach Lizenz).

### Manueller Sync

```bash
# Bidirektionaler Sync
sudo -u pi python3 /opt/stabsstelle/scripts/sync.py

# Nur Push (lokale Änderungen senden)
sudo -u pi python3 /opt/stabsstelle/scripts/sync.py --mode push

# Nur Pull (Server-Änderungen holen)
sudo -u pi python3 /opt/stabsstelle/scripts/sync.py --mode pull
```

### Sync-Status prüfen

```bash
sudo journalctl -u stabsstelle-sync -f
```

## 🔧 Wartung

### System-Update

```bash
cd /root/stabsstelle-pi-deploy
git pull
sudo ./scripts/update.sh
```

### Health-Check

```bash
sudo ./scripts/health-check.sh
```

### Logs anzeigen

```bash
# Hauptanwendung
sudo journalctl -u stabsstelle -f

# Sync-Service
sudo journalctl -u stabsstelle-sync -f

# Nginx
sudo tail -f /var/log/nginx/error.log
```

### Backup erstellen

```bash
sudo tar -czf backup_$(date +%Y%m%d).tar.gz \
    /opt/stabsstelle \
    /var/lib/stabsstelle \
    /etc/stabsstelle
```

## 📁 Verzeichnisstruktur

```
/opt/stabsstelle/          # Hauptanwendung
├── app/                   # Flask-Anwendung
├── venv/                  # Python Virtual Environment
├── scripts/               # Utility-Scripts
└── logs/                  # Anwendungs-Logs

/var/lib/stabsstelle/      # Daten
├── stabsstelle.db         # SQLite-Datenbank
├── sync_meta.db          # Sync-Metadaten
├── uploads/              # Hochgeladene Dateien
├── backups/              # Automatische Backups
└── tiles/                # Offline-Kartentiles

/etc/stabsstelle/         # Konfiguration
├── license.json          # Lizenz-Information
├── device.json           # Geräte-Registrierung
└── sync.json            # Sync-Konfiguration
```

## 🌐 Zugriff

Nach erfolgreicher Installation ist die Anwendung erreichbar unter:

- **HTTP**: `http://<PI-IP-ADRESSE>`
- **mDNS**: `http://stabsstelle.local` (wenn mDNS aktiviert)
- **Standard-Port**: 80 (Nginx Proxy zu Port 8004)

## 🚨 Troubleshooting

### Service startet nicht

```bash
# Status prüfen
sudo systemctl status stabsstelle

# Logs prüfen
sudo journalctl -u stabsstelle -n 100

# Neustart versuchen
sudo systemctl restart stabsstelle
```

### Sync funktioniert nicht

```bash
# Lizenz prüfen
python3 /opt/stabsstelle/tools/license_validator.py check

# Netzwerk prüfen
ping stab.digitmi.de

# Manueller Sync mit Debug
sudo -u pi python3 /opt/stabsstelle/scripts/sync.py --mode pull
```

### Datenbank-Fehler

```bash
# Integrität prüfen
sqlite3 /var/lib/stabsstelle/stabsstelle.db "PRAGMA integrity_check;"

# Backup wiederherstellen
sudo systemctl stop stabsstelle
sudo cp /var/lib/stabsstelle/backups/backup_DATUM.tar.gz /tmp/
cd /tmp && tar -xzf backup_DATUM.tar.gz
sudo cp var/lib/stabsstelle/stabsstelle.db /var/lib/stabsstelle/
sudo systemctl start stabsstelle
```

## 📊 Monitoring

### Systemd-Status

```bash
# Alle Stabsstelle-Services
systemctl list-units stabsstelle*

# Timer-Status
systemctl list-timers stabsstelle*
```

### Ressourcen-Nutzung

```bash
# CPU und RAM
htop

# Festplatte
df -h

# Datenbank-Größe
du -h /var/lib/stabsstelle/stabsstelle.db
```

## 🔒 Sicherheit

### Firewall-Regeln

```bash
# Standard-Ports
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS (wenn konfiguriert)
sudo ufw allow 22/tcp   # SSH
sudo ufw enable
```

### SSL-Zertifikat (optional)

Für lokale SSL-Verschlüsselung:

```bash
# Self-signed Zertifikat erstellen
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/stabsstelle.key \
    -out /etc/ssl/certs/stabsstelle.crt
```

## 🆘 Support

### Dokumentation
- Hauptdokumentation: [/docs](https://github.com/MLeprich/Stabsstelle/tree/main/docs)
- API-Dokumentation: [/docs/API.md](https://github.com/MLeprich/Stabsstelle/blob/main/docs/API.md)

### Kontakt
- **E-Mail**: support@digitmi.de
- **Issue Tracker**: [GitHub Issues](https://github.com/MLeprich/stabsstelle-pi-deploy/issues)

## ⚖️ Rechtliches

### Open Source Deployment-Scripts
Die Deployment-Scripts in diesem Repository stehen unter der [MIT License](LICENSE) zur freien Verfügung.

### Proprietäre Hauptanwendung
Die Stabsstelle-Hauptanwendung ist proprietäre Software und erfordert eine gültige kommerzielle Lizenz.
Details zu Lizenzen: [Lizenz-Tiers](#lizenz-tiers)

### Haftungsausschluss
Diese Software wird ohne Gewährleistung bereitgestellt. Die Nutzung erfolgt auf eigene Verantwortung.
Für produktiven Einsatz in kritischen Infrastrukturen wird professioneller Support empfohlen.

## 🔄 Changelog

### Version 1.0.0 (2025-01-25)
- Initiales Release
- Automatische Installation und Konfiguration
- Bidirektionale Synchronisation
- Lizenz-Management
- Offline-Funktionalität

---

**Entwickelt mit ❤️ für Stabsstellen, Feuerwehren und Hilfsorganisationen**