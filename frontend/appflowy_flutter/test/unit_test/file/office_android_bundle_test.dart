import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/mobile/presentation/base/app_bar/app_bar_actions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_editor_android_bundle.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_embedded_host.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_embedded_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_embedded_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_mobile_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_platform.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_server_settings.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_office_view.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _theme = OfficeEmbeddedTheme(
  isDark: false,
  themeId: 'theme-white',
  storedTheme: '{"id":"theme-white"}',
  background: '#FFFFFF',
);

/// Scratch space inside the package's build folder.
Directory _scratch(String name) {
  final parent = Directory(
    p.join(Directory.current.path, 'build', 'office_android_bundle_test'),
  );
  final directory = Directory(
    p.join(parent.path, '$name-${DateTime.now().microsecondsSinceEpoch}'),
  )..createSync(recursive: true);
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
    if (parent.existsSync() && parent.listSync().isEmpty) {
      parent.deleteSync();
    }
  });
  return directory;
}

/// The files the editor cannot start without, as an unpacked copy has them.
void _writeBundle(Directory root) {
  void write(String path, List<int> bytes) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  write(
    'editor.html',
    utf8.encode('<!doctype html><html><head></head><body>editor</body></html>'),
  );
  write('web-apps/apps/api/documents/api.js', utf8.encode('// api'));
  write('sdkjs/common/wasm/x2t/x2t.wasm.br', gzip.encode([0, 97, 115, 109]));
}

/// flutter_test answers every HttpClient request with a 400; this talks to a
/// real loopback server.
class _RealHttp extends HttpOverrides {}

Future<(int, String)> _get(Uri uri) async {
  final client =
      HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttp());
  try {
    final response = await (await client.getUrl(uri)).close();
    return (response.statusCode, await utf8.decodeStream(response));
  } finally {
    client.close(force: true);
  }
}

class _FakeInstaller implements OfficeEditorBundleInstaller {
  _FakeInstaller({
    this.packaged = true,
    this.unpacked = false,
    this.bytes,
    this.bundle,
  });

  final bool packaged;
  final bool unpacked;
  final int? bytes;
  final Directory? bundle;
  final ValueNotifier<OfficeEditorInstallProgress?> progressNotifier =
      ValueNotifier(null);

  /// Lets a test hold [install] open, or fail it.
  Completer<Directory>? pending;
  int installs = 0;
  Directory? _installed;

  @override
  Future<bool> isPackaged() async => packaged;

  @override
  Future<OfficeEditorInstallStatus> status() async => OfficeEditorInstallStatus(
        packaged: packaged,
        installed: unpacked,
        bytes: bytes,
      );

  @override
  Future<Directory> install() async {
    installs++;
    final directory = await (pending?.future ?? Future.value(bundle!));
    _installed = directory;
    return directory;
  }

  @override
  Directory? get installed => _installed;

  @override
  ValueListenable<OfficeEditorInstallProgress?> get progress =>
      progressNotifier;
}

class _EmptyStore extends OfficeServerStore {
  const _EmptyStore();

  @override
  Future<OfficeServerSettings> read() async => const OfficeServerSettings();

  @override
  Future<void> write(OfficeServerSettings settings) async {}
}

enum _Look { light, dark, paper }

ThemeData _material(_Look look) => switch (look) {
      _Look.light => ThemeData.light(),
      _Look.dark => ThemeData.dark(),
      _Look.paper => ThemeData.light().copyWith(
          extensions: const [PaperThemeExtension(enabled: true)],
        ),
    };

AppFlowyThemeData _appFlowy(_Look look) => look == _Look.dark
    ? AppFlowyDefaultTheme().dark()
    : AppFlowyDefaultTheme().light();

Widget _app(_Look look, Widget home) => MaterialApp(
      theme: _material(look),
      builder: (context, child) =>
          AppFlowyTheme(data: _appFlowy(look), child: child!),
      home: home,
    );

/// Takes Android's paths for the rest of the test.
void _android() {
  debugOfficePlatformOverride = TargetPlatform.android;
  addTearDown(() => debugOfficePlatformOverride = null);
}

