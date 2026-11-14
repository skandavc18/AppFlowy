import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'sync_files.dart';

const automationDataFolders = ['workflows', 'extensions', 'extension_data'];
const automationFileSyncPrefix = 'automation.file:';

String automationFileSyncKey(String path) => '$automationFileSyncPrefix$path';

bool isAutomationSyncPath(String path) =>
    isSafeSyncPath(path) &&
    automationDataFolders.contains(p.posix.split(path).first);

bool isAutomationFileSyncKey(String key) =>
    key.startsWith(automationFileSyncPrefix) &&
    isAutomationSyncPath(key.substring(automationFileSyncPrefix.length));

/// Carries the same automation files as folder sync through sealed account
/// settings. File contents, including binary extension assets, stay lossless.
class SyncedAutomationFiles {
  SyncedAutomationFiles({required this.dataPath});

  final Future<String> Function() dataPath;

  Future<Map<String, String>> read() async {
    final root = await dataPath();
    final scan = await scanSyncedFiles(
      dataPath: root,
      index: SyncFileIndex(),
      folders: automationDataFolders,
      strict: true,
    );
    final values = <String, String>{};
    for (final path in scan.current.keys.toList()..sort()) {
      if (!isAutomationSyncPath(path)) {
        throw FormatException('An automation file has an unsafe sync path.');
      }
      final file = await _file(root, path);
      values[automationFileSyncKey(path)] =
          base64Encode(await file.readAsBytes());
    }
    return values;
  }

  Future<Set<String>> apply(Map<String, String?> changes) async {
    final decoded = <String, List<int>?>{};
    for (final entry in changes.entries) {
      if (!isAutomationFileSyncKey(entry.key)) {
        throw const FormatException('An automation sync key is invalid.');
      }
      final path = entry.key.substring(automationFileSyncPrefix.length);
      decoded[path] = entry.value == null ? null : base64Decode(entry.value!);
    }
    if (decoded.isEmpty) return {};
    final root = await dataPath();
    for (final entry in decoded.entries) {
      final file = await _file(root, entry.key);
      final bytes = entry.value;
      if (bytes == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.parent.create(recursive: true);
        final staging = File(
          p.join(file.parent.path, '.${p.basename(file.path)}.sync.part'),
        );
        await staging.writeAsBytes(bytes, flush: true);
        await staging.rename(file.path);
      }
    }
    return changes.keys.toSet();
  }

  Future<File> _file(String root, String path) async {
    if (root.isEmpty || !isAutomationSyncPath(path)) {
      throw const FormatException('An automation sync path is invalid.');
    }
    var current = root;
    final segments = p.posix.split(path);
    for (var index = 0; index < segments.length; index++) {
      current = p.join(current, segments[index]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link ||
          (index < segments.length - 1 &&
              type != FileSystemEntityType.notFound &&
              type != FileSystemEntityType.directory) ||
          (index == segments.length - 1 &&
              type != FileSystemEntityType.notFound &&
              type != FileSystemEntityType.file)) {
        throw FileSystemException(
          'An automation sync path is not a regular file or directory.',
          current,
        );
      }
    }
    return File(current);
  }
}
