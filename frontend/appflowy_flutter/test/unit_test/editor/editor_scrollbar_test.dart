import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/editor_page_scrollbar.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('display-only scrollbar metrics', () {
    test('extent estimates preserve position and thumb length', () {
      final projection = EditorScrollbarMetrics();
      projection.project(_metrics(0));
      final before = projection.project(_metrics(300));
      final after = projection.project(_metrics(300, max: 1800));
      expect(after.pixels, before.pixels);
      expect(after.maxScrollExtent, before.maxScrollExtent);
      expect(
        projection.project(_metrics(320, max: 1800)).pixels,
        greaterThan(after.pixels),
      );
      expect(
        projection.project(_metrics(280, max: 1800)).pixels,
        lessThan(after.pixels),
      );
      for (final pixels in [0.0, 100.0, 300.0, 700.0, 1790.0, 1800.0]) {
        final projected = projection.project(_metrics(pixels, max: 1800));
        expect(
          projection.scrollPixelsFor(projected.pixels),
          closeTo(pixels, 0.001),
        );
      }
    });

    test('content growth restores a previously absent scrollbar', () {
      final projection = EditorScrollbarMetrics();
      projection.project(_metrics(0, max: 0));
      final grown = projection.project(_metrics(100, max: 200));
      expect(grown.maxScrollExtent, 200);
      expect(grown.pixels, 100);
    });

    test('growing beyond either endpoint does not pin the thumb', () {
      for (final atEnd in [false, true]) {
        final projection = EditorScrollbarMetrics();
        final pixels = atEnd ? 1000.0 : 0.0;
        projection.project(_metrics(pixels));
        final result = projection.project(
          _metrics(pixels, min: atEnd ? 0 : -1000, max: atEnd ? 2000 : 1000),
        );
        expect(result.pixels, greaterThan(0));
        expect(result.extentAfter, greaterThan(0));
        expect(
          projection.scrollPixelsFor(result.pixels),
          closeTo(pixels, 0.001),
        );
      }
    });

    test('negative anchors and viewport resizes use the full range', () {
      final projection = EditorScrollbarMetrics();
      final result = projection.project(_metrics(0, min: -1000));
      expect(result.pixels, 1000);
      expect(projection.scrollPixelsFor(1000), 0);
      final resized = projection.project(
        _metrics(0, min: -1000, max: 2000, viewport: 800),
      );
      expect(resized.pixels, 1000);
      expect(resized.maxScrollExtent, 3000);
    });
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
      '$appearance page scrollbar stays aligned during a forward pan',
      (tester) async {
        final editor = EditorState(
          document: Document(
            root: pageNode(
              children: [
                for (var i = 0; i < 180; i++)
                  Node(
                    type: 'sized_paragraph',
                    attributes: {'height': i >= 40 && i < 80 ? 320.0 : 40.0},
                  ),
              ],
            ),
          ),
        );
        final controller = EditorScrollController(editorState: editor);
        final theme = _theme(appearance);
        final pan =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.copyWith(
                scrollbarTheme: theme.scrollbarTheme.copyWith(
                  thumbVisibility: const WidgetStatePropertyAll(true),
                ),
              ),
              home: PremiumScrollScope(
                enabled: true,
                child: Scaffold(
                  body: AppFlowyEditor(
                    editorState: editor,
                    editorScrollController: controller,
                    blockComponentBuilders: {
                      ...standardBlockComponentBuilderMap,
                      PageBlockKeys.type: CustomPageBlockComponentBuilder(),
                      'sized_paragraph': _SizedParagraphBuilder(),
                    },
                    contextMenuItems: const [],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(EditorPageScrollbar), findsOneWidget);
          final scrollable =
              tester.state<ScrollableState>(find.byType(Scrollable));
          final scrollbar = tester.state<RawScrollbarState>(
            find.byWidgetPredicate((widget) => widget is RawScrollbar),
          );
          // Inspect the painter rather than infer its position from page motion.
          // ignore: invalid_use_of_protected_member
          final painter = scrollbar.scrollbarPainter;
          var previous = painter.getThumbScrollOffset();
          final backwards = <String>[];
          const point = Offset(300, 300);
          await pan.panZoomStart(point);
          for (var i = 1; i <= 240; i++) {
            await pan.panZoomUpdate(
              point,
              pan: Offset(0, -20.0 * i),
              timeStamp: Duration(milliseconds: i * 16),
            );
            await tester.pump(const Duration(milliseconds: 16));
            final current = painter.getThumbScrollOffset();
            if (current < previous - 0.1) {
              backwards.add(
                'frame $i: $previous -> $current; '
                'pixels ${scrollable.position.pixels}, '
                'max ${scrollable.position.maxScrollExtent}',
              );
            }
            expect(painter.thickness, 4);
            expect(painter.crossAxisMargin, 0);
            previous = current;
          }
          await pan.panZoomEnd();
          await tester.pumpAndSettle();
          expect(backwards, isEmpty);

          // Index jumps rebase at pixels=0, including a jump from pixels=0
          // itself. The scrollbar must use the new negative minimum.
          for (final index in [0, 90, 10, 179]) {
            controller.itemScrollController.jumpTo(index: index);
            await tester.pumpAndSettle();
            final currentScroll =
                tester.state<ScrollableState>(find.byType(Scrollable));
            final currentBar = tester
                .state<RawScrollbarState>(find.byType(EditorPageScrollbar));
            // ignore: invalid_use_of_protected_member
            final currentPainter = currentBar.scrollbarPainter;
            final metrics = currentScroll.position;
            if (index == 0) {
              expect(
                _paintedThumb(
                  currentPainter,
                  tester.getSize(find.byType(EditorPageScrollbar)),
                ).top,
                closeTo(currentPainter.mainAxisMargin, 0.001),
              );
            } else {
              expect(
                _paintedThumb(
                  currentPainter,
                  tester.getSize(find.byType(EditorPageScrollbar)),
                ).top,
                greaterThan(currentPainter.mainAxisMargin),
                reason: 'index $index: min=${metrics.minScrollExtent}, '
                    'pixels=${metrics.pixels}, max=${metrics.maxScrollExtent}; '
                    'same bar=${identical(currentBar, scrollbar)}',
              );
              expect(metrics.minScrollExtent, lessThan(0));
            }
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          editor.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  for (final reverse in [false, true]) {
    testWidgets(
      'mouse thumb drag is exact and cancellable: reverse=$reverse',
      (tester) async {
        final controller = ScrollController(initialScrollOffset: 400);
        final theme = _theme('paper');
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.copyWith(
                scrollbarTheme: theme.scrollbarTheme.copyWith(
                  thumbVisibility: const WidgetStatePropertyAll(true),
                ),
              ),
              home: PremiumScrollScope(
                enabled: true,
                child: Builder(
                  builder: (context) => ScrollConfiguration(
                    behavior: EditorPageScrollBehavior(
                      ScrollConfiguration.of(context),
                    ),
                    child: SingleChildScrollView(
                      controller: controller,
                      reverse: reverse,
                      child: const SizedBox(height: 4000),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scrollbar = tester.state<RawScrollbarState>(
            find.byType(EditorPageScrollbar),
          );
          // ignore: invalid_use_of_protected_member
          final painter = scrollbar.scrollbarPainter;
          final size = tester.getSize(find.byType(EditorPageScrollbar));
          final y = [
            for (var y = 0.0; y < size.height; y++)
              if (painter.hitTestOnlyThumbInteractive(
                Offset(size.width - 2, y),
                PointerDeviceKind.mouse,
              ))
                y,
          ];
          final start = Offset(size.width - 2, (y.first + y.last) / 2);
          final drag = await tester.startGesture(
            start,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          final expectedDelta = painter.getTrackToScroll(40);
          await drag.moveTo(start + Offset(0, reverse ? -40 : 40));
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(controller.offset, closeTo(400 + expectedDelta, 0.01));
          expect(controller.position.isScrollingNotifier.value, isTrue);

          // Waiting outside while held must not invalidate the mapping.
          await drag.moveTo(start + Offset(30, reverse ? -45 : 45));
          await tester.pump(const Duration(seconds: 2));
          await drag.moveTo(start + Offset(0, reverse ? -50 : 50));
          await tester.pump();
          expect(tester.takeException(), isNull);
          await drag.cancel();
          await tester.pumpAndSettle();
          expect(controller.position.isScrollingNotifier.value, isFalse);

          // Navigation cancels a thumb drag; later packets cannot move it.
          controller.jumpTo(400);
          await tester.pumpAndSettle();
          final cancelled = await tester.startGesture(
            start,
            kind: PointerDeviceKind.mouse,
          );
          await cancelled.moveTo(start + Offset(0, reverse ? -10 : 10));
          await tester.pump();
          controller.jumpTo(600);
          await tester.pump();
          await cancelled.moveTo(start + Offset(0, reverse ? -30 : 30));
          await tester.pump();
          expect(controller.offset, 600);
          await cancelled.up();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

ScrollMetrics _metrics(
  double pixels, {
  double min = 0,
  double max = 1000,
  double viewport = 600,
}) =>
    FixedScrollMetrics(
      minScrollExtent: min,
      maxScrollExtent: max,
      pixels: pixels,
      viewportDimension: viewport,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

ThemeData _theme(String appearance) => DesktopAppearance().getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

Rect _paintedThumb(ScrollbarPainter painter, Size size) {
  final canvas = _ThumbCanvas();
  painter.paint(canvas, size);
  return canvas.thumb!;
}

class _ThumbCanvas implements Canvas {
  Rect? thumb;

  @override
  void drawRRect(RRect rect, Paint paint) => thumb = rect.outerRect;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SizedParagraphBuilder extends BlockComponentBuilder {
  @override
  BlockComponentWidget build(BlockComponentContext context) =>
      _SizedParagraph(node: context.node);
}

class _SizedParagraph extends BlockComponentStatelessWidget {
  const _SizedParagraph({required super.node})
      : super(configuration: const BlockComponentConfiguration());

  @override
  Widget build(BuildContext context) => SizedBox(
        height: node.attributes['height'] as double,
        child: const Text('Paragraph'),
      );
}
