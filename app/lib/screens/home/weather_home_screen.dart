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
import '../../widgets/temp_range_bar.dart';
import '../../widgets/oni_gauge_meter.dart';
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

  List<FarmProfile> _farms = [];
  FarmProfile? _currentFarm;
  WeatherData? _weather;
  FarmRiskData? _riskData;
  EnsoSummary? _ensoData;
  bool _isLoading = true;
  bool _isLocating = false; // GPS location fetch in progress
  String _lang = 'hi';
  DateTime? _cachedTime;
  // Custom GPS location (overrides farm lat/lon)
  double? _gpsLat;
  double? _gpsLon;
  String? _gpsLocationName;

  @override
  void initState() {
    super.initState();
    _loadData();
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

    setState(() {
      _lang = lang;
      _farms = farms;
      _currentFarm = current;
    });

    await _fetchWeather(initialLat, initialLon, locationName: initialName);

    // Auto-fetch user's current GPS location immediately on app open (with IP fallback)
    _autoFetchGPSLocation();
  }

  /// Automatically fetch live GPS location on app start without blocking initial view
  Future<void> _autoFetchGPSLocation() async {
    try {
      final loc = await LocationService.getCurrentLocation(fallbackToIp: true);
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

      // Fetch risks & ENSO in parallel with active location coordinates & name
      _apiService.getFarmRisks(
        _currentFarm?.id ?? 1,
        lat: lat,
        lon: lon,
        locationName: locName,
      ).then((r) {
        if (mounted && r != null) {
          setState(() => _riskData = r);
          _checkAndShowAlertPopup(r);
        }
      });
      _apiService.getEnsoStatus().then((e) {
        if (mounted && e != null) setState(() => _ensoData = e);
      });

      if (mounted) {
        setState(() {
          _weather = data;
          _cachedTime = cachedTs ?? DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Called when risk data loads — pops up an alert dialog for high-severity risks.
  void _checkAndShowAlertPopup(FarmRiskData risk) {
    final redRisks = risk.horizon1.risks.where((r) => r.severity == 'red').toList();
    final orangeRisks = risk.horizon1.risks.where((r) => r.severity == 'orange').toList();

    if (redRisks.isNotEmpty) {
      final r = redRisks.first;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          AlertService.showHazardAlert(
            context,
            titleHi: r.titleHi,
            titleEn: r.titleEn,
            bodyHi: '${_currentFarm?.village ?? "आपके क्षेत्र"} में ${r.expectedValue} की संभावना है। तुरंत सावधानी बरतें।',
            bodyEn: 'Risk detected at ${_currentFarm?.village ?? "your location"}: ${r.expectedValue}.',
            severity: 'red',
            actionHi: r.actionHi,
            probability: r.probability,
            lang: _lang,
          );
        }
      });
    } else if (orangeRisks.isNotEmpty) {
      final r = orangeRisks.first;
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          AlertService.showHazardAlert(
            context,
            titleHi: r.titleHi,
            titleEn: r.titleEn,
            bodyHi: '${_currentFarm?.village ?? "आपके क्षेत्र"} में ${r.expectedValue} का जोखिम है।',
            bodyEn: 'Warning at ${_currentFarm?.village ?? "your location"}: ${r.expectedValue}.',
            severity: 'orange',
            actionHi: r.actionHi,
            probability: r.probability,
            lang: _lang,
          );
        }
      });
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

    final loc = await LocationService.getCurrentLocation(fallbackToIp: true);
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
                              final r = await LocationService.searchLocation(controller.text.trim());
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
                    final r = await LocationService.searchLocation(q.trim());
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
    if (code == 0) return lang == 'hi' ? 'आसमान साफ (धूप)' : 'Clear Sky';
    if (code >= 1 && code <= 3) return lang == 'hi' ? 'हल्के बादल' : 'Partly Cloudy';
    if (code == 45 || code == 48) return lang == 'hi' ? 'कोहरा / धुंध' : 'Foggy';
    if (code >= 51 && code <= 55) return lang == 'hi' ? 'हल्की बूंदाबांदी' : 'Drizzle';
    if (code >= 61 && code <= 65) return lang == 'hi' ? 'बारिश' : 'Rain';
    if (code >= 80 && code <= 82) return lang == 'hi' ? 'तेज बौछारें' : 'Rain Showers';
    if (code == 95) return lang == 'hi' ? 'गरज-चमक के साथ बारिश' : 'Thunderstorm';
    if (code == 96 || code == 99) return lang == 'hi' ? 'ओलावृष्टि चेतावनी' : 'Thunderstorm with Hail';
    return lang == 'hi' ? 'सामान्य मौसम' : 'Fair Weather';
  }

  IconData _getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code >= 1 && code <= 3) return Icons.cloud_queue;
    if (code == 45 || code == 48) return Icons.cloud;
    if (code >= 51 && code <= 65) return Icons.water_drop;
    if (code >= 80 && code <= 82) return Icons.umbrella;
    if (code >= 95) return Icons.flash_on;
    return Icons.wb_cloudy;
  }

  String _formatLastUpdated() {
    if (_cachedTime == null) return '';
    final diff = DateTime.now().difference(_cachedTime!);
    if (diff.inMinutes < 1) return _lang == 'hi' ? 'अभी-अभी' : 'Just now';
    if (diff.inMinutes < 60) return _lang == 'hi' ? '${diff.inMinutes} मिनट पहले' : '${diff.inMinutes}m ago';
    return _lang == 'hi' ? '${diff.inHours} घंटे पहले' : '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: ProminentMicButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => KrishiSahayakScreen(
                farm: _currentFarm,
                locationName: _gpsLocationName ?? _currentFarm?.village,
                latitude: _gpsLat ?? _weather?.latitude ?? _currentFarm?.latitude,
                longitude: _gpsLon ?? _weather?.longitude ?? _currentFarm?.longitude,
                weather: _weather,
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: GlassCard(
                      borderRadius: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        children: [
                          // Farm Switcher Dropdown
                          Expanded(
                            child: InkWell(
                              onTap: _showFarmSelector,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.location_on, color: Color(0xFF1B5E20), size: 20),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _gpsLocationName ?? _currentFarm?.name ?? 'मेरा खेत',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            _gpsLocationName != null
                                                ? 'GPS • ${_gpsLat?.toStringAsFixed(2)}°N, ${_gpsLon?.toStringAsFixed(2)}°E'
                                                : '${_currentFarm?.village ?? ""}, ${_currentFarm?.district ?? ""}',
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
                          const SizedBox(width: 4),
                          // GPS Current Location button
                          _isLocating
                              ? const SizedBox(
                                  width: 38,
                                  height: 38,
                                  child: Padding(
                                    padding: EdgeInsets.all(8),
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF1B5E20)),
                                  ),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: _gpsLat != null
                                        ? const Color(0xFF1B5E20).withValues(alpha: 0.15)
                                        : Colors.black.withValues(alpha: 0.04),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: Icon(
                                      Icons.my_location,
                                      size: 20,
                                      color: _gpsLat != null ? const Color(0xFF1B5E20) : Colors.black87,
                                    ),
                                    tooltip: _lang == 'hi' ? 'मेरा स्थान' : 'My Location',
                                    onPressed: _fetchCurrentLocationGPS,
                                  ),
                                ),
                          const SizedBox(width: 4),
                          // Search Location button
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.04),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.search, size: 20, color: Colors.black87),
                              tooltip: _lang == 'hi' ? 'स्थान खोजें' : 'Search Location',
                              onPressed: _showLocationSearchDialog,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Settings
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
                // 2. WeatherMaster-inspired Large Current Conditions Hero Header
                SliverToBoxAdapter(
                  child: _buildCurrentWeatherHero(_weather!.current),
                ),

                // 2.2 Risk Early Warnings Hero Section
                SliverToBoxAdapter(
                  child: _buildRiskWarningsCard(),
                ),

                // 2.4 Monthly ENSO Status Card
                SliverToBoxAdapter(
                  child: _buildEnsoStatusCard(),
                ),

                // 2.5 Crop Recommender Entry Card
                SliverToBoxAdapter(
                  child: _buildCropRecommenderEntryCard(),
                ),

                // 3. Hourly 48-Hour Strip
                SliverToBoxAdapter(
                  child: _buildHourlyForecastStrip(_weather!.hourly),
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

                // 6. 10-Day Daily Forecast Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month, color: Color(0xFF1B5E20), size: 24),
                        const SizedBox(width: 8),
                        Text(
                          AppStrings.get('daily_forecast', _lang),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _weather!.daily[index];
                      return _buildDailyForecastCard(item);
                    },
                    childCount: _weather!.daily.length,
                  ),
                ),

                // 7. Open-Meteo CC BY 4.0 Attribution Footer
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
                        const SizedBox(height: 48), // Padding for mic FAB
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

  Widget _buildCurrentWeatherHero(CurrentWeather current) {
    final isDay = current.isDay;
    final condText = _getWeatherConditionText(current.weatherCode, _lang);
    final displayCond = (!isDay && current.weatherCode == 0)
        ? (_lang == 'hi' ? 'साफ रात (Clear Night)' : 'Clear Night')
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
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

  Widget _buildHourlyForecastStrip(List<HourlyForecast> hourly) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.schedule, color: Color(0xFF1B5E20), size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.get('hourly_forecast', _lang),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 152,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: hourly.length,
            itemBuilder: (context, index) {
              final item = hourly[index];
              final isNow = index == 0;
              final hourStr = item.time.length >= 16 ? item.time.substring(11, 16) : item.time;

              return Container(
                width: 82,
                margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: isNow
                      ? const LinearGradient(
                          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.92),
                            Colors.white.withValues(alpha: 0.75),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isNow ? Colors.white.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.8),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isNow
                          ? const Color(0xFF1B5E20).withValues(alpha: 0.35)
                          : Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      isNow ? AppStrings.get('now', _lang) : hourStr,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isNow ? Colors.white : Colors.black87,
                      ),
                    ),
                    Icon(
                      _getWeatherIcon(item.weatherCode),
                      size: 26,
                      color: isNow ? const Color(0xFFFFF176) : const Color(0xFF1B5E20),
                    ),
                    Text(
                      '${item.temperature.round()}°',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: isNow ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (item.precipitationProbability > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isNow
                              ? Colors.white.withValues(alpha: 0.25)
                              : Colors.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.water_drop, size: 9, color: isNow ? Colors.lightBlueAccent : Colors.blue),
                            const SizedBox(width: 2),
                            Text(
                              '${item.precipitationProbability}%',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isNow ? Colors.white : Colors.blue.shade800,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: 14),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSoilHealthTile(CurrentWeather current) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      tintColor: const Color(0xFFEFEBE9),
      border: Border.all(color: const Color(0xFFBCAAA4), width: 1.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF5D4037).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.grass, color: Color(0xFF5D4037), size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.get('soil_health', _lang),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4E342E)),
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
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      tintColor: const Color(0xFFFFF8E1),
      border: Border.all(color: Colors.amber.shade200, width: 1.0),
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
                    color: Colors.orange.withValues(alpha: 0.15),
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
          Container(width: 1, height: 32, color: Colors.orange.shade200),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withValues(alpha: 0.15),
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

  String _formatDayLabel(String rawDate) {
    try {
      final dt = DateTime.parse(rawDate);
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return _lang == 'hi' ? 'आज' : 'Today';
      }
      final monthsHi = ['', 'जन', 'फ़र', 'मार्च', 'अप्रै', 'मई', 'जून', 'जुलाई', 'अग', 'सित', 'अक्तू', 'नव', 'दिस'];
      final monthsEn = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final m = _lang == 'hi' ? monthsHi[dt.month] : monthsEn[dt.month];
      return '${dt.day} $m';
    } catch (_) {
      return rawDate.length >= 5 ? rawDate.substring(5) : rawDate;
    }
  }

  Widget _buildDailyForecastCard(DailyForecast day) {
    final icon = _getWeatherIcon(day.weatherCode);

    // Compute weekly min & max for spectrum normalization
    double weekMin = 50;
    double weekMax = -20;
    if (_weather != null) {
      for (final d in _weather!.daily) {
        if (d.tempMin < weekMin) weekMin = d.tempMin;
        if (d.tempMax > weekMax) weekMax = d.tempMax;
      }
    }

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Date
          SizedBox(
            width: 72,
            child: Text(
              _formatDayLabel(day.date),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          // Weather Icon
          Icon(icon, size: 24, color: const Color(0xFF1B5E20)),
          const SizedBox(width: 6),
          // Rain chance pill
          SizedBox(
            width: 48,
            child: day.precipitationProbabilityMax > 0
                ? Row(
                    children: [
                      const Icon(Icons.water_drop, size: 11, color: Colors.blue),
                      const SizedBox(width: 1),
                      Text(
                        '${day.precipitationProbabilityMax}%',
                        style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 6),
          // Min Temp
          Text(
            '${day.tempMin.round()}°',
            style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          // Temperature Spectrum Range Bar
          Expanded(
            child: TempRangeBar(
              minTemp: day.tempMin,
              maxTemp: day.tempMax,
              overallMin: (weekMin - 1),
              overallMax: (weekMax + 1),
            ),
          ),
          const SizedBox(width: 8),
          // Max Temp
          Text(
            '${day.tempMax.round()}°',
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskWarningsCard() {
    final h1Risks = _riskData?.horizon1.risks ?? [];
    final h3Risks = _riskData?.horizon3.risks ?? [];
    final hasHighRisk = h1Risks.isNotEmpty;

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      tintColor: hasHighRisk ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
      border: Border.all(
        color: hasHighRisk ? Colors.red.shade300 : Colors.green.shade300,
        width: 1.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: hasHighRisk
                      ? Colors.red.withValues(alpha: 0.15)
                      : Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasHighRisk ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                  color: hasHighRisk ? Colors.red.shade700 : Colors.green.shade800,
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lang == 'hi' ? 'मौसम जोखिम व पूर्व चेतावनी (1-3 दिन)' : 'Weather Hazards (Days 1-3)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: hasHighRisk ? Colors.red.shade900 : Colors.green.shade900,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasHighRisk ? Colors.red : Colors.green,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          hasHighRisk
                              ? (_lang == 'hi' ? 'सक्रिय चेतावनी (Active Alert)' : 'Active Hazards')
                              : (_lang == 'hi' ? 'खेत सुरक्षित • IMD रडार' : 'Crops Protected • Radar Active'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hasHighRisk ? Colors.red.shade800 : Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(60, 34),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: _showSimulationDialog,
                icon: const Icon(Icons.bolt, size: 16, color: Color(0xFFFFD54F)),
                label: Text(_lang == 'hi' ? 'टेस्ट अलर्ट' : 'Test Alert', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasHighRisk) ...[
            ...h1Risks.map((risk) => _buildDetectedRiskItem(risk)),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _lang == 'hi'
                          ? 'अगले 1 से 3 दिनों में कोई गंभीर मौसम खतरा नहीं है। फसल सुरक्षित है।'
                          : 'No imminent severe weather risks for next 1-3 days.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.green.shade900),
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
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.date_range, size: 16, color: Color(0xFF1B5E20)),
                      const SizedBox(width: 6),
                      Text(
                        _lang == 'hi' ? '30-दिवसीय मौसमी रुझान (EC46 / SEAS5)' : '30-Day Seasonal Outlook',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    () {
                      final rawStatement = h3Risks.first.accuracyStatementHi;
                      final activeLoc = _gpsLocationName ?? _currentFarm?.village ?? "आपके क्षेत्र";
                      if (rawStatement != null && rawStatement.isNotEmpty) {
                        if (_gpsLocationName != null && rawStatement.contains('उमरेड')) {
                          return rawStatement.replaceAll('उमरेड (Umred)', activeLoc).replaceAll('उमरेड', activeLoc);
                        }
                        return rawStatement;
                      }
                      return '$activeLoc में अगले 30 दिनों में सामान्य से कम वर्षा होने की संभावना 35% है।';
                    }(),
                    style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.3),
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
                  isRed ? 'RED ALERT' : 'WARNING',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  risk.titleHi,
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
            'समय: ${risk.expectedDate ?? "अगले 24-48 घंटे"} (${risk.expectedValue})',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    risk.actionHi,
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

  Widget _buildEnsoStatusCard() {
    final enso = _ensoData;
    final phaseText = enso?.phaseHi ?? 'तटस्थ (Neutral)';
    final oniVal = enso?.oniValue ?? -0.2;

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      tintColor: const Color(0xFFE1F5FE),
      border: Border.all(color: Colors.blue.shade200, width: 1.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF0277BD).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.public, color: Color(0xFF0277BD), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lang == 'hi' ? 'वैश्विक ईएनएसओ (El Niño / La Niña) स्थिति' : 'Global ENSO Status',
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Color(0xFF01579B)),
                    ),
                    Text(
                      'Oceanic Nino Index (ONI)',
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade800),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0288D1), Color(0xFF01579B)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0288D1).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  phaseText,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Interactive ONI Gauge Meter
          OniGaugeMeter(oniValue: oniVal),
          const SizedBox(height: 12),
          Text(
            enso?.explanationHi ??
                'एल नीनो व ला नीना प्रशांत महासागर का समुद्री तापमान चक्र है। वर्तमान में तटस्थ (Neutral) स्थिति है। यह एक वैश्विक सूचकांक है; अपने स्थानीय खेत के लिए 30-दिवसीय वर्षा पूर्वानुमान देखें।',
            style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'ONI Index: ${oniVal >= 0 ? "+" : ""}$oniVal°C',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.blue.shade900),
                ),
              ),
              Text(
                'स्रोत: NOAA CPC / IMD',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCropRecommenderEntryCard() {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      borderRadius: 24,
      padding: const EdgeInsets.all(18),
      tintColor: const Color(0xFFF1F8E9),
      border: Border.all(color: const Color(0xFF81C784), width: 1.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.psychology_alt, color: Color(0xFF1B5E20), size: 24),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'फसल चयन व सिफारिशें (Crop Advisory)',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B5E20),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: const Text(
                  '🌾 रबी सीजन',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.brown),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'खेत की मिट्टी, सिंचाई, वर्तमान मौसम व 30-दिवसीय जलवायु रुझान के आधार पर शीर्ष 5 अनुशंसित फसलें देखें।',
            style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.3),
          ),
          const SizedBox(height: 10),
          // Suggested crop teaser badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildCropTeaserChip('🌾 गेहूं (Wheat)'),
              _buildCropTeaserChip('🌱 चना (Chickpea)'),
              _buildCropTeaserChip('🟡 सरसों (Mustard)'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 3,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CropRecommenderScreen(
                      farmId: _currentFarm?.id ?? 1,
                      farmName: _currentFarm?.name ?? 'बड़ा खेत 1',
                      village: _currentFarm?.village ?? 'उमरेड (Umred)',
                      farm: _currentFarm,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('सर्वोत्तम फसलें देखें (View Recommendations)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCropTeaserChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC8E6C9)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
      ),
    );
  }

  void _showSimulationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.notification_important, color: Color(0xFF1B5E20)),
            SizedBox(width: 8),
            Text('अलर्ट टेस्ट सिमुलेशन', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'एक मौसमी आपदा चुनें जिसे सिम्युलेट कर Push, SMS और Email चैनल पर टेस्ट करना है:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.ac_unit, color: Colors.lightBlue),
              title: const Text('पाला व शीतलहर (Ground Frost 1.2°C)'),
              subtitle: const Text('Red Alert • 85% संभावना'),
              onTap: () {
                Navigator.pop(ctx);
                _triggerSimulation('frost');
              },
            ),
            ListTile(
              leading: const Icon(Icons.thunderstorm, color: Colors.blue),
              title: const Text('अत्यधिक भारी वर्षा (Heavy Rain 145mm)'),
              subtitle: const Text('Red Alert • 90% संभावना'),
              onTap: () {
                Navigator.pop(ctx);
                _triggerSimulation('heavy_rain');
              },
            ),
            ListTile(
              leading: const Icon(Icons.whatshot, color: Colors.orange),
              title: const Text('भीषण लू (Heat Wave 44.5°C)'),
              subtitle: const Text('Orange Alert • 88% संभावना'),
              onTap: () {
                Navigator.pop(ctx);
                _triggerSimulation('heat_wave');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('रद्द करें'),
          ),
        ],
      ),
    );
  }

  void _triggerSimulation(String scenario) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('अलर्ट सिमुलेशन भेजा जा रहा है... (SMS, Push, Email)')),
    );

    final res = await _apiService.simulateAlert(_currentFarm?.id ?? 1, scenario);
    if (!mounted) return;

    if (res != null) {
      final logsCount = res['dispatched_logs_count'] ?? 0;
      final scenarioName = res['scenario'] ?? scenario;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1B5E20),
          content: Text(
            logsCount > 0
                ? '✅ $scenarioName चेतावनी सफलतापूर्वक भेजी गई! ($logsCount चैनल डिलीवर)'
                : 'ℹ️ अलर्ट डुप्लिकेशन रोक दिया गया (पिछले 6 घंटे में पहले ही भेजा गया था)',
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
