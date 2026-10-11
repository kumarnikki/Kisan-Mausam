import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Renders a realistic, multi-layered 3D-styled animated weather visual
/// with volumetric shadows, specular highlights, and ambient light auras.
class RealisticWeatherVisual extends StatefulWidget {
  final int weatherCode;
  final double size;
  final bool? isDay;

  const RealisticWeatherVisual({
    super.key,
    required this.weatherCode,
    this.size = 100,
    this.isDay,
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
    )..repeat();
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
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_appActive && !disableAnimations && tickerEnabled) {
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
            final isDaytime = widget.isDay ?? (DateTime.now().hour >= 6 && DateTime.now().hour < 19);
            final progress = _controller.value;
            final code = widget.weatherCode;

            if (code == 0) {
              // Clear Sky (Daytime 3D Sun vs Nighttime 3D Moon with stars)
              return isDaytime ? _build3DSun(progress) : _build3DMoon(progress);
            } else if (code >= 1 && code <= 3) {
              // Partly Cloudy (Day sun behind cloud vs Night moon behind cloud)
              return isDaytime ? _buildPartlyCloudy(progress) : _buildPartlyCloudyNight(progress);
            } else if (code == 45 || code == 48) {
              // Foggy / Mist
              return _buildFoggy(progress, isNight: !isDaytime);
            } else if (code >= 51 && code <= 65) {
              // Rain
              return _buildRain(progress, isNight: !isDaytime);
            } else if (code >= 80 && code <= 82) {
              // Showers
              return _buildShowers(progress, isNight: !isDaytime);
            } else if (code >= 95) {
              // Thunderstorm / Hail
              return _buildThunderstorm(progress, isNight: !isDaytime);
            } else {
              // Fair weather cloud
              return _buildDefaultCloud(progress, isNight: !isDaytime);
            }
          },
        ),
      ),
    );
  }

  // 1. 3D Sun with rotating rays and multi-stop spherical lighting
  Widget _build3DSun(double progress) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulsing Corona Glow Aura
        Container(
          width: widget.size * 0.95,
          height: widget.size * 0.95,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFFFD54F).withValues(alpha: 0.5 + 0.15 * math.sin(progress * 2 * math.pi)),
                const Color(0xFFFF9800).withValues(alpha: 0.2),
                Colors.transparent,
              ],
              stops: const [0.3, 0.65, 1.0],
            ),
          ),
        ),

        // Rotating Sunbeam Ray Corona
        Transform.rotate(
          angle: progress * 2 * math.pi,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _SunRaysPainter(color: const Color(0xFFFFE082).withValues(alpha: 0.7)),
          ),
        ),

        // 3D Volumetric Core Sphere
        Container(
          width: widget.size * 0.54,
          height: widget.size * 0.54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.35, -0.35),
              radius: 0.8,
              colors: [
                Color(0xFFFFFDE7), // Top-left specular gleam
                Color(0xFFFFEE58), // Radiant gold
                Color(0xFFFFA000), // Rich amber
                Color(0xFFE65100), // Deep solar edge
              ],
              stops: [0.0, 0.35, 0.75, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF8F00).withValues(alpha: 0.6),
                blurRadius: 18,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 1b. 3D Crescent Moon with Twinkling Stars & Celestial Aurora
  Widget _build3DMoon(double progress) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulsing Indigo-Silver Lunar Aurora Glow
        Container(
          width: widget.size * 0.96,
          height: widget.size * 0.96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF818CF8).withValues(alpha: 0.35 + 0.12 * math.sin(progress * 2 * math.pi)),
                const Color(0xFF38BDF8).withValues(alpha: 0.15),
                Colors.transparent,
              ],
              stops: const [0.35, 0.7, 1.0],
            ),
          ),
        ),

        // Twinkling Starfield with Diamond Sparkles
        CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _StarsPainter(progress: progress),
        ),

        // 3D Crescent Moon with Volumetric Lighting
        CustomPaint(
          size: Size(widget.size * 0.72, widget.size * 0.72),
          painter: _CrescentMoonPainter(progress: progress),
        ),
      ],
    );
  }

  // 2. Partly Cloudy: 3D Sun behind fluffy 3D Cloud
  Widget _buildPartlyCloudy(double progress) {
    final floatY = math.sin(progress * 2 * math.pi) * 3;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Sun peeking top right
        Positioned(
          top: widget.size * 0.08,
          right: widget.size * 0.08,
          child: Container(
            width: widget.size * 0.44,
            height: widget.size * 0.44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.3),
                colors: [
                  Color(0xFFFFF9C4),
                  Color(0xFFFFCA28),
                  Color(0xFFF57C00),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.5),
                  blurRadius: 14,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),

        // Front 3D Cloud floating
        Positioned(
          bottom: widget.size * 0.12 + floatY,
          left: widget.size * 0.06,
          child: _buildCloudBody(
            width: widget.size * 0.76,
            height: widget.size * 0.46,
            baseColor: const Color(0xFFF5F7FA),
            shadeColor: const Color(0xFFB0BEC5),
          ),
        ),
      ],
    );
  }

  // 2b. Partly Cloudy Night: 3D Moon peeking behind dark twilight cloud
  Widget _buildPartlyCloudyNight(double progress) {
    final floatY = math.sin(progress * 2 * math.pi) * 3;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Twinkling Starfield
        CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _StarsPainter(progress: progress),
        ),

        // Crescent Moon peeking top right
        Positioned(
          top: widget.size * 0.06,
          right: widget.size * 0.06,
          child: CustomPaint(
            size: Size(widget.size * 0.48, widget.size * 0.48),
            painter: _CrescentMoonPainter(progress: progress),
          ),
        ),

        // Front 3D Night Cloud floating
        Positioned(
          bottom: widget.size * 0.12 + floatY,
          left: widget.size * 0.06,
          child: _buildCloudBody(
            width: widget.size * 0.76,
            height: widget.size * 0.46,
            baseColor: const Color(0xFF475569),
            shadeColor: const Color(0xFF1E293B),
            isNight: true,
          ),
        ),
      ],
    );
  }

  // 3. 3D Cloud with Raindrops
  Widget _buildRain(double progress, {bool isNight = false}) {
    final floatY = math.sin(progress * 2 * math.pi) * 2;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Stormy Cloud Body
        Positioned(
          top: widget.size * 0.12 + floatY,
          child: _buildCloudBody(
            width: widget.size * 0.78,
            height: widget.size * 0.48,
            baseColor: isNight ? const Color(0xFF334155) : const Color(0xFFECEFF1),
            shadeColor: isNight ? const Color(0xFF0F172A) : const Color(0xFF78909C),
            isNight: isNight,
          ),
        ),
        // Animated Raindrops
        Positioned(
          bottom: widget.size * 0.08,
          child: CustomPaint(
            size: Size(widget.size * 0.65, widget.size * 0.32),
            painter: _RaindropsPainter(progress: progress),
          ),
        ),
      ],
    );
  }

  // 4. Heavy Showers with Cyan glow
  Widget _buildShowers(double progress, {bool isNight = false}) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: widget.size * 0.10,
          child: _buildCloudBody(
            width: widget.size * 0.82,
            height: widget.size * 0.50,
            baseColor: isNight ? const Color(0xFF1E293B) : const Color(0xFFCFD8DC),
            shadeColor: isNight ? const Color(0xFF0F172A) : const Color(0xFF546E7A),
            isNight: isNight,
          ),
        ),
        Positioned(
          bottom: widget.size * 0.05,
          child: CustomPaint(
            size: Size(widget.size * 0.7, widget.size * 0.38),
            painter: _RaindropsPainter(progress: progress, isHeavy: true),
          ),
        ),
      ],
    );
  }

  // 5. Thunderstorm with pulsing golden-cyan lightning
  Widget _buildThunderstorm(double progress, {bool isNight = false}) {
    final lightningFlash = (math.sin(progress * 8 * math.pi) > 0.7) ? 1.0 : 0.2;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Dark Thunder Cloud
        Positioned(
          top: widget.size * 0.08,
          child: _buildCloudBody(
            width: widget.size * 0.82,
            height: widget.size * 0.50,
            baseColor: isNight ? const Color(0xFF1E1B4B) : const Color(0xFF90A4AE),
            shadeColor: isNight ? const Color(0xFF0F0E2A) : const Color(0xFF37474F),
            isNight: isNight,
          ),
        ),
        // Animated Lightning Bolt
        Positioned(
          bottom: widget.size * 0.06,
          child: Opacity(
            opacity: lightningFlash,
            child: Icon(
              Icons.flash_on,
              size: widget.size * 0.42,
              color: const Color(0xFFFFD600),
            ),
          ),
        ),
      ],
    );
  }

  // 6. Foggy Ethereal Mist
  Widget _buildFoggy(double progress, {bool isNight = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final shift = math.sin((progress + i * 0.3) * 2 * math.pi) * 8;
        return Transform.translate(
          offset: Offset(shift, 0),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            width: widget.size * (0.8 - i * 0.12),
            height: widget.size * 0.11,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: isNight
                    ? [
                        Colors.white.withValues(alpha: 0.05),
                        const Color(0xFF94A3B8).withValues(alpha: 0.5),
                        Colors.white.withValues(alpha: 0.05),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.1),
                        Colors.white.withValues(alpha: 0.75),
                        Colors.white.withValues(alpha: 0.1),
                      ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // Default Cloud
  Widget _buildDefaultCloud(double progress, {bool isNight = false}) {
    return Center(
      child: _buildCloudBody(
        width: widget.size * 0.8,
        height: widget.size * 0.5,
        baseColor: isNight ? const Color(0xFF334155) : const Color(0xFFF5F5F5),
        shadeColor: isNight ? const Color(0xFF1E293B) : const Color(0xFFBDBDBD),
        isNight: isNight,
      ),
    );
  }

  // Reusable 3D Volumetric Cloud Component
  Widget _buildCloudBody({
    required double width,
    required double height,
    required Color baseColor,
    required Color shadeColor,
    bool isNight = false,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor,
            shadeColor,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: shadeColor.withValues(alpha: isNight ? 0.6 : 0.45),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Specular highlights on top puffs
          Positioned(
            left: width * 0.2,
            top: -height * 0.35,
            child: Container(
              width: width * 0.45,
              height: width * 0.45,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isNight ? const Color(0xFFE2E8F0) : Colors.white).withValues(alpha: isNight ? 0.45 : 0.9),
                    baseColor.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for rotating radial sun rays
class _SunRaysPainter extends CustomPainter {
  final Color color;
  _SunRaysPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    const count = 12;
    final innerR = size.width * 0.34;
    final outerR = size.width * 0.46;

    for (int i = 0; i < count; i++) {
      final angle = (i * 2 * math.pi) / count;
      final start = Offset(
        center.dx + innerR * math.cos(angle),
        center.dy + innerR * math.sin(angle),
      );
      final end = Offset(
        center.dx + outerR * math.cos(angle),
        center.dy + outerR * math.sin(angle),
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for animated falling rain drops
class _RaindropsPainter extends CustomPainter {
  final double progress;
  final bool isHeavy;

  _RaindropsPainter({required this.progress, this.isHeavy = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isHeavy ? const Color(0xFF40C4FF) : const Color(0xFF80D8FF)
      ..strokeWidth = isHeavy ? 2.8 : 2.0
      ..strokeCap = StrokeCap.round;

    final count = isHeavy ? 6 : 4;
    final stepX = size.width / (count + 1);

    for (int i = 0; i < count; i++) {
      final dropProgress = (progress + (i * 0.25)) % 1.0;
      final x = stepX * (i + 1);
      final y = size.height * dropProgress;

      canvas.drawLine(
        Offset(x - 2, y),
        Offset(x + 2, y + 10),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RaindropsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Custom painter for a volumetric 3D Crescent Moon with craters and rim lighting
class _CrescentMoonPainter extends CustomPainter {
  final double progress;
  _CrescentMoonPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.48, h * 0.5);
    final radius = w * 0.42;

    // Create Crescent shape using Path difference
    final outerPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));

    final innerCutter = Path()
      ..addOval(Rect.fromCircle(
        center: Offset(center.dx + radius * 0.52, center.dy - radius * 0.22),
        radius: radius * 0.88,
      ));

    final moonPath = Path.combine(PathOperation.difference, outerPath, innerCutter);

    // Glowing moonlight halo shadow
    final glowPaint = Paint()
      ..color = const Color(0xFFBAE6FD).withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(moonPath, glowPaint);

    // Volumetric 3D Shader for the Moon surface
    final shaderRect = Rect.fromCircle(center: center, radius: radius);
    final moonPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.6, -0.6),
        radius: 0.9,
        colors: [
          Color(0xFFFFFFFF), // Specular gleam
          Color(0xFFF1F5F9), // Pearl silver
          Color(0xFFCBD5E1), // Lunar dust
          Color(0xFF94A3B8), // Crater shadow
          Color(0xFF475569), // Edge shadow
        ],
        stops: [0.0, 0.3, 0.65, 0.85, 1.0],
      ).createShader(shaderRect);

    canvas.drawPath(moonPath, moonPaint);

    // Subtle Lunar Crater Details (soft translucent indentations)
    canvas.save();
    canvas.clipPath(moonPath);
    final craterPaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final craterHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Crater 1
    final c1 = Offset(center.dx - radius * 0.22, center.dy + radius * 0.15);
    canvas.drawCircle(c1, radius * 0.14, craterPaint);
    canvas.drawCircle(Offset(c1.dx - 1, c1.dy - 1), radius * 0.12, craterHighlight);

    // Crater 2
    final c2 = Offset(center.dx - radius * 0.12, center.dy - radius * 0.22);
    canvas.drawCircle(c2, radius * 0.09, craterPaint);

    // Crater 3
    final c3 = Offset(center.dx - radius * 0.35, center.dy - radius * 0.05);
    canvas.drawCircle(c3, radius * 0.07, craterPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CrescentMoonPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Custom painter for twinkling stars with diamond sparkle rays
class _StarsPainter extends CustomPainter {
  final double progress;
  _StarsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Star positions (dx, dy, size, twinklePhase)
    final stars = [
      [w * 0.16, h * 0.22, 3.2, 0.0],
      [w * 0.82, h * 0.18, 2.5, 0.3],
      [w * 0.26, h * 0.78, 2.8, 0.6],
      [w * 0.76, h * 0.82, 3.5, 0.8],
      [w * 0.08, h * 0.55, 2.0, 0.45],
      [w * 0.88, h * 0.48, 2.2, 0.15],
      [w * 0.48, h * 0.08, 2.8, 0.7],
    ];

    for (final s in stars) {
      final x = s[0];
      final y = s[1];
      final starSize = s[2];
      final phase = s[3];

      // Twinkle pulsation
      final opacity = (0.35 + 0.65 * ((math.sin((progress + phase) * 2 * math.pi) + 1) / 2)).clamp(0.1, 1.0);

      final starPaint = Paint()
        ..color = const Color(0xFFF8FAFC).withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      // Center glowing dot
      canvas.drawCircle(Offset(x, y), starSize * 0.6, starPaint);

      // Four-point diamond rays
      final rayLength = starSize * 2.2;
      final rayPaint = Paint()
        ..color = const Color(0xFFE0F2FE).withValues(alpha: opacity * 0.85)
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(Offset(x - rayLength, y), Offset(x + rayLength, y), rayPaint);
      canvas.drawLine(Offset(x, y - rayLength), Offset(x, y + rayLength), rayPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
