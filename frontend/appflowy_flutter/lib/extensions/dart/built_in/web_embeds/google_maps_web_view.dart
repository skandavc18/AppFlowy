import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/extensions/presentation/web_embed_widgets.dart';
import 'package:appflowy/shared/maps/app_map_toolbar.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_linux_webview/appflowy_linux_webview.dart';
import 'package:flutter/material.dart';

import 'google_maps_page.dart';
import 'google_maps_view.dart';

/// A Google Maps link where no page can be shown in place (Linux).
///
/// With a Google key in Settings it is Google's own map, drawn by the Maps
/// JavaScript API in a web view; a Maps Demo Key is enough. Without a key, or
/// once Google turns the key away or cannot be reached, it is the
/// application's own map ([GoogleMapsNativeView]).
class GoogleMapsEmbedView extends StatefulWidget {
  const GoogleMapsEmbedView({
    super.key,
    required this.link,
    required this.target,
    this.options = const WebEmbedViewOptions(),
  });

  final WebEmbedLink link;
  final GoogleMapsTarget target;
  final WebEmbedViewOptions options;

  /// Stands in for the Linux web view, so tests reach Google's map anywhere.
  @visibleForTesting
  static GoogleMapsPages? debugPages;

  /// Keys Google refused this session, with its reason. A spent daily quota
  /// is not worth asking about again on every map, so the app's own map is
  /// drawn for them until the key changes or the app starts again.
  static final Map<String, String> _refused = {};

  @visibleForTesting
  static void debugForgetRefusals() => _refused.clear();

  @override
  State<GoogleMapsEmbedView> createState() => _GoogleMapsEmbedViewState();
}

class _GoogleMapsEmbedViewState extends State<GoogleMapsEmbedView> {
  GoogleMapsPages get _pages =>
      GoogleMapsEmbedView.debugPages ?? GoogleMapsPages.linux;

  bool? _supported;

  /// Set once Google's map could not be shown for this link; a reload or a
  /// change in Settings asks again.
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    MapsSettings.instance.addListener(_onSettings);
    unawaited(
      _pages.isSupported().then((supported) {
        if (mounted) {
          setState(() => _supported = supported);
        }
      }),
    );
  }

  @override
  void didUpdateWidget(covariant GoogleMapsEmbedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link ||
        oldWidget.options.reloadToken != widget.options.reloadToken) {
      _unavailable = false;
    }
  }

  @override
  void dispose() {
    MapsSettings.instance.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (mounted) {
      setState(() => _unavailable = false);
    }
  }

  void _onFailed(String key, GoogleMapsFailure failure) {
    if (!mounted) {
      return;
    }
    if (!failure.refused) {
      Log.warn(
        "Google's map could not be shown (${failure.reason}); "
        "drawing the app's own map instead.",
      );
    } else if (GoogleMapsEmbedView._refused[key] == null) {
      Log.warn(
        'Google refused the Maps key for its map (${failure.reason}); '
        "drawing the app's own map instead.",
      );
    }
    if (failure.refused) {
      GoogleMapsEmbedView._refused[key] = failure.reason;
    }
    setState(() => _unavailable = true);
  }

  @override
  Widget build(BuildContext context) {
    final key = MapsSettings.instance.apiKey;
    final wanted = key.isNotEmpty &&
        !_unavailable &&
        !GoogleMapsEmbedView._refused.containsKey(key);
    if (wanted && _supported == null) {
      return WebEmbedLoadingPlaceholder(link: widget.link);
    }
    if (wanted && _supported == true) {
      return GoogleMapsWebView(
        link: widget.link,
        target: widget.target,
        apiKey: key,
        options: widget.options,
        pages: _pages,
        onFailed: (failure) => _onFailed(key, failure),
      );
    }
    return GoogleMapsNativeView(
      link: widget.link,
      target: widget.target,
      options: widget.options,
    );
  }
}

/// Why Google's map could not be shown.
@immutable
class GoogleMapsFailure {
  const GoogleMapsFailure(this.reason, {required this.refused});

  /// Google's own name for it where it gave one, like `OverQuotaMapError`.
  final String reason;

  /// Whether Google turned the key away, rather than not being reached.
  final bool refused;
}

/// A page Google's map is drawn in.
abstract class GoogleMapsPage {
  /// What the page posts.
  Stream<String> get messages;

  /// Runs [script] in the page, without waiting for a result.
  Future<void> run(String script);

  /// Loads the page again from [url].
  Future<void> reload(Uri url);

  Widget build(BuildContext context);

  Future<void> dispose();
}

/// Where Google's maps are drawn: the page's address and the view that shows
/// it.
@immutable
class GoogleMapsPages {
  const GoogleMapsPages({
    required this.address,
    required this.open,
    required this.isSupported,
  });

