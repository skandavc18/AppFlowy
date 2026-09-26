import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_theme.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../test/widget_test/chart_appearance_test_support.dart';
import '../../test/widget_test/chart_find_native_fixture.dart';

// Separate opt-in Windows entrypoint: no main/shared-base/Rust/workspace boot.
// Reuses MaterialApp, DesktopAppearance, AppFlowyTheme, mock SharedPreferences,
// bundled fonts and real TestBundleAssetLoader translations, not fake engines.
// Ctrl+F/text entry exercise Flutter-host routing, NOT OS-to-DOM key delivery.
// Captures are component review sheets, not goldens or native-window screenshots.
const _ocrLimit = Duration(seconds: 110);
const _ocrHelp = 'Install a Windows OCR language pack for the display language '
    '(including English), and ensure Windows PowerShell/WinRT OCR is available. '
    'A missing engine is a failure, not a skipped smoke test.';
int _outerFinds = 0;

void main() {
  const enabled = bool.fromEnvironment('CHART_FIND_FIXTURE');
  const root = String.fromEnvironment('CHART_FIND_PROJECT_ROOT');
  if (!enabled ||
      !Platform.isWindows ||
      !p.isAbsolute(root) ||
      !File(p.join(root, 'pubspec.yaml')).existsSync() ||
      !File(
        p.join(
          root,
          'test',
          'widget_test',
          'chart_find_native_fixture.dart',
        ),
      ).existsSync()) {
    throw StateError('Requires Windows, CHART_FIND_FIXTURE=true and absolute '
        'CHART_FIND_PROJECT_ROOT pointing to frontend/appflowy_flutter.');
  }
  // Must precede the reusable widget fixture's binding initialization.
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpChartAppearanceFixtures();
  final fixture = NativeFindFixture();
  setUpAll(() => fixture.initialize(root));
  tearDownAll(fixture.dispose);

  void nativeTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(
      name,
      (tester) async {
        _outerFinds = 0;
        // IntegrationTest deliberately does not register this by default.
        // Only Flutter text input is controlled; no native plugin is mocked.
        tester.testTextInput.register();
        try {
          await binding.setSurfaceSize(const Size(1100, 900));
          await body(tester);
          expect(
            _outerFinds,
            0,
            reason: 'The surrounding document must not find.',
          );
          expect(tester.takeException(), isNull);
        } finally {
          try {
            await _unmount(tester);
            await _until(
              tester,
              () => fixture.scansClosed,
              'Cancelled OCR must reap its process and delete owned scratch.',
              timeout: const Duration(seconds: 15),
            );
          } finally {
            tester.testTextInput.unregister();
            await binding.setSurfaceSize(null);
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }

  nativeTest('Windows OCR bytes, image matches and three themed chart sheets',
      (tester) async {
    // Mount the actual popup content directly so its one native scan survives
    // theme changes. This is not a popup-route dismissal or clipboard test.
    final overlay = ImageOcrOverlay(
      source: ImageEditorSource(
        url: fixture.image.path,
        type: CustomImageType.local,
      ),
      name: 'Synthetic image',
      find: true,
    );
    await _mount(tester, 'light', overlay);
    expect(
      tester.widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay)).service,
      isNull,
      reason: 'Default OcrService.recognizeBytes must really run.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('findTextField')),
      'search',
    );
    await _until(
      tester,
      () => !_bar(tester).busy,
      _ocrHelp,
      timeout: _ocrLimit,
    );
    final status = tester
        .widget<Text>(
          find.byKey(const ValueKey('image-ocr-status')),
        )
        .data!;
    expect(status, contains('Windows OCR'), reason: _ocrHelp);
    expect(_bar(tester).matchCount, 1, reason: '$status. $_ocrHelp');
    expect(_bar(tester).currentMatch, 1);
    expect(_bar(tester).options.caseSensitive, isFalse);
    final row = find.byKey(const ValueKey('image-ocr-row-0'));
    final recognized = tester
        .widgetList<Text>(
          find.descendant(of: row, matching: find.byType(Text)),
        )
        .map((text) => text.data ?? '')
        .join(' ');
    expect(
      recognized.toLowerCase(),
      contains('search'),
    ); // Not engine punctuation.
    await tester.tap(row); // Select only; deliberately never invoke Copy.
    await tester.pump();
    final paint = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('image-ocr-highlights')),
        )
        .foregroundPainter! as OcrHighlightPainter;
    expect(paint.matched, isNotEmpty);
    expect(paint.active, isNotEmpty);
    expect(paint.selected, isNotEmpty);
    final state = tester.state(find.byType(ImageOcrOverlay));
    for (final appearance in chartAppearances) {
      await _mount(tester, appearance, overlay);
      expect(tester.state(find.byType(ImageOcrOverlay)), same(state));
      expect(_bar(tester).matchCount, 1);
      await _capture(tester, fixture, 'image-$appearance.png');
    }
  });

  nativeTest('PDFium text then automatic scanned-page OCR and painted match',
      (tester) async {
    final ref = NativeFindDocumentRef(fixture.pdf);
    final handle = ref.resolveListenable();
    final preview = PdfPreview(
      file: fixture.pdf,
      name: 'Synthetic PDF',
      sourceDocumentRef: ref,
      metadata: const {'pageTransition': 'none'},
      editable: false,
      onMetadataChanged: (_) => fail('Find must not persist PDF metadata.'),
    );
    try {
      await _mount(tester, 'light', preview);
      await _until(
        tester,
        () => tester
            .widget<PdfPreviewToolbar>(find.byType(PdfPreviewToolbar))
            .ready,
        'PDFium must load two synthetic pages; check the Windows pdfrx bundle.',
      );
      expect(handle.document!.pages.length, 2);
      expect(
        (await handle.document!.pages[1]
                .loadText()
                .timeout(const Duration(seconds: 10)))
            .fullText
            .trim(),
        isEmpty,
        reason: 'Page two must be a bitmap, not a hidden text layer.',
      );
      await _hoverFind(tester, find.byType(PdfViewer));
      await tester.enterText(
        find.byKey(const ValueKey('pdf-search-field')),
        'alpha',
      );
      await _until(
        tester,
        () => !_pdfBar(tester).isSearching && _pdfBar(tester).matchCount == 2,
        'Native PDF search must find Alpha and alpha.',
      );
      expect(_pdfBar(tester).controller.text, 'alpha');
      expect(_pdfBar(tester).options.caseSensitive, isFalse);
      expect(_pdfBar(tester).ocrEnabled, isFalse);
      final viewerState = tester.state(find.byType(PdfViewer));
      await tester.enterText(
        find.byKey(const ValueKey('pdf-search-field')),
        'search',
      );
      await _until(
        tester,
        () =>
            !_pdfBar(tester).isSearching &&
            _pdfBar(tester).ocrEnabled &&
            _pdfBar(tester).matchCount == 1,
        'Automatic OCR must find Search on the bitmap page. $_ocrHelp',
        timeout: _ocrLimit,
      );
      expect(_pdfBar(tester).currentMatch, 1);
      expect(_pdfBar(tester).statusOverride, isNull);
      expect(
        _pdfBar(tester).onCopyMatch,
        isNotNull,
      ); // OCR hit, no clipboard write.
      expect(
        find.byKey(const ValueKey('pdf-search-copy-match')),
        findsOneWidget,
      );
      for (final appearance in chartAppearances) {
        await _mount(tester, appearance, preview);
        expect(tester.state(find.byType(PdfViewer)), same(viewerState));
        expect(_pdfBar(tester).matchCount, 1);
        final controller =
            tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
        final page = controller.layout.pageLayouts[1];
        final visiblePage = Rect.fromPoints(
          controller.documentToGlobal(page.topLeft)!,
          controller.documentToGlobal(page.bottomRight)!,
        ).intersect(tester.getRect(find.byType(PdfViewer)));
        final palette =
            PdfPreviewPalette.of(tester.element(find.byType(PdfPreview)));
        await _until(
          tester,
          () => nativeFindSnapshot(
            tester,
            globalRegion: visiblePage,
            ink: Color.alphaBlend(palette.activeSearchMatch, Colors.white),
          ),
          'The visible bitmap page must paint the active OCR highlight.',
        );
        await _capture(tester, fixture, 'pdf-$appearance.png');
      }
    } finally {
      await _unmount(tester);
      await _until(
        tester,
        () => handle.document == null,
        'PDF renderer/search leases must release before native disposal.',
        timeout: const Duration(seconds: 15),
      );
      await ref
          .close(); // Never forcibly dispose while a native lease survives.
    }
  });

  nativeTest(
      'WebView2 loopback HTML, real isolated-world counts and case option',
      (tester) async {
    await _mount(
      tester,
      'paper',
      FilePreview(
        file: fixture.html,
        name: 'Synthetic HTML',
        kind: FilePreviewKind.html,
        metadata: const {},
        editable: false,
        bare: true,
        onMetadataChanged: (_) => fail('Find must not persist HTML metadata.'),
      ),
    );
    final owner = find.byWidgetPredicate(
      (widget) =>
          widget is ContextualFindRegion && widget.debugLabel == 'HTML file',
    );
    await _until(
      tester,
      () => owner.evaluate().length == 1,
      'The real HTML file preview must mount.',
    );
    await _hoverFind(tester, owner);
    // Deliberately do not wait for onLoadStop before typing. No callbacks are
    // invoked by the test; a slow load must replay this query. A fast load may
    // already be ready, so this is not a deterministic pre-load timing proof.
    await tester.enterText(
      find.byKey(const ValueKey('findTextField')),
      'hello world',
    );
    await _until(
      tester,
      () => !_bar(tester).busy && _bar(tester).matchCount == 2,
      'WebView2 must return two DOM matches across <b>; install its Windows '
      'runtime and check the real CDP/content-world transport (30s deadline).',
    );
    final webview = tester.widget<InAppWebView>(find.byType(InAppWebView));
    final url = webview.platform.params.initialUrlRequest!.url!;
    expect(url.host, '127.0.0.1');
    expect(url.scheme, 'http');
    expect(
      fixture.isolatedProfileCreated,
      isTrue,
      reason: 'WebView2 must use the synthetic run directory, not user data.',
    );
    expect(_bar(tester).options.caseSensitive, isFalse);
    await tester.tap(
      find.descendant(
        of: find.byType(FindReplaceBar),
        matching: find.text('Aa'),
      ),
    );
    await _until(
      tester,
      () => !_bar(tester).busy && _bar(tester).matchCount == 1,
      'Case-sensitive DOM find must retain only lowercase hello world.',
    );
    expect(_bar(tester).options.caseSensitive, isTrue);
    expect(_bar(tester).findController.text, 'hello world');
    // No WebView screenshot claim: toImage need not contain platform textures.
  });
}

