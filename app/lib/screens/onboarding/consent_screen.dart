import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';

class ConsentScreen extends StatefulWidget {
  final VoidCallback onConsentAccepted;
  final VoidCallback? onBack;

  const ConsentScreen({
    super.key,
    required this.onConsentAccepted,
    this.onBack,
  });

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _consentLocation = true;
  bool _consentSms = true;
  bool _consentNotifications = true;
  bool _consentAiLogging = false; // Off by default as required
  String _lang = 'hi';

  @override
  void initState() {
    super.initState();
    StorageService.getLanguage().then((l) {
      if (mounted) setState(() => _lang = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppTheme.textPrimary(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        quiet: true,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
                child: Row(
                  children: [
                    if (widget.onBack != null)
                      IconAction(
                        icon: Icons.arrow_back_rounded,
                        semanticLabel: _lang == 'hi' ? 'वापस जाएं' : 'Back',
                        onPressed: widget.onBack!,
                      )
                    else
                      const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppStrings.get('consent_title', _lang),
                        style: AppTheme.titleStyle.copyWith(color: textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.screenPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InfoBanner(
                        icon: Icons.security_rounded,
                        text: AppStrings.get('consent_subtitle', _lang),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: AppSurface(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: ListView(
                            children: [
                              _ConsentSwitchTile(
                                icon: Icons.location_on_rounded,
                                title: AppStrings.get('consent_location', _lang),
                                subtitle: _lang == 'en'
                                    ? 'Farm location for accurate warnings even when app is closed'
                                    : 'खेत का स्थान ताकि ऐप बंद होने पर भी सटीक चेतावनी मिले',
                                value: _consentLocation,
                                onChanged: (v) => setState(() => _consentLocation = v),
                              ),
                              const Divider(height: 1),
                              _ConsentSwitchTile(
                                icon: Icons.sms_rounded,
                                title: AppStrings.get('consent_sms', _lang),
                                subtitle: _lang == 'en'
                                    ? 'Critical warnings via direct SMS (TRAI DLT registered)'
                                    : 'आपातकालीन चेतावनी सीधे SMS पर (TRAI DLT पंजीकृत)',
                                value: _consentSms,
                                onChanged: (v) => setState(() => _consentSms = v),
                              ),
                              const Divider(height: 1),
                              _ConsentSwitchTile(
                                icon: Icons.notifications_active_rounded,
                                title: AppStrings.get('consent_notifications', _lang),
                                subtitle: _lang == 'en'
                                    ? 'Early notification alerts on device before severe weather'
                                    : 'खराब मौसम से पहले मोबाइल पर अलर्ट सूचना',
                                value: _consentNotifications,
                                onChanged: (v) => setState(() => _consentNotifications = v),
                              ),
                              const Divider(height: 1),
                              _ConsentSwitchTile(
                                icon: Icons.record_voice_over_rounded,
                                title: AppStrings.get('consent_ai_logging', _lang),
                                subtitle: _lang == 'en'
                                    ? 'Agri Assistant discussion history (never sold or shared)'
                                    : 'कृषि सलाहकार से बातचीत का इतिहास (डेटा कभी बेचा या साझा नहीं किया जाता)',
                                value: _consentAiLogging,
                                onChanged: (v) => setState(() => _consentAiLogging = v),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: AppStrings.get('accept_and_continue', _lang),
                        icon: Icons.check_rounded,
                        onPressed: widget.onConsentAccepted,
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

class _ConsentSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ConsentSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primaryActionColor(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);

    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      secondary: CircleAvatar(
        backgroundColor: accent.withValues(alpha: 0.12),
        child: Icon(icon, color: accent),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: AppTheme.labelStyle.copyWith(color: textSecondary, fontSize: 12.5),
      ),
      value: value,
      activeTrackColor: AppTheme.primaryGreen,
      onChanged: onChanged,
    );
  }
}
