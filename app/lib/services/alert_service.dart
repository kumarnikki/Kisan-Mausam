import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

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

  static bool get isSoundPlaying => _isSoundPlaying;

  /// Requests Android SEND_SMS, READ_PHONE_STATE & POST_NOTIFICATIONS permissions so weather change SMS dispatches automatically.
  static Future<void> requestSmsPermission() async {
    try {
      await _nativeAlertChannel.invokeMethod('requestSmsPermission');
    } catch (_) {}
  }

  /// Reads the 10-digit Indian mobile number from the device's active SIM card if available.
  static Future<String?> detectSimPhoneNumber() async {
    try {
      final simPhone = await _nativeAlertChannel.invokeMethod<String>('getSimPhoneNumber');
      if (simPhone != null && simPhone.trim().length >= 10) {
        return simPhone.trim();
      }
    } catch (_) {}
    return null;
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

  /// Triggers Android Native Emergency SOS Dialer (112 National Emergency).
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

  /// Triggers Kisan Call Center Helpline Dialer (1800-180-1551).
  static Future<void> callKisanHelpline() async {
    final uri = Uri.parse('tel:18001801551');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri);
      } catch (_) {}
    }
  }

  /// Full-screen / modal SOS-active surface (Step 4.3):
  /// - Red header with "SOS active"
  /// - Status line "SMS sent to +91 XXXXX XXXXX" with failure/retry state
  /// - "Stop siren" as dominant primary button at top of actions
  /// - "Call 112" and "Call Kisan helpline 1800-180-1551" as secondary buttons
  /// - No fake "100% probability / RED ALERT" or weather source/date text
  /// - Dismissing this surface automatically stops the siren
  static Future<void> showSosActiveSurface(
    BuildContext context, {
    required String lang,
    required String? phoneNumber,
    required String locationName,
    double? lat,
    double? lon,
    required Future<bool> Function() onSendSms,
    Future<bool> Function(String newPhone)? onSendSmsWithPhone,
  }) async {
    final isHi = lang == 'hi';
    final spokenWarning = isHi
        ? 'आपातकालीन एसओएस सक्रिय है! सायरन बज रहा है और आपातकालीन एसएमएस भेजा जा रहा है।'
        : 'Emergency SOS active! Siren is sounding and emergency SMS is being dispatched.';

    playAlertSound(voiceText: spokenWarning, lang: lang).catchError((_) {});

    if (!context.mounted) return;

    bool sirenActive = true;
    bool smsSending = true;
    bool smsSent = false;
    bool dispatchInFlight = false;
    String currentPhone = (phoneNumber ?? '').trim();
    final phoneInputCtrl = TextEditingController(text: currentPhone);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (smsSending && !dispatchInFlight) {
              dispatchInFlight = true;
              Future.microtask(() async {
                final ok = (currentPhone.length >= 10 && onSendSmsWithPhone != null)
                    ? await onSendSmsWithPhone(currentPhone)
                    : await onSendSms();
                dispatchInFlight = false;
                if (ctx.mounted) {
                  setSheetState(() {
                    smsSending = false;
                    smsSent = ok;
                  });
                }
              });
            }

            final hasValidPhone = currentPhone.replaceAll(RegExp(r'\D'), '').length >= 10;
            final displayPhone = hasValidPhone
                ? '+91 ${currentPhone.replaceAll(RegExp(r'\D'), '')}'
                : (isHi ? 'पंजीकृत मोबाइल नंबर' : 'registered mobile number');

            String smsStatusText;
            if (smsSending) {
              smsStatusText = isHi
                  ? '$displayPhone पर स्थान ($locationName) सहित SMS भेजा जा रहा है...'
                  : 'Sending SMS with location ($locationName) to $displayPhone...';
            } else if (smsSent && hasValidPhone) {
              smsStatusText = isHi
                  ? '$displayPhone पर आपातकालीन SMS भेज दिया गया है ($locationName)'
                  : 'SMS sent to $displayPhone ($locationName)';
            } else if (!hasValidPhone) {
              smsStatusText = isHi
                  ? 'आपातकालीन अलर्ट सक्रिय ($locationName)। SMS पाने हेतु नीचे 10 अंकों का मोबाइल नंबर दर्ज करें:'
                  : 'Emergency alert active ($locationName). Enter 10-digit mobile number below to receive SMS:';
            } else {
              smsStatusText = isHi
                  ? '$displayPhone पर SMS लंबित है (पुनः प्रयास करें या SMS अनुमति दें)'
                  : 'SMS to $displayPhone could not be confirmed';
            }

            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, _) {
                stopAlertSound();
              },
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppTheme.rSheet),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Red header with "SOS active"
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.s24,
                              vertical: AppTheme.s24,
                            ),
                            decoration: const BoxDecoration(
                              color: AppTheme.danger,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(AppTheme.rSheet),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.shield_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                const SizedBox(width: AppTheme.s12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppStrings.get('sos_active_title', lang),
                                        style: AppTheme.titleStyle.copyWith(
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        locationName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(AppTheme.s24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // SMS Status Surface
                                AppSurface(
                                  padding: const EdgeInsets.all(AppTheme.s16),
                                  borderRadius: AppTheme.rInput,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Icon(
                                            smsSending
                                                ? Icons.schedule_send_rounded
                                                : (smsSent && hasValidPhone
                                                    ? Icons.check_circle_rounded
                                                    : Icons.sms_rounded),
                                            color: (smsSent && hasValidPhone)
                                                ? AppTheme.semanticSuccessText(ctx)
                                                : AppTheme.semanticWarningText(ctx),
                                            size: 24,
                                          ),
                                          const SizedBox(width: AppTheme.s12),
                                          Expanded(
                                            child: Text(
                                              smsStatusText,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textPrimary(ctx),
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                          if (!smsSending && hasValidPhone)
                                            TextButton(
                                              onPressed: () {
                                                setSheetState(() {
                                                  smsSent = false;
                                                  smsSending = true;
                                                });
                                              },
                                              child: Text(isHi ? 'पुनः भेजें' : 'Resend'),
                                            ),
                                        ],
                                      ),
                                      if (!hasValidPhone) ...[
                                        const SizedBox(height: AppTheme.s12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: phoneInputCtrl,
                                                keyboardType: TextInputType.phone,
                                                maxLength: 10,
                                                decoration: InputDecoration(
                                                  hintText: isHi
                                                      ? '10 अंकों का मोबाइल नंबर'
                                                      : '10-digit mobile number',
                                                  prefixText: '+91 ',
                                                  counterText: '',
                                                  isDense: true,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: AppTheme.s8),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppTheme.primaryButtonFill(ctx),
                                                foregroundColor: Colors.white,
                                                minimumSize: const Size(88, 44),
                                              ),
                                              onPressed: () {
                                                final digits = phoneInputCtrl.text
                                                    .replaceAll(RegExp(r'\D'), '');
                                                if (digits.length >= 10) {
                                                  final ten = digits.substring(digits.length - 10);
                                                  setSheetState(() {
                                                    currentPhone = ten;
                                                    smsSent = false;
                                                    smsSending = true;
                                                  });
                                                }
                                              },
                                              child: Text(isHi ? 'SMS भेजें' : 'Send SMS'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: AppTheme.s24),

                            // 1. Dominant Primary Action at top: Stop Siren
                            DangerButton(
                              icon: sirenActive
                                  ? Icons.volume_off_rounded
                                  : Icons.check_rounded,
                              label: sirenActive
                                  ? AppStrings.get('sos_stop_siren', lang)
                                  : (isHi
                                      ? 'सायरन बंद है • बंद करें'
                                      : 'Siren stopped • Close'),
                              onPressed: () {
                                stopAlertSound();
                                if (sirenActive) {
                                  setSheetState(() => sirenActive = false);
                                } else {
                                  Navigator.pop(sheetCtx);
                                }
                              },
                            ),
                            const SizedBox(height: AppTheme.s12),

                            // 2. Secondary Action: Call 112
                            SecondaryButton(
                              icon: Icons.call_rounded,
                              label: AppStrings.get('sos_call_112', lang),
                              onPressed: () => triggerAndroidSos(
                                locationName: locationName,
                                lat: lat,
                                lon: lon,
                              ),
                            ),
                            const SizedBox(height: AppTheme.s12),

                            // 3. Secondary Action: Call Kisan Helpline 1800-180-1551
                            SecondaryButton(
                              icon: Icons.support_agent_rounded,
                              label: AppStrings.get('sos_call_kvk', lang),
                              onPressed: callKisanHelpline,
                            ),
                            if (!sirenActive) ...[
                              const SizedBox(height: AppTheme.s12),
                              TextButton(
                                onPressed: () {
                                  stopAlertSound();
                                  Navigator.pop(sheetCtx);
                                },
                                child: Text(
                                  isHi ? 'बंद करें' : 'Dismiss',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSecondary(ctx),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      phoneInputCtrl.dispose();
      stopAlertSound();
    });
  }

  /// Show an in-app weather hazard popup dialog restyled to match the StatusRow / AppSurface design system.
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
    bool isSos = false,
  }) async {
    final isHi = lang == 'hi';
    final spokenAction = isHi ? actionHi : (actionEn ?? actionHi);
    final spokenWarning = isHi
        ? 'मौसम चेतावनी! $titleHi। $bodyHi। $spokenAction'
        : 'Weather Alert! $titleEn. $bodyEn. $spokenAction';

    playAlertSound(voiceText: spokenWarning, lang: lang).catchError((_) {});

    if (!context.mounted) return;

    final isRed = severity == 'red';
    final isOrange = severity == 'orange';
    final Color stripColor = isRed
        ? AppTheme.danger
        : isOrange
            ? AppTheme.warningText
            : AppTheme.cautionAmber;
    final IconData alertIcon = isRed
        ? Icons.warning_rounded
        : isOrange
            ? Icons.error_outline_rounded
            : Icons.info_outline_rounded;
    final String badgeText = isRed ? 'RED ALERT' : (isOrange ? 'WARNING' : 'WATCH');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rCard),
        ),
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rCard),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 6, color: stripColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.s24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(alertIcon, color: stripColor, size: 28),
                            const SizedBox(width: AppTheme.s12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isHi ? titleHi : titleEn,
                                    style: AppTheme.sectionStyle.copyWith(
                                      color: AppTheme.textPrimary(ctx),
                                    ),
                                  ),
                                  if (!isSos) ...[
                                    const SizedBox(height: AppTheme.s4),
                                    Text(
                                      '${probability.round()}% ${AppStrings.get('likelihood_suffix', lang)} • $badgeText',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: stripColor,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.s12),
                        Text(
                          isHi ? bodyHi : bodyEn,
                          style: TextStyle(
                            fontSize: 15,
                            color: AppTheme.textPrimary(ctx),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: AppTheme.s12),
                        Container(
                          padding: const EdgeInsets.all(AppTheme.s12),
                          decoration: BoxDecoration(
                            color: AppTheme.cautionAmber.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(AppTheme.rInput),
                            border: Border.all(
                              color: AppTheme.borderColor(ctx),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                color: AppTheme.primaryActionColor(ctx),
                                size: 20,
                              ),
                              const SizedBox(width: AppTheme.s8),
                              Expanded(
                                child: Text(
                                  spokenAction,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary(ctx),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isSos) ...[
                          const SizedBox(height: AppTheme.s12),
                          Text(
                            '${isHi ? "स्रोत" : "Source"}: Open-Meteo / IMD • ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary(ctx),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              stopAlertSound();
              Navigator.pop(ctx);
            },
            child: Text(
              isHi ? 'ध्वनि बंद करें' : 'Stop Sound',
              style: TextStyle(color: AppTheme.textSecondary(ctx)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: stripColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(96, 48),
            ),
            onPressed: () {
              stopAlertSound();
              Navigator.pop(ctx);
            },
            child: Text(isHi ? 'समझ गया' : 'Got it'),
          ),
        ],
      ),
    ).whenComplete(() {
      stopAlertSound();
    });
  }
}
