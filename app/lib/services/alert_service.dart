import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Manages constant loud emergency sirens, continuous Android TTS voice warnings,
/// heavy vibration feedback, and Android Native SOS (112) dispatch.
class AlertService {
  static const MethodChannel _nativeAlertChannel =
      MethodChannel('in.kishanmausam.kisan_mausam/native_alert');
  static final AudioPlayer _player = AudioPlayer();
  static final FlutterTts _tts = FlutterTts();
  static bool _isSoundPlaying = false;
  static Timer? _vibrationTimer;
  static Timer? _voiceLoopTimer;

  /// Requests Android SEND_SMS & POST_NOTIFICATIONS permissions so weather change SMS dispatches automatically.
  static Future<void> requestSmsPermission() async {
    try {
      await _nativeAlertChannel.invokeMethod('requestSmsPermission');
    } catch (_) {}
  }

  /// Dispatches a real custom SMS directly from the device's SIM (and posts a high-priority system alert banner)
  /// with the exact weather change or SOS alert message (NEVER an OTP).
  static Future<bool> sendNativeDirectSms({
    required String phone,
    required String title,
    required String message,
  }) async {
    try {
      final res = await _nativeAlertChannel.invokeMethod<bool>(
        'sendDirectAlertSms',
        {
          'phone': phone,
          'title': title,
          'message': message,
        },
      );
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Play the constant MAX-VOLUME emergency siren + repeating strong voice alarm + vibration.
  static Future<void> playAlertSound({
    String? voiceText,
    String lang = 'hi',
  }) async {
    _isSoundPlaying = true;

    // 1. Force Android hardware speaker volume (STREAM_ALARM + STREAM_MUSIC) to 100% MAX
    //    and start native Android ToneGenerator emergency alarm + waveform vibration
    try {
      await _nativeAlertChannel.invokeMethod('boostAlarmVolumeAndSiren');
    } catch (_) {}

    // 2. Continuous heavy haptic impact backup
    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_isSoundPlaying) {
        HapticFeedback.heavyImpact();
      }
    });

    // 3. Constant looping ultra-loud piezo emergency siren on Android ALARM audio stream at 100% volume
    try {
      await _player.stop();
      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.alarm,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('sounds/alert.wav'), volume: 1.0);
    } catch (_) {}

    // 4. Strong, constant Android TTS voice announcement loop
    if (voiceText != null && voiceText.trim().isNotEmpty) {
      _startConstantVoiceLoop(voiceText, lang);
    }
  }

  static Future<void> _startConstantVoiceLoop(String text, String lang) async {
    try {
      await _tts.setLanguage(lang == 'en' ? 'en-IN' : 'hi-IN');
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(0.54);
      await _tts.setPitch(1.15);
      await _tts.speak(text);

      _voiceLoopTimer?.cancel();
      _voiceLoopTimer = Timer.periodic(const Duration(seconds: 7), (timer) async {
        if (!_isSoundPlaying) {
          timer.cancel();
          return;
        }
        try {
          await _tts.setVolume(1.0);
          await _tts.speak(text);
        } catch (_) {}
      });
    } catch (_) {}
  }

  /// Stop the constant siren, native hardware alarm, voice loop, and vibration.
  static Future<void> stopAlertSound() async {
    _isSoundPlaying = false;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    _voiceLoopTimer?.cancel();
    _voiceLoopTimer = null;
    try {
      await _nativeAlertChannel.invokeMethod('stopAlarmAndRestoreVolume');
    } catch (_) {}
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Triggers Android Native Emergency SOS Dialer (112 National Emergency) or SMS with live GPS coordinates.
  static Future<void> triggerAndroidSos({
    String? locationName,
    double? lat,
    double? lon,
  }) async {
    final emergencyUri = Uri.parse('tel:112');
    try {
      await launchUrl(emergencyUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(emergencyUri);
      } catch (_) {}
    }
  }

  /// Show an in-app hazard / SOS alert dialog with constant loud siren, strong voice, and Android SOS button.
  static Future<void> showHazardAlert(
    BuildContext context, {
    required String titleHi,
    required String titleEn,
    required String bodyHi,
    required String bodyEn,
    required String severity, // 'red' | 'orange' | 'yellow'
    required String actionHi,
    String? actionEn,
    required double probability,
    required String lang,
    double? lat,
    double? lon,
    String? locationName,
  }) async {
    final isHi = lang == 'hi';
    final spokenAction = isHi ? actionHi : (actionEn ?? actionHi);
    final spokenWarning = isHi
        ? 'आपातकालीन मौसम चेतावनी! $titleHi। $bodyHi। $spokenAction'
        : 'Emergency Weather SOS Alert! $titleEn. $bodyEn. $spokenAction';

    // Start constant loud siren + constant strong voice + vibration in background
    playAlertSound(voiceText: spokenWarning, lang: lang).catchError((_) {});

    if (!context.mounted) return;

    final isRed = severity == 'red';
    final isOrange = severity == 'orange';

    final Color headerColor = isRed
        ? const Color(0xFFB71C1C)
        : isOrange
            ? const Color(0xFFE65100)
            : const Color(0xFFF57F17);

    final IconData alertIcon = isRed
        ? Icons.sos_rounded
        : isOrange
            ? Icons.warning_amber_rounded
            : Icons.info_outline;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Colored header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(alertIcon, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isHi ? titleHi : titleEn,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${probability.round()}% संभावना • ${isRed ? "RED ALERT" : isOrange ? "WARNING" : "WATCH"}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isHi ? bodyHi : bodyEn,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.lightbulb, color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            spokenAction,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Native Android Emergency SOS button (112)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB71C1C),
                        side: const BorderSide(color: Color(0xFFB71C1C), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.emergency_share, size: 20),
                      label: Text(
                        isHi ? '🚨 Android आपातकालीन SOS (112 कॉल)' : '🚨 Android Emergency SOS (Call 112)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: () {
                        triggerAndroidSos(
                          locationName: locationName,
                          lat: lat,
                          lon: lon,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'स्रोत: Open-Meteo / IMD • ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              stopAlertSound();
              Navigator.pop(ctx);
            },
            child: Text(
              isHi ? 'ध्वनि बंद करें' : 'Stop Sound',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: headerColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(80, 36),
            ),
            onPressed: () {
              stopAlertSound();
              Navigator.pop(ctx);
            },
            child: Text(isHi ? 'समझ गया' : 'Got it'),
          ),
        ],
      ),
    );
  }
}
