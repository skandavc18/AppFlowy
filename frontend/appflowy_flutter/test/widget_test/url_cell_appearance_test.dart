import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/database/widgets/cell/property_style_cell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const _modes = ['light', 'dark', 'paper'];
const _url = 'https://www.example.invalid/guides/quiet-links?ref=table#reading';
const _rawUrl = 'https://www.example.invalid:8443/notes/100%25-ready'
    '?next=%2Fnotes%3Fx%3D1&tag=blue%20green#part%202';
const _newUrl = 'https://updated.example.invalid:9443/other%20page'
    '?filter=a%26b#new%20section';
const _faviconUrl = 'https://example.invalid/favicon.ico';
const _captureKey = ValueKey('url-cells-reference');
late Uint8List _faviconPng;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final families = _modes
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet();
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
    // Native PNG encoding runs outside the widget tests' fake clock.
    _faviconPng = await _makeFavicon();
  });

  for (final mode in _modes) {
    _case('$mode: idle and hover are flat, legible and stationary',
        (tester, launcher, images) async {
      await tester.pumpWidget(_app(mode, _grid()));
      await _finishFavicons(tester);
      expect(tester.widget<Text>(_part('host')).data, 'example.invalid');
      final path = tester.widget<Text>(_part('path'));
      expect(path.data, 'guides/quiet-links');
      expect(path.style!.fontSize, 11.5);
      expect(path.style!.color, _palette(tester).textSecondary);
      expect(path.maxLines, 1);
      expect(path.overflow, TextOverflow.ellipsis);
      expect(_tooltip(tester).message, _url);
      expect(_tooltip(tester).excludeFromSemantics, isTrue);
      expect(images.urls, [Uri.parse(_faviconUrl)]);
      _expectFlat(tester);
      _expectAppearance(tester, active: false);
      final geometry = _geometry(tester);
      final context = tester.element(_chip());
      expect(PaperTheme.isEnabled(context), mode == 'paper');
      if (mode == 'paper') {
        final backdrop = Theme.of(context).cardColor;
        expect(backdrop.r, greaterThan(backdrop.b));
      }

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(_part('surface')));
        await _frames(tester);
        _expectAppearance(tester, active: true);
        _expectFlat(tester);
        expect(_geometry(tester), geometry);
        await mouse.moveTo(Offset.zero);
        await _frames(tester);
        _expectAppearance(tester, active: false);
        _expectFlat(tester);
        expect(_geometry(tester), geometry);
        expect(launcher.urls, isEmpty);
      } finally {
        await mouse.removePointer();
      }
    });

    _case('$mode: keyboard focus keeps the accent after hover exits',
        (tester, launcher, _) async {
      await tester.pumpWidget(_app(mode, _grid()));
      await _finishFavicons(tester);
      final geometry = _geometry(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _frames(tester);
      expect(_focus(tester).hasPrimaryFocus, isTrue);
      _expectAppearance(tester, active: true);
      _expectFlat(tester);
      expect(_geometry(tester), geometry);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(_part('surface')));
        await _frames(tester);
        await mouse.moveTo(Offset.zero);
        await _frames(tester);
        expect(_focus(tester).hasPrimaryFocus, isTrue);
        _expectAppearance(tester, active: true);
        expect(_geometry(tester), geometry);
        _focus(tester).unfocus();
        await _frames(tester);
        _expectAppearance(tester, active: false);
        _expectFlat(tester);
        expect(_geometry(tester), geometry);
        expect(launcher.urls, isEmpty);
      } finally {
        await mouse.removePointer();
      }
    });

    _case('$mode: thumbnail off is a compact link with no favicon request',
        (tester, launcher, images) async {
      await tester.pumpWidget(
        _app(mode, _grid(url: _rawUrl, thumbnail: false, height: 32)),
      );
      await _frames(tester);
      expect(_within(_chip(), find.byType(Image)), findsNothing);
      expect(_within(_chip(), find.byType(ClipRRect)), findsNothing);
      expect(_part('path'), findsNothing);
      final glyph = _within(_chip(), find.byIcon(Icons.link_rounded));
      expect(tester.widget<Icon>(glyph).size, 16);
      expect(tester.getSize(glyph), const Size.square(20));
      expect(tester.getSize(_part('surface')).height, 32);
      expect(_tooltip(tester).message, _rawUrl);
      _expectFlat(tester);
      await tester.tap(_part('surface'), kind: PointerDeviceKind.mouse);
      await _frames(tester);
      _expectFlat(tester);
      expect(launcher.urls, [_rawUrl]);
      expect(images.urls, isEmpty);
    });

    _case('$mode: a failed favicon is a visible flat public icon',
        (tester, launcher, images) async {
      images.statusCode = HttpStatus.notFound;
      await tester.pumpWidget(_app(mode, _grid()));
      final failures = await _finishFavicons(tester, expectFailure: true);
      expect(failures.single, isA<NetworkImageLoadException>());
      final fallback = _within(_chip(), find.byIcon(Icons.public_rounded));
      expect(fallback, findsOneWidget);
      expect(tester.getSize(fallback), const Size.square(20));
      expect(tester.widget<Icon>(fallback).size, 18);
      expect(tester.widget<Icon>(fallback).color, _palette(tester).textMuted);
      expect(images.urls, isNotEmpty);
      expect(images.urls, everyElement(Uri.parse(_faviconUrl)));
      _expectFlat(tester);
      await tester.tap(_part('surface'), kind: PointerDeviceKind.mouse);
      await _frames(tester);
      expect(launcher.urls, [_url]);
    });

    _case('$mode: 60/80/120px intrinsic tall rows fit at 2x text scale',
        (tester, launcher, _) async {
      for (final width in [60.0, 80.0, 120.0]) {
        for (final thumbnail in [true, false]) {
          await tester.pumpWidget(
            _app(
              mode,
              _grid(width: width, height: 140, thumbnail: thumbnail),
              textScale: 2,
            ),
          );
          if (thumbnail) {
            await _finishFavicons(tester);
          } else {
            await _frames(tester);
          }
          expect(find.byType(IntrinsicHeight), findsOneWidget);
          expect(_within(_chip(), find.byType(LayoutBuilder)), findsNothing);
          expect(tester.getSize(_part('surface')), Size(width, 140));
          final box = tester.renderObject<RenderBox>(_part('surface'));
          for (final measurement in [
            box.getMinIntrinsicHeight(width),
            box.getMaxIntrinsicHeight(width),
            box.getMinIntrinsicWidth(140),
            box.getMaxIntrinsicWidth(140),
          ]) {
            expect(measurement.isFinite, isTrue);
            expect(measurement, greaterThanOrEqualTo(0));
          }
          final bounds = tester.getRect(_part('surface'));
          expect(
            tester.getRect(_part('open-indicator')).right,
            lessThanOrEqualTo(bounds.right),
          );
          final geometry = _geometry(tester);
          _focus(tester).requestFocus();
          await _frames(tester);
          _expectAppearance(tester, active: true);
          expect(_geometry(tester), geometry);
          _focus(tester).unfocus();
          await _frames(tester);
          _expectFlat(tester);
          expect(
            tester.takeException(),
            isNull,
            reason: '$mode, width $width, thumbnail $thumbnail',
          );
        }
      }
      expect(launcher.urls, isEmpty);
    });

    _case('$mode: resting and hovered URL cell visual reference',
        (tester, launcher, _) async {
      await tester.pumpWidget(_app(mode, _reference(mode)));
      await _finishFavicons(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(_part('surface', id: 'hovered')));
        await _frames(tester);
        for (final id in ['resting', 'hovered', 'compact']) {
          _expectAppearance(tester, id: id, active: id == 'hovered');
          _expectFlat(tester, id: id);
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(_captureKey),
          matchesGoldenFile('goldens/url_cells_$mode.png'),
        );
        expect(launcher.urls, isEmpty);
      } finally {
        await mouse.removePointer();
      }
    });
  }

  _case('primary mouse release opens the complete raw destination exactly once',
      (tester, launcher, _) async {
    await tester.pumpWidget(_app('light', _grid(url: _rawUrl)));
    await _finishFavicons(tester);
    // The transparent padding is part of the link, not just its text glyphs.
    final press = await tester.startGesture(
      tester.getTopLeft(_part('surface')) + const Offset(2, 2),
      kind: PointerDeviceKind.mouse,
    );
    try {
      await tester.pump();
      expect(launcher.urls, isEmpty);
      await press.up();
      await _frames(tester);
      expect(launcher.urls, [_rawUrl]);
    } finally {
      await press.removePointer();
    }
    await _frames(tester);
    expect(launcher.urls, [_rawUrl]);
  });

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    _case('${key.keyLabel}: a down/up pair activates once, not twice',
        (tester, launcher, _) async {
      await tester.pumpWidget(
        _app('light', _grid(url: _rawUrl, thumbnail: false)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _frames(tester);
      expect(_focus(tester).hasPrimaryFocus, isTrue);
      expect(launcher.urls, isEmpty);
      await tester.sendKeyDownEvent(key);
      try {
        await _frames(tester);
        expect(launcher.urls, [_rawUrl]);
      } finally {
        await tester.sendKeyUpEvent(key);
      }
      await _frames(tester);
      expect(launcher.urls, [_rawUrl]);
      await tester.sendKeyEvent(key);
      await _frames(tester);
      expect(launcher.urls, [_rawUrl, _rawUrl]);
    });
  }

  _case('right-click and navigation keys never launch the link',
      (tester, launcher, _) async {
    await tester.pumpWidget(_app('light', _grid(thumbnail: false)));
    final rightClick = await tester.startGesture(
      tester.getCenter(_part('surface')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    try {
      await rightClick.up();
    } finally {
      await rightClick.removePointer();
    }
    await _frames(tester);
    expect(launcher.urls, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _frames(tester);
    expect(_focus(tester).hasPrimaryFocus, isTrue);
    for (final key in [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.tab,
    ]) {
      await tester.sendKeyEvent(key);
      await _frames(tester);
      expect(launcher.urls, isEmpty, reason: key.keyLabel);
    }
  });

  _case('ellipsis keeps the raw destination accessible as one tappable link',
      (tester, launcher, _) async {
    await tester.pumpWidget(
      _app('paper', _grid(url: _rawUrl, width: 80), textScale: 2),
    );
    await _finishFavicons(tester);
    final node = tester.getSemantics(_link());
    final data = node.getSemanticsData();
    expect(data.label, _rawUrl);
    expect(data.hasFlag(ui.SemanticsFlag.isLink), isTrue);
    expect(data.hasFlag(ui.SemanticsFlag.isButton), isFalse);
    expect(data.hasFlag(ui.SemanticsFlag.isFocusable), isTrue);
    expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(_tooltip(tester).message, _rawUrl);
    expect(_tooltip(tester).excludeFromSemantics, isTrue);
    expect(tester.widget<Text>(_part('host')).overflow, TextOverflow.ellipsis);
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await _frames(tester);
    expect(launcher.urls, [_rawUrl]);
  });

  _case(
      'focused URL replacement retains the node but launches only the new URL',
      (tester, launcher, _) async {
    await tester.pumpWidget(_app('light', _grid(url: _rawUrl)));
    await _finishFavicons(tester);
    final state = tester.state(_chip());
    final focus = _focus(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _frames(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(_part('surface')));
      await _frames(tester);
      await mouse.moveTo(Offset.zero);
      await _frames(tester);
      await tester.pumpWidget(_app('paper', _grid(url: _newUrl)));
      await _finishFavicons(tester);
      expect(tester.state(_chip()), same(state));
      expect(_focus(tester), same(focus));
      expect(focus.hasPrimaryFocus, isTrue);
      expect(
        tester.widget<Text>(_part('host')).data,
        'updated.example.invalid',
      );
      expect(_tooltip(tester).message, _newUrl);
      expect(tester.getSemantics(_link()).getSemanticsData().label, _newUrl);
      _expectAppearance(tester, active: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _frames(tester);
      expect(launcher.urls, [_newUrl]);
      focus.unfocus();
      await _frames(tester);
      _expectAppearance(tester, active: false);
      _expectFlat(tester);
    } finally {
      await mouse.removePointer();
    }
  });

  _case('persistent keyed fields keep independent hover state after reordering',
      (tester, launcher, images) async {
    Widget fields(List<String> ids) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final id in ids)
              _grid(id: id, url: id == 'a' ? _url : _newUrl, thumbnail: false),
          ],
        );
    await tester.pumpWidget(_app('light', fields(['a', 'b'])));
    await _frames(tester);
    final first = tester.state(_chip('a'));
    final second = tester.state(_chip('b'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(_part('surface', id: 'a')));
      await _frames(tester);
      _expectAppearance(tester, id: 'a', active: true);
      _expectAppearance(tester, id: 'b', active: false);
      // Move out first: a row moving under a pointer is legitimate hover.
      await mouse.moveTo(Offset.zero);
      await _frames(tester);
      await tester.pumpWidget(_app('light', fields(['b', 'a'])));
      await _frames(tester);
      expect(tester.state(_chip('a')), same(first));
      expect(tester.state(_chip('b')), same(second));
      _expectAppearance(tester, id: 'a', active: false);
      _expectAppearance(tester, id: 'b', active: false);
      await mouse.moveTo(tester.getCenter(_part('surface', id: 'b')));
      await _frames(tester);
      _expectAppearance(tester, id: 'a', active: false);
      _expectAppearance(tester, id: 'b', active: true);
      expect(images.urls, isEmpty);
      expect(launcher.urls, isEmpty);
    } finally {
      await mouse.removePointer();
    }
  });

  for (final url in ['', '/notes/local', 'https:///notes/no-host']) {
    _case('hostless "$url" uses a public icon without network IO',
        (tester, launcher, images) async {
      await tester.pumpWidget(_app('paper', _grid(url: url)));
      await _frames(tester);
      expect(_within(_chip(), find.byType(Image)), findsNothing);
      expect(
        _within(_chip(), find.byIcon(Icons.public_rounded)),
        findsOneWidget,
      );
      expect(tester.widget<Text>(_part('host')).data, url);
      _expectFlat(tester);
      expect(images.urls, isEmpty);
      expect(launcher.urls, isEmpty);
    });
  }

  _case(
      'real favicon pixels use DPR decode hints and survive cached URL updates',
      (tester, launcher, images) async {
    for (final dpr in [1.25, 2.0]) {
      tester.view
        ..devicePixelRatio = dpr
        ..physicalSize = Size(800 * dpr, 600 * dpr);
      await tester.pumpWidget(_app('light', _grid(url: _rawUrl)));
      await _finishFavicons(tester);
      final image = tester.widget<Image>(_within(_chip(), find.byType(Image)));
      final provider = image.image as ResizeImage;
      expect(provider.width, (20 * dpr).ceil());
      expect(provider.height, isNull);
      expect((provider.imageProvider as NetworkImage).url, _faviconUrl);
      expect(image.width, 20);
      expect(image.height, 20);
      expect(image.fit, BoxFit.contain);
      expect(
        tester.getSize(_within(_chip(), find.byType(Image))),
        const Size.square(20),
      );
      final decoded = _rawImage(tester).image!;
      expect(decoded.width, lessThanOrEqualTo(provider.width!));
      expect(decoded.width, decoded.height);
      await _expectFaviconPixels(tester, decoded);
      final retained = decoded.clone();
      final requests = images.urls.length;
      try {
        final updated = _app(
          'dark',
          _grid(url: 'https://example.invalid/another?raw=%25#new'),
        );
        await tester.pumpWidget(updated);
        await _finishFavicons(tester);
        expect(_rawImage(tester).image!.isCloneOf(retained), isTrue);
        // Retaining ImageState alone would not prove a cache hit.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(updated);
        await _finishFavicons(tester);
        expect(_rawImage(tester).image!.isCloneOf(retained), isTrue);
        expect(images.urls.length, requests);
        await _expectFaviconPixels(tester, _rawImage(tester).image!);
      } finally {
        retained.dispose();
      }
    }
    expect(launcher.urls, isEmpty);
  });

  _case(
      'pending favicon uses the public glyph, never a spinner or a new layout',
      (tester, launcher, images) async {
    images.responseGate = Completer<void>();
    await tester.pumpWidget(_app('light', _grid()));
    await _frames(tester);
    final geometry = _geometry(tester);
    try {
      expect(images.urls, [Uri.parse(_faviconUrl)]);
      expect(
        _within(_chip(), find.byIcon(Icons.public_rounded)),
        findsOneWidget,
        reason: 'Null loading progress also means no bytes have arrived yet; '
            'the public fallback must remain visible until the first frame.',
      );
      _expectFlat(tester);
    } finally {
      // Finish decoding even if the initial fallback regression is exposed.
      images.release();
      await _finishFavicons(tester);
    }
    expect(_within(_chip(), find.byIcon(Icons.public_rounded)), findsNothing);
    expect(_rawImage(tester).image, isNotNull);
    expect(_geometry(tester), geometry);
    _expectFlat(tester);
    expect(launcher.urls, isEmpty);
  });

  _case('invalid image bytes also produce the visible public fallback',
      (tester, launcher, images) async {
    images.bytes = Uint8List.fromList([0, 1, 2, 3]);
    await tester.pumpWidget(_app('dark', _grid()));
    await _finishFavicons(tester, expectFailure: true);
    expect(_within(_chip(), find.byIcon(Icons.public_rounded)), findsOneWidget);
    _expectFlat(tester);
    expect(launcher.urls, isEmpty);
  });

  _case('a shortened path does not repeat the host or expose query text',
      (tester, launcher, _) async {
    final path = List.filled(12, 'long-segment').join('/');
    final url = 'https://www.example.invalid/$path?private=value#section';
    await tester.pumpWidget(_app('light', _grid(url: url)));
    await _finishFavicons(tester);
    final detail = tester.widget<Text>(_part('path')).data!;
    expect(detail, startsWith('long-segment/'));
    expect(detail, endsWith('…'));
    expect(detail.length, lessThan(path.length));
    expect(detail, isNot(contains('example.invalid')));
    expect(detail, isNot(contains('private=value')));
    expect(detail, isNot(contains('section')));
    expect(_tooltip(tester).message, url);
    expect(launcher.urls, isEmpty);
  });

  _case('a host-only destination has no redundant secondary line',
      (tester, launcher, _) async {
    await tester.pumpWidget(
      _app('light', _grid(url: 'https://www.example.invalid/?ref=table#top')),
    );
    await _finishFavicons(tester);
    expect(tester.widget<Text>(_part('host')).data, 'example.invalid');
    expect(_part('path'), findsNothing);
    _expectFlat(tester);
    expect(launcher.urls, isEmpty);
  });

  _case('reduced motion updates focus decoration and arrow without animation',
      (tester, launcher, _) async {
    await tester.pumpWidget(
      _app('paper', _grid(thumbnail: false), disableAnimations: true),
    );
    await _frames(tester);
    final geometry = _geometry(tester);
    _focus(tester).requestFocus();
    await tester.pump();
    await tester.pump();
    _expectAppearance(tester, active: true, duration: Duration.zero);
    expect(_geometry(tester), geometry);
    _focus(tester).unfocus();
    await tester.pump();
    await tester.pump();
    _expectAppearance(tester, active: false, duration: Duration.zero);
    _expectFlat(tester);
    expect(launcher.urls, isEmpty);
  });
}

void _case(
  String name,
  Future<void> Function(WidgetTester, _UrlLauncher, _FaviconClient) body,
) {
  testWidgets(
    name,
    (tester) async {
      tester.view
        ..physicalSize = const Size(800, 600)
        ..devicePixelRatio = 1;
      final semantics = tester.ensureSemantics();
      final previousLauncher = UrlLauncherPlatform.instance;
      final previousClient = debugNetworkImageHttpClientProvider;
      final previousHighlight = FocusManager.instance.highlightStrategy;
      final launcher = _UrlLauncher();
      final images = _FaviconClient(_faviconPng);
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
      UrlLauncherPlatform.instance = launcher;
      debugNetworkImageHttpClientProvider = () => images;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      try {
        await body(tester, launcher, images);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          images.release();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        } finally {
          cache.clear();
          cache.clearLiveImages();
          debugNetworkImageHttpClientProvider = previousClient;
          UrlLauncherPlatform.instance = previousLauncher;
          FocusManager.instance.highlightStrategy = previousHighlight;
          semantics.dispose();
          tester.view.reset();
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Finder _chip([String id = 'primary']) => find.byKey(ValueKey('test-url-$id'));
Finder _within(Finder parent, Finder child) =>
    find.descendant(of: parent, matching: child);
Finder _part(String suffix, {String id = 'primary'}) =>
    _within(_chip(id), find.byKey(ValueKey('bookmark-link-$suffix')));
Finder _link() => _within(_chip(), find.byKey(const ValueKey('bookmark-link')));
Tooltip _tooltip(WidgetTester tester) =>
    tester.widget<Tooltip>(_within(_chip(), find.byType(Tooltip)));
FocusNode _focus(WidgetTester tester) => tester
    .widget<FocusableActionDetector>(
      _within(_chip(), find.byType(FocusableActionDetector)),
    )
    .focusNode!;
InteractivePalette _palette(WidgetTester tester, [String id = 'primary']) =>
    interactivePaletteOf(tester.element(_chip(id)));
RawImage _rawImage(WidgetTester tester) =>
    tester.widget<RawImage>(_within(_chip(), find.byType(RawImage)));

Map<String, Rect> _geometry(WidgetTester tester) => {
      for (final part in ['surface', 'host', 'path', 'open-indicator'])
        if (_part(part).evaluate().isNotEmpty)
          part: tester.getRect(_part(part)),
    };

void _expectAppearance(
  WidgetTester tester, {
  required bool active,
  String id = 'primary',
  Duration duration = InteractiveMetrics.hover,
}) {
  final palette = _palette(tester, id);
  final textAnimation = tester.widget<AnimatedDefaultTextStyle>(
    _within(_chip(id), find.byType(AnimatedDefaultTextStyle)),
  );
  final inheritedStyle = DefaultTextStyle.of(tester.element(_chip(id))).style;
  expect(inheritedStyle.fontFamily, isNotNull);
  expect(textAnimation.duration, duration);
  for (final style in [
    textAnimation.style,
    DefaultTextStyle.of(tester.element(_part('host', id: id))).style,
  ]) {
    expect(style.fontFamily, inheritedStyle.fontFamily);
    expect(style.fontFamilyFallback, inheritedStyle.fontFamilyFallback);
    expect(style.fontSize, 13);
    expect(style.fontWeight, FontWeight.w500);
    expect(style.color, active ? palette.accent : palette.text);
    expect(
      style.decoration,
      active ? TextDecoration.underline : TextDecoration.none,
    );
    expect(style.decorationColor, palette.accent.withValues(alpha: 0.5));
  }
  final indicator = _part('open-indicator', id: id);
  final opacity = tester.widget<AnimatedOpacity>(indicator);
  expect(opacity.opacity, active ? 1 : 0);
  expect(opacity.duration, duration);
  final fade = tester.widget<FadeTransition>(
    _within(indicator, find.byType(FadeTransition)),
  );
  expect(fade.opacity.value, active ? 1 : 0);
  final arrow = tester.widget<Icon>(
    _within(indicator, find.byIcon(Icons.north_east_rounded)),
  );
  expect(arrow.size, 14);
  expect(arrow.color, palette.accent);
}

void _expectFlat(WidgetTester tester, {String id = 'primary'}) {
  final chip = _chip(id);
  expect(
    tester.widget<Padding>(_part('surface', id: id)).padding,
    const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
  );
  for (final type in [
    Card,
    Material,
    DecoratedBox,
    ColoredBox,
    PhysicalModel,
    PhysicalShape,
    CircularProgressIndicator,
    LinearProgressIndicator,
    LayoutBuilder,
  ]) {
    expect(
      _within(chip, find.byType(type)),
      findsNothing,
      reason: '$type in $id',
    );
  }
  for (final container in tester.widgetList<Container>(
    _within(chip, find.byType(Container)),
  )) {
    expect(container.color, isNull);
    expect(container.decoration, isNull);
    expect(container.foregroundDecoration, isNull);
  }
  for (final clip in tester.widgetList<ClipRRect>(
    _within(chip, find.byType(ClipRRect)),
  )) {
    expect(
      clip.child,
      isA<Image>(),
      reason: 'Only the favicon may be rounded.',
    );
    expect(clip.borderRadius, BorderRadius.circular(4));
    expect(clip.clipBehavior, Clip.antiAlias);
  }
}

// Flush deferred focus notifications, then build and finish the real 150ms
// transitions without waiting for tooltips.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 180));
}

Future<List<Object>> _finishFavicons(
  WidgetTester tester, {
  bool expectFailure = false,
}) async {
  final elements = _within(find.byType(BookmarkChip), find.byType(Image))
      .evaluate()
      .toList();
  expect(elements, isNotEmpty);
  final listeners = <(ImageStream, ImageStreamListener)>[];
  final failures = <Object>[];
  var completed = 0;
  for (final element in elements) {
    final image = element.widget as Image;
    // Resolve the mounted provider/configuration, including its ResizeImage key.
    final stream = image.image.resolve(
      createLocalImageConfiguration(
        element,
        size: image.width != null && image.height != null
            ? Size(image.width!, image.height!)
            : null,
      ),
    );
    var finished = false;
    void finish() {
      if (!finished) completed++;
      finished = true;
    }

    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        finish();
      },
      onError: (Object error, StackTrace? stack) {
        failures.add(error);
        finish();
      },
    );
    stream.addListener(listener);
    listeners.add((stream, listener));
  }
  try {
    // Engine PNG decoding needs real IO turns interleaved with fake-clock pumps.
    for (var attempt = 0;
        completed < elements.length && attempt < 100;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      completed,
      elements.length,
      reason: 'Every favicon must finish decoding.',
    );
    expect(failures, expectFailure ? hasLength(elements.length) : isEmpty);
  } finally {
    for (final (stream, listener) in listeners) {
      stream.removeListener(listener);
    }
  }
  await _frames(tester);
  if (!expectFailure) {
    final raw = tester.widgetList<RawImage>(
      _within(find.byType(BookmarkChip), find.byType(RawImage)),
    );
    expect(raw, hasLength(elements.length));
    for (final image in raw) {
      expect(
        image.image,
        isNotNull,
        reason: 'A fallback is not decoded pixels.',
      );
      expect(image.fit, BoxFit.contain);
    }
  }
  return failures;
}

Future<void> _expectFaviconPixels(WidgetTester tester, ui.Image image) async {
  final bytes = await tester.runAsync(
    () => image.toByteData(),
  );
  expect(bytes, isNotNull);
  for (final sample in [
    (x: image.width ~/ 4, rgba: [0x14, 0x3C, 0xDC, 0xFF]),
    (x: image.width * 3 ~/ 4, rgba: [0x16, 0x98, 0x5D, 0xFF]),
  ]) {
    final offset = ((image.height ~/ 2) * image.width + sample.x) * 4;
    expect(
      List.generate(4, (channel) => bytes!.getUint8(offset + channel)),
      sample.rgba,
    );
  }
}

Future<Uint8List> _makeFavicon() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 16, 32),
    Paint()..color = const Color(0xFF143CDC),
  );
  canvas.drawRect(
    const Rect.fromLTWH(16, 0, 16, 32),
    Paint()..color = const Color(0xFF16985D),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

ThemeData _theme(String mode) => DesktopAppearance().getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );

