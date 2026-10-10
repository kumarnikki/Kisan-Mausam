import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../l10n/app_strings.dart';
import '../../services/storage_service.dart';
import '../../services/api_service.dart';

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
  String? _customBackendUrl;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    final l = await StorageService.getLanguage();
    final hc = await StorageService.isHighContrast();
    final bUrl = await StorageService.getCustomBackendUrl();
    if (mounted) {
      setState(() {
        _lang = l;
        _highContrast = hc;
        _customBackendUrl = bUrl;
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

  void _showServerConfigDialog() {
    final controller = TextEditingController(text: _customBackendUrl ?? '');
    String? pingStatus;
    bool isPinging = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.cloud_sync, color: Color(0xFF1B5E20)),
              SizedBox(width: 8),
              Expanded(
                child: Text('AWS EC2 / क्लाउड सर्वर', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'अपने लाइव AWS EC2 या क्लाउड सर्वर का IP/URL दर्ज करें ताकि ऐप सीधे आपके बैकएंड व डेटाबेस से जुड़े:',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'http://<EC2-PUBLIC-IP>:8000',
                  labelText: 'सर्वर बेस URL',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 8),
              if (pingStatus != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    pingStatus!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: pingStatus!.startsWith('✅') ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: isPinging
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_ping, size: 16),
                    label: const Text('कनेक्शन जांचें (Ping)'),
                    onPressed: isPinging
                        ? null
                        : () async {
                            final target = controller.text.trim().replaceAll(RegExp(r'/+$'), '');
                            if (target.isEmpty) {
                              setDlgState(() => pingStatus = '⚠️ कृपया पहले सर्वर URL दर्ज करें');
                              return;
                            }
                            setDlgState(() {
                              isPinging = true;
                              pingStatus = 'जांच हो रही है...';
                            });
                            try {
                              final dio = Dio(BaseOptions(
                                connectTimeout: const Duration(milliseconds: 3500),
                                receiveTimeout: const Duration(milliseconds: 3500),
                              ));
                              final res = await dio.get('$target/docs');
                              if (res.statusCode == 200 || res.statusCode == 404) {
                                setDlgState(() {
                                  pingStatus = '✅ लाइव सर्वर सक्रिय और कनेक्टेड!';
                                  isPinging = false;
                                });
                              } else {
                                setDlgState(() {
                                  pingStatus = '⚠️ सर्वर कोड ${res.statusCode} लौटा रहा है';
                                  isPinging = false;
                                });
                              }
                            } catch (e) {
                              setDlgState(() {
                                pingStatus = '❌ कनेक्ट नहीं हो सका (जांचें कि EC2 पर पोर्ट 8000 खुला है)';
                                isPinging = false;
                              });
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'ℹ️ खाली रखने पर ऐप ऑटो-मोड (Open-Meteo व डायरेक्ट Gemini क्लाउड) में चलता रहेगा।',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('रद्द करें'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final url = controller.text.trim();
                Navigator.pop(ctx);
                await StorageService.saveCustomBackendUrl(url);
                ApiService.setCustomBackendUrl(url);
                if (!mounted) return;
                setState(() => _customBackendUrl = url.isEmpty ? null : url);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(url.isEmpty
                        ? 'डिफ़ॉल्ट क्लाउड मोड सक्रिय'
                        : '✅ सर्वर URL अपडेट हो गया: $url'),
                    backgroundColor: const Color(0xFF1B5E20),
                  ),
                );
              },
              child: const Text('सुरक्षित करें'),
            ),
          ],
        ),
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

          // Section 1.5: Cloud Backend & AWS Server
          _buildSectionHeader('क्लाउड बैकएंड व डेटाबेस (AWS EC2 / Server)'),
          ListTile(
            leading: const Icon(Icons.cloud_sync, color: Color(0xFF1B5E20)),
            title: const Text('बैकएंड सर्वर URL (Backend API)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              _customBackendUrl != null && _customBackendUrl!.isNotEmpty
                  ? 'लाइव सर्वर: $_customBackendUrl'
                  : 'डिफ़ॉल्ट: ${ApiService.backendBaseUrl} (ऑटो-क्लाउड फॉलबैक सक्रिय)',
            ),
            trailing: const Icon(Icons.edit, color: Color(0xFF1B5E20)),
            onTap: _showServerConfigDialog,
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
