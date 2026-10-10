import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../l10n/app_strings.dart';
import '../../services/storage_service.dart';
import '../../services/api_service.dart';
import '../../services/update_service.dart';

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
  bool _isCheckingUpdate = false;
  int _developerTapCount = 0;

  void _onFooterTapped() {
    _developerTapCount++;
    if (_developerTapCount == 7) {
      _developerTapCount = 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lang == 'en' ? 'Developer Options Unlocked' : 'डेवलपर सेटिंग्स खोली गईं'),
          backgroundColor: const Color(0xFF1B5E20),
          duration: const Duration(seconds: 2),
        ),
      );
      _showServerConfigDialog();
    } else if (_developerTapCount >= 4) {
      final remaining = 7 - _developerTapCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lang == 'en'
              ? 'You are now $remaining steps away from Developer Options'
              : 'आप डेवलपर विकल्पों से $remaining कदम दूर हैं'),
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
  }

  Future<void> _checkAppUpdate() async {
    setState(() => _isCheckingUpdate = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final info = await UpdateService.checkForUpdate();
      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);
      if (info.hasUpdate) {
        UpdateService.showUpdateDialog(context, info, lang: _lang);
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF1B5E20)),
                const SizedBox(width: 8),
                Text(
                  AppStrings.get('update_dialog_current', _lang),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Text(
              AppStrings.get('update_dialog_current_desc', _lang),
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppStrings.get('update_dialog_ok', _lang)),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);
      messenger.showSnackBar(
        SnackBar(content: Text(AppStrings.get('update_check_failed', _lang))),
      );
    }
  }

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
        title: Text(AppStrings.get('settings_delete_title', _lang)),
        content: Text(AppStrings.get('settings_delete_confirm_desc', _lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.get('settings_delete_cancel', _lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.setOnboardingComplete(false);
              widget.onResetOnboarding();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppStrings.get('settings_delete_success', _lang)),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(
              AppStrings.get('settings_delete_confirm_btn', _lang),
              style: const TextStyle(color: Colors.white),
            ),
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
          title: Row(
            children: [
              const Icon(Icons.cloud_sync, color: Color(0xFF1B5E20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.get('server_dialog_title', _lang),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.get('server_dialog_desc', _lang),
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'http://<EC2-PUBLIC-IP>:8000',
                  labelText: AppStrings.get('server_dialog_label', _lang),
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
                    label: Text(AppStrings.get('server_dialog_ping', _lang)),
                    onPressed: isPinging
                        ? null
                        : () async {
                            final target = controller.text.trim().replaceAll(RegExp(r'/+$'), '');
                            if (target.isEmpty) {
                              setDlgState(() => pingStatus = AppStrings.get('server_dialog_empty_warn', _lang));
                              return;
                            }
                            setDlgState(() {
                              isPinging = true;
                              pingStatus = AppStrings.get('server_dialog_pinging', _lang);
                            });
                            try {
                              final dio = Dio(BaseOptions(
                                connectTimeout: const Duration(milliseconds: 3500),
                                receiveTimeout: const Duration(milliseconds: 3500),
                              ));
                              final res = await dio.get('$target/docs');
                              if (res.statusCode == 200 || res.statusCode == 404) {
                                setDlgState(() {
                                  pingStatus = AppStrings.get('server_dialog_ping_success', _lang);
                                  isPinging = false;
                                });
                              } else {
                                setDlgState(() {
                                  pingStatus = '⚠️ ${res.statusCode}';
                                  isPinging = false;
                                });
                              }
                            } catch (_) {
                              setDlgState(() {
                                pingStatus = AppStrings.get('server_dialog_ping_fail', _lang);
                                isPinging = false;
                              });
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.get('server_dialog_hint', _lang),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.get('server_dialog_cancel', _lang)),
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
                        ? AppStrings.get('server_saved_default', _lang)
                        : '${AppStrings.get('server_saved_custom', _lang)}$url'),
                    backgroundColor: const Color(0xFF1B5E20),
                  ),
                );
              },
              child: Text(AppStrings.get('server_dialog_save', _lang)),
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
          tooltip: AppStrings.get('settings_back', _lang),
          onPressed: widget.onClose,
        ),
        title: Text(AppStrings.get('settings', _lang)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // Section 1: Appearance & Accessibility
          _buildSectionHeader(AppStrings.get('settings_appearance', _lang)),
          ListTile(
            leading: const Icon(Icons.language, color: Color(0xFF1B5E20)),
            title: Text(AppStrings.get('settings_language', _lang), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(AppStrings.get('settings_current_lang', _lang)),
            trailing: OutlinedButton(
              onPressed: _toggleLanguage,
              child: Text(AppStrings.get('settings_switch_to', _lang)),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.contrast, color: Color(0xFF1B5E20)),
            title: Text(AppStrings.get('high_contrast', _lang), style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(AppStrings.get('settings_high_contrast_sub', _lang)),
            value: _highContrast,
            onChanged: _toggleHighContrast,
          ),
          const Divider(),

          // Section 3: Privacy & DPDP Act 2023
          _buildSectionHeader(AppStrings.get('settings_privacy_section', _lang)),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: Color(0xFF1B5E20)),
            title: Text(AppStrings.get('settings_privacy_policy', _lang)),
            subtitle: Text(AppStrings.get('settings_privacy_policy_sub', _lang)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppStrings.get('consent_subtitle', _lang))),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: Text(
              AppStrings.get('delete_data', _lang),
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(AppStrings.get('settings_delete_sub', _lang)),
            onTap: _confirmDeleteData,
          ),
          const Divider(),

          // Section 4: In-App Updates
          _buildSectionHeader(AppStrings.get('settings_updates_section', _lang)),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.system_update_alt, color: Color(0xFF1B5E20), size: 20),
            ),
            title: Text(AppStrings.get('settings_check_update', _lang)),
            subtitle: Text('v${UpdateService.currentVersion} • ${AppStrings.get('settings_update_sub', _lang)}'),
            trailing: _isCheckingUpdate
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF1B5E20)),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isCheckingUpdate ? null : _checkAppUpdate,
          ),
          const Divider(),

          // Section 5: About & Attribution
          _buildSectionHeader(AppStrings.get('settings_attribution_section', _lang)),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Color(0xFF1B5E20)),
            title: Text(AppStrings.get('settings_data_source', _lang)),
            subtitle: const Text('Powered by Open-Meteo under CC BY 4.0 (Non-Commercial License)'),
          ),
          ListTile(
            leading: const Icon(Icons.agriculture, color: Color(0xFF1B5E20)),
            title: Text(AppStrings.get('settings_standards', _lang)),
            subtitle: Text(AppStrings.get('settings_standards_sub', _lang)),
          ),
          const SizedBox(height: 32),
          Center(
            child: InkWell(
              onTap: _onFooterTapped,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  AppStrings.get('settings_footer', _lang),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
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
