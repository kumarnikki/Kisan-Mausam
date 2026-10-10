import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/app_theme.dart';
import 'services/storage_service.dart';
import 'screens/onboarding/login_screen.dart';
import 'screens/onboarding/language_screen.dart';
import 'screens/onboarding/otp_screen.dart';
import 'screens/onboarding/consent_screen.dart';
import 'screens/onboarding/farm_setup_screen.dart';
import 'screens/home/weather_home_screen.dart';
import 'screens/settings/settings_screen.dart';

import 'services/api_service.dart';
import 'l10n/app_strings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final customUrl = await StorageService.getCustomBackendUrl();
  if (customUrl != null) {
    ApiService.setCustomBackendUrl(customUrl);
  }
  runApp(const KisanMausamApp());
}

class KisanMausamApp extends StatefulWidget {
  const KisanMausamApp({super.key});

  @override
  State<KisanMausamApp> createState() => _KisanMausamAppState();
}

class _KisanMausamAppState extends State<KisanMausamApp> {
  String _language = 'hi';
  bool _isHighContrast = false;
  bool _isOnboardingDone = false;
  // 0: Login, 1: Language, 2: OTP, 3: Consent, 4: Farm
  int _onboardingStep = 0;
  bool _isSettingsOpen = false;

  @override
  void initState() {
    super.initState();
    _loadAppState();
  }

  void _loadAppState() async {
    final lang = await StorageService.getLanguage();
    final hc = await StorageService.isHighContrast();
    final done = await StorageService.isOnboardingComplete();
    final loggedIn = await StorageService.isLoggedIn();
    if (mounted) {
      setState(() {
        _language = lang;
        _isHighContrast = hc;
        _isOnboardingDone = done || loggedIn;
        _onboardingStep = loggedIn ? 1 : 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ThemeData selectedTheme;
    if (_isHighContrast) {
      selectedTheme = AppTheme.highContrastTheme();
    } else {
      selectedTheme = AppTheme.lightTheme();
    }

    return MaterialApp(
      title: AppStrings.get('app_title', _language),
      debugShowCheckedModeBanner: false,
      theme: selectedTheme,
      locale: Locale(_language),
      supportedLocales: const [
        Locale('hi', 'IN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _buildCurrentScreen(),
    );
  }

  Widget _buildCurrentScreen() {
    if (_isSettingsOpen) {
      return SettingsScreen(
        onClose: () => setState(() => _isSettingsOpen = false),
        onThemeChanged: _loadAppState,
        onLanguageChanged: _loadAppState,
        onResetOnboarding: () async {
          await StorageService.logout();
          await StorageService.setOnboardingComplete(false);
          setState(() {
            _isSettingsOpen = false;
            _isOnboardingDone = false;
            _onboardingStep = 0;
          });
        },
      );
    }

    if (_isOnboardingDone) {
      return WeatherHomeScreen(
        key: ValueKey('home_${_language}_$_isHighContrast'),
        onOpenSettings: () => setState(() => _isSettingsOpen = true),
      );
    }

    switch (_onboardingStep) {
      case 0: // Login / Sign-Up screen (first time)
        return LoginScreen(
          onLoginSuccess: () => setState(() {
            _isOnboardingDone = true;
          }),
        );
      case 1: // Language selection
        return LanguageScreen(
          onLanguageSelected: () => setState(() => _onboardingStep = 2),
          onBack: () => setState(() => _onboardingStep = 0),
        );
      case 2: // OTP / Phone verification
        return OtpScreen(
          onOtpVerified: () => setState(() => _onboardingStep = 3),
          onBack: () => setState(() => _onboardingStep = 1),
        );
      case 3: // Consent
        return ConsentScreen(
          onConsentAccepted: () => setState(() => _onboardingStep = 4),
          onBack: () => setState(() => _onboardingStep = 2),
        );
      case 4: // Farm setup
        return FarmSetupScreen(
          onBack: () => setState(() => _onboardingStep = 3),
          onFarmCreated: () {
            setState(() {
              _isOnboardingDone = true;
            });
          },
        );
      default:
        return LoginScreen(
          onLoginSuccess: () => setState(() {
            _onboardingStep = 1;
          }),
        );
    }
  }
}
