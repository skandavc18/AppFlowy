import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_web_environment.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// How long the page waits for a route transition before drawing anyway.
const _readyBackstop = Duration(milliseconds: 320);

/// The smallest box a composition surface is created for.
const _minimumSurface = 64.0;

/// The live page, rendered in place.
///
/// This is a reading surface for a page someone chose to save, not a browser:
/// it follows links within the page but hands anything else — a mail client,
/// an app scheme, a download — back to the system browser. Popups, local file
/// access and autoplay stay at the plugin's own defaults, which are off.
///
/// **The renderer scrolls itself.** Feeding a page from Dart costs a platform
/// round trip per gesture step, and the jitter in those round trips is visible
/// as a stutter no amount of smoothing hides. Chromium animates the wheel and
/// flings a two-finger pan on its own compositor thread, which is the only way
/// this is ever frame-perfect.
class BookmarkWebPage extends StatefulWidget {
  const BookmarkWebPage({
    super.key,
    required this.url,
    required this.theme,
    this.onOpenExternally,
  });

  final String url;
  final BookmarkTheme theme;
  final ValueChanged<Uri>? onOpenExternally;

  @override
  State<BookmarkWebPage> createState() => _BookmarkWebPageState();
}

class _BookmarkWebPageState extends State<BookmarkWebPage> {
  InAppWebViewController? _controller;
  Animation<double>? _routeAnimation;
  Brightness? _appliedBrightness;
  double _progress = 0;
  bool _failed = false;
  bool _ready = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareEnvironment());
  }

  Future<void> _prepareEnvironment() async {
    await BookmarkWebEnvironment.ensure();
    if (_alive) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchRouteAnimation();
    unawaited(_applyColorScheme());
  }

  @override
  void dispose() {
    // Every callback checks this: a platform call that lands after the native
    // view is gone is what takes the renderer down.
    _closing = true;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _controller = null;
    super.dispose();
  }

  bool get _alive => mounted && !_closing;

  /// A platform view created while the route is still animating can take the
  /// renderer down with it, so the page waits for the transition to settle.
  void _watchRouteAnimation() {
    if (_ready) {
      return;
    }
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _ready = true;
      return;
    }
    if (identical(animation, _routeAnimation)) {
      return;
    }
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation..addStatusListener(_onRouteStatus);
    // A status listener attached while the route is already settling never
    // fires, so the page is never left waiting on it alone.
    Future<void>.delayed(_readyBackstop, _markReady);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _markReady();
      return;
    }
    // Tear the renderer down before the closing fade rather than during it:
    // a texture that disappears mid-animation is still referenced by the
    // compositor.
    if (status == AnimationStatus.reverse && _alive && _ready) {
      _controller = null;
      setState(() => _ready = false);
    }
  }

  void _markReady() {
    if (_alive && !_ready) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    if (_failed) {
      return BookmarkEmptyState(
        theme: theme,
        icon: Icons.cloud_off_rounded,
        title: LocaleKeys.collections_bookmark_pageUnavailable.tr(),
        message:
            LocaleKeys.collections_bookmark_pageUnavailableDescription.tr(),
        action: BookmarkAction(
          icon: Icons.refresh_rounded,
          tooltip: LocaleKeys.collections_bookmark_reload.tr(),
          theme: theme,
          label: LocaleKeys.collections_bookmark_reload.tr(),
          active: true,
          onPressed: reload,
        ),
      );
    }

    if (!_ready) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: theme.accent),
        ),
      );
    }

    return Stack(
      children: [
        // The renderer owns its scrolling, so the application's own dispatcher
        // stays out of the way rather than fighting it.
        Positioned.fill(
          child: PremiumScrollExclusion(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // A composition surface sized from a degenerate box faults in
                // DirectComposition, so the renderer waits for a real one.
                if (constraints.maxWidth < _minimumSurface ||
                    constraints.maxHeight < _minimumSurface) {
                  return const SizedBox.shrink();
                }
                return _webView();
              },
            ),
          ),
        ),
        if (_progress > 0 && _progress < 1)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: theme.accent,
            ),
          ),
      ],
    );
  }

  Widget _webView() => InAppWebView(
        webViewEnvironment: BookmarkWebEnvironment.instance,
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          useShouldOverrideUrlLoading: true,
          // The Windows renderer emulates a trackpad pan as a dragged touch
          // pointer. Zeroing the horizontal axis keeps that pointer from
          // wandering sideways across the page as you scroll.
          disableHorizontalScroll: Platform.isWindows,
        ),
        onWebViewCreated: (controller) {
          if (!_alive) {
            return;
          }
          _controller = controller;
          _appliedBrightness = null;
          unawaited(_applyColorScheme());
        },
        onLoadStop: (controller, _) => unawaited(_dress(controller)),
        onProgressChanged: (_, progress) {
          if (_alive) {
            setState(() => _progress = progress / 100);
          }
        },
        onReceivedError: (_, request, __) {
          if (_alive && request.isForMainFrame == true) {
            setState(() => _failed = true);
          }
        },
        // A saved article may ask for the camera, the microphone or a device
        // identifier. None of that belongs in a reading surface, and leaving
        // the request unanswered is what crashed the renderer on pages with an
        // embedded video.
        onPermissionRequest: (_, request) async =>
            PermissionResponse(resources: request.resources),
        // A link that asks for a new tab has nowhere to go here, so it opens
        // in this view instead of silently doing nothing.
        onCreateWindow: (controller, action) async {
          final uri = action.request.url;
          if (uri == null) {
            return false;
          }
          if (uri.scheme == 'http' || uri.scheme == 'https') {
            await controller.loadUrl(urlRequest: URLRequest(url: uri));
          } else {
            widget.onOpenExternally?.call(uri);
          }
          return true;
        },
        shouldOverrideUrlLoading: (controller, action) async {
          final uri = action.request.url;
          // Nothing to judge without a scheme; the renderer is sandboxed.
          if (uri == null ||
              uri.scheme == 'http' ||
              uri.scheme == 'https' ||
              uri.scheme == 'about') {
            return NavigationActionPolicy.ALLOW;
          }
          widget.onOpenExternally?.call(uri);
          return NavigationActionPolicy.CANCEL;
        },
      );

  /// Makes the page answer `prefers-color-scheme` with AppFlowy's own
  /// appearance, so a site that follows the system does not open dark inside a
  /// light workspace.
  Future<void> _applyColorScheme() async {
    final controller = _controller;
    final brightness = widget.theme.brightness;
    if (!_alive || controller == null || brightness == _appliedBrightness) {
      return;
    }
    _appliedBrightness = brightness;
    final scheme = brightness == Brightness.dark ? 'dark' : 'light';
    try {
      await controller.callDevToolsProtocolMethod(
        methodName: 'Emulation.setEmulatedMedia',
        parameters: {
          'features': [
            {'name': 'prefers-color-scheme', 'value': scheme},
          ],
        },
      );
    } on PlatformException catch (error) {
      // Only a Chromium-backed renderer emulates media; the injected
      // `color-scheme` still does what it can elsewhere.
      Log.warn('Could not set the bookmark page colour scheme: $error');
    }
    await _run(controller, _colorSchemeScript(scheme));
  }

  /// Dresses the page in the application's scrollbars once it has loaded.
  Future<void> _dress(InAppWebViewController controller) async {
    if (!_alive || controller != _controller) {
      return;
    }
    await _run(
      controller,
      '''
${_colorSchemeScript(widget.theme.isDark ? 'dark' : 'light')}
${_scrollbarStyleScript(widget.theme)}
${buildHtmlPreviewScrollbarAutoHideScript()}
''',
    );
  }

  Future<void> _run(InAppWebViewController controller, String source) async {
    if (!_alive || controller != _controller) {
      return;
    }
    try {
      await controller.evaluateJavascript(source: source);
    } on PlatformException catch (error) {
      Log.warn('Bookmark page script failed: $error');
    }
  }

  void reload() {
    if (!_alive) {
      return;
    }
    setState(() {
      _failed = false;
      _progress = 0;
    });
    unawaited(_controller?.reload());
  }
}

