import 'dart:async';
import 'dart:io';

import 'package:appflowy/extensions/application/action_definition.dart';
import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/action_runner.dart';
import 'package:appflowy/extensions/application/action_scheduler.dart';
import 'package:appflowy/extensions/application/extension_data_store.dart';
import 'package:appflowy/extensions/application/extension_manifest.dart';
import 'package:appflowy/extensions/application/extension_run_log.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'late callbacks from a logged-out Dart extension cannot access the next account',
      () async {
    final root = await Directory.systemTemp.createTemp('extension_scope');
    final data = ExtensionDataStore(rootOverride: p.join(root.path, 'data'));
    const info = DartExtensionInfo(id: 'demo', name: 'Demo');
    final old = DartExtensionContext(info: info, dataStore: data);
    final next = DartExtensionContext(info: info, dataStore: data);
    try {
      await old.data.write('private', 'account A');
      await data.flush();
      final response = Completer<void>();
      final late = () async {
        await response.future;
        await old.data.write('private', 'late account A response');
      }();
      old.scope.close();
      await Directory(p.join(root.path, 'data')).delete(recursive: true);
      await data.resetAccount();
      await next.data.write('private', 'account B');
      response.complete();
      await late;
      expect(data.read('demo.private'), 'account B');
      expect(old.data.read('private'), isNull);
      expect(old.data.entryFor('private'), isNull);
      expect(old.data.listenable('private').value, isNull);
      expect(old.data.revision.value, 0);
      await old.data.remove('private');
      expect(next.data.read('private'), 'account B');
    } finally {
      next.scope.close();
      data.dispose();
      await root.delete(recursive: true);
    }
  });

  test('bundled extensions restart with fresh account choices and scopes',
      () async {
    final extension = _BundledExtension();
    final host = DartExtensionHost(builtIns: () => [extension]);
    await host.start();
    expect(host.isActive('fixture'), isTrue);
    await host.setEnabled('fixture', false);
    expect(host.isActive('fixture'), isFalse);
    await host.stop();
    expect(extension.closedScopes, 1);
    expect(host.extensions, isEmpty);
    await host.start();
    expect(host.extensions, hasLength(1));
    expect(host.isEnabled('fixture'), isTrue);
    expect(host.isActive('fixture'), isTrue);
    expect(extension.activations, 2);
    await host.stop();
    expect(extension.closedScopes, 2);
    host.dispose();
  });

  test('logout waits for an active extension action and refuses later writes',
      () async {
    final root = await Directory.systemTemp.createTemp('extension_lifecycle');
    final entered = Completer<void>();
    final release = Completer<void>();
    final data = ExtensionDataStore(rootOverride: p.join(root.path, 'data'));
    final log = ExtensionRunLog(rootOverride: p.join(root.path, 'data'));
    final action = ActionDefinition.fromJson({
      'id': 'private-action',
      'steps': [
        {
          'id': 'request',
          'http': {'get': 'https://example.com/data'},
        },
        {
          'id': 'write',
          'set': {'key': 'private', 'value': 'old account'},
        },
      ],
    })!;
    final store = _Store(
      LoadedExtension(
        manifest: ExtensionManifest.fromJson({
          'id': 'demo',
          'permissions': ['data', 'net:example.com'],
        })!,
        folder: root.path,
        actions: [action],
      ),
    );
    final runner = ActionRunner(
      data: data,
      client: MockClient((_) async {
        entered.complete();
        await release.future;
        return http.Response('{"value":1}', 200);
      }),
    );
    final scheduler = ActionScheduler(store: store, log: log, runner: runner);
    try {
      final running = scheduler.runNow(
        extensionId: 'demo',
        actionId: action.id,
      );
      await entered.future;
      var stopped = false;
      final stopping = scheduler.stop().then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero);
      expect(stopped, isFalse);
      release.complete();
      await stopping;
      final outcome = await running;
      expect(outcome.status, ActionRunStatus.refused);
      expect(data.read('demo.private'), isNull);
      expect(scheduler.isRunning, isFalse);
      final refused = await scheduler.runNow(
        extensionId: 'demo',
        actionId: action.id,
      );
      expect(refused.status, ActionRunStatus.refused);
      expect(data.read('demo.private'), isNull);
    } finally {
      scheduler.dispose();
      await data.flush();
      await log.flush();
      data.dispose();
      log.dispose();
      store.dispose();
      await root.delete(recursive: true);
    }
  });
}

class _BundledExtension extends AppFlowyExtension {
  int activations = 0;
  int closedScopes = 0;
  @override
  DartExtensionInfo get info =>
      const DartExtensionInfo(id: 'fixture', name: 'Fixture');
  @override
  Future<void> activate(ExtensionContext context) async {
    activations++;
    context.scope.onDispose(() => closedScopes++);
  }
}

class _Store extends ExtensionStore {
  _Store(this.extension);
  final LoadedExtension extension;
  @override
  Future<void> ensureLoaded() async {}
  @override
  Future<void> stopWatching() async {}
  @override
  LoadedExtension? byId(String id) => id == extension.id ? extension : null;
}
