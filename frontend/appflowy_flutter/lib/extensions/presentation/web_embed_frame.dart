import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_web_environment.dart';
import 'package:appflowy/shared/find_replace/webview_find.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_request_policy.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';

/// Whether this platform has a renderer a web embed can live in.
bool get canShowWebEmbedPages =>
    Platform.isWindows ||
    Platform.isMacOS ||
    Platform.isAndroid ||
    Platform.isIOS;

/// How one site's page should be dressed inside a frame.
@immutable
class WebEmbedPageStyle {
  const WebEmbedPageStyle({
    this.userAgent,
    this.css = '',
    this.fitsContent = false,
    this.stayInFrame,
  });

  /// Sent instead of the renderer's own, for a site that serves a better page
  /// to a phone than to a narrow desktop window.
  final String? userAgent;

  /// Added to the page once it has loaded, to hide what an embed has no use
  /// for.
  final String css;

  /// Whether the page is a single card whose height is worth reporting, so a
  /// host without a stored height can hug it.
  final bool fitsContent;

  /// Pages a click may open inside the frame instead of the browser, like a
  /// site's own sign-in.
  final bool Function(Uri uri)? stayInFrame;
}

/// A site's page shown in place, behaving like an embed rather than a browser.
///
/// Clicks that leave the page open the real browser, pop-ups never open, and
/// the renderer is the bookmark reader's, so signing in to a site there also
/// shows its embeds signed in.
class WebEmbedFrame extends StatefulWidget {
  const WebEmbedFrame({
    super.key,
    required this.url,
    this.style = const WebEmbedPageStyle(),
    this.options = const WebEmbedViewOptions(),
    this.placeholder,
  });

  final String url;
  final WebEmbedPageStyle style;
  final WebEmbedViewOptions options;

  /// Shown until the page has drawn. A small spinner when null.
  final Widget? placeholder;

  @override
  State<WebEmbedFrame> createState() => _WebEmbedFrameState();
}

class _WebEmbedFrameState extends State<WebEmbedFrame> {
  /// ⚠️ Below this a composition surface is degenerate and Windows faults in
  /// `dcomp.dll`. Nothing is built until the box is real.
  static const double minimumSurface = 64;

  /// Content measurements after each load: scripts that draw the card, like
  /// Pinterest's, finish well after the page says it has loaded.
  static const _measureDelays = [0, 600, 1500, 3000, 6000];

  /// How often a loading page is asked whether it has drawn yet. A page is
  /// shown once it has, not once every advert and tracker on it has loaded:
  /// on a news site that is the difference between a second and half a
  /// minute.
  static const _paintPoll = Duration(milliseconds: 120);

  /// How many times it is asked (about thirty seconds) before only the end
  /// of the load is waited for.
  static const _paintChecks = 250;

  /// How long a page may stand parsed without drawing anything before it is
  /// shown regardless: one that draws only into a canvas never reports it.
  static const _undrawnGrace = Duration(seconds: 4);

  /// Sign-in pages a click inside an embed should be allowed to reach.
  static const _signInHosts = {
    'accounts.google.com',
    'consent.google.com',
    'consent.youtube.com',
    'login.microsoftonline.com',
    'login.microsoft.com',
    'login.live.com',
    'account.live.com',
    // Apple's, for a shared iCloud file that asks the reader to sign in.
    'appleid.apple.com',
    'idmsa.apple.com',
    'account.apple.com',
  };

  InAppWebViewController? _controller;
  WebViewEnvironment? _environment;
  bool _environmentReady = false;

  bool _loading = true;
  bool _failed = false;
  String? _loadingUrl;
  Brightness? _appliedBrightness;
  double? _reportedHeight;
  final List<Timer> _measureTimers = [];

  /// When the page being waited for was asked for. Tells its document apart
  /// from the one it replaces, which has drawn long ago.
  DateTime _requestedAt = DateTime.now();
  Timer? _paintWatch;
  bool _probing = false;

  /// Changes with every load waited for, so a late answer about an earlier
  /// one cannot reveal this one.
  int _paintRevision = 0;

  /// Chromium's word on when this view's page draws, where it can say.
  WebEmbedPaintSignal? _paintSignal;

  String? _lastExternalUrl;
  DateTime _lastExternalAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// ⚠️ Every platform callback checks this. A late call into a view that is
  /// going away is an access violation in the Windows plugin.
  bool _closing = false;

