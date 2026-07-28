import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/util/color_to_hex_string.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart'
    as sidebar_settings;
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import 'office_document_bridge.dart';
import 'office_cloud_session.dart';
import 'office_server_settings.dart';
import 'office_server_settings_form.dart';

@visibleForTesting
const kOfficePanelSurfaceKey = ValueKey('office_panel_surface');
@visibleForTesting
const kOfficeEditorScrollExclusionKey =
    ValueKey('office_editor_scroll_exclusion');

/// Opens a Word, Excel or PowerPoint document.
///
/// Cloud accounts receive a managed editor session from AppFlowy Cloud. Local
/// accounts can connect a self-hosted ONLYOFFICE Docs instance instead.
class OfficeDocumentView extends StatefulWidget {
  const OfficeDocumentView({
    super.key,
    required this.file,
    required this.name,
    required this.source,
    required this.editable,
    this.store = const OfficeServerStore(),
    this.cloudService = const AppFlowyCloudOfficeSessionService(),
    this.probe = probeOfficeServer,
    this.editorBuilder,
    this.fallbackBuilder,
  });

  final File file;
  final String name;
  final String source;
  final bool editable;
  final OfficeServerStore store;
  final OfficeCloudSessionService cloudService;
  final OfficeServerProbe probe;

  /// What to show instead of the "no server" panel.
  ///
  /// Formats AppFlowy can already read on its own — a CSV, say — pass their
  /// own renderer here, so losing the Office server costs the editing tools
  /// rather than the file itself.
  final WidgetBuilder? fallbackBuilder;

  @visibleForTesting
  final Widget Function(BuildContext, HostedOfficeEditor)? editorBuilder;

  @override
  State<OfficeDocumentView> createState() => _OfficeDocumentViewState();
}

enum _OfficeConnectionMode {
  unknown,
  local,
  cloud,
}

@visibleForTesting
enum OfficeEditorRefreshAction {
  none,
  editorPage,
  managedSession,
}

@visibleForTesting
OfficeEditorRefreshAction officeEditorRefreshAction({
  required bool managed,
  required bool? editorIsDark,
  required Color? editorBackground,
  required bool isDark,
  required Color background,
}) {
  if (editorIsDark != isDark) {
    return managed
        ? OfficeEditorRefreshAction.managedSession
        : OfficeEditorRefreshAction.editorPage;
  }
  if (editorBackground != background) {
    return OfficeEditorRefreshAction.editorPage;
  }
  return OfficeEditorRefreshAction.none;
}

