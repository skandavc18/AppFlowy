// What one copy is, written down beside it.
//
// A backup that cannot be read without the application that wrote it is not a
// backup. The manifest is plain JSON next to the archive and says everything
// needed to open it — which parts are inside, how it was compressed, and, when
// it is sealed, the salt and work factor the key was derived with. It carries
// no content of its own, so it can be read before anything is downloaded and
// before a passphrase is asked for.

import 'dart:convert';

import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:flutter/foundation.dart';

/// The current shape of a manifest. A reader refuses a version it was not
/// written for rather than guessing what a field meant.
const int backupManifestVersion = 1;

/// The file extensions this layer writes. Both are looked for when a
/// destination is listed, so a folder full of other files reads as empty
/// rather than as broken backups.
const String backupArchiveExtension = '.afbackup';
const String backupManifestExtension = '.afbackup.json';

/// One thing that was left out, and why.
@immutable
class BackupOmission {
  const BackupOmission({
    required this.reason,
    required this.count,
    required this.bytes,
    this.names = const <String>[],
  });

  factory BackupOmission.fromJson(Map<String, Object?> json) {
    final names = json['names'];
    return BackupOmission(
      reason: BackupOmissionReason.fromValue(json['reason']),
      count: json['count'] is int ? json['count']! as int : 0,
      bytes: json['bytes'] is int ? json['bytes']! as int : 0,
      names: names is List
          ? [
              for (final name in names)
                if (name is String) name
            ]
          : const <String>[],
    );
  }

  final BackupOmissionReason reason;
  final int count;
  final int bytes;

  /// The names, when the archive is not sealed. A sealed archive records the
  /// count only — file names are content, and a manifest sitting in the clear
  /// beside a sealed archive must not describe what is in it.
  final List<String> names;

  BackupOmission withoutNames() => BackupOmission(
        reason: reason,
        count: count,
        bytes: bytes,
      );

  Map<String, Object?> toJson() => {
        'reason': reason.name,
        'count': count,
        'bytes': bytes,
        if (names.isNotEmpty) 'names': names,
      };
}

enum BackupOmissionReason {
  tooLarge,
  unreadable;

  static BackupOmissionReason fromValue(Object? value) {
    for (final reason in BackupOmissionReason.values) {
      if (reason.name == value) {
        return reason;
      }
    }
    return BackupOmissionReason.unreadable;
  }
}

/// Everything known about one copy.
@immutable
class BackupManifest {
  const BackupManifest({
    required this.id,
    required this.createdAt,
    required this.parts,
    required this.compression,
    required this.fileCount,
    required this.rawBytes,
    required this.archiveBytes,
    this.sealedBytes = 0,
    this.appVersion = '',
    this.workspaceName = '',
    this.encrypted = false,
    this.salt = '',
    this.iterations = 0,
    this.verifier = '',
    this.chunkBytes = 0,
    this.hint = '',
    this.omissions = const <BackupOmission>[],
    this.version = backupManifestVersion,
  });

  factory BackupManifest.fromJson(Map<String, Object?> json) {
    String readString(String key) {
      final value = json[key];
      return value is String ? value : '';
    }

    int readInt(String key) {
      final value = json[key];
      return value is int ? value : 0;
    }

    final storedParts = json['parts'];
    final parts = <BackupPart>{};
    if (storedParts is List) {
      for (final name in storedParts) {
        final part = BackupPart.fromValue(name);
        if (part != null) {
          parts.add(part);
        }
      }
    }

    final storedOmissions = json['omissions'];

    return BackupManifest(
      id: readString('id'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        readInt('created_at'),
        isUtc: true,
      ),
      parts: parts,
      compression: BackupCompression.fromValue(json['compression']),
      fileCount: readInt('file_count'),
      rawBytes: readInt('raw_bytes'),
      archiveBytes: readInt('archive_bytes'),
      sealedBytes: readInt('sealed_bytes'),
      appVersion: readString('app_version'),
      workspaceName: readString('workspace_name'),
      encrypted: json['encrypted'] == true,
      salt: readString('salt'),
      iterations: readInt('iterations'),
      verifier: readString('verifier'),
      chunkBytes: readInt('chunk_bytes'),
      hint: readString('hint'),
      omissions: storedOmissions is List
          ? [
              for (final omission in storedOmissions)
                if (omission is Map)
                  BackupOmission.fromJson(
                    Map<String, Object?>.from(omission),
                  ),
            ]
          : const <BackupOmission>[],
      version: readInt('version'),
    );
  }

