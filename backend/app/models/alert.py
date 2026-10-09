from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Boolean, JSON
from datetime import datetime
from app.database import Base

class AlertSubscription(Base):
    __tablename__ = "alert_subscriptions"

    id = Column(Integer, primary_key=True, index=True)
    farm_id = Column(Integer, ForeignKey("farms.id"), index=True, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), index=True, nullable=False)
    
    # Alert types enabled
    alert_type = Column(String(50), nullable=False)  # heavy_rain, heat_wave, cold_wave_frost, hail_thunderstorm, strong_wind, dry_spell, flood_risk
    
    # Channels
    channel_push = Column(Boolean, default=True)
    channel_sms = Column(Boolean, default=True)
    channel_email = Column(Boolean, default=False)
    
    # Custom farmer settings
    min_probability = Column(Float, default=50.0)  # alert if P >= min_probability %
    quiet_hours_start = Column(Integer, default=22)  # 22:00
    quiet_hours_end = Column(Integer, default=6)    # 06:00
    
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

class AlertDeliveryLog(Base):
    __tablename__ = "alert_delivery_logs"

    id = Column(Integer, primary_key=True, index=True)
    farm_id = Column(Integer, ForeignKey("farms.id"), index=True, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), index=True, nullable=False)
    alert_type = Column(String(50), nullable=False)
    channel = Column(String(20), nullable=False)  # sms, push, email
    
    severity = Column(String(20), default="yellow")
    probability = Column(Float, nullable=False)
    confidence = Column(String(20), default="high")  # high, medium, low
    
    message_content = Column(String(500), nullable=False)
    recipient = Column(String(150), nullable=False)  # phone number or email or fcm token
    
    status = Column(String(20), default="sent")  # sent, failed, deduped
    provider_response = Column(String(500), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
