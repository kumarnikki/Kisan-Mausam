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
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "in.kishanmausam.kisan_mausam/native_alert"
    private val SMS_PERMISSION_REQ_CODE = 9001
    private val ALERT_CHANNEL_ID = "kisan_mausam_critical_alerts_v2"
    private val ACTION_SMS_SENT = "in.kishanmausam.kisan_mausam.SMS_SENT"

    private var toneGenerator: ToneGenerator? = null
    private val alarmHandler = Handler(Looper.getMainLooper())
    private var alarmRunnable: Runnable? = null
    private var isSirenActive = false
    private var previousMusicVolume: Int? = null
    private var previousAlarmVolume: Int? = null
    private var pendingInstallApkPath: String? = null

    private data class PendingAlert(
        val phone: String,
        val title: String,
        val message: String
    )

    private val pendingAlerts = mutableListOf<PendingAlert>()

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
                "getUpdateApkPath" -> {
                    val apkFile = File(cacheDir, "kisan-mausam-update.apk")
                    result.success(apkFile.absolutePath)
                }
                "canInstallPackages" -> {
                    val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(allowed)
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val launched = installApkFile(filePath)
                    result.success(launched)
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
            try {
                ActivityCompat.requestPermissions(this, needed.toTypedArray(), SMS_PERMISSION_REQ_CODE)
            } catch (_: Exception) {}
            return false
        }
        return true
    }

    private fun requestSmsPermissionsWithRetry(attempt: Int) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED) {
            flushPendingAlerts()
            return
        }
        ensurePermissionsRequested()
        if (attempt < 4) {
            alarmHandler.postDelayed({
                if (pendingAlerts.isNotEmpty() &&
                    ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED
                ) {
                    requestSmsPermissionsWithRetry(attempt + 1)
                }
            }, 1600)
        }
    }

    private fun flushPendingAlerts() {
        val hasSmsPerm = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED

        val snapshot = pendingAlerts.toList()
        pendingAlerts.clear()

        for (item in snapshot) {
            showHighPriorityAlertNotification(item.title, item.message, item.phone)
            if (hasSmsPerm && item.phone.isNotBlank()) {
                val ok = dispatchSmsReliable(item.phone, item.message, item.title)
                if (ok) {
                    Toast.makeText(
                        this,
                        "SMS Alert sent to ${item.phone}",
                        Toast.LENGTH_SHORT
                    ).show()
                }
            }
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
     * deliver the exact weather/SOS alert text as a single standard SMS PDU.
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
            "$cleanTitle: Weather/SOS alert active for your farm location. Take immediate precaution. Helpline: 1800-180-1551"
        }

        return if (baseText.length <= 152) {
            baseText
        } else {
            baseText.substring(0, 149) + "..."
        }
    }

    private fun sendDirectSmsAndNotify(rawPhone: String, title: String, message: String): Boolean {
        if (message.isBlank()) return false
        val digits = rawPhone.filter { it.isDigit() }
        val resolvedPhone = if (digits.length >= 10) normalizePhone(rawPhone) else {
            val simDetected = detectDeviceSimPhoneNumber()
            if (simDetected != null) "+91$simDetected" else ""
        }

        // Always show high-priority heads-up notification immediately
        showHighPriorityAlertNotification(title, message, resolvedPhone)

        if (resolvedPhone.isBlank()) {
            // Request permissions in case SIM detection or notifications needed them
            ensurePermissionsRequested()
            return false
        }

        val hasSmsPerm = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED

        if (hasSmsPerm) {
            val ok = dispatchSmsReliable(resolvedPhone, message, title)
            if (ok) {
                Toast.makeText(
                    this,
                    "SMS Alert sent to $resolvedPhone",
                    Toast.LENGTH_SHORT
                ).show()
            }
            return ok
        } else {
            if (pendingAlerts.none { it.phone == resolvedPhone && it.message == message }) {
                pendingAlerts.add(PendingAlert(resolvedPhone, title, message))
            }
            requestSmsPermissionsWithRetry(0)
            return true
        }
    }

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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val sysMgr = getSystemService(SmsManager::class.java)
                if (sysMgr != null) {
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

        sendWithManagerIndex(managers, 0, plus91Phone, tenDigits, smsText)
        return true
    }

    private fun sendWithManagerIndex(
        managers: List<SmsManager>,
        index: Int,
        plus91Phone: String,
        tenDigits: String,
        smsText: String
    ) {
        if (index >= managers.size) return
        val mgr = managers[index]

        val reqCode = ((System.currentTimeMillis() % 100000).toInt() + index * 17)
        val sentAction = "$ACTION_SMS_SENT.$reqCode"

        var sentPI: PendingIntent? = null
        try {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    try {
                        unregisterReceiver(this)
                    } catch (_: Exception) {}
                    if (resultCode != Activity.RESULT_OK && index + 1 < managers.size) {
                        sendWithManagerIndex(managers, index + 1, plus91Phone, tenDigits, smsText)
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, IntentFilter(sentAction), Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, IntentFilter(sentAction))
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_ONE_SHOT
            }
            val explicitIntent = Intent(sentAction).setPackage(packageName)
            sentPI = PendingIntent.getBroadcast(this, reqCode, explicitIntent, flags)
        } catch (_: Exception) {
            sentPI = null
        }

        try {
            mgr.sendTextMessage(plus91Phone, null, smsText, sentPI, null)
        } catch (_: Exception) {
            try {
                mgr.sendTextMessage(tenDigits, null, smsText, sentPI, null)
            } catch (_: Exception) {
                if (index + 1 < managers.size) {
                    sendWithManagerIndex(managers, index + 1, plus91Phone, tenDigits, smsText)
                }
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
            if (grantResults.isEmpty()) {
                if (pendingAlerts.isNotEmpty()) {
                    alarmHandler.postDelayed({ ensurePermissionsRequested() }, 1200)
                }
                return
            }
            flushPendingAlerts()
        }
    }

    private fun createAlertNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ALERT_CHANNEL_ID,
                "Kisan Mausam Weather & SOS Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Critical Weather Change & SOS Emergency SMS Alerts"
                enableVibration(true)
                enableLights(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun showHighPriorityAlertNotification(title: String, message: String, destPhone: String) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val phoneLine = if (destPhone.isNotBlank()) "\n📲 SMS -> $destPhone" else ""
            val defaultSoundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            val contentPI = if (launchIntent != null) {
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                PendingIntent.getActivity(this, 0, launchIntent, flags)
            } else null

            val builder = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle(title)
                .setContentText(message)
                .setStyle(NotificationCompat.BigTextStyle().bigText("$message$phoneLine"))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setSound(defaultSoundUri)
                .setVibrate(longArrayOf(0, 500, 200, 500))
                .setAutoCancel(true)
            if (contentPI != null) {
                builder.setContentIntent(contentPI)
            }
            nm.notify((System.currentTimeMillis() % 100000).toInt(), builder.build())
        } catch (_: Exception) {}
    }

    private fun installApkFile(filePath: String): Boolean {
        try {
            if (filePath.isBlank()) return false
            val apkFile = File(filePath)
            if (!apkFile.exists() || apkFile.length() <= 0L) return false

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                pendingInstallApkPath = filePath
                Toast.makeText(
                    this,
                    "कृपया ऐप अपडेट इंस्टॉल करने के लिए अनुमति दें (Allow from this source)",
                    Toast.LENGTH_LONG
                ).show()
                val settingsIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(settingsIntent)
                return true
            }

            return launchPackageInstaller(apkFile)
        } catch (_: Exception) {
            return false
        }
    }

    private fun launchPackageInstaller(apkFile: File): Boolean {
        return try {
            val apkUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apkFile
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(installIntent)
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onResume() {
        super.onResume()
        val pendingPath = pendingInstallApkPath
        if (!pendingPath.isNullOrBlank()) {
            val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                packageManager.canRequestPackageInstalls()
            } else {
                true
            }
            if (canInstall) {
                pendingInstallApkPath = null
                val apkFile = File(pendingPath)
                if (apkFile.exists() && apkFile.length() > 0L) {
                    launchPackageInstaller(apkFile)
                }
            }
        }
    }

    override fun onDestroy() {
        stopHardwareSiren()
        super.onDestroy()
    }
}
