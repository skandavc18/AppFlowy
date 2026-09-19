import 'package:appflowy/plugins/database/widgets/row/row_detail_scroll_surface.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _actions = ValueKey('row-actions');
const _coverHeight = 250.0;

void main() {
  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets(
        '$mode: wheel frames move content and actions without rebuilding',
        (tester) async {
      final scroll = ScrollController();
      var builds = 0;
      var actionBuilds = 0;
      var presses = 0;
      try {
        await tester.pumpWidget(
          _app(
            mode,
            RowDetailScrollSurface(
              coverHeight: _coverHeight,
              actions: Builder(
                builder: (_) {
                  actionBuilds++;
                  return SizedBox(
                    key: _actions,
                    width: 48,
                    height: 24,
                    child: TextButton(
                      onPressed: () => presses++,
                      child: const Text('Open'),
                    ),
                  );
                },
              ),
              child: Builder(
                builder: (_) {
                  builds++;
                  return SingleChildScrollView(
                    controller: scroll,
                    child: const SizedBox(height: 3000),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final baseline = builds;
        final actionBaseline = actionBuilds;
        final top = tester.getTopLeft(find.byType(RowDetailScrollSurface)).dy;
        expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 262);
        const point = Offset(250, 200);
        await tester.sendEventToBinding(
          const PointerScrollEvent(
            position: point,
            scrollDelta: Offset(0, 120),
          ),
        );
        expect(scroll.offset, 0);
        await tester.pump(const Duration(microseconds: 8333));
        var previous = scroll.offset;
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(microseconds: 8333));
          final delta = scroll.offset - previous;
          expect(delta, greaterThan(0));
          expect(delta, lessThanOrEqualTo(1000 / 120 + 0.01));
          expect(
            tester.getTopLeft(find.byKey(_actions)).dy,
            closeTo(top + 262 - scroll.offset, 0.01),
          );
          expect(builds, baseline);
          expect(actionBuilds, actionBaseline);
          previous = scroll.offset;
        }
        await tester.pumpAndSettle(const Duration(milliseconds: 8));
        expect(scroll.offset, closeTo(120, 0.11));
        scroll.jumpTo(600);
        await tester.pump();
        expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 12);
        await tester.tap(find.byKey(_actions));
        await tester.pumpAndSettle();
        expect(presses, 1);
        scroll.jumpTo(0);
        await tester.pump();
        expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 262);
        expect(builds, baseline);
        expect(actionBuilds, actionBaseline);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        scroll.dispose();
      }
    });

    testWidgets(
      '$mode: one lazy document scrolls through fields into notes',
      (tester) async {
        final editor = EditorState(
          document: Document(
            root: pageNode(
              children: [
                for (var i = 0; i < 120; i++)
                  Node(type: 'row_test_note', attributes: {'number': i}),
              ],
            ),
          ),
        );
        final scroll = EditorScrollController(editorState: editor);
        final field = TextEditingController(text: 'unsaved field draft');
        final headerKey = GlobalKey();
        var headerBuilds = 0;
        var noteBuilds = 0;
        try {
          await tester.pumpWidget(
            _app(
              mode,
              RowDetailScrollSurface(
                coverHeight: _coverHeight,
                actions: const SizedBox(key: _actions, width: 40, height: 24),
                child: AppFlowyEditor(
                  editorState: editor,
                  editorScrollController: scroll,
                  contextMenuItems: const [],
                  header: RowDetailScrollHeader(
                    child: Builder(
                      key: headerKey,
                      builder: (_) {
                        headerBuilds++;
                        return SizedBox(
                          height: 700,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: _coverHeight),
                              TextField(controller: field),
                              const Text('Photos and other row fields'),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  blockComponentBuilders: {
                    ...standardBlockComponentBuilderMap,
                    PageBlockKeys.type: CustomPageBlockComponentBuilder(),
                    'row_test_note': _NoteBuilder(() => noteBuilds++),
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(NestedScrollView), findsNothing);
          ScrollableState documentScroller() => tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .singleWhere((state) => state.position.maxScrollExtent > 500);
          final position = documentScroller().position;
          expect(position.physics, isA<PremiumKineticScrollPhysics>());
          expect(noteBuilds, lessThan(120));
          final baseline = headerBuilds;
          final headerElement = headerKey.currentContext;
          final fieldState = tester.state(find.byType(TextField));
          final top = tester.getTopLeft(find.byType(RowDetailScrollSurface)).dy;
          final pan =
              await tester.createGesture(kind: PointerDeviceKind.trackpad);
          const point = Offset(240, 400);
          await pan.panZoomStart(point);
          var previous = position.pixels;
          for (var frame = 1; frame <= 130; frame++) {
            await pan.panZoomUpdate(
              point,
              pan: Offset(0, -30.0 * frame),
              timeStamp: Duration(milliseconds: frame * 16),
            );
            await tester.pump(const Duration(milliseconds: 16));
            expect(position.pixels, greaterThanOrEqualTo(previous));
            expect(position.pixels - previous, lessThanOrEqualTo(18.01));
            previous = position.pixels;
          }
          await pan.panZoomEnd(timeStamp: const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(position.pixels, greaterThan(1500));
          expect(headerKey.currentContext, same(headerElement));
          expect(headerBuilds, baseline);
          expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 12);
          position.jumpTo(0);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(TextField)), same(fieldState));
          expect(field.text, 'unsaved field draft');
          expect(tester.getTopLeft(find.byKey(_actions)).dy, top + 262);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          scroll.dispose();
          editor.dispose();
          field.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets('nested field scroll does not move the action overlay',
      (tester) async {
    final outer = ScrollController();
    final inner = ScrollController();
    try {
      await tester.pumpWidget(
        _app(
          'paper',
          RowDetailScrollSurface(
            coverHeight: _coverHeight,
            actions: const SizedBox(key: _actions, width: 40, height: 24),
            child: SingleChildScrollView(
              controller: outer,
              child: Column(
                children: [
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      controller: inner,
                      itemCount: 20,
                      itemExtent: 40,
                      itemBuilder: (_, index) => Text('File $index'),
                    ),
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getTopLeft(find.byKey(_actions));
      inner.jumpTo(100);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(_actions)), before);
      expect(outer.offset, 0);
      outer.jumpTo(100);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(_actions)).dy, before.dy - 100);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      outer.dispose();
      inner.dispose();
    }
  });
}

Widget _app(String mode, Widget child) => MaterialApp(
      theme: DesktopAppearance()
          .getThemeData(
            mode == 'paper'
                ? AppTheme.builtins.firstWhere(
                    (theme) => theme.themeName == BuiltInTheme.paper,
                  )
                : AppTheme.fallback,
            mode == 'dark' ? Brightness.dark : Brightness.light,
            defaultFontFamily,
            builtInCodeFontFamily,
          )
          .copyWith(platform: TargetPlatform.windows),
      home: PremiumScrollScope(
        enabled: true,
        child: Scaffold(body: child),
      ),
    );

class _NoteBuilder extends BlockComponentBuilder {
  _NoteBuilder(this.onBuild);

  final VoidCallback onBuild;

  @override
  BlockComponentWidget build(BlockComponentContext context) {
    onBuild();
    return _Note(node: context.node);
  }
}

class _Note extends BlockComponentStatelessWidget {
  const _Note({required super.node})
      : super(configuration: const BlockComponentConfiguration());

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 80,
        child: Text('Note ${node.attributes['number']}'),
      );
}
