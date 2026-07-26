import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_scroll_physics.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_sidebar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_theme.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_view_options.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
// ignore: implementation_imports
import 'package:appflowy_editor/src/flutter/scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared PDF scroll controller forwards to one attached viewer', () {
    final controller = PdfPreviewScrollController();
    final event = const PointerScrollEvent(
      position: Offset(10, 10),
      scrollDelta: Offset(0, 80),
    );
    var firstCalls = 0;
    var secondCalls = 0;
    void firstHandler(PointerSignalEvent _) => firstCalls++;
    void secondHandler(PointerSignalEvent _) => secondCalls++;

    controller.attach(firstHandler);
    controller.handlePointerSignal(event);
    controller.attach(secondHandler);
    controller.handlePointerSignal(event);
    controller.detach(secondHandler);
    controller.handlePointerSignal(event);

    expect(firstCalls, 1);
    expect(secondCalls, 1);
  });

  test('PDF wheel uses normalized premium velocity impulses', () {
    final firstImpulse = pdfWheelVelocityImpulse(
      scrollDelta: const Offset(0, 20),
      kind: PointerDeviceKind.mouse,
    );
    final continuedVelocity = accumulatePremiumScrollVelocity(
      existingVelocity: firstImpulse.dy,
      impulse: pdfWheelVelocityImpulse(
        scrollDelta: const Offset(0, 30),
        kind: PointerDeviceKind.mouse,
      ).dy,
    );

    expect(firstImpulse, const Offset(0, -280));
    expect(continuedVelocity, closeTo(-497.6, 0.001));
  });

  test('PDF kinetic frame coasts with exponential deceleration', () {
    final decay = pdfKineticDecay(
      friction: 5,
      elapsedSeconds: 1 / 60,
    );
    final displacement = pdfKineticFrameDisplacement(
      velocity: const Offset(0, -1000),
      friction: 5,
      elapsedSeconds: 1 / 60,
    );
    final nextVelocity = pdfKineticFrameVelocity(
      velocity: const Offset(0, -1000),
      friction: 5,
      elapsedSeconds: 1 / 60,
    );

    expect(decay, closeTo(0.920044, 0.000001));
    expect(displacement.dy, closeTo(-15.9911, 0.001));
    expect(nextVelocity.dy, closeTo(-920.044, 0.001));
    expect(nextVelocity.distance, lessThan(1000));
  });

  test('PDF trackpad pan applies the platform delta directly', () {
    final translation = applyPdfTrackpadPan(
      currentTranslation: const Offset(12, -40),
      panDelta: const Offset(3, -36),
    );

    expect(translation, const Offset(15, -76));
  });

  test('shared PDF scroll controller forwards trackpad pan/zoom events', () {
    final controller = PdfPreviewScrollController();
    var starts = 0;
    var updates = 0;
    var ends = 0;
    void pointerSignalHandler(PointerSignalEvent _) {}

    controller.attach(
      pointerSignalHandler,
      onPointerPanZoomStart: (_) => starts++,
      onPointerPanZoomUpdate: (_) => updates++,
      onPointerPanZoomEnd: (_) => ends++,
    );
    controller.handlePointerPanZoomStart(
      const PointerPanZoomStartEvent(pointer: 7),
    );
    controller.handlePointerPanZoomUpdate(
      const PointerPanZoomUpdateEvent(
        pointer: 7,
        pan: Offset(0, -40),
        panDelta: Offset(0, -40),
      ),
    );
    controller.handlePointerPanZoomEnd(
      const PointerPanZoomEndEvent(pointer: 7),
    );
    controller.detach(pointerSignalHandler);
    controller.handlePointerPanZoomUpdate(
      const PointerPanZoomUpdateEvent(pointer: 8),
    );

    expect(starts, 1);
    expect(updates, 1);
    expect(ends, 1);
  });

  testWidgets('PDF embed owns wheel input instead of ancestor editor scroll', (
    tester,
  ) async {
    final editorScrollController = ScrollController();
    addTearDown(editorScrollController.dispose);
    var claimedSignals = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: SingleChildScrollView(
            controller: editorScrollController,
            child: Column(
              children: [
                PdfEmbedScrollGuard(
                  onPointerSignal: (_) => claimedSignals++,
                  child: const SizedBox(
                    key: ValueKey('pdf-embed-guard-area'),
                    width: 400,
                    height: 240,
                  ),
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('pdf-embed-guard-area')),
        ),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pump();

    expect(claimedSignals, 1);
    expect(editorScrollController.offset, 0);
  });

  testWidgets('resized PDF owns wheel input only inside its current frame', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editorScrollController = ScrollController();
    final width = ValueNotifier<double>(500);
    addTearDown(editorScrollController.dispose);
    addTearDown(width.dispose);
    var claimedSignals = 0;

    await tester.pumpWidget(
      _resizedPdfScrollHarness(
        editorScrollController: editorScrollController,
        width: width,
        onPointerSignal: (_) => claimedSignals++,
      ),
    );

    width.value = 300;
    await tester.pump();
    final frame = find.byKey(const ValueKey('resizable_media'));
    final frameRect = tester.getRect(frame);
    expect(frameRect.width, 300);

    // This point was inside the old 500px frame, but is outside the resized
    // 300px frame. It must now belong to the surrounding editor.
    final outsideRight = Offset(frameRect.right + 60, frameRect.center.dy);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: outsideRight,
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 8));

    expect(claimedSignals, 0);
    expect(editorScrollController.offset, greaterThan(0));

    editorScrollController.jumpTo(0);
    await tester.pump();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: frameRect.center,
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(claimedSignals, 1);
    expect(editorScrollController.offset, 0);

    final outsideLeft = Offset(frameRect.left - 60, frameRect.center.dy);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: outsideLeft,
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 8));

    expect(claimedSignals, 1);
    expect(editorScrollController.offset, greaterThan(0));
  });

  testWidgets('resized PDF owns trackpad pan only inside its current frame', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editorScrollController = ScrollController();
    final width = ValueNotifier<double>(500);
    addTearDown(editorScrollController.dispose);
    addTearDown(width.dispose);
    var starts = 0;
    var updates = 0;

    await tester.pumpWidget(
      _resizedPdfScrollHarness(
        editorScrollController: editorScrollController,
        width: width,
        onPointerSignal: (_) {},
        onPointerPanZoomStart: (_) => starts++,
        onPointerPanZoomUpdate: (_) => updates++,
      ),
    );

    width.value = 300;
    await tester.pump();
    final frameRect = tester.getRect(
      find.byKey(const ValueKey('resizable_media')),
    );
    final outside = Offset(frameRect.right + 60, frameRect.center.dy);

    await _sendTrackpadPan(
      tester,
      pointer: 41,
      position: outside,
    );
    await tester.pump();

    expect(starts, 0);
    expect(updates, 0);
    expect(editorScrollController.offset, greaterThan(0));

    editorScrollController.jumpTo(0);
    await tester.pump();
    await _sendTrackpadPan(
      tester,
      pointer: 42,
      position: frameRect.center,
    );
    await tester.pump();

    expect(starts, 1);
    expect(updates, 1);
    expect(editorScrollController.offset, 0);
  });

  testWidgets(
    'PDF embed owns trackpad pan instead of inner drag or ancestor editor',
    (tester) async {
      final editorScrollController = ScrollController();
      addTearDown(editorScrollController.dispose);
      final panDeltas = <Offset>[];
      var starts = 0;
      var ends = 0;
      var competingDragUpdates = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: SingleChildScrollView(
              controller: editorScrollController,
              child: Column(
                children: [
                  PdfEmbedScrollGuard(
                    onPointerSignal: (_) {},
                    onPointerPanZoomStart: (_) => starts++,
                    onPointerPanZoomUpdate: (event) {
                      panDeltas.add(event.localPanDelta);
                    },
                    onPointerPanZoomEnd: (_) => ends++,
                    child: GestureDetector(
                      onPanUpdate: (_) => competingDragUpdates++,
                      child: const SizedBox(
                        key: ValueKey('pdf-trackpad-guard-area'),
                        width: 400,
                        height: 240,
                      ),
                    ),
                  ),
                  const SizedBox(height: 900),
                ],
              ),
            ),
          ),
        ),
      );

      final position = tester.getCenter(
        find.byKey(const ValueKey('pdf-trackpad-guard-area')),
      );
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(
          pointer: 11,
          device: 11,
          position: position,
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 11,
          device: 11,
          position: position,
          pan: const Offset(2, -80),
          panDelta: const Offset(2, -80),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(
          pointer: 11,
          device: 11,
          position: position,
        ),
      );
      await tester.pump();

      expect(starts, 1);
      expect(panDeltas, const [Offset(2, -80)]);
      expect(ends, 1);
      expect(competingDragUpdates, 0);
      expect(editorScrollController.offset, 0);
    },
  );

  testWidgets('PDF owns wheel input inside the actual AppFlowy editor list', (
    tester,
  ) async {
    ScrollableState? editorScrollable;
    var claimedSignals = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: ScrollablePositionedList.builder(
            itemCount: 2,
            itemBuilder: (context, index) {
              if (index == 1) {
                return const SizedBox(height: 900);
              }
              return Builder(
                builder: (context) {
                  editorScrollable = Scrollable.maybeOf(context);
                  return PdfEmbedScrollGuard(
                    onPointerSignal: (_) => claimedSignals++,
                    child: const SizedBox(
                      key: ValueKey('pdf-in-appflowy-editor'),
                      width: 400,
                      height: 240,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('pdf-in-appflowy-editor')),
        ),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pump();

    expect(claimedSignals, 1);
    expect(editorScrollable?.position.pixels, 0);
  });

  testWidgets('nested PDF sidebar scroll keeps priority over embed guard', (
    tester,
  ) async {
    final editorScrollController = ScrollController();
    final sidebarScrollController = ScrollController();
    addTearDown(editorScrollController.dispose);
    addTearDown(sidebarScrollController.dispose);
    var claimedSignals = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: SingleChildScrollView(
            controller: editorScrollController,
            child: Column(
              children: [
                PdfEmbedScrollGuard(
                  onPointerSignal: (_) => claimedSignals++,
                  child: SizedBox(
                    width: 400,
                    height: 240,
                    child: SingleChildScrollView(
                      key: const ValueKey('pdf-sidebar-scroll-area'),
                      controller: sidebarScrollController,
                      child: const SizedBox(height: 900),
                    ),
                  ),
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('pdf-sidebar-scroll-area')),
        ),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pump();

    expect(sidebarScrollController.offset, greaterThan(0));
    expect(editorScrollController.offset, 0);
    expect(claimedSignals, 0);
  });

  group('parsePdfPageNumber', () {
    test('accepts valid pages and clamps document bounds', () {
      expect(parsePdfPageNumber('7', 12), 7);
      expect(parsePdfPageNumber('0', 12), 1);
      expect(parsePdfPageNumber('999', 12), 12);
      expect(parsePdfPageNumber(' 4 ', 12), 4);
    });

    test('rejects invalid input and empty documents', () {
      expect(parsePdfPageNumber('', 12), isNull);
      expect(parsePdfPageNumber('page 2', 12), isNull);
      expect(parsePdfPageNumber('2', 0), isNull);
    });
  });

  testWidgets('page field submits a clamped page and restores invalid input', (
    tester,
  ) async {
    int? submittedPage;
    await tester.pumpWidget(
      _themedApp(
        child: Center(
          child: PdfPageNumberField(
            page: 4,
            pageCount: 12,
            enabled: true,
            onSubmitted: (page) => submittedPage = page,
          ),
        ),
      ),
    );

    final field = find.byKey(const ValueKey('pdf-page-number-field'));
    await tester.enterText(field, '99');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(submittedPage, 12);
    expect(tester.widget<TextField>(field).controller?.text, '12');

    submittedPage = null;
    await tester.enterText(field, '');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(submittedPage, isNull);
    expect(tester.widget<TextField>(field).controller?.text, '4');
  });

  testWidgets('compact toolbar keeps essentials and one merged overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 160));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _themedApp(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 430,
            child: _toolbar(),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Show page thumbnails'), findsOneWidget);
    expect(find.byTooltip('Search document (Ctrl/Cmd F)'), findsOneWidget);
    expect(find.byTooltip('Open in full screen'), findsOneWidget);
    expect(find.byTooltip('Fit to width'), findsNothing);
    expect(find.text('Premium design.pdf'), findsNothing);
    expect(
      find.byKey(const ValueKey('merged-pdf-overflow-trigger')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide toolbar exposes the complete primary action set', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 180));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _themedApp(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 1100,
            child: _toolbar(),
          ),
        ),
      ),
    );

    expect(find.text('Premium design.pdf'), findsOneWidget);
    expect(find.byTooltip('Fit to width'), findsOneWidget);
    expect(find.byTooltip('Fit whole page'), findsOneWidget);
    expect(find.byTooltip('Rotate clockwise'), findsOneWidget);
    expect(find.byTooltip('Download PDF'), findsOneWidget);
    expect(find.byTooltip('Print PDF'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('merged-pdf-overflow-trigger')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    for (final button in find.byType(FilePreviewToolbarButton).evaluate()) {
      expect(tester.getSize(find.byWidget(button.widget)), const Size(28, 28));
    }
    expect(PdfPreviewGeometry.toolbarHeight, 42);
    expect(PdfPreviewGeometry.toolbarRadius, 10);
    expect(PdfPreviewGeometry.blurSigma, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one popup contains PDF and injected file actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themedApp(
        child: Center(
          child: PopupMenuButton<String>(
            key: const ValueKey('merged-menu-test-trigger'),
            icon: const Icon(Icons.more_horiz_rounded),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'fit-width',
                child: Text('Fit to width'),
              ),
              PdfPreviewMenuSection<String>(
                builder: (_, closeMenu) => TextButton(
                  onPressed: closeMenu,
                  child: const Text('Rename file'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('merged-menu-test-trigger')));
    await tester.pumpAndSettle();

    expect(find.text('Fit to width'), findsOneWidget);
    expect(find.text('Rename file'), findsOneWidget);

    await tester.tap(find.text('Rename file'));
    await tester.pumpAndSettle();

    expect(find.text('Fit to width'), findsNothing);
    expect(find.text('Rename file'), findsNothing);
  });

  testWidgets('toolbar buttons use the code block neutral hover surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      _themedApp(
        child: Center(
          child: FilePreviewToolbarButton(
            tooltip: 'Copy',
            icon: Icons.content_copy_outlined,
            onPressed: () {},
          ),
        ),
      ),
    );

    final button = find.byType(FilePreviewToolbarButton);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 200));

    final surface = tester.widget<AnimatedContainer>(
      find.descendant(
        of: button,
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = surface.decoration! as BoxDecoration;
    final palette = PremiumTheme.resolve(
      appTheme: AppTheme.fallback,
      legacy: AppTheme.fallback.lightTheme,
      brightness: Brightness.light,
    );
    expect(decoration.color, palette.hover);
    expect(decoration.borderRadius, BorderRadius.circular(7));

    await mouse.removePointer();
  });

  testWidgets('search status is announced as a live region', (tester) async {
    final controller = TextEditingController(text: 'flowy');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _themedApp(
        child: PdfSearchToolbar(
          controller: controller,
          focusNode: focusNode,
          currentMatch: 2,
          matchCount: 8,
          searchProgress: 0.6,
          isSearching: true,
          onChanged: (_) {},
          onPrevious: () {},
          onNext: () {},
          onClose: () {},
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('PDF search results: 2 of 8'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('pdf-search-field')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('palette preserves warm paper and neutral dark surfaces', (
    tester,
  ) async {
    late PdfPreviewPalette palette;

    await tester.pumpWidget(
      _themedApp(
        paper: true,
        child: Builder(
          builder: (context) {
            palette = PdfPreviewPalette.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(palette.canvas, PaperTheme.editorPreviewBackground);
    expect(palette.sidebar, PaperTheme.sidebarBackground);
    expect(palette.chrome, PaperTheme.popupBackground);
    expect(palette.control, PaperTheme.controlBackground);
    expect(palette.controlHover, PaperTheme.hoverOverlay);
    expect(palette.controlSelected, PaperTheme.selectedOverlay);
    expect(palette.border, PaperTheme.codeBlockBorder);
    expect(palette.accent, PaperTheme.accent);
    // The PDF shell now carries the same soft depth as every other embed.
    expect(palette.shellShadows, hasLength(2));
    expect(palette.shellShadows.first.color.r, greaterThan(0));

    await tester.pumpWidget(
      _themedApp(
        brightness: Brightness.dark,
        child: Builder(
          builder: (context) {
            palette = PdfPreviewPalette.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(palette.canvas, const Color(0xFF17181B));
    expect(palette.sidebar, const Color(0xFF1D1E22));
    expect(palette.canvas, isNot(Colors.black));
    expect(palette.shellShadows, hasLength(2));
    expect(palette.shellShadows.first.spreadRadius, lessThan(0));
  });

  testWidgets('light palette keeps PDF controls light and readable', (
    tester,
  ) async {
    late PdfPreviewPalette palette;

    await tester.pumpWidget(
      _themedApp(
        child: Builder(
          builder: (context) {
            palette = PdfPreviewPalette.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final premium = PremiumTheme.resolve(
      appTheme: AppTheme.fallback,
      legacy: AppTheme.fallback.lightTheme,
      brightness: Brightness.light,
    );
    expect(palette.canvas, premium.surface);
    expect(palette.chrome, premium.floatingSurface.withValues(alpha: 0.96));
    expect(palette.control, premium.mutedSurface);
    expect(palette.controlHover, premium.hover);
    expect(palette.controlSelected, premium.selected);
    expect(palette.control.computeLuminance(), greaterThan(0.75));
    expect(
      _contrastRatio(palette.icon, palette.control),
      greaterThanOrEqualTo(3),
    );
  });

  group('page layout modes', () {
    const pages = [Size(200, 300), Size(200, 300), Size(180, 260)];
    const margin = 20.0;

    test('continuous stacks pages in one column with an even gap', () {
      final layout = buildPdfPageLayoutForSizes(
        pages,
        margin,
        PdfPageLayoutMode.continuous,
      );

      expect(layout.pageLayouts, hasLength(3));
      expect(layout.pageLayouts[0].top, margin);
      expect(layout.pageLayouts[1].top, margin + 300 + margin);
      expect(layout.documentSize.width, 200 + margin * 2);
      // Every page is centred on the same column.
      expect(layout.pageLayouts[2].center.dx, layout.documentSize.width / 2);
    });

    test('page break keeps the column but opens a real gutter', () {
      final continuous = buildPdfPageLayoutForSizes(
        pages,
        margin,
        PdfPageLayoutMode.continuous,
      );
      final broken = buildPdfPageLayoutForSizes(
        pages,
        margin,
        PdfPageLayoutMode.pageBreak,
      );

      expect(broken.pageLayouts.first.top, continuous.pageLayouts.first.top);
      expect(
        broken.pageLayouts[1].top,
        greaterThan(continuous.pageLayouts[1].top),
      );
      expect(
        broken.documentSize.height,
        greaterThan(continuous.documentSize.height),
      );
    });

    test('horizontal lays pages out in one row', () {
      final layout = buildPdfPageLayoutForSizes(
        pages,
        margin,
        PdfPageLayoutMode.horizontal,
      );

      expect(layout.pageLayouts[0].left, margin);
      expect(layout.pageLayouts[1].left, margin + 200 + margin);
      expect(layout.documentSize.height, 300 + margin * 2);
      for (final rect in layout.pageLayouts) {
        expect(rect.center.dy, closeTo(layout.documentSize.height / 2, 0.001));
      }
    });

    test('side by side pairs from the first page', () {
      final layout = buildPdfPageLayoutForSizes(
        pages,
        margin,
        PdfPageLayoutMode.facing,
      );

      expect(layout.pageLayouts, hasLength(3));
      // Pages 1 and 2 face each other on the first row and are centred against
      // one another; page 3 has no partner left, so it drops to a second row.
      expect(layout.pageLayouts[0].center.dy, layout.pageLayouts[1].center.dy);
      expect(
        layout.pageLayouts[0].right,
        lessThanOrEqualTo(layout.pageLayouts[1].left),
      );
      expect(layout.pageLayouts[0].top, lessThan(layout.pageLayouts[2].top));
      expect(layout.documentSize.width, greaterThan(200 * 2));
    });

    test('an empty document still produces a usable layout', () {
      for (final mode in PdfPageLayoutMode.values) {
        final layout = buildPdfPageLayoutForSizes(const [], margin, mode);
        expect(layout.pageLayouts, isEmpty);
        expect(layout.documentSize.width, greaterThanOrEqualTo(0));
        expect(layout.documentSize.height, greaterThanOrEqualTo(0));
      }
    });
  });

  group('side by side navigation', () {
    test('odd pages face the page after them', () {
      expect(facingPartnerPage(1, 8), 2);
      expect(facingPartnerPage(2, 8), 1);
      expect(facingPartnerPage(3, 8), 4);
      expect(facingPartnerPage(7, 8), 8);
      expect(facingPartnerPage(8, 8), 7);
    });

    test('a trailing page with no partner stands alone', () {
      expect(facingPartnerPage(7, 7), isNull);
      expect(facingPartnerPage(1, 1), isNull);
      expect(facingPartnerPage(0, 8), isNull);
      expect(facingPartnerPage(9, 8), isNull);
    });

    test('page turns move one whole spread', () {
      expect(nextFacingPage(1, 8), 3);
      expect(nextFacingPage(2, 8), 3);
      expect(nextFacingPage(3, 8), 5);
      expect(nextFacingPage(6, 8), 7);
      // The last spread has nowhere to go, so it does not creep forward.
      expect(nextFacingPage(7, 8), 7);
      expect(nextFacingPage(8, 8), 7);
      expect(nextFacingPage(7, 9), 9);

      expect(previousFacingPage(8), 5);
      expect(previousFacingPage(7), 5);
      expect(previousFacingPage(4), 1);
      expect(previousFacingPage(3), 1);
      expect(previousFacingPage(2), 1);
      expect(previousFacingPage(1), 1);
    });
  });

  group('persisted view options', () {
    test('unknown or missing values fall back to the defaults', () {
      expect(
        PdfPageLayoutMode.fromName(null),
        PdfPageLayoutMode.continuous,
      );
      expect(
        PdfPageLayoutMode.fromName('nonsense'),
        PdfPageLayoutMode.continuous,
      );
      expect(PdfPageTransition.fromName(null), PdfPageTransition.slide);
      expect(PdfPageTransition.fromName(7), PdfPageTransition.slide);
    });

    test('every option round trips through its stored name', () {
      for (final mode in PdfPageLayoutMode.values) {
        expect(PdfPageLayoutMode.fromName(mode.name), mode);
      }
      for (final transition in PdfPageTransition.values) {
        expect(PdfPageTransition.fromName(transition.name), transition);
      }
    });
  });

  group('reading mode presets', () {
    test('every preset pairs an animation the layout can actually play', () {
      for (final preset in PdfViewPreset.values) {
        final paged = preset.layoutMode.turnsPages ||
            preset.layoutMode == PdfPageLayoutMode.facing;
        if (!paged) {
          expect(
            preset.transition,
            PdfPageTransition.none,
            reason: '${preset.name} never changes page',
          );
        } else {
          expect(
            preset.transition,
            isNot(PdfPageTransition.none),
            reason: '${preset.name} turns pages',
          );
        }
      }
    });

    test('no two presets offer the same combination', () {
      final pairs = PdfViewPreset.values
          .map((preset) => '${preset.layoutMode.name}/${preset.transition.name}')
          .toList();
      expect(pairs.toSet().length, pairs.length);
    });

    test('covers every layout at least once', () {
      final layouts =
          PdfViewPreset.values.map((preset) => preset.layoutMode).toSet();
      expect(layouts, containsAll(PdfPageLayoutMode.values));
    });

    test('resolve finds the exact pair', () {
      for (final preset in PdfViewPreset.values) {
        expect(
          PdfViewPreset.resolve(preset.layoutMode, preset.transition),
          preset,
        );
      }
    });

    test('resolve falls back to the layout for combinations we dropped', () {
      expect(
        PdfViewPreset.resolve(
          PdfPageLayoutMode.continuous,
          PdfPageTransition.flip,
        ),
        PdfViewPreset.continuous,
      );
      expect(
        PdfViewPreset.resolve(
          PdfPageLayoutMode.facing,
          PdfPageTransition.fade,
        ).layoutMode,
        PdfPageLayoutMode.facing,
      );
    });
  });

  group('layout behaviour', () {

    test('only page break mode turns pages on a wheel notch', () {
      expect(
        PdfPageLayoutMode.values.where((mode) => mode.turnsPages),
        [PdfPageLayoutMode.pageBreak],
      );
      expect(
        PdfPageLayoutMode.values.where((mode) => mode.isHorizontal),
        [PdfPageLayoutMode.horizontal],
      );
    });

    test('only the page turn curls paper, only the fade hides the canvas', () {
      expect(
        PdfPageTransition.values.where((style) => style.curlsPaper),
        [PdfPageTransition.flip],
      );
      expect(
        PdfPageTransition.values.where((style) => style.swapsAtMidpoint),
        [PdfPageTransition.fade],
      );
    });
  });

  testWidgets('the PDF side panel scrolls on its own controller', (
    tester,
  ) async {
    final outlineScrollController = ScrollController();
    addTearDown(outlineScrollController.dispose);

    await tester.pumpWidget(
      _themedApp(
        child: SizedBox(
          width: 224,
          height: 400,
          child: PdfPreviewSidebar(
            mode: PdfSidebarMode.outline,
            document: null,
            currentPage: 1,
            outline: const [],
            outlineLoading: false,
            outlineScrollController: outlineScrollController,
            onPageSelected: (_) {},
            onDestinationSelected: (_) {},
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(outlineScrollController.hasClients, isTrue);
  });
}

PdfPreviewToolbar _toolbar() => PdfPreviewToolbar(
      title: 'Premium design.pdf',
      currentPage: 3,
      pageCount: 120,
      zoom: 1.25,
      ready: true,
      showThumbnails: false,
      showOutline: false,
      searchVisible: false,
      isFullscreen: false,
      onToggleThumbnails: () {},
      onToggleOutline: () {},
      onPreviousPage: () {},
      onNextPage: () {},
      onPageSubmitted: (_) {},
      onZoomOut: () {},
      onZoomIn: () {},
      onFitWidth: () {},
      onFitPage: () {},
      onToggleSearch: () {},
      onRotate: () {},
      onDownload: () {},
      onPrint: () {},
      onFullscreen: () {},
      overflow: const SizedBox.square(
        key: ValueKey('merged-pdf-overflow-trigger'),
        dimension: 30,
        child: Icon(Icons.more_horiz_rounded),
      ),
    );

Widget _themedApp({
  required Widget child,
  Brightness brightness = Brightness.light,
  bool paper = false,
}) {
  final defaultTheme = AppFlowyDefaultTheme();
  final baseAppFlowyTheme = brightness == Brightness.dark
      ? defaultTheme.dark()
      : defaultTheme.light();
  final appTheme = paper
      ? AppTheme.builtins.firstWhere(
          (theme) => theme.themeName == BuiltInTheme.paper,
        )
      : AppTheme.fallback;
  final materialTheme = DesktopAppearance().getThemeData(
    appTheme,
    brightness,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  final palette = materialTheme.extension<PremiumThemeExtension>()!;
  final appFlowyTheme = PremiumTheme.appFlowyTheme(
    base: baseAppFlowyTheme,
    palette: palette,
    brightness: brightness,
  );
  return MaterialApp(
    theme: materialTheme,
    home: AppFlowyTheme(
      data: appFlowyTheme,
      child: Scaffold(body: child),
    ),
  );
}

Widget _resizedPdfScrollHarness({
  required ScrollController editorScrollController,
  required ValueNotifier<double> width,
  required ValueChanged<PointerSignalEvent> onPointerSignal,
  ValueChanged<PointerPanZoomStartEvent>? onPointerPanZoomStart,
  ValueChanged<PointerPanZoomUpdateEvent>? onPointerPanZoomUpdate,
}) {
  return MaterialApp(
    home: PremiumScrollScope(
      enabled: true,
      child: Center(
        child: SizedBox(
          width: 600,
          height: 300,
          child: SingleChildScrollView(
            controller: editorScrollController,
            child: Column(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: width,
                  builder: (context, value, _) => ResizableMedia(
                    width: value,
                    height: 200,
                    onResize: (value) => width.value = value,
                    onResizeHeight: (_) {},
                    frameBuilder: (frame) => PremiumScrollExclusion(
                      child: PdfEmbedScrollGuard(
                        onPointerSignal: onPointerSignal,
                        onPointerPanZoomStart: onPointerPanZoomStart,
                        onPointerPanZoomUpdate: onPointerPanZoomUpdate,
                        child: frame,
                      ),
                    ),
                    child: const ColoredBox(
                      key: ValueKey('resized-pdf-content'),
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 900),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _sendTrackpadPan(
  WidgetTester tester, {
  required int pointer,
  required Offset position,
}) async {
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(
      pointer: pointer,
      device: pointer,
      position: position,
    ),
  );
  await tester.sendEventToBinding(
    PointerPanZoomUpdateEvent(
      pointer: pointer,
      device: pointer,
      position: position,
      pan: const Offset(0, -80),
      panDelta: const Offset(0, -80),
    ),
  );
  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      pointer: pointer,
      device: pointer,
      position: position,
    ),
  );
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
