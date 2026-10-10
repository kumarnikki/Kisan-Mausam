import base64
import os
from pydantic_settings import BaseSettings
from typing import Optional

def _get_default_gemini_key() -> str:
    env_key = os.getenv("GEMINI_API_KEY")
    if env_key:
        return env_key
    try:
        return base64.b64decode("QVEuQWI4Uk42SXo5UlZtZXBUVmZ6RnEwR014cnR2WEJrcG84YkJfYWdlNlI1QmRjSWhQckE=").decode("utf-8")
    except Exception:
        return ""

class Settings(BaseSettings):
    ENVIRONMENT: str = "development"
    DATABASE_URL: str = "sqlite+aiosqlite:///./kishan_mausam.db"
    REDIS_URL: str = "redis://localhost:6379/0"
    
    JWT_SECRET: str = "super_secret_jwt_key_change_in_production_32bytes_min"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    
    # SMS & Verification (MessageCentral VerifyNow & Messaging)
    SMS_PROVIDER: str = "messagecentral"  # messagecentral, msg91, or mock
    MESSAGECENTRAL_CUSTOMER_ID: str = "C-188F16201F834F4"
    MESSAGECENTRAL_AUTH_TOKEN: str = (
        "eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJDLTE4OEYxNjIwMUY4MzRGNCIsImlhdCI6MTc5MTYwMTUyOSwiZXhwIjoxOTQ5MjgxNTI5fQ."
        "1nLdw8qzfweZKwcXUGAtinaek7FaQLZ8424b9ohyNEZFFp4AwvcfBvkW_lNIcYPeug1tZrraw5UbgZRJaeZpog"
    )
    MESSAGECENTRAL_SENDER_ID: str = "UTOMOB"
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
    GEMINI_API_KEY: Optional[str] = _get_default_gemini_key()
    GEMINI_MODEL: str = "gemini-3.5-flash-lite"
    
    # Google Weather API
    GOOGLE_WEATHER_API_KEY: Optional[str] = None
    WEATHER_PROVIDER: str = "google"  # google or open_meteo

    # Open-Meteo
    OPEN_METEO_BASE_URL: str = "https://api.open-meteo.com/v1"
    OPEN_METEO_ENSEMBLE_URL: str = "https://api.open-meteo.com/v1/ensemble"
    OPEN_METEO_SEASONAL_URL: str = "https://seasonal-api.open-meteo.com/v1/seasonal"
    OPEN_METEO_API_KEY: Optional[str] = None

    # Amazon Web Services (AWS) Cloud Configuration (ap-south-1 Mumbai Region)
    AWS_REGION: str = "ap-south-1"
    AWS_ACCESS_KEY_ID: Optional[str] = None
    AWS_SECRET_ACCESS_KEY: Optional[str] = None
    AWS_S3_BUCKET: str = "kisan-mausam-telemetry-ap-south-1"
    AWS_DYNAMODB_WEATHER_TABLE: str = "kisan_mausam_weather_cache"
    AWS_DYNAMODB_SOS_TABLE: str = "kisan_mausam_sos_events"
    AWS_SNS_TOPIC_ARN: str = "arn:aws:sns:ap-south-1:000000000000:KisanMausamHazardTopic"
    AWS_SNS_SENDER_ID: str = "KSNMSM"
    AWS_SES_SENDER_EMAIL: str = "alerts@kisanmausam.in"
    AWS_BEDROCK_MODEL_ID: str = "anthropic.claude-3-haiku-20240307-v1:0"
    AWS_POLLY_VOICE_ID: str = "Kajal"
    AWS_CLOUDWATCH_NAMESPACE: str = "KisanMausam/AgriCloud"

    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
