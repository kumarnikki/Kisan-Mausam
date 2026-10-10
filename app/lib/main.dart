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
  int _profileRevision = 0;

  @override
  void initState() {
    super.initState();
    _loadAppState();
  }

  void _loadAppState() async {
    final lang = await StorageService.getLanguage();
    final hc = await StorageService.isHighContrast();
    final loggedIn = await StorageService.isLoggedIn();
    final profileConfigured = await StorageService.isProfileConfigured();
    if (mounted) {
      setState(() {
        _language = lang;
        _isHighContrast = hc;
        _profileRevision++;
        if (loggedIn && profileConfigured) {
          _isOnboardingDone = true;
        } else if (loggedIn && !profileConfigured) {
          // User logged in (e.g. via Continue with Phone OTP) -> ask for Name, Crops, Land Area, etc.
          _isOnboardingDone = false;
          _onboardingStep = 4;
        } else {
          _isOnboardingDone = false;
          _onboardingStep = 0;
        }
      });
    }
  }

  void _handlePostLogin() async {
    final profileConfigured = await StorageService.isProfileConfigured();
    if (!mounted) return;
    setState(() {
      if (profileConfigured) {
        _isOnboardingDone = true;
      } else {
        // Always ask for Farmer Name, Crops, Land Area, etc. when setting up a new account
        _isOnboardingDone = false;
        _onboardingStep = 4;
      }
    });
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
        onClose: () {
          setState(() {
            _isSettingsOpen = false;
            _profileRevision++;
          });
        },
        onThemeChanged: _loadAppState,
        onLanguageChanged: _loadAppState,
        onResetOnboarding: () async {
          await StorageService.logout();
          await StorageService.setOnboardingComplete(false);
          setState(() {
            _isSettingsOpen = false;
            _isOnboardingDone = false;
            _onboardingStep = 0;
            _profileRevision++;
          });
        },
      );
    }

    if (_isOnboardingDone) {
      return WeatherHomeScreen(
        key: ValueKey('home_${_language}_${_isHighContrast}_$_profileRevision'),
        onOpenSettings: () => setState(() => _isSettingsOpen = true),
      );
    }

    switch (_onboardingStep) {
      case 0: // Login / Sign-Up screen (first time)
        return LoginScreen(
          onLoginSuccess: _handlePostLogin,
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
      case 4: // Farm & Farmer Profile setup
        return FarmSetupScreen(
          onBack: () async {
            await StorageService.logout();
            if (mounted) {
              setState(() => _onboardingStep = 0);
            }
          },
          onFarmCreated: () {
            setState(() {
              _isOnboardingDone = true;
              _profileRevision++;
            });
          },
        );
      default:
        return LoginScreen(
          onLoginSuccess: _handlePostLogin,
        );
    }
  }
}
