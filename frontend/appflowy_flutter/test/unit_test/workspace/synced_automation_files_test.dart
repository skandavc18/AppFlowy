import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/sync/synced_automation_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory a;
  late Directory b;
  late SyncedAutomationFiles source;
  late SyncedAutomationFiles target;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('synced_automation');
    a = await Directory(p.join(root.path, 'a')).create();
    b = await Directory(p.join(root.path, 'b')).create();
    source = SyncedAutomationFiles(dataPath: () async => a.path);
    target = SyncedAutomationFiles(dataPath: () async => b.path);
  });
  tearDown(() => root.delete(recursive: true));

  File put(Directory home, String path, List<int> bytes) =>
      File(p.join(home.path, path))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);

  test('workflows, extension source, binary assets and data travel losslessly',
      () async {
    final contents = {
      'workflows/workflows.json': utf8.encode('{"workflows":[{"id":"one"}]}'),
      'workflows/settings.json': utf8.encode('{"notifyOnFailure":false}'),
      'extensions/demo/manifest.json': utf8.encode('{"id":"demo"}'),
      'extensions/demo/actions/read.json': utf8.encode('{"id":"read"}'),
      'extensions/demo/widget.js': utf8.encode('export const title = "Demo";'),
      'extensions/demo/icon.png': [0, 255, 137, 80, 78, 71],
      'extension_data/demo/values.json': utf8.encode('{"demo.value":1}'),
    };
    for (final entry in contents.entries) {
      put(a, entry.key, entry.value);
    }
    put(a, 'images/private.png', [1, 2]);
    put(a, 'workflows/.workflows.json.sync.part', [3]);
    put(a, 'extensions/demo/unfinished.tmp', [4]);
    final values = await source.read();
    expect(
      values.keys,
      unorderedEquals(contents.keys.map(automationFileSyncKey)),
    );
    expect(await target.apply(values), values.keys.toSet());
    for (final entry in contents.entries) {
      expect(File(p.join(b.path, entry.key)).readAsBytesSync(), entry.value);
    }

    put(
      b,
      'extensions/demo/widget.js',
      utf8.encode('export const title = "New";'),
    );
    await source.apply(await target.read());
    expect(
      File(p.join(a.path, 'extensions/demo/widget.js')).readAsStringSync(),
      'export const title = "New";',
    );
  });

  test('a synced removal removes only its file, not another folder', () async {
    put(a, 'workflows/workflows.json', utf8.encode('{}'));
    await target.apply(await source.read());
    final unrelated = put(b, 'images/keep.png', [1]);
    await target.apply({
      automationFileSyncKey('workflows/workflows.json'): null,
    });
    expect(
      File(p.join(b.path, 'workflows/workflows.json')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(a.path, 'workflows/workflows.json')).existsSync(),
      isTrue,
    );
    expect(unrelated.readAsBytesSync(), [1]);
  });

  test('unsafe paths and malformed contents fail before any file is written',
      () async {
    final good = automationFileSyncKey('workflows/workflows.json');
    for (final path in [
      '../outside',
      '/workflows/file.json',
      'workflows/../outside',
      r'workflows\file.json',
      'extensions/C:/file',
      'files/not-automation',
    ]) {
      final key = automationFileSyncKey(path);
      expect(isAutomationFileSyncKey(key), isFalse, reason: path);
      await expectLater(
        target.apply({
          good: base64Encode([1]),
          key: base64Encode([2]),
        }),
        throwsFormatException,
      );
    }
    await expectLater(
      target.apply({good: 'not base64!'}),
      throwsFormatException,
    );
    expect(await target.read(), isEmpty);
  });

  test(
    'linked extension files are neither exported nor overwritten',
    () async {
      final outside = put(root, 'outside.txt', utf8.encode('keep'));
      final link = Link(p.join(a.path, 'extensions/demo/widget.js'));
      await link.parent.create(recursive: true);
      await link.create(outside.path);
      await expectLater(source.read(), throwsA(isA<FileSystemException>()));
      await expectLater(
        source.apply({
          automationFileSyncKey('extensions/demo/widget.js'):
              base64Encode(utf8.encode('replace')),
        }),
        throwsA(isA<FileSystemException>()),
      );
      expect(outside.readAsStringSync(), 'keep');
    },
    skip: Platform.isWindows,
  );
}
