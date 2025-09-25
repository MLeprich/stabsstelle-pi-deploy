#!/bin/bash
#
# Docker Build Script für Stabsstelle
# Erstellt robuste Docker-Images für Server und Pi
#

set -e

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================"
echo "  Stabsstelle Docker Builder"
echo "============================================"
echo ""

# 1. Extrahiere alle Requirements aus dem Hauptprojekt
echo -e "${GREEN}→${NC} Analysiere Requirements..."
cd /root/projects/Stabsstelle

# Sammle alle imports aus Python-Dateien
MISSING_MODULES=$(python3 << 'EOF'
import os
import ast
import sys

modules = set()

def find_imports(path):
    for root, dirs, files in os.walk(path):
        # Skip venv and cache directories
        dirs[:] = [d for d in dirs if d not in ['venv', '__pycache__', '.git']]

        for file in files:
            if file.endswith('.py'):
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, 'r') as f:
                        tree = ast.parse(f.read())

                    for node in ast.walk(tree):
                        if isinstance(node, ast.Import):
                            for alias in node.names:
                                modules.add(alias.name.split('.')[0])
                        elif isinstance(node, ast.ImportFrom):
                            if node.module:
                                modules.add(node.module.split('.')[0])
                except:
                    pass

find_imports('app')
find_imports('migrations')

# Filter out built-in modules and local modules
import_modules = []
for mod in modules:
    if mod not in ['app', 'os', 'sys', 'json', 'datetime', 'time', 'random',
                   'string', 'hashlib', 'uuid', 'io', 'base64', 'functools',
                   'collections', 'itertools', 're', 'typing', 'enum', 'pathlib',
                   'subprocess', 'shutil', 'tempfile', 'warnings', 'copy']:
        import_modules.append(mod)

print(' '.join(sorted(import_modules)))
EOF
)

echo -e "${GREEN}→${NC} Gefundene Module: $MISSING_MODULES"

# 2. Erstelle vollständige Requirements-Liste
cd /root/projects/stabsstelle-pi-deploy/docker

cat > requirements-complete.txt << 'REQUIREMENTS'
# Core Framework
Flask==3.0.0
Flask-Login==0.6.3
Flask-WTF==1.2.1
Flask-Migrate==4.0.5
Flask-CORS==4.0.0
Flask-SQLAlchemy==3.1.1
Flask-Mail==0.9.1
Flask-SocketIO==5.3.5
Flask-Caching==2.1.0
Flask-Limiter==3.5.0

# Database
SQLAlchemy==2.0.23
alembic==1.13.1

# Authentication & Security
PyJWT==2.8.0
cryptography==41.0.7
bcrypt==4.1.2
python-dotenv==1.0.0
pyotp==2.9.0

# Web Server
gunicorn==21.2.0
gevent==23.9.1
eventlet==0.33.3

# Forms & Validation
WTForms==3.1.1
email-validator==2.1.0

# Utilities
python-dateutil==2.8.2
pytz==2023.3
Pillow==10.1.0
requests==2.31.0
psutil==5.9.6
vobject==0.9.6.1

# WebSocket & Realtime
python-socketio==5.11.0

# Task Queue
redis==5.0.1
celery==5.3.4

# Data Processing
pandas==2.1.4
numpy==1.26.2
openpyxl==3.1.2

# QR Code
qrcode==7.4.2

# Text Processing
Markdown==3.5.1
bleach==6.1.0

# Core Python
Werkzeug==3.0.1
Jinja2==3.1.2
click==8.1.7
itsdangerous==2.1.2

# Scheduling
APScheduler==3.10.4

# HTTP
urllib3==2.1.0
httplib2==0.22.0
REQUIREMENTS

# 3. Erstelle optimiertes Dockerfile
cat > Dockerfile.complete << 'DOCKERFILE'
# Stabsstelle Docker Image - Production Ready
FROM python:3.11-slim-bookworm as builder

# Build-Dependencies
RUN apt-get update && apt-get install -y \
    gcc g++ make build-essential \
    python3-dev libffi-dev libssl-dev \
    libjpeg-dev zlib1g-dev libpng-dev \
    libxml2-dev libxslt1-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY requirements-complete.txt .
RUN pip install --upgrade pip setuptools wheel && \
    pip wheel --wheel-dir /wheels -r requirements-complete.txt

