import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/sync/server_settings_sync.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart'
    show SyncError;
import 'package:appflowy/workspace/application/sync/sync_preferences.dart';
import 'package:appflowy/workspace/application/sync/sync_vault.dart';
import 'package:appflowy/workspace/application/sync/synced_automation_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _passphrase = 'a passphrase for the account';

void main() {
  late Directory root;
  late _Server server;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('server_settings');
    server = _Server();
  });
  tearDown(() => root.delete(recursive: true));

  _Computer computer(String name, {String? password = _passphrase}) =>
      _Computer(root, name, server, password: password);

  test(
      'automation follows its account, survives logout remotely, and never leaks to the next account',
      () async {
    final accounts = _AccountServer();
    final a = _Computer(root, 'a', accounts, password: _passphrase);
    final b = _Computer(root, 'b', accounts, password: _passphrase);
    final source = _AutomationPreferences(a.home);
    a.sync.configure(preferences: source);
    b.sync.configure(preferences: _AutomationPreferences(b.home));
    final workflow = File(p.join(a.home.path, 'workflows/workflows.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('private workflow');
    final extension = File(p.join(a.home.path, 'extensions/demo/widget.js'))
      ..createSync(recursive: true)
      ..writeAsStringSync('private extension');
    await a.sync.attach(uid: 7);
    await a.sync.syncNow();
    await b.sync.attach(uid: 7);
    await b.sync.syncNow();
    expect(
      File(p.join(b.home.path, 'workflows/workflows.json')).readAsStringSync(),
      'private workflow',
    );
    expect(
      File(p.join(b.home.path, 'extensions/demo/widget.js')).readAsStringSync(),
      'private extension',
    );
    expect(
      accounts.accounts[7]!.values.any((value) => value.contains('private')),
      isFalse,
      reason: 'automation contents are sealed, not clear account metadata',
    );
    b.sync.detach();
    await a.sync.suspendForSignOut();
    final saved = Map<String, String>.of(accounts.accounts[7]!);
    await a.sync.forgetAccount();
    for (final name in ['workflows', 'extensions']) {
      await Directory(p.join(a.home.path, name)).delete(recursive: true);
    }
    expect(
      File(p.join(a.home.path, 'sync/server-7/prefs.json')).existsSync(),
      isFalse,
    );
    await a.sync.syncNow();
    expect(accounts.accounts[7], saved);

    accounts.uid = 8;
    a.sync.configure(preferences: source);
    await a.sync.attach(uid: 8);
    await a.sync.syncNow();
    expect(workflow.existsSync(), isFalse);
    expect(extension.existsSync(), isFalse);
    expect(accounts.accounts[7], saved);
    await a.sync.suspendForSignOut();
    await a.sync.forgetAccount();

    accounts.uid = 7;
    a.sync.configure(preferences: source);
    await a.sync.attach(uid: 7);
    await a.sync.syncNow();
    expect(workflow.readAsStringSync(), 'private workflow');
    expect(extension.readAsStringSync(), 'private extension');
    expect(accounts.accounts[7], saved);
    a.sync.detach();
  });

  test('nothing travels until there is an AppFlowy password', () async {
    final a = computer('a', password: null);
    await a.sync.attach(uid: 7);
    expect(a.sync.phase, ServerSettingsPhase.notSetUp);
    expect(server.values, isEmpty);

    // Chosen later, it seals the account's settings.
    a.passwords.value = _passphrase;
    await a.sync.setUp();
    expect(a.sync.phase, ServerSettingsPhase.idle);
    expect(server.values, isNotEmpty);
    a.sync.detach();
  });

  test('settings and keys follow the account, sealed', () async {
    final a = computer('a');
    final b = computer('b', password: null);
    a.prefs.values.addAll({
      'theme': 'dark',
      'cred:connection:google': 'a refresh token',
    });
    // The AppFlowy password seals it without anything being asked.
    await a.sync.attach(uid: 7);
    await a.sync.syncNow();
    expect(a.sync.phase, ServerSettingsPhase.idle);

    for (final value in server.values.values) {
      expect(value, isNot(contains('dark')));
      expect(value, isNot(contains('refresh token')));
    }

    await b.sync.attach(uid: 7);
    expect(b.sync.phase, ServerSettingsPhase.locked);
    expect(b.sync.passwordChangedElsewhere, isFalse);
    await expectLater(
      b.sync.unlock('not the passphrase'),
      throwsA(isA<SyncError>()),
    );
    await b.sync.unlock(_passphrase);
    expect(b.passwords.adopted, [_passphrase]);
    await b.sync.syncNow();
    expect(b.prefs.values['theme'], 'dark');
    expect(b.prefs.values['cred:connection:google'], 'a refresh token');

    b.prefs.values['theme'] = 'light';
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(a.prefs.values['theme'], 'light');

    a.sync.detach();
    b.sync.detach();
  });

  test('keys taken off the server stay on each computer', () async {
    final a = computer('a');
    final b = computer('b');
    a.prefs.values['cred:mail:inbox'] = 'mail password';
    await a.sync.attach(uid: 7);
    await b.sync.attach(uid: 7);
    expect(b.sync.phase, isNot(ServerSettingsPhase.locked));
    await b.sync.syncNow();
    expect(b.prefs.values['cred:mail:inbox'], 'mail password');

    await a.sync.setSyncCredentials(false);
    final key = a.keys.keys.values.single;
    final document = key.openText(
      server.values[ServerSettingsSync.settingsValueKey]!,
      context: 'server-settings',
    );
    expect(document, isNot(contains('cred:')));

    await b.sync.syncNow();
    expect(b.sync.credentialsSynced, isFalse);
    expect(b.prefs.values['cred:mail:inbox'], 'mail password');
    b.prefs.values['cred:mail:inbox'] = 'changed on B';
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(a.prefs.values['cred:mail:inbox'], 'mail password');

    a.sync.detach();
    b.sync.detach();
  });

  test('a write from another computer in between is not lost', () async {
    final a = computer('a');
    final b = computer('b');
    await a.sync.attach(uid: 7);
    await b.sync.attach(uid: 7);
    await a.sync.syncNow();
    await b.sync.syncNow();

    // B's round runs while A is between reading and writing.
    a.prefs.values['font'] = 'Inter';
    b.prefs.values['theme'] = 'sepia';
    server.beforeNextWrite = () => b.sync.syncNow();
    await a.sync.syncNow();
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(a.prefs.values, {'font': 'Inter', 'theme': 'sepia'});
    expect(b.prefs.values, {'font': 'Inter', 'theme': 'sepia'});

    a.sync.detach();
    b.sync.detach();
  });

  test('a new AppFlowy password seals the settings again; the others ask once',
      () async {
    final a = computer('a');
    final b = computer('b');
    a.prefs.values['theme'] = 'dark';
    await a.sync.attach(uid: 7);
    await b.sync.attach(uid: 7);
    await b.sync.syncNow();
    expect(b.prefs.values['theme'], 'dark');

    a.passwords.value = 'a brand new password';
    await a.sync.resealWithAppPassword();
    expect(a.sync.phase, ServerSettingsPhase.idle);

    // B still holds the old key: it stops rather than write with it.
    b.prefs.values['theme'] = 'light';
    await b.sync.syncNow();
    expect(b.sync.phase, ServerSettingsPhase.locked);
    expect(b.sync.passwordChangedElsewhere, isTrue);
    await b.sync.unlock('a brand new password');
    expect(b.passwords.value, 'a brand new password');
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(a.prefs.values['theme'], 'light');

    a.sync.detach();
    b.sync.detach();
  });
}

class _MemoryStorage implements KeyValueStorage {
  final Map<String, String> values = {};

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

class _FakePasswords implements AppPasswordSource {
  _FakePasswords(this.value);

  String? value;
  final List<String> adopted = [];

  @override
  Future<String?> current() async => value;

  @override
  Future<void> adopt(String password) async {
    adopted.add(password);
    value = password;
  }
}

class _Computer {
  _Computer(
    Directory root,
    String name,
    CloudUserValues server, {
    required String? password,
  })  : home = Directory(p.join(root.path, name))..createSync(),
        passwords = _FakePasswords(password) {
    sync = ServerSettingsSync(
      values: server,
      keys: keys,
      passwords: passwords,
      storage: _MemoryStorage(),
      home: () async => home,
      vaultIterations: 1000,
      interval: const Duration(hours: 1),
    )..configure(preferences: prefs);
  }

  final Directory home;
  final _FakePasswords passwords;
  final MemoryKeyKeeper keys = MemoryKeyKeeper();
  final _MemoryPreferences prefs = _MemoryPreferences();
  late final ServerSettingsSync sync;
}

class _Server implements CloudUserValues {
  final Map<String, String> values = {};
  Future<void> Function()? beforeNextWrite;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    final interloper = beforeNextWrite;
    if (interloper != null && key == ServerSettingsSync.settingsValueKey) {
      beforeNextWrite = null;
      await interloper();
    }
    values[key] = value;
  }
}

class _AutomationPreferences implements SyncedPreferencesSource {
  _AutomationPreferences(Directory root)
      : files = SyncedAutomationFiles(dataPath: () async => root.path);
  final SyncedAutomationFiles files;
  @override
  Set<String> get unreadable => const {};
  @override
  bool handles(String key) => isAutomationFileSyncKey(key);
  @override
  Future<Map<String, String>> read() => files.read();
  @override
  Future<void> apply(Map<String, String?> changes) async {
    await files.apply(changes);
  }
}

class _AccountServer implements CloudUserValues {
  int uid = 7;
  final Map<int, Map<String, String>> accounts = {};
  Map<String, String> get values => accounts.putIfAbsent(uid, () => {});
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _MemoryPreferences implements SyncedPreferencesSource {
  final Map<String, String> values = {};

  @override
  Set<String> unreadable = {};

  @override
  bool handles(String key) => true;

  @override
  Future<Map<String, String>> read() async => Map.of(values);

  @override
  Future<void> apply(Map<String, String?> changes) async {
    changes.forEach((key, value) {
      if (value == null) {
        values.remove(key);
      } else {
        values[key] = value;
      }
    });
  }
}