  /// Reads a manifest, or returns null when the text is not one this build
  /// understands. Never throws — a stranger's folder can hold anything.
  static BackupManifest? tryParse(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return null;
      }
      final manifest = BackupManifest.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (manifest.id.isEmpty ||
          manifest.version < 1 ||
          manifest.version > backupManifestVersion) {
        return null;
      }
      return manifest;
    } on Object {
      return null;
    }
  }

  final String id;
  final DateTime createdAt;
  final Set<BackupPart> parts;
  final BackupCompression compression;

  final int fileCount;

  /// What the copied files measured before anything was done to them.
  final int rawBytes;

  /// The archive's own size.
  final int archiveBytes;

  /// The size of what was actually written or sent, after sealing.
  final int sealedBytes;

  final String appVersion;
  final String workspaceName;

  final bool encrypted;

  /// Base64. Needed to derive the key again on a machine that has never seen
  /// this workspace, which is exactly the machine a restore happens on.
  final String salt;
  final int iterations;

  /// A known phrase sealed with the key, so a wrong passphrase is refused
  /// before a gigabyte is decrypted into rubbish.
  final String verifier;

  final int chunkBytes;

  /// The reminder that was left beside the passphrase, if any.
  final String hint;

  final List<BackupOmission> omissions;

  final int version;

  /// The size that matters to somebody looking at a list.
  int get storedBytes => sealedBytes > 0 ? sealedBytes : archiveBytes;

  String get archiveFileName => '$id$backupArchiveExtension';

  String get manifestFileName => '$id$backupManifestExtension';

  /// The same manifest with everything that could name a file removed.
  BackupManifest redacted() => copyWith(
        omissions: [for (final omission in omissions) omission.withoutNames()],
      );

  BackupManifest copyWith({
    int? sealedBytes,
    bool? encrypted,
    String? salt,
    int? iterations,
    String? verifier,
    int? chunkBytes,
    String? hint,
    String? workspaceName,
    String? appVersion,
    BackupCompression? compression,
    int? archiveBytes,
    List<BackupOmission>? omissions,
  }) =>
      BackupManifest(
        id: id,
        createdAt: createdAt,
        parts: parts,
        compression: compression ?? this.compression,
        fileCount: fileCount,
        rawBytes: rawBytes,
        archiveBytes: archiveBytes ?? this.archiveBytes,
        sealedBytes: sealedBytes ?? this.sealedBytes,
        appVersion: appVersion ?? this.appVersion,
        workspaceName: workspaceName ?? this.workspaceName,
        encrypted: encrypted ?? this.encrypted,
        salt: salt ?? this.salt,
        iterations: iterations ?? this.iterations,
        verifier: verifier ?? this.verifier,
        chunkBytes: chunkBytes ?? this.chunkBytes,
        hint: hint ?? this.hint,
        omissions: omissions ?? this.omissions,
        version: version,
      );

  Map<String, Object?> toJson() => {
        'version': version,
        'id': id,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'parts': [for (final part in parts) part.name],
        'compression': compression.name,
        'file_count': fileCount,
        'raw_bytes': rawBytes,
        'archive_bytes': archiveBytes,
        if (sealedBytes > 0) 'sealed_bytes': sealedBytes,
        if (appVersion.isNotEmpty) 'app_version': appVersion,
        if (workspaceName.isNotEmpty) 'workspace_name': workspaceName,
        if (encrypted) 'encrypted': true,
        if (salt.isNotEmpty) 'salt': salt,
        if (iterations > 0) 'iterations': iterations,
        if (verifier.isNotEmpty) 'verifier': verifier,
        if (chunkBytes > 0) 'chunk_bytes': chunkBytes,
        if (hint.isNotEmpty) 'hint': hint,
        if (omissions.isNotEmpty)
          'omissions': [for (final omission in omissions) omission.toJson()],
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// A size written the way a person reads one.
String backupSizeLabel(int bytes) {
  if (bytes < 0) {
    return '—';
  }
  const megabyte = 1024 * 1024;
  if (bytes >= 1024 * megabyte) {
    final gigabytes = bytes / (1024 * megabyte);
    return '${gigabytes.toStringAsFixed(gigabytes >= 10 ? 0 : 1)} GB';
  }
  if (bytes >= megabyte) {
    final megabytes = bytes / megabyte;
    return '${megabytes.toStringAsFixed(megabytes >= 10 ? 0 : 1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).round()} KB';
  }
  return '$bytes B';
}

/// Names a copy after the moment it was taken, so a listing sorts by name and
/// by date at once and a person can tell two apart without opening either.
String newBackupId(DateTime at) {
  String two(int value) => value.toString().padLeft(2, '0');
  final utc = at.toUtc();
  return 'appflowy-'
      '${utc.year}${two(utc.month)}${two(utc.day)}-'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
}
