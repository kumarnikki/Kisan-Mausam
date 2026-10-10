import 'dart:ui';
import 'package:flutter/material.dart';

/// A modern, reusable glassmorphic container with frosted blur,
/// ambient rim lighting, and smooth drop shadows.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double blur;
  final Color? tintColor;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Border? border;
  final List<BoxShadow>? shadows;
  final Gradient? gradient;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24.0,
    this.blur = 16.0,
    this.tintColor,
    this.opacity = 0.82,
    this.padding = const EdgeInsets.all(16.0),
    this.margin,
    this.border,
    this.shadows,
    this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorder = border ??
        Border.all(
          color: Colors.white.withValues(alpha: 0.65),
          width: 1.2,
        );

    final effectiveShadows = shadows ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: (tintColor ?? const Color(0xFF1B5E20)).withValues(alpha: 0.06),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ];

    final effectiveGradient = gradient ??
        LinearGradient(
          colors: [
            (tintColor ?? Colors.white).withValues(alpha: opacity),
            (tintColor ?? Colors.white).withValues(alpha: (opacity * 0.75).clamp(0.0, 1.0)),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

    Widget content = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: effectiveShadows,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: effectiveGradient,
              borderRadius: BorderRadius.circular(borderRadius),
              border: effectiveBorder,
            ),
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: content,
        ),
      );
    }

    return content;
  }
}
