import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_linux_webview/appflowy_linux_webview.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'office_editor_chrome.dart';
import 'office_editor_scroll.dart';
import 'office_editor_skin.dart';
import 'office_embedded_host.dart';
import 'office_embedded_page.dart';
import 'office_panel.dart';

/// What the bundled editor runs in. Either way it sits inside the page.
enum EmbeddedOfficePresentation {
  /// A platform WebView (Windows and macOS).
  webView,

  /// A WebKitGTK view drawn into a Flutter texture (Linux, where Flutter has
  /// no platform views).
  texture,
}

Future<bool> _alwaysSupported() async => true;

/// The office editor bundled with this build, as the document view uses it.
class EmbeddedOfficeEditor {
  const EmbeddedOfficeEditor({
    required this.host,
    required this.presentation,
    this.webViewSupported = _alwaysSupported,
  });

  static final _webView = EmbeddedOfficeEditor(
    host: EmbeddedOfficeHost.instance,
    presentation: EmbeddedOfficePresentation.webView,
  );
  static final _texture = EmbeddedOfficeEditor(
    host: EmbeddedOfficeHost.instance,
    presentation: EmbeddedOfficePresentation.texture,
    webViewSupported: LinuxWebViewController.isSupported,
  );

  /// The editor for this platform; mobile keeps the server-based editors.
  static EmbeddedOfficeEditor? forCurrentPlatform() {
    if (kIsWeb) {
      return null;
    }
    if (Platform.isWindows || Platform.isMacOS) {
      return _webView;
    }
    if (Platform.isLinux) {
      return _texture;
    }
    return null;
  }

  final EmbeddedOfficeHost host;
  final EmbeddedOfficePresentation presentation;

  /// Whether the web engine the editor runs in is installed: WebKitGTK on
  /// Linux; Windows and macOS always have one.
  final Future<bool> Function() webViewSupported;

  /// Whether [name] can open here: the bundle ships with this build, reads
  /// the format, and on Linux WebKitGTK is installed.
  Future<bool> canOpen(String name) async {
    if (!canEmbedOfficeFile(name) || !await host.isAvailable) {
      return false;
    }
    return webViewSupported();
  }
}

/// A document the view asks the bundled editor to open.
@immutable
class EmbeddedOfficeRequest {
  const EmbeddedOfficeRequest({
    required this.file,
    required this.name,
    required this.editable,
    this.notice,
  });

  final File file;
  final String name;
  final bool editable;

  /// Why the document is open the way it is, shown above the editor.
  final String? notice;
}

class EmbeddedOfficeEditorView extends StatelessWidget {
  const EmbeddedOfficeEditorView({
    super.key,
    required this.editor,
    required this.request,
    this.fallbackBuilder,
  });

  final EmbeddedOfficeEditor editor;
  final EmbeddedOfficeRequest request;
  final WidgetBuilder? fallbackBuilder;

  @override
  Widget build(BuildContext context) {
    return _InlineOfficeEditor(
      editor: editor,
      request: request,
      fallbackBuilder: fallbackBuilder,
    );
  }
}

String _appFontFamily(BuildContext context) {
  try {
    return context.read<AppearanceSettingsCubit>().state.font;
  } on ProviderNotFoundException {
    return defaultFontFamily;
  }
}

OfficeEmbeddedTheme _themeOf(BuildContext context) =>
    OfficeEmbeddedTheme.fromSkin(OfficeEditorSkin.of(context));

class _InlineOfficeEditor extends StatefulWidget {
  const _InlineOfficeEditor({
    required this.editor,
    required this.request,
    this.fallbackBuilder,
  });

  final EmbeddedOfficeEditor editor;
  final EmbeddedOfficeRequest request;
  final WidgetBuilder? fallbackBuilder;

  @override
  State<_InlineOfficeEditor> createState() => _InlineOfficeEditorState();
}

class _InlineOfficeEditorState extends State<_InlineOfficeEditor> {
  final _scroll = OfficeEditorScrollController();
  EmbeddedOfficeSession? _session;

  /// Keeps the WebView running after this widget goes, until a save that is
  /// still in flight has reached the file.
  InAppWebViewKeepAlive? _keepAlive;
  InAppWebViewController? _controller;

  /// The Linux view, which likewise outlives this widget until the last save.
  LinuxWebViewController? _textureView;
  OfficeEditorTypography? _typography;
  Object? _openError;
  bool _started = false;

