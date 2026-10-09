"""
Router for Crop Recommendations and Knowledge Base
Exposes endpoints for deterministic crop recommendations per farm profile and risk outlook.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Dict, Any, List, Optional
from datetime import date

from app.database import get_db
from app.models.farm import Farm
from app.models.crop import Crop
from app.services.crop_recommender import CropRecommenderService, seed_crops_if_empty
from app.services.risk_engine import RiskEngine
from app.services.weather_service import WeatherService
import logging

logger = logging.getLogger("kishan_mausam.router.crops")
router = APIRouter(tags=["Crop Recommendations & Knowledge Base"])

risk_engine = RiskEngine()

@router.get("/farms/{farm_id}/crops/recommendations", response_model=Dict[str, Any])
async def get_crop_recommendations(
    farm_id: int,
    db: AsyncSession = Depends(get_db)
):
    """
    Get top 5 deterministically ranked crop recommendations for a farm.
    Takes into account:
    - Farm soil, terrain, irrigation type
    - Active cropping season (Kharif, Rabi, Zaid)
    - Horizon 3 seasonal rainfall outlook from the Risk Engine (Open-Meteo EC46/SEAS5)
    - Returns suitability reasons, hazard notes, drought-tolerant alternatives, and 'needs_expert_review: True'.
    """
    farm_res = await db.execute(select(Farm).where(Farm.id == farm_id))
    farm = farm_res.scalars().first()
    if not farm:
        first_farm = (await db.execute(select(Farm))).scalars().first()
        if first_farm:
            farm = first_farm
        else:
            raise HTTPException(status_code=404, detail="Farm not found")

    lat = farm.latitude or 20.85
    lon = farm.longitude or 79.32
    forecast = await WeatherService.get_forecast(lat, lon)
    evaluation = risk_engine.evaluate_farm_risks(
        farm_profile={
            "id": farm.id,
            "name": farm.name,
            "village": farm.village,
            "district": farm.district,
            "terrain": farm.terrain,
            "soil_type": farm.soil_type,
            "current_crop": farm.current_crop,
            "crop_stage": farm.crop_stage
        },
        weather_forecast=forecast
    )
    h3 = evaluation.get("horizon_10_46d_seasonal", {})
    below_normal_rain = h3.get("below_normal_rain_prob", 35.0)
    above_normal_temp = h3.get("above_normal_temp_prob", 35.0)

    recommender = CropRecommenderService(db)
    result = await recommender.recommend_crops(
        farm=farm,
        below_normal_rain_prob=below_normal_rain,
        above_normal_temp_prob=above_normal_temp
    )
    return result

@router.get("/crops/database", response_model=List[Dict[str, Any]])
async def get_crop_database(
    season: Optional[str] = Query(None, description="Filter by season (kharif, rabi, zaid)"),
    db: AsyncSession = Depends(get_db)
):
    """
    List all crops in the knowledge base.
    Used for inspection, audit, and expert agronomist review.
    """
    await seed_crops_if_empty(db)
    
    query = select(Crop)
    if season:
        query = query.where(Crop.season == season.lower())
    
    res = await db.execute(query)
    crops = res.scalars().all()
    
    return [
        {
            "id": c.id,
            "name_hi": c.name_hi,
            "name_en": c.name_en,
            "season": c.season,
            "suitable_terrains": c.suitable_terrains,
            "suitable_soils": c.suitable_soils,
            "irrigation_need": c.irrigation_need,
            "drought_tolerance": c.drought_tolerance,
            "frost_tolerance": c.frost_tolerance,
            "flood_tolerance": c.flood_tolerance,
            "duration_days_min": c.duration_days_min,
            "duration_days_max": c.duration_days_max,
            "water_need_mm_season": c.water_need_mm_season,
            "source_citation": c.source_citation,
            "needs_expert_review": c.needs_expert_review,
        }
        for c in crops
    ]
