import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:nanoid/nanoid.dart';

import 'ai_provider.dart';

/// Every AI service the person has set up, and which of their models the chat
/// is currently using.
///
/// The list itself is ordinary settings and lives in key-value storage. The API
/// keys never do: they go to [ProviderSecretStore], which seals them with
/// DPAPI on Windows and keeps them for the session anywhere else.
class CustomAIProviderStore extends ChangeNotifier {
  CustomAIProviderStore(
      {KeyValueStorage? storage, ProviderSecretStore? secrets})
      : _storage = storage,
        _secrets = secrets ?? ProviderSecretStore(storage: storage);

  static final CustomAIProviderStore instance = CustomAIProviderStore();

  static const providersKey = 'appflowy_custom_ai_providers';
  static const selectedModelKey = 'appflowy_custom_ai_selected_model';
  static const secretPrefix = 'appflowy_ai_provider_';

  final KeyValueStorage? _storage;
  final ProviderSecretStore _secrets;

  final List<CustomAIProvider> _providers = [];
  String? _selectedModel;
  Future<void>? _loading;
  bool _loaded = false;

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  List<CustomAIProvider> get providers => List.unmodifiable(_providers);

  /// The encoded name of the model the chat should use, or null when the
  /// built-in AppFlowy model is in force.
  String? get selectedModelName => _selectedModel;

  /// Whether settings have been read. Until they have, nothing is known about
  /// which model is really selected.
  bool get isLoaded => _loaded;

  /// Whether a secret survives closing the application on this platform.
  bool get keysPersist => _secrets.canPersist;

  Future<void> ensureLoaded() {
    if (_loaded) {
      return Future.value();
    }
    // ⚠️ Nothing to read from yet. Returning without remembering an attempt is
    // what lets the next caller try again; caching here would leave the whole
    // session believing no provider was ever configured.
    if (_kv == null) {
      return Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _kv?.get(providersKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final stored = decoded
              .whereType<Map>()
              .map((entry) => CustomAIProvider.fromJson(entry.cast()))
              .where((provider) => provider.id.isNotEmpty)
              .toList();
          // Merge rather than replace: a provider added while this read was in
          // flight must not be thrown away by the answer arriving late.
          for (final provider in stored) {
            if (!_providers.any((existing) => existing.id == provider.id)) {
              _providers.add(provider);
            }
          }
        }
      }
      _selectedModel ??= await _kv?.get(selectedModelKey);
      _loaded = true;
    } catch (error) {
      Log.warn('Could not read the configured AI providers: $error');
    } finally {
      _loading = null;
    }

    if (_loaded) {
      notifyListeners();
    }
  }

  CustomAIProvider? providerFor(String id) {
    for (final provider in _providers) {
      if (provider.id == id) {
        return provider;
      }
    }
    return null;
  }

  /// The provider and model the chat should use right now, or null.
  ({CustomAIProvider provider, String model})? get activeSelection {
    final selected = _selectedModel;
    if (selected == null) {
      return null;
    }
    final decoded = CustomAIModelName.decode(selected);
    if (decoded == null) {
      return null;
    }
    final provider = providerFor(decoded.providerId);
    if (provider == null) {
      return null;
    }
    return (provider: provider, model: decoded.model);
  }

  /// Every configured model, dressed as the picker's own model type so no
  /// other surface has to learn what a custom provider is.
  List<AIModelPB> get models {
    final models = <AIModelPB>[];
    for (final provider in _providers) {
      for (final model in provider.models) {
        models.add(
          AIModelPB(
            name: CustomAIModelName.encode(provider.id, model),
            isLocal: provider.runsLocally,
            desc: provider.name,
          ),
        );
      }
    }
    return models;
  }

  Future<void> select(String? encodedModelName) async {
    await ensureLoaded();
    if (_selectedModel == encodedModelName) {
      return;
    }
    _selectedModel = encodedModelName;
    if (encodedModelName == null) {
      await _kv?.remove(selectedModelKey);
    } else {
      await _kv?.set(selectedModelKey, encodedModelName);
    }
    notifyListeners();
  }

  Future<CustomAIProvider> upsert(
    CustomAIProvider provider, {
    String? apiKey,
  }) async {
    await ensureLoaded();

    final resolved =
        provider.id.isEmpty ? provider.copyWith(id: nanoid(12)) : provider;
    final index = _providers.indexWhere((entry) => entry.id == resolved.id);
    if (index == -1) {
      _providers.add(resolved);
    } else {
      _providers[index] = resolved;
    }

    if (apiKey != null) {
      if (apiKey.isEmpty) {
        await _secrets.forget('$secretPrefix${resolved.id}');
      } else {
        await _secrets.write('$secretPrefix${resolved.id}', apiKey);
      }
    }

    await _persist();
    notifyListeners();
    return resolved;
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    _providers.removeWhere((provider) => provider.id == id);
    await _secrets.forget('$secretPrefix$id');

    final selected = _selectedModel;
    if (selected != null &&
        CustomAIModelName.decode(selected)?.providerId == id) {
      _selectedModel = null;
      await _kv?.remove(selectedModelKey);
    }

    await _persist();
    notifyListeners();
  }

  Future<String?> apiKeyFor(String id) => _secrets.read('$secretPrefix$id');

  Future<bool> hasApiKey(String id) async {
    final key = await apiKeyFor(id);
    return key != null && key.isNotEmpty;
  }

  Future<void> _persist() async {
    final payload = jsonEncode(
      _providers.map((provider) => provider.toJson()).toList(),
    );
    await _kv?.set(providersKey, payload);
  }
}
