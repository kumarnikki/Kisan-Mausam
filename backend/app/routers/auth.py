from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
from app.database import get_db
from app.models.user import User, FCMDevice
from app.models.farm import Farm
from app.models.alert import AlertSubscription, AlertDeliveryLog
from app.schemas.user import (
    OTPRequest,
    OTPVerify,
    TokenResponse,
    UserProfile,
    UserConsentUpdate,
    FCMRegisterRequest,
    EmailAuthRequest,
    GoogleAuthRequest,
)
from app.services.auth_service import AuthService, get_current_user
from app.services.sms_service import get_sms_provider

router = APIRouter(prefix="/auth", tags=["Authentication & Profile"])

@router.post("/otp/send")
async def send_otp(req: OTPRequest):
    phone = req.phone_number.strip()
    otp = AuthService.generate_otp(phone)
    sms_provider = get_sms_provider()
    verification_id = await sms_provider.send_otp(phone, otp)
    return {
        "status": "success",
        "message": "OTP sent successfully via MessageCentral SMS",
        "phone_number": phone,
        "verification_id": verification_id if isinstance(verification_id, str) else None,
        "dev_hint": f"OTP sent via MessageCentral (fallback test OTP: {otp} or 123456)"
    }

@router.post("/otp/verify", response_model=TokenResponse)
async def verify_otp(req: OTPVerify, db: AsyncSession = Depends(get_db)):
    phone = req.phone_number.strip()
    sms_provider = get_sms_provider()
    verified_via_gateway = await sms_provider.validate_otp(phone, req.otp)
    if not verified_via_gateway and not AuthService.verify_otp(phone, req.otp):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP"
        )
    user, is_new = await AuthService.get_or_create_user(db, phone)
    token = AuthService.create_access_token({"sub": str(user.id), "phone": user.phone_number})
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        user_id=user.id,
        phone_number=user.phone_number,
        is_new_user=is_new
    )

@router.post("/email", response_model=TokenResponse)
async def auth_with_email(req: EmailAuthRequest, db: AsyncSession = Depends(get_db)):
    email = req.email.strip().lower()
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalars().first()
    is_new = False
    if not user:
        # Generate placeholder phone for email user if needed
        import hashlib
        suffix = hashlib.md5(email.encode()).hexdigest()[:8]
        phone = f"99{int(suffix, 16) % 100000000:08d}"
        user = User(
            phone_number=phone,
            email=email,
            name=req.name or email.split("@")[0],
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
        is_new = True

    token = AuthService.create_access_token({"sub": str(user.id), "email": user.email})
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        user_id=user.id,
        phone_number=user.phone_number,
        is_new_user=is_new
    )

@router.post("/google", response_model=TokenResponse)
async def auth_with_google(req: GoogleAuthRequest, db: AsyncSession = Depends(get_db)):
    email = req.email.strip().lower()
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalars().first()
    is_new = False
    if not user:
        import hashlib
        suffix = hashlib.md5(email.encode()).hexdigest()[:8]
        phone = f"88{int(suffix, 16) % 100000000:08d}"
        user = User(
            phone_number=phone,
            email=email,
            name=req.name or email.split("@")[0],
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
        is_new = True

    token = AuthService.create_access_token({"sub": str(user.id), "email": user.email})
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        user_id=user.id,
        phone_number=user.phone_number,
        is_new_user=is_new
    )

@router.get("/me", response_model=UserProfile)
async def get_my_profile(current_user: User = Depends(get_current_user)):
    return current_user

@router.put("/consent", response_model=UserProfile)
async def update_consents(
    consents: UserConsentUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    update_data = consents.model_dump(exclude_unset=True)
    for field, val in update_data.items():
        setattr(current_user, field, val)
    await db.commit()
    await db.refresh(current_user)
    return current_user

@router.post("/fcm/register")
async def register_fcm_token(
    req: FCMRegisterRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    result = await db.execute(select(FCMDevice).where(FCMDevice.device_token == req.device_token))
    existing = result.scalars().first()
    if existing:
        existing.user_id = current_user.id
        existing.is_active = True
    else:
        new_device = FCMDevice(
            user_id=current_user.id,
            device_token=req.device_token,
            device_type=req.device_type
        )
        db.add(new_device)
    await db.commit()
    return {"status": "success", "message": "FCM token registered"}

@router.delete("/me")
async def delete_my_data(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    # DPDP Act 2023 - Right to Erasure
    await db.execute(delete(AlertDeliveryLog).where(AlertDeliveryLog.user_id == current_user.id))
    await db.execute(delete(AlertSubscription).where(AlertSubscription.user_id == current_user.id))
    await db.execute(delete(Farm).where(Farm.user_id == current_user.id))
    await db.execute(delete(FCMDevice).where(FCMDevice.user_id == current_user.id))
    await db.delete(current_user)
    await db.commit()
    return {"status": "success", "message": "All personal data deleted successfully in compliance with DPDP Act 2023."}
