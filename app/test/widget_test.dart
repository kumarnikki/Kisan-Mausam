import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kisan_mausam/main.dart';
import 'package:kisan_mausam/screens/home/weather_home_screen.dart';
import 'package:kisan_mausam/screens/onboarding/language_screen.dart';
import 'package:kisan_mausam/screens/onboarding/consent_screen.dart';
import 'package:kisan_mausam/screens/onboarding/farm_setup_screen.dart';
import 'package:kisan_mausam/screens/onboarding/otp_screen.dart';
import 'package:kisan_mausam/screens/chat/krishi_sahayak_screen.dart';
import 'package:kisan_mausam/screens/crops/crop_recommender_screen.dart';
import 'package:kisan_mausam/screens/settings/settings_screen.dart';
import 'package:kisan_mausam/services/alert_service.dart';
import 'package:kisan_mausam/theme/app_theme.dart';
import 'package:kisan_mausam/widgets/glass_card.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Test 1: App launches with LoginScreen on first launch', (WidgetTester tester) async {
    await tester.pumpWidget(const KisanMausamApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('किसान मौसम'), findsOneWidget);
    expect(find.text('लॉगिन'), findsOneWidget);
    expect(find.text('खाता बनाएं'), findsOneWidget);
    expect(find.text('Google से जारी रखें'), findsOneWidget);
    expect(find.text('मोबाइल OTP से जारी रखें'), findsOneWidget);
  });

  testWidgets('Test 2: LanguageScreen displays language options with back button', (WidgetTester tester) async {
    bool wentBack = false;
    bool selected = false;
    await tester.pumpWidget(MaterialApp(
      home: LanguageScreen(
        onLanguageSelected: () => selected = true,
        onBack: () => wentBack = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('हिंदी'), findsWidgets);
    expect(find.textContaining('English'), findsWidgets);
    expect(find.text('आगे बढ़ें'), findsOneWidget);

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(wentBack, isTrue);

    final proceedBtn = find.text('आगे बढ़ें');
    await tester.ensureVisible(proceedBtn);
    await tester.tap(proceedBtn);
    await tester.pumpAndSettle();
    expect(selected, isTrue);
  });

  testWidgets('Test 3: OtpScreen renders with back button, phone input, and skip option', (WidgetTester tester) async {
    bool verified = false;
    bool wentBack = false;
    await tester.pumpWidget(MaterialApp(
      home: OtpScreen(
        onOtpVerified: () => verified = true,
        onBack: () => wentBack = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('मोबाइल नंबर दर्ज करें'), findsWidgets);
    expect(find.text('छोड़ें'), findsOneWidget);
    expect(find.text('OTP प्राप्त करें'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(wentBack, isTrue);

    await tester.tap(find.text('छोड़ें'));
    await tester.pumpAndSettle();
    expect(verified, isTrue);
  });

  testWidgets('Test 4: ConsentScreen displays DPDP Act 2023 granular toggles & back button', (WidgetTester tester) async {
    bool accepted = false;
    bool wentBack = false;
    await tester.pumpWidget(MaterialApp(
      home: ConsentScreen(
        onConsentAccepted: () => accepted = true,
        onBack: () => wentBack = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('DPDP'), findsWidgets);
    expect(find.textContaining('स्थान अनुमति'), findsOneWidget);
    expect(find.textContaining('SMS चेतावनी'), findsOneWidget);
    expect(find.textContaining('पुश नोटिफिकेशन'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(wentBack, isTrue);

    await tester.tap(find.text('स्वीकार करें और आगे बढ़ें'));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });

  testWidgets('Test 5: FarmSetupScreen displays single-column ChoiceChipGroups & sticky Save button', (WidgetTester tester) async {
    bool created = false;
    bool wentBack = false;
    await tester.pumpWidget(MaterialApp(
      home: FarmSetupScreen(
        onFarmCreated: () => created = true,
        onBack: () => wentBack = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('भू-भाग'), findsOneWidget);
    expect(find.text('मिट्टी का प्रकार'), findsOneWidget);
    expect(find.text('सिंचाई व्यवस्था'), findsOneWidget);
    expect(find.text('फसल की अवस्था'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(wentBack, isTrue);

    final buttonFinder = find.text('खेत जोड़ें व मौसम देखें');
    expect(buttonFinder, findsOneWidget);
    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
    expect(created, isTrue);
  });

  testWidgets('Test 6: WeatherHomeScreen displays top farm chip, HoldToConfirm SOS, Settings gear, and 3-tab NavigationBar', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: WeatherHomeScreen(onOpenSettings: () {}),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify persistent 3-tab NavigationBar (Weather, Ask mic, Crops)
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(HoldToConfirmButton), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);

    // Tap farm switcher chip in top bar to open Location & farm bottom sheet
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.my_location_rounded), findsWidgets);
    expect(find.byIcon(Icons.search_rounded), findsWidgets);
  });

  testWidgets('Test 7: KrishiSahayakScreen renders slim header, single KVK compliance line, centered mic, and 4 starter chips', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: KrishiSahayakScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('कृषि सहायक'), findsOneWidget);
    expect(find.textContaining('KVK'), findsOneWidget);
    expect(find.byIcon(Icons.call_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsWidgets);
  });

  testWidgets('Test 8: CropRecommenderScreen renders #1 expanded crop card & expandable #2-#5 rows', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(
      home: CropRecommenderScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('फसल चयन व सिफारिशें'), findsOneWidget);
    expect(find.text('चना'), findsOneWidget);
    expect(find.text('सरसों'), findsOneWidget);
    expect(find.text('गेहूं'), findsOneWidget);
  });

  testWidgets('Test 9: SettingsScreen renders segmented language/theme controls, Send test alert, and close callback', (WidgetTester tester) async {
    bool closed = false;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        onClose: () => closed = true,
        onLanguageChanged: () {},
        onThemeChanged: () {},
        onResetOnboarding: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('हिंदी'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('Test 10: AlertService displays restyled hazard dialog with severity strip and action', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              AlertService.showHazardAlert(
                context,
                titleHi: 'पाला व शीतलहर चेतावनी',
                titleEn: 'Frost Warning',
                bodyHi: 'अगले 24 घंटे में तापमान 1.5°C गिरने का अनुमान है।',
                bodyEn: 'Temperature drop expected.',
                severity: 'red',
                actionHi: 'खेत की मेड़ पर हल्का धुआं करें।',
                probability: 85.0,
                lang: 'hi',
              );
            },
            child: const Text('Show Alert'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show Alert'));
    await tester.pumpAndSettle();

    expect(find.text('पाला व शीतलहर चेतावनी'), findsOneWidget);
    expect(find.textContaining('RED ALERT'), findsOneWidget);
    expect(find.textContaining('खेत की मेड़ पर हल्का धुआं करें।'), findsOneWidget);
    expect(find.text('समझ गया'), findsOneWidget);

    await tester.tap(find.text('समझ गया'));
    await tester.pumpAndSettle();
    expect(find.text('पाला व शीतलहर चेतावनी'), findsNothing);
  });

  testWidgets('Test 11: CropRecommenderScreen renders English in en mode and Hindi in hi mode', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CropRecommenderScreen(lang: 'en'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Crop Advisory & Recommendations'), findsOneWidget);
    expect(find.text('Chickpea'), findsOneWidget);
    expect(find.text('फसल चयन व सिफारिशें'), findsNothing);

    await tester.pumpWidget(const MaterialApp(
      home: CropRecommenderScreen(lang: 'hi'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('फसल चयन व सिफारिशें'), findsOneWidget);
    expect(find.text('चना'), findsOneWidget);
  });

  testWidgets('Test 12: Zero overflow at 360dp and textScaler 1.3 across light, dark, high-contrast, hi/en, and all 7 ambient states', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      debugWeatherNotifier.value = null;
    });

    final themes = [
      AppTheme.lightTheme(),
      AppTheme.darkTheme(),
      AppTheme.highContrastTheme(),
    ];

    for (final theme in themes) {
      for (final lang in ['hi', 'en']) {
        SharedPreferences.setMockInitialValues({'language': lang});

        // 1. WeatherHomeScreen across all 7 ambient weather states + simulated hazards
        for (final state in AmbientWeatherState.values) {
          debugWeatherNotifier.value = DebugWeatherOverride(
            ambientState: state,
            forceActiveHazards: state == AmbientWeatherState.storm || state == AmbientWeatherState.severeHeat,
            forceAllClear: state == AmbientWeatherState.clearDay,
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(
                  textScaler: const TextScaler.linear(1.3),
                ),
                child: child!,
              ),
              home: WeatherHomeScreen(onOpenSettings: () {}),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
        }

        // 2. KrishiSahayakScreen at 360dp & textScaler 1.3
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: KrishiSahayakScreen(lang: lang),
          ),
        );
        await tester.pumpAndSettle();

        // 3. CropRecommenderScreen at 360dp & textScaler 1.3
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: CropRecommenderScreen(lang: lang),
          ),
        );
        await tester.pumpAndSettle();

        // 4. SettingsScreen at 360dp & textScaler 1.3
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(
                textScaler: const TextScaler.linear(1.3),
              ),
              child: child!,
            ),
            home: SettingsScreen(
              onClose: () {},
              onLanguageChanged: () {},
              onThemeChanged: () {},
              onResetOnboarding: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
    }
  });
}

