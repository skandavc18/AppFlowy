// Settings that follow the workspace to every computer that syncs it.
//
// Each setting travels on its own, so two computers changing different
// settings never lose either change; when both change the same one, the later
// change wins everywhere. A computer that has never synced a setting takes
// the folder's, which is what joining a folder means. Settings that only make
// sense on one kind of computer are carried along by the others, untouched, so
// the folder never forgets them.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appflowy/workspace/application/sync/sync_vault.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// Accounts, passwords and keys travel under names starting with this. They
/// travel only in a sealed folder, and can be taken out of it on their own.
const String credentialKeyPrefix = 'cred:';

/// Sync's own switches, which travel like settings but are read by sync.
const String syncSwitchPrefix = 'sync:';

/// Whether accounts, passwords and keys travel through the folder: absent or
/// anything but [syncSwitchOff] means they do.
const String credentialsSwitchKey = '${syncSwitchPrefix}credentials';

const String syncSwitchOn = 'on';
const String syncSwitchOff = 'off';

bool isCredentialKey(String key) => key.startsWith(credentialKeyPrefix);

bool isSyncSwitchKey(String key) => key.startsWith(syncSwitchPrefix);

/// One setting as it was at [modified]: [value] is its canonical encoding, or
/// null once the setting was removed.
@immutable
class SyncPreferenceRecord {
  const SyncPreferenceRecord({
    required this.key,
    required this.modified,
    this.value,
  });

  factory SyncPreferenceRecord.fromJson(Map<String, Object?> json) =>
      SyncPreferenceRecord(
        key: json['k'] is String ? json['k']! as String : '',
        value: json['v'] is String ? json['v']! as String : null,
        modified: json['m'] is int ? json['m']! as int : 0,
      );

  final String key;
  final String? value;

  /// Milliseconds since the epoch.
  final int modified;

  bool get isRemoval => value == null;

  /// Whether this version is later than [other]. The later change wins; two
  /// made at the same moment are told apart by their values, so every computer
  /// picks the same one.
  bool isLaterThan(SyncPreferenceRecord? other) {
    if (other == null) {
      return true;
    }
    if (modified != other.modified) {
      return modified > other.modified;
    }
    return (value ?? '').compareTo(other.value ?? '') > 0;
  }

  Map<String, Object?> toJson() => {
        'k': key,
        if (value != null) 'v': value,
        'm': modified,
      };

  @override
  bool operator ==(Object other) =>
      other is SyncPreferenceRecord &&
      other.key == key &&
      other.value == value &&
      other.modified == modified;

  @override
  int get hashCode => Object.hash(key, value, modified);
}

/// Where this computer's synced settings are read and put.
abstract class SyncedPreferencesSource {
  /// Every synced setting set on this computer, by key, canonically encoded.
  /// A setting that is not set is not there.
  Future<Map<String, String>> read();

  /// Settings this computer has whose values the last [read] could not get —
  /// a token the keyring would not hand over, say. They are never taken for
  /// removed, and the folder's value is taken for them.
  Set<String> get unreadable;

  /// Whether [key] is kept on this computer. A setting for another kind of
  /// computer, or one this version does not know, is carried, never applied.
  bool handles(String key);

  /// Puts [changes] in place; a null value removes the setting.
  Future<void> apply(Map<String, String?> changes);
}

/// A source that keeps nothing: settings are carried, not synced, while a
/// computer has settings sync turned off.
class InertPreferencesSource implements SyncedPreferencesSource {
  const InertPreferencesSource();

  @override
  Future<Map<String, String>> read() async => const {};

  @override
  Set<String> get unreadable => const {};

  @override
  bool handles(String key) => false;

  @override
  Future<void> apply(Map<String, String?> changes) async {}
}

/// What each setting was when this computer last sent or took it, removals
/// included — everything a checkpoint has to carry.
class SyncPreferencesIndex {
  SyncPreferencesIndex([Map<String, SyncPreferenceRecord>? entries])
      : entries = entries ?? <String, SyncPreferenceRecord>{};

  final Map<String, SyncPreferenceRecord> entries;

  /// Settings noted for the folder but never put in place here, because this
  /// computer did not keep them when they arrived — a Mac's shortcuts, say,
  /// or the Home of a workspace that was joined but not open yet. One this
  /// computer comes to keep is taken from here, never sent as if it had been
  /// removed.
  final Set<String> carried = <String>{};

