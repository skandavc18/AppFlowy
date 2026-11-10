import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_embedded_host.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_embedded_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_linux_view_pool.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _theme = OfficeEmbeddedTheme(
  isDark: true,
  themeId: 'theme-night',
  storedTheme: '{"id":"theme-night"}',
  background: '#262422',
);

final _idle = Uri.parse('http://127.0.0.1:4321/__appflowy__/idle');
Uri _page(String token) =>
    Uri.parse('http://127.0.0.1:4321/__appflowy__/office/$token/');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('appflowy_linux_webview');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Completer<void> created;
  var textures = 0;

  setUp(() {
    calls = [];
    created = Completer();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') {
        if (!created.isCompleted) created.complete();
        return ++textures;
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  List<String> methods() => [
        for (final call in calls)
          if (call.method != 'disposeAll') call.method,
      ];
  Map<Object?, Object?> last(String method) =>
      calls.lastWhere((call) => call.method == method).arguments
          as Map<Object?, Object?>;

  test('a closed document leaves its view, web process and all, to the next',
      () async {
    final pool = OfficeLinuxViewPool();
    addTearDown(pool.dispose);
    final first = await pool.acquire(url: _page('a'), userScripts: ['one']);
    expect(methods(), ['create']);
    expect(last('create')['url'], _page('a').toString());

    calls.clear();
    await pool.release(first, idleUrl: _idle);
    // It waits on the editor's own origin: anywhere else, WebKit would give
    // the next document a new process.
    expect(methods(), ['setUserScripts', 'load']);
    expect(last('setUserScripts')['userScripts'], isEmpty);
    expect(last('load'), {
      'id': last('load')['id'],
      'url': _idle.toString(),
      'origin': 'http://127.0.0.1:4321',
    });
    expect(pool.idleCount, 1);

    calls.clear();
    final second = await pool.acquire(url: _page('b'), userScripts: ['two']);
    expect(second, same(first));
    expect(methods(), ['setUserScripts', 'load']);
    expect(last('setUserScripts')['userScripts'], ['two']);
    expect(last('load')['url'], _page('b').toString());
    expect(pool.idleCount, 0);
  });

  test('keeps one view and lets it go once unused for a while', () async {
    final pool = OfficeLinuxViewPool(
      idleTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(pool.dispose);
    final first = await pool.acquire(url: _page('a'), userScripts: const []);
    final second = await pool.acquire(url: _page('b'), userScripts: const []);
    expect(second, isNot(same(first)));
    await pool.release(first, idleUrl: _idle);
    await pool.release(second, idleUrl: _idle);
    expect(pool.idleCount, 1);
    expect(second.isDisposed, isTrue);
    expect(first.isDisposed, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(pool.idleCount, 0);
    expect(first.isDisposed, isTrue);
  });

  test('a document opening as another closes waits for its view', () async {
    final pool = OfficeLinuxViewPool();
    addTearDown(pool.dispose);
    final first = await pool.acquire(url: _page('a'), userScripts: const []);
    calls.clear();
    final releasing = pool.release(first, idleUrl: _idle);
    final next = await pool.acquire(url: _page('b'), userScripts: const []);
    await releasing;
    expect(next, same(first));
    expect(methods(), isNot(contains('create')));
    expect(last('load')['url'], _page('b').toString());
  });

  group('warm-up', () {
    late Directory bundle;
    late EmbeddedOfficeHost host;
    late _MemoryKeyValue storage;

    setUp(() {
      bundle = Directory.systemTemp.createTempSync('office_warm_up_bundle');
      File(p.join(bundle.path, 'editor.html'))
          .writeAsStringSync('<!doctype html><html><head></head></html>');
      host = EmbeddedOfficeHost(locate: () => bundle, cacheBundle: true);
      storage = _MemoryKeyValue();
      getIt.pushNewScope();
      getIt.registerSingleton<KeyValueStorage>(storage);
    });

    tearDown(() async {
      await getIt.popScope();
      await host.shutdown();
      bundle.deleteSync(recursive: true);
    });

    Future<void> report(Uri page, String type) async {
      final response = await _post(
        page.resolve('events'),
        jsonEncode({'type': type}),
        origin: host.origin.toString(),
      );
      expect(response, HttpStatus.noContent);
    }

    test('does nothing on a device that never opened a document', () async {
      final pool = OfficeLinuxViewPool();
      addTearDown(pool.dispose);
      await pool.warmUp(host: host);
      expect(methods(), isEmpty);
      expect(pool.idleCount, 0);
    });

    test('waits while a document is open, and runs once it has closed',
        () async {
      await OfficeEditorUsage.remember('Budget.xlsx', _theme);
      final pool = OfficeLinuxViewPool(capacity: 0);
      addTearDown(pool.dispose);
      final view = await pool.acquire(url: _page('open'), userScripts: []);

      // A second editor loading beside the one in use would slow it down.
      await pool.warmUp(host: host);
      expect(pool.isWarmingUp, isFalse);
      expect(calls.where((call) => call.method == 'create'), hasLength(1));

      // Once closed (and here not kept), the next launch's warm-up may run.
      await pool.release(view, idleUrl: _idle);
      expect(view.isDisposed, isTrue);
      final warming = pool.warmUp(host: host);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(pool.isWarmingUp, isTrue);
      expect(calls.where((call) => call.method == 'create'), hasLength(2));
      await pool.dispose();
      await warming;
    });

    test('loads a blank document of the last kind, then keeps the view',
        () async {
      await OfficeEditorUsage.remember('Budget.xlsx', _theme);
      final usage = await OfficeEditorUsage.recall();
      expect(usage?.kind, WorkspaceFileKind.excel);
      expect(usage?.theme, _theme);

      final pool = OfficeLinuxViewPool();
      addTearDown(pool.dispose);
      final warming = pool.warmUp(host: host);
      await created.future;
      expect(pool.isWarmingUp, isTrue);
      final page = Uri.parse(last('create')['url']! as String);
      // The page reads a real blank workbook from its session.
      final document = await _get(page.resolve('document'));
      expect(document.take(2), [0x50, 0x4b]);

      await report(page, 'opened');
      await report(page, 'loaded');
      await warming;
      expect(pool.isWarmingUp, isFalse);
      expect(pool.idleCount, 1);
      expect(last('load')['url'], host.idleUrl.toString());
      // Its session is over.
      expect(await _status(page), HttpStatus.notFound);

      calls.clear();
      final view = await pool.acquire(url: _page('real'), userScripts: ['s']);
      expect(methods(), ['setUserScripts', 'load']);
      expect(view.isDisposed, isFalse);
    });

    test('a document opening meanwhile takes the warm-up view over', () async {
      await OfficeEditorUsage.remember('Report.docx', _theme);
      final pool = OfficeLinuxViewPool();
      addTearDown(pool.dispose);
      final warming = pool.warmUp(host: host);
      await created.future;
      final page = Uri.parse(last('create')['url']! as String);
      final warmView = calls.where((call) => call.method == 'create').length;
      expect(warmView, 1);

      final view = await pool.acquire(url: _page('real'), userScripts: ['s']);
      await warming;
      expect(calls.where((call) => call.method == 'create'), hasLength(1));
      expect(last('load')['url'], _page('real').toString());
      expect(view.isDisposed, isFalse);
      expect(pool.isWarmingUp, isFalse);
      // Taken over, not parked.
      expect(pool.idleCount, 0);
      expect(await _status(page), HttpStatus.notFound);
    });
  });
}

/// flutter_test answers every HttpClient request with a 400; these tests talk
/// to a real loopback server.
class _RealHttp extends HttpOverrides {}

Future<T> _withClient<T>(Future<T> Function(HttpClient) body) async {
  final client =
      HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
  try {
    return await body(client);
  } finally {
    client.close(force: true);
  }
}

Future<int> _post(Uri uri, String body, {required String origin}) =>
    _withClient((client) async {
      final request = await client.postUrl(uri);
      request.headers
        ..set('origin', origin)
        ..contentType = ContentType.json;
      request.write(body);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    });

Future<List<int>> _get(Uri uri) => _withClient((client) async {
      final response = await (await client.getUrl(uri)).close();
      return response
          .fold<List<int>>(<int>[], (all, part) => all..addAll(part));
    });

Future<int> _status(Uri uri) => _withClient((client) async {
      final response = await (await client.getUrl(uri)).close();
      await response.drain<void>();
      return response.statusCode;
    });

class _MemoryKeyValue implements KeyValueStorage {
  final values = <String, String>{};

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();
}
