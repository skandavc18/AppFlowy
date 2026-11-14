// The settings of this application that follow the workspace, and the
// accounts, passwords and keys that go with them.
//
// Settings are synced by name: appearance, language, date and time, the
// editor, notifications, keyboard shortcuts, extensions, AI, backup, feature
// flags, the window and display size, the sidebar, Home and the like.
// Accounts, passwords and keys travel too — sealed with the sync passphrase
// like everything in the folder, only to computers that can keep them in a
// keyring, and they can be taken out of the folder on their own. What stays on
// each computer is what only makes sense there: where its data is kept, which
// server it signs in to, the record of its own backups and syncs, and caches.
// A setting not named here is never sent, so one added later stays local until
// it is added.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/ai/providers/ai_provider_store.dart';
import 'package:appflowy/ai/tools/mcp_server_config.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:appflowy/user/application/user_settings_service.dart';
import 'package:appflowy/workspace/application/backup/backup_settings.dart';
import 'package:appflowy/workspace/application/collections/email/mail_secret_store.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_config.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:appflowy/workspace/application/sync/sync_preferences.dart';
import 'package:appflowy/workspace/application/sync/sync_vault.dart';
import 'package:appflowy/workspace/application/sync/synced_automation_files.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Preferences kept in shared preferences that are synced, by name.
const Set<String> syncedPreferenceNames = {
  KVKeys.kDocumentAppearanceFontSize,
  KVKeys.kDocumentAppearanceFontFamily,
  KVKeys.kDocumentAppearanceDefaultTextDirection,
  KVKeys.kDocumentAppearanceCursorColor,
  KVKeys.kDocumentAppearanceSelectionColor,
  KVKeys.kDocumentAppearanceWidth,
  KVKeys.showNotificationIcon,
  KVKeys.compactModeIds,
  KVKeys.spaceOrder,
  'appflowy_extension_theme',
  'appflowy_extensions_disabled',
  'appflowy_dart_extensions_disabled',
  'appflowy_default_icon_style',
  'appflowy_cover_appearance',
  'appflowy_gallery_card_size',
  'appflowy_favorites_gallery',
  'appflowy_library_gallery',
  'appflowy_recents_gallery',
  'appflowy_google_calendar_selection',
  'appflowy_grammar_check_enabled',
  'appflowy_spell_check_enabled',
  'appflowy_spell_check_dictionary',
  'appflowy_page_versions_policy',
  'appflowy_ai_skills',
  'appflowy_ai_skills_disabled',
  'appflowy_ai_tool_permissions',
  'appflowy_ai_tool_ask_for_reads',
  'appflowy_custom_ai_providers',
  'appflowy_custom_ai_selected_model',
  'io.appflowy.appflowy_flutter.automatic_view_cover_enabled',
  'io.appflowy.appflowy_flutter.automatic_view_cover_theme',
  'io.appflowy.appflowy_flutter.automatic_view_cover_set',
  KVKeys.featureFlag,
  KVKeys.enableKineticScrolling,
  KVKeys.textScaleFactor,
  KVKeys.scaleFactor,
  // Read when the window opens, so they take effect at the next start.
  KVKeys.windowSize,
  KVKeys.windowPosition,
  KVKeys.windowMaximized,
  KVKeys.expandedViews,
  KVKeys.expandedFolders,
  KVKeys.lastOpenedSpace,
  KVKeys.lastOpenedSpaceId,
  KVKeys.recentIcons,
  'appflowy_home_weather',
  // A salt and a verifier, so pages encrypted on one computer open on another
  // with the same passphrase. The passphrase itself is never written down.
  'appflowy_workspace_encryption',
};

/// Preferences that are credentials, or name them: they travel and are taken
/// out of the folder with the accounts, passwords and keys.
const Set<String> credentialPreferenceNames = {
  'appflowy_maps_google_api_key',
  'appflowy_mcp_servers',
  'appflowy_connected_mail_accounts',
  'appflowy_office_document_server',
};

/// Credential preferences by the start of their name: the app identities
/// Google, Microsoft and Box sign in through.
const List<String> credentialPreferencePrefixes = [
  OAuthAppRegistry.storageKeyPrefix,
];

/// How each kind of account, password or key travels.
const String credentialPreferenceSyncPrefix = '${credentialKeyPrefix}pref:';
const String connectionSyncPrefix = '${credentialKeyPrefix}connection:';
const String secretSyncPrefix = '${credentialKeyPrefix}secret:';
const String mailPasswordSyncPrefix = '${credentialKeyPrefix}mail:';

