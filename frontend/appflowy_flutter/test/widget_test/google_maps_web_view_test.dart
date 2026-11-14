import 'dart:async';
import 'dart:convert';

import 'package:appflowy/extensions/dart/built_in/web_embeds/google_maps_view.dart';
import 'package:appflowy/extensions/dart/built_in/web_embeds/google_maps_web_view.dart';
import 'package:appflowy/extensions/dart/built_in/web_embeds/web_embed_sites.dart';
import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/extensions/presentation/web_embed_widgets.dart';
import 'package:appflowy/shared/maps/app_map_toolbar.dart';
import 'package:appflowy/shared/maps/google/google_maps_pages.dart';
import 'package:appflowy/shared/maps/maps_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chart_appearance_test_support.dart';

const _extension = 'test.google_maps_web';
const _key = 'demo-key';
const _place =
    'https://www.google.com/maps/place/Akshaya+Hall/@12.9329292,77.5688711,17z/data=!3m1!4b1!4m6!3m5!1s0x3bae158f91e68a6f:0xff1b8c4025545c1a!8m2!3d12.9329292!4d77.5714514';
const _named = 'https://www.google.com/maps/search/?api=1&query=Nowhere+Hall';

/// Stands in for the WebKitGTK view: remembers what it was told to run.
class _FakePage implements GoogleMapsPage {
  final _messages = StreamController<String>.broadcast();
  final scripts = <String>[];
  var reloads = 0;
  var disposed = false;

  void post(String type, [String? detail]) =>
      _messages.add(jsonEncode({'type': type, 'detail': detail}));

  Iterable<String> calls(String method) =>
      scripts.where((script) => script.contains('appflowyMap.$method('));

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> run(String script) async => scripts.add(script);

  @override
  Future<void> reload(Uri url) async => reloads++;

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: ValueKey('google-map'), color: Color(0xFF00AA00));

  @override
  Future<void> dispose() async {
    disposed = true;
    await _messages.close();
  }
}

final _opened = <_FakePage>[];
var _supported = true;

WebEmbedLink _link(String url) => ExtensionWebEmbedRegistry.recognize(url)!;

Widget _embed(String url, {int reload = 0}) => Center(
      child: SizedBox(
        width: 640,
        height: 420,
        child: WebEmbedSurface(link: _link(url), reloadToken: reload),
      ),
    );

/// Pumps [child] once translations have loaded.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String appearance = 'light',
}) async {
  await tester.pumpWidget(chartAppearanceApp(appearance, const SizedBox()));
  await tester.pumpAndSettle();
  await tester.pumpWidget(chartAppearanceApp(appearance, child));
  await tester.pump();
  await tester.pump();
}

double _placeholderOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byType(WebEmbedLoadingPlaceholder),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

