#!/bin/bash
#
# Build and Push Docker Images to GitHub Container Registry
#

set -e

echo "============================================"
echo "  Build & Push Stabsstelle Docker Images"
echo "============================================"
echo ""

# Variablen
REGISTRY="ghcr.io"
NAMESPACE="mleprich"
IMAGE_NAME="stabsstelle"
VERSION="1.1.0"

# GitHub Token (muss gesetzt sein)
if [ -z "$GITHUB_TOKEN" ]; then
    echo "GITHUB_TOKEN nicht gesetzt!"
    echo "Bitte setzen Sie:"
    echo "  export GITHUB_TOKEN=your_github_token"
    exit 1
fi

# Login zu GitHub Container Registry
echo "→ Login zu GitHub Container Registry..."
echo $GITHUB_TOKEN | docker login $REGISTRY -u $NAMESPACE --password-stdin

# Erstelle optimiertes Dockerfile
cat > Dockerfile.production << 'DOCKERFILE'
FROM python:3.11-slim as builder

# Build dependencies
RUN apt-get update && apt-get install -y \
    gcc g++ git \
    && rm -rf /var/lib/apt/lists/*

# Clone repository
RUN git clone https://github.com/MLeprich/stab.git /app

# Install Python packages
WORKDIR /app
RUN pip install --user --no-cache-dir \
    Flask==3.0.0 Flask-Login==0.6.3 Flask-SQLAlchemy==3.1.1 \
    Flask-Migrate==4.0.5 Flask-WTF==1.2.1 Flask-CORS==4.0.0 \
    Flask-SocketIO==5.3.5 SQLAlchemy==2.0.23 gunicorn==21.2.0 \
    eventlet==0.33.3 python-dotenv==1.0.0 redis==5.0.1 \
    requests==2.31.0 psutil==5.9.6 alembic==1.13.1 \
    Werkzeug==3.0.1 Jinja2==3.1.2 APScheduler==3.10.4 \
    cryptography==41.0.7 bcrypt==4.1.2 PyJWT==2.8.0 \
    python-dateutil==2.8.2 Pillow==10.1.0 qrcode==7.4.2

# Runtime image
FROM python:3.11-slim

# Runtime dependencies
RUN apt-get update && apt-get install -y \
    nginx supervisor sqlite3 curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy app and Python packages from builder
COPY --from=builder /app /app
COPY --from=builder /root/.local /root/.local

# Make Python packages available
ENV PATH=/root/.local/bin:$PATH

WORKDIR /app

# Nginx configuration
RUN cat > /etc/nginx/sites-enabled/default << 'EOF'
server {
    listen 80;
    server_name _;
    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8004;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
    }

    location /static {
        alias /app/app/static;
        expires 30d;
    }
}
EOF

# Supervisor configuration
RUN cat > /etc/supervisor/conf.d/supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true

[program:gunicorn]
command=/root/.local/bin/gunicorn --workers 2 --bind 127.0.0.1:8004 --timeout 120 run:app
directory=/app
autostart=true
autorestart=true
environment=DATABASE_URL="sqlite:///var/lib/stabsstelle/stabsstelle.db",FLASK_ENV="production"
EOF

# Create directories
RUN mkdir -p /var/lib/stabsstelle/{uploads,backups,tiles} \
             /var/log/stabsstelle

# Entrypoint
RUN cat > /entrypoint.sh << 'EOF'
#!/bin/bash
set -e

# Initialize database if needed
if [ ! -f /var/lib/stabsstelle/stabsstelle.db ]; then
    cd /app
    flask db upgrade 2>/dev/null || {
        flask db init 2>/dev/null || true
        flask db migrate -m "Initial" 2>/dev/null || true
        flask db upgrade 2>/dev/null || echo "DB will be initialized on first request"
    }
fi

# Start supervisor
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
EOF

RUN chmod +x /entrypoint.sh

EXPOSE 80
VOLUME ["/var/lib/stabsstelle"]
HEALTHCHECK CMD curl -f http://localhost/ || exit 1
ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

# Build für multiple Architekturen
echo "→ Setup Docker Buildx..."
docker buildx create --name multiarch --use 2>/dev/null || docker buildx use multiarch

# Build und Push
echo "→ Building multi-arch images..."
docker buildx build \
    --platform linux/amd64,linux/arm64,linux/arm/v7 \
    -t $REGISTRY/$NAMESPACE/$IMAGE_NAME:$VERSION \
    -t $REGISTRY/$NAMESPACE/$IMAGE_NAME:latest \
    -f Dockerfile.production \
    --push \
    . || {
    echo "Multi-arch build fehlgeschlagen, versuche single-arch..."

    # Fallback: Single arch build
    docker build -t $REGISTRY/$NAMESPACE/$IMAGE_NAME:latest -f Dockerfile.production .
    docker push $REGISTRY/$NAMESPACE/$IMAGE_NAME:latest
}

echo ""
echo "✓ Docker Images erfolgreich gebaut und gepusht!"
echo ""
echo "Images:"
echo "  - $REGISTRY/$NAMESPACE/$IMAGE_NAME:latest"
echo "  - $REGISTRY/$NAMESPACE/$IMAGE_NAME:$VERSION"
echo ""
echo "Verwendung:"
echo "  docker pull $REGISTRY/$NAMESPACE/$IMAGE_NAME:latest"
echo ""