/// The backup settings, as [BackupSettings.syncedPolicy] gives them.
const String backupPolicySyncKey = 'backup.policy';

bool isCredentialPreference(String name) =>
    credentialPreferenceNames.contains(name) ||
    credentialPreferencePrefixes.any(name.startsWith);

/// Whether a secret of the provider store travels: AI keys and the backup
/// passphrase. Never the key the folder is sealed with.
bool isSyncedSecretId(String id) =>
    !id.startsWith(SecretStoreKeyKeeper.idPrefix) &&
    (id.startsWith(CustomAIProviderStore.secretPrefix) ||
        id == BackupSettings.passphraseSecretId);

/// Preferences kept per workspace, named after it: Home's layout, and the
/// covers of Home, Recents, Favorites and Library. Only the synced
/// workspace's travel; another workspace's stay on this computer.
const List<String> perWorkspacePreferencePrefixes = [
  'appflowy_home_layout_',
  'appflowy_local_page_',
];

/// The key a shared preference travels under.
String preferenceSyncKey(String name) => 'pref:$name';

/// Keyboard shortcuts are written for a kind of keyboard: Command on a Mac,
/// Control everywhere else. They travel only between computers of one kind.
String shortcutsSyncKey({bool? macOS}) =>
    'shortcuts.${(macOS ?? Platform.isMacOS) ? 'macos' : 'desktop'}';

/// Settings kept by the backend, by the name each travels under.
const Set<String> backendSettingKeys = {
  'appearance.theme',
  'appearance.theme_mode',
  'appearance.font',
  'appearance.monospace_font',
  'appearance.locale',
  'appearance.layout_direction',
  'appearance.text_direction',
  'appearance.rtl_toolbar_items',
  'appearance.cursor_color',
  'appearance.selection_color',
  'datetime.date_format',
  'datetime.time_format',
  'datetime.timezone',
  'notifications.enabled',
};

/// The application's synced settings.
///
/// The backend's appearance, date and notification settings are put through
/// [writeAppearance], [writeDateTime] and [writeNotifications] when given, so
/// whatever holds them on screen takes them and is not left to save its old
/// copy over them later. [onApplied] hears which of the other settings arrived.
class AppSyncedPreferences implements SyncedPreferencesSource {
  AppSyncedPreferences({
    required this.dataPath,
    required this.workspaceId,
    this.writeAppearance,
    this.writeDateTime,
    this.writeNotifications,
    this.onApplied,
    bool syncAutomationFiles = false,
    UserSettingsBackendService settingsService =
        const UserSettingsBackendService(),
    CredentialHolders? credentials,
  })  : _service = settingsService,
        _automationFiles = syncAutomationFiles
            ? SyncedAutomationFiles(dataPath: dataPath)
            : null,
        _credentials = credentials ?? AppCredentialHolders();

  final Future<String> Function() dataPath;

  /// The workspace being synced, whose own preferences travel with it.
  final String? Function() workspaceId;

  final Future<void> Function(AppearanceSettingsPB settings)? writeAppearance;
  final Future<void> Function(DateTimeSettingsPB settings)? writeDateTime;
  final Future<void> Function(NotificationSettingsPB settings)?
      writeNotifications;
  final FutureOr<void> Function(Set<String> keys)? onApplied;
  final SyncedAutomationFiles? _automationFiles;
  final UserSettingsBackendService _service;
  final CredentialHolders _credentials;

  Set<String> _unreadable = const {};

  @override
  Set<String> get unreadable => _unreadable;

  bool isSyncedPreference(String name) {
    if (isCredentialPreference(name)) {
      return false;
    }
    if (syncedPreferenceNames.contains(name)) {
      return true;
    }
    final workspace = workspaceId();
    return workspace != null &&
        workspace.isNotEmpty &&
        perWorkspacePreferencePrefixes.any(name.startsWith) &&
        (name.endsWith('_$workspace') || name.endsWith('-$workspace'));
  }

  @override
  bool handles(String key) {
    if (_automationFiles != null && isAutomationFileSyncKey(key)) {
      return true;
    }
    if (key.startsWith('pref:')) {
      return isSyncedPreference(key.substring(5));
    }
    if (isCredentialKey(key)) {
      return _credentials.canKeep && _isSyncedCredential(key);
    }
    return backendSettingKeys.contains(key) ||
        key == shortcutsSyncKey() ||
        key == backupPolicySyncKey;
  }

