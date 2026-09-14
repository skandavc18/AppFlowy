import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/materialized_file_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/shared/scrolling/deferred_page_embed.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _fillerType = 'embed-loading-test-filler';
const _leadingFillers = 8;
const _embedIndex = _leadingFillers + 1; // The leading paragraph is index zero.
const _blockPadding = EdgeInsets.fromLTRB(12, 12, 12, 20);
const _headerHeight = 48.0;

void main() {
  for (final shrinkWrap in [false, true]) {
    group('editor embed loading: shrinkWrap=$shrinkWrap', () {
      testWidgets(
        'cached file stays cold through a real fling and return to the top',
        (tester) async {
          await _withEditor(tester, shrinkWrap, (fixture) async {
            _expectProductionHierarchy(tester, fixture, previewEnabled: true);
            _expectOutsidePreload(tester, fixture);
            final record = fixture.record;
            final frameElement = record.frameKey.currentContext;
            expect(tester.getSize(_byKey(record.frameKey)), const Size(400, 240));
            // Header and padding exist even though the expensive body does not.
            expect(tester.getSize(_byKey(record.blockKey)).height, 320);
            expect(tester.getSize(_byKey(record.headerKey)).height, 48);
            await _pumpIdle(tester);
            _expectCold(record);

            final position = fixture.position;
            final pan = _PagePan(tester, fixture.panTarget);
            await pan.start();
            try {
              // Native trackpad release, including Premium's Windows scale.
              // No synthetic isScrollingNotifier or disabled editor services.
              for (var step = 0; step < 6; step++) {
                await pan.moveBy(-150, milliseconds: 25);
              }
              await pan.end(coast: true);
              expect(position.isScrollingNotifier.value, isTrue);
              await tester.pump();
              final releasedOffset = position.pixels;
              await tester.pump(const Duration(milliseconds: 16));
              expect(position.pixels, greaterThan(releasedOffset));
              expect(position.isScrollingNotifier.value, isTrue);
              expect(
                tester.getRect(_byKey(record.frameKey)).overlaps(fixture.viewport),
                isTrue,
                reason: 'the cold frame actually passed into the viewport',
              );
              expect(record.frameKey.currentContext, same(frameElement));
              _expectCold(record);
            } finally {
              await pan.end();
              // Stop after layout, before pumping idle; do not coast arbitrarily
              // far away or wait for an offscreen preview to schedule no frames.
              position.jumpTo(0);
              await tester.pump();
            }

            _expectOutsidePreload(tester, fixture);
            await _pumpIdle(tester);
            expect(position.pixels, 0);
            expect(record.frameKey.currentContext, same(frameElement));
            expect(tester.getSize(_byKey(record.frameKey)), const Size(400, 240));
            _expectCold(record);
          });
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );

      testWidgets(
        'held pan delays a 320px frame without a jump; scroll and resize keep state',
        (tester) async {
          await _withEditor(tester, shrinkWrap, (fixture) async {
            _expectProductionHierarchy(tester, fixture, previewEnabled: true);
            _expectOutsidePreload(tester, fixture);
            await fixture.reveal(tester);
            final record = fixture.record;
            final position = fixture.position;
            final pan = _PagePan(tester, fixture.panTarget);
            final beforePan = position.pixels;
            await pan.start();
            try {
              for (var step = 0; step < 3; step++) {
                await pan.moveBy(-20);
              }
              await tester.pump();
              expect(position.pixels, greaterThan(beforePan));
              expect(position.isScrollingNotifier.value, isTrue);
              expect(
                tester.getRect(_byKey(record.frameKey)).overlaps(fixture.viewport),
                isTrue,
              );
              // Give both the debounce and admission queue frames while a REAL
              // drag remains held. A visible frame alone must not mount it.
              await _pumpIdle(tester);
              expect(position.isScrollingNotifier.value, isTrue);
              _expectCold(record);
              expect(tester.getSize(_byKey(record.frameKey)), const Size(400, 320));
            } finally {
              await pan.end();
            }

            await tester.pump();
            position.jumpTo(position.pixels); // Eliminate residual native coast.
            await tester.pump();
            _expectCold(record);
            final before = _Geometry.capture(tester, fixture);
            before.expectFrame(height: 320);
            final idleOffset = position.pixels;
            final frameElement = record.frameKey.currentContext;

            await _pumpIdle(tester);
            final after = _Geometry.capture(tester, fixture);
            after.expectFrame(height: 320);
            expect(after.frame, before.frame);
            expect(after.block, before.block);
            expect(after.header, before.header);
            expect(after.pageHeader, before.pageHeader);
            expect((after.belowY - before.belowY).abs(), lessThan(0.1));
            expect(position.pixels, idleOffset, reason: 'admission must not scroll');
            expect(record.frameKey.currentContext, same(frameElement));
            final state = record.bodyKey.currentState!;
            final element = record.bodyKey.currentContext!;
            _expectSameBody(record, state, element);
            expect(record.previewEnabledInBody, isFalse);
            expect(state.inner.hasClients, isTrue);

            // Leave the visible/preload area, but stay within the real list's
            // two-viewport cache. We deliberately do not force any keep-alive:
            // disposal beyond actual virtualization is normal for shrinkWrap=false.
            final excursion = after.frame.bottom - fixture.viewport.top + 160;
            expect(excursion, lessThan(fixture.viewport.height * 2));
            position.jumpTo(idleOffset + excursion);
            await tester.pump(const Duration(milliseconds: 16));
            final cachedFrame = tester.getRect(_byKey(record.frameKey));
            expect(cachedFrame.bottom, lessThan(fixture.viewport.top - 128));
            expect(
              cachedFrame.bottom,
              greaterThan(fixture.viewport.top - fixture.viewport.height * 2),
            );
            await _pumpIdle(tester);
            _expectSameBody(record, state, element);
            position.jumpTo(idleOffset);
            await tester.pump(const Duration(milliseconds: 16));
            _expectSameBody(record, state, element);

            await tester.tap(_byKey(record.buttonKey));
            await tester.pump();
            expect(state.presses, 1);
            state.focus.requestFocus();
            await tester.pump();
            expect(state.focus.hasFocus, isTrue);
            // A real native list's retained offset is observable local state too.
            state.inner.jumpTo(64);
            await tester.pump();
            final beforeResizeOffset = position.pixels;
            final corner = find.descendant(
              of: _byKey(record.frameKey),
              matching: find.byKey(
                const ValueKey('resizable_media_bottom_right_handle'),
              ),
            );
            final resize = await tester.startGesture(
              tester.getCenter(corner),
              kind: PointerDeviceKind.mouse,
            );
            try {
              for (var step = 0; step < 2; step++) {
                await resize.moveBy(const Offset(-20, 20));
                await tester.pump(); // Catch reparenting during, not after, a drag.
                _expectSameBody(record, state, element);
              }
            } finally {
              await resize.up();
            }
            await tester.pump();
            expect(tester.getSize(_byKey(record.frameKey)), const Size(360, 360));
            expect(record.width, 360);
            expect(record.height, 360);
            expect(record.widthCommits, 1);
            expect(record.heightCommits, 1);
            expect(position.pixels, beforeResizeOffset);
            expect(state.inner.offset, 64);
            expect(state.presses, 1);
            expect(state.focus.hasFocus, isTrue);
            _expectSameBody(record, state, element);
          }, height: 320,);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );

      testWidgets(
        'file materialization starts only after real page admission and is reused',
        (tester) async {
          final loader = _RecordingLoader();
          await _withEditor(tester, shrinkWrap, (fixture) async {
            _expectProductionHierarchy(tester, fixture, previewEnabled: true);
            _expectOutsidePreload(tester, fixture);
            final record = fixture.record;
            final materializer = find.byType(
              MaterializedFileBuilder,
              skipOffstage: false,
            );
            await _pumpIdle(tester);
            expect(materializer, findsNothing);
            expect(loader.calls, 0);
            _expectCold(record);

            await fixture.reveal(tester);
            expect(materializer, findsNothing);
            expect(loader.calls, 0);
            final before = _Geometry.capture(tester, fixture);
            final position = fixture.position;
            final idleOffset = position.pixels;
            await _pumpIdle(tester);
            expect(materializer, findsOneWidget);
            expect(loader.calls, 1);
            expect(loader.source, 'fake-source');
            expect(loader.name, 'preview.txt');
            expect(record.initializations, 0, reason: 'the fake file is still pending');
            expect(record.bodyKey.currentContext, isNull);
            expect(position.pixels, idleOffset);
            expect(tester.getRect(_byKey(record.frameKey)), before.frame);
            final materializerElement = tester.element(materializer);
            final futureFinder = find.descendant(
              of: materializer,
              matching: find.byType(FutureBuilder<File>, skipOffstage: false),
              skipOffstage: false,
            );
            final future = tester.widget<FutureBuilder<File>>(futureFinder).future;

            // File is only a value here: no filesystem or network operation.
            loader.completion.complete(File('fake-preview.txt'));
            await tester.pump();
            await tester.pump();
            final state = record.bodyKey.currentState!;
            final element = record.bodyKey.currentContext!;
            _expectSameBody(record, state, element);
            final after = _Geometry.capture(tester, fixture);
            after.expectFrame(height: 240);
            expect(after.frame, before.frame);
            expect(after.header, before.header);
            expect((after.belowY - before.belowY).abs(), lessThan(0.1));
            expect(position.pixels, idleOffset);

            for (final delta in [40.0, -40.0]) {
              position.jumpTo(position.pixels + delta);
              await tester.pump(const Duration(milliseconds: 16));
              fixture.embed.notify();
              await tester.pump();
              expect(tester.element(materializer), same(materializerElement));
              expect(
                tester.widget<FutureBuilder<File>>(futureFinder).future,
                same(future),
              );
              expect(loader.calls, 1);
              _expectSameBody(record, state, element);
            }
          }, loader: loader,);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );

      testWidgets(
        'code uses the same bounded frame but its body is available immediately',
        (tester) async {
          await _withEditor(tester, shrinkWrap, (fixture) async {
            _expectProductionHierarchy(tester, fixture, previewEnabled: false);
            _expectOutsidePreload(tester, fixture);
            // No idle pump precedes this assertion. The renderer must exclude
            // editable code even when its identical fixed frame is only cached.
            final record = fixture.record;
            expect(record.initializations, 1);
            expect(fixture.editor.editable, isTrue);
            final state = record.bodyKey.currentState!;
            final element = record.bodyKey.currentContext!;
            _expectSameBody(record, state, element);
            expect(tester.getSize(_byKey(record.frameKey)), const Size(400, 240));
            expect(tester.getSize(_byKey(record.blockKey)).height, 320);
            await _pumpIdle(tester);
            _expectSameBody(record, state, element);
          }, type: CodeBlockKeys.type,);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    });
  }
}

Future<void> _withEditor(
  WidgetTester tester,
  bool shrinkWrap,
  Future<void> Function(_EditorFixture) test, {
  double height = 240,
  String type = 'file',
  _RecordingLoader? loader,
}) async {
  final fixture = _EditorFixture(
    shrinkWrap: shrinkWrap,
    height: height,
    type: type,
    loader: loader,
  );
  final semantics = tester.ensureSemantics();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 600);
  try {
    await tester.pumpWidget(fixture.app());
    await test(fixture);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.page.dispose();
    fixture.editor.dispose();
    semantics.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

// An idle timer does not itself keep pumpAndSettle alive. Pump its 80ms window
// explicitly, then the post-layout check and queued admission frames.
Future<void> _pumpIdle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Finder _byKey(Key key) => find.byKey(key, skipOffstage: false);

void _expectProductionHierarchy(
  WidgetTester tester,
  _EditorFixture fixture, {
  required bool previewEnabled,
}) {
  final record = fixture.record;
  expect(fixture.embed.path, [_embedIndex]);
  expect(record.builtIndices, contains(_embedIndex));
  expect(record.builtNodes, contains(same(fixture.embed)));
  expect(_byKey(fixture.embed.key), findsOneWidget);
  expect(_byKey(record.frameKey), findsOneWidget);
  final frame = _byKey(record.frameKey);
  for (final type in <Type>[
    FlowyOverlay,
    AppFlowyEditor,
    ScrollServiceWidget,
    SelectionServiceWidget,
    KeyboardServiceWidget,
    CustomPageBlockComponent,
    PageEmbedLoadScope,
    ScrollActivationRegion,
    ResizableMedia,
  ]) {
    expect(
      find.ancestor(of: frame, matching: find.byType(type, skipOffstage: false)),
      findsOneWidget,
      reason: 'the actual frame must be under $type',
    );
  }
  final editor = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
  expect(editor.disableSelectionService, isFalse);
  expect(editor.disableKeyboardService, isFalse);
  expect(editor.disableScrollService, isFalse);
  expect(editor.disableAutoScroll, isFalse);
  expect(
    record.frameKey.currentContext!
        .getInheritedWidgetOfExactType<PageEmbedPreviewScope>()
        ?.enabled,
    previewEnabled,
  );
  final deferred = find.descendant(
    of: frame,
    matching: find.byType(DeferredPageEmbed, skipOffstage: false),
    skipOffstage: false,
  );
  expect(deferred, findsOneWidget);
  expect(tester.widget<DeferredPageEmbed>(deferred).enabled, isTrue);
  final physics = <ScrollPhysics>[];
  for (ScrollPhysics? value = fixture.position.physics;
      value != null;
      value = value.parent) {
    physics.add(value);
  }
  expect(physics.whereType<PremiumKineticScrollPhysics>(), hasLength(1));
}

void _expectOutsidePreload(WidgetTester tester, _EditorFixture fixture) {
  final frame = tester.getRect(_byKey(fixture.record.frameKey));
  final viewport = fixture.viewport;
  expect(frame.top, greaterThan(viewport.bottom + 128));
  expect(frame.bottom, lessThan(viewport.bottom + viewport.height * 2));
  expect(frame.overlaps(viewport), isFalse);
  expect(fixture.record.frameKey.currentContext!.mounted, isTrue);
}

void _expectCold(_EmbedRecord record) {
  expect(record.initializations, 0);
  expect(record.disposals, 0);
  expect(record.bodyKey.currentContext, isNull);
  expect(record.elementAtInit, isNull);
}

void _expectSameBody(
  _EmbedRecord record,
  _BodyProbeState state,
  BuildContext element,
) {
  expect(record.initializations, 1);
  expect(record.deactivations, 0);
  expect(record.disposals, 0);
  expect(record.bodyKey.currentState, same(state));
  expect(record.bodyKey.currentContext, same(element));
  expect(record.elementAtInit, same(element));
}

class _EditorFixture {
  _EditorFixture({
    required bool shrinkWrap,
    required double height,
    required String type,
    _RecordingLoader? loader,
  }) : record = _EmbedRecord(height: height) {
    embed = Node(
      type: type,
      attributes: {
        if (type == CodeBlockKeys.type)
          'delta': (Delta()..insert('Editable code')).toJson(),
      },
    );
    below = paragraphNode(text: 'Paragraph immediately after the embed');
    editor = EditorState(
      document: Document(
        root: pageNode(
          children: [
            paragraphNode(text: 'Leading paragraph'),
            for (var i = 0; i < _leadingFillers; i++) Node(type: _fillerType),
            embed,
            below,
            for (var i = 0; i < 100; i++) paragraphNode(text: 'Trailing $i'),
          ],
        ),
      ),
    );
    page = EditorScrollController(editorState: editor, shrinkWrap: shrinkWrap);
    // Copy the map, never mutate the shared standard builders or their config.
    builders = {
      ...standardBlockComponentBuilderMap,
      PageBlockKeys.type: CustomPageBlockComponentBuilder(),
      _fillerType: _FillerBuilder(),
      type: _EmbedBuilder(record, loader: loader),
    };
  }

  final _EmbedRecord record;
  final pageHeaderKey = GlobalKey(debugLabel: 'page-header');
  late final Node embed;
  late final Node below;
  late final EditorState editor;
  late final EditorScrollController page;
  late final Map<String, BlockComponentBuilder> builders;

  // Particularly for shrinkWrap=true, page.scrollController is not necessarily
  // the position carrying this frame. Resolve the real ancestor before the body.
  ScrollPosition get position =>
      Scrollable.of(record.frameKey.currentContext!).position;

  Rect get viewport {
    final box = record.frameKey.currentContext!.findRenderObject()!;
    final viewport = RenderAbstractViewport.maybeOf(box.parent)!;
    return MatrixUtils.transformRect(
      viewport.getTransformTo(null),
      viewport.paintBounds,
    );
  }

  // The page margin, outside the frame and all its resize handles.
  Offset get panTarget => Offset(viewport.right - 24, viewport.center.dy);

  Future<void> reveal(WidgetTester tester) async {
    final frame = tester.getRect(_byKey(record.frameKey));
    final target = position.pixels + frame.top - viewport.top - 96;
    position.jumpTo(target);
    await tester.pump();
    expect(tester.getRect(_byKey(record.frameKey)).overlaps(viewport), isTrue);
    _expectCold(record);
  }

  Widget app() => MaterialApp(
        home: PremiumScrollScope(
          enabled: true,
          child: FlowyOverlay(
            child: Scaffold(
              body: Column(
                children: [
                  const SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: Text('Page toolbar'),
                  ),
                  Expanded(
                    child: AppFlowyEditor(
                      editorState: editor,
                      editorScrollController: page,
                      editorStyle: const EditorStyle.desktop(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                      ),
                      header: SizedBox(
                        key: pageHeaderKey,
                        height: 44,
                        width: double.infinity,
                        child: const Text('Page header'),
                      ),
                      blockComponentBuilders: builders,
                      contextMenuItems: const [],
                      // Keep every editor service at its production default.
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _EmbedRecord {
  _EmbedRecord({required this.height});

  final blockKey = GlobalKey(debugLabel: 'embed-block');
  final headerKey = GlobalKey(debugLabel: 'embed-header');
  final frameKey = GlobalKey(debugLabel: 'embed-frame');
  final bodyKey = GlobalKey<_BodyProbeState>(debugLabel: 'embed-body');
  final buttonKey = GlobalKey(debugLabel: 'embed-button');
  final builtIndices = <int>{};
  final builtNodes = <Node>[];
  Element? elementAtInit;
  bool? previewEnabledInBody;
  int initializations = 0;
  int deactivations = 0;
  int disposals = 0;
  int widthCommits = 0;
  int heightCommits = 0;
  double width = 400;
  double height;
}

class _EmbedBuilder extends BlockComponentBuilder {
  _EmbedBuilder(this.record, {this.loader});

  final _EmbedRecord record;
  final _RecordingLoader? loader;

  @override
  BlockComponentWidget build(BlockComponentContext context) {
    record.builtIndices.add(context.node.path.single);
    record.builtNodes.add(context.node);
    return _Embed(
      key: context.node.key,
      node: context.node,
      record: record,
      loader: loader,
    );
  }
}

class _Embed extends BlockComponentStatelessWidget {
  const _Embed({
    super.key,
    required super.node,
    required this.record,
    this.loader,
  }) : super(configuration: const BlockComponentConfiguration());

  final _EmbedRecord record;
  final _RecordingLoader? loader;

  @override
  Widget build(BuildContext context) {
    final probe = _BodyProbe(key: record.bodyKey, record: record);
    final fileLoader = loader;
    final body = fileLoader == null
        ? probe
        : MaterializedFileBuilder(
            source: 'fake-source',
            name: 'preview.txt',
            loader: fileLoader.load,
            builder: (_, snapshot) => snapshot.hasData
                ? probe
                : const Center(child: Text('Waiting for fake file')),
          );
    // No test-owned load/preview scopes or visibility gates: CustomPage and
    // editorEmbedScrollRegion must supply them, and ResizableMedia must defer.
    return StatefulBuilder(
      builder: (context, setState) => Padding(
        key: record.blockKey,
        padding: _blockPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              key: record.headerKey,
              height: _headerHeight,
              width: double.infinity,
              child: const Text('Embed header'),
            ),
            ResizableMedia(
              width: record.width,
              height: record.height,
              alignment: Alignment.centerLeft,
              onResize: (width) => setState(() {
                record.width = width;
                record.widthCommits++;
              }),
              onResizeHeight: (height) => setState(() {
                record.height = height;
                record.heightCommits++;
              }),
              frameBuilder: (frame) => KeyedSubtree(
                key: record.frameKey,
                child: frame,
              ),
              child: body,
            ),
          ],
        ),
      ),
    );
  }
}

class _FillerBuilder extends BlockComponentBuilder {
  @override
  BlockComponentWidget build(BlockComponentContext context) =>
      _Filler(key: context.node.key, node: context.node);
}

class _Filler extends BlockComponentStatelessWidget {
  const _Filler({super.key, required super.node})
      : super(configuration: const BlockComponentConfiguration());

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 80,
        width: double.infinity,
        child: Text('Lightweight filler'),
      );
}

// Intentionally no AutomaticKeepAliveClientMixin. A completed body is retained
// only as long as the real editor retains its block in the viewport/cache.
class _BodyProbe extends StatefulWidget {
  const _BodyProbe({super.key, required this.record});

  final _EmbedRecord record;

  @override
  State<_BodyProbe> createState() => _BodyProbeState();
}

class _BodyProbeState extends State<_BodyProbe> {
  final inner = ScrollController();
  final focus = FocusNode();
  int presses = 0;

  @override
  void initState() {
    super.initState();
    widget.record.initializations++;
    widget.record.elementAtInit = context as Element;
  }

  @override
  Widget build(BuildContext context) {
    widget.record.previewEnabledInBody = context
        .dependOnInheritedWidgetOfExactType<PageEmbedPreviewScope>()
        ?.enabled;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          SizedBox(
            height: 36,
            child: TextButton(
              key: widget.record.buttonKey,
              focusNode: focus,
              onPressed: () => setState(() => presses++),
              child: const Text('Use fake preview'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: inner,
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: 80,
              itemExtent: 32,
              itemBuilder: (_, index) => Text('Embedded row $index'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void deactivate() {
    widget.record.deactivations++;
    super.deactivate();
  }

  @override
  void dispose() {
    widget.record.disposals++;
    inner.dispose();
    focus.dispose();
    super.dispose();
  }
}

class _Geometry {
  _Geometry.capture(WidgetTester tester, _EditorFixture fixture)
      : frame = tester.getRect(_byKey(fixture.record.frameKey)),
        block = tester.getRect(_byKey(fixture.record.blockKey)),
        header = tester.getRect(_byKey(fixture.record.headerKey)),
        pageHeader = tester.getRect(_byKey(fixture.pageHeaderKey)),
        belowY = tester.getTopLeft(_byKey(fixture.below.key)).dy;

  final Rect frame;
  final Rect block;
  final Rect header;
  final Rect pageHeader;
  final double belowY;

  void expectFrame({required double height}) {
    expect(frame.size, Size(400, height));
    expect(block.height, height + _headerHeight + _blockPadding.vertical);
    expect(header.height, _headerHeight);
    expect(header.top - block.top, _blockPadding.top);
    expect(header.left - block.left, _blockPadding.left);
    expect(block.right - header.right, _blockPadding.right);
    expect(frame.left, header.left);
    expect(frame.top, header.bottom);
    expect(block.bottom - frame.bottom, _blockPadding.bottom);
    expect(pageHeader.height, 44);
  }
}

class _RecordingLoader {
  final completion = Completer<File>();
  late final MaterializedFileLoader load = _load;
  int calls = 0;
  String? source;
  String? name;

  Future<File> _load({
    required String source,
    required String name,
    required Map<String, String> httpHeaders,
  }) {
    calls++;
    this.source = source;
    this.name = name;
    return completion.future;
  }
}

// Same PointerPanZoom input path as editor_embed_scroll_test.dart. The optional
// stationary sample suppresses release velocity; coast=true exercises a fling.
class _PagePan {
  _PagePan(this.tester, this.position);

  final WidgetTester tester;
  final Offset position;
  double _pan = 0;
  int _milliseconds = 0;
  bool _active = false;

  Future<void> start() async {
    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(pointer: 81, device: 81, position: position),
    );
    _active = true;
  }

  Future<void> moveBy(double delta, {int milliseconds = 10}) async {
    _pan += delta;
    _milliseconds += milliseconds;
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 81,
        device: 81,
        position: position,
        pan: Offset(0, _pan),
        panDelta: Offset(0, delta),
        timeStamp: Duration(milliseconds: _milliseconds),
      ),
    );
  }

  Future<void> end({bool coast = false}) async {
    if (!_active) return;
    if (!coast) await moveBy(0, milliseconds: 200);
    _milliseconds++;
    await tester.sendEventToBinding(
      PointerPanZoomEndEvent(
        pointer: 81,
        device: 81,
        position: position,
        timeStamp: Duration(milliseconds: _milliseconds),
      ),
    );
    _active = false;
  }
}