#!/bin/bash
#
# Erstellt komplettes Deployment-Bundle für Pi
#

set -e

echo "Creating Stabsstelle Pi Bundle..."

BUNDLE_DIR="stabsstelle-pi-bundle"
rm -rf $BUNDLE_DIR
mkdir -p $BUNDLE_DIR/{app,wheels,configs,scripts}

# 1. Kopiere Anwendung
echo "→ Copying application..."
cp -r /root/projects/Stabsstelle/* $BUNDLE_DIR/app/
rm -rf $BUNDLE_DIR/app/{.git,venv,__pycache__}

# 2. Download wheels für ARM
echo "→ Downloading Python wheels..."
cd $BUNDLE_DIR
cat > requirements.txt << 'REQS'
Flask==3.0.0
Flask-Login==0.6.3
Flask-SQLAlchemy==3.1.1
Flask-Migrate==4.0.5
Flask-WTF==1.2.1
Flask-CORS==4.0.0
Flask-SocketIO==5.3.5
SQLAlchemy==2.0.23
gunicorn==21.2.0
eventlet==0.33.3
python-dotenv==1.0.0
redis==5.0.1
requests==2.31.0
Pillow==10.1.0
psutil==5.9.6
alembic==1.13.1
REQS

pip download -r requirements.txt -d wheels/ \
    --platform linux_armv7l --python-version 3.11 --no-deps || \
pip download -r requirements.txt -d wheels/

# 3. Nginx config
cat > configs/nginx.conf << 'NGINX'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:8004;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /static {
        alias /app/app/static;
    }
}
NGINX

# 4. Supervisor config
cat > configs/supervisor.conf << 'SUPERVISOR'
[supervisord]
nodaemon=true

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"

[program:gunicorn]
command=gunicorn --bind 127.0.0.1:8004 run:app
directory=/app
SUPERVISOR

# 5. Entrypoint
cat > scripts/entrypoint.sh << 'ENTRYPOINT'
#!/bin/bash
if [ ! -f /var/lib/stabsstelle/stabsstelle.db ]; then
    cd /app && flask db upgrade || flask db init && flask db upgrade
fi
exec supervisord -c /etc/supervisor/conf.d/supervisord.conf
ENTRYPOINT

# 6. Install script für Pi
cat > install.sh << 'INSTALLER'
#!/bin/bash
echo "Installing Stabsstelle on Pi..."

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker $USER
fi

# Build image
docker build -t stabsstelle:latest -f Dockerfile.pi .

# Start with docker-compose
docker-compose up -d

echo "Installation complete!"
echo "Access at: http://$(hostname -I | cut -d' ' -f1)"
INSTALLER

chmod +x install.sh
cd ..

# Create archive
tar czf stabsstelle-pi-docker-bundle.tar.gz $BUNDLE_DIR/

echo "Bundle created: stabsstelle-pi-docker-bundle.tar.gz"
echo "Size: $(du -h stabsstelle-pi-docker-bundle.tar.gz | cut -f1)"
