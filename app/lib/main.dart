import 'package:flutter/foundation.dart';
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
import 'widgets/glass_card.dart';

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
  String _themeMode = 'light'; // 'system' | 'light' | 'dark'
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
    final tm = await StorageService.getThemeMode();
    final loggedIn = await StorageService.isLoggedIn();
    final profileConfigured = await StorageService.isProfileConfigured();
    if (mounted) {
      setState(() {
        _language = lang;
        _isHighContrast = hc;
        _themeMode = tm;
        _profileRevision++;
        if (loggedIn && profileConfigured) {
          _isOnboardingDone = true;
        } else if (loggedIn && !profileConfigured) {
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
        _isOnboardingDone = false;
        _onboardingStep = 4;
      }
    });
  }

  ThemeMode _resolveThemeMode() {
    if (_isHighContrast) return ThemeMode.light;
    switch (_themeMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData lightTheme = _isHighContrast
        ? AppTheme.highContrastTheme()
        : AppTheme.lightTheme();
    final ThemeData darkTheme = _isHighContrast
        ? AppTheme.highContrastTheme()
        : AppTheme.darkTheme();

    return ValueListenableBuilder<DebugWeatherOverride?>(
      valueListenable: debugWeatherNotifier,
      builder: (context, debugOverride, _) {
        return MaterialApp(
          title: AppStrings.get('app_title', _language),
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: _resolveThemeMode(),
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
          builder: (ctx, child) {
            Widget wrapped = child ?? const SizedBox.shrink();
            // Width-constrained centered layout for wide/web viewports (max ~600dp)
            final width = MediaQuery.sizeOf(ctx).width;
            if (width > 640) {
              wrapped = ColoredBox(
                color: Theme.of(ctx).scaffoldBackgroundColor,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: wrapped,
                  ),
                ),
              );
            }
            if (kDebugMode && debugOverride?.textScaleOverride != null) {
              wrapped = MediaQuery(
                data: MediaQuery.of(ctx).copyWith(
                  textScaler: TextScaler.linear(debugOverride!.textScaleOverride!),
                ),
                child: wrapped,
              );
            }
            return wrapped;
          },
          home: _buildCurrentScreen(),
        );
      },
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
        key: ValueKey('home_${_language}_${_isHighContrast}_${_themeMode}_$_profileRevision'),
        onOpenSettings: () => setState(() => _isSettingsOpen = true),
      );
    }

    switch (_onboardingStep) {
      case 0:
        return LoginScreen(
          onLoginSuccess: _handlePostLogin,
        );
      case 1:
        return LanguageScreen(
          onLanguageSelected: () => setState(() => _onboardingStep = 2),
          onBack: () => setState(() => _onboardingStep = 0),
        );
      case 2:
        return OtpScreen(
          onOtpVerified: () => setState(() => _onboardingStep = 3),
          onBack: () => setState(() => _onboardingStep = 1),
        );
      case 3:
        return ConsentScreen(
          onConsentAccepted: () => setState(() => _onboardingStep = 4),
          onBack: () => setState(() => _onboardingStep = 2),
        );
      case 4:
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
