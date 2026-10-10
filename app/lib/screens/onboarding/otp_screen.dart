import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/storage_service.dart';

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
  final _phoneController = TextEditingController(text: '9876543210');
  final _otpController = TextEditingController(text: '123456');
  final _emailController = TextEditingController();
  
  bool _otpSent = false;
  String _lang = 'hi';

  @override
  void initState() {
    super.initState();
    StorageService.getLanguage().then((l) {
      if (mounted) setState(() => _lang = l);
    });
  }

  void _sendOtp() {
    if (_phoneController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('कृपया सही 10 अंकों का मोबाइल नंबर भरें')),
      );
      return;
    }
    setState(() => _otpSent = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('OTP भेजा गया (डेवलपमेंट मोड में 123456 दर्ज करें)'),
        backgroundColor: Color(0xFF1B5E20),
      ),
    );
  }

  void _verifyOtp() {
    if (_otpController.text.trim().isEmpty) return;
    widget.onOtpVerified();
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
        title: Text(AppStrings.get('phone_title', _lang)),
        actions: [
          TextButton(
            onPressed: () => widget.onOtpVerified(),
            child: Text(
              AppStrings.get('skip', _lang),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text(
                _otpSent ? AppStrings.get('otp_title', _lang) : AppStrings.get('phone_title', _lang),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _otpSent ? AppStrings.get('otp_subtitle', _lang) : AppStrings.get('phone_subtitle', _lang),
                style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 32),
              if (!_otpSent) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.phone_android, size: 28),
                    prefixText: '+91 ',
                    labelText: AppStrings.get('phone_hint', _lang),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.email_outlined),
                    labelText: AppStrings.get('optional_email', _lang),
                    hintText: AppStrings.get('email_hint', _lang),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _sendOtp,
                  child: Text(AppStrings.get('send_otp', _lang)),
                ),
              ] else ...[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 32, letterSpacing: 8, fontWeight: FontWeight.w900),
                  decoration: InputDecoration(
                    labelText: AppStrings.get('otp_hint', _lang),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _verifyOtp,
                  child: Text(AppStrings.get('verify_btn', _lang)),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() => _otpSent = false),
                    child: Text(AppStrings.get('resend_otp', _lang)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
