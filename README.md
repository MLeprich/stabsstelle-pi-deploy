# Stabsstelle Production Deployment for Raspberry Pi

🚨 **Production-ready Docker deployment for Stabsstelle Dashboard** 

This repository contains a fully tested and working deployment configuration extracted from a running production system on Raspberry Pi 5.

## 🎯 What This Solves

This deployment fixes all major issues found in the original repository:

### ✅ Fixed Issues:
1. **UUID SQLite Compatibility** - PostgreSQL UUID types don't work with SQLite. Implemented compatibility layer.
2. **Missing Python Packages** - All required packages now included:
   - `vobject` - vCard/iCalendar support
   - `weasyprint` - PDF generation
   - `PyPDF2` - PDF manipulation
   - `xlsxwriter` - Excel export
   - `reportlab` - Advanced PDF generation
   - `python-magic` - File type detection
   - `opencv-python-headless` - Image processing
   - `webauthn` - Biometric authentication
   - `pywebpush` - Push notifications
   - `prometheus_client` - Metrics
3. **System Dependencies** - All required system libraries included
4. **Database Initialization** - Automatic database creation with admin user
5. **Working Nginx Configuration** - Properly configured reverse proxy

## 🚀 Quick Installation

### Prerequisites
- Raspberry Pi 5 (or any ARM64 system)
- Fresh Raspberry Pi OS installation
- Internet connection
- GitHub Personal Access Token ([Create one here](https://github.com/settings/tokens))

### One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/install-production.sh | bash
```

Or manual installation:

```bash
wget https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/install-production.sh
chmod +x install-production.sh
./install-production.sh
```

## 📋 Manual Installation

If you prefer to install manually:

```bash
# 1. Clone this repository
git clone https://github.com/MLeprich/stabsstelle-pi-deploy.git
cd stabsstelle-pi-deploy

# 2. Build Docker image (replace YOUR_TOKEN with your GitHub token)
docker build --build-arg GITHUB_TOKEN=YOUR_TOKEN -t stabsstelle:production .

# 3. Run container
docker run -d \
    --name stabsstelle \
    --restart unless-stopped \
    -p 80:80 \
    -v stabsstelle_data:/root/projects/Stabsstelle/data \
    -v stabsstelle_logs:/logs \
    stabsstelle:production
```

## 🔑 Login Credentials

- **URL:** `http://YOUR_RASPBERRY_PI_IP`
- **Username:** `admin`
- **Password:** `admin123`

⚠️ **Important:** Change the admin password immediately after first login!

## 🛠️ Container Management

```bash
# View logs
docker logs stabsstelle

# View real-time logs
docker logs -f stabsstelle

# Stop container
docker stop stabsstelle

# Start container
docker start stabsstelle

# Restart container
docker restart stabsstelle

# Remove container (keeps data)
docker stop stabsstelle && docker rm stabsstelle

# Remove everything (including data)
docker stop stabsstelle
docker rm stabsstelle
docker volume rm stabsstelle_data stabsstelle_logs
```

## 📁 File Structure

```
/opt/stabsstelle-deploy/
├── Dockerfile                 # Production Docker configuration
├── requirements_production.txt # Python dependencies
├── nginx.conf                 # Nginx reverse proxy config
├── supervisord.conf           # Process manager config
├── uuid_compat.py             # UUID SQLite compatibility layer
├── fix_models.py              # Model UUID fix script
├── entrypoint.sh              # Container startup script
└── install-production.sh      # Automated installer
```

## 🔧 Technical Details

### UUID Compatibility Layer
The original application uses PostgreSQL UUID types which are not compatible with SQLite. This deployment includes a compatibility layer (`uuid_compat.py`) that:
- Uses native PostgreSQL UUID when available
- Falls back to CHAR(36) for SQLite
- Handles automatic conversion between UUID objects and strings

### Services Running
- **Gunicorn** - WSGI server running on port 8004 with 2 workers
- **Nginx** - Reverse proxy on port 80
- **Supervisor** - Process manager ensuring services stay running

### Data Persistence
- Database: `/root/projects/Stabsstelle/data/stabsstelle.db`
- Logs: `/logs/`
- Backups: `/root/projects/Stabsstelle/data/backups/`

## 🐛 Troubleshooting

### Container won't start
```bash
# Check logs
docker logs stabsstelle

# Check if port 80 is already in use
sudo netstat -tlnp | grep :80
```

### 502 Bad Gateway
```bash
# Restart services
docker restart stabsstelle

# Check Gunicorn status
docker exec stabsstelle ps aux | grep gunicorn
```

### Database errors
```bash
# Recreate database
docker exec stabsstelle bash -c "
cd /app
python -c 'from app import create_app, db; app = create_app(); app.app_context().push(); db.drop_all(); db.create_all()'
"
```

### Reset admin password
```bash
docker exec stabsstelle bash -c "
cd /app
python -c '
from app import create_app, db
from app.models import User
app = create_app()
with app.app_context():
    admin = User.query.filter_by(username=\"admin\").first()
    if admin:
        admin.set_password(\"newpassword123\")
        db.session.commit()
        print(\"Password reset to: newpassword123\")
'
"
```

## 📊 System Requirements

- **Minimum:** Raspberry Pi 4 with 2GB RAM
- **Recommended:** Raspberry Pi 5 with 4GB+ RAM
- **Storage:** 16GB+ SD card or SSD
- **OS:** Raspberry Pi OS (64-bit) or any ARM64 Linux

## 🔄 Updates

To update to the latest version:

```bash
# Pull latest changes
cd /opt/stabsstelle-deploy
git pull

# Rebuild image
docker build --build-arg GITHUB_TOKEN=YOUR_TOKEN -t stabsstelle:production .

# Recreate container
docker stop stabsstelle
docker rm stabsstelle
docker run -d \
    --name stabsstelle \
    --restart unless-stopped \
    -p 80:80 \
    -v stabsstelle_data:/root/projects/Stabsstelle/data \
    -v stabsstelle_logs:/logs \
    stabsstelle:production
```

## 📝 License

This deployment configuration is provided as-is for use with the Stabsstelle application.

## 🤝 Contributing

Found an issue or have an improvement? Please open an issue or submit a pull request!

## 📞 Support

For issues specific to this deployment:
- Open an issue in this repository

For issues with the Stabsstelle application itself:
- Contact the original repository maintainer

---

**Last tested:** September 25, 2025  
**Platform:** Raspberry Pi 5 (8GB) with Raspberry Pi OS 64-bit  
**Status:** ✅ Production Ready
