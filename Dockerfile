FROM python:3.11-slim

# Setze Arbeitsverzeichnis
WORKDIR /app

# Installiere System-Dependencies
RUN apt-get update && apt-get install -y \
    git \
    nginx \
    supervisor \
    curl \
    procps \
    # WeasyPrint dependencies
    libcairo2 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libgdk-pixbuf-2.0-0 \
    libffi-dev \
    shared-mime-info \
    # Magic dependencies
    libmagic1 \
    # Build tools
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Kopiere requirements und installiere Python packages
COPY requirements_production.txt /tmp/
RUN pip install --no-cache-dir -r /tmp/requirements_production.txt

# Erstelle notwendige Verzeichnisse
RUN mkdir -p /logs /root/projects/Stabsstelle/logs /root/projects/Stabsstelle/data/backups \
    && touch /root/projects/Stabsstelle/data/backups/.backup_key \
    && chmod -R 777 /root/projects/Stabsstelle

# Kopiere Konfigurationsdateien
COPY nginx.conf /etc/nginx/sites-available/default
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY uuid_compat.py /tmp/uuid_compat.py
COPY entrypoint.sh /entrypoint.sh
COPY fix_models.py /tmp/fix_models.py

# Setze Permissions
RUN chmod +x /entrypoint.sh

# GitHub Token als Build-Argument
ARG GITHUB_TOKEN

# Clone Repository mit Token
RUN if [ -z "$GITHUB_TOKEN" ]; then \
        echo "Error: GITHUB_TOKEN not provided!" && exit 1; \
    else \
        git clone https://${GITHUB_TOKEN}@github.com/MLeprich/stab.git /app; \
    fi

# UUID-Fix anwenden
RUN cp /tmp/uuid_compat.py /app/app/utils/uuid_compat.py \
    && python /tmp/fix_models.py

# Erstelle Supervisor-Konfiguration falls nicht vorhanden
RUN if [ ! -f /etc/supervisor/conf.d/supervisord.conf ]; then \
    echo '[supervisord]' > /etc/supervisor/conf.d/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo '[program:gunicorn]' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'command=gunicorn --bind 127.0.0.1:8004 --workers 2 --timeout 120 --log-file=/logs/gunicorn.log --access-logfile=/logs/gunicorn-access.log --error-logfile=/logs/gunicorn-error.log run:app' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'directory=/app' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stdout_logfile=/logs/gunicorn.log' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stderr_logfile=/logs/gunicorn-error.log' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo '[program:nginx]' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'command=/usr/sbin/nginx -g "daemon off;"' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'autostart=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stdout_logfile=/logs/nginx.log' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'stderr_logfile=/logs/nginx-error.log' >> /etc/supervisor/conf.d/supervisord.conf; \
    fi

# Expose port
EXPOSE 80

# Entrypoint
ENTRYPOINT ["/entrypoint.sh"]