Widget _app(
  String mode,
  Widget child, {
  double textScale = 1,
  bool disableAnimations = false,
}) =>
    MaterialApp(
      theme: _theme(mode),
      themeAnimationDuration: Duration.zero,
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: navigator!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    );

// The zero-width sibling forces a tall grid row without constraining the chip
// directly. IntrinsicHeight must measure the real Row/Expanded descendant.
Widget _grid({
  String id = 'primary',
  String url = _url,
  bool thumbnail = true,
  double width = 320,
  double height = 92,
}) =>
    SizedBox(
      key: ValueKey('test-grid-row-$id'),
      width: width,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 0, height: height),
            Expanded(
              child: BookmarkChip(
                key: ValueKey('test-url-$id'),
                url: url,
                thumbnail: thumbnail,
              ),
            ),
          ],
        ),
      ),
    );

Widget _reference(String mode) => Builder(
      builder: (context) => RepaintBoundary(
        key: _captureKey,
        child: ColoredBox(
          color: Theme.of(context).cardColor,
          child: SizedBox(
            width: 440,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'URL cells · $mode',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  for (final entry in [
                    (id: 'resting', label: 'At rest'),
                    (id: 'hovered', label: 'Hovered'),
                    (id: 'compact', label: 'Thumbnail off'),
                  ]) ...[
                    Text(
                      entry.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: interactivePaletteOf(context).textMuted,
                      ),
                    ),
                    _grid(
                      id: entry.id,
                      height: entry.id == 'compact' ? 44 : 76,
                      thumbnail: entry.id != 'compact',
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

class _UrlLauncher extends UrlLauncherPlatform {
  final urls = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    return true;
  }
}

// Only the image transport is replaced: Image.network, ResizeImage, decoding,
// its real image cache, and the production loading/error builders all run.
class _FaviconClient extends Fake implements HttpClient {
  _FaviconClient(this.bytes);

  Uint8List bytes;
  final urls = <Uri>[];
  int statusCode = HttpStatus.ok;
  Completer<void>? responseGate;

  void release() {
    final gate = responseGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    urls.add(url);
    return _FaviconRequest(this);
  }
}

class _FaviconRequest extends Fake implements HttpClientRequest {
  _FaviconRequest(this.client);

  final _FaviconClient client;
  @override
  final HttpHeaders headers = _FaviconHeaders();

  @override
  Future<HttpClientResponse> close() async {
    final gate = client.responseGate;
    if (gate != null) await gate.future;
    return _FaviconResponse(client.bytes, client.statusCode);
  }
}

class _FaviconResponse extends Fake implements HttpClientResponse {
  _FaviconResponse(Uint8List bytes, this.statusCode)
      : contentLength = bytes.length,
        _stream = Stream<List<int>>.value(bytes),
        headers = (_FaviconHeaders()
          ..add(HttpHeaders.contentTypeHeader, 'image/png')
          ..add(HttpHeaders.contentLengthHeader, bytes.length));

  final Stream<List<int>> _stream;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final HttpHeaders headers;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _stream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  Future<T> drain<T>([T? futureValue]) => _stream.drain<T>(futureValue);
}

class _FaviconHeaders extends Fake implements HttpHeaders {
  final _values = <String, List<String>>{};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values.putIfAbsent(name.toLowerCase(), () => []).add('$value');

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  String? value(String name) => this[name]?.join(',');
}
