import random
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict
from jose import JWTError, jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.config import settings
from app.database import get_db
from app.models.user import User

logger = logging.getLogger(__name__)

security = HTTPBearer()

# In-memory store for OTPs in development: {phone_number: {"otp": code, "expires_at": timestamp}}
_OTP_STORE: Dict[str, Dict] = {}

class AuthService:
    @staticmethod
    def generate_otp(phone_number: str) -> str:
        # For mock / dev convenience, 123456 is always accepted, but we generate random 6 digits
        otp = str(random.randint(100000, 999999))
        _OTP_STORE[phone_number] = {
            "otp": otp,
            "expires_at": datetime.now(timezone.utc) + timedelta(minutes=10)
        }
        return otp

    @staticmethod
    def verify_otp(phone_number: str, entered_otp: str) -> bool:
        # In mock mode, allow "123456" or any matching stored OTP
        if settings.SMS_PROVIDER == "mock" and entered_otp == "123456":
            return True

        if phone_number not in _OTP_STORE:
            return False

        stored = _OTP_STORE[phone_number]
        if datetime.now(timezone.utc) > stored["expires_at"]:
            del _OTP_STORE[phone_number]
            return False

        if stored["otp"] == entered_otp:
            del _OTP_STORE[phone_number]
            return True
        return False

    @staticmethod
    def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
        to_encode = data.copy()
        if expires_delta:
            expire = datetime.now(timezone.utc) + expires_delta
        else:
            expire = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        to_encode.update({"exp": expire})
        encoded_jwt = jwt.encode(to_encode, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
        return encoded_jwt

    @staticmethod
    async def get_or_create_user(db: AsyncSession, phone_number: str) -> tuple[User, bool]:
        clean_phone = phone_number.strip()
        result = await db.execute(select(User).where(User.phone_number == clean_phone))
        user = result.scalars().first()
        is_new = False
        if not user:
            user = User(phone_number=clean_phone)
            db.add(user)
            await db.commit()
            await db.refresh(user)
            is_new = True
        return user, is_new

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db)
) -> User:
    token = credentials.credentials
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    result = await db.execute(select(User).where(User.id == int(user_id)))
    user = result.scalars().first()
    if user is None:
        raise credentials_exception
    return user