  bool get _usesTexture =>
      widget.editor.presentation == EmbeddedOfficePresentation.texture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = _themeOf(context);
    if (!_started) {
      _started = true;
      unawaited(_open(theme));
      return;
    }
    final session = _session;
    if (session != null && session.theme != theme) {
      unawaited(session.updateTheme(theme));
    }
    unawaited(_syncTypography());
  }

  @override
  void dispose() {
    _scroll.detach();
    final session = _session;
    if (session != null) {
      unawaited(
        _release(session, keepAlive: _keepAlive, textureView: _textureView),
      );
    }
    super.dispose();
  }

  static Future<void> _release(
    EmbeddedOfficeSession session, {
    InAppWebViewKeepAlive? keepAlive,
    LinuxWebViewController? textureView,
  }) async {
    try {
      if (!await session.flush()) {
        Log.error('The last edits to ${session.fileName} may not be saved.');
      }
    } finally {
      session.close();
      if (keepAlive != null) {
        try {
          await InAppWebViewController.disposeKeepAlive(keepAlive);
        } catch (error) {
          Log.warn('Unable to release the office editor WebView: $error');
        }
      }
      await textureView?.dispose();
    }
  }

  Future<void> _open(OfficeEmbeddedTheme theme) async {
    setState(() => _openError = null);
    try {
      _typography = await loadOfficeEditorTypography(_appFontFamily(context));
      final session = await widget.editor.host.open(
        file: widget.request.file,
        fileName: widget.request.name,
        editable: widget.request.editable,
        theme: theme,
        relayScroll: _usesTexture || officeEditorScrollSupported,
      );
      LinuxWebViewController? textureView;
      if (mounted && _usesTexture) {
        try {
          textureView = await LinuxWebViewController.create(
            url: session.pageUrl,
            userScripts: _scriptSources(session),
          );
        } catch (_) {
          session.close();
          rethrow;
        }
      }
      if (!mounted) {
        session.close();
        await textureView?.dispose();
        return;
      }
      setState(() {
        _session = session;
        if (textureView != null) {
          _textureView = textureView;
        } else {
          _keepAlive = InAppWebViewKeepAlive();
        }
      });
      if (textureView != null) {
        _scroll.attachTexture(textureView);
      }
    } catch (error) {
      Log.error('Unable to open ${widget.request.name} in the office editor: '
          '$error');
      if (mounted) {
        setState(() => _openError = error);
      }
    }
  }

  Future<void> _reopen() async {
    final session = _session;
    final keepAlive = _keepAlive;
    final textureView = _textureView;
    _scroll.detach();
    setState(() {
      _session = null;
      _keepAlive = null;
      _controller = null;
      _textureView = null;
    });
    if (session != null) {
      await _release(session, keepAlive: keepAlive, textureView: textureView);
    }
    if (mounted) {
      await _open(_themeOf(context));
    }
  }

  /// A new interface font reaches the editor through fresh user scripts,
  /// which only a reloaded page runs.
  Future<void> _syncTypography() async {
    final typography =
        await loadOfficeEditorTypography(_appFontFamily(context));
    final controller = _controller;
    final textureView = _textureView;
    final session = _session;
    if (!mounted || typography == _typography) {
      return;
    }
    _typography = typography;
    if (session == null || (controller == null && textureView == null)) {
      return;
    }
    try {
      if (textureView != null) {
        await textureView.setUserScripts(_scriptSources(session));
      } else if (controller != null) {
        await controller.removeAllUserScripts();
        await controller.addUserScripts(userScripts: _userScripts(session));
      }
      await session.updateTheme(session.theme, force: true);
    } catch (error) {
      Log.warn('Unable to update the office editor typography: $error');
    }
  }

  OfficeEditorTypography get _currentTypography =>
      _typography ??
      OfficeEditorTypography(family: resolveFontFamily(defaultFontFamily));

  List<UserScript> _userScripts(EmbeddedOfficeSession session) {
    final origin = session.host.origin.toString();
    final physics = officeScrollPhysics(context);
    return [
      buildOfficeEditorChromeUserScript(
        documentServerUrl: origin,
        typography: _currentTypography,
      ),
      if (officeEditorScrollSupported)
        buildOfficeScrollUserScript(
          documentServerUrl: origin,
          hostUrl: session.pageUrl.toString(),
          config: physics.config,
          smooth: physics.smooth,
        ),
    ];
  }

  /// The Linux view's scripts, which run in every frame.
  List<String> _scriptSources(EmbeddedOfficeSession session) {
    final physics = officeScrollPhysics(context);
    return [
      buildOfficeEditorChromeScript(
        documentServerOrigin: session.host.origin.toString(),
        typography: _currentTypography,
      ),
      buildOfficeScrollRuntimeScript(
        documentServerOrigin: session.host.origin.toString(),
        hostOrigin: session.pageUrl.toString(),
        config: physics.config,
        smooth: physics.smooth,
        pixelDeltas: true,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final error = _openError;
    if (error != null) {
      return _EmbeddedOfficeFailure(
        file: widget.request.file,
        message: 'AppFlowy could not start its document editor.',
        onRetry: () => unawaited(_open(_themeOf(context))),
      );
    }
    final session = _session;
    final keepAlive = _keepAlive;
    final textureView = _textureView;
    if (session == null || (keepAlive == null && textureView == null)) {
      return const _EmbeddedOfficeLoading();
    }
    return ValueListenableBuilder<EmbeddedOfficeStatus>(
      valueListenable: session.status,
      builder: (context, status, editor) {
        if (status.phase == EmbeddedOfficePhase.failed) {
          return widget.fallbackBuilder?.call(context) ??
              _EmbeddedOfficeFailure(
                file: widget.request.file,
                message: status.error,
                onRetry: () => unawaited(_reopen()),
              );
        }
        final notice = widget.request.notice;
        final saveError = status.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notice != null) _OfficeNotice(text: notice),
            if (saveError != null)
              _OfficeNotice(
                text: saveError,
                warning: true,
                actionLabel: 'Try again',
                onAction: () => unawaited(session.flush()),
              ),
            Expanded(child: editor!),
          ],
        );
      },
      child: textureView != null
          ? _buildTextureView(textureView)
          : _buildWebView(session, keepAlive!),
    );
  }

  Widget _buildTextureView(LinuxWebViewController view) {
    return PremiumScrollExclusion(
      child: ViewerCard(
        color: OfficeEditorSkin.of(context).desk,
        child: OfficeEditorScroll(
          controller: _scroll,
          child: LinuxWebView(controller: view),
        ),
      ),
    );
  }

  Widget _buildWebView(
    EmbeddedOfficeSession session,
    InAppWebViewKeepAlive keepAlive,
  ) {
    final skin = OfficeEditorSkin.of(context);
    return PremiumScrollExclusion(
      child: ViewerCard(
        color: skin.desk,
        child: OfficeEditorScroll(
          controller: _scroll,
          child: InAppWebView(
            keepAlive: keepAlive,
            initialUrlRequest: URLRequest(
              url: WebUri(session.pageUrl.toString()),
            ),
            initialUserScripts: UnmodifiableListView(_userScripts(session)),
            // The editor is a JavaScript application, so scripting stays on
            // (the default) unlike sandboxed markdown and HTML previews.
            initialSettings: InAppWebViewSettings(
              supportZoom: false,
              transparentBackground: true,
              mediaPlaybackRequiresUserGesture: false,
              supportMultipleWindows: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              _scroll.attach(controller);
            },
            // Links in a document open in the browser.
            onCreateWindow: (_, action) async {
              final uri = action.request.url;
              if (uri != null &&
                  const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
                await afLaunchUri(uri);
              }
              return false;
            },
            onConsoleMessage: (_, message) {
              if (message.messageLevel == ConsoleMessageLevel.ERROR) {
                Log.error('Office editor: ${message.message}');
              }
            },
          ),
        ),
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        height: 18 / 13,
        color: theme.textColorScheme.secondary,
      ),
    );
  }
}

