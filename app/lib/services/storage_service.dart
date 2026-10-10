import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/farm_profile.dart';
import '../models/weather_models.dart';

class StorageService {
  static const String _keyLanguage = 'selected_language';
  static const String _keyHighContrast = 'high_contrast_mode';
  static const String _keyOnboardingDone = 'onboarding_done';
  static const String _keyFarms = 'saved_farms';
  static const String _keyActiveFarmId = 'active_farm_id';
  static const String _keyWeatherCache = 'weather_cache_';
  static const String _keyWeatherTimestamp = 'weather_ts_';

  static Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLanguage) ?? 'hi';
  }

  static Future<void> setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, lang);
  }

  static Future<bool> isHighContrast() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHighContrast) ?? false;
  }

  static Future<void> setHighContrast(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHighContrast, value);
  }

  static Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOnboardingDone) ?? false;
  }

  static Future<void> setOnboardingComplete(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnboardingDone, value);
  }

  static Future<List<FarmProfile>> getFarms() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFarms);
    if (raw == null) {
      // Return default sample farm for instant rich UI
      return [
        FarmProfile(
          id: 1,
          name: 'बड़ा खेत',
          latitude: 21.1458,
          longitude: 79.0882,
          village: 'उमरेड',
          district: 'नागपुर',
          state: 'महाराष्ट्र',
          terrain: 'plain',
          soilType: 'black',
          irrigationType: 'tube-well',
          landSizeAcres: 4.5,
          currentCrop: 'सोयाबीन',
          cropStage: 'flowering',
          sowingDate: '2026-07-05',
        )
      ];
    }
    try {
      final list = jsonDecode(raw) as List;
      return list.map((item) => FarmProfile.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveFarms(List<FarmProfile> farms) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(farms.map((f) => f.toJson()).toList());
    await prefs.setString(_keyFarms, raw);
  }

  static Future<int> getActiveFarmId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyActiveFarmId) ?? 1;
  }

  static Future<void> setActiveFarmId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyActiveFarmId, id);
  }

  static Future<void> cacheWeather(String key, WeatherData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyWeatherCache$key', jsonEncode(data.toJson()));
    await prefs.setInt('$_keyWeatherTimestamp$key', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<WeatherData?> getCachedWeather(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyWeatherCache$key');
    if (raw == null) return null;
    try {
      return WeatherData.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> getWeatherCachedTime(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('$_keyWeatherTimestamp$key');
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts);
  }

  // ── User account helpers ──────────────────────────────────────────────────
  static const String _keyUserEmail = 'user_email';
  static const String _keyUserName = 'user_name';
  static const String _keyUserPhone = 'user_phone';
  static const String _keyIsLoggedIn = 'is_logged_in';

  static Future<void> saveUserEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserEmail, email);
    await prefs.setBool(_keyIsLoggedIn, true);
  }

  static Future<void> saveUserPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserPhone, phone.trim());
    await prefs.setBool(_keyIsLoggedIn, true);
  }

  static Future<void> saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserName, name);
  }

  static Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserEmail);
  }

  static Future<String?> getUserPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserPhone);
  }

  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserName);
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserPhone);
  }

  /// Alias for setLanguage (used by login screen language toggle)
  static Future<void> saveLanguage(String lang) => setLanguage(lang);

  static const String _keyGeminiApiKey = 'gemini_api_key';

  static Future<String?> getGeminiApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyGeminiApiKey);
  }

  static Future<void> saveGeminiApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key.trim().isEmpty) {
      await prefs.remove(_keyGeminiApiKey);
    } else {
      await prefs.setString(_keyGeminiApiKey, key.trim());
    }
  }

  // ── Last known GPS/IP Location persistence ─────────────────────────────
  static const String _keyLastLat = 'last_known_lat';
  static const String _keyLastLon = 'last_known_lon';
  static const String _keyLastLocName = 'last_known_loc_name';

  static Future<void> saveLastLocation(double lat, double lon, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLastLat, lat);
    await prefs.setDouble(_keyLastLon, lon);
    await prefs.setString(_keyLastLocName, name);
  }

  static Future<Map<String, dynamic>?> getLastLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_keyLastLat);
    final lon = prefs.getDouble(_keyLastLon);
    final name = prefs.getString(_keyLastLocName);
    if (lat != null && lon != null) {
      return {'latitude': lat, 'longitude': lon, 'displayName': name ?? ''};
    }
    return null;
  }

  // ── Custom Cloud Backend URL (e.g. AWS EC2 IP) ──────────────────────────
  static const String _keyBackendUrl = 'custom_backend_url';

  static Future<void> saveCustomBackendUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url.trim().isEmpty) {
      await prefs.remove(_keyBackendUrl);
    } else {
      await prefs.setString(_keyBackendUrl, url.trim());
    }
  }

  static Future<String?> getCustomBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBackendUrl);
  }
}
