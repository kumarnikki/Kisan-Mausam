import httpx
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional
from app.config import settings
from app.services.google_weather_service import GoogleWeatherService

logger = logging.getLogger(__name__)

# Simple in-memory cache with timestamp (TTL 15 minutes)
_WEATHER_CACHE: Dict[str, Dict[str, Any]] = {}
CACHE_TTL_SECONDS = 900

class WeatherService:
    @staticmethod
    def _cache_key(lat: float, lon: float) -> str:
        return f"{round(lat, 3)}_{round(lon, 3)}"

    @classmethod
    async def get_forecast(cls, latitude: float, longitude: float) -> Dict[str, Any]:
        cache_key = cls._cache_key(latitude, longitude)
        now_ts = datetime.now(timezone.utc).timestamp()

        # Check cache
        if cache_key in _WEATHER_CACHE:
            cached = _WEATHER_CACHE[cache_key]
            if now_ts - cached["timestamp"] < CACHE_TTL_SECONDS:
                return cached["data"]

        # 1. Try Google Weather API if configured
        if settings.WEATHER_PROVIDER == "google" or settings.GOOGLE_WEATHER_API_KEY:
            google_data = await GoogleWeatherService.fetch_forecast(latitude, longitude)
            if google_data:
                _WEATHER_CACHE[cache_key] = {
                    "timestamp": now_ts,
                    "data": google_data
                }
                return google_data

        # 2. Fall back to Open-Meteo API
        url = f"{settings.OPEN_METEO_BASE_URL}/forecast"
        params = {
            "latitude": latitude,
            "longitude": longitude,
            "current": "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m,wind_gusts_10m",
            "hourly": "temperature_2m,relativehumidity_2m,precipitation_probability,precipitation,rain,weathercode,windspeed_10m,windgusts_10m,uv_index,soil_temperature_0cm,soil_moisture_0_1cm,apparent_temperature",
            "daily": "temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,windspeed_10m_max,sunrise,sunset,uv_index_max,weathercode",
            "timezone": "auto",
            "forecast_days": 16,
        }
        if settings.OPEN_METEO_API_KEY:
            params["apikey"] = settings.OPEN_METEO_API_KEY

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(url, params=params)
                resp.raise_for_status()
                raw = resp.json()

            # Format normalized response
            cur_raw = raw.get("current", {})
            hourly = raw.get("hourly", {})
            daily = raw.get("daily", {})

            # Current hour closest index
            now_idx = 0
            times = hourly.get("time", [])
            now_iso = datetime.now().strftime("%Y-%m-%dT%H:00")
            if now_iso in times:
                now_idx = times.index(now_iso)
            elif times:
                # Find closest index
                for idx, t in enumerate(times):
                    if t >= now_iso:
                        now_idx = idx
                        break

            cur_is_day = cur_raw.get("is_day")
            if cur_is_day is None:
                cur_is_day = 1 if (6 <= datetime.now().hour < 19) else 0

            current_data = {
                "time": cur_raw.get("time") or (times[now_idx] if times else datetime.now().isoformat()),
                "temperature_2m": cur_raw.get("temperature_2m") if cur_raw.get("temperature_2m") is not None else hourly.get("temperature_2m", [25.0])[now_idx],
                "relativehumidity_2m": cur_raw.get("relative_humidity_2m") if cur_raw.get("relative_humidity_2m") is not None else hourly.get("relativehumidity_2m", [60.0])[now_idx],
                "apparent_temperature": cur_raw.get("apparent_temperature") if cur_raw.get("apparent_temperature") is not None else hourly.get("apparent_temperature", [26.0])[now_idx],
                "precipitation": cur_raw.get("precipitation") if cur_raw.get("precipitation") is not None else hourly.get("precipitation", [0.0])[now_idx],
                "weathercode": cur_raw.get("weather_code") if cur_raw.get("weather_code") is not None else hourly.get("weathercode", [0])[now_idx],
                "windspeed_10m": cur_raw.get("wind_speed_10m") if cur_raw.get("wind_speed_10m") is not None else hourly.get("windspeed_10m", [10.0])[now_idx],
                "windgusts_10m": cur_raw.get("wind_gusts_10m") if cur_raw.get("wind_gusts_10m") is not None else hourly.get("windgusts_10m", [15.0])[now_idx],
                "uv_index": hourly.get("uv_index", [5.0])[now_idx] if now_idx < len(hourly.get("uv_index", [])) else 5.0,
                "soil_temperature_0cm": hourly.get("soil_temperature_0cm", [24.0])[now_idx] if now_idx < len(hourly.get("soil_temperature_0cm", [])) else 24.0,
                "soil_moisture_0_1cm": hourly.get("soil_moisture_0_1cm", [0.22])[now_idx] if now_idx < len(hourly.get("soil_moisture_0_1cm", [])) else 0.22,
                "is_day": int(cur_is_day),
            }

            hourly_items = []
            for i in range(now_idx, min(now_idx + 48, len(times))):
                hourly_items.append({
                    "time": times[i],
                    "temperature_2m": hourly.get("temperature_2m", [])[i],
                    "precipitation_probability": hourly.get("precipitation_probability", [0])[i] or 0,
                    "precipitation": hourly.get("precipitation", [0.0])[i],
                    "weathercode": hourly.get("weathercode", [0])[i],
                    "windspeed_10m": hourly.get("windspeed_10m", [0.0])[i],
                    "relativehumidity_2m": hourly.get("relativehumidity_2m", [0.0])[i]
                })

            daily_items = []
            daily_times = daily.get("time", [])
            for i in range(min(14, len(daily_times))):
                daily_items.append({
                    "date": daily_times[i],
                    "temperature_2m_max": daily.get("temperature_2m_max", [])[i],
                    "temperature_2m_min": daily.get("temperature_2m_min", [])[i],
                    "precipitation_sum": daily.get("precipitation_sum", [])[i],
                    "precipitation_probability_max": daily.get("precipitation_probability_max", [0])[i] or 0,
                    "windspeed_10m_max": daily.get("windspeed_10m_max", [0.0])[i],
                    "sunrise": daily.get("sunrise", ["06:00"])[i],
                    "sunset": daily.get("sunset", ["18:00"])[i],
                    "uv_index_max": daily.get("uv_index_max", [6.0])[i],
                    "weathercode": daily.get("weathercode", [0])[i]
                })

            formatted = {
                "latitude": raw.get("latitude", latitude),
                "longitude": raw.get("longitude", longitude),
                "timezone": raw.get("timezone", "Asia/Kolkata"),
                "elevation": raw.get("elevation", 0.0),
                "current": current_data,
                "hourly": hourly_items,
                "daily": daily_items,
                "attribution": "Weather data provided by Open-Meteo.com under CC BY 4.0 (Non-Commercial)",
                "cached_at": datetime.now(timezone.utc).isoformat()
            }

            _WEATHER_CACHE[cache_key] = {
                "timestamp": now_ts,
                "data": formatted
            }
            return formatted

        except Exception as e:
            logger.error(f"Error fetching Open-Meteo forecast: {e}")
            if cache_key in _WEATHER_CACHE:
                return _WEATHER_CACHE[cache_key]["data"]
            raise
