import logging
from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.farm import Farm
from app.models.alert import AlertSubscription, AlertDeliveryLog
from app.schemas.alert import (
    AlertSubscriptionCreate,
    AlertSubscriptionResponse,
    AlertDeliveryLogResponse,
    RiskForecastResponse,
)
from app.services.risk_engine import RiskEngine
from app.services.enso_service import fetch_enso_status
from app.services.weather_service import WeatherService
from app.services.alert_dispatcher import AlertDispatcher

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/farms/{farm_id}/alerts", tags=["Risk & Alerts"])

risk_engine = RiskEngine()

@router.get("/risk", response_model=RiskForecastResponse)
async def get_farm_risk_forecast(
    farm_id: int,
    latitude: Optional[float] = Query(None),
    longitude: Optional[float] = Query(None),
    location_name: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_db)
):
    """
    Evaluates 3 risk horizons for a farm based on live Open-Meteo forecast:
    - Horizon 1 (Days 1-3, High confidence)
    - Horizon 2 (Days 4-10, Medium confidence)
    - Horizon 3 (Days 10-46 Seasonal outlook)
    Applies crop stage sensitivity weights.
    """
    stmt = select(Farm).where(Farm.id == farm_id)
    res = await db.execute(stmt)
    farm = res.scalars().first()

    if not farm:
        # If testing with demo farm id 1
        farm_dict = {
            "id": farm_id,
            "name": "बड़ा खेत 1",
            "village": "उमरेड (Umred)",
            "district": "नागपुर (Nagpur)",
            "latitude": 21.1458,
            "longitude": 79.0882,
            "terrain": "plain",
            "soil_type": "black",
            "current_crop": "सोयाबीन (Soybean)",
            "crop_stage": "flowering"
        }
    else:
        farm_dict = {
            "id": farm.id,
            "name": farm.name,
            "village": farm.village,
            "district": farm.district,
            "latitude": farm.latitude,
            "longitude": farm.longitude,
            "terrain": farm.terrain,
            "soil_type": farm.soil_type,
            "current_crop": farm.current_crop,
            "crop_stage": farm.crop_stage
        }

    # Override coordinates and location name if provided dynamically by user/GPS
    if latitude is not None and longitude is not None:
        farm_dict["latitude"] = latitude
        farm_dict["longitude"] = longitude
    if location_name:
        farm_dict["village"] = location_name
        farm_dict["district"] = location_name

    forecast = await WeatherService.get_forecast(
        farm_dict["latitude"], farm_dict["longitude"]
    )

    evaluation = risk_engine.evaluate_farm_risks(
        farm_profile=farm_dict,
        weather_forecast=forecast
    )

    enso = await fetch_enso_status()
    evaluation["enso_summary"] = enso

    return RiskForecastResponse(
        farm_id=evaluation["farm_id"],
        farm_name=evaluation["farm_name"],
        village=evaluation.get("village"),
        crop=evaluation.get("crop"),
        crop_stage=evaluation["crop_stage"],
        horizon_1_3d=evaluation["horizon_1_3d"],
        horizon_4_10d=evaluation["horizon_4_10d"],
        horizon_10_46d_seasonal=evaluation["horizon_10_46d_seasonal"],
        enso_summary=enso
    )


@router.post("/subscribe", response_model=AlertSubscriptionResponse)
async def subscribe_alerts(
    farm_id: int,
    payload: AlertSubscriptionCreate,
    user_id: int = Query(1, description="Authenticated User ID"),
    db: AsyncSession = Depends(get_db)
):
    """
    Creates or updates an alert subscription for a farm.
    """
    stmt = select(AlertSubscription).where(
        AlertSubscription.farm_id == farm_id,
        AlertSubscription.alert_type == payload.alert_type
    )
    res = await db.execute(stmt)
    sub = res.scalars().first()

    if sub:
        sub.channel_push = payload.channel_push
        sub.channel_sms = payload.channel_sms
        sub.channel_email = payload.channel_email
        sub.min_probability = payload.min_probability
        sub.quiet_hours_start = payload.quiet_hours_start
        sub.quiet_hours_end = payload.quiet_hours_end
    else:
        sub = AlertSubscription(
            farm_id=farm_id,
            user_id=user_id,
            alert_type=payload.alert_type,
            channel_push=payload.channel_push,
            channel_sms=payload.channel_sms,
            channel_email=payload.channel_email,
            min_probability=payload.min_probability,
            quiet_hours_start=payload.quiet_hours_start,
            quiet_hours_end=payload.quiet_hours_end,
            is_active=True
        )
        db.add(sub)

    await db.commit()
    await db.refresh(sub)
    return sub


@router.get("/subscriptions", response_model=List[AlertSubscriptionResponse])
async def get_subscriptions(farm_id: int, db: AsyncSession = Depends(get_db)):
    stmt = select(AlertSubscription).where(AlertSubscription.farm_id == farm_id)
    res = await db.execute(stmt)
    return res.scalars().all()


