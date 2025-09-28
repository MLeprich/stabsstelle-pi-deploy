"""
Konfiguration für Stabsstelle Pi-Deployment mit SQLite
"""

import os
from datetime import timedelta

basedir = os.path.abspath(os.path.dirname(__file__))

class Config:
    """Basis-Konfiguration"""
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-secret-key-change-in-production'

    # Environment
    ENV = os.environ.get('FLASK_ENV') or 'development'
    DEBUG = os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'
    PROPAGATE_EXCEPTIONS = True

    # SQLite Datenbank (lokal)
    SQLALCHEMY_DATABASE_URI = 'sqlite:////app/data/stabsstelle.db'
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # Session - HTTPS über Nginx Proxy
    SESSION_COOKIE_SECURE = True
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = 'Lax'
    PERMANENT_SESSION_LIFETIME = timedelta(hours=8)
    SESSION_COOKIE_NAME = 'stabsstelle_session'

    # CSRF Protection
    WTF_CSRF_ENABLED = False  # Temporarily disabled for video streaming
    WTF_CSRF_TIME_LIMIT = None
    WTF_CSRF_SSL_STRICT = False

    # JWT
    JWT_SECRET_KEY = SECRET_KEY
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=1)
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(days=1)

    # Upload
    MAX_CONTENT_LENGTH = 16 * 1024 * 1024  # 16MB
    UPLOAD_FOLDER = os.path.join(basedir, 'data', 'uploads')
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'pdf', 'docx', 'xlsx'}

    # Maps
    MAP_TILES_PATH = os.path.join(basedir, 'data', 'tiles')
    MAP_DEFAULT_CENTER = [51.1657, 10.4515]  # Deutschland Mitte
    MAP_DEFAULT_ZOOM = 6

    # Pi Synchronisation
    PI_SYNC_ENABLED = os.environ.get('PI_SYNC_ENABLED', 'false').lower() == 'true'
    PI_SYNC_INTERVAL = int(os.environ.get('PI_SYNC_INTERVAL', 900))
    PI_SYNC_URL = os.environ.get('PI_SYNC_URL')

    # Logging
    LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')
    LOG_FILE = os.environ.get('LOG_FILE', 'logs/app.log')