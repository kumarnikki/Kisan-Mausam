import pytest
from datetime import datetime, date
from app.services.risk_engine import RiskEngine
from app.services.enso_service import fetch_enso_status
from app.services.alert_dispatcher import AlertDispatcher
from app.models.farm import Farm
from app.models.user import User
from app.models.alert import AlertDeliveryLog

@pytest.fixture
def risk_engine():
    return RiskEngine()

@pytest.fixture
def sample_farm_plain():
    return {
        "id": 1,
        "name": "बड़ा खेत 1",
        "village": "उमरेड (Umred)",
        "district": "नागपुर (Nagpur)",
        "terrain": "plain",
        "soil_type": "black",
        "current_crop": "सोयाबीन (Soybean)",
        "crop_stage": "flowering"
    }

@pytest.fixture
def sample_farm_hilly():
    return {
        "id": 2,
        "name": "पहाड़ी खेत",
        "village": "शिमला देहात",
        "district": "शिमला",
        "terrain": "hilly",
        "soil_type": "loamy",
        "current_crop": "सेब (Apple)",
        "crop_stage": "flowering"
    }

def test_risk_engine_heavy_rain_detection(risk_engine, sample_farm_plain):
    # Simulated weather forecast with heavy rain 120mm on day 2
    mock_weather = {
        "daily": [
            {"time": "2026-10-08", "precipitation_sum": 5.0, "precipitation_probability_max": 20},
            {"time": "2026-10-09", "precipitation_sum": 125.0, "precipitation_probability_max": 85},  # Very Heavy Rain
            {"time": "2026-10-10", "precipitation_sum": 10.0, "precipitation_probability_max": 30},
        ],
        "hourly": []
    }

    result = risk_engine.evaluate_farm_risks(sample_farm_plain, mock_weather)
    h1 = result["horizon_1_3d"]
    assert h1["confidence"] == "High"
    assert len(h1["risks_detected"]) >= 1

    rain_risk = next((r for r in h1["risks_detected"] if r["alert_type"] == "heavy_rain"), None)
    assert rain_risk is not None
    assert rain_risk["severity"] == "orange"  # 115.6 - 204.4 mm
    assert rain_risk["probability"] == 85.0
    assert rain_risk["crop_stage_impact_weight"] == 2.2  # flowering weight from IMD/ICAR config
    assert "जल निकासी" in rain_risk["action_hi"]

def test_risk_engine_heat_wave_terrain_sensitivity(risk_engine, sample_farm_plain, sample_farm_hilly):
    # Plains: 38C should NOT trigger (threshold 40C)
    mock_plains_weather = {
        "daily": [
            {"time": "2026-10-08", "temperature_2m_max": 38.5, "precipitation_sum": 0.0},
        ],
        "hourly": []
    }
    res_plain = risk_engine.evaluate_farm_risks(sample_farm_plain, mock_plains_weather)
    assert not any(r["alert_type"] == "heat_wave" for r in res_plain["horizon_1_3d"]["risks_detected"])

    # Hills: 32C SHOULD trigger heat wave (hills threshold 30C)
    mock_hilly_weather = {
        "daily": [
            {"time": "2026-10-08", "temperature_2m_max": 32.5, "precipitation_sum": 0.0},
        ],
        "hourly": []
    }
    res_hilly = risk_engine.evaluate_farm_risks(sample_farm_hilly, mock_hilly_weather)
    hw_risk = next((r for r in res_hilly["horizon_1_3d"]["risks_detected"] if r["alert_type"] == "heat_wave"), None)
    assert hw_risk is not None
    assert hw_risk["severity"] == "yellow"
    assert "30.0°C for hilly" in hw_risk["expected_value"]

def test_risk_engine_frost_criteria(risk_engine, sample_farm_plain):
    # Minimum temperature 1.5C triggers ground frost warning (severity orange)
    mock_frost_weather = {
        "daily": [
            {"time": "2026-10-08", "temperature_2m_min": 1.5, "precipitation_sum": 0.0},
        ],
        "hourly": []
    }
    res = risk_engine.evaluate_farm_risks(sample_farm_plain, mock_frost_weather)
    frost_risk = next((r for r in res["horizon_1_3d"]["risks_detected"] if r["alert_type"] == "cold_wave_frost"), None)
    assert frost_risk is not None
    assert frost_risk["severity"] == "orange"
    assert "पाला" in frost_risk["title_hi"]