@router.get("/logs", response_model=List[AlertDeliveryLogResponse])
async def get_delivery_logs(farm_id: int, limit: int = 50, db: AsyncSession = Depends(get_db)):
    """
    Retrieves delivery audit logs for dispatched alerts.
    """
    stmt = select(AlertDeliveryLog).where(
        AlertDeliveryLog.farm_id == farm_id
    ).order_by(AlertDeliveryLog.created_at.desc()).limit(limit)
    res = await db.execute(stmt)
    return res.scalars().all()


@router.post("/simulate")
async def simulate_hazard_alert(
    farm_id: int,
    hazard_scenario: str = Query("frost", description="frost, heavy_rain, heat_wave, strong_wind"),
    db: AsyncSession = Depends(get_db)
):
    """
    Simulates a dangerous weather scenario (e.g. frost or heavy rain)
    and executes the full AlertDispatcher pipeline across Push, SMS, and Email.
    """
    stmt = select(Farm).where(Farm.id == farm_id)
    res = await db.execute(stmt)
    farm = res.scalars().first()

    if not farm:
        # Create default demo farm if not exists
        farm = Farm(
            id=farm_id,
            user_id=1,
            name="बड़ा खेत 1",
            village="उमरेड (Umred)",
            district="नागपुर (Nagpur)",
            state="Maharashtra",
            latitude=21.1458,
            longitude=79.0882,
            terrain="plain",
            soil_type="black",
            irrigation_type="tube-well",
            land_size_acres=4.5,
            current_crop="चना / सोयाबीन",
            crop_stage="flowering",
            sowing_date=datetime.strptime("2026-07-01", "%Y-%m-%d").date()
        )
        db.add(farm)
        await db.commit()
        await db.refresh(farm)

    scenarios = {
        "frost": {
            "alert_type": "cold_wave_frost",
            "title_hi": "पाला एवं शीतलहर चेतावनी (Ground Frost)",
            "title_en": "Ground Frost & Cold Wave Warning",
            "severity": "red",
            "probability": 85.0,
            "confidence": "High",
            "expected_value": "1.2°C ground minimum temperature",
            "expected_date": "कल सुबह (Tomorrow Early Morning)",
            "action_hi": "शाम के समय खेत की मेड़ों पर धुआं करें तथा पाले से बचाव हेतु शाम को हल्की सिंचाई करें।",
            "action_en": "Apply light evening irrigation and burn organic debris on boundaries to create protective smoke."
        },
        "heavy_rain": {
            "alert_type": "heavy_rain",
            "title_hi": "अत्यधिक भारी वर्षा चेतावनी (Red Alert)",
            "title_en": "Extremely Heavy Rainfall Warning",
            "severity": "red",
            "probability": 90.0,
            "confidence": "High",
            "expected_value": "145 mm / 24h",
            "expected_date": "अगले 24 घंटे",
            "action_hi": "खेत में तत्काल जल निकासी (Drainage) का प्रबंध करें। कीटनाशक व उर्वरक छिड़काव तुरंत रोकें।",
            "action_en": "Ensure immediate drainage channels. Postpone chemical sprays and fertilizers."
        },
        "heat_wave": {
            "alert_type": "heat_wave",
            "title_hi": "भीषण लू (Severe Heat Wave)",
            "title_en": "Severe Heat Wave Warning",
            "severity": "orange",
            "probability": 88.0,
            "confidence": "High",
            "expected_value": "44.5°C maximum temperature",
            "expected_date": "आगामी 48 घंटे",
            "action_hi": "शाम के समय हल्की सिंचाई करें। पुआल या सूखी घास से मल्चिंग (Mulching) करें।",
            "action_en": "Apply light evening irrigation and cover soil with organic mulch."
        }
    }

    selected_hazard = scenarios.get(hazard_scenario, scenarios["frost"])
    dispatcher = AlertDispatcher(db)

    sub_stmt = select(AlertSubscription).where(
        AlertSubscription.farm_id == farm_id,
        AlertSubscription.alert_type == selected_hazard["alert_type"]
    )
    sub_res = await db.execute(sub_stmt)
    sub = sub_res.scalars().first()

    logs = await dispatcher.dispatch_hazard_alert(
        farm=farm,
        hazard=selected_hazard,
        subscription=sub
    )

    return {
        "scenario": hazard_scenario,
        "dispatched_logs_count": len(logs),
        "hazard_details": selected_hazard,
        "logs": [
            {
                "id": l.id,
                "channel": l.channel,
                "status": l.status,
                "severity": l.severity,
                "message": l.message_content
            }
            for l in logs
        ]
    }


@router.post("/weekly-digest")
async def trigger_weekly_digest(farm_id: int, db: AsyncSession = Depends(get_db)):
    """
    Triggers the weekly digest containing the 2-week outlook and ENSO card.
    """
    stmt = select(Farm).where(Farm.id == farm_id)
    res = await db.execute(stmt)
    farm = res.scalars().first()
    if not farm:
        raise HTTPException(status_code=404, detail="Farm not found")

    dispatcher = AlertDispatcher(db)
    result = await dispatcher.dispatch_weekly_digest(farm)
    return result
