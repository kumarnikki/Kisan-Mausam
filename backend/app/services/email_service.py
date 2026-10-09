import logging
import httpx
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional
from app.config import settings

logger = logging.getLogger(__name__)

class BaseEmailProvider(ABC):
    @abstractmethod
    async def send_email(self, to_email: str, subject: str, html_content: str) -> Dict[str, Any]:
        pass

class MockEmailProvider(BaseEmailProvider):
    async def send_email(self, to_email: str, subject: str, html_content: str) -> Dict[str, Any]:
        logger.info(f"📧 [MOCK EMAIL DISPATCH] To: {to_email} | Subject: {subject}")
        return {"status": "success", "provider": "mock", "id": f"mock_email_{to_email}"}

class ResendEmailProvider(BaseEmailProvider):
    def __init__(self):
        self.api_key = settings.RESEND_API_KEY
        self.from_email = settings.EMAIL_FROM

    async def send_email(self, to_email: str, subject: str, html_content: str) -> Dict[str, Any]:
        if not self.api_key:
            return await MockEmailProvider().send_email(to_email, subject, html_content)

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "from": self.from_email,
            "to": [to_email],
            "subject": subject,
            "html": html_content
        }
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.post("https://api.resend.com/emails", json=payload, headers=headers)
            resp.raise_for_status()
            return resp.json()

def get_email_provider() -> BaseEmailProvider:
    if settings.EMAIL_PROVIDER.lower() == "resend":
        return ResendEmailProvider()
    return MockEmailProvider()