def test_risk_engine_accuracy_rules(risk_engine, sample_farm_plain):
    """
    CRITICAL REQUIREMENT:
    - NEVER state or imply 'El Nino is coming to your area'.
    - Phrase local risk as 'X% chance of below-normal rainfall over the next 30 days at your farm'.
    - Source and update date must be explicit.
    """
    mock_weather = {"daily": [], "hourly": []}
    res = risk_engine.evaluate_farm_risks(sample_farm_plain, mock_weather)
    h3 = res["horizon_10_46d_seasonal"]
    assert h3["confidence"] == "Low-Medium"
    
    seasonal_precip = next(r for r in h3["risks_detected"] if r["alert_type"] == "seasonal_precipitation_outlook")
    statement_hi = seasonal_precip["accuracy_compliant_statement_hi"]
    statement_en = seasonal_precip["accuracy_compliant_statement_en"]

    assert "एल नीनो आपके क्षेत्र में आ रहा है" not in statement_hi
    assert "El Nino is coming" not in statement_en
    assert "सामान्य से कम वर्षा होने की संभावना" in statement_hi
    assert "chance of below-normal rainfall over the next 30 days" in statement_en
    assert "Open-Meteo Seasonal Forecast API" in seasonal_precip["source"]

@pytest.mark.asyncio
async def test_enso_service():
    enso = await fetch_enso_status()
    assert enso["phase"] in ["Neutral", "El Nino", "La Nina"]
    assert "probabilities" in enso
    assert "season_1" in enso["probabilities"]
    assert "monsoon_impact_explanation_hi" in enso
    assert "accuracy_rule_notice" in enso
    assert "Never state or imply" in enso["accuracy_rule_notice"]

@pytest.mark.asyncio
async def test_alert_dispatcher_deduplication_and_rate_limit(async_session):
    # Setup test farm and user
    user = User(
        id=999,
        phone_number="+919876543210",
        email="farmer999@test.com",
        consent_location=True,
        consent_sms=True,
        consent_notifications=True
    )
    farm = Farm(
        id=999,
        user_id=999,
        name="टेस्ट फार्म",
        village="रामपुर",
        district="नागपुर",
        state="Maharashtra",
        latitude=21.0,
        longitude=79.0,
        terrain="plain",
        soil_type="black",
        irrigation_type="canal",
        land_size_acres=5.0,
        current_crop="गेहूं",
        crop_stage="vegetative",
        sowing_date=date(2026, 7, 1)
    )
    async_session.add(user)
    async_session.add(farm)
    await async_session.commit()

    dispatcher = AlertDispatcher(async_session)

    # 1. First alert should be permitted
    allowed = await dispatcher.check_deduplication(farm_id=999, alert_type="heat_wave", current_severity="yellow", dedupe_window_hours=6)
    assert allowed is True

    # Simulate dispatch by recording a log
    log = AlertDeliveryLog(
        farm_id=999,
        user_id=999,
        alert_type="heat_wave",
        channel="push",
        severity="yellow",
        probability=75.0,
        confidence="High",
        message_content="Test yellow heat wave",
        recipient="token_test",
        status="delivered",
        created_at=datetime.utcnow()
    )
    async_session.add(log)
    await async_session.commit()

    # 2. Duplicate alert with same severity should be SUPPRESSED
    allowed_dupe = await dispatcher.check_deduplication(farm_id=999, alert_type="heat_wave", current_severity="yellow", dedupe_window_hours=6)
    assert allowed_dupe is False

    # 3. Escalated severity (yellow -> red) should be ALLOWED
    allowed_escalated = await dispatcher.check_deduplication(farm_id=999, alert_type="heat_wave", current_severity="red", dedupe_window_hours=6)
    assert allowed_escalated is True
