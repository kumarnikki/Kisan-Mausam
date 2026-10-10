import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/storage_service.dart';

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
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: _lang == 'hi' ? 'वापस जाएं' : 'Back',
                onPressed: widget.onBack,
              )
            : null,
        title: Text(AppStrings.get('consent_title', _lang)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1B5E20).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: Color(0xFF1B5E20), size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        AppStrings.get('consent_subtitle', _lang),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: [
                    _ConsentSwitchTile(
                      icon: Icons.location_on,
                      title: AppStrings.get('consent_location', _lang),
                      subtitle: 'खेत का पिन या गाँव चयन ताकि फ़ोन बंद होने पर भी चेतावनी सही मिले',
                      value: _consentLocation,
                      onChanged: (v) => setState(() => _consentLocation = v),
                    ),
                    const Divider(),
                    _ConsentSwitchTile(
                      icon: Icons.sms,
                      title: AppStrings.get('consent_sms', _lang),
                      subtitle: 'आपातकालीन चेतावनी सीधे SMS पर (TRAI DLT पंजीकृत)',
                      value: _consentSms,
                      onChanged: (v) => setState(() => _consentSms = v),
                    ),
                    const Divider(),
                    _ConsentSwitchTile(
                      icon: Icons.notifications_active,
                      title: AppStrings.get('consent_notifications', _lang),
                      subtitle: 'खराब मौसम से पहले मोबाइल पर अलर्ट सूचना',
                      value: _consentNotifications,
                      onChanged: (v) => setState(() => _consentNotifications = v),
                    ),
                    const Divider(),
                    _ConsentSwitchTile(
                      icon: Icons.record_voice_over,
                      title: AppStrings.get('consent_ai_logging', _lang),
                      subtitle: 'कृषि सलाहकार से बातचीत का इतिहास (डेटा कभी बेचा या साझा नहीं किया जाता)',
                      value: _consentAiLogging,
                      onChanged: (v) => setState(() => _consentAiLogging = v),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => widget.onConsentAccepted(),
                child: Text(AppStrings.get('accept_and_continue', _lang)),
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
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      secondary: CircleAvatar(
        backgroundColor: const Color(0xFF1B5E20).withValues(alpha: 0.12),
        child: Icon(icon, color: const Color(0xFF1B5E20)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      value: value,
      activeThumbColor: const Color(0xFF1B5E20),
      onChanged: onChanged,
    );
  }
}
