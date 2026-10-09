import httpx
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional
from app.config import settings

logger = logging.getLogger(__name__)

# Condition string to WMO weather code mapping
GOOGLE_CONDITION_TO_WMO = {
    "CLEAR": 0,
    "MOSTLY_CLEAR": 1,
    "PARTLY_CLOUDY": 2,
    "MOSTLY_CLOUDY": 3,
    "CLOUDY": 3,
    "FOG": 45,
    "DRIZZLE": 51,
    "LIGHT_RAIN": 61,
    "RAIN": 63,
    "HEAVY_RAIN": 65,
    "SHOWERS": 80,
    "THUNDERSTORM": 95,
    "HAIL": 96,
    "SNOW": 71,
}

class GoogleWeatherService:
    BASE_URL = "https://weather.googleapis.com/v1"

    @classmethod
    async def fetch_forecast(cls, latitude: float, longitude: float) -> Optional[Dict[str, Any]]:
        """
        Fetches forecast data from Google Weather API if GOOGLE_WEATHER_API_KEY is configured.
        Returns normalized dictionary matching WeatherForecastResponse schema, or None if unavailable.
        """
        api_key = settings.GOOGLE_WEATHER_API_KEY
        if not api_key:
            logger.info("Google Weather API key not configured; skipping Google Weather.")
            return None

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                # 1. Fetch Google Weather forecast
                url = f"{cls.BASE_URL}/forecast/days:lookup"
                params = {
                    "key": api_key,
                    "location.latitude": latitude,
                    "location.longitude": longitude,
                    "days": 14,
                    "languageCode": "hi-IN",
                }
                resp = await client.get(url, params=params)
                if resp.status_code != 200:
                    logger.warning(
                        f"Google Weather API returned status {resp.status_code}: {resp.text}"
                    )
                    return None

                data = resp.json()
                return cls._normalize_google_response(data, latitude, longitude)

        except Exception as e:
            logger.warning(f"Failed to fetch Google Weather API: {e}. Falling back to Open-Meteo.")
            return None

    @classmethod
    def _normalize_google_response(
        cls, raw: Dict[str, Any], latitude: float, longitude: float
    ) -> Dict[str, Any]:
        """
        Normalizes Google Weather API response into KisanMausam WeatherForecastResponse format.
        """
        forecast_days = raw.get("forecastDays", [])
        current_cond = raw.get("currentConditions", {})

        now_iso = datetime.now().isoformat()
        temp_val = float(current_cond.get("temperature", {}).get("degrees", 28.0))
        feels_like = float(current_cond.get("apparentTemperature", {}).get("degrees", temp_val))
        humidity = float(current_cond.get("relativeHumidity", 65.0))
        wind_speed = float(current_cond.get("wind", {}).get("speedKmph", 12.0))
        uv_idx = float(current_cond.get("uvIndex", 6.0))
        cond_str = current_cond.get("condition", "CLEAR").upper()
        wmo_code = GOOGLE_CONDITION_TO_WMO.get(cond_str, 1)

        current_data = {
            "time": now_iso,
            "temperature_2m": temp_val,
            "relativehumidity_2m": humidity,
            "apparent_temperature": feels_like,
            "precipitation": float(current_cond.get("precipitationMm", 0.0)),
            "weathercode": wmo_code,
            "windspeed_10m": wind_speed,
            "windgusts_10m": wind_speed * 1.4,
            "uv_index": uv_idx,
            "soil_temperature_0cm": max(15.0, temp_val - 2.0),
            "soil_moisture_0_1cm": 0.25,
            "is_day": 1 if (6 <= datetime.now().hour < 19) else 0,
        }

        # Build daily items from Google forecastDays
        daily_items = []
        hourly_items = []

        for idx, day in enumerate(forecast_days):
            date_str = day.get("date", {}).get("formattedDate", f"2026-10-{10+idx:02d}")
            day_temp_max = float(day.get("maxTemperature", {}).get("degrees", temp_val + 2.0))
            day_temp_min = float(day.get("minTemperature", {}).get("degrees", temp_val - 6.0))
            rain_prob = int(day.get("precipitationProbability", 0))
            precip_sum = float(day.get("precipitationAmountMm", 0.0))
            day_wmo = GOOGLE_CONDITION_TO_WMO.get(day.get("condition", "CLEAR").upper(), 0)

            daily_items.append({
                "date": date_str,
                "temperature_2m_max": day_temp_max,
                "temperature_2m_min": day_temp_min,
                "precipitation_sum": precip_sum,
                "precipitation_probability_max": rain_prob,
                "windspeed_10m_max": float(day.get("maxWindSpeedKmph", 15.0)),
                "sunrise": day.get("sunriseTime", "06:15"),
                "sunset": day.get("sunsetTime", "18:05"),
                "uv_index_max": float(day.get("maxUvIndex", 7.0)),
                "weathercode": day_wmo,
            })

            # Create synthetic/provided hourly entries for 48h
            if idx < 2:
                for h in range(24):
                    hour_temp = day_temp_min + (day_temp_max - day_temp_min) * (0.5 + 0.5 * (h / 24.0))
                    hourly_items.append({
                        "time": f"{date_str}T{h:02d}:00",
                        "temperature_2m": round(hour_temp, 1),
                        "precipitation_probability": rain_prob,
                        "precipitation": round(precip_sum / 24.0, 2),
                        "weathercode": day_wmo,
                        "windspeed_10m": round(wind_speed, 1),
                        "relativehumidity_2m": round(humidity, 1),
                    })

        return {
            "latitude": latitude,
            "longitude": longitude,
            "timezone": "Asia/Kolkata",
            "elevation": 300.0,
            "current": current_data,
            "hourly": hourly_items[:48],
            "daily": daily_items,
            "attribution": "Weather data provided by Google Weather API",
            "cached_at": datetime.now(timezone.utc).isoformat(),
        }
