import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/util/color_to_hex_string.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import 'office_document_bridge.dart';
import 'office_server_settings.dart';

/// Opens a Word, Excel or PowerPoint document.
///
/// Editing runs in a self hosted ONLYOFFICE Docs (DocumentServer) instance;
/// AppFlowy hands it the file through a short lived local bridge and writes the
/// saved copy back into workspace storage. Without a reachable server the file
/// stays read only.
class OfficeDocumentView extends StatefulWidget {
  const OfficeDocumentView({
    super.key,
    required this.file,
    required this.name,
    required this.editable,
    this.store = const OfficeServerStore(),
  });

  final File file;
  final String name;
  final bool editable;
  final OfficeServerStore store;

  @override
  State<OfficeDocumentView> createState() => _OfficeDocumentViewState();
}

class _OfficeDocumentViewState extends State<OfficeDocumentView> {
  OfficeServerSettings _settings = const OfficeServerSettings();
  OfficeServerStatus _status = OfficeServerStatus.connecting;
  BridgedOfficeDocument? _bridged;
  String? _documentKey;
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    final token = _bridged?.token;
    if (token != null) {
      OfficeDocumentBridge.instance.revoke(token);
    }
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await widget.store.read();
    if (!mounted) {
      return;
    }
    setState(() => _settings = settings);
    if (!settings.isConfigured) {
      setState(() {
        _status = OfficeServerStatus.unconfigured;
        _showSettings = true;
      });
      return;
    }
    await _connect(settings);
  }

  Future<void> _connect(OfficeServerSettings settings) async {
    setState(() => _status = OfficeServerStatus.connecting);
    final reachable = await probeOfficeServer(settings);
    if (!mounted) {
      return;
    }
    if (!reachable) {
      setState(() => _status = OfficeServerStatus.unreachable);
      return;
    }

    try {
      final stat = await widget.file.stat();
      final previous = _bridged?.token;
      if (previous != null) {
        OfficeDocumentBridge.instance.revoke(previous);
      }
      final bridged = await OfficeDocumentBridge.instance.publish(
        file: widget.file,
        host: settings.resolveBridgeHost(),
        secret: settings.jwtSecret.trim(),
        onSaved: _writeBack,
      );
      if (!mounted) {
        OfficeDocumentBridge.instance.revoke(bridged.token);
        return;
      }
      setState(() {
        _bridged = bridged;
        _documentKey = _buildDocumentKey(stat.modified);
        _status = OfficeServerStatus.connected;
        _showSettings = false;
      });
    } catch (error) {
      Log.error('Unable to publish the office document: $error');
      if (mounted) {
        setState(() => _status = OfficeServerStatus.unreachable);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    if (_showSettings) {
      return _OfficeServerSettingsPanel(
        settings: _settings,
        status: _status,
        onSubmit: (settings) async {
          await widget.store.write(settings);
          if (!mounted) {
            return;
          }
          setState(() => _settings = settings);
          await _connect(settings);
        },
        onDismiss: _status == OfficeServerStatus.unconfigured
            ? null
            : () => setState(() => _showSettings = false),
      );
    }

    return switch (_status) {
      OfficeServerStatus.connecting => const Center(
          child: CircularProgressIndicator(),
        ),
      OfficeServerStatus.connected => _buildEditor(context),
      OfficeServerStatus.unconfigured ||
      OfficeServerStatus.unreachable =>
        _OfficeUnavailable(
          name: widget.name,
          file: widget.file,
          serverUrl: _settings.serverUrl,
          onRetry: () => unawaited(_connect(_settings)),
          onConfigure: () => setState(() => _showSettings = true),
        ),
    };
  }

  Widget _buildEditor(BuildContext context) {
    final bridged = _bridged;
    final base = _settings.baseUri;
    if (bridged == null || base == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = AppFlowyTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final html = buildOfficeEditorHtml(
      serverOrigin: base.toString(),
      document: bridged,
      fileName: widget.name,
      documentKey: _documentKey ?? '',
      editable: widget.editable,
      isDark: isDark,
      background: theme.surfaceColorScheme.primary,
      secret: _settings.jwtSecret.trim(),
    );

    return ViewerCard(
      color: theme.surfaceColorScheme.primary,
      child: InAppWebView(
        key: ValueKey('${bridged.token}_$isDark'),
        initialData: InAppWebViewInitialData(
          data: html,
          baseUrl: WebUri(base.toString()),
        ),
        // The editor is a JavaScript application, so scripting stays on (the
        // default) unlike the sandboxed markdown and HTML previews.
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
    );
  }
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
  final documentType = officeDocumentTypeFor(fileName) ?? OfficeDocumentType.word;
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
        'uiTheme': isDark ? 'theme-dark' : 'theme-classic-light',
      },
    },
  };
  if (secret.isNotEmpty) {
    config['token'] = officeJwt(config, secret);
  }

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
        window.appflowyEditor = new DocsAPI.DocEditor('appflowy-office', ${jsonEncode(config)});
      })();
    </script>
  </body>
