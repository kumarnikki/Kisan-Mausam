import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../services/storage_service.dart';

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
    return Scaffold(
      appBar: widget.onBack != null
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: _selected == 'en' ? 'Back' : 'वापस जाएं',
                onPressed: widget.onBack,
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              // Logo & App Name
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wb_sunny_rounded, size: 48, color: Color(0xFF1B5E20)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  AppStrings.get('app_title', _selected),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1B5E20)),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  AppStrings.get('tagline', _selected),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                AppStrings.get('select_language', _selected),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              // Hindi Card (Default)
              _LanguageCard(
                title: 'हिंदी',
                subtitle: 'सम्पूर्ण जानकारी हिंदी में उपलब्ध',
                code: 'hi',
                isSelected: _selected == 'hi',
                onTap: () => _choose('hi'),
              ),
              const SizedBox(height: 14),
              // English Card
              _LanguageCard(
                title: 'English',
                subtitle: 'Weather forecasts, alerts and advisory in English',
                code: 'en',
                isSelected: _selected == 'en',
                onTap: () => _choose('en'),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () => widget.onLanguageSelected(),
                child: Text(AppStrings.get('continue_btn', _selected)),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F5E9) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF1B5E20) : Colors.grey.shade300,
            width: isSelected ? 2.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFF1B5E20) : Colors.grey,
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFF1B5E20) : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
