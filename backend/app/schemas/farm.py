from pydantic import BaseModel, Field
from typing import Optional
from datetime import date, datetime

class FarmCreate(BaseModel):
    name: str = Field(..., max_length=100)
    latitude: float = Field(..., ge=-90.0, le=90.0)
    longitude: float = Field(..., ge=-180.0, le=180.0)
    village: Optional[str] = None
    district: Optional[str] = None
    state: Optional[str] = None
    
    terrain: str = Field("plain", description="hilly, plain, plateau, coastal, barren-dry")
    soil_type: str = Field("alluvial", description="alluvial, black, red, sandy, loamy, unknown")
    irrigation_type: str = Field("rain-fed", description="rain-fed, tube-well, canal")
    land_size_acres: float = Field(2.0, ge=0.1)
    
    current_crop: Optional[str] = None
    crop_stage: str = Field("vegetative", description="sowing, vegetative, flowering, grain_fill, harvest")
    sowing_date: Optional[date] = None

class FarmUpdate(BaseModel):
    name: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    village: Optional[str] = None
    district: Optional[str] = None
    state: Optional[str] = None
    terrain: Optional[str] = None
    soil_type: Optional[str] = None
    irrigation_type: Optional[str] = None
    land_size_acres: Optional[float] = None
    current_crop: Optional[str] = None
    crop_stage: Optional[str] = None
    sowing_date: Optional[date] = None

class FarmResponse(FarmCreate):
    id: int
    user_id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True
