import 'dart:async';

import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/photon_geocoder.dart';
import 'package:geolocator/geolocator.dart';

import 'astrology_model.dart';
import 'astrology_time.dart';

/// Only place searches use a network. Photon permits search-as-you-type;
/// names and birth dates are never sent to it. Device location uses the
/// platform's permission flow.
class AstrologyLocationService {
  AstrologyLocationService({MapGeocoder? geocoder})
      : _geocoder = geocoder ?? _defaultGeocoder;

  static final MapGeocoder _defaultGeocoder = PhotonGeocoder();
  static final instance = AstrologyLocationService();
  final MapGeocoder _geocoder;
  Future<AstrologyPlace>? _pending;
  AstrologyPlace? _last;
  String? _failure;
  DateTime? _attempted;

  Future<List<AstrologyPlace>> search(String query) async {
    if (query.trim().length < 2) return const [];
    final found = await _geocoder.search(query.trim());
    return [
      for (final place in found)
        AstrologyPlace(
          name: place.address.isEmpty ? place.name : place.address,
          latitude: place.point.latitude,
          longitude: place.point.longitude,
          timeZone:
              AstrologyTime.zoneAt(place.point.latitude, place.point.longitude),
        ),
    ];
  }

  Future<AstrologyPlace> current({bool force = false}) async {
    final pending = _pending;
    if (pending != null) return pending;
    if (!force &&
        _attempted != null &&
        DateTime.now().difference(_attempted!) < const Duration(minutes: 5)) {
      if (_last != null) return _last!;
      if (_failure != null) throw FormatException(_failure!);
    }
    final operation = _locate();
    _pending = operation;
    try {
      _last = await operation;
      _failure = null;
      return _last!;
    } on Object {
      _last = null;
      _failure = 'Current location is unavailable or permission was denied. '
          'Choose a place, enter coordinates, or enable Windows location services and retry.';
      throw FormatException(_failure!);
    } finally {
      _attempted = DateTime.now();
      _pending = null;
    }
  }

  Future<AstrologyPlace> _locate() async {
    if (!await Geolocator.isLocationServiceEnabled()
        .timeout(const Duration(seconds: 8))) {
      throw StateError('Location services are disabled.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission was denied.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 20),
      ),
    ).timeout(const Duration(seconds: 25));
    return AstrologyPlace(
      name: 'Current location',
      latitude: position.latitude,
      longitude: position.longitude,
      timeZone: AstrologyTime.zoneAt(position.latitude, position.longitude),
      isDeviceLocation: true,
    );
  }
}
