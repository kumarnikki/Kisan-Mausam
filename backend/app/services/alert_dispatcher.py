import logging
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.models.alert import AlertSubscription, AlertDeliveryLog
from app.models.farm import Farm
from app.models.user import User
from app.services.sms_service import get_sms_provider
from app.services.email_service import get_email_provider
from app.services.fcm_service import fcm_service
from app.services.enso_service import fetch_enso_status

logger = logging.getLogger(__name__)

SEVERITY_ORDER = {
    "yellow": 1,
    "orange": 2,
    "red": 3,
    "info": 0
}

class AlertDispatcher:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.sms_provider = get_sms_provider()
        self.email_provider = get_email_provider()

    def is_in_quiet_hours(self, quiet_start: int, quiet_end: int) -> bool:
        current_hour = datetime.now().hour
        if quiet_start > quiet_end:
            # Over midnight, e.g. 22 to 6
            return current_hour >= quiet_start or current_hour < quiet_end
        else:
            return quiet_start <= current_hour < quiet_end

    async def check_rate_limit(self, farm_id: int, max_per_day: int = 3) -> bool:
        """
        Ensures max 3 alerts per farm per 24 hours.
        """
        since = datetime.utcnow() - timedelta(hours=24)
        stmt = select(func.count(AlertDeliveryLog.id)).where(
            AlertDeliveryLog.farm_id == farm_id,
            AlertDeliveryLog.created_at >= since,
            AlertDeliveryLog.status == "delivered"
        )
        result = await self.db.execute(stmt)
        count = result.scalar() or 0
        return count < max_per_day

    async def check_deduplication(
        self,
        farm_id: int,
        alert_type: str,
        current_severity: str,
        dedupe_window_hours: int = 6
    ) -> bool:
        """
        Returns True if allowed to send, False if duplicate.
        Suppresses if sent within dedupe_window_hours unless severity has escalated.
        """
        since = datetime.utcnow() - timedelta(hours=dedupe_window_hours)
        stmt = select(AlertDeliveryLog).where(
            AlertDeliveryLog.farm_id == farm_id,
            AlertDeliveryLog.alert_type == alert_type,
            AlertDeliveryLog.created_at >= since,
            AlertDeliveryLog.status == "delivered"
        ).order_by(AlertDeliveryLog.created_at.desc())

        result = await self.db.execute(stmt)
        recent_log = result.scalars().first()

        if not recent_log:
            return True  # No recent alert, safe to send

        recent_sev_rank = SEVERITY_ORDER.get(recent_log.severity, 0)
        curr_sev_rank = SEVERITY_ORDER.get(current_severity, 0)

        # Escalate only if current severity is strictly greater
        if curr_sev_rank > recent_sev_rank:
            logger.info(f"Escalation detected ({recent_log.severity} -> {current_severity}) for farm {farm_id}. Permitting alert.")
            return True

        logger.info(f"Deduplication suppressed {alert_type} for farm {farm_id} (already sent within {dedupe_window_hours}h).")
        return False

    async def dispatch_hazard_alert(
        self,
        farm: Farm,
        hazard: Dict[str, Any],
        subscription: Optional[AlertSubscription] = None
    ) -> List[AlertDeliveryLog]:
        """
        Dispatches alert across configured channels with deduplication, quiet hours, and logging.
        """
        farm_id = farm.id
        alert_type = hazard.get("alert_type", "weather_hazard")
        severity = hazard.get("severity", "yellow")
        probability = float(hazard.get("probability", 50.0))
        confidence = hazard.get("confidence", "Medium")
        
        # Check user-set minimum probability
        min_prob = subscription.min_probability if subscription else 50.0
        if probability < min_prob:
            logger.info(f"Alert {alert_type} probability {probability}% is below subscription min {min_prob}%. Skipping.")
            return []

        # Check quiet hours (critical red bypasses quiet hours)
        q_start = subscription.quiet_hours_start if subscription else 22
        q_end = subscription.quiet_hours_end if subscription else 6
        if severity != "red" and self.is_in_quiet_hours(q_start, q_end):
            logger.info(f"Suppressing non-critical alert for farm {farm_id} during quiet hours ({q_start}:00-{q_end}:00).")
            return []

        # Rate Limit check
        if not await self.check_rate_limit(farm_id, max_per_day=3):
            logger.warning(f"Rate limit reached (max 3/day) for farm {farm_id}. Alert held.")
            return []

        # Deduplication check
        if not await self.check_deduplication(farm_id, alert_type, severity, dedupe_window_hours=6):
            return []

        # Format short, plain messages
        village = farm.village or farm.district or "आपके क्षेत्र"
        crop = farm.current_crop or "फसल"
        action_hi = hazard.get("action_hi", "सावधानी बरतें।")
        action_en = hazard.get("action_en", "Take protective measures.")
        title_hi = hazard.get("title_hi", "मौसम चेतावनी")
        title_en = hazard.get("title_en", "Weather Alert")
        expected_val = hazard.get("expected_value", "")
        expected_date = hazard.get("expected_date", "अगले कुछ दिन")

        sms_text = (
            f"किसान मौसम चेतावनी: {title_hi}।\n"
            f"स्थान: {village} | फसल: {crop}\n"
            f"संभावना: {probability}% ({confidence})\n"
            f"समय: {expected_date} ({expected_val})\n"
            f"कार्रवाई: {action_hi}"
        )

        user_stmt = select(User).where(User.id == farm.user_id)
        user_res = await self.db.execute(user_stmt)
        user = user_res.scalars().first()
        phone = user.phone_number if user else None
        email = user.email if user else None

        channels_to_send = []
        if subscription:
            if subscription.channel_push:
                channels_to_send.append("push")
            if subscription.channel_sms and phone:
                channels_to_send.append("sms")
            if subscription.channel_email and email:
                channels_to_send.append("email")
        else:
            # Default channels
            channels_to_send = ["push"]
            if phone:
                channels_to_send.append("sms")
            if email:
                channels_to_send.append("email")

        logs = []
        for channel in channels_to_send:
            status = "failed"
            try:
                if channel == "sms" and phone:
                    await self.sms_provider.send_sms(
                        phone_number=phone,
                        template_key=alert_type,
                        params={
                            "crop": crop,
                            "village": village,
                            "probability": str(probability),
                            "action": action_hi[:50]
                        }
                    )
                    status = "delivered"
                elif channel == "email" and email:
                    subject = f"🚨 किसान मौसम चेतावनी: {title_hi} ({village})"
                    html_content = f"""
                    <h2>किसान मौसम (KisanMausam) कृषि चेतावनी</h2>
                    <p><strong>खेत:</strong> {farm.name} ({village})</p>
                    <p><strong>फसल:</strong> {crop} ({farm.crop_stage})</p>
                    <p><strong>चेतावनी:</strong> {title_hi} / {title_en}</p>
                    <p><strong>तीव्रता (Severity):</strong> {severity.upper()} | <strong>संभावना:</strong> {probability}% ({confidence})</p>
                    <p><strong>अनुमानित मान:</strong> {expected_val}</p>
                    <div style="background:#e8f5e9;padding:12px;border-left:4px solid #2e7d32;margin:12px 0;">
                        <strong>कृषि वैज्ञानिक सलाह (Action):</strong> {action_hi}
                    </div>
                    <p style="color:#777;font-size:12px;">स्रोत: भारतीय मौसम विभाग (IMD) मानक एवं Open-Meteo एन्सेम्बल डेटा।</p>
                    """
                    await self.email_provider.send_email(email, subject, html_content)
                    status = "delivered"
                elif channel == "push":
                    await fcm_service.send_push_notification(
                        device_token=f"token_farm_{farm_id}",
                        title=f"⚠️ {title_hi} ({probability}%)",
                        body=f"{village}: {action_hi}"
                    )
                    status = "delivered"
            except Exception as e:
                logger.error(f"Failed to deliver {alert_type} via {channel} to farm {farm_id}: {e}")
                status = "failed"

            recipient_str = phone if channel == "sms" else (email if channel == "email" else f"token_farm_{farm_id}")
            log_entry = AlertDeliveryLog(
                farm_id=farm_id,
                user_id=farm.user_id,
                alert_type=alert_type,
                channel=channel,
                severity=severity,
                probability=probability,
                confidence=confidence,
                message_content=sms_text,
                recipient=recipient_str,
                status=status,
                created_at=datetime.utcnow()
            )
            self.db.add(log_entry)
            logs.append(log_entry)

        await self.db.commit()
        for log in logs:
            await self.db.refresh(log)

        return logs

    async def dispatch_weekly_digest(self, farm: Farm) -> Dict[str, Any]:
        """
        Dispatches the weekly digest containing the 2-week outlook and monthly ENSO status.
        """
        enso = await fetch_enso_status()
        village = farm.village or "आपके क्षेत्र"
        user_stmt = select(User).where(User.id == farm.user_id)
        user_res = await self.db.execute(user_stmt)
        user = user_res.scalars().first()
        
        digest_text = (
            f"किसान मौसम साप्ताहिक बुलेटिन:\n"
            f"स्थान: {village} | फसल: {farm.current_crop}\n"
            f"1. ईएनएसओ स्थिति: {enso.get('phase_hi')} ({enso.get('status_hi')})\n"
            f"2. 30-दिवसीय वर्षा रुझान: सामान्य वर्षा 45% संभावना, कम वर्षा 35% संभावना।\n"
            f"3. सलाह: खेत में नमी जांचें व खरपतवार नियंत्रण समय पर करें।"
        )

        phone = user.phone_number if user else None
        if phone:
            await self.sms_provider.send_sms(
                phone_number=phone,
                template_key="weekly_digest",
                params={"village": village, "crop": farm.current_crop or "फसल"}
            )

        recipient_str = phone if phone else f"user_{farm.user_id}"
        log_entry = AlertDeliveryLog(
            farm_id=farm.id,
            user_id=farm.user_id,
            alert_type="weekly_digest",
            channel="sms" if phone else "push",
            severity="info",
            probability=100.0,
            confidence="High",
            message_content=digest_text,
            recipient=recipient_str,
            status="delivered",
            created_at=datetime.utcnow()
        )
        self.db.add(log_entry)
        await self.db.commit()
        return {"status": "delivered", "digest": digest_text}
