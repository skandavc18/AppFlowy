import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/weather/weather_reading.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// The place Home shows the weather for.
@immutable
class HomeWeatherPlace {
  const HomeWeatherPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;
}

typedef HomeWeatherFetch = Future<WeatherReading> Function(
  HomeWeatherPlace place,
  bool fahrenheit,
);

/// Home's weather. Nothing is read until somebody chooses a place, and that
/// choice stays on this device.
class HomeWeatherSource extends ChangeNotifier {
  HomeWeatherSource({
    KeyValueStorage? storage,
    bool persist = true,
    HomeWeatherFetch? fetch,
    this.refreshEvery = const Duration(minutes: 30),
  })  : _storage = storage,
        _persist = persist,
        _fetch = fetch ?? _readOpenMeteo;

  static const storageKey = 'appflowy_home_weather';

  final KeyValueStorage? _storage;
  final bool _persist;
  final HomeWeatherFetch _fetch;
  final Duration refreshEvery;

  HomeWeatherPlace? _place;
  bool _fahrenheit = false;
  WeatherReading? _reading;
  bool _loading = false;
  bool _failed = false;
  bool _started = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _timer;

  HomeWeatherPlace? get place => _place;
  bool get fahrenheit => _fahrenheit;
  WeatherReading? get reading => _reading;
  bool get isLoading => _loading;
  bool get failed => _failed;

  KeyValueStorage? get _kv => !_persist
      ? null
      : _storage ??
          (getIt.isRegistered<KeyValueStorage>()
              ? getIt<KeyValueStorage>()
              : null);

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    await _readSettings();
    if (_disposed) return;
    _timer = Timer.periodic(refreshEvery, (_) => unawaited(refresh()));
    await refresh();
  }

  Future<void> _readSettings() async {
    try {
      final stored = await _kv?.get(storageKey);
      if (stored == null || stored.isEmpty) return;
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return;
      final name = decoded['place'];
      final latitude = decoded['latitude'];
      final longitude = decoded['longitude'];
      // A choice made while the stored one was loading wins.
      if (_place == null &&
          name is String &&
          name.trim().isNotEmpty &&
          latitude is num &&
          longitude is num) {
        _place = HomeWeatherPlace(
          name: name.trim(),
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
        );
        _fahrenheit = decoded['fahrenheit'] == true;
      }
    } catch (error) {
      Log.warn('The Home weather place could not be read: $error');
    }
  }

  Future<void> refresh() async {
    final place = _place;
    if (_disposed || place == null) return;
    final generation = ++_generation;
    _loading = true;
    _failed = false;
    _notify();
    try {
      final reading = await _fetch(place, _fahrenheit);
      if (_disposed || generation != _generation) return;
      _reading = reading;
      _loading = false;
      _notify();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      Log.warn('The weather could not be read: $error');
      _loading = false;
      _failed = true;
      _notify();
    }
  }

  Future<void> setPlace(HomeWeatherPlace place) async {
    _place = place;
    _reading = null;
    await _save();
    await refresh();
  }

  Future<void> setFahrenheit(bool fahrenheit) async {
    if (_fahrenheit == fahrenheit) return;
    _fahrenheit = fahrenheit;
    _reading = null;
    await _save();
    await refresh();
  }

  /// Stop showing the weather and forget the place.
  Future<void> clear() async {
    _generation++;
    _place = null;
    _reading = null;
    _loading = false;
    _failed = false;
    _notify();
    try {
      await _kv?.remove(storageKey);
    } catch (error) {
      Log.warn('The Home weather place could not be forgotten: $error');
    }
  }

  Future<void> _save() async {
    _notify();
    final place = _place;
    try {
      await _kv?.set(
        storageKey,
        jsonEncode({
          if (place != null) ...{
            'place': place.name,
            'latitude': place.latitude,
            'longitude': place.longitude,
          },
          if (_fahrenheit) 'fahrenheit': true,
        }),
      );
    } catch (error) {
      Log.warn('The Home weather place could not be saved: $error');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static Future<WeatherReading> _readOpenMeteo(
    HomeWeatherPlace place,
    bool fahrenheit,
  ) =>
      readWeather(
        latitude: place.latitude,
        longitude: place.longitude,
        fahrenheit: fahrenheit,
      );

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
