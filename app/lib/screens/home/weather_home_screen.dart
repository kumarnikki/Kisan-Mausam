import 'dart:ui';
import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../models/farm_profile.dart';
import '../../models/weather_models.dart';
import '../../models/risk_models.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../services/location_service.dart';
import '../../services/alert_service.dart';
import '../../widgets/mic_button.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/realistic_weather_visual.dart';
import '../crops/crop_recommender_screen.dart';
import '../chat/krishi_sahayak_screen.dart';
import '../../services/update_service.dart';

class WeatherHomeScreen extends StatefulWidget {
  final VoidCallback onOpenSettings;

  const WeatherHomeScreen({super.key, required this.onOpenSettings});

  @override
  State<WeatherHomeScreen> createState() => _WeatherHomeScreenState();
}

class _WeatherHomeScreenState extends State<WeatherHomeScreen> {
  final ApiService _apiService = ApiService();

  List<FarmProfile> _farms = [];
  FarmProfile? _currentFarm;
  WeatherData? _weather;
  FarmRiskData? _riskData;
  bool _isLoading = true;
  bool _isLocating = false; // GPS location fetch in progress
  String _lang = 'hi';
  DateTime? _cachedTime;
  // Custom GPS location (overrides farm lat/lon)
  double? _gpsLat;
  double? _gpsLon;
  String? _gpsLocationName;
  String? _userPhone;
  String? _lastWeatherSmsLocationKey;
  AppUpdateInfo? _availableUpdate;
  bool _updateBannerDismissed = false;

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
    final current = farms.firstWhere((f) => f.id == activeId, orElse: () => farms.first);

    // Check if we have previously detected user's real GPS/IP location
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

    setState(() {
      _lang = lang;
      _farms = farms;
      _currentFarm = current;
      _userPhone = savedPhone;
    });

    await _fetchWeather(initialLat, initialLon, locationName: initialName);

    // Auto-fetch user's current GPS location first, then request SMS permission so Android permission dialogs never collide
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

  /// Automatically fetch live GPS location on app start without blocking initial view
  Future<void> _autoFetchGPSLocation() async {
    try {
      final loc = await LocationService.getCurrentLocation(fallbackToIp: true, lang: _lang);
      if (!mounted || loc == null) return;
      final diff = (_gpsLat == null || _gpsLon == null)
          ? 1.0
          : ((_gpsLat! - loc.latitude).abs() + (_gpsLon! - loc.longitude).abs());

      setState(() {
        _gpsLat = loc.latitude;
        _gpsLon = loc.longitude;
        _gpsLocationName = loc.displayName;
      });
      await StorageService.saveLastLocation(loc.latitude, loc.longitude, loc.displayName);

      // Re-fetch weather if coordinates differ or initial weather was missing
      if (diff > 0.05 || _weather == null) {
        await _fetchWeather(loc.latitude, loc.longitude, locationName: loc.displayName);
      }
    } catch (_) {}
  }

