import 'dart:async';
import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:universal_platform/universal_platform.dart';

import 'excalidraw_host.dart';

/// Whether the real Excalidraw editor can be opened on this platform.
///
/// It runs in a web view, which the desktop builds carry; on mobile the block
/// still shows its drawing and its data, it simply cannot be edited yet.
bool get canRunExcalidrawEditor => UniversalPlatform.isDesktop;

/// Hosts the bundled Excalidraw editor and speaks to it.
///
/// The editor is the unmodified open-source component; everything AppFlowy
/// needs from it — the scene as it changes, an exported picture — travels over
/// one message channel, so nothing about the drawing is inferred from the DOM.
class ExcalidrawEditorView extends StatefulWidget {
  const ExcalidrawEditorView({
    super.key,
    required this.scene,
    required this.onSceneChanged,
    this.editable = true,
    this.onReady,
    this.controller,
  });

  /// The `.excalidraw` document to open.
  final String scene;

  /// Called with the whole scene each time the drawing settles.
  final ValueChanged<String> onSceneChanged;

  final bool editable;
  final VoidCallback? onReady;
  final ExcalidrawEditorController? controller;

  @override
  State<ExcalidrawEditorView> createState() => _ExcalidrawEditorViewState();
}

/// Lets a host ask the editor for things it can only answer itself.
class ExcalidrawEditorController {
  _ExcalidrawEditorViewState? _state;

  bool get isAttached => _state != null;

  /// The scene exactly as the editor holds it now.
  Future<String?> requestScene() async => _state?._requestScene();

  /// Writes whatever the editor is holding, without waiting for the pause.
  Future<void> flush() async => _state?._flush();

  /// A picture rendered by Excalidraw itself, so an export is what the editor
  /// draws rather than a second interpretation of it.
  Future<String?> exportImage(String format) async =>
      _state?._exportImage(format);
}

class _ExcalidrawEditorViewState extends State<ExcalidrawEditorView> {
  static const String _handler = 'appflowyExcalidraw';

