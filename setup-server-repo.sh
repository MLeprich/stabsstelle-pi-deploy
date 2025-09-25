#!/bin/bash
#
# Setup Git Repository auf Server für Pi-Deployment
# Erstellt ein lokales Git-Repository mit HTTP-Zugang
#

set -e

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

echo "============================================"
echo "  Git Repository Server Setup"
echo "============================================"
echo ""

# Root check
if [ "$EUID" -ne 0 ]; then
    print_error "Bitte als root ausführen"
fi

# Variablen
REPO_DIR="/var/git/stabsstelle.git"
WORK_DIR="/var/git/stabsstelle-work"
SOURCE_DIR="/root/projects/Stabsstelle"
NGINX_CONF="/etc/nginx/sites-available/git-stabsstelle"

# 1. Git-Verzeichnis erstellen
print_status "Erstelle Git-Repository Verzeichnis..."
mkdir -p /var/git
cd /var/git

# 2. Bare Repository erstellen
if [ ! -d "$REPO_DIR" ]; then
    print_status "Initialisiere Bare Repository..."
    git init --bare "$REPO_DIR"
else
    print_warning "Repository existiert bereits"
fi

# 3. Working Directory für Updates
if [ ! -d "$WORK_DIR" ]; then
    print_status "Erstelle Arbeitsverzeichnis..."
    git clone "$SOURCE_DIR" "$WORK_DIR"
else
    print_warning "Arbeitsverzeichnis existiert bereits"
fi

# 4. Push zum Bare Repository
cd "$WORK_DIR"
git remote remove server 2>/dev/null || true
git remote add server "$REPO_DIR"
git push server main

# 5. Git HTTP Backend einrichten
print_status "Installiere Git HTTP Backend..."
apt-get install -y git-core fcgiwrap apache2-utils >/dev/null 2>&1

# 6. Erstelle Passwort-Datei
print_status "Erstelle Authentifizierung..."
htpasswd -bc /var/git/.htpasswd pi-deploy "$(openssl rand -base64 12)"
DEPLOY_PASS=$(grep pi-deploy /var/git/.htpasswd | cut -d: -f2)

# 7. Nginx-Konfiguration
print_status "Konfiguriere Nginx..."
cat > "$NGINX_CONF" << 'EOF'
server {
    listen 8090;
    server_name _;

    location ~ /git(/.*) {
        auth_basic "Git Repository";
        auth_basic_user_file /var/git/.htpasswd;

        fastcgi_pass unix:/var/run/fcgiwrap.socket;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME /usr/lib/git-core/git-http-backend;
        fastcgi_param GIT_PROJECT_ROOT /var/git;
        fastcgi_param GIT_HTTP_EXPORT_ALL "";
        fastcgi_param PATH_INFO $1;
        fastcgi_param REMOTE_USER $remote_user;
    }
}
EOF

# 8. Aktiviere Site
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# 9. Git-Konfiguration für HTTP
cd "$REPO_DIR"
git config http.receivepack true
git config http.uploadpack true

# 10. Berechtigungen
chown -R www-data:www-data /var/git
chmod -R 755 /var/git

# 11. Update-Hook für automatische Aktualisierung
cat > "$REPO_DIR/hooks/post-receive" << 'EOF'
#!/bin/bash
echo "Repository update received"
EOF
chmod +x "$REPO_DIR/hooks/post-receive"

# 12. Erstelle Update-Script
cat > /usr/local/bin/update-pi-repo << EOF
#!/bin/bash
# Aktualisiert das Pi-Repository vom Hauptrepository

cd /var/git/stabsstelle-work
git pull origin main
git push server main
echo "Repository aktualisiert: \$(date)"
EOF
chmod +x /usr/local/bin/update-pi-repo

# 13. Cron-Job für automatische Updates
echo "*/30 * * * * root /usr/local/bin/update-pi-repo >> /var/log/git-update.log 2>&1" > /etc/cron.d/update-pi-repo

# Ausgabe
echo ""
echo "============================================"
echo "  Git Repository Server eingerichtet!"
echo "============================================"
echo ""
echo "Repository-URL für Pi:"
echo "  http://91.99.228.2:8090/git/stabsstelle.git"
echo ""
echo "Authentifizierung:"
echo "  Username: pi-deploy"
echo "  Password: $(openssl rand -base64 12)"
echo ""
echo "Speichern Sie diese Daten sicher!"
echo ""
echo "Repository wird alle 30 Minuten automatisch"
echo "vom Hauptrepository aktualisiert."
echo ""
echo "Manuelles Update: /usr/local/bin/update-pi-repo"
echo ""