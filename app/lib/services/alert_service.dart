import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Manages in-app alert sounds and pop-up dialogs.
class AlertService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _isSoundPlaying = false;

  /// Play the alert beep sound.
  static Future<void> playAlertSound() async {
    if (_isSoundPlaying) return;
    _isSoundPlaying = true;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/alert.wav'));
      _player.onPlayerComplete.listen((_) => _isSoundPlaying = false);
    } catch (e) {
      _isSoundPlaying = false;
    }
  }

  /// Stop the alert sound.
  static Future<void> stopAlertSound() async {
    _isSoundPlaying = false;
    await _player.stop();
  }

  /// Show an in-app hazard alert dialog with SFX.
  static Future<void> showHazardAlert(
    BuildContext context, {
    required String titleHi,
    required String titleEn,
    required String bodyHi,
    required String bodyEn,
    required String severity, // 'red' | 'orange' | 'yellow'
    required String actionHi,
    required double probability,
    required String lang,
  }) async {
    // Play sound in background without blocking dialog
    playAlertSound().catchError((_) {});

    if (!context.mounted) return;

    final isRed = severity == 'red';
    final isOrange = severity == 'orange';

    final Color headerColor = isRed
        ? const Color(0xFFB71C1C)
        : isOrange
            ? const Color(0xFFE65100)
            : const Color(0xFFF57F17);

    final IconData alertIcon = isRed
        ? Icons.warning_rounded
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
                          lang == 'hi' ? titleHi : titleEn,
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
                    lang == 'hi' ? bodyHi : bodyEn,
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
                            actionHi,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
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
              lang == 'hi' ? 'ध्वनि बंद करें' : 'Stop Sound',
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
            child: Text(lang == 'hi' ? 'समझ गया' : 'Got it'),
          ),
        ],
      ),
    );
  }
}
