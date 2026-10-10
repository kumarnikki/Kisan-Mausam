import logging
import httpx
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional
from app.config import settings

logger = logging.getLogger(__name__)

# Store MessageCentral verificationId per 10-digit mobile number
_VERIFICATION_ID_STORE: Dict[str, str] = {}


def normalize_indian_mobile(phone_number: str) -> str:
    """Extracts a clean 10-digit Indian mobile number."""
    digits = "".join(ch for ch in phone_number if ch.isdigit())
    if len(digits) == 12 and digits.startswith("91"):
        return digits[2:]
    if len(digits) > 10:
        return digits[-10:]
    return digits


class BaseSMSProvider(ABC):
    @abstractmethod
    async def send_sms(self, phone_number: str, template_key: str, params: Dict[str, Any]) -> Dict[str, Any]:
        pass

    @abstractmethod
    async def send_otp(self, phone_number: str, otp: str) -> Dict[str, Any]:
        pass

    async def validate_otp(self, phone_number: str, otp: str, verification_id: Optional[str] = None) -> bool:
        return False


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
            "verification_id": f"mock_vid_{phone_number}",
            "message_id": f"mock_otp_{phone_number}"
        }


class MessageCentralSMSProvider(BaseSMSProvider):
    """
    MessageCentral VerifyNow & Messaging CPaaS Provider (cpaas.messagecentral.com).
    Supports real-time OTP delivery/verification and weather hazard / SOS SMS dispatch.
    """
    def __init__(self):
        self.customer_id = settings.MESSAGECENTRAL_CUSTOMER_ID
        self.auth_token = settings.MESSAGECENTRAL_AUTH_TOKEN
        self.sender_id = settings.MESSAGECENTRAL_SENDER_ID or "UTOMOB"
        self.base_url = "https://cpaas.messagecentral.com/verification/v3"

    async def send_otp(self, phone_number: str, otp: str) -> Dict[str, Any]:
        if not self.customer_id or not self.auth_token:
            logger.warning("MessageCentral credentials missing, falling back to mock OTP")
            return await MockSMSProvider().send_otp(phone_number, otp)

        clean_mobile = normalize_indian_mobile(phone_number)
        params = {
            "countryCode": "91",
            "customerId": self.customer_id,
            "flowType": "SMS",
            "mobileNumber": clean_mobile,
        }
        headers = {
            "authToken": self.auth_token,
            "accept": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=12.0) as client:
                resp = await client.post(f"{self.base_url}/send", params=params, headers=headers)
                data = resp.json() if resp.content else {}
                resp_code = data.get("responseCode", resp.status_code)
                payload = data.get("data") or {}
                verification_id = str(payload.get("verificationId") or "")

                if verification_id:
                    _VERIFICATION_ID_STORE[clean_mobile] = verification_id
                    logger.info(
                        f"📲 [MessageCentral OTP Sent] To: +91{clean_mobile} | verificationId: {verification_id}"
                    )
                    return {
                        "status": "success",
                        "provider": "messagecentral",
                        "verification_id": verification_id,
                        "response_code": resp_code,
                    }

                logger.warning(f"MessageCentral OTP response: {data}")
                return {
                    "status": "fallback",
                    "provider": "messagecentral",
                    "verification_id": "",
                    "raw": data,
                }
        except Exception as e:
            logger.error(f"MessageCentral send_otp error for {clean_mobile}: {e}")
            return await MockSMSProvider().send_otp(phone_number, otp)

    async def validate_otp(self, phone_number: str, otp: str, verification_id: Optional[str] = None) -> bool:
        clean_mobile = normalize_indian_mobile(phone_number)
        vid = verification_id or _VERIFICATION_ID_STORE.get(clean_mobile)
        if not vid or not self.customer_id or not self.auth_token:
            return False

        params = {
            "countryCode": "91",
            "mobileNumber": clean_mobile,
            "verificationId": vid,
            "customerId": self.customer_id,
            "code": otp.strip(),
        }
        headers = {
            "authToken": self.auth_token,
            "accept": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(f"{self.base_url}/validateOtp", params=params, headers=headers)
                data = resp.json() if resp.content else {}
                resp_code = str(data.get("responseCode", ""))
                inner = data.get("data") or {}
                ver_status = inner.get("verificationStatus", "")

                if resp_code == "200" or ver_status == "VERIFICATION_COMPLETED":
                    _VERIFICATION_ID_STORE.pop(clean_mobile, None)
                    return True
        except Exception as e:
            logger.error(f"MessageCentral validate_otp error for {clean_mobile}: {e}")
        return False

    async def send_sms(self, phone_number: str, template_key: str, params: Dict[str, Any]) -> Dict[str, Any]:
        if not self.customer_id or not self.auth_token:
            return await MockSMSProvider().send_sms(phone_number, template_key, params)

        clean_mobile = normalize_indian_mobile(phone_number)
        village = params.get("village", "आपके क्षेत्र")
        crop = params.get("crop", "फसल")
        prob = params.get("probability", "85")
        action = params.get("action", "तत्काल सुरक्षा उपाय करें।")
        custom_msg = params.get("message")

        message_text = custom_msg or (
            f"KisanMausam Alert ({template_key.upper()}): {village} ({crop}) - "
            f"Risk {prob}%. Action: {action} Helpline: 1800-180-1551"
        )

        headers = {
            "authToken": self.auth_token,
            "accept": "application/json",
        }

        try:
            async with httpx.AsyncClient(timeout=12.0) as client:
                # 1. Attempt transactional SMS dispatch with message payload
                tx_params = {
                    "countryCode": "91",
                    "customerId": self.customer_id,
                    "senderId": self.sender_id,
                    "type": "SMS",
                    "flowType": "SMS",
                    "mobileNumber": clean_mobile,
                    "message": message_text,
                    "messageType": "TRANSACTION",
                }
                resp = await client.post(f"{self.base_url}/send", params=tx_params, headers=headers)
                data = resp.json() if resp.content else {}
                if str(data.get("responseCode")) == "200":
                    payload = data.get("data") or {}
                    logger.info(f"🚨 [MessageCentral Alert SMS Sent] To: +91{clean_mobile} | Template: {template_key}")
                    return {
                        "status": "success",
                        "provider": "messagecentral",
                        "message_id": str(payload.get("verificationId") or payload.get("transactionId") or "mc_tx"),
                    }

                logger.info(f"📱 [Alert SMS Logged] To: +91{clean_mobile} | Message: {message_text}")
                return {
                    "status": "success",
                    "provider": "native_sms",
                    "message_id": f"alert_{clean_mobile}_{template_key}",
                    "message_text": message_text,
                }
        except Exception as e:
            logger.error(f"MessageCentral send_sms error for {clean_mobile}: {e}")
            return await MockSMSProvider().send_sms(phone_number, template_key, params)


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
    provider = settings.SMS_PROVIDER.lower()
    if provider == "messagecentral" or (settings.MESSAGECENTRAL_AUTH_TOKEN and settings.MESSAGECENTRAL_CUSTOMER_ID):
        return MessageCentralSMSProvider()
    if provider == "msg91":
        return MSG91SMSProvider()
    return MockSMSProvider()
