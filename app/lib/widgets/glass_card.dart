import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

enum AmbientWeatherState {
  clearDay,
  dawnDusk,
  clearNight,
  cloudy,
  rain,
  storm,
  severeHeat,
}

/// Debug-only override for visual verification across weather states, hazard states, and text scale.
/// Never active in release builds (!kDebugMode).
class DebugWeatherOverride {
  final AmbientWeatherState? ambientState;
  final bool? forceAllClear;
  final bool? forceActiveHazards;
  final double? textScaleOverride;

  const DebugWeatherOverride({
    this.ambientState,
    this.forceAllClear,
    this.forceActiveHazards,
    this.textScaleOverride,
  });

  int get weatherCode {
    switch (ambientState) {
      case AmbientWeatherState.clearDay:
      case AmbientWeatherState.dawnDusk:
      case AmbientWeatherState.clearNight:
      case AmbientWeatherState.severeHeat:
        return 0;
      case AmbientWeatherState.cloudy:
        return 2;
      case AmbientWeatherState.rain:
        return 63;
      case AmbientWeatherState.storm:
        return 95;
      case null:
        return 0;
    }
  }

  bool get isDay {
    return ambientState != AmbientWeatherState.clearNight;
  }

  double get temperature {
    if (ambientState == AmbientWeatherState.severeHeat) return 41.0;
    if (ambientState == AmbientWeatherState.rain) return 24.0;
    if (ambientState == AmbientWeatherState.storm) return 23.0;
    if (ambientState == AmbientWeatherState.clearNight) return 20.0;
    return 31.0;
  }
}

final ValueNotifier<DebugWeatherOverride?> debugWeatherNotifier =
    ValueNotifier<DebugWeatherOverride?>(null);

/// Replaces BackdropFilter blur with a solid semi-opaque fill and 1px hairline border.
/// Keeps the GlassCard class name and API so all existing call sites compile cleanly.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double opacity;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.s16),
    this.borderRadius = AppTheme.rCard,
    this.opacity = 0.92,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: padding,
      borderRadius: borderRadius,
      child: child,
    );
  }
}

/// Primary surface component: solid semi-opaque fill + 1px low-contrast hairline border (no blur, no drop shadow).
class AppSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.s16),
    this.margin,
    this.borderRadius = AppTheme.rCard,
    this.color,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fill = color ?? AppTheme.surfaceFill(context);
    final bColor = borderColor ?? AppTheme.borderColor(context);
    final bWidth = AppTheme.borderWidth(context);

    Widget content = Padding(
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      content = InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: content,
      );
    }

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: fill,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: bColor, width: bWidth),
        ),
        child: content,
      ),
    );
  }
}

