import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';

class LanguageScreen extends StatefulWidget {
  final VoidCallback onLanguageSelected;
  final VoidCallback? onBack;

  const LanguageScreen({
    super.key,
    required this.onLanguageSelected,
    this.onBack,
  });

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selected = 'hi';

  @override
  void initState() {
    super.initState();
    StorageService.getLanguage().then((lang) {
      if (mounted) setState(() => _selected = lang);
    });
  }

  void _choose(String code) async {
    setState(() => _selected = code);
    await StorageService.setLanguage(code);
    widget.onLanguageSelected();
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final accent = AppTheme.primaryActionColor(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        quiet: true,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onBack != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconAction(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: _selected == 'en' ? 'Back' : 'वापस जाएं',
                      onPressed: widget.onBack!,
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.s24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppTheme.s16),
                      Center(
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.wb_sunny_rounded, size: 42, color: accent),
                        ),
                      ),
                      const SizedBox(height: AppTheme.s16),
                      Center(
                        child: Text(
                          AppStrings.get('app_title', _selected),
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          AppStrings.get('tagline', _selected),
                          textAlign: TextAlign.center,
                          style: AppTheme.bodyStyle.copyWith(color: textSecondary),
                        ),
                      ),
                      const SizedBox(height: AppTheme.s32),
                      Text(
                        AppStrings.get('select_language', _selected),
                        style: AppTheme.sectionStyle.copyWith(color: textPrimary),
                      ),
                      const SizedBox(height: AppTheme.s12),
                      _LanguageCard(
                        title: 'हिंदी',
                        subtitle: 'सम्पूर्ण जानकारी हिंदी में उपलब्ध',
                        code: 'hi',
                        isSelected: _selected == 'hi',
                        onTap: () => _choose('hi'),
                      ),
                      const SizedBox(height: AppTheme.s12),
                      _LanguageCard(
                        title: 'English',
                        subtitle: 'Weather forecasts, alerts and advisory in English',
                        code: 'en',
                        isSelected: _selected == 'en',
                        onTap: () => _choose('en'),
                      ),
                      const SizedBox(height: AppTheme.s24),
                      PrimaryButton(
                        label: AppStrings.get('continue_btn', _selected),
                        icon: Icons.arrow_forward_rounded,
                        onPressed: widget.onLanguageSelected,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String code;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.title,
    required this.subtitle,
    required this.code,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primaryActionColor(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);

    return AppSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      borderColor: isSelected ? accent : AppTheme.borderColor(context),
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: isSelected ? accent : textSecondary,
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? accent : textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTheme.labelStyle.copyWith(color: textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
