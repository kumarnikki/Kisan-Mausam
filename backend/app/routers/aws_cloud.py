from typing import Any, Dict, Optional
from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.aws_cloud_service import aws_cloud_service, SUPPORTED_INDIAN_LANGUAGES

router = APIRouter(prefix="/api/v1/aws", tags=["AWS Cloud Services"])


class PollySynthesisRequest(BaseModel):
    text: str = Field(..., description="Hindi or English agricultural advisory text to synthesize")
    language_code: str = Field(default="hi-IN", description="BCP-47 language code (hi-IN or en-IN)")
    voice_id: str = Field(default="Kajal", description="Amazon Polly Neural Voice ID (Kajal or Aditi)")


class TranslateAdvisoryRequest(BaseModel):
    text: str = Field(..., description="Source agricultural advisory text")
    source_lang: str = Field(default="hi", description="Source language code (e.g., hi)")
    target_lang: str = Field(default="mr", description="Target Indian language code (en, mr, pa, gu, ta, te, kn, bn)")


class TelemetryArchiveRequest(BaseModel):
    farm_id: int = Field(default=1, description="Farm identifier")
    lat: float = Field(default=20.85, description="Farm latitude")
    lon: float = Field(default=79.32, description="Farm longitude")
    telemetry_type: str = Field(default="weather_soil_snapshot", description="Telemetry category")
    payload: Dict[str, Any] = Field(default_factory=dict, description="Weather and soil telemetry payload")


class SNSBroadcastRequest(BaseModel):
    subject: str = Field(default="KisanMausam IMD Red Alert", description="SNS Notification Subject")
    phone_number: Optional[str] = Field(default=None, description="Optional 10-digit Indian phone for direct SNS SMS")
    hazard_payload: Dict[str, Any] = Field(default_factory=dict, description="Structured hazard alert payload")


@router.get("/status")
async def get_aws_cloud_status():
    """
    Returns the complete Amazon Web Services (AWS) architecture status,
    active region (ap-south-1 Mumbai), and health of all integrated AWS services.
    """
    return aws_cloud_service.get_aws_architecture_status()


@router.post("/polly/synthesize")
async def synthesize_speech_with_polly(req: PollySynthesisRequest):
    """
    Synthesizes natural Hindi/Indian-English voice audio using Amazon Polly Neural TTS (Voice: Kajal).
    """
    return await aws_cloud_service.synthesize_speech(
        text=req.text,
        language_code=req.language_code,
        voice_id=req.voice_id,
    )


@router.post("/translate")
async def translate_regional_advisory(req: TranslateAdvisoryRequest):
    """
    Translates weather warnings and crop advisories across 9 Indian languages using Amazon Translate.
    """
    res = await aws_cloud_service.translate_advisory(
        text=req.text,
        source_lang=req.source_lang,
        target_lang=req.target_lang,
    )
    res["available_languages"] = SUPPORTED_INDIAN_LANGUAGES
    return res


@router.post("/telemetry/archive")
async def archive_farm_telemetry(req: TelemetryArchiveRequest):
    """
    Archives farm weather and soil telemetry to Amazon S3 (AES-256) and caches
    hyper-local GPS cell data in Amazon DynamoDB.
    """
    s3_res = await aws_cloud_service.archive_weather_telemetry(
        farm_id=req.farm_id,
        telemetry_type=req.telemetry_type,
        payload=req.payload,
    )
    ddb_res = await aws_cloud_service.cache_hyperlocal_weather(
        lat=req.lat,
        lon=req.lon,
        weather_summary=req.payload,
    )
    return {
        "s3_archive": s3_res,
        "dynamodb_cache": ddb_res,
    }


@router.post("/sns/broadcast")
async def broadcast_hazard_via_sns(req: SNSBroadcastRequest):
    """
    Publishes emergency weather/SOS alerts to the Amazon SNS Hazard Topic
    and optionally dispatches direct Transactional SMS via AWS SNS.
    """
    topic_res = await aws_cloud_service.broadcast_hazard_topic(
        subject=req.subject,
        hazard_payload=req.hazard_payload,
    )
    sms_res = None
    if req.phone_number:
        msg = req.hazard_payload.get("message") or f"{req.subject}: कृपया तत्काल सुरक्षा उपाय करें।"
        sms_res = await aws_cloud_service.publish_hazard_sms(
            phone_number=req.phone_number,
            message=msg,
        )
    return {
        "sns_topic_broadcast": topic_res,
        "sns_transactional_sms": sms_res,
    }
