from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime

class OTPRequest(BaseModel):
    phone_number: str = Field(..., description="Indian 10-digit mobile number or with +91")

class OTPVerify(BaseModel):
    phone_number: str
    otp: str = Field(..., min_length=4, max_length=6)

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int
    phone_number: str
    is_new_user: bool

class UserConsentUpdate(BaseModel):
    consent_location: Optional[bool] = None
    consent_sms: Optional[bool] = None
    consent_email: Optional[bool] = None
    consent_notifications: Optional[bool] = None
    consent_ai_logging: Optional[bool] = None

class UserProfile(BaseModel):
    id: int
    phone_number: str
    name: Optional[str] = None
    email: Optional[str] = None
    preferred_language: str = "hi"
    consent_location: bool
    consent_sms: bool
    consent_email: bool
    consent_notifications: bool
    consent_ai_logging: bool
    created_at: datetime

    class Config:
        from_attributes = True

class FCMRegisterRequest(BaseModel):
    device_token: str
    device_type: str = "android"

class EmailAuthRequest(BaseModel):
    email: str = Field(..., description="User email address")
    password: str = Field(..., min_length=6, description="User password")
    name: Optional[str] = None

class GoogleAuthRequest(BaseModel):
    email: str = Field(..., description="Google account email")
    name: Optional[str] = None
    id_token: Optional[str] = None