  InAppWebViewController? _webView;
  Uri? _url;
  Object? _failure;
  bool _ready = false;
  bool _loaded = false;
  bool _booting = false;
  Brightness? _appliedBrightness;

  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  int _requestCounter = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    unawaited(_resolveUrl());
  }

  @override
  void didUpdateWidget(covariant ExcalidrawEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._state = null;
      widget.controller?._state = this;
    }
    if (_ready && oldWidget.editable != widget.editable) {
      unawaited(_call('setViewMode(${!widget.editable})'));
    }
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('The editor was closed.'));
      }
    }
    _webView = null;
    super.dispose();
  }

  Future<void> _resolveUrl() async {
    try {
      final url = await ExcalidrawHost.instance.editorUrl();
      if (mounted) {
        setState(() => _url = url);
      }
    } catch (error) {
      Log.error('The Excalidraw editor could not be started: $error');
      if (mounted) {
        setState(() => _failure = error);
      }
    }
  }

  Future<void> _call(String expression) async {
    final webView = _webView;
    if (webView == null) {
      return;
    }
    // The bridge is installed by the page, so a call that arrives before it is
    // ready must not throw — it is retried when `ready` comes back.
    await webView.evaluateJavascript(
      source: 'window.appflowyExcalidraw && '
          'window.appflowyExcalidraw.$expression;',
    );
  }

  Future<Map<String, dynamic>?> _ask(String method, String format) async {
    if (_webView == null || !_ready) {
      return null;
    }
    final id = 'r${_requestCounter++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    await _call("$method(${jsonEncode(format)}, ${jsonEncode(id)})");
    try {
      return await completer.future.timeout(const Duration(seconds: 20));
    } catch (error) {
      Log.warn('The Excalidraw editor did not answer $method: $error');
      return null;
    } finally {
      _pending.remove(id);
    }
  }

  Future<String?> _requestScene() async {
    final webView = _webView;
    if (webView == null || !_ready) {
      return null;
    }
    // Reading the value straight out of the page does not depend on the
    // page being able to call back, so it is tried first.
    try {
      final direct = await webView.evaluateJavascript(
        source: 'window.appflowyExcalidraw ? '
            'window.appflowyExcalidraw.sceneNow() : null;',
      );
      if (direct is String && direct.isNotEmpty) {
        return direct;
      }
    } catch (error) {
      Log.warn('The Excalidraw scene could not be read directly: $error');
    }

    final id = 'r${_requestCounter++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    await _call('requestScene(${jsonEncode(id)})');
    try {
      final answer =
          await completer.future.timeout(const Duration(seconds: 20));
      return answer['scene'] as String?;
    } catch (error) {
      Log.warn('The Excalidraw editor did not return its scene: $error');
      return null;
    } finally {
      _pending.remove(id);
    }
  }

  Future<String?> _exportImage(String format) async {
    final answer = await _ask('exportImage', format);
    return answer?['data'] as String?;
  }

  void _onMessage(dynamic raw) {
    // Depending on the platform's bridge the payload arrives either as a map
    // or as the JSON text of one; a message dropped here is a lost drawing.
    var value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return;
      }
    }
    final message = value is Map ? Map<String, dynamic>.from(value) : null;
    if (message == null) {
      return;
    }
    final type = message['type'] as String?;
    final requestId = message['requestId'] as String?;
    if (requestId != null) {
      _pending.remove(requestId)?.complete(message);
      if (type != 'change') {
        return;
      }
    }

    switch (type) {
      case 'ready':
        // The page announces itself until it is answered, so this arrives
        // more than once; loading it twice would throw away the drawing.
        if (!_loaded) {
          _ready = true;
          unawaited(_bootstrap());
          widget.onReady?.call();
        }
      case 'change':
        final scene = message['scene'] as String?;
        if (scene != null && scene.isNotEmpty) {
          widget.onSceneChanged(scene);
        }
      case 'error':
        Log.warn('Excalidraw reported: ${message['message']}');
    }
  }

  Future<void> _bootstrap() async {
    final webView = _webView;
    if (_loaded || _booting || webView == null) {
      return;
    }
    _booting = true;
    try {
      // The page installs its bridge when the editor commits, which can be
      // after the load event, so it is waited for rather than assumed.
      for (var attempt = 0; attempt < 60; attempt++) {
        if (!mounted) {
          return;
        }
        final present = await webView.evaluateJavascript(
          source: 'window.appflowyExcalidraw != null;',
        );
        if (present == true || present == 1 || present == 'true') {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      if (!mounted || _loaded) {
        return;
      }
      _loaded = true;
      await _call('load(${jsonEncode(widget.scene)})');
      await _applyTheme(force: true);
      if (!widget.editable) {
        await _call('setViewMode(true)');
      }
    } finally {
      _booting = false;
    }
  }

  Future<void> _flush() async {
    if (!_ready) {
      return;
    }
    final scene = await _requestScene();
    if (scene != null && scene.isNotEmpty) {
      widget.onSceneChanged(scene);
    }
  }

  Future<void> _applyTheme({bool force = false}) async {
    if (!mounted) {
      return;
    }
    final brightness = Theme.of(context).brightness;
    if (!force && brightness == _appliedBrightness) {
      return;
    }
    _appliedBrightness = brightness;
    await _call(
      "setTheme('${brightness == Brightness.dark ? 'dark' : 'light'}')",
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    if (_ready) {
      // A theme change while the editor is open reaches it too.
      unawaited(_applyTheme());
    }

    if (_failure != null) {
      return _Notice(
        palette: palette,
        icon: Icons.brush_outlined,
        message: LocaleKeys.diagrams_drawing_editorUnavailable.tr(),
      );
    }
    final url = _url;
    if (url == null) {
      return ColoredBox(
        color: palette.canvas,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.accent,
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: palette.canvas,
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri.uri(url)),
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          supportZoom: false,
          // The page is our own bundle served from loopback; it needs no
          // access to files, no popups and no third-party navigation.
          useShouldOverrideUrlLoading: true,
        ),
        onWebViewCreated: (controller) {
          _webView = controller;
          controller.addJavaScriptHandler(
            handlerName: _handler,
            callback: (arguments) {
              if (arguments.isNotEmpty) {
                _onMessage(arguments.first);
              }
              return null;
            },
          );
        },
        shouldOverrideUrlLoading: (controller, action) async {
          final target = action.request.url;
          if (target == null || target.host == '127.0.0.1') {
            return NavigationActionPolicy.ALLOW;
          }
          // A link inside a drawing belongs in the system browser, never in
          // the editor's own frame.
          return NavigationActionPolicy.CANCEL;
        },
        onLoadStop: (controller, url) {
          // Belt and braces: the page also announces itself, but a lost
          // `ready` must not leave the editor showing an empty canvas.
          _ready = true;
          unawaited(_bootstrap());
        },
        onConsoleMessage: (controller, message) {
          if (message.messageLevel == ConsoleMessageLevel.ERROR) {
            Log.warn('Excalidraw: ${message.message}');
          }
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.palette,
    required this.icon,
    required this.message,
  });

  final VisualBlockPalette palette;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: palette.canvas,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: palette.textMuted),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
