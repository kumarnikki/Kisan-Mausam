from pydantic import BaseModel, Field
from typing import List, Optional

class CropBase(BaseModel):
    name_hi: str
    name_en: str
    season: str
    suitable_terrains: List[str]
    suitable_soils: List[str]
    irrigation_need: str
    drought_tolerance: str
    flood_tolerance: str
    frost_tolerance: str
    duration_days_min: int
    duration_days_max: int
    sowing_temp_min_c: float
    sowing_temp_max_c: float
    water_need_mm_season: float
    source_citation: str
    needs_expert_review: bool

class CropResponse(CropBase):
    id: int

    class Config:
        from_attributes = True

class CropRecommendationItem(BaseModel):
    crop: CropResponse
    match_score: float = Field(..., ge=0.0, le=100.0)
    match_reasons_hi: List[str]
    match_reasons_en: List[str]
    risk_notes_hi: Optional[str] = None
    risk_notes_en: Optional[str] = None
    resilient_alternative: Optional[str] = None

class CropRecommendationResponse(BaseModel):
    farm_id: int
    season: str
    terrain: str
    soil: str
    irrigation: str
    outlook_rainfall_anomaly_pct: float
    recommendations: List[CropRecommendationItem]
    ai_guidance_hi: Optional[str] = None
    disclaimer_hi: str = "यह सुझाव कृषि वैज्ञानिकों एवं मौसम आंकड़ों पर आधारित हैं। कृपया अंतिम निर्णय से पूर्व नजदीकी कृषि विज्ञान केंद्र (KVK) से संपर्क करें।"