  static bool _isSyncedCredential(String key) {
    if (key.startsWith(credentialPreferenceSyncPrefix)) {
      return isCredentialPreference(
        key.substring(credentialPreferenceSyncPrefix.length),
      );
    }
    if (key.startsWith(secretSyncPrefix)) {
      return isSyncedSecretId(key.substring(secretSyncPrefix.length));
    }
    return key.startsWith(connectionSyncPrefix) ||
        key.startsWith(mailPasswordSyncPrefix);
  }

  @override
  Future<Map<String, String>> read() async {
    final values = <String, String>{};
    final unreadable = <String>{};
    final keepsCredentials = _credentials.canKeep;

    final preferences = await SharedPreferences.getInstance();
    for (final name in preferences.getKeys()) {
      final String key;
      if (isSyncedPreference(name)) {
        key = preferenceSyncKey(name);
      } else if (keepsCredentials && isCredentialPreference(name)) {
        key = '$credentialPreferenceSyncPrefix$name';
      } else {
        continue;
      }
      final encoded = encodeSyncedValue(preferences.get(name));
      if (encoded != null) {
        values[key] = encoded;
      }
    }

    final backup = await _credentials.backupPolicy();
    if (backup != null) {
      values[backupPolicySyncKey] = _string(jsonEncode(backup));
    }

    if (keepsCredentials) {
      for (final (connection, credentials)
          in await _credentials.connections()) {
        final key = '$connectionSyncPrefix${connection.id}';
        if (credentials == null) {
          unreadable.add(key);
          continue;
        }
        values[key] = _string(
          jsonEncode({
            'connection': connection.toJson(),
            'credentials': jsonDecode(credentials.encode()),
          }),
        );
      }
      for (final id in [
        BackupSettings.passphraseSecretId,
        for (final provider in _aiProviderIds(preferences))
          '${CustomAIProviderStore.secretPrefix}$provider',
      ]) {
        final secret = await _credentials.readSecret(id);
        if (secret != null && secret.isNotEmpty) {
          values['$secretSyncPrefix$id'] = _string(secret);
        }
      }
      for (final account in _mailAccountIds(preferences)) {
        final password = await _credentials.readMailPassword(account);
        if (password != null && password.isNotEmpty) {
          values['$mailPasswordSyncPrefix$account'] = _string(password);
        }
      }
    }
    _unreadable = unreadable;

    // A failure here fails the whole read: settings left out would look
    // removed, and the removal would be sent everywhere.
    final appearance = await _service.getAppearanceSetting();
    values.addAll({
      'appearance.theme': _string(appearance.theme),
      'appearance.theme_mode': _int(appearance.themeMode.value),
      'appearance.font': _string(appearance.font),
      'appearance.monospace_font': _string(appearance.monospaceFont),
      'appearance.locale': _string(
        '${appearance.locale.languageCode}_${appearance.locale.countryCode}',
      ),
      'appearance.layout_direction': _int(appearance.layoutDirection.value),
      'appearance.text_direction': _int(appearance.textDirection.value),
      'appearance.rtl_toolbar_items': _bool(appearance.enableRtlToolbarItems),
      'appearance.cursor_color':
          _string(appearance.documentSetting.cursorColor),
      'appearance.selection_color':
          _string(appearance.documentSetting.selectionColor),
    });
    final dateTime = await _service.getDateTimeSettings();
    values['datetime.date_format'] = _int(dateTime.dateFormat.value);
    values['datetime.time_format'] = _int(dateTime.timeFormat.value);
    values['datetime.timezone'] = _string(dateTime.timezoneId);
    final notifications = await _service.getNotificationSettings();
    values['notifications.enabled'] = _bool(notifications.notificationsEnabled);

    final shortcuts = await _shortcutsFile();
    if (shortcuts.existsSync()) {
      final content = await shortcuts.readAsString();
      if (content.trim().isNotEmpty) {
        values[shortcutsSyncKey()] = _string(content);
      }
    }
    final automation = _automationFiles;
    if (automation != null) {
      for (final entry in (await automation.read()).entries) {
        values[entry.key] = _string(entry.value);
      }
    }
    return values;
  }