/// Full-screen ambient weather gradient driven by weather code, is_day, temperature, and sunrise/sunset (+-45 min dawn/dusk window).
/// Cross-fades smoothly over ~600ms. High-contrast mode overrides with plain white/black.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  final int weatherCode;
  final bool isDay;
  final double temperature;
  final String? sunrise;
  final String? sunset;
  final bool quiet;

  const AmbientBackground({
    super.key,
    required this.child,
    this.weatherCode = 0,
    this.isDay = true,
    this.temperature = 28.0,
    this.sunrise,
    this.sunset,
    this.quiet = false,
  });

  static AmbientWeatherState resolveState({
    required int weatherCode,
    required bool isDay,
    required double temperature,
    String? sunrise,
    String? sunset,
  }) {
    if (kDebugMode && debugWeatherNotifier.value?.ambientState != null) {
      return debugWeatherNotifier.value!.ambientState!;
    }
    if (temperature >= 38.0) {
      return AmbientWeatherState.severeHeat;
    }
    if (weatherCode >= 95) {
      return AmbientWeatherState.storm;
    }
    if (weatherCode >= 51 && weatherCode <= 82) {
      return AmbientWeatherState.rain;
    }
    if (weatherCode >= 1 && weatherCode <= 48) {
      return AmbientWeatherState.cloudy;
    }
    if (_isWithinDawnOrDusk(sunrise, sunset)) {
      return AmbientWeatherState.dawnDusk;
    }
    return isDay ? AmbientWeatherState.clearDay : AmbientWeatherState.clearNight;
  }

  static bool _isWithinDawnOrDusk(String? sunriseIso, String? sunsetIso) {
    final now = DateTime.now();
    final nowMins = now.hour * 60 + now.minute;

    int? parseMinutes(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      try {
        if (raw.contains('T')) {
          final dt = DateTime.parse(raw);
          return dt.hour * 60 + dt.minute;
        }
        final parts = raw.split(':');
        if (parts.length >= 2) {
          return int.parse(parts[0]) * 60 + int.parse(parts[1]);
        }
      } catch (_) {}
      return null;
    }

    final srMins = parseMinutes(sunriseIso);
    final ssMins = parseMinutes(sunsetIso);
    if (srMins != null && (nowMins - srMins).abs() <= 45) return true;
    if (ssMins != null && (nowMins - ssMins).abs() <= 45) return true;
    return false;
  }

  static List<Color> paletteForState(
    AmbientWeatherState state, {
    required bool isDark,
    required bool quiet,
  }) {
    late final Color top;
    late final Color bottom;

    switch (state) {
      case AmbientWeatherState.clearDay:
        top = isDark ? const Color(0xFF231845) : const Color(0xFFA796FF);
        bottom = isDark ? const Color(0xFF140D2B) : const Color(0xFF7B5DF9);
        break;
      case AmbientWeatherState.dawnDusk:
        top = isDark ? const Color(0xFF281948) : const Color(0xFFB399FF);
        bottom = isDark ? const Color(0xFF160E2E) : const Color(0xFF835FF8);
        break;
      case AmbientWeatherState.clearNight:
        top = isDark ? const Color(0xFF171033) : const Color(0xFF7E68F2);
        bottom = isDark ? const Color(0xFF0E0921) : const Color(0xFF5A3FE0);
        break;
      case AmbientWeatherState.cloudy:
        top = isDark ? const Color(0xFF211740) : const Color(0xFFA292FF);
        bottom = isDark ? const Color(0xFF130D28) : const Color(0xFF775AF7);
        break;
      case AmbientWeatherState.rain:
        top = isDark ? const Color(0xFF1D163D) : const Color(0xFF968AFF);
        bottom = isDark ? const Color(0xFF110C26) : const Color(0xFF6B52F2);
        break;
      case AmbientWeatherState.storm:
        top = isDark ? const Color(0xFF1B123A) : const Color(0xFF8976FA);
        bottom = isDark ? const Color(0xFF0F0A24) : const Color(0xFF5D3FE8);
        break;
      case AmbientWeatherState.severeHeat:
        top = isDark ? const Color(0xFF2A1846) : const Color(0xFFB094FF);
        bottom = isDark ? const Color(0xFF170D2B) : const Color(0xFF8156F6);
        break;
    }

    if (quiet) {
      final neutralTop = isDark ? const Color(0xFF1C1436) : const Color(0xFFF6F3FF);
      final neutralBottom = isDark ? const Color(0xFF130E26) : const Color(0xFFE7E0FF);
      return [
        Color.lerp(top, neutralTop, 0.72)!,
        Color.lerp(bottom, neutralBottom, 0.75)!,
      ];
    }
    return [top, bottom];
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DebugWeatherOverride?>(
      valueListenable: debugWeatherNotifier,
      builder: (context, override, _) {
        final highContrast = AppTheme.isHighContrast(context);
        if (highContrast) {
          return Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: child,
          );
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final state = resolveState(
          weatherCode: weatherCode,
          isDay: isDay,
          temperature: temperature,
          sunrise: sunrise,
          sunset: sunset,
        );
        final colors = paletteForState(state, isDark: isDark, quiet: quiet);
        final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

        return AnimatedContainer(
          duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// Reusable section header (18sp bold, Devanagari-safe line height).
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppTheme.s8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTheme.sectionStyle.copyWith(
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Flat expandable row for Horizon-1 weather hazards (4dp severity strip, icon, localized title, single likelihood chip, 1-line action).
class StatusRow extends StatelessWidget {
  final String severity; // 'red' | 'orange'
  final String severityLabel;
  final IconData icon;
  final String title;
  final String likelihoodText;
  final String actionText;
  final String timeWindowLabel;
  final String timeWindowValue;
  final String expectedLabel;
  final String expectedValue;
  final bool isExpanded;
  final VoidCallback onToggle;

  const StatusRow({
    super.key,
    required this.severity,
    required this.severityLabel,
    required this.icon,
    required this.title,
    required this.likelihoodText,
    required this.actionText,
    required this.timeWindowLabel,
    required this.timeWindowValue,
    required this.expectedLabel,
    required this.expectedValue,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isRed = severity.toLowerCase() == 'red';
    final stripColor = isRed ? AppTheme.danger : AppTheme.warningText;
    final accentText = isRed
        ? AppTheme.semanticDangerText(context)
        : AppTheme.semanticWarningText(context);
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      button: true,
      expanded: isExpanded,
      label: '$severityLabel: $title, $likelihoodText. $actionText',
      child: AppSurface(
        padding: EdgeInsets.zero,
        borderRadius: AppTheme.rInput,
        onTap: onToggle,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.rInput),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 4dp severity strip
                Container(
                  width: 4,
                  color: stripColor,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.s12,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(icon, size: 20, color: accentText),
                            const SizedBox(width: AppTheme.s8),
                            Expanded(
                              child: Text(
                                '$severityLabel • $title',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary(context),
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTheme.s8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.s8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isRed
                                    ? AppTheme.danger.withValues(alpha: 0.14)
                                    : AppTheme.cautionAmber,
                                borderRadius: BorderRadius.circular(AppTheme.rPill),
                              ),
                              child: Text(
                                likelihoodText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isRed
                                      ? accentText
                                      : AppTheme.textPrimaryLight,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTheme.s4),
                            Icon(
                              isExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 20,
                              color: AppTheme.textSecondary(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.s4),
                        Text(
                          actionText,
                          maxLines: isExpanded ? 4 : 1,
                          overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary(context),
                            height: 1.4,
                          ),
                        ),
                        AnimatedSize(
                          duration: disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: isExpanded
                              ? Padding(
                                  padding: const EdgeInsets.only(top: AppTheme.s8),
                                  child: Wrap(
                                    spacing: AppTheme.s12,
                                    runSpacing: AppTheme.s4,
                                    children: [
                                      Text(
                                        '$timeWindowLabel: $timeWindowValue',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary(context),
                                        ),
                                      ),
                                      if (expectedValue.isNotEmpty)
                                        Text(
                                          '$expectedLabel: $expectedValue',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: accentText,
                                          ),
                                        ),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact metric tile for the 4-up detail grid on Home.
class MetricTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? expandedDetail;
  final String? semanticsLabel;

  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.expandedDetail,
    this.semanticsLabel,
  });

  @override
  State<MetricTile> createState() => _MetricTileState();
}

class _MetricTileState extends State<MetricTile> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    final hasDetail = widget.expandedDetail != null && widget.expandedDetail!.isNotEmpty;
    return Semantics(
      label: widget.semanticsLabel ?? '${widget.label}: ${widget.value}${hasDetail ? " (${widget.expandedDetail})" : ""}',
      button: hasDetail,
      child: AppSurface(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s12, vertical: 10),
        borderRadius: AppTheme.rInput,
        onTap: hasDetail ? () => setState(() => _showDetail = !_showDetail) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: AppTheme.primaryActionColor(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary(context),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.s4),
            Text(
              widget.value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary(context),
                height: 1.25,
              ),
            ),
            if (_showDetail && hasDetail)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  widget.expandedDetail!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChoiceChipOption<T> {
  final T value;
  final String label;

  const ChoiceChipOption({required this.value, required this.label});
}

/// Unified single-select ChoiceChipGroup (check + primary fill when selected, >= 48dp touch target).
class ChoiceChipGroup<T> extends StatelessWidget {
  final List<ChoiceChipOption<T>> options;
  final T selectedValue;
  final ValueChanged<T> onSelected;

  const ChoiceChipGroup({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final fillSelected = AppTheme.primaryButtonFill(context);
    final surfaceUnselected = AppTheme.surfaceFill(context);
    final borderCol = AppTheme.borderColor(context);
    final bWidth = AppTheme.borderWidth(context);

    return Wrap(
      spacing: AppTheme.s8,
      runSpacing: AppTheme.s8,
      children: options.map((opt) {
        final isSelected = opt.value == selectedValue;
        return Semantics(
          selected: isSelected,
          button: true,
          label: opt.label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.rChip),
              onTap: () => onSelected(opt.value),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.s16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? fillSelected : surfaceUnselected,
                    borderRadius: BorderRadius.circular(AppTheme.rChip),
                    border: Border.all(
                      color: isSelected ? fillSelected : borderCol,
                      width: isSelected ? 1.5 : bWidth,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected) ...[
                        const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          opt.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.textPrimary(context),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 56dp height Pill Primary Button (matching 3D "Get Start" pill button in reference UI).
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = AppTheme.primaryButtonFill(context);
    final isHc = AppTheme.isHighContrast(context);
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.rPill),
        gradient: isHc || onPressed == null
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF6E3BFF),
                  Color(0xFF521CE0),
                ],
              ),
        boxShadow: isHc || onPressed == null
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF4B18D6).withValues(alpha: 0.38),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isHc ? bg : Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rPill),
            side: isHc
                ? const BorderSide(color: Colors.black, width: 2)
                : BorderSide.none,
          ),
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: Colors.white),
                    const SizedBox(width: AppTheme.s8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 56dp height Secondary Outlined Pill Button.
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.primaryActionColor(context);
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: AppTheme.surfaceFill(context),
          side: BorderSide(
            color: fg.withValues(alpha: 0.45),
            width: AppTheme.isHighContrast(context) ? 2.0 : 1.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rPill),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: AppTheme.s8),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 56dp height Danger Button (#C62828).
class DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;

  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.rInput),
            ),
          ),
          onPressed: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: Colors.white),
                const SizedBox(width: AppTheme.s8),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final fg = AppTheme.semanticDangerText(context);
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: AppTheme.surfaceFill(context),
          side: BorderSide(color: fg, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.rInput),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: AppTheme.s8),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Accessible icon-only button with guaranteed >= 48x48dp hit target and Semantics label.
class IconAction extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;
  final Color? color;
  final Color? backgroundColor;

  const IconAction({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.color,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? AppTheme.textPrimary(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: backgroundColor ?? AppTheme.surfaceFill(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rInput),
          side: BorderSide(
            color: AppTheme.borderColor(context),
            width: AppTheme.borderWidth(context),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rInput),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 22, color: fg),
          ),
        ),
      ),
    );
  }
}

