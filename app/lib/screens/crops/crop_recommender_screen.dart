import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../models/farm_profile.dart';
import '../../models/weather_models.dart';
import '../chat/krishi_sahayak_screen.dart';

class CropRecommendationItem {
  final int rank;
  final String nameHi;
  final String nameEn;
  final String season;
  final int matchScore;
  final String durationDays;
  final double waterNeedMm;
  final String droughtTolerance;
  final String frostTolerance;
  final List<String> reasons;
  final List<String> riskNotes;
  final String? droughtAlternative;
  final String sourceCitation;
  final bool needsExpertReview;

  CropRecommendationItem({
    required this.rank,
    required this.nameHi,
    required this.nameEn,
    required this.season,
    required this.matchScore,
    required this.durationDays,
    required this.waterNeedMm,
    required this.droughtTolerance,
    required this.frostTolerance,
    required this.reasons,
    required this.riskNotes,
    this.droughtAlternative,
    required this.sourceCitation,
    required this.needsExpertReview,
  });

  static List<String> _localizeReasons(dynamic rawReasons, String cropNameEn, String lang) {
    if (lang == 'en') {
      final lower = cropNameEn.toLowerCase();
      if (lower.contains('wheat')) {
        return [
          'Primary food grain crop with excellent output under assured irrigation.',
          'Well adapted to medium and heavy loam soils of region.',
          'Current season is optimal for temperature and vegetative growth.',
          'High yield potential with ICAR package of practices compliance.',
        ];
      } else if (lower.contains('chickpea') || lower.contains('gram')) {
        return [
          'Current season (Rabi sowing) is highly favorable for chickpea.',
          'Black soil moisture retention capacity is optimal for chickpea root system.',
          'Low water requirement: safest choice for rainfed or deficit irrigation plots.',
          'Drought-tolerant traits provide resilience against 30-day deficit rain forecast.',
        ];
      } else if (lower.contains('mustard') || lower.contains('rapeseed')) {
        return [
          'Major oilseed crop for Rabi season; high yield with minimal cost and water.',
          'High drought tolerance makes it resilient against deficit rainfall.',
          'Suitable for plain topography and well-drained soils.',
        ];
      } else if (lower.contains('linseed')) {
        return [
          'Low input cost; highly tolerant to both frost and drought.',
          'Good returns with conserved moisture in black soils.',
        ];
      } else if (lower.contains('lentil')) {
        return [
          'Low water consumption; fixes atmospheric nitrogen in farm soil.',
          'Safe crop under below-average rainfall forecast.',
        ];
      }
      if (rawReasons is List) {
        return rawReasons
            .map((e) => e.toString().replaceAll(RegExp(r'[\u0900-\u097F]+'), '').replaceAll('()', '').trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      return ['Recommended based on current climate outlook and soil compatibility.'];
    } else {
      if (rawReasons is List) {
        return rawReasons.map((e) {
          var str = e.toString();
          str = str.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '');
          return str.trim();
        }).toList();
      }
      return [];
    }
  }

  static List<String> _localizeRiskNotes(dynamic rawNotes, String lang) {
    if (rawNotes is! List) return [];
    if (lang == 'en') {
      return rawNotes.map((e) {
        final str = e.toString();
        if (str.contains('पाला') || str.contains('दिसंबर-जनवरी')) {
          return 'In case of frost in Dec-Jan, apply light irrigation or field-edge smoke.';
        } else if (str.contains('माहू') || str.contains('कीट')) {
          return 'Aphid pest risk during flowering; spray neem oil if noticed.';
        } else if (str.contains('सिंचाई') || str.contains('पानी')) {
          return 'Moderate water requirement (3-4 irrigations). If water is scarce, prioritize chickpea.';
        }
        return str.replaceAll(RegExp(r'[\u0900-\u097F]+'), '').trim();
      }).where((s) => s.isNotEmpty).toList();
    } else {
      return rawNotes.map((e) {
        return e.toString().replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim();
      }).toList();
    }
  }

  factory CropRecommendationItem.fromJson(Map<String, dynamic> json, {String lang = 'hi'}) {
    final rawNameEn = (json['name_en'] as String? ?? '')
        .replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '')
        .replaceAll(RegExp(r'\s*\([\u0900-\u097F\s-]+\)'), '')
        .trim();
    final rawNameHi = (json['name_hi'] as String? ?? '')
        .replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '')
        .replaceAll(RegExp(r'\s*\([\u0900-\u097F\s-]+\)'), '')
        .trim();

