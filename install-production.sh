#!/bin/bash

# Stabsstelle Production Deployment Script
# Automated installer for Raspberry Pi

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Stabsstelle Production Deployment${NC}"
echo -e "${GREEN}   For Raspberry Pi 5 (ARM64)${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# Check if running on ARM64
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" ]]; then
    echo -e "${YELLOW}Warning: This system is not ARM64 (detected: $ARCH)${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Request GitHub Token
echo -e "${YELLOW}GitHub Token required for private repository access${NC}"
echo "Get your token from: https://github.com/settings/tokens"
echo "Required scopes: repo (full control)"
echo ""
read -sp "Enter GitHub Token: " GITHUB_TOKEN
echo ""

if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${RED}Error: GitHub token is required!${NC}"
    exit 1
fi

# Validate token format (basic check)
if [[ ! "$GITHUB_TOKEN" =~ ^YOUR_GITHUB_TOKEN[a-zA-Z0-9]{36}$ ]]; then
    echo -e "${YELLOW}Warning: Token format looks unusual. Continuing anyway...${NC}"
fi

# Install Docker if not present
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker not found. Installing Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    echo -e "${GREEN}Docker installed successfully${NC}"
    echo -e "${YELLOW}Note: You may need to log out and back in for group changes to take effect${NC}"
fi

# Stop and remove existing container if exists
if docker ps -a | grep -q stabsstelle; then
    echo -e "${YELLOW}Removing existing stabsstelle container...${NC}"
    docker stop stabsstelle 2>/dev/null || true
    docker rm stabsstelle 2>/dev/null || true
fi

# Create deployment directory
DEPLOY_DIR="/opt/stabsstelle-deploy"
echo -e "${GREEN}Creating deployment directory at $DEPLOY_DIR${NC}"
sudo mkdir -p $DEPLOY_DIR
cd $DEPLOY_DIR

# Download deployment files from GitHub
echo -e "${GREEN}Downloading deployment files...${NC}"
curl -H "Authorization: token $GITHUB_TOKEN" \
     -L https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/Dockerfile \
     -o Dockerfile

curl -H "Authorization: token $GITHUB_TOKEN" \
     -L https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/requirements_production.txt \
     -o requirements_production.txt

curl -H "Authorization: token $GITHUB_TOKEN" \
     -L https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/nginx.conf \
     -o nginx.conf

curl -H "Authorization: token $GITHUB_TOKEN" \
     -L https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/supervisord.conf \
     -o supervisord.conf

curl -H "Authorization: token $GITHUB_TOKEN" \
     -L https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/uuid_compat.py \
     -o uuid_compat.py

curl -H "Authorization: token $GITHUB_TOKEN" \
     -L https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/entrypoint.sh \
     -o entrypoint.sh

curl -H "Authorization: token $GITHUB_TOKEN" \
     -L https://raw.githubusercontent.com/MLeprich/stabsstelle-pi-deploy/main/fix_models.py \
     -o fix_models.py

# Build Docker image
echo -e "${GREEN}Building Docker image (this may take 5-10 minutes)...${NC}"
docker build --build-arg GITHUB_TOKEN=$GITHUB_TOKEN -t stabsstelle:production .

# Get IP address
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Run container
echo -e "${GREEN}Starting Stabsstelle container...${NC}"
docker run -d \
    --name stabsstelle \
    --restart unless-stopped \
    -p 80:80 \
    -v stabsstelle_data:/root/projects/Stabsstelle/data \
    -v stabsstelle_logs:/logs \
    stabsstelle:production

# Wait for startup
echo -e "${YELLOW}Waiting for services to start...${NC}"
sleep 10

# Check if running
if docker ps | grep -q stabsstelle; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}✓ Stabsstelle deployed successfully!${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "${GREEN}Access the dashboard at:${NC}"
    echo -e "${GREEN}  http://$IP_ADDRESS${NC}"
    echo ""
    echo -e "${GREEN}Login credentials:${NC}"
    echo -e "${GREEN}  Username: admin${NC}"
    echo -e "${GREEN}  Password: admin123${NC}"
    echo ""
    echo -e "${YELLOW}Important: Change the admin password after first login!${NC}"
    echo ""
    echo -e "${GREEN}Container management:${NC}"
    echo "  View logs:    docker logs stabsstelle"
    echo "  Stop:         docker stop stabsstelle"
    echo "  Start:        docker start stabsstelle"
    echo "  Restart:      docker restart stabsstelle"
    echo "  Remove:       docker stop stabsstelle && docker rm stabsstelle"
else
    echo -e "${RED}Error: Container failed to start${NC}"
    echo "Check logs with: docker logs stabsstelle"
    exit 1
fi