  List<SyncPreferenceRecord> get records => entries.values.toList();

  /// Whether accounts, passwords and keys travel, as the folder last said.
  bool get credentialsOn =>
      entries[credentialsSwitchKey]?.value != syncSwitchOff;

  /// Forgets every account, password and key, so that they all count as new
  /// when they travel again.
  void dropCredentials() {
    entries.removeWhere((key, _) => isCredentialKey(key));
    carried.removeWhere(isCredentialKey);
  }

  /// Remembers [record] when it is later than what is known of its setting.
  bool note(SyncPreferenceRecord record) {
    if (record.key.isEmpty || !record.isLaterThan(entries[record.key])) {
      return false;
    }
    entries[record.key] = record;
    return true;
  }

  /// Reads the record kept in [file]. With [key] it was sealed, because it
  /// holds accounts, passwords and keys; one that does not open with [key]
  /// reads as empty.
  static Future<SyncPreferencesIndex> load(File file, {SyncKey? key}) async {
    try {
      if (!file.existsSync()) {
        return SyncPreferencesIndex();
      }
      var text = await file.readAsString();
      if (!text.trimLeft().startsWith('{')) {
        if (key == null) {
          return SyncPreferencesIndex();
        }
        text = key.openText(text, context: _localContext);
      }
      final decoded = jsonDecode(text);
      final listed = decoded is Map ? decoded['settings'] : null;
      final index = SyncPreferencesIndex();
      if (listed is List) {
        for (final entry in listed) {
          if (entry is Map) {
            index.note(
              SyncPreferenceRecord.fromJson(Map<String, Object?>.from(entry)),
            );
          }
        }
      }
      final carried = decoded is Map ? decoded['carried'] : null;
      if (carried is List) {
        index.carried.addAll(
          carried.whereType<String>().where(index.entries.containsKey),
        );
      }
      return index;
    } on Object catch (error) {
      Log.warn('The synced settings record could not be read: $error');
      return SyncPreferencesIndex();
    }
  }

  /// Keeps the record in [file], sealed with [key] when there is one. Without
  /// a key accounts, passwords and keys are left out: they are never written
  /// down in the clear.
  Future<void> save(File file, {SyncKey? key}) async {
    await file.parent.create(recursive: true);
    final staging = File('${file.path}.tmp');
    final text = jsonEncode({
      'settings': [
        for (final record in entries.values)
          if (key != null || !isCredentialKey(record.key)) record.toJson(),
      ],
      'carried': [
        for (final name in carried)
          if (key != null || !isCredentialKey(name)) name,
      ],
    });
    await staging.writeAsString(
      key == null ? text : key.sealText(text, context: _localContext),
    );
    await staging.rename(file.path);
  }

  static const String _localContext = 'local-index';
}

/// The settings changed on this computer since [index] was last brought up to
/// date, stamped [now].
///
/// A change is always stamped later than the version it replaced, even when
/// this computer's clock is behind the one that made that version: otherwise
/// the others would take the change for an old one and keep theirs.
List<SyncPreferenceRecord> scanSyncedPreferences({
  required Map<String, String> current,
  required SyncPreferencesIndex index,
  required bool Function(String key) handles,
  required int now,
  Set<String> unreadable = const {},
}) {
  int stamp(SyncPreferenceRecord? known) =>
      known == null ? now : max(now, known.modified + 1);

  final changed = <SyncPreferenceRecord>[];
  for (final entry in current.entries) {
    if (!handles(entry.key) || index.carried.contains(entry.key)) {
      continue;
    }
    final known = index.entries[entry.key];
    if (known?.value != entry.value) {
      changed.add(
        SyncPreferenceRecord(
          key: entry.key,
          value: entry.value,
          modified: stamp(known),
        ),
      );
    }
  }
  for (final known in index.entries.values) {
    if (!known.isRemoval &&
        handles(known.key) &&
        !index.carried.contains(known.key) &&
        !unreadable.contains(known.key) &&
        !current.containsKey(known.key)) {
      changed.add(SyncPreferenceRecord(key: known.key, modified: stamp(known)));
    }
  }
  return changed;
}

