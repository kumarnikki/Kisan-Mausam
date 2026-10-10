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

    // Verify back button is present and triggers callback
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(wentBack, isTrue);

    // Tap proceed button
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
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // Tap back button
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(wentBack, isTrue);

    // Tap skip
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
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(wentBack, isTrue);

    await tester.tap(find.text('स्वीकार करें और आगे बढ़ें'));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
  });

  testWidgets('Test 5: FarmSetupScreen displays pickers & back button', (WidgetTester tester) async {
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
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(wentBack, isTrue);

    final buttonFinder = find.text('खेत जोड़ें व मौसम देखें');
    expect(buttonFinder, findsOneWidget);
    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
    expect(created, isTrue);
  });

  testWidgets('Test 6: WeatherHomeScreen displays current conditions, GPS & search buttons', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: WeatherHomeScreen(onOpenSettings: () {}),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    // Verify Prominent Mic Button is visible
    expect(find.text('बोलकर पूछें'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);

    // Verify Top Bar elements: GPS my_location button, Search button, Settings button
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
  });

  testWidgets('Test 7: KrishiSahayakScreen renders AI chat, quick chips, back button and KVK helpline', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: KrishiSahayakScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('किसान मौसम कृषि सहायक'), findsOneWidget);
    expect(find.textContaining('ICAR मानक:'), findsOneWidget);
    expect(find.text('क्या आज पानी दूं? 💧'), findsOneWidget);
    expect(find.text('पाले से कैसे बचाएं? ❄️'), findsOneWidget);
    expect(find.byIcon(Icons.phone_in_talk), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('Test 8: CropRecommenderScreen renders top 5 ranked crops & back button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const MaterialApp(
      home: CropRecommenderScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('फसल चयन व सिफारिशें'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.textContaining('विशेषज्ञ समीक्षा आवश्यक'), findsOneWidget);
    expect(find.textContaining('शीर्ष 5 अनुशंसित फसलें'), findsOneWidget);
    expect(find.text('चना'), findsOneWidget);
    expect(find.text('सरसों'), findsOneWidget);
    expect(find.text('गेहूं'), findsOneWidget);
    expect(find.text('फसल पर सवाल पूछें'), findsOneWidget);
  });

  testWidgets('Test 9: SettingsScreen renders with back button and close callback', (WidgetTester tester) async {
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

    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('Test 10: AlertService displays hazard dialog with sound effect action', (WidgetTester tester) async {
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

  testWidgets('Test 11: CropRecommenderScreen renders pure English in English mode and pure Hindi in Hindi mode', (WidgetTester tester) async {
    // English mode
    await tester.pumpWidget(const MaterialApp(
      home: CropRecommenderScreen(lang: 'en'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Crop Advisory & Recommendations'), findsOneWidget);
    expect(find.text('Top 5 Recommended Crops'), findsOneWidget);
    expect(find.text('Chickpea'), findsOneWidget);
    expect(find.text('Call Now'), findsOneWidget);
    expect(find.text('फसल चयन व सिफारिशें'), findsNothing);

    // Hindi mode
    await tester.pumpWidget(const MaterialApp(
      home: CropRecommenderScreen(lang: 'hi'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('फसल चयन व सिफारिशें'), findsOneWidget);
    expect(find.text('शीर्ष 5 अनुशंसित फसलें'), findsOneWidget);
    expect(find.text('कॉल करें'), findsOneWidget);
    expect(find.text('Top 5 Recommended Crops'), findsNothing);
  });
}
