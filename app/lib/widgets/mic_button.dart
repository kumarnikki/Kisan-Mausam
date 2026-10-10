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
    this.label = 'बोलकर पूछें',
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

            // Compact 56px circular FAB to prevent overlapping text content on scroll
            SizedBox(
              width: 56,
              height: 56,
              child: FloatingActionButton(
                heroTag: 'kisan_mic_fab',
                onPressed: widget.onPressed ??
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const KrishiSahayakScreen(),
                        ),
                      );
                    },
                elevation: 6,
                highlightElevation: 10,
                backgroundColor: const Color(0xFF1B5E20),
                shape: const CircleBorder(),
                child: const Icon(Icons.mic, size: 28, color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}
