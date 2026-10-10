import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Renders the 3D Claymorphic Weather Icon Pack (matching the Lavender-Violet
/// reference UI): puffy multi-lobe 3D white clouds with soft purple drop shadows,
/// golden sun with 8 rounded triangular rays, deep purple crescent moon with
/// golden stars, 3D blue teardrop raindrops, and golden lightning bolts.
class RealisticWeatherVisual extends StatefulWidget {
  final int weatherCode;
  final double size;
  final bool? isDay;
  final bool animate;

  const RealisticWeatherVisual({
    super.key,
    required this.weatherCode,
    this.size = 100,
    this.isDay,
    this.animate = true,
  });

  @override
  State<RealisticWeatherVisual> createState() => _RealisticWeatherVisualState();
}

class _RealisticWeatherVisualState extends State<RealisticWeatherVisual>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimationState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncAnimationState();
  }

  void _syncAnimationState() {
    if (!mounted) return;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (widget.animate && _appActive && !disableAnimations && tickerEnabled) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final isDaytime = widget.isDay ??
                (DateTime.now().hour >= 6 && DateTime.now().hour < 19);
            final progress = _controller.value;
            final code = widget.weatherCode;

            return CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _ClayWeatherPainter(
                weatherCode: code,
                isDay: isDaytime,
                progress: progress,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ClayWeatherPainter extends CustomPainter {
  final int weatherCode;
  final bool isDay;
  final double progress;

  _ClayWeatherPainter({
    required this.weatherCode,
    required this.isDay,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final floatY = math.sin(progress * 2 * math.pi) * (h * 0.022);

    if (weatherCode == 0) {
      // Clear sky: 3D Sun with triangular rays (day) or 3D Purple Crescent Moon + Stars (night)
      if (isDay) {
        _drawClaySun(
          canvas,
          center: Offset(w * 0.5, h * 0.5 + floatY * 0.5),
          radius: w * 0.27,
          progress: progress,
        );
      } else {
        _drawClayMoonAndStars(
          canvas,
          center: Offset(w * 0.5, h * 0.5 + floatY * 0.5),
          radius: w * 0.30,
          progress: progress,
        );
      }
      return;
    }

    if (weatherCode >= 1 && weatherCode <= 3) {
      // Partly cloudy: Sun or Purple Moon peeking behind puffy 3D white cloud
      if (isDay) {
        _drawClaySun(
          canvas,
          center: Offset(w * 0.64, h * 0.34 - floatY * 0.4),
          radius: w * 0.21,
          progress: progress,
        );
      } else {
        _drawClayMoonAndStars(
          canvas,
          center: Offset(w * 0.66, h * 0.32 - floatY * 0.4),
          radius: w * 0.22,
          progress: progress,
        );
      }
      _drawPuffyClayCloud(
        canvas,
        rect: Rect.fromCenter(
          center: Offset(w * 0.46, h * 0.58 + floatY),
          width: w * 0.78,
          height: h * 0.48,
        ),
        warmInnerGlow: isDay,
      );
      return;
    }

    if (weatherCode == 45 || weatherCode == 48) {
      // Foggy / Mist: Sun/Moon + Puffy 3D Cloud + Wavy 3D Mist bars
      if (isDay) {
        _drawClaySun(
          canvas,
          center: Offset(w * 0.64, h * 0.28),
          radius: w * 0.18,
          progress: progress,
        );
      }
      _drawPuffyClayCloud(
        canvas,
        rect: Rect.fromCenter(
          center: Offset(w * 0.48, h * 0.48 + floatY),
          width: w * 0.76,
          height: h * 0.44,
        ),
        warmInnerGlow: isDay,
      );
      _drawWavyFogLines(
        canvas,
        center: Offset(w * 0.5, h * 0.80),
        width: w * 0.62,
        progress: progress,
      );
      return;
    }

    if (weatherCode >= 51 && weatherCode <= 67) {
      // Rain / Drizzle: Sun peeking top-right + Puffy 3D Cloud + 3D Blue Teardrops
      if (isDay) {
        _drawClaySun(
          canvas,
          center: Offset(w * 0.68, h * 0.28 - floatY * 0.3),
          radius: w * 0.18,
          progress: progress,
        );
      } else {
        _drawClayMoonAndStars(
          canvas,
          center: Offset(w * 0.68, h * 0.28 - floatY * 0.3),
          radius: w * 0.19,
          progress: progress,
        );
      }
      _drawPuffyClayCloud(
        canvas,
        rect: Rect.fromCenter(
          center: Offset(w * 0.46, h * 0.48 + floatY),
          width: w * 0.78,
          height: h * 0.46,
        ),
        warmInnerGlow: isDay,
      );
      _drawTeardropRain(
        canvas,
        area: Rect.fromLTWH(w * 0.22, h * 0.68, w * 0.52, h * 0.24),
        count: 3,
        progress: progress,
      );
      return;
    }

    if (weatherCode >= 80 && weatherCode <= 82) {
      // Heavy Showers: Puffy 3D Cloud + 4 3D Blue Teardrops
      _drawPuffyClayCloud(
        canvas,
        rect: Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.44 + floatY),
          width: w * 0.82,
          height: h * 0.48,
        ),
        warmInnerGlow: false,
      );
      _drawTeardropRain(
        canvas,
        area: Rect.fromLTWH(w * 0.18, h * 0.66, w * 0.62, h * 0.26),
        count: 4,
        progress: progress,
      );
      return;
    }

    if (weatherCode >= 95) {
      // Thunderstorm: Puffy 3D Cloud + 3D Golden Lightning Bolt + Teardrop Raindrops
      _drawPuffyClayCloud(
        canvas,
        rect: Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.42 + floatY),
          width: w * 0.82,
          height: h * 0.48,
        ),
        warmInnerGlow: true,
      );
      _drawClayLightning(
        canvas,
        center: Offset(w * 0.48, h * 0.73),
        size: Size(w * 0.24, h * 0.32),
        progress: progress,
      );
      _drawTeardropRain(
        canvas,
        area: Rect.fromLTWH(w * 0.20, h * 0.68, w * 0.60, h * 0.24),
        count: 2,
        progress: progress,
      );
      return;
    }

    // Default: Puffy 3D Cloud with Sun peeking
    if (isDay) {
      _drawClaySun(
        canvas,
        center: Offset(w * 0.65, h * 0.34),
        radius: w * 0.20,
        progress: progress,
      );
    }
    _drawPuffyClayCloud(
      canvas,
      rect: Rect.fromCenter(
        center: Offset(w * 0.48, h * 0.56 + floatY),
        width: w * 0.78,
        height: h * 0.48,
      ),
      warmInnerGlow: isDay,
    );
  }

  /// 3D Golden Sun with 8 rounded triangular rays around the circumference
  void _drawClaySun(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double progress,
  }) {
    // Soft warm amber aura
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFD54F).withValues(alpha: 0.45),
          const Color(0xFFFF9800).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.65));
    canvas.drawCircle(center, radius * 1.65, auraPaint);

    // 8 Rounded-Triangle Rays (slow rotation)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * 2 * math.pi * 0.25);

    const rayCount = 8;
    final innerR = radius * 1.10;
    final outerR = radius * 1.38;
    final halfBaseAngle = 0.16;

    for (int i = 0; i < rayCount; i++) {
      final angle = (i * 2 * math.pi) / rayCount;
      final tip = Offset(outerR * math.cos(angle), outerR * math.sin(angle));
      final baseLeft = Offset(
        innerR * math.cos(angle - halfBaseAngle),
        innerR * math.sin(angle - halfBaseAngle),
      );
      final baseRight = Offset(
        innerR * math.cos(angle + halfBaseAngle),
        innerR * math.sin(angle + halfBaseAngle),
      );

      final rayPath = Path()
        ..moveTo(baseLeft.dx, baseLeft.dy)
        ..quadraticBezierTo(tip.dx, tip.dy, baseRight.dx, baseRight.dy)
        ..close();

      final rayPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE57F), Color(0xFFFFA000)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: outerR));

      canvas.drawPath(rayPath, rayPaint);
    }
    canvas.restore();

    // Main 3D Sun Sphere
    final sphereRect = Rect.fromCircle(center: center, radius: radius);
    final sunShadow = Paint()
      ..color = const Color(0xFFFF8F00).withValues(alpha: 0.38)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center.translate(0, radius * 0.14), radius * 0.95, sunShadow);

    final sunPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.35, -0.38),
        radius: 0.88,
        colors: [
          Color(0xFFFFFDE7),
          Color(0xFFFFD54F),
          Color(0xFFFFA000),
          Color(0xFFFF6F00),
        ],
        stops: [0.0, 0.35, 0.78, 1.0],
      ).createShader(sphereRect);
    canvas.drawCircle(center, radius, sunPaint);
  }

  /// 3D Deep Violet-Purple Crescent Moon + 3D Golden Stars (matching reference icon pack)
  void _drawClayMoonAndStars(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double progress,
  }) {
    final outer = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    final cutter = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(center.dx + radius * 0.44, center.dy - radius * 0.24),
          radius: radius * 0.82,
        ),
      );
    final crescent = Path.combine(PathOperation.difference, outer, cutter);

    // Soft purple glow shadow
    final shadowPaint = Paint()
      ..color = const Color(0xFF4A18C9).withValues(alpha: 0.42)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawPath(crescent.shift(const Offset(0, 4)), shadowPaint);

    // 3D Purple-Violet Claymorphic Shader
    final moonPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.4, -0.4),
        radius: 1.0,
        colors: [
          Color(0xFFB388FF),
          Color(0xFF7C4DFF),
          Color(0xFF521CE0),
          Color(0xFF340D9E),
        ],
        stops: [0.0, 0.35, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(crescent, moonPaint);

    // Golden 3D Stars around the crescent
    _drawGoldenStar(
      canvas,
      Offset(center.dx - radius * 0.85, center.dy - radius * 0.55),
      radius * 0.22,
    );
    _drawGoldenStar(
      canvas,
      Offset(center.dx + radius * 0.72, center.dy - radius * 0.62),
      radius * 0.18,
    );
    _drawGoldenStar(
      canvas,
      Offset(center.dx + radius * 0.85, center.dy + radius * 0.20),
      radius * 0.15,
    );
  }

  void _drawGoldenStar(Canvas canvas, Offset center, double r) {
    final path = Path()
      ..moveTo(center.dx, center.dy - r)
      ..quadraticBezierTo(center.dx + r * 0.2, center.dy - r * 0.2, center.dx + r, center.dy)
      ..quadraticBezierTo(center.dx + r * 0.2, center.dx == 0 ? 0 : center.dy + r * 0.2, center.dx, center.dy + r)
      ..quadraticBezierTo(center.dx - r * 0.2, center.dy + r * 0.2, center.dx - r, center.dy)
      ..quadraticBezierTo(center.dx - r * 0.2, center.dy - r * 0.2, center.dx, center.dy - r)
      ..close();

    final starPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFFF59D), Color(0xFFFFB300)],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawPath(path, starPaint);
  }

  /// Puffy Multi-Lobe 3D Claymorphic White Cloud with Soft Purple Drop Shadow
  void _drawPuffyClayCloud(
    Canvas canvas, {
    required Rect rect,
    required bool warmInnerGlow,
  }) {
    final w = rect.width;
    final h = rect.height;
    final left = rect.left;
    final top = rect.top;

    // Build unified cloud silhouette for the soft purple drop shadow
    final baseRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + w * 0.04, top + h * 0.34, w * 0.92, h * 0.62),
      Radius.circular(h * 0.31),
    );
    final leftPuff = Offset(left + w * 0.28, top + h * 0.50);
    final leftRadius = w * 0.22;
    final centerPuff = Offset(left + w * 0.50, top + h * 0.38);
    final centerRadius = w * 0.27;
    final rightPuff = Offset(left + w * 0.72, top + h * 0.52);
    final rightRadius = w * 0.20;

    final silhouette = Path()
      ..addRRect(baseRRect)
      ..addOval(Rect.fromCircle(center: leftPuff, radius: leftRadius))
      ..addOval(Rect.fromCircle(center: centerPuff, radius: centerRadius))
      ..addOval(Rect.fromCircle(center: rightPuff, radius: rightRadius));

    // 1. Soft Purple Claymorphic Drop Shadow (matches reference image)
    final shadowPaint = Paint()
      ..color = const Color(0xFF4F26CA).withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11);
    canvas.drawPath(silhouette.shift(Offset(0, h * 0.14)), shadowPaint);

    // 2. Cloud Base Pill with 3D Lavender-White Gradient
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFFFFFF),
          const Color(0xFFF6F2FF),
          const Color(0xFFE4DCFF),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(rect);
    canvas.drawPath(silhouette, basePaint);

    // 3. Warm solar / lavender inner subsurface scattering glow
    if (warmInnerGlow) {
      final glowCenter = Offset(left + w * 0.62, top + h * 0.36);
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFE082).withValues(alpha: 0.45),
            const Color(0xFFFFB74D).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: w * 0.34));
      canvas.save();
      canvas.clipPath(silhouette);
      canvas.drawCircle(glowCenter, w * 0.34, glowPaint);
      canvas.restore();
    }

    // 4. Individual 3D Spherical Puff Lobes for Claymorphic Volume
    _drawCloudLobe(canvas, leftPuff, leftRadius);
    _drawCloudLobe(canvas, rightPuff, rightRadius);
    _drawCloudLobe(canvas, centerPuff, centerRadius);

    // 5. Crisp Top-Left Specular Rim Gleam
    final rimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawArc(
      Rect.fromCircle(center: centerPuff, radius: centerRadius * 0.92),
      math.pi * 1.05,
      math.pi * 0.65,
      false,
      rimPaint,
    );
  }

  void _drawCloudLobe(Canvas canvas, Offset center, double radius) {
    final lobePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.42),
        radius: 0.95,
        colors: [
          const Color(0xFFFFFFFF),
          const Color(0xFFF9F6FF),
          const Color(0xFFE5DEFF).withValues(alpha: 0.85),
        ],
        stops: const [0.0, 0.58, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, lobePaint);
  }

  /// 3D Glossy Blue Teardrop Raindrops (matching reference image)
  void _drawTeardropRain(
    Canvas canvas, {
    required Rect area,
    required int count,
    required double progress,
  }) {
    final stepX = area.width / (count + 0.5);
    final dropW = (area.width * 0.16).clamp(6.0, 13.0);
    final dropH = dropW * 1.45;

    for (int i = 0; i < count; i++) {
      final phase = (progress * 1.5 + i * 0.33) % 1.0;
      final cx = area.left + stepX * (i + 0.75) - phase * 3.0;
      final cy = area.top + phase * (area.height - dropH * 0.5);

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(0.22); // Slight diagonal tilt like reference image

      final dropPath = Path()
        ..moveTo(0, -dropH * 0.55)
        ..cubicTo(
          dropW * 0.65,
          -dropH * 0.05,
          dropW * 0.62,
          dropH * 0.45,
          0,
          dropH * 0.45,
        )
        ..cubicTo(
          -dropW * 0.62,
          dropH * 0.45,
          -dropW * 0.65,
          -dropH * 0.05,
          0,
          -dropH * 0.55,
        )
        ..close();

      final dropShadow = Paint()
        ..color = const Color(0xFF2962FF).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawPath(dropPath.shift(const Offset(0, 2)), dropShadow);

      final dropPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            Color(0xFF80D8FF),
            Color(0xFF2979FF),
            Color(0xFF1565C0),
          ],
        ).createShader(
          Rect.fromCenter(center: Offset.zero, width: dropW, height: dropH),
        );
      canvas.drawPath(dropPath, dropPaint);

      // Tiny specular highlight dot
      canvas.drawCircle(
        Offset(-dropW * 0.16, dropH * 0.08),
        dropW * 0.12,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
      canvas.restore();
    }
  }

  /// 3D Golden Lightning Bolt
  void _drawClayLightning(
    Canvas canvas, {
    required Offset center,
    required Size size,
    required double progress,
  }) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(center.dx + w * 0.12, center.dy - h * 0.50)
      ..lineTo(center.dx - w * 0.36, center.dy + h * 0.04)
      ..lineTo(center.dx - w * 0.02, center.dy + h * 0.04)
      ..lineTo(center.dx - w * 0.18, center.dy + h * 0.52)
      ..lineTo(center.dx + w * 0.38, center.dy - h * 0.08)
      ..lineTo(center.dx + w * 0.04, center.dy - h * 0.08)
      ..close();

    final glow = Paint()
      ..color = const Color(0xFFFFB300).withValues(alpha: 0.55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawPath(path, glow);

    final boltPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Color(0xFFFFF59D),
          Color(0xFFFFCA28),
          Color(0xFFFF8F00),
        ],
      ).createShader(Rect.fromCenter(center: center, width: w, height: h));
    canvas.drawPath(path, boltPaint);
  }

  /// 3D Wavy Mist Lines under Cloud
  void _drawWavyFogLines(
    Canvas canvas, {
    required Offset center,
    required double width,
    required double progress,
  }) {
    final paint = Paint()
      ..color = const Color(0xFFEDE7FF).withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;

    for (int row = 0; row < 2; row++) {
      final y = center.dy + row * 8.0;
      final shift = math.sin((progress + row * 0.4) * 2 * math.pi) * 4.0;
      final lineW = width * (row == 0 ? 1.0 : 0.75);
      final startX = center.dx - lineW / 2 + shift;

      final path = Path()
        ..moveTo(startX, y)
        ..quadraticBezierTo(
          startX + lineW * 0.25,
          y - 3.5,
          startX + lineW * 0.5,
          y,
        )
        ..quadraticBezierTo(
          startX + lineW * 0.75,
          y + 3.5,
          startX + lineW,
          y,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ClayWeatherPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.weatherCode != weatherCode ||
      oldDelegate.isDay != isDay;
}
