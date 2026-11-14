import 'dart:async';
import 'dart:io';

import 'package:appflowy/shared/linux_keyring.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Chooses the platform secret store: `libsecret` on Linux, Android Keystore on
/// Android, and Keychain on macOS (Windows uses DPAPI directly in
/// `ProviderSecretStore` / `MailSecretStore`).
DesktopKeyring defaultPlatformKeyring() {
  if (!kIsWeb && (Platform.isAndroid || Platform.isMacOS)) {
    return PlatformChannelKeyring.instance;
  }
  return LinuxKeyring.instance;
}

/// Reaches the native Android Keystore (AES-256-GCM) or macOS Keychain through
/// `appflowy/secure_store`.
class PlatformChannelKeyring implements DesktopKeyring {
  PlatformChannelKeyring._();

  static final PlatformChannelKeyring instance = PlatformChannelKeyring._();

  static const MethodChannel _channel = MethodChannel('appflowy/secure_store');

  bool _refused = false;
  final Set<String> _absent = <String>{};
  final Map<String, Future<String?>> _reading = <String, Future<String?>>{};

  @override
  bool get isAvailable =>
      !kIsWeb &&
      !_refused &&
      (Platform.isAndroid || Platform.isMacOS) &&
      !Platform.environment.containsKey('FLUTTER_TEST');

  static String _key(String scope, String id) => '$scope\u0000$id';

  @override
  Future<void> store({
    required String scope,
    required String id,
    required String label,
    required String secret,
  }) async {
    final key = _key(scope, id);
    _absent.remove(key);
    try {
      await _channel.invokeMethod<void>('store', {
        'scope': scope,
        'id': id,
        'label': label,
        'secret': secret,
      });
      _absent.remove(key);
    } on MissingPluginException catch (error) {
      _refused = true;
      throw KeyringError('$error');
    } on PlatformException catch (error) {
      throw KeyringError(error.message ?? error.code);
    }
  }

  @override
  Future<String?> lookup({
    required String scope,
    required String id,
  }) {
    final key = _key(scope, id);
    if (_absent.contains(key)) {
      return Future<String?>.value();
    }
    return _reading[key] ??= () async {
      try {
        final found = await _channel.invokeMethod<String>('lookup', {
          'scope': scope,
          'id': id,
        });
        if (found == null) {
          _absent.add(key);
        }
        return found;
      } on MissingPluginException catch (error) {
        _refused = true;
        throw KeyringError('$error');
      } on PlatformException catch (error) {
        throw KeyringError(error.message ?? error.code);
      } finally {
        unawaited(_reading.remove(key));
      }
    }();
  }

  @override
  Future<void> clear({
    required String scope,
    required String id,
  }) async {
    final key = _key(scope, id);
    try {
      await _channel.invokeMethod<void>('clear', {
        'scope': scope,
        'id': id,
      });
      _absent.add(key);
    } on MissingPluginException catch (error) {
      _refused = true;
      throw KeyringError('$error');
    } on PlatformException catch (error) {
      throw KeyringError(error.message ?? error.code);
    }
  }

  Future<void> clearProfile() async {
    if (!isAvailable) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('clearAll');
      _absent.clear();
    } on Object {
      // Best-effort during app reset.
    }
  }
}
