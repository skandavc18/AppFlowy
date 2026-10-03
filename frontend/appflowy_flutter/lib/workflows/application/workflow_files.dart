import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where workflows keep their files, and how those files are read and written.
class WorkflowFiles {
  WorkflowFiles({this.rootOverride});

  static const folderName = 'workflows';

  /// Set in tests, where the application directories do not exist.
  final String? rootOverride;

  String? _root;
  Future<void> _writes = Future.value();

  Future<String> resolveRoot() async {
    final override = rootOverride;
    if (override != null) {
      await Directory(override).create(recursive: true);
      return override;
    }
    final cached = _root;
    if (cached != null) {
      return cached;
    }
    String base;
    try {
      base = await getIt<ApplicationDataStorage>().getPath();
    } on Object catch (_) {
      base = (await getApplicationSupportDirectory()).path;
    }
    final root = p.join(base, folderName);
    await Directory(root).create(recursive: true);
    return _root = root;
  }

  /// Reads one JSON file. A missing file is null.
  ///
  /// ⚠️ A file that exists but is not JSON is moved aside, never overwritten:
  /// the next save would otherwise replace someone's workflows with nothing.
  /// A file that could not be READ throws, so the caller tries again later
  /// instead of latching an empty store.
  Future<Object?> read(String name) async {
    final file = File(p.join(await resolveRoot(), name));
    if (!file.existsSync()) {
      return null;
    }
    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final aside = '${file.path}.corrupt-$stamp';
      Log.warn(
        'Workflow file $name is not valid JSON ($error); kept as $aside',
      );
      try {
        await file.rename(aside);
      } on Object catch (_) {
        // Left where it is; it is still not overwritten by a later save until
        // something valid has been written.
      }
      return null;
    }
  }

  /// Writes one JSON file: to a temporary file first, then over the old one,
  /// so a crash mid-write leaves the previous copy rather than half of one.
  /// Writes are queued, never interleaved.
  Future<void> write(String name, Object? value) {
    final next = _writes.then((_) => _write(name, value));
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _write(String name, Object? value) async {
    try {
      final root = await resolveRoot();
      final target = File(p.join(root, name));
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsString(jsonEncode(value), flush: true);
      await temporary.rename(target.path);
    } on Object catch (error) {
      Log.warn('Workflow file $name could not be written: $error');
    }
  }

  /// Waits for every queued write.
  Future<void> settle() => _writes;
}
