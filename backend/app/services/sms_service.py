import json
import logging
import httpx
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional
from pathlib import Path
from app.config import settings

logger = logging.getLogger(__name__)

class BaseSMSProvider(ABC):
    @abstractmethod
    async def send_sms(self, phone_number: str, template_key: str, params: Dict[str, Any]) -> Dict[str, Any]:
        pass

    @abstractmethod
    async def send_otp(self, phone_number: str, otp: str) -> Dict[str, Any]:
        pass

class MockSMSProvider(BaseSMSProvider):
    async def send_sms(self, phone_number: str, template_key: str, params: Dict[str, Any]) -> Dict[str, Any]:
        logger.info(f"📱 [MOCK SMS DISPATCH] To: {phone_number} | Template: {template_key} | Params: {params}")
        return {
            "status": "success",
            "provider": "mock",
            "message_id": f"mock_sms_{phone_number}_{template_key}"
        }

    async def send_otp(self, phone_number: str, otp: str) -> Dict[str, Any]:
        logger.info(f"🔑 [MOCK OTP DISPATCH] To: {phone_number} | OTP: {otp}")
        return {
            "status": "success",
            "provider": "mock",
            "message_id": f"mock_otp_{phone_number}"
        }

class MSG91SMSProvider(BaseSMSProvider):
    def __init__(self):
        self.auth_key = settings.MSG91_AUTH_KEY
        self.sender = settings.MSG91_SENDER_ID
        self.base_url = "https://control.msg91.com/api/v5"

    async def send_sms(self, phone_number: str, template_key: str, params: Dict[str, Any]) -> Dict[str, Any]:
        if not self.auth_key:
            logger.warning("MSG91 Auth Key missing, falling back to mock send")
            return await MockSMSProvider().send_sms(phone_number, template_key, params)

        clean_number = phone_number.replace("+", "").strip()
        flow_id = getattr(settings, f"MSG91_FLOW_ID_{template_key.upper()}", None) or template_key

        payload = {
            "template_id": flow_id,
            "sender": self.sender,
            "recipients": [
                {
                    "mobiles": clean_number,
                    **params
                }
            ]
        }
        headers = {
            "authkey": self.auth_key,
            "content-type": "application/json"
        }

        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(f"{self.base_url}/flow/", json=payload, headers=headers)
            resp.raise_for_status()
            return resp.json()

    async def send_otp(self, phone_number: str, otp: str) -> Dict[str, Any]:
        if not self.auth_key:
            return await MockSMSProvider().send_otp(phone_number, otp)

        clean_number = phone_number.replace("+", "").strip()
        params = {"mobile": clean_number, "otp": otp}
        headers = {"authkey": self.auth_key}

        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post(f"{self.base_url}/otp", params=params, headers=headers)
            resp.raise_for_status()
            return resp.json()

def get_sms_provider() -> BaseSMSProvider:
    if settings.SMS_PROVIDER.lower() == "msg91":
        return MSG91SMSProvider()
    return MockSMSProvider()
