#!/bin/bash
# ==============================================================================
# Kisan Mausam - Automated AWS EC2 Deployment Script (Ubuntu 22.04 / 24.04 LTS)
# Designed for Hackathon Deployment on AWS Free Tier (t2.micro / t3.small)
# ==============================================================================

set -e

echo "🚀 [1/5] Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y curl git ufw nginx-common apt-transport-https ca-certificates gnupg lsb-release

echo "🐳 [2/5] Installing Docker & Docker Compose..."
if ! command -v docker &> /dev/null; then
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker $USER
fi

echo "🛡️ [3/5] Configuring firewall (UFW)..."
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8000/tcp
sudo ufw --force enable

echo "📦 [4/5] Building and launching Kisan Mausam containers..."
if [ -f "docker-compose.yml" ]; then
    sudo docker compose down || true
    sudo docker compose up -d --build
else
    echo "⚠️ docker-compose.yml not found in current directory. Please run this script from the project root."
    exit 1
fi

echo "✅ [5/5] Checking container status..."
sudo docker compose ps

echo "=================================================================="
echo "🎉 Deployment Successful!"
echo "🌐 Frontend (Flutter Web): http://$(curl -s http://checkip.amazonaws.com)"
echo "⚡ Backend API (FastAPI):  http://$(curl -s http://checkip.amazonaws.com):8000/docs"
echo "=================================================================="
