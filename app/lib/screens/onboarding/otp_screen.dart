import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/alert_service.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';

class OtpScreen extends StatefulWidget {
  final VoidCallback onOtpVerified;
  final VoidCallback? onBack;

  const OtpScreen({
    super.key,
    required this.onOtpVerified,
    this.onBack,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _emailController = TextEditingController();
  final ApiService _apiService = ApiService();

  bool _otpSent = false;
  bool _isLoading = false;
  String? _verificationId;
  String _lang = 'hi';

  @override
  void initState() {
    super.initState();
    StorageService.getLanguage().then((l) {
      if (mounted) setState(() => _lang = l);
    });
    StorageService.getUserPhone().then((savedPhone) async {
      if (savedPhone != null && savedPhone.isNotEmpty) {
        if (mounted) _phoneController.text = savedPhone;
      } else {
        final sim = await AlertService.detectSimPhoneNumber();
        if (sim != null && sim.isNotEmpty) {
          await StorageService.saveUserPhone(sim);
          if (mounted) setState(() => _phoneController.text = sim);
        }
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final rawPhone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    if (rawPhone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _lang == 'en'
                ? 'Please enter a valid 10-digit mobile number'
                : 'कृपया सही 10 अंकों का मोबाइल नंबर भरें',
          ),
        ),
      );
      return;
    }

    final mobile = rawPhone.length > 10
        ? rawPhone.substring(rawPhone.length - 10)
        : rawPhone;

    await StorageService.saveUserPhone(mobile);
    AlertService.requestSmsPermission();

    setState(() => _isLoading = true);
    final res = await _apiService.sendOtpSms(mobile);
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _otpSent = true;
      _verificationId = res['verificationId']?.toString();
      _otpController.clear();
    });

    final sentLive = res['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          _lang == 'en'
              ? (sentLive ? 'SMS OTP sent to +91 $mobile' : 'OTP sent to +91 $mobile')
              : (sentLive
                  ? '+91 $mobile पर SMS द्वारा OTP भेजा गया है'
                  : '+91 $mobile पर OTP भेजा गया है'),
        ),
        backgroundColor: AppTheme.primaryGreen,
      ),
    );
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _lang == 'en' ? 'Please enter the OTP code' : 'कृपया OTP कोड दर्ज करें',
          ),
        ),
      );
      return;
    }

    final rawPhone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final mobile = rawPhone.length > 10
        ? rawPhone.substring(rawPhone.length - 10)
        : rawPhone;

    setState(() => _isLoading = true);
    final verified = await _apiService.verifyOtpSms(
      mobile,
      code,
      verificationId: _verificationId,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _lang == 'en'
                ? 'Invalid or expired OTP. Please check the SMS and try again.'
                : 'अमान्य या समाप्त OTP। कृपया SMS जांचें और पुनः प्रयास करें।',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    await StorageService.saveUserPhone(mobile);
    final email = _emailController.text.trim().isNotEmpty
        ? _emailController.text.trim()
        : '$mobile@kisanmausam.app';
    await StorageService.saveUserEmail(email);
    await StorageService.saveUserName(
      _lang == 'en' ? 'Farmer (+91 $mobile)' : 'किसान (+91 $mobile)',
    );
    _apiService.sendWeatherOrSosSms(
      phone: mobile,
      alertType: 'account_weather_active',
      message:
          'KisanMausam: Your mobile +91$mobile is now active for real-time GPS Weather, Climate Change & SOS SMS alerts.',
    );
    await StorageService.setOnboardingComplete(true);
    if (!mounted) return;
    widget.onOtpVerified();
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
                        AppStrings.get('phone_title', _lang),
                        style: AppTheme.titleStyle.copyWith(color: textPrimary),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final raw = _phoneController.text.replaceAll(RegExp(r'\D'), '');
                        if (raw.length >= 10) {
                          final mobile = raw.substring(raw.length - 10);
                          StorageService.saveUserPhone(mobile);
                        }
                        widget.onOtpVerified();
                      },
                      child: Text(
                        AppStrings.get('skip', _lang),
                        style: TextStyle(
                          color: accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.s24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _otpSent
                            ? AppStrings.get('otp_title', _lang)
                            : AppStrings.get('phone_title', _lang),
                        style: AppTheme.titleStyle.copyWith(color: textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _otpSent
                            ? AppStrings.get('otp_subtitle', _lang)
                            : AppStrings.get('phone_subtitle', _lang),
                        style: AppTheme.bodyStyle.copyWith(color: textSecondary),
                      ),
                      const SizedBox(height: 24),
                      AppSurface(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!_otpSent) ...[
                              TextField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                  color: textPrimary,
                                ),
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.phone_android_rounded),
                                  prefixText: '+91 ',
                                  hintText: '9876543210',
                                  counterText: '',
                                  labelText: AppStrings.get('phone_hint', _lang),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.email_outlined),
                                  labelText: AppStrings.get('optional_email', _lang),
                                  hintText: AppStrings.get('email_hint', _lang),
                                ),
                              ),
                              const SizedBox(height: 24),
                              PrimaryButton(
                                label: AppStrings.get('send_otp', _lang),
                                isLoading: _isLoading,
                                onPressed: _isLoading ? null : _sendOtp,
                              ),
                            ] else ...[
                              TextField(
                                controller: _otpController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 28,
                                  letterSpacing: 8,
                                  fontWeight: FontWeight.w800,
                                  color: textPrimary,
                                ),
                                decoration: InputDecoration(
                                  labelText: AppStrings.get('otp_hint', _lang),
                                ),
                              ),
                              const SizedBox(height: 20),
                              PrimaryButton(
                                label: AppStrings.get('verify_btn', _lang),
                                isLoading: _isLoading,
                                onPressed: _isLoading ? null : _verifyOtp,
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () {
                                          setState(() => _otpSent = false);
                                          _sendOtp();
                                        },
                                  child: Text(AppStrings.get('resend_otp', _lang)),
                                ),
                              ),
                              Center(
                                child: TextButton(
                                  onPressed:
                                      _isLoading ? null : () => setState(() => _otpSent = false),
                                  child: Text(
                                    _lang == 'en' ? 'Change mobile number' : 'मोबाइल नंबर बदलें',
                                    style: AppTheme.labelStyle.copyWith(color: textSecondary),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
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