  final Future<Uri> Function() address;
  final Future<GoogleMapsPage> Function(Uri url) open;
  final Future<bool> Function() isSupported;

  /// WebKitGTK, through the Linux web view, with the page on a loopback port.
  static final GoogleMapsPages linux = GoogleMapsPages(
    address: () => GoogleMapsPageHost.instance.url,
    open: _LinuxGoogleMapsPage.open,
    isSupported: () => _linuxSupported ??= LinuxWebViewController.isSupported(),
  );

  static Future<bool>? _linuxSupported;
}

class _LinuxGoogleMapsPage implements GoogleMapsPage {
  _LinuxGoogleMapsPage(this._view);

  static Future<GoogleMapsPage> open(Uri url) async =>
      _LinuxGoogleMapsPage(await LinuxWebViewController.create(url: url));

  final LinuxWebViewController _view;

  @override
  Stream<String> get messages => _view.messages;

  @override
  Future<void> run(String script) => _view.evaluateJavascript(script);

  @override
  Future<void> reload(Uri url) => _view.load(url);

  @override
  Widget build(BuildContext context) => LinuxWebView(controller: _view);

  @override
  Future<void> dispose() => _view.dispose();
}

/// Serves [googleMapsPageHtml] on a loopback port, as the Linux web view only
/// starts on an http(s) address.
///
/// The page is the same for every map and carries nothing private; only its
/// own address, under a random token, is answered.
class GoogleMapsPageHost {
  GoogleMapsPageHost._();

  static final GoogleMapsPageHost instance = GoogleMapsPageHost._();

  static const _name = 'map.html';

  final String _token = base64UrlEncode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  Future<HttpServer>? _server;

  Future<Uri> get url async {
    final server = await (_server ??= _start());
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: [_token, _name],
    );
  }

  Future<HttpServer> _start() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(_serve, onError: (Object _) {});
      return server;
    } on Object {
      // The next map tries again.
      _server = null;
      rethrow;
    }
  }

  void _serve(HttpRequest request) {
    final response = request.response;
    try {
      final host = '${InternetAddress.loopbackIPv4.address}:'
          '${request.connectionInfo?.localPort}';
      if (request.method != 'GET' ||
          request.headers.value(HttpHeaders.hostHeader) != host ||
          request.uri.path != '/$_token/$_name') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      response.headers
        ..contentType = ContentType.html
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');
      response.write(googleMapsPageHtml);
    } on Object {
      // A view can drop a request while it changes pages.
    } finally {
      unawaited(response.close().then<void>((_) {}, onError: (Object _) {}));
    }
  }
}

/// Google's own map of a Google Maps link, drawn by the Maps JavaScript API
/// with [apiKey] in a [GoogleMapsPage].
///
/// The page is covered by the link's placeholder until the map has drawn,
/// and [onFailed] is told when Google turns the key away, cannot be reached
/// or does not draw within [deadline], for the host to show the app's own
/// map instead.
class GoogleMapsWebView extends StatefulWidget {
  const GoogleMapsWebView({
    super.key,
    required this.link,
    required this.target,
    required this.apiKey,
    required this.onFailed,
    required this.pages,
    this.options = const WebEmbedViewOptions(),
  });

  final WebEmbedLink link;
  final GoogleMapsTarget target;
  final String apiKey;
  final ValueChanged<GoogleMapsFailure> onFailed;
  final GoogleMapsPages pages;
  final WebEmbedViewOptions options;

  /// How long Google's map may take to draw before the app's own is shown.
  static const Duration deadline = Duration(seconds: 30);

  @override
  State<GoogleMapsWebView> createState() => _GoogleMapsWebViewState();
}

class _GoogleMapsWebViewState extends State<GoogleMapsWebView> {
  GoogleMapsPage? _page;
  Uri? _url;
  StreamSubscription<String>? _messages;
  Timer? _deadline;
  MapPalette? _palette;
  String? _language;
  String _look = '';

  /// Whether the page has been told what to show since it last loaded.
  bool _started = false;
  bool _shown = false;

