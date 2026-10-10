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

class AWSSESProvider(BaseEmailProvider):
    """
    Amazon Simple Email Service (AWS SES) Transactional Email Provider (ap-south-1).
    """
    async def send_email(self, to_email: str, subject: str, html_content: str) -> Dict[str, Any]:
        from app.services.aws_cloud_service import aws_cloud_service

        return await aws_cloud_service.send_transactional_email(
            to_email=to_email,
            subject=subject,
            html_content=html_content,
        )


def get_email_provider() -> BaseEmailProvider:
    provider = settings.EMAIL_PROVIDER.lower()
    if provider == "aws_ses":
        return AWSSESProvider()
    if provider == "resend":
        return ResendEmailProvider()
    return MockEmailProvider()
