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

    private fun ensurePermissionsRequested(): Boolean {
        val needed = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
            needed.add(Manifest.permission.SEND_SMS)
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

            // Force hardware speaker volumes to 100% MAXIMUM so SOS is physically as loud as the phone can get
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

        // Start continuous hardware vibration waveform
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

        // Start native Android STREAM_ALARM ToneGenerator overlay at 100% volume
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
                    // Rapidly alternate emergency alarm tones at max volume (100)
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

    private fun sendDirectSmsAndNotify(rawPhone: String, title: String, message: String): Boolean {
        val destPhone = normalizePhone(rawPhone)
        // Always post a high-priority heads-up notification with the exact alert details
        showHighPriorityAlertNotification(title, message, destPhone)

        if (destPhone.length < 10 || message.isBlank()) return false

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
            return dispatchSmsNow(destPhone, message)
        } else {
            // Save pending SMS and request permission immediately; will auto-send in onRequestPermissionsResult
            pendingSmsPhone = destPhone
            pendingSmsMessage = message
            pendingSmsTitle = title
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.SEND_SMS),
                SMS_PERMISSION_REQ_CODE
            )
            return true
        }
    }

    private fun dispatchSmsNow(destPhone: String, message: String): Boolean {
        return try {
            val smsManager: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                getSystemService(SmsManager::class.java) ?: SmsManager.getDefault()
            } else {
                @Suppress("DEPRECATION")
                val subId = SubscriptionManager.getDefaultSmsSubscriptionId()
                if (subId != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                    @Suppress("DEPRECATION")
                    SmsManager.getSmsManagerForSubscriptionId(subId)
                } else {
                    @Suppress("DEPRECATION")
                    SmsManager.getDefault()
                }
            }
            val parts = smsManager.divideMessage(message)
            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(destPhone, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(destPhone, null, message, null, null)
            }
            true
        } catch (e: Exception) {
            false
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
            if (phone != null && msg != null &&
                ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED
            ) {
                pendingSmsPhone = null
                pendingSmsMessage = null
                pendingSmsTitle = null
                dispatchSmsNow(phone, msg)
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