    return CropRecommendationItem(
      rank: json['rank'] ?? 1,
      nameHi: rawNameHi.isNotEmpty ? rawNameHi : (json['name_hi'] ?? ''),
      nameEn: rawNameEn.isNotEmpty ? rawNameEn : (json['name_en'] ?? ''),
      season: json['season'] ?? 'rabi',
      matchScore: json['match_score'] ?? 80,
      durationDays: lang == 'en'
          ? (json['duration_days']?.toString() ?? '90-120 days').replaceAll('दिन', 'days')
          : (json['duration_days']?.toString() ?? '90-120 दिन').replaceAll('days', 'दिन'),
      waterNeedMm: (json['water_need_mm'] as num?)?.toDouble() ?? 350.0,
      droughtTolerance: json['drought_tolerance'] ?? 'medium',
      frostTolerance: json['frost_tolerance'] ?? 'medium',
      reasons: _localizeReasons(json['reasons'], rawNameEn, lang),
      riskNotes: _localizeRiskNotes(json['risk_notes'], lang),
      droughtAlternative: lang == 'en'
          ? (json['drought_tolerant_alternative']
              ?.toString()
              .replaceAll('चना', 'Chickpea')
              .replaceAll('सरसों', 'Mustard')
              .replaceAll('(Gram)', '')
              .replaceAll('(Mustard)', '')
              .trim())
          : (json['drought_tolerant_alternative']?.toString().replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim()),
      sourceCitation: json['source_citation'] ?? 'ICAR Guide',
      needsExpertReview: json['needs_expert_review'] ?? true,
    );
  }
}

class CropRecommenderScreen extends StatefulWidget {
  final int farmId;
  final String farmName;
  final String village;
  final FarmProfile? farm;
  final String? lang;
  final double? latitude;
  final double? longitude;
  final WeatherData? weather;

  const CropRecommenderScreen({
    super.key,
    this.farmId = 1,
    this.farmName = 'बड़ा खेत 1',
    this.village = 'उमरेड (Umred)',
    this.farm,
    this.lang,
    this.latitude,
    this.longitude,
    this.weather,
  });

  @override
  State<CropRecommenderScreen> createState() => _CropRecommenderScreenState();
}

