import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/features/page_access_level/data/repositories/page_access_level_repository.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_identity.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_plugin.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// Only font loading is substituted, not the code editor or highlighting.
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

import 'page_icon_widget_test_support.dart';
import 'test_asset_bundle.dart';

const _title = ValueKey('workspace-file-name');
const _nameInput = ValueKey('workspace-inline-name-editor');
const _row = ValueKey('workspace-file-identity-row');
const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File jpg;
  late _TrackedFile python;
  late File pdf;
  late PdfDocumentFactory originalPdfFactory;
  late _PdfFactory pdfFactory;
  late ui.Image raster;
  late bool fetching;
  late bool recents;
  late bool sharedSection;
  final code = List.generate(180, (i) => 'print("fixture line $i")').join('\n');

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    fetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    recents = RecentIcons.enable;
    RecentIcons.enable = false;
    for (final weight in [FontWeight.w400, FontWeight.w500, FontWeight.w600]) {
      await font_io.loadFontIfNecessary(
        GoogleFontsDescriptor(
          familyWithVariant: _BundledMono(weight),
          file: GoogleFontsFile('identity-local-font-fixture', 0),
        ),
      );
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final bytes = await File('assets/test/images/sample.jpeg').readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 40);
    raster = (await codec.getNextFrame()).image;
    codec.dispose();
    originalPdfFactory = PdfDocumentFactory.instance;
  });

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('file-photo-identity-');
    jpg = await File('assets/test/images/sample.jpeg')
        .copy('${temporary.path}/stored-photo.jpg');
    python = _TrackedFile(
      await File('${temporary.path}/stored-source.py').writeAsString(code),
    );
    // The injected PDF factory owns decoding. These bytes are only the
    // original-file payload for the storage/export contract, never pdfium input.
    pdf = await File('${temporary.path}/stored-document.pdf')
        .writeAsString('%PDF synthetic native-boundary fixture');
    pdfFactory = _PdfFactory(raster);
    PdfDocumentFactory.instance = pdfFactory;
    sharedSection = FeatureFlag.sharedSection.isOn;
    getIt.pushNewScope();
    getIt.registerSingleton<KeyValueStorage>(_MemoryKV());
    await FeatureFlag.sharedSection.turnOn();
  });

  tearDown(() async {
    PdfDocumentFactory.instance = originalPdfFactory;
    await FeatureFlag.sharedSection.update(sharedSection);
    await getIt.popScope();
    await temporary.delete(recursive: true);
  });

  tearDownAll(() {
    RecentIcons.enable = recents;
    GoogleFonts.config.allowRuntimeFetching = fetching;
    font_io.clearCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    raster.dispose();
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    for (final extension in ['jpg', 'py', 'pdf']) {
      _test('$appearance/$extension: one live identity and retained renderer',
          (tester) async {
        final file = switch (extension) {
          'jpg' => jpg,
          'py' => python,
          _ => pdf,
        };
        final name = 'Full original filename # %.$extension';
        final repository = _Repository(_view('identity', name, file.path));
        final files = _Files({file.path: file});
        final actions = _Actions();
        final child = _fileView(repository, files, actions);
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        final semantics = tester.ensureSemantics();
        try {
          await mouse.addPointer(location: const Offset(1100, 700));
          await _mount(tester, child, appearance: appearance);
          await _ready(tester, extension);
          expect(find.byType(WorkspaceFileIdentityRow), findsOneWidget);
          expect(find.text(name), findsOneWidget);
          expect(
            find.byKey(const ValueKey('workspace-file-identity-icon')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('workspace-file-media-actions')),
            findsNothing,
          );
          if (extension == 'pdf') {
            final controls = find.byKey(const ValueKey('pdf-toolbar-controls'));
            expect(controls, findsOneWidget);
            expect(
              find.descendant(of: find.byKey(_row), matching: controls),
              findsOneWidget,
              reason: 'PDF navigation belongs to the central file header',
            );
            for (final key in [
              _copy,
              _share,
              const ValueKey('workspace-file-rename'),
            ]) {
              expect(
                find.descendant(of: controls, matching: find.byKey(key)),
                findsOneWidget,
              );
              expect(
                tester.getCenter(find.byKey(key)).dy,
                closeTo(
                  tester.getCenter(find.byType(PdfPageNumberField)).dy,
                  1,
                ),
              );
            }
            expect(
              find.byKey(const ValueKey('pdf-fullscreen-media-actions')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('pdf-toolbar-scroll')),
              findsNothing,
            );
          }
          final canvasContext = tester.element(find.byType(WorkspaceFileView));
          expect(
            _canvas(tester),
            EditorSurfaceStyle.canvasBackgroundFor(
              Theme.of(canvasContext).brightness,
              Theme.of(canvasContext).scaffoldBackgroundColor,
              isPaper: PaperTheme.isEnabled(canvasContext),
            ),
          );
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('workspace-file-metadata')),
                )
                .data,
            startsWith('${extension.toUpperCase()} · '),
          );
          final finder = _renderer(extension);
          final state = tester.state(finder);
          final bounds = tester.getRect(finder);
          final addCover = find.byKey(const ValueKey('view-decoration-cover'));
          expect(addCover, findsOneWidget);
          expect(addCover.hitTestable(), findsNothing);
          expect(find.semantics.byLabel('Add Cover'), findsNothing);
          TextEditingController? draft;
          ScrollController? scroll;
          TransformationController? transform;
          PdfViewerController? pdfController;
          if (extension == 'py') {
            final field = tester.widget<TextField>(find.byType(TextField));
            draft = field.controller!;
            draft.value = TextEditingValue(
              text: 'Unsaved draft\n$code',
              selection: const TextSelection(baseOffset: 3, extentOffset: 19),
            );
            scroll = field.scrollController!;
            scroll.jumpTo(80);
            final context = tester.element(find.byType(TextField));
            expect(codeBlockSurfaceColor(context), _canvas(tester));
            expect(CodeBlockPalette.resolve(context).header, _canvas(tester));
            expect(_nearestFill(context), _canvas(tester));
          } else if (extension == 'jpg') {
            transform = tester
                .widget<InteractiveViewer>(finder)
                .transformationController!;
            transform.value = Matrix4.identity()..scale(2.0);
            expect(find.byIcon(Icons.text_fields_rounded), findsNothing);
            expect(find.byIcon(Icons.format_size_rounded), findsNothing);
          } else {
            pdfController = tester.widget<PdfViewer>(finder).controller!;
            unawaited(pdfController.setZoom(pdfController.centerPosition, 2));
            await tester.pump(const Duration(milliseconds: 400));
          }
          await tester.pump();
          await mouse.moveTo(tester.getCenter(find.byKey(_row)));
          await _motion(tester);
          expect(find.byKey(_copy).hitTestable(), findsOneWidget);
          expect(addCover.hitTestable(), findsOneWidget);
          expect(find.semantics.byLabel('Add Cover'), findsOneWidget);
          expect(tester.state(finder), same(state));
          expect(tester.getRect(finder), bounds);
          if (extension == 'jpg') {
            final extract = find.byWidgetPredicate(
              (widget) =>
                  widget is DocumentViewportButton &&
                  widget.tooltip == 'Extract text',
            );
            expect(extract, findsOneWidget);
            expect(
              tester.widget<DocumentViewportButton>(extract).icon,
              Icons.document_scanner_rounded,
            );
            expect(find.semantics.byLabel('Extract text'), findsOneWidget);
          }
          await mouse.moveTo(tester.getCenter(finder));
          await _motion(tester);
          expect(addCover.hitTestable(), findsNothing);
          expect(find.semantics.byLabel('Add Cover'), findsNothing);
          expect(tester.state(finder), same(state));
          expect(tester.getRect(finder), bounds);

          await _beginRename(tester);
          final nameField = tester.widget<EditableText>(find.byKey(_nameInput));
          expect(
            nameField.controller.selection,
            TextSelection(
              baseOffset: 0,
              extentOffset: name.lastIndexOf('.'),
            ),
          );
          await tester.enterText(
            find.byKey(_nameInput),
            'Renamed full filename',
          );
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await _motion(tester);
          final renamed = 'Renamed full filename.$extension';
          expect(repository.renames, [('identity', renamed)]);
          expect(find.text(renamed), findsOneWidget);
          expect(find.text(name), findsNothing);
          expect(tester.state(finder), same(state));
          expect(files.loads, 1);
          expect(_target(tester).name, renamed);
          expect(_target(tester).source, file.path);
          expect(_target(tester).httpHeaders, isEmpty);

          // The same mounted child is resized and themed, not replaced by a
          // synthetic renderer. Its real selection/zoom/buffer remain owned.
          await _mount(
            tester,
            child,
            appearance: appearance == 'dark' ? 'paper' : 'dark',
            size: const Size(420, 680),
            scale: 1.5,
          );
          await _motion(tester);
          expect(tester.state(finder), same(state));
          expect(files.loads, 1);
          expect(find.text(renamed), findsOneWidget);
          if (draft != null) {
            expect(draft.text, 'Unsaved draft\n$code');
            expect(
              draft.selection,
              const TextSelection(baseOffset: 3, extentOffset: 19),
            );
            expect(scroll!.offset, 80);
            expect(python.reads, 1);
            expect(python.writes, 0);
            expect(
              _nearestFill(tester.element(find.byType(TextField))),
              _canvas(tester),
            );
          }
          if (transform != null) {
            expect(transform.value.getMaxScaleOnAxis(), 2);
          }
          if (pdfController != null) {
            expect(pdfController.currentZoom, closeTo(2, 0.001));
            expect(pdfFactory.opened, [pdf.path]);
          }
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await mouse.removePointer();
          await _unmount(tester);
        }
      });
    }

    _test('$appearance: embedded code keeps its original card and filename',
        (tester) async {
      try {
        await _mount(
          tester,
          FilePreview(
            file: python,
            name: 'embedded.py',
            kind: FilePreviewKind.code,
            metadata: const {},
            onMetadataChanged: (_) {},
          ),
          appearance: appearance,
        );
        await _ready(tester, 'py');
        final context = tester.element(find.byType(TextField));
        expect(StandaloneFileScope.maybeOf(context), isNull);
        expect(find.byType(WorkspaceFileIdentityRow), findsNothing);
        expect(find.text('embedded.py'), findsOneWidget);
        expect(
          codeBlockSurfaceColor(context),
          switch (appearance) {
            'dark' => const Color(0xFF18191D),
            'paper' => PaperTheme.codeBlockBackground,
            _ => PremiumThemeExtension.of(context).surface,
          },
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
      }
    });
  }

  _test(
      'keyboard rename failure keeps draft; retry accepts an empty native ACK',
      (tester) async {
    final repository = _Repository(_view('retry', 'original.py', python.path))
      ..failNext = true;
    final files = _Files({python.path: python});
    final child = _fileView(repository, files, _Actions());
    try {
      await _mount(tester, child);
      await _ready(tester, 'py');
      final renderer = tester.state(find.byType(SandboxedCodeRunner));
      await _beginRename(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      expect(
        tester.widget<EditableText>(find.byKey(_nameInput)).controller.text,
        '.py',
      );
      await tester.enterText(find.byKey(_nameInput), 'My revised source.py');
      final inputState = tester.state(find.byKey(_nameInput));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _motion(tester);
      expect(
        find.byKey(const ValueKey('workspace-file-rename-error')),
        findsOneWidget,
      );
      expect(repository.stored['retry']!.name, 'original.py');
      expect(tester.state(find.byKey(_nameInput)), same(inputState));
      expect(
        tester.widget<EditableText>(find.byKey(_nameInput)).controller.text,
        'My revised source.py',
      );
      await _mount(
        tester,
        child,
        appearance: 'paper',
        size: const Size(460, 640),
      );
      await _motion(tester);
      expect(tester.state(find.byKey(_nameInput)), same(inputState));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _motion(tester);
      expect(find.text('My revised source.py'), findsOneWidget);
      expect(find.byKey(_nameInput), findsNothing);
      expect(repository.renames, hasLength(2));
      expect(tester.state(find.byType(SandboxedCodeRunner)), same(renderer));
      expect(files.loads, 1);
      expect(python.reads, 1);
      expect(python.writes, 0);
      expect(await tester.runAsync(python.file.readAsString), code);
      await _beginRename(tester);
      await tester.enterText(find.byKey(_nameInput), 'Cancelled.py');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _motion(tester);
      expect(find.text('My revised source.py'), findsOneWidget);
      expect(repository.renames, hasLength(2));
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
    }
  });

  for (final phase in ['read', 'write']) {
    _test('rebind rejects a late rename $phase and retained callbacks',
        (tester) async {
      final first = _view('first', 'First.py', python.path);
      final second = _view('second', 'Second.jpg', jpg.path);
      final repository = _Repository(first)..stored['second'] = second;
      final pending = Completer<FlowyResult<ViewPB, FlowyError>>();
      if (phase == 'read') {
        repository.readGate = pending.future;
      } else {
        repository.writeGate = pending.future;
      }
      final current = ValueNotifier(first);
      final files = _Files({python.path: python, jpg.path: jpg});
      try {
        await _mount(
          tester,
          ValueListenableBuilder<ViewPB>(
            valueListenable: current,
            builder: (_, view, __) => _fileView(
              repository,
              files,
              const MediaActionService(),
              view: view,
            ),
          ),
        );
        await _ready(tester, 'py');
        await _beginRename(tester);
        final obsolete = tester
            .widget<WorkspaceInlineEditableText>(find.byKey(_title))
            .onSubmitted;
        await tester.enterText(find.byKey(_nameInput), 'Late.py');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        current.value = second;
        await _ready(tester, 'jpg');
        pending
            .complete(FlowyResult.success(phase == 'read' ? first : ViewPB()));
        await _motion(tester);
        expect(await obsolete('Must not write.py'), isFalse);
        expect(find.text('Second.jpg'), findsOneWidget);
        expect(repository.renames, hasLength(phase == 'read' ? 0 : 1));
        expect(repository.stored['second']!.name, 'Second.jpg');
        expect(files.loads, 2);
        expect(repository.listeners.first.stopped, isTrue);
        repository.listeners.first.updated
            ?.call(first..name = 'Old delivery.py');
        await _motion(tester);
        expect(find.text('Second.jpg'), findsOneWidget);
        expect(find.text('Old delivery.py'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!pending.isCompleted) pending.complete(FlowyResult.success(first));
        await _unmount(tester);
        current.dispose();
      }
    });
  }

  for (final blocked in ['locked', 'readOnly', 'host-readOnly', 'wrong-view']) {
    _test('$blocked: actual access blocks rename and image writes, not reading',
        (tester) async {
      final view = _view('guarded', 'Guarded.jpg', jpg.path)
        ..isLocked = blocked == 'locked';
      final repository = _Repository(view);
      final accessView = blocked == 'wrong-view'
          ? _view('unrelated', 'Other.jpg', jpg.path)
          : view;
      final access = PageAccessLevelBloc(
        view: accessView,
        repository: _AccessRepository(
          accessView,
          readOnly: blocked == 'readOnly',
        ),
      )..add(const PageAccessLevelEvent.initial());
      final files = _Files({jpg.path: jpg});
      final actions = _Actions();
      try {
        await _mount(
          tester,
          BlocProvider<PageAccessLevelBloc>.value(
            value: access,
            child: _fileView(
              repository,
              files,
              actions,
              editable: blocked != 'host-readOnly',
            ),
          ),
          accessible: true,
        );
        await _ready(tester, 'jpg');
        expect(find.byType(ViewIconPicker), findsNothing);
        expect(
          find.byKey(const ValueKey('workspace-file-rename')),
          findsNothing,
        );
        final edit = tester.widget<DocumentViewportButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is DocumentViewportButton &&
                widget.tooltip == 'Edit image',
          ),
        );
        expect(edit.onPressed, isNull);
        await tester.tap(find.byKey(_title));
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await _motion(tester);
        expect(find.byKey(_nameInput), findsNothing);
        final title =
            tester.widget<WorkspaceInlineEditableText>(find.byKey(_title));
        expect(await title.onSubmitted('Refused.jpg'), isFalse);
        expect(repository.renames, isEmpty);
        await tester.tap(find.byKey(_copy));
        await _motion(tester);
        expect(actions.calls.single.source.source, jpg.path);
        expect(actions.calls.single.source.name, 'Guarded.jpg');
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        await tester.runAsync(access.close);
      }
    });
  }

  _test(
      'lock revocation during preflight refuses the write and keeps the draft',
      (tester) async {
    final view = _view('revoked', 'Original.py', python.path);
    final repository = _Repository(view);
    final access = PageAccessLevelBloc(
      view: view,
      repository: _AccessRepository(view),
    )..add(const PageAccessLevelEvent.initial());
    final pending = Completer<FlowyResult<ViewPB, FlowyError>>();
    repository.readGate = pending.future;
    try {
      await _mount(
        tester,
        BlocProvider<PageAccessLevelBloc>.value(
          value: access,
          child:
              _fileView(repository, _Files({python.path: python}), _Actions()),
        ),
      );
      await _ready(tester, 'py');
      await _beginRename(tester);
      await tester.enterText(find.byKey(_nameInput), 'Keep this draft.py');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      access.add(const PageAccessLevelEvent.updateLockStatus(true));
      await _motion(tester);
      pending.complete(FlowyResult.success(view));
      await _motion(tester);
      expect(repository.renames, isEmpty);
      expect(
        tester.widget<EditableText>(find.byKey(_nameInput)).controller.text,
        'Keep this draft.py',
      );
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) pending.complete(FlowyResult.success(view));
      await _unmount(tester);
      await tester.runAsync(access.close);
    }
  });

  _test(
      'deleted photo rejects retained copy/extract callbacks without native IO',
      (tester) async {
    final repository = _Repository(_view('deleted', 'Photo.jpg', jpg.path));
    final actions = _Actions();
    try {
      await _mount(
        tester,
        _fileView(repository, _Files({jpg.path: jpg}), actions),
        accessible: true,
      );
      await _ready(tester, 'jpg');
      final copy = tester.widget<IconButton>(find.byKey(_copy)).onPressed!;
      final extract = tester
          .widget<DocumentViewportButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is DocumentViewportButton &&
                  widget.tooltip == 'Extract text',
            ),
          )
          .onPressed!;
      repository.listeners.single.deleted!(
        FlowyResult.success(repository.stored.values.single),
      );
      await _motion(tester);
      copy();
      extract();
      await _motion(tester);
      expect(actions.calls, isEmpty);
      expect(find.byKey(_copy).hitTestable(), findsNothing);
      expect(find.byType(ViewIconPicker), findsNothing);
      expect(find.byKey(const ValueKey('workspace-file-rename')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
    }
  });

  _test('pending Copy survives rename; next Share uses the same original bytes',
      (tester) async {
    final repository = _Repository(_view('export', 'Before.jpg', jpg.path));
    final files = _Files({jpg.path: jpg});
    final pending = Completer<void>();
    final actions = _Actions()..copyGate = pending.future;
    final originalBytes = await tester.runAsync(jpg.readAsBytes);
    try {
      await _mount(
        tester,
        _fileView(repository, files, actions),
        accessible: true,
      );
      await _ready(tester, 'jpg');
      final controls = tester.state(find.byType(MediaActionButtons));
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      expect(actions.calls.single.source.name, 'Before.jpg');
      await _beginRename(tester);
      await tester.enterText(find.byKey(_nameInput), 'After.jpg');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _motion(tester);
      expect(tester.state(find.byType(MediaActionButtons)), same(controls));
      expect(tester.widget<IconButton>(find.byKey(_share)).onPressed, isNull);
      pending.complete();
      await _motion(tester);
      expect(find.byKey(const ValueKey('media-copied')), findsNothing);
      await tester.tap(find.byKey(_share));
      await _motion(tester);
      expect(actions.calls.last.source.name, 'After.jpg');
      expect(actions.calls.last.source.source, jpg.path);
      expect(await tester.runAsync(jpg.readAsBytes), originalBytes);
      expect(files.loads, 1);
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) pending.complete();
      await _unmount(tester);
    }
  });

  _test('plugin body forwards its exact access bloc, never a replacement',
      (tester) async {
    final view = _view('plugin', 'Plugin.py', python.path);
    final access = PageAccessLevelBloc(
      view: view,
      repository: _AccessRepository(view, readOnly: true),
    )..add(const PageAccessLevelEvent.initial());
    final notifier = ViewPluginNotifier(view: view);
    // The builder does not use this information bloc in its body. Its real
    // constructor queries a native user profile, outside this test boundary.
    final info = _ViewInfo();
    final builder = WorkspaceFilePluginWidgetBuilder(
      notifier: notifier,
      viewInfoBloc: info,
      pageAccessLevelBloc: access,
    );
    try {
      await _mount(
        tester,
        builder.buildWidget(context: PluginContext(), shrinkWrap: false),
      );
      await _ready(tester, 'py');
      expect(
        tester
            .element(find.byType(WorkspaceFileView))
            .read<PageAccessLevelBloc>(),
        same(access),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(find.byType(ViewIconPicker), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester);
      notifier.dispose();
      await tester.runAsync(info.close);
      await tester.runAsync(access.close);
    }
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

WorkspaceFileView _fileView(
  _Repository repository,
  _Files files,
  MediaActionService actions, {
  ViewPB? view,
  bool editable = true,
}) =>
    WorkspaceFileView(
      view: view ?? repository.stored.values.first,
      repository: repository,
      resolveStorageUrl: files.resolve,
      materializeFile: files.load,
      iconListenerFactory: repository.listen,
      mediaActions: actions,
      editable: editable,
    );

ViewPB _view(String id, String name, String path) => ViewPB(
      id: id,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: path,
        size: 128,
      ).mergeIntoExtra('{"fixture":"keep metadata"}'),
    );

class _Repository extends WorkspaceItemService {
  _Repository(ViewPB view) : stored = {view.id: view};
  final Map<String, ViewPB> stored;
  final renames = <(String, String)>[];
  final listeners = <_Listener>[];
  bool failNext = false;
  Future<FlowyResult<ViewPB, FlowyError>>? readGate;
  Future<FlowyResult<ViewPB, FlowyError>>? writeGate;

  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String id) async {
    final gate = readGate;
    if (gate != null) return gate;
    return FlowyResult.success(ViewPB.fromBuffer(stored[id]!.writeToBuffer()));
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) async {
    renames.add((viewId, name));
    if (writeGate != null) return writeGate!;
    if (failNext) {
      failNext = false;
      return FlowyResult.failure(FlowyError(msg: 'Synthetic refusal'));
    }
    stored[viewId] = ViewPB.fromBuffer(stored[viewId]!.writeToBuffer())
      ..name = name;
    return FlowyResult.success(ViewPB());
  }

  ViewListener listen(String id) {
    final listener = _Listener(id);
    listeners.add(listener);
    return listener;
  }
}

class _Listener extends ViewListener {
  _Listener(String id) : super(viewId: id);
  void Function(UpdateViewNotifiedValue)? updated;
  void Function(DeleteViewNotifyValue)? deleted;
  bool stopped = false;
  @override
  void start({
    void Function(UpdateViewNotifiedValue)? onViewUpdated,
    void Function(ChildViewUpdatePB)? onViewChildViewsUpdated,
    void Function(DeleteViewNotifyValue)? onViewDeleted,
    void Function(RestoreViewNotifiedValue)? onViewRestored,
    void Function(MoveToTrashNotifiedValue)? onViewMoveToTrash,
  }) {
    updated = onViewUpdated;
    deleted = onViewDeleted;
  }

  @override
  Future<void> stop() async => stopped = true;
}

class _Files {
  _Files(this.files);
  final Map<String, File> files;
  int loads = 0;
  Future<String?> resolve(ViewPB view) async => view.workspaceItem?.storageUrl;
  Future<File> load({required String source, required String name}) async {
    loads++;
    return files[source]!;
  }
}

class _TrackedFile extends Fake implements File {
  _TrackedFile(this.file);
  final File file;
  int reads = 0;
  int writes = 0;
  @override
  String get path => file.path;
  @override
  Uri get uri => file.uri;
  @override
  Directory get parent => file.parent;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<int> length() => file.length();
  @override
  FileStat statSync() => file.statSync();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    reads++;
    return file.readAsString(encoding: encoding);
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    writes++;
    throw StateError('Chrome must not write the file');
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    writes++;
    throw StateError('Chrome must not flush a retained draft');
  }
}

