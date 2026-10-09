from sqlalchemy import Column, Integer, String, Boolean, DateTime
from datetime import datetime
from app.database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    phone_number = Column(String(20), unique=True, index=True, nullable=False)
    name = Column(String(100), nullable=True)
    preferred_language = Column(String(10), default="hi")  # hi, en
    email = Column(String(150), nullable=True)
    
    # DPDP Act 2023 Consents
    consent_location = Column(Boolean, default=True)
    consent_sms = Column(Boolean, default=True)
    consent_email = Column(Boolean, default=True)
    consent_notifications = Column(Boolean, default=True)
    consent_ai_logging = Column(Boolean, default=False)
    
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class FCMDevice(Base):
    __tablename__ = "fcm_devices"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, index=True, nullable=False)
    device_token = Column(String(300), unique=True, nullable=False)
    device_type = Column(String(50), default="android")
    created_at = Column(DateTime, default=datetime.utcnow)
    is_active = Column(Boolean, default=True)