/// Protected SOS Hold-to-Confirm Button (~1.2s hold with progress ring + haptics + TalkBack custom Semantics action).
class HoldToConfirmButton extends StatefulWidget {
  final String label;
  final String holdHint;
  final String confirmDialogTitle;
  final String confirmDialogBody;
  final String confirmButtonLabel;
  final String cancelButtonLabel;
  final VoidCallback onConfirmed;

  const HoldToConfirmButton({
    super.key,
    this.label = 'SOS',
    required this.holdHint,
    required this.confirmDialogTitle,
    required this.confirmDialogBody,
    required this.confirmButtonLabel,
    required this.cancelButtonLabel,
    required this.onConfirmed,
  });

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _holdController;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_triggered) {
          _triggered = true;
          HapticFeedback.heavyImpact();
          widget.onConfirmed();
          _holdController.reset();
        }
      });
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  void _onHoldStart() {
    _triggered = false;
    HapticFeedback.mediumImpact();
    _holdController.forward(from: 0.0);
  }

  void _onHoldCancel() {
    if (_holdController.isAnimating && !_triggered) {
      _holdController.reverse();
    }
  }

  void _showAccessibilityConfirmDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.rCard),
        ),
        title: Row(
          children: [
            const Icon(Icons.shield_rounded, color: AppTheme.danger),
            const SizedBox(width: AppTheme.s8),
            Expanded(child: Text(widget.confirmDialogTitle)),
          ],
        ),
        content: Text(widget.confirmDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(widget.cancelButtonLabel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(120, 48),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onConfirmed();
            },
            child: Text(widget.confirmButtonLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.label}. ${widget.holdHint}',
      customSemanticsActions: {
        CustomSemanticsAction(label: widget.confirmDialogTitle):
            _showAccessibilityConfirmDialog,
      },
      child: GestureDetector(
        onTapDown: (_) => _onHoldStart(),
        onTapUp: (_) {
          if (!_triggered) {
            _onHoldCancel();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(widget.holdHint),
                duration: const Duration(milliseconds: 1800),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onTapCancel: _onHoldCancel,
        child: AnimatedBuilder(
          animation: _holdController,
          builder: (context, _) {
            final progress = _holdController.value;
            return ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 72),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                  border: Border.all(
                    color: progress > 0 ? Colors.white : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (progress > 0)
                            CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 2.5,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                          const Icon(
                            Icons.shield_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Slim 1-level InfoBanner.
class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const InfoBanner({
    super.key,
    required this.icon,
    required this.text,
    this.iconColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tint = iconColor ?? AppTheme.primaryActionColor(context);
    return AppSurface(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.s12, vertical: 8),
      borderRadius: AppTheme.rInput,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: AppTheme.s8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
                height: 1.35,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppTheme.s8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Standardized bottom sheet wrapper with 20dp top radius, drag handle, title, and shadow.
class SheetScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const SheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = AppTheme.isHighContrast(context)
        ? Colors.white
        : (isDark ? AppTheme.surfaceCard : Colors.white);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.rSheet),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: AppTheme.s16,
            right: AppTheme.s16,
            top: AppTheme.s12,
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppTheme.s16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textSecondary(context).withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(AppTheme.rPill),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.s12),
                Text(
                  title,
                  style: AppTheme.sectionStyle.copyWith(
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.s4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: AppTheme.textSecondary(context),
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: AppTheme.s12),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle skeleton placeholder for loading weather/alerts.
class SkeletonBox extends StatelessWidget {
  final double height;
  final double? width;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.height,
    this.width,
    this.borderRadius = AppTheme.rInput,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
