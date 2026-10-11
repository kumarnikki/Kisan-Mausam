import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_strings.dart';
import '../../models/farm_profile.dart';
import '../../models/weather_models.dart';
import '../../models/risk_models.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../services/location_service.dart';
import '../../services/alert_service.dart';
import '../../services/update_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/oni_gauge_meter.dart';
import '../../widgets/realistic_weather_visual.dart';
import '../crops/crop_recommender_screen.dart';
import '../chat/krishi_sahayak_screen.dart';

class WeatherHomeScreen extends StatefulWidget {
  final VoidCallback onOpenSettings;

  const WeatherHomeScreen({super.key, required this.onOpenSettings});

  @override
  State<WeatherHomeScreen> createState() => _WeatherHomeScreenState();
}

class _WeatherHomeScreenState extends State<WeatherHomeScreen> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  int _currentTabIndex = 0; // 0: Weather, 1: Ask (Chat), 2: Crops
  String? _pendingChatPrompt;

  List<FarmProfile> _farms = [];
  FarmProfile? _currentFarm;
  WeatherData? _weather;
  FarmRiskData? _riskData;
  EnsoSummary? _ensoData;
  bool _isEnsoLoading = true;
  List<CropRecommendationItem> _topCrops = [];
  bool _isCropsLoading = true;

  bool _isLoading = true;
  bool _isLocating = false;
  bool _isOfflineMode = false;
  String _lang = 'hi';
  DateTime? _cachedTime;

  double? _gpsLat;
  double? _gpsLon;
  String? _gpsLocationName;
  String? _userPhone;
  String? _lastWeatherSmsLocationKey;
  AppUpdateInfo? _availableUpdate;
  bool _updateBannerDismissed = false;

  // Scroll & overlay state for pinned warning bar
  bool _isWarningCompact = false;
  bool _isHazardOverlayOpen = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _enableEdgeToEdgeStatusBar();
    _loadData();
    _checkAppUpdateSilently();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _enableEdgeToEdgeStatusBar() {
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final shouldCompact = offset >= 80.0;
    if (shouldCompact != _isWarningCompact) {
      setState(() {
        _isWarningCompact = shouldCompact;
      });
    }
  }

  void _checkAppUpdateSilently() {
    UpdateService.checkForUpdate().then((info) {
      if (mounted && info.hasUpdate) {
        setState(() => _availableUpdate = info);
      }
    }).catchError((_) {});
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _isEnsoLoading = true;
      _isCropsLoading = true;
    });
    final lang = await StorageService.getLanguage();
    final farms = await StorageService.getFarms();
    final activeId = await StorageService.getActiveFarmId();
    final current = farms.firstWhere(
      (f) => f.id == activeId,
      orElse: () => farms.first,
    );

    final savedLoc = await StorageService.getLastLocation();
    double initialLat = current.latitude;
    double initialLon = current.longitude;
    String initialName = current.village;

    if (savedLoc != null) {
      initialLat = (savedLoc['latitude'] as num).toDouble();
      initialLon = (savedLoc['longitude'] as num).toDouble();
      final sName = (savedLoc['displayName'] as String?) ?? '';
      if (sName.isNotEmpty) initialName = sName;
      _gpsLat = initialLat;
      _gpsLon = initialLon;
      _gpsLocationName = initialName;
    }

    final savedPhone = await StorageService.getUserPhone();
    final cacheKey =
        '${initialLat.toStringAsFixed(2)}_${initialLon.toStringAsFixed(2)}';
    final cachedWeather = await StorageService.getCachedWeather(cacheKey);
    final cachedTs = await StorageService.getWeatherCachedTime(cacheKey);
    final cachedEnso = await StorageService.getCachedEnso();

    if (!mounted) return;
    setState(() {
      _lang = lang;
      _farms = farms;
      _currentFarm = current;
      _userPhone = savedPhone;
      if (cachedWeather != null) {
        _weather = cachedWeather;
        _cachedTime = cachedTs;
        _isLoading = false;
      }
      if (cachedEnso != null) {
        _ensoData = cachedEnso;
        _isEnsoLoading = false;
      }
    });

    // Lazy-load shared crop recommendations immediately from cache/weather
    _loadSharedCrops(
      lat: initialLat,
      lon: initialLon,
      locName: initialName,
      weather: cachedWeather,
    );
    // Fetch live ENSO status
    _loadEnsoStatus();

    await _initSmsPhoneAndPermission();
    if (!mounted) return;

    await _fetchWeather(initialLat, initialLon, locationName: initialName);
    await _autoFetchGPSLocation();
  }

  Future<void> _loadEnsoStatus({bool isRetry = false}) async {
    if (isRetry && mounted) {
      setState(() => _isEnsoLoading = true);
    }
    final debugOverride = kDebugMode ? debugWeatherNotifier.value : null;
    if (debugOverride?.forceEnsoUnavailable == true) {
      if (mounted) {
        setState(() {
          _ensoData = null;
          _isEnsoLoading = false;
        });
      }
      return;
    }
    try {
      final enso = await _apiService.getEnsoStatus(
        forceOffline: debugOverride?.forceOfflineCached == true,
        forceUnavailable: debugOverride?.forceEnsoUnavailable == true,
      );
      if (mounted) {
        setState(() {
          _ensoData = enso ?? _riskData?.enso;
          _isEnsoLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isEnsoLoading = false);
      }
    }
  }

  Future<void> _loadSharedCrops({
    required double lat,
    required double lon,
    required String locName,
    WeatherData? weather,
  }) async {
    try {
      final crops = await CropRecommenderScreen.getSharedRecommendations(
        lang: _lang,
        latitude: lat,
        longitude: lon,
        locationName: locName,
        weather: weather,
      );
      if (mounted) {
        setState(() {
          _topCrops = crops.take(3).toList();
          _isCropsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isCropsLoading = false);
      }
    }
  }

  Future<void> _initSmsPhoneAndPermission() async {
    if (_userPhone == null || _userPhone!.isEmpty) {
      final simPhone = await AlertService.detectSimPhoneNumber();
      if (simPhone != null && simPhone.isNotEmpty) {
        await StorageService.saveUserPhone(simPhone);
        if (mounted) setState(() => _userPhone = simPhone);
      }
    }
    await AlertService.requestSmsPermission();
    if (_userPhone == null || _userPhone!.isEmpty) {
      final simPhone = await AlertService.detectSimPhoneNumber();
      if (simPhone != null && simPhone.isNotEmpty) {
        await StorageService.saveUserPhone(simPhone);
        if (mounted) setState(() => _userPhone = simPhone);
      }
    }
  }

  Future<void> _autoFetchGPSLocation() async {
    try {
      final loc = await LocationService.getCurrentLocation(
        fallbackToIp: true,
        lang: _lang,
      );
      if (!mounted || loc == null) return;
      final diff = (_gpsLat == null || _gpsLon == null)
          ? 1.0
          : ((_gpsLat! - loc.latitude).abs() + (_gpsLon! - loc.longitude).abs());

      setState(() {
        _gpsLat = loc.latitude;
        _gpsLon = loc.longitude;
        _gpsLocationName = loc.displayName;
      });
      await StorageService.saveLastLocation(
        loc.latitude,
        loc.longitude,
        loc.displayName,
      );

      if (diff > 0.05 || _weather == null) {
        await _fetchWeather(
          loc.latitude,
          loc.longitude,
          locationName: loc.displayName,
        );
      }
    } catch (_) {}
  }

  Future<void> _fetchWeather(
    double lat,
    double lon, {
    String? locationName,
  }) async {
    try {
      final locName =
          locationName ?? _gpsLocationName ?? _currentFarm?.village ?? 'Nagpur';
      final data = await _apiService.getWeatherForecast(lat, lon);
      final cacheKey = '${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
      final cachedTs = await StorageService.getWeatherCachedTime(cacheKey);
      final isCachedOffline =
          data.attribution.toLowerCase().contains('offline');

      if (mounted) {
        setState(() {
          _weather = data;
          _cachedTime = cachedTs ?? DateTime.now();
          _isOfflineMode = isCachedOffline;
          _isLoading = false;
        });
      }

      await _loadSharedCrops(
        lat: lat,
        lon: lon,
        locName: locName,
        weather: data,
      );

      _apiService
          .getFarmRisks(
        _currentFarm?.id ?? 1,
        lat: lat,
        lon: lon,
        locationName: locName,
        weather: data,
      )
          .then((r) {
        if (mounted && r != null) {
          setState(() {
            _riskData = r;
            _ensoData ??= r.enso;
            _isEnsoLoading = false;
          });
          _checkAndShowAlertPopup(r, weather: data, locKey: cacheKey);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _checkAndShowAlertPopup(
    FarmRiskData risk, {
    WeatherData? weather,
    String? locKey,
  }) {
    final redRisks =
        risk.horizon1.risks.where((r) => r.severity == 'red').toList();
    final orangeRisks =
        risk.horizon1.risks.where((r) => r.severity == 'orange').toList();
    final activeLoc = _gpsLocationName ??
        _currentFarm?.village ??
        (_lang == 'hi' ? 'आपके क्षेत्र' : 'your location');

    if (redRisks.isNotEmpty) {
      final r = redRisks.first;
      if (locKey == null || _lastWeatherSmsLocationKey != locKey) {
        _lastWeatherSmsLocationKey = locKey;
        _autoSendRiskSms(r);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AlertService.showHazardAlert(
            context,
            titleHi: AppStrings.hazardTitle(
              r.alertType,
              r.severity,
              'hi',
              fallbackHi: r.titleHi,
              fallbackEn: r.titleEn,
            ),
            titleEn: AppStrings.hazardTitle(
              r.alertType,
              r.severity,
              'en',
              fallbackHi: r.titleHi,
              fallbackEn: r.titleEn,
            ),
            bodyHi:
                '$activeLoc में ${AppStrings.localizeExpectedValue(r.expectedValue, 'hi')} की संभावना है। तुरंत सावधानी बरतें।',
            bodyEn:
                'Risk detected at $activeLoc: ${AppStrings.localizeExpectedValue(r.expectedValue, 'en')}.',
            severity: 'red',
            actionHi: AppStrings.hazardAction(
              r.alertType,
              'hi',
              fallbackHi: r.actionHi,
              fallbackEn: r.actionEn,
            ),
            actionEn: AppStrings.hazardAction(
              r.alertType,
              'en',
              fallbackHi: r.actionHi,
              fallbackEn: r.actionEn,
            ),
            probability: r.probability,
            lang: _lang,
            lat: _gpsLat ?? _currentFarm?.latitude,
            lon: _gpsLon ?? _currentFarm?.longitude,
            locationName: activeLoc,
          );
        }
      });
    } else if (orangeRisks.isNotEmpty) {
      final r = orangeRisks.first;
      if (locKey == null || _lastWeatherSmsLocationKey != locKey) {
        _lastWeatherSmsLocationKey = locKey;
        _autoSendRiskSms(r);
      }
    } else if (weather != null &&
        locKey != null &&
        _lastWeatherSmsLocationKey != locKey) {
      _lastWeatherSmsLocationKey = locKey;
      _autoSendWeatherSummarySms(weather);
    }
  }

  Future<void> _autoSendWeatherSummarySms(WeatherData weather) async {
    var savedPhone = _userPhone ?? await StorageService.getUserPhone();
    if (savedPhone == null || savedPhone.isEmpty) {
      savedPhone = await AlertService.detectSimPhoneNumber();
      if (savedPhone != null && savedPhone.isNotEmpty) {
        await StorageService.saveUserPhone(savedPhone);
        if (mounted) setState(() => _userPhone = savedPhone);
      }
    }

    final locEn = _gpsLocationName ?? _currentFarm?.getVillage('en') ?? 'Farm';
    final temp = weather.current.temperature.round();
    final condEn = _getWeatherConditionText(weather.current.weatherCode, 'en');
    final wind = weather.current.windSpeed.round();
    final hum = weather.current.relativeHumidity.round();
    final msg =
        'KisanMausam Weather ($locEn): Temp ${temp}C, $condEn, Wind ${wind}km/h, Humidity $hum%. Farm weather is currently safe.';

    final sent = await _apiService.sendWeatherOrSosSms(
      phone: savedPhone ?? '',
      alertType: 'weather_change',
      message: msg,
    );
    if (sent && mounted && savedPhone != null && savedPhone.isNotEmpty) {
      final isHi = _lang == 'hi';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(
            isHi
                ? 'मौसम अपडेट SMS +91 $savedPhone पर भेजा गया'
                : 'Weather Update SMS sent to +91 $savedPhone',
          ),
        ),
      );
    }
  }

  Future<void> _autoSendRiskSms(DetectedRisk r) async {
    var savedPhone = _userPhone ?? await StorageService.getUserPhone();
    if (savedPhone == null || savedPhone.isEmpty) {
      savedPhone = await AlertService.detectSimPhoneNumber();
      if (savedPhone != null && savedPhone.isNotEmpty) {
        await StorageService.saveUserPhone(savedPhone);
        if (mounted) setState(() => _userPhone = savedPhone);
      }
    }
    final loc = _gpsLocationName ?? _currentFarm?.getVillage('en') ?? 'Farm';
    final isHi = _lang == 'hi';
    final alertNameDisplay = AppStrings.hazardTitle(
      r.alertType,
      r.severity,
      _lang,
      fallbackHi: r.titleHi,
      fallbackEn: r.titleEn,
    );
    final alertNameAscii =
        r.titleEn.isNotEmpty ? r.titleEn : 'Weather Hazard Alert';
    final actionAscii = r.actionEn.isNotEmpty
        ? r.actionEn
        : 'Take immediate crop protection measures.';
    final expectedEn = AppStrings.localizeExpectedValue(r.expectedValue, 'en');
    final msg =
        'KisanMausam Alert ($loc): $alertNameAscii ($expectedEn, ${r.probability.round()}% risk). Action: $actionAscii';
    final sent = await _apiService.sendWeatherOrSosSms(
      phone: savedPhone ?? '',
      alertType: r.alertType,
      message: msg,
    );
    if (sent && mounted && savedPhone != null && savedPhone.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(
            isHi
                ? 'मौसम अलर्ट SMS ($alertNameDisplay) +91 $savedPhone पर भेजा गया'
                : 'Weather Alert SMS ($alertNameDisplay) sent to +91 $savedPhone',
          ),
        ),
      );
    }
  }

  Future<void> _fetchCurrentLocationGPS() async {
    setState(() => _isLocating = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          _lang == 'hi'
              ? 'GPS स्थान प्राप्त किया जा रहा है...'
              : 'Getting GPS location...',
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    final loc = await LocationService.getCurrentLocation(
      fallbackToIp: true,
      lang: _lang,
    );
    if (!mounted) return;

    if (loc != null) {
      setState(() {
        _gpsLat = loc.latitude;
        _gpsLon = loc.longitude;
        _gpsLocationName = loc.displayName;
        _isLocating = false;
        _isLoading = true;
      });
      await StorageService.saveLastLocation(
        loc.latitude,
        loc.longitude,
        loc.displayName,
      );
      if (!mounted) return;
      await _fetchWeather(
        loc.latitude,
        loc.longitude,
        locationName: loc.displayName,
      );
    } else {
      setState(() => _isLocating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _lang == 'hi'
                ? 'GPS उपलब्ध नहीं। कृपया अनुमति दें।'
                : 'GPS unavailable. Please grant permission.',
          ),
        ),
      );
    }
  }

  String _getWeatherConditionText(int code, String lang) {
    if (code == 0) return lang == 'hi' ? 'साफ धूप' : 'Clear Sky';
    if (code >= 1 && code <= 2) {
      return lang == 'hi' ? 'आंशिक बादल' : 'Partly Cloudy';
    }
    if (code == 3) return lang == 'hi' ? 'घने बादल' : 'Cloudy';
    if (code == 45 || code == 48) return lang == 'hi' ? 'कोहरा' : 'Foggy';
    if (code >= 51 && code <= 55) {
      return lang == 'hi' ? 'हल्की बूंदाबांदी' : 'Drizzle';
    }
    if (code >= 61 && code <= 65) return lang == 'hi' ? 'बारिश' : 'Rain';
    if (code >= 80 && code <= 82) {
      return lang == 'hi' ? 'तेज बौछारें' : 'Rain Showers';
    }
    if (code == 95) {
      return lang == 'hi' ? 'गरज-चमक के साथ बारिश' : 'Thunderstorm';
    }
    if (code == 96 || code == 99) {
      return lang == 'hi' ? 'ओलावृष्टि तूफान' : 'Thunderstorm with Hail';
    }
    return lang == 'hi' ? 'सामान्य मौसम' : 'Fair Weather';
  }

  String _formatFreshnessText({bool forceOffline = false}) {
    if (forceOffline || _isOfflineMode) {
      final mins = _cachedTime != null
          ? DateTime.now().difference(_cachedTime!).inMinutes.clamp(5, 720)
          : 18;
      return _lang == 'hi'
          ? '${AppStrings.get("offline_cached", _lang)} • $mins मिनट पहले'
          : '${AppStrings.get("offline_cached", _lang)} • ${mins}m ago';
    }
    if (_cachedTime == null) {
      return AppStrings.get('updated_just_now', _lang);
    }
    final diff = DateTime.now().difference(_cachedTime!);
    if (diff.inMinutes < 2) {
      return AppStrings.get('updated_just_now', _lang);
    }
    if (diff.inMinutes < 60) {
      return _lang == 'hi'
          ? '${AppStrings.get("last_updated", _lang)} ${diff.inMinutes} मिनट पहले'
          : '${AppStrings.get("last_updated", _lang)} ${diff.inMinutes}m ago';
    }
    return _lang == 'hi'
        ? '${AppStrings.get("last_updated", _lang)} ${diff.inHours} घंटे पहले'
        : '${AppStrings.get("last_updated", _lang)} ${diff.inHours}h ago';
  }

  String _formatSunTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$min $period';
    } catch (_) {
      return iso.contains('T') ? iso.split('T').last : iso;
    }
  }

  Future<void> _activateSos() async {
    var cleanPhone = '';
    final stored = _userPhone ??
        await StorageService.getUserPhone() ??
        await AlertService.detectSimPhoneNumber();
    if (stored != null && stored.length >= 10) {
      final digits = stored.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 10) {
        cleanPhone = digits.substring(digits.length - 10);
        await StorageService.saveUserPhone(cleanPhone);
        if (mounted) setState(() => _userPhone = cleanPhone);
      }
    }

    if (!mounted) return;
    final loc = _gpsLocationName ??
        _currentFarm?.getVillage(_lang) ??
        (_lang == 'hi' ? 'आपका खेत' : 'Your Farm');

    await AlertService.showSosActiveSurface(
      context,
      lang: _lang,
      phoneNumber: cleanPhone.isNotEmpty ? cleanPhone : null,
      locationName: loc,
      lat: _gpsLat ?? _currentFarm?.latitude,
      lon: _gpsLon ?? _currentFarm?.longitude,
      onSendSms: () async {
        final res = await _apiService.simulateAlert(
          _currentFarm?.id ?? 1,
          'sos',
          phoneNumber: cleanPhone.isNotEmpty ? cleanPhone : null,
          locationName: loc,
        );
        final logsCount = res?['dispatched_logs_count'] ?? 0;
        return res?['sms_sent'] == true || logsCount > 0;
      },
      onSendSmsWithPhone: (newPhone) async {
        final digits = newPhone.replaceAll(RegExp(r'\D'), '');
        if (digits.length >= 10) {
          cleanPhone = digits.substring(digits.length - 10);
          await StorageService.saveUserPhone(cleanPhone);
          if (mounted) setState(() => _userPhone = cleanPhone);
        }
        final res = await _apiService.simulateAlert(
          _currentFarm?.id ?? 1,
          'sos',
          phoneNumber: cleanPhone.isNotEmpty ? cleanPhone : null,
          locationName: loc,
        );
        final logsCount = res?['dispatched_logs_count'] ?? 0;
        return res?['sms_sent'] == true ||
            logsCount > 0 ||
            cleanPhone.isNotEmpty;
      },
    );
  }

  void _showFarmSelector() {
    final searchController = TextEditingController();
    List<LocationResult> searchResults = [];
    bool isSearching = false;
    bool showInlineSearch = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isHi = _lang == 'hi';
            final primaryCol = AppTheme.primaryActionColor(ctx);

            Future<void> performSearch(String query) async {
              final q = query.trim();
              if (q.isEmpty) return;
              setSheetState(() => isSearching = true);
              final r = await LocationService.searchLocation(q, lang: _lang);
              if (ctx.mounted) {
                setSheetState(() {
                  searchResults = r;
                  isSearching = false;
                });
              }
            }

            return SheetScaffold(
              title: AppStrings.get('location_and_farm', _lang),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._farms.map((farm) {
                    final isSelected = farm.id == _currentFarm?.id;
                    final villageLabel = farm.getVillage(_lang);
                    final cropLabel = farm.getCurrentCrop(_lang);
                    return SizedBox(
                      height: 56,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTheme.rInput),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await StorageService.setActiveFarmId(farm.id);
                          final farmLoc = farm.getVillage(_lang);
                          setState(() {
                            _currentFarm = farm;
                            _gpsLat = farm.latitude;
                            _gpsLon = farm.longitude;
                            _gpsLocationName = farmLoc;
                            _isLoading = true;
                          });
                          await StorageService.saveLastLocation(
                            farm.latitude,
                            farm.longitude,
                            farmLoc,
                          );
                          await _fetchWeather(
                            farm.latitude,
                            farm.longitude,
                            locationName: farmLoc,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.s8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.agriculture_rounded,
                                color: isSelected
                                    ? primaryCol
                                    : AppTheme.textSecondary(ctx),
                                size: 22,
                              ),
                              const SizedBox(width: AppTheme.s12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      farm.getName(_lang),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: AppTheme.textPrimary(ctx),
                                      ),
                                    ),
                                    Text(
                                      '$villageLabel • $cropLabel',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textSecondary(ctx),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_rounded,
                                  color: primaryCol,
                                  size: 22,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  const Divider(height: AppTheme.s16),
                  SizedBox(
                    height: 56,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.rInput),
                      onTap: () {
                        Navigator.pop(ctx);
                        _fetchCurrentLocationGPS();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.s8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.my_location_rounded,
                              color: primaryCol,
                              size: 22,
                            ),
                            const SizedBox(width: AppTheme.s12),
                            Expanded(
                              child: Text(
                                AppStrings.get('use_current_gps', _lang),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary(ctx),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!showInlineSearch)
                    SizedBox(
                      height: 56,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTheme.rInput),
                        onTap: () {
                          setSheetState(() => showInlineSearch = true);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.s8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.search_rounded,
                                color: primaryCol,
                                size: 22,
                              ),
                              const SizedBox(width: AppTheme.s12),
                              Expanded(
                                child: Text(
                                  AppStrings.get('search_city_village', _lang),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary(ctx),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else ...[
                    const SizedBox(height: AppTheme.s8),
                    TextField(
                      controller: searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: isHi
                            ? 'शहर या गाँव का नाम लिखें (जैसे: नागपुर)'
                            : 'Enter city or village name (e.g. Nagpur)',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.arrow_forward_rounded),
                                onPressed: () =>
                                    performSearch(searchController.text),
                              ),
                      ),
                      onSubmitted: performSearch,
                    ),
                    if (searchResults.isNotEmpty) ...[
                      const SizedBox(height: AppTheme.s8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: searchResults.length,
                          itemBuilder: (_, i) {
                            final item = searchResults[i];
                            return SizedBox(
                              height: 56,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rInput,
                                ),
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _gpsLat = item.latitude;
                                    _gpsLon = item.longitude;
                                    _gpsLocationName = item.displayName;
                                    _isLoading = true;
                                  });
                                  await StorageService.saveLastLocation(
                                    item.latitude,
                                    item.longitude,
                                    item.displayName,
                                  );
                                  await _fetchWeather(
                                    item.latitude,
                                    item.longitude,
                                    locationName: item.displayName,
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.s8,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.place_rounded,
                                        color: primaryCol,
                                        size: 20,
                                      ),
                                      const SizedBox(width: AppTheme.s12),
                                      Expanded(
                                        child: Text(
                                          item.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary(ctx),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final hideBottomNav = _currentTabIndex == 1 && isKeyboardOpen;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: PopScope(
        canPop: _currentTabIndex == 0 && !_isHazardOverlayOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            if (_isHazardOverlayOpen) {
              setState(() => _isHazardOverlayOpen = false);
            } else if (_currentTabIndex != 0) {
              setState(() => _currentTabIndex = 0);
            }
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: IndexedStack(
            index: _currentTabIndex,
            children: [
              // Tab 0: Weather (Home)
              _buildWeatherHomeTab(context),
              // Tab 1: Ask (Krishi Sahayak)
              KrishiSahayakScreen(
                key: ValueKey('chat_tab_${_lang}_$_pendingChatPrompt'),
                farm: _currentFarm,
                locationName:
                    _gpsLocationName ?? _currentFarm?.getVillage(_lang),
                latitude:
                    _gpsLat ?? _weather?.latitude ?? _currentFarm?.latitude,
                longitude:
                    _gpsLon ?? _weather?.longitude ?? _currentFarm?.longitude,
                weather: _weather,
                lang: _lang,
                initialPrompt: _pendingChatPrompt,
                onBack: () => setState(() => _currentTabIndex = 0),
              ),
              // Tab 2: Crops (Crop Recommender)
              CropRecommenderScreen(
                key: ValueKey('crops_tab_${_lang}_${_gpsLat}_$_gpsLon'),
                farmId: _currentFarm?.id ?? 1,
                farmName: _currentFarm?.getName(_lang) ??
                    AppStrings.get('my_farm', _lang),
                village: _gpsLocationName ??
                    _currentFarm?.getVillage(_lang) ??
                    'Umred',
                farm: _currentFarm,
                lang: _lang,
                latitude: _gpsLat ?? _currentFarm?.latitude,
                longitude: _gpsLon ?? _currentFarm?.longitude,
                weather: _weather,
                onBack: () => setState(() => _currentTabIndex = 0),
                onAskCrop: (prompt) {
                  setState(() {
                    _pendingChatPrompt = prompt;
                    _currentTabIndex = 1;
                  });
                },
              ),
            ],
          ),
          bottomNavigationBar:
              hideBottomNav ? null : _buildBottomNavBar(context),
        ),
      ),
    );
  }

  /// Bottom Navigation Bar with aligned baselines across Weather, Ask, and Crops,
  /// and a distinct surface + 1px top hairline border.
  Widget _buildBottomNavBar(BuildContext context) {
    final primaryFill = AppTheme.primaryButtonFill(context);
    final isHc = AppTheme.isHighContrast(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedIconColor =
        isHc ? Colors.white : AppTheme.primaryActionColor(context);

    final navSurfaceColor = isHc
        ? Colors.white
        : (isDark ? const Color(0xFF121C2E) : Colors.white);
    final topHairlineColor = isHc
        ? Colors.black
        : (isDark ? const Color(0x1FFFFFFF) : const Color(0xFFCFD8DF));

    return Container(
      decoration: BoxDecoration(
        color: navSurfaceColor,
        border: Border(
          top: BorderSide(
            color: topHairlineColor,
            width: isHc ? 2.0 : 1.0,
          ),
        ),
      ),
      child: NavigationBar(
        backgroundColor: navSurfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _isHazardOverlayOpen = false;
            _currentTabIndex = idx;
          });
        },
        destinations: [
          NavigationDestination(
            icon: const SizedBox(
              height: 32,
              child: Center(child: Icon(Icons.wb_sunny_outlined, size: 22)),
            ),
            selectedIcon: SizedBox(
              height: 32,
              child: Center(
                child: Icon(
                  Icons.wb_sunny_rounded,
                  size: 22,
                  color: selectedIconColor,
                ),
              ),
            ),
            label: AppStrings.get('nav_weather', _lang),
          ),
          // Centre visually emphasized Ask (Mic) destination with identical 32dp icon box height so all 3 labels share the exact same baseline!
          NavigationDestination(
            icon: SizedBox(
              height: 32,
              child: Center(
                child: Container(
                  width: 44,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primaryFill,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            selectedIcon: SizedBox(
              height: 32,
              child: Center(
                child: Container(
                  width: 48,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primaryFill,
                    borderRadius: BorderRadius.circular(AppTheme.rPill),
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            label: AppStrings.get('nav_ask', _lang),
          ),
          NavigationDestination(
            icon: const SizedBox(
              height: 32,
              child: Center(child: Icon(Icons.grass_outlined, size: 22)),
            ),
            selectedIcon: SizedBox(
              height: 32,
              child: Center(
                child: Icon(
                  Icons.grass_rounded,
                  size: 22,
                  color: selectedIconColor,
                ),
              ),
            ),
            label: AppStrings.get('nav_crops', _lang),
          ),
        ],
      ),
    );
  }

  List<DetectedRisk> _resolveActiveH1Hazards(
    DebugWeatherOverride? debugOverride,
  ) {
    List<DetectedRisk> h1Risks = List<DetectedRisk>.from(
      _riskData?.horizon1.risks ?? const <DetectedRisk>[],
    );

    if (kDebugMode && debugOverride != null) {
      if (debugOverride.forceAllClear == true) {
        h1Risks = [];
      } else if (debugOverride.forceMultipleHazards == true) {
        h1Risks = [
          DetectedRisk(
            alertType: 'heavy_rain',
            titleHi: 'भारी वर्षा एवं जलभराव चेतावनी',
            titleEn: 'Heavy Rainfall Warning',
            severity: 'red',
            probability: 88.0,
            confidence: 'High',
            expectedValue: '68.0 mm',
            expectedDate: 'अगले 24-48 घंटे',
            actionHi:
                'खेत में जल निकासी नालियां साफ रखें और कीटनाशक छिड़काव स्थगित करें।',
            actionEn:
                'Keep field drainage channels clear and postpone pesticide spraying.',
          ),
          DetectedRisk(
            alertType: 'strong_wind',
            titleHi: 'तेज आंधी और हवा चेतावनी',
            titleEn: 'Strong Gusty Winds Alert',
            severity: 'orange',
            probability: 74.0,
            confidence: 'Medium',
            expectedValue: '42 km/h',
            expectedDate: 'अगले 24-48 घंटे',
            actionHi:
                'ऊंची फसलों व बागवानी पौधों को सहारा दें और आज स्प्रे न करें।',
            actionEn:
                'Provide staking support to tall crops and avoid spraying today.',
          ),
        ];
      } else if (debugOverride.forceActiveHazards == true && h1Risks.isEmpty) {
        h1Risks = [
          DetectedRisk(
            alertType: 'heavy_rain',
            titleHi: 'भारी वर्षा चेतावनी',
            titleEn: 'Heavy rainfall warning',
            severity: 'red',
            probability: 88.0,
            confidence: 'High',
            expectedValue: '68.0 mm',
            expectedDate: 'अगले 24-48 घंटे',
            actionHi:
                'खेत में जल निकासी नालियां साफ रखें और कीटनाशक छिड़काव स्थगित करें।',
            actionEn:
                'Keep field drainage channels clear and postpone pesticide spraying.',
          ),
        ];
      }
    }

    // Sort by severity: red before orange
    h1Risks.sort((a, b) {
      final aScore = a.severity.toLowerCase() == 'red' ? 0 : 1;
      final bScore = b.severity.toLowerCase() == 'red' ? 0 : 1;
      return aScore.compareTo(bScore);
    });
    return h1Risks;
  }

  Widget _buildWeatherHomeTab(BuildContext context) {
    return ValueListenableBuilder<DebugWeatherOverride?>(
      valueListenable: debugWeatherNotifier,
      builder: (context, debugOverride, _) {
        final effectiveCode =
            (kDebugMode && debugOverride?.ambientState != null)
                ? debugOverride!.weatherCode
                : (_weather?.current.weatherCode ?? 0);
        final effectiveIsDay =
            (kDebugMode && debugOverride?.ambientState != null)
                ? debugOverride!.isDay
                : (_weather?.current.isDay ?? true);
        final effectiveTemp =
            (kDebugMode && debugOverride?.ambientState != null)
                ? debugOverride!.temperature
                : (_weather?.current.temperature ?? 28.0);
        final effectiveWeather = _weather ??
            ((kDebugMode && debugOverride?.ambientState != null)
                ? WeatherData(
                    latitude: 21.1458,
                    longitude: 79.0882,
                    timezone: 'Asia/Kolkata',
                    elevation: 310.0,
                    current: CurrentWeather(
                      time: DateTime.now().toIso8601String(),
                      temperature: effectiveTemp,
                      relativeHumidity: 65.0,
                      apparentTemperature: effectiveTemp - 2,
                      precipitation: 0.0,
                      weatherCode: effectiveCode,
                      windSpeed: 14.0,
                      windGusts: 18.0,
                      uvIndex: 5.4,
                      soilTemperature: 24.5,
                      soilMoisture: 0.32,
                      isDay: effectiveIsDay,
                    ),
                    hourly: const [],
                    daily: [
                      DailyForecast(
                        date: '2026-10-11',
                        tempMax: effectiveTemp + 4,
                        tempMin: effectiveTemp - 4,
                        precipitationSum: 0.0,
                        precipitationProbabilityMax: 10,
                        windSpeedMax: 16.0,
                        sunrise: '2026-10-11T06:12',
                        sunset: '2026-10-11T18:04',
                        uvIndexMax: 6.0,
                        weatherCode: effectiveCode,
                      ),
                    ],
                    attribution: 'Open-Meteo.com (CC BY 4.0)',
                    cachedAt: DateTime.now().toIso8601String(),
                  )
                : null);

        final sunrise = effectiveWeather?.daily.isNotEmpty == true
            ? effectiveWeather!.daily.first.sunrise
            : null;
        final sunset = effectiveWeather?.daily.isNotEmpty == true
            ? effectiveWeather!.daily.first.sunset
            : null;

        final h1Risks = _resolveActiveH1Hazards(debugOverride);
        final topPad = MediaQuery.paddingOf(context).top;

        return AmbientBackground(
          weatherCode: effectiveCode,
          isDay: effectiveIsDay,
          temperature: effectiveTemp,
          sunrise: sunrise,
          sunset: sunset,
          child: Stack(
            children: [
              // Main scrollable area with Pinned SliverPersistentHeader for Top Bar + Warning Bar
              RefreshIndicator(
                edgeOffset: topPad + 110,
                color: AppTheme.primaryActionColor(context),
                onRefresh: () async {
                  final rLat = _gpsLat ?? _currentFarm?.latitude ?? 21.1458;
                  final rLon = _gpsLon ?? _currentFarm?.longitude ?? 79.0882;
                  final rName = _gpsLocationName ?? _currentFarm?.village;
                  await _loadEnsoStatus();
                  await _fetchWeather(rLat, rLon, locationName: rName);
                },
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // 1) PINNED HEADER: Top bar (farm chip, SOS, settings) + pinned active warning bar
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PinnedHomeHeaderDelegate(
                        topInset: topPad,
                        textScale: MediaQuery.textScalerOf(context).scale(1.0),
                        hasActiveHazard: h1Risks.isNotEmpty,
                        isCompactScroll: _isWarningCompact,
                        topBar: _buildTopBar(context),
                        expandedWarning: h1Risks.isNotEmpty
                            ? _buildExpandedPinnedWarning(
                                context,
                                h1Risks.first,
                                extraCount: h1Risks.length - 1,
                              )
                            : null,
                        compactWarning: h1Risks.isNotEmpty
                            ? _buildCompactPinnedWarning(
                                context,
                                h1Risks.first,
                                extraCount: h1Risks.length - 1,
                              )
                            : null,
                      ),
                    ),

                    // If no hazards are active, show the slim green "No severe hazards in the next 3 days" bar (can scroll away)
                    if (h1Risks.isEmpty && effectiveWeather != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.s16,
                            0,
                            AppTheme.s16,
                            AppTheme.s8,
                          ),
                          child: _buildNoHazardsGreenBar(context),
                        ),
                      ),

                    // Optional OTA Update Banner
                    if (_availableUpdate != null &&
                        _availableUpdate!.hasUpdate &&
                        !_updateBannerDismissed)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.s16,
                            0,
                            AppTheme.s16,
                            AppTheme.s8,
                          ),
                          child: InfoBanner(
                            icon: Icons.system_update_alt_rounded,
                            text:
                                '${AppStrings.get('update_banner_title', _lang)} (v${_availableUpdate!.latestVersion})',
                            onTap: () => UpdateService.showUpdateDialog(
                              context,
                              _availableUpdate!,
                              lang: _lang,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () =>
                                  setState(() => _updateBannerDismissed = true),
                            ),
                          ),
                        ),
                      ),

                    if (_isLoading && effectiveWeather == null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.s16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: const [
                              SkeletonBox(height: 64),
                              SizedBox(height: AppTheme.s16),
                              SkeletonBox(
                                height: 180,
                                borderRadius: AppTheme.rCard,
                              ),
                              SizedBox(height: AppTheme.s16),
                              SkeletonBox(
                                height: 120,
                                borderRadius: AppTheme.rCard,
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (effectiveWeather != null) ...[
                      // 2a) Weather hero card (saturated weather gradient, white text, inner white-10% metrics panel)
                      SliverToBoxAdapter(
                        child: _StaggeredEntrance(
                          index: 0,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.s16,
                              AppTheme.s8,
                              AppTheme.s16,
                              AppTheme.s16,
                            ),
                            child: _buildWeatherHero(
                              context,
                              effectiveWeather.current,
                              effectiveCode: effectiveCode,
                              effectiveIsDay: effectiveIsDay,
                              effectiveTemp: effectiveTemp,
                              sunrise: sunrise,
                              sunset: sunset,
                              forceOffline:
                                  debugOverride?.forceOfflineCached == true,
                            ),
                          ),
                        ),
                      ),

                      // 2b) Field conditions: ONE card with four cells in a 2x2 grid with hairline dividers
                      SliverToBoxAdapter(
                        child: _StaggeredEntrance(
                          index: 1,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.s16,
                              0,
                              AppTheme.s16,
                              AppTheme.s16,
                            ),
                            child: _buildFieldConditionsCard(
                              context,
                              effectiveWeather,
                            ),
                          ),
                        ),
                      ),

                      // 2c) Section label "This season" with El Niño season card + 30-day outlook card
                      SliverToBoxAdapter(
                        child: _StaggeredEntrance(
                          index: 2,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.s16,
                              0,
                              AppTheme.s16,
                              AppTheme.s16,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildSmallSectionLabel(
                                  context,
                                  AppStrings.get('section_this_season', _lang),
                                ),
                                const SizedBox(height: AppTheme.s8),
                                _buildElNinoSeasonCard(context, debugOverride),
                                const SizedBox(height: AppTheme.s12),
                                _build30DayOutlookCard(
                                  context,
                                  effectiveWeather,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // 2d) Section label "Best crops now" (with season badge) + top 3 crops inline
                      SliverToBoxAdapter(
                        child: _StaggeredEntrance(
                          index: 3,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppTheme.s16,
                              0,
                              AppTheme.s16,
                              0,
                            ),
                            child: _buildBestCropsSection(
                              context,
                              effectiveWeather,
                            ),
                          ),
                        ),
                      ),

                      // 2e) Footer: Open-Meteo CC BY 4.0 attribution with bottom padding above nav bar
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.s16,
                            AppTheme.s24,
                            AppTheme.s16,
                            AppTheme.s32,
                          ),
                          child: GestureDetector(
                            onLongPress:
                                kDebugMode ? _showDebugOverrideSheet : null,
                            child: Text(
                              AppStrings.get('attribution', _lang),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Floating Overlay Panel when compact warning bar or "+N more" is tapped (never pushes page content)
              if (_isHazardOverlayOpen && h1Risks.isNotEmpty)
                _buildHazardOverlayPanel(context, h1Risks, topPad),
            ],
          ),
        );
      },
    );
  }

  /// Section label: small (13sp, medium weight, muted) for scannable rhythm, with optional trailing badge.
  Widget _buildSmallSectionLabel(
    BuildContext context,
    String label, {
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
                color: AppTheme.textSecondary(context),
                height: 1.3,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// 1) Top bar:
  /// Farm chip with TWO lines inside the chip:
  /// - Line 1 (bold): district/village (never truncates "Outer North D..." at 360dp)
  /// - Line 2 (secondary): "{crop} - {acres} ac"
  /// SOS and Settings are fixed-size controls on the right.
  Widget _buildTopBar(BuildContext context) {
    final rawLoc = _gpsLocationName ??
        _currentFarm?.getVillage(_lang) ??
        AppStrings.get('my_farm', _lang);
    final parts = rawLoc
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    String line1Loc = parts.isNotEmpty ? parts.first : rawLoc.trim();
    if (parts.length >= 2 && line1Loc.length < 12) {
      line1Loc = '${parts[0]}, ${parts[1]}';
    }

    if (_lang == 'en') {
      if (line1Loc.contains('माउंटेन व्यू')) {
        line1Loc = 'Mountain View';
      } else if (line1Loc.contains('उमरेड') || line1Loc.contains('Umred')) {
        line1Loc = 'Umred, Nagpur';
      } else if (line1Loc.contains('नागपुर') || line1Loc.contains('Nagpur')) {
        line1Loc = 'Nagpur';
      } else {
        final stripped = line1Loc
            .replaceAll(RegExp(r'[\u0900-\u097F]+'), '')
            .replaceAll('()', '')
            .trim();
        line1Loc = stripped.isNotEmpty
            ? stripped
            : (_currentFarm?.getVillage('en') ?? 'Nagpur');
      }
    } else {
      if (line1Loc.toLowerCase() == 'mountain view') {
        line1Loc = 'माउंटेन व्यू';
      } else if (line1Loc.contains('उमरेड') || line1Loc.contains('Umred')) {
        line1Loc = 'उमरेड, नागपुर';
      } else if (line1Loc.contains('नागपुर') || line1Loc.contains('Nagpur')) {
        line1Loc = 'नागपुर';
      }
    }

    final cropLabel = _currentFarm?.getCurrentCrop(_lang) ??
        (_lang == 'en' ? 'Wheat' : 'गेहूं');
    final acresVal = _currentFarm?.landSizeAcres ?? 3.0;
    final acresFormatted = acresVal == acresVal.roundToDouble()
        ? acresVal.round().toString()
        : acresVal.toStringAsFixed(1);
    final acresUnit = AppStrings.get('acres_short', _lang);
    final line2Text = '$cropLabel - $acresFormatted $acresUnit';

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 54),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Farm chip takes all remaining width
          Expanded(
            child: Semantics(
              button: true,
              label:
                  '${AppStrings.get("location_and_farm", _lang)}: $line1Loc, $line2Text',
              child: AppSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                borderRadius: 16,
                onTap: _showFarmSelector,
                child: Row(
                  children: [
                    if (_isLocating)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primaryActionColor(context),
                        ),
                      )
                    else
                      Icon(
                        Icons.location_on_rounded,
                        size: 18,
                        color: AppTheme.primaryActionColor(context),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // First line: district/village (bold), scaled down only if super long so it never truncates "Outer North D..."
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              line1Loc,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary(context),
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 1),
                          // Second line: "{crop} - {acres} ac" (secondary)
                          Text(
                            line2Text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary(context),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppTheme.textSecondary(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.s8),
          // Fixed-size SOS HoldToConfirmButton
          HoldToConfirmButton(
            label: AppStrings.get('sos_label', _lang),
            holdHint: AppStrings.get('sos_hold_hint', _lang),
            confirmDialogTitle: AppStrings.get('sos_confirm_title', _lang),
            confirmDialogBody: AppStrings.get('sos_confirm_body', _lang),
            confirmButtonLabel: AppStrings.get('sos_activate_btn', _lang),
            cancelButtonLabel: AppStrings.get('settings_delete_cancel', _lang),
            onConfirmed: _activateSos,
          ),
          const SizedBox(width: AppTheme.s8),
          // Fixed-size Settings Gear IconAction (48x48dp)
          IconAction(
            icon: Icons.settings_rounded,
            semanticLabel: AppStrings.get('settings', _lang),
            onPressed: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }

  /// Expanded warning card shown at scroll offset 0 (< 80dp):
  /// Severity strip, icon, localized title, likelihood chip, action advice, "Time window" and "Expected" values.
  Widget _buildExpandedPinnedWarning(
    BuildContext context,
    DetectedRisk risk, {
    required int extraCount,
  }) {
    final isRed = risk.severity.toLowerCase() == 'red';
    final stripColor = isRed ? AppTheme.danger : AppTheme.warningText;
    final accentText = isRed
        ? AppTheme.semanticDangerText(context)
        : AppTheme.semanticWarningText(context);
    final severityLabel = AppStrings.get(
      isRed ? 'severity_red' : 'severity_orange',
      _lang,
    );
    final title = AppStrings.hazardTitle(
      risk.alertType,
      risk.severity,
      _lang,
      fallbackHi: risk.titleHi,
      fallbackEn: risk.titleEn,
    );
    final action = AppStrings.hazardAction(
      risk.alertType,
      _lang,
      fallbackHi: risk.actionHi,
      fallbackEn: risk.actionEn,
    );
    final timeWindowLabel = AppStrings.get('time_window_label', _lang);
    final timeWindowValue = AppStrings.localizeTimeWindow(
      risk.expectedDate,
      _lang,
    );
    final expectedLabel = AppStrings.get('expected_amount_label', _lang);
    final cleanExpected = AppStrings.localizeExpectedValue(
      risk.expectedValue.replaceAll(
        RegExp(r'\s*\([^)]*%\s*chance\)', caseSensitive: false),
        '',
      ),
      _lang,
    );
    final likelihoodText =
        '${risk.probability.round()}% ${AppStrings.get('likelihood_suffix', _lang)}';
    final likelihoodChipText = extraCount > 0
        ? '${risk.probability.round()}%'
        : likelihoodText;
    final plusMoreText = extraCount > 0
        ? AppStrings.get('plus_n_more', _lang).replaceAll('{n}', '$extraCount')
        : null;

    return Semantics(
      button: true,
      label: '$severityLabel: $title, $likelihoodText. $action',
      child: AppSurface(
        padding: EdgeInsets.zero,
        borderRadius: AppTheme.rInput,
        onTap: () {
          setState(() => _isHazardOverlayOpen = !_isHazardOverlayOpen);
        },
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: stripColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.s12,
                    vertical: 9,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _hazardIconForType(risk.alertType, isRed),
                            size: 19,
                            color: accentText,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '$severityLabel • $title',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary(context),
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isRed
                                  ? AppTheme.danger.withValues(alpha: 0.14)
                                  : AppTheme.cautionAmber,
                              borderRadius: BorderRadius.circular(
                                AppTheme.rPill,
                              ),
                            ),
                            child: Text(
                              likelihoodChipText,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: isRed
                                    ? accentText
                                    : AppTheme.textPrimaryLight,
                              ),
                            ),
                          ),
                          if (plusMoreText != null) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryActionColor(
                                  context,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.rPill,
                                ),
                              ),
                              child: Text(
                                plusMoreText,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primaryActionColor(context),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        action,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary(context),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: AppTheme.s12,
                        runSpacing: 2,
                        children: [
                          Text(
                            '$timeWindowLabel: $timeWindowValue',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                          if (cleanExpected.isNotEmpty)
                            Text(
                              '$expectedLabel: $cleanExpected',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: accentText,
                              ),
                            ),
                        ],
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

  /// Compact one-line pinned warning bar (48dp tall) shown after ~80dp scroll:
  /// Icon + short title + likelihood chip + "+N more" (if multiple) + chevron.
  Widget _buildCompactPinnedWarning(
    BuildContext context,
    DetectedRisk risk, {
    required int extraCount,
  }) {
    final isRed = risk.severity.toLowerCase() == 'red';
    final stripColor = isRed ? AppTheme.danger : AppTheme.warningText;
    final accentText = isRed
        ? AppTheme.semanticDangerText(context)
        : AppTheme.semanticWarningText(context);
    final title = AppStrings.hazardTitle(
      risk.alertType,
      risk.severity,
      _lang,
      fallbackHi: risk.titleHi,
      fallbackEn: risk.titleEn,
    );
    final likelihoodText = '${risk.probability.round()}%';
    final plusMoreText = extraCount > 0
        ? AppStrings.get('plus_n_more', _lang).replaceAll('{n}', '$extraCount')
        : null;

    return SizedBox(
      height: 48,
      child: AppSurface(
        padding: EdgeInsets.zero,
        borderRadius: AppTheme.rInput,
        onTap: () {
          setState(() => _isHazardOverlayOpen = !_isHazardOverlayOpen);
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: stripColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(
                      _hazardIconForType(risk.alertType, isRed),
                      size: 18,
                      color: accentText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isRed
                            ? AppTheme.danger.withValues(alpha: 0.14)
                            : AppTheme.cautionAmber,
                        borderRadius: BorderRadius.circular(AppTheme.rPill),
                      ),
                      child: Text(
                        likelihoodText,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color:
                              isRed ? accentText : AppTheme.textPrimaryLight,
                        ),
                      ),
                    ),
                    if (plusMoreText != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryActionColor(
                            context,
                          ).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppTheme.rPill),
                        ),
                        child: Text(
                          plusMoreText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryActionColor(context),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      _isHazardOverlayOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: AppTheme.textSecondary(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Overlay panel on top of content when the compact bar (or multi-hazard bar) is tapped.
  Widget _buildHazardOverlayPanel(
    BuildContext context,
    List<DetectedRisk> risks,
    double topPad,
  ) {
    final topOffset = topPad + (_isWarningCompact ? 118.0 : 178.0);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _isHazardOverlayOpen = false),
        child: Container(
          color: Colors.black.withValues(alpha: 0.28),
          alignment: Alignment.topCenter,
          padding: EdgeInsets.fromLTRB(
            AppTheme.s16,
            topOffset,
            AppTheme.s16,
            AppTheme.s24,
          ),
          child: GestureDetector(
            onTap: () {}, // Prevent tap inside panel from closing
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: risks.map((risk) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.s8),
                      child: _buildExpandedPinnedWarning(
                        context,
                        risk,
                        extraCount: 0,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoHazardsGreenBar(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.s12,
        vertical: 10,
      ),
      borderRadius: AppTheme.rInput,
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: AppTheme.semanticSuccessText(context),
          ),
          const SizedBox(width: AppTheme.s8),
          Expanded(
            child: Text(
              AppStrings.get('no_severe_hazards_3d', _lang),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2a) Weather hero card:
  /// Saturated weather gradient (AA contrast >= 5.25:1 for white text),
  /// RealisticWeatherVisual clipped inside, and wind/humidity/UV row on a subtle white-10% inner panel.
  Widget _buildWeatherHero(
    BuildContext context,
    CurrentWeather current, {
    required int effectiveCode,
    required bool effectiveIsDay,
    required double effectiveTemp,
    String? sunrise,
    String? sunset,
    bool forceOffline = false,
  }) {
    final condText = _getWeatherConditionText(effectiveCode, _lang);
    final displayCond = (!effectiveIsDay && effectiveCode == 0)
        ? (_lang == 'hi' ? 'साफ रात' : 'Clear Night')
        : condText;
    final isHc = AppTheme.isHighContrast(context);
    final ambientState = AmbientBackground.resolveState(
      weatherCode: effectiveCode,
      isDay: effectiveIsDay,
      temperature: effectiveTemp,
      sunrise: sunrise,
      sunset: sunset,
    );

    final primaryHeroText = isHc ? Colors.black : Colors.white;
    final secondaryHeroText =
        isHc ? Colors.black87 : Colors.white.withValues(alpha: 0.90);
    final mutedHeroText =
        isHc ? Colors.black87 : Colors.white.withValues(alpha: 0.84);
    final innerPanelColor = isHc
        ? Colors.black.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.11);
    final innerDividerColor =
        isHc ? Colors.black26 : Colors.white.withValues(alpha: 0.20);

    return AppSurface(
      borderRadius: AppTheme.rCard,
      padding: const EdgeInsets.all(20),
      gradient: isHc
          ? null
          : AmbientBackground.heroGradientForState(ambientState),
      color: isHc ? Colors.white : null,
      borderColor: isHc ? Colors.black : Colors.white.withValues(alpha: 0.18),
      borderWidth: isHc ? 2.0 : 1.0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onLongPress: kDebugMode ? _showDebugOverrideSheet : null,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${effectiveTemp.round()}°',
                          style: AppTheme.heroTempStyle.copyWith(
                            color: primaryHeroText,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayCond,
                      style: AppTheme.titleStyle.copyWith(
                        color: primaryHeroText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${AppStrings.get('feels_like', _lang)} ${current.apparentTemperature.round()}°C',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: secondaryHeroText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatFreshnessText(forceOffline: forceOffline),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: mutedHeroText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.s8),
              RepaintBoundary(
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: RealisticWeatherVisual(
                    weatherCode: effectiveCode,
                    isDay: effectiveIsDay,
                    size: 96,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Subtle white-10% inner panel at the bottom of the hero (max 1 nesting level)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: innerPanelColor,
              borderRadius: BorderRadius.circular(14),
              border: isHc ? Border.all(color: Colors.black, width: 1) : null,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildHeroMetricColumn(
                      context,
                      icon: Icons.air_rounded,
                      value: '${current.windSpeed.round()} km/h',
                      label: AppStrings.get('wind_speed', _lang),
                      textColor: primaryHeroText,
                      subColor: secondaryHeroText,
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    color: innerDividerColor,
                  ),
                  Expanded(
                    child: _buildHeroMetricColumn(
                      context,
                      icon: Icons.water_drop_rounded,
                      value: '${current.relativeHumidity.round()}%',
                      label: AppStrings.get('humidity', _lang),
                      textColor: primaryHeroText,
                      subColor: secondaryHeroText,
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    color: innerDividerColor,
                  ),
                  Expanded(
                    child: _buildHeroMetricColumn(
                      context,
                      icon: Icons.wb_sunny_rounded,
                      value: current.uvIndex.toStringAsFixed(1),
                      label: AppStrings.get('uv_index', _lang),
                      textColor: primaryHeroText,
                      subColor: secondaryHeroText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetricColumn(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color textColor,
    required Color subColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: textColor),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: textColor,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: subColor,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }

  /// 2b) Field conditions: ONE card with four cells (soil temp, soil moisture, sunrise, sunset)
  /// in a 2x2 grid with hairline dividers.
  Widget _buildFieldConditionsCard(BuildContext context, WeatherData weather) {
    final cur = weather.current;
    final today = weather.daily.isNotEmpty ? weather.daily.first : null;
    final soilPct = (cur.soilMoisture <= 1.0
            ? cur.soilMoisture * 100
            : cur.soilMoisture)
        .round();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHc = AppTheme.isHighContrast(context);
    final dividerCol = isHc
        ? Colors.black
        : (isDark ? const Color(0x1FFFFFFF) : const Color(0xFFCFD8DF));

    return AppSurface(
      borderRadius: AppTheme.rCard,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildFieldCell(
                    context,
                    icon: Icons.thermostat_rounded,
                    label: AppStrings.get('soil_temp', _lang),
                    value: '${cur.soilTemperature.toStringAsFixed(1)}°C',
                  ),
                ),
                Container(width: 1, color: dividerCol),
                Expanded(
                  child: _buildFieldCell(
                    context,
                    icon: Icons.opacity_rounded,
                    label: AppStrings.get('soil_moisture', _lang),
                    value: '$soilPct%',
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: dividerCol),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildFieldCell(
                    context,
                    icon: Icons.wb_twilight_rounded,
                    label: AppStrings.get('sunrise', _lang),
                    value: today != null
                        ? _formatSunTime(today.sunrise)
                        : '6:12 AM',
                  ),
                ),
                Container(width: 1, color: dividerCol),
                Expanded(
                  child: _buildFieldCell(
                    context,
                    icon: Icons.nights_stay_rounded,
                    label: AppStrings.get('sunset', _lang),
                    value: today != null
                        ? _formatSunTime(today.sunset)
                        : '6:04 PM',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldCell(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: AppTheme.primaryActionColor(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary(context),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  /// 3) EL NINO SEASON CARD
  /// - Phase chip (El Niño / La Niña / Neutral, each with its own icon + color)
  /// - ONI value + thin ONI scale bar (-2 to +2) with animated marker
  /// - "as of {month}" and source "NOAA CPC / IRI" (plus cache age if offline)
  /// - Mini 3-segment probability bar if forecast probabilities exist; otherwise titled "Current ENSO phase"
  /// - One localized farmer-facing hedged advice line per phase + "Check IMD advisories"
  /// - Skeleton shimmer while loading; "ENSO data unavailable" with retry icon on failure
  Widget _buildElNinoSeasonCard(
    BuildContext context,
    DebugWeatherOverride? debugOverride,
  ) {
    if (_isEnsoLoading) {
      return AppSurface(
        borderRadius: AppTheme.rCard,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(height: 22, width: 180),
            SizedBox(height: 12),
            SkeletonBox(height: 18),
            SizedBox(height: 12),
            SkeletonBox(height: 36),
          ],
        ),
      );
    }

    final forceUnavailable =
        kDebugMode && debugOverride?.forceEnsoUnavailable == true;
    final enso = forceUnavailable ? null : (_ensoData ?? _riskData?.enso);

    if (enso == null) {
      return AppSurface(
        borderRadius: AppTheme.rCard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () => _loadEnsoStatus(isRetry: true),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 20,
              color: AppTheme.textSecondary(context),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.get('enso_unavailable', _lang),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.refresh_rounded,
                color: AppTheme.primaryActionColor(context),
              ),
              tooltip: AppStrings.get('enso_retry', _lang),
              onPressed: () => _loadEnsoStatus(isRetry: true),
            ),
          ],
        ),
      );
    }

    final rawPhase =
        (kDebugMode && debugOverride?.forceEnsoPhase != null)
            ? debugOverride!.forceEnsoPhase!
            : enso.phase;
    final lowerPhase = rawPhase.toLowerCase();
    final isElNino = lowerPhase.contains('el') || lowerPhase.contains('अल');
    final isLaNina = lowerPhase.contains('la') || lowerPhase.contains('ला');

    final double oniVal = (kDebugMode && debugOverride?.forceEnsoPhase != null)
        ? (isElNino ? 0.9 : (isLaNina ? -0.8 : -0.2))
        : enso.oniValue;

    final String phaseLabel;
    final String adviceLine;
    final IconData phaseIcon;
    final Color phaseBgColor;

    if (isElNino) {
      phaseLabel = AppStrings.get('enso_phase_el_nino', _lang);
      adviceLine = AppStrings.get('enso_advice_el_nino', _lang);
      phaseIcon = Icons.wb_sunny_rounded;
      phaseBgColor = const Color(0xFFD84315);
    } else if (isLaNina) {
      phaseLabel = AppStrings.get('enso_phase_la_nina', _lang);
      adviceLine = AppStrings.get('enso_advice_la_nina', _lang);
      phaseIcon = Icons.ac_unit_rounded;
      phaseBgColor = const Color(0xFF0277BD);
    } else {
      phaseLabel = AppStrings.get('enso_phase_neutral', _lang);
      adviceLine = AppStrings.get('enso_advice_neutral', _lang);
      phaseIcon = Icons.balance_rounded;
      phaseBgColor = const Color(0xFF00695C);
    }

    // Extract coming season probabilities if present in response
    Map<String, int>? comingProbs;
    final bool allowProbs =
        !(kDebugMode && debugOverride?.forceEnsoCurrentOnly == true) &&
            enso.hasForecastProbabilities &&
            enso.probabilities.isNotEmpty;
    if (allowProbs) {
      final rawProbs = enso.probabilities;
      if (rawProbs['season_1'] is Map) {
        final s1 = rawProbs['season_1'] as Map;
        comingProbs = {
          'el_nino': (s1['el_nino'] as num?)?.round() ?? 15,
          'neutral': (s1['neutral'] as num?)?.round() ?? 60,
          'la_nina': (s1['la_nina'] as num?)?.round() ?? 25,
        };
      } else if (rawProbs.containsKey('El Niño') ||
          rawProbs.containsKey('El Nino')) {
        comingProbs = {
          'el_nino':
              ((rawProbs['El Niño'] ?? rawProbs['El Nino']) as num?)?.round() ??
                  15,
          'neutral': (rawProbs['Neutral'] as num?)?.round() ?? 25,
          'la_nina':
              ((rawProbs['La Niña'] ?? rawProbs['La Nina']) as num?)?.round() ??
                  60,
        };
      }
    }

    final cardTitle = comingProbs != null
        ? AppStrings.get('enso_seasonal_outlook_title', _lang)
        : AppStrings.get('enso_current_phase_title', _lang);

    final monthStr =
        enso.updatedAt.isNotEmpty ? enso.updatedAt : 'Oct 2026';
    final asOfText =
        AppStrings.get('enso_as_of', _lang).replaceAll('{month}', monthStr);
    final isOfflineCached =
        _isOfflineMode || (kDebugMode && debugOverride?.forceOfflineCached == true);
    final isHc = AppTheme.isHighContrast(context);

    return AppSurface(
      borderRadius: AppTheme.rCard,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cardTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary(context),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ONI ${oniVal >= 0 ? "+" : ""}${oniVal.toStringAsFixed(1)}°C • $asOfText',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Phase chip with distinct icon + color (never color-only)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isHc ? Colors.black : phaseBgColor,
                  borderRadius: BorderRadius.circular(AppTheme.rPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(phaseIcon, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      phaseLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Thin ONI scale bar (-2 to +2) with animated marker
          OniGaugeMeter(oniValue: oniVal, lang: _lang),

          // Mini 3-segment probability bar if forward-looking probabilities are returned
          if (comingProbs != null) ...[
            const SizedBox(height: 12),
            _buildMiniProbabilityBar(context, comingProbs),
          ],

          const SizedBox(height: 10),
          // Localized farmer-facing hedged advice line
          Text(
            adviceLine,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary(context),
              height: 1.38,
            ),
          ),
          const SizedBox(height: 6),
          // Footer: "NOAA CPC / IRI" + "Check IMD advisories" (+ cache age if offline)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                '${AppStrings.get('enso_source_noaa_iri', _lang)}${isOfflineCached ? " (${AppStrings.get('cached_age_prefix', _lang)})" : ""}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
              Text(
                AppStrings.get('enso_check_imd', _lang),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryActionColor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniProbabilityBar(
    BuildContext context,
    Map<String, int> probs,
  ) {
    final laNina = (probs['la_nina'] ?? 25).clamp(1, 100);
    final neutral = (probs['neutral'] ?? 50).clamp(1, 100);
    final elNino = (probs['el_nino'] ?? 25).clamp(1, 100);
    final isHc = AppTheme.isHighContrast(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.get('enso_coming_season_prob', _lang),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary(context),
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 7,
            child: Row(
              children: [
                Expanded(
                  flex: laNina,
                  child: Container(
                    color: isHc ? Colors.black87 : const Color(0xFF0277BD),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: neutral,
                  child: Container(
                    color: isHc ? Colors.black45 : const Color(0xFF00796B),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: elNino,
                  child: Container(
                    color: isHc ? Colors.black : const Color(0xFFD84315),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '${AppStrings.get('enso_phase_la_nina', _lang)} $laNina%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
            Flexible(
              child: Text(
                '${AppStrings.get('enso_phase_neutral', _lang)} $neutral%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
            Flexible(
              child: Text(
                '${AppStrings.get('enso_phase_el_nino', _lang)} $elNino%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary(context),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 4) 30-DAY OUTLOOK CARD (restored, visible by default, not collapsed):
  /// - Source: Horizon-3 (15-30 day seasonal) data in FarmRiskData
  /// - Headline figure as a labelled gauge (e.g., "35% chance of below-normal rainfall") with animated progress bar
  /// - Localized sentence + temperature outlook if present in data + "Multi-model forecast" source note
  Widget _build30DayOutlookCard(BuildContext context, WeatherData weather) {
    final h3Risks = _riskData?.horizon3.risks ?? const <DetectedRisk>[];
    final DetectedRisk? rainRisk = h3Risks.isNotEmpty ? h3Risks.first : null;
    final DetectedRisk? tempRisk = h3Risks.length > 1 ? h3Risks[1] : null;

    final int rainProb = (rainRisk?.probability ?? 35.0).round().clamp(0, 100);
    final headlineLabel = AppStrings.get(
      'outlook_below_normal_rain_chance',
      _lang,
    ).replaceAll('{p}', '$rainProb');

    final String sentence;
    if (_lang == 'en') {
      if (rainRisk?.accuracyStatementEn != null &&
          rainRisk!.accuracyStatementEn!.trim().isNotEmpty) {
        sentence = rainRisk.accuracyStatementEn!;
      } else {
        sentence = _seasonalOutlookSentence();
      }
    } else {
      if (rainRisk?.accuracyStatementHi != null &&
          rainRisk!.accuracyStatementHi!.trim().isNotEmpty) {
        sentence = rainRisk.accuracyStatementHi!;
      } else {
        sentence = _seasonalOutlookSentence();
      }
    }

    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final primaryCol = AppTheme.primaryActionColor(context);

    return AppSurface(
      borderRadius: AppTheme.rCard,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 18, color: primaryCol),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.get('outlook_30d_title', _lang),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Headline labelled gauge + animated progress bar (400 ms easeOutCubic)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  headlineLabel,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$rainProb%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: primaryCol,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: disableAnimations ? (rainProb / 100.0) : 0.0,
              end: rainProb / 100.0,
            ),
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, val, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: val,
                  minHeight: 7,
                  backgroundColor: primaryCol.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation<Color>(primaryCol),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            sentence,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary(context),
              height: 1.38,
            ),
          ),
          // Additional temperature outlook row if present in Horizon-3 data
          if (tempRisk != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.thermostat_rounded,
                  size: 15,
                  color: AppTheme.semanticWarningText(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    AppStrings.get('outlook_above_normal_temp_chance', _lang)
                        .replaceAll('{p}', '${tempRisk.probability.round()}'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            AppStrings.get('outlook_source_multimodel', _lang),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 5) CROP RECOMMENDATIONS ON HOME (restored):
  /// - Section label "Best crops now" with Season badge (Rabi/Kharif) in section header
  /// - Top 3 crops from shared cache/provider with CropRecommenderScreen
  /// - Each row: rank, localized crop name, match % with thin animated bar, one trait chip (water need or duration)
  /// - Footer link "See all 5 crops" navigates to Crops tab
  /// - Small caption "Based on ICAR data - verify with your KVK"
  Widget _buildBestCropsSection(BuildContext context, WeatherData weather) {
    final seasonBadge = CropRecommenderScreen.resolveSeasonBadge(
      lang: _lang,
      weather: weather,
      rawSeason: _topCrops.isNotEmpty ? _topCrops.first.season : 'rabi',
    );
    final primaryCol = AppTheme.primaryActionColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isHc = AppTheme.isHighContrast(context);
    final dividerCol = isHc
        ? Colors.black26
        : (isDark ? const Color(0x1FFFFFFF) : const Color(0xFFCFD8DF));
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSmallSectionLabel(
          context,
          AppStrings.get('section_best_crops', _lang),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: primaryCol.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.rPill),
            ),
            child: Text(
              seasonBadge,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: primaryCol,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.s8),
        AppSurface(
          borderRadius: AppTheme.rCard,
          padding: const EdgeInsets.all(16),
          child: _isCropsLoading && _topCrops.isEmpty
              ? Column(
                  children: const [
                    SkeletonBox(height: 38),
                    SizedBox(height: 10),
                    SkeletonBox(height: 38),
                    SizedBox(height: 10),
                    SkeletonBox(height: 38),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ...List.generate(_topCrops.take(3).length, (idx) {
                      final crop = _topCrops[idx];
                      final cropName =
                          _lang == 'en' ? crop.nameEn : crop.nameHi;
                      final waterTrait = crop.waterNeedMm <= 300
                          ? AppStrings.get('water_need_low', _lang)
                          : (crop.waterNeedMm <= 480
                              ? AppStrings.get('water_need_medium', _lang)
                              : AppStrings.get('water_need_high', _lang));

                      return Column(
                        children: [
                          if (idx > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Container(height: 1, color: dividerCol),
                            ),
                           InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => _currentTabIndex = 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Rank badge
                                Container(
                                  width: 26,
                                  height: 26,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: primaryCol.withValues(alpha: 0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${crop.rank}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: primaryCol,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Crop name, trait chip, match %, and thin match bar
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              cropName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.textPrimary(
                                                  context,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            flex: 0,
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 108,
                                              ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.textSecondary(
                                                    context,
                                                  ).withValues(alpha: 0.10),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    AppTheme.rPill,
                                                  ),
                                                ),
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    waterTrait,
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          AppTheme.textPrimary(
                                                        context,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${crop.matchScore}%',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: primaryCol,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      TweenAnimationBuilder<double>(
                                        tween: Tween<double>(
                                          begin: disableAnimations
                                              ? (crop.matchScore / 100.0)
                                              : 0.0,
                                          end: (crop.matchScore / 100.0)
                                              .clamp(0.0, 1.0),
                                        ),
                                        duration: disableAnimations
                                            ? Duration.zero
                                            : const Duration(milliseconds: 400),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, val, _) {
                                          return ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(3),
                                            child: LinearProgressIndicator(
                                              value: val,
                                              minHeight: 5,
                                              backgroundColor:
                                                  primaryCol.withValues(
                                                alpha: 0.12,
                                              ),
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                primaryCol,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 12),
                    Container(height: 1, color: dividerCol),
                    const SizedBox(height: 10),
                    // Footer link "See all 5 crops" + ICAR/KVK caption
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _currentTabIndex = 2),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    AppStrings.get('see_all_5_crops', _lang),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: primaryCol,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: primaryCol,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppStrings.get('icar_kvk_caption', _lang),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  IconData _hazardIconForType(String alertType, bool isRed) {
    final t = alertType.toLowerCase();
    if (t.contains('heat')) return Icons.wb_sunny_rounded;
    if (t.contains('rain') || t.contains('flood')) {
      return Icons.thunderstorm_rounded;
    }
    if (t.contains('frost') || t.contains('cold')) return Icons.ac_unit_rounded;
    if (t.contains('wind')) return Icons.air_rounded;
    return isRed ? Icons.warning_rounded : Icons.error_outline_rounded;
  }

  String _seasonalOutlookSentence() {
    final rawLoc = _gpsLocationName ??
        _currentFarm?.getVillage(_lang) ??
        (_lang == 'hi' ? 'आपके क्षेत्र' : 'your area');
    final activeLoc = _lang == 'en'
        ? (rawLoc
                .replaceAll(RegExp(r'[\u0900-\u097F]+'), '')
                .replaceAll('()', '')
                .trim()
                .isNotEmpty
            ? rawLoc
                .replaceAll(RegExp(r'[\u0900-\u097F]+'), '')
                .replaceAll('()', '')
                .trim()
            : 'Nagpur')
        : rawLoc;
    final temp = _weather?.current.temperature.toStringAsFixed(0) ?? '28';
    final soilPct = ((_weather?.current.soilMoisture ?? 0.25) * 100).round();
    if (_lang == 'en') {
      return 'In $activeLoc ($temp°C, $soilPct% soil moisture), 30-day multi-model outlook indicates normal-to-mildly dry conditions; conserve topsoil moisture.';
    }
    return '$activeLoc ($temp°C, मिट्टी नमी $soilPct%) में अगले 30 दिनों के मौसमी पूर्वानुमान के अनुसार नमी संरक्षण व समय पर हल्की सिंचाई की सलाह है।';
  }

  void _showDebugOverrideSheet() {
    if (!kDebugMode) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SheetScaffold(
          title: 'Debug Visual Verification (kDebugMode only)',
          subtitle: 'Switch ambient weather state, hazard state, or text scale',
          child: Wrap(
            spacing: AppTheme.s8,
            runSpacing: AppTheme.s8,
            children: [
              ActionChip(
                label: const Text('Live Default'),
                onPressed: () {
                  debugWeatherNotifier.value = null;
                  _loadEnsoStatus();
                  Navigator.pop(ctx);
                },
              ),
              ...AmbientWeatherState.values.map(
                (st) => ActionChip(
                  label: Text(st.name),
                  onPressed: () {
                    final prev = debugWeatherNotifier.value;
                    debugWeatherNotifier.value = DebugWeatherOverride(
                      ambientState: st,
                      forceAllClear: prev?.forceAllClear,
                      forceActiveHazards: prev?.forceActiveHazards,
                      forceMultipleHazards: prev?.forceMultipleHazards,
                      forceEnsoUnavailable: prev?.forceEnsoUnavailable,
                      forceOfflineCached: prev?.forceOfflineCached,
                      forceEnsoPhase: prev?.forceEnsoPhase,
                      forceEnsoCurrentOnly: prev?.forceEnsoCurrentOnly,
                      textScaleOverride: prev?.textScaleOverride,
                    );
                    Navigator.pop(ctx);
                  },
                ),
              ),
              ActionChip(
                label: const Text('All-Clear Home'),
                onPressed: () {
                  final prev = debugWeatherNotifier.value;
                  debugWeatherNotifier.value = DebugWeatherOverride(
                    ambientState: prev?.ambientState,
                    forceAllClear: true,
                    forceActiveHazards: false,
                    forceMultipleHazards: false,
                    textScaleOverride: prev?.textScaleOverride,
                  );
                  Navigator.pop(ctx);
                },
              ),
              ActionChip(
                label: const Text('Active Hazard'),
                onPressed: () {
                  final prev = debugWeatherNotifier.value;
                  debugWeatherNotifier.value = DebugWeatherOverride(
                    ambientState: prev?.ambientState,
                    forceAllClear: false,
                    forceActiveHazards: true,
                    forceMultipleHazards: false,
                    textScaleOverride: prev?.textScaleOverride,
                  );
                  Navigator.pop(ctx);
                },
              ),
              ActionChip(
                label: const Text('Multiple Hazards (+1 more)'),
                onPressed: () {
                  final prev = debugWeatherNotifier.value;
                  debugWeatherNotifier.value = DebugWeatherOverride(
                    ambientState: prev?.ambientState,
                    forceAllClear: false,
                    forceActiveHazards: true,
                    forceMultipleHazards: true,
                    textScaleOverride: prev?.textScaleOverride,
                  );
                  Navigator.pop(ctx);
                },
              ),
              ActionChip(
                label: const Text('ENSO Unavailable'),
                onPressed: () {
                  final prev = debugWeatherNotifier.value;
                  debugWeatherNotifier.value = DebugWeatherOverride(
                    ambientState: prev?.ambientState,
                    forceAllClear: prev?.forceAllClear,
                    forceActiveHazards: prev?.forceActiveHazards,
                    forceEnsoUnavailable: true,
                    textScaleOverride: prev?.textScaleOverride,
                  );
                  Navigator.pop(ctx);
                },
              ),
              ActionChip(
                label: const Text('Offline Cached'),
                onPressed: () {
                  final prev = debugWeatherNotifier.value;
                  debugWeatherNotifier.value = DebugWeatherOverride(
                    ambientState: prev?.ambientState,
                    forceAllClear: prev?.forceAllClear,
                    forceActiveHazards: prev?.forceActiveHazards,
                    forceOfflineCached: true,
                    textScaleOverride: prev?.textScaleOverride,
                  );
                  Navigator.pop(ctx);
                },
              ),
              ActionChip(
                label: const Text('Text Scale 1.3x'),
                onPressed: () {
                  final prev = debugWeatherNotifier.value;
                  debugWeatherNotifier.value = DebugWeatherOverride(
                    ambientState: prev?.ambientState,
                    forceAllClear: prev?.forceAllClear,
                    forceActiveHazards: prev?.forceActiveHazards,
                    forceMultipleHazards: prev?.forceMultipleHazards,
                    textScaleOverride: 1.3,
                  );
                  Navigator.pop(ctx);
                },
              ),
              ActionChip(
                label: const Text('Text Scale 1.0x'),
                onPressed: () {
                  final prev = debugWeatherNotifier.value;
                  debugWeatherNotifier.value = DebugWeatherOverride(
                    ambientState: prev?.ambientState,
                    forceAllClear: prev?.forceAllClear,
                    forceActiveHazards: prev?.forceActiveHazards,
                    forceMultipleHazards: prev?.forceMultipleHazards,
                    textScaleOverride: 1.0,
                  );
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pinned SliverPersistentHeaderDelegate that pins the Top Bar and the active Warning Bar.
/// At scroll offset 0 (< 80dp), shows the expanded warning bar.
/// After ~80dp of scroll, animates (<= 250 ms) to the compact 48dp one-line warning bar.
class _PinnedHomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double topInset;
  final double textScale;
  final bool hasActiveHazard;
  final bool isCompactScroll;
  final Widget topBar;
  final Widget? expandedWarning;
  final Widget? compactWarning;

  _PinnedHomeHeaderDelegate({
    required this.topInset,
    required this.textScale,
    required this.hasActiveHazard,
    required this.isCompactScroll,
    required this.topBar,
    this.expandedWarning,
    this.compactWarning,
  });

  double get _topBarHeight => (58.0 * textScale.clamp(1.0, 1.25));

  double get _expandedWarningHeight =>
      textScale > 1.15 ? 156.0 : 114.0;

  @override
  double get maxExtent {
    if (!hasActiveHazard) {
      return topInset + _topBarHeight + 16.0;
    }
    return topInset + _topBarHeight + _expandedWarningHeight + 22.0;
  }

  @override
  double get minExtent {
    if (!hasActiveHazard) {
      return topInset + _topBarHeight + 16.0;
    }
    return topInset + _topBarHeight + 48.0 + 20.0;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final ambient = AmbientScope.maybeOf(context);
    final isDark =
        ambient?.isDark ?? (Theme.of(context).brightness == Brightness.dark);
    final isHc = ambient?.isHighContrast ?? AppTheme.isHighContrast(context);
    final state = ambient?.state ?? AmbientWeatherState.clearDay;
    final topBgColor = isHc
        ? Colors.white
        : AmbientBackground.paletteForState(
            state,
            isDark: isDark,
            quiet: false,
          ).first;

    final showCompact = isCompactScroll || shrinkOffset >= 56.0;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Container(
      decoration: BoxDecoration(
        color: (shrinkOffset > 4 || overlapsContent)
            ? topBgColor.withValues(alpha: 0.96)
            : Colors.transparent,
      ),
      padding: EdgeInsets.fromLTRB(
        AppTheme.s16,
        topInset + 6,
        AppTheme.s16,
        6,
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              topBar,
              if (hasActiveHazard &&
                  expandedWarning != null &&
                  compactWarning != null) ...[
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: showCompact
                      ? KeyedSubtree(
                          key: const ValueKey('warning_compact'),
                          child: compactWarning!,
                        )
                      : KeyedSubtree(
                          key: const ValueKey('warning_expanded'),
                          child: expandedWarning!,
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedHomeHeaderDelegate oldDelegate) {
    return topInset != oldDelegate.topInset ||
        textScale != oldDelegate.textScale ||
        hasActiveHazard != oldDelegate.hasActiveHazard ||
        isCompactScroll != oldDelegate.isCompactScroll ||
        topBar != oldDelegate.topBar ||
        expandedWarning != oldDelegate.expandedWarning ||
        compactWarning != oldDelegate.compactWarning;
  }
}

/// Staggered card entrance animation: fade + 8px rise staggered 40 ms on first load.
/// Disabled when reduce-motion is on.
class _StaggeredEntrance extends StatefulWidget {
  final int index;
  final Widget child;

  const _StaggeredEntrance({
    required this.index,
    required this.child,
  });

  @override
  State<_StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<_StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 8),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    final delayMs = (widget.index * 40).clamp(0, 240);
    if (delayMs == 0) {
      _controller.forward();
    } else {
      Future<void>.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: _slide.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