  @override
  Future<void> apply(Map<String, String?> changes) async {
    final applied = <String>{};
    final automationChanges = <String, String?>{};
    if (_automationFiles != null) {
      for (final entry in changes.entries) {
        if (!isAutomationFileSyncKey(entry.key)) continue;
        final value = decodeSyncedValue(entry.value);
        if (entry.value != null && value is! String) {
          throw const FormatException(
            'Synced automation contents are invalid.',
          );
        }
        automationChanges[entry.key] = value as String?;
      }
    }

    final preferences = await SharedPreferences.getInstance();
    final credentialNames = <String>{};
    for (final entry in changes.entries) {
      if (!handles(entry.key)) {
        continue;
      }
      final String name;
      if (entry.key.startsWith('pref:')) {
        name = entry.key.substring(5);
      } else if (entry.key.startsWith(credentialPreferenceSyncPrefix)) {
        name = entry.key.substring(credentialPreferenceSyncPrefix.length);
        credentialNames.add(name);
      } else {
        continue;
      }
      if (await writeSyncedValue(preferences, name, entry.value)) {
        applied.add(entry.key);
      }
    }

    await _applyBackend(changes);
    await _applyCredentials(changes);
    if (changes.containsKey(backupPolicySyncKey)) {
      final policy = decodeSyncedValue(changes[backupPolicySyncKey]);
      if (policy is String) {
        final decoded = jsonDecode(policy);
        if (decoded is Map) {
          await _credentials
              .adoptBackupPolicy(Map<String, Object?>.from(decoded));
        }
      }
    }
    await _credentials.reloadAfter({
      ...credentialNames,
      for (final key in applied)
        if (key.startsWith('pref:')) key.substring(5),
    });

    final shortcuts = shortcutsSyncKey();
    if (changes.containsKey(shortcuts)) {
      final file = await _shortcutsFile();
      final encoded = changes[shortcuts];
      final content = decodeSyncedValue(encoded);
      if (content is String) {
        await file.parent.create(recursive: true);
        final staging = File('${file.path}.sync.tmp');
        await staging.writeAsString(content, flush: true);
        await staging.rename(file.path);
        applied.add(shortcuts);
      } else if (encoded == null) {
        // Put back to the defaults on the other computer.
        if (file.existsSync()) {
          await file.delete();
        }
        applied.add(shortcuts);
      }
    }
    if (_automationFiles case final automation?) {
      applied.addAll(await automation.apply(automationChanges));
    }

    if (applied.isNotEmpty) {
      await onApplied?.call(applied);
    }
  }

  Future<void> _applyBackend(Map<String, String?> changes) async {
    Object? value(String key) => decodeSyncedValue(changes[key]);
    bool has(String prefix) => changes.entries.any(
          (entry) => entry.key.startsWith(prefix) && entry.value != null,
        );

    if (has('appearance.')) {
      final settings = await _service.getAppearanceSetting();
      if (value('appearance.theme') case final String theme) {
        settings.theme = theme;
      }
      if (value('appearance.theme_mode') case final int mode) {
        settings.themeMode = ThemeModePB.valueOf(mode) ?? settings.themeMode;
      }
      if (value('appearance.font') case final String font) {
        settings.font = font;
      }
      if (value('appearance.monospace_font') case final String font) {
        settings.monospaceFont = font;
      }
      if (value('appearance.locale') case final String locale) {
        final parts = locale.split('_');
        settings.locale = LocaleSettingsPB(
          languageCode: parts.first,
          countryCode: parts.length > 1 ? parts[1] : '',
        );
      }
      if (value('appearance.layout_direction') case final int direction) {
        settings.layoutDirection =
            LayoutDirectionPB.valueOf(direction) ?? settings.layoutDirection;
      }
      if (value('appearance.text_direction') case final int direction) {
        settings.textDirection =
            TextDirectionPB.valueOf(direction) ?? settings.textDirection;
      }
      if (value('appearance.rtl_toolbar_items') case final bool enabled) {
        settings.enableRtlToolbarItems = enabled;
      }
      if (value('appearance.cursor_color') case final String color) {
        settings.ensureDocumentSetting().cursorColor = color;
      }
      if (value('appearance.selection_color') case final String color) {
        settings.ensureDocumentSetting().selectionColor = color;
      }
      // Chosen by somebody now, not a first start's defaults.
      settings.resetToDefault = false;
      final write = writeAppearance;
      if (write != null) {
        await write(settings);
      } else {
        await _service.setAppearanceSetting(settings);
      }
    }

    if (has('datetime.')) {
      final settings = await _service.getDateTimeSettings();
      if (value('datetime.date_format') case final int format) {
        settings.dateFormat =
            UserDateFormatPB.valueOf(format) ?? settings.dateFormat;
      }
      if (value('datetime.time_format') case final int format) {
        settings.timeFormat =
            UserTimeFormatPB.valueOf(format) ?? settings.timeFormat;
      }
      if (value('datetime.timezone') case final String timezone) {
        settings.timezoneId = timezone;
      }
      final write = writeDateTime;
      if (write != null) {
        await write(settings);
      } else {
        await _service.setDateTimeSettings(settings);
      }
    }

    if (has('notifications.')) {
      final settings = await _service.getNotificationSettings();
      if (value('notifications.enabled') case final bool enabled) {
        settings.notificationsEnabled = enabled;
      }
      final write = writeNotifications;
      if (write != null) {
        await write(settings);
      } else {
        await _service.setNotificationSettings(settings);
      }
    }
  }