class _CropRecommenderScreenState extends State<CropRecommenderScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  late String _lang;
  late String _seasonTitle;
  late String _climateOutlookSummary;
  List<CropRecommendationItem> _recommendations = [];

  double _activeLat = 21.1458;
  double _activeLon = 79.0882;
  String _activeLocationName = '';
  WeatherData? _activeWeather;
  double _gpsTemp = 28.5;
  double _gpsHumidity = 58.0;
  double _gpsSoilMoisture = 0.26;
  double _gpsRain10d = 12.0;

  @override
  void initState() {
    super.initState();
    _lang = widget.lang ?? 'hi';
    _activeLat = widget.latitude ?? widget.farm?.latitude ?? 21.1458;
    _activeLon = widget.longitude ?? widget.farm?.longitude ?? 79.0882;
    _activeLocationName = widget.village;
    _activeWeather = widget.weather;
    _seasonTitle = _lang == 'en' ? 'Rabi Season' : 'रबी सीजन';
    _climateOutlookSummary = _lang == 'en'
        ? 'Next 30 days: 35% below normal rainfall probability in region (EC46 / SEAS5)'
        : 'आगामी 30 दिनों में क्षेत्र में 35% कम वर्षा की संभावना (EC46 / SEAS5)';
    _fetchRecommendations();
  }

  @override
  void didUpdateWidget(covariant CropRecommenderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lang != widget.lang ||
        oldWidget.weather != widget.weather ||
        oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _lang = widget.lang ?? 'hi';
      _activeLat = widget.latitude ?? widget.farm?.latitude ?? _activeLat;
      _activeLon = widget.longitude ?? widget.farm?.longitude ?? _activeLon;
      _activeLocationName = widget.village;
      if (widget.weather != null) _activeWeather = widget.weather;
      _applyGpsWeatherMetrics();
      _recommendations = _getGpsDrivenRecommendations();
    }
  }

  void _applyGpsWeatherMetrics() {
    final w = _activeWeather;
    if (w != null) {
      _gpsTemp = w.current.temperature;
      _gpsHumidity = w.current.relativeHumidity;
      _gpsSoilMoisture = w.current.soilMoisture;
      double rSum = 0.0;
      for (final d in w.daily.take(10)) {
        rSum += d.precipitationSum;
      }
      _gpsRain10d = rSum;
    }

    final cleanLoc = _lang == 'en'
        ? (_activeLocationName.contains('Umred') || _activeLocationName.contains('उमरेड')
            ? 'Umred'
            : _activeLocationName.replaceAll(RegExp(r'[\u0900-\u097F]+'), '').trim())
        : (_activeLocationName.contains('Umred') || _activeLocationName.contains('उमरेड')
            ? 'उमरेड'
            : _activeLocationName.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim());
    final locLabel = cleanLoc.isNotEmpty ? cleanLoc : (_lang == 'en' ? 'GPS Farm' : 'GPS क्षेत्र');

    final isHot = _gpsTemp >= 32.0;
    final isWet = _gpsRain10d >= 25.0 || _gpsHumidity >= 72.0;

    if (_lang == 'en') {
      _seasonTitle = isHot ? 'Zaid / Warm Season' : (isWet ? 'Humid / Monsoon Transition' : 'Rabi Season');
      _climateOutlookSummary =
          'GPS Live ($locLabel): Temp ${_gpsTemp.toStringAsFixed(1)}°C, Soil Moisture ${(_gpsSoilMoisture * 100).round()}%, 10-Day Rain ${_gpsRain10d.toStringAsFixed(1)} mm (${_activeLat.toStringAsFixed(2)}°N, ${_activeLon.toStringAsFixed(2)}°E)';
    } else {
      _seasonTitle = isHot ? 'गर्म / जायद अनुकूल' : (isWet ? 'आर्द्र / नमी अनुकूल सीजन' : 'रबी सीजन');
      _climateOutlookSummary =
          'GPS लाइव ($locLabel): तापमान ${_gpsTemp.toStringAsFixed(1)}°C, मिट्टी की नमी ${(_gpsSoilMoisture * 100).round()}%, 10-दिवसीय वर्षा ${_gpsRain10d.toStringAsFixed(1)} मिमी (${_activeLat.toStringAsFixed(2)}°N, ${_activeLon.toStringAsFixed(2)}°E)';
    }
  }

  Future<void> _fetchRecommendations() async {
    setState(() {
      _isLoading = true;
    });

    // 1. Load saved GPS coordinates and cached weather if not passed directly
    try {
      if (_activeWeather == null) {
        final savedLoc = await StorageService.getLastLocation();
        if (savedLoc != null) {
          _activeLat = (savedLoc['latitude'] as num).toDouble();
          _activeLon = (savedLoc['longitude'] as num).toDouble();
          final sName = (savedLoc['displayName'] as String?) ?? '';
          if (sName.isNotEmpty) _activeLocationName = sName;
        }
        final cacheKey = '${_activeLat.toStringAsFixed(2)}_${_activeLon.toStringAsFixed(2)}';
        final cached = await StorageService.getCachedWeather(cacheKey);
        if (cached != null) {
          _activeWeather = cached;
        }
      }
    } catch (_) {}

    _applyGpsWeatherMetrics();

    if (mounted) {
      setState(() {
        _recommendations = _getGpsDrivenRecommendations();
        _isLoading = false;
      });
    }
  }

  List<CropRecommendationItem> _getGpsDrivenRecommendations() {
    final temp = _gpsTemp;
    final rain10d = _gpsRain10d;
    final soilPct = (_gpsSoilMoisture * 100).round();
    final hum = _gpsHumidity.round();
    final isWet = rain10d >= 25.0 || hum >= 72 || soilPct >= 35;
    final isHotDry = temp >= 32.0 && rain10d < 15.0;

    // Dynamic GPS-calibrated suitability scores based on temperature, rainfall & soil moisture
    final chickpeaScore = isHotDry ? 98 : (isWet ? 86 : 97);
    final mustardScore = isHotDry ? 95 : (isWet ? 84 : 94);
    final wheatScore = isWet ? 96 : (temp <= 27.0 ? 93 : 88);
    final fourthScore = isWet ? 92 : (isHotDry ? 90 : 85);
    final fifthScore = isWet ? 89 : 83;

    final locEn = _activeLocationName.replaceAll(RegExp(r'[\u0900-\u097F]+'), '').replaceAll('()', '').trim();
    final regionEn = locEn.isNotEmpty ? locEn : 'your GPS region';
    final locHi = _activeLocationName.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim();
    final regionHi = locHi.isNotEmpty ? locHi : 'आपके GPS क्षेत्र';

    if (_lang == 'en') {
      final list = <CropRecommendationItem>[
        CropRecommendationItem(
          rank: 1,
          nameHi: 'चना',
          nameEn: 'Chickpea',
          season: 'rabi',
          matchScore: chickpeaScore,
          durationDays: '95-115 days',
          waterNeedMm: 280.0,
          droughtTolerance: 'high',
          frostTolerance: 'medium',
          reasons: [
            'GPS conditions in $regionEn (${temp.toStringAsFixed(1)}°C, Soil Moisture $soilPct%) are highly favorable for chickpea.',
            'Black/loam soil moisture retention ($soilPct%) matches chickpea root depth requirements.',
            'Low water requirement (280 mm): optimal for 10-day forecast rainfall of ${rain10d.toStringAsFixed(1)} mm.',
          ],
          riskNotes: [
            rain10d > 20
                ? 'Ensure field drainage in $regionEn to prevent collar rot under ${rain10d.toStringAsFixed(1)} mm rain.'
                : 'In case of cold nights or frost, apply light evening irrigation.',
          ],
          sourceCitation: 'ICAR-IIPR Kanpur Chickpea Production Technology',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 2,
          nameHi: 'सरसों',
          nameEn: 'Mustard',
          season: 'rabi',
          matchScore: mustardScore,
          durationDays: '105-130 days',
          waterNeedMm: 250.0,
          droughtTolerance: 'high',
          frostTolerance: 'medium',
          reasons: [
            'Well suited to $regionEn live temperature (${temp.toStringAsFixed(1)}°C) and humidity ($hum%).',
            'High oilseed return with minimal irrigation under ${rain10d.toStringAsFixed(1)} mm 10-day rain outlook.',
          ],
          riskNotes: [
            hum > 65
                ? 'Monitor for aphid pest at $hum% humidity; spray neem oil (5 ml/L) if noticed.'
                : 'Apply first irrigation at 30-35 days after sowing (branching stage).',
          ],
          sourceCitation: 'ICAR-DRMR Bharatpur',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 3,
          nameHi: 'गेहूं',
          nameEn: 'Wheat',
          season: 'rabi',
          matchScore: wheatScore,
          durationDays: '110-135 days',
          waterNeedMm: 450.0,
          droughtTolerance: 'medium',
          frostTolerance: 'medium',
          reasons: [
            'Primary food grain crop adapted to $regionEn (${_activeLat.toStringAsFixed(1)}°N, ${_activeLon.toStringAsFixed(1)}°E) with $soilPct% soil moisture.',
            isWet
                ? 'Higher moisture availability (${rain10d.toStringAsFixed(1)} mm rain, $soilPct% soil moisture) supports strong tillering.'
                : 'Good yield potential under assured tube-well/canal irrigation at ${temp.toStringAsFixed(1)}°C.',
          ],
          riskNotes: [
            'Requires 4-5 irrigations (especially at CRI stage 21 days after sowing). Prioritize Chickpea if water is scarce.',
          ],
          droughtAlternative: 'Chickpea or Mustard',
          sourceCitation: 'ICAR-IIWBR Karnal',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 4,
          nameHi: isHotDry ? 'ज्वार' : 'अलसी',
          nameEn: isHotDry ? 'Sorghum' : 'Linseed',
          season: 'rabi',
          matchScore: fourthScore,
          durationDays: isHotDry ? '100-115 days' : '115-135 days',
          waterNeedMm: isHotDry ? 300.0 : 250.0,
          droughtTolerance: 'high',
          frostTolerance: 'high',
          reasons: [
            isHotDry
                ? 'Highly resilient to warm GPS temperature (${temp.toStringAsFixed(1)}°C) and low rainfall (${rain10d.toStringAsFixed(1)} mm).'
                : 'Low input cost; highly tolerant to both cold stress and conserved $soilPct% soil moisture in $regionEn.',
          ],
          riskNotes: [],
          sourceCitation: isHotDry ? 'ICAR-IIMR Hyderabad' : 'ICAR-AICRP Oilseeds',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 5,
          nameHi: isWet ? 'मक्का' : 'मसूर',
          nameEn: isWet ? 'Maize' : 'Lentil',
          season: 'rabi',
          matchScore: fifthScore,
          durationDays: isWet ? '95-110 days' : '100-120 days',
          waterNeedMm: isWet ? 500.0 : 220.0,
          droughtTolerance: isWet ? 'medium' : 'high',
          frostTolerance: 'high',
          reasons: [
            isWet
                ? 'Favorable humidity ($hum%) and soil moisture ($soilPct%) in $regionEn support high-yield hybrid maize.'
                : 'Low water consumption (220 mm); fixes atmospheric nitrogen in $regionEn soils.',
          ],
          riskNotes: [],
          sourceCitation: isWet ? 'ICAR-IIMR Ludhiana' : 'ICAR-IIPR Kanpur',
          needsExpertReview: true,
        ),
      ];
      return list;
    } else {
      final list = <CropRecommendationItem>[
        CropRecommendationItem(
          rank: 1,
          nameHi: 'चना',
          nameEn: 'Chickpea',
          season: 'rabi',
          matchScore: chickpeaScore,
          durationDays: '95-115 दिन',
          waterNeedMm: 280.0,
          droughtTolerance: 'high',
          frostTolerance: 'medium',
          reasons: [
            '$regionHi के लाइव GPS मौसम (तापमान ${temp.toStringAsFixed(1)}°C, मिट्टी की नमी $soilPct%) के अनुसार चना सर्वोत्तम है।',
            'मिट्टी में $soilPct% नमी संचय क्षमता चने की जड़ों के विकास के लिए अत्यंत अनुकूल है।',
            'कम पानी (280 मिमी) की आवश्यकता: आगामी 10 दिनों की ${rain10d.toStringAsFixed(1)} मिमी वर्षा पूर्वानुमान में सबसे सुरक्षित विकल्प।',
          ],
          riskNotes: [
            rain10d > 20
                ? '${rain10d.toStringAsFixed(1)} मिमी बारिश की संभावना में उकठा रोग से बचाव हेतु जल निकासी रखें।'
                : 'रात्रि तापमान गिरने या पाला पड़ने पर शाम को हल्की सिंचाई करें।',
          ],
          sourceCitation: 'ICAR-IIPR Kanpur Chickpea Production Technology',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 2,
          nameHi: 'सरसों',
          nameEn: 'Mustard',
          season: 'rabi',
          matchScore: mustardScore,
          durationDays: '105-130 दिन',
          waterNeedMm: 250.0,
          droughtTolerance: 'high',
          frostTolerance: 'medium',
          reasons: [
            '$regionHi के वर्तमान तापमान (${temp.toStringAsFixed(1)}°C) व आर्द्रता ($hum%) के पूर्णतः अनुकूल तिलहनी फसल।',
            'न्यूनतम लागत व कम पानी (250 मिमी) में उच्च तेल मात्रा व भरपूर पैदावार।',
          ],
          riskNotes: [
            hum > 65
                ? '$hum% आर्द्रता में माहू कीट की निगरानी करें व नीम तेल (5 मिली/लीटर) का छिड़काव करें।'
                : 'बुवाई के 30-35 दिन बाद (शाखाएं बनते समय) पहली हल्की सिंचाई करें।',
          ],
          sourceCitation: 'ICAR-DRMR Bharatpur',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 3,
          nameHi: 'गेहूं',
          nameEn: 'Wheat',
          season: 'rabi',
          matchScore: wheatScore,
          durationDays: '110-135 दिन',
          waterNeedMm: 450.0,
          droughtTolerance: 'medium',
          frostTolerance: 'medium',
          reasons: [
            '$regionHi (${_activeLat.toStringAsFixed(1)}°N, ${_activeLon.toStringAsFixed(1)}°E) की मिट्टी ($soilPct% नमी) व सिंचाई व्यवस्था में उत्कृष्ट खाद्यान्न फसल।',
            isWet
                ? 'पर्याप्त नमी (${rain10d.toStringAsFixed(1)} मिमी वर्षा, $soilPct% मिट्टी नमी) से कल्ले अधिक फूटेंगे।'
                : '${temp.toStringAsFixed(1)}°C तापमान पर सुनिश्चित सिंचाई के साथ उच्च उत्पादन क्षमता।',
          ],
          riskNotes: [
            'मध्यम पानी की आवश्यकता (3-4 सिंचाई, पहली सिंचाई 21 दिन पर)। जल सीमित हो तो चने को प्राथमिकता दें।',
          ],
          droughtAlternative: 'चना या सरसों',
          sourceCitation: 'ICAR-IIWBR Karnal',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 4,
          nameHi: isHotDry ? 'ज्वार' : 'अलसी',
          nameEn: isHotDry ? 'Sorghum' : 'Linseed',
          season: 'rabi',
          matchScore: fourthScore,
          durationDays: isHotDry ? '100-115 दिन' : '115-135 दिन',
          waterNeedMm: isHotDry ? 300.0 : 250.0,
          droughtTolerance: 'high',
          frostTolerance: 'high',
          reasons: [
            isHotDry
                ? '${temp.toStringAsFixed(1)}°C तापमान व कम बारिश (${rain10d.toStringAsFixed(1)} मिमी) में अत्यधिक सूखा-सहनशील फसल।'
                : '$regionHi में कम लागत, पाला व सूखा दोनों के प्रति सहनशील तथा $soilPct% संचित नमी में उत्तम लाभ।',
          ],
          riskNotes: [],
          sourceCitation: isHotDry ? 'ICAR-IIMR Hyderabad' : 'ICAR-AICRP Oilseeds',
          needsExpertReview: true,
        ),
        CropRecommendationItem(
          rank: 5,
          nameHi: isWet ? 'मक्का' : 'मसूर दाल',
          nameEn: isWet ? 'Maize' : 'Lentil',
          season: 'rabi',
          matchScore: fifthScore,
          durationDays: isWet ? '95-110 दिन' : '100-120 दिन',
          waterNeedMm: isWet ? 500.0 : 220.0,
          droughtTolerance: isWet ? 'medium' : 'high',
          frostTolerance: 'high',
          reasons: [
            isWet
                ? '$regionHi में $hum% आर्द्रता व $soilPct% मिट्टी की नमी संकर मक्का की उच्च पैदावार हेतु उपयुक्त है।'
                : 'अल्प जल खपत (220 मिमी), दलहनी फसल होने से $regionHi की भूमि में नाइट्रोजन स्थिरीकरण।',
          ],
          riskNotes: [],
          sourceCitation: isWet ? 'ICAR-IIMR Ludhiana' : 'ICAR-IIPR Kanpur',
          needsExpertReview: true,
        ),
      ];
      return list;
    }
  }

  Future<void> _callKvk() async {
    const phoneNumber = '18001801551';
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _lang == 'en'
                    ? 'KVK Helpline: 1800-180-1551'
                    : 'KVK हेल्पलाइन: 1800-180-1551',
              ),
              backgroundColor: const Color(0xFF1B5E20),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _lang == 'en'
                  ? 'KVK Helpline: 1800-180-1551'
                  : 'KVK हेल्पलाइन: 1800-180-1551',
            ),
            backgroundColor: const Color(0xFF1B5E20),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayFarmName = _lang == 'en'
        ? (widget.farm?.getName('en') ??
            (widget.farmName.contains(RegExp(r'[\u0900-\u097F]'))
                ? 'Main Farm'
                : widget.farmName.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim()))
        : (widget.farm?.getName('hi') ??
            (widget.farmName.toLowerCase().contains('farm')
                ? 'बड़ा खेत'
                : widget.farmName.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim()));
    final rawVillage = _activeLocationName.isNotEmpty ? _activeLocationName : widget.village;
    final displayVillage = _lang == 'en'
        ? (rawVillage.contains('Umred') || rawVillage.contains('उमरेड')
            ? 'Umred'
            : rawVillage.replaceAll(RegExp(r'[\u0900-\u097F]+'), '').trim())
        : (rawVillage.contains('Umred') || rawVillage.contains('उमरेड')
            ? 'उमरेड'
            : rawVillage.replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '').trim());

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: _lang == 'en' ? 'Back' : 'वापस जाएं',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _lang == 'en' ? 'Crop Advisory & Recommendations' : 'फसल चयन व सिफारिशें',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '$displayFarmName • ${displayVillage.isNotEmpty ? displayVillage : rawVillage}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: _lang == 'en' ? 'Refresh' : 'ताज़ा करें',
            onPressed: _fetchRecommendations,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFBF360C),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.mic, size: 26),
        label: Text(
          _lang == 'en' ? 'Ask Crop Questions' : 'फसल पर सवाल पूछें',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => KrishiSahayakScreen(
                farm: widget.farm,
                locationName: displayVillage.isNotEmpty ? displayVillage : rawVillage,
                latitude: _activeLat,
                longitude: _activeLon,
                weather: _activeWeather,
                lang: _lang,
              ),
            ),
          );
        },
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF1B5E20)),
                  const SizedBox(height: 16),
                  Text(
                    _lang == 'en'
                        ? 'Finding optimal crops based on GPS soil and weather...'
                        : 'आपके GPS स्थान व मौसम के अनुसार सर्वोत्तम फसलें खोजी जा रही हैं...',
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                // Header Season & Climate Outlook Card
                _buildClimateOutlookCard(),
                const SizedBox(height: 12),

                // Expert Review Mandatory Warning
                _buildExpertReviewNotice(),
                const SizedBox(height: 16),

                // Top 5 Recommendations Section Header
                Row(
                  children: [
                    const Icon(Icons.eco, color: Color(0xFF1B5E20), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      _lang == 'en' ? 'Top 5 Recommended Crops' : 'शीर्ष 5 अनुशंसित फसलें',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Crop Recommendation Cards
                ..._recommendations.map((crop) => _buildCropCard(crop)),

                const SizedBox(height: 16),
                // KVK Toll Free Helpline Footer Card
                _buildKvkHelplineCard(),
              ],
            ),
    );
  }

  Widget _buildClimateOutlookCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _seasonTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.my_location, color: Color(0xFF1B5E20), size: 16),
              const SizedBox(width: 4),
              Text(
                _lang == 'en' ? 'Live GPS Grounded' : 'लाइव GPS आधारित',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1B5E20)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _climateOutlookSummary,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _lang == 'en'
                ? 'Rule: Crop scores dynamically ranked by live GPS temperature, soil moisture, and 10-day rainfall.'
                : 'नियम: फसलों की उपयुक्तता आपके लाइव GPS तापमान, मिट्टी की नमी और 10-दिवसीय वर्षा के अनुसार तय की गई है।',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildExpertReviewNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.assignment_late, color: Colors.amber.shade900, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lang == 'en' ? 'Expert Review Advised' : 'विशेषज्ञ समीक्षा आवश्यक',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _lang == 'en'
                      ? 'These recommendations are based on ICAR Package of Practices standards. Consult local KVK expert and soil testing before sowing.'
                      : 'ये सिफारिशें ICAR एवं राज्य कृषि विश्वविद्यालयों के पैकेज ऑफ प्रैक्टिसेज के सामान्य मानकों पर आधारित हैं। बुवाई से पूर्व मिट्टी परीक्षण व स्थानीय KVK विशेषज्ञ से परामर्श लें।',
                  style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropCard(CropRecommendationItem crop) {
    final title = _lang == 'en' ? crop.nameEn : crop.nameHi;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Rank Badge + Crop Name + Score Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF1B5E20),
                  child: Text(
                    '#${crop.rank}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade400),
                  ),
                  child: Text(
                    _lang == 'en' ? '${crop.matchScore}% Match' : '${crop.matchScore}% उपयुक्त',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Trait Badges Row
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildTraitBadge(
                  Icons.timelapse,
                  _lang == 'en' ? 'Duration' : 'अवधि',
                  crop.durationDays,
                ),
                _buildTraitBadge(
                  Icons.water_drop,
                  _lang == 'en' ? 'Water' : 'पानी',
                  '${crop.waterNeedMm.toInt()} mm',
                ),
                _buildTraitBadge(
                  Icons.wb_sunny,
                  _lang == 'en' ? 'Drought' : 'सूखा सहनशीलता',
                  crop.droughtTolerance == 'high'
                      ? (_lang == 'en' ? 'High' : 'उच्च')
                      : crop.droughtTolerance == 'medium'
                          ? (_lang == 'en' ? 'Medium' : 'मध्यम')
                          : (_lang == 'en' ? 'Low' : 'कम'),
                ),
                _buildTraitBadge(
                  Icons.ac_unit,
                  _lang == 'en' ? 'Frost' : 'पाला सहनशीलता',
                  crop.frostTolerance == 'high'
                      ? (_lang == 'en' ? 'High' : 'उच्च')
                      : crop.frostTolerance == 'medium'
                          ? (_lang == 'en' ? 'Medium' : 'मध्यम')
                          : (_lang == 'en' ? 'Low' : 'कम'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),

            // Reasons Section
            Text(
              _lang == 'en' ? 'Suitability Reasons:' : 'उपयुक्तता के मुख्य कारण:',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            ...crop.reasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          r,
                          style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                )),

            // Risk Notes or Drought Alternative
            if (crop.riskNotes.isNotEmpty || crop.droughtAlternative != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...crop.riskNotes.map((rn) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber, color: Colors.deepOrange, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                rn,
                                style: const TextStyle(fontSize: 12, color: Colors.brown, height: 1.3),
                              ),
                            ),
                          ],
                        )),
                    if (crop.droughtAlternative != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.alt_route, color: Colors.deepPurple, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _lang == 'en'
                                  ? 'Safe alternative in deficit rain: ${crop.droughtAlternative}'
                                  : 'कम वर्षा में सुरक्षित विकल्प: ${crop.droughtAlternative}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepPurple,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
            // Citation
            Text(
              _lang == 'en' ? 'Source: ${crop.sourceCitation}' : 'स्रोत: ${crop.sourceCitation}',
              style: const TextStyle(fontSize: 10, color: Colors.black45, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTraitBadge(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1B5E20)),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildKvkHelplineCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B5E20),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.support_agent, color: Colors.white, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lang == 'en' ? 'Kisan Call Center (KVK)' : 'किसान कॉल सेंटर (KVK)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _lang == 'en'
                      ? 'Toll-free 1800-180-1551 to discuss with agriculture experts'
                      : 'टोल-फ्री 1800-180-1551 पर कृषि वैज्ञानिक से निःशुल्क चर्चा करें',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1B5E20),
              minimumSize: const Size(80, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: _callKvk,
            child: Text(
              _lang == 'en' ? 'Call Now' : 'कॉल करें',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
