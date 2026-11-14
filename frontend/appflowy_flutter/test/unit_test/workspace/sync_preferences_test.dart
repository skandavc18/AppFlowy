import 'dart:convert';
import 'dart:io';

import 'package:appflowy/user/application/user_settings_service.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/sync/app_synced_preferences.dart';
import 'package:appflowy/workspace/application/sync/sync_preferences.dart';
import 'package:appflowy/workspace/application/sync/synced_automation_files.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:protobuf/protobuf.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('settings changed here', () {
    test('new, changed and removed settings are seen, and nothing else', () {
      final index = SyncPreferencesIndex({
        'same':
            const SyncPreferenceRecord(key: 'same', value: '1', modified: 5),
        'changed': const SyncPreferenceRecord(
          key: 'changed',
          value: 'old',
          modified: 5,
        ),
        'gone':
            const SyncPreferenceRecord(key: 'gone', value: 'x', modified: 5),
        'elsewhere': const SyncPreferenceRecord(
          key: 'elsewhere',
          value: 'kept',
          modified: 5,
        ),
      });
      final found = scanSyncedPreferences(
        current: {'same': '1', 'changed': 'new', 'added': 'a'},
        index: index,
        handles: (key) => key != 'elsewhere',
        now: 100,
      );
      expect(
        {for (final record in found) record.key: record.value},
        {'changed': 'new', 'added': 'a', 'gone': null},
      );
    });

    test('a change is stamped after what it replaced, whatever the clock', () {
      final index = SyncPreferenceRecord(
        key: 'theme',
        value: 'dark',
        // Made on a computer whose clock is ahead.
        modified: DateTime.utc(2030).millisecondsSinceEpoch,
      );
      final found = scanSyncedPreferences(
        current: {'theme': 'light'},
        index: SyncPreferencesIndex({'theme': index}),
        handles: (_) => true,
        now: DateTime.utc(2026).millisecondsSinceEpoch,
      ).single;
      expect(found.isLaterThan(index), isTrue);
    });
  });

  group('settings from another computer', () {
    late _MemorySource source;

    setUp(() => source = _MemorySource());

    test('a setting never synced here takes the folder value', () async {
      source.values['theme'] = 'mine';
      final index = SyncPreferencesIndex();
      final current = await source.read();
      final changed = await applyRemotePreferences(
        source: source,
        index: index,
        records: const [
          SyncPreferenceRecord(key: 'theme', value: 'theirs', modified: 1),
        ],
        current: current,
      );
      expect(changed, 1);
      expect(source.values['theme'], 'theirs');
      expect(current['theme'], 'theirs');
      expect(index.entries['theme']!.value, 'theirs');
    });

    test('a change here not sent yet stays, and goes out after theirs',
        () async {
      source.values['theme'] = 'changed here';
      final index = SyncPreferencesIndex({
        'theme': const SyncPreferenceRecord(
          key: 'theme',
          value: 'synced',
          modified: 1,
        ),
      });
      const theirs = SyncPreferenceRecord(
        key: 'theme',
        value: 'theirs',
        modified: 50,
      );
      await applyRemotePreferences(
        source: source,
        index: index,
        records: const [theirs],
        current: await source.read(),
      );
      expect(source.values['theme'], 'changed here');
      final outgoing = scanSyncedPreferences(
        current: await source.read(),
        index: index,
        handles: source.handles,
        now: 10,
      ).single;
      expect(outgoing.value, 'changed here');
      expect(outgoing.isLaterThan(theirs), isTrue);
    });

    test('an older version changes nothing; the latest of a batch wins',
        () async {
      source.values['theme'] = 'synced';
      final index = SyncPreferencesIndex({
        'theme': const SyncPreferenceRecord(
          key: 'theme',
          value: 'synced',
          modified: 10,
        ),
      });
      var changed = await applyRemotePreferences(
        source: source,
        index: index,
        records: const [
          SyncPreferenceRecord(key: 'theme', value: 'older', modified: 5),
        ],
        current: await source.read(),
      );
      expect(changed, 0);
      expect(source.values['theme'], 'synced');

      changed = await applyRemotePreferences(
        source: source,
        index: index,
        records: const [
          SyncPreferenceRecord(key: 'theme', value: 'first', modified: 20),
          SyncPreferenceRecord(key: 'theme', value: 'second', modified: 30),
          SyncPreferenceRecord(key: 'font', modified: 30),
        ],
        current: await source.read(),
      );
      expect(changed, 1);
      expect(source.values['theme'], 'second');
      expect(source.applied, 1, reason: 'one write for the whole batch');
    });

    test('a setting for another kind of computer is carried, not applied',
        () async {
      final index = SyncPreferencesIndex();
      await applyRemotePreferences(
        source: source,
        index: index,
        records: const [
          SyncPreferenceRecord(
            key: 'shortcuts.macos',
            value: 'mac keys',
            modified: 3,
          ),
        ],
        current: await source.read(),
      );
      expect(source.values, isEmpty);
      expect(index.entries['shortcuts.macos']!.value, 'mac keys');
    });

    test('the record of what was synced reads back as it was written',
        () async {
      final folder = await Directory.systemTemp.createTemp('sync_prefs');
      addTearDown(() => folder.delete(recursive: true));
      final file = File(p.join(folder.path, 'prefs.json'));
      final index = SyncPreferencesIndex()
        ..note(const SyncPreferenceRecord(key: 'a', value: '1', modified: 2))
        ..note(const SyncPreferenceRecord(key: 'b', modified: 3));
      await index.save(file);
      final read = await SyncPreferencesIndex.load(file);
      expect(read.entries, index.entries);
    });
  });

  group("the application's settings", () {
    late Directory data;

    setUp(() async {
      data = await Directory.systemTemp.createTemp('synced_settings');
    });
    tearDown(() => data.delete(recursive: true));

    test('account sync includes automation files and awaits live reloads',
        () async {
      SharedPreferences.setMockInitialValues({});
      final service = _FakeSettingsService();
      final key = automationFileSyncKey('extensions/demo/widget.js');
      final file = File(p.join(data.path, 'extensions/demo/widget.js'))
        ..createSync(recursive: true)
        ..writeAsStringSync('private extension');
      final folderSource = AppSyncedPreferences(
        dataPath: () async => data.path,
        workspaceId: () => 'workspace-1',
        settingsService: service,
        credentials: _FakeCredentials(),
      );
      expect(folderSource.handles(key), isFalse);
      expect((await folderSource.read()).containsKey(key), isFalse);
      var reloaded = false;
      final account = AppSyncedPreferences(
        dataPath: () async => data.path,
        workspaceId: () => 'workspace-1',
        settingsService: service,
        credentials: _FakeCredentials(),
        syncAutomationFiles: true,
        onApplied: (keys) async {
          expect(keys, contains(key));
          await Future<void>.delayed(Duration.zero);
          reloaded = true;
        },
      );
      expect(account.handles(key), isTrue);
      expect(
        decodeSyncedValue((await account.read())[key]),
        base64Encode(utf8.encode('private extension')),
      );
      await account.apply({
        key: encodeSyncedValue(base64Encode(utf8.encode('new extension'))),
      });
      expect(file.readAsStringSync(), 'new extension');
      expect(reloaded, isTrue);
      await account.apply({key: null});
      expect(file.existsSync(), isFalse);
    });

    test('only what is the person choice everywhere is synced', () {
      final source = AppSyncedPreferences(
        dataPath: () async => data.path,
        workspaceId: () => 'workspace-1',
      );
      for (final key in [
        'pref:kDocumentAppearanceFontSize',
        'pref:appflowy_extension_theme',
        'pref:appflowy_home_layout_workspace-1',
        'pref:appflowy_local_page_appflowy-page-home-workspace-1',
        'pref:appflowy_custom_ai_providers',
        'pref:windowSize',
        'pref:scaleFactor',
        'pref:textScaleFactor',
        'pref:enableKineticScrolling',
        'pref:featureFlag',
        'pref:appflowy_home_weather',
        'pref:expandedFolders',
        'pref:appflowy_workspace_encryption',
        'appearance.theme',
        'datetime.date_format',
        'datetime.timezone',
        'notifications.enabled',
        backupPolicySyncKey,
        shortcutsSyncKey(),
      ]) {
        expect(source.handles(key), isTrue, reason: key);
      }
      for (final key in [
        'pref:io.appflowy.appflowy_flutter.path_location',
        'pref:appflowy_provider_connections',
        'pref:appflowy_provider_secret_google|me',
        'pref:appflowy_ai_provider_openai',
        'pref:appflowy_sync_binding',
        'pref:appflowy_sync_device',
        'pref:appflowy_backup_policy',
        'pref:appflowy_backup_ledger',
        'pref:appflowy_geocode_cache',
        'pref:appflowy_home_layout_workspace-2',
        'pref:appflowy_local_page_appflowy-page-home-workspace-2',
        'pref:appflowy_local_page_appflowy-page-home',
        'pref:kCloudType',
        'pref:kAppFlowyCloudBaseURL',
        // Credentials travel as credentials, never as plain settings.
        'pref:appflowy_oauth_app_google',
        'pref:appflowy_maps_google_api_key',
        'pref:appflowy_mcp_servers',
        'pref:appflowy_office_document_server',
        'shortcuts.${Platform.isMacOS ? 'desktop' : 'macos'}',
        'appearance.menu_offset',
      ]) {
        expect(source.handles(key), isFalse, reason: key);
      }
    });

    test(
        'accounts, passwords and keys travel only from a computer that '
        'can keep them', () {
      for (final canKeep in [true, false]) {
        final source = AppSyncedPreferences(
          dataPath: () async => data.path,
          workspaceId: () => 'workspace-1',
          credentials: _FakeCredentials()..canKeep = canKeep,
        );
        for (final key in [
          'cred:pref:appflowy_oauth_app_google',
          'cred:pref:appflowy_maps_google_api_key',
          'cred:pref:appflowy_mcp_servers',
          'cred:pref:appflowy_connected_mail_accounts',
          'cred:pref:appflowy_office_document_server',
          'cred:connection:google|me',
          'cred:secret:appflowy_ai_provider_openai',
          'cred:secret:appflowy-backup-passphrase',
          'cred:mail:account-1',
        ]) {
          expect(source.handles(key), canKeep, reason: key);
        }
        for (final key in [
          'cred:secret:appflowy-sync-key-vault',
          'cred:secret:something_else',
          'cred:pref:windowSize',
        ]) {
          expect(source.handles(key), isFalse, reason: key);
        }
      }
    });

    test(
        'accounts, passwords and keys are read and put through their '
        'holders', () async {
      SharedPreferences.setMockInitialValues({
        'appflowy_custom_ai_providers': jsonEncode([
          {'id': 'openai', 'name': 'OpenAI'},
        ]),
        'appflowy_connected_mail_accounts': jsonEncode([
          {'id': 'mail-1'},
        ]),
        'appflowy_maps_google_api_key': 'maps-key',
      });
      final credentials = _FakeCredentials()
        ..canKeep = true
        ..connected.add(
          (
            const ProviderConnection(
              id: 'google|me',
              service: ProviderService.googleDrive,
              accountLabel: 'me@example.com',
              accountId: 'me',
            ),
            const ProviderCredentials(accessToken: 'a', refreshToken: 'r'),
          ),
        )
        ..connected.add(
          (
            const ProviderConnection(
              id: 'box|me',
              service: ProviderService.box,
              accountLabel: 'me',
            ),
            null,
          ),
        )
        ..secrets['appflowy_ai_provider_openai'] = 'sk-test'
        ..mail['mail-1'] = 'mail password';
      final source = AppSyncedPreferences(
        dataPath: () async => data.path,
        workspaceId: () => 'workspace-1',
        settingsService: _FakeSettingsService(),
        credentials: credentials,
      );

      final read = await source.read();
      expect(
        decodeSyncedValue(read['cred:pref:appflowy_maps_google_api_key']),
        'maps-key',
      );
      expect(read.containsKey('pref:appflowy_maps_google_api_key'), isFalse);
      expect(
        decodeSyncedValue(read['cred:secret:appflowy_ai_provider_openai']),
        'sk-test',
      );
      expect(decodeSyncedValue(read['cred:mail:mail-1']), 'mail password');
      expect(read.containsKey('cred:connection:google|me'), isTrue);
      // A sign in that could not be read is never taken for removed.
      expect(read.containsKey('cred:connection:box|me'), isFalse);
      expect(source.unreadable, {'cred:connection:box|me'});

      final travelled = read['cred:connection:google|me']!;
      await source.apply({
        'cred:connection:google|me': null,
        'cred:connection:google|you': travelled.replaceAll(
          'google|me',
          'google|you',
        ),
        'cred:secret:appflowy_ai_provider_openai': null,
        'cred:mail:mail-1': encodeSyncedValue('new password'),
        'cred:pref:appflowy_maps_google_api_key': encodeSyncedValue('k2'),
      });
      expect(credentials.removed, ['google|me']);
      expect(credentials.put.single.$1.id, 'google|you');
      expect(credentials.put.single.$2.refreshToken, 'r');
      expect(
        credentials.secrets.containsKey('appflowy_ai_provider_openai'),
        isFalse,
      );
      expect(credentials.mail['mail-1'], 'new password');
      expect(
        (await SharedPreferences.getInstance())
            .getString('appflowy_maps_google_api_key'),
        'k2',
      );
      expect(credentials.reloaded, contains('appflowy_maps_google_api_key'));
    });

    test('values keep their type on the way through', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      for (final value in <Object>[
        true,
        42,
        16.0,
        'text',
        ['a', 'b'],
      ]) {
        final encoded = encodeSyncedValue(value)!;
        expect(await writeSyncedValue(preferences, 'key', encoded), isTrue);
        expect(preferences.get('key'), value);
        expect(encodeSyncedValue(preferences.get('key')), encoded);
      }
      expect(await writeSyncedValue(preferences, 'key', null), isTrue);
      expect(preferences.containsKey('key'), isFalse);
      expect(
        await writeSyncedValue(preferences, 'key', '{"x":1}'),
        isFalse,
        reason: 'nothing unreadable is written',
      );
    });

    test('preferences, backend settings and shortcuts are read and put',
        () async {
      SharedPreferences.setMockInitialValues({
        'kDocumentAppearanceFontSize': 18.0,
        'io.appflowy.appflowy_flutter.path_location': '/data/here',
        'appflowy_home_layout_workspace-1': '{"rows":[]}',
      });
      final service = _FakeSettingsService();
      final arrived = <String>{};
      final source = AppSyncedPreferences(
        dataPath: () async => data.path,
        workspaceId: () => 'workspace-1',
        settingsService: service,
        onApplied: arrived.addAll,
      );
      final shortcuts = File(p.join(data.path, 'shortcuts', 'shortcuts.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"commandShortcuts":[]}');

      final read = await source.read();
      expect(
        read.containsKey('pref:io.appflowy.appflowy_flutter.path_location'),
        isFalse,
      );
      expect(
        decodeSyncedValue(read['pref:kDocumentAppearanceFontSize']),
        18.0,
      );
      expect(decodeSyncedValue(read['appearance.theme']), 'Default');
      expect(
        decodeSyncedValue(read[shortcutsSyncKey()]),
        '{"commandShortcuts":[]}',
      );

      await source.apply({
        'pref:kDocumentAppearanceFontSize': encodeSyncedValue(14.0),
        'pref:appflowy_home_layout_workspace-1': null,
        'pref:io.appflowy.appflowy_flutter.path_location':
            encodeSyncedValue('/data/elsewhere'),
        'appearance.theme': encodeSyncedValue('Dandelion'),
        'appearance.locale': encodeSyncedValue('de_DE'),
        'datetime.time_format':
            encodeSyncedValue(UserTimeFormatPB.TwelveHour.value),
        'notifications.enabled': encodeSyncedValue(false),
        shortcutsSyncKey(): encodeSyncedValue('{"commandShortcuts":[1]}'),
      });

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getDouble('kDocumentAppearanceFontSize'), 14.0);
      expect(
        preferences.containsKey('appflowy_home_layout_workspace-1'),
        isFalse,
      );
      expect(
        preferences.getString('io.appflowy.appflowy_flutter.path_location'),
        '/data/here',
        reason: 'a device setting is never written',
      );
      expect(service.appearance.theme, 'Dandelion');
      expect(service.appearance.locale.languageCode, 'de');
      expect(service.appearance.locale.countryCode, 'DE');
      expect(service.appearance.resetToDefault, isFalse);
      expect(service.dateTime.timeFormat, UserTimeFormatPB.TwelveHour);
      expect(service.notifications.notificationsEnabled, isFalse);
      expect(shortcuts.readAsStringSync(), '{"commandShortcuts":[1]}');
      expect(arrived, {
        'pref:kDocumentAppearanceFontSize',
        'pref:appflowy_home_layout_workspace-1',
        shortcutsSyncKey(),
      });

      // Shortcuts put back to their defaults elsewhere go here too.
      await source.apply({shortcutsSyncKey(): null});
      expect(shortcuts.existsSync(), isFalse);
    });
  });
}

