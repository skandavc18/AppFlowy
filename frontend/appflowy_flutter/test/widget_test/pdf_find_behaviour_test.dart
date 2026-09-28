import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/book/book_chapter_stage.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_ocr_search.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_page_turn.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_theme.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_view_options.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_result.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/collections/book/book_chapter.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// The same bundled-font boundary as the existing real PDF viewer tests.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as font_io;
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_descriptor.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_family_with_variant.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_variant.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';
import 'file_controls_test_support.dart' show fileControlView;

const _query = ValueKey('pdf-search-field');
const _pageInput = ValueKey('pdf-page-number-field');
const _outsideInput = ValueKey('outside-pdf-input');
const _otherSurface = ValueKey('other-find-viewer');
const _capture = ValueKey('pdf-find-capture');
const _paper = Color(0xFFF7F1E5);
const _modes = ['light', 'dark', 'paper'];
late Map<String, dynamic> _strings;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PdfDocumentFactory nativeFactory;
  late _Factory factory;
  late ui.Image raster;
  late bool fetchFonts;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    _strings = await const TestBundleAssetLoader()
        .load('assets/translations', const Locale('en', 'US'));
    fetchFonts = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final weight in [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
    ]) {
      await font_io.loadFontIfNecessary(
        GoogleFontsDescriptor(
          familyWithVariant: _BundledMono(weight),
          file: GoogleFontsFile('pdf-find-fixture', 0),
        ),
      );
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final family in _modes
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet()) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(_paper, BlendMode.src);
    final picture = recorder.endRecording();
    raster = await picture.toImage(60, 80);
    picture.dispose();
    nativeFactory = PdfDocumentFactory.instance;
  });

  setUp(() {
    factory = _Factory(raster);
    PdfDocumentFactory.instance = factory;
  });
  tearDown(() => PdfDocumentFactory.instance = nativeFactory);
  tearDownAll(() {
    raster.dispose();
    GoogleFonts.config.allowRuntimeFetching = fetchFonts;
    font_io.clearCache();
  });

  for (final mode in _modes) {
    _test(
        '$mode: hovered and focused PDF owns Ctrl+F; outside click does not steal focus',
        (tester) async {
      final pdf =
          await _Fixture.prepare(factory, 'routing-$mode', ['Alpha alpha']);
      final host = _Host();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: const Offset(2, 2));
        await _mount(tester, pdf.preview(), host, mode: mode);
        await _ready(tester);
        host.outerFocus.requestFocus();
        await tester.pump();
        final viewer = tester.state(find.byType(PdfViewer));
        await mouse.moveTo(tester.getCenter(find.byType(PdfViewer)));
        await tester.pump();
        expect(
          host.outerFocus.hasPrimaryFocus,
          isTrue,
          reason: 'Hover alone must not change focus or selection',
        );
        await _controlF(tester);
        expect(find.byType(PdfSearchToolbar), findsOneWidget);
        expect(host.finds, 0);
        expect(_bar(tester).options.caseSensitive, isFalse);
        await tester.enterText(find.byKey(_query), 'alpha');
        await _settledSearch(tester, 2);
        expect(tester.state(find.byType(PdfViewer)), same(viewer));
        expect(pdf.indexCreations, 0);
        expect(pdf.scanCalls, isEmpty);

        final palette =
            PdfPreviewPalette.of(tester.element(find.byType(PdfPreview)));
        final searchSurface = tester.widget<DocumentViewportBar>(
          find.descendant(
            of: find.byType(PdfSearchToolbar),
            matching: find.byType(DocumentViewportBar),
          ),
        );
        expect(searchSurface.background, palette.canvas);
        if (mode == 'paper') {
          expect(palette.canvas, PaperTheme.editorPreviewBackground);
        }

        await tester.tap(
          find.byKey(_outsideInput),
          kind: PointerDeviceKind.mouse,
        );
        await _motion(tester);
        expect(find.byType(PdfSearchToolbar), findsNothing);
        expect(host.outsideFocus.hasPrimaryFocus, isTrue);
        tester.testTextInput.enterText('one click was enough');
        await tester.pump(const Duration(seconds: 1));
        expect(host.outside.text, 'one click was enough');
        expect(host.outsideFocus.hasPrimaryFocus, isTrue);
        expect(tester.state(find.byType(PdfViewer)), same(viewer));

        // Focused PDF still owns find after the cursor leaves its content.
        // Assert pointer-down focus before any tap recognizer can rescue it:
        // the outside field's tap-region unfocus must not win this click.
        final outsideValue = host.outside.value;
        final canvasPress = await tester.press(
          find.byType(PdfViewer),
          kind: PointerDeviceKind.mouse,
        );
        try {
          await tester.pump();
          expect(
            Focus.of(tester.element(find.byType(PdfViewer))).hasFocus,
            isTrue,
            reason: 'The canvas must own focus before Ctrl+F is routed',
          );
          expect(host.outsideFocus.hasFocus, isFalse);
          expect(host.outside.value, outsideValue);
        } finally {
          await canvasPress.up();
        }
        await mouse.moveTo(const Offset(2, 2));
        await tester.pump();
        await _controlF(tester);
        expect(find.byType(PdfSearchToolbar), findsOneWidget);
        expect(host.finds, 0);
        // The canvas is not part of the search field/control tap group.
        // Closing there must still leave keyboard ownership with this PDF.
        await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
        await mouse.moveTo(const Offset(2, 2));
        await _motion(tester);
        expect(find.byType(PdfSearchToolbar), findsNothing);
        expect(
          Focus.of(tester.element(find.byType(PdfViewer))).hasFocus,
          isTrue,
        );
        expect(host.outside.value, outsideValue);
        await _controlF(tester);
        expect(find.byType(PdfSearchToolbar), findsOneWidget);
        expect(host.finds, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _motion(tester);
        expect(find.byType(PdfSearchToolbar), findsNothing);
        await _open(tester);
        await tester.tap(find.byTooltip('Search document (Ctrl/Cmd F)'));
        await _motion(tester);
        expect(
          find.byType(PdfSearchToolbar),
          findsNothing,
          reason: 'Outside pointer-down must not turn toggle-close into reopen',
        );
        expect(factory.opened, [pdf.file.path]);
        pdf.expectNoOriginalIO();
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await _unmount(tester);
        pdf.release();
        host.dispose();
      }
    });

    for (final scale in [1.0, 2.0]) {
      _test(
          '$mode ${scale}x: page input line, count and arrows share actual centers; draft survives page refresh',
          (tester) async {
        final pdf = await _Fixture.prepare(
          factory,
          'geometry-$mode-$scale',
          ['One', 'Two', 'Three'],
        );
        final host = _Host();
        try {
          await _mount(tester, pdf.preview(), host, mode: mode, scale: scale);
          await _ready(tester);
          final input = find.byKey(_pageInput);
          final field = tester.widget<TextField>(input);
          final editor = tester.state<EditableTextState>(
            find.descendant(
              of: input,
              matching: find.byType(EditableText),
            ),
          );
          final inputLine = _editableLine(editor);
          final countLine = _paragraphLine(tester, find.text('/ 3'));
          final fieldRect = tester.getRect(input);
          expect(inputLine.center.dy, closeTo(fieldRect.center.dy, 1));
          expect(countLine.center.dy, closeTo(inputLine.center.dy, 1));
          for (final tooltip in [
            'Previous page (Page Up)',
            'Next page (Page Down)',
          ]) {
            expect(
              tester.getCenter(find.byTooltip(tooltip)).dy,
              closeTo(inputLine.center.dy, 1),
            );
          }
          expect(field.style!.fontSize, 12);
          expect(
            field.style!.fontFamily,
            _theme(mode).textTheme.bodyMedium!.fontFamily,
          );

          await tester.tap(input);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '2',
              selection: TextSelection.collapsed(offset: 1),
            ),
          );
          await tester.pump();
          unawaited(
            _viewer(tester).goToPage(
              pageNumber: 3,
              duration: Duration.zero,
            ),
          );
          await _motion(tester);
          expect(_toolbar(tester).currentPage, 3);
          expect(field.controller!.text, '2');
          expect(field.focusNode!.hasPrimaryFocus, isTrue);
          expect(
            tester.widget<TextField>(input).controller,
            same(field.controller),
          );
          expect(
            tester.state<EditableTextState>(
              find.descendant(
                of: input,
                matching: find.byType(EditableText),
              ),
            ),
            same(editor),
          );
          await tester.testTextInput.receiveAction(TextInputAction.go);
          await _until(tester, () => _toolbar(tester).currentPage == 2);
          expect(field.controller!.text, '2');
          expect(factory.opened, [pdf.file.path]);
          pdf.expectNoOriginalIO();
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester);
          pdf.release();
          host.dispose();
        }
      });
    }
  }

  for (final layout in PdfPageLayoutMode.values) {
    for (final presentation in ['normal', 'fullscreen', 'bare']) {
      _test(
          '$presentation ${layout.name}: delayed all-page totals and last-page navigation',
          (tester) async {
        final pdf = await _Fixture.prepare(
            factory,
            'totals-${layout.name}-$presentation',
            ['needle needle', 'other needle', 'last needle needle']);
        final host = _Host();
        final lastPage = Completer<void>();
        pdf.document.pages.last.textGate = lastPage.future;
        try {
          await _mount(
              tester,
              pdf.preview(
                bare: presentation == 'bare',
                fullscreen: presentation == 'fullscreen',
                metadata: {'layoutMode': layout.name, 'pageTransition': 'none'},
              ),
              host,
              mode: 'paper',
              reduced: true);
          await _ready(tester);
          final viewer = tester.state(find.byType(PdfViewer));
          final controller = _viewer(tester);
          unawaited(
              controller.goToPage(pageNumber: 3, duration: Duration.zero));
          await _until(tester, () => controller.pageNumber == 3);
          // Real key routing, also for the chrome-less book reading.
          Focus.of(tester.element(find.byType(PdfViewer))).requestFocus();
          await tester.pump();
          await _controlF(tester);
          await tester.enterText(_queryInput, 'needle');
          await _until(tester, () => _bar(tester).matchCount == 3);
          expect(_bar(tester).isSearching, isTrue);
          expect(_bar(tester).searchProgress, closeTo(2 / 3, 0.001));
          expect(_bar(tester).statusOverride,
              '3 matches so far · Searching all 3 pages (2/3)');
          expect(find.text(_bar(tester).statusOverride!), findsOneWidget);
          expect(_bar(tester).currentMatch, 0);
          expect(controller.pageNumber, 3,
              reason:
                  'Partial earlier results must not steal the starting page');
          lastPage.complete();
          await _settledSearch(tester, 5);
          expect(_bar(tester).statusOverride, isNull);
          expect(_bar(tester).currentMatch, 4);
          expect(controller.pageNumber, 3);
          for (final (index, page) in [
            (5, 3),
            (1, 1),
            (2, 1),
            (3, 2),
            (4, 3)
          ]) {
            await tester.tap(find.byKey(const ValueKey('findNextMatch')));
            await _motion(tester);
            expect(_bar(tester).matchCount, 5);
            expect(_bar(tester).currentMatch, index);
            expect(controller.pageNumber, page);
          }
          await tester.tap(find.byKey(const ValueKey('findPreviousMatch')));
          await _motion(tester);
          expect(_bar(tester).currentMatch, 3);
          expect(controller.pageNumber, 2);
          expect(tester.state(find.byType(PdfViewer)), same(viewer));
          expect(factory.opened, [pdf.file.path]);
          expect(pdf.scanCalls, isEmpty);
          pdf.expectNoOriginalIO();
          expect(tester.takeException(), isNull);
        } finally {
          if (!lastPage.isCompleted) lastPage.complete();
          await _unmount(tester);
          pdf.release();
          host.dispose();
        }
      });
    }
  }

  _test('native PDF text selection after an outside field still owns Ctrl+F',
      (tester) async {
    final pdf =
        await _Fixture.prepare(factory, 'selection-focus', ['Alpha alpha']);
    final host = _Host();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: const Offset(2, 2));
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      await tester.tap(
        find.byKey(_outsideInput),
        kind: PointerDeviceKind.mouse,
      );
      await _motion(tester);
      const outsideValue = TextEditingValue(
        text: 'outside selection',
        selection: TextSelection(baseOffset: 0, extentOffset: 7),
      );
      tester.testTextInput.updateEditingValue(outsideValue);
      await tester.pump();

      final controller = _viewer(tester);
      final page = pdf.document.pages.single;
      final text = await page.loadText();
      final bounds = text.fragments.single.bounds.toRectInPageRect(
        page: page,
        pageRect: controller.layout.pageLayouts.single,
      );
      final start =
          controller.documentToGlobal(bounds.topLeft + const Offset(1, 2))!;
      final end =
          controller.documentToGlobal(bounds.bottomRight - const Offset(1, 2))!;
      final viewport = tester.getRect(find.byType(PdfViewer));
      expect(viewport.contains(start) && viewport.contains(end), isTrue);
      // Use the PDF character geometry and actual viewer hit path. Selection
      // is handled by pdfrx's SelectionArea, not necessarily the leaf box
      // (the link overlay and IgnorePointer can precede it).
      await mouse.moveTo(start);
      await tester.pump();
      final selectable = tester
          .widget<PdfPageTextOverlay>(find.byType(PdfPageTextOverlay))
          .selectables[1]!;
      expect(
        tester.hitTestOnBinding(start).path.map((hit) => hit.target),
        contains(same(controller.renderBox)),
      );
      expect(host.outsideFocus.hasPrimaryFocus, isTrue);
      expect(host.outside.value, outsideValue);

      await tester.dragFrom(start, end - start, kind: PointerDeviceKind.mouse);
      await _motion(tester);
      final selectionRegion = tester.widget<SelectableRegion>(
        find.descendant(
          of: find.byType(PdfViewer),
          matching: find.byType(SelectableRegion),
        ),
      );
      expect(
        selectionRegion.focusNode.hasPrimaryFocus,
        isTrue,
        reason: 'Canvas focus must not steal native selection focus',
      );
      expect(selectable.selectedRanges.text, 'Alpha alpha');
      expect(host.outside.value, outsideValue);
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(selectable.selectedRanges.text, 'Alpha alpha');
      await _controlF(tester);
      expect(find.byType(PdfSearchToolbar), findsOneWidget);
      expect(_bar(tester).focusNode.hasPrimaryFocus, isTrue);
      expect(host.finds, 0);
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test(
      'native matching honors literal/case/word/regex options and keyboard navigation',
      (tester) async {
    final pdf = await _Fixture.prepare(
      factory,
      'options',
      ['Alpha alpha ALPHABET a.b axb\nbeta'],
    );
    final host = _Host();
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      await _open(tester);
      await tester.enterText(find.byKey(_query), 'alpha');
      await tester.pump();
      expect(_bar(tester).isSearching, isTrue);
      await _settledSearch(tester, 3);
      expect(_bar(tester).currentMatch, 1);
      final queryValue = _bar(tester).controller.value;
      // Flutter's engine translates an unhandled Enter into performAction.
      // sendKeyEvent only reaches the framework: it never invokes onSubmitted.
      // Model both halves, and ensure no extra key listener navigates twice.
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      await tester.pump();
      expect(_bar(tester).currentMatch, 1);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _motion(tester);
      expect(_bar(tester).currentMatch, 2);
      expect(_bar(tester).focusNode.hasPrimaryFocus, isTrue);
      expect(_bar(tester).controller.value, queryValue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await _motion(tester);
      expect(_bar(tester).currentMatch, 1);
      await tester.tap(find.byKey(const ValueKey('findPreviousMatch')));
      await _motion(tester);
      expect(_bar(tester).currentMatch, 3, reason: 'Navigation wraps');

      // _query keys the whole shared bar. At 420px its center is an option
      // toggle, not the editable field; tapping it would restart the query.
      final options = _bar(tester).options;
      expect(_queryInput, findsOneWidget);
      await tester.tap(_queryInput);
      await tester.pump();
      expect(_bar(tester).options, options);
      expect(_bar(tester).currentMatch, 3);
      expect(_bar(tester).controller.text, 'alpha');
      expect(_bar(tester).focusNode.hasPrimaryFocus, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _motion(tester);
      expect(
        _bar(tester).currentMatch,
        1,
        reason: 'A platform search action advances exactly once too',
      );
      expect(_bar(tester).focusNode.hasPrimaryFocus, isTrue);
      expect(_bar(tester).controller.text, 'alpha');

      await tester.tap(find.text('Aa'));
      await _settledSearch(tester, 1);
      expect(_bar(tester).options.caseSensitive, isTrue);
      await tester.tap(find.text('Aa'));
      await tester.pump();
      expect(_bar(tester).options.caseSensitive, isFalse);
      await tester.tap(find.text('ab'));
      await _settledSearch(tester, 2);
      expect(_bar(tester).options.caseSensitive, isFalse);
      expect(_bar(tester).options.wholeWord, isTrue);
      await tester.enterText(find.byKey(_query), 'a.b');
      await _settledSearch(tester, 1);
      await tester.tap(find.text('.*'));
      await _settledSearch(tester, 2);
      await tester.enterText(find.byKey(_query), '[');
      await tester.pump();
      expect(_bar(tester).queryInvalid, isTrue);
      expect(_bar(tester).isSearching, isFalse);
      expect(_bar(tester).matchCount, 0);
      await tester.tap(find.text('ab'));
      await tester.enterText(find.byKey(_query), r'^beta$');
      await _settledSearch(tester, 1);
      await tester.enterText(find.byKey(_query), '^');
      await _settledSearch(tester, 0);
      expect(
          find.text(LocaleKeys.findAndReplace_noResult.tr()), findsOneWidget);
      await tester.enterText(find.byKey(_query), '');
      await tester.pump();
      expect(find.text('Type to search'), findsOneWidget);
      expect(_bar(tester).isSearching, isFalse);
      expect(pdf.indexCreations, 0, reason: 'A textual PDF must not auto-scan');
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test('reduced-motion PDF resize retains its viewer and open Find draft',
      (tester) async {
    final pdf = await _Fixture.prepare(
        factory, 'reduced-find-resize', ['Needle needle']);
    final host = _Host();
    final width = ValueNotifier(980.0);
    final child = ValueListenableBuilder<double>(
      valueListenable: width,
      builder: (_, value, __) => Align(
        child: SizedBox(width: value, child: pdf.preview()),
      ),
    );
    try {
      await _mount(tester, child, host, mode: 'paper', reduced: true);
      await _ready(tester);
      final preview = tester.state(find.byType(PdfPreview));
      final viewer = tester.state(find.byType(PdfViewer));
      final controller = _viewer(tester);
      expect(tester.takeException(), isNull);

      // A hidden search wrapper must also tolerate a changed viewport width.
      width.value = 420;
      await _motion(tester);
      expect(find.byType(PdfSearchToolbar), findsNothing);
      expect(tester.state(find.byType(PdfViewer)), same(viewer));
      expect(tester.takeException(), isNull);
      final closedBounds = tester.getRect(find.byType(PdfViewer));

      await _open(tester);
      await tester.enterText(_queryInput, 'needle');
      await _settledSearch(tester, 2);
      final field = tester.widget<TextField>(_queryInput);
      final editable = find.descendant(
        of: _queryInput,
        matching: find.byType(EditableText),
      );
      final editor = tester.state<EditableTextState>(editable);
      const draft = TextEditingValue(
        text: 'needle',
        selection: TextSelection(baseOffset: 1, extentOffset: 4),
        composing: TextRange(start: 0, end: 6),
      );
      tester.testTextInput.updateEditingValue(draft);
      await tester.pump();
      for (final available in [240.0, 980.0, 420.0]) {
        width.value = available;
        await _motion(tester);
        expect(tester.state(find.byType(PdfPreview)), same(preview));
        expect(tester.state(find.byType(PdfViewer)), same(viewer));
        expect(_viewer(tester), same(controller));
        expect(tester.state<EditableTextState>(editable), same(editor));
        expect(tester.widget<TextField>(_queryInput).controller,
            same(field.controller));
        expect(field.controller!.value, draft);
        expect(field.focusNode!.hasPrimaryFocus, isTrue);
        expect(_bar(tester).matchCount, 2);
        expect(
          tester.getRect(find.byType(PdfSearchToolbar)).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(PdfViewer)).top),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape);
      await _motion(tester);
      expect(find.byType(PdfSearchToolbar), findsNothing);
      expect(tester.getRect(find.byType(PdfViewer)), closedBounds);
      expect(tester.state(find.byType(PdfViewer)), same(viewer));
      expect(_viewer(tester), same(controller));
      expect(factory.opened, [pdf.file.path]);
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      width.dispose();
      pdf.release();
      host.dispose();
    }
  });

  _test('hardware Enter leaves active composition to the IME', (tester) async {
    final pdf = await _Fixture.prepare(
      factory,
      'composing-enter',
      ['alpha alpha alpha'],
    );
    final host = _Host();
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      await _open(tester);
      await tester.enterText(find.byKey(_query), 'alpha');
      await _settledSearch(tester, 3);
      final composing = _bar(tester).controller.value.copyWith(
            composing: const TextRange(start: 0, end: 5),
          );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.enter),
        isFalse,
        reason: 'IME confirmation must not navigate or be swallowed',
      );
      await _motion(tester);
      expect(_bar(tester).currentMatch, 1);
      expect(_bar(tester).controller.value, composing);
      expect(_bar(tester).focusNode.hasPrimaryFocus, isTrue);

      tester.testTextInput
          .updateEditingValue(composing.copyWith(composing: TextRange.empty));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _motion(tester);
      expect(_bar(tester).currentMatch, 2);
      expect(_bar(tester).focusNode.hasPrimaryFocus, isTrue);
      expect(_bar(tester).controller.text, 'alpha');
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      await tester.pump();
      expect(_bar(tester).currentMatch, 2);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _motion(tester);
      expect(_bar(tester).currentMatch, 3);
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test(
      'pending/identical newer queries reject cancelled empty-page completion',
      (tester) async {
    final pdf = await _Fixture.prepare(factory, 'pending', ['Alpha', '']);
    final host = _Host();
    final pageReady = Completer<void>();
    pdf.document.pages[1].textGate = pageReady.future;
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      await _open(tester);
      await tester.enterText(find.byKey(_query), 'absent');
      await tester.pump(const Duration(milliseconds: 400));
      expect(_bar(tester).isSearching, isTrue);
      expect(find.text(LocaleKeys.findAndReplace_noResult.tr()), findsNothing);
      expect(pdf.scanCalls, isEmpty);
      await tester.enterText(find.byKey(_query), 'Alpha');
      await tester.pump(const Duration(milliseconds: 400));
      // Reapplying the same options while pending creates an identical native
      // pattern. It must restart, not cancel and then skip the same pattern.
      _bar(tester).onOptionsChanged!(_bar(tester).options);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_bar(tester).isSearching, isTrue);
      pageReady.complete();
      await _settledSearch(tester, 1);
      expect(_bar(tester).currentMatch, 1);
      expect(
        pdf.scanCalls,
        isEmpty,
        reason: 'The obsolete no-match query must never start OCR',
      );
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      if (!pageReady.isCompleted) pageReady.complete();
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test(
      'same-reference document replacement restarts with current options, not raw text or cached pages',
      (tester) async {
    final pdf = await _Fixture.prepare(factory, 'replacement', ['Alpha']);
    final host = _Host();
    final latePage = Completer<void>();
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      final viewerState = tester.state(find.byType(PdfViewer));
      await _open(tester);
      await tester.tap(find.text('Aa'));
      // tap sends pointer events, not a frame. Rebuild each options snapshot
      // before the next toggle, or .* would copy the old case-insensitive one.
      await tester.pump();
      expect(_bar(tester).options.caseSensitive, isTrue);
      await tester.tap(find.text('.*'));
      await tester.pump();
      expect(_bar(tester).options.caseSensitive, isTrue);
      expect(_bar(tester).options.useRegex, isTrue);
      await tester.enterText(find.byKey(_query), r'^Alpha$');
      await _settledSearch(tester, 1);

      final listenable = pdf.ref.resolveListenable();
      expect(
        PdfDocumentRefFile(pdf.file.path).resolveListenable(),
        same(listenable),
      );
      final interim = _Document(pdf.file.path, raster, ['']);
      interim.pages.single.textGate = latePage.future;
      expect(listenable.setDocument(interim), isTrue);
      await _ready(tester, expectedDocument: interim);
      await tester.pump();
      expect(_bar(tester).isSearching, isTrue);
      final replacement =
          _Document(pdf.file.path, raster, ['alpha\nAlpha\nALPHA']);
      expect(listenable.setDocument(replacement), isTrue);
      await _ready(tester, expectedDocument: replacement);
      await _settledSearch(tester, 1);
      latePage.complete();
      await _motion(tester);
      expect(_bar(tester).matchCount, 1);
      expect(_bar(tester).options.caseSensitive, isTrue);
      expect(_bar(tester).options.useRegex, isTrue);
      expect(_bar(tester).controller.text, r'^Alpha$');
      expect(pdf.scanCalls, isEmpty);
      expect(tester.state(find.byType(PdfViewer)), same(viewerState));
      expect(factory.opened, [pdf.file.path]);
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      if (!latePage.isCompleted) latePage.complete();
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test(
      'OCR fallback waits for text, scans current page first, paints bounds and preserves mixed matches',
      (tester) async {
    final pdf =
        await _Fixture.prepare(factory, 'mixed', ['Native alpha', '', '']);
    final host = _Host();
    final third = Completer<OcrResult>();
    final second = Completer<OcrResult>();
    pdf.scanner = (page) => page.pageNumber == 3 ? third.future : second.future;
    final clipboard = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      await _open(tester);
      await tester.enterText(find.byKey(_query), 'alpha');
      await _settledSearch(tester, 1);
      expect(pdf.scanCalls, isEmpty);
      // Place page 3 at the top at a zoom where its lower match is offscreen.
      _toolbar(tester).onPageSubmitted(3);
      await _until(tester, () => _toolbar(tester).currentPage == 3);
      final controller = _viewer(tester);
      unawaited(controller.setZoom(controller.centerPosition, 2));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(_query), 'scanned');
      await _until(tester, () => pdf.scanCalls.isNotEmpty);
      expect(pdf.scanCalls, [3]);
      expect(_bar(tester).ocrEnabled, isTrue);
      expect(_bar(tester).isSearching, isTrue);
      expect(find.text(LocaleKeys.findAndReplace_noResult.tr()), findsNothing);
      final page = controller.layout.pageLayouts[2];
      final hit = Rect.fromLTWH(
        page.left + page.width * 0.68,
        page.top + page.height * 0.78,
        page.width * 0.18,
        page.height * 0.04,
      );
      // Last-page navigation normally anchors its bottom. Explicitly expose
      // the top so a page-only jump cannot accidentally satisfy this test.
      controller.value = controller.calcMatrixFor(
        Offset(page.center.dx, page.top + controller.viewSize.height / 4),
        zoom: 2,
      );
      await tester.pump();
      expect(controller.visibleRect.contains(hit.center), isFalse);
      third.complete(
        OcrResult(
          engine: 'fixture',
          lines: [
            OcrLine.fromWords(const [
              OcrWord(
                text: 'ScAnNeD',
                bounds: Rect.fromLTWH(0.68, 0.78, 0.18, 0.04),
              ),
              OcrWord(
                text: 'NaTiVe',
                bounds: Rect.fromLTWH(0.68, 0.86, 0.18, 0.04),
              ),
            ]),
          ],
        ),
      );
      await _until(
        tester,
        () => _bar(tester).matchCount == 1 && pdf.scanCalls.length == 2,
      );
      await _motion(tester);
      expect(pdf.scanCalls, [3, 2]);
      expect(controller.visibleRect.contains(hit.center), isTrue);
      final palette =
          PdfPreviewPalette.of(tester.element(find.byType(PdfPreview)));
      final painted =
          await _pixelAt(tester, controller.documentToGlobal(hit.center)!);
      final expected = Color.alphaBlend(palette.activeSearchMatch, _paper);
      expect(painted.r, closeTo(expected.r, 2 / 255));
      expect(painted.g, closeTo(expected.g, 2 / 255));
      expect(painted.b, closeTo(expected.b, 2 / 255));

      await tester.enterText(find.byKey(_query), 'native');
      await _until(tester, () => _bar(tester).matchCount == 2);
      expect(
        _bar(tester).isSearching,
        isTrue,
        reason: 'Page 2 is still scanning',
      );
      expect(
        pdf.scanCalls,
        [3, 2],
        reason: 'Keystrokes reuse one active index',
      );
      expect(_bar(tester).currentMatch, 2);
      await tester.tap(find.byKey(const ValueKey('pdf-search-copy-match')));
      await _motion(tester);
      expect(clipboard, ['NaTiVe']);
      expect(find.byType(PdfSearchToolbar), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('findNextMatch')));
      await _motion(tester);
      expect(_bar(tester).currentMatch, 1);
      expect(_toolbar(tester).currentPage, 1);
      await tester.tap(find.byKey(const ValueKey('findPreviousMatch')));
      await _motion(tester);
      expect(_bar(tester).currentMatch, 2);
      expect(_toolbar(tester).currentPage, 3);
      second.complete(OcrResult.empty);
      await _settledSearch(tester, 2);
      await tester.enterText(find.byKey(_query), 'genuine-empty');
      await _settledSearch(tester, 0);
      expect(
          find.text(LocaleKeys.findAndReplace_noResult.tr()), findsOneWidget);
      expect(pdf.scanCalls, [3, 2]);
      expect(pdf.indexCreations, 1);
      expect(
        pdf.metadataWrites,
        isEmpty,
        reason: 'Find does not persist highlights',
      );
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      if (!third.isCompleted) third.complete(OcrResult.empty);
      if (!second.isCompleted) second.complete(OcrResult.empty);
      await _unmount(tester);
      pdf.release();
      host.dispose();
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    }
  });

  _test(
      'explicit OCR retains native matches on failure, deduplicates text and retries only failed pages',
      (tester) async {
    final pdf = await _Fixture.prepare(factory, 'retry', ['Alpha', '']);
    final host = _Host();
    var unavailable = true;
    pdf.scanner = (page) async {
      if (page.pageNumber == 2 && unavailable) {
        throw const OcrUnavailableException(
          'Local engine unavailable',
          hint: 'Install a pack',
        );
      }
      return _ocr(
        'Alpha',
        page.pageNumber == 1
            ? Rect.fromLTWH(40 / 600, 40 / 800, 35 / 600, 18 / 800)
            : const Rect.fromLTWH(0.2, 0.8, 0.2, 0.05),
      );
    };
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      await _open(tester);
      await tester.enterText(find.byKey(_query), 'alpha');
      await _settledSearch(tester, 1);
      await tester.tap(find.byKey(const ValueKey('pdf-search-ocr')));
      await _until(tester, () => _bar(tester).onRetryOcr != null);
      expect(_bar(tester).matchCount, 1);
      expect(_bar(tester).statusOverride, contains('Install a pack'));
      expect(pdf.scanCalls, [1, 2]);
      await tester.enterText(find.byKey(_query), 'Alpha');
      await _settledSearch(tester, 1);
      expect(pdf.scanCalls, [1, 2], reason: 'Typing is not an OCR retry');
      unavailable = false;
      await tester.tap(find.byKey(const ValueKey('pdf-search-ocr-retry')));
      await _settledSearch(tester, 2);
      expect(pdf.scanCalls, [1, 2, 2]);
      expect(_bar(tester).statusOverride, isNull);
      await tester.tap(find.byKey(const ValueKey('pdf-search-ocr')));
      await _settledSearch(tester, 1);
      expect(_bar(tester).ocrEnabled, isFalse);
      await tester.enterText(find.byKey(_query), 'absent');
      await _settledSearch(tester, 0);
      expect(
        _bar(tester).ocrEnabled,
        isFalse,
        reason: 'Explicit opt-out is respected',
      );
      expect(pdf.scanCalls, [1, 2, 2]);
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test(
      'outside dismissal and disposal reject pending OCR and native completions',
      (tester) async {
    final pdf = await _Fixture.prepare(factory, 'dismiss-pending', ['', '']);
    final host = _Host();
    final pending = Completer<OcrResult>();
    final nativePending = Completer<void>();
    pdf.scanner = (_) => pending.future;
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      await _open(tester);
      await tester.enterText(find.byKey(_query), 'late');
      await _until(tester, () => pdf.scanCalls.isNotEmpty);
      await tester.tap(
        find.byKey(_outsideInput),
        kind: PointerDeviceKind.mouse,
      );
      await _motion(tester);
      expect(find.byType(PdfSearchToolbar), findsNothing);
      expect(host.outsideFocus.hasPrimaryFocus, isTrue);
      pending.complete(_ocr('late', const Rect.fromLTWH(0.2, 0.2, 0.2, 0.05)));
      await _motion(tester);
      expect(
        pdf.scanCalls,
        [1],
        reason: 'Closing find cancels remaining pages',
      );
      expect(host.outsideFocus.hasPrimaryFocus, isTrue);

      final replacement = _Document(pdf.file.path, raster, ['late']);
      replacement.pages.single.textGate = nativePending.future;
      pdf.ref.resolveListenable().setDocument(replacement);
      await _ready(tester);
      await _open(tester);
      await tester.enterText(find.byKey(_query), 'late');
      await tester.pump(const Duration(milliseconds: 400));
      expect(_bar(tester).isSearching, isTrue);
      await _unmount(tester);
      nativePending.complete();
      await _motion(tester);
      expect(find.byType(PdfSearchToolbar), findsNothing);
      expect(pdf.scanCalls, [1]);
      expect(tester.takeException(), isNull);
      pdf.expectNoOriginalIO();
    } finally {
      if (!pending.isCompleted) pending.complete(OcrResult.empty);
      if (!nativePending.isCompleted) nativePending.complete();
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test(
      'reopening PDF find resumes completed OCR pages and rejects the cancelled page',
      (tester) async {
    final pdf = await _Fixture.prepare(factory, 'resume', ['', '']);
    final host = _Host();
    final oldSecond = Completer<OcrResult>();
    final newSecond = Completer<OcrResult>();
    var secondAttempts = 0;
    pdf.scanner = (page) {
      if (page.pageNumber == 1) {
        return Future.value(
          _ocr('cached', const Rect.fromLTWH(0.1, 0.2, 0.2, 0.05)),
        );
      }
      return ++secondAttempts == 1 ? oldSecond.future : newSecond.future;
    };
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      final viewer = tester.state(find.byType(PdfViewer));
      await _open(tester);
      await tester.enterText(find.byKey(_query), 'cached');
      await _until(tester, () => pdf.scanCalls.length == 2);
      expect(_bar(tester).matchCount, 1);
      expect(_bar(tester).isSearching, isTrue);
      await tester.tap(
        find.byKey(_outsideInput),
        kind: PointerDeviceKind.mouse,
      );
      await _motion(tester);
      expect(find.byType(PdfSearchToolbar), findsNothing);
      await _open(tester);
      await tester.enterText(find.byKey(_query), 'cached');
      await _until(tester, () => pdf.scanCalls.length == 3);
      expect(pdf.scanCalls, [1, 2, 2]);
      expect(pdf.indexCreations, 1);
      oldSecond
          .complete(_ocr('obsolete', const Rect.fromLTWH(0.1, 0.2, 0.2, 0.05)));
      await _motion(tester);
      expect(_bar(tester).isSearching, isTrue);
      expect(_bar(tester).matchCount, 1);
      newSecond
          .complete(_ocr('cached', const Rect.fromLTWH(0.1, 0.8, 0.2, 0.05)));
      await _settledSearch(tester, 2);
      await tester.enterText(find.byKey(_query), 'obsolete');
      await _settledSearch(tester, 0);
      expect(pdf.scanCalls, [1, 2, 2]);
      expect(tester.state(find.byType(PdfViewer)), same(viewer));
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      if (!oldSecond.isCompleted) oldSecond.complete(OcrResult.empty);
      if (!newSecond.isCompleted) newSecond.complete(OcrResult.empty);
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test(
      'switching find owners dismisses PDF without restoring its former focus',
      (tester) async {
    final pdf = await _Fixture.prepare(factory, 'switch-owner', ['Alpha']);
    final host = _Host();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      await _open(tester);
      final searchFocus = _bar(tester).focusNode;
      expect(searchFocus.hasPrimaryFocus, isTrue);
      await mouse.addPointer(
        location: tester.getCenter(find.byKey(_otherSurface)),
      );
      await _controlF(tester);
      expect(host.otherFinds, 1);
      expect(host.finds, 0);
      expect(find.byType(PdfSearchToolbar), findsNothing);
      expect(host.otherFocus.hasPrimaryFocus, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(host.otherFocus.hasPrimaryFocus, isTrue);
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test(
      'native extraction errors are not reported as empty or used to start OCR',
      (tester) async {
    final pdf = await _Fixture.prepare(
      factory,
      'native-error',
      List.filled(10, 'Alpha'),
    );
    final host = _Host();
    // The last page is outside the viewer's render cache. Only native find
    // asks for it; allMatches itself is still the installed pdfrx matcher.
    pdf.document.pages.last.textFailure = StateError('Synthetic text failure');
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      await _open(tester);
      await tester.enterText(find.byKey(_query), 'alpha');
      await _until(
        tester,
        () => _bar(tester).statusOverride?.contains('could not finish') == true,
      );
      expect(_bar(tester).isSearching, isFalse);
      expect(_bar(tester).matchCount, 9);
      expect(find.text(LocaleKeys.findAndReplace_noResult.tr()), findsNothing);
      expect(pdf.scanCalls, isEmpty);
      pdf.document.pages.last.textFailure = null;
      await tester.enterText(find.byKey(_query), 'Alpha');
      await _settledSearch(tester, 10);
      expect(_bar(tester).statusOverride, isNull);
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test('presets retain PDF/controller/page-field state and write one snapshot',
      (tester) async {
    final pdf = await _Fixture.prepare(
        factory, 'presets', ['One', 'Two', 'Three', 'Four']);
    final host = _Host();
    try {
      await _mount(tester, pdf.preview(), host);
      await _ready(tester);
      final preview = tester.state(find.byType(PdfPreview));
      final viewer = tester.state(find.byType(PdfViewer));
      final controller = _viewer(tester);
      final ref = tester.widget<PdfViewer>(find.byType(PdfViewer)).documentRef;
      await tester.enterText(find.byKey(_pageInput), '2');
      final field = tester.widget<TextField>(find.byKey(_pageInput));
      final draft = field.controller!.value;
      var writes = 0;
      for (final preset in [
        PdfViewPreset.book,
        PdfViewPreset.singlePageFade,
        PdfViewPreset.horizontal,
        PdfViewPreset.singlePage,
        PdfViewPreset.continuous,
      ]) {
        tester
            .widget<PdfViewOptionsMenu>(find.byType(PdfViewOptionsMenu))
            .onPresetChanged(preset);
        expect(pdf.metadataWrites, hasLength(++writes));
        expect(pdf.metadataWrites.last['layoutMode'], preset.layoutMode.name);
        expect(
            pdf.metadataWrites.last['pageTransition'], preset.transition.name);
        await _motion(tester);
        await tester.pump();
        expect(tester.state(find.byType(PdfPreview)), same(preview));
        expect(tester.state(find.byType(PdfViewer)), same(viewer));
        expect(_viewer(tester), same(controller));
        expect(tester.widget<PdfViewer>(find.byType(PdfViewer)).documentRef,
            same(ref));
        expect(tester.widget<TextField>(find.byKey(_pageInput)).controller,
            same(field.controller));
        expect(field.controller!.value, draft);
        expect(field.focusNode!.hasPrimaryFocus, isTrue);
        tester
            .widget<PdfViewOptionsMenu>(find.byType(PdfViewOptionsMenu))
            .onPresetChanged(preset);
        expect(pdf.metadataWrites, hasLength(writes),
            reason: 'Reselecting is a no-op');
      }
      expect(factory.opened, [pdf.file.path]);
      expect(pdf.file.reads, 0);
      expect(pdf.file.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test('high-DPI inner PDF keyboard navigation paints a real bounded curl',
      (tester) async {
    final pdf = await _Fixture.prepare(
        factory, 'high-dpi-curl', ['One', 'Two', 'Three']);
    final host = _Host();
    try {
      await _mount(
        tester,
        pdf.preview(metadata: const {
          'layoutMode': 'pageBreak',
          'pageTransition': 'flip'
        }),
        host,
        dpr: 6,
      );
      await _ready(tester);
      final viewer = tester.state(find.byType(PdfViewer));
      final controller = _viewer(tester);
      final selection = tester.widget<SelectableRegion>(
        find.descendant(
            of: find.byType(PdfViewer),
            matching: find.byType(SelectableRegion)),
      );
      selection.focusNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown,
          physicalKey: PhysicalKeyboardKey.pageDown);
      await _until(tester, () => _curl.evaluate().isNotEmpty);
      final painter =
          tester.widget<CustomPaint>(_curl).painter! as PageTurnPainter;
      expect(painter.scene.leafRect.width * 6, greaterThan(1600 / 0.78));
      expect(pdf.document.pages.expand((page) => page.curlWidths),
          everyElement(lessThanOrEqualTo(1600)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          (tester.widget<CustomPaint>(_curl).painter! as PageTurnPainter)
              .progress,
          greaterThan(0));
      await _until(tester,
          () => _toolbar(tester).currentPage == 2 && _curl.evaluate().isEmpty);
      expect(tester.state(find.byType(PdfViewer)), same(viewer));
      expect(_viewer(tester), same(controller));
      expect(factory.opened, [pdf.file.path]);
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test(
      'changing mode during a live curl cancels its commit, not the next turn',
      (tester) async {
    final pdf = await _Fixture.prepare(
        factory, 'cancel-live-curl', ['One', 'Two', 'Three']);
    final host = _Host();
    try {
      await _mount(
        tester,
        pdf.preview(metadata: const {
          'layoutMode': 'pageBreak',
          'pageTransition': 'flip'
        }),
        host,
      );
      await _ready(tester);
      final viewer = tester.state(find.byType(PdfViewer));
      final controller = _viewer(tester);
      _toolbar(tester).onPageSubmitted(2);
      await _until(tester, () => _curl.evaluate().isNotEmpty);
      await tester.pump(const Duration(milliseconds: 80));
      tester
          .widget<PdfViewOptionsMenu>(find.byType(PdfViewOptionsMenu))
          .onPresetChanged(PdfViewPreset.singlePageFade);
      await tester.pump();
      expect(_curl, findsNothing);
      expect(_toolbar(tester).currentPage, 1);
      _toolbar(tester).onPageSubmitted(3);
      await _until(tester, () => _toolbar(tester).currentPage == 3);
      await tester.pump(const Duration(seconds: 1));
      expect(_toolbar(tester).currentPage, 3);
      expect(tester.state(find.byType(PdfViewer)), same(viewer));
      expect(_viewer(tester), same(controller));
      expect(pdf.metadataWrites, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test(
      'mode change rejects a pending raster turn without unlocking a newer fade',
      (tester) async {
    final pdf = await _Fixture.prepare(
        factory, 'cancel-raster', ['One', 'Two', 'Three', 'Four']);
    final host = _Host();
    final gate = Completer<void>();
    for (final page in pdf.document.pages) {
      page.curlGate = gate.future;
    }
    try {
      await _mount(
        tester,
        pdf.preview(metadata: const {
          'layoutMode': 'pageBreak',
          'pageTransition': 'flip'
        }),
        host,
      );
      await _ready(tester);
      _toolbar(tester).onPageSubmitted(2);
      await tester.pump();
      expect(pdf.document.pages.first.curlWidths, isNotEmpty);
      tester
          .widget<PdfViewOptionsMenu>(find.byType(PdfViewOptionsMenu))
          .onPresetChanged(PdfViewPreset.singlePageFade);
      await tester.pump();
      _toolbar(tester).onPageSubmitted(4);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(_toolbar(tester).currentPage, 1);
      expect(_curl, findsNothing);
      _toolbar(tester).onPageSubmitted(3); // Must still be busy with page 4.
      await _until(tester, () => _toolbar(tester).currentPage == 4);
      await tester.pump(const Duration(seconds: 1));
      expect(_toolbar(tester).currentPage, 4);
      expect(pdf.metadataWrites, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  _test('same-reference document replacement rejects the old curl commit',
      (tester) async {
    final pdf = await _Fixture.prepare(
        factory, 'curl-replacement', ['One', 'Two', 'Three']);
    final host = _Host();
    final gate = Completer<void>();
    for (final page in pdf.document.pages) {
      page.curlGate = gate.future;
    }
    try {
      await _mount(
        tester,
        pdf.preview(metadata: const {
          'layoutMode': 'pageBreak',
          'pageTransition': 'flip'
        }),
        host,
      );
      await _ready(tester);
      final viewer = tester.state(find.byType(PdfViewer));
      final controller = _viewer(tester);
      _toolbar(tester).onPageSubmitted(2);
      await tester.pump();
      final replacement =
          _Document(pdf.file.path, raster, ['New one', 'New two', 'New three']);
      pdf.ref.resolveListenable().setDocument(replacement);
      await _ready(tester, expectedDocument: replacement);
      tester
          .widget<PdfViewOptionsMenu>(find.byType(PdfViewOptionsMenu))
          .onPresetChanged(PdfViewPreset.continuous);
      await _motion(tester);
      _toolbar(tester).onPageSubmitted(3);
      await _until(tester, () => _toolbar(tester).currentPage == 3);
      gate.complete();
      await _motion(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(_toolbar(tester).currentPage, 3);
      expect(_curl, findsNothing);
      expect(tester.state(find.byType(PdfViewer)), same(viewer));
      expect(_viewer(tester), same(controller));
      expect(factory.opened, [pdf.file.path]);
      expect(tester.takeException(), isNull);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await _unmount(tester);
      pdf.release();
      host.dispose();
    }
  });

  for (final transition in ['slide', 'fade', 'flip']) {
    _test('reduced motion skips $transition without rewriting the chosen mode',
        (tester) async {
      final pdf = await _Fixture.prepare(
          factory, 'reduced-$transition', ['One', 'Two']);
      final host = _Host();
      try {
        await _mount(
          tester,
          pdf.preview(metadata: {
            'layoutMode': 'pageBreak',
            'pageTransition': transition
          }),
          host,
          reduced: true,
        );
        await _ready(tester);
        _toolbar(tester).onPageSubmitted(2);
        await tester.pump();
        await tester.pump();
        expect(_toolbar(tester).currentPage, 2);
        expect(_curl, findsNothing);
        final opacity = tester.widget<Opacity>(
          find
              .ancestor(
                  of: find.byType(PdfViewer), matching: find.byType(Opacity))
              .first,
        );
        expect(opacity.opacity, 1);
        expect(pdf.document.pages.expand((page) => page.curlWidths), isEmpty);
        pdf.expectNoOriginalIO();
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        pdf.release();
        host.dispose();
      }
    });
  }

  for (final mode in _modes) {
    _test(
        '$mode bare reader Find beats collection fallback and reveals native matches',
        (tester) async {
      final pdf = await _Fixture.prepare(
          factory, 'bare-find-$mode', ['Chapter one', 'Needle needle', 'End']);
      final host = _Host();
      try {
        await _mount(tester, pdf.preview(bare: true), host, mode: mode);
        await _ready(tester);
        final viewer = tester.state(find.byType(PdfViewer));
        final controller = _viewer(tester);
        final normalBounds = tester.getRect(find.byType(PdfViewer));
        expect(find.byType(PdfPreviewToolbar), findsNothing);
        expect(find.byType(FindReplaceBar), findsNothing);
        host.outerFocus.requestFocus();
        await tester.pump();
        await _controlF(
            tester); // No hover/autofocus required for the active chapter.
        expect(host.finds, 0);
        expect(find.byType(FindReplaceBar), findsOneWidget);
        expect(find.byType(PdfPreviewToolbar), findsNothing);
        final zoom = controller.currentZoom;
        await tester.enterText(find.byKey(_query), 'needle');
        await _settledSearch(tester, 2);
        await _motion(tester);
        expect(controller.pageNumber, 2);
        final page = controller.layout.pageLayouts[1];
        expect(
          page.contains(controller.visibleRect.center),
          isTrue,
          reason:
              'Find must reveal this page, not a sliver below its neighbour',
        );
        expect(controller.currentZoom, closeTo(zoom, 0.001));
        final hit = Offset(page.left + 50, page.top + 48);
        expect(controller.visibleRect.contains(hit), isTrue);
        final palette =
            PdfPreviewPalette.of(tester.element(find.byType(PdfPreview)));
        final painted =
            await _pixelAt(tester, controller.documentToGlobal(hit)!);
        final expected = Color.alphaBlend(palette.activeSearchMatch, _paper);
        expect(painted.r, closeTo(expected.r, 2 / 255));
        expect(painted.g, closeTo(expected.g, 2 / 255));
        expect(painted.b, closeTo(expected.b, 2 / 255));
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await _motion(tester);
        expect(_bar(tester).currentMatch, 2);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape,
            physicalKey: PhysicalKeyboardKey.escape);
        await _motion(tester);
        expect(find.byType(FindReplaceBar), findsNothing);
        expect(find.byType(PdfPreviewToolbar), findsNothing);
        expect(tester.getRect(find.byType(PdfViewer)), normalBounds);
        expect(tester.state(find.byType(PdfViewer)), same(viewer));
        expect(_viewer(tester), same(controller));
        pdf.expectNoOriginalIO();
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        pdf.release();
        host.dispose();
      }
    });
  }

  _test('BookChapterStage settings update the retained bare PDF immediately',
      (tester) async {
    final pdf = await _Fixture.prepare(
        factory, 'book-settings', ['One', 'Two', 'Three']);
    final host = _Host();
    final settings = ValueNotifier(
        const BookReaderSettings(transition: BookPageTransition.none));
    final chapter = BookChapter(
      view: fileControlView('book-chapter', 'Chapter.pdf', pdf.file.path),
      kind: BookChapterKind.pdf,
      index: 0,
    );
    try {
      await _mount(
        tester,
        ValueListenableBuilder<BookReaderSettings>(
          valueListenable: settings,
          builder: (context, settings, _) => BookChapterStage(
            chapter: chapter,
            palette: BookReaderPalette.of(context, settings.theme),
            settings: settings,
            onProgress: (_) {},
            onReachedEnd: () {},
          ),
        ),
        host,
      );
      await _ready(tester);
      final preview = tester.state(find.byType(PdfPreview));
      final viewer = tester.state(find.byType(PdfViewer));
      final controller = _viewer(tester);
      final original = controller.layout.pageLayouts;
      expect(original[1].top, greaterThan(original[0].bottom));
      settings.value = settings.value.copyWith(flow: BookReaderFlow.horizontal);
      await _motion(tester);
      final horizontal = controller.layout.pageLayouts;
      expect(horizontal[0].center.dy, horizontal[1].center.dy);
      expect(horizontal[1].left, greaterThan(horizontal[0].right));
      settings.value = settings.value.copyWith(
        flow: BookReaderFlow.paged,
        transition: BookPageTransition.curl,
      );
      await _motion(tester);
      expect(
          controller.layout.pageLayouts[1].top, greaterThan(original[1].top));
      expect(tester.state(find.byType(PdfPreview)), same(preview));
      expect(tester.state(find.byType(PdfViewer)), same(viewer));
      expect(_viewer(tester), same(controller));
      expect(find.byType(PdfPreviewToolbar), findsNothing);
      await _controlF(tester);
      expect(find.byType(FindReplaceBar), findsOneWidget);
      expect(host.finds, 0);
      expect(factory.opened, [pdf.file.path]);
      pdf.expectNoOriginalIO();
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      settings.dispose();
      pdf.release();
      host.dispose();
    }
  });

  for (final bare in [true, false]) {
    _test(
        '${bare ? 'bare' : 'normal'} unreadable PDF does not swallow outer find',
        (tester) async {
      final pdf =
          await _Fixture.prepare(factory, 'ineligible-$bare', ['Alpha']);
      final host = _Host();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      pdf.ref
          .resolveListenable()
          .setError(const PdfException('Synthetic unreadable PDF'));
      try {
        await _mount(tester, pdf.preview(bare: bare), host);
        await mouse.addPointer(
          location: tester.getCenter(find.byType(PdfViewer)),
        );
        host.outerFocus.requestFocus();
        await tester.pump();
        await _controlF(tester);
        expect(host.finds, 1);
        expect(find.byType(PdfSearchToolbar), findsNothing);
        expect(pdf.scanCalls, isEmpty);
        pdf.expectNoOriginalIO();
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await _unmount(tester);
        pdf.release();
        host.dispose();
      }
    });
  }
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      (tester) async {
        var clients = 0;
        await HttpOverrides.runZoned(
          () => body(tester),
          createHttpClient: (_) {
            clients++;
            throw StateError('PDF find must not upload or download anything');
          },
        );
        expect(clients, 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      timeout: const Timeout(Duration(seconds: 30)),
    );

ThemeData _theme(String mode) => DesktopAppearance()
    .getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Future<void> _mount(
  WidgetTester tester,
  Widget child,
  _Host host, {
  String mode = 'light',
  double scale = 1,
  double dpr = 1,
  bool reduced = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1100, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = _theme(mode);
  final defaults = AppFlowyDefaultTheme();
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: _Strings(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: theme,
          themeAnimationDuration: Duration.zero,
          builder: (context, navigator) => AppFlowyTheme(
            data: PremiumTheme.appFlowyTheme(
              base: mode == 'dark' ? defaults.dark() : defaults.light(),
              palette: theme.extension<PremiumThemeExtension>()!,
              brightness: theme.brightness,
            ),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                devicePixelRatio: dpr,
                disableAnimations: reduced,
              ),
              child: TooltipVisibility(visible: false, child: navigator!),
            ),
          ),
          home: Scaffold(
            body: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                    host.find,
              },
              child: ContextualFindRegion(
                debugLabel: 'Outer document',
                onFind: host.find,
                child: Focus(
                  focusNode: host.outerFocus,
                  autofocus: true,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 240,
                            child: TextField(
                              key: _outsideInput,
                              controller: host.outside,
                              focusNode: host.outsideFocus,
                            ),
                          ),
                          const SizedBox(width: 20),
                          ContextualFindRegion(
                            debugLabel: 'Other viewer',
                            onFind: host.findOther,
                            child: Focus(
                              focusNode: host.otherFocus,
                              child: const SizedBox(
                                key: _otherSurface,
                                width: 150,
                                height: 56,
                                child: Center(child: Text('Other viewer')),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: RepaintBoundary(key: _capture, child: child),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _motion(tester);
}

Future<void> _motion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 220));
  await tester.runAsync(() async {});
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  // A callback may have dirtied State while the previous toolbar widget still
  // reports the previous query's already-complete count. Read the next frame.
  await tester.pump();
  for (var i = 0; i < 80 && !condition(); i++) {
    await tester.runAsync(() async {});
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    condition(),
    isTrue,
    reason: 'The real PDF viewer must reach the requested state',
  );
}

Future<void> _ready(WidgetTester tester, {PdfDocument? expectedDocument}) =>
    _until(tester, () {
      final viewer = _viewer(tester);
      final region = tester.widget<ContextualFindRegion>(
        find.descendant(
            of: find.byType(PdfPreview),
            matching: find.byType(ContextualFindRegion)),
      );
      if (!region.enabled || !viewer.isReady) return false;
      if (expectedDocument == null) return true;
      // useDocument reads the ref's cache, not the viewer's attached handle.
      // This assertion specifically verifies pdfrx accepted the replacement.
      // ignore: deprecated_member_use
      return identical(viewer.document, expectedDocument);
    });
Future<void> _settledSearch(WidgetTester tester, int count) async {
  await _until(tester, () => !_bar(tester).isSearching);
  final bar = _bar(tester);
  expect(
    bar.matchCount,
    count,
    reason: 'Query "${bar.controller.text}": '
        'case=${bar.options.caseSensitive}, word=${bar.options.wholeWord}, '
        'regex=${bar.options.useRegex}; status=${bar.statusOverride}',
  );
}

PdfPreviewToolbar _toolbar(WidgetTester tester) =>
    tester.widget(find.byType(PdfPreviewToolbar));
PdfSearchToolbar _bar(WidgetTester tester) =>
    tester.widget(find.byType(PdfSearchToolbar));
PdfViewerController _viewer(WidgetTester tester) =>
    tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;

Finder get _queryInput => find.descendant(
      of: find.byKey(_query),
      matching: find.byKey(const ValueKey('findTextField')),
    );

Finder get _curl => find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is PageTurnPainter,
    );

Future<void> _open(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip('Search document (Ctrl/Cmd F)'));
  await tester.tap(find.byTooltip('Search document (Ctrl/Cmd F)'));
  await _motion(tester);
  expect(find.byType(PdfSearchToolbar), findsOneWidget);
}

Future<void> _controlF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
      physicalKey: PhysicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF,
      physicalKey: PhysicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
      physicalKey: PhysicalKeyboardKey.controlLeft);
  await _motion(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  for (final field
      in tester.stateList<EditableTextState>(find.byType(EditableText))) {
    field.hideToolbar();
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() async {});
  await tester.pump();
}

Rect _editableLine(EditableTextState state) {
  final render = state.renderEditable;
  final length = state.widget.controller.text.length;
  final boxes = render
      .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: length));
  return boxes
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b))
      .shift(render.localToGlobal(Offset.zero));
}

Rect _paragraphLine(WidgetTester tester, Finder finder) {
  final render = tester.renderObject<RenderParagraph>(finder);
  final boxes = render.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: render.text.toPlainText().length,
    ),
  );
  return boxes
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b))
      .shift(render.localToGlobal(Offset.zero));
}

Future<Color> _pixelAt(WidgetTester tester, Offset global) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_capture));
  final local = boundary.globalToLocal(global);
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  try {
    expect(local.dx, inInclusiveRange(0, image.width - 1));
    expect(local.dy, inInclusiveRange(0, image.height - 1));
    final data = (await tester.runAsync(() => image.toByteData()))!;
    final offset = (local.dy.floor() * image.width + local.dx.floor()) * 4;
    return Color.fromARGB(
      data.getUint8(offset + 3),
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
    );
  } finally {
    image.dispose();
  }
}

OcrResult _ocr(String text, Rect bounds) => OcrResult(
      engine: 'fixture',
      lines: [
        OcrLine.fromWords([OcrWord(text: text, bounds: bounds)]),
      ],
    );

class _Host {
  final outerFocus = FocusNode(debugLabel: 'Outer document editor');
  final outsideFocus = FocusNode(debugLabel: 'Outside PDF input');
  final otherFocus = FocusNode(debugLabel: 'Other viewer find');
  final outside = TextEditingController();
  int finds = 0;
  int otherFinds = 0;
  void find() {
    finds++;
    outerFocus.requestFocus();
  }

  void findOther() {
    otherFinds++;
    otherFocus.requestFocus();
  }

  void dispose() {
    outerFocus.dispose();
    outsideFocus.dispose();
    otherFocus.dispose();
    outside.dispose();
  }
}

class _Fixture {
  _Fixture(this.file, this.ref, this.document, this.release);
  final _UnreadFile file;
  final PdfDocumentRef ref;
  final _Document document;
  final VoidCallback release;
  final scanCalls = <int>[];
  final metadataWrites = <Map<String, dynamic>>[];
  int indexCreations = 0;
  PdfOcrPageScanner scanner = (_) async => OcrResult.empty;
  static Future<_Fixture> prepare(
    _Factory factory,
    String id,
    List<String> pages,
  ) async {
    final file = _UnreadFile('C:/pdf-find-synthetic/$id.pdf');
    final document = _Document(file.path, factory.raster, pages);
    factory.documents[file.path] = document;
    final ref = PdfDocumentRefFile(file.path);
    final listenable = ref.resolveListenable();
    final release = listenable.addListener(() {});
    await listenable.load();
    return _Fixture(file, ref, document, release);
  }

  PdfPreview preview({
    bool bare = false,
    bool fullscreen = false,
    Map<String, dynamic> metadata = const {'pageTransition': 'none'},
  }) =>
      PdfPreview(
        file: file,
        name: 'Search fixture.pdf',
        metadata: metadata,
        onMetadataChanged: metadataWrites.add,
        editable: false,
        bare: bare,
        fullscreen: fullscreen,
        sourceDocumentRef: ref,
        ocrIndexFactory: () {
          indexCreations++;
          return PdfOcrSearchIndex(
            scanPage: (page) {
              scanCalls.add(page.pageNumber);
              return scanner(page);
            },
          );
        },
      );
  void expectNoOriginalIO() {
    expect(file.reads, 0);
    expect(file.writes, 0);
    expect(metadataWrites, isEmpty);
  }
}

class _UnreadFile extends Fake implements File {
  _UnreadFile(this.path);
  @override
  final String path;
  int reads = 0;
  int writes = 0;
  @override
  Future<Uint8List> readAsBytes() async {
    reads++;
    throw StateError('Search must not read original PDF bytes');
  }

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    writes++;
    throw StateError('Search must never modify PDF bytes');
  }
}

class _Factory extends Fake implements PdfDocumentFactory {
  _Factory(this.raster);
  final ui.Image raster;
  final documents = <String, _Document>{};
  final opened = <String>[];
  @override
  Future<PdfDocument> openFile(
    String path, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) async {
    opened.add(path);
    return documents[path]!;
  }
}

class _Document extends PdfDocument {
  _Document(String name, ui.Image raster, List<String> texts)
      : super(sourceName: name) {
    pages = [
      for (var i = 0; i < texts.length; i++)
        _Page(this, raster, i + 1, texts[i]),
    ];
  }
  @override
  late final List<_Page> pages;
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
  _Page(this.document, this.raster, this.pageNumber, this.text);
  @override
  final PdfDocument document;
  final ui.Image raster;
  final String text;
  Future<void>? textGate;
  Future<void>? curlGate;
  final curlWidths = <double>[];
  Object? textFailure;
  @override
  final int pageNumber;
  @override
  double get width => 600;
  @override
  double get height => 800;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
  @override
  PdfPageRenderCancellationToken createCancellationToken() => _Cancellation();
  @override
  Future<PdfPageText> loadText() async {
    if (textGate != null) await textGate;
    if (textFailure case final error?) throw error;
    return _Text(pageNumber, text);
  }

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
  }) async {
    if (cancellationToken == null) {
      curlWidths.add(fullWidth!);
      if (curlGate != null) await curlGate;
    }
    return cancellationToken?.isCanceled == true ? null : _Bitmap(raster);
  }
}

class _Cancellation extends PdfPageRenderCancellationToken {
  bool canceled = false;
  @override
  bool get isCanceled => canceled;
  @override
  void cancel() => canceled = true;
}

class _Bitmap extends PdfImage {
  _Bitmap(this.image);
  final ui.Image image;
  @override
  int get width => image.width;
  @override
  int get height => image.height;
  @override
  ui.PixelFormat get format => ui.PixelFormat.rgba8888;
  @override
  Uint8List get pixels => Uint8List(width * height * 4);
  @override
  Future<ui.Image> createImage() async => image.clone();
  @override
  void dispose() {}
}

// Only PDF decoding is fake. allMatches is the installed pdfrx implementation,
// with real text ranges/character boxes rather than a canned search response.
class _Text extends PdfPageText {
  _Text(this.pageNumber, this.fullText);
  @override
  final int pageNumber;
  @override
  final String fullText;
  @override
  List<PdfPageTextFragment> get fragments => fullText.isEmpty
      ? []
      : [
          PdfPageTextFragment.fromParams(
            0,
            fullText.length,
            PdfRect(40, 760, 40 + fullText.length * 7.0, 742),
            fullText,
            charRects: [
              for (var i = 0; i < fullText.length; i++)
                PdfRect(40 + i * 7.0, 760, 47 + i * 7.0, 742),
            ],
          ),
        ];
}

class _Strings extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_strings);
}

class _BundledMono extends GoogleFontsFamilyWithVariant {
  _BundledMono(FontWeight weight)
      : super(
          family: 'JetBrainsMono',
          googleFontsVariant: GoogleFontsVariant(
            fontWeight: weight,
            fontStyle: FontStyle.normal,
          ),
        );
  @override
  String toApiFilenamePrefix() => 'RobotoMono-Regular';
}
