#!/usr/bin/env python3
"""
Stabsstelle Pi License Validator
Validiert und verwaltet Lizenzen für Pi-Deployments
"""

import json
import os
import sys
import hashlib
import socket
import requests
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Optional, Tuple


class LicenseValidator:
    """Lizenz-Validierung für Stabsstelle Pi"""

    def __init__(self, config_dir: str = "/etc/stabsstelle"):
        self.config_dir = Path(config_dir)
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.license_file = self.config_dir / "license.json"
        self.device_file = self.config_dir / "device.json"
        self.server_url = os.getenv("SYNC_SERVER_URL", "https://stab.digitmi.de")

    def get_device_id(self) -> str:
        """Generiere eindeutige Device-ID"""
        # Versuche CPU-Serial zu lesen (Raspberry Pi)
        cpu_serial = "unknown"
        try:
            with open('/proc/cpuinfo', 'r') as f:
                for line in f:
                    if 'Serial' in line:
                        cpu_serial = line.split(':')[1].strip()
                        break
        except:
            pass

        # MAC-Adresse als Fallback
        mac = ':'.join(['{:02x}'.format((hash(socket.gethostname()) >> i) & 0xff)
                       for i in range(0, 48, 8)])

        # Kombiniere und hashe für eindeutige ID
        unique_string = f"{cpu_serial}-{mac}-{socket.gethostname()}"
        device_id = hashlib.sha256(unique_string.encode()).hexdigest()[:16]

        return device_id

    def get_system_info(self) -> Dict:
        """Sammle System-Informationen"""
        info = {
            'hostname': socket.gethostname(),
            'device_id': self.get_device_id(),
            'pi_version': '1.0.0',
            'python_version': sys.version.split()[0],
            'platform': sys.platform,
        }

        # Raspberry Pi Modell
        try:
            with open('/proc/device-tree/model', 'r') as f:
                info['pi_model'] = f.read().rstrip('\x00')
        except:
            info['pi_model'] = 'Unknown'

        # CPU Info
        try:
            with open('/proc/cpuinfo', 'r') as f:
                for line in f:
                    if 'Hardware' in line:
                        info['hardware'] = line.split(':')[1].strip()
                        break
        except:
            pass

        # Memory Info
        try:
            with open('/proc/meminfo', 'r') as f:
                for line in f:
                    if 'MemTotal' in line:
                        mem_kb = int(line.split()[1])
                        info['memory_mb'] = mem_kb // 1024
                        break
        except:
            pass

        return info

    def validate_online(self, license_key: str) -> Tuple[bool, Dict]:
        """Online-Validierung mit Server"""
        try:
            system_info = self.get_system_info()

            response = requests.post(
                f"{self.server_url}/api/pi/licenses/validate",
                json={
                    'license_key': license_key,
                    'device_id': system_info['device_id'],
                    'hostname': system_info['hostname'],
                    'pi_version': system_info['pi_version'],
                    'system_info': system_info,
                    'registration_type': 'validation'
                },
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()

                # Speichere Lizenz-Informationen
                license_data = {
                    'license_key': license_key,
                    'device_id': system_info['device_id'],
                    'validated_at': datetime.now().isoformat(),
                    'valid_until': data.get('valid_until'),
                    'features': data.get('features', {}),
                    'tier': data.get('tier', 'basic'),
                    'organization': data.get('organization'),
                    'max_devices': data.get('max_devices', 1),
                    'sync_interval': data.get('sync_interval', 900),
                    'server_url': self.server_url
                }

                self.save_license(license_data)

                # Speichere Device-Info
                self.save_device_info(system_info)

                return True, license_data
            else:
                error = response.json().get('error', 'Unbekannter Fehler')
                return False, {'error': error}

        except requests.exceptions.ConnectionError:
            # Offline-Validierung
            return self.validate_offline(license_key)
        except Exception as e:
            return False, {'error': str(e)}

    def validate_offline(self, license_key: str) -> Tuple[bool, Dict]:
        """Offline-Validierung mit gespeicherter Lizenz"""
        if not self.license_file.exists():
            return False, {'error': 'Keine gespeicherte Lizenz gefunden'}

        try:
            with open(self.license_file, 'r') as f:
                stored_license = json.load(f)

            # Prüfe ob Lizenzschlüssel übereinstimmt
            if stored_license.get('license_key') != license_key:
                return False, {'error': 'Lizenzschlüssel stimmt nicht überein'}

            # Prüfe Gültigkeit
            valid_until = datetime.fromisoformat(stored_license.get('valid_until'))
            if datetime.now() > valid_until:
                return False, {'error': 'Lizenz abgelaufen'}

            # Prüfe Device-ID
            if stored_license.get('device_id') != self.get_device_id():
                return False, {'error': 'Device-ID stimmt nicht überein'}

            return True, stored_license

        except Exception as e:
            return False, {'error': f'Fehler beim Lesen der Lizenz: {str(e)}'}

    def register_device(self, license_key: str) -> Tuple[bool, Dict]:
        """Registriere Gerät beim Server"""
        try:
            system_info = self.get_system_info()

            response = requests.post(
                f"{self.server_url}/api/pi/devices/register",
                json={
                    'license_key': license_key,
                    'device_id': system_info['device_id'],
                    'hostname': system_info['hostname'],
                    'system_info': system_info,
                    'registration_type': 'initial'
                },
                timeout=10
            )

            if response.status_code == 200:
                data = response.json()

                # Speichere Registrierung
                registration_data = {
                    'device_id': system_info['device_id'],
                    'registered_at': datetime.now().isoformat(),
                    'registration_token': data.get('token'),
                    'sync_endpoint': data.get('sync_endpoint'),
                    'features': data.get('features', {})
                }

                self.save_device_info({**system_info, **registration_data})

                return True, registration_data
            else:
                error = response.json().get('error', 'Registrierung fehlgeschlagen')
                return False, {'error': error}

        except Exception as e:
            return False, {'error': str(e)}

    def check_features(self) -> Dict:
        """Prüfe freigeschaltete Features"""
        if not self.license_file.exists():
            return {
                'core': True,  # Basis-Features immer verfügbar
                'offline': True,
                'maps': False,
                'sync': False,
                'wiki': False,
                'resources': False,
                'scenarios': False,
                'api_access': False
            }

        try:
            with open(self.license_file, 'r') as f:
                license_data = json.load(f)
            return license_data.get('features', {})
        except:
            return {}

    def save_license(self, license_data: Dict):
        """Speichere Lizenz-Informationen"""
        with open(self.license_file, 'w') as f:
            json.dump(license_data, f, indent=2)

        # Setze sichere Berechtigungen
        os.chmod(self.license_file, 0o600)

    def save_device_info(self, device_info: Dict):
        """Speichere Device-Informationen"""
        with open(self.device_file, 'w') as f:
            json.dump(device_info, f, indent=2)

        # Setze sichere Berechtigungen
        os.chmod(self.device_file, 0o600)

    def get_sync_config(self) -> Dict:
        """Hole Sync-Konfiguration basierend auf Lizenz"""
        if not self.license_file.exists():
            return {
                'enabled': False,
                'interval': 3600,  # 1 Stunde Standard
                'server_url': self.server_url
            }

        try:
            with open(self.license_file, 'r') as f:
                license_data = json.load(f)

            features = license_data.get('features', {})

            return {
                'enabled': features.get('sync', False),
                'interval': license_data.get('sync_interval', 900),
                'server_url': license_data.get('server_url', self.server_url),
                'device_id': license_data.get('device_id'),
                'license_key': license_data.get('license_key')
            }
        except:
            return {'enabled': False}

    def is_valid(self) -> bool:
        """Prüfe ob Lizenz gültig ist"""
        if not self.license_file.exists():
            return False

        try:
            with open(self.license_file, 'r') as f:
                license_data = json.load(f)

            # Prüfe Ablaufdatum
            valid_until = datetime.fromisoformat(license_data.get('valid_until'))
            if datetime.now() > valid_until:
                return False

            # Prüfe Device-ID
            if license_data.get('device_id') != self.get_device_id():
                return False

            return True
        except:
            return False


def main():
    """CLI für Lizenz-Validierung"""
    import argparse

    parser = argparse.ArgumentParser(description='Stabsstelle Pi License Validator')
    parser.add_argument('action', choices=['validate', 'register', 'check', 'info'],
                       help='Aktion: validate, register, check, info')
    parser.add_argument('--license-key', help='Lizenzschlüssel')
    parser.add_argument('--config-dir', default='/etc/stabsstelle',
                       help='Konfigurations-Verzeichnis')

    args = parser.parse_args()

    validator = LicenseValidator(args.config_dir)

    if args.action == 'validate':
        if not args.license_key:
            print("ERROR: Lizenzschlüssel erforderlich")
            sys.exit(1)

        success, data = validator.validate_online(args.license_key)
        if success:
            print(f"SUCCESS: Lizenz validiert bis {data.get('valid_until')}")
            print(f"Tier: {data.get('tier')}")
            print(f"Organisation: {data.get('organization')}")
        else:
            print(f"ERROR: {data.get('error')}")
            sys.exit(1)

    elif args.action == 'register':
        if not args.license_key:
            print("ERROR: Lizenzschlüssel erforderlich")
            sys.exit(1)

        success, data = validator.register_device(args.license_key)
        if success:
            print(f"SUCCESS: Gerät registriert")
            print(f"Device ID: {data.get('device_id')}")
        else:
            print(f"ERROR: {data.get('error')}")
            sys.exit(1)

    elif args.action == 'check':
        if validator.is_valid():
            print("SUCCESS: Lizenz ist gültig")
            features = validator.check_features()
            print("Freigeschaltete Features:")
            for feature, enabled in features.items():
                status = "✓" if enabled else "✗"
                print(f"  [{status}] {feature}")
        else:
            print("ERROR: Lizenz ist ungültig oder abgelaufen")
            sys.exit(1)

    elif args.action == 'info':
        info = validator.get_system_info()
        print("System-Informationen:")
        for key, value in info.items():
            print(f"  {key}: {value}")

        if validator.is_valid():
            sync_config = validator.get_sync_config()
            print("\nSync-Konfiguration:")
            print(f"  Aktiviert: {sync_config.get('enabled')}")
            print(f"  Intervall: {sync_config.get('interval')} Sekunden")
            print(f"  Server: {sync_config.get('server_url')}")


if __name__ == "__main__":
    main()