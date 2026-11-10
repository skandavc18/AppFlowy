import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/linux_keyring.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:ffi/ffi.dart';

/// Where a provider's access and refresh tokens live.
///
/// A provider token is exactly as sensitive as a password and must never be
/// written to [KeyValueStorage] in the clear — that is a plain file. On Windows
/// the token is sealed with DPAPI first, which binds the stored blob to the
/// signed-in Windows account: it is useless to another user and useless on
/// another machine. On Linux it goes into the desktop keyring, which the
/// person's login encrypts and unlocks in the same way. Anywhere else, or when
/// there is no keyring, the token is held for the session only, and the
/// interface says so rather than pretending the connection is permanent.
///
/// A provider *password* is never stored at all, for any service: the
/// connection dialogs only ever ask for a token the service itself issued, and
/// OAuth never sees one.
class ProviderSecretStore {
  ProviderSecretStore({KeyValueStorage? storage, DesktopKeyring? keyring})
      : _storage = storage,
        _keyring = keyring ?? LinuxKeyring.instance;

  static const _prefix = 'appflowy_provider_secret_';
  static const _keyringScope = 'provider';

  final KeyValueStorage? _storage;
  final DesktopKeyring _keyring;

  // One cache for every store over the same storage: a token written through
  // one of them — by sync, say — is the one all the others read.
  static final Expando<Map<String, String>> _sessions = Expando();
  static final Object _defaultOwner = Object();
  static final KeyValueStorage _nullStorage = _NullStorage();

  Map<String, String> get _session =>
      _sessions[_storage ?? _defaultOwner] ??= <String, String>{};

  KeyValueStorage get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>()
          ? getIt<KeyValueStorage>()
          : _nullStorage);

  /// Whether a token survives closing the application on this machine.
  bool get canPersist =>
      (Platform.isWindows && _dpapi.isAvailable) || _keyring.isAvailable;

  bool get isSessionOnly => !canPersist;

  /// Keeps [secret] for the session and, where the platform can seal it,
  /// between sessions too.
  Future<void> write(String connectionId, String secret) async {
    _session[connectionId] = secret;
    if (_keyring.isAvailable) {
      try {
        if (secret.isEmpty) {
          await _keyring.clear(scope: _keyringScope, id: connectionId);
        } else {
          await _keyring.store(
            scope: _keyringScope,
            id: connectionId,
            label: 'AppFlowy: $connectionId',
            secret: secret,
          );
        }
      } on KeyringError catch (error) {
        Log.warn(
          'The desktop keyring did not keep a provider token, so it is held '
          'for this session only: ${error.detail}',
        );
      }
      return;
    }
    if (!canPersist) {
      Log.info(
        'Provider tokens are held for this session only on this platform.',
      );
      return;
    }

    final sealed = _dpapi.protect(
      Uint8List.fromList(utf8.encode(secret)),
      entropy: connectionId,
    );
    if (sealed == null) {
      // Silence here reads as "signed in again every restart" with nothing to
      // go on, so the one thing that explains it is said out loud.
      Log.warn(
        'Windows refused to seal a provider token; it will not persist.',
      );
      return;
    }
    await _kv.set('$_prefix$connectionId', base64.encode(sealed));
  }

  Future<String?> read(String connectionId) async {
    final live = _session[connectionId];
    if (live != null) {
      return live;
    }
    if (_keyring.isAvailable) {
      return _readKeyring(connectionId);
    }
    if (!canPersist) {
      return null;
    }

    final stored = await _kv.get('$_prefix$connectionId');
    if (stored == null || stored.isEmpty) {
      return null;
    }

    try {
      final opened = _dpapi.unprotect(
        Uint8List.fromList(base64.decode(stored)),
        entropy: connectionId,
      );
      if (opened == null) {
        Log.warn('A stored provider token could not be unsealed.');
        return null;
      }
      final secret = utf8.decode(opened, allowMalformed: true);
      _session[connectionId] = secret;
      return secret;
    } catch (error) {
      Log.warn('A stored provider token could not be read: $error');
      return null;
    }
  }

  Future<bool> has(String connectionId) async =>
      (await read(connectionId))?.isNotEmpty ?? false;

  Future<String?> _readKeyring(String connectionId) async {
    try {
      final secret = await _keyring.lookup(
        scope: _keyringScope,
        id: connectionId,
      );
      // A write made while this read was out wins over what it found.
      final written = _session[connectionId];
      if (written != null) {
        return written;
      }
      if (secret != null) {
        _session[connectionId] = secret;
      }
      return secret;
    } on KeyringError catch (error) {
      Log.warn(
        'A provider token could not be read from the desktop keyring: '
        '${error.detail}',
      );
      return _session[connectionId];
    }
  }

  /// Drops the token everywhere. This is what disconnecting a service means.
  Future<void> forget(String connectionId) async {
    _session.remove(connectionId);
    if (_keyring.isAvailable) {
      try {
        await _keyring.clear(scope: _keyringScope, id: connectionId);
      } on KeyringError catch (error) {
        Log.warn(
          'A provider token could not be removed from the desktop keyring: '
          '${error.detail}',
        );
      }
    }
    await _kv.remove('$_prefix$connectionId');
  }
}