  Future<void> _applyCredentials(Map<String, String?> changes) async {
    for (final entry in changes.entries) {
      final key = entry.key;
      if (!isCredentialKey(key) || !handles(key)) {
        continue;
      }
      final value = decodeSyncedValue(entry.value);
      if (entry.value != null && value is! String) {
        continue;
      }
      final text = value as String?;
      if (key.startsWith(connectionSyncPrefix)) {
        final id = key.substring(connectionSyncPrefix.length);
        if (text == null) {
          await _credentials.removeConnection(id);
          continue;
        }
        final decoded = jsonDecode(text);
        final connection = decoded is Map
            ? ProviderConnection.fromJson(decoded['connection'])
            : null;
        final credentials = decoded is Map
            ? ProviderCredentials.decode(jsonEncode(decoded['credentials']))
            : null;
        if (connection == null || credentials == null || connection.id != id) {
          Log.warn('A synced account could not be read and was left alone.');
          continue;
        }
        await _credentials.putConnection(connection, credentials);
      } else if (key.startsWith(secretSyncPrefix)) {
        await _credentials.writeSecret(
          key.substring(secretSyncPrefix.length),
          text,
        );
      } else if (key.startsWith(mailPasswordSyncPrefix)) {
        await _credentials.writeMailPassword(
          key.substring(mailPasswordSyncPrefix.length),
          text,
        );
      }
    }
  }

  static Iterable<String> _aiProviderIds(SharedPreferences preferences) =>
      _idsIn(preferences.getString(CustomAIProviderStore.providersKey));

  static Iterable<String> _mailAccountIds(SharedPreferences preferences) =>
      _idsIn(preferences.getString('appflowy_connected_mail_accounts'));

  static Iterable<String> _idsIn(String? list) {
    if (list == null || list.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(list);
      return decoded is List
          ? [
              for (final entry in decoded)
                if (entry is Map && entry['id'] is String)
                  entry['id'] as String,
            ]
          : const [];
    } on FormatException {
      return const [];
    }
  }

  Future<File> _shortcutsFile() async =>
      File(p.join(await dataPath(), 'shortcuts', 'shortcuts.json'));

  static String _string(String value) => jsonEncode({'s': value});

  static String _int(int value) => jsonEncode({'i': value});

  static String _bool(bool value) => jsonEncode({'b': value});
}

/// A stored value in the form it travels in, keeping its type; null for a
/// value of a type that is never synced.
String? encodeSyncedValue(Object? value) => switch (value) {
      final bool flag => jsonEncode({'b': flag}),
      final int number => jsonEncode({'i': number}),
      final double number => jsonEncode({'d': number}),
      final String text => jsonEncode({'s': text}),
      final List<Object?> list => jsonEncode({
          'l': [for (final item in list) '$item'],
        }),
      _ => null,
    };

