import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_editor_scroll.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy_linux_webview/appflowy_linux_webview.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _headerHeight = 150.0;
const _bottomInset = 40.0;

/// Counts the layouts its child gets with new constraints.
class _LayoutCounter extends StatelessWidget {
  const _LayoutCounter({required this.onLayout, required this.child});

  final ValueChanged<BoxConstraints> onLayout;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          onLayout(constraints);
          return child;
        },
      );
}

void main() {
  testWidgets(
    'keeps its child at the header-retired height while the header scrolls',
    (tester) async {
      final layouts = <BoxConstraints>[];
      const child = Key('full-height-child');
      const body = Key('body');
      await tester.pumpWidget(
        MaterialApp(
          home: StandaloneFilePage(
            header: const SizedBox(height: _headerHeight),
            body: SizedBox.expand(
              key: body,
              child: StandaloneFileFullHeight(
                child: _LayoutCounter(
                  onLayout: layouts.add,
                  child: const SizedBox.expand(key: child),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewport = tester.getSize(find.byType(NestedScrollView)).height;
      expect(tester.getSize(find.byKey(body)).height, viewport - _headerHeight);
      expect(tester.getSize(find.byKey(child)).height, viewport);
      expect(tester.getTopLeft(find.byKey(child)).dy, _headerHeight);

      final outer = tester
          .state<NestedScrollViewState>(find.byType(NestedScrollView))
          .outerController;
      final settled = layouts.length;
      for (final offset in [20.0, 60.5, 149.0, _headerHeight, 70.0, 0.0]) {
        outer.jumpTo(offset);
        await tester.pump();
        expect(
          tester.getSize(find.byKey(body)).height,
          viewport - _headerHeight + offset,
        );
        expect(tester.getSize(find.byKey(child)).height, viewport);
        expect(tester.getTopLeft(find.byKey(child)).dy, _headerHeight - offset);
      }
      // The child moved with the page and was never laid out again.
      expect(layouts.length, settled);
    },
  );

  testWidgets('outside a whole-file page it fills its parent', (tester) async {
    const child = Key('full-height-child');
    await tester.pumpWidget(
      const Center(
        child: SizedBox(
          width: 200,
          height: 300,
          child: StandaloneFileFullHeight(
            child: SizedBox.expand(key: child),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(child)), const Size(200, 300));
  });

  testWidgets('takes input in the part below its own box', (tester) async {
    var taps = 0;
    const child = Key('full-height-child');
    await tester.pumpWidget(
      MaterialApp(
        home: StandaloneFilePage(
          header: const SizedBox(height: _headerHeight),
          body: Padding(
            padding: const EdgeInsets.only(bottom: _bottomInset),
            child: StandaloneFileFullHeight(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox.expand(key: child),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(NestedScrollView));
    // Within the viewport but below the box the page body gives it.
    final belowBox = Offset(viewport.center.dx, viewport.bottom - 10);
    expect(tester.getRect(find.byKey(child)).contains(belowBox), isTrue);
    await tester.tapAt(belowBox);
    expect(taps, 1);
  });

  group('with a pinned header', () {
    testWidgets('the body takes the rest of the page and nothing scrolls it',
        (tester) async {
      const header = Key('header');
      const child = Key('full-height-child');
      StandaloneFilePageScroll? adapter;
      await tester.pumpWidget(
        MaterialApp(
          home: StandaloneFilePage(
            pinHeader: true,
            header: const SizedBox(key: header, height: _headerHeight),
            body: Builder(
              builder: (context) {
                adapter = StandaloneFilePageScroll.maybeOf(context);
                return const StandaloneFileFullHeight(
                  child: SizedBox.expand(key: child),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final page = tester.getRect(find.byType(StandaloneFilePage));
      expect(find.byType(NestedScrollView), findsNothing);
      expect(adapter, isNull);
      expect(tester.getTopLeft(find.byKey(header)), page.topLeft);
      expect(
        tester.getRect(find.byKey(child)),
        Rect.fromLTRB(
          page.left,
          page.top + _headerHeight,
          page.right,
          page.bottom,
        ),
      );
    });

    testWidgets('an office editor gets every scroll, and the header stays',
        (tester) async {
      const header = Key('header');
      final routed = <Offset>[];
      final controller = OfficeEditorScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: PremiumScrollScope(
            enabled: true,
            child: StandaloneFilePage(
              pinHeader: true,
              header: const SizedBox(key: header, height: _headerHeight),
              body: PremiumScrollExclusion(
                child: OfficeEditorScroll(
                  controller: controller,
                  child: Builder(
                    builder: (context) => Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerSignal: (signal) {
                        if (signal is! PointerScrollEvent) return;
                        final scope = LinuxWebViewScrollScope.maybeOf(context)!;
                        GestureBinding.instance.pointerSignalResolver.register(
                          signal,
                          (_) => routed.add(scope.transform(signal)),
                        );
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final top = tester.getTopLeft(find.byKey(header));
      final point = tester.getRect(find.byType(OfficeEditorScroll)).center;
      Future<void> wheel(double dy) async {
        await tester.sendEventToBinding(
          PointerScrollEvent(position: point, scrollDelta: Offset(0, dy)),
        );
        await tester.pumpAndSettle();
      }

      // Down, then up past the document's top, as often as the hand goes.
      await wheel(120);
      controller.handleMessage([
        {'t': 'state', 'atTop': false},
      ]);
      for (var i = 0; i < 5; i++) {
        await wheel(-80);
      }
      controller.handleMessage([
        {'t': 'over', 'dy': -40.0},
      ]);
      await tester.pumpAndSettle();
      await wheel(-80);

      expect(routed, [
        const Offset(0, 120),
        for (var i = 0; i < 6; i++) const Offset(0, -80),
      ]);
      expect(tester.getTopLeft(find.byKey(header)), top);
      expect(tester.takeException(), isNull);
    });
  });
}