/// Windows' own secret sealing, reached through FFI so no package is needed.
class _Dpapi {
  _Dpapi() {
    if (!Platform.isWindows) {
      return;
    }
    try {
      final crypt32 = DynamicLibrary.open('Crypt32.dll');
      final kernel32 = DynamicLibrary.open('Kernel32.dll');
      _protect = crypt32.lookupFunction<_CryptDataNative, _CryptDataDart>(
        'CryptProtectData',
      );
      _unprotect = crypt32.lookupFunction<_CryptDataNative, _CryptDataDart>(
        'CryptUnprotectData',
      );
      _localFree = kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
        'LocalFree',
      );
    } catch (_) {
      _protect = null;
      _unprotect = null;
    }
  }

  /// Never show a prompt: this runs while somebody is looking at a list.
  static const _uiForbidden = 0x1;

  _CryptDataDart? _protect;
  _CryptDataDart? _unprotect;
  _LocalFreeDart? _localFree;

  bool get isAvailable => _protect != null && _unprotect != null;

  Uint8List? protect(Uint8List data, {required String entropy}) =>
      _call(_protect, data, entropy);

  Uint8List? unprotect(Uint8List data, {required String entropy}) =>
      _call(_unprotect, data, entropy);

  Uint8List? _call(_CryptDataDart? function, Uint8List data, String entropy) {
    if (function == null) {
      return null;
    }

    final entropyBytes = Uint8List.fromList(utf8.encode(entropy));
    final input = calloc<_DataBlob>();
    final salt = calloc<_DataBlob>();
    final output = calloc<_DataBlob>();
    final inputBytes = calloc<Uint8>(data.length);
    final saltBytes = calloc<Uint8>(entropyBytes.length);

    try {
      inputBytes.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = inputBytes;

      saltBytes.asTypedList(entropyBytes.length).setAll(0, entropyBytes);
      salt.ref
        ..cbData = entropyBytes.length
        ..pbData = saltBytes;

      final ok = function(
        input,
        nullptr,
        salt,
        nullptr,
        nullptr,
        _uiForbidden,
        output,
      );
      if (ok == 0) {
        return null;
      }

      final result = Uint8List.fromList(
        output.ref.pbData.asTypedList(output.ref.cbData),
      );
      _localFree?.call(output.ref.pbData.cast());
      return result;
    } catch (_) {
      return null;
    } finally {
      calloc
        ..free(inputBytes)
        ..free(saltBytes)
        ..free(input)
        ..free(salt)
        ..free(output);
    }
  }
}

final _dpapi = _Dpapi();

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptDataNative = Int32 Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Utf16> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  Uint32 flags,
  Pointer<_DataBlob> dataOut,
);

typedef _CryptDataDart = int Function(
  Pointer<_DataBlob> dataIn,
  Pointer<Utf16> description,
  Pointer<_DataBlob> entropy,
  Pointer<Void> reserved,
  Pointer<Void> prompt,
  int flags,
  Pointer<_DataBlob> dataOut,
);

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> handle);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> handle);

/// Stands in when the application has not registered its storage yet, so a
/// stored token is never worth failing a view over.
class _NullStorage implements KeyValueStorage {
  @override
  Future<void> set(String key, String value) async {}

  @override
  Future<String?> get(String key) async => null;

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async =>
      null;

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> clear() async {}
}
