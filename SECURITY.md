# Security Policy

## Unterstützte Versionen

| Version | Unterstützt        |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Sicherheitshinweise

### Was dieses Repository NICHT enthält

- ❌ Keine Passwörter oder API-Keys
- ❌ Keine privaten Schlüssel
- ❌ Keine Kundendaten
- ❌ Keine proprietäre Geschäftslogik

### Was dieses Repository enthält

- ✅ Öffentliche Deployment-Scripts
- ✅ Konfigurations-Templates
- ✅ Dokumentation
- ✅ Synchronisations-Tools

### Sicherheitsmaßnahmen

1. **Lizenzvalidierung**: Erfolgt ausschließlich über sichere API-Calls zum Hauptserver
2. **Authentifizierung**: Tokens werden zur Laufzeit generiert
3. **Verschlüsselung**: TLS für alle Netzwerkverbindungen
4. **Datenintegrität**: Hash-basierte Verifizierung

## Sicherheitslücken melden

Gefundene Sicherheitslücken bitte **NICHT** als öffentliches Issue melden!

Stattdessen bitte eine E-Mail an: **security@digitmi.de**

Bitte folgende Informationen angeben:
- Beschreibung der Sicherheitslücke
- Schritte zur Reproduktion
- Mögliche Auswirkungen
- Vorschlag zur Behebung (falls vorhanden)

Wir melden uns innerhalb von 48 Stunden zurück.

## Verantwortungsvoller Umgang

Dieses Repository ist für die öffentliche Nutzung vorgesehen. Bei der Verwendung:

1. **Lizenzschlüssel schützen**: Niemals Lizenzschlüssel in öffentlichen Repositories speichern
2. **Lokale Konfiguration**: Sensible Konfigurationsdateien nicht committen
3. **Netzwerksicherheit**: Pi-Geräte hinter Firewall betreiben
4. **Updates**: Regelmäßig Updates durchführen

## Kontakt

- Sicherheitsprobleme: security@digitmi.de
- Allgemeiner Support: support@digitmi.de
- Dokumentation: https://github.com/MLeprich/stabsstelle-pi-deploy/wiki