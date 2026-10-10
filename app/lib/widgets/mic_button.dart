import 'package:flutter/material.dart';
import '../screens/chat/krishi_sahayak_screen.dart';

/// Modernized, animated prominent Hindi voice microphone button
/// with realistic pulsing radar waves, specular light catches, and a rich terracotta gradient.
class ProminentMicButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String label;

  const ProminentMicButton({
    super.key,
    this.onPressed,
    this.label = 'बोलकर पूछें (Voice)',
  });

  @override
  State<ProminentMicButton> createState() => _ProminentMicButtonState();
}

class _ProminentMicButtonState extends State<ProminentMicButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final progress = _pulseController.value;
        final waveRadius = 4.0 + 16.0 * progress;
        final waveOpacity = (1.0 - progress).clamp(0.0, 1.0) * 0.45;

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Outer Pulsing Radar Ripple Ring
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFBF360C).withValues(alpha: waveOpacity),
                      blurRadius: waveRadius * 1.5,
                      spreadRadius: waveRadius * 0.5,
                    ),
                  ],
                ),
              ),
            ),

            // Actual FAB with exact text & icon expected by tests
            FloatingActionButton.extended(
              heroTag: 'kisan_mic_fab',
              onPressed: widget.onPressed ??
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const KrishiSahayakScreen(),
                      ),
                    );
                  },
              elevation: 8,
              highlightElevation: 12,
              backgroundColor: const Color(0xFFBF360C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.mic, size: 28, color: Colors.white),
              ),
              label: Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.4,
                  shadows: [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
