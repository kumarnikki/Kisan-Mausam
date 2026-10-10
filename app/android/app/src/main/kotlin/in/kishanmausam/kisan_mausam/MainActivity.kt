package `in`.kishanmausam.kisan_mausam

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
    private val ACTION_SMS_SENT = "in.kishanmausam.kisan_mausam.SMS_SENT"

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
                        SubscriptionManager.getDefaultDataSubscriptionId(),
                        SubscriptionManager.getDefaultVoiceSubscriptionId(),
                        1,
                        2
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_NUMBERS) != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.READ_PHONE_NUMBERS)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                needed.add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), SMS_PERMISSION_REQ_CODE)
            return false
        }
        return true
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
     * Strips emoji surrogate pairs so Indian carriers (Jio / Airtel / Vi / BSNL)
     * never drop the SMS or split it into broken UCS-2 chunks.
     */
    private fun sanitizeCarrierSmsText(rawMessage: String): String {
        val cleaned = rawMessage
            .replace("°C", "C")
            .replace(Regex("[\\uD800-\\uDFFF]"), "")
            .replace(Regex("[⚠️🚨🌧️❄️🔥📲✅🌾🌱🟡]"), "")
            .replace(Regex("\\s+"), " ")
            .trim()
        return cleaned
    }

    private fun sendDirectSmsAndNotify(rawPhone: String, title: String, message: String): Boolean {
        val resolvedPhone = if (rawPhone.filter { it.isDigit() }.length >= 10) {
            normalizePhone(rawPhone)
        } else {
            val sim = detectDeviceSimPhoneNumber()
            if (sim != null) "+91$sim" else ""
        }

        if (resolvedPhone.length < 10 || message.isBlank()) return false

        val cleanSmsText = sanitizeCarrierSmsText(message)

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
            val ok = dispatchSmsMultiSim(resolvedPhone, cleanSmsText)
            showHighPriorityAlertNotification(title, message, resolvedPhone)
            return ok
        } else {
            pendingSmsPhone = resolvedPhone
            pendingSmsMessage = cleanSmsText
            pendingSmsTitle = title
            ensurePermissionsRequested()
            // Retry requesting permission after 1.2s in case GPS location dialog was open at the same moment
            alarmHandler.postDelayed({
                if (pendingSmsPhone != null &&
                    ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED
                ) {
                    ensurePermissionsRequested()
                }
            }, 1200)
            return true
        }
    }

    @Suppress("MissingPermission")
    private fun getCandidateSmsManagers(): List<SmsManager> {
        val managers = mutableListOf<SmsManager>()
        val subIds = mutableListOf<Int>()

        try {
            val defaultSms = SubscriptionManager.getDefaultSmsSubscriptionId()
            if (defaultSms != SubscriptionManager.INVALID_SUBSCRIPTION_ID && defaultSms > 0) {
                subIds.add(defaultSms)
            }
        } catch (_: Exception) {}

        try {
            val defaultData = SubscriptionManager.getDefaultDataSubscriptionId()
            if (defaultData != SubscriptionManager.INVALID_SUBSCRIPTION_ID && defaultData > 0) {
                subIds.add(defaultData)
            }
        } catch (_: Exception) {}

        try {
            val defaultVoice = SubscriptionManager.getDefaultVoiceSubscriptionId()
            if (defaultVoice != SubscriptionManager.INVALID_SUBSCRIPTION_ID && defaultVoice > 0) {
                subIds.add(defaultVoice)
            }
        } catch (_: Exception) {}

        try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED) {
                val subMgr = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                val activeList = subMgr?.activeSubscriptionInfoList
                if (activeList != null) {
                    for (info in activeList) {
                        if (info.subscriptionId > 0) {
                            subIds.add(info.subscriptionId)
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        subIds.add(1)
        subIds.add(2)

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
            @Suppress("DEPRECATION")
            val defMgr = SmsManager.getDefault()
            if (defMgr != null) {
                managers.add(defMgr)
            }
        } catch (_: Exception) {}

        return managers
    }

    private fun dispatchSmsMultiSim(destPhone: String, message: String): Boolean {
        val managers = getCandidateSmsManagers()
        if (managers.isEmpty()) return false

        sendWithManagerIndex(managers, 0, destPhone, message)
        return true
    }

    private fun sendWithManagerIndex(
        managers: List<SmsManager>,
        index: Int,
        destPhone: String,
        message: String
    ) {
        if (index >= managers.size) return
        val smsManager = managers[index]

        val reqCode = (System.currentTimeMillis() % 100000).toInt() + index
        val sentAction = "$ACTION_SMS_SENT.$reqCode"

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                try {
                    unregisterReceiver(this)
                } catch (_: Exception) {}
                if (resultCode != Activity.RESULT_OK && index + 1 < managers.size) {
                    // Automatically fallback to the next SIM slot SmsManager if this SIM slot failed
                    sendWithManagerIndex(managers, index + 1, destPhone, message)
                }
            }
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, IntentFilter(sentAction), Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, IntentFilter(sentAction))
            }
        } catch (_: Exception) {}

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_ONE_SHOT
        }
        val sentPI = PendingIntent.getBroadcast(this, reqCode, Intent(sentAction), flags)

        try {
            val parts = smsManager.divideMessage(message)
            if (parts.size <= 1) {
                smsManager.sendTextMessage(destPhone, null, message, sentPI, null)
            } else {
                val sentIntents = ArrayList<PendingIntent>()
                for (i in parts.indices) {
                    sentIntents.add(if (i == 0) sentPI else PendingIntent.getBroadcast(this, reqCode + 100 + i, Intent(sentAction), flags))
                }
                smsManager.sendMultipartTextMessage(destPhone, null, parts, sentIntents, null)
            }
        } catch (e: Exception) {
            if (index + 1 < managers.size) {
                sendWithManagerIndex(managers, index + 1, destPhone, message)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_REQ_CODE) {
            val phone = pendingSmsPhone
            val msg = pendingSmsMessage
            val title = pendingSmsTitle ?: "Kisan Mausam Weather Alert"
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
                if (phone != null && msg != null) {
                    pendingSmsPhone = null
                    pendingSmsMessage = null
                    pendingSmsTitle = null
                    dispatchSmsMultiSim(phone, msg)
                    showHighPriorityAlertNotification(title, msg, phone)
                }
            } else {
                Toast.makeText(
                    this,
                    "Please allow SMS permission in App Settings so Weather & SOS SMS alerts can be sent to your mobile.",
                    Toast.LENGTH_LONG
                ).show()
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
