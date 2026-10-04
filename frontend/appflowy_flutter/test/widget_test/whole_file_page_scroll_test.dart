import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_scope.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'file_controls_test_support.dart';

void main() {
  fileControlTestSetup();
  for (final reduced in [false, true]) {
    for (final pan in [false, true]) {
      testWidgets(
          'page-break PDF Premium root reduced=$reduced pan=$pan: header before turn',
          (tester) async {
        final originalFactory = PdfDocumentFactory.instance;
        final factory = _Factory();
        PdfDocumentFactory.instance = factory;
        final chrome = StandaloneFileChromeController();
        final file = File('C:/synthetic-not-read/paged-flow.pdf');
        final ref = PdfDocumentRefFile(file.path);
        final release = ref.resolveListenable().addListener(() {});
        await ref.resolveListenable().load();
        try {
          await mountFileControls(
            tester,
            PremiumScrollScope(
              enabled: true,
              child: StandaloneFileScope(
                canvas: Colors.transparent,
                rendererName: 'paged-flow.pdf',
                displayName: 'paged-flow.pdf',
                chrome: chrome,
                canEdit: () => false,
                canRead: () => true,
                editable: false,
                available: true,
                child: StandaloneFilePage(
                  header: const SizedBox(
                    height: 240,
                    child: Text('PDF identity'),
                  ),
                  body: PdfPreview(
                    file: file,
                    name: 'paged-flow.pdf',
                    metadata: const {
                      'layoutMode': 'pageBreak',
                      'pageTransition': 'none',
                    },
                    sourceDocumentRef: ref,
                    editable: false,
                    onMetadataChanged: (_) {},
                  ),
                ),
              ),
            ),
            reduced: reduced,
          );
          await tester.pumpAndSettle();
          final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
          final controller = viewer.controller!;
          expect(controller.isReady, isTrue);
          // At first-page Fit, reverse is a verified page boundary, not just
          // an arbitrary matrix position on a later fitted page.
          await controller.goTo(
            Matrix4.diagonal3Values(.5, .5, 1),
            duration: Duration.zero,
          );
          await tester.pumpAndSettle();
          final page = tester
              .state<NestedScrollViewState>(find.byType(NestedScrollView));
          final start = controller.value.clone();
          final point = tester
                  .getRect(find.byType(PdfViewer))
                  .intersect(tester.getRect(find.byType(StandaloneFilePage)))
                  .bottomCenter -
              const Offset(0, 24);
          final gesture = pan
              ? await tester.createGesture(kind: PointerDeviceKind.trackpad)
              : null;
          if (gesture != null) await gesture.panZoomStart(point);
          var total = 0.0;
          Future<void> move(double delta) async {
            total += delta;
            if (gesture != null) {
              await gesture.panZoomUpdate(point, pan: Offset(0, -total));
            } else {
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  position: point,
                  scrollDelta: Offset(0, delta),
                ),
              );
            }
            await tester.pump();
          }

          await move(60); // Exceeds the pager threshold, but not the header.
          expect(page.outerController.offset, closeTo(60, .01));
          expect(controller.value, start);
          await move(-20);
          expect(page.outerController.offset, closeTo(40, .01));
          expect(controller.value, start);
          if (gesture != null) {
            final zoom = controller.currentZoom;
            await gesture.panZoomUpdate(
              point,
              pan: Offset(0, -total),
              scale: 1.2,
            );
            await tester.pump();
            expect(controller.currentZoom, greaterThan(zoom));
            expect(page.outerController.offset, closeTo(40, .01));
            await gesture.panZoomEnd();
          }
          expect(
            tester.widget<PdfViewer>(find.byType(PdfViewer)).controller,
            same(controller),
          );
          expect(factory.opens, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await unmountFileControls(tester);
          release();
          chrome.dispose();
          PdfDocumentFactory.instance = originalFactory;
        }
      });
    }
  }
  for (final theme in fileControlAppearances) {
    for (final pan in [false, true]) {
      testWidgets(
          '$theme: actual code body ${pan ? 'pan' : 'wheel'} consumes header then residual',
          (tester) async {
        final file =
            MemoryCodeFile(List.generate(400, (i) => 'print($i)').join('\n'));
        final backend = FileControlBackend(
          fileControlView('flow', 'flow.py', file.path),
          file,
        );
        await mountFileControls(
          tester,
          backend.viewer(),
          mode: theme,
          width: 800,
          reduced: true,
        );
        final fieldFinder =
            find.byWidgetPredicate((w) => w is TextField && w.expands);
        final field = tester.widget<TextField>(fieldFinder);
        final native = tester.state(
          find.descendant(
            of: fieldFinder,
            matching: find.byType(EditableText),
          ),
        );
        final runner = tester.state(find.byType(SandboxedCodeRunner));
        final page = tester.state<NestedScrollViewState>(
          find.byKey(const ValueKey('workspace-file-page-scroll')),
        );
        final header = find.byKey(
          const ValueKey('workspace-file-identity'),
          skipOffstage: false,
        );
        final initial = tester.getRect(header);
        final extent = page.outerController.position.maxScrollExtent;
        final selection = const TextSelection(baseOffset: 1, extentOffset: 7);
        field.controller!.selection = selection;
        final region = tester
            .getRect(fieldFinder)
            .intersect(tester.getRect(find.byType(StandaloneFilePage)));
        expect(region.height, greaterThan(40));
        final point = Offset(region.center.dx, region.bottom - 24);
        final gesture = pan
            ? await tester.createGesture(kind: PointerDeviceKind.trackpad)
            : null;
        if (gesture != null) await gesture.panZoomStart(point);
        var total = 0.0;
        Future<void> move(double delta) async {
          total += delta;
          if (gesture != null) {
            await gesture.panZoomUpdate(point, pan: Offset(0, -total));
          } else {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: point,
                scrollDelta: Offset(0, delta),
              ),
            );
          }
          await tester.pump();
        }

        await move(40);
        expect(page.outerController.offset, closeTo(40, .01));
        expect(field.scrollController!.offset, 0);
        await move(extent + 80 - 40);
        expect(page.outerController.offset, closeTo(extent, .01));
        expect(field.scrollController!.offset, closeTo(80, .01));
        expect(tester.getRect(header).top, closeTo(initial.top - extent, .01));
        expect(header.hitTestable(), findsNothing);
        await move(-30);
        expect(field.scrollController!.offset, closeTo(50, .01));
        expect(page.outerController.offset, closeTo(extent, .01));
        await move(-70);
        expect(field.scrollController!.offset, closeTo(0, .01));
        expect(page.outerController.offset, closeTo(extent - 20, .01));
        if (gesture != null) await gesture.panZoomEnd();
        expect(tester.state(find.byType(SandboxedCodeRunner)), same(runner));
        expect(
          tester.state(
            find.descendant(
              of: fieldFinder,
              matching: find.byType(EditableText),
            ),
          ),
          same(native),
        );
        expect(
          tester.widget<TextField>(fieldFinder).controller,
          same(field.controller),
        );
        expect(field.controller!.selection, selection);
        expect(file.reads, 1);
        expect(file.writes, 0);
        expect(backend.loads, 1);
        expect(backend.extraWrites, isEmpty);
        expect(tester.takeException(), isNull);
        await unmountFileControls(tester);
      });
    }
  }

  testWidgets(
      'continuous PDF consumes header before real safe matrix, reverses once',
      (tester) async {
    final originalFactory = PdfDocumentFactory.instance;
    final factory = _Factory();
    PdfDocumentFactory.instance = factory;
    final chrome = StandaloneFileChromeController();
    final file = File('C:/synthetic-not-read/page-flow.pdf');
    final ref = PdfDocumentRefFile(file.path);
    final release = ref.resolveListenable().addListener(() {});
    await ref.resolveListenable().load();
    try {
      await mountFileControls(
        tester,
        StandaloneFileScope(
          canvas: Colors.transparent,
          rendererName: 'page-flow.pdf',
          displayName: 'page-flow.pdf',
          chrome: chrome,
          canEdit: () => false,
          canRead: () => true,
          editable: false,
          available: true,
          child: StandaloneFilePage(
            header:
                const SizedBox(height: 240, child: Text('PDF page identity')),
            body: PdfPreview(
              file: file,
              name: 'page-flow.pdf',
              metadata: const {},
              sourceDocumentRef: ref,
              editable: false,
              onMetadataChanged: (_) {},
            ),
          ),
        ),
        reduced: true,
      );
      await tester.pumpAndSettle();
      final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
      final controller = viewer.controller!;
      expect(controller.isReady, isTrue);
      final matrix = controller.value.clone();
      matrix.setTranslationRaw(matrix.getTranslation().x, 100000, 0);
      controller.value = controller.makeMatrixInSafeRange(matrix);
      await tester.pump();
      final start = controller.value.clone();
      final zoom = controller.currentZoom;
      final page =
          tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
      final bounds = tester
          .getRect(find.byType(PdfViewer))
          .intersect(tester.getRect(find.byType(StandaloneFilePage)));
      final point = Offset(bounds.center.dx, bounds.bottom - 30);
      Future<void> wheel(double delta) async {
        await tester.sendEventToBinding(
          PointerScrollEvent(position: point, scrollDelta: Offset(0, delta)),
        );
        await tester.pump();
      }

      await wheel(100);
      expect(page.outerController.offset, 100);
      expect(controller.value, start);
      await wheel(200);
      expect(page.outerController.offset, 240);
      expect(
        controller.value.getTranslation().y,
        closeTo(start.getTranslation().y - 60, .01),
      );
      await wheel(-80);
      expect(
        controller.value.getTranslation().y,
        closeTo(start.getTranslation().y, .01),
      );
      expect(page.outerController.offset, 220);
      expect(controller.currentZoom, zoom);
      expect(
        tester.widget<PdfViewer>(find.byType(PdfViewer)).controller,
        same(controller),
      );
      expect(factory.opens, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      release();
      chrome.dispose();
      PdfDocumentFactory.instance = originalFactory;
    }
  });
}

