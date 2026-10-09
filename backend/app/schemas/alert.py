from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime

class AlertSubscriptionCreate(BaseModel):
    farm_id: int
    alert_type: str  # heavy_rain, heat_wave, cold_wave_frost, hail_thunderstorm, strong_wind, dry_spell, flood_risk
    channel_push: bool = True
    channel_sms: bool = True
    channel_email: bool = False
    min_probability: float = Field(50.0, ge=10.0, le=100.0)
    quiet_hours_start: int = Field(22, ge=0, le=23)
    quiet_hours_end: int = Field(6, ge=0, le=23)

class AlertSubscriptionResponse(AlertSubscriptionCreate):
    id: int
    user_id: int
    is_active: bool
    created_at: datetime

    class Config:
        from_attributes = True

class AlertDeliveryLogResponse(BaseModel):
    id: int
    farm_id: int
    alert_type: str
    channel: str
    severity: str
    probability: float
    confidence: str
    message_content: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True

class RiskHorizonDetail(BaseModel):
    horizon_name: str  # "Days 1-3", "Days 4-10", "Days 10-46 Outlook"
    confidence: str    # "High", "Medium", "Low-Medium"
    risks_detected: List[dict]
    source: str
    updated_at: str

class RiskForecastResponse(BaseModel):
    farm_id: int
    farm_name: str
    village: Optional[str]
    crop: Optional[str]
    crop_stage: str
    horizon_1_3d: RiskHorizonDetail
    horizon_4_10d: RiskHorizonDetail
    horizon_10_46d_seasonal: RiskHorizonDetail
    enso_summary: dict