FindReplaceBar _bar(WidgetTester tester) =>
    tester.widget(find.byType(FindReplaceBar));
PdfSearchToolbar _pdfBar(WidgetTester tester) =>
    tester.widget(find.byType(PdfSearchToolbar));

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  Widget child,
) async {
  final spec = chartAppearanceSpec(ChartType.bar, showLegend: false);
  await tester.pumpWidget(
    chartAppearanceApp(
      appearance,
      Builder(
        builder: (context) => RepaintBoundary(
          key: nativeFindCapture,
          child: ColoredBox(
            color: EditorSurfaceStyle.canvasBackground(context),
            child: ContextualFindRegion(
              onFind: () => _outerFinds++,
              debugLabel: 'Synthetic outer document',
              child: Focus(
                autofocus: true,
                child: Column(
                  children: [
                    SizedBox(
                      height: 150,
                      child: AppChart(
                        data: buildChartData(chartAppearanceTable, spec),
                        spec: chartAppearanceTable.displaySpec(spec),
                        palette: chartPaletteOf(context),
                        animate: false,
                      ),
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      reducedMotion: true,
    ),
  );
  await _until(
    tester,
    () => find.byType(AppChart).evaluate().length == 1,
    'Bundled translations and themed component host must load.',
  );
  expect(
    PaperTheme.isEnabled(tester.element(find.byType(AppChart))),
    appearance == 'paper',
  );
  expect(chartAppearancePainter(tester).hits, isNotEmpty);
}

Future<void> _until(
  WidgetTester tester,
  FutureOr<bool> Function() ready,
  String reason, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final clock = Stopwatch()..start();
  do {
    // Real elapsed time, not a guessed motion delay or pumpAndSettle: native
    // completions, debounce, blinking carets and progress tickers may coexist.
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull, reason: reason);
    final remaining = timeout - clock.elapsed;
    if (remaining <= Duration.zero) break;
    if (await Future<bool>.sync(ready)
        .timeout(remaining, onTimeout: () => false)) {
      return;
    }
  } while (clock.elapsed < timeout);
  fail(reason);
}

Future<void> _hoverFind(WidgetTester tester, Finder surface) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  try {
    await mouse.addPointer(location: tester.getCenter(surface));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    try {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.pump();
    expect(_outerFinds, 0);
  } finally {
    await mouse.removePointer();
  }
}

Future<void> _capture(
  WidgetTester tester,
  NativeFindFixture fixture,
  String name,
) async {
  await tester.pump();
  await nativeFindSnapshot(
    tester,
    output: File(p.join(fixture.output.path, name)),
  );
}

Future<void> _unmount(WidgetTester tester) async {
  for (final field
      in tester.stateList<EditableTextState>(find.byType(EditableText))) {
    field.hideToolbar();
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
}