void _phone(WidgetTester tester, double width) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('AndroidOfficeEditorBundle', () {
    var channels = 0;
    late MethodChannel channel;
    late Directory storage;
    late Directory target;
    late List<MethodCall> calls;

    setUp(() {
      channel = MethodChannel('test/office_editor_bundle/${channels++}');
      storage = _scratch('storage');
      target = Directory(p.join(storage.path, kOfficeEditorFolderName));
      calls = [];
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    AndroidOfficeEditorBundle bundle(
      Future<Object?> Function(MethodCall call) platform,
    ) {
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return platform(call);
      });
      return AndroidOfficeEditorBundle(
        channel: channel,
        storage: () async => storage,
      );
    }

    Future<void> progress(int copied, int total) {
      final completer = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('progress', {'copied': copied, 'total': total}),
        ),
        (_) => completer.complete(),
      );
      return completer.future;
    }

    test('asks the APK whether it carries the editor', () async {
      final yes = bundle((call) async => call.method == 'packaged');
      expect(await yes.isPackaged(), isTrue);
      final no = bundle((call) async => false);
      expect(await no.isPackaged(), isFalse);
    });

    test('reports a current copy only when its files are there', () async {
      final installer = bundle(
        (call) async => {'packaged': true, 'installed': true, 'bytes': 1234},
      );
      var status = await installer.status();
      expect(calls.single.arguments, {'target': target.path});
      expect(status.packaged, isTrue);
      expect(status.bytes, 1234);
      // The marker alone is not enough without the files it vouches for.
      expect(status.installed, isFalse);

      _writeBundle(target);
      status = await installer.status();
      expect(status.installed, isTrue);
    });

    test('unpacks into the app files, reporting progress', () async {
      final seen = <OfficeEditorInstallProgress?>[];
      late AndroidOfficeEditorBundle installer;
      installer = bundle((call) async {
        expect(call.method, 'extract');
        await progress(0, 0);
        await progress(50, 200);
        await progress(200, 200);
        _writeBundle(Directory(call.arguments['target'] as String));
        return {'path': target.path, 'extracted': true};
      });
      installer.progress.addListener(() => seen.add(installer.progress.value));

      final first = installer.install();
      final second = installer.install();
      final directory = await first;
      expect(await second, directory);

      expect(directory.path, target.path);
      expect(installer.installed?.path, target.path);
      expect(calls, hasLength(1), reason: 'both views share one copy');
      expect(calls.single.arguments, {'target': target.path, 'force': false});
      expect(
        seen,
        const [
          OfficeEditorInstallProgress(copiedBytes: 0, totalBytes: 0),
          OfficeEditorInstallProgress(copiedBytes: 50, totalBytes: 200),
          OfficeEditorInstallProgress(copiedBytes: 200, totalBytes: 200),
          null,
        ],
      );
      expect(seen[1]!.fraction, 0.25);
      expect(seen.first!.fraction, isNull);

      // A later open reuses the copy without asking again.
      await installer.install();
      expect(calls, hasLength(1));
    });

    test('copies again when a current copy has lost files', () async {
      final installer = bundle((call) async {
        if (call.arguments['force'] == true) {
          _writeBundle(target);
        }
        return {'path': target.path, 'extracted': false};
      });
      expect((await installer.install()).path, target.path);
      expect(
        calls.map((call) => call.arguments['force']),
        [false, true],
      );
    });

    test('fails clearly when the copy stays incomplete', () async {
      final installer = bundle((call) async => {'extracted': true});
      await expectLater(
        installer.install(),
        throwsA(
          isA<OfficeEditorInstallException>().having(
            (error) => error.message,
            'message',
            contains('incomplete'),
          ),
        ),
      );
      expect(installer.installed, isNull);
    });

    test('explains a lack of storage', () async {
      final installer = bundle((call) async {
        throw PlatformException(
          code: 'no_space',
          message: 'needs more',
          details: {'required': 500 * 1024 * 1024, 'available': 1},
        );
      });
      await expectLater(
        installer.install(),
        throwsA(
          isA<OfficeEditorInstallException>().having(
            (error) => error.message,
            'message',
            allOf(contains('not enough free storage'), contains('500 MB')),
          ),
        ),
      );
      expect(installer.progress.value, isNull);

      final unpackaged = bundle((call) async {
        throw PlatformException(code: 'not_packaged');
      });
      await expectLater(
        unpackaged.install(),
        throwsA(
          isA<OfficeEditorInstallException>().having(
            (error) => error.message,
            'message',
            contains('does not include'),
          ),
        ),
      );
    });
  });

  group('EmbeddedOfficeHost with an installer', () {
    test('desktop hosts stay synchronous and never unpack', () async {
      final bundle = _scratch('desktop');
      _writeBundle(bundle);
      final host = EmbeddedOfficeHost(locate: () => bundle);
      expect(host.installer, isNull);
      expect(host.installProgress, isNull);
      expect(host.isAvailable, isA<SynchronousFuture<bool>>());
      expect(await host.isAvailable, isTrue);
    });

    test('is available when the APK carries the editor', () async {
      final packaged = EmbeddedOfficeHost(installer: _FakeInstaller());
      expect(await packaged.isAvailable, isTrue);
      expect(packaged.bundle, isNull, reason: 'nothing is unpacked yet');
      final missing = EmbeddedOfficeHost(
        installer: _FakeInstaller(packaged: false),
      );
      expect(await missing.isAvailable, isFalse);
    });

    test('unpacks before serving the first document', () async {
      final bundle = _scratch('unpacked');
      _writeBundle(bundle);
      final work = _scratch('work');
      final file = File(p.join(work.path, 'Report.docx'))
        ..writeAsBytesSync([1, 2, 3]);
      final installer = _FakeInstaller(bundle: bundle);
      final host = EmbeddedOfficeHost(installer: installer);
      addTearDown(host.shutdown);
      expect(host.installProgress, same(installer.progress));

      final session = await host.open(
        file: file,
        fileName: 'Report.docx',
        editable: true,
        theme: _theme,
      );
      expect(installer.installs, 1);
      expect(host.bundle?.path, bundle.path);
      expect(host.origin.host, '127.0.0.1');

      final (status, body) = await _get(host.origin.resolve('/editor.html'));
      expect(status, HttpStatus.ok);
      expect(body, contains('/__appflowy__/shim.js'));
      expect(session.pageUrl.path, startsWith('/__appflowy__/office/'));
    });

    test('passes on why unpacking failed', () async {
      final pending = Completer<Directory>();
      final host = EmbeddedOfficeHost(
        installer: _FakeInstaller()..pending = pending,
      );
      final opening = host.open(
        file: File('Report.docx'),
        fileName: 'Report.docx',
        editable: true,
        theme: _theme,
      );
      pending.completeError(
        const OfficeEditorInstallException('Not enough storage.'),
      );
      await expectLater(
        opening,
        throwsA(isA<OfficeEditorInstallException>()),
      );
    });
  });

  group('WebView settings', () {
    test('desktop keeps its settings', () {
      for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
        final settings = officeEmbeddedWebViewSettings(platform: platform);
        expect(settings.supportZoom, isFalse);
        expect(settings.transparentBackground, isTrue);
        expect(settings.mediaPlaybackRequiresUserGesture, isFalse);
        expect(settings.supportMultipleWindows, isTrue);
        expect(settings.javaScriptCanOpenWindowsAutomatically, isFalse);
        expect(settings.allowFileAccess, isTrue);
      }
    });

    test('follows the platform AppFlowy runs on', () {
      // flutter_test reports Android as the target platform, yet these tests
      // run on a desktop host.
      expect(
        officeEmbeddedWebViewSettings().allowFileAccess,
        isTrue,
        reason: 'desktop settings on a desktop host',
      );
      _android();
      expect(officeEmbeddedWebViewSettings().allowFileAccess, isFalse);
    });

    test('Android runs the editor and nothing else', () {
      final settings =
          officeEmbeddedWebViewSettings(platform: TargetPlatform.android);
      expect(settings.javaScriptEnabled, isTrue);
      expect(settings.domStorageEnabled, isTrue);
      expect(settings.databaseEnabled, isTrue);
      expect(settings.useHybridComposition, isTrue);
      expect(settings.supportMultipleWindows, isTrue);
      expect(settings.javaScriptCanOpenWindowsAutomatically, isTrue);
      expect(settings.supportZoom, isFalse);
      expect(settings.builtInZoomControls, isFalse);
      expect(settings.transparentBackground, isTrue);
      expect(settings.allowFileAccess, isFalse);
      expect(settings.allowContentAccess, isFalse);
      expect(settings.algorithmicDarkeningAllowed, isFalse);
      expect(settings.forceDark, ForceDark.OFF);
    });
  });

  group('opening office files on Android', () {
    test('uses the desktop notion of an office file', () {
      _android();
      for (final name in [
        'Report.docx',
        'old.doc',
        'Budget.XLSX',
        'deck.pptx',
        'notes.odt',
        'data.csv',
        'data.tsv',
        'letter.rtf',
      ]) {
        expect(opensOfficeFileInApp(name), isTrue, reason: name);
      }
      for (final name in ['paper.pdf', 'photo.png', 'notes.md', null]) {
        expect(opensOfficeFileInApp(name), isFalse, reason: name);
      }
    });

    test('leaves other platforms alone', () {
      addTearDown(() => debugOfficePlatformOverride = null);
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        debugOfficePlatformOverride = platform;
        expect(
          opensOfficeFileInApp('Report.docx'),
          isFalse,
          reason: platform.name,
        );
      }
      debugOfficePlatformOverride = null;
      expect(opensOfficeFileInApp('Report.docx'), isFalse);
    });
  });

  group('full-screen office page', () {
    Future<File> loader({
      required String source,
      required String name,
      required Map<String, String> httpHeaders,
    }) async =>
        File('/documents/$name');

    for (final look in _Look.values) {
      testWidgets('opens over the page and goes back (${look.name})',
          (tester) async {
        _phone(tester, 360);
        await tester.pumpWidget(
          _app(
            look,
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OfficeEditorPage(
                          source: '/documents/Quarterly report.docx',
                          name: 'Quarterly report.docx',
                          editable: true,
                          loader: loader,
                          documentBuilder: (_, file) =>
                              Text('editing ${file.path}'),
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('Quarterly report.docx'), findsOneWidget);
        expect(
          find.text('editing /documents/Quarterly report.docx'),
          findsOneWidget,
        );
        expect(find.byTooltip('Open with another app'), findsOneWidget);

        final scaffold = tester.widget<Scaffold>(
          find.ancestor(
            of: find.text('Quarterly report.docx'),
            matching: find.byType(Scaffold),
          ),
        );
        final background = scaffold.backgroundColor!;
        if (look == _Look.paper) {
          expect(background, PaperTheme.editorBackground);
        } else {
          expect(
            background,
            Theme.of(tester.element(find.text('Quarterly report.docx')))
                .colorScheme
                .surface,
          );
        }

        await tester.tap(find.byType(AppBarImmersiveBackButton));
        await tester.pumpAndSettle();
        expect(find.text('open'), findsOneWidget);
        expect(find.text('Quarterly report.docx'), findsNothing);
      });
    }

    testWidgets('says why a file cannot be loaded', (tester) async {
      _phone(tester, 360);
      await tester.pumpWidget(
        _app(
          _Look.light,
          OfficeEditorPage(
            source: '/gone/Report.docx',
            name: 'Report.docx',
            editable: true,
            loader: ({
              required source,
              required name,
              required httpHeaders,
            }) async =>
                throw const FileSystemException(
              'AppFlowy could not find this file where it was stored.',
            ),
            documentBuilder: (_, __) => const Text('editor'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This file could not be opened'), findsOneWidget);
      expect(
        find.text('AppFlowy could not find this file where it was stored.'),
        findsOneWidget,
      );
      expect(find.text('editor'), findsNothing);
      expect(find.byTooltip('Open with another app'), findsNothing);
    });
  });

  group('office preview card', () {
    for (final look in _Look.values) {
      testWidgets('fits a phone and opens on tap (${look.name})',
          (tester) async {
        _phone(tester, 320);
        var opened = 0;
        await tester.pumpWidget(
          _app(
            look,
            Scaffold(
              body: Column(
                children: [
                  for (final name in [
                    'A very long name for the third quarter budget review.xlsx',
                    'Roadmap.pptx',
                    'Letter.docx',
                  ])
                    OfficeFileLaunchCard(name: name, onOpen: () => opened++),
                ],
              ),
            ),
          ),
        );
        expect(find.text('Spreadsheet · Tap to open'), findsOneWidget);
        expect(find.text('Presentation · Tap to open'), findsOneWidget);
        expect(find.text('Document · Tap to open'), findsOneWidget);

        await tester.tap(find.text('Letter.docx'));
        expect(opened, 1);

        final surface = tester
            .widget<Material>(
              find
                  .ancestor(
                    of: find.byKey(kOfficeFileLaunchCardKey).first,
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color;
        if (look == _Look.paper) {
          expect(surface, PaperTheme.editorPreviewBackground);
        }
        expect(surface, isNot(Colors.white));
      });
    }
  });

  group('document editing settings on a phone', () {
    EmbeddedOfficeEditor editor(_FakeInstaller installer) =>
        EmbeddedOfficeEditor(
          host: EmbeddedOfficeHost(installer: installer),
          presentation: EmbeddedOfficePresentation.webView,
        );

    Future<void> pump(
      WidgetTester tester, {
      required _Look look,
      required double width,
      required EmbeddedOfficeEditor embeddedEditor,
      AuthTypePB auth = AuthTypePB.Local,
    }) async {
      _phone(tester, width);
      await tester.pumpWidget(
        _app(
          look,
          Scaffold(
            body: SettingsOfficeView(
              userProfile: UserProfilePB()..userAuthType = auth,
              store: const _EmptyStore(),
              probe: (_) async => false,
              embeddedEditor: embeddedEditor,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final look in _Look.values) {
      for (final width in [360.0, 420.0]) {
        testWidgets(
          'built-in editor fits ${width.round()} px (${look.name})',
          (tester) async {
            _android();
            await pump(
              tester,
              look: look,
              width: width,
              auth: AuthTypePB.Server,
              embeddedEditor: editor(
                _FakeInstaller(bytes: 413 * 1024 * 1024),
              ),
            );
            expect(find.textContaining('on this device'), findsOneWidget);
            expect(find.textContaining('this computer'), findsNothing);
            expect(
              find.textContaining('first time you open a document'),
              findsOneWidget,
            );
            expect(find.textContaining('about 413 MB'), findsOneWidget);
            expect(find.text('Direct document server'), findsNothing);
          },
        );

        testWidgets(
          'server form fits ${width.round()} px (${look.name})',
          (tester) async {
            _android();
            await pump(
              tester,
              look: look,
              width: width,
              embeddedEditor: editor(_FakeInstaller(packaged: false)),
            );
            expect(find.text('Direct document server'), findsOneWidget);
            expect(find.text('https://docs.example.com'), findsOneWidget);
            expect(find.text('http://localhost:8080'), findsNothing);

            await tester.tap(find.text('Advanced settings'));
            await tester.pumpAndSettle();
            expect(find.text('192.168.1.20'), findsOneWidget);
            expect(
              find.textContaining('address on your network'),
              findsOneWidget,
            );
          },
        );
      }
    }

    testWidgets(
      'says when the editor is ready',
      (tester) async {
        _android();
        await pump(
          tester,
          look: _Look.light,
          width: 360,
          embeddedEditor: editor(
            _FakeInstaller(unpacked: true, bytes: 413 * 1024 * 1024),
          ),
        );
        expect(
          find.text(
            'The built-in editor is ready on this device '
            '(about 413 MB of storage).',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('keeps the desktop wording on a computer', (tester) async {
      await pump(
        tester,
        look: _Look.light,
        width: 840,
        auth: AuthTypePB.Server,
        embeddedEditor: editor(_FakeInstaller()),
      );
      expect(find.textContaining('on this computer'), findsOneWidget);
    });
  });

  group('preparing the editor', () {
    Future<_FakeInstaller> pump(WidgetTester tester) async {
      final installer = _FakeInstaller()..pending = Completer<Directory>();
      _phone(tester, 360);
      await tester.pumpWidget(
        _app(
          _Look.paper,
          Scaffold(
            body: EmbeddedOfficeEditorView(
              editor: EmbeddedOfficeEditor(
                host: EmbeddedOfficeHost(installer: installer),
                presentation: EmbeddedOfficePresentation.webView,
              ),
              request: EmbeddedOfficeRequest(
                file: File('/documents/Report.docx'),
                name: 'Report.docx',
                editable: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return installer;
    }

    testWidgets('shows progress while the editor is unpacked', (tester) async {
      final installer = await pump(tester);
      // Opening itself is quiet: the editor's card, without a message.
      expect(
        find.byKey(const ValueKey('office-editor-opening')),
        findsOneWidget,
      );
      expect(find.text('Opening the document...'), findsNothing);

      installer.progressNotifier.value = const OfficeEditorInstallProgress(
        copiedBytes: 0,
        totalBytes: 0,
      );
      await tester.pump();
      expect(find.text('Preparing the document editor...'), findsOneWidget);

      installer.progressNotifier.value = const OfficeEditorInstallProgress(
        copiedBytes: 42,
        totalBytes: 100,
      );
      await tester.pump();
      expect(
        find.text('Preparing the document editor... 42%'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        0.42,
      );

      installer.progressNotifier.value = null;
      installer.pending!.completeError(
        const OfficeEditorInstallException(
          'There is not enough free storage to prepare the document editor.',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('This document could not be opened'), findsOneWidget);
      expect(
        find.text(
          'There is not enough free storage to prepare the document editor.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
