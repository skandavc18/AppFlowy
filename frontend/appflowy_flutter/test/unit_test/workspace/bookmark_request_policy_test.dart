import 'dart:async';

import 'package:appflowy/workspace/application/collections/bookmark/bookmark_request_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('small host list covers exact/subdomains without broad first parties',
      () {
    expect(BookmarkRequestPolicy.domains.length, lessThanOrEqualTo(12));
    for (final domain in BookmarkRequestPolicy.domains) {
      expect(BookmarkRequestPolicy.isAdHost(domain), isTrue);
      expect(BookmarkRequestPolicy.isAdHost('a.b.$domain'), isTrue);
      expect(BookmarkRequestPolicy.isAdHost('$domain.evil.invalid'), isFalse);
      expect(BookmarkRequestPolicy.isAdHost('not$domain'), isFalse);
    }
    for (final host in [
      'google.com',
      'accounts.google.com',
      'maps.googleapis.com',
      'maps.gstatic.com',
      'stripe.com',
      'paypal.com',
      'amazon.com',
      'news.example',
      'header.example',
      'download.example',
    ]) {
      expect(BookmarkRequestPolicy.isAdHost(host), isFalse, reason: host);
    }
  });

  test('CDP patterns include scheme/host boundaries and nondefault ports', () {
    final patterns =
        BookmarkRequestPolicy.blockedUrls('https://news.example/a');
    for (final domain in BookmarkRequestPolicy.domains) {
      for (final scheme in ['http', 'https']) {
        expect(patterns, contains('$scheme://$domain/*'));
        expect(patterns, contains('$scheme://*.$domain/*'));
        expect(patterns, contains('$scheme://$domain:*/*'));
        expect(patterns, contains('$scheme://*.$domain:*/*'));
      }
    }
    expect(patterns.any((p) => p.startsWith('*')), isFalse);
    for (final url in [
      'https://news.example/header',
      'https://news.example/download',
      'https://news.example/?ad=doubleclick.net',
      'https://doubleclick.net.evil.invalid/ad',
      'https://news.example/story/foo.doubleclick.net/ordinary',
      'https://news.example/?return=https://ads.doubleclick.net/path',
      'https://maps.googleapis.com/maps/api/js',
      'https://accounts.google.com/login',
      'https://checkout.stripe.com/pay',
    ]) {
      // Native URLPattern semantics are intentionally NOT approximated with
      // whole-URL globs. Assert the host policy independently of path/query.
      expect(
        BookmarkRequestPolicy.isAdHost(Uri.parse(url).host),
        isFalse,
        reason: url,
      );
    }
  });

  test('uses URLPattern objects, never deprecated whole-URL wildcard blocking',
      () async {
    final calls = <Map<String, dynamic>>[];
    final patterns = BookmarkRequestPolicy.blockedUrls('https://news.example');
    await BookmarkRequestPolicy.install(patterns, (parameters) async {
      calls.add(parameters);
      if (calls.length == 1) throw PlatformException(code: '-2147024809');
      return <String, dynamic>{};
    });
    expect(calls, hasLength(2));
    expect(calls.last['urls'], isEmpty);
    expect(calls.last['urlPatterns'], [
      for (final pattern in patterns) {'urlPattern': pattern, 'block': true},
    ]);
  });

  test('a runtime ignoring URLPattern cannot claim blocking is installed',
      () async {
    var calls = 0;
    await expectLater(
      BookmarkRequestPolicy.install(
        BookmarkRequestPolicy.blockedUrls('https://news.example'),
        (_) async {
          calls++;
          return null;
        },
      ),
      throwsUnsupportedError,
    );
    expect(calls, 1);
  });

  for (final error in <Object>[
    MissingPluginException('unavailable'),
    PlatformException(code: 'network-unavailable'),
    const FormatException('Malformed response'),
    StateError('Disconnected'),
  ]) {
    test('${error.runtimeType} is not CDP capability evidence', () async {
      var calls = 0;
      await expectLater(
        BookmarkRequestPolicy.install(
          BookmarkRequestPolicy.blockedUrls('https://news.example'),
          (_) async {
            calls++;
            throw error;
          },
        ),
        throwsA(same(error)),
      );
      expect(
        calls,
        1,
        reason: 'Do not attempt installation after an unrelated failure.',
      );
    });
  }

  test('an intentional first-party ad-network bookmark is exempt', () {
    expect(
      BookmarkRequestPolicy.blockedUrls('https://console.adnxs.com/docs')
          .any((pattern) => pattern.contains('adnxs.com')),
      isFalse,
    );
  });

  test('activation is explicit; unknown and script requests are denied', () {
    expect(BookmarkRequestPolicy.userActivated(), isFalse);
    expect(BookmarkRequestPolicy.userActivated(hasGesture: false), isFalse);
    expect(
      BookmarkRequestPolicy.userActivated(
        hasGesture: false,
        linkActivated: true,
      ),
      isFalse,
    );
    expect(BookmarkRequestPolicy.userActivated(hasGesture: true), isTrue);
    expect(BookmarkRequestPolicy.userActivated(linkActivated: true), isTrue);
    for (final value in [
      'file:///C:/secret',
      'javascript:alert(1)',
      'data:text/html,x',
    ]) {
      expect(BookmarkRequestPolicy.safeExternal(Uri.parse(value)), isFalse);
    }
    expect(
      BookmarkRequestPolicy.safeExternal(
        Uri.parse('mailto:reader@example.com'),
      ),
      isTrue,
    );
  });

  test('target navigation waits for policy acknowledgment', () async {
    final session = BookmarkBlockingSession();
    final gate = Completer<void>();
    final entered = Completer<void>();
    final events = <String>[];
    final result = session.apply(
      enabled: true,
      firstPartyUrl: 'https://news.example',
      isCurrent: () => true,
      install: (patterns) async {
        expect(patterns, isNotEmpty);
        events.add('install');
        entered.complete();
        await gate.future;
        events.add('acknowledged');
      },
      navigate: () async {
        events.add('navigate');
      },
    );
    await entered.future;
    expect(events, ['install']);
    gate.complete();
    expect(await result, isTrue);
    expect(events, ['install', 'acknowledged', 'navigate']);
    session.close();
  });

  test('opt-out supersedes pending install, then clears before reloading',
      () async {
    final session = BookmarkBlockingSession();
    final gate = Completer<void>();
    final entered = Completer<void>();
    final events = <String>[];
    final first = session.apply(
      enabled: true,
      firstPartyUrl: 'https://news.example',
      isCurrent: () => true,
      install: (_) async {
        events.add('on');
        entered.complete();
        await gate.future;
      },
      navigate: () async {
        events.add('obsolete navigation');
      },
    );
    await entered.future;
    final second = session.apply(
      enabled: false,
      firstPartyUrl: 'https://news.example',
      isCurrent: () => true,
      install: (patterns) async {
        expect(patterns, isEmpty);
        events.add('off');
      },
      navigate: () async {
        events.add('reload');
      },
    );
    gate.complete();
    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(events, ['on', 'off', 'reload']);
    session.close();
  });

  for (final action in ['navigation', 'dispose']) {
    test('$action during install prevents late navigation', () async {
      final session = BookmarkBlockingSession();
      final gate = Completer<void>();
      final entered = Completer<void>();
      var current = true;
      var navigations = 0;
      final result = session.apply(
        enabled: true,
        firstPartyUrl: 'https://news.example',
        isCurrent: () => current,
        install: (_) async {
          entered.complete();
          await gate.future;
        },
        navigate: () async {
          navigations++;
        },
      );
      await entered.future;
      if (action == 'dispose') {
        session.close();
      } else {
        current = false;
      }
      gate.complete();
      expect(await result, isFalse);
      expect(navigations, 0);
      session.close();
    });
  }

  test('failed policy never silently navigates unprotected', () async {
    final session = BookmarkBlockingSession();
    var navigations = 0;
    expect(
      await session.apply(
        enabled: true,
        firstPartyUrl: 'https://news.example',
        isCurrent: () => true,
        install: (_) async => throw StateError('CDP unavailable'),
        navigate: () async {
          navigations++;
        },
      ),
      isFalse,
    );
    expect(navigations, 0);
    session.close();
  });
}
