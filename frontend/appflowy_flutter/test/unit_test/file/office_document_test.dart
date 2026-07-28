import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_cloud_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_bridge.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_server_settings.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_office_view.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  group('officeDocumentTypeFor', () {
    test('maps office extensions to the editor families', () {
      expect(officeDocumentTypeFor('a.docx'), OfficeDocumentType.word);
      expect(officeDocumentTypeFor('a.ODT'), OfficeDocumentType.word);
      expect(officeDocumentTypeFor('a.xlsx'), OfficeDocumentType.cell);
      expect(officeDocumentTypeFor('a.pptx'), OfficeDocumentType.slide);
      expect(officeDocumentTypeFor('a.png'), isNull);
    });
  });

  group('OfficeServerSettings', () {
    test('normalizes the server address', () {
      const settings = OfficeServerSettings(serverUrl: 'localhost:8080/');
      expect(settings.baseUri.toString(), 'http://localhost:8080');
      expect(settings.isConfigured, isTrue);
      expect(const OfficeServerSettings().isConfigured, isFalse);
    });

    test('rejects unsupported and malformed server addresses', () {
      expect(
        const OfficeServerSettings(serverUrl: 'ftp://docs.local').baseUri,
        isNull,
      );
      expect(
        const OfficeServerSettings(serverUrl: 'http:///missing-host').baseUri,
        isNull,
      );
      expect(validateOfficeServerUrl('not a valid address'), isNotNull);
      expect(validateOfficeServerUrl('https://docs.local'), isNull);
    });

    test('routes the callback back through the docker host by default', () {
      const local = OfficeServerSettings(serverUrl: 'http://localhost:8080');
      expect(local.resolveBridgeHost(), 'host.docker.internal');

      const explicit = OfficeServerSettings(
        serverUrl: 'http://127.0.0.1:8080',
        bridgeHost: '192.168.1.20',
      );
      expect(explicit.resolveBridgeHost(), '192.168.1.20');
    });

    test('round trips through json', () {
      const settings = OfficeServerSettings(
        serverUrl: 'http://docs.local',
        jwtSecret: 'secret',
        bridgeHost: 'host',
      );
      expect(
        OfficeServerSettings.fromJson(
          Map<String, dynamic>.from(settings.toJson()),
        ),
        settings,
      );
    });
  });

  group('officeJwt', () {
    test('produces a three part token with the payload in the middle', () {
      final token = officeJwt(const {'a': 1}, 'secret');
      final parts = token.split('.');
      expect(parts, hasLength(3));
      expect(
        jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ),
        {'a': 1},
      );
      expect(officeJwt(const {'a': 1}, 'other'), isNot(token));
    });
  });

  group('OfficeDocumentBridge editor host', () {
    tearDown(OfficeDocumentBridge.instance.shutdown);

    test('serves the editor bootstrap from a real localhost HTTP origin',
        () async {
      final editor = await OfficeDocumentBridge.instance.publishEditorPage(
        '<!doctype html><title>Office editor</title>',
      );
      final uri = Uri.parse(editor.url);

      expect(uri.scheme, 'http');
      expect(uri.host, 'localhost');

      final response = await _rawHttpGet(uri);
      expect(response, startsWith('HTTP/1.1 200 OK'));
      expect(response, contains('cache-control: no-store'));
      expect(response, contains('Office editor'));

      OfficeDocumentBridge.instance.revoke(editor.token);
      expect(await _rawHttpGet(uri), startsWith('HTTP/1.1 404 Not Found'));
    });
  });

  group('buildOfficeEditorHtml', () {
    const document = BridgedOfficeDocument(
      downloadUrl: 'http://host:1234/documents/tok/file.docx',
      callbackUrl: 'http://host:1234/documents/tok/callback',
      token: 'tok',
    );

    String render({
      bool editable = true,
      bool isDark = false,
      String secret = '',
    }) {
      return buildOfficeEditorHtml(
        serverOrigin: 'http://docs.local',
        document: document,
        fileName: 'Report.docx',
        documentKey: 'key-1',
        editable: editable,
        isDark: isDark,
        background: const Color(0xFFFFFFFF),
        secret: secret,
      );
    }

    test('loads the api from the configured server', () {
      expect(
        render(),
        contains('http://docs.local/web-apps/apps/api/documents/api.js'),
      );
    });

    test('passes the bridge urls and edit mode', () {
      final html = render();
      expect(html, contains(document.downloadUrl));
      expect(html, contains(document.callbackUrl));
      expect(html, contains('"mode":"edit"'));
      expect(html, contains('"documentType":"word"'));
      expect(html, contains('"fileType":"docx"'));
    });

    test('drops the callback when the file is read only', () {
      final html = render(editable: false);
      expect(html, contains('"mode":"view"'));
      expect(html, isNot(contains(document.callbackUrl)));
    });

    test('signs the configuration when a secret is set', () {
      expect(render(), isNot(contains('"token"')));
      expect(render(secret: 'shh'), contains('"token":"'));
    });

    test('uses the modern light and dark themes', () {
      expect(render(), contains('"uiTheme":"theme-white"'));
      expect(render(isDark: true), contains('"uiTheme":"theme-night"'));
      expect(render(), isNot(contains('theme-classic-light')));
    });
  });

  group('office theme storage script', () {
    test('overrides the saved theme in every document-server frame', () {
      final script = buildOfficeThemeStorageUserScript(
        documentServerUrl: 'https://docs.example.com:8443/office/',
        isDark: true,
      );

      expect(
        script.injectionTime,
        UserScriptInjectionTime.AT_DOCUMENT_START,
      );
      expect(script.forMainFrameOnly, isFalse);
      expect(
        script.allowedOriginRules,
        {'https://docs.example.com:8443'},
      );
      expect(
        script.source,
        contains(
          'window.location.origin === "https://docs.example.com:8443"',
        ),
      );
      expect(script.source, contains('"ui-theme-id"'));
      expect(script.source, contains('"theme-night"'));
      expect(script.source, contains('"content-theme"'));
      expect(script.source, contains('"dark"'));
      expect(script.source, isNot(contains('/office/')));
    });

    test('uses the modern light preference in light mode', () {
      final script = buildOfficeThemeStorageUserScript(
        documentServerUrl: 'http://localhost:8080',
        isDark: false,
      );

      expect(script.source, contains('"theme-white"'));
      expect(script.source, isNot(contains('"theme-night"')));
      expect(script.source, contains('"content-theme"'));
      expect(script.source, contains('"light"'));
    });
  });

  group('office editor appearance refresh', () {
    const lightBackground = Color(0xFFFFFFFF);
    const darkBackground = Color(0xFF202020);

    test('refreshes the editor page for a direct server theme change', () {
      expect(
        officeEditorRefreshAction(
          managed: false,
          editorIsDark: false,
          editorBackground: lightBackground,
          isDark: true,
          background: darkBackground,
        ),
        OfficeEditorRefreshAction.editorPage,
      );
    });

    test('requests a signed config for a managed server theme change', () {
      expect(
        officeEditorRefreshAction(
          managed: true,
          editorIsDark: false,
          editorBackground: lightBackground,
          isDark: true,
          background: darkBackground,
        ),
        OfficeEditorRefreshAction.managedSession,
      );
    });

    test('refreshes only the page when the surface color changes', () {
      expect(
        officeEditorRefreshAction(
          managed: true,
          editorIsDark: false,
          editorBackground: lightBackground,
          isDark: false,
          background: const Color(0xFFF7F1E7),
        ),
        OfficeEditorRefreshAction.editorPage,
      );
      expect(
        officeEditorRefreshAction(
          managed: true,
          editorIsDark: false,
          editorBackground: lightBackground,
          isDark: false,
          background: lightBackground,
        ),
        OfficeEditorRefreshAction.none,
      );
    });
  });

  group('managed office sessions', () {
    test('uses managed sessions for authenticated cloud profiles', () {
      final profile = UserProfilePB()..userAuthType = AuthTypePB.Server;

      expect(usesManagedOfficeServer(profile), isTrue);
    });

    test('uses managed sessions for server workspaces', () {
      final profile = UserProfilePB()
        ..userAuthType = AuthTypePB.Local
        ..workspaceType = WorkspaceTypePB.ServerW;

      expect(usesManagedOfficeServer(profile), isTrue);
    });

    test('uses managed sessions when a cloud access token is present', () {
      final profile = UserProfilePB()
        ..userAuthType = AuthTypePB.Local
        ..workspaceType = WorkspaceTypePB.LocalW
        ..token = jsonEncode({'access_token': 'cloud-token'});

      expect(usesManagedOfficeServer(profile), isTrue);
    });

    test('decodes the cloud editor configuration', () {
      final session = ManagedOfficeSession.fromJson({
        'session_id': 'session-1',
        'document_server_url': 'https://cloud.example.com/office',
        'editor_config': {
          'documentType': 'word',
          'token': 'server-signed-token',
        },
      });

      expect(session.sessionId, 'session-1');
      expect(
        session.documentServerUrl,
        'https://cloud.example.com/office',
      );
      expect(session.editorConfig['token'], 'server-signed-token');
    });

    test('reuses the managed session when refreshing its theme', () {
      final request = buildOfficeSessionRequest(
        storageUrl: 'https://cloud.example.com/file.docx',
        fileName: 'Report.docx',
        editable: true,
        userName: 'AppFlowy User',
        isDark: true,
        sessionId: 'session-1',
      );

      expect(request['session_id'], 'session-1');
      expect(request['is_dark'], isTrue);
      expect(
        buildOfficeSessionRequest(
          storageUrl: 'https://cloud.example.com/file.docx',
          fileName: 'Report.docx',
          editable: true,
          userName: 'AppFlowy User',
          isDark: false,
        ),
        isNot(contains('session_id')),
      );
    });

    test('rejects incomplete cloud responses', () {
      expect(
        () => ManagedOfficeSession.fromJson(const {
          'session_id': 'session-1',
          'document_server_url': 'https://cloud.example.com/office',
        }),
        throwsA(isA<OfficeCloudException>()),
      );
      expect(
        () => ManagedOfficeSession.fromJson(const {
          'session_id': 'session-1',
          'document_server_url': 'ftp://cloud.example.com/office',
          'editor_config': {'documentType': 'word'},
        }),
        throwsA(isA<OfficeCloudException>()),
      );
    });

    test('boots the editor with the server-signed configuration', () {
      final html = buildManagedOfficeEditorHtml(
        serverOrigin: 'https://cloud.example.com/office',
        editorConfig: const {
          'documentType': 'word',
          'token': 'server-signed-token',
        },
        background: const Color(0xFFF7F1E7),
      );

      expect(
        html,
        contains(
          'https://cloud.example.com/office/'
          'web-apps/apps/api/documents/api.js',
        ),
      );
      expect(html, contains('"token":"server-signed-token"'));
    });
  });

  group('OfficeDocumentView connection mode', () {
    testWidgets('refreshes a managed session when app brightness changes',
        (tester) async {
      final brightness = ValueNotifier(Brightness.light);
      final cloudService = _RecordingOfficeCloudSessionService();
      addTearDown(brightness.dispose);
      addTearDown(OfficeDocumentBridge.instance.shutdown);

      await tester.pumpWidget(
        _themeSwitchingTestApp(
          brightness: brightness,
          cloudService: cloudService,
        ),
      );
      await tester.pumpAndSettle();

      expect(cloudService.requests, [(isDark: false, sessionId: null)]);

      brightness.value = Brightness.dark;
      await tester.pumpAndSettle();

      expect(
        cloudService.requests,
        [
          (isDark: false, sessionId: null),
          (isDark: true, sessionId: 'session-1'),
        ],
      );

      brightness.value = Brightness.light;
      await tester.pumpAndSettle();

      expect(
        cloudService.requests,
        [
          (isDark: false, sessionId: null),
          (isDark: true, sessionId: 'session-1'),
          (isDark: false, sessionId: 'session-1'),
        ],
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(OfficeDocumentBridge.instance.shutdown);
    });

    testWidgets('shows self-hosted setup only to local users', (tester) async {
      await tester.pumpWidget(
        _testApp(
          const _FakeOfficeCloudSessionService.local(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Set up document editing'), findsOneWidget);
      expect(find.text('Connect server'), findsOneWidget);
    });

    testWidgets('does not expose server settings to cloud users',
        (tester) async {
      var probeCalls = 0;
      await tester.pumpWidget(
        _testApp(
          const _FakeOfficeCloudSessionService.cloudFailure(),
          store: const _ConfiguredOfficeServerStore(),
          probe: (_) async {
            probeCalls++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Document editing is temporarily unavailable'),
        findsOneWidget,
      );
      expect(find.text('Set up document editing'), findsNothing);
      expect(find.text('Open document settings'), findsNothing);
      expect(probeCalls, 0);
    });

    testWidgets(
        'does not reopen first-run setup for an unreachable configured server',
        (tester) async {
      await tester.pumpWidget(
        _testApp(
          const _FakeOfficeCloudSessionService.local(),
          store: const _ConfiguredOfficeServerStore(),
          probe: (_) async => false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Set up document editing'), findsNothing);
      expect(
        find.text('Document server unavailable'),
        findsOneWidget,
      );
      expect(find.text('Open document settings'), findsOneWidget);
    });

    for (final themeCase in <({
      String name,
      Brightness brightness,
      bool paper,
    })>[
      (
        name: 'light',
        brightness: Brightness.light,
        paper: false,
      ),
      (
        name: 'dark',
        brightness: Brightness.dark,
        paper: false,
      ),
      (
        name: 'paper',
        brightness: Brightness.light,
        paper: true,
      ),
    ]) {
      testWidgets('uses a ${themeCase.name} setup surface', (tester) async {
        await tester.pumpWidget(
          _testApp(
            const _FakeOfficeCloudSessionService.local(),
            brightness: themeCase.brightness,
            paper: themeCase.paper,
          ),
        );
        await tester.pumpAndSettle();

        final appFlowyTheme = themeCase.brightness == Brightness.light
            ? AppFlowyDefaultTheme().light()
            : AppFlowyDefaultTheme().dark();
        final expected = themeCase.paper
            ? PaperTheme.editorPreviewBackground
            : appFlowyTheme.fillColorScheme.content;
        final panel = tester.widget<Container>(
          find.byKey(kOfficePanelSurfaceKey),
        );
        final decoration = panel.decoration! as BoxDecoration;
        final border = decoration.border! as Border;
        expect(decoration.color, expected);
        expect(decoration.boxShadow, isNull);
        expect(border.top.width, 1);
      });
    }
  });

  group('document editing settings', () {
    testWidgets('shows direct fallback settings for local users',
        (tester) async {
      await tester.pumpWidget(
        _settingsTestApp(
          UserProfilePB()..userAuthType = AuthTypePB.Local,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Document editing'), findsOneWidget);
      expect(find.text('Direct document server'), findsOneWidget);
      expect(find.text('Document server address'), findsOneWidget);
    });

    testWidgets('explains cloud priority for connected users', (tester) async {
      await tester.pumpWidget(
        _settingsTestApp(
          UserProfilePB()..userAuthType = AuthTypePB.Server,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'AppFlowy Cloud is connected. Office files always use the document '
          'server managed by this Cloud deployment.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'These settings are saved as a local fallback',
        ),
        findsOneWidget,
      );
    });
  });
}

Future<String> _rawHttpGet(Uri uri) async {
  final socket = await Socket.connect(uri.host, uri.port);
  socket.write(
    'GET ${uri.path} HTTP/1.1\r\n'
    'Host: ${uri.host}:${uri.port}\r\n'
    'Connection: close\r\n\r\n',
  );
  await socket.flush();
  return utf8.decoder.bind(socket).join();
}

Widget _testApp(
  OfficeCloudSessionService cloudService, {
  Brightness brightness = Brightness.light,
  bool paper = false,
  OfficeServerStore store = const _EmptyOfficeServerStore(),
  OfficeServerProbe probe = probeOfficeServer,
}) {
  final appFlowyTheme = brightness == Brightness.light
      ? AppFlowyDefaultTheme().light()
      : AppFlowyDefaultTheme().dark();
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      extensions: [
        PaperThemeExtension(enabled: paper),
      ],
    ),
    home: Scaffold(
      body: AppFlowyTheme(
        data: appFlowyTheme,
        child: OfficeDocumentView(
          file: File('Report.docx'),
          name: 'Report.docx',
          source: 'https://cloud.example.com/api/file_storage/Report.docx',
          editable: true,
          store: store,
          cloudService: cloudService,
          probe: probe,
        ),
      ),
    ),
  );
}

Widget _settingsTestApp(UserProfilePB profile) {
  final appFlowyTheme = AppFlowyDefaultTheme().light();
  return MaterialApp(
    home: Scaffold(
      body: AppFlowyTheme(
        data: appFlowyTheme,
        child: SettingsOfficeView(
          userProfile: profile,
          store: const _EmptyOfficeServerStore(),
          probe: (_) async => true,
        ),
      ),
    ),
  );
}

Widget _themeSwitchingTestApp({
  required ValueNotifier<Brightness> brightness,
  required OfficeCloudSessionService cloudService,
}) {
  return ValueListenableBuilder<Brightness>(
    valueListenable: brightness,
    builder: (_, value, __) {
      final appFlowyTheme = value == Brightness.light
          ? AppFlowyDefaultTheme().light()
          : AppFlowyDefaultTheme().dark();
      return MaterialApp(
        theme: ThemeData(brightness: value),
        home: Scaffold(
          body: AppFlowyTheme(
            data: appFlowyTheme,
            child: OfficeDocumentView(
              file: File('Report.docx'),
              name: 'Report.docx',
              source: 'https://cloud.example.com/api/file_storage/Report.docx',
              editable: true,
              cloudService: cloudService,
              editorBuilder: (_, __) => const SizedBox(),
            ),
          ),
        ),
      );
    },
  );
}

class _EmptyOfficeServerStore extends OfficeServerStore {
  const _EmptyOfficeServerStore();

  @override
  Future<OfficeServerSettings> read() async => const OfficeServerSettings();

  @override
  Future<void> write(OfficeServerSettings settings) async {}
}

class _ConfiguredOfficeServerStore extends OfficeServerStore {
  const _ConfiguredOfficeServerStore();

  @override
  Future<OfficeServerSettings> read() async =>
      const OfficeServerSettings(serverUrl: 'http://localhost:8080');

  @override
  Future<void> write(OfficeServerSettings settings) async {}
}

class _RecordingOfficeCloudSessionService implements OfficeCloudSessionService {
  final requests = <({bool isDark, String? sessionId})>[];

  @override
  Future<UserProfilePB?> connectedCloudProfile() async =>
      UserProfilePB()..userAuthType = AuthTypePB.Server;

  @override
  Future<ManagedOfficeSession> createSession({
    required UserProfilePB profile,
    required String storageUrl,
    required String fileName,
    required bool editable,
    required bool isDark,
    String? sessionId,
  }) async {
    requests.add((isDark: isDark, sessionId: sessionId));
    return ManagedOfficeSession(
      sessionId: sessionId ?? 'session-1',
      documentServerUrl: 'https://cloud.example.com/office',
      editorConfig: {
        'documentType': 'word',
        'editorConfig': {
          'customization': {'uiTheme': officeUiTheme(isDark)},
        },
      },
    );
  }
}

class _FakeOfficeCloudSessionService implements OfficeCloudSessionService {
  const _FakeOfficeCloudSessionService.local() : isCloud = false;

  const _FakeOfficeCloudSessionService.cloudFailure() : isCloud = true;

  final bool isCloud;

  @override
  Future<UserProfilePB?> connectedCloudProfile() async {
    if (!isCloud) {
      return null;
    }
    return UserProfilePB()..userAuthType = AuthTypePB.Server;
  }

  @override
  Future<ManagedOfficeSession> createSession({
    required UserProfilePB profile,
    required String storageUrl,
    required String fileName,
    required bool editable,
    required bool isDark,
    String? sessionId,
  }) {
    throw const OfficeCloudException(
      'AppFlowy Cloud could not reach its document server.',
    );
  }
}