void main() {
  setUpChartAppearanceFixtures();

  setUp(() async {
    for (final site in webEmbedSites()) {
      ExtensionWebEmbedRegistry.register(_extension, site);
    }
    debugCanShowWebEmbedPagesOverride = false;
    _opened.clear();
    _supported = true;
    GoogleMapsEmbedView.debugPages = GoogleMapsPages(
      address: () async => Uri.parse('http://127.0.0.1:9/token/map.html'),
      open: (url) async {
        final page = _FakePage();
        _opened.add(page);
        return page;
      },
      isSupported: () async => _supported,
    );
    await MapsSettings.instance.setApiKey(_key);
  });

  tearDown(() async {
    ExtensionWebEmbedRegistry.unregisterAll(_extension);
    debugCanShowWebEmbedPagesOverride = null;
    GoogleMapsEmbedView.debugPages = null;
    GoogleMapsRefusals.debugForget();
    await MapsSettings.instance.setApiKey('');
  });

  testWidgets(
      'with a key, Google draws the map, given the key and the place, and is '
      'shown once drawn', (tester) async {
    await _pump(tester, _embed(_place));

    final page = _opened.single;
    expect(find.byKey(const ValueKey('google-map')), findsOneWidget);
    expect(find.byType(GoogleMapsNativeView), findsNothing);
    expect(_placeholderOpacity(tester), 1);

    page.post('ready');
    await tester.pump();
    final start = page.calls('start').single;
    final config = jsonDecode(
      start.substring(start.indexOf('(') + 1, start.lastIndexOf(')')),
    ) as Map<String, dynamic>;
    expect(config['key'], _key);
    expect(config['target']['stops'], [
      {
        'name': 'Akshaya Hall',
        'point': [12.9329292, 77.5714514],
        'fill': isA<String>(),
        'fillTop': isA<String>(),
        'initial': 'A',
      },
    ]);
    expect(config['target']['zoom'], 17);
    expect(config['look']['name'], 'light');

    page.post('shown');
    await tester.pumpAndSettle();
    // Faded out and gone, so its spinner asks for no more frames.
    expect(find.byType(WebEmbedLoadingPlaceholder), findsNothing);
    expect(find.text('Akshaya Hall'), findsOneWidget);
  });

  testWidgets(
      "the app's own controls zoom the map and put it back on the link's view",
      (tester) async {
    await _pump(tester, _embed(_place));
    final page = _opened.single..post('ready');
    await tester.pump();
    page.post('shown');
    await tester.pumpAndSettle();

    expect(find.byType(AppMapToolbar), findsOneWidget);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.tap(find.byTooltip('Reset view'));
    await tester.pump();
    expect(page.calls('zoomBy'), [
      contains('zoomBy(1)'),
      contains('zoomBy(-1)'),
    ]);
    expect(page.calls('resetView'), hasLength(1));
  });

  testWidgets(
      'a change of appearance restyles the map in place, without loading it '
      'again', (tester) async {
    await _pump(tester, _embed(_place));
    final page = _opened.single..post('ready');
    await tester.pump();

    for (final appearance in const ['dark', 'paper']) {
      await tester.pumpWidget(chartAppearanceApp(appearance, _embed(_place)));
      await tester.pump();
      expect(
        page.calls('setLook').last,
        contains('"name":"$appearance"'),
        reason: appearance,
      );
    }
    expect(page.calls('start'), hasLength(1));
    expect(page.reloads, 0);
    expect(_opened, hasLength(1));
  });

  testWidgets(
      "a refused key draws the app's own map instead, and is not offered "
      'again', (tester) async {
    await _pump(tester, _embed(_place));
    final page = _opened.single..post('ready');
    await tester.pump();
    page.post('refused', 'OverQuotaMapError');
    await tester.pump();
    await tester.pump();

    expect(find.byType(GoogleMapsNativeView), findsOneWidget);
    expect(find.byKey(const ValueKey('google-map')), findsNothing);
    expect(page.disposed, isTrue);

    // Another map in the same session goes straight to the app's own.
    await _pump(tester, _embed(_named));
    expect(find.byType(GoogleMapsNativeView), findsOneWidget);
    expect(_opened, hasLength(1));

    // A new key is worth trying.
    await MapsSettings.instance.setApiKey('another-key');
    await tester.pump();
    await tester.pump();
    expect(_opened, hasLength(2));
  });

  testWidgets(
      "Google out of reach draws the app's own map for that link, and a "
      'reload asks Google again', (tester) async {
    await _pump(tester, _embed(_place));
    _opened.single.post('unavailable', 'offline');
    await tester.pump();
    await tester.pump();
    expect(find.byType(GoogleMapsNativeView), findsOneWidget);

    await tester
        .pumpWidget(chartAppearanceApp('light', _embed(_place, reload: 1)));
    await tester.pump();
    await tester.pump();
    expect(find.byType(GoogleMapsNativeView), findsNothing);
    expect(_opened, hasLength(2));
  });

  testWidgets("a map that never draws gives way to the app's own",
      (tester) async {
    await _pump(tester, _embed(_place));
    _opened.single.post('ready');
    await tester.pump(GoogleMapsWebView.deadline + const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(GoogleMapsNativeView), findsOneWidget);
  });

  testWidgets('a place Google cannot find says so and can be asked again',
      (tester) async {
    await _pump(tester, _embed(_named));
    final page = _opened.single..post('ready');
    await tester.pump();
    page.post('unplaced');
    await tester.pump();

    expect(
      find.text('“Nowhere Hall” could not be found on the map.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(page.reloads, 1);
    // The page asks for what to show again once it has loaded.
    page.post('ready');
    await tester.pump();
    expect(page.calls('start'), hasLength(2));
  });

  testWidgets("without a key or a web view, the app's own map", (tester) async {
    await MapsSettings.instance.setApiKey('');
    await _pump(tester, _embed(_place));
    expect(find.byType(GoogleMapsNativeView), findsOneWidget);

    _supported = false;
    await MapsSettings.instance.setApiKey(_key);
    await _pump(tester, _embed(_named));
    expect(find.byType(GoogleMapsNativeView), findsOneWidget);
    expect(_opened, isEmpty);
  });

  testWidgets('the page goes when the map does', (tester) async {
    await _pump(tester, _embed(_place));
    final page = _opened.single;
    await tester.pumpWidget(chartAppearanceApp('light', const SizedBox()));
    await tester.pump();
    expect(page.disposed, isTrue);
  });
}
