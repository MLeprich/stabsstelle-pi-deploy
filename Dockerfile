# Multi-stage build für optimierte Größe
FROM python:3.11-slim as builder

# Build dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    build-essential \
    libssl-dev \
    libffi-dev \
    python3-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Arbeitsverzeichnis
WORKDIR /build

# Clone repository
RUN git clone https://github.com/MLeprich/stab.git /build/app

# Virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python dependencies
WORKDIR /build/app
RUN pip install --upgrade pip setuptools wheel
RUN grep -v "psycopg2\|pg8000\|postgresql" requirements.txt > requirements-docker.txt
RUN pip install -r requirements-docker.txt

# Production image
FROM python:3.11-slim

# System dependencies
RUN apt-get update && apt-get install -y \
    nginx \
    sqlite3 \
    curl \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application
COPY --from=builder /build/app /opt/stabsstelle

# Working directory
WORKDIR /opt/stabsstelle

# Create directories
RUN mkdir -p /var/lib/stabsstelle/uploads \
    /var/lib/stabsstelle/backups \
    /var/lib/stabsstelle/tiles \
    /var/log/stabsstelle

# Environment variables
ENV FLASK_APP=run.py \
    FLASK_ENV=production \
    DATABASE_URL=sqlite:///var/lib/stabsstelle/stabsstelle.db \
    PYTHONUNBUFFERED=1

# Nginx configuration
RUN echo 'server { \n\
    listen 80; \n\
    server_name _; \n\
    location / { \n\
        proxy_pass http://127.0.0.1:8004; \n\
        proxy_set_header Host $host; \n\
        proxy_set_header X-Real-IP $remote_addr; \n\
    } \n\
    location /static { \n\
        alias /opt/stabsstelle/app/static; \n\
    } \n\
}' > /etc/nginx/sites-available/default

# Supervisor configuration
RUN echo '[supervisord] \n\
nodaemon=true \n\
[program:nginx] \n\
command=/usr/sbin/nginx -g "daemon off;" \n\
[program:gunicorn] \n\
command=gunicorn --workers 2 --bind 127.0.0.1:8004 run:app \n\
directory=/opt/stabsstelle \n\
autostart=true \n\
autorestart=true' > /etc/supervisor/conf.d/supervisord.conf

# Initialize database
RUN python -c "from app import create_app, db; app = create_app(); app.app_context().push(); db.create_all()"

# Expose port
EXPOSE 80

# Start services
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]