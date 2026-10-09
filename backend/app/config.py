import os
from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    ENVIRONMENT: str = "development"
    DATABASE_URL: str = "sqlite+aiosqlite:///./kishan_mausam.db"
    REDIS_URL: str = "redis://localhost:6379/0"
    
    JWT_SECRET: str = "super_secret_jwt_key_change_in_production_32bytes_min"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    
    # SMS & Verification
    SMS_PROVIDER: str = "mock"  # mock or msg91
    MSG91_AUTH_KEY: Optional[str] = None
    MSG91_SENDER_ID: str = "KISANW"
    DLT_ENTITY_ID: Optional[str] = None
    
    # Email
    EMAIL_PROVIDER: str = "mock"  # mock or resend
    RESEND_API_KEY: Optional[str] = None
    EMAIL_FROM: str = "alerts@kishanmausam.in"
    
    # Push (FCM)
    FIREBASE_PROJECT_ID: str = "kishan-weather"
    FIREBASE_SERVICE_ACCOUNT_PATH: Optional[str] = None
    
    # AI (Gemini)
    GEMINI_API_KEY: Optional[str] = None
    GEMINI_MODEL: str = "gemini-2.0-flash"
    
    # Google Weather API
    GOOGLE_WEATHER_API_KEY: Optional[str] = None
    WEATHER_PROVIDER: str = "google"  # google or open_meteo

    # Open-Meteo
    OPEN_METEO_BASE_URL: str = "https://api.open-meteo.com/v1"
    OPEN_METEO_ENSEMBLE_URL: str = "https://api.open-meteo.com/v1/ensemble"
    OPEN_METEO_SEASONAL_URL: str = "https://seasonal-api.open-meteo.com/v1/seasonal"
    OPEN_METEO_API_KEY: Optional[str] = None

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
