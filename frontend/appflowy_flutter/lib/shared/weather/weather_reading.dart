import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// One reading of the weather at a place, as Open-Meteo reported it.
@immutable
class WeatherReading {
  const WeatherReading({
    required this.temperature,
    required this.high,
    required this.low,
    required this.code,
  });

  final double temperature;
  final double high;
  final double low;

  /// The WMO weather code.
  final int code;
}

/// The temperature now and today's range at a place. Callers only ask once
/// somebody has chosen that place: nothing leaves the machine before then.
Future<WeatherReading> readWeather({
  required double latitude,
  required double longitude,
  bool fahrenheit = false,
  http.Client? client,
}) async {
  final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': '$latitude',
    'longitude': '$longitude',
    'current': 'temperature_2m,weather_code',
    'daily': 'temperature_2m_max,temperature_2m_min',
    'forecast_days': '1',
    'timezone': 'auto',
    if (fahrenheit) 'temperature_unit': 'fahrenheit',
  });
  final response = await (client?.get(uri) ?? http.get(uri))
      .timeout(const Duration(seconds: 12));
  if (response.statusCode != 200) {
    throw StateError('HTTP ${response.statusCode}');
  }
  final body = jsonDecode(response.body);
  if (body is! Map) {
    throw const FormatException('unexpected answer');
  }
  final current = body['current'];
  final daily = body['daily'];
  if (current is! Map || daily is! Map) {
    throw const FormatException('unexpected answer');
  }
  return WeatherReading(
    temperature: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
    high: _firstNumber(daily['temperature_2m_max']),
    low: _firstNumber(daily['temperature_2m_min']),
    code: (current['weather_code'] as num?)?.round() ?? 0,
  );
}

double _firstNumber(Object? value) =>
    value is List && value.isNotEmpty && value.first is num
        ? (value.first as num).toDouble()
        : 0;

/// WMO weather codes, as Open-Meteo reports them.
IconData weatherIconFor(int code) {
  if (code == 0) {
    return Icons.wb_sunny_rounded;
  }
  if (code <= 3) {
    return Icons.wb_cloudy_rounded;
  }
  if (code <= 48) {
    return Icons.foggy;
  }
  if (code <= 67 || (code >= 80 && code <= 82)) {
    return Icons.water_drop_rounded;
  }
  if (code <= 79 || (code >= 85 && code <= 86)) {
    return Icons.ac_unit_rounded;
  }
  return Icons.thunderstorm_rounded;
}
