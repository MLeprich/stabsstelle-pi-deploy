#!/bin/bash
set -e

echo "=== Starting Stabsstelle Container ==="

# Erstelle Log-Verzeichnisse falls nicht vorhanden
mkdir -p /logs /root/projects/Stabsstelle/logs /root/projects/Stabsstelle/data/backups

# Initialisiere Datenbank
echo "=== Initializing Database ==="
cd /app
python << PYTHON
from app import create_app, db
from app.models import User

app = create_app()
with app.app_context():
    try:
        db.create_all()
        print("Database tables created successfully")
        
        # Create admin user if not exists
        admin = User.query.filter_by(username='admin').first()
        if not admin:
            admin = User(
                username='admin',
                email='admin@stabsstelle.local',
                role='ADMINISTRATOR',
                is_active=True
            )
            admin.set_password('admin123')
            db.session.add(admin)
            db.session.commit()
            print("Admin user created: admin/admin123")
        else:
            print("Admin user already exists")
    except Exception as e:
        print(f"Database initialization error: {e}")
PYTHON

echo "=== Starting Services ==="
# Start supervisor
/usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
