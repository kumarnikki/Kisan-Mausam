from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.database import engine, Base
from app.routers import auth, farms, weather, alerts, ai, crops
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
    title="KisanMausam API",
    description="""
# किसान मौसम (KisanMausam) Backend API
Hindi-first weather, risk early warnings, crop advisory, and alerts system for farmers in rural India.

### Data Sources & Attribution:
- **Weather Forecasts:** Powered by [Open-Meteo](https://open-meteo.com) under CC BY 4.0 license (Non-Commercial use).
- **Climate Outlook & ENSO:** NOAA CPC & ECMWF Seasonal Models.
- **Risk Thresholds:** Calibrated to IMD (India Meteorological Department) Warning Standards.

### Regulatory & Privacy Compliance:
- Aligned with India's **Digital Personal Data Protection (DPDP) Act 2023**.
- Transactional SMS templates registered under **TRAI DLT** guidelines.
""",
    version="1.0.0",
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

@app.get("/", tags=["Health & Info"])
async def root():
    return {
        "app_name": "KisanMausam Backend",
        "version": "1.0.0",
        "status": "online",
        "environment": settings.ENVIRONMENT,
        "language_primary": "hi-IN",
        "attribution": "Open-Meteo.com (CC BY 4.0)",
        "dpdp_compliant": True
    }
