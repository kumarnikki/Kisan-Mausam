import 'package:geolocator/geolocator.dart';
import 'package:dio/dio.dart';

class LocationResult {
  final double latitude;
  final double longitude;
  final String displayName;

  LocationResult({
    required this.latitude,
    required this.longitude,
    required this.displayName,
  });
}

class LocationService {
  static final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8)));

  /// Request permission and return current GPS location (with seamless IP fallback).
  static Future<LocationResult?> getCurrentLocation({bool fallbackToIp = true}) async {
    Position? pos;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (serviceEnabled &&
          (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always)) {
        // Fast path 1: Get cached last known location instantly (<50ms)
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {}

        // Path 2: Fetch fresh position with reasonable timeout
        try {
          final freshPos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
          pos = freshPos;
        } catch (_) {
          // If medium accuracy timed out and no last known position, try low accuracy
          if (pos == null) {
            try {
              pos = await Geolocator.getCurrentPosition(
                locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.low,
                  timeLimit: Duration(seconds: 5),
                ),
              );
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // If GPS returned a valid coordinate
    if (pos != null) {
      final name = await reverseGeocode(pos.latitude, pos.longitude);
      return LocationResult(
        latitude: pos.latitude,
        longitude: pos.longitude,
        displayName: name,
      );
    }

    // Fallback: If GPS is disabled, indoor timeout, or permission denied, use IP location
    if (fallbackToIp) {
      return await getIpLocation();
    }

    return null;
  }

  /// IP-based geolocation fallback (requires no GPS hardware/satellites)
  static Future<LocationResult?> getIpLocation() async {
    // 1. Try ipwho.is
    try {
      final r = await _dio.get(
        'https://ipwho.is/',
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      if (r.statusCode == 200 && r.data != null && r.data['success'] == true) {
        final lat = (r.data['latitude'] as num?)?.toDouble();
        final lon = (r.data['longitude'] as num?)?.toDouble();
        final city = (r.data['city'] as String?) ?? '';
        final region = (r.data['region'] as String?) ?? '';

        if (lat != null && lon != null) {
          final localizedName = await reverseGeocode(lat, lon);
          final finalName = localizedName.contains('°') && city.isNotEmpty
              ? (region.isNotEmpty ? '$city, $region' : city)
              : localizedName;
          return LocationResult(
            latitude: lat,
            longitude: lon,
            displayName: finalName,
          );
        }
      }
    } catch (_) {}

    // 2. Try ip-api.com
    try {
      final r = await _dio.get(
        'http://ip-api.com/json',
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      if (r.statusCode == 200 && r.data != null && r.data['status'] == 'success') {
        final lat = (r.data['lat'] as num?)?.toDouble();
        final lon = (r.data['lon'] as num?)?.toDouble();
        final city = (r.data['city'] as String?) ?? '';
        final region = (r.data['regionName'] as String?) ?? '';

        if (lat != null && lon != null) {
          final localizedName = await reverseGeocode(lat, lon);
          final finalName = localizedName.contains('°') && city.isNotEmpty
              ? (region.isNotEmpty ? '$city, $region' : city)
              : localizedName;
          return LocationResult(
            latitude: lat,
            longitude: lon,
            displayName: finalName,
          );
        }
      }
    } catch (_) {}

    return null;
  }

  /// Reverse geocode lat/lon → Hindi/English place name using BigDataCloud + Nominatim
  static Future<String> reverseGeocode(double lat, double lon) async {
    // 1. BigDataCloud Client API (fast, localized Hindi, no strict rate-limiting)
    try {
      final r = await _dio.get(
        'https://api.bigdatacloud.net/data/reverse-geocode-client',
        queryParameters: {
          'latitude': lat,
          'longitude': lon,
          'localityLanguage': 'hi',
        },
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );
      if (r.statusCode == 200 && r.data != null) {
        final locality = (r.data['locality'] as String?) ?? '';
        final city = (r.data['city'] as String?) ?? '';
        final state = (r.data['principalSubdivision'] as String?) ?? '';

        final mainPlace = locality.isNotEmpty ? locality : city;
        if (mainPlace.isNotEmpty) {
          return state.isNotEmpty && state != mainPlace
              ? '$mainPlace, $state'
              : mainPlace;
        }
      }
    } catch (_) {}

    // 2. OpenStreetMap Nominatim fallback
    try {
      final r = await _dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {'lat': lat, 'lon': lon, 'format': 'json', 'accept-language': 'hi'},
        options: Options(
          headers: {'User-Agent': 'KisanMausamApp/1.0'},
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      if (r.statusCode == 200 && r.data != null) {
        final addr = r.data['address'] as Map<String, dynamic>? ?? {};
        final parts = [
          addr['village'] ?? addr['town'] ?? addr['city'] ?? addr['county'] ?? '',
          addr['state_district'] ?? addr['state'] ?? '',
        ].where((s) => s.isNotEmpty).toList();
        if (parts.isNotEmpty) {
          return parts.join(', ');
        }
      }
    } catch (_) {}

    return '${lat.toStringAsFixed(2)}°N, ${lon.toStringAsFixed(2)}°E';
  }

  /// Search for a location by city/village name → list of results.
  static Future<List<LocationResult>> searchLocation(String query) async {
    try {
      final r = await _dio.get(
        'https://geocoding-api.open-meteo.com/v1/search',
        queryParameters: {'name': query, 'count': 7, 'language': 'hi', 'format': 'json'},
      );
      if (r.statusCode == 200 && r.data != null) {
        final results = (r.data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        return results.map((item) {
          final parts = [
            (item['name'] as String?) ?? '',
            (item['admin1'] as String?) ?? '',
            (item['country'] as String?) ?? '',
          ].where((s) => s.isNotEmpty).toList();
          return LocationResult(
            latitude: (item['latitude'] as num).toDouble(),
            longitude: (item['longitude'] as num).toDouble(),
            displayName: parts.join(', '),
          );
        }).toList();
      }
    } catch (_) {}
    return [];
  }
}
