import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/linux_keyring.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('provider tokens in the desktop keyring', () {
    late _MemoryKeyValue storage;
    late _MemoryKeyring keyring;

    setUp(() {
      storage = _MemoryKeyValue();
      keyring = _MemoryKeyring();
    });

    test('a sign in outlives a restart, and never lands in preferences',
        () async {
      const connection = ProviderConnection(
        id: 'google|sub-1',
        service: ProviderService.googleDrive,
        accountLabel: 'me@gmail.com',
        accountId: 'sub-1',
      );
      const token = ProviderCredentials(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
      );
      final before = ProviderConnections(
        storage: storage,
        secrets: ProviderSecretStore(storage: storage, keyring: keyring),
      );
      expect(before.canPersistSecrets, isTrue);
      await before.upsert(connection, token);

      // A new start: nothing in memory but what is stored.
      final restarted = storage.restarted();
      final after = ProviderConnections(
        storage: restarted,
        secrets: ProviderSecretStore(storage: restarted, keyring: keyring),
      );
      await after.ensureLoaded();
      final restored = await after.credentialsFor(connection.id);
      expect(restored?.accessToken, 'access-token');
      expect(restored?.refreshToken, 'refresh-token');
      expect(await after.hasCredentials(connection.id), isTrue);
      for (final value in storage.values.values) {
        expect(value, isNot(contains('access-token')));
        expect(value, isNot(contains('refresh-token')));
      }
    });

    test('forgetting or emptying a secret removes it from the keyring',
        () async {
      final store = ProviderSecretStore(storage: storage, keyring: keyring);
      await store.write('one', 'first');
      await store.write('two', 'second');
      expect(keyring.items.length, 2);

      await store.forget('one');
      await store.write('two', '');
      expect(keyring.items, isEmpty);
      final fresh =
          ProviderSecretStore(storage: storage.restarted(), keyring: keyring);
      expect(await fresh.read('one'), isNull);
      expect(await fresh.has('two'), isFalse);
    });

    test('a keyring that refuses leaves the secret for this session', () async {
      keyring.refuses = true;
      final store = ProviderSecretStore(storage: storage, keyring: keyring);
      await store.write('one', 'kept for now');
      expect(await store.read('one'), 'kept for now');
      await store.forget('one');
      expect(await store.read('one'), isNull);
      expect(storage.values, isEmpty);
    });

    test('without a keyring a secret is held for the session only', () async {
      keyring.available = false;
      final store = ProviderSecretStore(storage: storage, keyring: keyring);
      expect(store.canPersist, isFalse);
      await store.write('one', 'session');
      expect(await store.read('one'), 'session');
      expect(
        await ProviderSecretStore(
          storage: storage.restarted(),
          keyring: keyring,
        ).read('one'),
        isNull,
      );
      expect(keyring.items, isEmpty);
    });

    test('unit tests never reach the keyring of whoever runs them', () {
      expect(LinuxKeyring.instance.isAvailable, isFalse);
    });
  });
}

class _MemoryKeyring implements DesktopKeyring {
  final Map<String, String> items = {};
  bool available = true;
  bool refuses = false;

  @override
  bool get isAvailable => available;

  @override
  Future<void> store({
    required String scope,
    required String id,
    required String label,
    required String secret,
  }) async {
    _refuse();
    items['$scope/$id'] = secret;
  }

  @override
  Future<String?> lookup({required String scope, required String id}) async {
    _refuse();
    return items['$scope/$id'];
  }

  @override
  Future<void> clear({required String scope, required String id}) async {
    _refuse();
    items.remove('$scope/$id');
  }

  void _refuse() {
    if (refuses) {
      throw const KeyringError('The keyring refused.');
    }
  }
}

class _MemoryKeyValue implements KeyValueStorage {
  final Map<String, String> values = {};

  /// The same storage after a restart: what was written down, and nothing
  /// that was only in memory.
  _MemoryKeyValue restarted() => _MemoryKeyValue()..values.addAll(values);

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> clear() async {
    values.clear();
  }

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }
}
