import 'dart:math' as math;

import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:appflowy/shared/maps/map_tile_layer.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:appflowy/shared/scrolling/trackpad_history_navigation.dart';
import 'package:appflowy/shared/slides/slide_card.dart';
import 'package:appflowy/shared/slides/slide_deck.dart';
import 'package:appflowy/shared/slides/slide_geometry.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/widget/history_swipe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _surfaceSize = Size(600, 420);
const _outside = Offset(20, 40);
const _layout = SlideDeckLayout(viewport: _surfaceSize);

void main() {
  for (final appearance in ['light', 'dark', 'paper']) {
    for (final kinetic in [false, true]) {
      testWidgets(
        '$appearance kinetic=$kinetic: Slide owns swipes and commits only once',
        (tester) async {
          final page = ScrollController();
          final deck = SlideDeckController();
          final changes = <int>[];
          var navigation = 0;
          try {
            await tester.pumpWidget(
              _app(
                page: page,
                appearance: appearance,
                kinetic: kinetic,
                onNavigate: () => navigation++,
                child: _deck(deck, changes: changes),
              ),
            );
            await tester.pumpAndSettle();
            final point = tester.getCenter(find.byType(SlideDeck));
            final first = find.byKey(const ValueKey('row-0'));
            final before = tester.getTopLeft(first);
            final pan =
                await tester.createGesture(kind: PointerDeviceKind.trackpad);
            await pan.panZoomStart(point);
            await pan.panZoomUpdate(
              point,
              pan: const Offset(-12, 0),
              timeStamp: const Duration(milliseconds: 16),
            );
            await tester.pump(const Duration(milliseconds: 16));
            await pan.panZoomUpdate(
              point,
              pan: Offset(-_layout.step * 0.65, 0),
              timeStamp: const Duration(milliseconds: 32),
            );
            await tester.pump(const Duration(milliseconds: 16));

            expect(tester.getTopLeft(first).dx, lessThan(before.dx));
            expect(_history(tester).isActive, isFalse);
            expect(page.offset, 0);
            expect(changes, isEmpty);
            final held = tester.getTopLeft(first);
            // Neither a wheel timer nor a host index echo may snap a gesture
            // that is still held, even past the normal animation duration.
            await tester.pump(const Duration(milliseconds: 500));
            expect(tester.getTopLeft(first), held);
            expect(changes, isEmpty);

            await pan.panZoomEnd(
              timeStamp: const Duration(milliseconds: 550),
            );
            expect(changes, isEmpty);
            await tester.pumpAndSettle();
            expect(deck.index, 1);
            expect(changes, [1]);
            expect(navigation, 0);

            await _pan(
              tester,
              point,
              [const Offset(12, 0), Offset(_layout.step * 0.65, 0)],
            );
            expect(deck.index, 0);
            expect(changes, [1, 0]);

            // Plain wheel on the deck background still advances slides, but
            // not the outer page, and reports just the final settled index.
            final background =
                tester.getTopLeft(find.byType(SlideDeck)) + const Offset(8, 8);
            await _wheel(tester, background, const Offset(0, 240));
            await tester.pump(const Duration(milliseconds: 100));
            expect(changes, [1, 0]);
            await tester.pump(const Duration(milliseconds: 50));
            await tester.pumpAndSettle();
            expect(deck.index, 1);
            expect(changes, [1, 0, 1]);
            expect(page.offset, 0);

            await _wheel(tester, _outside, const Offset(0, 120));
            await tester.pumpAndSettle();
            expect(page.offset, closeTo(120, 0.11));
            expect(changes, [1, 0, 1]);
            expect(navigation, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            deck.dispose();
            page.dispose();
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );

      testWidgets(
        '$appearance kinetic=$kinetic: Map owns pan, wheel and anchored pinch',
        (tester) async {
          final page = ScrollController();
          final map = AppMapController();
          final changes = <MapViewport>[];
          var navigation = 0;
          try {
            await tester.pumpWidget(
              _app(
                page: page,
                appearance: appearance,
                kinetic: kinetic,
                onNavigate: () => navigation++,
                child: _map(map, onChanged: changes.add),
              ),
            );
            await tester.pumpAndSettle();
            final rect = tester.getRect(find.byType(AppMapView));
            const local = Offset(155, 140);
            final point = rect.topLeft + local;
            final initial = map.camera!;
            final pan =
                await tester.createGesture(kind: PointerDeviceKind.trackpad);
            await pan.panZoomStart(point);
            await pan.panZoomUpdate(
              point,
              pan: const Offset(12, 0),
              timeStamp: const Duration(milliseconds: 16),
            );
            await tester.pump(const Duration(milliseconds: 16));
            _expectOffset(
              map.camera!.toScreen(initial.center),
              _surfaceSize.center(Offset.zero) + const Offset(12, 0),
            );
            expect(_history(tester).isActive, isFalse);
            await pan.panZoomUpdate(
              point,
              pan: const Offset(-60, -80),
              timeStamp: const Duration(milliseconds: 32),
            );
            await tester.pump(const Duration(milliseconds: 16));
            _expectOffset(
              map.camera!.toScreen(initial.center),
              _surfaceSize.center(Offset.zero) + const Offset(-60, -80),
            );
            expect(changes, isEmpty);
            expect(page.offset, 0);
            await pan.panZoomEnd();
            await tester.pumpAndSettle();
            expect(changes, hasLength(1));

            final beforeWheel = map.camera!;
            final wheelAnchor = beforeWheel.toLatLng(local);
            await _wheel(tester, point, const Offset(0, -120));
            await tester.pumpAndSettle();
            expect(map.camera!.zoom, closeTo(beforeWheel.zoom + 0.42, 1e-9));
            _expectOffset(map.camera!.toScreen(wheelAnchor), local);
            expect(changes, hasLength(2));
            expect(page.offset, 0);

            final beforePinch = map.camera!;
            final anchor = beforePinch.toLatLng(local);
            final pinch =
                await tester.createGesture(kind: PointerDeviceKind.trackpad);
            await pinch.panZoomStart(point);
            for (var i = 1; i <= 3; i++) {
              await pinch.panZoomUpdate(
                point,
                pan: Offset(40.0 * i, -25.0 * i),
                scale: 1 + i / 6,
                timeStamp: Duration(milliseconds: i * 16),
              );
              await tester.pump(const Duration(milliseconds: 16));
              _expectOffset(map.camera!.toScreen(anchor), local);
              expect(_history(tester).isActive, isFalse);
              expect(page.offset, 0);
            }
            expect(
              map.camera!.zoom,
              closeTo(beforePinch.zoom + math.log(1.5) / math.ln2, 1e-9),
            );
            expect(changes, hasLength(2));
            await pinch.panZoomEnd();
            await tester.pumpAndSettle();
            expect(changes, hasLength(3));

            await _wheel(tester, _outside, const Offset(0, 120));
            await tester.pumpAndSettle();
            expect(page.offset, closeTo(120, 0.11));
            expect(changes, hasLength(3));
            expect(navigation, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            map.dispose();
            page.dispose();
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }

  for (final scale in [1.0, 0.75]) {
    testWidgets(
      'Slide trackpad displacement ignores viewport translation at scale=$scale',
      (tester) async {
        final page = ScrollController();
        final deck = SlideDeckController();
        final changes = <int>[];
        var navigation = 0;
        try {
          await tester.pumpWidget(
            _app(
              page: page,
              onNavigate: () => navigation++,
              child: Transform.translate(
                offset: const Offset(40, 30),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: _deck(deck, changes: changes),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final point = tester.getCenter(find.byType(SlideDeck));
          final first = find.byKey(const ValueKey('row-0'));
          final before = tester.getCenter(first);
          final pan =
              await tester.createGesture(kind: PointerDeviceKind.trackpad);
          await pan.panZoomStart(point);
          await pan.panZoomUpdate(point, pan: Offset(-8 * scale, 0));
          await tester.pump();
          _expectOffset(tester.getCenter(first), before);

          await pan.panZoomUpdate(point, pan: Offset(-24 * scale, 0));
          await tester.pump();
          _expectOffset(
            tester.getCenter(first),
            before + Offset(-24 * scale, 0),
          );
          final travel = Offset(-_layout.step * 0.65 * scale, 0);
          await pan.panZoomUpdate(point, pan: travel);
          await tester.pump();
          _expectOffset(tester.getCenter(first), before + travel);

          // A stationary total must not be accumulated for a second time.
          await pan.panZoomUpdate(point, pan: travel);
          await tester.pump(const Duration(milliseconds: 500));
          _expectOffset(tester.getCenter(first), before + travel);
          expect(changes, isEmpty);
          expect(page.offset, 0);
          expect(_history(tester).isActive, isFalse);
          await pan.panZoomEnd();
          expect(changes, isEmpty);
          await tester.pumpAndSettle();
          expect(deck.index, 1);
          expect(changes, [1]);
          expect(navigation, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          deck.dispose();
          page.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final isMap in [false, true]) {
    testWidgets(
      '${isMap ? 'Map' : 'Slide'} ownership follows the start, not later hover',
      (tester) async {
        final page = ScrollController();
        final deck = SlideDeckController();
        final map = AppMapController();
        var navigation = 0;
        try {
          await tester.pumpWidget(
            _app(
              page: page,
              onNavigate: () => navigation++,
              child: isMap ? _map(map) : _deck(deck),
            ),
          );
          await tester.pumpAndSettle();
          final surface = find.byType(isMap ? AppMapView : SlideDeck);
          final inside = tester.getCenter(surface);
          final initialCamera = map.camera;
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: inside);
          await tester.pumpAndSettle();

          final outsidePan =
              await tester.createGesture(kind: PointerDeviceKind.trackpad);
          await outsidePan.panZoomStart(_outside);
          // The pointer was hovering inside previously and moves inside again
          // now; neither can make the surface join a gesture started outside.
          await outsidePan.panZoomUpdate(inside, pan: const Offset(144, 0));
          await tester.pump();
          expect(_history(tester).isActive, isTrue);
          expect(deck.index, 0);
          expect(map.camera?.center, initialCamera?.center);
          await outsidePan.panZoomEnd();
          await tester.pumpAndSettle();
          expect(navigation, 1);

          final insidePan =
              await tester.createGesture(kind: PointerDeviceKind.trackpad);
          await insidePan.panZoomStart(inside);
          await insidePan.panZoomUpdate(inside, pan: const Offset(-12, 0));
          await tester.pump();
          await insidePan.panZoomUpdate(
            _outside,
            pan: Offset(-_layout.step * 0.7, 0),
          );
          await tester.pump();
          expect(_history(tester).isActive, isFalse);
          expect(page.offset, 0);
          await insidePan.panZoomEnd();
          await tester.pumpAndSettle();
          expect(navigation, 1);
          if (isMap) {
            expect(map.camera!.center, isNot(initialCamera!.center));
          } else {
            expect(deck.index, 1);
          }
          await mouse.removePointer();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          deck.dispose();
          map.dispose();
          page.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      '${isMap ? 'Map' : 'Slide'} respects an inactive embed gate without remounting',
      (tester) async {
        final page = ScrollController();
        final deck = SlideDeckController();
        final map = AppMapController();
        final blocked = ValueNotifier(true);
        var navigation = 0;
        try {
          await tester.pumpWidget(
            _app(
              page: page,
              onNavigate: () => navigation++,
              child: ValueListenableBuilder<bool>(
                valueListenable: blocked,
                builder: (_, value, child) => ScrollGestureGate(
                  blocked: value,
                  child: child!,
                ),
                child: isMap ? _map(map) : _deck(deck),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final surface = find.byType(isMap ? AppMapView : SlideDeck);
          final element = tester.element(surface);
          final inside = tester.getCenter(surface);
          final initialCamera = map.camera;
          await _pan(
            tester,
            inside,
            const [Offset(0, -24), Offset(0, -110)],
          );
          expect(page.offset, greaterThan(0));
          expect(deck.index, 0);
          expect(map.camera?.center, initialCamera?.center);
          page.jumpTo(0);
          await tester.pump();

          // Changing activation mid-gesture cannot switch from history to the
          // newly enabled surface: the start hit-test is still authoritative.
          final pan =
              await tester.createGesture(kind: PointerDeviceKind.trackpad);
          await pan.panZoomStart(inside);
          await pan.panZoomUpdate(inside, pan: const Offset(24, 0));
          await tester.pump();
          blocked.value = false;
          await tester.pump();
          await pan.panZoomUpdate(inside, pan: const Offset(144, 0));
          await pan.panZoomEnd();
          await tester.pumpAndSettle();
          expect(navigation, 1);
          expect(tester.element(surface), same(element));
          expect(deck.index, 0);
          expect(map.camera?.center, initialCamera?.center);

          await _pan(
            tester,
            inside,
            [const Offset(-12, 0), Offset(-_layout.step * 0.7, 0)],
          );
          expect(page.offset, 0);
          expect(navigation, 1);
          if (isMap) {
            expect(map.camera!.center, isNot(initialCamera!.center));
          } else {
            expect(deck.index, 1);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          blocked.dispose();
          deck.dispose();
          map.dispose();
          page.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'Slide properties keep vertical scrolling, including wheel at their boundary',
    (tester) async {
      final page = ScrollController();
      final deck = SlideDeckController();
      final changes = <int>[];
      var navigation = 0;
      try {
        await tester.pumpWidget(
          _app(
            page: page,
            onNavigate: () => navigation++,
            child: _deck(deck, changes: changes, properties: true),
          ),
        );
        await tester.pumpAndSettle();
        final live = find.byWidgetPredicate(
          (widget) => widget is SlideCard && widget.live,
        );
        final scroller = find.descendant(
          of: live,
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scroller).position;
        final point = tester.getCenter(scroller);
        expect(position.maxScrollExtent, greaterThan(120));
        await _wheel(tester, point, const Offset(0, 120));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(120, 0.11));
        expect(deck.index, 0);
        expect(changes, isEmpty);
        expect(page.offset, 0);

        await _pan(
          tester,
          point,
          const [Offset(8, -24), Offset(28, -110), Offset(90, -170)],
        );
        expect(position.pixels, greaterThan(120));
        expect(deck.index, 0);
        expect(changes, isEmpty);
        expect(page.offset, 0);

        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        await _wheel(tester, point, const Offset(0, 360));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(deck.index, 0);
        expect(changes, isEmpty);
        expect(page.offset, 0);

        await _pan(
          tester,
          point,
          [const Offset(-12, 0), Offset(-_layout.step * 0.65, 0)],
        );
        expect(deck.index, 1);
        expect(changes, [1]);
        expect(navigation, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        deck.dispose();
        page.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'Map search suggestions own trackpad and wheel without moving the camera',
    (tester) async {
      final page = ScrollController();
      final map = AppMapController();
      try {
        await tester.pumpWidget(
          _app(
            page: page,
            child: AppMapView(
              controller: map,
              initialCenter: const LatLng(20, 10),
              initialZoom: 4,
              autoFit: false,
              showControls: false,
              showPopup: false,
              showSearch: true,
              onSearch: (_) async => null,
              onSuggestPins: (_) => [
                for (var i = 0; i < 12; i++)
                  MapSuggestion(
                    title: 'Local place $i',
                    point: const LatLng(20, 10),
                    pinId: '$i',
                  ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final initial = map.camera!;
        await tester.enterText(find.byType(TextField), 'local places');
        await tester.pump();
        final scroller = find.descendant(
          of: find.byType(MapSuggestionList),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scroller).position;
        final point = tester.getCenter(scroller);
        await _wheel(tester, point, const Offset(0, 80));
        await tester.pump();
        expect(position.pixels, greaterThan(0));
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        await _wheel(tester, point, const Offset(0, 120));
        await tester.pump();
        expect(map.camera!.zoom, initial.zoom);
        expect(map.camera!.center, initial.center);
        expect(page.offset, 0);

        position.jumpTo(0);
        await tester.pump();
        final pan =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await pan.panZoomStart(point);
        await pan.panZoomUpdate(
          point,
          pan: const Offset(0, -24),
          timeStamp: const Duration(milliseconds: 16),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await pan.panZoomUpdate(
          point,
          pan: const Offset(0, -90),
          timeStamp: const Duration(milliseconds: 32),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await pan.panZoomUpdate(
          point,
          pan: const Offset(0, -90),
          timeStamp: const Duration(milliseconds: 200),
        );
        await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 201));
        expect(position.pixels, greaterThan(0));
        expect(map.camera!.center, initial.center);
        expect(map.camera!.zoom, initial.zoom);
        expect(page.offset, 0);
        expect(_history(tester).isActive, isFalse);
        // Local suggestions are synchronous. Clear before the 320ms lookup
        // debounce fires: this test never needs a geocoder or live data.
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        map.dispose();
        page.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a map inside a Slide owns its wheel, vertical pan and horizontal pan',
    (tester) async {
      final page = ScrollController();
      final deck = SlideDeckController();
      final changes = <int>[];
      var navigation = 0;
      try {
        await tester.pumpWidget(
          _app(
            page: page,
            onNavigate: () => navigation++,
            child: _deck(deck, changes: changes, location: true),
          ),
        );
        await tester.pumpAndSettle();
        final point = tester.getCenter(find.byType(AppMapView));
        final initial = _paintedMapCamera(tester);
        await _wheel(tester, point, const Offset(0, -240));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(
          _paintedMapCamera(tester).zoom,
          closeTo(initial.zoom + 0.84, 1e-9),
        );
        expect(deck.index, 0);
        expect(changes, isEmpty);
        expect(page.offset, 0);

        for (final delta in const [Offset(0, -90), Offset(-240, 0)]) {
          final before = _paintedMapCamera(tester);
          await _pan(tester, point, [delta / 10, delta]);
          final after = _paintedMapCamera(tester);
          _expectOffset(
            after.toScreen(before.center),
            before.size.center(Offset.zero) + delta,
          );
          expect(deck.index, 0);
          expect(changes, isEmpty);
          expect(page.offset, 0);
          expect(navigation, 0);
          expect(_history(tester).isActive, isFalse);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        deck.dispose();
        page.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'short, undone, pinch and rotation gestures do not change slides',
    (tester) async {
      final page = ScrollController();
      final deck = SlideDeckController();
      final changes = <int>[];
      try {
        await tester.pumpWidget(
          _app(page: page, child: _deck(deck, changes: changes)),
        );
        await tester.pumpAndSettle();
        final point = tester.getCenter(find.byType(SlideDeck));
        await _pan(tester, point, const [Offset(-8, 0)]);
        await _pan(
          tester,
          point,
          [Offset(-_layout.step * 0.7, 0), const Offset(-20, 0)],
        );
        for (final rotate in [false, true]) {
          final pan =
              await tester.createGesture(kind: PointerDeviceKind.trackpad);
          await pan.panZoomStart(point);
          await pan.panZoomUpdate(point, pan: const Offset(-24, 0));
          await tester.pump();
          await pan.panZoomUpdate(
            point,
            pan: Offset(-_layout.step * 0.8, 0),
            scale: rotate ? 1 : 1.2,
            rotation: rotate ? 0.2 : 0,
          );
          await pan.panZoomEnd();
          await tester.pumpAndSettle();
          expect(deck.index, 0);
          expect(changes, isEmpty);
          expect(_history(tester).isActive, isFalse);
        }
        expect(page.offset, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        deck.dispose();
        page.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a vertically locked Slide background gesture remains page scrolling',
    (tester) async {
      final page = ScrollController();
      final deck = SlideDeckController();
      final changes = <int>[];
      try {
        await tester.pumpWidget(
          _app(page: page, child: _deck(deck, changes: changes)),
        );
        await tester.pumpAndSettle();
        final point =
            tester.getTopLeft(find.byType(SlideDeck)) + const Offset(8, 8);
        await _pan(
          tester,
          point,
          const [Offset(6, -24), Offset(160, -120)],
        );
        expect(page.offset, greaterThan(0));
        expect(deck.index, 0);
        expect(changes, isEmpty);
        expect(_history(tester).isActive, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        deck.dispose();
        page.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      '$kind flick past halfway settles on the next slide, not two slides',
      (tester) async {
        final page = ScrollController();
        final deck = SlideDeckController();
        final changes = <int>[];
        try {
          await tester.pumpWidget(
            _app(page: page, child: _deck(deck, changes: changes)),
          );
          await tester.pumpAndSettle();
          final drag = await tester.startGesture(
            tester.getCenter(find.byType(SlideDeck)),
            kind: kind,
          );
          await drag.moveBy(
            const Offset(-24, 0),
            timeStamp: const Duration(milliseconds: 16),
          );
          await tester.pump(const Duration(milliseconds: 16));
          for (var i = 2; i <= 4; i++) {
            await drag.moveBy(
              Offset(-_layout.step * 0.22, 0),
              timeStamp: Duration(milliseconds: i * 16),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(changes, isEmpty);
          await drag.up(timeStamp: const Duration(milliseconds: 65));
          await tester.pumpAndSettle();
          expect(deck.index, 1);
          expect(changes, [1]);
          expect(page.offset, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          deck.dispose();
          page.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final flow in SlideFlow.values) {
    testWidgets(
      '$flow boundaries and wrapping never hand the swipe to history',
      (tester) async {
        final page = ScrollController();
        final deck = SlideDeckController();
        var navigation = 0;
        try {
          for (final wrap in [false, true]) {
            await tester.pumpWidget(
              _app(
                page: page,
                onNavigate: () => navigation++,
                child: _deck(deck, flow: flow, wrap: wrap),
              ),
            );
            await tester.pumpAndSettle();
            deck.goTo(0, animate: false);
            await tester.pump();
            final point = tester.getCenter(find.byType(SlideDeck));
            final layout = SlideDeckLayout(viewport: _surfaceSize, flow: flow);
            await _pan(
              tester,
              point,
              [const Offset(12, 0), Offset(layout.step * 0.75, 0)],
            );
            expect(deck.index, wrap ? 4 : 0);
            deck.goTo(4, animate: false);
            await tester.pump();
            await _pan(
              tester,
              point,
              [const Offset(-12, 0), Offset(-layout.step * 0.75, 0)],
            );
            expect(deck.index, wrap ? 0 : 4);
            expect(navigation, 0);
            expect(page.offset, 0);
            expect(_history(tester).isActive, isFalse);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          deck.dispose();
          page.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'a trackpad takeover cancels wheel settling until the gesture ends',
    (tester) async {
      final page = ScrollController();
      final deck = SlideDeckController();
      final changes = <int>[];
      try {
        await tester.pumpWidget(
          _app(page: page, child: _deck(deck, changes: changes)),
        );
        await tester.pumpAndSettle();
        final point =
            tester.getTopLeft(find.byType(SlideDeck)) + const Offset(8, 8);
        await _wheel(tester, point, const Offset(0, 120));
        final pan =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await pan.panZoomStart(point);
        await pan.panZoomUpdate(point, pan: const Offset(-12, 0));
        await pan.panZoomUpdate(point, pan: Offset(-_layout.step * 0.4, 0));
        await tester.pump(const Duration(milliseconds: 600));
        expect(changes, isEmpty);
        expect(_history(tester).isActive, isFalse);
        await pan.panZoomEnd();
        await tester.pumpAndSettle();
        expect(deck.index, 1);
        expect(changes, [1]);
        expect(page.offset, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        deck.dispose();
        page.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a late host index update cannot animate over an owned Slide gesture',
    (tester) async {
      final page = ScrollController();
      final deck = SlideDeckController();
      final requested = ValueNotifier(0);
      final changes = <int>[];
      try {
        await tester.pumpWidget(
          _app(
            page: page,
            child: ValueListenableBuilder<int>(
              valueListenable: requested,
              builder: (_, index, __) => _deck(
                deck,
                index: index,
                changes: changes,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final point = tester.getCenter(find.byType(SlideDeck));
        final pan =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await pan.panZoomStart(point);
        await pan.panZoomUpdate(point, pan: Offset(-_layout.step * 0.65, 0));
        await tester.pump();
        final first = find.byKey(const ValueKey('row-0'));
        final held = tester.getTopLeft(first);
        requested.value = 3;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.getTopLeft(first), held);
        expect(changes, isEmpty);
        await pan.panZoomEnd();
        await tester.pumpAndSettle();
        expect(deck.index, 1);
        expect(changes, [1]);

        // The host remains authoritative for a new request made while idle.
        requested.value = 4;
        await tester.pump();
        await tester.pumpAndSettle();
        expect(deck.index, 4);
        expect(changes, [1, 4]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        requested.dispose();
        deck.dispose();
        page.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'reduced motion commits the released Slide immediately without animation',
    (tester) async {
      final page = ScrollController();
      final deck = SlideDeckController();
      final changes = <int>[];
      try {
        await tester.pumpWidget(
          _app(
            page: page,
            reducedMotion: true,
            child: _deck(deck, changes: changes),
          ),
        );
        await tester.pumpAndSettle();
        final point = tester.getCenter(find.byType(SlideDeck));
        final pan =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await pan.panZoomStart(point);
        await pan.panZoomUpdate(point, pan: Offset(-_layout.step * 0.7, 0));
        await tester.pump();
        expect(changes, isEmpty);
        await pan.panZoomEnd();
        expect(changes, [1]);
        await tester.pumpAndSettle();
        expect(changes, [1]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        deck.dispose();
        page.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'unused and actively swiped decks dispose without starting animations',
    (tester) async {
      for (final active in [false, true]) {
        final page = ScrollController();
        final deck = SlideDeckController();
        final changes = <int>[];
        try {
          await tester.pumpWidget(
            _app(page: page, child: _deck(deck, changes: changes)),
          );
          await tester.pumpAndSettle();
          TestGesture? pan;
          if (active) {
            pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
            final point = tester.getCenter(find.byType(SlideDeck));
            await pan.panZoomStart(point);
            await pan.panZoomUpdate(point, pan: const Offset(-40, 0));
            await tester.pump();
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await pan?.panZoomEnd();
          await tester.pumpAndSettle();
          expect(changes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          deck.dispose();
          page.dispose();
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Widget _deck(
  SlideDeckController controller, {
  List<int>? changes,
  int index = 0,
  bool properties = false,
  bool location = false,
  SlideFlow flow = SlideFlow.deck,
  bool wrap = false,
}) =>
    Builder(
      builder: (context) => SlideDeck(
        controller: controller,
        index: index,
        palette: slidePaletteOf(context),
        flow: flow,
        wrap: wrap,
        onIndexChanged: changes?.add,
        cards: [
          for (var row = 0; row < 5; row++)
            SlideCardData(
              rowId: 'row-$row',
              title: 'Slide $row',
              properties: [
                if (location)
                  const SlideProperty(
                    fieldId: 'place',
                    name: 'Place',
                    value: '20, 10',
                    kind: SlidePropertyKind.location,
                  ),
                if (properties)
                  for (var i = 0; i < 24; i++)
                    SlideProperty(
                      fieldId: 'field-$i',
                      name: 'Property $i',
                      value: 'Value $i',
                      kind: SlidePropertyKind.text,
                    ),
              ],
            ),
        ],
      ),
    );

Widget _map(
  AppMapController controller, {
  ValueChanged<MapViewport>? onChanged,
}) =>
    AppMapView(
      controller: controller,
      initialCenter: const LatLng(20, 10),
      initialZoom: 4,
      autoFit: false,
      showControls: false,
      showPopup: false,
      onViewportChanged: onChanged,
    );

Widget _app({
  required ScrollController page,
  required Widget child,
  String appearance = 'light',
  bool kinetic = true,
  bool reducedMotion = false,
  VoidCallback? onNavigate,
}) =>
    MaterialApp(
      theme: DesktopAppearance().getThemeData(
        appearance == 'paper'
            ? AppTheme.builtins
                .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        appearance == 'dark' ? Brightness.dark : Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
          ),
          child: PremiumScrollScope(
            enabled: kinetic,
            child: TrackpadHistoryNavigation(
              canGoBack: () => true,
              canGoForward: () => true,
              onBack: onNavigate ?? () {},
              onForward: onNavigate ?? () {},
              navigationToken: () => 0,
              allowPreviews: false,
              child: Scaffold(
                body: SingleChildScrollView(
                  controller: page,
                  child: Column(
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: SizedBox.fromSize(
                          size: _surfaceSize,
                          child: child,
                        ),
                      ),
                      const SizedBox(height: 1800),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

HistorySwipeController _history(WidgetTester tester) => tester
    .widget<HistorySwipeSurface>(find.byType(HistorySwipeSurface))
    .controller;

MapCamera _paintedMapCamera(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(AppMapView),
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is MapTilePainter,
      ),
    ),
  );
  return (paint.painter! as MapTilePainter).camera;
}

void _expectOffset(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 0.01));
  expect(actual.dy, closeTo(expected.dy, 0.01));
}

Future<void> _wheel(WidgetTester tester, Offset point, Offset delta) =>
    tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: delta),
    );

Future<void> _pan(
  WidgetTester tester,
  Offset point,
  List<Offset> values,
) async {
  final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  await pan.panZoomStart(point);
  for (var i = 0; i < values.length; i++) {
    await pan.panZoomUpdate(
      point,
      pan: values[i],
      timeStamp: Duration(milliseconds: (i + 1) * 16),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  // A stationary tail avoids platform-dependent outer/inner scroll flings.
  await pan.panZoomUpdate(
    point,
    pan: values.last,
    timeStamp: const Duration(milliseconds: 200),
  );
  await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 201));
  await tester.pumpAndSettle();
}
