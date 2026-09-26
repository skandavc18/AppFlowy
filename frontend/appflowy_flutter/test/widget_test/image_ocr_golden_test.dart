import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'image_ocr_test_support.dart';

const _reference = ValueKey('image-ocr-reference');

// Real OCR overlay, shared find bar, bundled fonts/translations and PNG codec.
// Only image bytes/OCR/clipboard transport are controlled. These three new
// baselines must be generated and reviewed separately; intentionally UNRUN.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  late Map<String, dynamic> translations;
  late bool fontFetching;
  setUpAll(() async {
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    translations = await loadOcrTestTranslations();
    await (FontLoader('DM Sans')
          ..addFont(
            rootBundle.load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
          ))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    png = await makeOcrTestPng(paint: _paintWords);
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);

  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets(
      '$mode: OCR overlay search highlights normalized word positions '
      '(caseSensitive=false)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1080, 760);
        final source = MemoryOcrSource('local-text.png', png);
        final service = ControlledOcrService();
        final clipboard = OcrTestClipboard()..install();
        ui.Image? decoded;
        try {
          await tester.pumpWidget(
            ocrTestApp(
              RepaintBoundary(
                key: _reference,
                child: ImageOcrOverlay(
                  source: source,
                  name: 'Local image search',
                  find: true,
                  service: service,
                ),
              ),
              mode: mode,
              fontFamily: 'DM Sans',
              translations: translations,
            ),
          );
          await waitForOcrCalls(tester, service, 1);
          expect(service.calls.single.bytes, png);
          expect(service.calls.single.imageSize, const Size(320, 180));
          service.calls.single.done.complete(ocrTestResult());
          await tester.pump();
          await tester.pump();
          await tester.enterText(
            find.byKey(const ValueKey('findTextField')),
            'WoRlD',
          );
          await tester.pump();
          await tester.pump();
          final bar =
              tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));
          // No blinking caret in the reference image; keep the actual query.
          bar.findFocusNode.unfocus();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          final context = tester.element(find.byType(ImageOcrOverlay));
          expect(Theme.of(context).textTheme.bodyMedium!.fontFamily, 'DM Sans');
          expect(
            Theme.of(context).brightness,
            mode == 'dark' ? Brightness.dark : Brightness.light,
          );
          expect(PaperTheme.isEnabled(context), mode == 'paper');
          expect(bar.findController.text, 'WoRlD');
          expect(bar.options.caseSensitive, isFalse);
          expect(bar.matchCount, 2);
          expect(bar.currentMatch, 1);
          // These labels come from the real en-US asset, not a stub dictionary.
          expect(find.byTooltip('Case sensitive'), findsOneWidget);
          expect(find.text('1 of 2'), findsOneWidget);

          final highlights = find.byKey(const ValueKey('image-ocr-highlights'));
          final painter = tester
              .widget<CustomPaint>(highlights)
              .foregroundPainter! as OcrHighlightPainter;
          expect(painter.boxes, const [
            Rect.fromLTWH(.1, .15, .2, .15),
            Rect.fromLTWH(.5, .15, .25, .15),
            Rect.fromLTWH(.1, .6, .2, .15),
            Rect.fromLTWH(.5, .6, .35, .15),
          ]);
          expect(painter.matched, {1, 3});
          expect(painter.active, {1});
          expect(painter.selected, {1});
          final photo =
              tester.getRect(find.byKey(const ValueKey('image-ocr-photo')));
          expect(tester.getRect(highlights), photo);
          expect(photo.size.aspectRatio, closeTo(320 / 180, .0001));
          decoded = tester.widget<RawImage>(find.byType(RawImage)).image!;
          expect(decoded.debugDisposed, isFalse);
          expect(source.reads, 1);
          expect(clipboard.writes, isEmpty);
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_reference),
            matchesGoldenFile('goldens/image_ocr_find_$mode.png'),
          );
        } finally {
          clipboard.release();
          await tester.pumpWidget(const SizedBox.shrink());
          service.finishPending();
          await tester.pump();
          clipboard.uninstall();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          if (decoded != null) expect(decoded.debugDisposed, isTrue);
          expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
          expect(tester.takeException(), isNull);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

void _paintWords(Canvas canvas, Size size) {
  for (final line in ocrTestResult().lines) {
    for (final word in line.words) {
      final text = TextPainter(
        text: TextSpan(
          text: word.text,
          style: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 18,
            height: 1.2,
            color: Color(0xFF342B23),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      );
      try {
        text.layout(maxWidth: word.bounds.width * size.width);
        text.paint(
          canvas,
          Offset(
            word.bounds.left * size.width,
            word.bounds.top * size.height,
          ),
        );
      } finally {
        text.dispose();
      }
    }
  }
}
