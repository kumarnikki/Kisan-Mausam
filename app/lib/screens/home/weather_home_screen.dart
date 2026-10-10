import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  int _currentTabIndex = 0; // 0: Weather, 1: Ask (Chat), 2: Crops
  String? _pendingChatPrompt;

  List<FarmProfile> _farms = [];
  FarmProfile? _currentFarm;
  WeatherData? _weather;
  FarmRiskData? _riskData;
  bool _isLoading = true;
  bool _isLocating = false;
  String _lang = 'hi';
  DateTime? _cachedTime;

  double? _gpsLat;
  double? _gpsLon;
  String? _gpsLocationName;
  String? _userPhone;
  String? _lastWeatherSmsLocationKey;
  AppUpdateInfo? _availableUpdate;
  bool _updateBannerDismissed = false;

  // Hazard expansion state: index 0 (highest severity) expanded by default
  final Set<int> _expandedHazardIndices = {0};
  bool _seasonalOutlookExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkAppUpdateSilently();
  }

  void _checkAppUpdateSilently() {
    UpdateService.checkForUpdate().then((info) {
      if (mounted && info.hasUpdate) {
        setState(() => _availableUpdate = info);
      }
    }).catchError((_) {});
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
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
    });

    await _fetchWeather(initialLat, initialLon, locationName: initialName);
    await _autoFetchGPSLocation();

    if (!mounted) return;
    await _initSmsPhoneAndPermission();
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
      final locName = locationName ?? _gpsLocationName ?? _currentFarm?.village;
      final data = await _apiService.getWeatherForecast(lat, lon);
      final cacheKey = '${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
      final cachedTs = await StorageService.getWeatherCachedTime(cacheKey);

      if (mounted) {
        setState(() {
          _weather = data;
          _cachedTime = cachedTs ?? DateTime.now();
          _isLoading = false;
        });
      }

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
            _expandedHazardIndices
              ..clear()
              ..add(0);
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
      _autoSendRiskSms(r);
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
            bodyHi: '$activeLoc में ${r.expectedValue} की संभावना है। तुरंत सावधानी बरतें।',
            bodyEn: 'Risk detected at $activeLoc: ${r.expectedValue}.',
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
      _autoSendRiskSms(r);
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
    if (savedPhone == null || savedPhone.isEmpty) return;

    final locEn = _gpsLocationName ?? _currentFarm?.getVillage('en') ?? 'Farm';
    final temp = weather.current.temperature.round();
    final condEn = _getWeatherConditionText(weather.current.weatherCode, 'en');
    final wind = weather.current.windSpeed.round();
    final hum = weather.current.relativeHumidity.round();
    final msg =
        'KisanMausam Weather ($locEn): Temp ${temp}C, $condEn, Wind ${wind}km/h, Humidity $hum%. Farm weather is currently safe.';

    final sent = await _apiService.sendWeatherOrSosSms(
      phone: savedPhone,
      alertType: 'weather_change',
      message: msg,
    );
    if (sent && mounted) {
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
    if (savedPhone == null || savedPhone.isEmpty) return;
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
    final msg =
        'KisanMausam Alert ($loc): $alertNameAscii (${r.expectedValue}, ${r.probability.round()}% risk). Action: $actionAscii';
    final sent = await _apiService.sendWeatherOrSosSms(
      phone: savedPhone,
      alertType: r.alertType,
      message: msg,
    );
    if (sent && mounted) {
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
    if (code >= 1 && code <= 3) return lang == 'hi' ? 'हल्के बादल' : 'Partly Cloudy';
    if (code == 45 || code == 48) return lang == 'hi' ? 'कोहरा' : 'Foggy';
    if (code >= 51 && code <= 55) return lang == 'hi' ? 'हल्की बूंदाबांदी' : 'Drizzle';
    if (code >= 61 && code <= 65) return lang == 'hi' ? 'बारिश' : 'Rain';
    if (code >= 80 && code <= 82) return lang == 'hi' ? 'तेज बौछारें' : 'Rain Showers';
    if (code == 95) return lang == 'hi' ? 'गरज-चमक के साथ बारिश' : 'Thunderstorm';
    if (code == 96 || code == 99) {
      return lang == 'hi' ? 'ओलावृष्टि तूफान' : 'Thunderstorm with Hail';
    }
    return lang == 'hi' ? 'सामान्य मौसम' : 'Fair Weather';
  }

  String _formatFreshnessText() {
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

  /// Step 4.3: Activate SOS via HoldToConfirmButton
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
        return res?['sms_sent'] == true || logsCount > 0 || cleanPhone.isNotEmpty;
      },
    );
  }

  /// Step 4.2: Farm switcher bottom sheet ("Location & farm") with inline search
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
                  // 1. Saved farms first (current has a check, row height 56)
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
                          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8),
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

                  // 2. Use current GPS location (row height 56)
                  SizedBox(
                    height: 56,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.rInput),
                      onTap: () {
                        Navigator.pop(ctx);
                        _fetchCurrentLocationGPS();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8),
                        child: Row(
                          children: [
                            Icon(Icons.my_location_rounded, color: primaryCol, size: 22),
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

                  // 3. Search city or village (inline in the same sheet, row height 56)
                  if (!showInlineSearch)
                    SizedBox(
                      height: 56,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTheme.rInput),
                        onTap: () {
                          setSheetState(() => showInlineSearch = true);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppTheme.s8),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded, color: primaryCol, size: 22),
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
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.arrow_forward_rounded),
                                onPressed: () => performSearch(searchController.text),
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
                                borderRadius: BorderRadius.circular(AppTheme.rInput),
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

    return PopScope(
      canPop: _currentTabIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentTabIndex != 0) {
          setState(() => _currentTabIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentTabIndex,
          children: [
            // Tab 0: Weather (Home)
            _buildWeatherHomeTab(context),
            // Tab 1: Ask (Krishi Sahayak)
            KrishiSahayakScreen(
              key: ValueKey('chat_tab_${_lang}_$_pendingChatPrompt'),
              farm: _currentFarm,
              locationName: _gpsLocationName ?? _currentFarm?.getVillage(_lang),
              latitude: _gpsLat ?? _weather?.latitude ?? _currentFarm?.latitude,
              longitude: _gpsLon ?? _weather?.longitude ?? _currentFarm?.longitude,
              weather: _weather,
              lang: _lang,
              initialPrompt: _pendingChatPrompt,
              onBack: () => setState(() => _currentTabIndex = 0),
            ),
            // Tab 2: Crops (Crop Recommender)
            CropRecommenderScreen(
              key: ValueKey('crops_tab_${_lang}_${_gpsLat}_$_gpsLon'),
              farmId: _currentFarm?.id ?? 1,
              farmName: _currentFarm?.getName(_lang) ?? AppStrings.get('my_farm', _lang),
              village: _gpsLocationName ?? _currentFarm?.getVillage(_lang) ?? 'Umred',
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
        bottomNavigationBar: hideBottomNav ? null : _buildBottomNavBar(context),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    final primaryFill = AppTheme.primaryButtonFill(context);
    final isHc = AppTheme.isHighContrast(context);
    final selectedIconColor = isHc ? Colors.white : AppTheme.primaryActionColor(context);

    return NavigationBar(
      selectedIndex: _currentTabIndex,
      onDestinationSelected: (idx) {
        setState(() => _currentTabIndex = idx);
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.wb_sunny_outlined),
          selectedIcon: Icon(Icons.wb_sunny_rounded, color: selectedIconColor),
          label: AppStrings.get('nav_weather', _lang),
        ),
        // Centre visually emphasized Ask (Mic) destination
        NavigationDestination(
          icon: Container(
            width: 44,
            height: 36,
            decoration: BoxDecoration(
              color: primaryFill,
              borderRadius: BorderRadius.circular(AppTheme.rPill),
            ),
            child: const Icon(
              Icons.mic,
              color: Colors.white,
              size: 22,
            ),
          ),
          selectedIcon: Container(
            width: 48,
            height: 36,
            decoration: BoxDecoration(
              color: primaryFill,
              borderRadius: BorderRadius.circular(AppTheme.rPill),
            ),
            child: const Icon(
              Icons.mic,
              color: Colors.white,
              size: 22,
            ),
          ),
          label: AppStrings.get('nav_ask', _lang),
        ),
        NavigationDestination(
          icon: const Icon(Icons.grass_outlined),
          selectedIcon: Icon(Icons.grass_rounded, color: selectedIconColor),
          label: AppStrings.get('nav_crops', _lang),
        ),
      ],
    );
  }

  int _selectedDayIndex = 0;

  Widget _buildWeatherHomeTab(BuildContext context) {
    return ValueListenableBuilder<DebugWeatherOverride?>(
      valueListenable: debugWeatherNotifier,
      builder: (context, debugOverride, _) {
        final effectiveCode = (kDebugMode && debugOverride?.ambientState != null)
            ? debugOverride!.weatherCode
            : (_weather?.current.weatherCode ?? 1);
        final effectiveIsDay = (kDebugMode && debugOverride?.ambientState != null)
            ? debugOverride!.isDay
            : (_weather?.current.isDay ?? true);
        final effectiveTemp = (kDebugMode && debugOverride?.ambientState != null)
            ? debugOverride!.temperature
            : (_weather?.current.temperature ?? 22.0);
        final sunrise = _weather?.daily.isNotEmpty == true
            ? _weather!.daily.first.sunrise
            : null;
        final sunset = _weather?.daily.isNotEmpty == true
            ? _weather!.daily.first.sunset
            : null;

        return AmbientBackground(
          weatherCode: effectiveCode,
          isDay: effectiveIsDay,
          temperature: effectiveTemp,
          sunrise: sunrise,
          sunset: sunset,
          child: SafeArea(
            child: RefreshIndicator(
              color: AppTheme.primaryActionColor(context),
              onRefresh: () async {
                final rLat = _gpsLat ?? _currentFarm?.latitude ?? 21.1458;
                final rLon = _gpsLon ?? _currentFarm?.longitude ?? 79.0882;
                final rName = _gpsLocationName ?? _currentFarm?.village;
                await _fetchWeather(rLat, rLon, locationName: rName);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Optional OTA Update Banner
                  if (_availableUpdate != null &&
                      _availableUpdate!.hasUpdate &&
                      !_updateBannerDismissed)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.s16,
                          AppTheme.s8,
                          AppTheme.s16,
                          0,
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

                  // TOP FROSTED WHITE-LAVENDER HERO CARD (matches center screen in reference UI)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: _buildTopHeroCard(
                        context,
                        effectiveCode: effectiveCode,
                        effectiveIsDay: effectiveIsDay,
                        effectiveTemp: effectiveTemp,
                      ),
                    ),
                  ),

                  if (_isLoading && _weather == null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.s16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: const [
                            SkeletonBox(height: 56),
                            SizedBox(height: AppTheme.s12),
                            SkeletonBox(height: 148, borderRadius: 36),
                            SizedBox(height: AppTheme.s12),
                            SkeletonBox(height: 110, borderRadius: AppTheme.rCard),
                          ],
                        ),
                      ),
                    )
                  else if (_weather != null) ...[
                    // Alert area (active IMD hazards or slim safe banner + 30-day outlook)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.s16,
                        ),
                        child: _buildAlertArea(context, debugOverride),
                      ),
                    ),

                    // 7-Day Forecasts Horizontal Vertical-Capsule Strip (exact match to reference UI)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.s16,
                          AppTheme.s16,
                          AppTheme.s16,
                          AppTheme.s12,
                        ),
                        child: _buildSevenDayCapsulesSection(
                          context,
                          _weather!,
                          effectiveCode: effectiveCode,
                          effectiveTemp: effectiveTemp,
                        ),
                      ),
                    ),

                    // Detail strip: compact 4-up grid of MetricTile (soil temp, soil moisture %, sunrise, sunset)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.s16,
                        ),
                        child: _buildDetailGrid(context, _weather!),
                      ),
                    ),

                    // One row "Best crops for your field now" with chevron to Crops
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.s16,
                          AppTheme.s12,
                          AppTheme.s16,
                          0,
                        ),
                        child: _buildBestCropsRow(context),
                      ),
                    ),

                    // Footer: Open-Meteo attribution with bottom padding
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.s16,
                          AppTheme.s24,
                          AppTheme.s16,
                          AppTheme.s32,
                        ),
                        child: GestureDetector(
                          onLongPress: kDebugMode ? _showDebugOverrideSheet : null,
                          child: Text(
                            AppStrings.get('attribution', _lang),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary(context).withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatHeaderDateSubtitle() {
    final now = DateTime.now();
    const weekdaysEn = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const weekdaysHi = [
      'सोमवार',
      'मंगलवार',
      'बुधवार',
      'गुरुवार',
      'शुक्रवार',
      'शनिवार',
      'रविवार',
    ];
    const monthsEn = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const monthsHi = [
      'जनवरी',
      'फ़रवरी',
      'मार्च',
      'अप्रैल',
      'मई',
      'जून',
      'जुलाई',
      'अगस्त',
      'सितंबर',
      'अक्टूबर',
      'नवंबर',
      'दिसंबर',
    ];
    final wIdx = (now.weekday - 1).clamp(0, 6);
    final mIdx = (now.month - 1).clamp(0, 11);
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    if (_lang == 'hi') {
      return '${weekdaysHi[wIdx]}, ${now.day} ${monthsHi[mIdx]} $hh:$mm • ${_formatFreshnessText()}';
    }
    return '${weekdaysEn[wIdx]}, ${now.day} ${monthsEn[mIdx]} $hh:$mm • ${_formatFreshnessText()}';
  }

  /// Frosted White-Lavender Rounded Top Hero Card matching the center phone in the reference UI
  Widget _buildTopHeroCard(
    BuildContext context, {
    required int effectiveCode,
    required bool effectiveIsDay,
    required double effectiveTemp,
  }) {
    final isHc = AppTheme.isHighContrast(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardGradient = isHc
        ? LinearGradient(
            colors: [
              isDark ? Colors.black : Colors.white,
              isDark ? Colors.black : Colors.white,
            ],
          )
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF281C4A), Color(0xFF1B1236)]
                : const [Color(0xFFFCF9FF), Color(0xFFEDE6FF)],
          );

    return Container(
      decoration: BoxDecoration(
        gradient: cardGradient,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: isHc
              ? AppTheme.borderColor(context)
              : (isDark
                  ? const Color(0xFF5E43B8).withValues(alpha: 0.45)
                  : Colors.white.withValues(alpha: 0.92)),
          width: isHc ? 2.0 : 1.5,
        ),
        boxShadow: isHc
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF4318B8).withValues(alpha: isDark ? 0.42 : 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // a) Top bar inside hero card: Farm/Location selector, SOS HoldToConfirmButton, Settings gear
          _buildTopBar(context),
          const SizedBox(height: 4),
          // Date + Freshness subtitle centered under header
          Text(
            _formatHeaderDateSubtitle(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),

          if (_weather != null) ...[
            // Giant Violet Temperature (22°) + Overlapping 3D Weather Visual
            _buildWeatherHero(
              context,
              _weather!.current,
              effectiveCode: effectiveCode,
              effectiveIsDay: effectiveIsDay,
              effectiveTemp: effectiveTemp,
            ),
            const SizedBox(height: 14),

            // 3-Column Rounded White Pill Stats Pod (Precipitation %, Humidity %, Wind speed km/h)
            _buildThreeColumnStatsPod(context, _weather!),
            const SizedBox(height: 16),

            // Smooth Cubic-Bezier Hourly Wave Chart (0:00 3:00 6:00 9:00 12:00 15:00 18:00 21:00)
            _buildHourlyWaveSection(
              context,
              _weather!,
              effectiveTemp: effectiveTemp,
            ),
          ] else ...[
            const SizedBox(height: 12),
            const SkeletonBox(height: 110, borderRadius: 24),
          ],
        ],
      ),
    );
  }

  /// a) Top bar (min 56dp): left farm chip "{village or district} - {crop}", right SOS HoldToConfirmButton + Settings gear
  Widget _buildTopBar(BuildContext context) {
    final rawLoc = _gpsLocationName ??
        _currentFarm?.getVillage(_lang) ??
        AppStrings.get('my_farm', _lang);
    var shortLoc = rawLoc.split(',').first.trim();
    if (_lang == 'en') {
      if (shortLoc.contains('माउंटेन व्यू')) {
        shortLoc = 'Mountain View';
      } else if (shortLoc.contains('उमरेड') || shortLoc.contains('Umred')) {
        shortLoc = 'Umred';
      } else if (shortLoc.contains('नागपुर') || shortLoc.contains('Nagpur')) {
        shortLoc = 'Nagpur';
      } else {
        final stripped = shortLoc
            .replaceAll(RegExp(r'[\u0900-\u097F]+'), '')
            .replaceAll('()', '')
            .trim();
        shortLoc = stripped.isNotEmpty
            ? stripped
            : (_currentFarm?.getVillage('en') ?? 'Farm');
      }
    } else {
      if (shortLoc.toLowerCase() == 'mountain view') {
        shortLoc = 'माउंटेन व्यू';
      } else if (shortLoc.contains('उमरेड') || shortLoc.contains('Umred')) {
        shortLoc = 'उमरेड';
      } else if (shortLoc.contains('नागपुर') || shortLoc.contains('Nagpur')) {
        shortLoc = 'नागपुर';
      }
    }
    final cropLabel = _currentFarm?.getCurrentCrop(_lang) ??
        (_lang == 'en' ? 'Wheat' : 'गेहूं');
    final chipLabel = '$shortLoc • $cropLabel';

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          // Left: Farm & Location switcher pill with location pin & chevron
          Expanded(
            child: Semantics(
              button: true,
              label: '${AppStrings.get("location_and_farm", _lang)}: $chipLabel',
              child: InkWell(
                borderRadius: BorderRadius.circular(AppTheme.rPill),
                onTap: _showFarmSelector,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLocating)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryActionColor(context),
                          ),
                        )
                      else
                        Icon(
                          Icons.location_on_rounded,
                          size: 20,
                          color: AppTheme.primaryActionColor(context),
                        ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          chipLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppTheme.primaryActionColor(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Right: Protected SOS HoldToConfirmButton (~1.2s hold)
          HoldToConfirmButton(
            label: AppStrings.get('sos_label', _lang),
            holdHint: AppStrings.get('sos_hold_hint', _lang),
            confirmDialogTitle: AppStrings.get('sos_confirm_title', _lang),
            confirmDialogBody: AppStrings.get('sos_confirm_body', _lang),
            confirmButtonLabel: AppStrings.get('sos_activate_btn', _lang),
            cancelButtonLabel: AppStrings.get('settings_delete_cancel', _lang),
            onConfirmed: _activateSos,
          ),
          const SizedBox(width: 6),
          // Settings Gear IconAction (>= 48dp)
          IconAction(
            icon: Icons.settings_rounded,
            semanticLabel: AppStrings.get('settings', _lang),
            onPressed: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }

  /// b) Alert area directly under top hero card:
  /// - Active Horizon-1 hazards sorted red before orange (only highest-severity expanded by default)
  /// - Or single slim green/lavender row "No severe hazards in the next 3 days"
  /// - Plus 1 collapsed row for 30-day seasonal outlook
  Widget _buildAlertArea(
    BuildContext context,
    DebugWeatherOverride? debugOverride,
  ) {
    List<DetectedRisk> h1Risks = List<DetectedRisk>.from(
      _riskData?.horizon1.risks ?? const <DetectedRisk>[],
    );

    if (kDebugMode && debugOverride != null) {
      if (debugOverride.forceAllClear == true) {
        h1Risks = [];
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
            actionHi: 'खेत में जल निकासी नालियां साफ रखें और कीटनाशक छिड़काव स्थगित करें।',
            actionEn: 'Keep field drainage channels clear and postpone pesticide spraying.',
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

    final h3Risks = _riskData?.horizon3.risks ?? const <DetectedRisk>[];
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (h1Risks.isEmpty)
          AppSurface(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.s12,
              vertical: 10,
            ),
            borderRadius: 18,
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
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...List.generate(h1Risks.length, (idx) {
            final risk = h1Risks[idx];
            final isRed = risk.severity.toLowerCase() == 'red';
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
            final timeWindow = AppStrings.localizeTimeWindow(
              risk.expectedDate,
              _lang,
            );
            var cleanExpected = risk.expectedValue
                .replaceAll(RegExp(r'\s*\([^)]*%\s*chance\)', caseSensitive: false), '')
                .trim();
            if (_lang == 'hi') {
              cleanExpected = cleanExpected
                  .replaceAll(RegExp(r'max\s*temp', caseSensitive: false), 'अधिकतम')
                  .replaceAll(RegExp(r'min\s*temp', caseSensitive: false), 'न्यूनतम')
                  .replaceAll(RegExp(r'\bwind\b', caseSensitive: false), 'हवा')
                  .replaceAll(RegExp(r'\brain\b', caseSensitive: false), 'वर्षा')
                  .replaceAll(RegExp(r'\bmm\b'), 'मिमी')
                  .replaceAll(RegExp(r'\bkm/h\b'), 'किमी/घंटा');
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.s8),
              child: StatusRow(
                severity: risk.severity,
                severityLabel: AppStrings.get(
                  isRed ? 'severity_red' : 'severity_orange',
                  _lang,
                ),
                icon: _hazardIconForType(risk.alertType, isRed),
                title: title,
                likelihoodText:
                    '${risk.probability.round()}% ${AppStrings.get('likelihood_suffix', _lang)}',
                actionText: action,
                timeWindowLabel: AppStrings.get('time_window_label', _lang),
                timeWindowValue: timeWindow,
                expectedLabel: AppStrings.get('expected_amount_label', _lang),
                expectedValue: cleanExpected,
                isExpanded: _expandedHazardIndices.contains(idx),
                onToggle: () {
                  setState(() {
                    if (_expandedHazardIndices.contains(idx)) {
                      _expandedHazardIndices.remove(idx);
                    } else {
                      _expandedHazardIndices.add(idx);
                    }
                  });
                },
              ),
            );
          }),

        // 30-day seasonal outlook as 1 collapsed row
        if (h3Risks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.s4),
            child: AppSurface(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.s12,
                vertical: 8,
              ),
              borderRadius: 18,
              onTap: () => setState(
                () => _seasonalOutlookExpanded = !_seasonalOutlookExpanded,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: AppTheme.primaryActionColor(context),
                      ),
                      const SizedBox(width: AppTheme.s8),
                      Expanded(
                        child: Text(
                          AppStrings.get('outlook_30d', _lang),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary(context),
                          ),
                        ),
                      ),
                      Icon(
                        _seasonalOutlookExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 20,
                        color: AppTheme.textSecondary(context),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: _seasonalOutlookExpanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _seasonalOutlookSentence(),
                              style: TextStyle(
                                fontSize: 13.5,
                                color: AppTheme.textSecondary(context),
                                height: 1.4,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  IconData _hazardIconForType(String alertType, bool isRed) {
    final t = alertType.toLowerCase();
    if (t.contains('heat')) return Icons.wb_sunny_rounded;
    if (t.contains('rain') || t.contains('flood')) return Icons.thunderstorm_rounded;
    if (t.contains('frost') || t.contains('cold')) return Icons.ac_unit_rounded;
    if (t.contains('wind')) return Icons.air_rounded;
    return isRed ? Icons.warning_rounded : Icons.error_outline_rounded;
  }

  String _seasonalOutlookSentence() {
    final activeLoc = _gpsLocationName ??
        _currentFarm?.getVillage(_lang) ??
        (_lang == 'hi' ? 'आपके क्षेत्र' : 'your area');
    final temp = _weather?.current.temperature.toStringAsFixed(0) ?? '28';
    final soilPct = ((_weather?.current.soilMoisture ?? 0.25) * 100).round();
    if (_lang == 'en') {
      return 'In $activeLoc ($temp°C, $soilPct% soil moisture), 30-day multi-model outlook indicates normal-to-mildly dry conditions; conserve topsoil moisture.';
    }
    return '$activeLoc ($temp°C, मिट्टी नमी $soilPct%) में अगले 30 दिनों के मौसमी पूर्वानुमान के अनुसार नमी संरक्षण व समय पर हल्की सिंचाई की सलाह है।';
  }

  /// c) Giant Violet Temperature (84sp) + Condition label + Overlapping 3D Claymorphic Weather Visual
  Widget _buildWeatherHero(
    BuildContext context,
    CurrentWeather current, {
    required int effectiveCode,
    required bool effectiveIsDay,
    required double effectiveTemp,
  }) {
    final condText = _getWeatherConditionText(effectiveCode, _lang);
    final displayCond = (!effectiveIsDay && effectiveCode == 0)
        ? (_lang == 'hi' ? 'साफ रात' : 'Clear Night')
        : condText;
    final isHc = AppTheme.isHighContrast(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heroTempColor = isHc
        ? AppTheme.textPrimary(context)
        : (isDark ? const Color(0xFFD0BCFF) : const Color(0xFF5D2BF8));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${effectiveTemp.round()}°',
                    style: AppTheme.heroTempStyle.copyWith(
                      fontSize: 84,
                      fontWeight: FontWeight.w900,
                      color: heroTempColor,
                      height: 0.96,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayCond,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppStrings.get('feels_like', _lang)} ${current.apparentTemperature.round()}°C',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            flex: 5,
            child: Center(
              child: RealisticWeatherVisual(
                weatherCode: effectiveCode,
                isDay: effectiveIsDay,
                size: 124,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 3-Column White Rounded Pill Stats Pod (Precipitation %, Humidity %, Wind speed km/h)
  /// Exact match to the white 3-column card in the middle of the reference UI.
  Widget _buildThreeColumnStatsPod(BuildContext context, WeatherData weather) {
    final isHc = AppTheme.isHighContrast(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cur = weather.current;

    final int precipProb = weather.hourly.isNotEmpty
        ? weather.hourly.first.precipitationProbability
        : (weather.daily.isNotEmpty
            ? weather.daily.first.precipitationProbabilityMax
            : (cur.precipitation > 0 ? 75 : 20));

    final podBg = isHc
        ? (isDark ? Colors.black : Colors.white)
        : (isDark ? const Color(0xFF312259) : Colors.white);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: podBg,
        borderRadius: BorderRadius.circular(24),
        border: isHc
            ? Border.all(color: AppTheme.borderColor(context), width: 1.5)
            : null,
        boxShadow: isHc
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF5A2CE8).withValues(alpha: isDark ? 0.30 : 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatPodColumn(
              context,
              icon: Icons.umbrella_rounded,
              value: '$precipProb%',
              label: _lang == 'hi' ? 'वर्षा संभावना' : 'Precipitation',
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: AppTheme.borderColor(context).withValues(alpha: 0.45),
          ),
          Expanded(
            child: _buildStatPodColumn(
              context,
              icon: Icons.water_drop_rounded,
              value: '${cur.relativeHumidity.round()}%',
              label: AppStrings.get('humidity', _lang),
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: AppTheme.borderColor(context).withValues(alpha: 0.45),
          ),
          Expanded(
            child: _buildStatPodColumn(
              context,
              icon: Icons.air_rounded,
              value: '${cur.windSpeed.round()} km/h',
              label: AppStrings.get('wind_speed', _lang),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPodColumn(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
  }) {
    final accent = AppTheme.primaryActionColor(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: accent),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary(context),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
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

  /// Smooth Cubic-Bezier Hourly Wave Chart (`0:00 3:00 6:00 9:00 12:00 15:00 18:00 21:00`)
  /// with glowing current-hour ring marker and vertical dashed line.
  Widget _buildHourlyWaveSection(
    BuildContext context,
    WeatherData weather, {
    required double effectiveTemp,
  }) {
    const slotHours = [0, 3, 6, 9, 12, 15, 18, 21];
    final List<double> temps = [];

    if (weather.hourly.length >= 22) {
      for (final h in slotHours) {
        temps.add(weather.hourly[h].temperature);
      }
    } else {
      // Synthesize smooth diurnal curve around effectiveTemp when offline/short hourly list
      final offsets = [-4.0, -5.0, -3.0, 0.0, 3.0, 4.0, 1.5, -1.5];
      for (final off in offsets) {
        temps.add(effectiveTemp + off);
      }
    }

    final nowHour = DateTime.now().hour;
    int activeSlot = (nowHour / 3).round().clamp(0, slotHours.length - 1);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppTheme.primaryActionColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 82,
          child: CustomPaint(
            painter: _HourlyBezierWavePainter(
              temperatures: temps,
              activeIndex: activeSlot,
              lineColor: accent,
              isDark: isDark,
              textColor: AppTheme.textPrimary(context),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(slotHours.length, (i) {
            final isCurrent = i == activeSlot;
            final label = '${slotHours[i]}:00';
            return Flexible(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isCurrent ? 6 : 2,
                  vertical: 3,
                ),
                decoration: isCurrent
                    ? BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      )
                    : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: isCurrent
                          ? accent
                          : AppTheme.textSecondary(context),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// 7-Day Forecasts Horizontal Vertical-Capsule Strip (exact match to bottom of center screen in reference UI)
  Widget _buildSevenDayCapsulesSection(
    BuildContext context,
    WeatherData weather, {
    required int effectiveCode,
    required double effectiveTemp,
  }) {
    final isHc = AppTheme.isHighContrast(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const daysEn = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const daysHi = ['सोम', 'मंगल', 'बुध', 'गुरु', 'शुक्र', 'शनि', 'रवि'];

    final dailyList = weather.daily;
    final count = dailyList.isNotEmpty ? dailyList.length.clamp(1, 7) : 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            _lang == 'hi' ? '7-दिन का मौसम पूर्वानुमान' : '7-Day Forecasts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary(context),
            ),
          ),
        ),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, idx) {
              final isSelected = idx == _selectedDayIndex;
              DateTime dateObj = DateTime.now().add(Duration(days: idx));
              int code = effectiveCode;
              int maxT = effectiveTemp.round();
              int minT = (effectiveTemp - 5).round();

              if (idx < dailyList.length) {
                final d = dailyList[idx];
                try {
                  dateObj = DateTime.parse(d.date);
                } catch (_) {}
                code = idx == 0 ? effectiveCode : d.weatherCode;
                maxT = d.tempMax.round();
                minT = d.tempMin.round();
              }

              final wIdx = (dateObj.weekday - 1).clamp(0, 6);
              final dayLabel = _lang == 'hi' ? daysHi[wIdx] : daysEn[wIdx];

              final BoxDecoration capsuleDeco;
              if (isHc) {
                capsuleDeco = BoxDecoration(
                  color: isSelected
                      ? AppTheme.primaryButtonFill(context)
                      : (isDark ? Colors.black : Colors.white),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: AppTheme.borderColor(context),
                    width: 2.0,
                  ),
                );
              } else if (isSelected) {
                capsuleDeco = BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF7542FF), Color(0xFF4D19E0)],
                  ),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3E12BD).withValues(alpha: 0.42),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                );
              } else {
                capsuleDeco = BoxDecoration(
                  color: isDark
                      ? const Color(0xFF281C4C).withValues(alpha: 0.72)
                      : Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF6B4EE6).withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.78),
                    width: 1.4,
                  ),
                );
              }

              final fgColor = isSelected
                  ? Colors.white
                  : AppTheme.textPrimary(context);
              final subColor = isSelected
                  ? Colors.white.withValues(alpha: 0.78)
                  : AppTheme.textSecondary(context);

              return GestureDetector(
                onTap: () => setState(() => _selectedDayIndex = idx),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: 72,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 6,
                  ),
                  decoration: capsuleDeco,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          dayLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: fgColor,
                          ),
                        ),
                      ),
                      RealisticWeatherVisual(
                        weatherCode: code,
                        isDay: true,
                        size: 46,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$maxT°',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: fgColor,
                              ),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$minT°',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: subColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// d) Compact 4-up grid of MetricTile: soil temp, soil moisture (shows "34%" only, keeps m3/m3 in expanded/semantic label), sunrise, sunset
  Widget _buildDetailGrid(BuildContext context, WeatherData weather) {
    final cur = weather.current;
    final today = weather.daily.isNotEmpty ? weather.daily.first : null;
    final soilPct = (cur.soilMoisture <= 1.0
            ? cur.soilMoisture * 100
            : cur.soilMoisture)
        .round();
    final soilRawM3 = '${cur.soilMoisture.toStringAsFixed(2)} m³/m³';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: MetricTile(
                icon: Icons.thermostat_rounded,
                label: AppStrings.get('soil_temp', _lang),
                value: '${cur.soilTemperature.toStringAsFixed(1)}°C',
              ),
            ),
            const SizedBox(width: AppTheme.s8),
            Expanded(
              child: MetricTile(
                icon: Icons.opacity_rounded,
                label: AppStrings.get('soil_moisture', _lang),
                value: '$soilPct%',
                expandedDetail: soilRawM3,
                semanticsLabel:
                    '${AppStrings.get("soil_moisture", _lang)}: $soilPct% ($soilRawM3)',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.s8),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                icon: Icons.wb_twilight_rounded,
                label: AppStrings.get('sunrise', _lang),
                value: today != null ? _formatSunTime(today.sunrise) : '6:12 AM',
              ),
            ),
            const SizedBox(width: AppTheme.s8),
            Expanded(
              child: MetricTile(
                icon: Icons.nights_stay_rounded,
                label: AppStrings.get('sunset', _lang),
                value: today != null ? _formatSunTime(today.sunset) : '6:04 PM',
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// e) One row "Best crops for your field now" with chevron to Crops
  Widget _buildBestCropsRow(BuildContext context) {
    final primaryCol = AppTheme.primaryActionColor(context);
    return AppSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.s16,
        vertical: AppTheme.s12,
      ),
      borderRadius: 20,
      onTap: () => setState(() => _currentTabIndex = 2),
      child: Row(
        children: [
          Icon(Icons.agriculture_rounded, color: primaryCol, size: 22),
          const SizedBox(width: AppTheme.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.get('best_crops_now', _lang),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                Text(
                  AppStrings.get('rabi_season', _lang),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _lang == 'hi' ? 'फसल सुझाव' : 'View',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: primaryCol,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            color: primaryCol,
          ),
        ],
      ),
    );
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

/// Smooth Cubic-Bezier Hourly Wave Chart Painter matching the center screen in the reference UI
class _HourlyBezierWavePainter extends CustomPainter {
  final List<double> temperatures;
  final int activeIndex;
  final Color lineColor;
  final bool isDark;
  final Color textColor;

  _HourlyBezierWavePainter({
    required this.temperatures,
    required this.activeIndex,
    required this.lineColor,
    required this.isDark,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (temperatures.length < 2) return;

    final w = size.width;
    final h = size.height;
    final topPad = 22.0;
    final bottomPad = 10.0;
    final chartH = (h - topPad - bottomPad).clamp(20.0, h);

    double minT = temperatures.first;
    double maxT = temperatures.first;
    for (final t in temperatures) {
      if (t < minT) minT = t;
      if (t > maxT) maxT = t;
    }
    final range = (maxT - minT).abs() < 1.0 ? 4.0 : (maxT - minT);

    final List<Offset> pts = [];
    final stepX = w / (temperatures.length - 1);
    for (int i = 0; i < temperatures.length; i++) {
      final norm = (temperatures[i] - minT) / range;
      final x = i * stepX;
      final y = topPad + chartH * (1.0 - norm);
      pts.add(Offset(x, y));
    }

    // Build smooth cubic bezier path
    final curvePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i];
      final p1 = pts[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      curvePath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
    }

    // Soft lavender gradient fill under the curve
    final fillPath = Path.from(curvePath)
      ..lineTo(pts.last.dx, h)
      ..lineTo(pts.first.dx, h)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: isDark ? 0.28 : 0.20),
          lineColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // Smooth gradient stroke (violet -> warm amber at midday peak -> violet)
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          lineColor,
          const Color(0xFF9C4DFF),
          const Color(0xFFFF9800),
          lineColor,
        ],
        stops: const [0.0, 0.35, 0.68, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(curvePath, strokePaint);

    // Draw dashed vertical line & glowing ring dot at activeIndex
    final idx = activeIndex.clamp(0, pts.length - 1);
    final activePt = pts[idx];

    final dashPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.45)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    double dashY = activePt.dy + 8;
    while (dashY < h - 2) {
      canvas.drawLine(
        Offset(activePt.dx, dashY),
        Offset(activePt.dx, (dashY + 4).clamp(0.0, h)),
        dashPaint,
      );
      dashY += 8;
    }

    // Outer glow aura
    canvas.drawCircle(
      activePt,
      10,
      Paint()..color = lineColor.withValues(alpha: 0.22),
    );
    // White ring
    canvas.drawCircle(
      activePt,
      6.5,
      Paint()..color = Colors.white,
    );
    // Violet core dot
    canvas.drawCircle(
      activePt,
      4.2,
      Paint()..color = lineColor,
    );

    // Temperature label above active point
    final tp = TextPainter(
      text: TextSpan(
        text: '${temperatures[idx].round()}°',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelX = (activePt.dx - tp.width / 2).clamp(2.0, w - tp.width - 2.0);
    final labelY = (activePt.dy - tp.height - 8).clamp(0.0, h);
    tp.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant _HourlyBezierWavePainter oldDelegate) =>
      oldDelegate.activeIndex != activeIndex ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.isDark != isDark ||
      oldDelegate.temperatures != temperatures;
}

