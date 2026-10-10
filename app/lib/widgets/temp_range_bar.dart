import 'package:flutter/material.dart';

/// A modern iOS / Pixel Weather-inspired temperature spectrum range bar
/// displaying the day's low-to-high temperature visually with a warm/cool gradient.
class TempRangeBar extends StatelessWidget {
  final double minTemp;
  final double maxTemp;
  final double overallMin;
  final double overallMax;

  const TempRangeBar({
    super.key,
    required this.minTemp,
    required this.maxTemp,
    this.overallMin = 10,
    this.overallMax = 42,
  });

  @override
  Widget build(BuildContext context) {
    final range = (overallMax - overallMin).clamp(1.0, 100.0);
    final startFraction = ((minTemp - overallMin) / range).clamp(0.0, 0.85);
    final endFraction = ((maxTemp - overallMin) / range).clamp(startFraction + 0.1, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final barLeft = totalWidth * startFraction;
        final barWidth = (totalWidth * (endFraction - startFraction)).clamp(12.0, totalWidth);

        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Track background
            Container(
              height: 6,
              width: totalWidth,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // Active spectrum pill
            Positioned(
              left: barLeft,
              child: Container(
                height: 6,
                width: barWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF26A69A), // Cool teal
                      Color(0xFFFFB300), // Amber
                      Color(0xFFFF7043), // Warm coral
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
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
