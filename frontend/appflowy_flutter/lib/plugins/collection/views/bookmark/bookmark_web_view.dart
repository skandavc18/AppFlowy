import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_web_environment.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
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
  final _findSession = WebViewFindSession();
  final _findController = TextEditingController();
  final _findFocus = FocusNode(debugLabel: 'bookmark-page-find');
  final _pageFocus = FocusNode(debugLabel: 'bookmark-page');
  FindOptions _findOptions = const FindOptions();
  WebViewFindResult _findResult = WebViewFindResult.empty;
  Timer? _findDebounce;
  bool _findVisible = false;
  bool _active = true;
  String? _loadingUrl;
  Animation<double>? _routeAnimation;
  Brightness? _appliedBrightness;
  double _progress = 0;
  bool _failed = false;
  bool _ready = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _findController.addListener(_scheduleFind);
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
  void didUpdateWidget(covariant BookmarkWebPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _findDebounce?.cancel();
      _findSession.attach(null);
      _findResult = WebViewFindResult.empty;
      _loadingUrl = widget.url;
      unawaited(
        _controller?.loadUrl(
          urlRequest: URLRequest(url: WebUri(widget.url)),
        ),
      );
    }
  }

  @override
  void deactivate() {
    _active = false;
    _findDebounce?.cancel();
    _findSession.invalidatePending();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _controller;
      if (_alive && _active && controller != null) {
        unawaited(_installFindEngine(controller));
      }
    });
  }

  @override
  void dispose() {
    // Every callback checks this: a platform call that lands after the native
    // view is gone is what takes the renderer down.
    _closing = true;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _controller = null;
    _findDebounce?.cancel();
    _findSession.dispose();
    _findController
      ..removeListener(_scheduleFind)
      ..dispose();
    _findFocus.dispose();
    _pageFocus.dispose();
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
      _findSession.attach(null);
      _findDebounce?.cancel();
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
    return ContextualFindRegion(
      debugLabel: 'Bookmark web page',
      onFind: _openFind,
      onDismiss: () => _closeFind(restoreFocus: false),
      findOpen: _findVisible,
      findFocusNode: _findFocus,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openFind,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        },
        child: Focus(
          focusNode: _pageFocus,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPage(),
              if (_findVisible)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: FindReplaceBar(
                      findController: _findController,
                      findFocusNode: _findFocus,
                      options: _findOptions,
                      onOptionsChanged: (value) {
                        setState(() => _findOptions = value);
                        _scheduleFind();
                      },
                      matchCount: _findResult.count,
                      currentMatch: _findResult.index,
                      queryInvalid: _findResult.invalid,
                      busy: _findSession.pending,
                      onPrevious: _findResult.count == 0
                          ? null
                          : () => unawaited(_moveFind(forward: false)),
                      onNext: _findResult.count == 0
                          ? null
                          : () => unawaited(_moveFind(forward: true)),
                      onClose: _closeFind,
                      onTapOutside: () => _closeFind(restoreFocus: false),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage() {
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
          // Explicitly retain website history gestures on this reading surface.
          // ignore: avoid_redundant_argument_values
          allowsBackForwardNavigationGestures: true,
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
          _attachFindController(controller);
          unawaited(_installFindBridge(controller));
          _appliedBrightness = null;
          unawaited(_applyColorScheme());
        },
        onLoadStart: (controller, url) {
          if (!_alive || !sameWebViewController(controller, _controller)) {
            return;
          }
          _loadingUrl = url?.toString();
          _findDebounce?.cancel();
          _attachFindController(controller);
          if (_active) setState(() => _findResult = WebViewFindResult.empty);
        },
        onLoadStop: (controller, url) {
          if (!_alive ||
              !sameWebViewController(controller, _controller) ||
              (_loadingUrl != null && url?.toString() != _loadingUrl)) {
            return;
          }
          unawaited(_dress(controller));
          // Scrollbar decoration and find have independent readiness/results.
          unawaited(_installFindEngine(controller));
        },
        onProgressChanged: (_, progress) {
          if (_alive) {
            setState(() => _progress = progress / 100);
          }
        },
        onReceivedError: (_, request, __) {
          if (_alive && request.isForMainFrame == true) {
            _findDebounce?.cancel();
            _findSession.attach(null);
            _controller = null;
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

  void _attachFindController(InAppWebViewController controller) {
    _findSession.attach(
      (source) => controller.evaluateJavascript(
        source: source,
        contentWorld: Platform.isWindows ? htmlPreviewScrollContentWorld : null,
      ),
    );
  }

  Future<void> _installFindBridge(InAppWebViewController controller) async {
    try {
      await installWebViewFindOpenBridge(
        controller,
        contentWorld: htmlPreviewScrollContentWorld,
        onFind: _openFind,
        isCurrent: () =>
            _alive && sameWebViewController(controller, _controller),
      );
    } on PlatformException catch (error, stackTrace) {
      Log.error('Failed to install bookmark find shortcut', error, stackTrace);
    }
  }

  Future<void> _installFindEngine(InAppWebViewController controller) async {
    if (!_alive ||
        !_active ||
        !sameWebViewController(controller, _controller)) {
      return;
    }
    final palette = FindBarPalette.of(context);
    _findDebounce?.cancel();
    await _acceptFindResponse(
      _findSession.install(
        buildWebViewFindInstallScript(
          matchColor:
              _findCssColor(FindHighlightColors.match(widget.theme.brightness)),
          currentColor: _findCssColor(
            FindHighlightColors.current(widget.theme.brightness),
          ),
          currentTextColor: _findCssColor(palette.textPrimary),
        ),
      ),
    );
  }

  void _openFind() {
    if (!_alive || !_active) return;
    final wasVisible = _findVisible;
    _findSession
      ..setQuery(_findController.text, _findOptions)
      ..open();
    setState(() => _findVisible = true);
    if (!wasVisible) unawaited(_runFind());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_alive || !_active || !_findVisible) return;
      _findFocus.requestFocus();
      _findController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findController.text.length,
      );
    });
  }

  void _closeFind({bool restoreFocus = true}) {
    if (!_alive || !_active || !_findVisible) return;
    _findDebounce?.cancel();
    setState(() {
      _findVisible = false;
      _findResult = WebViewFindResult.empty;
    });
    unawaited(_clearFind());
    if (restoreFocus) _pageFocus.requestFocus();
  }

  Future<void> _clearFind() async {
    try {
      await _findSession.close();
    } on PlatformException catch (error, stackTrace) {
      Log.error('Failed to clear bookmark find highlights', error, stackTrace);
    }
  }

  void _scheduleFind() {
    if (!_findSession.setQuery(_findController.text, _findOptions)) return;
    _findDebounce?.cancel();
    if (!_alive || !_active || !_findVisible) return;
    setState(() => _findResult = WebViewFindResult.empty);
    _findDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_runFind()),
    );
  }

  Future<void> _runFind() => _acceptFindResponse(_findSession.find());

  Future<void> _moveFind({required bool forward}) =>
      _acceptFindResponse(_findSession.move(forward: forward));

  Future<void> _acceptFindResponse(Future<WebViewFindResult?> request) async {
    try {
      final result = await request;
      if (!_alive || !_active || !_findVisible || result == null) return;
      setState(() => _findResult = result);
    } on PlatformException catch (error, stackTrace) {
      Log.error('Bookmark find failed', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      Log.error('Invalid bookmark find response', error, stackTrace);
    }
  }

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
    if (!_alive || !sameWebViewController(controller, _controller)) {
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
    if (!_alive || !sameWebViewController(controller, _controller)) {
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
    _findDebounce?.cancel();
    _findSession.attach(null);
    setState(() {
      _failed = false;
      _progress = 0;
      _findResult = WebViewFindResult.empty;
    });
    unawaited(_controller?.reload());
  }
}

String _findCssColor(Color color) => 'rgba(${(color.r * 255).round()}, '
    '${(color.g * 255).round()}, ${(color.b * 255).round()}, ${color.a})';

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
