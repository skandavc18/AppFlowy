import 'dart:async';

import 'package:flutter/services.dart';

/// Small, static network list, not cosmetic filtering or a general tracker list.
/// Deliberately excludes publisher, Google APIs, identity and payment domains.
abstract final class BookmarkRequestPolicy {
  static const domains = <String>{
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'amazon-adsystem.com',
    'adnxs.com',
    'adsrvr.org',
    'rubiconproject.com',
    'pubmatic.com',
    'openx.net',
  };

  static bool isAdHost(String host) {
    final normalized = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return domains.any(
      (domain) => normalized == domain || normalized.endsWith('.$domain'),
    );
  }

  /// CDP `urlPatterns` uses WHATWG URLPattern, not the legacy `urls` glob
  /// (whose wildcard also consumes paths/query strings). Exempt the site's network
  /// family if a bookmark intentionally points at one of these domains.
  static List<String> blockedUrls(String firstPartyUrl) {
    final host = Uri.tryParse(firstPartyUrl)?.host.toLowerCase() ?? '';
    return [
      for (final domain in domains)
        if (host != domain && !host.endsWith('.$domain'))
          for (final scheme in ['http', 'https']) ...[
            '$scheme://$domain/*',
            '$scheme://*.$domain/*',
            '$scheme://$domain:*/*',
            '$scheme://*.$domain:*/*',
          ],
    ];
  }

  /// Older CDP silently ignores unknown optional parameters. Probe with a
  /// deliberately incomplete BlockPattern: a supporting runtime rejects its
  /// missing required fields; an older runtime accepts only the empty `urls`.
  /// The real installation must also succeed before target navigation.
  static Future<void> install(
    List<String> patterns,
    Future<dynamic> Function(Map<String, dynamic>) command, {
    bool Function()? isCurrent,
  }) async {
    if (!(isCurrent?.call() ?? true)) return;
    if (patterns.isNotEmpty) {
      var recognized = false;
      try {
        await command({
          'urls': <String>[],
          'urlPatterns': [<String, dynamic>{}],
        });
      } on PlatformException catch (error) {
        // WebView2 reports E_INVALIDARG through the vendored HRESULT channel.
        // Missing plugins/transport failures are not evidence of URLPattern
        // support and must not be followed by a supposedly supported install.
        recognized = const {'-2147024809', '-32602', 'invalid-parameters'}
            .contains(error.code);
        if (!recognized) rethrow;
      }
      if (!recognized) {
        throw UnsupportedError('CDP URLPattern blocking unavailable');
      }
    }
    if (!(isCurrent?.call() ?? true)) return;
    await command({
      'urls': <String>[],
      'urlPatterns': [
        for (final pattern in patterns) {'urlPattern': pattern, 'block': true},
      ],
    });
  }

  static bool userActivated({bool? hasGesture, bool linkActivated = false}) =>
      hasGesture == true || (hasGesture == null && linkActivated);

  static bool safeExternal(Uri uri) =>
      const {'https', 'http', 'mailto', 'tel'}.contains(uri.scheme);
}

/// Serializes policy installation and navigation. A superseded request may
/// finish its native call but cannot navigate; the newest policy runs last.
/// No per-resource Dart callback is installed.
class BookmarkBlockingSession {
  int _revision = 0;
  bool _closed = false;
  Future<void> _tail = Future.value();

  void invalidate() => _revision++;

  void close() {
    _closed = true;
    invalidate();
  }

  Future<bool> apply({
    required bool enabled,
    required String firstPartyUrl,
    required Future<void> Function(List<String>) install,
    required Future<void> Function() navigate,
    required bool Function() isCurrent,
  }) {
    final revision = ++_revision;
    bool current() => !_closed && revision == _revision && isCurrent();
    final result = Completer<bool>();
    _tail = _tail.then((_) async {
      if (!current()) {
        result.complete(false);
        return;
      }
      try {
        await install(
          enabled ? BookmarkRequestPolicy.blockedUrls(firstPartyUrl) : const [],
        ).timeout(const Duration(seconds: 5));
        if (!current()) {
          result.complete(false);
          return;
        }
        await navigate().timeout(const Duration(seconds: 5));
        // A successful navigation necessarily changes the document generation.
        // Only session disposal or a superseding policy invalidates this ack.
        result.complete(!_closed && revision == _revision);
      } on Object {
        // Fail closed for this navigation, with an explicit UI opt-out/retry.
        // A timeout cannot cancel a native command; never race another command
        // on the same session after an uncertain completion.
        _closed = true;
        result.complete(false);
      }
    });
    return result.future;
  }
}

/// Best-effort document-start guard, not a claim that every popup is blocked.
/// Explicit user activation retains window.open (including authentication).
/// Does not inspect page text, replace links, or mutate article content.
const bookmarkPopupActivationScript = '''
(() => {
  const original = window.open;
  window.open = function(...args) {
    if (navigator.userActivation && !navigator.userActivation.isActive) return null;
    return Reflect.apply(original, this, args);
  };
})()
''';
