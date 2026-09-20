import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:archive/archive.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// Test-only bundled font boundary, as in fullscreen_media_actions_test.dart.
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

const _appearances = ['light', 'dark', 'paper'];
const _frame = ValueKey('file-toolbar-frame');
const _extra = ValueKey('file-toolbar-extra');
const _copyCode = ValueKey('code-copy');
const _fade = Duration(milliseconds: 141);
const _kinds = [
  FilePreviewKind.text,
  FilePreviewKind.code,
  FilePreviewKind.archive,
  FilePreviewKind.notebook,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool fontFetching;
  late PdfDocumentFactory nativePdfFactory;
  late _PdfFactory pdfFactory;
  late ui.Image raster;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
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
          file: GoogleFontsFile('bundled-toolbar-fixture', 0),
        ),
      );
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final family in _appearances
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
    Canvas(recorder).drawColor(const Color(0xFFE3D9C5), BlendMode.src);
    final picture = recorder.endRecording();
    raster = await picture.toImage(40, 50);
    picture.dispose();
    nativePdfFactory = PdfDocumentFactory.instance;
  });

  setUp(() {
    pdfFactory = _PdfFactory(raster);
    PdfDocumentFactory.instance = pdfFactory;
  });

  tearDown(() => PdfDocumentFactory.instance = nativePdfFactory);
  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = fontFetching;
    font_io.clearCache();
    raster.dispose();
  });

  for (final mode in _appearances) {
    _test(
        '$mode: actual text preview retains selection and scroll through reveal',
        (tester) async {
      final file = _file(FilePreviewKind.text);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final semantics = tester.ensureSemantics();
      try {
        await mouse.addPointer(location: const Offset(2, 2));
        await _mount(tester, mode, _preview(file, FilePreviewKind.text));
        await _ready(tester, FilePreviewKind.text);
        final action = find.byKey(_extra);
        final toolbar = _toolbarFor(action);
        final preview = tester.state(find.byType(FilePreview));
        final text = find.byType(SelectableText);
        final editable =
            find.descendant(of: text, matching: find.byType(EditableText));
        final body = tester.state(editable);
        final field = tester.widget<EditableText>(editable);
        final position = Scrollable.of(tester.element(text)).position;
        field.focusNode.requestFocus();
        field.controller.selection =
            const TextSelection(baseOffset: 4, extentOffset: 18);
        position.jumpTo(80);
        await _motion(tester);
        _expectToolbar(tester, toolbar, false);
        expect(action.hitTestable(), findsNothing);
        _expectIdentity(file.name);
        final bounds = tester.getRect(text);

        await mouse.moveTo(
          tester.getRect(find.byKey(_frame)).bottomLeft + const Offset(50, -30),
        );
        await _motion(tester);
        _expectToolbar(tester, toolbar, true);
        // The tooltip/role wrapper and the actionable focus node need not
        // merge. Inspect the real gesture's node, not a wrapper without tap.
        final node = tester.getSemantics(
          find.descendant(of: action, matching: find.byType(GestureDetector)),
        );
        final nodeId = node.id;
        expect(
          node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        expect(_semanticsIds(tester), contains(nodeId));
        await mouse.moveTo(const Offset(2, 2));
        await tester.pump();
        expect(action.hitTestable(), findsNothing);
        expect(_semanticsIds(tester), isNot(contains(nodeId)));
        await tester.pump(_fade);
        expect(tester.state(find.byType(FilePreview)), same(preview));
        expect(tester.state(editable), same(body));
        expect(tester.getRect(text), bounds);
        expect(
          field.controller.selection,
          const TextSelection(baseOffset: 4, extentOffset: 18),
        );
        expect(position.pixels, 80);

        await _tabTo(tester, action);
        _expectToolbar(tester, toolbar, true);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        await mouse.moveTo(const Offset(3, 3));
        await _motion(tester);
        _expectToolbar(tester, toolbar, true);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        _focusOutside(tester);
        await _motion(tester);
        _expectToolbar(tester, toolbar, false);

        // A first touch reveals, rather than accidentally activating, hidden tools.
        await tester.tapAt(tester.getCenter(action));
        await _motion(tester);
        expect(find.byType(AppMenuSurface), findsNothing);
        _expectToolbar(tester, toolbar, true);
        expect(tester.state(editable), same(body));

        field.focusNode.requestFocus();
        await _motion(tester);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await _motion(tester);
        final search = find.byType(FindReplaceBar);
        expect(search, findsOneWidget);
        await tester.enterText(
          find.descendant(of: search, matching: find.byType(TextField)).first,
          'preview',
        );
        await _motion(tester);
        _focusOutside(tester);
        await mouse.moveTo(tester.getCenter(find.byKey(_frame)));
        await mouse.moveTo(const Offset(2, 2));
        await _motion(tester);
        expect(search.hitTestable(), findsOneWidget);
        expect(
          find.ancestor(of: search, matching: find.byType(PreviewToolbar)),
          findsNothing,
        );
        expect(tester.state(editable), same(body));
        expect(file.reads, 1);
        expect(file.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        try {
          await _unmount(tester);
        } finally {
          semantics.dispose();
        }
      }
    });

    _test(
        '$mode: actual code file retains its draft and action focus when narrowed',
        (tester) async {
      final file = _file(FilePreviewKind.code);
      final width = ValueNotifier(760.0);
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
        await _mount(
          tester,
          mode,
          _preview(file, FilePreviewKind.code, editable: true),
          width: width,
        );
        await _ready(tester, FilePreviewKind.code);
        final copy = find.byKey(_copyCode);
        final toolbar = _toolbarFor(copy);
        _expectToolbar(tester, toolbar, false);
        _expectIdentity(file.name);
        _expectIdentity('Javascript');
        expect(find.byType(InAppWebView), findsNothing);
        final runner = tester.state(find.byType(SandboxedCodeRunner));
        final copyState = tester.state(copy);
        final source = find.byType(TextField);
        final field = tester.widget<TextField>(source);
        final editor = tester.state(find.byType(EditableText));

        await _tabTo(tester, find.byTooltip('Select language'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        _expectToolbar(tester, toolbar, true);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        await tester.enterText(source, 'console.log("retained draft");');
        field.controller!.selection =
            const TextSelection(baseOffset: 4, extentOffset: 10);
        await _motion(tester);
        _expectToolbar(tester, toolbar, true);
        await _tabTo(tester, copy);
        width.value = 300;
        await _motion(tester);
        expect(tester.state(copy), same(copyState));
        expect(_focusedInside(copy), isTrue);
        _expectIdentity(file.name);
        _expectIdentity('Javascript');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _motion(tester);
        expect(clipboard, ['console.log("retained draft");']);
        expect(find.text('Copied'), findsOneWidget);
        expect(tester.state(find.byType(SandboxedCodeRunner)), same(runner));
        expect(tester.state(find.byType(EditableText)), same(editor));
        expect(
          tester.widget<TextField>(source).controller,
          same(field.controller),
        );
        expect(field.controller!.text, 'console.log("retained draft");');
        expect(
          field.controller!.selection,
          const TextSelection(baseOffset: 4, extentOffset: 10),
        );
        _focusOutside(tester);
        await tester.pump(const Duration(seconds: 3));
        await _motion(tester);
        _expectToolbar(tester, toolbar, false);
        expect(file.reads, 1);
        // The explicit source edit, not hover or resize.
        expect(file.writes, 1);
        expect(find.byType(InAppWebView), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        width.dispose();
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
    });

    _test('$mode: archive menus and search retain the gallery at narrow widths',
        (tester) async {
      final file = _file(FilePreviewKind.archive);
      final width = ValueNotifier(1100.0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: const Offset(2, 2));
        await _mount(
          tester,
          mode,
          _preview(file, FilePreviewKind.archive),
          width: width,
        );
        await _ready(tester, FilePreviewKind.archive);
        final explorer = tester.state(find.byType(ArchiveExplorer));
        final cardSize = find.byTooltip('Card size');
        final toolbar = _toolbarFor(cardSize);
        final gallery = tester.element(find.byType(ArchiveGallery));
        _expectToolbar(tester, toolbar, false);
        _expectIdentity(file.name);
        expect(find.textContaining('ZIP archive'), findsOneWidget);

        await _tabTo(tester, cardSize);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        await mouse.moveTo(const Offset(3, 3));
        await _motion(tester);
        _expectToolbar(tester, toolbar, true);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await _tabTo(tester, find.byTooltip('Search this archive  ·  Ctrl+F'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final search = find.byType(TextField);
        await tester.enterText(search, 'readme');
        await _waitFor(
          tester,
          () => find.byType(FolderGalleryCard).evaluate().length == 1,
        );
        final input = tester.widget<TextField>(search);
        final inputState = tester.state(find.byType(EditableText));
        final selection = input.controller!.selection;
        for (final next in [300.0, 800.0, 320.0]) {
          width.value = next;
          await _motion(tester);
          expect(tester.state(find.byType(EditableText)), same(inputState));
          expect(input.controller!.text, 'readme');
          expect(input.controller!.selection, selection);
          expect(input.focusNode!.hasFocus, isTrue);
          expect(tester.element(find.byType(ArchiveGallery)), same(gallery));
          expect(tester.state(find.byType(ArchiveExplorer)), same(explorer));
          _expectIdentity(file.name);
          _expectToolbar(tester, toolbar, true);
          expect(tester.takeException(), isNull);
        }
        _focusOutside(tester);
        await _motion(tester);
        _expectToolbar(tester, toolbar, true); // An open search stays usable.
        expect(file.byteReads, 1);
        expect(file.writes, 0);
      } finally {
        await mouse.removePointer();
        await _unmount(tester);
        width.dispose();
      }
    });

    _test(
        '$mode: notebook header keeps identity/status and cell state while resizing',
        (tester) async {
      final file = _file(FilePreviewKind.notebook);
      final width = ValueNotifier(760.0);
      try {
        await _mount(
          tester,
          mode,
          _preview(file, FilePreviewKind.notebook, editable: true),
          width: width,
        );
        await _ready(tester, FilePreviewKind.notebook);
        final menu = find.byTooltip('Notebook actions');
        final toolbar = _toolbarFor(menu);
        final notebook = tester.state(find.byType(NotebookView));
        _expectToolbar(tester, toolbar, false);
        _expectIdentity(file.name);
        _expectIdentity('Idle');
        await _tabTo(tester, menu);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.textContaining('· not started'), findsOneWidget);
        _expectToolbar(tester, toolbar, true);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        final field = find.byType(TextField).first;
        await tester.enterText(field, 'answer = 42');
        final input = tester.widget<TextField>(field);
        input.controller!.selection = const TextSelection.collapsed(offset: 6);
        final inputState = tester.state(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        for (final next in [280.0, 700.0, 320.0]) {
          width.value = next;
          await _motion(tester);
          expect(tester.state(find.byType(NotebookView)), same(notebook));
          expect(
            tester.state(
              find.descendant(of: field, matching: find.byType(EditableText)),
            ),
            same(inputState),
          );
          expect(input.controller!.text, 'answer = 42');
          expect(
            input.controller!.selection,
            const TextSelection.collapsed(offset: 6),
          );
          expect(input.focusNode!.hasFocus, isTrue);
          _expectToolbar(tester, toolbar, true);
          _expectIdentity(file.name);
          _expectIdentity('Idle');
          expect(tester.takeException(), isNull);
        }
        _focusOutside(tester);
        await _motion(tester);
        _expectToolbar(tester, toolbar, false);
        expect(file.reads, 1);
      } finally {
        await _unmount(tester);
        width.dispose();
      }
    });

    _test('$mode: PDF frame hover, page draft and menus retain the real viewer',
        (tester) async {
      final pdf = await _PdfFixture.prepare('embed-$mode');
      final width = ValueNotifier(700.0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: const Offset(2, 2));
        await _mount(
          tester,
          mode,
          ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, value, child) => ResizableMedia(
              width: value,
              height: 480,
              onResize: (value) => width.value = value,
              child: child!,
            ),
            child: pdf.preview(),
          ),
          fixedWidth: 1100,
        );
        await _waitFor(tester, () => _pdfToolbar(tester).ready);
        final viewer = tester.state(find.byType(PdfViewer));
        final controller =
            tester.widget<PdfViewer>(find.byType(PdfViewer)).controller;
        final menu = find.byKey(const ValueKey('pdf-overflow-menu'));
        final toolbar = _toolbarFor(menu);
        final bounds =
            tester.getRect(find.byKey(const ValueKey('resizable_media')));
        _expectToolbar(tester, toolbar, false);
        _expectIdentity(pdf.name);
        await mouse.moveTo(Offset(bounds.left - 30, bounds.center.dy));
        await _motion(tester);
        _expectToolbar(tester, toolbar, false);
        await mouse.moveTo(bounds.center);
        await _motion(tester);
        _expectToolbar(tester, toolbar, true);
        final matrix = controller!.value.clone();
        await tester.tap(menu, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        await mouse.moveTo(const Offset(2, 2));
        await _motion(tester);
        _expectToolbar(tester, toolbar, true);
        expect(controller.value, matrix);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        _focusOutside(tester);
        await _motion(tester);
        _expectToolbar(tester, toolbar, false);

        final page = find.byKey(const ValueKey('pdf-page-number-field'));
        await _tabTo(tester, page);
        await tester.enterText(page, '2');
        final input = tester.widget<TextField>(page);
        width.value = 320;
        await _motion(tester);
        expect(
          tester.widget<TextField>(page).controller,
          same(input.controller),
        );
        expect(input.controller!.text, '2');
        expect(input.focusNode!.hasFocus, isTrue);
        expect(tester.state(find.byType(PdfViewer)), same(viewer));
        expect(pdfFactory.opened, [pdf.file.path]);
        _expectToolbar(tester, toolbar, true);

        await _tabTo(tester, find.byTooltip('Search document (Ctrl/Cmd F)'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _motion(tester);
        expect(find.byType(PdfSearchToolbar), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('pdf-search-field')),
          'Searchable',
        );
        await tester.pump(const Duration(milliseconds: 400));
        _focusOutside(tester);
        await _motion(tester);
        expect(
          find.byKey(const ValueKey('pdf-search-field')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.state(find.byType(PdfViewer)), same(viewer));
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await _unmount(tester);
        width.dispose();
        pdf.release();
      }
    });

    for (final kind in _kinds) {
      for (final accessible in [false, true]) {
        _test('$mode: $kind fits 280px / 2x text, accessibility=$accessible',
            (tester) async {
          final file = _file(kind);
          try {
            await _mount(
              tester,
              mode,
              _preview(file, kind),
              fixedWidth: 280,
              scale: 2,
              accessible: accessible,
              reduced: true,
            );
            await _ready(tester, kind);
            final toolbar = _toolbarFor(_trigger(kind));
            _expectToolbar(tester, toolbar, accessible);
            expect(_opacity(tester, toolbar).duration, Duration.zero);
            _expectIdentity(file.name);
            final context = tester.element(_trigger(kind));
            expect(PaperTheme.isEnabled(context), mode == 'paper');
            expect(
              Theme.of(context).brightness,
              mode == 'dark' ? Brightness.dark : Brightness.light,
            );
            if (mode == 'paper' && kind == FilePreviewKind.code) {
              expect(
                codeBlockSurfaceColor(context),
                PaperTheme.codeBlockBackground,
              );
            }
            expect(file.writes, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await _unmount(tester);
          }
        });
      }
    }

    for (final scale in [1.0, 2.0]) {
      _test(
          '$mode: the title-less PDF toolbar also reveals as one group at ${scale}x',
          (tester) async {
        try {
          await _mount(
            tester,
            mode,
            PreviewToolbarRegion(
              child: Align(
                alignment: Alignment.topLeft,
                child: _titlelessPdfToolbar(),
              ),
            ),
            fixedWidth: 320,
            scale: scale,
          );
          final field = find.byType(PdfPageNumberField);
          final toolbar = _toolbarFor(field);
          _expectToolbar(tester, toolbar, false);
          expect(find.byType(DocumentViewportHeader), findsNothing);
          await _tabTo(
            tester,
            find.byKey(const ValueKey('pdf-page-number-field')),
          );
          _expectToolbar(tester, toolbar, true);
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester);
        }
      });
    }
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final kind in _kinds) {
      _test('$platform: $kind top actions never require hover', (tester) async {
        try {
          await _mount(
            tester,
            'paper',
            _preview(_file(kind), kind),
            fixedWidth: 320,
            platform: platform,
          );
          await _ready(tester, kind);
          _expectToolbar(tester, _toolbarFor(_trigger(kind)), true);
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester);
        }
      });
    }
  }

  for (final kind in _kinds) {
    _test('standalone $kind retains visible chrome without a preview region',
        (tester) async {
      try {
        await _mount(
          tester,
          'paper',
          _preview(_file(kind), kind, framed: false),
        );
        await _ready(tester, kind);
        await tester.pump(const Duration(seconds: 4));
        expect(find.byType(PreviewToolbarRegion), findsNothing);
        _expectToolbar(tester, _toolbarFor(_trigger(kind)), true);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
      }
    });
  }

  _test('bare text remains renderer-only and source editing pins Done actions',
      (tester) async {
    final file = _file(FilePreviewKind.text);
    try {
      await _mount(
        tester,
        'paper',
        _preview(file, FilePreviewKind.text, bare: true),
      );
      await _ready(tester, FilePreviewKind.text);
      expect(find.byType(DocumentViewportHeader), findsNothing);
      expect(find.byType(PreviewToolbarRegion), findsNothing);
      expect(find.byType(PreviewToolbar), findsNothing);
      await _unmount(tester);
      await _mount(
        tester,
        'paper',
        _preview(
          file,
          FilePreviewKind.text,
          editable: true,
          metadata: const {filePreviewEditModeKey: true},
        ),
      );
      await _waitFor(
        tester,
        () => find.byType(TextField).evaluate().isNotEmpty,
      );
      _expectToolbar(tester, _toolbarFor(find.byKey(_extra)), true);
      expect(find.textContaining('Editing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
    }
  });

  for (final pointer in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    _test('preview load recovery stays clickable with no hover: $pointer',
        (tester) async {
      final file = _file(FilePreviewKind.text)..available = false;
      try {
        await _mount(
          tester,
          'paper',
          _preview(file, FilePreviewKind.text),
          fixedWidth: 280,
        );
        await _waitFor(tester, () => find.text('Retry').evaluate().isNotEmpty);
        final preview = tester.state(find.byType(FilePreview));
        expect(find.text('Retry').hitTestable(), findsOneWidget);
        expect(file.existenceChecks, [false]);
        expect(file.reads, 0);
        file.available = true;
        await tester.tap(find.text('Retry'), kind: pointer);
        await _ready(tester, FilePreviewKind.text);
        expect(tester.state(find.byType(FilePreview)), same(preview));
        expect(find.text('Retry'), findsNothing);
        expect(
          tester
              .widget<SelectableText>(find.byType(SelectableText))
              .textSpan!
              .toPlainText(),
          utf8.decode(file.bytes),
        );
        expect(file.existenceChecks, [false, true]);
        expect(file.reads, 1);
        expect(file.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
      }
    });
  }

  _test(
      'an empty archive retains setup actions without revealing every archive',
      (tester) async {
    final file =
        _MemoryFile.bytes('empty.zip', ZipEncoder().encode(Archive())!);
    try {
      await _mount(
        tester,
        'paper',
        _preview(file, FilePreviewKind.archive, editable: true),
      );
      await _waitFor(
        tester,
        () => find.text('This archive is empty').evaluate().isNotEmpty,
      );
      _expectToolbar(
        tester,
        _toolbarFor(find.byTooltip('Add files to this archive')),
        true,
      );
      expect(
        find.byTooltip('Add files to this archive').hitTestable(),
        findsOneWidget,
      );
      expect(file.byteReads, 1);
      expect(file.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
    }
  });

  _test(
      'direct embedded archive body menu holds the region below its State context',
      (tester) async {
    final file = _file(FilePreviewKind.archive);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final reportError = FlutterError.onError!;
    FlutterErrorDetails? lastError;
    FlutterError.onError = (details) {
      lastError = details;
      reportError(details);
    };
    try {
      await mouse.addPointer(location: const Offset(2, 2));
      await _mount(
        tester,
        'paper',
        ArchiveExplorer(file: file, name: file.name, editable: false),
      );
      await _ready(tester, FilePreviewKind.archive);
      final toolbar = _toolbarFor(find.byTooltip('Card size'));
      final frame = tester.getRect(find.byKey(_frame));
      await mouse.moveTo(frame.bottomLeft + const Offset(8, -8));
      await _motion(tester);
      final click = await tester.startGesture(
        frame.bottomLeft + const Offset(8, -8),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await click.up();
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuSurface), findsOneWidget);
      await mouse.moveTo(const Offset(2, 2));
      await _motion(tester);
      _expectToolbar(tester, toolbar, true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      _focusOutside(tester);
      await _motion(tester);
      _expectToolbar(tester, toolbar, false);
      expect(file.byteReads, 1);
      expect(tester.takeException(), isNull, reason: lastError?.toString());
    } finally {
      try {
        await mouse.removePointer();
        await _unmount(tester);
      } finally {
        FlutterError.onError = reportError;
      }
    }
  });

  _test(
      'stored PDF idle hide remains fullscreen-only; all fullscreen menus pin it',
      (tester) async {
    final pdf = await _PdfFixture.prepare('fullscreen-menus');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: const Offset(2, 2));
      await _mount(
        tester,
        'paper',
        pdf.preview(autoHide: true),
        fixedWidth: 1100,
      );
      await _waitFor(tester, () => _pdfToolbar(tester).ready);
      await tester.pump(const Duration(seconds: 4));
      await _motion(tester);
      _expectToolbar(
        tester,
        _toolbarFor(find.byKey(const ValueKey('pdf-overflow-menu'))),
        true,
      );
      expect(find.byType(PreviewToolbarRegion), findsNothing);
      await _unmount(tester);

      await _mount(
        tester,
        'paper',
        pdf.preview(fullscreen: true, autoHide: true),
        fixedWidth: 1100,
      );
      await _waitFor(tester, () => _pdfToolbar(tester).ready);
      final viewer = tester.state(find.byType(PdfViewer));
      final chrome = find.byKey(const ValueKey('media-action-reveal'));
      for (final tooltip in ['More actions', 'Reading mode', 'Fit options']) {
        await mouse.moveTo(tester.getRect(find.byKey(_frame)).center);
        await _motion(tester);
        final button = find.byTooltip(tooltip);
        await tester.ensureVisible(button);
        await mouse.moveTo(tester.getCenter(button));
        await tester.tap(button, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        await mouse.moveTo(const Offset(2, 2));
        await tester.pump(const Duration(seconds: 4));
        await _motion(tester);
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 1);
        expect(tester.state(find.byType(PdfViewer)), same(viewer));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        _focusOutside(tester);
        await tester.pump(const Duration(seconds: 4));
        await _motion(tester);
        expect(tester.widget<AnimatedOpacity>(chrome).opacity, 0);
      }
      expect(pdfFactory.opened, [pdf.file.path]);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _unmount(tester);
      pdf.release();
    }
  });
}

// Every case refuses network creation, including accidental font fetches.
// Archive members use only the explorer's own disposable temporary directory;
// the source files, writes, PDF decoder, and clipboard boundary are synthetic.
void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      (tester) async {
        var clients = 0;
        await HttpOverrides.runZoned(
          () => body(tester),
          createHttpClient: (_) {
            clients++;
            throw StateError('No downloads are allowed in toolbar tests');
          },
        );
        expect(clients, 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

FilePreview _preview(
  _MemoryFile file,
  FilePreviewKind kind, {
  bool framed = true,
  bool bare = false,
  bool editable = false,
  Map<String, dynamic> metadata = const {},
}) =>
    FilePreview(
      file: file,
      name: file.name,
      kind: kind,
      metadata: metadata,
      onMetadataChanged: (_) {},
      editable: editable,
      framed: framed,
      bare: bare,
      toolbarTrailing: AppMenuIconButton(
        key: _extra,
        icon: Icons.more_horiz_rounded,
        tooltip: 'Inspect fixture file',
        entries: () => [const AppMenuItem(label: 'Fixture file details')],
      ),
    );

_MemoryFile _file(FilePreviewKind kind) => switch (kind) {
      FilePreviewKind.code =>
        _MemoryFile.text('sample.js', 'console.log("fixture");'),
      FilePreviewKind.notebook => _MemoryFile.text(
          'analysis.ipynb',
          jsonEncode({
            'nbformat': 4,
            'nbformat_minor': 5,
            'metadata': {
              'kernelspec': {'name': 'python3', 'display_name': 'Python 3'},
              'language_info': {'name': 'python'},
            },
            'cells': [
              {
                'id': 'fixture-cell',
                'cell_type': 'code',
                'metadata': {'language': 'python'},
                'execution_count': null,
                'outputs': [],
                'source': ['answer = 1\n'],
              },
            ],
          }),
        ),
      FilePreviewKind.archive => _MemoryFile.bytes(
          'bundle.zip',
          ZipEncoder().encode(
            Archive()
              ..addFile(ArchiveFile('readme.txt', 5, utf8.encode('Hello')))
              ..addFile(ArchiveFile('src/note.txt', 5, utf8.encode('World'))),
          )!,
        ),
      _ => _MemoryFile.text(
          'notes.txt',
          List.generate(100, (i) => 'Line $i: retained preview text.')
              .join('\n'),
        ),
    };

Finder _trigger(FilePreviewKind kind) => switch (kind) {
      FilePreviewKind.code => find.byKey(_copyCode),
      FilePreviewKind.archive => find.byTooltip('Card size'),
      FilePreviewKind.notebook => find.byTooltip('Notebook actions'),
      _ => find.byKey(_extra),
    };

Future<void> _ready(WidgetTester tester, FilePreviewKind kind) async {
  await _waitFor(
    tester,
    () => switch (kind) {
      FilePreviewKind.code =>
        find.byType(SandboxedCodeRunner).evaluate().isNotEmpty,
      FilePreviewKind.archive => tester
          .widgetList<ArchiveGallery>(find.byType(ArchiveGallery))
          .any((gallery) => gallery.entries.isNotEmpty),
      FilePreviewKind.notebook =>
        find.byType(NotebookView).evaluate().isNotEmpty,
      _ => find.byType(SelectableText).evaluate().isNotEmpty,
    },
  );
  if (kind == FilePreviewKind.archive) {
    // The grid virtualizes cards outside the viewport. Readiness is the real
    // decoded listing, not whether every offscreen card happens to be built.
    final gallery = tester.widget<ArchiveGallery>(find.byType(ArchiveGallery));
    expect(
      gallery.entries.map((entry) => entry.entry.path),
      unorderedEquals(['src', 'readme.txt']),
    );
    final file = tester
        .widget<ArchiveExplorer>(find.byType(ArchiveExplorer))
        .file as _MemoryFile;
    expect(file.byteReads, 1);
    expect(find.byType(FolderGalleryCard).hitTestable(), findsWidgets);
  }
}

ThemeData _theme(String mode) => DesktopAppearance().getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );

Future<void> _mount(
  WidgetTester tester,
  String mode,
  Widget child, {
  ValueNotifier<double>? width,
  double fixedWidth = 640,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.windows,
  bool accessible = false,
  bool reduced = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = _theme(mode).copyWith(platform: platform);
  final defaults = AppFlowyDefaultTheme();
  Widget frame(double value, Widget child) => Center(
        child: SizedBox(key: _frame, width: value, height: 520, child: child),
      );
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
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
                accessibleNavigation: accessible,
                disableAnimations: reduced,
              ),
              child: TooltipVisibility(visible: false, child: navigator!),
            ),
          ),
          home: Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {},
                  child: const Text('Outside preview'),
                ),
                if (width == null)
                  frame(fixedWidth, child)
                else
                  ValueListenableBuilder<double>(
                    valueListenable: width,
                    builder: (_, value, child) => frame(value, child!),
                    child: child,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await _motion(tester);
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: 'The real file renderer must finish loading');
  await tester.pump(const Duration(milliseconds: 300));
  await _motion(tester);
}

Future<void> _motion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(_fade);
}

Future<void> _unmount(WidgetTester tester) async {
  // Remove native selection menus while their fields and semantics owner are
  // still alive, inside the test body rather than after leak verification.
  for (final state in tester.stateList<EditableTextState>(
    find.byType(EditableText),
  )) {
    state.hideToolbar();
  }
  await tester.pump();
  await tester.pumpWidget(const SizedBox());
  await tester.runAsync(() async {});
  await tester.pump();
}

Finder _toolbarFor(Finder control) =>
    find.ancestor(of: control, matching: find.byType(PreviewToolbar)).first;

AnimatedOpacity _opacity(WidgetTester tester, Finder toolbar) =>
    tester.widget<AnimatedOpacity>(
      find
          .descendant(of: toolbar, matching: find.byType(AnimatedOpacity))
          .first,
    );

void _expectToolbar(WidgetTester tester, Finder toolbar, bool visible) {
  expect(_opacity(tester, toolbar).opacity, visible ? 1 : 0);
  expect(
    tester
        .widget<IgnorePointer>(
          find
              .descendant(of: toolbar, matching: find.byType(IgnorePointer))
              .first,
        )
        .ignoring,
    !visible,
  );
  expect(
    tester
        .widget<ExcludeSemantics>(
          find
              .descendant(of: toolbar, matching: find.byType(ExcludeSemantics))
              .first,
        )
        .excluding,
    !visible,
  );
}

void _expectIdentity(String text) {
  expect(find.text(text), findsOneWidget);
  expect(
    find.ancestor(of: find.text(text), matching: find.byType(PreviewToolbar)),
    findsNothing,
  );
}

void _focusOutside(WidgetTester tester) =>
    Focus.of(tester.element(find.text('Outside preview'))).requestFocus();

bool _focusedInside(Finder control) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final target = control.evaluate().single;
  var found = identical(context, target);
  context.visitAncestorElements((element) {
    if (identical(element, target)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Future<void> _tabTo(WidgetTester tester, Finder control) async {
  _focusOutside(tester);
  await tester.pump();
  for (var i = 0; i < 50 && !_focusedInside(control); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
  }
  expect(
    _focusedInside(control),
    isTrue,
    reason: 'The real toolbar control must be reachable by Tab',
  );
  await _motion(tester);
}

Set<int> _semanticsIds(WidgetTester tester) {
  final ids = <int>{};
  final root = tester
      .binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode;
  void visit(SemanticsNode node) {
    ids.add(node.id);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  if (root != null) visit(root);
  return ids;
}

class _MemoryFile extends Fake implements File {
  _MemoryFile.text(this.name, String text)
      : bytes = Uint8List.fromList(utf8.encode(text));
  _MemoryFile.bytes(this.name, List<int> bytes)
      : bytes = Uint8List.fromList(bytes);
  final String name;
  Uint8List bytes;
  bool available = true;
  final existenceChecks = <bool>[];
  int reads = 0;
  int byteReads = 0;
  int writes = 0;
  @override
  String get path => 'C:/file-toolbar-fixture/$name';
  @override
  Uri get uri => Uri.file(path);
  @override
  Future<bool> exists() async {
    existenceChecks.add(available);
    return available;
  }

  @override
  Future<int> length() async => bytes.length;
  @override
  FileStat statSync() => _MemoryStat(bytes.length);
  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    reads++;
    return encoding.decode(bytes);
  }

  @override
  Future<Uint8List> readAsBytes() async {
    byteReads++;
    return Uint8List.fromList(bytes);
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    writeAsStringSync(contents, mode: mode, encoding: encoding, flush: flush);
    return this;
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    writes++;
    bytes = Uint8List.fromList(encoding.encode(contents));
  }
}

class _MemoryStat extends Fake implements FileStat {
  _MemoryStat(this.size);
  @override
  final int size;
  @override
  FileSystemEntityType get type => FileSystemEntityType.file;
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

PdfPreviewToolbar _pdfToolbar(WidgetTester tester) =>
    tester.widget<PdfPreviewToolbar>(find.byType(PdfPreviewToolbar));

PdfPreviewToolbar _titlelessPdfToolbar() => PdfPreviewToolbar(
      title: 'Host already supplies the identity',
      showDocumentTitle: false,
      currentPage: 1,
      pageCount: 3,
      zoom: 1,
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
      overflow: const SizedBox(width: 28),
    );

// Only the public PDF IO/decoder boundary is substituted. PdfViewer,
// PdfPreview, page input, focus, scroll transforms and menus are all real.
class _PdfFixture {
  _PdfFixture(this.file, this.ref, this.release);
  final File file;
  final PdfDocumentRef ref;
  final VoidCallback release;
  String get name => 'Retained PDF.pdf';
  static Future<_PdfFixture> prepare(String id) async {
    final file = File('C:/file-toolbar-fixture/$id.pdf');
    final ref = PdfDocumentRefFile(file.path);
    final listenable = ref.resolveListenable();
    final release = listenable.addListener(() {});
    await listenable.load();
    return _PdfFixture(file, ref, release);
  }

  PdfPreview preview({bool fullscreen = false, bool autoHide = false}) =>
      PdfPreview(
        file: file,
        name: name,
        metadata: {'autoHideToolbar': autoHide},
        onMetadataChanged: (_) {},
        editable: false,
        fullscreen: fullscreen,
        sourceDocumentRef: ref,
      );
}

class _PdfFactory extends Fake implements PdfDocumentFactory {
  _PdfFactory(this.raster);
  final ui.Image raster;
  final opened = <String>[];
  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) async {
    opened.add(filePath);
    return _PdfDocument(filePath, raster);
  }
}

class _PdfDocument extends PdfDocument {
  _PdfDocument(String name, ui.Image raster) : super(sourceName: name) {
    pages = [
      for (var page = 1; page <= 3; page++) _PdfPage(this, raster, page),
    ];
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

class _PdfPage extends PdfPage {
  _PdfPage(this.document, this.raster, this.pageNumber);
  @override
  final PdfDocument document;
  final ui.Image raster;
  @override
  final int pageNumber;
  @override
  double get width => 600;
  @override
  double get height => 800;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
  @override
  PdfPageRenderCancellationToken createCancellationToken() =>
      _PdfCancellation();
  @override
  Future<PdfPageText> loadText() async => _PdfText(pageNumber);
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
      cancellationToken?.isCanceled == true ? null : _PdfBitmap(raster);
}

class _PdfCancellation extends PdfPageRenderCancellationToken {
  bool canceled = false;
  @override
  void cancel() => canceled = true;
  @override
  bool get isCanceled => canceled;
}

class _PdfBitmap extends PdfImage {
  _PdfBitmap(this.raster);
  final ui.Image raster;
  @override
  int get width => raster.width;
  @override
  int get height => raster.height;
  @override
  ui.PixelFormat get format => ui.PixelFormat.rgba8888;
  @override
  Uint8List get pixels => Uint8List(width * height * 4);
  @override
  Future<ui.Image> createImage() async => raster.clone();
  @override
  void dispose() {}
}

class _PdfText extends PdfPageText {
  _PdfText(this.pageNumber);
  @override
  final int pageNumber;
  @override
  String get fullText => 'Searchable PDF fixture';
  @override
  List<PdfPageTextFragment> get fragments => [
        PdfPageTextFragment.fromParams(
          0,
          fullText.length,
          const PdfRect(40, 760, 440, 720),
          fullText,
        ),
      ];
}
