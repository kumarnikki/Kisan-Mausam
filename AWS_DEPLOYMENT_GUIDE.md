# ☁️ AWS Cloud Architecture & Production Deployment Guide — Kisan Mausam (किसान मौसम)

This guide covers deploying **Kisan Mausam** across **Amazon Web Services (AWS)** (`ap-south-1` Asia Pacific — Mumbai Region) using Infrastructure-as-Code (CloudFormation), Amazon EC2, AWS App Runner, Amazon S3 + CloudFront, AWS Lambda + EventBridge, and AWS AI/Messaging services.

---

## 🏗️ AWS Services Integrated in Kisan Mausam

| AWS Service | Category | Implementation File | Role in Kisan Mausam |
| :--- | :--- | :--- | :--- |
| **Amazon EC2** | Compute | [`deploy/aws-ec2-setup.sh`](./deploy/aws-ec2-setup.sh) | Hosts containerized FastAPI backend & Nginx web server on Ubuntu 24.04 LTS (`t3.small`). |
| **AWS App Runner** | Serverless Compute | [`backend/Dockerfile`](./backend/Dockerfile) | Auto-scaling managed container deployment with zero-config HTTPS TLS load balancing. |
| **AWS Lambda** | Serverless Functions | [`deploy/aws_lambda_weather_poller.py`](./deploy/aws_lambda_weather_poller.py) | Executes every 15 minutes to poll Open-Meteo for registered farms and evaluate IMD hazard rules. |
| **Amazon EventBridge** | Event Bus & Cron | [`deploy/aws-cloudformation.yaml`](./deploy/aws-cloudformation.yaml) | Triggers the `KisanMausam-IMD-Hazard-Poller` Lambda function on a `rate(15 minutes)` schedule. |
| **Amazon Bedrock** | Generative AI | [`backend/app/services/aws_cloud_service.py`](./backend/app/services/aws_cloud_service.py) | Invokes `anthropic.claude-3-haiku-20240307-v1:0` / `amazon.titan-text-express-v1` for grounded Hindi agricultural advisory. |
| **Amazon Polly** | Neural Speech (TTS) | [`backend/app/services/aws_cloud_service.py`](./backend/app/services/aws_cloud_service.py) | Synthesizes natural spoken Hindi (`hi-IN`) & Indian English (`en-IN`) audio bulletins using the **`Kajal` Neural Voice**. |
| **Amazon Translate** | Neural Translation | [`backend/app/services/aws_cloud_service.py`](./backend/app/services/aws_cloud_service.py) | Translates weather warnings & crop advisories across 9 Indian languages (`hi`, `en`, `mr`, `pa`, `gu`, `ta`, `te`, `kn`, `bn`). |
| **Amazon SNS** | Mobile & Pub/Sub | [`backend/app/services/sms_service.py`](./backend/app/services/sms_service.py) | Dispatches TRAI DLT Transactional SMS (`KSNMSM`) and broadcasts Red Alerts / SOS 112 events to `KisanMausamHazardTopic`. |
| **Amazon SES** | Transactional Email | [`backend/app/services/email_service.py`](./backend/app/services/email_service.py) | Delivers HTML weather warning bulletins and weekly agro-advisories from `alerts@kisanmausam.in`. |
| **Amazon S3** | Object Storage Lake | [`backend/app/services/aws_cloud_service.py`](./backend/app/services/aws_cloud_service.py) | Stores encrypted (`AES-256`) farm weather snapshots, soil moisture telemetry, and OTA Android APK binaries. |
| **Amazon CloudFront** | Global Edge CDN | [`deploy/aws-cloudformation.yaml`](./deploy/aws-cloudformation.yaml) | Accelerates web assets and APK downloads via Indian Edge Locations (Mumbai, Delhi, Chennai, Hyderabad, Kolkata). |
| **Amazon DynamoDB** | NoSQL Key-Value | [`backend/app/services/aws_cloud_service.py`](./backend/app/services/aws_cloud_service.py) | Sub-millisecond geohash weather cell caching (`kisan_mausam_weather_cache`) with TTL and SOS 112 audit ledger (`kisan_mausam_sos_events`). |
| **Amazon RDS (PostgreSQL)** | Relational DB | [`backend/app/database.py`](./backend/app/database.py) | Primary ACID relational database for `Users`, `Farms`, `AlertSubscriptions`, and `AlertDeliveryLogs`. |
| **Amazon CloudWatch** | Observability | [`backend/app/services/aws_cloud_service.py`](./backend/app/services/aws_cloud_service.py) | Tracks custom metrics (`HazardsDispatched`, `FarmsEvaluated`, `PollySynthesisCount`, `SNSSMSDispatched`) under `KisanMausam/AgriCloud`. |

