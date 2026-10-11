from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.database import engine, Base
from app.routers import auth, farms, weather, alerts, ai, crops, aws_cloud
from app.config import settings
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("kishan_mausam")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Auto-create tables on startup
    logger.info("Initializing database tables...")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("Database initialized successfully.")
    yield
    logger.info("Shutting down application...")

app = FastAPI(
    title="KisanMausam API (AWS Cloud-Native AgriTech Platform)",
    description="""
# किसान मौसम (KisanMausam) — Cloud-Native Backend API on AWS (`ap-south-1`)
Hindi-first hyper-local weather, multi-horizon IMD risk early warnings, GPS-calibrated ICAR crop advisory, and emergency SOS alerting system for farmers in rural India.

### ☁️ Powered by Amazon Web Services (AWS):
- **Compute & Serverless:** Amazon EC2, AWS App Runner, AWS Lambda & Amazon EventBridge (15-min automated hazard polling).
- **AI & Voice:** Amazon Bedrock (Claude 3 Haiku / Titan), Amazon Polly (`Kajal` Neural Hindi TTS), Amazon Translate (9 Indian Languages) + Google Gemini.
- **Storage & Caching:** Amazon S3 (AES-256 Telemetry Lake), Amazon CloudFront CDN, Amazon RDS (PostgreSQL), Amazon DynamoDB (Geohash Weather Cache).
- **Messaging & Observability:** Amazon SNS (Transactional DLT SMS & Topic Fanout), Amazon SES (HTML Bulletins), Amazon CloudWatch (`KisanMausam/AgriCloud`).

### Data Sources & Attribution:
- **Weather Forecasts:** Powered by [Open-Meteo](https://open-meteo.com) under CC BY 4.0 license.
- **Risk Thresholds:** Calibrated to IMD (India Meteorological Department) Warning Standards & ICAR Package of Practices.

### Regulatory & Privacy Compliance:
- Aligned with India's **Digital Personal Data Protection (DPDP) Act 2023**.
- Transactional SMS templates registered under **TRAI DLT** guidelines.
""",
    version="1.2.0",
    lifespan=lifespan
)

# Enable CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routers
app.include_router(auth.router)
app.include_router(farms.router)
app.include_router(weather.router)
app.include_router(alerts.router)
app.include_router(ai.router)
app.include_router(crops.router)
app.include_router(aws_cloud.router)

@app.get("/", tags=["Health & Info"])
async def root():
    return {
        "app_name": "KisanMausam Backend",
        "version": "1.2.0",
        "status": "online",
        "cloud_provider": "AWS (ap-south-1 Mumbai)",
        "environment": settings.ENVIRONMENT,
        "language_primary": "hi-IN",
        "attribution": "Open-Meteo.com (CC BY 4.0)",
        "dpdp_compliant": True
    }

@app.get("/api/v1/app/version", tags=["App Updates"])
async def get_app_version():
    return {
        "version": "2.0.0",
        "versionCode": 24,
        "releaseName": "Kisan Mausam v2.0.0 - Clean Home UI, Account Phone Security & El Niño Outlook Edition",
        "apkUrl": "https://github.com/kumarnikki/Kisan-Mausam/releases/download/v2.0.0/kisan-mausam-release.apk",
        "githubReleaseUrl": "https://github.com/kumarnikki/Kisan-Mausam/releases/latest",
        "changelog": "• Clean Home Layout: Removed footer attribution text for a distraction-free bottom layout\n• Registered Account Phone Security: Locked mobile number against editing or overwriting in Settings once an account is created\n• Pinned Weather Warning Header, Saturated Weather Hero Card, 2×2 Field Conditions Grid, NOAA CPC / IRI El Niño (ENSO) Season Card, 30-Day Seasonal Outlook Card, and Top 3 ICAR Crop Recommendations",
        "minRequiredVersion": "1.0.0",
        "publishedAt": "2026-10-11T10:15:00Z"
    }

