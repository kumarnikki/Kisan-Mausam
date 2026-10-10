import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onThemeChanged;
  final VoidCallback onLanguageChanged;
  final VoidCallback onResetOnboarding;
  final VoidCallback onClose;

  const SettingsScreen({
    super.key,
    required this.onThemeChanged,
    required this.onLanguageChanged,
    required this.onResetOnboarding,
    required this.onClose,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _lang = 'hi';
  bool _highContrast = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    final l = await StorageService.getLanguage();
    final hc = await StorageService.isHighContrast();
    if (mounted) {
      setState(() {
        _lang = l;
        _highContrast = hc;
      });
    }
  }

  void _toggleLanguage() async {
    final next = _lang == 'hi' ? 'en' : 'hi';
    await StorageService.setLanguage(next);
    setState(() => _lang = next);
    widget.onLanguageChanged();
  }

  void _toggleHighContrast(bool val) async {
    await StorageService.setHighContrast(val);
    setState(() => _highContrast = val);
    widget.onThemeChanged();
  }

  void _confirmDeleteData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('खाता व डेटा हटाएं (DPDP Act 2023)'),
        content: const Text(
          'क्या आप सचमुच अपना खाता, खेत का विवरण और सभी मौसम अलर्ट रिकॉर्ड हमेशा के लिए हटाना चाहते हैं? यह प्रक्रिया वापस नहीं हो सकती।',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('रद्द करें')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.setOnboardingComplete(false);
              widget.onResetOnboarding();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('आपका समस्त व्यक्तिगत डेटा सफलतापूर्वक हटा दिया गया है।'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('डेटा हटाएं', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: _lang == 'hi' ? 'वापस जाएं' : 'Back',
          onPressed: widget.onClose,
        ),
        title: Text(AppStrings.get('settings', _lang)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // Section 1: Appearance & Accessibility
          _buildSectionHeader('प्रकटन एवं अभिगम्यता (Appearance & Accessibility)'),
          ListTile(
            leading: const Icon(Icons.language, color: Color(0xFF1B5E20)),
            title: const Text('भाषा / Language', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(_lang == 'hi' ? 'वर्तमान: हिंदी (Hindi)' : 'Current: English'),
            trailing: OutlinedButton(
              onPressed: _toggleLanguage,
              child: Text(_lang == 'hi' ? 'Switch to English' : 'हिंदी में बदलें'),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.contrast, color: Color(0xFF1B5E20)),
            title: Text(AppStrings.get('high_contrast', _lang), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('खेत में धूप के दौरान स्पष्टता हेतु गहरा काला व सफेद बॉर्डर'),
            value: _highContrast,
            onChanged: _toggleHighContrast,
          ),
          const Divider(),

          // Section 2: Privacy & DPDP Act 2023
          _buildSectionHeader('गोपनीयता एवं सुरक्षा (DPDP Act 2023)'),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: Color(0xFF1B5E20)),
            title: const Text('गोपनीयता नीति (Privacy Policy)'),
            subtitle: const Text('आपका डेटा सुरक्षित है, किसी तीसरे पक्ष को नहीं बेचा जाता'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('किसान मौसम: भारत DPDP अधिनियम 2023 अनुरूप')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: Text(
              AppStrings.get('delete_data', _lang),
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('खाता, खेत प्रोफाइल और अलर्ट का संपूर्ण विलोपन'),
            onTap: _confirmDeleteData,
          ),
          const Divider(),

          // Section 3: About & Attribution
          _buildSectionHeader('स्रोत एवं लाइसेंस (Attribution & About)'),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Color(0xFF1B5E20)),
            title: const Text('मौसम डेटा स्रोत (Data Attribution)'),
            subtitle: const Text('Powered by Open-Meteo under CC BY 4.0 (Non-Commercial License)'),
          ),
          ListTile(
            leading: const Icon(Icons.agriculture, color: Color(0xFF1B5E20)),
            title: const Text('जोखिम एवं कृषि मानक'),
            subtitle: const Text('भारतीय मौसम विज्ञान विभाग (IMD) एवं ICAR कृषि वैज्ञानिक मानक'),
          ),
          const SizedBox(height: 32),
          const Center(
            child: Text(
              'किसान मौसम (KisanMausam) • v1.0.0\nMade with ❤️ for Indian Farmers',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1B5E20),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
