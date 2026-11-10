// libsecret's password calls, reached straight through FFI.
//
// Kept apart from [LinuxKeyring] and free of Flutter, so it runs on any isolate
// and in a plain Dart program.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The keyring could not do what was asked.
class KeyringError implements Exception {
  const KeyringError(this.detail);

  final String detail;

  @override
  String toString() => 'KeyringError: $detail';
}

/// The schema every AppFlowy secret is filed under.
const String keyringSchemaName = 'io.appflowy.AppFlowy.Secret';

final class _GError extends Struct {
  @Uint32()
  external int domain;

  @Int32()
  external int code;

  external Pointer<Utf8> message;
}

typedef _HashTableNewNative = Pointer<Void> Function(
  Pointer<Void> hash,
  Pointer<Void> equal,
);
typedef _HashTableInsertNative = Int32 Function(
  Pointer<Void> table,
  Pointer<Void> key,
  Pointer<Void> value,
);
typedef _HashTableInsertDart = int Function(
  Pointer<Void> table,
  Pointer<Void> key,
  Pointer<Void> value,
);
typedef _StrHashNative = Uint32 Function(Pointer<Void> key);
typedef _StrEqualNative = Int32 Function(Pointer<Void> a, Pointer<Void> b);
typedef _UnrefNative = Void Function(Pointer<Void> pointer);
typedef _UnrefDart = void Function(Pointer<Void> pointer);
typedef _ErrorFreeNative = Void Function(Pointer<_GError> error);
typedef _ErrorFreeDart = void Function(Pointer<_GError> error);
typedef _SchemaNewNative = Pointer<Void> Function(
  Pointer<Utf8> name,
  Int32 flags,
  Pointer<Void> attributeTypes,
);
typedef _SchemaNewDart = Pointer<Void> Function(
  Pointer<Utf8> name,
  int flags,
  Pointer<Void> attributeTypes,
);
typedef _StoreNative = Int32 Function(
  Pointer<Void> schema,
  Pointer<Void> attributes,
  Pointer<Utf8> collection,
  Pointer<Utf8> label,
  Pointer<Utf8> password,
  Pointer<Void> cancellable,
  Pointer<Pointer<_GError>> error,
);
typedef _StoreDart = int Function(
  Pointer<Void> schema,
  Pointer<Void> attributes,
  Pointer<Utf8> collection,
  Pointer<Utf8> label,
  Pointer<Utf8> password,
  Pointer<Void> cancellable,
  Pointer<Pointer<_GError>> error,
);
typedef _LookupNative = Pointer<Utf8> Function(
  Pointer<Void> schema,
  Pointer<Void> attributes,
  Pointer<Void> cancellable,
  Pointer<Pointer<_GError>> error,
);
typedef _ClearNative = Int32 Function(
  Pointer<Void> schema,
  Pointer<Void> attributes,
  Pointer<Void> cancellable,
  Pointer<Pointer<_GError>> error,
);
typedef _ClearDart = int Function(
  Pointer<Void> schema,
  Pointer<Void> attributes,
  Pointer<Void> cancellable,
  Pointer<Pointer<_GError>> error,
);
typedef _PasswordFreeNative = Void Function(Pointer<Utf8> password);
typedef _PasswordFreeDart = void Function(Pointer<Utf8> password);

/// libsecret's password calls, looked up once per isolate. Every call
/// blocks until the keyring answers.
class Libsecret {
  Libsecret._(DynamicLibrary secret, DynamicLibrary glib)
      : _hashTableNew =
            glib.lookupFunction<_HashTableNewNative, _HashTableNewNative>(
          'g_hash_table_new',
        ),
        _hashTableInsert =
            glib.lookupFunction<_HashTableInsertNative, _HashTableInsertDart>(
          'g_hash_table_insert',
        ),
        _hashTableUnref = glib.lookupFunction<_UnrefNative, _UnrefDart>(
          'g_hash_table_unref',
        ),
        _strHash =
            glib.lookup<NativeFunction<_StrHashNative>>('g_str_hash').cast(),
        _strEqual =
            glib.lookup<NativeFunction<_StrEqualNative>>('g_str_equal').cast(),
        _errorFree = glib.lookupFunction<_ErrorFreeNative, _ErrorFreeDart>(
          'g_error_free',
        ),
        _schemaNew = secret.lookupFunction<_SchemaNewNative, _SchemaNewDart>(
          'secret_schema_newv',
        ),
        _schemaUnref = secret.lookupFunction<_UnrefNative, _UnrefDart>(
          'secret_schema_unref',
        ),
        _store = secret.lookupFunction<_StoreNative, _StoreDart>(
          'secret_password_storev_sync',
        ),
        _lookup = secret.lookupFunction<_LookupNative, _LookupNative>(
          'secret_password_lookupv_sync',
        ),
        _clear = secret.lookupFunction<_ClearNative, _ClearDart>(
          'secret_password_clearv_sync',
        ),
        _passwordFree =
            secret.lookupFunction<_PasswordFreeNative, _PasswordFreeDart>(
          'secret_password_free',
        );

