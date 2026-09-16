import 'dart:async';

import 'package:appflowy/plugins/database/board/presentation/board_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:appflowy/shared/scrolling/trackpad_history_navigation.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
      '$appearance real editor supports swipes without changing vertical scroll',
      (tester) async {
        final editor = EditorState(
          document: Document(
            root: pageNode(
              children: [
                for (var i = 0; i < 100; i++)
                  paragraphNode(text: 'Paragraph $i'),
              ],
            ),
          ),
        );
        final scroll = EditorScrollController(editorState: editor);
        var back = 0;
        var forward = 0;
        try {
          await tester.pumpWidget(
            _app(
              appearance: appearance,
              back: () => back++,
              forward: () => forward++,
              child: AppFlowyEditor(
                editorState: editor,
                editorScrollController: scroll,
                blockComponentBuilders: {
                  ...standardBlockComponentBuilderMap,
                  PageBlockKeys.type: CustomPageBlockComponentBuilder(),
                },
                contextMenuItems: const [],
              ),
            ),
          );
          await tester.pumpAndSettle();
          await _swipe(tester, const [Offset(12, 0), Offset(144, 0)]);
          expect(back, 1);
          expect(scroll.offsetNotifier.value, 0);
          await _swipe(tester, const [Offset(-12, 0), Offset(-144, 0)]);
          expect(forward, 1);
          await _swipe(tester, const [Offset(0, -24), Offset(0, -160)]);
          expect(scroll.offsetNotifier.value, greaterThan(0));
          expect(back, 1);
          expect(forward, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          scroll.dispose();
          editor.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final kinetic in [false, true]) {
    testWidgets(
      'right goes Back, left Forward once on release: kinetic=$kinetic',
      (tester) async {
        var back = 0;
        var forward = 0;
        final scroll = ScrollController();
        await tester.pumpWidget(
          _app(
            kinetic: kinetic,
            back: () => back++,
            forward: () => forward++,
            child: SingleChildScrollView(
              controller: scroll,
              child: const SizedBox(height: 4000),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final pan =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        const point = Offset(300, 300);
        await pan.panZoomStart(point);
        for (var i = 1; i <= 12; i++) {
          await pan.panZoomUpdate(
            point,
            pan: Offset(12.0 * i, 1.0 * i),
            timeStamp: Duration(milliseconds: i * 16),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(back, 0);
        await pan.panZoomEnd();
        await tester.pumpAndSettle();
        expect(back, 1);
        expect(scroll.offset, 0);
        await _swipe(tester, const [Offset(-24, 0), Offset(-144, 0)]);
        expect(forward, 1);
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final motion in <List<Offset>>[
    [const Offset(24, 0), const Offset(80, 0)], // too short
    [const Offset(0, -24), const Offset(160, -28)], // vertical locked first
    [const Offset(20, -20), const Offset(160, -25)], // diagonal locked first
    [const Offset(24, 0), const Offset(160, 100)], // diagonal on release
    [const Offset(24, 0), const Offset(160, 0), const Offset(20, 0)], // undone
  ]) {
    testWidgets(
      'reject short, diagonal, vertical or undone swipe: $motion',
      (tester) async {
        var count = 0;
        await tester
            .pumpWidget(_app(back: () => count++, forward: () => count++));
        await _swipe(tester, motion);
        expect(count, 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'pinch, rotation, wheel and mouse drags are not history',
    (tester) async {
      var count = 0;
      await tester
          .pumpWidget(_app(back: () => count++, forward: () => count++));
      await _swipe(tester, const [Offset(24, 0), Offset(160, 0)], scale: 1.1);
      await _swipe(
        tester,
        const [Offset(24, 0), Offset(160, 0)],
        rotation: 0.2,
      );
      await tester.dragFrom(
        const Offset(200, 200),
        const Offset(160, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(300, 300),
          scrollDelta: Offset(160, 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(count, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'vertical scrolling remains functional and unchanged',
    (tester) async {
      final scroll = ScrollController();
      var count = 0;
      await tester.pumpWidget(
        _app(
          back: () => count++,
          child: SingleChildScrollView(
            controller: scroll,
            child: const SizedBox(height: 4000),
          ),
        ),
      );
      await _swipe(tester, const [Offset(0, -24), Offset(0, -160)]);
      expect(scroll.offset, greaterThan(0));
      expect(count, 0);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'horizontal scrollers retain swipes even at their edges',
    (tester) async {
      final scroll = ScrollController();
      var count = 0;
      await tester.pumpWidget(
        _app(
          back: () => count++,
          forward: () => count++,
          child: SingleChildScrollView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            child: const SizedBox(width: 4000),
          ),
        ),
      );
      await _swipe(tester, const [Offset(24, 0), Offset(160, 0)]);
      expect(count, 0);
      await _swipe(tester, const [Offset(-24, 0), Offset(-160, 0)]);
      expect(scroll.offset, greaterThan(0));
      expect(count, 0);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'custom viewers and explicit exclusions retain gesture ownership',
    (tester) async {
      var count = 0;
      var updates = 0;
      for (final premium in [false, true]) {
        final viewer = Listener(
          behavior: HitTestBehavior.opaque,
          onPointerPanZoomUpdate: (_) => updates++,
          child: const SizedBox.expand(),
        );
        await tester.pumpWidget(
          _app(
            back: () => count++,
            child: premium
                ? PremiumScrollExclusion(child: viewer)
                : HistorySwipeExclusion(child: viewer),
          ),
        );
        await _swipe(tester, const [Offset(24, 0), Offset(160, 0)]);
      }
      expect(count, 0);
      expect(updates, 4);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'navigation change and unavailable history invalidate gestures',
    (tester) async {
      var epoch = 0;
      var available = true;
      var count = 0;
      await tester.pumpWidget(
        _app(
          back: () => count++,
          token: () => epoch,
          canBack: () => available,
        ),
      );
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      const point = Offset(300, 300);
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(144, 0));
      epoch++;
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(count, 0);
      available = false;
      await _swipe(tester, const [Offset(24, 0), Offset(144, 0)]);
      expect(count, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'inactive embeds permit history, engaged embeds keep their pan',
    (tester) async {
      var navigation = 0;
      var innerUpdates = 0;
      for (final inactive in [true, false]) {
        await tester.pumpWidget(
          _app(
            back: () => navigation++,
            child: ScrollGestureGate(
              blocked: inactive,
              child: HistorySwipeExclusion(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerPanZoomUpdate: (_) => innerUpdates++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
        await _swipe(tester, const [Offset(24, 0), Offset(144, 0)]);
        expect(navigation, 1);
        expect(innerUpdates, inactive ? 0 : 2);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'opening a modal or unmounting cancels pending navigation',
    (tester) async {
      var navigation = 0;
      await tester.pumpWidget(_app(back: () => navigation++));
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      const point = Offset(300, 300);
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(144, 0));
      final context = tester.element(find.byType(TrackpadHistoryNavigation));
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Modal')),
        ),
      );
      await tester.pumpAndSettle();
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(navigation, 0);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point, pan: const Offset(144, 0));
      await tester.pumpWidget(const SizedBox());
      await pan.panZoomEnd();
      await tester.pumpAndSettle();
      expect(navigation, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'board local scroll behavior keeps slow horizontal swipes',
    (tester) async {
      final scroll = ScrollController();
      var navigation = 0;
      try {
        await tester.pumpWidget(
          _app(
            back: () => navigation++,
            forward: () => navigation++,
            child: ScrollConfiguration(
              behavior: const BoardScrollBehaviour(),
              child: SingleChildScrollView(
                controller: scroll,
                scrollDirection: Axis.horizontal,
                child: const SizedBox(width: 4000),
              ),
            ),
          ),
        );
        await _swipe(tester, const [Offset(12, 0), Offset(144, 0)]);
        expect(navigation, 0);
        await _swipe(tester, const [Offset(-12, 0), Offset(-144, 0)]);
        expect(navigation, 0);
        expect(scroll.offset, greaterThan(0));
      } finally {
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Widget _app({
  VoidCallback? back,
  VoidCallback? forward,
  bool Function()? canBack,
  Object Function()? token,
  bool kinetic = true,
  String appearance = 'light',
  Widget child = const SizedBox.expand(),
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
      home: PremiumScrollScope(
        enabled: kinetic,
        child: TrackpadHistoryNavigation(
          canGoBack: canBack ?? () => true,
          canGoForward: () => true,
          onBack: back ?? () {},
          onForward: forward ?? () {},
          navigationToken: token ?? () => 0,
          child: child,
        ),
      ),
    );

Future<void> _swipe(
  WidgetTester tester,
  List<Offset> values, {
  double scale = 1,
  double rotation = 0,
}) async {
  final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  const point = Offset(300, 300);
  await pan.panZoomStart(point);
  for (var i = 0; i < values.length; i++) {
    await pan.panZoomUpdate(
      point,
      pan: values[i],
      scale: scale,
      rotation: rotation,
      timeStamp: Duration(milliseconds: (i + 1) * 16),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await pan.panZoomEnd(
    timeStamp: Duration(milliseconds: values.length * 16 + 1),
  );
  await tester.pumpAndSettle();
}