/// What [encoded] holds, or null for a removal or anything unreadable.
Object? decodeSyncedValue(String? encoded) {
  if (encoded == null) {
    return null;
  }
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map || decoded.length != 1) {
      return null;
    }
    final MapEntry(:key, :value) = decoded.entries.single;
    return switch (key) {
      'b' when value is bool => value,
      'i' when value is int => value,
      'd' when value is num => value.toDouble(),
      's' when value is String => value,
      'l' when value is List => [for (final item in value) '$item'],
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

/// Puts [encoded] into [preferences] as [name], or removes it when [encoded]
/// is null. False when there was nothing that could be written.
Future<bool> writeSyncedValue(
  SharedPreferences preferences,
  String name,
  String? encoded,
) async {
  if (encoded == null) {
    await preferences.remove(name);
    return true;
  }
  final value = decodeSyncedValue(encoded);
  switch (value) {
    case final bool flag:
      await preferences.setBool(name, flag);
    case final int number:
      await preferences.setInt(name, number);
    case final double number:
      await preferences.setDouble(name, number);
    case final String text:
      await preferences.setString(name, text);
    case final List<String> list:
      await preferences.setStringList(name, list);
    default:
      Log.warn('A synced setting could not be read and was left alone.');
      return false;
  }
  return true;
}

/// What holds accounts, passwords and keys on this computer.
abstract class CredentialHolders {
  /// Whether this computer can keep them between sessions. One that cannot
  /// neither sends them nor takes them.
  bool get canKeep;

  /// Every connected account, with its sign in, which is null when it could
  /// not be read.
  Future<List<(ProviderConnection, ProviderCredentials?)>> connections();

  Future<void> putConnection(
    ProviderConnection connection,
    ProviderCredentials credentials,
  );

  Future<void> removeConnection(String id);

  Future<String?> readSecret(String id);

  /// Keeps [value] as [id]; null forgets it.
  Future<void> writeSecret(String id, String? value);

  Future<String?> readMailPassword(String accountId);

  /// Keeps [value] for [accountId]; null forgets it.
  Future<void> writeMailPassword(String accountId, String? value);

  /// The backup settings as they follow the workspace.
  Future<Map<String, Object?>?> backupPolicy();

  Future<void> adoptBackupPolicy(Map<String, Object?> policy);

  /// Tells whatever holds the preferences named in [names] that they changed.
  Future<void> reloadAfter(Set<String> names);
}

/// The application's own holders.
class AppCredentialHolders implements CredentialHolders {
  AppCredentialHolders({
    ProviderConnections? connections,
    ProviderSecretStore? secrets,
    MailSecretStore? mail,
  })  : _connections = connections ?? ProviderConnections.instance,
        _secrets = secrets ?? ProviderSecretStore(),
        _mail = mail ?? MailSecretStore();

  final ProviderConnections _connections;
  final ProviderSecretStore _secrets;
  final MailSecretStore _mail;

  @override
  bool get canKeep => _secrets.canPersist && _mail.canPersist;

  @override
  Future<List<(ProviderConnection, ProviderCredentials?)>> connections() async {
    await _connections.ensureLoaded();
    return [
      for (final connection in _connections.all)
        (connection, await _connections.credentialsFor(connection.id)),
    ];
  }

  @override
  Future<void> putConnection(
    ProviderConnection connection,
    ProviderCredentials credentials,
  ) =>
      _connections.upsertAll([connection], credentials);

  @override
  Future<void> removeConnection(String id) => _connections.remove(id);

  @override
  Future<String?> readSecret(String id) => _secrets.read(id);

  @override
  Future<void> writeSecret(String id, String? value) async {
    if (value == null || value.isEmpty) {
      await _secrets.forget(id);
    } else {
      await _secrets.write(id, value);
    }
    if (id == BackupSettings.passphraseSecretId) {
      BackupSettings.instance.forgetKeyInMemory();
    }
  }

  @override
  Future<String?> readMailPassword(String accountId) =>
      _mail.readStored(accountId);

  @override
  Future<void> writeMailPassword(String accountId, String? value) async {
    if (value == null || value.isEmpty) {
      await _mail.forget(accountId);
    } else {
      await _mail.write(accountId, value, remember: true);
    }
  }

  @override
  Future<Map<String, Object?>?> backupPolicy() async {
    try {
      return await BackupSettings.instance.syncedPolicy();
    } on Object catch (error) {
      Log.warn('The backup settings could not be read for sync: $error');
      return null;
    }
  }

  @override
  Future<void> adoptBackupPolicy(Map<String, Object?> policy) =>
      BackupSettings.instance.adoptSyncedPolicy(policy);

  @override
  Future<void> reloadAfter(Set<String> names) async {
    try {
      if (names.any(
        (name) => name.startsWith(OAuthAppRegistry.storageKeyPrefix),
      )) {
        OAuthAppRegistry.instance.invalidate();
      }
      if (names.contains('appflowy_maps_google_api_key')) {
        await MapsSettings.instance.reload();
      }
      if (names.contains(McpServerStore.serversKey)) {
        await McpServerStore.instance.reload();
      }
      if (names.contains(CustomAIProviderStore.providersKey) ||
          names.contains(CustomAIProviderStore.selectedModelKey)) {
        await CustomAIProviderStore.instance.reload();
      }
      if (names.contains(EncryptionVault.storageKey)) {
        await EncryptionVault.instance.reload();
      }
    } on Object catch (error) {
      Log.warn('Settings from another computer were not all shown: $error');
    }
  }
}