  Future<void> _fetchWeather(double lat, double lon, {String? locationName}) async {
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

      // Fetch risks with active location coordinates, name & live weather
      _apiService.getFarmRisks(
        _currentFarm?.id ?? 1,
        lat: lat,
        lon: lon,
        locationName: locName,
        weather: data,
      ).then((r) {
        if (mounted && r != null) {
          setState(() => _riskData = r);
          _checkAndShowAlertPopup(r, weather: data, locKey: cacheKey);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Called when risk data loads — pops up an alert dialog for red risks and sends SMS for weather/climate changes.
  void _checkAndShowAlertPopup(FarmRiskData risk, {WeatherData? weather, String? locKey}) {
    final redRisks = risk.horizon1.risks.where((r) => r.severity == 'red').toList();
    final orangeRisks = risk.horizon1.risks.where((r) => r.severity == 'orange').toList();
    final activeLoc = _gpsLocationName ?? _currentFarm?.village ?? (_lang == 'hi' ? 'आपके क्षेत्र' : 'your location');

    if (redRisks.isNotEmpty) {
      final r = redRisks.first;
      _autoSendRiskSms(r);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AlertService.showHazardAlert(
            context,
            titleHi: r.titleHi,
            titleEn: r.titleEn,
            bodyHi: '$activeLoc में ${r.expectedValue} की संभावना है। तुरंत सावधानी बरतें।',
            bodyEn: 'Risk detected at $activeLoc: ${r.expectedValue}.',
            severity: 'red',
            actionHi: _lang == 'hi' ? r.actionHi : (r.actionEn.isNotEmpty ? r.actionEn : r.actionHi),
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
    } else if (weather != null && locKey != null && _lastWeatherSmsLocationKey != locKey) {
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
    final msg = 'KisanMausam Weather ($locEn): Temp ${temp}C, $condEn, Wind ${wind}km/h, Humidity $hum%. Farm weather is currently safe.';

    final sent = await _apiService.sendWeatherOrSosSms(
      phone: savedPhone,
      alertType: 'weather_change',
      message: msg,
    );
    if (sent && mounted) {
      final isHi = _lang == 'hi';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1B5E20),
          duration: const Duration(seconds: 3),
          content: Text(
            isHi
                ? '📲 मौसम अपडेट SMS +91 $savedPhone पर भेजा गया'
                : '📲 Weather Update SMS sent to +91 $savedPhone',
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
    final alertNameDisplay = isHi ? r.titleHi : (r.titleEn.isNotEmpty ? r.titleEn : r.titleHi);
    final alertNameAscii = r.titleEn.isNotEmpty ? r.titleEn : 'Weather Hazard Alert';
    final actionAscii = r.actionEn.isNotEmpty ? r.actionEn : 'Take immediate crop protection measures.';
    final msg = 'KisanMausam Alert ($loc): $alertNameAscii (${r.expectedValue}, ${r.probability.round()}% risk). Action: $actionAscii';
    final sent = await _apiService.sendWeatherOrSosSms(
      phone: savedPhone,
      alertType: r.alertType,
      message: msg,
    );
    if (sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1B5E20),
          duration: const Duration(seconds: 3),
          content: Text(
            isHi
                ? '📲 मौसम अलर्ट SMS ($alertNameDisplay) +91 $savedPhone पर भेजा गया'
                : '📲 Weather Alert SMS ($alertNameDisplay) sent to +91 $savedPhone',
          ),
        ),
      );
    }
  }

  /// Fetch GPS location and reload weather for current GPS position.
  Future<void> _fetchCurrentLocationGPS() async {
    setState(() => _isLocating = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_lang == 'hi' ? '📍 GPS स्थान प्राप्त किया जा रहा है...' : '📍 Getting GPS location...'),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1B5E20),
      ),
    );

    final loc = await LocationService.getCurrentLocation(fallbackToIp: true, lang: _lang);
    if (!mounted) return;

    if (loc != null) {
      setState(() {
        _gpsLat = loc.latitude;
        _gpsLon = loc.longitude;
        _gpsLocationName = loc.displayName;
        _isLocating = false;
        _isLoading = true;
      });
      await StorageService.saveLastLocation(loc.latitude, loc.longitude, loc.displayName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lang == 'hi' ? '✅ स्थान: ${loc.displayName}' : '✅ Location: ${loc.displayName}'),
          backgroundColor: const Color(0xFF1B5E20),
        ),
      );
      await _fetchWeather(loc.latitude, loc.longitude, locationName: loc.displayName);
    } else {
      setState(() => _isLocating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lang == 'hi' ? '⚠️ GPS उपलब्ध नहीं। कृपया अनुमति दें।' : '⚠️ GPS unavailable. Please grant permission.'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    }
  }