class _OfficeDocumentViewState extends State<OfficeDocumentView> {
  OfficeServerSettings _settings = const OfficeServerSettings();
  OfficeServerStatus _status = OfficeServerStatus.connecting;
  BridgedOfficeDocument? _bridged;
  HostedOfficeEditor? _hostedEditor;
  ManagedOfficeSession? _managedSession;
  UserProfilePB? _cloudProfile;
  Color? _editorBackground;
  bool? _editorIsDark;
  String? _documentKey;
  String? _errorMessage;
  _OfficeConnectionMode _mode = _OfficeConnectionMode.unknown;
  bool _showInitialSetup = false;
  bool _didLoad = false;
  bool _refreshingEditorPage = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoad) {
      _didLoad = true;
      unawaited(_load());
    } else if (_status == OfficeServerStatus.connected) {
      final action = officeEditorRefreshAction(
        managed: _mode == _OfficeConnectionMode.cloud,
        editorIsDark: _editorIsDark,
        editorBackground: _editorBackground,
        isDark: _currentIsDark(),
        background: _currentEditorBackground(),
      );
      if (action != OfficeEditorRefreshAction.none) {
        unawaited(_refreshEditorAppearance());
      }
    }
  }

  @override
  void dispose() {
    _releaseEditorResources();
    super.dispose();
  }

  void _releaseEditorResources() {
    for (final token in {_bridged?.token, _hostedEditor?.token}) {
      if (token != null) {
        OfficeDocumentBridge.instance.revoke(token);
      }
    }
    _bridged = null;
    _hostedEditor = null;
    _managedSession = null;
    _editorBackground = null;
    _editorIsDark = null;
    _documentKey = null;
  }

  Future<void> _load() async {
    if (mounted) {
      _releaseEditorResources();
      setState(() {
        _status = OfficeServerStatus.connecting;
        _errorMessage = null;
        _showInitialSetup = false;
        _mode = _OfficeConnectionMode.unknown;
        _cloudProfile = null;
      });
    }
    try {
      final profile = await widget.cloudService.connectedCloudProfile();
      if (!mounted) {
        return;
      }
      if (profile != null) {
        setState(() {
          _mode = _OfficeConnectionMode.cloud;
          _cloudProfile = profile;
          _showInitialSetup = false;
        });
        await _connectManaged(profile);
        return;
      }

      setState(() => _mode = _OfficeConnectionMode.local);
      await _loadLocalSettings();
    } catch (error) {
      Log.error('Unable to prepare office document editing: $error');
      if (mounted) {
        setState(() {
          _status = OfficeServerStatus.unreachable;
          _errorMessage = 'AppFlowy could not determine how this document '
              'should be opened. Please try again.';
          _showInitialSetup = false;
        });
      }
    }
  }

  Future<void> _loadLocalSettings() async {
    final settings = await widget.store.read();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
      _showInitialSetup = !settings.isConfigured;
    });
    if (!settings.isConfigured) {
      setState(() {
        _status = OfficeServerStatus.unconfigured;
      });
      return;
    }
    await _connectLocal(settings);
  }

  Future<void> _connectLocal(OfficeServerSettings settings) async {
    setState(() {
      _status = OfficeServerStatus.connecting;
      _errorMessage = null;
    });
    final reachable = await widget.probe(settings);
    if (!mounted) {
      return;
    }
    if (!reachable) {
      setState(() {
        _status = OfficeServerStatus.unreachable;
        _errorMessage =
            'The document server did not answer. Check its address and status.';
      });
      return;
    }

    BridgedOfficeDocument? bridged;
    HostedOfficeEditor? hostedEditor;
    try {
      final stat = await widget.file.stat();
      final previous = _bridged?.token;
      if (previous != null) {
        OfficeDocumentBridge.instance.revoke(previous);
      }
      bridged = await OfficeDocumentBridge.instance.publish(
        file: widget.file,
        host: settings.resolveBridgeHost(),
        secret: settings.jwtSecret.trim(),
        onSaved: _writeBack,
      );
      if (!mounted) {
        OfficeDocumentBridge.instance.revoke(bridged.token);
        return;
      }
      final serverOrigin = settings.baseUri;
      if (serverOrigin == null) {
        throw const FormatException('Invalid document server address');
      }
      final documentKey = _buildDocumentKey(stat.modified);
      final isDark = _currentIsDark();
      final background = _currentEditorBackground();
      hostedEditor = await OfficeDocumentBridge.instance.publishEditorPage(
        buildOfficeEditorHtml(
          serverOrigin: serverOrigin.toString(),
          document: bridged,
          fileName: widget.name,
          documentKey: documentKey,
          editable: widget.editable,
          isDark: isDark,
          background: background,
          secret: settings.jwtSecret.trim(),
        ),
      );
      if (!mounted) {
        OfficeDocumentBridge.instance
          ..revoke(bridged.token)
          ..revoke(hostedEditor.token);
        return;
      }
      final previousEditor = _hostedEditor?.token;
      if (previousEditor != null) {
        OfficeDocumentBridge.instance.revoke(previousEditor);
      }
      setState(() {
        _bridged = bridged;
        _hostedEditor = hostedEditor;
        _editorBackground = background;
        _editorIsDark = isDark;
        _documentKey = documentKey;
        _status = OfficeServerStatus.connected;
        _showInitialSetup = false;
      });
      _refreshAppearanceIfStale(background, isDark);
    } catch (error) {
      final bridgeToken = bridged?.token;
      final editorToken = hostedEditor?.token;
      if (bridgeToken != null && bridgeToken != _bridged?.token) {
        OfficeDocumentBridge.instance.revoke(bridgeToken);
      }
      if (editorToken != null && editorToken != _hostedEditor?.token) {
        OfficeDocumentBridge.instance.revoke(editorToken);
      }
      Log.error('Unable to publish the office document: $error');
      if (mounted) {
        setState(() {
          _status = OfficeServerStatus.unreachable;
          _errorMessage = 'AppFlowy could not share this file with the '
              'document server.';
        });
      }
    }
  }

  Future<void> _connectManaged(UserProfilePB profile) async {
    setState(() {
      _status = OfficeServerStatus.connecting;
      _errorMessage = null;
    });
    try {
      final isDark = _currentIsDark();
      final session = await widget.cloudService.createSession(
        profile: profile,
        storageUrl: widget.source,
        fileName: widget.name,
        editable: widget.editable,
        isDark: isDark,
      );
      if (!mounted) {
        return;
      }
      final background = _currentEditorBackground();
      final hostedEditor =
          await OfficeDocumentBridge.instance.publishEditorPage(
        buildManagedOfficeEditorHtml(
          serverOrigin: session.documentServerUrl,
          editorConfig: session.editorConfig,
          background: background,
        ),
      );
      if (!mounted) {
        OfficeDocumentBridge.instance.revoke(hostedEditor.token);
        return;
      }
      final previousEditor = _hostedEditor?.token;
      if (previousEditor != null) {
        OfficeDocumentBridge.instance.revoke(previousEditor);
      }
      setState(() {
        _managedSession = session;
        _hostedEditor = hostedEditor;
        _editorBackground = background;
        _editorIsDark = isDark;
        _status = OfficeServerStatus.connected;
      });
      _refreshAppearanceIfStale(background, isDark);
    } catch (error) {
      Log.error('AppFlowy Cloud could not start the office editor: $error');
      if (mounted) {
        setState(() {
          _status = OfficeServerStatus.unreachable;
          _errorMessage = error is OfficeCloudException
              ? error.message
              : 'AppFlowy Cloud could not start the document editor. '
                  'Please try again.';
        });
      }
    }
  }

  Future<void> _saveLocalSettings(OfficeServerSettings settings) async {
    try {
      await widget.store.write(settings);
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = settings;
        _showInitialSetup = false;
      });
      await _connectLocal(settings);
    } catch (error) {
      Log.error('Unable to save the document server settings: $error');
      if (mounted) {
        setState(() {
          _status = OfficeServerStatus.unreachable;
          _errorMessage = 'AppFlowy could not save these server settings.';
        });
      }
    }
  }

  void _retry() {
    switch (_mode) {
      case _OfficeConnectionMode.cloud:
        final profile = _cloudProfile;
        if (profile != null) {
          unawaited(_connectManaged(profile));
        } else {
          unawaited(_load());
        }
        return;
      case _OfficeConnectionMode.local:
        unawaited(_connectLocal(_settings));
        return;
      case _OfficeConnectionMode.unknown:
        unawaited(_load());
        return;
    }
  }

  void _openDocumentSettings() {
    final userWorkspaceBloc = context.read<UserWorkspaceBloc>();
    sidebar_settings.showSettingsDialog(
      context,
      userWorkspaceBloc: userWorkspaceBloc,
      initPage: SettingsPage.documentEditing,
      onClosed: () {
        if (mounted) {
          unawaited(_load());
        }
      },
    );
  }

  /// ONLYOFFICE caches by key, so it has to change whenever the bytes do.
  String _buildDocumentKey(DateTime modified) {
    final raw = '${widget.file.path}_${modified.millisecondsSinceEpoch}';
    final encoded = base64Url
        .encode(utf8.encode(raw))
        .replaceAll(RegExp('[^A-Za-z0-9_-]'), '');
    return encoded.length <= 40
        ? encoded
        : encoded.substring(encoded.length - 40);
  }

  Future<void> _writeBack(List<int> bytes) async {
    try {
      await widget.file.writeAsBytes(bytes, flush: true);
      Log.info('Saved ${widget.name} from the document server.');
    } on FileSystemException catch (error) {
      Log.error('Unable to save ${widget.name}: $error');
    }
  }

  Color _currentEditorBackground() {
    final theme = AppFlowyTheme.of(context);
    return EditorSurfaceStyle.previewBackgroundFor(
      Theme.of(context).brightness,
      theme.surfaceColorScheme.primary,
      isPaper: PaperTheme.isEnabled(context),
    );
  }

  bool _currentIsDark() => Theme.of(context).brightness == Brightness.dark;

  bool _matchesCurrentAppearance(Color background, bool isDark) =>
      _currentEditorBackground() == background && _currentIsDark() == isDark;

  void _refreshAppearanceIfStale(Color background, bool isDark) {
    if (!_matchesCurrentAppearance(background, isDark)) {
      unawaited(_refreshEditorAppearance());
    }
  }

  String? _currentEditorHtml(
    Color background, {
    required bool isDark,
  }) {
    if (_mode == _OfficeConnectionMode.cloud) {
      final session = _managedSession;
      if (session == null) {
        return null;
      }
      return buildManagedOfficeEditorHtml(
        serverOrigin: session.documentServerUrl,
        editorConfig: session.editorConfig,
        background: background,
      );
    }

    final bridged = _bridged;
    final base = _settings.baseUri;
    if (bridged == null || base == null) {
      return null;
    }
    return buildOfficeEditorHtml(
      serverOrigin: base.toString(),
      document: bridged,
      fileName: widget.name,
      documentKey: _documentKey ?? '',
      editable: widget.editable,
      isDark: isDark,
      background: background,
      secret: _settings.jwtSecret.trim(),
    );
  }

  Future<void> _refreshEditorAppearance() async {
    if (_refreshingEditorPage || !mounted) {
      return;
    }
    final isDark = _currentIsDark();
    final background = _currentEditorBackground();
    final action = officeEditorRefreshAction(
      managed: _mode == _OfficeConnectionMode.cloud,
      editorIsDark: _editorIsDark,
      editorBackground: _editorBackground,
      isDark: isDark,
      background: background,
    );
    if (action == OfficeEditorRefreshAction.none) {
      return;
    }
    _refreshingEditorPage = true;
    HostedOfficeEditor? replacement;
    var retry = false;
    try {
      ManagedOfficeSession? replacementSession;
      late final String? html;
      switch (action) {
        case OfficeEditorRefreshAction.managedSession:
          final profile = _cloudProfile;
          final session = _managedSession;
          if (profile == null || session == null) {
            return;
          }
          replacementSession = await widget.cloudService.createSession(
            profile: profile,
            storageUrl: widget.source,
            fileName: widget.name,
            editable: widget.editable,
            isDark: isDark,
            sessionId: session.sessionId,
          );
          html = buildManagedOfficeEditorHtml(
            serverOrigin: replacementSession.documentServerUrl,
            editorConfig: replacementSession.editorConfig,
            background: background,
          );
          break;
        case OfficeEditorRefreshAction.editorPage:
          html = _currentEditorHtml(background, isDark: isDark);
          break;
        case OfficeEditorRefreshAction.none:
          return;
      }
      if (html == null) {
        return;
      }
      if (!_matchesCurrentAppearance(background, isDark)) {
        retry = true;
        return;
      }
      final newEditor =
          await OfficeDocumentBridge.instance.publishEditorPage(html);
      replacement = newEditor;
      if (!mounted || _status != OfficeServerStatus.connected) {
        OfficeDocumentBridge.instance.revoke(newEditor.token);
        replacement = null;
        return;
      }
      if (!_matchesCurrentAppearance(background, isDark)) {
        OfficeDocumentBridge.instance.revoke(newEditor.token);
        replacement = null;
        retry = true;
        return;
      }
      final previous = _hostedEditor?.token;
      setState(() {
        if (replacementSession != null) {
          _managedSession = replacementSession;
        }
        _hostedEditor = newEditor;
        _editorBackground = background;
        _editorIsDark = isDark;
      });
      if (previous != null) {
        OfficeDocumentBridge.instance.revoke(previous);
      }
    } catch (error) {
      final token = replacement?.token;
      if (token != null) {
        OfficeDocumentBridge.instance.revoke(token);
      }
      Log.error('Unable to refresh the office editor appearance: $error');
    } finally {
      _refreshingEditorPage = false;
      if (retry && mounted) {
        unawaited(_refreshEditorAppearance());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _currentIsDark();
    final background = _currentEditorBackground();
    if (_status == OfficeServerStatus.connected &&
        officeEditorRefreshAction(
              managed: _mode == _OfficeConnectionMode.cloud,
              editorIsDark: _editorIsDark,
              editorBackground: _editorBackground,
              isDark: isDark,
              background: background,
            ) !=
            OfficeEditorRefreshAction.none) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_refreshEditorAppearance());
        }
      });
    }

    if (_mode == _OfficeConnectionMode.local && _showInitialSetup) {
      if (widget.fallbackBuilder case final fallback?) {
        return fallback(context);
      }
      return _OfficeServerSettingsPanel(
        settings: _settings,
        status: _status,
        onSubmit: _saveLocalSettings,
      );
    }

    return switch (_status) {
      OfficeServerStatus.connecting => _OfficeLoading(
          managed: _mode == _OfficeConnectionMode.cloud,
        ),
      OfficeServerStatus.connected => _buildEditor(context),
      OfficeServerStatus.unconfigured ||
      OfficeServerStatus.unreachable =>
        widget.fallbackBuilder?.call(context) ??
            _OfficeUnavailable(
              name: widget.name,
              file: widget.file,
              serverUrl: _settings.serverUrl,
              managed: _mode != _OfficeConnectionMode.local,
              details: _errorMessage,
              onRetry: _retry,
              onConfigure: _mode == _OfficeConnectionMode.local
                  ? _openDocumentSettings
                  : null,
            ),
    };
  }

  Widget _buildEditor(BuildContext context) {
    final hostedEditor = _hostedEditor;
    if (hostedEditor == null) {
      return _OfficeLoading(
        managed: _mode == _OfficeConnectionMode.cloud,
      );
    }
    final background = _editorBackground ?? _currentEditorBackground();
    final documentServerUrl = _mode == _OfficeConnectionMode.cloud
        ? _managedSession!.documentServerUrl
        : _settings.baseUri!.toString();

    return PremiumScrollExclusion(
      key: kOfficeEditorScrollExclusionKey,
      child: ViewerCard(
        color: background,
        child: widget.editorBuilder?.call(context, hostedEditor) ??
            InAppWebView(
              key: ValueKey(hostedEditor.token),
              initialUrlRequest: URLRequest(
                url: WebUri(hostedEditor.url),
              ),
              initialUserScripts: UnmodifiableListView([
                buildOfficeThemeStorageUserScript(
                  documentServerUrl: documentServerUrl,
                  isDark: _editorIsDark ?? _currentIsDark(),
                ),
              ]),
              // The editor is a JavaScript application, so scripting stays on
              // (the default) unlike sandboxed markdown and HTML previews.
              initialSettings: InAppWebViewSettings(
                supportZoom: false,
                transparentBackground: true,
                mediaPlaybackRequiresUserGesture: false,
              ),
              onConsoleMessage: (_, message) {
                if (message.messageLevel == ConsoleMessageLevel.ERROR) {
                  Log.error('ONLYOFFICE: ${message.message}');
                }
              },
            ),
      ),
    );
  }
}

