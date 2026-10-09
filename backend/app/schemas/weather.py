from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any

class CurrentWeather(BaseModel):
    time: str
    temperature_2m: float
    relativehumidity_2m: float
    apparent_temperature: float
    precipitation: float
    weathercode: int
    windspeed_10m: float
    windgusts_10m: float
    uv_index: float
    soil_temperature_0cm: float
    soil_moisture_0_1cm: float
    is_day: int = Field(default=1, description="1 for day, 0 for night")

class HourlyForecastItem(BaseModel):
    time: str
    temperature_2m: float
    precipitation_probability: int
    precipitation: float
    weathercode: int
    windspeed_10m: float
    relativehumidity_2m: float

class DailyForecastItem(BaseModel):
    date: str
    temperature_2m_max: float
    temperature_2m_min: float
    precipitation_sum: float
    precipitation_probability_max: int
    windspeed_10m_max: float
    sunrise: str
    sunset: str
    uv_index_max: float
    weathercode: int

class WeatherForecastResponse(BaseModel):
    latitude: float
    longitude: float
    timezone: str
    elevation: float
    current: CurrentWeather
    hourly: List[HourlyForecastItem]
    daily: List[DailyForecastItem]
    attribution: str = "Weather data provided by Open-Meteo.com under CC BY 4.0 (Non-Commercial)"
    cached_at: str