# Runtime Image
FROM python:3.11-slim-bookworm

# Runtime-Dependencies
RUN apt-get update && apt-get install -y \
    sqlite3 nginx supervisor curl wget \
    libjpeg62-turbo libpng16-16 libxml2 libxslt1.1 \
    && rm -rf /var/lib/apt/lists/*

# Kopiere wheels vom Builder
COPY --from=builder /wheels /wheels

# Installiere Python-Pakete
RUN pip install --upgrade pip && \
    pip install --no-cache-dir --no-index --find-links=/wheels /wheels/*.whl && \
    rm -rf /wheels

# Erstelle Verzeichnisse
RUN mkdir -p /app /var/lib/stabsstelle/{uploads,backups,tiles} \
    /var/log/{stabsstelle,nginx,supervisor}

WORKDIR /app

# Environment
ENV FLASK_APP=run.py \
    FLASK_ENV=production \
    DATABASE_URL=sqlite:///var/lib/stabsstelle/stabsstelle.db \
    PYTHONUNBUFFERED=1

# Nginx Config
RUN echo 'server { \
    listen 80; \
    server_name _; \
    client_max_body_size 100M; \
    location / { \
        proxy_pass http://127.0.0.1:8004; \
        proxy_set_header Host $host; \
        proxy_set_header X-Real-IP $remote_addr; \
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \
        proxy_http_version 1.1; \
        proxy_set_header Upgrade $http_upgrade; \
        proxy_set_header Connection "upgrade"; \
        proxy_read_timeout 300; \
    } \
    location /static { \
        alias /app/app/static; \
        expires 30d; \
    } \
}' > /etc/nginx/sites-enabled/default

# Supervisor Config
RUN echo '[supervisord] \n\
nodaemon=true \n\
[program:nginx] \n\
command=/usr/sbin/nginx -g "daemon off;" \n\
autostart=true \n\
[program:gunicorn] \n\
command=gunicorn --workers 2 --bind 127.0.0.1:8004 --timeout 120 run:app \n\
directory=/app \n\
autostart=true \n\
environment=DATABASE_URL="sqlite:///var/lib/stabsstelle/stabsstelle.db"' \
> /etc/supervisor/conf.d/supervisord.conf

# Entrypoint
RUN echo '#!/bin/bash \n\
set -e \n\
if [ ! -f /app/run.py ]; then \n\
    echo "ERROR: Mount app to /app" \n\
    exit 1 \n\
fi \n\
if [ ! -f /var/lib/stabsstelle/stabsstelle.db ]; then \n\
    cd /app \n\
    flask db upgrade || flask db init && flask db upgrade \n\
fi \n\
exec supervisord -c /etc/supervisor/conf.d/supervisord.conf' > /entrypoint.sh \
&& chmod +x /entrypoint.sh

EXPOSE 80
HEALTHCHECK CMD curl -f http://localhost/ || exit 1
VOLUME ["/var/lib/stabsstelle", "/app"]
ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

# 4. Baue Docker Images
echo -e "${GREEN}→${NC} Baue x86_64 Image..."
docker build -t stabsstelle:latest -f Dockerfile.complete .

echo -e "${GREEN}→${NC} Teste Container..."
docker stop stabsstelle-test 2>/dev/null || true
docker rm stabsstelle-test 2>/dev/null || true
docker run -d --name stabsstelle-test \
    -p 8088:80 \
    -v /root/projects/Stabsstelle:/app \
    stabsstelle:latest

sleep 5

if docker ps | grep -q stabsstelle-test; then
    echo -e "${GREEN}✓${NC} Container läuft!"
    echo ""
    echo "Test-URL: http://$(hostname -I | cut -d' ' -f1):8088"
    echo ""
    docker logs stabsstelle-test | tail -20
else
    echo -e "${YELLOW}⚠${NC} Container gestoppt. Logs:"
    docker logs stabsstelle-test
fi

echo ""
echo "============================================"
echo "  Docker Build abgeschlossen"
echo "============================================"
echo ""
echo "Nächste Schritte:"
echo "1. ARM-Build für Pi: docker buildx build --platform linux/arm64 ..."
echo "2. Push zu Registry: docker push ..."
echo "3. Deployment-Script erstellen"
echo ""