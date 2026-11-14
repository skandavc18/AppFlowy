import 'dart:async';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/application/extension_run_log.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy/user/application/account_automation_session.dart';
import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_run_log.dart';
import 'package:appflowy/workflows/application/workflow_store.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late _Storage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('account_automation');
    storage = _Storage();
  });
  tearDown(() => root.delete(recursive: true));

  File put(String path, String text) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  test(
      'successful logout removes files, choices and live caches without resurrection',
      () async {
    final workflows =
        WorkflowStore(rootOverride: p.join(root.path, 'workflows'));
    final history =
        WorkflowRunLog(rootOverride: p.join(root.path, 'workflows'));
    final extensions =
        ExtensionStore(rootOverride: p.join(root.path, 'extensions'));
    final data =
        ExtensionDataStore(rootOverride: p.join(root.path, 'extension_data'));
    final runs =
        ExtensionRunLog(rootOverride: p.join(root.path, 'extension_data'));
    addTearDown(() {
      workflows.dispose();
      history.dispose();
      extensions.dispose();
      data.dispose();
      runs.dispose();
    });
    put('extensions/demo/manifest.json', '{"id":"demo","name":"Private"}');
    final unrelated = put('images/keep.txt', 'keep');
    await workflows.save(Workflow.create(name: 'Private workflow'));
    await history.ensureLoaded();
    await extensions.ensureLoaded();
    await data.write('demo.private', 'account A');
    await runs.ensureLoaded();
    storage.values.addAll({
      ExtensionStore.enabledKey: '["demo"]',
      DartExtensionHost.disabledKey: 'stock',
      DartExtensionHost.themeKey: 'glass',
      'unrelated': 'keep',
    });
    var stopped = false;
    var reset = false;
    final session = AccountAutomationSession(
      dataPath: () async => root.path,
      storage: storage,
      stop: () async {
        await Future.wait(
          [workflows.flush(), history.flush(), data.flush(), runs.flush()],
        );
        stopped = true;
      },
      reset: () async {
        await Future.wait([
          workflows.resetAccount(),
          history.resetAccount(),
          extensions.resetAccount(),
          data.resetAccount(),
          runs.resetAccount(),
        ]);
        reset = true;
      },
      resume: () async =>
          fail('A successful logout must not restart automation.'),
    );
    await session.signOut(() async {
      expect(stopped, isTrue);
      expect(
        File(p.join(root.path, 'workflows/workflows.json')).existsSync(),
        isTrue,
      );
      return FlowyResult.success(null);
    });
    expect(reset, isTrue);
    expect(workflows.workflows, isEmpty);
    expect(history.runs, isEmpty);
    expect(extensions.extensions, isEmpty);
    expect(data.read('demo.private'), isNull);
    expect(storage.values, {'unrelated': 'keep'});
    await Future<void>.delayed(
      ExtensionDataStore.persistDebounce + const Duration(milliseconds: 50),
    );
    for (final folder in ['workflows', 'extensions', 'extension_data']) {
      expect(Directory(p.join(root.path, folder)).existsSync(), isFalse);
    }
    expect(unrelated.readAsStringSync(), 'keep');
  });

  test('a rejected logout retains local automation and resumes it', () async {
    final original = put('workflows/workflows.json', 'private');
    final events = <String>[];
    final session = AccountAutomationSession(
      dataPath: () async => root.path,
      storage: storage,
      stop: () async => events.add('stop'),
      reset: () async => events.add('reset'),
      resume: () async => events.add('resume'),
    );
    final result = await session.signOut(() async {
      events.add('backend');
      return FlowyResult.failure(FlowyError(msg: 'not signed out'));
    });
    expect(result.fold((_) => true, (_) => false), isFalse);
    expect(events, ['stop', 'backend', 'resume']);
    expect(original.readAsStringSync(), 'private');
  });

  test('a backend exception also resumes without deleting local files',
      () async {
    final original = put('extensions/demo/manifest.json', '{"id":"demo"}');
    var resumed = false;
    final session = AccountAutomationSession(
      dataPath: () async => root.path,
      storage: storage,
      stop: () async {},
      reset: () async => fail('The account is still signed in.'),
      resume: () async => resumed = true,
    );
    final result = await session.signOut(
      () async => throw const FileSystemException('offline'),
    );
    expect(result.fold((_) => true, (_) => false), isFalse);
    expect(resumed, isTrue);
    expect(original.existsSync(), isTrue);
  });

  test('concurrent logout requests share one cleanup and backend operation',
      () async {
    final backend = Completer<FlowyResult<void, FlowyError>>();
    var stopped = 0;
    var calls = 0;
    var resets = 0;
    final session = AccountAutomationSession(
      dataPath: () async => root.path,
      storage: storage,
      stop: () async => stopped++,
      reset: () async => resets++,
      resume: () async {},
    );
    Future<FlowyResult<void, FlowyError>> signOut() {
      calls++;
      return backend.future;
    }

    final first = session.signOut(signOut);
    final second = session.signOut(signOut);
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    backend.complete(FlowyResult.success(null));
    await Future.wait([first, second]);
    expect(stopped, 1);
    expect(resets, 1);
  });
}

class _Storage implements KeyValueStorage {
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
