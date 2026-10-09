import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.database import engine, Base

@pytest_asyncio.fixture(autouse=True)
async def setup_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

@pytest.mark.asyncio
async def test_health_check():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["app_name"] == "KisanMausam Backend"
    assert data["dpdp_compliant"] is True

@pytest.mark.asyncio
async def test_auth_and_farm_flow():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Send OTP
        phone = "9876543210"
        otp_res = await ac.post("/auth/otp/send", json={"phone_number": phone})
        assert otp_res.status_code == 200
        assert otp_res.json()["status"] == "success"

        # 2. Verify OTP (mock accepts 123456)
        verify_res = await ac.post("/auth/otp/verify", json={"phone_number": phone, "otp": "123456"})
        assert verify_res.status_code == 200
        token_data = verify_res.json()
        assert "access_token" in token_data
        token = token_data["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # 3. Get profile
        me_res = await ac.get("/auth/me", headers=headers)
        assert me_res.status_code == 200
        assert me_res.json()["phone_number"] == phone

        # 4. Create Farm
        farm_payload = {
            "name": "रामेश्वर खेत 1",
            "latitude": 21.1458,
            "longitude": 79.0882,
            "village": "उमरेड (Umred)",
            "district": "नागपुर (Nagpur)",
            "state": "महाराष्ट्र (Maharashtra)",
            "terrain": "plain",
            "soil_type": "black",
            "irrigation_type": "tube-well",
            "land_size_acres": 4.5,
            "current_crop": "सोयाबीन (Soybean)",
            "crop_stage": "flowering"
        }
        create_farm_res = await ac.post("/farms", json=farm_payload, headers=headers)
        assert create_farm_res.status_code == 200
        farm = create_farm_res.json()
        assert farm["name"] == "रामेश्वर खेत 1"
        assert farm["soil_type"] == "black"

        # 5. List Farms
        list_res = await ac.get("/farms", headers=headers)
        assert list_res.status_code == 200
        farms = list_res.json()
        assert len(farms) == 1
        assert farms[0]["id"] == farm["id"]

@pytest.mark.asyncio
async def test_weather_forecast_live():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # Nagpur coordinates
        res = await ac.get("/weather/forecast?latitude=21.1458&longitude=79.0882")
        assert res.status_code == 200
        data = res.json()
        assert "current" in data
        assert "temperature_2m" in data["current"]
        assert "soil_temperature_0cm" in data["current"]
        assert "soil_moisture_0_1cm" in data["current"]
        assert len(data["hourly"]) > 0
        assert len(data["daily"]) > 0
        assert "Open-Meteo" in data["attribution"]
