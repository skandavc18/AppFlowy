import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_result.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'image_ocr_test_support.dart';

// Real popup, shared bar, Flutter image codec and platform clipboard API. Only
// image bytes/OCR/clipboard transport are injected. Intentionally UNRUN.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  late bool fontFetching;
  setUpAll(() async {
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    png = await makeOcrTestPng();
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);

  testWidgets(
      'public find API accepts a query before OCR and never auto-copies',
      (tester) async {
    final fixture = _Fixture(png);
    try {
      await fixture.open(tester, initialQuery: 'world');
      expect(_bar(tester).findController.text, 'world');
      expect(_bar(tester).busy, isTrue);
      expect(_bar(tester).currentMatch, 0);
      await _query(tester, 'HELLO');
      await waitForOcrCalls(tester, fixture.service, 1);
      expect(fixture.service.calls.single.bytes, png);
      expect(fixture.service.calls.single.imageSize, const Size(320, 180));
      expect(_status(tester), contains('Test local OCR'));
      fixture.service.calls.single.done.complete(ocrTestResult());
      await tester.pump();
      await tester.pump();
      expect(_bar(tester).options.caseSensitive, isFalse);
      expect(_bar(tester).matchCount, 2);
      expect(_bar(tester).currentMatch, 1);
      expect(_painter(tester).selected, {0});
      expect(_painter(tester).matched, {0, 2});
      expect(_status(tester), '1 of 2 matches · Test local OCR');
      expect(fixture.clipboard.writes, isEmpty);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
      'next/previous, native submit and F3 select matches without copying',
      (tester) async {
    final fixture = _Fixture(png);
    try {
      await fixture.open(tester);
      await fixture.ready(tester);
      await _query(tester, 'world');
      final photo = tester.element(find.byType(RawImage));
      await tester.tap(find.byKey(const ValueKey('findNextMatch')));
      await tester.pump();
      expect(_bar(tester).currentMatch, 2);
      expect(_painter(tester).selected, {3});
      await tester.tap(find.byKey(const ValueKey('findPreviousMatch')));
      await tester.pump();
      expect(_painter(tester).selected, {1});
      _bar(tester).findFocusNode.requestFocus();
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump();
      expect(_bar(tester).currentMatch, 2);
      expect(_bar(tester).findFocusNode.hasFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(_bar(tester).currentMatch, 1);
      expect(tester.element(find.byType(RawImage)), same(photo));
      expect(fixture.clipboard.writes, isEmpty);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
      'find clicks select a word; explicit copy waits for ACK and keeps geometry',
      (tester) async {
    final fixture = _Fixture(png);
    final semantics = tester.ensureSemantics();
    try {
      await fixture.open(tester);
      await fixture.ready(tester);
      await _query(tester, 'world');
      await tester.tapAt(_wordPoint(tester, 0));
      await tester.pump();
      expect(_painter(tester).selected, {0});
      expect(fixture.clipboard.writes, isEmpty);
      final photoBounds = tester.getRect(_photo);
      final ack = fixture.clipboard.acknowledgement = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('image-ocr-copy-selected')));
      await tester.pump();
      expect(fixture.clipboard.writes, ['Hello']);
      expect(find.text('Copying…'), findsOneWidget);
      expect(find.text('Copied'), findsNothing);
      expect(tester.getRect(_photo), photoBounds);
      ack.complete();
      await tester.pump();
      expect(find.text('Copied'), findsOneWidget);
      expect(find.semantics.byLabel('Copied'), findsOneWidget);
      expect(tester.getRect(_photo), photoBounds);
      await tester.pump(const Duration(milliseconds: 1401));
      expect(find.text('Copied'), findsNothing);
    } finally {
      semantics.dispose();
      await fixture.dispose(tester);
    }
  });

  testWidgets('native find-field Ctrl+A/C does not select/copy OCR words',
      (tester) async {
    final fixture = _Fixture(png);
    try {
      await fixture.open(tester);
      await fixture.ready(tester);
      await _query(tester, 'world');
      await ocrChord(tester, LogicalKeyboardKey.keyA);
      expect(
        _bar(tester).findController.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(_painter(tester).selected, {1});
      await ocrChord(tester, LogicalKeyboardKey.keyC);
      expect(fixture.clipboard.writes, ['world']);
      expect(find.text('Copied'), findsNothing);
      expect(_painter(tester).selected, {1});
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('default extraction retains click-to-copy with a real ACK',
      (tester) async {
    final fixture = _Fixture(png);
    try {
      await fixture.open(tester, findMode: false);
      await fixture.ready(tester);
      expect(find.byType(FindReplaceBar), findsNothing);
      expect(_painter(tester).selected, isEmpty);
      expect(_painter(tester).matched, isEmpty);
      final ack = fixture.clipboard.acknowledgement = Completer<void>();
      await tester.tapAt(_wordPoint(tester, 1));
      await tester.pump();
      expect(fixture.clipboard.writes, ['Hello WORLD']);
      expect(_painter(tester).selected, {0, 1});
      expect(find.text('Copied'), findsNothing);
      ack.complete();
      await tester.pump();
      expect(find.text('Copied'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('image-ocr-find')));
      await tester.pump();
      await _query(tester, 'HELLO');
      expect(_bar(tester).matchCount, 2);
      expect(fixture.service.calls, hasLength(1));
      expect(fixture.clipboard.writes, hasLength(1));
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('clipboard failure is honest, sanitized and retryable',
      (tester) async {
    final fixture = _Fixture(png);
    try {
      await fixture.open(tester);
      await fixture.ready(tester);
      await _query(tester, 'hello');
      fixture.clipboard.failure =
          PlatformException(code: 'synthetic', message: 'private path');
      await tester.tap(find.byKey(const ValueKey('image-ocr-copy-selected')));
      await tester.pump();
      expect(find.text('Copied'), findsNothing);
      expect(find.text('Unable to copy text. Try again.'), findsOneWidget);
      expect(find.textContaining('private path'), findsNothing);
      fixture.clipboard.failure = null;
      await tester.tap(find.byKey(const ValueKey('image-ocr-copy-selected')));
      await tester.pump();
      expect(find.text('Copied'), findsOneWidget);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final unavailable in [false, true]) {
    testWidgets(
        'OCR failure (unavailable=$unavailable) keeps query and retries',
        (tester) async {
      final fixture = _Fixture(png);
      try {
        await fixture.open(tester, initialQuery: 'hello');
        await waitForOcrCalls(tester, fixture.service, 1);
        fixture.service.calls.single.done.completeError(
          unavailable
              ? const OcrUnavailableException(
                  'private path',
                  hint: 'private hint',
                )
              : const FileSystemException(
                  'private path',
                  r'C:\private\picture.png',
                ),
        );
        await tester.pump();
        expect(_bar(tester).busy, isFalse);
        expect(_bar(tester).findController.text, 'hello');
        expect(find.textContaining('private'), findsNothing);
        expect(find.byKey(const ValueKey('image-ocr-retry')), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('image-ocr-copy-all')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byKey(const ValueKey('image-ocr-retry')));
        await waitForOcrCalls(tester, fixture.service, 2);
        fixture.service.calls.last.done.complete(ocrTestResult());
        await tester.pump();
        await tester.pump();
        expect(_bar(tester).matchCount, 2);
        expect(fixture.source.reads, 2);
        expect(fixture.clipboard.writes, isEmpty);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
      'new source rejects a slow old result and retires its decoded image',
      (tester) async {
    final fixture = _Fixture(png);
    final source = ValueNotifier<ImageEditorSource>(fixture.source);
    try {
      fixture.clipboard.install();
      await tester.pumpWidget(
        ocrTestApp(
          ValueListenableBuilder<ImageEditorSource>(
            valueListenable: source,
            builder: (_, value, __) => ImageOcrOverlay(
              source: value,
              name: 'Synthetic image',
              find: true,
              initialQuery: 'hello',
              service: fixture.service,
            ),
          ),
        ),
      );
      await waitForOcrCalls(tester, fixture.service, 1);
      final oldImage = tester.widget<RawImage>(find.byType(RawImage)).image!;
      source.value = MemoryOcrSource('new-source.png', png);
      await tester.pump();
      await waitForOcrCalls(tester, fixture.service, 2);
      expect(fixture.service.calls.first.cancellation!.isCancelled, isTrue);
      expect(oldImage.debugDisposed, isTrue);
      fixture.service.calls.first.done
          .complete(ocrTestResult(engine: 'Obsolete'));
      await tester.pump();
      expect(_bar(tester).busy, isTrue);
      expect(_painter(tester).matched, isEmpty);
      fixture.service.calls.last.done
          .complete(ocrTestResult(engine: 'New engine'));
      await tester.pump();
      expect(_status(tester), contains('New engine'));
      expect(_status(tester), isNot(contains('Obsolete')));
      expect(_bar(tester).matchCount, 2);
    } finally {
      await fixture.dispose(tester);
      source.dispose();
    }
  });

  testWidgets(
      'retained row/copy/close callbacks cannot act on a rebound or disposed popup',
      (tester) async {
    final fixture = _Fixture(png);
    final source = ValueNotifier<ImageEditorSource>(fixture.source);
    try {
      fixture.clipboard.install();
      await tester.pumpWidget(
        ocrTestApp(
          ValueListenableBuilder<ImageEditorSource>(
            valueListenable: source,
            builder: (_, value, __) => ImageOcrOverlay(
              source: value,
              name: 'Synthetic image',
              service: fixture.service,
            ),
          ),
        ),
      );
      await fixture.ready(tester);
      final oldCopy = tester
          .widget<IconButton>(find.byKey(const ValueKey('image-ocr-copy-all')))
          .onPressed!;
      final oldClose = tester
          .widget<IconButton>(find.byKey(const ValueKey('image-ocr-close')))
          .onPressed!;
      final oldRow = tester
          .widget<TextButton>(find.byKey(const ValueKey('image-ocr-row-1')))
          .onPressed!;
      source.value = MemoryOcrSource('replacement.png', png);
      await tester.pump();
      await waitForOcrCalls(tester, fixture.service, 2);
      oldCopy();
      oldClose();
      oldRow();
      expect(fixture.clipboard.writes, isEmpty);
      expect(fixture.service.calls.last.cancellation!.isCancelled, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      oldCopy();
      oldClose();
      oldRow();
      await tester.pump();
      expect(fixture.clipboard.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
      source.dispose();
    }
  });

  testWidgets(
      'dispose during byte read never starts OCR or initializes a copy ticker',
      (tester) async {
    final fixture = _Fixture(png);
    final bytes = Completer<Uint8List>();
    try {
      await tester.pumpWidget(
        ocrTestApp(
          ImageOcrOverlay(
            source: MemoryOcrSource('late.png', png, read: () => bytes.future),
            name: 'Late image',
            service: fixture.service,
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      bytes.complete(png);
      await tester.pump();
      expect(fixture.service.calls, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final fail in [false, true]) {
    testWidgets(
        'closing cancels the scan and ignores late ${fail ? 'failure' : 'success'}',
        (tester) async {
      final fixture = _Fixture(png);
      try {
        await fixture.open(tester);
        await waitForOcrCalls(tester, fixture.service, 1);
        final call = fixture.service.calls.single;
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await fixture.closed;
        expect(call.cancellation!.isCancelled, isTrue);
        if (fail) {
          call.done.completeError(StateError('late private failure'));
        } else {
          call.done.complete(ocrTestResult());
        }
        await tester.pump();
        expect(find.byType(ImageOcrOverlay), findsNothing);
        expect(fixture.clipboard.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets('inside panel/bar/photo never closes; actual photo margin does',
      (tester) async {
    final fixture = _Fixture(png);
    try {
      await fixture.open(tester);
      await fixture.ready(tester);
      await _query(tester, 'hello');
      for (final key in ['image-ocr-header', 'image-ocr-panel']) {
        final bounds = tester.getRect(find.byKey(ValueKey(key)));
        await tester.tapAt(bounds.topLeft + const Offset(4, 4));
        await tester.pump();
        expect(find.byType(ImageOcrOverlay), findsOneWidget);
        expect(find.byType(FindReplaceBar), findsOneWidget);
      }
      await tester.tapAt(_wordPoint(tester, 2));
      await tester.pump();
      expect(find.byType(ImageOcrOverlay), findsOneWidget);
      expect(_painter(tester).selected, {2});
      final stage =
          tester.getRect(find.byKey(const ValueKey('image-ocr-stage')));
      final margin = stage.topLeft + const Offset(2, 2);
      expect(tester.getRect(_photo).contains(margin), isFalse);
      await tester.tapAt(margin);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await fixture.closed;
      expect(find.byType(ImageOcrOverlay), findsNothing);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('bar × hides only find; Ctrl+F reopens; Escape closes the popup',
      (tester) async {
    final fixture = _Fixture(png);
    try {
      await fixture.open(tester);
      await fixture.ready(tester);
      await _query(tester, 'hello');
      await tester.tap(find.byKey(const ValueKey('findClose')));
      await tester.pump();
      expect(find.byType(FindReplaceBar), findsNothing);
      expect(find.byType(ImageOcrOverlay), findsOneWidget);
      expect(_painter(tester).matched, isEmpty);
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      expect(find.byType(FindReplaceBar), findsOneWidget);
      expect(fixture.service.calls, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await fixture.closed;
      expect(find.byType(ImageOcrOverlay), findsNothing);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('drag selection and cancellation stay inside the picture',
      (tester) async {
    final fixture = _Fixture(png);
    try {
      await fixture.open(tester);
      await fixture.ready(tester);
      final photo = tester.getRect(_photo);
      final gesture = await tester.startGesture(
        photo.topLeft + const Offset(2, 2),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(8, 8));
      await tester.pump();
      await gesture.moveTo(_wordPoint(tester, 3) + const Offset(2, 2));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(_painter(tester).selected, {0, 1, 2, 3});
      expect(fixture.clipboard.writes, isEmpty);
      final cancelled = await tester.startGesture(
        photo.topLeft + const Offset(2, 2),
        kind: PointerDeviceKind.mouse,
      );
      await cancelled.moveBy(const Offset(10, 10));
      await tester.pump();
      await cancelled.cancel();
      await tester.pump();
      expect(_painter(tester).band, isNull);
      expect(_painter(tester).selected, {0, 1, 2, 3});
      expect(find.byType(ImageOcrOverlay), findsOneWidget);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets(
        '$mode: warm surfaces, transparent idle boxes, active pixels and stable responsive photo',
        (tester) async {
      final fixture = _Fixture(png);
      try {
        await fixture.open(tester, mode: mode);
        await fixture.ready(tester);
        final context = tester.element(find.byType(ImageOcrOverlay));
        for (final key in ['image-ocr-header', 'image-ocr-panel']) {
          final surface = tester
              .widget<DecoratedBox>(find.byKey(ValueKey(key)))
              .decoration as BoxDecoration;
          expect(surface.color, FindBarPalette.of(context).surface);
          expect(surface.border, isNull);
          expect(surface.borderRadius, BorderRadius.circular(16));
          expect(surface.boxShadow, EditorSurfaceStyle.embedShadow(context));
          if (mode == 'paper') {
            expect(surface.color, PaperTheme.popupBackground);
          }
        }
        expect(PaperTheme.isEnabled(context), mode == 'paper');
        final backdrop = tester.widget<ColoredBox>(
          find.descendant(
            of: find.byKey(const ValueKey('image-ocr-outside')),
            matching: find.byType(ColoredBox),
          ),
        );
        expect(
          backdrop.color,
          EditorSurfaceStyle.canvasBackground(context).withValues(alpha: .76),
        );
        expect(find.byType(BackdropFilter), findsNothing);
        final idle = await _paintLayer(tester, _painter(tester));
        expect(
          [for (var i = 3; i < idle.length; i += 4) idle[i]]
              .every((a) => a == 0),
          isTrue,
        );
        await _query(tester, 'world');
        final painter = _painter(tester);
        expect(painter.boxes[1], const Rect.fromLTWH(.5, .15, .25, .15));
        final active = await _paintLayer(tester, painter);
        expect(active[(22 * 200 + 125) * 4 + 3], greaterThan(0));
        expect(active[(90 * 200 + 190) * 4 + 3], 0);
        final element = tester.element(find.byType(RawImage));
        final image = tester.widget<RawImage>(find.byType(RawImage)).image;
        tester.view.physicalSize = const Size(640, 720);
        await tester.pump();
        expect(tester.element(find.byType(RawImage)), same(element));
        expect(
          tester.widget<RawImage>(find.byType(RawImage)).image,
          same(image),
        );
        expect(_bar(tester).matchCount, 2);
        expect(fixture.service.calls, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  for (final reduceMotion in [false, true]) {
    testWidgets(
        'previous wraps to a lazy last result and next returns to the first '
        '(reduced motion: $reduceMotion)', (tester) async {
      final fixture = _Fixture(png);
      try {
        await fixture.open(tester, reduceMotion: reduceMotion);
        await waitForOcrCalls(tester, fixture.service, 1);
        fixture.service.calls.single.done.complete(
          OcrResult(
            engine: 'Test local OCR',
            lines: [
              for (var index = 0; index < 100; index++)
                OcrLine.fromWords([
                  OcrWord(
                    text: 'Needle $index',
                    bounds: Rect.fromLTWH(.1, index / 100, .5, .005),
                  ),
                ]),
            ],
          ),
        );
        await tester.pump();
        await _query(tester, 'needle');
        final results = find.byKey(const ValueKey('image-ocr-results'));
        final scroll = tester.widget<ListView>(results).controller!;
        final lastRow = find.byKey(const ValueKey('image-ocr-row-99'));
        expect(scroll.positions, hasLength(1));
        expect(scroll.position.axis, Axis.vertical);
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        expect(scroll.offset, 0);
        expect(_bar(tester).currentMatch, 1);
        expect(
          lastRow,
          findsNothing,
          reason: 'Navigation must reveal a row that is not built yet.',
        );

        await tester.tap(find.byKey(const ValueKey('findPreviousMatch')));
        await _pumpResultReveal(tester, reduceMotion: reduceMotion);
        expect(_bar(tester).currentMatch, 100);
        expect(tester.widget<ListView>(results).controller, same(scroll));
        expect(scroll.offset, greaterThan(0));
        expect(lastRow.hitTestable(), findsOneWidget);
        expect(_painter(tester).selected, {99});

        await tester.tap(find.byKey(const ValueKey('findNextMatch')));
        await _pumpResultReveal(tester, reduceMotion: reduceMotion);
        expect(_bar(tester).currentMatch, 1);
        expect(_bar(tester).matchCount, 100);
        expect(tester.widget<ListView>(results).controller, same(scroll));
        expect(scroll.offset, closeTo(scroll.position.minScrollExtent, .01));
        expect(
          find.byKey(const ValueKey('image-ocr-row-0')).hitTestable(),
          findsOneWidget,
        );
        expect(_painter(tester).selected, {0});
        expect(fixture.clipboard.writes, isEmpty);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }
}

class _Fixture {
  _Fixture(Uint8List png) : source = MemoryOcrSource('synthetic.png', png);
  final MemoryOcrSource source;
  final service = ControlledOcrService();
  final clipboard = OcrTestClipboard();
  Future<void>? closed;

  Future<void> open(
    WidgetTester tester, {
    bool findMode = true,
    String initialQuery = '',
    String mode = 'light',
    bool reduceMotion = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1080, 760);
    clipboard.install();
    late BuildContext owner;
    await tester.pumpWidget(
      ocrTestApp(
        Builder(
          builder: (context) {
            owner = context;
            return const Text('Underlying page stays open');
          },
        ),
        mode: mode,
        reduceMotion: reduceMotion,
      ),
    );
    closed = showImageOcrOverlay(
      owner,
      source: source,
      name: 'Synthetic image',
      find: findMode,
      initialQuery: initialQuery,
      service: service,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> ready(WidgetTester tester) async {
    await waitForOcrCalls(tester, service, 1);
    service.calls.single.done.complete(ocrTestResult());
    await tester.pump();
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    clipboard.release();
    await tester.pumpWidget(const SizedBox.shrink());
    service.finishPending();
    await tester.pump();
    clipboard.uninstall();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
    expect(tester.takeException(), isNull);
  }
}

Finder get _photo => find.byKey(const ValueKey('image-ocr-photo'));
FindReplaceBar _bar(WidgetTester tester) =>
    tester.widget(find.byType(FindReplaceBar));
String _status(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('image-ocr-status'))).data!;
OcrHighlightPainter _painter(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byKey(const ValueKey('image-ocr-highlights')))
    .foregroundPainter! as OcrHighlightPainter;

Future<void> _query(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const ValueKey('findTextField')), query);
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpResultReveal(
  WidgetTester tester, {
  required bool reduceMotion,
}) async {
  // The overlay starts its reveal post-frame. The next frame lays out a jump,
  // or supplies the animated scroll's zero-time tick (Ticker.start/_tick).
  // Advancing time in that first tick alone would still leave offset == 0.
  await tester.pump();
  await tester.pump();
  if (!reduceMotion) {
    await tester.pump(const Duration(milliseconds: 160));
  }
}

Offset _wordPoint(WidgetTester tester, int index) {
  final bounds = _painter(tester).boxes[index];
  final photo = tester.getRect(_photo);
  return photo.topLeft +
      Offset(bounds.center.dx * photo.width, bounds.center.dy * photo.height);
}

Future<Uint8List> _paintLayer(
  WidgetTester tester,
  OcrHighlightPainter painter,
) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(200, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(200, 100);
      try {
        return (await image.toByteData())!.buffer.asUint8List();
      } finally {
        image.dispose();
        picture.dispose();
      }
    }))!;