---

## ⚡ Option 1: One-Click Infrastructure-as-Code via AWS CloudFormation

Provision the complete serverless & storage stack (S3 Telemetry Lake, CloudFront CDN, DynamoDB Tables, SNS Hazard Topic, IAM Roles, Lambda Poller, and EventBridge 15-min Cron) in **`ap-south-1` (Mumbai)**:

```bash
aws cloudformation deploy \
  --template-file deploy/aws-cloudformation.yaml \
  --stack-name kisan-mausam-production \
  --region ap-south-1 \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides EnvironmentName=production PollyVoiceId=Kajal
```

---

## 🖥️ Option 2: AWS EC2 Production Deployment (Docker Compose)

### Step 1: Launch an EC2 Instance in `ap-south-1` (Mumbai)
1. Log in to the [AWS Management Console](https://aws.amazon.com/console/).
2. Navigate to **EC2** → **Launch Instance**.
3. Configure Instance:
   - **Name**: `kisan-mausam-production-server`
   - **AMI**: Ubuntu Server 24.04 LTS (64-bit x86 / Graviton ARM64)
   - **Instance Type**: `t3.small` (2 vCPU, 2 GB RAM) or `t2.micro`
   - **IAM Instance Profile**: Attach `KisanMausam-AgriCloud-Role-production` (grants zero-secret access to Bedrock, Polly, Translate, SNS, SES, S3, DynamoDB, and CloudWatch)
   - **Security Group Inbound Rules**:
     - SSH (`22`), HTTP (`80`), HTTPS (`443`), Custom TCP (`8000` for FastAPI Swagger UI)
   - **Storage**: 20 GiB `gp3` Encrypted EBS Volume

### Step 2: Connect & Run Automated Provisioning
```bash
ssh -i "kisan-key.pem" ubuntu@<YOUR-EC2-PUBLIC-IP>

git clone https://github.com/kumarnikki/Kisan-Mausam.git
cd Kisan-Mausam
chmod +x deploy/aws-ec2-setup.sh
./deploy/aws-ec2-setup.sh
```

### Step 3: Verify Live AWS Endpoints
- 🌐 **Web Application**: `http://<YOUR-EC2-PUBLIC-IP>`
- 📖 **Interactive OpenAPI / Swagger UI**: `http://<YOUR-EC2-PUBLIC-IP>:8000/docs`
- ☁️ **AWS Architecture Status API**: `http://<YOUR-EC2-PUBLIC-IP>:8000/api/v1/aws/status`

---

## 🚀 Option 3: Serverless Container Deployment via AWS App Runner + S3 / CloudFront

### A. Backend on AWS App Runner
1. Open **AWS App Runner** → **Create service** → Connect GitHub repository `kumarnikki/Kisan-Mausam`.
2. Runtime: **Python 3.11**
   - Build command: `cd backend && pip install -r requirements.txt`
   - Start command: `cd backend && uvicorn app.main:app --host 0.0.0.0 --port 8000`
   - Port: `8000`
3. Attach IAM Instance Role `KisanMausam-AgriCloud-Role-production` and set `AWS_REGION=ap-south-1`.

### B. Frontend & OTA APK on Amazon S3 + Amazon CloudFront
```bash
cd app
flutter build web --release
aws s3 sync build/web/ s3://kisan-mausam-web-ap-south-1/ --delete
aws cloudfront create-invalidation --distribution-id <DIST_ID> --paths "/*"
```

---

## 🔒 SSL / HTTPS Configuration with AWS Certificate Manager (ACM) or Certbot
- For **CloudFront / ALB / App Runner**: Provision a free public TLS 1.3 certificate in **AWS Certificate Manager (ACM)** for your domain.
- For **Standalone EC2**:
  ```bash
  sudo apt-get install -y certbot python3-certbot-nginx
  sudo certbot --nginx -d kisanmausam.in
  ```