class _Factory extends Fake implements PdfDocumentFactory {
  int opens = 0;
  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) async {
    opens++;
    return _Document(filePath);
  }
}

class _Document extends PdfDocument {
  _Document(String path) : super(sourceName: path) {
    pages = List.generate(4, (i) => _Page(this, i + 1));
  }
  @override
  late final List<PdfPage> pages;
  @override
  PdfPermissions? get permissions => null;
  @override
  bool get isEncrypted => false;
  @override
  Future<void> dispose() async {}
  @override
  Future<List<PdfOutlineNode>> loadOutline() async => [];
  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);
}

class _Page extends PdfPage {
  _Page(this.document, this.pageNumber);
  @override
  final PdfDocument document;
  @override
  final int pageNumber;
  @override
  double get width => 600;
  @override
  double get height => 800;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => _Cancel();
  @override
  Future<PdfPageText> loadText() async => _Text(pageNumber);
  @override
  Future<List<PdfLink>> loadLinks({bool compact = false}) async => [];
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    Color? backgroundColor,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async =>
      null;
}

class _Cancel extends PdfPageRenderCancellationToken {
  bool cancelled = false;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  bool get isCanceled => cancelled;
}

class _Text extends PdfPageText {
  _Text(this.pageNumber);
  @override
  final int pageNumber;
  @override
  String get fullText => '';
  @override
  List<PdfPageTextFragment> get fragments => [];
}
