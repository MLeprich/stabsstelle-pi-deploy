# Stabsstelle Docker Image - Vollständige Lösung
FROM python:3.11-slim-bookworm

# Setze Arbeitsverzeichnis
WORKDIR /app

# System-Updates und Basis-Pakete
RUN apt-get update && apt-get install -y \
    # Build-Tools
    gcc g++ make \
    build-essential \
    # Python-Dependencies
    python3-dev \
    libffi-dev \
    libssl-dev \
    # Datenbank
    sqlite3 \
    # Netzwerk-Tools
    curl wget \
    # Git für eventuelle Updates
    git \
    # Nginx als Reverse Proxy
    nginx \
    # Supervisor für Prozess-Management
    supervisor \
    # Cleanup
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Erstelle requirements-docker.txt mit allen wichtigen Paketen
RUN echo 'Flask==3.0.0' > requirements-docker.txt && \
    echo 'Flask-Login==0.6.3' >> requirements-docker.txt && \
    echo 'Flask-SQLAlchemy==3.1.1' >> requirements-docker.txt && \
    echo 'Flask-Migrate==4.0.5' >> requirements-docker.txt && \
    echo 'Flask-WTF==1.2.1' >> requirements-docker.txt && \
    echo 'Flask-CORS==4.0.0' >> requirements-docker.txt && \
    echo 'Flask-Mail==0.9.1' >> requirements-docker.txt && \
    echo 'Flask-SocketIO==5.3.5' >> requirements-docker.txt && \
    echo 'Flask-Caching==2.1.0' >> requirements-docker.txt && \
    echo 'Flask-Limiter==3.5.0' >> requirements-docker.txt && \
    echo 'SQLAlchemy==2.0.23' >> requirements-docker.txt && \
    echo 'WTForms==3.1.1' >> requirements-docker.txt && \
    echo 'python-dotenv==1.0.0' >> requirements-docker.txt && \
    echo 'gunicorn==21.2.0' >> requirements-docker.txt && \
    echo 'eventlet==0.33.3' >> requirements-docker.txt && \
    echo 'python-socketio==5.11.0' >> requirements-docker.txt && \
    echo 'redis==5.0.1' >> requirements-docker.txt && \
    echo 'celery==5.3.4' >> requirements-docker.txt && \
    echo 'requests==2.31.0' >> requirements-docker.txt && \
    echo 'Pillow==10.1.0' >> requirements-docker.txt && \
    echo 'qrcode==7.4.2' >> requirements-docker.txt && \
    echo 'python-dateutil==2.8.2' >> requirements-docker.txt && \
    echo 'pytz==2023.3' >> requirements-docker.txt && \
    echo 'cryptography==41.0.7' >> requirements-docker.txt && \
    echo 'PyJWT==2.8.0' >> requirements-docker.txt && \
    echo 'bcrypt==4.1.2' >> requirements-docker.txt && \
    echo 'pyotp==2.9.0' >> requirements-docker.txt && \
    echo 'Werkzeug==3.0.1' >> requirements-docker.txt && \
    echo 'Jinja2==3.1.2' >> requirements-docker.txt && \
    echo 'click==8.1.7' >> requirements-docker.txt && \
    echo 'itsdangerous==2.1.2' >> requirements-docker.txt && \
    echo 'Markdown==3.5.1' >> requirements-docker.txt && \
    echo 'bleach==6.1.0' >> requirements-docker.txt && \
    echo 'email-validator==2.1.0' >> requirements-docker.txt && \
    echo 'APScheduler==3.10.4' >> requirements-docker.txt && \
    echo 'psutil==5.9.6' >> requirements-docker.txt && \
    echo 'alembic==1.13.0' >> requirements-docker.txt

# Upgrade pip und installiere alle Python-Pakete
RUN pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements-docker.txt

