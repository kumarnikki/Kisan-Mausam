package `in`.kishanmausam.kisan_mausam

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "in.kishanmausam.kisan_mausam/native_alert"
    private val SMS_PERMISSION_REQ_CODE = 9001

    private var toneGenerator: ToneGenerator? = null
    private val alarmHandler = Handler(Looper.getMainLooper())
    private var alarmRunnable: Runnable? = null
    private var isSirenActive = false
    private var previousMusicVolume: Int? = null
    private var previousAlarmVolume: Int? = null

    private var pendingSmsPhone: String? = null
    private var pendingSmsMessage: String? = null
    private var pendingSmsTitle: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createAlertNotificationChannel()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestSmsPermission" -> {
                    val granted = ensurePermissionsRequested()
                    result.success(granted)
                }
                "hasSmsPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.SEND_SMS
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "getSimPhoneNumber" -> {
                    val simNumber = detectDeviceSimPhoneNumber()
                    result.success(simNumber)
                }
                "boostAlarmVolumeAndSiren" -> {
                    startMaxVolumeHardwareSiren()
                    result.success(true)
                }
                "stopAlarmAndRestoreVolume" -> {
                    stopHardwareSiren()
                    result.success(true)
                }
                "sendDirectAlertSms" -> {
                    val phone = call.argument<String>("phone") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    val title = call.argument<String>("title") ?: "Kisan Mausam Weather Alert"
                    val sent = sendDirectSmsAndNotify(phone, title, message)
                    result.success(sent)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun extractTenDigitIndianMobile(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        val digits = raw.filter { it.isDigit() }
        if (digits.length >= 10) {
            val ten = digits.takeLast(10)
            if (ten[0] in '6'..'9') {
                return ten
            }
        }
        return null
    }

    @Suppress("MissingPermission")
    private fun detectDeviceSimPhoneNumber(): String? {
        try {
            val hasPhoneNumbersPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_NUMBERS) == PackageManager.PERMISSION_GRANTED
            } else {
                false
            }
            val hasPhoneStatePerm = ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED

            if (hasPhoneNumbersPerm || hasPhoneStatePerm) {
                val subMgr = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && subMgr != null) {
                    val subIds = listOf(
                        SubscriptionManager.getDefaultSmsSubscriptionId(),
                        SubscriptionManager.getDefaultVoiceSubscriptionId(),
                        SubscriptionManager.getDefaultDataSubscriptionId()
                    ).filter { it != SubscriptionManager.INVALID_SUBSCRIPTION_ID && it > 0 }.distinct()
                    for (sid in subIds) {
                        try {
                            val num = subMgr.getPhoneNumber(sid)
                            val clean = extractTenDigitIndianMobile(num)
                            if (clean != null) return clean
                        } catch (_: Exception) {}
                    }
                }
                if (subMgr != null) {
                    try {
                        val activeList = subMgr.activeSubscriptionInfoList
                        if (activeList != null) {
                            for (info in activeList) {
                                @Suppress("DEPRECATION")
                                val clean = extractTenDigitIndianMobile(info.number)
                                if (clean != null) return clean
                            }
                        }
                    } catch (_: Exception) {}
                }
                val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                @Suppress("DEPRECATION")
                val line1 = extractTenDigitIndianMobile(tm?.line1Number)
                if (line1 != null) return line1
            }
        } catch (_: Exception) {}
        return null
    }

    private fun ensurePermissionsRequested(): Boolean {
        val needed = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.SEND_SMS)
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.READ_PHONE_STATE)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        if (needed.isNotEmpty()) {
            try {
                ActivityCompat.requestPermissions(this, needed.toTypedArray(), SMS_PERMISSION_REQ_CODE)
            } catch (_: Exception) {}
            return false
        }
        return true
    }

    private fun requestSmsPermissionsWithRetry(attempt: Int) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
            val phone = pendingSmsPhone
            val msg = pendingSmsMessage
            val title = pendingSmsTitle ?: "Kisan Mausam Weather Alert"
            if (phone != null && msg != null) {
                pendingSmsPhone = null
                pendingSmsMessage = null
                pendingSmsTitle = null
                dispatchSmsReliable(phone, msg, title)
            }
            return
        }
        ensurePermissionsRequested()
        if (attempt < 4) {
            alarmHandler.postDelayed({
                if (pendingSmsPhone != null &&
                    ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED
                ) {
                    requestSmsPermissionsWithRetry(attempt + 1)
                }
            }, 1600)
        }
    }

    private fun startMaxVolumeHardwareSiren() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (previousMusicVolume == null) {
                previousMusicVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            }
            if (previousAlarmVolume == null) {
                previousAlarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
            }

            val maxAlarm = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
            val maxMusic = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val maxRing = audioManager.getStreamMaxVolume(AudioManager.STREAM_RING)

            audioManager.setStreamVolume(AudioManager.STREAM_ALARM, maxAlarm, 0)
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxMusic, 0)
            try {
                audioManager.setStreamVolume(AudioManager.STREAM_RING, maxRing, 0)
            } catch (_: Exception) {}

            audioManager.mode = AudioManager.MODE_NORMAL
            @Suppress("DEPRECATION")
            audioManager.isSpeakerphoneOn = true
        } catch (_: Exception) {}

        try {
            val pattern = longArrayOf(0, 600, 150, 600, 150, 900)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    v.vibrate(VibrationEffect.createWaveform(pattern, 0))
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(pattern, 0)
                }
            }
        } catch (_: Exception) {}

        stopToneLoopOnly()
        isSirenActive = true
        try {
            toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
        } catch (_: Exception) {}

        alarmRunnable = object : Runnable {
            var toggle = false
            override fun run() {
                if (!isSirenActive) return
                try {
                    val tone = if (toggle) ToneGenerator.TONE_CDMA_EMERGENCY_RINGBACK else ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD
                    toneGenerator?.startTone(tone, 550)
                    toggle = !toggle
                } catch (_: Exception) {}
                if (isSirenActive) {
                    alarmHandler.postDelayed(this, 650)
                }
            }
        }
        alarmHandler.post(alarmRunnable!!)
    }

    private fun stopToneLoopOnly() {
        isSirenActive = false
        alarmRunnable?.let { alarmHandler.removeCallbacks(it) }
        alarmRunnable = null
        try {
            toneGenerator?.stopTone()
            toneGenerator?.release()
        } catch (_: Exception) {}
        toneGenerator = null
    }

    private fun stopHardwareSiren() {
        stopToneLoopOnly()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vm.defaultVibrator.cancel()
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
                v.cancel()
            }
        } catch (_: Exception) {}
    }

    private fun normalizePhone(raw: String): String {
        val digits = raw.filter { it.isDigit() }
        val ten = if (digits.length > 10) digits.takeLast(10) else digits
        return if (ten.length == 10) "+91$ten" else raw
    }

    /**
     * Converts any alert message into a clean, single-segment GSM 7-bit ASCII string (<= 152 chars)
     * so Indian carriers (Jio / Airtel / Vi / BSNL) and Android SmsManager.sendTextMessage
     * deliver it as a single standard SMS PDU without UCS-2 70-char overflow or multipart drops.
     */
    private fun toSingleSegmentAsciiSms(rawMessage: String, title: String): String {
        val asciiOnly = rawMessage
            .replace("°C", "C")
            .replace("°", "")
            .replace("•", "-")
            .replace("—", "-")
            .replace("–", "-")
            .map { ch -> if (ch.code in 32..126) ch else ' ' }
            .joinToString("")
            .replace(Regex("\\s+"), " ")
            .trim()

        val letterCount = asciiOnly.count { it in 'A'..'Z' || it in 'a'..'z' }
        val baseText = if (letterCount >= 12) {
            asciiOnly
        } else {
            val cleanTitle = title
                .map { ch -> if (ch.code in 32..126) ch else ' ' }
                .joinToString("")
                .replace(Regex("\\s+"), " ")
                .trim()
                .ifEmpty { "KisanMausam Weather Alert" }
            "$cleanTitle: Weather alert active for your farm location. Take precaution. Helpline: 1800-180-1551"
        }

        return if (baseText.length <= 152) {
            baseText
        } else {
            baseText.substring(0, 149) + "..."
        }
    }

    private fun sendDirectSmsAndNotify(rawPhone: String, title: String, message: String): Boolean {
        val resolvedPhone = if (rawPhone.filter { it.isDigit() }.length >= 10) {
            normalizePhone(rawPhone)
        } else {
            val sim = detectDeviceSimPhoneNumber()
            if (sim != null) "+91$sim" else ""
        }

        if (resolvedPhone.length < 10 || message.isBlank()) return false

        showHighPriorityAlertNotification(title, message, resolvedPhone)

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
            return dispatchSmsReliable(resolvedPhone, message, title)
        } else {
            pendingSmsPhone = resolvedPhone
            pendingSmsMessage = message
            pendingSmsTitle = title
            requestSmsPermissionsWithRetry(0)
            return false
        }
    }

    @Suppress("MissingPermission")
    private fun getActiveSmsManagers(): List<SmsManager> {
        val managers = mutableListOf<SmsManager>()
        val subIds = mutableListOf<Int>()

        try {
            val defaultSms = SubscriptionManager.getDefaultSmsSubscriptionId()
            if (defaultSms != SubscriptionManager.INVALID_SUBSCRIPTION_ID && defaultSms > 0) {
                subIds.add(defaultSms)
            }
        } catch (_: Exception) {}

        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
                val subMgr = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                val activeList = subMgr?.activeSubscriptionInfoList
                if (!activeList.isNullOrEmpty()) {
                    for (info in activeList) {
                        if (info.subscriptionId > 0) {
                            subIds.add(info.subscriptionId)
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        try {
            val defaultVoice = SubscriptionManager.getDefaultVoiceSubscriptionId()
            if (defaultVoice != SubscriptionManager.INVALID_SUBSCRIPTION_ID && defaultVoice > 0) {
                subIds.add(defaultVoice)
            }
        } catch (_: Exception) {}

        try {
            val defaultData = SubscriptionManager.getDefaultDataSubscriptionId()
            if (defaultData != SubscriptionManager.INVALID_SUBSCRIPTION_ID && defaultData > 0) {
                subIds.add(defaultData)
            }
        } catch (_: Exception) {}

        for (sid in subIds.distinct()) {
            try {
                val mgr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    getSystemService(SmsManager::class.java)?.createForSubscriptionId(sid)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getSmsManagerForSubscriptionId(sid)
                }
                if (mgr != null) {
                    managers.add(mgr)
                }
            } catch (_: Exception) {}
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val sysMgr = getSystemService(SmsManager::class.java)
                if (sysMgr != null && managers.isEmpty()) {
                    managers.add(sysMgr)
                }
            }
        } catch (_: Exception) {}

        try {
            @Suppress("DEPRECATION")
            val defMgr = SmsManager.getDefault()
            if (defMgr != null) {
                managers.add(defMgr)
            }
        } catch (_: Exception) {}

        return managers
    }

    private fun dispatchSmsReliable(destPhone: String, rawMessage: String, title: String): Boolean {
        val smsText = toSingleSegmentAsciiSms(rawMessage, title)
        val managers = getActiveSmsManagers()
        if (managers.isEmpty()) return false

        val digits = destPhone.filter { it.isDigit() }
        val tenDigits = if (digits.length >= 10) digits.takeLast(10) else digits
        val plus91Phone = if (tenDigits.length == 10) "+91$tenDigits" else destPhone

        var sentOnAny = false
        for (mgr in managers) {
            try {
                mgr.sendTextMessage(plus91Phone, null, smsText, null, null)
                sentOnAny = true
                break
            } catch (_: Exception) {
                try {
                    mgr.sendTextMessage(tenDigits, null, smsText, null, null)
                    sentOnAny = true
                    break
                } catch (_: Exception) {}
            }
        }
        return sentOnAny
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_REQ_CODE) {
            if (grantResults.isEmpty()) {
                // Permission dialog was interrupted by another system prompt (e.g. GPS); retry shortly
                if (pendingSmsPhone != null) {
                    alarmHandler.postDelayed({ ensurePermissionsRequested() }, 1200)
                }
                return
            }
            val phone = pendingSmsPhone
            val msg = pendingSmsMessage
            val title = pendingSmsTitle ?: "Kisan Mausam Weather Alert"
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
                if (phone != null && msg != null) {
                    pendingSmsPhone = null
                    pendingSmsMessage = null
                    pendingSmsTitle = null
                    val ok = dispatchSmsReliable(phone, msg, title)
                    if (ok) {
                        Toast.makeText(
                            this,
                            "Weather Alert SMS sent to $phone",
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            }
        }
    }

    private fun createAlertNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "kisan_weather_sms_alerts",
                "Kisan Mausam Weather & SOS Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Critical Weather Change & SOS SMS Alerts"
                enableVibration(true)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun showHighPriorityAlertNotification(title: String, message: String, destPhone: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val notif = NotificationCompat.Builder(this, "kisan_weather_sms_alerts")
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText("$message\n📲 SMS -> $destPhone"))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .build()
            nm.notify((System.currentTimeMillis() % 100000).toInt(), notif)
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        stopHardwareSiren()
        super.onDestroy()
    }
}