  /// Whether the placeholder is still over the page: until it has faded out
  /// after the map drew. Gone, its spinner no longer asks for frames.
  bool _covered = true;
  bool _unplaced = false;
  bool _failed = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final palette = _palette = mapPaletteOf(context);
    _language = Localizations.maybeLocaleOf(context)?.languageCode;
    final look = googleMapsPageLook(palette);
    final encoded = jsonEncode(look);
    if (encoded == _look) {
      return;
    }
    _look = encoded;
    // A change of appearance restyles the map in place: loading it again
    // would count against the key's daily quota.
    if (_started) {
      unawaited(_page?.run(googleMapsLookScript(look)));
    }
  }

  @override
  void didUpdateWidget(covariant GoogleMapsWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link ||
        oldWidget.apiKey != widget.apiKey ||
        oldWidget.options.reloadToken != widget.options.reloadToken) {
      _reload();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _deadline?.cancel();
    unawaited(_messages?.cancel());
    final page = _page;
    _page = null;
    if (page != null) {
      unawaited(page.dispose());
    }
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final url = await widget.pages.address();
      final page = await widget.pages.open(url);
      if (!mounted || _closed) {
        await page.dispose();
        return;
      }
      _url = url;
      _messages = page.messages.listen(_onMessage);
      setState(() => _page = page);
      _armDeadline();
    } on Object catch (error) {
      _fail(GoogleMapsFailure('$error', refused: false));
    }
  }

  void _reload() {
    final page = _page;
    final url = _url;
    _started = false;
    _failed = false;
    if (page == null || url == null) {
      // Still opening: the page asks for what to show once it has loaded.
      return;
    }
    setState(() {
      _shown = false;
      _covered = true;
      _unplaced = false;
    });
    _armDeadline();
    unawaited(page.reload(url));
  }

  void _armDeadline() {
    _deadline?.cancel();
    _deadline = Timer(GoogleMapsWebView.deadline, () {
      if (!_shown) {
        _fail(const GoogleMapsFailure('timeout', refused: false));
      }
    });
  }

  void _fail(GoogleMapsFailure failure) {
    if (!mounted || _closed || _failed) {
      return;
    }
    _failed = true;
    _deadline?.cancel();
    widget.onFailed(failure);
  }

  void _onMessage(String text) {
    if (!mounted || _closed) {
      return;
    }
    final Object? message;
    try {
      message = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (message is! Map) {
      return;
    }
    final detail = message['detail'];
    final reason = detail is String ? detail : '';
    switch (message['type']) {
      case 'ready':
        // Also after the web process restarted and loaded the page again.
        _started = true;
        unawaited(_page?.run(googleMapsStartScript(_config())));
      case 'shown':
        _deadline?.cancel();
        if (!_shown) {
          setState(() => _shown = true);
        }
      case 'refused':
        _fail(GoogleMapsFailure(reason, refused: true));
      case 'unavailable':
        _fail(GoogleMapsFailure(reason, refused: false));
      case 'unplaced':
        _deadline?.cancel();
        setState(() => _unplaced = true);
      case 'open':
        unawaited(afLaunchUrlString(widget.link.url));
    }
  }

  Map<String, Object?> _config() => googleMapsPageConfig(
        apiKey: widget.apiKey,
        target: widget.target,
        palette: _palette ?? mapPaletteOf(context),
        language: _language,
      );

  void _run(String script) {
    if (_started) {
      unawaited(_page?.run(script));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unplaced) {
      return WebEmbedFailure(
        url: widget.link.url,
        message: GoogleMapsNativeView.unplacedMessage(widget.target),
        onRetry: _reload,
      );
    }
    final palette = mapPaletteOf(context);
    final page = _page;
    final stops = widget.target.stops;
    final title =
        widget.link.title ?? (stops.length == 1 ? stops.single.name : null);
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: palette.canvas)),
        if (page != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !widget.options.interactive,
              // The map takes the wheel and the trackpad, as the app's own
              // map does.
              child: PremiumScrollExclusion(child: page.build(context)),
            ),
          ),
        if (title != null && title.isNotEmpty)
          Positioned(
            left: 12,
            top: 12,
            right: GoogleMapsNativeView.toolbarWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: GoogleMapsTitleChip(
                title: title,
                icon: widget.link.icon,
                palette: palette,
              ),
            ),
          ),
        if (page != null)
          // The app's own controls, where the app's own map has them, rather
          // than Google's white ones.
          Positioned(
            right: MapMetrics.controlInset,
            top:
                MapMetrics.controlInset + GoogleMapsNativeView.toolbarClearance,
            child: IgnorePointer(
              ignoring: !widget.options.interactive,
              child: AppMapToolbar(
                palette: palette,
                onZoomIn: () => _run(googleMapsZoomScript(1)),
                onZoomOut: () => _run(googleMapsZoomScript(-1)),
                onResetView: () => _run(googleMapsResetScript),
              ),
            ),
          ),
        if (_covered)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _shown,
              child: AnimatedOpacity(
                opacity: _shown ? 0 : 1,
                duration: const Duration(milliseconds: 220),
                onEnd: () {
                  if (mounted && _shown) {
                    setState(() => _covered = false);
                  }
                },
                child: TickerMode(
                  enabled: !_shown,
                  child: WebEmbedLoadingPlaceholder(link: widget.link),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
