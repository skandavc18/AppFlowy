import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_scroll_physics.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/trackpad_history_navigation.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/widget/history_swipe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'incoming viewer initializes at its final position during handoff',
      (tester) async {
    final controller = HistorySwipeController();
    final page = ValueNotifier('a');
    final firstPositions = <Offset>[];
    await tester.pumpWidget(
      _app(
        child: ValueListenableBuilder(
          valueListenable: page,
          builder: (_, value, __) => HistorySwipeSurface(
            controller: controller,
            pageKey: value,
            child: _InitialPositionProbe(
              key: ValueKey(value),
              onPosition: firstPositions.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    firstPositions.clear();
    controller.begin(forward: true, available: true);
    controller.update(160);
    unawaited(
      controller.finish(
        commit: true,
        isValid: () => true,
        navigate: () {
          page.value = 'b';
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(firstPositions, [Offset.zero]);
    expect(controller.isActive, isFalse);
    await tester.pumpWidget(const SizedBox());
    page.dispose();
    controller.dispose();
  });

  testWidgets(
    'HTML reading guard shows both history boundaries without stealing pan',
    (tester) async {
      final deltas = <Offset>[];
      var starts = 0;
      var ends = 0;
      var navigations = 0;
      await tester.pumpWidget(
        _app(
          child: TrackpadHistoryNavigation(
            canGoBack: () => false,
            canGoForward: () => false,
            onBack: () => navigations++,
            onForward: () => navigations++,
            navigationToken: () => 0,
            child: HistorySwipeBoundaryFeedback(
              child: PremiumScrollExclusion(
                child: PdfEmbedScrollGuard(
                  onPointerSignal: (_) {},
                  onPointerPanZoomStart: (_) => starts++,
                  onPointerPanZoomUpdate: (event) =>
                      deltas.add(event.localPanDelta),
                  onPointerPanZoomEnd: (_) => ends++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      const point = Offset(300, 300);
      for (final direction in [1.0, -1.0]) {
        deltas.clear();
        await pan.panZoomStart(point);
        for (final distance in [24.0, 120.0, 300.0]) {
          await pan.panZoomUpdate(point, pan: Offset(direction * distance, 0));
          await tester.pump();
          expect(_sheetX(tester) * direction, inExclusiveRange(0, 64));
          expect(
            find.text(direction > 0 ? 'No previous page' : 'No next page'),
            findsOneWidget,
          );
        }
        expect(
          deltas,
          [
            Offset(direction * 24, 0),
            Offset(direction * 96, 0),
            Offset(direction * 180, 0),
          ],
        );
        await pan.panZoomEnd();
        await tester.pumpAndSettle();
        expect(_sheetX(tester), 0);
      }
      expect(starts, 2);
      expect(ends, 2);
      expect(navigations, 0);
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'reading feedback never navigates or replaces vertical, pinch or available-history pan',
    (tester) async {
      var available = false;
      var navigations = 0;
      var updates = 0;
      await tester.pumpWidget(
        _app(
          child: TrackpadHistoryNavigation(
            canGoBack: () => available,
            canGoForward: () => available,
            onBack: () => navigations++,
            onForward: () => navigations++,
            navigationToken: () => 0,
            child: HistorySwipeBoundaryFeedback(
              child: PremiumScrollExclusion(
                child: PdfEmbedScrollGuard(
                  onPointerSignal: (_) {},
                  onPointerPanZoomUpdate: (_) => updates++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      const point = Offset(300, 300);
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(0, -24));
      await pan.panZoomUpdate(point, pan: const Offset(160, -28));
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(_sheetX(tester), 0);
      expect(find.text('No previous page'), findsNothing);
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(160, 0), scale: 1.1);
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(_sheetX(tester), 0);
      expect(find.text('No previous page'), findsNothing);
      available = true;
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(160, 0));
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(_sheetX(tester), 0);
      expect(find.text('Back'), findsNothing);
      expect(navigations, 0);
      expect(updates, 4);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'sidebar swipes animate the page pane, not the sidebar',
    (tester) async {
      const sidebarKey = ValueKey('stationary-sidebar');
      final scroll = ScrollController();
      await tester.pumpWidget(
        _app(
          child: TrackpadHistoryNavigation(
            animateChild: false,
            canGoBack: () => false,
            canGoForward: () => false,
            onBack: () => fail('No previous page'),
            onForward: () => fail('No next page'),
            navigationToken: () => 0,
            child: Row(
              children: [
                SizedBox(
                  key: sidebarKey,
                  width: 200,
                  child: SingleChildScrollView(
                    controller: scroll,
                    child: const SizedBox(height: 2400),
                  ),
                ),
                const Expanded(
                  child: HistorySwipePageSurface(child: SizedBox.expand()),
                ),
              ],
            ),
          ),
        ),
      );
      final before = tester.getRect(find.byKey(sidebarKey));
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      const point = Offset(100, 300);
      for (final direction in [1.0, -1.0]) {
        await pan.panZoomStart(point);
        await pan.panZoomUpdate(point, pan: Offset(direction * 160, 0));
        await tester.pump();
        expect(_sheetX(tester) * direction, inExclusiveRange(0, 64));
        expect(tester.getRect(find.byKey(sidebarKey)), before);
        expect(scroll.offset, 0);
        await pan.panZoomEnd();
        await tester.pumpAndSettle();
      }
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(0, -24));
      await pan.panZoomUpdate(point, pan: const Offset(0, -100));
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(_sheetX(tester), 0);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
      '$appearance: both history edges give resisted, readable feedback',
      (tester) async {
        var navigations = 0;
        await tester.pumpWidget(
          _app(
            appearance: appearance,
            child: TrackpadHistoryNavigation(
              canGoBack: () => false,
              canGoForward: () => false,
              onBack: () => navigations++,
              onForward: () => navigations++,
              navigationToken: () => 0,
              child: const SizedBox.expand(),
            ),
          ),
        );
        final semantics = tester.ensureSemantics();
        for (final direction in [1.0, -1.0]) {
          final pan =
              await tester.createGesture(kind: PointerDeviceKind.trackpad);
          const point = Offset(300, 300);
          await pan.panZoomStart(point);
          await pan.panZoomUpdate(point, pan: Offset(direction * 180, 0));
          await tester.pump();
          expect(_sheetX(tester) * direction, inExclusiveRange(0, 64));
          final label = direction > 0 ? 'No previous page' : 'No next page';
          expect(find.text(label), findsOneWidget);
          expect(find.bySemanticsLabel(label), findsOneWidget);
          final cue = tester.widget<Material>(
            find
                .ancestor(of: find.text(label), matching: find.byType(Material))
                .first,
          );
          expect(cue.color, _surface(appearance));
          await pan.panZoomEnd();
          await tester.pumpAndSettle();
          expect(_sheetX(tester), 0);
          expect(find.text(label), findsOneWidget);
          expect(navigations, 0);
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.text(label), findsNothing);
        }
        semantics.dispose();
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'the live page follows fingers and returns without rebuilding its editor',
    (tester) async {
      var builds = 0;
      var navigations = 0;
      final text = TextEditingController(text: 'Keep my unsaved text');
      await tester.pumpWidget(
        _app(
          child: TrackpadHistoryNavigation(
            canGoBack: () => true,
            canGoForward: () => true,
            onBack: () => navigations++,
            onForward: () => navigations++,
            navigationToken: () => 0,
            child: Builder(
              builder: (_) {
                builds++;
                return Material(child: TextField(controller: text));
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editor = tester.state(find.byType(EditableText));
      final before = builds;
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      const point = Offset(300, 300);
      await pan.panZoomStart(point);
      for (final distance in [24.0, 80.0, 160.0, 20.0]) {
        await pan.panZoomUpdate(point, pan: Offset(distance, 0));
        await tester.pump();
        expect(_sheetX(tester), closeTo(distance, .01));
        expect(navigations, 0);
        expect(builds, before);
      }
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(_sheetX(tester), 0);
      expect(navigations, 0);
      expect(tester.state(find.byType(EditableText)), same(editor));
      expect(text.text, 'Keep my unsaved text');
      await tester.pumpWidget(const SizedBox());
      text.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a new swipe replaces an existing boundary cue',
    (tester) async {
      var back = 0;
      await tester.pumpWidget(
        _app(
          child: TrackpadHistoryNavigation(
            canGoBack: () => true,
            canGoForward: () => false,
            onBack: () => back++,
            onForward: () {},
            navigationToken: () => 0,
            child: const SizedBox.expand(),
          ),
        ),
      );
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      const point = Offset(300, 300);
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(-160, 0));
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(find.text('No next page'), findsOneWidget);
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(160, 0));
      await tester.pump();
      expect(find.text('Back'), findsOneWidget);
      expect(_sheetX(tester), 160);
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(back, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'reduced motion keeps boundary feedback and navigation, without translation',
    (tester) async {
      var available = false;
      var back = 0;
      await tester.pumpWidget(
        _app(
          reducedMotion: true,
          child: TrackpadHistoryNavigation(
            canGoBack: () => available,
            canGoForward: () => false,
            onBack: () => back++,
            onForward: () {},
            navigationToken: () => 0,
            child: const SizedBox.expand(),
          ),
        ),
      );
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      const point = Offset(300, 300);
      for (final hasPrevious in [false, true]) {
        available = hasPrevious;
        await pan.panZoomStart(point);
        await pan.panZoomUpdate(point, pan: const Offset(160, 0));
        await tester.pump();
        expect(_sheetX(tester), 0);
        expect(
          find.text(hasPrevious ? 'Back' : 'No previous page'),
          findsOneWidget,
        );
        await pan.panZoomEnd();
        await tester.pumpAndSettle();
      }
      expect(back, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'focus/lifecycle interruption clears a held gesture and permits the next',
    (tester) async {
      var back = 0;
      await tester.pumpWidget(
        _app(
          child: TrackpadHistoryNavigation(
            canGoBack: () => true,
            canGoForward: () => false,
            onBack: () => back++,
            onForward: () {},
            navigationToken: () => 0,
            child: const SizedBox.expand(),
          ),
        ),
      );
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      const point = Offset(300, 300);
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(160, 0));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(_sheetX(tester), 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(back, 0);
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(160, 0));
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(back, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
      'preview handoff waits for navigation and keeps one live destination',
      (tester) async {
    final controller = HistorySwipeController();
    final page = ValueNotifier('a');
    await tester.pumpWidget(
      _app(
        child: ValueListenableBuilder(
          valueListenable: page,
          builder: (_, value, __) => HistorySwipeSurface(
            controller: controller,
            pageKey: value,
            child: ColoredBox(
              color: Colors.blue,
              child: Center(child: Text('Page $value')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    page.value = 'b';
    await tester.pumpAndSettle();
    expect(controller.previews.length, 1);
    controller.begin(forward: false, available: true, target: 'a');
    controller.update(140);
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.text('Page b'), findsOneWidget);
    expect(find.text('Page a'), findsNothing);
    unawaited(
      controller.finish(
        commit: true,
        isValid: () => true,
        navigate: () {
          page.value = 'a';
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(page.value, 'b');
    await tester.pumpAndSettle();
    expect(page.value, 'a');
    expect(controller.isActive, isFalse);
    expect(find.text('Page a'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    page.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace and privacy changes erase previews and active sheets',
      (tester) async {
    final controller = HistorySwipeController();
    var scope = 0;
    var allowed = true;
    late StateSetter refresh;
    await tester.pumpWidget(
      _app(
        child: StatefulBuilder(
          builder: (_, setState) {
            refresh = setState;
            return HistorySwipeSurface(
              controller: controller,
              pageKey: 'a',
              scope: scope,
              allowPreviews: allowed,
              child: const ColoredBox(
                color: Colors.blue,
                child: SizedBox.expand(),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.captureCurrent();
    expect(controller.previews.length, 1);
    controller.begin(forward: false, available: true, target: 'a');
    controller.update(100);
    refresh(() => scope++);
    await tester.pumpAndSettle();
    expect(controller.previews.length, 0);
    expect(controller.isActive, isFalse);
    controller.captureCurrent();
    expect(controller.previews.length, 1);
    refresh(() => allowed = false);
    await tester.pumpAndSettle();
    controller.captureCurrent();
    expect(controller.previews.length, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('preview privacy crosses a nested app/overlay boundary',
      (tester) async {
    final controller = HistorySwipeController();
    final allowed = ValueNotifier(true);
    await tester.pumpWidget(
      _app(
        child: ValueListenableBuilder(
          valueListenable: allowed,
          builder: (_, value, __) => HistorySwipeTheme(
            surface: _surface('paper'),
            allowPreviews: value,
            child: MaterialApp(
              home: HistorySwipeSurface(
                controller: controller,
                pageKey: 'bookmark',
                child: const ColoredBox(
                  color: Colors.blue,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.captureCurrent();
    expect(controller.previews.length, 1);
    controller.begin(forward: false, available: true, target: 'bookmark');
    controller.update(100);
    allowed.value = false;
    await tester.pumpAndSettle();
    expect(controller.isActive, isFalse);
    expect(controller.previews.length, 0);
    controller.captureCurrent();
    expect(controller.previews.length, 0);
    await tester.pumpWidget(const SizedBox());
    allowed.dispose();
    controller.dispose();
  });

  testWidgets('native history updates never relabel new pixels as the old page',
      (tester) async {
    final controller = HistorySwipeController();
    final page = ValueNotifier('a');
    await tester.pumpWidget(
      _app(
        child: ValueListenableBuilder(
          valueListenable: page,
          builder: (_, value, __) => HistorySwipeSurface(
            controller: controller,
            pageKey: value,
            captureOnPageChange: false,
            child: ColoredBox(
              color: value == 'a' ? Colors.red : Colors.blue,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.captureCurrent();
    final previous = controller.previews.read('a')!;
    page.value = 'b';
    await tester.pumpAndSettle();
    final retained = controller.previews.read('a')!;
    expect(retained.isCloneOf(previous), isTrue);
    retained.dispose();
    previous.dispose();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    page.dispose();
  });

  test(
      'preview cache bounds bytes and preserves active image handles on eviction',
      () {
    ui.Image image() {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(Colors.blue, ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(16, 16);
      picture.dispose();
      return image;
    }

    final cache = HistorySwipePreviewCache(capacity: 2, maxBytes: 2048);
    cache.store('a', image());
    final active = cache.read('a')!;
    cache.store('b', image());
    cache.store('c', image());
    expect(cache.length, 2);
    expect(cache.bytes, 2048);
    expect(cache.read('a'), isNull);
    expect(active.debugDisposed, isFalse);
    cache.clear();
    expect(cache.bytes, 0);
    active.dispose();
  });
}

double _sheetX(WidgetTester tester) => tester
    .widget<Transform>(
      find.byKey(const ValueKey('history-swipe-sheet')),
    )
    .transform
    .getTranslation()
    .x;

class _InitialPositionProbe extends StatefulWidget {
  const _InitialPositionProbe({super.key, required this.onPosition});
  final ValueChanged<Offset> onPosition;

  @override
  State<_InitialPositionProbe> createState() => _InitialPositionProbeState();
}

class _InitialPositionProbeState extends State<_InitialPositionProbe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onPosition(
          (context.findRenderObject()! as RenderBox).localToGlobal(Offset.zero),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

ThemeData _theme(String appearance) => DesktopAppearance().getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

Color _surface(String appearance) => EditorSurfaceStyle.canvasBackgroundFor(
      _theme(appearance).brightness,
      _theme(appearance).colorScheme.surface,
      isPaper: appearance == 'paper',
    );

Widget _app({
  required Widget child,
  String appearance = 'light',
  bool reducedMotion = false,
}) =>
    MaterialApp(
      theme: _theme(appearance),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: HistorySwipeTheme(surface: _surface(appearance), child: child),
      ),
    );