@visibleForTesting
String officeUiTheme(bool isDark) => isDark ? 'theme-night' : 'theme-white';

@visibleForTesting
UserScript buildOfficeThemeStorageUserScript({
  required String documentServerUrl,
  required bool isDark,
}) {
  final documentServerOrigin = Uri.parse(documentServerUrl).origin;
  final source = '''
(() => {
  if (window.location.origin === ${jsonEncode(documentServerOrigin)}) {
    window.localStorage.setItem(
      "ui-theme-id",
      ${jsonEncode(officeUiTheme(isDark))}
    );
    window.localStorage.setItem(
      "content-theme",
      ${jsonEncode(isDark ? 'dark' : 'light')}
    );
  }
})();
''';
  return UserScript(
    source: source,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
    allowedOriginRules: {documentServerOrigin},
  );
}

/// Builds the page that boots the ONLYOFFICE editor for [document].
@visibleForTesting
String buildOfficeEditorHtml({
  required String serverOrigin,
  required BridgedOfficeDocument document,
  required String fileName,
  required String documentKey,
  required bool editable,
  required bool isDark,
  required Color background,
  required String secret,
}) {
  final extension = p.extension(fileName).replaceFirst('.', '').toLowerCase();
  final documentType =
      officeDocumentTypeFor(fileName) ?? OfficeDocumentType.word;
  final config = <String, Object?>{
    'document': {
      'fileType': extension,
      'key': documentKey,
      'title': fileName,
      'url': document.downloadUrl,
      'permissions': {
        'edit': editable,
        'download': true,
        'print': true,
      },
    },
    'documentType': documentType.value,
    'type': 'desktop',
    'editorConfig': {
      'mode': editable ? 'edit' : 'view',
      'lang': 'en',
      if (editable) 'callbackUrl': document.callbackUrl,
      'user': {'id': 'appflowy', 'name': 'AppFlowy'},
      'customization': {
        'autosave': true,
        'forcesave': true,
        'compactHeader': true,
        'hideRightMenu': true,
        'uiTheme': officeUiTheme(isDark),
      },
    },
  };
  if (secret.isNotEmpty) {
    config['token'] = officeJwt(config, secret);
  }

  return _buildOfficeEditorPage(
    serverOrigin: serverOrigin,
    editorConfig: config,
    background: background,
  );
}

