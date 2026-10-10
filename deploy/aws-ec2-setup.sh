#!/bin/bash
# ==============================================================================
# Kisan Mausam — Automated AWS EC2 Production Deployment Script
# Target OS: Ubuntu 22.04 / 24.04 LTS (AWS ap-south-1 Mumbai Region)
# Integrates Docker Compose, Nginx, UFW, and AWS Cloud Services (Bedrock, Polly,
# Translate, SNS, SES, S3, DynamoDB, CloudWatch)
# ==============================================================================

set -e

echo "🚀 [1/5] Updating Ubuntu system packages on AWS EC2..."
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y curl git ufw nginx-common apt-transport-https ca-certificates gnupg lsb-release awscli

echo "🐳 [2/5] Installing Docker Engine & Docker Compose Plugin..."
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

echo "🛡️ [3/5] Configuring AWS EC2 Host Firewall (UFW)..."
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8000/tcp
sudo ufw --force enable

echo "📦 [4/5] Building and launching Kisan Mausam AWS containers..."
if [ -f "docker-compose.yml" ]; then
    sudo docker compose down || true
    sudo docker compose up -d --build
else
    echo "⚠️ docker-compose.yml not found in current directory. Please run this script from the repository root."
    exit 1
fi

echo "✅ [5/5] Verifying container health and AWS service endpoints..."
sudo docker compose ps

EC2_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || curl -s http://checkip.amazonaws.com)
echo "=================================================================="
echo "🎉 Kisan Mausam AWS Cloud Deployment Complete!"
echo "🌐 Web Application (CloudFront/EC2): http://${EC2_PUBLIC_IP}"
echo "⚡ FastAPI Swagger Documentation:    http://${EC2_PUBLIC_IP}:8000/docs"
echo "☁️ AWS Cloud Services Health Check:  http://${EC2_PUBLIC_IP}:8000/api/v1/aws/status"
echo "=================================================================="
