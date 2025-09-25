#!/usr/bin/env python3
"""
Stabsstelle Pi Sync Service
Synchronisiert Daten zwischen Pi und Hauptserver
"""

import os
import sys
import json
import sqlite3
import requests
import hashlib
import gzip
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import argparse
import time

# Füge Parent-Directory zum Path hinzu
sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.license_validator import LicenseValidator


class StabsstelleSync:
    """Sync-Engine für bidirektionale Synchronisation"""

    def __init__(self, config_file: str = "/etc/stabsstelle/sync.json"):
        self.config_file = Path(config_file)
        self.config = self.load_config()
        self.license_validator = LicenseValidator()

        # Logging
        self.setup_logging()

        # Datenbank-Pfade
        self.local_db = self.config.get('database_path', '/var/lib/stabsstelle/stabsstelle.db')
        self.sync_db = self.config.get('sync_db_path', '/var/lib/stabsstelle/sync_meta.db')

        # Server-Konfiguration
        self.server_url = self.config.get('server_url', 'https://stab.digitmi.de')

        # Sync-Status
        self.device_id = self.license_validator.get_device_id()
        self.last_sync = None

        # Initialisiere Sync-Metadatenbank
        self.init_sync_db()

    def setup_logging(self):
        """Konfiguriere Logging"""
        log_dir = Path('/var/log/stabsstelle')
        log_dir.mkdir(parents=True, exist_ok=True)

        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_dir / 'sync.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)

    def load_config(self) -> Dict:
        """Lade Sync-Konfiguration"""
        if self.config_file.exists():
            with open(self.config_file, 'r') as f:
                return json.load(f)

        # Standard-Konfiguration
        return {
            'database_path': '/var/lib/stabsstelle/stabsstelle.db',
            'sync_db_path': '/var/lib/stabsstelle/sync_meta.db',
            'server_url': os.getenv('SYNC_SERVER_URL', 'https://stab.digitmi.de'),
            'sync_interval': 900,  # 15 Minuten
            'batch_size': 100,
            'compression': True,
            'encryption': False
        }

    def save_config(self):
        """Speichere Sync-Konfiguration"""
        self.config_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f, indent=2)

    def init_sync_db(self):
        """Initialisiere Sync-Metadatenbank"""
        conn = sqlite3.connect(self.sync_db)
        cursor = conn.cursor()

        # Sync-Historie
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS sync_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sync_id TEXT UNIQUE,
                started_at TIMESTAMP,
                completed_at TIMESTAMP,
                status TEXT,
                direction TEXT,  -- push, pull, bidirectional
                records_sent INTEGER DEFAULT 0,
                records_received INTEGER DEFAULT 0,
                conflicts INTEGER DEFAULT 0,
                error TEXT
            )
        ''')

        # Änderungs-Tracking
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS change_tracking (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                table_name TEXT,
                record_id TEXT,
                operation TEXT,  -- INSERT, UPDATE, DELETE
                changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                synced BOOLEAN DEFAULT 0,
                sync_id TEXT,
                data_hash TEXT
            )
        ''')

        # Konflikt-Log
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS conflict_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sync_id TEXT,
                table_name TEXT,
                record_id TEXT,
                local_data TEXT,
                remote_data TEXT,
                resolution TEXT,  -- local_wins, remote_wins, merged
                resolved_at TIMESTAMP,
                resolved_by TEXT
            )
        ''')

        conn.commit()
        conn.close()

    def track_change(self, table_name: str, record_id: str, operation: str, data: Dict):
        """Tracke eine lokale Änderung"""
        conn = sqlite3.connect(self.sync_db)
        cursor = conn.cursor()

        data_hash = hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()

        cursor.execute('''
            INSERT INTO change_tracking (table_name, record_id, operation, data_hash)
            VALUES (?, ?, ?, ?)
        ''', (table_name, record_id, operation, data_hash))

        conn.commit()
        conn.close()

    def get_pending_changes(self, limit: int = 100) -> List[Dict]:
        """Hole ausstehende lokale Änderungen"""
        conn = sqlite3.connect(self.sync_db)
        cursor = conn.cursor()

        cursor.execute('''
            SELECT ct.*,
                   CASE
                       WHEN ct.operation = 'DELETE' THEN NULL
                       ELSE (SELECT data FROM change_data WHERE change_id = ct.id)
                   END as data
            FROM change_tracking ct
            WHERE ct.synced = 0
            ORDER BY ct.changed_at ASC
            LIMIT ?
        ''', (limit,))

        changes = []
        for row in cursor.fetchall():
            changes.append({
                'id': row[0],
                'table_name': row[1],
                'record_id': row[2],
                'operation': row[3],
                'changed_at': row[4],
                'data': json.loads(row[7]) if row[7] else None
            })

        conn.close()
        return changes

    def sync(self, mode: str = 'bidirectional') -> bool:
        """Hauptsync-Funktion"""
        self.logger.info(f"Starte Sync im Modus: {mode}")

        # Prüfe Lizenz
        if not self.license_validator.is_valid():
            self.logger.error("Lizenz ungültig - Sync abgebrochen")
            return False

        # Hole Sync-Konfiguration
        sync_config = self.license_validator.get_sync_config()
        if not sync_config.get('enabled'):
            self.logger.warning("Sync in Lizenz nicht freigeschaltet")
            return False

        # Generiere Sync-ID
        sync_id = f"{self.device_id}-{int(time.time())}"

        # Starte Sync-Session
        self.start_sync_session(sync_id, mode)

        try:
            success = True

            # Push lokale Änderungen
            if mode in ['push', 'bidirectional']:
                success = success and self.push_changes(sync_id)

            # Pull Server-Änderungen
            if mode in ['pull', 'bidirectional']:
                success = success and self.pull_changes(sync_id)

            # Markiere Sync als erfolgreich
            self.complete_sync_session(sync_id, 'completed' if success else 'failed')

            return success

        except Exception as e:
            self.logger.error(f"Sync-Fehler: {str(e)}")
            self.complete_sync_session(sync_id, 'error', str(e))
            return False

    def push_changes(self, sync_id: str) -> bool:
        """Sende lokale Änderungen zum Server"""
        self.logger.info("Sende lokale Änderungen...")

        try:
            # Hole ausstehende Änderungen
            changes = self.get_pending_changes()

            if not changes:
                self.logger.info("Keine ausstehenden Änderungen")
                return True

            # Bereite Payload vor
            payload = {
                'device_id': self.device_id,
                'sync_id': sync_id,
                'changes': changes,
                'timestamp': datetime.now().isoformat()
            }

            # Komprimiere wenn aktiviert
            if self.config.get('compression'):
                payload_json = json.dumps(payload)
                payload_compressed = gzip.compress(payload_json.encode())
                headers = {'Content-Encoding': 'gzip'}
            else:
                payload_compressed = json.dumps(payload)
                headers = {}

            # Sende zum Server
            response = requests.post(
                f"{self.server_url}/api/pi/sync/push",
                data=payload_compressed,
                headers={
                    **headers,
                    'X-Device-ID': self.device_id,
                    'X-Sync-ID': sync_id,
                    'Authorization': f"Bearer {self.get_auth_token()}"
                },
                timeout=30
            )

            if response.status_code == 200:
                result = response.json()

                # Markiere Änderungen als synchronisiert
                self.mark_changes_synced(changes, sync_id)

                self.logger.info(f"Push erfolgreich: {len(changes)} Änderungen gesendet")
                return True
            else:
                self.logger.error(f"Push fehlgeschlagen: {response.status_code}")
                return False

        except Exception as e:
            self.logger.error(f"Push-Fehler: {str(e)}")
            return False

    def pull_changes(self, sync_id: str) -> bool:
        """Hole Änderungen vom Server"""
        self.logger.info("Hole Server-Änderungen...")

        try:
            # Hole letzten Sync-Timestamp
            last_sync = self.get_last_sync_timestamp()

            # Anfrage an Server
            response = requests.get(
                f"{self.server_url}/api/pi/sync/pull",
                params={
                    'device_id': self.device_id,
                    'since': last_sync.isoformat() if last_sync else None,
                    'limit': self.config.get('batch_size', 100)
                },
                headers={
                    'X-Device-ID': self.device_id,
                    'X-Sync-ID': sync_id,
                    'Authorization': f"Bearer {self.get_auth_token()}"
                },
                timeout=30
            )

            if response.status_code == 200:
                # Dekomprimiere wenn nötig
                if response.headers.get('Content-Encoding') == 'gzip':
                    data = json.loads(gzip.decompress(response.content))
                else:
                    data = response.json()

                changes = data.get('changes', [])

                # Wende Änderungen an
                conflicts = self.apply_remote_changes(changes, sync_id)

                self.logger.info(
                    f"Pull erfolgreich: {len(changes)} Änderungen empfangen, "
                    f"{len(conflicts)} Konflikte"
                )

                # Behandle Konflikte
                if conflicts:
                    self.resolve_conflicts(conflicts, sync_id)

                return True
            else:
                self.logger.error(f"Pull fehlgeschlagen: {response.status_code}")
                return False

        except Exception as e:
            self.logger.error(f"Pull-Fehler: {str(e)}")
            return False

    def apply_remote_changes(self, changes: List[Dict], sync_id: str) -> List[Dict]:
        """Wende Remote-Änderungen auf lokale Datenbank an"""
        conflicts = []
        conn = sqlite3.connect(self.local_db)
        cursor = conn.cursor()

        for change in changes:
            try:
                table_name = change['table_name']
                record_id = change['record_id']
                operation = change['operation']
                data = change.get('data')

                # Prüfe auf Konflikte
                if self.has_local_conflict(table_name, record_id, change):
                    conflicts.append(change)
                    continue

                # Wende Änderung an
                if operation == 'INSERT':
                    self.insert_record(cursor, table_name, data)
                elif operation == 'UPDATE':
                    self.update_record(cursor, table_name, record_id, data)
                elif operation == 'DELETE':
                    self.delete_record(cursor, table_name, record_id)

                conn.commit()

            except Exception as e:
                self.logger.error(f"Fehler beim Anwenden von Änderung: {str(e)}")
                conn.rollback()

        conn.close()
        return conflicts

    def has_local_conflict(self, table_name: str, record_id: str, remote_change: Dict) -> bool:
        """Prüfe auf lokale Konflikte"""
        conn = sqlite3.connect(self.sync_db)
        cursor = conn.cursor()

        cursor.execute('''
            SELECT data_hash FROM change_tracking
            WHERE table_name = ? AND record_id = ? AND synced = 0
            ORDER BY changed_at DESC
            LIMIT 1
        ''', (table_name, record_id))

        row = cursor.fetchone()
        conn.close()

        if row:
            # Es gibt eine lokale ungesynchronisierte Änderung
            return True

        return False

    def resolve_conflicts(self, conflicts: List[Dict], sync_id: str):
        """Löse Konflikte auf"""
        self.logger.info(f"Löse {len(conflicts)} Konflikte...")

        for conflict in conflicts:
            # Standard-Strategie: Server gewinnt (kann konfiguriert werden)
            resolution_strategy = self.config.get('conflict_resolution', 'remote_wins')

            if resolution_strategy == 'remote_wins':
                # Überschreibe lokale Änderung mit Server-Version
                self.apply_remote_change_forced(conflict)
            elif resolution_strategy == 'local_wins':
                # Behalte lokale Version
                pass
            elif resolution_strategy == 'merge':
                # Versuche zu mergen (komplexer)
                self.merge_conflict(conflict)

            # Logge Konflikt
            self.log_conflict(sync_id, conflict, resolution_strategy)

    def get_auth_token(self) -> str:
        """Hole Authentifizierungs-Token"""
        sync_config = self.license_validator.get_sync_config()
        license_key = sync_config.get('license_key')

        # Generiere Token aus Lizenz und Device-ID
        token_data = f"{license_key}:{self.device_id}:{int(time.time())}"
        return hashlib.sha256(token_data.encode()).hexdigest()

    def get_last_sync_timestamp(self) -> Optional[datetime]:
        """Hole Timestamp des letzten erfolgreichen Syncs"""
        conn = sqlite3.connect(self.sync_db)
        cursor = conn.cursor()

        cursor.execute('''
            SELECT completed_at FROM sync_history
            WHERE status = 'completed' AND device_id = ?
            ORDER BY completed_at DESC
            LIMIT 1
        ''', (self.device_id,))

        row = cursor.fetchone()
        conn.close()

        if row:
            return datetime.fromisoformat(row[0])
        return None

    def start_sync_session(self, sync_id: str, mode: str):
        """Starte eine neue Sync-Session"""
        conn = sqlite3.connect(self.sync_db)
        cursor = conn.cursor()

        cursor.execute('''
            INSERT INTO sync_history (sync_id, started_at, status, direction)
            VALUES (?, ?, 'running', ?)
        ''', (sync_id, datetime.now().isoformat(), mode))

        conn.commit()
        conn.close()

    def complete_sync_session(self, sync_id: str, status: str, error: str = None):
        """Beende Sync-Session"""
        conn = sqlite3.connect(self.sync_db)
        cursor = conn.cursor()

        cursor.execute('''
            UPDATE sync_history
            SET completed_at = ?, status = ?, error = ?
            WHERE sync_id = ?
        ''', (datetime.now().isoformat(), status, error, sync_id))

        conn.commit()
        conn.close()

    def mark_changes_synced(self, changes: List[Dict], sync_id: str):
        """Markiere Änderungen als synchronisiert"""
        conn = sqlite3.connect(self.sync_db)
        cursor = conn.cursor()

        for change in changes:
            cursor.execute('''
                UPDATE change_tracking
                SET synced = 1, sync_id = ?
                WHERE id = ?
            ''', (sync_id, change['id']))

        conn.commit()
        conn.close()

    def initial_sync(self) -> bool:
        """Führe initialen Sync durch (kompletter Datenabgleich)"""
        self.logger.info("Führe initialen Sync durch...")

        try:
            # Hole kompletten Datensatz vom Server
            response = requests.get(
                f"{self.server_url}/api/pi/sync/initial",
                params={'device_id': self.device_id},
                headers={'Authorization': f"Bearer {self.get_auth_token()}"},
                timeout=60
            )

            if response.status_code == 200:
                data = response.json()

                # Importiere Daten
                self.import_initial_data(data)

                self.logger.info("Initialer Sync erfolgreich")
                return True
            else:
                self.logger.error(f"Initialer Sync fehlgeschlagen: {response.status_code}")
                return False

        except Exception as e:
            self.logger.error(f"Fehler beim initialen Sync: {str(e)}")
            return False

    def import_initial_data(self, data: Dict):
        """Importiere initiale Daten vom Server"""
        conn = sqlite3.connect(self.local_db)
        cursor = conn.cursor()

        # Importiere Tabellen in richtiger Reihenfolge (Foreign Keys beachten)
        table_order = [
            'users', 'roles', 'permissions',
            'contacts', 'resources', 'logbook_entries',
            'wiki_articles', 'scenarios', 'checklists'
        ]

        for table_name in table_order:
            if table_name in data:
                records = data[table_name]
                self.logger.info(f"Importiere {len(records)} {table_name}...")

                for record in records:
                    self.insert_or_update_record(cursor, table_name, record)

        conn.commit()
        conn.close()

    def insert_or_update_record(self, cursor, table_name: str, record: Dict):
        """Füge einen Record ein oder aktualisiere ihn"""
        # Dynamisches SQL basierend auf Record-Struktur
        columns = list(record.keys())
        values = list(record.values())

        # Versuche Update, dann Insert
        if 'id' in record:
            # Update
            set_clause = ', '.join([f"{col} = ?" for col in columns if col != 'id'])
            sql = f"UPDATE {table_name} SET {set_clause} WHERE id = ?"
            cursor.execute(sql, [v for k, v in record.items() if k != 'id'] + [record['id']])

            if cursor.rowcount == 0:
                # Insert wenn Update nichts gefunden hat
                placeholders = ', '.join(['?' * len(columns)])
                col_names = ', '.join(columns)
                sql = f"INSERT INTO {table_name} ({col_names}) VALUES ({placeholders})"
                cursor.execute(sql, values)
        else:
            # Nur Insert
            placeholders = ', '.join(['?' * len(columns)])
            col_names = ', '.join(columns)
            sql = f"INSERT INTO {table_name} ({col_names}) VALUES ({placeholders})"
            cursor.execute(sql, values)


def main():
    """CLI für Sync-Service"""
    parser = argparse.ArgumentParser(description='Stabsstelle Pi Sync Service')
    parser.add_argument('--mode', choices=['push', 'pull', 'bidirectional'],
                       default='bidirectional', help='Sync-Modus')
    parser.add_argument('--initial', action='store_true',
                       help='Führe initialen Sync durch')
    parser.add_argument('--daemon', action='store_true',
                       help='Laufe als Daemon')
    parser.add_argument('--interval', type=int, default=900,
                       help='Sync-Intervall in Sekunden (für Daemon-Modus)')

    args = parser.parse_args()

    sync = StabsstelleSync()

    if args.initial:
        # Initialer Sync
        success = sync.initial_sync()
        sys.exit(0 if success else 1)

    if args.daemon:
        # Daemon-Modus
        sync.logger.info(f"Starte Sync-Daemon (Intervall: {args.interval}s)")

        while True:
            try:
                sync.sync(args.mode)
            except Exception as e:
                sync.logger.error(f"Sync-Fehler: {str(e)}")

            time.sleep(args.interval)
    else:
        # Einmaliger Sync
        success = sync.sync(args.mode)
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()