class _MemorySource implements SyncedPreferencesSource {
  @override
  Set<String> unreadable = {};

  final Map<String, String> values = {};
  int applied = 0;

  @override
  bool handles(String key) => !key.startsWith('shortcuts.macos');

  @override
  Future<Map<String, String>> read() async => Map.of(values);

  @override
  Future<void> apply(Map<String, String?> changes) async {
    applied++;
    changes.forEach((key, value) {
      if (value == null) {
        values.remove(key);
      } else {
        values[key] = value;
      }
    });
  }
}

class _FakeSettingsService extends UserSettingsBackendService {
  _FakeSettingsService();

  final AppearanceSettingsPB appearance = AppearanceSettingsPB(
    theme: 'Default',
    resetToDefault: true,
  );
  final DateTimeSettingsPB dateTime = DateTimeSettingsPB();
  final NotificationSettingsPB notifications =
      NotificationSettingsPB(notificationsEnabled: true);

  @override
  Future<AppearanceSettingsPB> getAppearanceSetting() async =>
      appearance.deepCopy();

  @override
  Future<FlowyResult<void, FlowyError>> setAppearanceSetting(
    AppearanceSettingsPB setting,
  ) async {
    appearance
      ..clear()
      ..mergeFromMessage(setting);
    return FlowyResult.success(null);
  }

