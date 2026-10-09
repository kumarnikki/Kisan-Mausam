from fastapi import APIRouter, Query, HTTPException
from typing import Optional, Dict, Any
from app.schemas.weather import WeatherForecastResponse
from app.services.weather_service import WeatherService
from app.services.enso_service import fetch_enso_status

router = APIRouter(prefix="/weather", tags=["Live Weather"])

@router.get("/forecast", response_model=WeatherForecastResponse)
async def get_weather_forecast(
    latitude: float = Query(..., ge=-90.0, le=90.0, description="Latitude (e.g. 21.1458 for Nagpur)"),
    longitude: float = Query(..., ge=-180.0, le=180.0, description="Longitude (e.g. 79.0882 for Nagpur)")
):
    try:
        data = await WeatherService.get_forecast(latitude, longitude)
        return data
    except Exception as e:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to retrieve forecast data from weather source: {str(e)}"
        )

@router.get("/enso")
async def get_enso_status():
    """
    Returns monthly ENSO (El Niño / Southern Oscillation) phase, NOAA CPC ONI status,
    probabilities for upcoming seasons, plain Hindi explanation, and accuracy rules.
    """
    return await fetch_enso_status()
