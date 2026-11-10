// Pages remember an attached file by the absolute path it was copied to on the
// computer that added it. On another computer — or after the data folder
// moved — that path names nothing, although the same file is right here, at
// the same place inside this computer's data folder, because sync put it
// there.

import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/sync/sync_files.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

final Map<String, String> _found = {};
const int _rememberAtMost = 4096;

/// Where the file a page recorded at [path] is on this computer.
///
/// Returns [path] itself when it exists, when it is a web address, and when it
/// cannot be found under this computer's data folder either. Synchronous, and
/// cheap after the first look, so it can sit in a build method.
String resolveWorkspaceFilePath(String path) => _resolve(path, _dataRoot());

@visibleForTesting
String resolveWorkspaceFilePathUnder(String path, String? dataRoot) =>
    _resolve(path, dataRoot);

String _resolve(String path, String? dataRoot) {
  if (path.isEmpty) {
    return path;
  }
  final known = _found[path];
  if (known != null) {
    return known;
  }
  final uri = Uri.tryParse(path);
  if (uri != null &&
      (uri.isScheme('http') || uri.isScheme('https') || uri.isScheme('data'))) {
    return path;
  }

  var local = path;
  if (uri != null && uri.isScheme('file')) {
    try {
      local = uri.toFilePath(windows: Platform.isWindows);
    } on UnsupportedError {
      return path;
    }
  }
  if (_exists(local)) {
    return _remember(path, local);
  }
  if (dataRoot == null || dataRoot.isEmpty) {
    return path;
  }

  // Written on Windows or anywhere else, the part after the data folder is the
  // same: the synced folder's name and what is inside it. The innermost match
  // wins, so a synced folder's name higher up the old path cannot mislead it.
  final segments = local
      .split(RegExp(r'[\\/]+'))
      .where((segment) => segment.isNotEmpty)
      .toList();
  for (var i = segments.length - 2; i >= 0; i--) {
    if (!syncedDataFolders.contains(segments[i])) {
      continue;
    }
    final candidate = p.joinAll([dataRoot, ...segments.sublist(i)]);
    if (_exists(candidate)) {
      return _remember(path, candidate);
    }
  }
  return path;
}

String _remember(String path, String found) {
  if (_found.length >= _rememberAtMost) {
    _found.clear();
  }
  return _found[path] = found;
}

bool _exists(String path) {
  try {
    return File(path).existsSync();
  } on Object {
    return false;
  }
}

String? _dataRoot() => getIt.isRegistered<ApplicationDataStorage>()
    ? getIt<ApplicationDataStorage>().cachedPath
    : null;
