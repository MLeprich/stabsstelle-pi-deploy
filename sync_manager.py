#!/usr/bin/env python3
"""
Sync Manager für Stabsstelle Pi-Server Synchronisation
"""

import os
import sys
import json
import time
import sqlite3
import requests
import hashlib
import platform
import subprocess
from datetime import datetime
from typing import Dict, Any, Optional

class StabsstelleSyncManager:
    def __init__(self):
        self.server_url = os.getenv('SYNC_SERVER_URL', 'https://stab.digitmi.de')
        self.license_key = os.getenv('LICENSE_KEY', '')
        self.api_key = os.getenv('API_KEY', '')
        self.device_id = self._get_device_id()
        self.db_path = '/app/data/stabsstelle.db'
        self.config_file = '/app/data/sync_config.json'
        self.load_config()

    def _get_device_id(self) -> str:
        """Generiert eine eindeutige Geräte-ID basierend auf MAC-Adresse"""
        try:
            # MAC-Adresse der ersten Netzwerkschnittstelle
            import uuid
            mac = ':'.join(['{:02x}'.format((uuid.getnode() >> ele) & 0xff)
                          for ele in range(0,8*6,8)][::-1])
            return hashlib.sha256(mac.encode()).hexdigest()[:16]
        except:
            return hashlib.sha256(platform.node().encode()).hexdigest()[:16]

    def load_config(self):
        """Lädt gespeicherte Konfiguration"""
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                    self.api_key = config.get('api_key', self.api_key)
                    self.license_key = config.get('license_key', self.license_key)
            except:
                pass

    def save_config(self):
        """Speichert Konfiguration"""
        config = {
            'api_key': self.api_key,
            'license_key': self.license_key,
            'device_id': self.device_id,
            'registered_at': datetime.now().isoformat()
        }
        with open(self.config_file, 'w') as f:
            json.dump(config, f)

    def register_device(self) -> bool:
        """Registriert das Gerät beim Server"""
        print(f"📡 Registriere Gerät {self.device_id} beim Server...")

        data = {
            'device_id': self.device_id,
            'device_name': platform.node(),
            'device_type': 'raspberry_pi',
            'os_version': platform.platform(),
            'app_version': '1.0.0',
            'license_key': self.license_key
        }

        try:
            response = requests.post(
                f'{self.server_url}/api/pi/register',
                json=data,
                timeout=10
            )

            if response.status_code == 200:
                result = response.json()
                self.api_key = result.get('api_key', '')
                self.save_config()
                print("✅ Registrierung erfolgreich!")
                return True
            else:
                print(f"❌ Registrierung fehlgeschlagen: {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Verbindungsfehler: {e}")
            return False

    def sync_data(self) -> bool:
        """Synchronisiert Daten mit dem Server"""
        print(f"🔄 Starte Synchronisation...")

        # Sammle lokale Daten
        local_data = self.collect_local_data()

        sync_data = {
            'device_id': self.device_id,
            'api_key': self.api_key,
            'timestamp': datetime.now().isoformat(),
            'data': local_data,
            'system_info': self.get_system_info()
        }

        try:
            # Verwende unterschiedliche Endpoints je nach API-Key
            endpoint = '/api/pi/sync' if self.api_key else '/api/pi/sync-simple'

            response = requests.post(
                f'{self.server_url}{endpoint}',
                json=sync_data,
                headers={'X-API-Key': self.api_key} if self.api_key else {},
                timeout=30
            )

            if response.status_code == 200:
                result = response.json()

                # Verarbeite Server-Updates
                if 'updates' in result:
                    self.apply_server_updates(result['updates'])

                print(f"✅ Sync erfolgreich! Nächster Sync: {result.get('next_sync', 'in 5 Minuten')}")
                return True
            else:
                print(f"❌ Sync fehlgeschlagen: {response.status_code}")
                return False
        except Exception as e:
            print(f"❌ Sync-Fehler: {e}")
            return False

    def collect_local_data(self) -> Dict[str, Any]:
        """Sammelt lokale Daten aus der SQLite-Datenbank"""
        data = {}

        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()

            # Sammle Statistiken
            tables = ['users', 'roles', 'messages', 'alerts', 'exercises']
            for table in tables:
                try:
                    cursor.execute(f"SELECT COUNT(*) FROM {table}")
                    count = cursor.fetchone()[0]
                    data[f'{table}_count'] = count
                except:
                    pass

            # Letzte Aktivitäten
            try:
                cursor.execute("""
                    SELECT username, last_login
                    FROM users
                    WHERE last_login IS NOT NULL
                    ORDER BY last_login DESC
                    LIMIT 5
                """)
                data['recent_logins'] = cursor.fetchall()
            except:
                pass

            conn.close()
        except Exception as e:
            print(f"⚠️ Datenbankfehler: {e}")

        return data

    def apply_server_updates(self, updates: Dict[str, Any]):
        """Wendet Server-Updates auf lokale Datenbank an"""
        if not updates:
            return

        print(f"📥 Wende {len(updates)} Updates an...")

        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()

            # Beispiel: Neue Benachrichtigungen
            if 'notifications' in updates:
                for notification in updates['notifications']:
                    cursor.execute("""
                        INSERT OR IGNORE INTO notifications
                        (id, message, type, created_at)
                        VALUES (?, ?, ?, ?)
                    """, (
                        notification['id'],
                        notification['message'],
                        notification['type'],
                        notification['created_at']
                    ))

            conn.commit()
            conn.close()
            print("✅ Updates angewendet")
        except Exception as e:
            print(f"⚠️ Update-Fehler: {e}")

    def get_system_info(self) -> Dict[str, Any]:
        """Sammelt System-Informationen"""
        info = {
            'hostname': platform.node(),
            'platform': platform.platform(),
            'python_version': platform.python_version(),
            'uptime': self._get_uptime(),
            'memory': self._get_memory_info(),
            'disk': self._get_disk_info()
        }
        return info

    def _get_uptime(self) -> str:
        """Holt System-Uptime"""
        try:
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.readline().split()[0])
                days = int(uptime_seconds // 86400)
                hours = int((uptime_seconds % 86400) // 3600)
                return f"{days}d {hours}h"
        except:
            return "unknown"

    def _get_memory_info(self) -> Dict[str, int]:
        """Holt Speicher-Informationen"""
        try:
            with open('/proc/meminfo', 'r') as f:
                lines = f.readlines()
                meminfo = {}
                for line in lines:
                    parts = line.split()
                    if parts[0] in ['MemTotal:', 'MemFree:', 'MemAvailable:']:
                        meminfo[parts[0][:-1]] = int(parts[1])
                return meminfo
        except:
            return {}

    def _get_disk_info(self) -> Dict[str, Any]:
        """Holt Festplatten-Informationen"""
        try:
            df = subprocess.check_output(['df', '-h', '/'], text=True)
            lines = df.strip().split('\n')
            if len(lines) > 1:
                parts = lines[1].split()
                return {
                    'total': parts[1],
                    'used': parts[2],
                    'available': parts[3],
                    'percent': parts[4]
                }
        except:
            return {}

    def send_heartbeat(self):
        """Sendet Heartbeat an Server"""
        try:
            response = requests.post(
                f'{self.server_url}/api/pi/heartbeat',
                json={'device_id': self.device_id, 'api_key': self.api_key},
                headers={'X-API-Key': self.api_key} if self.api_key else {},
                timeout=5
            )
            return response.status_code == 200
        except:
            return False

    def run_continuous_sync(self, interval=300):
        """Führt kontinuierliche Synchronisation durch (Standard: alle 5 Minuten)"""
        print(f"🚀 Starte kontinuierliche Synchronisation (alle {interval}s)")

        # Registriere falls noch nicht geschehen
        if not self.api_key:
            if not self.register_device():
                print("⚠️ Fahre ohne Registrierung fort...")

        while True:
            try:
                # Sync
                self.sync_data()

                # Heartbeat
                self.send_heartbeat()

                # Warte
                time.sleep(interval)

            except KeyboardInterrupt:
                print("\n👋 Synchronisation beendet")
                break
            except Exception as e:
                print(f"❌ Fehler im Sync-Loop: {e}")
                time.sleep(60)  # Bei Fehler kürzer warten

def main():
    """Hauptfunktion"""
    manager = StabsstelleSyncManager()

    # CLI-Argumente
    if len(sys.argv) > 1:
        command = sys.argv[1]

        if command == 'register':
            manager.register_device()
        elif command == 'sync':
            manager.sync_data()
        elif command == 'heartbeat':
            manager.send_heartbeat()
        elif command == 'info':
            print(json.dumps(manager.get_system_info(), indent=2))
        elif command == 'continuous':
            interval = int(sys.argv[2]) if len(sys.argv) > 2 else 300
            manager.run_continuous_sync(interval)
        else:
            print(f"Unbekannter Befehl: {command}")
            print("Verfügbare Befehle: register, sync, heartbeat, info, continuous")
    else:
        # Standard: Kontinuierlicher Sync
        manager.run_continuous_sync()

if __name__ == '__main__':
    main()