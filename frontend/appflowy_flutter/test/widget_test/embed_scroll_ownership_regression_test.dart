import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_scroll_physics.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/editor_embed_scroll_region.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show Node;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final document in [false, true]) {
    testWidgets(
      '${document ? 'document' : 'default card'} custom gestures require deliberate activation',
      (tester) async {
        final page = ScrollController();
        final focus = FocusNode();
        var wheels = 0;
        var pans = 0;
        final embedKey = GlobalKey();
        final node = Node(type: 'file');
        final content = Focus(
          focusNode: focus,
          // The Windows texture view also requests focus automatically.
          autofocus: document,
          child: Column(
            children: [
              const SizedBox(
                key: ValueKey('activate-embed'),
                width: double.infinity,
                height: 40,
                child: Text('Viewer controls'),
              ),
              Expanded(
                child: PremiumScrollExclusion(
                  child: PdfEmbedScrollGuard(
                    onPointerSignal: (_) => wheels++,
                    onPointerPanZoomUpdate: (_) => pans++,
                    child: SizedBox.expand(key: embedKey),
                  ),
                ),
              ),
            ],
          ),
        );
        try {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: Scaffold(
              body: PremiumScrollScope(
                enabled: true,
                child: SingleChildScrollView(
                  controller: page,
                  child: Column(children: [
                    SizedBox(
                      width: 500,
                      height: 320,
                      child: document
                          ? editorEmbedScrollRegion(node, content)
                          : ScrollActivationRegion(child: content),
                    ),
                    const SizedBox(height: 2000),
                  ]),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          if (document) expect(focus.hasFocus, isTrue);
          final element = embedKey.currentContext;
          final pointer = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await pointer.addPointer(location: Offset.zero);
          await pointer.moveTo(tester.getCenter(find.byKey(embedKey)));
          await tester.pump();
          await _wheel(tester, find.byKey(embedKey), 40);
          expect(wheels, 0, reason: 'Hover/autofocus is not a click.');
          expect(page.offset, greaterThan(0));
          page.jumpTo(0);
          await tester.pumpAndSettle();
          await _pan(tester, tester.getCenter(find.byKey(embedKey)));
          expect(pans, 0);
          expect(page.offset, greaterThan(0));
          page.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('activate-embed')),
              kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
          final before = page.offset;
          await _wheel(tester, find.byKey(embedKey), 40);
          expect(wheels, 1);
          expect(page.offset, before);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape,
              physicalKey: PhysicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          await _wheel(tester, find.byKey(embedKey), 40);
          expect(wheels, 1);
          expect(page.offset, greaterThan(before));
          expect(embedKey.currentContext, same(element));
          await pointer.removePointer();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          focus.dispose();
          page.dispose();
        }
      },
    );
  }

  testWidgets('Escape cancels the file adapter wheel without resetting content',
      (tester) async {
    final page = ScrollController();
    final body = ScrollController();
    try {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: PremiumScrollScope(
            enabled: true,
            child: SingleChildScrollView(
              controller: page,
              child: Column(children: [
                SizedBox(
                  width: 500,
                  height: 320,
                  child: ScrollActivationRegion(
                    child: StandaloneFilePage(
                      header: const SizedBox(
                        key: ValueKey('file-activation'),
                        height: 60,
                        child: Text('File identity'),
                      ),
                      body: StandaloneFileScrollRegion(
                        controller: body,
                        child: ListView.builder(
                          key: const ValueKey('file-body'),
                          controller: body,
                          itemCount: 100,
                          itemExtent: 32,
                          itemBuilder: (_, i) => Text('Content $i'),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2000),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('file-activation')),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final nested = tester.state<NestedScrollViewState>(
        find.byType(NestedScrollView),
      );
      final target = find.byKey(const ValueKey('file-body'));
      await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(target),
        scrollDelta: const Offset(0, 120),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final retained = nested.outerController.offset + body.offset;
      expect(retained, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(nested.outerController.offset + body.offset, retained,
          reason: 'Closing the gate must cancel its renderer-owned ticker.');
      await _wheel(tester, target, 40);
      expect(page.offset, greaterThan(0));
      expect(nested.outerController.offset + body.offset, retained);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      body.dispose();
      page.dispose();
    }
  });
}

Future<void> _wheel(WidgetTester tester, Finder target, double delta) async {
  await tester.sendEventToBinding(PointerScrollEvent(
    position: tester.getCenter(target),
    scrollDelta: Offset(0, delta),
  ));
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
}

Future<void> _pan(WidgetTester tester, Offset position) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  await gesture.panZoomStart(position);
  for (var i = 1; i <= 3; i++) {
    await gesture.panZoomUpdate(position,
        pan: Offset(0, -20.0 * i), timeStamp: Duration(milliseconds: i * 10));
  }
  await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}