String _colorSchemeScript(String scheme) => '''
(function () {
  const root = document.documentElement;
  if (root) {
    root.style.colorScheme = '$scheme';
  }
})();
''';

/// Overlay scrollbars in the application's own ink, transparent until the page
/// moves — a remote page otherwise brings whatever the site chose, which on
/// Windows is a solid black bar.
String _scrollbarStyleScript(BookmarkTheme theme) {
  final thumb = theme.textFaint.withValues(alpha: theme.isDark ? 0.5 : 0.42);
  final rgba = 'rgba(${(thumb.r * 255).round()}, ${(thumb.g * 255).round()}, '
      '${(thumb.b * 255).round()}, ${thumb.a})';
  final css = '''
::-webkit-scrollbar { width: 12px; height: 12px; background: transparent; }
::-webkit-scrollbar-track, ::-webkit-scrollbar-corner { background: transparent; }
::-webkit-scrollbar-thumb {
  background-color: transparent;
  background-clip: padding-box;
  border: 4px solid transparent;
  border-radius: 999px;
  transition: background-color 160ms ease;
}
html.$htmlPreviewScrollingClassName::-webkit-scrollbar-thumb,
html.$htmlPreviewScrollingClassName ::-webkit-scrollbar-thumb {
  background-color: $rgba;
}
html { scrollbar-width: thin; scrollbar-color: transparent transparent; }
''';

  return '''
(function () {
  const id = '__appflowy_bookmark_scrollbars';
  if (document.getElementById(id)) {
    return;
  }
  const style = document.createElement('style');
  style.id = id;
  style.textContent = ${jsonEncode(css)};
  (document.head || document.documentElement).appendChild(style);
})();
''';
}

/// Whether an embedded renderer is available on this platform.
bool get canRenderLiveBookmarkPage =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
