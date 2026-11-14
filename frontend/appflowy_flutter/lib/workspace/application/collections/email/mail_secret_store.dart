import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/linux_keyring.dart';
import 'package:appflowy/shared/platform_secret_store.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:ffi/ffi.dart';

/// Where a mailbox password lives.
///
/// AppFlowy has no keychain of its own — [KeyValueStorage] is shared
/// preferences, which is a plain file on disk — so a mail password must not
/// simply be written there. On Windows the secret is sealed with DPAPI first,
/// which ties it to the signed-in Windows account: the stored blob is useless
/// to another user and useless on another machine. On Linux it goes into the
/// desktop keyring, which the person's login encrypts and unlocks in the same
/// way. Anywhere else the secret is held for the session only and the
/// interface says so, because a password written down in the clear is worse
/// than one typed again.
class MailSecretStore {
  MailSecretStore({KeyValueStorage? storage, DesktopKeyring? keyring})
      : _storage = storage,
        _keyring = keyring ?? defaultPlatformKeyring();

  static const _prefix = 'appflowy_mail_secret_';
  static const _keyringScope = 'mail';

  final KeyValueStorage? _storage;
  final DesktopKeyring _keyring;

  // One cache for every store over the same storage: a password written
  // through one of them — by sync, say — is the one all the others read.
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

  /// Whether a secret can be kept between sessions on this machine.
  bool get canPersist =>
      (Platform.isWindows && _dpapi.isAvailable) || _keyring.isAvailable;

  /// Why it cannot, for the interface to repeat.
  bool get isSessionOnly => !canPersist;

  /// Remembers [secret] for the session, and seals it to disk when the reader
  /// asked for that and the platform can do it safely.
  Future<void> write(
    String accountId,
    String secret, {
    required bool remember,
  }) async {
    _session[accountId] = secret;
    if (!remember || !canPersist) {
      await forgetStored(accountId);
      return;
    }

    if (_keyring.isAvailable) {
      try {
        await _keyring.store(
          scope: _keyringScope,
          id: accountId,
          label: 'AppFlowy mailbox: $accountId',
          secret: secret,
        );
      } on KeyringError {
        // Held for this session; the interface already says it may be asked
        // for again.
      }
      return;
    }

    final sealed = _dpapi.protect(
      Uint8List.fromList(utf8.encode(secret)),
      entropy: accountId,
    );
    if (sealed == null) {
      return;
    }
    await _kv.set('$_prefix$accountId', base64.encode(sealed));
  }

  /// The secret for [accountId], from this session or from the sealed store.
  Future<String?> read(String accountId) async {
    final live = _session[accountId];
    if (live != null) {
      return live;
    }
    final stored = await readStored(accountId);
    if (stored != null) {
      _session[accountId] = stored;
    }
    return stored;
  }

  /// The secret for [accountId] as it is kept between sessions: null when it
  /// was only ever typed for this one.
  Future<String?> readStored(String accountId) async {
    if (!canPersist) {
      return null;
    }
    if (_keyring.isAvailable) {
      try {
        return await _keyring.lookup(scope: _keyringScope, id: accountId);
      } on KeyringError {
        return null;
      }
    }

    final stored = await _kv.get('$_prefix$accountId');
    if (stored == null || stored.isEmpty) {
      return null;
    }

    try {
      final opened = _dpapi.unprotect(
        Uint8List.fromList(base64.decode(stored)),
        entropy: accountId,
      );
      if (opened == null) {
        return null;
      }
      return utf8.decode(opened, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  Future<bool> has(String accountId) async =>
      (await read(accountId))?.isNotEmpty ?? false;

  /// Drops the secret everywhere, which is what disconnecting a mailbox means.
  Future<void> forget(String accountId) async {
    _session.remove(accountId);
    await forgetStored(accountId);
  }

  Future<void> forgetStored(String accountId) async {
    if (_keyring.isAvailable) {
      try {
        await _keyring.clear(scope: _keyringScope, id: accountId);
      } on KeyringError {
        // Nothing more can be done from here.
      }
    }
    await _kv.remove('$_prefix$accountId');
  }
}

/// Windows' own secret sealing, reached straight through FFI so no package is
/// needed for it.
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

  /// Never show a prompt: this runs while the reader is looking at a list.
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

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> memory);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> memory);

/// Stands in when the application's storage is not registered, which is the
/// case in a plain unit test.
class _NullStorage implements KeyValueStorage {
  @override
  Future<void> clear() async {}

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
  Future<void> set(String key, String value) async {}
}