/// Brings another computer's setting changes in, and returns how many
/// settings changed here.
///
/// [current] is what this computer has now, and is kept up to date with what
/// is applied. A setting changed here since it was last synced keeps this
/// computer's value: that change goes out this round, stamped later than
/// anything already in the folder. A setting never synced here takes the
/// folder's value.
Future<int> applyRemotePreferences({
  required SyncedPreferencesSource source,
  required SyncPreferencesIndex index,
  required List<SyncPreferenceRecord> records,
  required Map<String, String> current,
}) async {
  final changes = <String, String?>{};
  final unreadable = source.unreadable;
  for (final record in records) {
    if (record.key.isEmpty) {
      continue;
    }
    if (!source.handles(record.key)) {
      if (index.note(record)) {
        index.carried.add(record.key);
      }
      continue;
    }
    if (index.carried.contains(record.key)) {
      // Taken with the rest of what was carried, below.
      index.note(record);
      continue;
    }
    final known = index.entries[record.key];
    // A value this computer could not read is taken to be the one last
    // synced, so the folder's later one replaces it.
    final original =
        unreadable.contains(record.key) ? known?.value : current[record.key];
    final here =
        changes.containsKey(record.key) ? changes[record.key] : original;
    if (known != null && here != known.value) {
      // Changed here and not sent yet: this computer's value stays, and goes
      // out stamped after [record], so every computer ends up with it.
      index.note(record);
      continue;
    }
    if (known != null && !record.isLaterThan(known)) {
      continue;
    }
    index.entries[record.key] = record;
    if (record.value == original) {
      changes.remove(record.key);
    } else {
      changes[record.key] = record.value;
    }
  }
  if (changes.isNotEmpty) {
    await source.apply(changes);
    changes.forEach((key, value) {
      if (value == null) {
        current.remove(key);
      } else {
        current[key] = value;
      }
    });
  }
  return changes.length +
      await adoptCarriedPreferences(
        source: source,
        index: index,
        current: current,
      );
}

/// Puts in place what was carried for the folder and this computer now keeps:
/// taken from the folder, never sent as if it had been removed here.
Future<int> adoptCarriedPreferences({
  required SyncedPreferencesSource source,
  required SyncPreferencesIndex index,
  required Map<String, String> current,
}) async {
  final ready = [
    for (final key in index.carried)
      if (source.handles(key)) key,
  ];
  if (ready.isEmpty) {
    return 0;
  }
  final changes = <String, String?>{
    for (final key in ready)
      if (current[key] != index.entries[key]?.value)
        key: index.entries[key]?.value,
  };
  if (changes.isNotEmpty) {
    await source.apply(changes);
    changes.forEach((key, value) {
      if (value == null) {
        current.remove(key);
      } else {
        current[key] = value;
      }
    });
  }
  index.carried.removeAll(ready);
  return changes.length;
}

/// Puts every setting [index] knows in place here — what turning settings
/// sync back on means: the folder's settings are taken, not this computer's
/// leftovers sent.
Future<int> adoptIndexedPreferences({
  required SyncedPreferencesSource source,
  required SyncPreferencesIndex index,
}) async {
  final current = await source.read();
  final changes = <String, String?>{};
  for (final record in index.entries.values) {
    if (source.handles(record.key) && current[record.key] != record.value) {
      changes[record.key] = record.value;
    }
  }
  if (changes.isNotEmpty) {
    await source.apply(changes);
  }
  index.carried.removeWhere(source.handles);
  return changes.length;
}

/// The settings sync may read and put: never its own switches, and accounts,
/// passwords and keys only while they travel.
class GatedPreferences implements SyncedPreferencesSource {
  GatedPreferences(this.inner, {required this.credentials});

  final SyncedPreferencesSource inner;
  final bool credentials;

  bool _allowed(String key) =>
      !isSyncSwitchKey(key) && (credentials || !isCredentialKey(key));

  @override
  bool handles(String key) => _allowed(key) && inner.handles(key);

  @override
  Set<String> get unreadable => {
        for (final key in inner.unreadable)
          if (_allowed(key)) key,
      };

  @override
  Future<Map<String, String>> read() async => {
        for (final entry in (await inner.read()).entries)
          if (_allowed(entry.key)) entry.key: entry.value,
      };

  @override
  Future<void> apply(Map<String, String?> changes) => inner.apply({
        for (final entry in changes.entries)
          if (_allowed(entry.key)) entry.key: entry.value,
      });
}
