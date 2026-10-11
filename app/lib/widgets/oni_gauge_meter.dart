import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Thin ONI scale bar (-2.0°C La Niña to +2.0°C El Niño) with animated marker (400 ms easeOutCubic from 0.0).
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
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    // ONI scale bar ranges from -2.0 to +2.0
    final clampedTarget = oniValue.clamp(-2.0, 2.0);

    final laNinaColor = isHc
        ? Colors.black
        : (isDark ? const Color(0xFF4FC3F7) : const Color(0xFF0277BD));
    final neutralColor = AppTheme.textSecondary(context);
    final elNinoColor = isHc
        ? Colors.black
        : (isDark ? const Color(0xFFFF8A65) : const Color(0xFFBF360C));

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: disableAnimations ? clampedTarget : 0.0,
        end: clampedTarget,
      ),
      duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, animatedOni, _) {
        final normalized = ((animatedOni - (-2.0)) / 4.0).clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final pinX = (width * normalized).clamp(7.0, (width - 7.0).clamp(7.0, double.infinity));

                return SizedBox(
                  height: 18,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      // Thin (-2 to +2) spectrum bar
                      Container(
                        height: 6,
                        width: width,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: isHc ? Colors.black12 : null,
                          border: isHc ? Border.all(color: Colors.black, width: 1.5) : null,
                          gradient: isHc
                              ? null
                              : const LinearGradient(
                                  colors: [
                                    Color(0xFF0277BD), // -2.0 La Niña
                                    Color(0xFF4FC3F7), // -0.5
                                    Color(0xFF80CBC4), //  0.0 Neutral
                                    Color(0xFFFFB74D), // +0.5
                                    Color(0xFFD84315), // +2.0 El Niño
                                  ],
                                ),
                        ),
                      ),

                      // Center 0°C Neutral tick mark
                      Positioned(
                        left: width * 0.5 - 1,
                        child: Container(
                          width: 2,
                          height: 12,
                          color: isHc ? Colors.black : Colors.white.withValues(alpha: 0.9),
                        ),
                      ),

                      // -0.5 and +0.5 threshold ticks
                      Positioned(
                        left: width * 0.375 - 0.5,
                        child: Container(
                          width: 1,
                          height: 10,
                          color: isHc ? Colors.black54 : Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                      Positioned(
                        left: width * 0.625 - 0.5,
                        child: Container(
                          width: 1,
                          height: 10,
                          color: isHc ? Colors.black54 : Colors.white.withValues(alpha: 0.65),
                        ),
                      ),

                      // Active ONI marker
                      Positioned(
                        left: pinX - 7,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isHc
                                  ? Colors.black
                                  : (oniValue >= 0.5
                                      ? const Color(0xFFD84315)
                                      : (oniValue <= -0.5
                                          ? const Color(0xFF0277BD)
                                          : const Color(0xFF00796B))),
                              width: 3,
                            ),
                            boxShadow: isHc
                                ? null
                                : const [
                                    BoxShadow(
                                      color: Color(0x26000000),
                                      blurRadius: 4,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    lang == 'en' ? '-2°C La Niña' : '-2°C ला नीना',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: laNinaColor,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '0°C',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: neutralColor,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    lang == 'en' ? '+2°C El Niño' : '+2°C अल नीनो',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: elNinoColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
