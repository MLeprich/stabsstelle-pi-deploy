FROM python:3.11-slim

# System-Abhängigkeiten installieren
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Arbeitsverzeichnis setzen
WORKDIR /app

# Stabsstelle-Code kopieren (oder über Volume einbinden)
# Dies setzt voraus, dass der Code bereits im Image ist oder via Volume gemountet wird

# SQLite Datenbank-Verzeichnis
RUN mkdir -p /app/data && chmod 777 /app/data

# Umgebungsvariablen
ENV FLASK_APP=app.py
ENV FLASK_ENV=development
ENV PYTHONUNBUFFERED=1

# Port freigeben
EXPOSE 5000

# Startbefehl
CMD ["python", "-m", "flask", "run", "--host=0.0.0.0", "--port=5000"]