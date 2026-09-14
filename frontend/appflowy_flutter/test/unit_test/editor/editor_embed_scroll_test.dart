import 'package:appflowy/plugins/document/presentation/editor_plugins/file/csv_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_scroll_physics.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final shrinkWrap in [false, true]) {
    testWidgets(
      'mixed page coast is identical over embeds and margins: shrinkWrap=$shrinkWrap',
      (tester) async {
        tester.view.display.refreshRate = 120;
        addTearDown(tester.view.display.resetRefreshRate);
        final semantics = tester.ensureSemantics();
        final nodes = [
          for (var index = 0; index < 12; index++) ...[
            Node(type: 'file', attributes: {'index': index}),
            paragraphNode(text: 'Text between preview frames $index'),
          ],
        ];
        final editor =
            EditorState(document: Document(root: pageNode(children: nodes)));
        final page =
            EditorScrollController(editorState: editor, shrinkWrap: shrinkWrap);
        final keys = List.generate(12, (_) => GlobalKey());
        var innerInput = 0;
        final csv =
            List.generate(100, (row) => '$row,first,second,third').join('\n');
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: PremiumScrollScope(
                enabled: true,
                child: FlowyOverlay(
                  child: Scaffold(
                    body: AppFlowyEditor(
                      editorState: editor,
                      editorScrollController: page,
                      editorStyle: const EditorStyle.desktop(
                        padding: EdgeInsets.symmetric(horizontal: 80),
                      ),
                      blockComponentBuilders: {
                        ...standardBlockComponentBuilderMap,
                        PageBlockKeys.type: CustomPageBlockComponentBuilder(),
                        'file': _MixedEmbedBuilder(
                          keys: keys,
                          csv: csv,
                          onInnerInput: () => innerInput++,
                        ),
                      },
                      contextMenuItems: const [],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pumpAndSettle();
          final position = Scrollable.of(keys.first.currentContext!).position;
          final viewport = tester.getRect(find.byType(AppFlowyEditor));
          final embedPoint = tester.getCenter(find.byKey(keys.first));
          final marginPoint = Offset(viewport.left + 12, embedPoint.dy);
          List<double>? baseline;
          for (final point in [embedPoint, marginPoint]) {
            position.jumpTo(0);
            await tester.pumpAndSettle();
            final trace = await _coastTrace(tester, position, point);
            expect(trace.last, greaterThan(600));
            if (baseline != null) {
              expect(trace.length, baseline.length);
              for (var frame = 0; frame < trace.length; frame++) {
                expect(trace[frame], closeTo(baseline[frame], 0.1));
              }
            }
            baseline = trace;
            expect(innerInput, 0);
          }

          // A cached/rendered embed at the page boundary must not trap the
          // spring return or change the inactive preview's scroll ownership.
          position.jumpTo(0);
          await tester.pumpAndSettle();
          final edgePoint = tester.getCenter(find.byKey(keys.first));
          await tester.sendEventToBinding(
            PointerPanZoomStartEvent(
                pointer: 83, device: 83, position: edgePoint),
          );
          for (var step = 1; step <= 5; step++) {
            await tester.sendEventToBinding(
              PointerPanZoomUpdateEvent(
                pointer: 83,
                device: 83,
                position: edgePoint,
                pan: Offset(0, 24.0 * step),
                panDelta: const Offset(0, 24),
                timeStamp: Duration(milliseconds: step * 8),
              ),
            );
            await tester.pump(const Duration(milliseconds: 8));
          }
          expect(position.pixels, lessThan(position.minScrollExtent));
          await tester.sendEventToBinding(
            PointerPanZoomEndEvent(
              pointer: 83,
              device: 83,
              position: edgePoint,
              timeStamp: const Duration(milliseconds: 41),
            ),
          );
          await tester.pumpAndSettle(const Duration(milliseconds: 8));
          expect(position.pixels, closeTo(position.minScrollExtent, 0.01));
          expect(innerInput, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          page.dispose();
          editor.dispose();
          semantics.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    for (final customViewer in [false, true]) {
      for (final kinetic in [false, true]) {
        testWidgets(
          'page owns inactive embed: shrinkWrap=$shrinkWrap '
          'custom=$customViewer kinetic=$kinetic',
          (tester) async {
            final semantics = tester.ensureSemantics();
            final editor = EditorState(
              document: Document(
                root: pageNode(
                  children: [
                    Node(type: 'file'),
                    for (var i = 0; i < 100; i++)
                      paragraphNode(text: 'Paragraph $i'),
                  ],
                ),
              ),
            );
            final page = EditorScrollController(
              editorState: editor,
              shrinkWrap: shrinkWrap,
            );
            final inner = ScrollController();
            final viewerKey = GlobalKey();
            var customScrolls = 0;
            try {
              Widget body = ListView.builder(
                controller: inner,
                itemCount: 100,
                itemExtent: 32,
                itemBuilder: (_, i) => Text('Embedded row $i'),
              );
              if (customViewer) {
                body = PremiumScrollExclusion(
                  child: PdfEmbedScrollGuard(
                    onPointerSignal: (_) => customScrolls++,
                    onPointerPanZoomUpdate: (_) => customScrolls++,
                    child: body,
                  ),
                );
              }
              final viewer = SizedBox(
                key: viewerKey,
                width: 500,
                height: 300,
                child: Column(
                  children: [
                    const SizedBox(
                      key: ValueKey('embed-header'),
                      height: 42,
                      width: double.infinity,
                      child: Text('Click to use the viewer'),
                    ),
                    Expanded(child: body),
                  ],
                ),
              );
              await tester.pumpWidget(
                MaterialApp(
                  home: PremiumScrollScope(
                    enabled: kinetic,
                    child: FlowyOverlay(
                      child: Scaffold(
                        body: Column(
                          children: [
                            const SizedBox(
                              key: ValueKey('outside-embed'),
                              height: 48,
                              width: double.infinity,
                              child: Text('Page toolbar'),
                            ),
                            Expanded(
                              child: AppFlowyEditor(
                                editorState: editor,
                                editorScrollController: page,
                                blockComponentBuilders: {
                                  ...standardBlockComponentBuilderMap,
                                  PageBlockKeys.type:
                                      CustomPageBlockComponentBuilder(),
                                  'file': _EmbedBuilder(viewer),
                                },
                                contextMenuItems: const [],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final original = viewerKey.currentContext;
              final pagePosition = Scrollable.of(original!).position;
              Offset target() => tester.getCenter(find.byKey(viewerKey));
              double offset() => pagePosition.pixels;

              await _pan(tester, target());
              expect(offset(), greaterThan(0));
              expect(inner.offset, 0);
              expect(customScrolls, 0);

              pagePosition.jumpTo(0);
              await tester.pumpAndSettle();
              await tester.tapAt(
                tester.getCenter(find.byKey(const ValueKey('embed-header'))),
              );
              await tester.pumpAndSettle();
              final selectedPageOffset = offset();
              await _pan(tester, target());
              expect(offset(), closeTo(selectedPageOffset, 0.01));
              expect(
                customViewer ? customScrolls : inner.offset,
                greaterThan(0),
              );
              expect(viewerKey.currentContext, same(original));

              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
              final retainedInner = inner.offset;
              final retainedCustom = customScrolls;
              await _pan(tester, target());
              expect(offset(), greaterThan(selectedPageOffset));
              expect(inner.offset, retainedInner);
              expect(customScrolls, retainedCustom);

              pagePosition.jumpTo(0);
              await tester.pumpAndSettle();
              await tester.tapAt(
                tester.getCenter(find.byKey(const ValueKey('embed-header'))),
              );
              await tester.pumpAndSettle();
              await tester.tapAt(
                tester.getCenter(find.byKey(const ValueKey('outside-embed'))),
              );
              await tester.pumpAndSettle();
              final outsidePageOffset = offset();
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  position: target(),
                  scrollDelta: const Offset(0, 40),
                ),
              );
              await tester.pumpAndSettle();
              expect(offset(), greaterThan(outsidePageOffset));
              expect(inner.offset, retainedInner);
              expect(customScrolls, retainedCustom);
              expect(viewerKey.currentContext, same(original));
              expect(tester.takeException(), isNull);
            } finally {
              await tester.pumpWidget(const SizedBox.shrink());
              page.dispose();
              editor.dispose();
              inner.dispose();
              semantics.dispose();
            }
          },
          variant: TargetPlatformVariant.only(TargetPlatform.windows),
        );
      }
    }
  }
}

class _EmbedBuilder extends BlockComponentBuilder {
  _EmbedBuilder(this.child);
  final Widget child;

  @override
  BlockComponentWidget build(BlockComponentContext context) =>
      _Embed(node: context.node, child: child);
}

class _MixedEmbedBuilder extends BlockComponentBuilder {
  _MixedEmbedBuilder(
      {required this.keys, required this.csv, required this.onInnerInput});

  final List<GlobalKey> keys;
  final String csv;
  final VoidCallback onInnerInput;

  @override
  BlockComponentWidget build(BlockComponentContext context) => _Embed(
        node: context.node,
        child: ResizableMedia(
          key: keys[context.node.attributes['index'] as int],
          width: 480,
          height: 220,
          editable: false,
          onResize: (_) {},
          child: PremiumScrollExclusion(
            child: PdfEmbedScrollGuard(
              onPointerSignal: (_) => onInnerInput(),
              onPointerPanZoomUpdate: (_) => onInnerInput(),
              child: CsvPreview(text: csv, separator: ','),
            ),
          ),
        ),
      );
}

class _Embed extends BlockComponentStatelessWidget {
  const _Embed({required super.node, required this.child})
      : super(configuration: const BlockComponentConfiguration());
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

Future<List<double>> _coastTrace(
  WidgetTester tester,
  ScrollPosition position,
  Offset point,
) async {
  const interval = Duration(microseconds: 16666);
  const frameInterval = Duration(microseconds: 8333);
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(pointer: 82, device: 82, position: point),
  );
  for (var step = 1; step <= 12; step++) {
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 82,
        device: 82,
        position: point,
        pan: Offset(0, -40.0 * step),
        panDelta: const Offset(0, -40),
        timeStamp: interval * step,
      ),
    );
    await tester.pump(frameInterval);
    final halfway = position.pixels;
    await tester.pump(frameInterval);
    if (step > 1) expect(position.pixels, greaterThan(halfway));
  }
  expect(position.pixels, closeTo(480 * 0.60, 0.01));
  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      pointer: 82,
      device: 82,
      position: point,
      timeStamp: interval * 12 + const Duration(milliseconds: 1),
    ),
  );
  await tester.pump();
  var previous = position.pixels;
  var previousDelta = double.infinity;
  final trace = <double>[];
  for (var frame = 0; frame < 160; frame++) {
    await tester.pump(frameInterval);
    final delta = position.pixels - previous;
    expect(delta, greaterThanOrEqualTo(-0.01));
    expect(delta, lessThanOrEqualTo(previousDelta + 0.05));
    previous = position.pixels;
    previousDelta = delta;
    trace.add(previous);
  }
  await tester.pumpAndSettle(interval);
  expect(position.isScrollingNotifier.value, isFalse);
  return trace;
}

Future<void> _pan(WidgetTester tester, Offset position) async {
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(
      pointer: 81,
      device: 81,
      position: position,
    ),
  );
  for (var step = 1; step <= 3; step++) {
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 81,
        device: 81,
        position: position,
        pan: Offset(0, -20.0 * step),
        panDelta: const Offset(0, -20),
        timeStamp: Duration(milliseconds: step * 10),
      ),
    );
  }
  await tester.sendEventToBinding(
    PointerPanZoomUpdateEvent(
      pointer: 81,
      device: 81,
      position: position,
      pan: const Offset(0, -60),
      timeStamp: const Duration(milliseconds: 200),
    ),
  );
  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      pointer: 81,
      device: 81,
      position: position,
      timeStamp: const Duration(milliseconds: 201),
    ),
  );
  await tester.pumpAndSettle();
}