@visibleForTesting
String buildManagedOfficeEditorHtml({
  required String serverOrigin,
  required Map<String, dynamic> editorConfig,
  required Color background,
}) {
  return _buildOfficeEditorPage(
    serverOrigin: serverOrigin,
    editorConfig: editorConfig,
    background: background,
  );
}

String _buildOfficeEditorPage({
  required String serverOrigin,
  required Map<String, dynamic> editorConfig,
  required Color background,
}) {
  final css = '#${background.toHexString().substring(4)}';
  return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      html, body { margin: 0; padding: 0; height: 100%; width: 100%; overflow: hidden; background: $css; }
      #appflowy-office { height: 100%; width: 100%; }
      #appflowy-office-error { display: none; font: 13px/1.5 -apple-system, Segoe UI, sans-serif; padding: 24px; color: #8a8a8a; }
    </style>
    <script type="text/javascript" src="$serverOrigin/web-apps/apps/api/documents/api.js"></script>
  </head>
  <body>
    <div id="appflowy-office"></div>
    <div id="appflowy-office-error">The document server did not answer.</div>
    <script type="text/javascript">
      (function () {
        if (typeof DocsAPI === 'undefined') {
          document.getElementById('appflowy-office-error').style.display = 'block';
          return;
        }
        window.appflowyEditor = new DocsAPI.DocEditor('appflowy-office', ${jsonEncode(editorConfig)});
      })();
    </script>
  </body>
</html>
''';
}

class _OfficeServerSettingsPanel extends StatelessWidget {
  const _OfficeServerSettingsPanel({
    required this.settings,
    required this.status,
    required this.onSubmit,
  });

  final OfficeServerSettings settings;
  final OfficeServerStatus status;
  final Future<void> Function(OfficeServerSettings settings) onSubmit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _OfficePanelCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 28, 30, 24),
              child: OfficeServerSettingsForm(
                settings: settings,
                status: status,
                onSubmit: onSubmit,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfficeUnavailable extends StatelessWidget {
  const _OfficeUnavailable({
    required this.name,
    required this.file,
    required this.serverUrl,
    required this.managed,
    required this.details,
    required this.onRetry,
    required this.onConfigure,
  });

  final String name;
  final File file;
  final String serverUrl;
  final bool managed;
  final String? details;
  final VoidCallback onRetry;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _OfficePanelCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  managed ? Icons.cloud_off_outlined : Icons.dns_outlined,
                  size: 34,
                  color: theme.iconColorScheme.secondary,
                ),
                const SizedBox(height: 14),
                Text(
                  managed
                      ? 'Document editing is temporarily unavailable'
                      : 'Document server unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textColorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  details ??
                      (managed
                          ? 'AppFlowy Cloud could not start the document '
                              'editor. Your file is still safe in cloud storage.'
                          : serverUrl.isEmpty
                              ? 'Connect a document server to edit this file '
                                  'inside AppFlowy.'
                              : 'AppFlowy could not reach $serverUrl.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 18 / 13,
                    color: theme.textColorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Try again'),
                    ),
                    if (onConfigure != null)
                      OutlinedButton(
                        onPressed: onConfigure,
                        child: const Text('Open document settings'),
                      ),
                    TextButton(
                      onPressed: () => unawaited(
                        _openExternally(context, file),
                      ),
                      child: const Text('Open with system app'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openExternally(BuildContext context, File file) async {
    await afLaunchUrlString(file.uri.toString());
  }
}

class _OfficeLoading extends StatelessWidget {
  const _OfficeLoading({required this.managed});

  final bool managed;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(height: 12),
          Text(
            managed
                ? 'Preparing your cloud document editor...'
                : 'Connecting to the document server...',
            style: TextStyle(
              fontSize: 13,
              color: theme.textColorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficePanelCard extends StatelessWidget {
  const _OfficePanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: kOfficePanelSurfaceKey,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _officePanelColor(context),
        borderRadius: EditorSurfaceStyle.embedBorderRadius,
        border: Border.all(
          color: EditorSurfaceStyle.embedBorder(context),
        ),
      ),
      child: child,
    );
  }
}

Color _officePanelColor(BuildContext context) {
  final theme = AppFlowyTheme.of(context);
  return EditorSurfaceStyle.previewBackgroundFor(
    Theme.of(context).brightness,
    theme.fillColorScheme.content,
    isPaper: PaperTheme.isEnabled(context),
  );
}