# Erstelle Verzeichnisse
RUN mkdir -p /var/lib/stabsstelle/uploads \
             /var/lib/stabsstelle/backups \
             /var/lib/stabsstelle/tiles \
             /var/log/stabsstelle \
             /var/log/nginx \
             /var/log/supervisor

# Environment-Variablen
ENV FLASK_APP=run.py \
    FLASK_ENV=production \
    DATABASE_URL=sqlite:///var/lib/stabsstelle/stabsstelle.db \
    SECRET_KEY=change-this-in-production-deployment \
    PYTHONUNBUFFERED=1

# Nginx-Konfiguration
RUN echo 'server { \n\
    listen 80; \n\
    server_name _; \n\
    client_max_body_size 100M; \n\
    \n\
    location / { \n\
        proxy_pass http://127.0.0.1:8004; \n\
        proxy_set_header Host $host; \n\
        proxy_set_header X-Real-IP $remote_addr; \n\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \n\
        proxy_set_header X-Forwarded-Proto $scheme; \n\
        proxy_http_version 1.1; \n\
        proxy_set_header Upgrade $http_upgrade; \n\
        proxy_set_header Connection "upgrade"; \n\
        proxy_connect_timeout 300; \n\
        proxy_send_timeout 300; \n\
        proxy_read_timeout 300; \n\
    } \n\
    \n\
    location /static { \n\
        alias /app/app/static; \n\
        expires 30d; \n\
    } \n\
}' > /etc/nginx/sites-enabled/default

# Supervisor-Konfiguration
RUN echo '[supervisord] \n\
nodaemon=true \n\
user=root \n\
logfile=/var/log/supervisor/supervisord.log \n\
pidfile=/var/run/supervisord.pid \n\
\n\
[program:nginx] \n\
command=/usr/sbin/nginx -g "daemon off;" \n\
autostart=true \n\
autorestart=true \n\
stdout_logfile=/var/log/nginx/access.log \n\
stderr_logfile=/var/log/nginx/error.log \n\
\n\
[program:gunicorn] \n\
command=gunicorn --workers 2 --bind 127.0.0.1:8004 --timeout 120 --worker-class eventlet run:app \n\
directory=/app \n\
autostart=true \n\
autorestart=true \n\
stdout_logfile=/var/log/stabsstelle/gunicorn.log \n\
stderr_logfile=/var/log/stabsstelle/gunicorn_error.log \n\
environment=PATH="/usr/local/bin",DATABASE_URL="sqlite:///var/lib/stabsstelle/stabsstelle.db"' \
> /etc/supervisor/conf.d/supervisord.conf

# Startup-Script
RUN echo '#!/bin/bash \n\
set -e \n\
\n\
echo "Starting Stabsstelle Container..." \n\
\n\
# Prüfe ob App-Code vorhanden ist \n\
if [ ! -f /app/run.py ]; then \n\
    echo "App-Code nicht gefunden. Bitte mounten Sie das App-Verzeichnis nach /app" \n\
    echo "docker run -v /pfad/zum/stabsstelle:/app ..." \n\
    exit 1 \n\
fi \n\
\n\
# Initialisiere Datenbank wenn nicht vorhanden \n\
if [ ! -f /var/lib/stabsstelle/stabsstelle.db ]; then \n\
    echo "Initializing database..." \n\
    cd /app \n\
    python3 -c "from app import create_app, db; app = create_app(); app.app_context().push(); db.create_all(); print(\"Database created\")" || { \n\
        echo "Trying with migrations..." \n\
        flask db init \n\
        flask db migrate -m "Initial" \n\
        flask db upgrade \n\
    } \n\
fi \n\
\n\
# Starte Supervisor \n\
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf' \
> /entrypoint.sh

RUN chmod +x /entrypoint.sh

# Expose Port
EXPOSE 80

# Health Check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s \
    CMD curl -f http://localhost/ || exit 1

# Volumes für Persistenz
VOLUME ["/var/lib/stabsstelle", "/var/log/stabsstelle", "/app"]

# Start
ENTRYPOINT ["/entrypoint.sh"]