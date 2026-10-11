import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Interactive oceanic ONI Climate Index Gauge meter (-2.0°C La Niña to +2.0°C El Niño)
class OniGaugeMeter extends StatelessWidget {
  final double oniValue;
  final String lang;

  const OniGaugeMeter({
    super.key,
    required this.oniValue,
    this.lang = 'hi',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHc = AppTheme.isHighContrast(context);

    // ONI ranges roughly from -2.5 to +2.5
    final clamped = oniValue.clamp(-2.5, 2.5);
    final normalized = ((clamped - (-2.5)) / 5.0).clamp(0.0, 1.0);

    final laNinaColor = isHc
        ? Colors.black
        : (isDark ? const Color(0xFF4FC3F7) : const Color(0xFF0277BD));
    final neutralColor = AppTheme.textSecondary(context);
    final elNinoColor = isHc
        ? Colors.black
        : (isDark ? const Color(0xFFFF8A65) : const Color(0xFFBF360C));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Indicator Track
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final pinX = (width * normalized).clamp(8.0, width - 8.0);

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                // Gradient spectrum bar
                Container(
                  height: 10,
                  width: width,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF0288D1), // La Niña (Cool Blue)
                        Color(0xFF81D4FA), // Weak La Niña
                        Color(0xFF80CBC4), // Neutral (Teal)
                        Color(0xFFFFB74D), // Weak El Niño
                        Color(0xFFE65100), // El Niño (Warm Coral/Red)
                      ],
                    ),
                  ),
                ),

                // Center Neutral Tick Mark
                Positioned(
                  left: width * 0.5 - 1,
                  child: Container(
                    width: 2,
                    height: 14,
                    color: Colors.white,
                  ),
                ),

                // Active Pointer Needle Pin
                Positioned(
                  left: pinX - 8,
                  top: -4,
                  child: Container(
                    width: 16,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: oniValue > 0.5
                            ? const Color(0xFFE65100)
                            : (oniValue < -0.5
                                ? const Color(0xFF0288D1)
                                : const Color(0xFF00897B)),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        // Scale labels (scale-safe at 320dp and 1.3x textScaler)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  lang == 'en' ? '❄️ La Niña (-2°C)' : '❄️ ला नीना (-2°C)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: laNinaColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  lang == 'en' ? 'Neutral (0°C)' : 'तटस्थ (0°C)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: neutralColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  lang == 'en' ? '☀️ El Niño (+2°C)' : '☀️ अल नीनो (+2°C)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: elNinoColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
