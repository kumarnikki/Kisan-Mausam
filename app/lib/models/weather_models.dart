class CurrentWeather {
  final String time;
  final double temperature;
  final double relativeHumidity;
  final double apparentTemperature;
  final double precipitation;
  final int weatherCode;
  final double windSpeed;
  final double windGusts;
  final double uvIndex;
  final double soilTemperature;
  final double soilMoisture;
  final bool isDay;

  CurrentWeather({
    required this.time,
    required this.temperature,
    required this.relativeHumidity,
    required this.apparentTemperature,
    required this.precipitation,
    required this.weatherCode,
    required this.windSpeed,
    required this.windGusts,
    required this.uvIndex,
    required this.soilTemperature,
    required this.soilMoisture,
    this.isDay = true,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> json) {
    final rawIsDay = json['is_day'];
    final bool calculatedIsDay;
    if (rawIsDay != null) {
      calculatedIsDay = rawIsDay == 1 || rawIsDay == true;
    } else {
      final hour = DateTime.now().hour;
      calculatedIsDay = hour >= 6 && hour < 19;
    }

    return CurrentWeather(
      time: json['time'] ?? '',
      temperature: (json['temperature_2m'] as num?)?.toDouble() ?? 0.0,
      relativeHumidity: (json['relativehumidity_2m'] as num?)?.toDouble() ?? 0.0,
      apparentTemperature: (json['apparent_temperature'] as num?)?.toDouble() ?? 0.0,
      precipitation: (json['precipitation'] as num?)?.toDouble() ?? 0.0,
      weatherCode: (json['weathercode'] as num?)?.toInt() ?? 0,
      windSpeed: (json['windspeed_10m'] as num?)?.toDouble() ?? 0.0,
      windGusts: (json['windgusts_10m'] as num?)?.toDouble() ?? 0.0,
      uvIndex: (json['uv_index'] as num?)?.toDouble() ?? 0.0,
      soilTemperature: (json['soil_temperature_0cm'] as num?)?.toDouble() ?? 0.0,
      soilMoisture: (json['soil_moisture_0_1cm'] as num?)?.toDouble() ?? 0.0,
      isDay: calculatedIsDay,
    );
  }

  Map<String, dynamic> toJson() => {
    'time': time,
    'temperature_2m': temperature,
    'relativehumidity_2m': relativeHumidity,
    'apparent_temperature': apparentTemperature,
    'precipitation': precipitation,
    'weathercode': weatherCode,
    'windspeed_10m': windSpeed,
    'windgusts_10m': windGusts,
    'uv_index': uvIndex,
    'soil_temperature_0cm': soilTemperature,
    'soil_moisture_0_1cm': soilMoisture,
    'is_day': isDay ? 1 : 0,
  };
}

class HourlyForecast {
  final String time;
  final double temperature;
  final int precipitationProbability;
  final double precipitation;
  final int weatherCode;
  final double windSpeed;
  final double relativeHumidity;

  HourlyForecast({
    required this.time,
    required this.temperature,
    required this.precipitationProbability,
    required this.precipitation,
    required this.weatherCode,
    required this.windSpeed,
    required this.relativeHumidity,
  });

  factory HourlyForecast.fromJson(Map<String, dynamic> json) {
    return HourlyForecast(
      time: json['time'] ?? '',
      temperature: (json['temperature_2m'] as num?)?.toDouble() ?? 0.0,
      precipitationProbability: (json['precipitation_probability'] as num?)?.toInt() ?? 0,
      precipitation: (json['precipitation'] as num?)?.toDouble() ?? 0.0,
      weatherCode: (json['weathercode'] as num?)?.toInt() ?? 0,
      windSpeed: (json['windspeed_10m'] as num?)?.toDouble() ?? 0.0,
      relativeHumidity: (json['relativehumidity_2m'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'time': time,
    'temperature_2m': temperature,
    'precipitation_probability': precipitationProbability,
    'precipitation': precipitation,
    'weathercode': weatherCode,
    'windspeed_10m': windSpeed,
    'relativehumidity_2m': relativeHumidity,
  };
}

class DailyForecast {
  final String date;
  final double tempMax;
  final double tempMin;
  final double precipitationSum;
  final int precipitationProbabilityMax;
  final double windSpeedMax;
  final String sunrise;
  final String sunset;
  final double uvIndexMax;
  final int weatherCode;

  DailyForecast({
    required this.date,
    required this.tempMax,
    required this.tempMin,
    required this.precipitationSum,
    required this.precipitationProbabilityMax,
    required this.windSpeedMax,
    required this.sunrise,
    required this.sunset,
    required this.uvIndexMax,
    required this.weatherCode,
  });

  factory DailyForecast.fromJson(Map<String, dynamic> json) {
    return DailyForecast(
      date: json['date'] ?? '',
      tempMax: (json['temperature_2m_max'] as num?)?.toDouble() ?? 0.0,
      tempMin: (json['temperature_2m_min'] as num?)?.toDouble() ?? 0.0,
      precipitationSum: (json['precipitation_sum'] as num?)?.toDouble() ?? 0.0,
      precipitationProbabilityMax: (json['precipitation_probability_max'] as num?)?.toInt() ?? 0,
      windSpeedMax: (json['windspeed_10m_max'] as num?)?.toDouble() ?? 0.0,
      sunrise: json['sunrise'] ?? '',
      sunset: json['sunset'] ?? '',
      uvIndexMax: (json['uv_index_max'] as num?)?.toDouble() ?? 0.0,
      weatherCode: (json['weathercode'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'temperature_2m_max': tempMax,
    'temperature_2m_min': tempMin,
    'precipitation_sum': precipitationSum,
    'precipitation_probability_max': precipitationProbabilityMax,
    'windspeed_10m_max': windSpeedMax,
    'sunrise': sunrise,
    'sunset': sunset,
    'uv_index_max': uvIndexMax,
    'weathercode': weatherCode,
  };
}

class WeatherData {
  final double latitude;
  final double longitude;
  final String timezone;
  final double elevation;
  final CurrentWeather current;
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;
  final String attribution;
  final String cachedAt;

  WeatherData({
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.elevation,
    required this.current,
    required this.hourly,
    required this.daily,
    required this.attribution,
    required this.cachedAt,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      timezone: json['timezone'] ?? 'Asia/Kolkata',
      elevation: (json['elevation'] as num?)?.toDouble() ?? 0.0,
      current: CurrentWeather.fromJson(json['current'] ?? {}),
      hourly: ((json['hourly'] as List?) ?? [])
          .map((item) => HourlyForecast.fromJson(item))
          .toList(),
      daily: ((json['daily'] as List?) ?? [])
          .map((item) => DailyForecast.fromJson(item))
          .toList(),
      attribution: json['attribution'] ?? 'Open-Meteo.com (CC BY 4.0)',
      cachedAt: json['cached_at'] ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'timezone': timezone,
    'elevation': elevation,
    'current': current.toJson(),
    'hourly': hourly.map((h) => h.toJson()).toList(),
    'daily': daily.map((d) => d.toJson()).toList(),
    'attribution': attribution,
    'cached_at': cachedAt,
  };
}