  /// Show a location search dialog to switch location.
  Future<void> _showLocationSearchDialog() async {
    final controller = TextEditingController();
    List<LocationResult> results = [];
    bool isSearching = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.search, color: Color(0xFF1B5E20)),
              const SizedBox(width: 8),
              Text(_lang == 'hi' ? 'स्थान बदलें' : 'Change Location'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: _lang == 'hi' ? 'शहर / गाँव का नाम' : 'City / Village name',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () async {
                              if (controller.text.trim().isEmpty) return;
                              setDialogState(() => isSearching = true);
                              final r = await LocationService.searchLocation(controller.text.trim(), lang: _lang);
                              setDialogState(() {
                                results = r;
                                isSearching = false;
                              });
                            },
                          ),
                  ),
                  onSubmitted: (q) async {
                    if (q.trim().isEmpty) return;
                    setDialogState(() => isSearching = true);
                    final r = await LocationService.searchLocation(q.trim(), lang: _lang);
                    setDialogState(() {
                      results = r;
                      isSearching = false;
                    });
                  },
                ),
                if (results.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final item = results[i];
                        return ListTile(
                          leading: const Icon(Icons.location_on, color: Color(0xFF1B5E20), size: 20),
                          title: Text(item.displayName, style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            '${item.latitude.toStringAsFixed(3)}°N, ${item.longitude.toStringAsFixed(3)}°E',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            setState(() {
                              _gpsLat = item.latitude;
                              _gpsLon = item.longitude;
                              _gpsLocationName = item.displayName;
                              _isLoading = true;
                            });
                            await StorageService.saveLastLocation(item.latitude, item.longitude, item.displayName);
                            await _fetchWeather(item.latitude, item.longitude, locationName: item.displayName);
                          },
                        );
                      },
                    ),
                  )
                else if (!isSearching && controller.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _lang == 'hi' ? 'कोई परिणाम नहीं मिला' : 'No results found',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_lang == 'hi' ? 'रद्द करें' : 'Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  String _getWeatherConditionText(int code, String lang) {
    if (code == 0) return lang == 'hi' ? 'साफ धूप' : 'Clear Sky';
    if (code >= 1 && code <= 3) return lang == 'hi' ? 'हल्के बादल' : 'Partly Cloudy';
    if (code == 45 || code == 48) return lang == 'hi' ? 'कोहरा' : 'Foggy';
    if (code >= 51 && code <= 55) return lang == 'hi' ? 'हल्की बूंदाबांदी' : 'Drizzle';
    if (code >= 61 && code <= 65) return lang == 'hi' ? 'बारिश' : 'Rain';
    if (code >= 80 && code <= 82) return lang == 'hi' ? 'तेज बौछारें' : 'Rain Showers';
    if (code == 95) return lang == 'hi' ? 'गरज-चमक के साथ बारिश' : 'Thunderstorm';
    if (code == 96 || code == 99) return lang == 'hi' ? 'ओलावृष्टि तूफान' : 'Thunderstorm with Hail';
    return lang == 'hi' ? 'सामान्य मौसम' : 'Fair Weather';
  }

  String _formatLastUpdated() {
    if (_cachedTime == null) return '';
    final diff = DateTime.now().difference(_cachedTime!);
    if (diff.inMinutes < 1) return _lang == 'hi' ? 'अभी-अभी' : 'Just now';
    if (diff.inMinutes < 60) return _lang == 'hi' ? '${diff.inMinutes} मिनट पहले' : '${diff.inMinutes}m ago';
    return _lang == 'hi' ? '${diff.inHours} घंटे पहले' : '${diff.inHours}h ago';
  }

  void _openCropRecommender() {
    final isHi = _lang == 'hi';
    final activeLoc = _gpsLocationName ?? _currentFarm?.getVillage(_lang) ?? (isHi ? 'उमरेड' : 'Umred');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CropRecommenderScreen(
          farmId: _currentFarm?.id ?? 1,
          farmName: _currentFarm?.getName(_lang) ?? (isHi ? 'मेरा खेत' : 'My Farm'),
          village: activeLoc,
          farm: _currentFarm,
          lang: _lang,
          latitude: _gpsLat ?? _currentFarm?.latitude,
          longitude: _gpsLon ?? _currentFarm?.longitude,
          weather: _weather,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: ProminentMicButton(
        label: AppStrings.get('voice_assistant_btn', _lang),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => KrishiSahayakScreen(
                farm: _currentFarm,
                locationName: _gpsLocationName ?? _currentFarm?.village,
                latitude: _gpsLat ?? _weather?.latitude ?? _currentFarm?.latitude,
                longitude: _gpsLon ?? _weather?.longitude ?? _currentFarm?.longitude,
                weather: _weather,
                lang: _lang,
              ),
            ),
          );
        },
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8F5E9), // Gentle morning mist green
              Color(0xFFF1F8E9), // Light pasture green
              Color(0xFFF7FAF7), // Clean airy surface
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            color: const Color(0xFF1B5E20),
            onRefresh: () async {
              final rLat = _gpsLat ?? _currentFarm?.latitude ?? 28.6139;
              final rLon = _gpsLon ?? _currentFarm?.longitude ?? 77.2090;
              final rName = _gpsLocationName ?? _currentFarm?.village;
              await _fetchWeather(rLat, rLon, locationName: rName);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // 1. Top Bar with Farm Switcher & Settings Icon in Glass Capsule
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: GlassCard(
                      borderRadius: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          // Farm Switcher Dropdown (Tap to change location, auto-locate or search)
                          Expanded(
                            child: InkWell(
                              onTap: _showFarmSelector,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: _isLocating
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B5E20)),
                                            )
                                          : const Icon(Icons.location_on, color: Color(0xFF1B5E20), size: 20),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _gpsLocationName ?? _currentFarm?.getName(_lang) ?? (_lang == 'en' ? 'My Farm' : 'मेरा खेत'),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '🌾 ${_currentFarm?.getCurrentCrop(_lang) ?? (_lang == "en" ? "Wheat" : "गेहूं")} (${_currentFarm?.landSizeAcres ?? 2.5} ${_lang == "en" ? "Ac" : "एकड़"}) • ${_gpsLocationName != null ? "GPS ${_gpsLat?.toStringAsFixed(2)}°N" : "${_currentFarm?.getVillage(_lang) ?? ""}"}',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1B5E20), size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Only One Icon on Right: Settings Gear
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.04),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.settings, size: 20, color: Colors.black87),
                              onPressed: widget.onOpenSettings,
                              tooltip: AppStrings.get('settings', _lang),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 1.5 Top Crop Advisory Navigation Button (Moved to top for easy 1-tap navigation)
                SliverToBoxAdapter(
                  child: _buildTopCropAdvisoryButton(),
                ),

                // In-App Update Banner (shows when newer APK/version is released)
                if (_availableUpdate != null && _availableUpdate!.hasUpdate && !_updateBannerDismissed)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.system_update_alt, color: Color(0xFF1B5E20), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${AppStrings.get('update_banner_title', _lang)}: v${_availableUpdate!.latestVersion}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    AppStrings.get('update_banner_sub', _lang),
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF1B5E20),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => UpdateService.showUpdateDialog(context, _availableUpdate!, lang: _lang),
                              child: Text(AppStrings.get('update_banner_btn', _lang), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => setState(() => _updateBannerDismissed = true),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Offline / Last Updated Notice Bar (Floating Glass Pill)
                if (_cachedTime != null)
                  SliverToBoxAdapter(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.amber.shade300, width: 1.0),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.amber.shade800,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.access_time, size: 14, color: Colors.amber.shade900),
                            const SizedBox(width: 5),
                            Text(
                              '${AppStrings.get('last_updated', _lang)}: ${_formatLastUpdated()}',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                if (_isLoading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFF1B5E20)),
                    ),
                  )
                else if (_weather != null) ...[
                  // 2. Large Current Conditions Hero Header (Voice banner below it removed per user request)
                  SliverToBoxAdapter(
                    child: _buildCurrentWeatherHero(_weather!.current),
                  ),

                  // 3. Risk Early Warnings & Mobile SMS Section
                  SliverToBoxAdapter(
                    child: _buildRiskWarningsCard(),
                  ),

                  // 4. Soil Health & Root Zone Tile
                  SliverToBoxAdapter(
                    child: _buildSoilHealthTile(_weather!.current),
                  ),

                  // 5. Sun Cycle Tile (Sunrise/Sunset)
                  if (_weather!.daily.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildSunCycleTile(_weather!.daily.first),
                    ),

                  // 6. Open-Meteo CC BY 4.0 Attribution Footer
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                      child: Column(
                        children: [
                          Text(
                            _weather!.attribution,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'KisanMausam v1.0 • Hindi-First Agri Weather App',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          const SizedBox(height: 84), // 84px clearance so bottom-right voice FAB never overlaps content
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopCropAdvisoryButton() {
    final isHi = _lang == 'hi';
    final liveTemp = _weather?.current.temperature.toStringAsFixed(1);
    final liveSoilRaw = _weather?.current.soilMoisture ?? 0.24;
    final liveSoilPct = (liveSoilRaw <= 1.0 ? liveSoilRaw * 100 : liveSoilRaw).round();
    final activeLoc = _gpsLocationName ?? _currentFarm?.getVillage(_lang) ?? (isHi ? 'उमरेड' : 'Umred');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _openCropRecommender,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.agriculture, color: Color(0xFF1B5E20), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              AppStrings.get('crop_recommender_title', _lang),
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B5E20),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              AppStrings.get('rabi_season', _lang),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.brown),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        liveTemp != null
                            ? (isHi
                                ? 'GPS ($activeLoc): $liveTemp°C • नमी $liveSoilPct% • गेहूं, चना, सरसों'
                                : 'GPS ($activeLoc): $liveTemp°C • Moisture $liveSoilPct% • Wheat, Chickpea')
                            : AppStrings.get('crop_recommender_subtitle', _lang),
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isHi ? 'फसल सुझाव' : 'Crops',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15),
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

  Widget _buildCurrentWeatherHero(CurrentWeather current) {
    final isDay = current.isDay;
    final condText = _getWeatherConditionText(current.weatherCode, _lang);
    final displayCond = (!isDay && current.weatherCode == 0)
        ? (_lang == 'hi' ? 'साफ रात' : 'Clear Night')
        : condText;
    final isRainy = current.weatherCode >= 51 && current.weatherCode <= 82;
    final isThunder = current.weatherCode >= 95;
    final isHot = current.temperature >= 38;

    final gradientColors = isHot
        ? const [Color(0xFF7A1F02), Color(0xFFA03006), Color(0xFFBF360C)]
        : (isThunder
            ? const [Color(0xFF281C3E), Color(0xFF39255C), Color(0xFF4A3470)]
            : (isRainy
                ? const [Color(0xFF0D324D), Color(0xFF1D536D), Color(0xFF176B87)]
                : (isDay
                    ? const [Color(0xFF134E2C), Color(0xFF1E6F3E), Color(0xFF2E8B57)]
                    : const [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0D1B2A)])));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.28),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.38),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${current.temperature.round()}',
                                style: const TextStyle(
                                  fontSize: 70,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 0.95,
                                  letterSpacing: -2.0,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black26,
                                      blurRadius: 10,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(top: 6, left: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                                ),
                                child: const Text(
                                  '°C',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            displayCond,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.thermostat, size: 14, color: Colors.white70),
                                const SizedBox(width: 4),
                                Text(
                                  '${AppStrings.get('feels_like', _lang)}: ${current.apparentTemperature.round()}°C',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    RealisticWeatherVisual(
                      weatherCode: current.weatherCode,
                      isDay: isDay,
                      size: 108,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Frosted Glass Metrics Pods Container
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildHeroStatPod(
                          Icons.air,
                          '${current.windSpeed.round()} km/h',
                          AppStrings.get('wind_speed', _lang),
                          const Color(0xFF81C784),
                        ),
                      ),
                      Container(width: 1, height: 38, color: Colors.white.withValues(alpha: 0.2)),
                      Expanded(
                        child: _buildHeroStatPod(
                          Icons.water_drop,
                          '${current.relativeHumidity.round()}%',
                          AppStrings.get('humidity', _lang),
                          const Color(0xFF4FC3F7),
                        ),
                      ),
                      Container(width: 1, height: 38, color: Colors.white.withValues(alpha: 0.2)),
                      Expanded(
                        child: _buildHeroStatPod(
                          Icons.wb_sunny_outlined,
                          current.uvIndex.toStringAsFixed(1),
                          AppStrings.get('uv_index', _lang),
                          const Color(0xFFFFD54F),
                        ),
                      ),
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

  Widget _buildHeroStatPod(IconData icon, String value, String label, Color accentColor) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.22),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: accentColor, size: 18),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildSoilHealthTile(CurrentWeather current) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF5D4037).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.grass, color: Color(0xFF5D4037), size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.get('soil_health', _lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4E342E)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDetailMetric(
                  Icons.thermostat,
                  '${current.soilTemperature.toStringAsFixed(1)}°C',
                  AppStrings.get('soil_temp', _lang),
                  const Color(0xFFBF360C),
                ),
              ),
              Container(width: 1, height: 42, color: Colors.grey.shade300),
              Expanded(
                child: _buildDetailMetric(
                  Icons.opacity,
                  '${(current.soilMoisture * 100).toStringAsFixed(0)}% (${current.soilMoisture.toStringAsFixed(2)} m³/m³)',
                  AppStrings.get('soil_moisture', _lang),
                  const Color(0xFF0288D1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

  Widget _buildSunCycleTile(DailyForecast today) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wb_sunny, color: Colors.orange, size: 22),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.get('sunrise', _lang), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    Text(_formatSunTime(today.sunrise), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          Container(width: 1, height: 32, color: Colors.grey.shade300),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.nightlight_round, color: Colors.deepOrange, size: 22),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.get('sunset', _lang), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    Text(_formatSunTime(today.sunset), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailMetric(IconData icon, String value, String label, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 4),
              Flexible(child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRiskWarningsCard() {
    final h1Risks = _riskData?.horizon1.risks ?? [];
    final h3Risks = _riskData?.horizon3.risks ?? [];
    final hasHighRisk = h1Risks.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasHighRisk ? Colors.red.shade400 : Colors.green.shade400,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasHighRisk
                      ? Colors.red.withValues(alpha: 0.12)
                      : const Color(0xFF1B5E20).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasHighRisk ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                  color: hasHighRisk ? Colors.red.shade700 : const Color(0xFF1B5E20),
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.get('risk_card_title', _lang),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: hasHighRisk ? Colors.red.shade900 : const Color(0xFF1B5E20),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasHighRisk ? Colors.red : Colors.green,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            hasHighRisk
                                ? (_lang == 'hi' ? 'सक्रिय चेतावनी' : 'Active Hazards')
                                : AppStrings.get('risk_farm_safe', _lang),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: hasHighRisk ? Colors.red.shade800 : Colors.green.shade800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    minimumSize: const Size(0, 38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _triggerSimulation('sos'),
                  icon: const Icon(Icons.sos_rounded, size: 17, color: Colors.white),
                  label: const Text('SOS', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    minimumSize: const Size(0, 38),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _showSimulationDialog,
                  icon: const Icon(Icons.bolt, size: 17, color: Color(0xFFFFD54F)),
                  label: Text(
                    AppStrings.get('risk_test_btn', _lang),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasHighRisk) ...[
            ...h1Risks.map((risk) => _buildDetectedRiskItem(risk)),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppStrings.get('risk_no_hazards', _lang),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (h3Risks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.date_range, size: 16, color: Color(0xFF1B5E20)),
                      const SizedBox(width: 6),
                      Text(
                        AppStrings.get('seasonal_title', _lang),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    () {
                      final activeLoc = _gpsLocationName ?? _currentFarm?.village ?? (_lang == 'hi' ? "आपके क्षेत्र" : "your area");
                      if (_lang == 'en') {
                        return 'In $activeLoc, 35% probability of below-normal rainfall over next 30 days based on multi-model forecasts.';
                      }
                      final rawStatement = h3Risks.first.accuracyStatementHi;
                      if (rawStatement != null && rawStatement.isNotEmpty) {
                        if (_gpsLocationName != null && rawStatement.contains('उमरेड')) {
                          return rawStatement.replaceAll('उमरेड (Umred)', activeLoc).replaceAll('उमरेड', activeLoc);
                        }
                        return rawStatement.replaceAll(' (Umred)', '');
                      }
                      return '$activeLoc में अगले 30 दिनों में सामान्य से कम वर्षा होने की संभावना 35% है।';
                    }(),
                    style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetectedRiskItem(DetectedRisk risk) {
    final isRed = risk.severity == 'red';
    final isHi = _lang == 'hi';
    final title = isHi ? risk.titleHi : (risk.titleEn.isNotEmpty ? risk.titleEn : risk.titleHi);
    final action = isHi ? risk.actionHi : (risk.actionEn.isNotEmpty ? rActionFallback(risk) : risk.actionHi);
    final badgeLabel = isHi ? (isRed ? 'गंभीर चेतावनी' : 'चेतावनी') : (isRed ? 'RED ALERT' : 'WARNING');
    final timePrefix = isHi ? 'समय' : 'Time';
    final timeValue = risk.expectedDate ?? (isHi ? 'अगले 24-48 घंटे' : 'Next 24-48 hours');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isRed ? Colors.red.shade300 : Colors.orange.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: (isRed ? Colors.red : Colors.orange).withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isRed ? Colors.red.shade700 : Colors.orange.shade800,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '${risk.probability.round()}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: isRed ? Colors.red.shade900 : Colors.orange.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$timePrefix: $timeValue (${risk.expectedValue})',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    action,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String rActionFallback(DetectedRisk risk) => risk.actionEn.isNotEmpty ? risk.actionEn : risk.actionHi;

  Future<void> _showSimulationDialog() async {
    final isHi = _lang == 'hi';
    var savedPhone = _userPhone ?? await StorageService.getUserPhone();
    if (savedPhone == null || savedPhone.isEmpty) {
      savedPhone = await AlertService.detectSimPhoneNumber();
      if (savedPhone != null && savedPhone.isNotEmpty) {
        await StorageService.saveUserPhone(savedPhone);
        if (mounted) setState(() => _userPhone = savedPhone);
      }
    }
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.notification_important, color: Color(0xFF1B5E20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isHi ? 'मौसम अलर्ट एवं SOS SMS' : 'Weather Alert & SOS SMS',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (savedPhone != null && savedPhone.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.phone_android, size: 16, color: Color(0xFF1B5E20)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isHi
                              ? 'लॉगिन मोबाइल नंबर: +91 $savedPhone'
                              : 'Login Mobile Number: +91 $savedPhone',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1B5E20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                isHi
                    ? 'चुनें कि कौन-सा अलर्ट या SOS भेजना है:'
                    : 'Select an alert or SOS to dispatch via SMS & Push:',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sos, color: Colors.red, size: 28),
                title: Text(
                  isHi ? 'SOS आपातकालीन अलर्ट' : 'SOS Emergency Alert',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
                subtitle: Text(isHi ? 'तत्काल आपातकालीन SMS व अलर्ट भेजें' : 'Immediate SOS SMS & alert dispatch'),
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerSimulation('sos');
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bolt, color: Colors.deepOrange),
                title: Text(isHi ? 'अचानक मौसम परिवर्तन' : 'Sudden Weather Change'),
                subtitle: Text(isHi ? 'चेतावनी SMS • 82% संभावना' : 'Weather Shift SMS • 82% Probability'),
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerSimulation('weather_change');
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.ac_unit, color: Colors.lightBlue),
                title: Text(isHi ? 'पाला व शीतलहर (1.2°C)' : 'Ground Frost (1.2°C)'),
                subtitle: Text(isHi ? 'गंभीर चेतावनी • 85% संभावना' : 'Red Alert • 85% Probability'),
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerSimulation('frost');
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.thunderstorm, color: Colors.blue),
                title: Text(isHi ? 'अत्यधिक भारी वर्षा (145 मिमी)' : 'Excessive Rain (145mm)'),
                subtitle: Text(isHi ? 'गंभीर चेतावनी • 90% संभावना' : 'Red Alert • 90% Probability'),
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerSimulation('heavy_rain');
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.whatshot, color: Colors.orange),
                title: Text(isHi ? 'भीषण लू (44.5°C)' : 'Severe Heat Wave (44.5°C)'),
                subtitle: Text(isHi ? 'चेतावनी • 88% संभावना' : 'Orange Alert • 88% Probability'),
                onTap: () {
                  Navigator.pop(ctx);
                  _triggerSimulation('heat_wave');
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isHi ? 'बंद करें' : 'Close'),
          ),
        ],
      ),
    );
  }

  void _triggerSimulation(String scenario) async {
    final isHi = _lang == 'hi';
    var cleanPhone = '';
    final stored = _userPhone ?? await StorageService.getUserPhone() ?? await AlertService.detectSimPhoneNumber();
    if (stored != null && stored.length >= 10) {
      final digits = stored.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 10) {
        cleanPhone = digits.substring(digits.length - 10);
        await StorageService.saveUserPhone(cleanPhone);
        if (mounted) setState(() => _userPhone = cleanPhone);
      }
    }

    if (!mounted) return;

    if (cleanPhone.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isHi
                ? '+91 $cleanPhone पर SMS एवं अलर्ट भेजा जा रहा है...'
                : 'Sending SMS & hazard alert to +91 $cleanPhone...',
          ),
        ),
      );
    }

    final loc = _gpsLocationName ?? _currentFarm?.village ?? (isHi ? 'आपके क्षेत्र' : 'your location');
    final res = await _apiService.simulateAlert(
      _currentFarm?.id ?? 1,
      scenario,
      phoneNumber: cleanPhone.isNotEmpty ? cleanPhone : null,
      locationName: loc,
    );
    if (!mounted) return;
    final titlesHi = {
      'sos': 'SOS आपातकालीन मौसम अलर्ट',
      'weather_change': 'अचानक मौसम परिवर्तन अलर्ट',
      'frost': 'पाला व शीतलहर चेतावनी',
      'heavy_rain': 'अत्यधिक भारी वर्षा चेतावनी',
      'heat_wave': 'भीषण लू चेतावनी',
    };
    final titlesEn = {
      'sos': 'SOS Emergency Weather Alert',
      'weather_change': 'Sudden Weather Change Alert',
      'frost': 'Ground Frost Warning',
      'heavy_rain': 'Excessive Rain Warning',
      'heat_wave': 'Severe Heat Wave Warning',
    };
    final actionsHi = {
      'sos': 'आपातकालीन कृषि सुरक्षा प्रोटोकॉल सक्रिय किया गया है। किसान हेल्पलाइन: 1800-180-1551।',
      'weather_change': 'कटाई की गई फसल को तुरंत सुरक्षित स्थान पर ढकें।',
      'frost': 'शाम के समय खेत में हल्की सिंचाई करें और मेड़ों पर धुआं करें।',
      'heavy_rain': 'खेत में जल निकासी नालियां तुरंत साफ करें और छिड़काव रोकें।',
      'heat_wave': 'शाम के समय सिंचाई करें और पुआल से मल्चिंग करें।',
    };

    AlertService.showHazardAlert(
      context,
      titleHi: titlesHi[scenario] ?? 'मौसम चेतावनी',
      titleEn: titlesEn[scenario] ?? 'Weather Alert',
      bodyHi: '$loc के लिए ${titlesHi[scenario] ?? "चेतावनी"} जारी की गई है और आपके मोबाइल पर SMS भेजा गया है।',
      bodyEn: '${titlesEn[scenario] ?? "Alert"} triggered for $loc and SMS dispatched to your mobile.',
      severity: (scenario == 'heat_wave' || scenario == 'weather_change') ? 'orange' : 'red',
      actionHi: actionsHi[scenario] ?? 'सावधानी बरतें।',
      probability: scenario == 'sos' ? 100.0 : 88.0,
      lang: _lang,
      lat: _gpsLat ?? _currentFarm?.latitude,
      lon: _gpsLon ?? _currentFarm?.longitude,
      locationName: loc,
    );

    if (res != null) {
      final logsCount = res['dispatched_logs_count'] ?? 0;
      final smsSent = res['sms_sent'] == true || logsCount > 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1B5E20),
          content: Text(
            smsSent
                ? (isHi
                    ? '✅ +91 $cleanPhone पर SMS एवं अलर्ट सफलतापूर्वक भेजा गया!'
                    : '✅ SMS & Alert dispatched to +91 $cleanPhone!')
                : (isHi
                    ? '✅ अलर्ट सक्रिय (SMS अनुमति स्वीकार करने पर तुरंत SMS भेजा जाएगा)'
                    : '✅ Alert active (SMS will dispatch once SMS permission is allowed)'),
          ),
          duration: const Duration(seconds: 4),
        ),
      );

      _apiService.getFarmRisks(_currentFarm?.id ?? 1).then((r) {
        if (mounted && r != null) setState(() => _riskData = r);
      });
    }
  }

  void _showFarmSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.get('farm_switcher', _lang),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.my_location, color: Color(0xFF1B5E20), size: 20),
                ),
                title: Text(
                  _lang == 'hi' ? 'वर्तमान GPS स्थान का उपयोग करें' : 'Use Current GPS Location',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Text(
                  _lang == 'hi' ? 'सटीक खेत मौसम हेतु स्वचालित पहचान' : 'Auto-detect exact farm location',
                  style: const TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _fetchCurrentLocationGPS();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.search, color: Colors.blue, size: 20),
                ),
                title: Text(
                  _lang == 'hi' ? 'नया शहर या गाँव खोजें' : 'Search City or Village',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Text(
                  _lang == 'hi' ? 'नाम लिखकर मौसम देखें' : 'Type name to check weather',
                  style: const TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showLocationSearchDialog();
                },
              ),
              const Divider(height: 20),
              ..._farms.map((farm) {
                final isSelected = farm.id == _currentFarm?.id;
                return ListTile(
                  leading: Icon(
                    Icons.agriculture,
                    color: isSelected ? const Color(0xFF1B5E20) : Colors.grey,
                  ),
                  title: Text(farm.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text('${farm.village}, ${farm.district} • ${farm.currentCrop}'),
                  trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF1B5E20)) : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await StorageService.setActiveFarmId(farm.id);
                    final farmLoc = '${farm.village}, ${farm.district}';
                    setState(() {
                      _currentFarm = farm;
                      _gpsLat = farm.latitude;
                      _gpsLon = farm.longitude;
                      _gpsLocationName = farmLoc;
                      _isLoading = true;
                    });
                    await StorageService.saveLastLocation(farm.latitude, farm.longitude, farmLoc);
                    await _fetchWeather(farm.latitude, farm.longitude, locationName: farmLoc);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
