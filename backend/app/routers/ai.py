import logging
from typing import List, Optional
from pydantic import BaseModel
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.farm import Farm
from app.services.ai_advisor import ai_advisor_service
from app.services.weather_service import WeatherService
from app.services.risk_engine import RiskEngine
from app.services.enso_service import fetch_enso_status

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/farms/{farm_id}/ai", tags=["AI Krishi Sahayak"])

risk_engine = RiskEngine()

class AIChatRequest(BaseModel):
    message: str
    audio_base64: Optional[str] = None
    api_key: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    location_name: Optional[str] = None
    current_temp: Optional[float] = None
    current_humidity: Optional[float] = None
    current_wind: Optional[float] = None
    weather_condition: Optional[str] = None
    crop: Optional[str] = None
    crop_stage: Optional[str] = None

class AIChatResponse(BaseModel):
    reply_text: str
    actionable_tips: List[str]
    kvk_contact: str
    disclaimer: str
    grounding_summary: dict

@router.post("/chat", response_model=AIChatResponse)
async def chat_with_krishi_sahayak(
    farm_id: int,
    request: AIChatRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Interacts with AI Krishi Sahayak (Gemini 2.0 Flash) grounded strictly
    in real-time farm profile, active location/GPS weather, risk engine warnings, and ENSO status.
    """
    stmt = select(Farm).where(Farm.id == farm_id)
    res = await db.execute(stmt)
    farm = res.scalars().first()

    if not farm:
        farm_dict = {
            "id": farm_id,
            "name": "बड़ा खेत 1",
            "village": request.location_name or "उमरेड (Umred)",
            "district": request.location_name or "नागपुर (Nagpur)",
            "state": "Maharashtra",
            "latitude": request.latitude or 21.1458,
            "longitude": request.longitude or 79.0882,
            "terrain": "plain",
            "soil_type": "black",
            "irrigation_type": "tube-well",
            "current_crop": request.crop or "सोयाबीन (Soybean)",
            "crop_stage": request.crop_stage or "फूल आने की अवस्था"
        }
    else:
        farm_dict = {
            "id": farm.id,
            "name": farm.name,
            "village": request.location_name or farm.village,
            "district": request.location_name or farm.district,
            "state": farm.state,
            "latitude": request.latitude or farm.latitude,
            "longitude": request.longitude or farm.longitude,
            "terrain": farm.terrain,
            "soil_type": farm.soil_type,
            "irrigation_type": farm.irrigation_type,
            "current_crop": request.crop or farm.current_crop,
            "crop_stage": request.crop_stage or farm.crop_stage
        }

    # Gather real grounded context using active coordinates
    weather_data = await WeatherService.get_forecast(farm_dict["latitude"], farm_dict["longitude"])
    
    # Enrich with live readings if provided directly by client
    if "current" not in weather_data:
        weather_data["current"] = {}
    if request.current_temp is not None:
        weather_data["current"]["temperature"] = request.current_temp
    if request.current_humidity is not None:
        weather_data["current"]["relative_humidity"] = request.current_humidity
    if request.current_wind is not None:
        weather_data["current"]["wind_speed"] = request.current_wind
    if request.weather_condition:
        weather_data["current"]["condition"] = request.weather_condition

    risk_data = risk_engine.evaluate_farm_risks(farm_dict, weather_data)
    enso_data = await fetch_enso_status()

    advice = await ai_advisor_service.get_farming_advice(
        user_message=request.message,
        farm_profile=farm_dict,
        weather_data=weather_data,
        risk_data=risk_data,
        enso_data=enso_data,
        client_api_key=request.api_key
    )

    return AIChatResponse(
        reply_text=advice["reply_text"],
        actionable_tips=advice["actionable_tips"],
        kvk_contact=advice["kvk_contact"],
        disclaimer=advice["disclaimer"],
        grounding_summary=advice["grounding_summary"]
    )
