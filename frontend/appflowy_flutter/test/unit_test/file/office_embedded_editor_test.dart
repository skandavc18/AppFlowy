import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_cloud_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_bridge.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_embedded_host.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_embedded_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_embedded_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_server_settings.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_office_view.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _theme = OfficeEmbeddedTheme(
  isDark: false,
  themeId: 'theme-white',
  storedTheme: '{"id":"theme-white"}',
  background: '#FFFFFF',
);

/// A minimal stand-in for the unpacked editor.
Directory _createBundle() {
  final root = Directory.systemTemp.createTempSync('office_editor_bundle');
  void write(String path, List<int> bytes) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  write(
    'editor.html',
    utf8.encode(
      '<!doctype html><html lang="en"><head data-x="1">'
      '<meta http-equiv="Content-Security-Policy" content="script-src \'self\'">'
      '</head><body>editor</body></html>',
    ),
  );
  write('web-apps/apps/api/documents/api.js', utf8.encode('// api'));
  write('sdkjs/common/wasm/x2t/x2t.wasm.br', gzip.encode([0, 97, 115, 109]));
  write('fonts/050', [1, 2, 3]);
  write('assets/app-1234.js', utf8.encode('// app'));
  return root;
}

class _Response {
  _Response(this.status, this.headers, this.body);

  final int status;
  final HttpHeaders headers;
  final List<int> body;

  String get text => utf8.decode(body);
}

/// flutter_test answers every HttpClient request with a 400; these tests talk
/// to a real loopback server.
class _RealHttp extends HttpOverrides {}

HttpClient _client() =>
    HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());

