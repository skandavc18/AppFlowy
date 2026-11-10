// One file in a sync folder: what it is, the attached files it names, and the
// workspace changes themselves — compressed together.
//
//   gzip( "AFSYNCPK" | u32 record length | record JSON | workspace bundle )
//
// The bundle is the file the Rust side writes and reads; this layer never
// looks inside it. Compressing and expanding run on an isolate of their own:
// a snapshot of a large workspace is seconds of solid work, and the window has
// to keep drawing while it happens.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/sync/sync_files.dart';
import 'package:appflowy/workspace/application/sync/sync_preferences.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart';
import 'package:flutter/foundation.dart';

const String _packMagic = 'AFSYNCPK';

enum SyncPackKind {
  base,
  changes,
  checkpoint;

  static SyncPackKind fromValue(Object? value) => SyncPackKind.values
      .firstWhere((kind) => kind.name == value, orElse: () => changes);
}

/// What a pack says about itself.
@immutable
class SyncPackRecord {
  const SyncPackRecord({
    required this.kind,
    required this.epoch,
    required this.device,
    required this.workspaceId,
    required this.createdAt,
    this.deviceName = '',
    this.seq = 0,
    this.hasBundle = false,
    this.files = const [],
    this.deleted = const [],
    this.filesComplete = false,
    this.preferences = const [],
  });

  factory SyncPackRecord.fromJson(Map<String, Object?> json) {
    List<SyncFileRecord> records(Object? value) => value is List
        ? [
            for (final entry in value)
              if (entry is Map)
                SyncFileRecord.fromJson(Map<String, Object?>.from(entry)),
          ]
        : const [];

    return SyncPackRecord(
      kind: SyncPackKind.fromValue(json['kind']),
      epoch: json['epoch'] is String ? json['epoch']! as String : '',
      device: json['device'] is String ? json['device']! as String : '',
      deviceName:
          json['device_name'] is String ? json['device_name']! as String : '',
      workspaceId:
          json['workspace_id'] is String ? json['workspace_id']! as String : '',
      seq: json['seq'] is int ? json['seq']! as int : 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['created_at'] is int ? json['created_at']! as int : 0,
        isUtc: true,
      ),
      hasBundle: json['has_bundle'] == true,
      files: records(json['files']),
      deleted: records(json['deleted']),
      filesComplete: json['files_complete'] == true,
      preferences: [
        if (json['prefs'] is List)
          for (final entry in json['prefs']! as List)
            if (entry is Map)
              SyncPreferenceRecord.fromJson(Map<String, Object?>.from(entry)),
      ],
    );
  }

  final SyncPackKind kind;
  final String epoch;
  final String device;
  final String deviceName;
  final String workspaceId;
  final int seq;
  final DateTime createdAt;

  /// Whether a workspace bundle follows the record.
  final bool hasBundle;

  /// Attached files added or changed.
  final List<SyncFileRecord> files;

  /// Attached files removed.
  final List<SyncFileRecord> deleted;

  /// Whether [files] lists every attached file, not only the changed ones.
  final bool filesComplete;

  /// Settings changed — or, in a base or checkpoint, every setting known.
  final List<SyncPreferenceRecord> preferences;

  bool get isEmpty =>
      !hasBundle && files.isEmpty && deleted.isEmpty && preferences.isEmpty;

  Map<String, Object?> toJson() => {
        'format': syncFormat,
        'kind': kind.name,
        'epoch': epoch,
        'device': device,
        'device_name': deviceName,
        'workspace_id': workspaceId,
        'seq': seq,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'has_bundle': hasBundle,
        'files': [for (final file in files) file.toJson()],
        'deleted': [for (final file in deleted) file.toJson()],
        'files_complete': filesComplete,
        if (preferences.isNotEmpty)
          'prefs': [for (final record in preferences) record.toJson()],
      };
}

/// Raised when a pack cannot be read.
class SyncPackError implements Exception {
  const SyncPackError(this.detail);

  final String detail;

  @override
  String toString() => 'SyncPackError: $detail';
}

/// Writes [record] and, when there is one, the bundle at [bundle] into
/// [destination].
Future<void> writeSyncPack({
  required File destination,
  required SyncPackRecord record,
  File? bundle,
}) async {
  final recordJson = jsonEncode(record.toJson());
  final destinationPath = destination.path;
  final bundlePath = bundle?.path;
  await Isolate.run(
    () => _writePack(destinationPath, recordJson, bundlePath),
  );
}

/// Reads the pack at [source], expanding its bundle, if it has one, to
/// [bundle].
Future<SyncPackRecord> readSyncPack({
  required File source,
  required File bundle,
}) async {
  final sourcePath = source.path;
  final bundlePath = bundle.path;
  final recordJson = await Isolate.run(
    () => _readPack(sourcePath, bundlePath),
  );
  final decoded = jsonDecode(recordJson);
  if (decoded is! Map) {
    throw const SyncPackError('The pack record is not readable.');
  }
  if (decoded['format'] is int && (decoded['format']! as int) > syncFormat) {
    throw const SyncPackError(
      'This sync folder was written by a newer version of AppFlowy.',
    );
  }
  return SyncPackRecord.fromJson(Map<String, Object?>.from(decoded));
}

Future<void> _writePack(
  String destinationPath,
  String recordJson,
  String? bundlePath,
) async {
  final destination = File(destinationPath);
  await destination.parent.create(recursive: true);
  final staging = File('$destinationPath.part');
  final output = staging.openWrite();
  final encoder = GZipCodec().encoder.startChunkedConversion(output);
  try {
    final record = utf8.encode(recordJson);
    final length = ByteData(4)..setUint32(0, record.length, Endian.little);
    encoder
      ..add(ascii.encode(_packMagic))
      ..add(length.buffer.asUint8List())
      ..add(record);
    if (bundlePath != null) {
      await for (final chunk in File(bundlePath).openRead()) {
        encoder.add(chunk);
      }
    }
  } finally {
    encoder.close();
    await output.close();
  }
  await staging.rename(destinationPath);
}

Future<String> _readPack(String sourcePath, String bundlePath) async {
  final header = BytesBuilder(copy: false);
  int? recordLength;
  String? record;
  IOSink? bundle;
  try {
    await for (final chunk
        in File(sourcePath).openRead().transform(gzip.decoder)) {
      if (record != null) {
        bundle ??= File(bundlePath).openWrite();
        bundle.add(chunk);
        continue;
      }
      header.add(chunk);
      final bytes = header.toBytes();
      if (recordLength == null && bytes.length >= 12) {
        if (ascii.decode(bytes.sublist(0, 8), allowInvalid: true) !=
            _packMagic) {
          throw const SyncPackError('That file is not a sync pack.');
        }
        recordLength =
            ByteData.sublistView(bytes, 8, 12).getUint32(0, Endian.little);
        if (recordLength > 64 << 20) {
          throw const SyncPackError('The pack record is too large.');
        }
      }
      if (recordLength != null && bytes.length >= 12 + recordLength) {
        record = utf8.decode(bytes.sublist(12, 12 + recordLength));
        final rest = bytes.sublist(12 + recordLength);
        if (rest.isNotEmpty) {
          bundle = File(bundlePath).openWrite()..add(rest);
        }
      }
    }
  } on FormatException {
    throw const SyncPackError('The pack is damaged.');
  } finally {
    await bundle?.close();
  }
  if (record == null) {
    throw const SyncPackError('The pack is incomplete.');
  }
  return record;
}
