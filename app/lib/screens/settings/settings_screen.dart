import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../l10n/app_strings.dart';
import '../../models/farm_profile.dart';
import '../../services/storage_service.dart';
import '../../services/api_service.dart';
import '../../services/alert_service.dart';
import '../../services/update_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../onboarding/farm_setup_screen.dart';

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
  final ApiService _apiService = ApiService();
  String _lang = 'hi';
  String _themeMode = 'light';
  bool _highContrast = false;
  String? _customBackendUrl;
  bool _isCheckingUpdate = false;
  int _developerTapCount = 0;
  String? _userName;
  String? _userPhone;
  FarmProfile? _currentFarm;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final l = await StorageService.getLanguage();
    final tm = await StorageService.getThemeMode();
    final hc = await StorageService.isHighContrast();
    final bUrl = await StorageService.getCustomBackendUrl();
    final uName = await StorageService.getUserName();
    final uPhone = await StorageService.getUserPhone();
    final farms = await StorageService.getFarms();
    final activeId = await StorageService.getActiveFarmId();
    final activeFarm = farms.isNotEmpty
        ? farms.firstWhere((f) => f.id == activeId, orElse: () => farms.first)
        : null;

    if (mounted) {
      setState(() {
        _lang = l;
        _themeMode = tm;
        _highContrast = hc;
        _customBackendUrl = bUrl;
        _userName = uName;
        _userPhone = uPhone;
        _currentFarm = activeFarm;
      });
    }
  }

  void _onFooterTapped() {
    _developerTapCount++;
    if (_developerTapCount == 7) {
      _developerTapCount = 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _lang == 'en' ? 'Developer Options Unlocked' : 'डेवलपर सेटिंग्स खोली गईं',
          ),
          backgroundColor: AppTheme.primaryGreen,
          duration: const Duration(seconds: 2),
        ),
      );
      _showServerConfigDialog();
    } else if (_developerTapCount >= 4) {
      final remaining = 7 - _developerTapCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _lang == 'en'
                ? 'You are now $remaining steps away from Developer Options'
                : 'आप डेवलपर विकल्पों से $remaining कदम दूर हैं',
          ),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rCard)),
            title: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppStrings.get('update_dialog_current', _lang),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            content: Text(
              AppStrings.get('update_dialog_current_desc', _lang),
              style: const TextStyle(fontSize: 15, height: 1.4),
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
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(AppStrings.get('update_check_failed', _lang)),
        ),
      );
    }
  }

  void _openEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => FarmSetupScreen(
          isEditing: true,
          onBack: () => Navigator.pop(ctx),
          onFarmCreated: () {
            Navigator.pop(ctx);
            _loadSettings();
            widget.onLanguageChanged();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    _lang == 'en'
                        ? 'Farmer & crop profile updated'
                        : 'किसान व फसल प्रोफाइल अपडेट कर दी गई',
                  ),
                  backgroundColor: AppTheme.primaryGreen,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _setLanguage(String next) async {
    if (_lang == next) return;
    await StorageService.setLanguage(next);
    setState(() => _lang = next);
    widget.onLanguageChanged();
  }

  Future<void> _setThemeMode(String mode) async {
    if (_themeMode == mode) return;
    await StorageService.setThemeMode(mode);
    setState(() => _themeMode = mode);
    widget.onThemeChanged();
  }

  Future<void> _toggleHighContrast(bool val) async {
    await StorageService.setHighContrast(val);
    setState(() => _highContrast = val);
    widget.onThemeChanged();
  }

  void _openTestAlertSheet() {
    final isEn = _lang == 'en';
    final phone = (_userPhone != null && _userPhone!.trim().isNotEmpty)
        ? '+91 ${_userPhone!.trim()}'
        : (isEn ? 'Login number not linked' : 'लॉगिन नंबर जुड़ा नहीं है');
    final sampleLabel = AppStrings.get('test_alert_sample_badge', _lang);

    final samples = <({
      IconData icon,
      Color color,
      String titleHi,
      String titleEn,
      String scenario,
      String severity,
      String bodyHi,
      String bodyEn,
      String actionHi,
      String actionEn,
    })>[
      (
        icon: Icons.cloud_sync_rounded,
        color: AppTheme.warningText,
        titleHi: 'अचानक मौसम परिवर्तन',
        titleEn: 'Sudden weather change',
        scenario: 'weather_change',
        severity: 'orange',
        bodyHi: 'नमूना: अगले 2 घंटों में हवा 42 km/h और बारिश की संभावना 65% बढ़ गई है।',
        bodyEn: 'Sample: Wind shifted 15 km/h to 42 km/h & rain probability rose 65% in 2h.',
        actionHi: 'छिड़काव तुरंत रोकें और कटी फसल को तिरपाल से ढकें।',
        actionEn: 'Pause spraying and cover harvested produce immediately.',
      ),
      (
        icon: Icons.ac_unit_rounded,
        color: AppTheme.danger,
        titleHi: 'तीव्र पाला चेतावनी',
        titleEn: 'Severe frost alert',
        scenario: 'frost',
        severity: 'red',
        bodyHi: 'नमूना: रात का तापमान 3°C से नीचे गिरने की संभावना है।',
        bodyEn: 'Sample: Night temperature may drop below 3°C. High frost risk.',
        actionHi: 'फसल बचाने हेतु शाम को हल्की सिंचाई करें।',
        actionEn: 'Apply light evening irrigation to protect standing crops.',
      ),
      (
        icon: Icons.thunderstorm_rounded,
        color: AppTheme.danger,
        titleHi: 'भारी बारिश व ओलावृष्टि',
        titleEn: 'Heavy rain & hailstorm',
        scenario: 'heavy_rain',
        severity: 'red',
        bodyHi: 'नमूना: अगले 24 घंटों में 65 मिमी से अधिक भारी बारिश की संभावना है।',
        bodyEn: 'Sample: Over 65 mm rainfall expected in next 24 hours.',
        actionHi: 'खेत की जल निकासी नालियां साफ करें और अनाज सुरक्षित स्थान पर रखें।',
        actionEn: 'Clear field drainage channels and secure harvested grain.',
      ),
      (
        icon: Icons.wb_sunny_rounded,
        color: AppTheme.danger,
        titleHi: 'लू (हीट वेव) चेतावनी',
        titleEn: 'Heat wave alert',
        scenario: 'heat_wave',
        severity: 'red',
        bodyHi: 'नमूना: दोपहर का तापमान 43°C से अधिक रहने की संभावना है।',
        bodyEn: 'Sample: Afternoon temperature expected to cross 43°C.',
        actionHi: 'शाम के समय सिंचाई करें और नमी बचाने हेतु पलवार (मल्चिंग) करें।',
        actionEn: 'Irrigate in the evening and mulch topsoil to retain moisture.',
      ),
      (
        icon: Icons.shield_rounded,
        color: AppTheme.danger,
        titleHi: 'आपातकालीन SOS अभ्यास',
        titleEn: 'SOS drill',
        scenario: 'sos',
        severity: 'red',
        bodyHi: 'नमूना: आपातकालीन सायरन और GPS लोकेशन के साथ SMS अभ्यास।',
        bodyEn: 'Sample: Emergency siren + SMS alert drill with GPS coordinates.',
        actionHi: 'आपातकालीन सायरन व SMS प्रसारण का परीक्षण करें।',
        actionEn: 'Test emergency siren and SMS dispatch.',
      ),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => SheetScaffold(
        title: AppStrings.get('test_alert_sheet_title', _lang),
        subtitle: '${AppStrings.get('test_alert_sheet_sub', _lang)} ($phone)',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: samples.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppSurface(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                borderRadius: AppTheme.rInput,
                onTap: () => _runTestAlert(
                  sheetCtx: sheetCtx,
                  scenario: item.scenario,
                  severity: item.severity,
                  titleHi: item.titleHi,
                  titleEn: item.titleEn,
                  bodyHi: item.bodyHi,
                  bodyEn: item.bodyEn,
                  actionHi: item.actionHi,
                  actionEn: item.actionEn,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, color: item.color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isEn ? item.titleEn : item.titleHi,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.cautionAmber,
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: Text(
                        sampleLabel,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimaryLight,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: AppTheme.textSecondary(context),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _runTestAlert({
    required BuildContext sheetCtx,
    required String scenario,
    required String severity,
    required String titleHi,
    required String titleEn,
    required String bodyHi,
    required String bodyEn,
    required String actionHi,
    required String actionEn,
  }) async {
    Navigator.pop(sheetCtx);
    final isEn = _lang == 'en';
    final messenger = ScaffoldMessenger.of(context);
    final phone = (_userPhone ?? await StorageService.getUserPhone() ?? '').trim();
    final village = _currentFarm?.getVillage(_lang) ?? (isEn ? 'My Farm' : 'मेरा खेत');
    final farmId = _currentFarm?.id ?? 1;

    if (mounted) {
      await AlertService.showHazardAlert(
        context,
        titleHi: titleHi,
        titleEn: titleEn,
        bodyHi: bodyHi,
        bodyEn: bodyEn,
        severity: severity,
        actionHi: actionHi,
        actionEn: actionEn,
        probability: 85.0,
        lang: _lang,
        locationName: village,
        isSos: scenario == 'sos',
      );
    }

    final res = await _apiService.simulateAlert(
      farmId,
      scenario,
      phoneNumber: phone.isNotEmpty ? phone : null,
      locationName: village,
    );

    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    final sentOk = res != null && res['sms_sent'] == true;
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: sentOk ? AppTheme.primaryGreen : AppTheme.warningText,
        content: Text(
          sentOk && phone.isNotEmpty
              ? '${AppStrings.get('test_alert_sent_snack', _lang)} +91 $phone'
              : (isEn
                  ? 'Sample alert previewed${phone.isNotEmpty ? " (+91 $phone)" : ""}'
                  : 'नमूना अलर्ट दिखाया गया${phone.isNotEmpty ? " (+91 $phone)" : ""}'),
        ),
      ),
    );
  }

  void _confirmDeleteData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rCard)),
        title: Text(AppStrings.get('settings_delete_title', _lang)),
        content: Text(
          AppStrings.get('settings_delete_confirm_desc', _lang),
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.get('settings_delete_cancel', _lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.logout();
              widget.onResetOnboarding();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text(AppStrings.get('settings_delete_success', _lang)),
                    backgroundColor: AppTheme.danger,
                  ),
                );
              }
            },
            child: Text(AppStrings.get('settings_delete_confirm_btn', _lang)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SheetScaffold(
        title: AppStrings.get('settings_privacy_policy', _lang),
        subtitle: AppStrings.get('settings_privacy_policy_sub', _lang),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.get('consent_subtitle', _lang),
              style: AppTheme.bodyStyle.copyWith(color: AppTheme.textPrimary(context)),
            ),
            const SizedBox(height: 12),
            Text(
              '• ${AppStrings.get('consent_location', _lang)}\n'
              '• ${AppStrings.get('consent_sms', _lang)}\n'
              '• ${AppStrings.get('consent_voice', _lang)}',
              style: AppTheme.labelStyle.copyWith(color: AppTheme.textSecondary(context)),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: AppStrings.get('update_dialog_ok', _lang),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rCard)),
          title: Row(
            children: [
              const Icon(Icons.cloud_sync_rounded, color: AppTheme.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.get('server_dialog_title', _lang),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
                style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondary(context)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: 'http://<EC2-PUBLIC-IP>:8000',
                  labelText: AppStrings.get('server_dialog_label', _lang),
                  prefixIcon: const Icon(Icons.link_rounded),
                ),
              ),
              const SizedBox(height: 8),
              if (pingStatus != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    pingStatus!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: pingStatus!.contains('Reachable') || pingStatus!.contains('सफल')
                          ? AppTheme.success
                          : AppTheme.danger,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                icon: isPinging
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_ping_rounded, size: 16),
                label: Text(AppStrings.get('server_dialog_ping', _lang)),
                onPressed: isPinging
                    ? null
                    : () async {
                        final target = controller.text.trim().replaceAll(RegExp(r'/+$'), '');
                        if (target.isEmpty) {
                          setDlgState(
                            () => pingStatus = AppStrings.get('server_dialog_empty_warn', _lang),
                          );
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
                              pingStatus = 'HTTP ${res.statusCode}';
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
              const SizedBox(height: 6),
              Text(
                AppStrings.get('server_dialog_hint', _lang),
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary(context)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.get('server_dialog_cancel', _lang)),
            ),
            ElevatedButton(
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
                    behavior: SnackBarBehavior.floating,
                    content: Text(
                      url.isEmpty
                          ? AppStrings.get('server_saved_default', _lang)
                          : '${AppStrings.get('server_saved_custom', _lang)}$url',
                    ),
                    backgroundColor: AppTheme.primaryGreen,
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
    final isEn = _lang == 'en';
    final textPrimary = AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);
    final accent = AppTheme.primaryActionColor(context);

    final displayName = (_userName != null && _userName!.trim().isNotEmpty)
        ? _userName!.trim()
        : (isEn ? 'Farmer' : 'किसान');
    final initial = displayName.characters.first.toUpperCase();
    final displayPhone = (_userPhone != null && _userPhone!.trim().isNotEmpty)
        ? '+91 ${_userPhone!.trim()}'
        : (isEn ? 'Phone not linked' : 'फ़ोन नंबर नहीं जुड़ा');
    final displayCrop = _currentFarm?.getCurrentCrop(_lang) ?? (isEn ? 'Wheat' : 'गेहूं');
    final displayAcres = _currentFarm != null
        ? '${_currentFarm!.landSizeAcres} ${AppStrings.get('acres_suffix', _lang)}'
        : '2.5 ${AppStrings.get('acres_suffix', _lang)}';
    final displayLocation = _currentFarm != null
        ? '${_currentFarm!.getVillage(_lang)}, ${_currentFarm!.getDistrict(_lang)}'
        : (isEn ? 'My Farm' : 'मेरा खेत');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        quiet: true,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Plain header (no solid green AppBar)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
                child: Row(
                  children: [
                    IconAction(
                      icon: Icons.arrow_back_rounded,
                      semanticLabel: AppStrings.get('settings_back', _lang),
                      onPressed: widget.onClose,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        AppStrings.get('settings', _lang),
                        style: AppTheme.titleStyle.copyWith(color: textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.screenPadding,
                    8,
                    AppTheme.screenPadding,
                    AppTheme.s32,
                  ),
                  children: [
                    // 1. Profile Row (compact single row with chevron into Edit Profile)
                    SectionHeader(title: isEn ? 'Profile' : 'प्रोफाइल'),
                    AppSurface(
                      onTap: _openEditProfile,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: AppTheme.primaryGreen,
                            child: Text(
                              initial,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$displayLocation — $displayCrop, $displayAcres',
                                  style: AppTheme.labelStyle.copyWith(color: textSecondary),
                                ),
                                Text(
                                  displayPhone,
                                  style: AppTheme.labelStyle.copyWith(
                                    color: textSecondary,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: textSecondary),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.s24),

                    // 2. Appearance & Language
                    SectionHeader(title: AppStrings.get('settings_appearance', _lang)),
                    AppSurface(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.get('settings_language', _lang),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _SegmentedSelector<String>(
                            value: _lang,
                            options: const [
                              (value: 'hi', label: 'हिंदी'),
                              (value: 'en', label: 'English'),
                            ],
                            onChanged: _setLanguage,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            AppStrings.get('settings_theme', _lang),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _SegmentedSelector<String>(
                            value: _themeMode,
                            options: [
                              (value: 'system', label: AppStrings.get('theme_system', _lang)),
                              (value: 'light', label: AppStrings.get('theme_light', _lang)),
                              (value: 'dark', label: AppStrings.get('theme_dark', _lang)),
                            ],
                            onChanged: _setThemeMode,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Divider(height: 1),
                          ),
                          Row(
                            children: [
                              Icon(Icons.contrast_rounded, color: accent, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppStrings.get('high_contrast', _lang),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppStrings.get('settings_high_contrast_sub', _lang),
                                      style: AppTheme.labelStyle.copyWith(color: textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _highContrast,
                                activeTrackColor: AppTheme.primaryGreen,
                                onChanged: _toggleHighContrast,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.s24),

                    // 3. Alerts & Updates
                    SectionHeader(title: AppStrings.get('settings_updates_section', _lang)),
                    AppSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _SettingsRow(
                            icon: Icons.notifications_active_rounded,
                            iconColor: AppTheme.warningText,
                            title: AppStrings.get('settings_test_alert', _lang),
                            subtitle: AppStrings.get('settings_test_alert_sub', _lang),
                            onTap: _openTestAlertSheet,
                          ),
                          const Divider(height: 1, indent: 52),
                          _SettingsRow(
                            icon: Icons.system_update_alt_rounded,
                            iconColor: accent,
                            title: AppStrings.get('settings_check_update', _lang),
                            subtitle:
                                'v${UpdateService.currentVersion} • ${AppStrings.get('settings_update_sub', _lang)}',
                            trailing: _isCheckingUpdate
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: accent,
                                    ),
                                  )
                                : null,
                            onTap: _isCheckingUpdate ? null : _checkAppUpdate,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.s24),

                    // 4. Privacy & About
                    SectionHeader(title: AppStrings.get('settings_attribution_section', _lang)),
                    AppSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _SettingsRow(
                            icon: Icons.privacy_tip_rounded,
                            iconColor: accent,
                            title: AppStrings.get('settings_privacy_policy', _lang),
                            subtitle: AppStrings.get('settings_privacy_policy_sub', _lang),
                            onTap: _showPrivacyDialog,
                          ),
                          const Divider(height: 1, indent: 52),
                          _SettingsRow(
                            icon: Icons.cloud_done_rounded,
                            iconColor: accent,
                            title: AppStrings.get('settings_data_source', _lang),
                            subtitle:
                                'Powered by Open-Meteo under CC BY 4.0 (Non-Commercial License)',
                            showChevron: false,
                          ),
                          const Divider(height: 1, indent: 52),
                          _SettingsRow(
                            icon: Icons.verified_rounded,
                            iconColor: accent,
                            title: AppStrings.get('settings_standards', _lang),
                            subtitle: AppStrings.get('settings_standards_sub', _lang),
                            showChevron: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.s24),

                    // 5. Delete Account & Data (separated at bottom in danger style)
                    AppSurface(
                      padding: EdgeInsets.zero,
                      borderColor: AppTheme.danger.withValues(alpha: 0.35),
                      onTap: _confirmDeleteData,
                      child: _SettingsRow(
                        icon: Icons.delete_forever_rounded,
                        iconColor: AppTheme.danger,
                        title: AppStrings.get('delete_data', _lang),
                        titleColor: AppTheme.danger,
                        subtitle: AppStrings.get('settings_delete_sub', _lang),
                        onTap: _confirmDeleteData,
                      ),
                    ),
                    const SizedBox(height: AppTheme.s24),

                    // Hidden 7-tap developer config footer
                    Center(
                      child: InkWell(
                        onTap: _onFooterTapped,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Text(
                            AppStrings.get('settings_footer', _lang),
                            textAlign: TextAlign.center,
                            style: AppTheme.labelStyle.copyWith(
                              color: textSecondary,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedSelector<T> extends StatelessWidget {
  final T value;
  final List<({T value, String label})> options;
  final ValueChanged<T> onChanged;

  const _SegmentedSelector({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final isHc = AppTheme.isHighContrast(context);
    final selectedBg = isHc
        ? const Color(0xFF004D20)
        : (isDark ? AppTheme.darkButtonFill : AppTheme.primaryGreen);
    final unselectedBg = isDark ? const Color(0xFF141D16) : const Color(0xFFF3F6F3);

    return Container(
      decoration: BoxDecoration(
        color: unselectedBg,
        borderRadius: BorderRadius.circular(AppTheme.rInput),
        border: Border.all(
          color: AppTheme.borderColor(context),
          width: isHc ? 2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.map((opt) {
          final selected = opt.value == value;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: opt.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.rInput - 3),
                onTap: () => onChanged(opt.value),
                child: AnimatedContainer(
                  duration: AppTheme.motionDuration(context, const Duration(milliseconds: 180)),
                  curve: Curves.easeOutCubic,
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? selectedBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppTheme.rInput - 3),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected) ...[
                        const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          opt.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                            color: selected ? Colors.white : AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final String subtitle;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    required this.subtitle,
    this.trailing,
    this.showChevron = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = titleColor ?? AppTheme.textPrimary(context);
    final textSecondary = AppTheme.textSecondary(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.rCard),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.labelStyle.copyWith(
                        color: textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (showChevron)
                Icon(Icons.chevron_right_rounded, color: textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