Future<_Response> _request(
  String method,
  Uri uri, {
  Map<String, String> headers = const {},
  List<int>? body,
  bool decompress = false,
}) async {
  final client = _client()..autoUncompress = decompress;
  try {
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.add(body);
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (previous, chunk) => previous..addAll(chunk),
    );
    return _Response(response.statusCode, response.headers, bytes);
  } finally {
    client.close(force: true);
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met in time');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('bundle lookup', () {
    test('prefers the override, then the platform install folder', () {
      expect(
        officeEditorBundleCandidates(
          executable: '/opt/AppFlowy/AppFlowy',
          environment: {kOfficeEditorDirectoryEnvironment: '/dev/editor'},
          isMacOS: false,
        ),
        ['/dev/editor', p.join('/opt/AppFlowy', 'data', 'office_editor')],
      );
      expect(
        officeEditorBundleCandidates(
          executable: '/Applications/AppFlowy.app/Contents/MacOS/AppFlowy',
          environment: const {},
          isMacOS: true,
        ).first,
        '/Applications/AppFlowy.app/Contents/Resources/office_editor',
      );
    });

    test('finds only a complete bundle', () {
      final bundle = _createBundle();
      addTearDown(() => bundle.deleteSync(recursive: true));
      final executable = p.join(bundle.parent.path, 'AppFlowy');

      expect(
        locateOfficeEditorBundle(
          executable: executable,
          environment: {kOfficeEditorDirectoryEnvironment: bundle.path},
          isMacOS: false,
        )?.path,
        bundle.path,
      );

      File(p.join(bundle.path, 'editor.html')).deleteSync();
      expect(
        locateOfficeEditorBundle(
          executable: executable,
          environment: {kOfficeEditorDirectoryEnvironment: bundle.path},
          isMacOS: false,
        ),
        isNull,
      );
    });

    test('knows which formats it reads and which it writes back', () {
      expect(canEmbedOfficeFile('Report.DOCX'), isTrue);
      expect(canEmbedOfficeFile('legacy.doc'), isTrue);
      expect(canEmbedOfficeFile('data.tsv'), isFalse);
      for (final name in ['a.docx', 'a.odt', 'a.rtf', 'a.xlsx', 'a.csv']) {
        expect(canEmbedOfficeFileForEditing(name), isTrue, reason: name);
      }
      for (final name in ['a.doc', 'a.xls', 'a.ppt']) {
        expect(canEmbedOfficeFileForEditing(name), isFalse, reason: name);
      }
    });
  });

  group('chooseOfficeEditorRoute', () {
    test('opens files on this machine in the bundled editor', () {
      for (final cloud in [true, false]) {
        expect(
          chooseOfficeEditorRoute(
            embeddedAvailable: true,
            hasCloudProfile: cloud,
            remoteSource: false,
          ),
          OfficeEditorRoute.embedded,
        );
      }
    });

    test('keeps cloud files on the managed editor', () {
      expect(
        chooseOfficeEditorRoute(
          embeddedAvailable: true,
          hasCloudProfile: true,
          remoteSource: true,
        ),
        OfficeEditorRoute.managed,
      );
    });

    test('shows downloaded copies read only without an account', () {
      expect(
        chooseOfficeEditorRoute(
          embeddedAvailable: true,
          hasCloudProfile: false,
          remoteSource: true,
        ),
        OfficeEditorRoute.embeddedReadOnly,
      );
    });

    test('falls back to the server-based editors without the bundle', () {
      expect(
        chooseOfficeEditorRoute(
          embeddedAvailable: false,
          hasCloudProfile: true,
          remoteSource: false,
        ),
        OfficeEditorRoute.managed,
      );
      expect(
        chooseOfficeEditorRoute(
          embeddedAvailable: false,
          hasCloudProfile: false,
          remoteSource: true,
        ),
        OfficeEditorRoute.local,
      );
    });
  });

  group('embedded page', () {
    test('loads the shim before anything else in the editor page', () {
      final html = injectOfficeEmbeddedShim(
        '<html><HEAD lang="en"><meta charset="utf-8"></HEAD></html>',
      );
      expect(
        html,
        '<html><HEAD lang="en"><script src="/__appflowy__/shim.js"></script>'
        '<meta charset="utf-8"></HEAD></html>',
      );
      expect(
        injectOfficeEmbeddedShim('<p>no head</p>'),
        startsWith('<script src="/__appflowy__/shim.js"></script>'),
      );
    });

    test('removes the service worker and customizes the editor', () {
      expect(
        officeEmbeddedShimScript,
        contains('delete Navigator.prototype.serviceWorker'),
      );
      expect(officeEmbeddedShimScript, contains('toolbarHideFileName: true'));
      expect(officeEmbeddedShimScript, contains("'DocsAPI'"));
    });

    test('passes the document and theme to the page safely', () {
      final html = buildOfficeEmbeddedPage(
        fileName: 'Q3 </script><script>alert(1)</script>.docx',
        editable: false,
        theme: _theme,
        origin: 'http://127.0.0.1:1234',
      );
      expect(html, isNot(contains('</script><script>alert(1)')));
      expect(html, contains(r'<\/script>'));
      expect(html, contains('"editable":false'));
      expect(html, contains('"id":"theme-white"'));
      expect(html, contains("new EventSource('commands')"));
      expect(html, isNot(contains('appflowyOfficeScroll')));
      expect(
        buildOfficeEmbeddedPage(
          fileName: 'a.docx',
          editable: true,
          theme: _theme,
          origin: 'http://127.0.0.1:1234',
          relayScroll: true,
        ),
        contains('appflowyOfficeScroll'),
      );
    });
  });

  group('EmbeddedOfficeHost', () {
    late Directory bundle;
    late Directory work;
    late EmbeddedOfficeHost host;
    late File file;

    setUp(() {
      bundle = _createBundle();
      work = Directory.systemTemp.createTempSync('office_editor_work');
      file = File(p.join(work.path, 'Report.docx'))
        ..writeAsBytesSync([1, 2, 3, 4]);
      host = EmbeddedOfficeHost(locate: () => bundle);
    });

    tearDown(() async {
      await host.shutdown();
      bundle.deleteSync(recursive: true);
      work.deleteSync(recursive: true);
    });

    Future<EmbeddedOfficeSession> open({bool editable = true}) => host.open(
          file: file,
          fileName: 'Report.docx',
          editable: editable,
          theme: _theme,
        );

    Map<String, String> origin() => {'Origin': host.origin.toString()};

    test('serves the editor isolated, with the shim injected', () async {
      await open();
      final page = await _request('GET', host.origin.resolve('/editor.html'));
      expect(page.status, HttpStatus.ok);
      expect(
        page.text,
        contains('<head data-x="1"><script src="/__appflowy__/shim.js">'),
      );
      expect(page.headers.value('cross-origin-opener-policy'), 'same-origin');
      expect(
        page.headers.value('cross-origin-embedder-policy'),
        'require-corp',
      );
      expect(page.headers.value('cross-origin-resource-policy'), 'same-origin');
      expect(page.headers.value('cache-control'), 'no-cache');

      final shim =
          await _request('GET', host.origin.resolve('/__appflowy__/shim.js'));
      expect(shim.text, officeEmbeddedShimScript);
      expect(shim.headers.contentType?.mimeType, 'text/javascript');
    });

    test('labels the gzip x2t build and the font catalog', () async {
      await open();
      final wasm = await _request(
        'GET',
        host.origin.resolve('/sdkjs/common/wasm/x2t/x2t.wasm.br'),
      );
      expect(wasm.headers.value('content-encoding'), 'gzip');
      expect(gzip.decode(wasm.body), [0, 97, 115, 109]);
      // The port changes each launch, so a stored copy could never be reused.
      expect(wasm.headers.value('cache-control'), 'no-store');

      final font = await _request('GET', host.origin.resolve('/fonts/050'));
      expect(font.headers.contentType?.mimeType, 'font/ttf');
      expect(font.headers.value('cache-control'), 'no-store');
    });

    test('never serves files outside the bundle', () async {
      File(p.join(bundle.parent.path, 'secret.txt')).writeAsStringSync('no');
      await open();
      for (final path in [
        '/../secret.txt',
        '/%2e%2e/secret.txt',
        '/fonts/..%2f..%2fsecret.txt',
        '/web-apps/%5c..%5csecret.txt',
      ]) {
        final response = await _request(
          'GET',
          Uri.parse('${host.origin}$path'),
        );
        expect(response.status, HttpStatus.notFound, reason: path);
      }
    });

    test('answers only to its own host name', () async {
      await open();
      final response = await _request(
        'GET',
        host.origin.resolve('/editor.html'),
        headers: {'Host': 'attacker.example:${host.origin.port}'},
      );
      expect(response.status, HttpStatus.forbidden);
    });

    test('reads the document and saves it only from its own origin', () async {
      final session = await open();
      final document = session.pageUrl.resolve('document');

      final read = await _request('GET', document);
      expect(read.body, [1, 2, 3, 4]);

      for (final headers in [
        <String, String>{},
        {'Origin': 'https://attacker.example'},
      ]) {
        final rejected = await _request(
          'PUT',
          document,
          headers: headers,
          body: [9],
        );
        expect(rejected.status, HttpStatus.forbidden);
      }
      expect(file.readAsBytesSync(), [1, 2, 3, 4]);

      final saved = await _request(
        'PUT',
        document,
        headers: {...origin(), 'X-AppFlowy-Dirty': 'false'},
        body: [5, 6, 7],
      );
      expect(saved.status, HttpStatus.noContent);
      expect(file.readAsBytesSync(), [5, 6, 7]);
      expect(session.status.value.lastSaved, isNotNull);
      expect(
        work.listSync().map((entry) => p.basename(entry.path)),
        ['Report.docx'],
        reason: 'no temporary file is left behind',
      );
    });

    test('refuses to save a read-only session', () async {
      final session = await open(editable: false);
      final response = await _request(
        'PUT',
        session.pageUrl.resolve('document'),
        headers: origin(),
        body: [9],
      );
      expect(response.status, HttpStatus.methodNotAllowed);
      expect(file.readAsBytesSync(), [1, 2, 3, 4]);
    });

    test('tracks page events and ignores ones arriving late', () async {
      final session = await open();
      final events = session.pageUrl.resolve('events');
      Future<int> post(Map<String, Object?> event) async => (await _request(
            'POST',
            events,
            headers: {...origin(), 'Content-Type': 'application/json'},
            body: utf8.encode(jsonEncode(event)),
          ))
              .status;

      expect(await post({'type': 'opened', 'seq': 1}), HttpStatus.noContent);
      expect(session.status.value.phase, EmbeddedOfficePhase.ready);
      await post({'type': 'dirty', 'dirty': true, 'seq': 3});
      await post({'type': 'saving', 'seq': 4});
      await post({'type': 'clean', 'seq': 2});
      expect(session.status.value.dirty, isTrue);
      expect(session.status.value.saving, isTrue);
      expect(await post({'type': 'unknown'}), HttpStatus.badRequest);

      final foreign = await _request(
        'POST',
        events,
        headers: {'Origin': 'https://attacker.example'},
        body: utf8.encode('{"type":"clean"}'),
      );
      expect(foreign.status, HttpStatus.forbidden);
    });

    test('asks the page to save and waits until the file has the edits',
        () async {
      final session = await open();
      final client = _client();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(session.pageUrl.resolve('commands'));
      final response = await request.close();
      final commands = <Map<String, dynamic>>[];
      final subscription = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.startsWith('data: '))
          .listen(
            (line) => commands.add(
              jsonDecode(line.substring(6)) as Map<String, dynamic>,
            ),
          );
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await _request(
        'POST',
        session.pageUrl.resolve('events'),
        headers: origin(),
        body: utf8.encode('{"type":"dirty","dirty":true,"seq":1}'),
      );
      final flushed = session.flush(timeout: const Duration(seconds: 5));
      await _until(() => commands.any((command) => command['type'] == 'save'));
      await _request(
        'PUT',
        session.pageUrl.resolve('document'),
        headers: {
          ...origin(),
          'X-AppFlowy-Dirty': 'false',
          'X-AppFlowy-Seq': '2',
        },
        body: [8, 8],
      );
      expect(await flushed, isTrue);
      expect(file.readAsBytesSync(), [8, 8]);

      await session.updateTheme(
        const OfficeEmbeddedTheme(
          isDark: true,
          themeId: 'theme-night',
          storedTheme: '{}',
          background: '#000000',
        ),
      );
      await _until(
        () => commands.any((command) => command['type'] == 'reload'),
      );
      expect(
        commands.lastWhere((command) => command['type'] == 'reload')['theme'],
        containsPair('id', 'theme-night'),
      );
    });

    test('tells other views of a saved file to reopen it', () async {
      final writer = await open();
      final reader = await open(editable: false);
      final client = _client();
      addTearDown(() => client.close(force: true));
      final response =
          await (await client.getUrl(reader.pageUrl.resolve('commands')))
              .close();
      final received = Completer<String>();
      final subscription = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.startsWith('data: '))
          .listen((line) {
        if (!received.isCompleted) received.complete(line);
      });
      addTearDown(subscription.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await _request(
        'PUT',
        writer.pageUrl.resolve('document'),
        headers: origin(),
        body: [4, 2],
      );
      expect(
        await received.future.timeout(const Duration(seconds: 5)),
        contains('external-change'),
      );
    });

    test('closes sessions', () async {
      final session = await open();
      session.close();
      final response = await _request('GET', session.pageUrl);
      expect(response.status, HttpStatus.notFound);
      expect(host.editingSessionFor(file), isNull);
    });
  });

  test('replaces a file in one step', () async {
    final directory = Directory.systemTemp.createTempSync('office_atomic');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File(p.join(directory.path, 'a.xlsx'))..writeAsBytesSync([1]);
    await writeOfficeFileAtomically(file, [2, 3]);
    expect(file.readAsBytesSync(), [2, 3]);
    expect(directory.listSync(), hasLength(1));
  });

  group('OfficeDocumentView with the bundled editor', () {
    late Directory bundle;

    setUpAll(() => bundle = _createBundle());
    tearDownAll(() => bundle.deleteSync(recursive: true));

    EmbeddedOfficeEditor editor({bool available = true}) =>
        EmbeddedOfficeEditor(
          host: EmbeddedOfficeHost(locate: () => available ? bundle : null),
          presentation: EmbeddedOfficePresentation.webView,
        );

    Future<List<EmbeddedOfficeRequest>> pump(
      WidgetTester tester, {
      required String name,
      required String source,
      required OfficeCloudSessionService cloud,
      bool available = true,
    }) async {
      final requests = <EmbeddedOfficeRequest>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFlowyTheme(
              data: AppFlowyDefaultTheme().light(),
              child: OfficeDocumentView(
                file: File(name),
                name: name,
                source: source,
                editable: true,
                store: const _EmptyStore(),
                cloudService: cloud,
                embeddedEditor: editor(available: available),
                editorBuilder: (_, __) => const Text('managed editor'),
                embeddedEditorBuilder: (_, request) {
                  requests.add(request);
                  return Text('embedded ${request.editable}');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return requests;
    }

    testWidgets('edits a local file with no server', (tester) async {
      final requests = await pump(
        tester,
        name: 'Report.docx',
        source: '/home/me/Report.docx',
        cloud: const _Cloud.local(),
      );
      expect(find.text('embedded true'), findsOneWidget);
      expect(requests.last.notice, isNull);
    });

    testWidgets('keeps cloud files on the Cloud editor', (tester) async {
      final cloud = _Cloud.signedIn();
      await pump(
        tester,
        name: 'Report.docx',
        source: 'https://cloud.example.com/api/file_storage/Report.docx',
        cloud: cloud,
      );
      expect(cloud.sessions, 1);
      expect(find.text('managed editor'), findsOneWidget);
      expect(find.textContaining('embedded'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(OfficeDocumentBridge.instance.shutdown);
    });

    testWidgets('shows a read-only copy when the Cloud editor fails',
        (tester) async {
      final requests = await pump(
        tester,
        name: 'Report.docx',
        source: 'https://cloud.example.com/api/file_storage/Report.docx',
        cloud: _Cloud.signedIn(fail: true),
      );
      expect(find.text('embedded false'), findsOneWidget);
      expect(requests.last.notice, contains('read-only'));
    });

    testWidgets('views downloaded copies read only without an account',
        (tester) async {
      await pump(
        tester,
        name: 'Report.docx',
        source: 'https://example.com/Report.docx',
        cloud: const _Cloud.local(),
      );
      expect(find.text('embedded false'), findsOneWidget);
    });

    testWidgets('opens legacy formats read only and says why', (tester) async {
      final requests = await pump(
        tester,
        name: 'Budget.xls',
        source: '/home/me/Budget.xls',
        cloud: const _Cloud.local(),
      );
      expect(find.text('embedded false'), findsOneWidget);
      expect(requests.last.notice, contains('.xls'));
    });

    testWidgets('falls back to the server setup without the bundle',
        (tester) async {
      await pump(
        tester,
        name: 'Report.docx',
        source: '/home/me/Report.docx',
        cloud: const _Cloud.local(),
        available: false,
      );
      expect(find.text('Set up document editing'), findsOneWidget);
    });
  });

  group('document editing settings with the bundled editor', () {
    late Directory bundle;

    setUpAll(() => bundle = _createBundle());
    tearDownAll(() => bundle.deleteSync(recursive: true));

    Future<void> pump(
      WidgetTester tester,
      EmbeddedOfficeEditor editor,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFlowyTheme(
              data: AppFlowyDefaultTheme().light(),
              child: SettingsOfficeView(
                userProfile: UserProfilePB()..userAuthType = AuthTypePB.Local,
                store: const _EmptyStore(),
                probe: (_) async => true,
                embeddedEditor: editor,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('needs no document server', (tester) async {
      await pump(
        tester,
        EmbeddedOfficeEditor(
          host: EmbeddedOfficeHost(locate: () => bundle),
          presentation: EmbeddedOfficePresentation.webView,
        ),
      );
      expect(find.textContaining('built-in editor'), findsOneWidget);
      expect(find.text('Direct document server'), findsNothing);
    });

    testWidgets('asks for WebKitGTK when only it is missing', (tester) async {
      await pump(
        tester,
        EmbeddedOfficeEditor(
          host: EmbeddedOfficeHost(locate: () => bundle),
          presentation: EmbeddedOfficePresentation.texture,
          webViewSupported: () async => false,
        ),
      );
      expect(find.textContaining('libwebkit2gtk-4.1-0'), findsOneWidget);
      expect(find.text('Direct document server'), findsOneWidget);
    });
  });
}

class _EmptyStore extends OfficeServerStore {
  const _EmptyStore();

  @override
  Future<OfficeServerSettings> read() async => const OfficeServerSettings();

  @override
  Future<void> write(OfficeServerSettings settings) async {}
}

class _Cloud implements OfficeCloudSessionService {
  const _Cloud.local()
      : signedIn = false,
        fail = false,
        _counter = null;

  _Cloud.signedIn({this.fail = false})
      : signedIn = true,
        _counter = [0];

  final bool signedIn;
  final bool fail;
  final List<int>? _counter;

  int get sessions => _counter?.first ?? 0;

  @override
  Future<UserProfilePB?> connectedCloudProfile() async =>
      signedIn ? (UserProfilePB()..userAuthType = AuthTypePB.Server) : null;

  @override
  Future<ManagedOfficeSession> createSession({
    required UserProfilePB profile,
    required String storageUrl,
    required String fileName,
    required bool editable,
    required bool isDark,
    String? sessionId,
  }) async {
    _counter?[0]++;
    if (fail) {
      throw const OfficeCloudException('The Cloud has no document server.');
    }
    return const ManagedOfficeSession(
      sessionId: 'session',
      documentServerUrl: 'https://cloud.example.com/office',
      editorConfig: {'documentType': 'word'},
    );
  }
}