class _Actions extends Fake implements MediaActionService {
  final calls = <({String kind, MediaActionSource source})>[];
  Future<void>? copyGate;
  @override
  Future<void> copy(MediaActionSource source) async {
    calls.add((kind: 'copy', source: source));
    await copyGate;
  }

  @override
  Future<void> share(
    MediaActionSource source, {
    Rect? sharePositionOrigin,
  }) async {
    calls.add((kind: 'share', source: source));
  }
}

class _AccessRepository extends Fake implements PageAccessLevelRepository {
  _AccessRepository(this.view, {this.readOnly = false});
  final ViewPB view;
  final bool readOnly;
  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String id) async =>
      FlowyResult.success(view);
  @override
  Future<FlowyResult<ShareAccessLevel, FlowyError>> getAccessLevel(
    String id,
  ) async =>
      FlowyResult.success(
        readOnly ? ShareAccessLevel.readOnly : ShareAccessLevel.fullAccess,
      );
  @override
  Future<FlowyResult<SharedSectionType, FlowyError>> getSectionType(
    String id,
  ) async =>
      FlowyResult.success(SharedSectionType.private);
}

class _ViewInfo extends Cubit<ViewInfoState> implements ViewInfoBloc {
  _ViewInfo() : super(ViewInfoState.initial());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryKV extends Fake implements KeyValueStorage {
  @override
  Future<void> set(String key, String value) async {}
}

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  String appearance = 'light',
  Size size = const Size(1000, 700),
  double scale = 1,
  bool accessible = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = _theme(appearance);
  final defaults = AppFlowyDefaultTheme();
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
          builder: (context, body) => AppFlowyTheme(
            data: PremiumTheme.appFlowyTheme(
              base: appearance == 'dark' ? defaults.dark() : defaults.light(),
              palette: theme.extension<PremiumThemeExtension>()!,
              brightness: theme.brightness,
            ),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                accessibleNavigation: accessible,
                disableAnimations: true,
              ),
              child: body!,
            ),
          ),
          home: Scaffold(
            body:
                PassivePageIconTestScope(child: SizedBox.expand(child: child)),
          ),
        ),
      ),
    ),
  );
  await _motion(tester);
}

