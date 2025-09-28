#!/usr/bin/env python
"""
Initialisiert die SQLite-Datenbank mit allen Rollen und dem Admin-User
"""

import sys
sys.path.insert(0, '/app')
from app import create_app, db
from app.models.user import User
from sqlalchemy import text
from datetime import datetime

def init_database():
    app = create_app()
    with app.app_context():
        # Datenbank-Tabellen erstellen
        db.create_all()
        print("✓ Datenbank-Tabellen erstellt")

        # Alle 27 Rollen wie auf dem Hauptserver
        roles_data = [
            (1, 'VERWALTUNGSADMIN', 'Verwaltungsadministrator', 'Verwaltung des Systems', True, 0),
            (2, 'SYSTEMVERWALTER', 'Systemverwalter', 'Technische Systemverwaltung', True, 0),
            (3, 'EINSATZLEITER', 'Einsatzleiter (EL)', 'Leitung des Einsatzes', True, 1),
            (4, 'LEITER_DES_STABS', 'Leiter des Stabs (LdS)', 'Führung des Stabs', True, 1),
            (5, 'S1_LEITER', 'S1 - Personal/Innerer Dienst (Leiter)', 'Leitung S1', True, 2),
            (6, 'S2_LEITER', 'S2 - Lage (Leiter)', 'Leitung S2', True, 2),
            (7, 'S3_LEITER', 'S3 - Einsatz (Leiter)', 'Leitung S3', True, 2),
            (8, 'S4_LEITER', 'S4 - Versorgung (Leiter)', 'Leitung S4', True, 2),
            (9, 'S5_LEITER', 'S5 - Presse/Medienarbeit (Leiter)', 'Leitung S5', True, 2),
            (10, 'S6_LEITER', 'S6 - IuK (Leiter)', 'Leitung S6', True, 2),
            (11, 'S1_ASSISTENT', 'S1 - Personal/Innerer Dienst (Assistent)', 'Assistenz S1', True, 3),
            (12, 'S2_ASSISTENT', 'S2 - Lage (Assistent)', 'Assistenz S2', True, 3),
            (13, 'S3_ASSISTENT', 'S3 - Einsatz (Assistent)', 'Assistenz S3', True, 3),
            (14, 'S4_ASSISTENT', 'S4 - Versorgung (Assistent)', 'Assistenz S4', True, 3),
            (15, 'S5_ASSISTENT', 'S5 - Presse/Medienarbeit (Assistent)', 'Assistenz S5', True, 3),
            (16, 'S6_ASSISTENT', 'S6 - IuK (Assistent)', 'Assistenz S6', True, 3),
            (17, 'UEBUNGSLEITER', 'Übungsleiter', 'Leitung von Übungen', True, 1),
            (18, 'UEBUNGSBEOBACHTER', 'Übungsbeobachter', 'Beobachtung von Übungen', True, 4),
            (19, 'UEBUNGSTEILNEHMER', 'Übungsteilnehmer', 'Teilnahme an Übungen', True, 4),
            (20, 'BEOBACHTER', 'Beobachter', 'Nur-Lese-Zugriff', True, 5),
            (21, 'EXTERNER_PARTNER', 'Externer Partner', 'Externe Kooperationspartner', True, 5),
            (22, 'EINSATZABSCHNITTSLEITER', 'Einsatzabschnittsleiter (EA-Leiter)', 'Leitung Einsatzabschnitt', True, 2),
            (23, 'BEREITSCHAFTSRAUMLEITER', 'Bereitschaftsraumleiter (BR-Leiter)', 'Leitung Bereitschaftsraum', True, 2),
            (24, 'ADMIN', 'Administrator', 'Vollzugriff auf alle Funktionen', True, 0),
            (25, 'KATASTROPHENSCHUTZ_LEITUNG', 'Katastrophenschutz-Leitung', 'Leitung Katastrophenschutz', True, 1),
            (26, 'KATASTROPHENSCHUTZ_BEARBEITER', 'Katastrophenschutz-Bearbeiter', 'Bearbeiter Katastrophenschutz', True, 3),
            (27, 'VIP', 'VIP/Oberbürgermeister/Landrat', 'VIP-Zugang', True, 1)
        ]

        # Rollen einfügen
        for role_data in roles_data:
            db.session.execute(text("""
                INSERT OR IGNORE INTO roles (id, name, display_name, description, is_system_role, hierarchy_level)
                VALUES (:id, :name, :display_name, :description, :is_system_role, :hierarchy_level)
            """), {
                'id': role_data[0],
                'name': role_data[1],
                'display_name': role_data[2],
                'description': role_data[3],
                'is_system_role': role_data[4],
                'hierarchy_level': role_data[5]
            })

        db.session.commit()
        print(f"✓ {len(roles_data)} Rollen eingefügt")

        # Admin-User erstellen oder aktualisieren
        admin_user = User.query.filter_by(username='admin').first()
        if not admin_user:
            admin_user = User(
                username='admin',
                email='admin@stabsstelle.local',
                is_admin=True,
                is_active=True,
                role='ADMIN',
                current_role_id=24  # ADMIN Rolle
            )
            admin_user.set_password('admin123')
            db.session.add(admin_user)
            db.session.commit()
            print("✓ Admin-User erstellt")
        else:
            admin_user.is_admin = True
            admin_user.current_role_id = 24
            db.session.commit()
            print("✓ Admin-User aktualisiert")

        # Alle Rollen dem Admin zuweisen
        db.session.execute(text('DELETE FROM user_roles WHERE user_id = :user_id'), {'user_id': admin_user.id})

        for role_id in range(1, 28):
            is_primary = (role_id == 24)  # ADMIN ist primär
            db.session.execute(text('''
                INSERT INTO user_roles (user_id, role_id, is_primary, assigned_at)
                VALUES (:user_id, :role_id, :is_primary, :assigned_at)
            '''), {
                'user_id': admin_user.id,
                'role_id': role_id,
                'is_primary': is_primary,
                'assigned_at': datetime.now()
            })

        db.session.commit()
        print("✓ Alle Rollen dem Admin zugewiesen")
        print("\n✅ Datenbank-Initialisierung abgeschlossen!")
        print("\n📝 Login-Daten:")
        print("   Benutzername: admin")
        print("   Passwort: admin123")

if __name__ == '__main__':
    init_database()