# Stabsstelle Offline Bundle

## 📦 Inhalt

Komplettes Offline-Installation Bundle für Raspberry Pi mit:
- Vollständige Stabsstelle-Anwendung
- Alle Python-Dependencies
- Installer-Script
- Nginx & Systemd Konfiguration

## 📥 Download auf dem Pi

### Option 1: Automatischer Download (Empfohlen)

```bash
# Script herunterladen und ausführen
wget https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/bundles/download-and-merge.sh
chmod +x download-and-merge.sh
./download-and-merge.sh
```

### Option 2: Manueller Download

```bash
# Alle Teile herunterladen
wget https://github.com/MLeprich/stabsstelle-pi-deploy/raw/main/bundles/bundle-part-aa
wget https://github.com/MLeprich/stabsstelle-pi-deploy/raw/main/bundles/bundle-part-ab
wget https://github.com/MLeprich/stabsstelle-pi-deploy/raw/main/bundles/bundle-part-ac
wget https://github.com/MLeprich/stabsstelle-pi-deploy/raw/main/bundles/bundle-part-ad

# Zusammenfügen
cat bundle-part-* > stabsstelle-bundle.tar.gz

# Aufräumen
rm bundle-part-*
```

## 🚀 Installation

Nach dem Download:

```bash
# 1. Bundle entpacken
tar xzf stabsstelle-bundle.tar.gz

# 2. In Verzeichnis wechseln
cd stabsstelle-bundle

# 3. Installation starten
sudo ./install.sh
```

## 📋 Was wird installiert?

- **Webserver**: Nginx auf Port 80
- **Anwendung**: Flask/Gunicorn auf Port 8004
- **Datenbank**: SQLite
- **Systemd Service**: Auto-Start bei Boot

## 🔧 Nach der Installation

- **Zugriff**: http://[PI-IP-ADRESSE]
- **Standard Login**: admin / admin (bitte ändern!)
- **Logs**: `sudo journalctl -u stabsstelle -f`
- **Service**: `sudo systemctl status stabsstelle`

## ❓ Troubleshooting

Falls die Installation fehlschlägt:

1. **Cleanup durchführen**:
   ```bash
   wget https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/cleanup.sh
   chmod +x cleanup.sh
   sudo ./cleanup.sh
   ```

2. **Erneut installieren**:
   ```bash
   sudo ./install.sh
   ```

## 📊 Bundle Details

- **Größe**: ~303 MB (aufgeteilt in 4 Teile à 95 MB)
- **Erstellt am**: 25.09.2025
- **Version**: 1.0.0

## 🔐 Lizenz

Eine gültige Stabsstelle-Lizenz ist für den produktiven Betrieb erforderlich.