  bool _routeSettled = false;
  Timer? _routeBackstop;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareEnvironment());
  }

  Future<void> _prepareEnvironment() async {
    final environment = await BookmarkWebEnvironment.ensure();
    if (!mounted || _closing) {
      return;
    }
    setState(() {
      _environment = environment;
      _environmentReady = true;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ⚠️ Creating a platform view while a route is still animating takes the
    // Windows renderer down. A listener attached to a route that is already
    // settling never fires, so a timer backs it up.
    if (_routeSettled) {
      return;
    }
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _routeSettled = true;
      return;
    }
    _routeAnimation ??= animation..addListener(_onRouteChanged);
    _routeBackstop ??= Timer(const Duration(milliseconds: 450), () {
      if (mounted && !_routeSettled) {
        setState(() => _routeSettled = true);
      }
    });
  }

  void _onRouteChanged() {
    final animation = _routeAnimation;
    if (animation == null) {
      return;
    }
    if (animation.status == AnimationStatus.reverse) {
      // Tear down BEFORE the closing fade, never during it.
      _closing = true;
      _controller = null;
      _cancelMeasures();
      _stopPaintWatch();
      return;
    }
    if (animation.status == AnimationStatus.completed && !_routeSettled) {
      if (mounted) {
        setState(() => _routeSettled = true);
      }
    }
  }

  @override
  void didUpdateWidget(covariant WebEmbedFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _reportedHeight = null;
      _restart(reload: false);
    } else if (widget.options.reloadToken != oldWidget.options.reloadToken) {
      _restart(reload: true);
    }
    if (widget.options.brightness != oldWidget.options.brightness) {
      unawaited(_applyColorScheme());
    }
  }

  @override
  void dispose() {
    _closing = true;
    _routeBackstop?.cancel();
    _routeAnimation?.removeListener(_onRouteChanged);
    _cancelMeasures();
    _stopPaintWatch();
    _controller = null;
    super.dispose();
  }

  bool _isCurrent(InAppWebViewController controller) =>
      mounted && !_closing && sameWebViewController(controller, _controller);

  void _restart({required bool reload}) {
    _cancelMeasures();
    _stopPaintWatch();
    _paintRevision++;
    _paintSignal?.restart();
    _requestedAt = DateTime.now();
    final controller = _controller;
    if (_failed || controller == null) {
      // A failed page has no view left; building again makes a new one.
      setState(() {
        _failed = false;
        _loading = true;
      });
      return;
    }
    setState(() => _loading = true);
    _watchFirstPaint(controller);
    unawaited(
      Future.sync(
        () => reload
            ? controller.reload()
            : controller.loadUrl(
                urlRequest: URLRequest(url: WebUri(widget.url)),
              ),
      ).catchError((Object error) {
        Log.warn('A web embed could not be reloaded: $error');
      }),
    );
  }

  void _cancelMeasures() {
    for (final timer in _measureTimers) {
      timer.cancel();
    }
    _measureTimers.clear();
  }

  void _fail() {
    _cancelMeasures();
    _stopPaintWatch();
    _controller = null;
    if (mounted && !_closing) {
      setState(() => _failed = true);
    }
  }

  /// Asks the loading page, every [_paintPoll], whether it has drawn, and
  /// shows it as soon as it has. The end of the load still shows it too.
  void _watchFirstPaint(InAppWebViewController controller) {
    _stopPaintWatch();
    final revision = _paintRevision;
    final requestedAt = _requestedAt;
    var checks = 0;
    _paintWatch = Timer.periodic(_paintPoll, (_) async {
      if (revision != _paintRevision) {
        return;
      }
      if (!_loading || !_isCurrent(controller) || ++checks > _paintChecks) {
        _stopPaintWatch();
        return;
      }
      if (_probing) {
        return;
      }
      _probing = true;
      Object? drawn;
      try {
        drawn = await controller.evaluateJavascript(
          source: _firstPaintScript(requestedAt, _undrawnGrace),
        );
      } on Object {
        drawn = null;
      } finally {
        _probing = false;
      }
      if (drawn == true && revision == _paintRevision) {
        await _reveal(controller);
      }
    });
  }

  void _stopPaintWatch() {
    _paintWatch?.cancel();
    _paintWatch = null;
  }

  /// Listens for Chromium's own first paint, which a page busy running its
  /// scripts cannot hold back the way it holds back a script asking it.
  Future<void> _listenForPaint(InAppWebViewController controller) async {
    final signal = _paintSignal = WebEmbedPaintSignal();
    bool live() => identical(signal, _paintSignal) && _isCurrent(controller);
    void reveal() {
      if (_loading && live()) {
        unawaited(_reveal(controller));
      }
    }

    try {
      await controller.addDevToolsProtocolEventListener(
        eventName: 'Page.lifecycleEvent',
        callback: (event) {
          if (live() && signal.painted(event)) {
            reveal();
          }
        },
      );
      if (!live()) {
        return;
      }
      await controller.callDevToolsProtocolMethod(
        methodName: 'Page.setLifecycleEventsEnabled',
        parameters: {'enabled': true},
      );
      if (!live()) {
        return;
      }
      final tree = await controller.callDevToolsProtocolMethod(
        methodName: 'Page.getFrameTree',
      );
      final frame = tree is Map && tree['frameTree'] is Map
          ? (tree['frameTree'] as Map)['frame']
          : null;
      final id = frame is Map ? frame['id'] : null;
      if (id is String && live() && signal.setMainFrame(id)) {
        reveal();
      }
    } on Object catch (error) {
      Log.debug('A web embed cannot hear when its page draws: $error');
    }
  }

  /// Lifts the placeholder off the page, then dresses it. Dressing waits on
  /// the page's own scripts, and the page is already dressed where the
  /// renderer ran [_adoptStyleScript] as it created the document.
  Future<void> _reveal(InAppWebViewController controller) async {
    final revision = _paintRevision;
    _stopPaintWatch();
    if (!_isCurrent(controller) || revision != _paintRevision) {
      return;
    }
    if (_loading) {
      setState(() => _loading = false);
    }
    _scheduleMeasures(controller);
    await _dress(controller);
  }

  @override
  Widget build(BuildContext context) {
    if (!canShowWebEmbedPages) {
      return WebEmbedFailure(
        url: widget.url,
        message: 'Pages cannot be shown in place on this device.',
      );
    }
    if (_failed) {
      return WebEmbedFailure(
        url: widget.url,
        message: 'This page could not be loaded.',
        onRetry: () => _restart(reload: false),
      );
    }
    final ready = _environmentReady && _routeSettled;
    return LayoutBuilder(
      builder: (context, constraints) {
        final roomy = constraints.maxWidth >= minimumSurface &&
            constraints.maxHeight >= minimumSurface;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (ready && roomy)
              IgnorePointer(
                ignoring: !widget.options.interactive,
                child: PremiumScrollExclusion(child: _webView()),
              )
            else
              const SizedBox.shrink(),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _loading ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: widget.placeholder ??
                    const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ⚠️ NO key on this view. A changing key destroys and recreates the
  // composition surface, which is the documented Windows renderer fault.
  Widget _webView() => InAppWebView(
        webViewEnvironment: _environment,
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: bookmarkPopupActivationScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
          UserScript(
            source: _adoptStyleScript('$_scrollbarCss\n${widget.style.css}'),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          supportZoom: false,
          useShouldOverrideUrlLoading: true,
          allowsInlineMediaPlayback: true,
          userAgent: widget.style.userAgent ?? '',
        ),
        onWebViewCreated: (controller) {
          if (!mounted || _closing) {
            return;
          }
          _controller = controller;
          _appliedBrightness = null;
          unawaited(_applyColorScheme());
          if (Platform.isWindows) {
            unawaited(_listenForPaint(controller));
          }
          if (_loading) {
            _watchFirstPaint(controller);
          }
        },
        onLoadStart: (controller, url) {
          if (!_isCurrent(controller)) {
            return;
          }
          _loadingUrl = url?.toString();
          _cancelMeasures();
        },
        onLoadStop: (controller, url) {
          if (!_isCurrent(controller)) {
            return;
          }
          unawaited(_reveal(controller));
        },
        onReceivedError: (controller, request, error) {
          if (!_isCurrent(controller) ||
              request.isForMainFrame != true ||
              error.type == WebResourceErrorType.CANCELLED ||
              (_loadingUrl != null && request.url.toString() != _loadingUrl)) {
            return;
          }
          Log.warn('A web embed failed to load: ${error.description}');
          _fail();
        },
        // ⚠️ Left unanswered this null-dereferences in the Windows plugin and
        // takes the renderer down.
        onPermissionRequest: (_, request) async =>
            PermissionResponse(resources: request.resources),
        // An embed never becomes a second browser: a pop-up the reader asked
        // for opens in the real one, and every other is refused.
        onCreateWindow: (controller, action) async {
          final uri = action.request.url;
          if (_isCurrent(controller) &&
              uri != null &&
              BookmarkRequestPolicy.safeExternal(uri) &&
              BookmarkRequestPolicy.userActivated(
                hasGesture: action.hasGesture,
                linkActivated:
                    action.navigationType == NavigationType.LINK_ACTIVATED,
              )) {
            _openExternally(uri);
          }
          await _rejectPopup(controller, action.windowId);
          return Platform.isWindows;
        },
        shouldOverrideUrlLoading: (controller, action) async {
          if (!_isCurrent(controller)) {
            return NavigationActionPolicy.CANCEL;
          }
          final uri = action.request.url;
          if (uri == null) {
            return NavigationActionPolicy.ALLOW;
          }
          final scheme = uri.scheme.toLowerCase();
          if (scheme == 'about' || scheme == 'data' || scheme == 'blob') {
            return NavigationActionPolicy.ALLOW;
          }
          final activated = BookmarkRequestPolicy.userActivated(
            hasGesture: action.hasGesture,
            linkActivated:
                action.navigationType == NavigationType.LINK_ACTIVATED,
          );
          if (scheme != 'http' && scheme != 'https') {
            if (activated && BookmarkRequestPolicy.safeExternal(uri)) {
              _openExternally(uri);
            }
            return NavigationActionPolicy.CANCEL;
          }
          // Frames inside the page, redirects and the page's own script go
          // where they like; only the reader's click leaves the embed.
          if (!action.isForMainFrame || !activated || _staysInFrame(uri)) {
            return NavigationActionPolicy.ALLOW;
          }
          _openExternally(uri);
          return NavigationActionPolicy.CANCEL;
        },
      );

  bool _staysInFrame(Uri uri) {
    if (_signInHosts.contains(uri.host.toLowerCase())) {
      return true;
    }
    return widget.style.stayInFrame?.call(uri) ?? false;
  }

  void _openExternally(Uri uri) {
    final url = uri.toString();
    final now = DateTime.now();
    // One click can reach both the pop-up and the navigation hook.
    if (url == _lastExternalUrl &&
        now.difference(_lastExternalAt) < const Duration(seconds: 1)) {
      return;
    }
    _lastExternalUrl = url;
    _lastExternalAt = now;
    unawaited(afLaunchUrlString(url));
  }

  Future<void> _rejectPopup(
    InAppWebViewController controller,
    int windowId,
  ) async {
    final platform = controller.platform;
    if (platform is! WindowsInAppWebViewController) {
      return;
    }
    try {
      // False from onCreateWindow means same-view navigation on Windows.
      // Rejection needs an explicit handled acknowledgement.
      await platform.rejectWindow(windowId).timeout(const Duration(seconds: 5));
    } on Object {
      // Still reported as handled: a failure must not open the pop-up here.
    }
  }

  /// Makes the page answer `prefers-color-scheme` with AppFlowy's own
  /// appearance, so a site that follows the system matches the workspace.
  Future<void> _applyColorScheme() async {
    final controller = _controller;
    final brightness = widget.options.brightness;
    if (controller == null || _closing || brightness == _appliedBrightness) {
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
    } on Object catch (error) {
      // Only a Chromium renderer emulates media; `color-scheme` still helps.
      Log.debug('A web embed could not follow the colour scheme: $error');
    }
    await _run(controller, _colorSchemeScript(scheme));
  }

  Future<void> _dress(InAppWebViewController controller) async {
    final scheme =
        widget.options.brightness == Brightness.dark ? 'dark' : 'light';
    await _run(
      controller,
      '''
${_colorSchemeScript(scheme)}
${_styleScript('$_scrollbarCss\n${widget.style.css}')}
''',
    );
  }

  void _scheduleMeasures(InAppWebViewController controller) {
    _cancelMeasures();
    if (!widget.style.fitsContent || widget.options.onContentHeight == null) {
      return;
    }
    for (final delay in _measureDelays) {
      _measureTimers.add(
        Timer(Duration(milliseconds: delay), () => _measure(controller)),
      );
    }
  }

  Future<void> _measure(InAppWebViewController controller) async {
    if (!_isCurrent(controller)) {
      return;
    }
    final Object? result;
    try {
      result = await controller.evaluateJavascript(source: _measureScript);
    } on Object {
      return;
    }
    final height = result is num ? result.toDouble() : null;
    final report = widget.options.onContentHeight;
    if (height == null ||
        height < 80 ||
        report == null ||
        !_isCurrent(controller)) {
      return;
    }
    final previous = _reportedHeight;
    if (previous != null && (previous - height).abs() < 4) {
      return;
    }
    _reportedHeight = height;
    report(height);
  }

  Future<void> _run(InAppWebViewController controller, String source) async {
    if (!_isCurrent(controller)) {
      return;
    }
    try {
      await controller.evaluateJavascript(source: source);
    } on Object catch (error) {
      Log.debug('A web embed script did not run: $error');
    }
  }
}

/// What a page that cannot be shown in place shows instead.
class WebEmbedFailure extends StatelessWidget {
  const WebEmbedFailure({
    super.key,
    required this.url,
    required this.message,
    this.onRetry,
  });

  final String url;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public_off_rounded, size: 22, color: muted),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                if (onRetry != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Try again'),
                  ),
                TextButton.icon(
                  onPressed: () => unawaited(afLaunchUrlString(url)),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open in browser'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

/// Whether the page asked for at [requestedAt] has drawn something: its own
/// document (not the one it replaces), past its first contentful paint, or
/// parsed and still blank after [grace].
String _firstPaintScript(DateTime requestedAt, Duration grace) {
  final asked = requestedAt.millisecondsSinceEpoch;
  return '''
(function () {
  if (!/^https?:\$/.test(location.protocol) ||
      performance.timeOrigin < $asked - 1500) {
    return false;
  }
  const state = document.readyState;
  if (state === 'complete' ||
      performance.getEntriesByName('first-contentful-paint').length > 0) {
    return true;
  }
  return state === 'interactive' && Date.now() - $asked > ${grace.inMilliseconds};
})();
''';
}

String _styleScript(String css) => '''
(function () {
  const id = '__appflowy_web_embed_style';
  let style = document.getElementById(id);
  if (!style) {
    style = document.createElement('style');
    style.id = id;
    (document.head || document.documentElement).appendChild(style);
  }
  style.textContent = ${jsonEncode(css)};
})();
''';

/// Dresses each top-level document as it is created, before it first draws,
/// without a node the page's own scripts could trip over.
String _adoptStyleScript(String css) => '''
(function () {
  if (window.top !== window) {
    return;
  }
  try {
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(${jsonEncode(css)});
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
  } catch (_) {}
})();
''';

/// Picks, out of Chromium's page lifecycle events, the first contentful paint
/// of the document a frame is waiting for.
///
/// Events arriving before the main frame is known are kept, and a load asked
/// for again only counts once its new document has been created, so the
/// document it replaces can never reveal it.
class WebEmbedPaintSignal {
  static const _maximumEarlyEvents = 64;

  String? _mainFrame;
  String? _document;
  bool _awaitingDocument = false;
  final _early = <Object?>[];

  /// Names the main frame and replays what came before. True when one of
  /// those events was already the paint being waited for.
  bool setMainFrame(String id) {
    _mainFrame = id;
    var painted = false;
    for (final event in _early) {
      painted = this.painted(event) || painted;
    }
    _early.clear();
    return painted;
  }

  /// A load was asked for again: only a document created after this counts.
  void restart() {
    _awaitingDocument = true;
    _document = null;
    _early.clear();
  }

  /// Whether [event], a `Page.lifecycleEvent`, is the main frame's awaited
  /// document drawing its first content.
  bool painted(Object? event) {
    if (event is! Map) {
      return false;
    }
    if (_mainFrame == null) {
      if (_early.length < _maximumEarlyEvents) {
        _early.add(event);
      }
      return false;
    }
    if (event['frameId'] != _mainFrame) {
      return false;
    }
    final loader = event['loaderId'];
    switch (event['name']) {
      case 'init':
        _document = loader is String ? loader : null;
        _awaitingDocument = false;
        return false;
      case 'firstContentfulPaint':
        return !_awaitingDocument && (_document == null || loader == _document);
      default:
        return false;
    }
  }
}

/// Thin overlay scrollbars: the renderer's own are a solid bar on Windows.
const _scrollbarCss = '''
::-webkit-scrollbar { width: 10px; height: 10px; background: transparent; }
::-webkit-scrollbar-track, ::-webkit-scrollbar-corner { background: transparent; }
::-webkit-scrollbar-thumb {
  background-color: rgba(128, 128, 128, 0.35);
  background-clip: padding-box;
  border: 3px solid transparent;
  border-radius: 999px;
}
''';

/// The bottom of what the page actually draws. `scrollHeight` is useless
/// here: several embed pages stretch the body to the viewport, so it would
/// only ever report the frame's own height back.
const _measureScript = '''
(function () {
  const body = document.body;
  if (!body) {
    return 0;
  }
  let bottom = 0;
  const visit = (parent, depth) => {
    for (const child of parent.children) {
      const style = getComputedStyle(child);
      if (style.display === 'none' ||
          style.visibility === 'hidden' ||
          style.position === 'fixed') {
        continue;
      }
      const rect = child.getBoundingClientRect();
      if (rect.height === 0 && depth < 4) {
        visit(child, depth + 1);
        continue;
      }
      bottom = Math.max(bottom, rect.bottom + window.scrollY);
    }
  };
  visit(body, 0);
  const margin = parseFloat(getComputedStyle(body).marginBottom) || 0;
  return Math.ceil(bottom + margin);
})();
''';
