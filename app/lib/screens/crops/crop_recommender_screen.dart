import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/farm_profile.dart';
import '../../models/weather_models.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
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

  static List<String> _localizeReasons(dynamic rawReasons, String nameEn, String lang) {
    if (lang == 'en') {
      final lower = nameEn.toLowerCase();
      if (lower.contains('wheat')) {
        return [
          'Primary food grain crop well-suited for Black/Alluvial soils and canal/tube-well irrigation.',
          'Ideal for Rabi season cool temperature range (12°C - 28°C).',
        ];
      } else if (lower.contains('chickpea') || lower.contains('gram')) {
        return [
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
          : (json['drought_tolerant_alternative']
              ?.toString()
              .replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '')
              .trim()),
      sourceCitation: json['source_citation'] ?? 'ICAR Guide',
      needsExpertReview: json['needs_expert_review'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'name_hi': nameHi,
        'name_en': nameEn,
        'season': season,
        'match_score': matchScore,
        'duration_days': durationDays,
        'water_need_mm': waterNeedMm,
        'drought_tolerance': droughtTolerance,
        'frost_tolerance': frostTolerance,
        'reasons': reasons,
        'risk_notes': riskNotes,
        'drought_tolerant_alternative': droughtAlternative,
        'source_citation': sourceCitation,
        'needs_expert_review': needsExpertReview,
      };
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
  final VoidCallback? onBack;
  final ValueChanged<String>? onAskCrop;

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
    this.onBack,
    this.onAskCrop,
  });

  /// Shared in-memory + StorageService cache so Home (top 3) and Crops (all 5)
  /// reuse the exact same recommendations without a duplicate computation.
  static final Map<String, List<CropRecommendationItem>> _sharedMemoryCache = {};

  static String resolveSeasonBadge({
    required String lang,
    WeatherData? weather,
    String? rawSeason,
  }) {
    final s = (rawSeason ?? '').toLowerCase();
    if (s.contains('kharif') || s.contains('खरीफ')) {
      return lang == 'en' ? 'Kharif' : 'खरीफ';
    }
    if (s.contains('zaid') || s.contains('जायद')) {
      return lang == 'en' ? 'Zaid' : 'जायद';
    }
    final month = DateTime.now().month;
    if (month >= 6 && month <= 9) {
      return lang == 'en' ? 'Kharif' : 'खरीफ';
    }
    return lang == 'en' ? 'Rabi' : 'रबी';
  }

  static Future<List<CropRecommendationItem>> getSharedRecommendations({
    required String lang,
    required double latitude,
    required double longitude,
    required String locationName,
    WeatherData? weather,
  }) async {
    final tempBucket = weather != null ? weather.current.temperature.round() : 28;
    final cacheKey = '${latitude.toStringAsFixed(2)}_${longitude.toStringAsFixed(2)}_${lang}_$tempBucket';

    if (_sharedMemoryCache.containsKey(cacheKey)) {
      return _sharedMemoryCache[cacheKey]!;
    }

    // Check persistent offline cache if weather is not yet available
    if (weather == null) {
      final diskKey = '${latitude.toStringAsFixed(2)}_${longitude.toStringAsFixed(2)}_$lang';
      final cachedMap = await StorageService.getCachedCropRecommendations(diskKey);
      if (cachedMap != null && cachedMap['crops'] is List) {
        final rawList = cachedMap['crops'] as List;
        final items = rawList
            .map((e) => CropRecommendationItem.fromJson(Map<String, dynamic>.from(e as Map), lang: lang))
            .toList();
        if (items.isNotEmpty) {
          _sharedMemoryCache[cacheKey] = items;
          return items;
        }
      }
    }

    final computed = _computeGpsDrivenRecommendationsStatic(
      lang: lang,
      lat: latitude,
      lon: longitude,
      locationName: locationName,
      weather: weather,
    );
    _sharedMemoryCache[cacheKey] = computed;

    final diskKey = '${latitude.toStringAsFixed(2)}_${longitude.toStringAsFixed(2)}_$lang';
    await StorageService.cacheCropRecommendations(
      diskKey,
      computed.map((e) => e.toJson()).toList(),
      season: computed.isNotEmpty ? computed.first.season : 'rabi',
    );
    return computed;
  }

  static List<CropRecommendationItem> _computeGpsDrivenRecommendationsStatic({
    required String lang,
    required double lat,
    required double lon,
    required String locationName,
    WeatherData? weather,
  }) {
    final temp = weather?.current.temperature ?? 28.5;
    final hum = (weather?.current.relativeHumidity ?? 58.0).round();
    final soilPct = ((weather?.current.soilMoisture ?? 0.26) * 100).round();
    double rain10d = 12.0;
    if (weather != null && weather.daily.isNotEmpty) {
      double sum = 0.0;
      for (final d in weather.daily.take(10)) {
        sum += d.precipitationSum;
      }
      rain10d = sum;
    }

    final isWet = rain10d >= 25.0 || hum >= 72 || soilPct >= 35;
    final isHotDry = temp >= 32.0 && rain10d < 15.0;

    final chickpeaScore = isHotDry ? 98 : (isWet ? 86 : 97);
    final mustardScore = isHotDry ? 95 : (isWet ? 84 : 94);
    final wheatScore = isWet ? 96 : (temp <= 27.0 ? 93 : 88);
    final fourthScore = isWet ? 92 : (isHotDry ? 90 : 85);
    final fifthScore = isWet ? 89 : 83;

    final cleanLoc = locationName
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .trim();
    final regionEn = cleanLoc.isNotEmpty ? cleanLoc : 'your GPS region';
    final regionHi = cleanLoc.isNotEmpty ? cleanLoc : 'आपके GPS क्षेत्र';

    if (lang == 'en') {
      return <CropRecommendationItem>[
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
            'Primary food grain crop adapted to $regionEn (${lat.toStringAsFixed(1)}°N, ${lon.toStringAsFixed(1)}°E) with $soilPct% soil moisture.',
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
    } else {
      return <CropRecommendationItem>[
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
            '$regionHi (${lat.toStringAsFixed(1)}°N, ${lon.toStringAsFixed(1)}°E) की मिट्टी ($soilPct% नमी) व सिंचाई व्यवस्था में उत्कृष्ट खाद्यान्न फसल।',
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
                ? '$regionHi में अनुकूल नमी ($hum%) और मिट्टी नमी ($soilPct%) से संकर मक्का की अच्छी उपज।'
                : 'कम पानी की खपत (220 मिमी); मिट्टी में नाइट्रोजन बढ़ाती है।',
          ],
          riskNotes: [],
          sourceCitation: isWet ? 'ICAR-IIMR Ludhiana' : 'ICAR-IIPR Kanpur',
          needsExpertReview: true,
        ),
      ];
    }
  }

  @override
  State<CropRecommenderScreen> createState() => _CropRecommenderScreenState();
}