Finder _renderer(String extension) => switch (extension) {
      'jpg' => find.byType(InteractiveViewer),
      'py' => find.byType(SandboxedCodeRunner),
      _ => find.byType(PdfViewer),
    };

Future<void> _ready(WidgetTester tester, String extension) async {
  bool ready() =>
      _renderer(extension).evaluate().isNotEmpty &&
      (extension != 'jpg' ||
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((image) => image.image != null)) &&
      (extension != 'pdf' ||
          tester
              .widget<PdfPreviewToolbar>(
                find.byType(PdfPreviewToolbar),
              )
              .ready);
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: 'The real renderer must finish loading');
  await _motion(tester);
}

Future<void> _motion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump();
}

Future<void> _beginRename(WidgetTester tester) async {
  final focus = tester
      .widget<Focus>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Focus &&
              widget.focusNode?.debugLabel == 'workspace-file-title',
        ),
      )
      .focusNode!;
  for (var i = 0; i < 40 && !focus.hasFocus; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(
    focus.hasFocus,
    isTrue,
    reason: 'The real title is keyboard reachable',
  );
  await tester.sendKeyEvent(LogicalKeyboardKey.f2);
  await _motion(tester);
  expect(find.byKey(_nameInput), findsOneWidget);
}

Future<void> _unmount(WidgetTester tester) async {
  for (final state
      in tester.stateList<EditableTextState>(find.byType(EditableText))) {
    state.hideToolbar();
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  await tester.runAsync(() async {});
}

Color _canvas(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find.byKey(const ValueKey('workspace-file-canvas')),
    )
    .color;

Color? _nearestFill(BuildContext context) {
  Color? color;
  context.visitAncestorElements((element) {
    if (element.widget case final ColoredBox box) {
      color = box.color;
      return false;
    }
    return true;
  });
  return color;
}

MediaActionSource _target(WidgetTester tester) =>
    tester.widget<MediaActionButtons>(find.byType(MediaActionButtons)).source;

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

/// Only pdfrx's native IO is substituted. PdfViewer's real widget/controller,
/// page layout, zoom and toolbar still run; there is no generated FFI or backend.
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
    pages = [_PdfPage(this, raster)];
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
  _PdfPage(this.document, this.raster);
  @override
  final PdfDocument document;
  final ui.Image raster;
  @override
  int get pageNumber => 1;
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
  Future<PdfPageText> loadText() async => _PdfText();
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
  @override
  int get pageNumber => 1;
  @override
  String get fullText => 'Real viewer selection fixture';
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
