# ☁️ AWS Deployment Guide - Kisan Mausam (किसान मौसम)

This guide walks you through deploying **Kisan Mausam** on **Amazon Web Services (AWS)** for your hackathon presentation or production deployment.

---

## ⚡ Option 1: AWS EC2 (Single-Instance Docker Compose) — *Recommended for Hackathons*
*Fastest, 100% AWS Free Tier eligible (`t2.micro` or `t3.small`).*

### Step 1: Launch an EC2 Instance
1. Log in to [AWS Management Console](https://aws.amazon.com/console/).
2. Navigate to **EC2** → **Launch Instance**.
3. Settings:
   - **Name**: `kisan-mausam-server`
   - **AMI**: Ubuntu Server 24.04 LTS (64-bit x86)
   - **Instance Type**: `t2.micro` (Free Tier) or `t3.small` (2 vCPU, 2 GB RAM recommended for faster builds)
   - **Key Pair**: Create or select your `.pem` key pair (e.g. `kisan-key.pem`)
   - **Network Settings (Security Group)**: Allow the following inbound traffic:
     - SSH (Port 22) from `My IP` or `0.0.0.0/0`
     - HTTP (Port 80) from `0.0.0.0/0`
     - HTTPS (Port 443) from `0.0.0.0/0`
     - Custom TCP (Port 8000) from `0.0.0.0/0` (FastAPI backend)
   - **Storage**: 20 GiB gp3
4. Click **Launch Instance**.

### Step 2: Connect via SSH
Open your terminal (PowerShell, Command Prompt, or bash) and run:
```bash
ssh -i "path/to/kisan-key.pem" ubuntu@<YOUR-EC2-PUBLIC-IP>
```

### Step 3: Clone Repository & Deploy with One Command
```bash
# 1. Clone your GitHub repository
git clone https://github.com/kumarnikki/Kisan-Mausam.git
cd Kisan-Mausam

# 2. Make the automated deployment script executable & run it
chmod +x deploy/aws-ec2-setup.sh
./deploy/aws-ec2-setup.sh
```

### Step 4: Access Your Live Application
- 🌐 **Web App**: `http://<YOUR-EC2-PUBLIC-IP>`
- 📖 **API Docs & Swagger**: `http://<YOUR-EC2-PUBLIC-IP>:8000/docs`
- 🤖 **FastAPI Health Check**: `http://<YOUR-EC2-PUBLIC-IP>:8000/alerts/risk`

---

## 🚀 Option 2: AWS App Runner (Serverless Backend) + S3 / CloudFront (Frontend)

If you prefer managed serverless deployment without maintaining an EC2 Linux VM:

### A. Deploy Backend on AWS App Runner
1. In AWS Console, search for **App Runner** → **Create service**.
2. Source: **Source code repository** (Connect your GitHub repo: `kumarnikki/Kisan-Mausam`).
3. Build Settings:
   - Configuration file: Configure all settings here
   - Runtime: `Python 3.11`
   - Build command: `cd backend && pip install -r requirements.txt`
   - Start command: `cd backend && uvicorn app.main:app --host 0.0.0.0 --port 8000`
   - Port: `8000`
4. Environment variables:
   - `GEMINI_API_KEY`: *(Optional Google Gemini API key)*
5. Click **Deploy**. App Runner will provide a live HTTPS URL like `https://xyz.awsapprunner.com`.

### B. Deploy Frontend on AWS S3 + CloudFront
1. Build Flutter web locally:
   ```bash
   cd app
   flutter build web --release
   ```
2. In AWS Console, search for **S3** → Create bucket (e.g. `kisan-mausam-web`).
3. Enable **Static website hosting** (Index document: `index.html`).
4. Upload all files from `app/build/web` to the S3 bucket.
5. Create an **AWS CloudFront Distribution** pointing to your S3 bucket for global HTTPS CDN delivery.

---

## 🔒 Free SSL / HTTPS Configuration (Let's Encrypt / Certbot)
If you have a domain name pointing to your EC2 Public IP (e.g., `kisan.yourdomain.com`):
```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d kisan.yourdomain.com
```
Certbot will automatically install and configure HTTPS with automatic renewal!
