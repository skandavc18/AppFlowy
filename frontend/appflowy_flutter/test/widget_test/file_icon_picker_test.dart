import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_icon_binding.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_icon_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/materialized_file_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/date_time.pbenum.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart';

const _iconButton = ValueKey('file-icon-picker-button');
const _previewIcon = ValueKey('file-preview-identity-icon');
const _frame = ValueKey('resizable_media');
const _text = 'The temporary file must not be changed by its identity tools.\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File textFile;
  late File pdfFile;
  late ui.Image raster;
  late PdfDocumentFactory nativePdf;
  late _PdfFactory pdf;
  late UrlLauncherPlatform nativeLauncher;
  late _Launcher launcher;
  late bool recentIconsEnabled;

  setUpAll(() async {
    recentIconsEnabled = RecentIcons.enable;
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFFE7DDC9), BlendMode.src);
    final picture = recorder.endRecording();
    raster = await picture.toImage(40, 50);
    picture.dispose();
  });

  setUp(() async {
    await resetVividIconTestPacks();
    temporary = await Directory.systemTemp.createTemp('file-icon-picker-');
    textFile = await File('${temporary.path}/notes.txt')
        .writeAsString(List.filled(150, _text).join());
    pdfFile = await File('${temporary.path}/report.pdf')
        .writeAsString('%PDF-1.7\nSynthetic decoder fixture only.');
    nativePdf = PdfDocumentFactory.instance;
    pdf = _PdfFactory(raster);
    PdfDocumentFactory.instance = pdf;
    nativeLauncher = UrlLauncherPlatform.instance;
    launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() async {
    PdfDocumentFactory.instance = nativePdf;
    UrlLauncherPlatform.instance = nativeLauncher;
    await temporary.delete(recursive: true);
  });

  tearDownAll(() {
    RecentIcons.enable = recentIconsEnabled;
    raster.dispose();
  });

  for (final appearance in vividIconTestAppearances) {
    _test(
        '$appearance: chip Vivid selection persists, undoes, reopens and removes',
        (tester) async {
      final fixture = _Fixture();
      final initialFocusHolds = keepEditorFocusNotifier.value;
      try {
        await _mount(tester, fixture, appearance: appearance);
        final paragraph = fixture.editor.document.root.children[1];
        await fixture.editor.apply(
          fixture.editor.transaction..insertText(paragraph, 0, 'Draft: '),
        );
        final draft = paragraph.delta!.toPlainText();
        final selection = Selection.collapsed(Position(path: [1], offset: 4));
        fixture.editor.selection = selection;
        await tester.pump();
        final before = Map<String, dynamic>.from(fixture.file.attributes);
        expect(_glyph(tester).icon.isEmpty, isTrue);
        expect(
          find.descendant(
            of: find.byKey(_iconButton),
            matching: find.byIcon(fileIconForName('report.pdf')),
          ),
          findsOneWidget,
        );

        await _openPicker(tester);
        _expectFullPicker(tester);
        expect(keepEditorFocusNotifier.value, initialFocusHolds + 1);
        await _chooseVivid(tester, 'rocket');
        final encoded = fixture.file.attributes[FileBlockKeys.icon] as String;
        _expectVivid(EmojiIconData.fromStorageString(encoded), 'rocket');
        _expectVivid(_glyph(tester).icon, 'rocket');
        expect(find.byType(RawEmojiIconWidget), findsOneWidget);
        expect(fixture.editor.selection, selection);
        expect(keepEditorFocusNotifier.value, initialFocusHolds);
        expect(launcher.opened, isEmpty);
        _expectOnlyIconChanged(before, fixture.file.attributes);

        final readback = Document.fromJson(
          jsonDecode(jsonEncode(fixture.editor.document.toJson())),
        );
        _expectVivid(
          EmojiIconData.fromStorageString(
            readback.root.children.first.attributes[FileBlockKeys.icon],
          ),
          'rocket',
        );
        readback.dispose();
        fixture.editor.undoManager.undo();
        await tester.pumpAndSettle();
        expect(_glyph(tester).icon.isEmpty, isTrue);
        expect(paragraph.delta!.toPlainText(), draft);
        expect(fixture.editor.selection, selection);
        fixture.editor.undoManager.redo();
        await tester.pumpAndSettle();
        _expectVivid(_glyph(tester).icon, 'rocket');

        await _openPicker(tester);
        expect(
          tester
              .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
              .initialType,
          PickerTabType.icon,
        );
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(_glyph(tester).icon.isEmpty, isTrue);
        expect(fixture.file.attributes[FileBlockKeys.icon], isNull);
        expect(fixture.editor.selection, selection);
        _expectOnlyIconChanged(before, fixture.file.attributes);
        expect(launcher.opened, isEmpty);
        if (appearance == 'paper') {
          final context = tester.element(find.byKey(_iconButton));
          expect(PaperTheme.isEnabled(context), isTrue);
          final hover =
              tester.widget<IconButton>(find.byKey(_iconButton)).hoverColor!;
          expect(hover.r, greaterThan(hover.b));
          expect(hover, isNot(Colors.white));
        }
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  for (final kind in ['text', 'PDF']) {
    _test(
        '$kind: overflow icon editing retains the real renderer and its state',
        (tester) async {
      final file = kind == 'text' ? textFile : pdfFile;
      final original = await tester.runAsync(file.readAsBytes);
      final fixture = _Fixture(
        url: file.path,
        name: kind == 'text' ? 'notes.txt' : 'report.pdf',
        type: FileUrlType.local,
        preview: true,
      );
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture, appearance: 'paper');
        await _waitFor(
          tester,
          () => kind == 'text'
              ? find.byType(SelectableText).evaluate().isNotEmpty
              : tester
                  .widgetList<PdfPreviewToolbar>(find.byType(PdfPreviewToolbar))
                  .any((toolbar) => toolbar.ready),
        );
        final previewState = tester.state(find.byType(FilePreview));
        final materializer = tester.state(find.byType(MaterializedFileBuilder));
        final future = tester
            .widget<FutureBuilder<Widget>>(
              find
                  .descendant(
                    of: find.byType(FilePreview),
                    matching: find.byType(FutureBuilder<Widget>),
                  )
                  .first,
            )
            .future;
        TextEditingController? textController;
        ScrollPosition? textScroll;
        PdfViewerController? pdfController;
        Matrix4? pdfTransform;
        State? pdfState;
        if (kind == 'text') {
          final text = find.byType(SelectableText);
          final input = tester.widget<EditableText>(
            find.descendant(of: text, matching: find.byType(EditableText)),
          );
          textController = input.controller
            ..selection = const TextSelection(baseOffset: 4, extentOffset: 19);
          textScroll = Scrollable.of(tester.element(text)).position;
          textScroll.jumpTo(90);
        } else {
          pdfState = tester.state(find.byType(PdfViewer));
          pdfController =
              tester.widget<PdfViewer>(find.byType(PdfViewer)).controller!;
          pdfTransform = pdfController.value.clone();
        }
        final before = Map<String, dynamic>.from(fixture.file.attributes);
        await mouse.moveTo(tester.getCenter(find.byKey(_frame)));
        await tester.pumpAndSettle();
        final more = kind == 'text'
            ? find.byTooltip('More actions')
            : find.byKey(const ValueKey('pdf-overflow-menu'));
        await tester.tap(more, kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.byType(FileBlockMenu), findsOneWidget);
        expect(
          tester.widget<FileBlockMenu>(find.byType(FileBlockMenu)).onChangeIcon,
          isNotNull,
        );
        await tester
            .tap(find.text(LocaleKeys.document_plugins_cover_changeIcon.tr()));
        await tester.pumpAndSettle();
        _expectFullPicker(tester);
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 150));
        final actions =
            find.byKey(const ValueKey('file-preview-media-actions'));
        expect(
          tester
              .widget<AnimatedOpacity>(
                find
                    .descendant(
                      of: actions,
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity,
          1,
          reason: 'The originating preview stays held while its picker is open',
        );
        await _chooseVivid(tester, 'coffee');
        _expectVivid(
          tester
              .widget<FileIdentityGlyph>(
                find.descendant(
                  of: find.byKey(_previewIcon),
                  matching: find.byType(FileIdentityGlyph),
                ),
              )
              .icon,
          'coffee',
        );
        expect(tester.state(find.byType(FilePreview)), same(previewState));
        expect(
          tester.state(find.byType(MaterializedFileBuilder)),
          same(materializer),
        );
        expect(
          tester
              .widget<FutureBuilder<Widget>>(
                find
                    .descendant(
                      of: find.byType(FilePreview),
                      matching: find.byType(FutureBuilder<Widget>),
                    )
                    .first,
              )
              .future,
          same(future),
        );
        if (textController != null) {
          expect(
            textController.selection,
            const TextSelection(baseOffset: 4, extentOffset: 19),
          );
          expect(textScroll!.pixels, 90);
        } else {
          expect(tester.state(find.byType(PdfViewer)), same(pdfState));
          expect(pdfController!.value, pdfTransform);
          expect(pdf.opened, [pdfFile.path]);
        }
        _expectOnlyIconChanged(before, fixture.file.attributes);
        expect(await tester.runAsync(file.readAsBytes), original);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  _test('read-only chips show saved icons but expose no icon edit action',
      (tester) async {
    final fixture = _Fixture(editable: false, icon: _vivid('book'));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture);
      final document = fixture.json;
      _expectVivid(_glyph(tester).icon, 'book');
      expect(
        tester.widget<IconButton>(find.byKey(_iconButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(_iconButton));
      await tester.pumpAndSettle();
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      expect(launcher.opened, isEmpty);
      final binding = tester
          .widget<FileBlockIconButton>(find.byType(FileBlockIconButton))
          .binding;
      expect(await binding.save(_vivid('coffee')), isFalse);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('file-block-chip'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FileMenuTrigger));
      await tester.pumpAndSettle();
      expect(
        find.text(LocaleKeys.document_plugins_cover_changeIcon.tr()),
        findsNothing,
      );
      expect(find.text(LocaleKeys.editor_copy.tr()), findsOneWidget);
      expect(find.text(LocaleKeys.button_share.tr()), findsOneWidget);
      tester
          .state<FileBlockComponentState>(find.byType(FileBlockComponent))
          .menuController
          .close();
      await tester.pumpAndSettle();
      expect(fixture.json, document);
      expect(fixture.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  for (final invalidation in [
    'read-only',
    'detached',
    'rebound',
    'dismissed',
    'unmounted',
  ]) {
    _test('late picker callbacks cannot write after $invalidation',
        (tester) async {
      final fixture = _Fixture();
      final holds = keepEditorFocusNotifier.value;
      try {
        await _mount(tester, fixture);
        await _openPicker(tester);
        final callback = tester
            .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
            .onSelectedEmoji!;
        switch (invalidation) {
          case 'read-only':
            fixture.editor.editable = false;
          case 'detached':
            await fixture.editor
                .apply(fixture.editor.transaction..deleteNode(fixture.file));
          case 'rebound':
            await fixture.update(
              {FileBlockKeys.url: 'https://files.example.invalid/new.bin'},
            );
          case 'dismissed':
            final popover = tester.widget<AppFlowyPopover>(
              find.descendant(
                of: find.byType(FileBlockIconButton),
                matching: find.byType(AppFlowyPopover),
              ),
            );
            popover.controller!.close();
          case 'unmounted':
            await tester.pumpWidget(const SizedBox());
        }
        final before = fixture.json;
        final writes = fixture.writes;
        // Submit before another frame too: guards must read the live target.
        callback(_vivid('rocket').toSelectedResult());
        await tester.pumpAndSettle();
        expect(fixture.json, before);
        expect(fixture.writes, writes);
        expect(keepEditorFocusNotifier.value, holds);
        expect(launcher.opened, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  test('native codec saves every icon kind without touching other attributes',
      () async {
    final fixture = _Fixture();
    final binding =
        FileBlockIconBinding(editorState: fixture.editor, node: fixture.file);
    final before = Map<String, dynamic>.from(fixture.file.attributes);
    try {
      for (final icon in [
        EmojiIconData.emoji('📚'),
        IconsData('appflowy_default_collections', 'book', null)
            .toEmojiIconData(),
        _vivid('rocket'),
        EmojiIconData.custom('https://icons.example.invalid/custom.svg'),
        EmojiIconData.none(),
      ]) {
        expect(await binding.save(icon), isTrue);
        final restored = EmojiIconData.fromStorageString(
          fixture.file.attributes[FileBlockKeys.icon],
        );
        expect(restored.emoji, icon.emoji);
        if (icon.isNotEmpty) expect(restored.type, icon.type);
        _expectOnlyIconChanged(before, fixture.file.attributes);
      }
      fixture.editor.dispose();
      expect(await binding.save(_vivid('coffee')), isFalse);
    } finally {
      binding.dispose();
      await fixture.subscription.cancel();
      if (!fixture.editor.isDisposed) fixture.editor.dispose();
    }
  });

  _test(
      'referenced workspace icons read, save and remove the ViewPB identity only',
      (tester) async {
    final backend = _Backend()
      ..views['file-a'] = _view('file-a', _vivid('rocket'));
    final fixture = _Fixture(
      reference: 'file-a',
      icon: EmojiIconData.emoji('❌'),
      backend: backend,
    );
    try {
      await _mount(tester, fixture);
      await _waitFor(
        tester,
        () =>
            _glyph(tester).icon.type == FlowyIconType.icon &&
            _glyph(tester).icon.isNotEmpty,
      );
      _expectVivid(_glyph(tester).icon, 'rocket');
      final document = fixture.json;
      await _openPicker(tester);
      expect(
        tester
            .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
            .documentId,
        'file-a',
      );
      await _chooseVivid(tester, 'coffee');
      expect(backend.writes.single.viewId, 'file-a');
      _expectVivid(backend.views['file-a']!.icon.toEmojiIconData(), 'coffee');
      _expectVivid(_glyph(tester).icon, 'coffee');
      expect(fixture.json, document);
      expect(fixture.writes, 0);

      backend
          .listeners.single.updated!(_view('unrelated-file', _vivid('home')));
      await tester.pump();
      _expectVivid(_glyph(tester).icon, 'coffee');
      backend.emit(_view('file-a', _vivid('home')));
      await tester.pumpAndSettle();
      _expectVivid(_glyph(tester).icon, 'home');
      await _openPicker(tester);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(backend.views['file-a']!.icon.value, isEmpty);
      expect(_glyph(tester).icon.isEmpty, isTrue);
      expect(fixture.json, document);
      expect(fixture.file.attributes[FileBlockKeys.icon], '❌');
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
      expect(backend.listeners.every((listener) => listener.stopped), isTrue);
    }
  });

  _test(
      'late reference reads cannot replace a rebound or newer notified identity',
      (tester) async {
    final pending = Completer<FlowyResult<ViewPB, FlowyError>>();
    final backend = _Backend()
      ..reads['file-a'] = pending
      ..views['file-b'] = _view('file-b', _vivid('coffee'));
    final fixture = _Fixture(reference: 'file-a', backend: backend);
    try {
      await _mount(tester, fixture);
      expect(
        tester.widget<IconButton>(find.byKey(_iconButton)).onPressed,
        isNull,
      );
      final firstListener = backend.listeners.single;
      firstListener.updated!(_view('file-a', _vivid('rocket')));
      await tester.pumpAndSettle();
      _expectVivid(_glyph(tester).icon, 'rocket');
      await fixture.update({FileBlockKeys.workspaceFileId: 'file-b'});
      await tester.pumpAndSettle();
      _expectVivid(_glyph(tester).icon, 'coffee');
      pending.complete(FlowyResult.success(_view('file-a', _vivid('home'))));
      firstListener.updated!(_view('file-a', _vivid('book')));
      await tester.pumpAndSettle();
      _expectVivid(_glyph(tester).icon, 'coffee');
      expect(firstListener.stopped, isTrue);
      expect(backend.writes, isEmpty);
      expect(fixture.file.attributes[FileBlockKeys.icon], isNull);
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) {
        pending
            .complete(FlowyResult.failure(FlowyError(msg: 'fixture closed')));
      }
      await fixture.dispose(tester);
    }
  });

  _test(
      'a pending reference save retains its target and cannot repaint a new file',
      (tester) async {
    final pending = Completer<FlowyResult<void, FlowyError>>();
    final backend = _Backend()
      ..views['file-a'] = _view('file-a', _vivid('rocket'))
      ..views['file-b'] = _view('file-b', _vivid('home'))
      ..pendingSave = pending;
    final fixture = _Fixture(reference: 'file-a', backend: backend);
    try {
      await _mount(tester, fixture);
      await _openPicker(tester);
      final callback = tester
          .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
          .onSelectedEmoji!;
      callback(_vivid('coffee').toSelectedResult());
      callback(_vivid('book').toSelectedResult());
      expect(backend.writes, hasLength(1));
      await fixture.update({FileBlockKeys.workspaceFileId: 'file-b'});
      await tester.pumpAndSettle();
      final writes = fixture.writes;
      pending.complete(FlowyResult.success(null));
      await tester.pumpAndSettle();
      callback(_vivid('book').toSelectedResult());
      await tester.pump();
      expect(backend.writes.single.viewId, 'file-a');
      _expectVivid(backend.views['file-a']!.icon.toEmojiIconData(), 'coffee');
      _expectVivid(_glyph(tester).icon, 'home');
      expect(fixture.writes, writes);
      expect(fixture.file.attributes[FileBlockKeys.icon], isNull);
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) pending.complete(FlowyResult.success(null));
      await fixture.dispose(tester);
    }
  });
}

void _test(String description, Future<void> Function(WidgetTester) test) =>
    testWidgets(
      description,
      test,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

EmojiIconData _vivid(String name) =>
    IconsData(vividIconTestGroup, name, null).toEmojiIconData();

void _expectVivid(EmojiIconData data, String name) {
  expect(data.type, FlowyIconType.icon);
  final icon = IconsData.fromJson(jsonDecode(data.emoji));
  expect(icon.groupName, vividIconTestGroup);
  expect(icon.iconName, name);
  expect(icon.color, isNull);
  expect(icon.svgString, isNotNull);
}

FileIdentityGlyph _glyph(WidgetTester tester) =>
    tester.widget<FileIdentityGlyph>(
      find.descendant(
        of: find.byKey(_iconButton),
        matching: find.byType(FileIdentityGlyph),
      ),
    );

void _expectOnlyIconChanged(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  expect(
    Map<String, dynamic>.from(after)..remove(FileBlockKeys.icon),
    Map<String, dynamic>.from(before)..remove(FileBlockKeys.icon),
  );
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(_iconButton));
  await tester.pumpAndSettle();
  expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
}

void _expectFullPicker(WidgetTester tester) => expect(
      tester
          .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
          .effectiveTabs,
      [
        PickerTabType.emoji,
        PickerTabType.defaultIcons,
        PickerTabType.icon,
        PickerTabType.custom,
      ],
    );

Future<void> _chooseVivid(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(Tab, 'Icons'));
  await tester.pumpAndSettle();
  await tester.tap(vividIconStyleButton('Vivid'));
  await settleVividIconPictures(tester);
  await tester.tap(vividIconOption(name));
  await tester.pumpAndSettle();
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: 'The isolated renderer must finish loading');
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

class _Fixture {
  _Fixture({
    String url = 'https://files.example.invalid/report.pdf',
    String name = 'report.pdf',
    FileUrlType type = FileUrlType.network,
    bool preview = false,
    bool editable = true,
    EmojiIconData? icon,
    String? reference,
    this.backend = const FileIconBackend(),
  }) {
    editor = EditorState(
      document: Document(
        root: pageNode(
          children: [
            Node(
              type: FileBlockKeys.type,
              attributes: {
                FileBlockKeys.url: url,
                FileBlockKeys.urlType: type.toIntValue(),
                FileBlockKeys.name: name,
                FileBlockKeys.uploadedAt: 1234,
                FileBlockKeys.displayMode: preview ? 'preview' : 'file',
                FileBlockKeys.width: 620.0,
                FileBlockKeys.height: 400.0,
                FileBlockKeys.previewMetadata: {'fixture': 'preserved'},
                if (icon != null) FileBlockKeys.icon: icon.toStorageString(),
                if (reference != null) FileBlockKeys.workspaceFileId: reference,
              },
            ),
            paragraphNode(text: 'Neighboring document draft'),
          ],
        ),
      ),
    )
      ..disableSealTimer = true
      ..editable = editable;
    subscription = editor.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after) writes++;
    });
  }

  final FileIconBackend backend;
  late final EditorState editor;
  late final StreamSubscription<EditorTransactionValue> subscription;
  int writes = 0;
  Node get file => editor.document.root.children.first;
  String get json => jsonEncode(editor.document.toJson());
  Future<void> update(Map<String, dynamic> values) => editor.apply(
        editor.transaction..updateNode(file, values),
        withUpdateSelection: false,
      );

  Future<void> dispose(WidgetTester tester) async {
    for (final state
        in tester.stateList<EditableTextState>(find.byType(EditableText))) {
      state.hideToolbar();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(subscription.cancel);
    if (!editor.isDisposed) editor.dispose();
    await tester.pumpAndSettle();
  }
}

class _Builder extends FileBlockComponentBuilder {
  _Builder(this.backend);
  final FileIconBackend backend;

  @override
  BlockComponentWidget build(BlockComponentContext context) =>
      FileBlockComponent(
        key: context.node.key,
        node: context.node,
        iconBackend: backend,
      );
}

class _Appearance extends Fake implements AppearanceSettingsCubit {
  @override
  AppearanceSettingsState get state => _AppearanceState();
}

class _AppearanceState extends Fake implements AppearanceSettingsState {
  @override
  UserDateFormatPB get dateFormat => UserDateFormatPB.values.first;
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  String appearance = 'light',
}) async {
  final theme = vividIconTestTheme(appearance);
  final defaults = AppFlowyDefaultTheme();
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    Provider<AppearanceSettingsCubit>.value(
      value: _Appearance(),
      child: EasyLocalization(
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
            builder: (context, child) => AppFlowyTheme(
              data: PremiumTheme.appFlowyTheme(
                base: appearance == 'dark' ? defaults.dark() : defaults.light(),
                palette: theme.extension<PremiumThemeExtension>()!,
                brightness: theme.brightness,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 820,
                  height: 760,
                  child: AppFlowyEditor(
                    editorState: fixture.editor,
                    editable: fixture.editor.editable,
                    disableAutoScroll: true,
                    disableKeyboardService: true,
                    editorStyle: const EditorStyle.desktop(
                      padding: EdgeInsets.all(40),
                    ),
                    blockComponentBuilders: {
                      ...standardBlockComponentBuilderMap,
                      FileBlockKeys.type: _Builder(fixture.backend),
                    },
                    contextMenuItems: const [],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _waitFor(
    tester,
    () => find.byType(FileBlockComponent).evaluate().isNotEmpty,
  );
}

ViewPB _view(String id, EmojiIconData icon) => ViewPB(
      id: id,
      name: '$id.pdf',
      icon: icon.toViewIcon(),
      layout: ViewLayoutPB.Document,
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: 'https://files.example.invalid/$id.pdf',
      ).mergeIntoExtra(''),
    );

class _Backend extends FileIconBackend {
  final views = <String, ViewPB>{};
  final reads = <String, Completer<FlowyResult<ViewPB, FlowyError>>>{};
  final writes = <({String viewId, EmojiIconData icon})>[];
  final listeners = <_ViewListener>[];
  Completer<FlowyResult<void, FlowyError>>? pendingSave;

  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String viewId) async {
    final pending = reads[viewId];
    if (pending != null) return pending.future;
    return views.containsKey(viewId)
        ? FlowyResult.success(ViewPB.fromBuffer(views[viewId]!.writeToBuffer()))
        : FlowyResult.failure(FlowyError(msg: 'Missing fixture view'));
  }

  @override
  Future<FlowyResult<void, FlowyError>> updateIcon({
    required ViewPB view,
    required EmojiIconData icon,
  }) async {
    writes.add((viewId: view.id, icon: icon));
    final result = await (pendingSave?.future ??
        Future.value(FlowyResult<void, FlowyError>.success(null)));
    result.onSuccess((_) {
      final updated = ViewPB.fromBuffer(views[view.id]!.writeToBuffer())
        ..icon = icon.toViewIcon();
      emit(updated);
    });
    return result;
  }

  void emit(ViewPB view) {
    views[view.id] = ViewPB.fromBuffer(view.writeToBuffer());
    for (final listener in listeners
        .where((listener) => listener.viewId == view.id && !listener.stopped)) {
      listener.updated?.call(views[view.id]!);
    }
  }

  @override
  ViewListener createListener(String viewId) {
    final listener = _ViewListener(viewId);
    listeners.add(listener);
    return listener;
  }
}

class _ViewListener extends ViewListener {
  _ViewListener(String id) : super(viewId: id);
  void Function(ViewPB)? updated;
  bool stopped = false;

  @override
  void start({
    void Function(UpdateViewNotifiedValue)? onViewUpdated,
    void Function(ChildViewUpdatePB)? onViewChildViewsUpdated,
    void Function(DeleteViewNotifyValue)? onViewDeleted,
    void Function(RestoreViewNotifiedValue)? onViewRestored,
    void Function(MoveToTrashNotifiedValue)? onViewMoveToTrash,
  }) =>
      updated = onViewUpdated;

  @override
  Future<void> stop() async => stopped = true;
}

class _Launcher extends UrlLauncherPlatform {
  final opened = <String>[];
  @override
  Null get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

// Only the decoder is fake: FilePreview, PdfPreview, PdfViewer and menus are real.
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
  String get fullText => 'Isolated file icon PDF';
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
