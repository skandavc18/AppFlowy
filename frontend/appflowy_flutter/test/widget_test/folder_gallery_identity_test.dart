import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/base/icon/icon_widget.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

const _cardKey = ValueKey('identity-card');
const _stageKey = ValueKey('folder-gallery-preview-stage');
const _fileFaceKey = ValueKey('folder-gallery-file-identity');
const _folderFaceKey = ValueKey('folder-gallery-folder-identity');
const _loadingKey = ValueKey('folder-gallery-preview-loading');
const _errorKey = ValueKey('folder-gallery-preview-unavailable');
const _retryKey = ValueKey('folder-gallery-preview-retry');
const _countKey = ValueKey('folder-gallery-child-count');
const _away = Offset(2, 2);
const _empty = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.document,
  blocks: [],
  wordCount: 0,
  readingMinutes: 0,
  tags: [],
  fileTypeLabel: 'PAGE',
);
const _populated = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.document,
  blocks: [
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.heading,
      runs: [FolderGalleryTextRun(text: 'Actual heading', bold: true)],
    ),
    FolderGalleryPreviewBlock(
      kind: FolderGalleryPreviewBlockKind.paragraph,
      runs: [FolderGalleryTextRun(text: 'Actual authored content')],
    ),
  ],
  wordCount: 5,
  readingMinutes: 1,
  tags: [],
  fileTypeLabel: 'PAGE',
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    for (final entry in {
      'Page': 'file-text',
      'Blank.txt': 'file-text',
      'Blank.dart': 'file-code',
      'Blank.docx': 'file-doc',
      'Blank.xlsx': 'file-xls',
      'Blank.pptx': 'file-ppt',
      'Unknown.bin': 'file',
      'Folder': 'folder',
    }.entries) {
      _test('$appearance ${entry.key}: a fitted default identity, not content',
          (tester) async {
        final view = entry.key == 'Folder'
            ? _folder('nested')
            : entry.key == 'Page'
                ? _page()
                : _file(entry.key);
        final preview = entry.key == 'Folder' ? _folderPreview(view) : _empty;
        for (final textScale in [1.0, 2.0]) {
          for (final size in [
            const Size(300, 180),
            const Size(120, 102),
            const Size(48, 32),
          ]) {
            await _mount(
              tester,
              _thumbnail(view, SynchronousFuture(preview), size: size),
              appearance: appearance,
              textScale: textScale,
            );
            final glyph = find.byType(WorkspaceGlyph);
            final widget = tester.widget<WorkspaceGlyph>(glyph);
            expect(widget.name, entry.value);
            expect(widget.size, 64);
            expect(widget.color, isNull, reason: 'Follow the shared icon set.');
            final svg = tester.widget<SvgPicture>(
              find.descendant(of: glyph, matching: find.byType(SvgPicture)),
            );
            expect(svg.width, 64);
            expect(svg.height, 64);
            final bounds =
                tester.getRect(find.byType(FolderGalleryPreviewThumbnail));
            final painted = _paintedRect(tester, glyph);
            _expectInside(painted, bounds);
            expect((painted.center - bounds.center).distance, lessThan(0.01));
            expect(painted.width, lessThanOrEqualTo(64.01));
            expect(find.byType(FolderGalleryRichTextPreview), findsNothing);
            expect(find.byType(FractionallySizedBox), findsNothing);
            expect(find.byType(Image), findsNothing);
            expect(find.byKey(_loadingKey), findsNothing);
            expect(find.byKey(_errorKey), findsNothing);
            expect(find.byKey(_countKey), findsNothing);
            final face = find
                .byKey(entry.key == 'Folder' ? _folderFaceKey : _fileFaceKey);
            final surface = tester.widget<ColoredBox>(
              find
                  .descendant(of: face, matching: find.byType(ColoredBox))
                  .first,
            );
            final context = tester.element(face);
            expect(
              surface.color,
              EditorSurfaceStyle.previewBackgroundFor(
                Theme.of(context).brightness,
                FolderExplorerPalette.of(context).floatingSurface,
                isPaper: PaperTheme.isEnabled(context),
              ),
            );
            expect(PaperTheme.isEnabled(context), appearance == 'paper');
            expect(tester.takeException(), isNull);
          }
        }
      });
    }

    _test('$appearance: known counts are real; an unread folder has no zero',
        (tester) async {
      final unread = _folder('unread');
      final listed =
          _folder('listed', children: [ViewPB(id: 'one'), ViewPB(id: 'two')]);
      final repository = _ListingRepository({});
      for (final (folder, count, expected) in [
        (unread, null, null),
        (unread, 0, 0),
        (listed, null, 2),
      ]) {
        await _mount(
          tester,
          SizedBox(
            width: 120,
            height: 102,
            child: FolderContentPreviewThumbnail(
              folder: folder,
              userProfile: null,
              repository: repository,
              childCount: count,
            ),
          ),
          appearance: appearance,
          textScale: 2,
        );
        expect(repository.reads, isEmpty);
        expect(
          tester.widget<WorkspaceGlyph>(find.byType(WorkspaceGlyph)).name,
          'folder',
        );
        if (expected == null) {
          expect(find.byKey(_countKey), findsNothing);
        } else {
          expect(
            tester.widget<Text>(find.byKey(_countKey)).data,
            LocaleKeys.workspaceFolderExplorer_itemCount
                .tr(args: ['$expected']),
          );
          _expectInside(
            _paintedRect(tester, find.byKey(_countKey)),
            tester.getRect(find.byType(FolderContentPreviewThumbnail)),
          );
        }
        expect(tester.takeException(), isNull);
      }
    });

    _test('$appearance: saved folder covers win even while content is pending',
        (tester) async {
      final pending = Completer<FolderGalleryPreview>();
      final folder = _folder('covered')
        ..extra = ViewCoverCodec.mergeCover(
          _folder('covered').extra,
          const PageStyleCover(
            type: PageStyleCoverImageType.pureColor,
            value: '#B8C6AF',
          ),
        );
      await _mount(
        tester,
        _card(folder, pending.future),
        appearance: appearance,
      );
      expect(find.byType(ViewCoverImage), findsOneWidget);
      expect(find.byKey(_folderFaceKey), findsNothing);
      expect(find.byKey(_loadingKey), findsNothing);
      pending.complete(_folderPreview(folder));
      await _settle(tester);
      expect(find.byType(ViewCoverImage), findsOneWidget);
      final content = ViewPB.fromBuffer(folder.writeToBuffer())
        ..extra =
            ViewPreviewModeCodec.merge(folder.extra, ViewPreviewMode.content);
      await _mount(
        tester,
        _card(content, SynchronousFuture(_folderPreview(content))),
        appearance: appearance,
      );
      expect(find.byType(ViewCoverImage), findsNothing);
      expect(find.byKey(_folderFaceKey), findsOneWidget);
      final removed = ViewPB.fromBuffer(folder.writeToBuffer())
        ..extra = ViewCoverCodec.mergeCover(
          folder.extra,
          const PageStyleCover.none(),
        );
      await _mount(
        tester,
        _thumbnail(removed, SynchronousFuture(_folderPreview(removed))),
        appearance: appearance,
      );
      expect(find.byType(ViewCoverImage), findsNothing);
      expect(find.byKey(_folderFaceKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _test('$appearance: saved emoji and SVG identities keep their own artwork',
        (tester) async {
      for (final icon in [
        ViewIconPB(ty: ViewIconTypePB.Emoji, value: '📚'),
        ViewIconPB(
          ty: ViewIconTypePB.Icon,
          value: jsonEncode({
            'groupName': 'appflowy_default_collections',
            'iconName': 'book',
            'color': '4283665274',
          }),
        ),
        ViewIconPB(
          ty: ViewIconTypePB.Icon,
          value: jsonEncode({
            'groupName': 'appflowy_vivid_essentials',
            'iconName': 'book',
            'color': '4278255360',
          }),
        ),
      ]) {
        final view = _folder('custom')..icon = icon;
        await _mount(
          tester,
          _thumbnail(view, SynchronousFuture(_folderPreview(view))),
          appearance: appearance,
          textScale: 2,
        );
        expect(find.byType(WorkspaceGlyph), findsNothing);
        final saved =
            tester.widget<RawEmojiIconWidget>(find.byType(RawEmojiIconWidget));
        expect(saved.emoji.emoji, icon.value);
        expect(saved.emojiSize, 64);
        if (icon.ty == ViewIconTypePB.Icon) {
          expect(tester.widget<IconWidget>(find.byType(IconWidget)).size, 64);
          final svg = tester.widget<FlowySvg>(find.byType(FlowySvg));
          expect(svg.size, const Size.square(64));
          if (icon.value.contains('appflowy_vivid')) {
            expect(svg.blendMode, isNull);
          }
        }
        final context = tester.element(find.byType(RawEmojiIconWidget));
        expect(MediaQuery.textScalerOf(context).scale(64), 64);
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final thumbnail in [false, true]) {
    for (final failsFuture in [false, true]) {
      _test(
          '${thumbnail ? 'thumbnail' : 'card'}: '
          '${failsFuture ? 'thrown' : 'reported'} failure, pending retry, empty',
          (tester) async {
        final view = _page();
        final pending = Completer<FolderGalleryPreview>();
        final recovery = Completer<FolderGalleryPreview>();
        Future<FolderGalleryPreview> preview = pending.future;
        var retries = 0;
        var opens = 0;
        await _mount(
          tester,
          StatefulBuilder(
            builder: (_, update) {
              void retry() {
                retries++;
                update(() {
                  preview = recovery.future;
                });
              }

              return thumbnail
                  ? _thumbnail(view, preview, onRetry: retry)
                  : _card(view, preview, onRetry: retry, onOpen: () => opens++);
            },
          ),
        );
        expect(find.byKey(_loadingKey), findsOneWidget);
        expect(find.byKey(_fileFaceKey), findsNothing);
        expect(find.byKey(_errorKey), findsNothing);
        if (failsFuture) {
          pending.completeError(StateError('Internal reader details'));
        } else {
          pending.complete(
            FolderGalleryPreviewParser.unavailable(
              view: view,
              item: WorkspaceExplorerItem.fromView(view),
            ),
          );
        }
        await _settle(tester);
        expect(find.byKey(_loadingKey), findsNothing);
        expect(find.byKey(_fileFaceKey), findsNothing);
        expect(find.byKey(_errorKey), findsOneWidget);
        expect(find.textContaining('Internal reader details'), findsNothing);
        expect(find.textContaining('AsyncSnapshot'), findsNothing);
        await tester.tap(find.byKey(_retryKey), kind: PointerDeviceKind.mouse);
        await _settle(tester);
        expect(retries, 1);
        expect(
          opens,
          0,
          reason: 'Recovery must not accidentally open the card.',
        );
        expect(find.byKey(_loadingKey), findsOneWidget);
        expect(find.byKey(_errorKey), findsNothing);
        expect(find.byKey(_retryKey), findsNothing);
        expect(find.byKey(_fileFaceKey), findsNothing);
        recovery.complete(_empty);
        await _settle(tester);
        expect(find.byKey(_errorKey), findsNothing);
        expect(find.byKey(_fileFaceKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  _test('a replacement future cannot reuse a previous item or late result',
      (tester) async {
    final view = _page();
    await _mount(tester, _thumbnail(view, SynchronousFuture(_populated)));
    expect(find.text('Actual heading'), findsOneWidget);
    final previous = Completer<FolderGalleryPreview>();
    await _mount(tester, _thumbnail(view, previous.future));
    expect(find.text('Actual heading'), findsNothing);
    expect(find.byKey(_loadingKey), findsOneWidget);
    final current = Completer<FolderGalleryPreview>();
    final rebound = _page()..id = 'different-page';
    await _mount(tester, _thumbnail(rebound, current.future));
    previous.complete(_populated);
    await _settle(tester);
    expect(find.byKey(_loadingKey), findsOneWidget);
    expect(find.text('Actual heading'), findsNothing);
    current.complete(_empty);
    await _settle(tester);
    expect(find.byKey(_fileFaceKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _test('decoded sibling folders keep exact IDs without reading their contents',
      (tester) async {
    final root = _folder('root');
    final folders = [
      for (final id in ['root::nested%2Fone', 'root::nested%2Ftwo'])
        ViewPB.fromBuffer(_folder(id, parent: root.id).writeToBuffer()),
    ];
    final repository = _ListingRepository({root.id: folders});
    final documents = _NoDocumentReads();
    final controller = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
      canWrite: () => false,
    );
    final cache = FolderGalleryPreviewCache(
      loader: FolderGalleryPreviewLoader(documentService: documents),
    );
    await controller.initialize();
    final opened = <String>[];
    try {
      await _mount(tester, _gallery(controller, cache, onNavigate: opened.add));
      for (final folder in folders) {
        final card = find.byKey(ValueKey('gallery-card-${folder.id}'));
        expect(card, findsOneWidget);
        final face =
            find.descendant(of: card, matching: find.byKey(_folderFaceKey));
        final glyph =
            find.descendant(of: face, matching: find.byType(WorkspaceGlyph));
        expect(tester.widget<WorkspaceGlyph>(glyph).name, 'folder');
        await tester.tap(glyph, kind: PointerDeviceKind.mouse);
        await _settle(tester);
      }
      expect(opened, folders.map((view) => view.id).toList());
      expect(repository.reads, [root.id]);
      expect(documents.reads, 0);
      expect(find.byKey(_countKey), findsNothing);
      // The host may already know a count from normal navigation. Reuse it,
      // but rendering/rebuilding must not enumerate any other folder.
      final known = folders.first.id;
      repository.children[known] = [];
      await controller.ensureLoaded(known);
      await _settle(tester);
      expect(
        tester.widget<Text>(find.byKey(_countKey)).data,
        LocaleKeys.workspaceFolderExplorer_itemCount.tr(args: ['0']),
      );
      await _mount(
        tester,
        _gallery(controller, cache, onNavigate: opened.add),
        appearance: 'paper',
      );
      expect(repository.reads, [root.id, known]);
      expect(documents.reads, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      cache.clear();
    }
  });

  _test('gallery recovery refreshes only the failed future and retains cards',
      (tester) async {
    final root = _folder('root');
    final first = _page()..parentViewId = root.id;
    final second = _page()
      ..id = 'second'
      ..parentViewId = root.id;
    final repository = _ListingRepository({
      root.id: [first, second],
    });
    final controller = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
    );
    final loader = _RecoveringLoader(first.id);
    final cache = FolderGalleryPreviewCache(loader: loader);
    await controller.initialize();
    try {
      await _mount(tester, _gallery(controller, cache));
      final firstCard = find.byKey(ValueKey('gallery-card-${first.id}'));
      final secondCard = find.byKey(ValueKey('gallery-card-${second.id}'));
      final firstState = tester.state(firstCard);
      final secondState = tester.state(secondCard);
      final secondFuture = tester.widget<FolderGalleryCard>(secondCard).preview;
      expect(find.byKey(_retryKey), findsOneWidget);
      await tester.tap(find.byKey(_retryKey), kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(loader.loads, {first.id: 2, second.id: 1});
      expect(tester.state(firstCard), same(firstState));
      expect(tester.state(secondCard), same(secondState));
      expect(
        tester.widget<FolderGalleryCard>(secondCard).preview,
        same(secondFuture),
      );
      expect(find.byKey(_errorKey), findsNothing);
      expect(find.text('Actual heading'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      cache.clear();
    }
  });

  _test('empty resolution, theme and resize retain the rename draft and caret',
      (tester) async {
    final view = _file('Draft.txt');
    final pending = Completer<FolderGalleryPreview>();
    var submissions = 0;
    Widget card(double width) => _card(
          view,
          pending.future,
          width: width,
          editing: true,
          onRenameSubmitted: (_) async {
            submissions++;
            return true;
          },
        );
    await _mount(tester, card(240));
    final editor = find.byKey(const ValueKey('workspace-inline-name-editor'));
    await tester.enterText(editor, 'Unsaved draft.txt');
    final state = tester.state<EditableTextState>(editor);
    final field = tester.widget<EditableText>(editor);
    field.controller.selection =
        const TextSelection(baseOffset: 2, extentOffset: 9);
    final value = field.controller.value;
    final stage = tester.element(find.byKey(_stageKey));
    pending.complete(_empty);
    await _settle(tester);
    for (final appearance in ['paper', 'dark', 'light']) {
      await _mount(tester, card(168), appearance: appearance, textScale: 2);
      expect(find.byKey(_fileFaceKey), findsOneWidget);
      expect(tester.element(find.byKey(_stageKey)), same(stage));
      expect(tester.state<EditableTextState>(editor), same(state));
      expect(field.controller.value, value);
      expect(field.focusNode.hasFocus, isTrue);
      expect(submissions, 0);
      expect(tester.takeException(), isNull);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  _test('animated reveal keeps the loaded glyph element and preview geometry',
      (tester) async {
    final preview = SynchronousFuture(_empty);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: _away);
      await _mount(tester, _card(_page(), preview));
      final glyph = find.descendant(
        of: find.byKey(_fileFaceKey),
        matching: find.byType(WorkspaceGlyph),
      );
      final element = tester.element(glyph);
      final card = tester.state(find.byKey(_cardKey));
      final bounds = tester.getRect(find.byKey(_stageKey));
      final fade = find
          .descendant(
            of: find.byType(PreviewToolbar),
            matching: find.byType(AnimatedOpacity),
          )
          .first;
      for (final visible in [true, false, true, false]) {
        await mouse.moveTo(visible ? bounds.center : _away);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        expect(tester.element(glyph), same(element));
        expect(tester.state(find.byKey(_cardKey)), same(card));
        expect(tester.getRect(find.byKey(_stageKey)), bounds);
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.widget<AnimatedOpacity>(fade).opacity, visible ? 1 : 0);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  _test('a decoded image preview remains real and mounted across reveal',
      (tester) async {
    const ioTimeout = Duration(seconds: 10);
    final temporary = (await tester.runAsync(
      () =>
          Directory.systemTemp.createTemp('gallery_image_').timeout(ioTimeout),
    ))!;
    final file = File('${temporary.path}/image.png');
    final provider = FileImage(file);
    final preview = SynchronousFuture(
      FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.image,
        blocks: const [],
        wordCount: 0,
        readingMinutes: 0,
        tags: const [],
        fileTypeLabel: 'PNG',
        heroUrl: file.path,
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    ImageInfo? cachedFrame;
    try {
      await mouse.addPointer(location: _away);
      cachedFrame = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder)
            .drawColor(const Color(0xFFE53935), ui.BlendMode.src);
        final picture = recorder.endRecording();
        try {
          final image = await picture.toImage(12, 8).timeout(ioTimeout);
          try {
            final png = await image
                .toByteData(format: ui.ImageByteFormat.png)
                .timeout(ioTimeout);
            await file
                .writeAsBytes(png!.buffer.asUint8List())
                .timeout(ioTimeout);
          } finally {
            image.dispose();
          }
        } finally {
          picture.dispose();
        }

        // Resolve BEFORE mounting Image.file: a later runAsync/precacheImage
        // would reuse a pending stream whose IO/codec began on the fake clock.
        // Keep the real provider/cache, and propagate errors instead of treating
        // precacheImage's error-or-first-frame completion as a successful decode.
        final firstFrame = Completer<ImageInfo>();
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (info, _) => firstFrame.complete(info),
          onError: firstFrame.completeError,
        );
        try {
          stream.addListener(listener);
          return await firstFrame.future.timeout(
            ioTimeout,
            onTimeout: () => throw TimeoutException(
              'The gallery FileImage did not decode its first frame.',
              ioTimeout,
            ),
          );
        } finally {
          stream.removeListener(listener);
        }
      });
      expect(tester.takeException(), isNull);
      expect(cachedFrame, isNotNull);
      expect(imageCache.statusForKey(provider).pending, isFalse);
      expect(imageCache.statusForKey(provider).keepAlive, isTrue);

      // Only widget/frame work remains on the fake clock; no polling or sleeps.
      await _mount(tester, _card(_file('image.png'), preview));
      final image = find.byType(Image);
      final state = tester.state(image);
      final rawImage = find.descendant(
        of: image,
        matching: find.byType(RawImage),
      );
      final decoded = tester.widget<RawImage>(rawImage).image!;
      expect(tester.widget<Image>(image).image, provider);
      expect(decoded.isCloneOf(cachedFrame!.image), isTrue);
      expect(decoded.width, 12);
      expect(decoded.height, 8);
      final pixels = await tester.runAsync(
        () => decoded.toByteData().timeout(ioTimeout),
      );
      expect(tester.takeException(), isNull);
      expect(pixels!.getUint8(0), 0xE5);
      expect(pixels.getUint8(1), 0x39);
      expect(find.byKey(_fileFaceKey), findsNothing);
      for (final visible in [true, false]) {
        await mouse.moveTo(visible ? tester.getCenter(image) : _away);
        await _settle(tester);
        expect(tester.state(image), same(state));
        expect(
          tester.widget<RawImage>(rawImage).image!.isCloneOf(decoded),
          isTrue,
        );
        expect(imageCache.statusForKey(provider).pending, isFalse);
        expect(imageCache.statusForKey(provider).keepAlive, isTrue);
        expect(imageCache.statusForKey(provider).live, isTrue);
        expect(tester.takeException(), isNull);
      }
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      cachedFrame?.dispose();
      await tester.runAsync(() async {
        try {
          await provider.evict().timeout(ioTimeout);
        } finally {
          await temporary.delete(recursive: true).timeout(ioTimeout);
        }
      });
    }
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    _test('$appearance: empty and missing items say so on one shared face',
        (tester) async {
      FolderGalleryPreview blank(
        FolderGalleryPreviewKind kind,
        FolderGalleryPreviewNote note,
      ) =>
          FolderGalleryPreview(
            kind: kind,
            blocks: const [],
            wordCount: 0,
            readingMinutes: 0,
            tags: const [],
            fileTypeLabel: 'FILE',
            note: note,
          );
      final table = ViewPB(
        id: 'table',
        name: 'Tasks',
        layout: ViewLayoutPB.Grid,
      );
      final dashboard = ViewPB(
        id: 'dashboard',
        name: 'Plans',
        layout: ViewLayoutPB.Document,
        extra: const DashboardMetadata(document: DashboardDocument())
            .mergeIntoExtra(''),
      );
      final canvas = ViewPB(
        id: 'canvas',
        name: 'Ideas',
        layout: ViewLayoutPB.Document,
        extra: CanvasMetadata.newExtra(),
      );
      FolderGalleryPreview selfContained(ViewPB view) =>
          FolderGalleryPreviewParser.selfContained(
            view: view,
            item: WorkspaceExplorerItem.fromView(view),
          )!;
      for (final (view, preview, caption) in [
        (
          _page(),
          blank(
            FolderGalleryPreviewKind.document,
            FolderGalleryPreviewNote.empty,
          ),
          'Nothing on this page yet',
        ),
        (
          _file('blank.txt'),
          blank(
            FolderGalleryPreviewKind.document,
            FolderGalleryPreviewNote.empty,
          ),
          'This file is empty',
        ),
        (
          _file('Untitled.py'),
          blank(
            FolderGalleryPreviewKind.code,
            FolderGalleryPreviewNote.missing,
          ),
          'Not found on this device',
        ),
        (
          table,
          const FolderGalleryPreview(
            kind: FolderGalleryPreviewKind.database,
            blocks: [],
            wordCount: 0,
            readingMinutes: 0,
            tags: [],
            fileTypeLabel: 'TABLE',
            database: FolderGalleryDatabaseSnapshot(
              columns: ['Name'],
              rows: [],
              totalRowCount: 0,
            ),
          ),
          'No rows yet',
        ),
        (dashboard, selfContained(dashboard), 'Nothing on this dashboard yet'),
        (canvas, selfContained(canvas), 'Nothing on this canvas yet'),
      ]) {
        for (final size in [const Size(280, 180), const Size(148, 148)]) {
          await _mount(
            tester,
            _thumbnail(view, SynchronousFuture(preview), size: size),
            appearance: appearance,
          );
          final note = find.byKey(const ValueKey('folder-gallery-empty-note'));
          expect(note, findsOneWidget, reason: '$caption $size');
          expect(tester.widget<Text>(note).data, caption);
          _expectInside(
            _paintedRect(tester, note),
            tester.getRect(find.byType(FolderGalleryPreviewThumbnail)),
          );
          expect(find.byKey(_errorKey), findsNothing);
          expect(find.byKey(_retryKey), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        try {
          await body(tester);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

ViewPB _page() =>
    ViewPB(id: 'page', name: 'Page', layout: ViewLayoutPB.Document);

ViewPB _file(String name) => ViewPB(
      id: 'synthetic::$name',
      name: name,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
      ).mergeIntoExtra(''),
    );

ViewPB _folder(
  String id, {
  String parent = '',
  List<ViewPB> children = const [],
}) =>
    ViewPB(
      id: id,
      parentViewId: parent,
      name: 'Nested folder',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      childViews: children,
    );

FolderGalleryPreview _folderPreview(ViewPB view) =>
    FolderGalleryPreviewParser.withoutDocument(
      view: view,
      item: WorkspaceExplorerItem.fromView(view),
    )!;

Widget _thumbnail(
  ViewPB view,
  Future<FolderGalleryPreview> preview, {
  Size size = const Size(280, 180),
  VoidCallback? onRetry,
}) =>
    SizedBox(
      width: size.width,
      height: size.height,
      child: FolderGalleryPreviewThumbnail(
        item: WorkspaceExplorerItem.fromView(view),
        view: view,
        preview: preview,
        userProfile: null,
        height: size.height,
        compact: size.height <= 102,
        onRetry: onRetry,
      ),
    );

Widget _card(
  ViewPB view,
  Future<FolderGalleryPreview> preview, {
  double width = 280,
  bool editing = false,
  VoidCallback? onRetry,
  VoidCallback? onOpen,
  Future<bool> Function(String)? onRenameSubmitted,
}) =>
    SizedBox(
      width: width,
      height: 360,
      child: FolderGalleryCard(
        key: _cardKey,
        item: WorkspaceExplorerItem.fromView(view),
        view: view,
        preview: preview,
        userProfile: null,
        selected: false,
        editing: editing,
        onRetry: onRetry,
        onTap: onOpen ?? () {},
        onRename: () {},
        onRenameSubmitted: onRenameSubmitted ?? (_) async => true,
        onRenameCancelled: () {},
        onMore: (_) {},
        onContextMenu: (_) {},
      ),
    );

Widget _gallery(
  WorkspaceExplorerController controller,
  FolderGalleryPreviewCache cache, {
  ValueChanged<String>? onNavigate,
}) =>
    SizedBox(
      width: 900,
      height: 500,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) => FolderGallery(
          controller: controller,
          previewCache: cache,
          userProfile: null,
          onOpen: (_) {},
          onNavigate: onNavigate ?? (_) {},
          onContextMenu: (_, __) {},
          onRequestDelete: () {},
          onRename: controller.beginRename,
        ),
      ),
    );

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  String appearance = 'light',
  double textScale = 1,
}) async {
  final theme = DesktopAppearance().getThemeData(
    appearance == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    appearance == 'dark' ? Brightness.dark : Brightness.light,
    preferredFontFamily,
    builtInCodeFontFamily,
  );
  await tester.pumpWidget(
    WidgetTestApp(
      child: Theme(
        data: theme.copyWith(platform: TargetPlatform.windows),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Center(child: child),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 160));
}

Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

void _expectInside(Rect child, Rect parent) {
  expect(child.width, greaterThan(0));
  expect(child.height, greaterThan(0));
  expect(child.left, greaterThanOrEqualTo(parent.left - 0.01));
  expect(child.top, greaterThanOrEqualTo(parent.top - 0.01));
  expect(child.right, lessThanOrEqualTo(parent.right + 0.01));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom + 0.01));
}

class _ListingRepository implements WorkspaceItemRepository {
  _ListingRepository(this.children);

  final Map<String, List<ViewPB>> children;
  final reads = <String>[];

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async {
    reads.add(parentViewId);
    final result = children[parentViewId];
    if (result == null) throw StateError('Unexpected children read');
    return FlowyResult.success(result);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoDocumentReads extends DocumentService {
  int reads = 0;

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> getDocument({
    required String documentId,
  }) async {
    reads++;
    throw StateError('Identity artwork must not open a document');
  }
}

class _RecoveringLoader extends FolderGalleryPreviewLoader {
  _RecoveringLoader(this.failedId);

  final String failedId;
  final loads = <String, int>{};

  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async {
    final count =
        loads.update(view.id, (count) => count + 1, ifAbsent: () => 1);
    if (view.id != failedId) return _empty;
    return count == 1
        ? FolderGalleryPreviewParser.unavailable(view: view, item: item)
        : _populated;
  }
}
