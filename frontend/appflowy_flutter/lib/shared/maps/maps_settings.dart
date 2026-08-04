import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// What the application has been told about map services.
///
/// Google is the default provider, but it will not draw a tile or find an
/// address without a key. Until one is given the map falls back to the keyless
/// providers, so it works out of the box and simply gets better once a key is
/// entered in Settings.
class MapsSettings extends ChangeNotifier {
  MapsSettings._();

  static final MapsSettings instance = MapsSettings._();

  static const _apiKeyStorageKey = 'appflowy_maps_google_api_key';

  String _apiKey = '';
  bool _loaded = false;

  String get apiKey => _apiKey;

  bool get hasGoogleKey => _apiKey.isNotEmpty;

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      _apiKey = await getIt<KeyValueStorage>().get(_apiKeyStorageKey) ?? '';
      notifyListeners();
    } on Object catch (error) {
      Log.warn('Could not read the map settings: $error');
    }
  }

  Future<void> setApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed == _apiKey) {
      return;
    }
    _apiKey = trimmed;
    notifyListeners();
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      if (trimmed.isEmpty) {
        await getIt<KeyValueStorage>().remove(_apiKeyStorageKey);
      } else {
        await getIt<KeyValueStorage>().set(_apiKeyStorageKey, trimmed);
      }
    } on Object catch (error) {
      Log.warn('Could not store the map settings: $error');
    }
  }
}