/// A one-line message above the inline editor.
class _OfficeNotice extends StatelessWidget {
  const _OfficeNotice({
    required this.text,
    this.warning = false,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final bool warning;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final color =
        warning ? theme.textColorScheme.error : theme.textColorScheme.secondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: officePanelColor(context),
        borderRadius: EditorSurfaceStyle.embedBorderRadius,
        border: Border.all(color: EditorSurfaceStyle.embedBorder(context)),
      ),
      child: Row(
        children: [
          Icon(
            warning ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 16 / 12, color: color),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class _EmbeddedOfficeLoading extends StatelessWidget {
  const _EmbeddedOfficeLoading();

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
            'Opening the document...',
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

class _EmbeddedOfficeFailure extends StatelessWidget {
  const _EmbeddedOfficeFailure({
    required this.file,
    required this.message,
    required this.onRetry,
  });

  final File file;
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: OfficePanelCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 34,
                  color: theme.iconColorScheme.secondary,
                ),
                const SizedBox(height: 14),
                Text(
                  'This document could not be opened',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.textColorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                _PanelMessage(
                  message ??
                      'The file may be damaged or in a format the built-in '
                          'editor cannot read.',
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
                    TextButton(
                      onPressed: () => unawaited(afLaunchUri(file.uri)),
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
}