  @override
  Future<DateTimeSettingsPB> getDateTimeSettings() async => dateTime.deepCopy();

  @override
  Future<FlowyResult<void, FlowyError>> setDateTimeSettings(
    DateTimeSettingsPB settings,
  ) async {
    dateTime
      ..clear()
      ..mergeFromMessage(settings);
    return FlowyResult.success(null);
  }

  @override
  Future<NotificationSettingsPB> getNotificationSettings() async =>
      notifications.deepCopy();

  @override
  Future<FlowyResult<void, FlowyError>> setNotificationSettings(
    NotificationSettingsPB settings,
  ) async {
    notifications
      ..clear()
      ..mergeFromMessage(settings);
    return FlowyResult.success(null);
  }
}

class _FakeCredentials implements CredentialHolders {
  @override
  bool canKeep = false;

  final List<(ProviderConnection, ProviderCredentials?)> connected = [];
  final List<(ProviderConnection, ProviderCredentials)> put = [];
  final List<String> removed = [];
  final Map<String, String> secrets = {};
  final Map<String, String> mail = {};
  final Set<String> reloaded = {};

  @override
  Future<List<(ProviderConnection, ProviderCredentials?)>>
      connections() async => connected;

  @override
  Future<void> putConnection(
    ProviderConnection connection,
    ProviderCredentials credentials,
  ) async =>
      put.add((connection, credentials));

  @override
  Future<void> removeConnection(String id) async => removed.add(id);

  @override
  Future<String?> readSecret(String id) async => secrets[id];

  @override
  Future<void> writeSecret(String id, String? value) async =>
      value == null ? secrets.remove(id) : secrets[id] = value;

  @override
  Future<String?> readMailPassword(String accountId) async => mail[accountId];

  @override
  Future<void> writeMailPassword(String accountId, String? value) async =>
      value == null ? mail.remove(accountId) : mail[accountId] = value;

  @override
  Future<Map<String, Object?>?> backupPolicy() async => null;

  @override
  Future<void> adoptBackupPolicy(Map<String, Object?> policy) async {}

  @override
  Future<void> reloadAfter(Set<String> names) async => reloaded.addAll(names);
}