class _CropRecommenderScreenState extends State<CropRecommenderScreen> {
  // ignore: unused_field
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  late String _lang;
  late String _seasonTitle;
  List<CropRecommendationItem> _recommendations = [];
  final Set<int> _expandedRanks = {};

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
      setState(() {
        _recommendations = _getGpsDrivenRecommendations();
      });
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

    final isHot = _gpsTemp >= 32.0;
    final isWet = _gpsRain10d >= 25.0 || _gpsHumidity >= 72.0;

    if (_lang == 'en') {
      _seasonTitle = isHot
          ? 'Zaid / Warm Season'
          : (isWet ? 'Humid / Monsoon Transition' : 'Rabi Season');
    } else {
      _seasonTitle = isHot
          ? 'गर्म / जायद अनुकूल'
          : (isWet ? 'आर्द्र / नमी अनुकूल सीजन' : 'रबी सीजन');
    }
  }

  Future<void> _fetchRecommendations() async {
    setState(() {
      _isLoading = true;
    });

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

    final shared = await CropRecommenderScreen.getSharedRecommendations(
      lang: _lang,
      latitude: _activeLat,
      longitude: _activeLon,
      locationName: _activeLocationName,
      weather: _activeWeather,
    );

    if (mounted) {
      setState(() {
        _recommendations = shared;
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

    final chickpeaScore = isHotDry ? 98 : (isWet ? 86 : 97);
    final mustardScore = isHotDry ? 95 : (isWet ? 84 : 94);
    final wheatScore = isWet ? 96 : (temp <= 27.0 ? 93 : 88);
    final fourthScore = isWet ? 92 : (isHotDry ? 90 : 85);
    final fifthScore = isWet ? 89 : 83;

    final regionEn = _resolveDisplayLocation(true, fallback: 'your GPS region');
    final regionHi = _resolveDisplayLocation(false, fallback: 'आपके GPS क्षेत्र');

    if (_lang == 'en') {
      return <CropRecommendationItem>[
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
    } else {
      return <CropRecommendationItem>[
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
    }
  }

  Future<void> _callKvk() async {
    const phoneNumber = '18001801551';
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _lang == 'en'
              ? 'KVK Helpline: 1800-180-1551'
              : 'KVK हेल्पलाइन: 1800-180-1551',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showIcarExpertNoticeSheet() {
    final isEn = _lang == 'en';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SheetScaffold(
        title: isEn
            ? 'ICAR / KVK Expert Review Notice'
            : 'विशेषज्ञ समीक्षा आवश्यक (ICAR / KVK मानक)',
        subtitle: isEn
            ? 'Scientific crop suitability & local agronomy verification'
            : 'वैज्ञानिक फसल उपयुक्तता एवं स्थानीय कृषि सत्यापन',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEn
                  ? 'These crop recommendations are calibrated from live Open-Meteo GPS weather, root-zone soil moisture, and ICAR package of practices. Before purchasing seeds or applying fertilizers, please confirm seed varieties with your local Krishi Vigyan Kendra (KVK).'
                  : 'ये फसल सिफारिशें लाइव GPS मौसम, मिट्टी की नमी और ICAR कृषि मानकों पर आधारित हैं। बीज खरीदने या बुवाई का अंतिम निर्णय लेने से पूर्व अपने नजदीकी कृषि विज्ञान केंद्र (KVK) के विशेषज्ञों से परामर्श अवश्य लें।',
              style: AppTheme.bodyStyle.copyWith(
                color: AppTheme.textPrimary(ctx),
              ),
            ),
            const SizedBox(height: AppTheme.s16),
            PrimaryButton(
              icon: Icons.phone_in_talk_rounded,
              label: isEn
                  ? 'Call KVK Helpline (1800-180-1551)'
                  : 'KVK हेल्पलाइन 1800-180-1551 पर कॉल करें',
              onPressed: () {
                Navigator.pop(ctx);
                _callKvk();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _askAboutCrop(CropRecommendationItem item) {
    final isEn = _lang == 'en';
    final cropLabel = isEn ? item.nameEn : item.nameHi;
    final prompt = isEn
        ? 'Give me sowing and irrigation advice for $cropLabel in my field.'
        : 'मेरे खेत में $cropLabel की बुवाई और सिंचाई के बारे में सलाह दें।';
    if (widget.onAskCrop != null) {
      widget.onAskCrop!(prompt);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => KrishiSahayakScreen(
          farm: widget.farm,
          locationName: _activeLocationName,
          latitude: _activeLat,
          longitude: _activeLon,
          weather: _activeWeather,
          lang: _lang,
          initialPrompt: prompt,
        ),
      ),
    );
  }

  String _formatTolerance(String level) {
    final isEn = _lang == 'en';
    switch (level.toLowerCase()) {
      case 'high':
        return isEn ? 'High' : 'उच्च';
      case 'medium':
        return isEn ? 'Medium' : 'मध्यम';
      default:
        return isEn ? 'Low' : 'कम';
    }
  }

  String _resolveDisplayLocation(bool isEn, {required String fallback}) {
    final raw = _activeLocationName.trim();
    if (isEn) {
      if (raw.contains('Umred') || raw.contains('उमरेड')) return 'Umred';
      if (raw.contains('Nagpur') || raw.contains('नागपुर')) return 'Nagpur';
      if (raw.contains('Mountain View') || raw.contains('माउंटेन व्यू')) {
        return 'Mountain View';
      }
      final stripped = raw
          .replaceAll(RegExp(r'[\u0900-\u097F]+'), '')
          .replaceAll('()', '')
          .replaceAll(RegExp(r'^[,.\s()-]+|[,.\s()-]+$'), '')
          .trim();
      if (stripped.isNotEmpty) return stripped;
      final farmVillage = (widget.farm?.village ?? '')
          .replaceAll(RegExp(r'[\u0900-\u097F]+'), '')
          .replaceAll('()', '')
          .replaceAll(RegExp(r'^[,.\s()-]+|[,.\s()-]+$'), '')
          .trim();
      return farmVillage.isNotEmpty ? farmVillage : fallback;
    } else {
      if (raw.contains('उमरेड') || raw.contains('Umred')) return 'उमरेड';
      final stripped = raw
          .replaceAll(RegExp(r'\s*\([A-Za-z\s-]+\)'), '')
          .replaceAll(RegExp(r'^[,.\s()-]+|[,.\s()-]+$'), '')
          .trim();
      return stripped.isNotEmpty ? stripped : fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEn = _lang == 'en';
    final soilPct = (_gpsSoilMoisture * 100).round();
    final locLabel = _resolveDisplayLocation(isEn, fallback: isEn ? 'Farm' : 'खेत');

    final gpsSummaryLine = isEn
        ? '$locLabel • ${_gpsTemp.toStringAsFixed(0)}°C • Soil moisture $soilPct% • 10-day rain ${_gpsRain10d.toStringAsFixed(0)} mm • $_seasonTitle'
        : '$locLabel • ${_gpsTemp.toStringAsFixed(0)}°C • मिट्टी नमी $soilPct% • 10-दिन वर्षा ${_gpsRain10d.toStringAsFixed(0)} मिमी • $_seasonTitle';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackdrop(
        child: AmbientBackground(
          quiet: true,
          weatherCode: _activeWeather?.current.weatherCode ?? 0,
          isDay: _activeWeather?.current.isDay ?? true,
          temperature: _gpsTemp,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // 1. Header
                Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.s16,
                    vertical: AppTheme.s8,
                  ),
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: isEn ? 'Back' : 'वापस जाएं',
                        child: IconButton(
                          icon: Icon(
                            Icons.arrow_back,
                            color: AppTheme.textPrimary(context),
                          ),
                          onPressed: () {
                            if (widget.onBack != null) {
                              widget.onBack!();
                            } else {
                              Navigator.of(context).maybePop();
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: AppTheme.s4),
                      Expanded(
                        child: Text(
                          isEn
                              ? 'Crop Advisory & Recommendations'
                              : 'फसल चयन व सिफारिशें',
                          style: AppTheme.sectionStyle.copyWith(
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _callKvk,
                        icon: Icon(
                          Icons.phone_in_talk_rounded,
                          size: 18,
                          color: AppTheme.primaryActionColor(context),
                        ),
                        label: Text(
                          isEn ? 'Call Now' : 'कॉल करें',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryActionColor(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.s16,
                            vertical: AppTheme.s8,
                          ),
                          children: [
                            // 2. Condensed 1-line GPS Summary Banner (SolidCard)
                            SolidCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.s12,
                                vertical: 10,
                              ),
                              radius: AppTheme.rInput,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.my_location_rounded,
                                    size: 18,
                                    color: AppTheme.primaryActionColor(context),
                                  ),
                                  const SizedBox(width: AppTheme.s8),
                                  Expanded(
                                    child: Text(
                                      gpsSummaryLine,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary(context),
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppTheme.s8),

                            // 3. 1-line ICAR/KVK Expert-Review Notice (GlassCard, tint amber 30%)
                            GlassCard(
                              radius: 20,
                              tint: const Color(0x4DFFB74D),
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.s12,
                                vertical: 10,
                              ),
                              onTap: _showIcarExpertNoticeSheet,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.verified_user_rounded,
                                    size: 20,
                                    color: AppTheme.semanticWarningText(
                                      context,
                                    ),
                                  ),
                                  const SizedBox(width: AppTheme.s8),
                                  Expanded(
                                    child: Text(
                                      isEn
                                          ? 'Expert Review Required: Verify final seed choice with KVK'
                                          : 'विशेषज्ञ समीक्षा आवश्यक: अंतिम निर्णय से पूर्व KVK से संपर्क करें',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary(context),
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppTheme.s8),
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 20,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppTheme.s16),

                            SectionHeader(
                              title: isEn
                                  ? 'Top 5 Recommended Crops'
                                  : 'शीर्ष 5 अनुशंसित फसलें',
                            ),

                            // 4. Rank #1 Expanded Card (GlassCard, tint white 50%, radius 28)
                            if (_recommendations.isNotEmpty)
                              _buildRankOneCard(_recommendations.first, isEn),

                            const SizedBox(height: AppTheme.s12),

                            // 5. Ranks #2-#5 Compact Expandable Rows (SolidCard)
                            ..._recommendations.skip(1).map(
                                  (item) => Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppTheme.s8,
                                    ),
                                    child: _buildCompactCropRow(item, isEn),
                                  ),
                                ),

                            // ~100px bottom padding for floating glass bottom nav bar
                            const SizedBox(height: 108),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRankOneCard(CropRecommendationItem item, bool isEn) {
    final cropTitle = isEn ? item.nameEn : item.nameHi;
    final isHc = AppTheme.isHighContrast(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryCol = AppTheme.primaryActionColor(context);
    final badgeFillCol = isHc ? const Color(0xFF004D20) : AppTheme.brandGreen;
    final pctChipBg = isHc
        ? Colors.white
        : (isDark
            ? primaryCol.withValues(alpha: 0.18)
            : const Color(0xFFE3EFE6));
    final pctChipText = isHc
        ? Colors.black
        : (isDark ? primaryCol : AppTheme.brandGreen);

    return GlassCard(
      radius: 28,
      tint: Colors.white.withValues(alpha: 0.50),
      padding: const EdgeInsets.all(AppTheme.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppTheme.s8,
            runSpacing: AppTheme.s8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Solid brandGreen "#1" badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.s12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeFillCol,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Text(
                  isEn ? '#1 Best Match' : '#1 सर्वोत्तम फसल',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Solid light-green (#E3EFE6) % chip with brandGreen text
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.s12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: pctChipBg,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                  border: isHc ? Border.all(color: Colors.black, width: 1.5) : null,
                ),
                child: Text(
                  '${item.matchScore}% ${isEn ? "match" : "उपयुक्त"}',
                  style: TextStyle(
                    color: pctChipText,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.s12),
          Text(
            cropTitle,
            style: AppTheme.titleStyle.copyWith(
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: AppTheme.s8),

          // Two key trait chips
          Wrap(
            spacing: AppTheme.s8,
            runSpacing: AppTheme.s8,
            children: [
              _buildTraitChip(
                Icons.schedule_rounded,
                item.durationDays,
              ),
              _buildTraitChip(
                Icons.water_drop_rounded,
                '${item.waterNeedMm.round()} mm • ${isEn ? "Drought" : "सूखा सहन"}: ${_formatTolerance(item.droughtTolerance)}',
              ),
            ],
          ),
          const SizedBox(height: AppTheme.s12),

          // Match Reasons
          ...item.reasons.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: primaryCol,
                    ),
                  ),
                  const SizedBox(width: AppTheme.s8),
                  Expanded(
                    child: Text(
                      r,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: AppTheme.textPrimary(context),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (item.riskNotes.isNotEmpty) ...[
            const SizedBox(height: AppTheme.s8),
            Text(
              item.riskNotes.first,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.semanticWarningText(context),
                height: 1.35,
              ),
            ),
          ],

          const SizedBox(height: AppTheme.s8),
          Text(
            '${isEn ? "Source" : "स्रोत"}: ${item.sourceCitation}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: AppTheme.s12),
          SecondaryButton(
            icon: Icons.mic_rounded,
            label: isEn ? 'Ask about Crop' : 'फसल पर सवाल पूछें',
            onPressed: () => _askAboutCrop(item),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCropRow(CropRecommendationItem item, bool isEn) {
    final isExpanded = _expandedRanks.contains(item.rank);
    final cropTitle = isEn ? item.nameEn : item.nameHi;
    final isHc = AppTheme.isHighContrast(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryCol = AppTheme.primaryActionColor(context);
    final pctChipBg = isHc
        ? Colors.white
        : (isDark
            ? primaryCol.withValues(alpha: 0.18)
            : const Color(0xFFE3EFE6));
    final pctChipText = isHc
        ? Colors.black
        : (isDark ? primaryCol : AppTheme.brandGreen);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return SolidCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.s16,
        vertical: AppTheme.s12,
      ),
      radius: AppTheme.rInput,
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedRanks.remove(item.rank);
          } else {
            _expandedRanks.add(item.rank);
          }
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pctChipBg,
                  borderRadius: BorderRadius.circular(AppTheme.s8),
                ),
                child: Text(
                  '#${item.rank}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: pctChipText,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cropTitle,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    Text(
                      '${item.durationDays} • ${item.waterNeedMm.round()} mm',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.s8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: pctChipBg,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                  border: isHc ? Border.all(color: Colors.black, width: 1.5) : null,
                ),
                child: Text(
                  '${item.matchScore}%',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: pctChipText,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.s4),
              Icon(
                isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AppTheme.textSecondary(context),
              ),
            ],
          ),
          AnimatedSize(
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: AppTheme.s12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppTheme.s8,
                          runSpacing: AppTheme.s8,
                          children: [
                            _buildTraitChip(
                              Icons.wb_sunny_rounded,
                              '${isEn ? "Drought" : "सूखा सहन"}: ${_formatTolerance(item.droughtTolerance)}',
                            ),
                            _buildTraitChip(
                              Icons.ac_unit_rounded,
                              '${isEn ? "Frost" : "पाला सहन"}: ${_formatTolerance(item.frostTolerance)}',
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTheme.s12),
                        ...item.reasons.map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 16,
                                    color: primaryCol,
                                  ),
                                ),
                                const SizedBox(width: AppTheme.s8),
                                Expanded(
                                  child: Text(
                                    r,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: AppTheme.textPrimary(context),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (item.riskNotes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            item.riskNotes.first,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.semanticWarningText(context),
                              height: 1.35,
                            ),
                          ),
                        ],
                        if (item.droughtAlternative != null &&
                            item.droughtAlternative!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${isEn ? "Drought-tolerant alternative" : "कम पानी विकल्प"}: ${item.droughtAlternative}',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: primaryCol,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          '${isEn ? "Source" : "स्रोत"}: ${item.sourceCitation}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary(context),
                          ),
                        ),
                        const SizedBox(height: AppTheme.s8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _askAboutCrop(item),
                            icon: const Icon(Icons.mic_rounded, size: 18),
                            label: Text(
                              isEn ? 'Ask about Crop' : 'फसल पर सवाल पूछें',
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildTraitChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.s12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primaryActionColor(context).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.rChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: AppTheme.primaryActionColor(context),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
