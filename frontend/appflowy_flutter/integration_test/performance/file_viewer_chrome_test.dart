import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_theme.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_toolbar.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart' show PdfViewer;
import 'package:window_manager/window_manager.dart';

// Real workspace file viewers and native PDF rendering, but no application
// startup, backend, preferences or user documents. Captures are opt-in.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'file chrome stays docked in light, dark and paper',
    (tester) async {
      final root =
          await Directory.systemTemp.createTemp('appflowy_viewer_chrome_');
      final pdf = File(p.join(root.path, 'A calmer workspace.pdf'));
      final text = File(p.join(root.path, 'Reading notes.txt'));
      final image = File(p.join(root.path, 'Landscape.png'));
      await pdf.writeAsBytes(_pdf());
      await text.writeAsString(
        List.generate(
          90,
          (i) => 'Line ${i + 1}   A place for ideas, notes and discoveries.',
        ).join('\n'),
      );
      await image.writeAsBytes(await _image());
      final views = [pdf, text, image].map(_view).toList();
      final selection = ValueNotifier(
        (
          appearance: 0,
          file: 0,
          width: 1100.0,
          reducedMotion: false,
        ),
      );
      final captureKey = GlobalKey();
      final samples = <Map<String, Object>>[];
      binding.reportData = {
        'run': const String.fromEnvironment(
          'PERF_RUN',
          defaultValue: 'file_viewer_chrome',
        ),
        'samples': samples,
      };
      try {
        await windowManager.ensureInitialized();
        await windowManager.setSize(const Size(1250, 850));
        await windowManager.show();
        await tester.pumpWidget(
          ValueListenableBuilder(
            valueListenable: selection,
            builder: (_, value, __) => _app(
              appearance: value.appearance,
              reducedMotion: value.reducedMotion,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: value.width,
                  child: RepaintBoundary(
                    key: captureKey,
                    child: Builder(
                      builder: (context) => ColoredBox(
                        // Include the inherited workspace surface in captures.
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: WorkspaceFileView(
                          key: ValueKey(views[value.file].id),
                          view: views[value.file],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (var appearance = 0; appearance < 3; appearance++) {
          for (var file = 0; file < views.length; file++) {
            selection.value = (
              appearance: appearance,
              file: file,
              width: 1100,
              reducedMotion: false,
            );
            await _waitFor(tester, () {
              if (find.byType(DocumentViewportHeader).evaluate().length != 1) {
                return false;
              }
              if (file == 0) {
                final viewer = find.byType(PdfViewer);
                return viewer.evaluate().length == 1 &&
                    tester.widget<PdfViewer>(viewer).controller!.isReady;
              }
              if (file == 2) {
                return find.byType(RawImage).evaluate().any(
                      (element) => (element.widget as RawImage).image != null,
                    );
              }
              return find.byType(SelectableText).evaluate().isNotEmpty;
            });
            await tester.pump(const Duration(milliseconds: 400));
            final headerFinder = find.byType(DocumentViewportHeader);
            final header = tester.getRect(headerFinder);
            final bounds = tester.getRect(find.byType(WorkspaceFileView));
            expect(header.topLeft, bounds.topLeft);
            expect(header.width, bounds.width);
            expect(find.byType(BackdropFilter), findsNothing);
            final style =
                DocumentViewportStyle.of(tester.element(headerFinder));
            expect(style.chrome.a, 1);
            expect(style.chromeShadow, isEmpty);
            if (appearance == 2) {
              expect(style.chrome, PaperTheme.editorPreviewBackground);
            }
            final bar = tester
                .widget<DocumentViewportBar>(find.byType(DocumentViewportBar));
            final barSurface = tester.widget<Container>(
              find
                  .descendant(
                    of: find.byType(DocumentViewportBar),
                    matching: find.byType(Container),
                  )
                  .first,
            );
            expect(barSurface.decoration, isNull);
            expect(
              barSurface.color,
              file == 0
                  ? PdfPreviewPalette.of(tester.element(headerFinder)).canvas
                  : file == 2
                      ? Theme.of(tester.element(headerFinder))
                          .scaffoldBackgroundColor
                      : style.canvas,
            );
            expect(bar.background, barSurface.color);
            await _capture(captureKey, '$appearance-$file');

            if (file == 0) {
              final viewerFinder = find.byType(PdfViewer);
              final viewerElement = tester.element(viewerFinder);
              final controller =
                  tester.widget<PdfViewer>(viewerFinder).controller!;
              await tester.tap(find.text('Fit'));
              await tester.pumpAndSettle();
              final fitZoom = controller.currentZoom;
              final fitMatrix = controller.calcMatrixForFit(
                pageNumber: controller.pageNumber ?? 1,
              );
              expect(fitMatrix, isNotNull);
              // This is a 2D zoom; an unscaled Z axis is not the page scale.
              expect(fitZoom, closeTo(fitMatrix!.entry(0, 0), 0.001));
              await tester.tap(find.byTooltip('Fit options'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('Fit to width'));
              await tester.pumpAndSettle();
              expect(controller.currentZoom, greaterThan(fitZoom));
              expect(
                tester.getRect(viewerFinder).top,
                greaterThanOrEqualTo(header.bottom),
              );
              final before = controller.value.clone();
              await tester.sendEventToBinding(
                PointerScrollEvent(
                  position: tester.getCenter(viewerFinder),
                  scrollDelta: const Offset(0, 160),
                ),
              );
              await tester.pump(const Duration(milliseconds: 400));
              expect(controller.value, isNot(before));
              // Old stored auto-hide=true must never hide a normal file toolbar.
              await tester.pump(const Duration(seconds: 4));
              expect(tester.getRect(headerFinder), header);
              await tester.tap(find.byTooltip('Search document (Ctrl/Cmd F)'));
              await tester.pumpAndSettle();
              expect(find.byType(PdfSearchToolbar), findsOneWidget);
              expect(tester.element(viewerFinder), same(viewerElement));
              expect(
                tester.getRect(viewerFinder).top,
                greaterThanOrEqualTo(
                  tester.getRect(find.byType(PdfSearchToolbar)).bottom,
                ),
              );
              await _capture(captureKey, '$appearance-pdf-search');
              await tester.tap(find.byTooltip('Close search (Esc)'));
              await tester.pumpAndSettle();
              selection.value = (
                appearance: appearance,
                file: file,
                width: 360,
                reducedMotion: false,
              );
              await tester.pumpAndSettle();
              expect(tester.element(viewerFinder), same(viewerElement));
              expect(controller.isReady, isTrue);
              expect(
                tester.getRect(headerFinder).height,
                greaterThan(header.height),
              );
              await _capture(captureKey, '$appearance-pdf-compact');
            } else if (file == 1) {
              final scrollable = find.descendant(
                of: find.byType(SelectableText),
                matching: find.byType(Scrollable),
              );
              // SelectableText's own field is not the outer reading scroll view.
              expect(scrollable, findsOneWidget);
              final reading = tester
                  .element(find.byType(SelectableText))
                  .findAncestorStateOfType<ScrollableState>()!;
              reading.position.jumpTo(500);
              await tester.pump();
              expect(reading.position.pixels, 500);
              expect(tester.getRect(headerFinder), header);
            } else {
              final viewer = tester
                  .widget<InteractiveViewer>(find.byType(InteractiveViewer));
              final transform = viewer.transformationController!;
              transform.value = Matrix4.identity()
                ..translate(-80.0, -40.0)
                ..scale(2.0);
              await tester.pump();
              final zoomed = transform.value.clone();
              await tester.tap(find.byTooltip('Fit to view'));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 60));
              expect(
                transform.value.getMaxScaleOnAxis(),
                lessThan(zoomed.getMaxScaleOnAxis()),
              );
              expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
              await tester.pumpAndSettle();
              expect(transform.value, Matrix4.identity());
              expect(tester.getRect(headerFinder), header);

              transform.value = zoomed.clone();
              await tester.tap(find.byTooltip('Fit to view'));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 40));
              final gesture = await tester.startGesture(
                tester.getCenter(find.byType(InteractiveViewer)),
                kind: PointerDeviceKind.mouse,
              );
              final interrupted = transform.value.clone();
              await tester.pump(const Duration(milliseconds: 300));
              expect(transform.value, interrupted);
              await gesture.up();

              // Exercise the real InteractiveViewer's scale-inertia path via
              // its wired callbacks, without moving the physical pointer.
              final imageViewport = find.byType(InteractiveViewer);
              final detector = tester
                  .widgetList<GestureDetector>(
                    find.descendant(
                      of: imageViewport,
                      matching: find.byType(GestureDetector),
                    ),
                  )
                  .firstWhere((widget) => widget.onScaleUpdate != null);
              final local = tester.getSize(imageViewport).center(Offset.zero);
              final global = tester.getTopLeft(imageViewport) + local;
              detector.onScaleStart!(
                ScaleStartDetails(
                  focalPoint: global,
                  localFocalPoint: local,
                ),
              );
              detector.onScaleUpdate!(
                ScaleUpdateDetails(
                  focalPoint: global,
                  localFocalPoint: local,
                  scale: 1.2,
                ),
              );
              final releasedScale = transform.value.getMaxScaleOnAxis();
              detector.onScaleEnd!(ScaleEndDetails(scaleVelocity: 12));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 30));
              expect(
                transform.value.getMaxScaleOnAxis(),
                greaterThan(releasedScale),
              );
              await tester.tap(find.byTooltip('Fit to view'));
              await tester.pumpAndSettle();
              await tester.pump(const Duration(milliseconds: 400));
              expect(transform.value, Matrix4.identity());

              selection.value = (
                appearance: appearance,
                file: file,
                width: 1100,
                reducedMotion: true,
              );
              await tester.pump();
              transform.value = zoomed.clone();
              await tester.tap(find.byTooltip('Fit to view'));
              expect(transform.value, Matrix4.identity());
              await tester.pump();
            }
            expect(tester.takeException(), isNull);
            samples.add({
              'appearance': ['light', 'dark', 'paper'][appearance],
              'kind': ['pdf', 'text', 'image'][file],
              'headerHeight': header.height,
              'headerWidth': header.width,
              'docked': true,
            });
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        selection.dispose();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

ViewPB _view(File file) => ViewPB()
  ..id = 'fixture-${p.basename(file.path)}'
  ..name = p.basename(file.path)
  ..layout = ViewLayoutPB.Document
  ..extra = WorkspaceFilePreviewCodec.merge(
    WorkspaceItemMetadata.file(
      contentKind: WorkspaceFileContentKind.binary,
      storageUrl: file.path,
    ).mergeIntoExtra(''),
    const {'autoHideToolbar': true, filePreviewEditModeKey: false},
  );

Widget _app({
  required int appearance,
  required Widget child,
  required bool reducedMotion,
}) {
  final brightness = appearance == 1 ? Brightness.dark : Brightness.light;
  final appTheme = appearance == 2
      ? AppTheme.builtins
          .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
      : AppTheme.fallback;
  final theme = DesktopAppearance().getThemeData(
    appTheme,
    brightness,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  final base = AppFlowyDefaultTheme();
  return MaterialApp(
    theme: theme,
    themeAnimationDuration: Duration.zero,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
      child: child!,
    ),
    home: AppFlowyTheme(
      data: PremiumTheme.appFlowyTheme(
        base: brightness == Brightness.dark ? base.dark() : base.light(),
        palette: theme.extension<PremiumThemeExtension>()!,
        brightness: brightness,
      ),
      child: Scaffold(body: PremiumScrollScope(enabled: true, child: child)),
    ),
  );
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 40));
    if (ready()) return;
  }
  throw StateError('The native file viewer did not become ready.');
}

Future<void> _capture(GlobalKey key, String name) async {
  const output = String.fromEnvironment('CHROME_CAPTURE_DIR');
  if (output.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File(p.join(output, 'viewer-chrome-$name.png'))
        .writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

Future<List<int>> _image() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const bounds = Rect.fromLTWH(0, 0, 720, 420);
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF426E71), Color(0xFFB9D2C5)],
      ).createShader(bounds),
  );
  canvas.drawCircle(
    const Offset(540, 112),
    48,
    Paint()..color = const Color(0xFFF5DEAC),
  );
  final hill = Path()
    ..moveTo(0, 330)
    ..quadraticBezierTo(190, 125, 430, 325)
    ..quadraticBezierTo(580, 170, 720, 300)
    ..lineTo(720, 420)
    ..lineTo(0, 420)
    ..close();
  canvas.drawPath(hill, Paint()..color = const Color(0xFF305251));
  final picture = recorder.endRecording();
  final image = await picture.toImage(720, 420);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

List<int> _pdf() {
  const content = '0.18 0.23 0.25 rg BT /F1 28 Tf 48 710 Td '
      '(A calmer workspace) Tj 0 -42 Td /F1 13 Tf '
      '(Read, explore and create without the clutter.) Tj '
      '0 -48 Td (One fixed toolbar. More room for your documents.) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>',
    for (var i = 0; i < 3; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
          '/Resources << /Font << /F1 6 0 R >> >> /Contents 7 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final text = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(text.length);
    text.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = text.length;
  text.write('xref\n0 8\n0000000000 65535 f \n');
  for (final offset in offsets) {
    text.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  text.write('trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return utf8.encode(text.toString());
}
