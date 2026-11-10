import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/linux_keyring.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryKeyValue storage;
  late _MemoryKeyring keyring;

  setUp(() {
    storage = _MemoryKeyValue();
    keyring = _MemoryKeyring();
  });

  AppPassword start(_MemoryKeyValue storage, {_MemoryKeyring? keyring}) =>
      AppPassword(
        storage: storage,
        secrets: ProviderSecretStore(
          storage: storage,
          keyring: keyring ?? _MemoryKeyring(),
        ),
        iterations: 1000,
      );

  test('chosen once, known after a restart, never written in clear', () async {
    final first = start(storage, keyring: keyring);
    await first.ensureLoaded();
    expect(first.isSet, isFalse);
    await first.choose('a fine password');
    expect(first.isKnown, isTrue);
    expect(await first.current(), 'a fine password');
    for (final value in storage.values.values) {
      expect(value, isNot(contains('a fine password')));
    }
    await expectLater(first.choose('another'), throwsStateError);

    final again = start(storage.restarted(), keyring: keyring);
    expect(await again.current(), 'a fine password');
    expect(await again.check('a fine password'), isTrue);
    expect(await again.check('a wrong password'), isFalse);
  });

  test('a computer whose keyring lost it is asked once', () async {
    final first = start(storage, keyring: keyring);
    await first.choose('a fine password');

    final forgetful = start(storage.restarted());
    await forgetful.ensureLoaded();
    expect(forgetful.needsTyping, isTrue);
    expect(await forgetful.current(), isNull);
    expect(await forgetful.unlock('a wrong password'), isFalse);
    expect(await forgetful.unlock('a fine password'), isTrue);
    expect(await forgetful.current(), 'a fine password');
  });

  test('a password that opened a sealed folder is taken as it is', () async {
    final passwords = start(storage, keyring: keyring);
    await passwords.adopt('from the folder');
    expect(await passwords.current(), 'from the folder');

    // Changed on another computer: the new one replaces the old here too.
    await passwords.adopt('changed elsewhere');
    expect(await passwords.check('from the folder'), isFalse);
    expect(await passwords.check('changed elsewhere'), isTrue);

    final again = start(storage.restarted(), keyring: keyring);
    expect(await again.current(), 'changed elsewhere');
  });

  test('a changed password is the one kept', () async {
    final passwords = start(storage, keyring: keyring);
    await passwords.choose('the first one');
    await passwords.commitChange('the second one');
    final again = start(storage.restarted(), keyring: keyring);
    expect(await again.current(), 'the second one');
    expect(await again.check('the first one'), isFalse);
  });
}

class _MemoryKeyring implements DesktopKeyring {
  final Map<String, String> items = {};

  @override
  bool get isAvailable => true;

  @override
  Future<void> store({
    required String scope,
    required String id,
    required String label,
    required String secret,
  }) async =>
      items['$scope/$id'] = secret;

  @override
  Future<String?> lookup({required String scope, required String id}) async =>
      items['$scope/$id'];

  @override
  Future<void> clear({required String scope, required String id}) async =>
      items.remove('$scope/$id');
}

class _MemoryKeyValue implements KeyValueStorage {
  final Map<String, String> values = {};

  _MemoryKeyValue restarted() => _MemoryKeyValue()..values.addAll(values);

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }
}
