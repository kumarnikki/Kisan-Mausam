import 'package:flutter/material.dart';

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
    // ONI ranges roughly from -2.5 to +2.5
    final clamped = oniValue.clamp(-2.5, 2.5);
    final normalized = ((clamped - (-2.5)) / 5.0).clamp(0.0, 1.0);

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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                  top: -5,
                  child: Container(
                    width: 16,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: oniValue > 0.5
                            ? const Color(0xFFE65100)
                            : (oniValue < -0.5 ? const Color(0xFF0288D1) : const Color(0xFF00897B)),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        // Scale labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              lang == 'en' ? '❄️ La Niña (-2°C)' : '❄️ ला नीना (-2°C)',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0277BD)),
            ),
            Text(
              lang == 'en' ? 'Neutral (0°C)' : 'तटस्थ (0°C)',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            Text(
              lang == 'en' ? '☀️ El Niño (+2°C)' : '☀️ एल नीनो (+2°C)',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFD84315)),
            ),
          ],
        ),
      ],
    );
  }
}
