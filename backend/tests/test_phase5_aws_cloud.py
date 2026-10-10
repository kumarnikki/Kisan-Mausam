import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app


@pytest.mark.asyncio
async def test_aws_architecture_status():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        res = await ac.get("/api/v1/aws/status")
    assert res.status_code == 200
    data = res.json()
    assert data["cloud_provider"] == "Amazon Web Services (AWS)"
    assert data["primary_region"] == "ap-south-1"
    assert "bedrock" in data["services"]["ai_and_ml"]
    assert "polly" in data["services"]["ai_and_ml"]
    assert "translate" in data["services"]["ai_and_ml"]
    assert "s3" in data["services"]["storage_and_database"]
    assert "dynamodb" in data["services"]["storage_and_database"]
    assert "sns" in data["services"]["messaging_and_observability"]


@pytest.mark.asyncio
async def test_aws_polly_translate_and_telemetry():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        # 1. Amazon Polly Neural TTS
        polly_res = await ac.post(
            "/api/v1/aws/polly/synthesize",
            json={
                "text": "किसान भाइयों, आज शाम हल्की सिंचाई करें।",
                "language_code": "hi-IN",
                "voice_id": "Kajal",
            },
        )
        assert polly_res.status_code == 200
        assert polly_res.json()["voice_id"] == "Kajal"

        # 2. Amazon Translate
        tr_res = await ac.post(
            "/api/v1/aws/translate",
            json={
                "text": "कल भारी वर्षा की संभावना है, जल निकासी नालियां खोलें।",
                "source_lang": "hi",
                "target_lang": "mr",
            },
        )
        assert tr_res.status_code == 200
        assert tr_res.json()["target_language"] == "mr"
        assert "translated_text" in tr_res.json()

        # 3. Amazon S3 + DynamoDB Telemetry Archive
        arch_res = await ac.post(
            "/api/v1/aws/telemetry/archive",
            json={
                "farm_id": 1,
                "lat": 20.85,
                "lon": 79.32,
                "telemetry_type": "soil_moisture_check",
                "payload": {"soil_moisture_0_1cm": 0.31, "temperature_2m": 28.5},
            },
        )
        assert arch_res.status_code == 200
        assert arch_res.json()["s3_archive"]["encryption"] == "AES256"
        assert arch_res.json()["dynamodb_cache"]["status"] == "cached"

        # 4. Amazon SNS Hazard Broadcast
        sns_res = await ac.post(
            "/api/v1/aws/sns/broadcast",
            json={
                "subject": "KisanMausam IMD Heavy Rain Alert",
                "phone_number": "9876543210",
                "hazard_payload": {"alert_type": "heavy_rain", "severity": "red"},
            },
        )
        assert sns_res.status_code == 200
        assert sns_res.json()["sns_topic_broadcast"]["status"] == "published"
        assert sns_res.json()["sns_transactional_sms"]["status"] == "success"
