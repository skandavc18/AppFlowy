import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_cloud_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_bridge.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_editor_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_editor_scroll.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_editor_skin.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_server_settings.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/presentation/settings/pages/settings_office_view.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

OfficeEditorSkin _skinFor({required bool isDark, bool paper = false}) {
  final appTheme = paper
      ? AppTheme.builtins.firstWhere(
          (theme) => theme.themeName == BuiltInTheme.paper,
        )
      : AppTheme.fallback;
  return OfficeEditorSkin.fromPalette(
    PremiumTheme.resolve(
      appTheme: appTheme,
      legacy: isDark ? appTheme.darkTheme : appTheme.lightTheme,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ),
    isDark: isDark,
  );
}

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

    test('leaves naming the file to AppFlowy', () {
      final config = _editorConfigOf(render());
      final customization = (config['editorConfig']
          as Map<String, dynamic>)['customization'] as Map<String, dynamic>;

      expect(customization['toolbarHideFileName'], isTrue);
      expect(customization['suggestFeature'], isFalse);
      expect(customization['features'], {'featuresTips': false});
      expect(customization['compactHeader'], isTrue);
      expect(customization['autosave'], isTrue);
    });
  });

  group('office editor skin', () {
    test('paints Paper chrome with its warm stationery surfaces', () {
      final skin = _skinFor(isDark: false, paper: true);
      final tokens = officeThemeTokens(skin);

      expect(skin.desk, PaperTheme.editorPreviewBackground);
      expect(skin.raised, PaperTheme.popupBackground);
      expect(skin.baseThemeId, 'theme-white');
      for (final token in [
        'toolbar-header-spreadsheet',
        'toolbar-header-document',
        'background-pane',
        'canvas-background',
      ]) {
        expect(
          tokens[token],
          officeCssColor(PaperTheme.editorPreviewBackground),
        );
      }
      expect(
        tokens['background-toolbar'],
        officeCssColor(PaperTheme.popupBackground),
      );
      expect(tokens['icon-blue-primary'], officeCssColor(PaperTheme.accent));
      expect(
        tokens['highlight-toolbar-tab-underline-spreadsheet'],
        officeCssColor(PaperTheme.accent),
      );
      expect(
        tokens['canvas-cell-title-background'],
        officeCssColor(PaperTheme.controlBackground),
      );
      expect(tokens['canvas-scroll-arrow'], officeCssColor(skin.textMuted));
      expect(tokens.values, isNot(contains('#FFFFFF')));
    });

    test('keeps Light and Paper distinct and Dark on the Night base', () {
      final light = _skinFor(isDark: false);
      final paper = _skinFor(isDark: false, paper: true);
      final dark = _skinFor(isDark: true);

      expect(light, isNot(paper));
      expect(light, _skinFor(isDark: false));
      expect(dark.baseThemeId, 'theme-night');
      expect(
        officeThemeTokens(dark)['background-toolbar'],
        officeCssColor(dark.raised),
      );
      expect(dark.desk.computeLuminance(), lessThan(0.05));
    });

    test('every surface and ink colour is opaque', () {
      for (final skin in [
        _skinFor(isDark: false),
        _skinFor(isDark: false, paper: true),
        _skinFor(isDark: true),
      ]) {
        for (final color in [
          skin.desk,
          skin.raised,
          skin.muted,
          skin.hover,
          skin.pressed,
          skin.textPrimary,
          skin.textSecondary,
          skin.textMuted,
          skin.accent,
          skin.onAccent,
        ]) {
          expect(color.a, 1);
        }
        for (final entry in officeThemeTokens(skin).entries) {
          expect(
            entry.value,
            anyOf(
              matches(RegExp(r'^#[0-9A-F]{6}$')),
              contains('rgba('),
            ),
            reason: entry.key,
          );
        }
      }
    });

    test('stores an overriding copy of the stock modern theme', () {
      final skin = _skinFor(isDark: false, paper: true);
      final stored = officeStoredUiTheme(skin);
      final colors = stored['colors']! as Map<String, String>;
      final skeleton = stored['skeleton']! as Map<String, String>;

      expect(stored['id'], 'theme-white');
      expect(stored['type'], 'light');
      expect(colors, isNotEmpty);
      expect(colors.values, everyElement(endsWith(' !important')));
      expect(
        skeleton['css'],
        allOf(
          startsWith('.loadmask{'),
          contains(
            '--sk-canvas-background:'
            '${officeCssColor(PaperTheme.editorPreviewBackground)} !important',
          ),
        ),
      );
      expect(
        jsonDecode(officeStoredUiThemeJson(skin)),
        jsonDecode(jsonEncode(stored)),
      );
    });

    testWidgets('follows Paper without the application palette',
        (tester) async {
      late OfficeEditorSkin skin;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [PaperThemeExtension(enabled: true)],
          ),
          home: Builder(
            builder: (context) {
              skin = OfficeEditorSkin.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(skin.isDark, isFalse);
      expect(skin.desk, PaperTheme.editorPreviewBackground);
      expect(skin.accent, PaperTheme.accent);
    });
  });

  group('office theme storage script', () {
    test('overrides the saved theme in every document-server frame', () {
      final skin = _skinFor(isDark: true);
      final script = buildOfficeThemeStorageUserScript(
        documentServerUrl: 'https://docs.example.com:8443/office/',
        skin: skin,
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
      expect(
        script.source,
        contains('"ui-theme", ${jsonEncode(officeStoredUiThemeJson(skin))}'),
      );
    });

    test('uses the modern light preference in light mode', () {
      final script = buildOfficeThemeStorageUserScript(
        documentServerUrl: 'http://localhost:8080',
        skin: _skinFor(isDark: false, paper: true),
      );

      expect(script.source, contains('"theme-white"'));
      expect(script.source, isNot(contains('"theme-night"')));
      expect(script.source, contains('"content-theme"'));
      expect(script.source, contains('"light"'));
      expect(
        script.source,
        contains(officeCssColor(PaperTheme.editorPreviewBackground)),
      );
    });
  });

  group('office editor chrome', () {
    test('inlines the app face at the regular weight for editor frames', () {
      const typography = OfficeEditorTypography(
        family: 'DM Sans',
        fontFace: '@font-face{font-family:"AppFlowy UI";}',
      );
      final script = buildOfficeEditorChromeUserScript(
        documentServerUrl: 'https://docs.example.com:8443/office/',
        typography: typography,
      );
      final css = officeEditorChromeCss(typography);

      expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(script.forMainFrameOnly, isFalse);
      expect(script.allowedOriginRules, {'https://docs.example.com:8443'});
      expect(script.source, contains('"https://docs.example.com:8443"'));
      expect(script.source, contains('spreadsheeteditor|presentationeditor'));
      expect(script.source, contains(jsonEncode(css)));
      expect(
        css,
        contains(
          '--font-family-base-custom: "AppFlowy UI", "Segoe UI", '
          'system-ui, sans-serif !important;',
        ),
      );
      expect(css, contains('letter-spacing: -0.005em;'));
      expect(css, contains('border-radius: 999px !important;'));
      expect(css, contains('var(--canvas-scroll-thumb)'));
    });

    test('keeps smooth text and rounded canvas bars without arrows', () {
      final source = buildOfficeEditorChromeScript(
        documentServerOrigin: 'http://localhost:8080',
        typography: const OfficeEditorTypography(family: 'DM Sans'),
      );

      for (final key in [
        'de-settings-fontrender',
        'sse-settings-fontrender',
        'pe-settings-fontrender',
      ]) {
        expect(source, contains("'$key'"));
      }
      expect(source, contains("getItem(key) === null"));
      expect(source, contains('settings.showArrows = false'));
      expect(source, contains('proto._drawScroll = function'));
      expect(source, contains('context.roundRect(x, y, w, h, radius)'));
      expect(source, contains('settings.scrollerHoverColor'));
    });

    test('asks for an installed downloaded family before the bundled face', () {
      final css = officeEditorChromeCss(
        const OfficeEditorTypography(
          family: 'Lato"; } body { display: none',
          fontFace: '@font-face{}',
        ),
      );

      expect(
        css,
        contains(
          '--font-family-base: "Lato  body  display none", "AppFlowy UI", '
          '"Segoe UI"',
        ),
      );
      expect(css, isNot(contains('Lato"')));
      expect(css, isNot(contains('body { display')));
    });

    test('reads the bundled face once and falls back without it', () async {
      final bundle = _FontBundle();
      final typography = await loadOfficeEditorTypography('', bundle: bundle);

      expect(typography.family, 'DM Sans');
      expect(typography.isBundled, isTrue);
      expect(
        bundle.loaded,
        ['assets/google_fonts/DM_Sans/DMSans-Variable.ttf'],
      );
      expect(
        typography.fontFace,
        allOf(
          contains('font-family:"AppFlowy UI"'),
          contains('font-weight:550 1000'),
          contains('base64,${base64Encode(const [1, 2, 3])}'),
        ),
      );

      final missing = await loadOfficeEditorTypography(
        'Inter',
        bundle: _FontBundle(fail: true),
      );
      expect(missing.family, 'Inter');
      expect(missing.fontFace, isEmpty);
    });
  });

  group('office editor scrolling', () {
    test('relays only the editor frame scroll fields to Flutter', () {
      final relay = buildOfficeScrollRelayScript('https://docs.example.com/x/');

      expect(relay, contains('var serverOrigin = "https://docs.example.com"'));
      expect(relay, contains('event.origin !== serverOrigin'));
      expect(relay, contains("callHandler('$officeScrollHandlerName'"));
      expect(relay, contains('window.__appflowyOfficeScrollCommand'));
      expect(
        buildOfficeEditorHtml(
          serverOrigin: 'http://docs.local',
          document: const BridgedOfficeDocument(
            downloadUrl: 'http://host:1234/documents/tok/file.docx',
            callbackUrl: 'http://host:1234/documents/tok/callback',
            token: 'tok',
          ),
          fileName: 'Report.docx',
          documentKey: 'key-1',
          editable: true,
          isDark: false,
          background: const Color(0xFFFFFFFF),
          secret: '',
        ),
        contains('var serverOrigin = "http://docs.local"'),
      );
    });

    test('eases wheel notches with the app physics in editor frames only', () {
      const config = PremiumScrollPhysicsConfig();
      final script = buildOfficeScrollUserScript(
        documentServerUrl: 'https://docs.example.com:8443/office/',
        hostUrl: 'http://localhost:51234/editors/token',
        config: config,
        smooth: true,
      );

      expect(script.forMainFrameOnly, isFalse);
      expect(script.allowedOriginRules, {'https://docs.example.com:8443'});
      expect(
        script.source,
        allOf(
          contains('const ORIGIN = "https://docs.example.com:8443"'),
          contains('const HOST = "http://localhost:51234"'),
          contains('window.parent === window'),
          contains('const UNITS_PER_PIXEL = 1.2;'),
          contains('const SMOOTH = true;'),
        ),
      );
      expect(
        script.source,
        allOf(
          contains('rate: ${config.wheelSmoothingRate}'),
          contains('speed: ${config.maxWheelScrollVelocity}'),
          contains('friction: ${config.desktopCoastFriction}'),
          contains("{ capture: true, passive: false }"),
          contains('event.source !== window.parent || event.origin !== HOST'),
        ),
      );
      // A release command can overtake its gesture's last input; that input
      // must not cancel the coast, while a new gesture always stops it.
      expect(
        script.source,
        allOf(
          contains('grace: 120'),
          contains('state.fling && now - state.flingAt < C.grace'),
          contains('state.flingAt = performance.now();'),
          contains('if (command.on === true) halt();'),
        ),
      );
      expect(
        buildOfficeScrollRuntimeScript(
          documentServerOrigin: 'http://localhost:8080',
          hostOrigin: 'http://localhost:1',
          config: config,
          smooth: false,
        ),
        contains('const SMOOTH = false;'),
      );
    });

    test('tracks the reported top and ignores malformed messages', () {
      final controller = OfficeEditorScrollController();

      expect(controller.editorAtTop, isNull);
      controller.handleMessage([
        {'t': 'state', 'atTop': false},
      ]);
      expect(controller.editorAtTop, isFalse);
      for (final message in [
        <String, Object>{'t': 'over', 'dy': 12},
        <String, Object>{'t': 'over', 'dy': 'far'},
        <String, Object>{'t': 'state', 'atTop': 'yes'},
        <String, Object>{'t': 'unknown'},
      ]) {
        controller.handleMessage([message]);
      }
      controller.handleMessage(const []);
      controller.handleMessage(const ['text']);
      expect(controller.editorAtTop, isFalse);
      controller.handleMessage([
        {'t': 'over', 'dy': -8},
      ]);
      expect(controller.editorAtTop, isTrue);
      controller.detach();
      expect(controller.editorAtTop, isNull);
    });
  });

  group('office editor appearance refresh', () {
    final light = _skinFor(isDark: false);
    final paper = _skinFor(isDark: false, paper: true);
    final dark = _skinFor(isDark: true);

    test('refreshes the editor page for a direct server theme change', () {
      expect(
        officeEditorRefreshAction(
          managed: false,
          editorSkin: light,
          skin: dark,
        ),
        OfficeEditorRefreshAction.editorPage,
      );
    });

    test('requests a signed config for a managed server theme change', () {
      expect(
        officeEditorRefreshAction(
          managed: true,
          editorSkin: light,
          skin: dark,
        ),
        OfficeEditorRefreshAction.managedSession,
      );
    });

    test('refreshes only the page when the palette changes', () {
      expect(
        officeEditorRefreshAction(
          managed: true,
          editorSkin: light,
          skin: paper,
        ),
        OfficeEditorRefreshAction.editorPage,
      );
      expect(
        officeEditorRefreshAction(
          managed: true,
          editorSkin: light,
          skin: _skinFor(isDark: false),
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

class _FontBundle extends CachingAssetBundle {
  _FontBundle({this.fail = false});

  final bool fail;
  final loaded = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    if (fail) throw FlutterError('Missing $key');
    return ByteData.sublistView(Uint8List.fromList(const [1, 2, 3]));
  }
}

Map<String, dynamic> _editorConfigOf(String html) {
  final match = RegExp(
    r"new DocsAPI\.DocEditor\('appflowy-office', (.*)\);",
  ).firstMatch(html);
  expect(match, isNotNull);
  return jsonDecode(match!.group(1)!) as Map<String, dynamic>;
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