</html>
''';
}

class _OfficeServerSettingsPanel extends StatefulWidget {
  const _OfficeServerSettingsPanel({
    required this.settings,
    required this.status,
    required this.onSubmit,
    required this.onDismiss,
  });

  final OfficeServerSettings settings;
  final OfficeServerStatus status;
  final Future<void> Function(OfficeServerSettings settings) onSubmit;
  final VoidCallback? onDismiss;

  @override
  State<_OfficeServerSettingsPanel> createState() =>
      _OfficeServerSettingsPanelState();
}

class _OfficeServerSettingsPanelState
    extends State<_OfficeServerSettingsPanel> {
  late final TextEditingController _url =
      TextEditingController(text: widget.settings.serverUrl);
  late final TextEditingController _secret =
      TextEditingController(text: widget.settings.jwtSecret);
  late final TextEditingController _bridge =
      TextEditingController(text: widget.settings.bridgeHost);

  @override
  void dispose() {
    _url.dispose();
    _secret.dispose();
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ViewerCard(
          color: theme.fillColorScheme.content,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connect a document server',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Word, Excel and PowerPoint files are edited by a self '
                  'hosted ONLYOFFICE Docs instance. Point AppFlowy at yours to '
                  'edit them; without it they stay read only.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 19 / 13,
                    color: theme.textColorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 18),
                _Field(
                  controller: _url,
                  label: 'Server address',
                  hint: 'http://localhost:8080',
                ),
                const SizedBox(height: 12),
                _Field(
                  controller: _secret,
                  label: 'JWT secret (optional)',
                  hint: 'Matches the server JWT_SECRET',
                  obscure: true,
                ),
                const SizedBox(height: 12),
                _Field(
                  controller: _bridge,
                  label: 'Callback host (optional)',
                  hint: 'How the server reaches this computer',
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.onDismiss != null)
                      TextButton(
                        onPressed: widget.onDismiss,
                        child: const Text('Cancel'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => unawaited(
                        widget.onSubmit(
                          OfficeServerSettings(
                            serverUrl: _url.text.trim(),
                            jwtSecret: _secret.text.trim(),
                            bridgeHost: _bridge.text.trim(),
                          ),
                        ),
                      ),
                      child: const Text('Connect'),
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
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.textColorScheme.secondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: TextStyle(fontSize: 13, color: theme.textColorScheme.primary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
        ),
      ],
    );
  }
}

class _OfficeUnavailable extends StatelessWidget {
  const _OfficeUnavailable({
    required this.name,
    required this.file,
    required this.serverUrl,
    required this.onRetry,
    required this.onConfigure,
  });

  final String name;
  final File file;
  final String serverUrl;
  final VoidCallback onRetry;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: ViewerCard(
          color: theme.fillColorScheme.content,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 34,
                  color: theme.iconColorScheme.secondary,
                ),
                const SizedBox(height: 14),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  serverUrl.isEmpty
                      ? 'No document server is configured, so this file cannot '
                          'be rendered here yet.'
                      : 'AppFlowy could not reach $serverUrl, so this file is '
                          'read only right now.',
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
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                    TextButton(
                      onPressed: onConfigure,
                      child: const Text('Server settings'),
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
