import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appflowy_linux_webview/appflowy_linux_webview.dart';
import 'package:flutter/widgets.dart';

/// Why Google's map could not be shown.
@immutable
class GoogleMapsFailure {
  const GoogleMapsFailure(this.reason, {required this.refused});

  /// Google's own name for it where it gave one, like `OverQuotaMapError`.
  final String reason;

  /// Whether Google turned the key away, rather than not being reached.
  final bool refused;
}

/// Keys the Maps JavaScript API turned away this session, with its reason.
///
/// A refused key, or one whose daily quota is spent, is not worth asking
/// about again on every map, so the app's own map is drawn for it until the
/// key changes or the app starts again.
abstract final class GoogleMapsRefusals {
  static final Map<String, String> _refused = {};

  static bool isRefused(String apiKey) => _refused.containsKey(apiKey);

  /// Remembers the refusal, and says whether it is news.
  static bool remember(String apiKey, String reason) {
    final known = _refused.containsKey(apiKey);
    _refused[apiKey] = reason;
    return !known;
  }

  @visibleForTesting
  static void debugForget() => _refused.clear();
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

  /// [html], served on a loopback port as [name] and shown by WebKitGTK
  /// through the Linux web view.
  factory GoogleMapsPages.linux({
    required String name,
    required String html,
  }) =>
      GoogleMapsPages(
        address: () => GoogleMapsPageHost.instance.urlFor(name, html),
        open: LinuxGoogleMapsPage.open,
        isSupported: linuxGoogleMapsSupported,
      );

  final Future<Uri> Function() address;
  final Future<GoogleMapsPage> Function(Uri url) open;
  final Future<bool> Function() isSupported;
}

/// Whether the Linux web view can show Google's maps here.
Future<bool> linuxGoogleMapsSupported() =>
    _linuxSupported ??= LinuxWebViewController.isSupported();

Future<bool>? _linuxSupported;

/// A page in the Linux web view.
class LinuxGoogleMapsPage implements GoogleMapsPage {
  LinuxGoogleMapsPage(this._view);

  static Future<GoogleMapsPage> open(Uri url) async =>
      LinuxGoogleMapsPage(await LinuxWebViewController.create(url: url));

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

/// Serves the map pages on a loopback port, as the Linux web view only starts
/// on an http(s) address.
///
/// Each page is the same for every map and carries nothing private; only
/// their own addresses, under a random token, are answered.
class GoogleMapsPageHost {
  GoogleMapsPageHost._();

  static final GoogleMapsPageHost instance = GoogleMapsPageHost._();

  final String _token = base64UrlEncode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');

  final Map<String, String> _pages = {};
  Future<HttpServer>? _server;

  /// Where [html] is served as [name].
  Future<Uri> urlFor(String name, String html) async {
    _pages[name] = html;
    final server = await (_server ??= _start());
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: [_token, name],
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
      final segments = request.uri.pathSegments;
      final html = segments.length == 2 && segments.first == _token
          ? _pages[segments.last]
          : null;
      if (request.method != 'GET' ||
          request.headers.value(HttpHeaders.hostHeader) != host ||
          html == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      response.headers
        ..contentType = ContentType.html
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');
      response.write(html);
    } on Object {
      // A view can drop a request while it changes pages.
    } finally {
      unawaited(response.close().then<void>((_) {}, onError: (Object _) {}));
    }
  }
}