  static Libsecret? _loaded;
  static bool _tried = false;

  static Libsecret? load() {
    if (!_tried) {
      _tried = true;
      try {
        _loaded = Libsecret._(
          DynamicLibrary.open('libsecret-1.so.0'),
          DynamicLibrary.open('libglib-2.0.so.0'),
        );
      } on Object {
        _loaded = null;
      }
    }
    return _loaded;
  }

  static Libsecret require() =>
      load() ?? (throw const KeyringError('libsecret is not installed.'));

  final _HashTableNewNative _hashTableNew;
  final _HashTableInsertDart _hashTableInsert;
  final _UnrefDart _hashTableUnref;
  final Pointer<Void> _strHash;
  final Pointer<Void> _strEqual;
  final _ErrorFreeDart _errorFree;
  final _SchemaNewDart _schemaNew;
  final _UnrefDart _schemaUnref;
  final _StoreDart _store;
  final _LookupNative _lookup;
  final _ClearDart _clear;
  final _PasswordFreeDart _passwordFree;

  void store(
    String profile,
    String scope,
    String id,
    String label,
    String secret,
  ) =>
      _call(profile, scope, id, (schema, attributes, error, arena) {
        final password = secret.toNativeUtf8(allocator: arena);
        try {
          final stored = _store(
            schema,
            attributes,
            nullptr,
            label.toNativeUtf8(allocator: arena),
            password,
            nullptr,
            error,
          );
          _check(error, succeeded: stored != 0);
        } finally {
          // Nothing of the secret is left behind in freed memory.
          password.cast<Uint8>().asTypedList(password.length).fillRange(
                0,
                password.length,
                0,
              );
        }
      });

  String? lookup(String profile, String scope, String id) =>
      _call(profile, scope, id, (schema, attributes, error, arena) {
        final found = _lookup(schema, attributes, nullptr, error);
        if (found == nullptr) {
          _check(error, succeeded: true);
          return null;
        }
        try {
          _check(error, succeeded: true);
          return found.toDartString();
        } finally {
          _passwordFree(found);
        }
      });

  /// Removes every secret kept for [profile].
  void clearProfile(String profile) => _withAttributes(
        {'profile': profile},
        (schema, attributes, error, arena) {
          _clear(schema, attributes, nullptr, error);
          _check(error, succeeded: true);
        },
      );

  void clear(String profile, String scope, String id) =>
      _call(profile, scope, id, (schema, attributes, error, arena) {
        // False with no error only means there was nothing to remove.
        _clear(schema, attributes, nullptr, error);
        _check(error, succeeded: true);
      });

  T _call<T>(
    String profile,
    String scope,
    String id,
    T Function(
      Pointer<Void> schema,
      Pointer<Void> attributes,
      Pointer<Pointer<_GError>> error,
      Arena arena,
    ) body,
  ) =>
      _withAttributes({'profile': profile, 'scope': scope, 'id': id}, body);

  // The schema always names all three attributes; [values] may give fewer,
  // to clear everything that matches them.
  T _withAttributes<T>(
    Map<String, String> values,
    T Function(
      Pointer<Void> schema,
      Pointer<Void> attributes,
      Pointer<Pointer<_GError>> error,
      Arena arena,
    ) body,
  ) =>
      using((arena) {
        final types = _hashTableNew(_strHash, _strEqual);
        final attributes = _hashTableNew(_strHash, _strEqual);
        var schema = nullptr.cast<Void>();
        try {
          for (final name in const ['profile', 'scope', 'id']) {
            // Every attribute is a string, which libsecret numbers 0.
            _hashTableInsert(
              types,
              name.toNativeUtf8(allocator: arena).cast<Void>(),
              nullptr,
            );
          }
          for (final entry in values.entries) {
            _hashTableInsert(
              attributes,
              entry.key.toNativeUtf8(allocator: arena).cast<Void>(),
              entry.value.toNativeUtf8(allocator: arena).cast<Void>(),
            );
          }
          schema = _schemaNew(
            keyringSchemaName.toNativeUtf8(allocator: arena),
            0,
            types,
          );
          if (schema == nullptr) {
            throw const KeyringError('The keyring schema was refused.');
          }
          final error = arena<Pointer<_GError>>()..value = nullptr;
          return body(schema, attributes, error, arena);
        } finally {
          if (schema != nullptr) {
            _schemaUnref(schema);
          }
          _hashTableUnref(attributes);
          _hashTableUnref(types);
        }
      });

  void _check(Pointer<Pointer<_GError>> error, {required bool succeeded}) {
    final raised = error.value;
    if (raised != nullptr) {
      final message = raised.ref.message == nullptr
          ? 'The keyring refused.'
          : raised.ref.message.toDartString();
      _errorFree(raised);
      error.value = nullptr;
      throw KeyringError(message);
    }
    if (!succeeded) {
      throw const KeyringError('The keyring refused.');
    }
  }
}
