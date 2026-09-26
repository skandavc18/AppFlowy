import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_artwork.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_tiles.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/folder_embed_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _appearances = ['light', 'dark', 'paper'];
const _styles = [
  FolderEmbedStyles.gallery,
  FolderEmbedStyles.compact,
  FolderEmbedStyles.list,
];
const _loading = ValueKey('folder-gallery-preview-loading');
const _unavailable = ValueKey('folder-gallery-preview-unavailable');
const _retry = ValueKey('folder-gallery-preview-retry');
const _folderFace = ValueKey('folder-gallery-folder-identity');
const _fileFace = ValueKey('folder-gallery-file-identity');
const _count = ValueKey('folder-gallery-child-count');
const _referenceKey = ValueKey('shared-reference-thumbnail');
const _goldenKey = ValueKey('folder-embed-shared-golden');
const _ioTimeout = Duration(seconds: 10);
const _settings = CollectionEmbedSettings(columns: 2, itemLimit: 8);

late Map<String, dynamic> _translations;
late Directory _files;
late File _blankFile;
late File _textFile;
late File _markdownFile;
late File _imageFile;
final _controllers = <CollectionEmbedController>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool previousFontFetching;
  setUpAll(() async {
    previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    _translations = Map<String, dynamic>.from(
      jsonDecode(
        await rootBundle
            .loadString('assets/translations/en-US.json')
            .timeout(_ioTimeout),
      ),
    );
    for (final (family, asset) in [
      ('DM Sans', 'assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
      ('Inter', 'assets/google_fonts/Inter/Inter-Variable.ttf'),
      ('RobotoMono', 'assets/google_fonts/Roboto_Mono/RobotoMono-Regular.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(asset)))
          .load()
          .timeout(_ioTimeout);
    }
    _files = await Directory.systemTemp
        .createTemp('folder_embed_preview_')
        .timeout(_ioTimeout);
    _blankFile = await File('${_files.path}/blank.txt')
        .writeAsString('')
        .timeout(_ioTimeout);
    _textFile = await File('${_files.path}/notes.txt')
        .writeAsString('Words from the actual stored file\nAnother real line')
        .timeout(_ioTimeout);
    _markdownFile = await File('${_files.path}/notes.md')
        .writeAsString('# Stored heading\n\nA **bold** word.\n\n- Actual item')
        .timeout(_ioTimeout);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xFFDE4937), ui.BlendMode.src);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(12, 8).timeout(_ioTimeout);
      try {
        final bytes = await image
            .toByteData(format: ui.ImageByteFormat.png)
            .timeout(_ioTimeout);
        _imageFile = await File('${_files.path}/photo.png')
            .writeAsBytes(bytes!.buffer.asUint8List())
            .timeout(_ioTimeout);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  });
  tearDown(() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers.clear();
  });
  tearDownAll(() async {
    GoogleFonts.config.allowRuntimeFetching = previousFontFetching;
    await _files.delete(recursive: true).timeout(_ioTimeout);
  });

  for (final appearance in _appearances) {
    for (final style in _styles) {
      _test('$appearance $style: genuine identities use the shared renderers',
          (tester) async {
        final views = [
          _folder('folder'),
          _page('page'),
          for (final kind in CollectionKind.values)
            ViewPB(
              id: 'collection-${kind.name}',
              name: kind.name,
              layout: ViewLayoutPB.Document,
              extra: CollectionMetadata.newExtra(kind),
            ),
          for (final name in [
            'Blank.txt',
            'Blank.dart',
            'Blank.docx',
            'Blank.xlsx',
            'Blank.pptx',
            'Track.mp3',
            'Archive.zip',
            'Unknown.bin',
          ])
            _file(name, _blankFile.path),
          ViewPB(id: 'chat', name: 'Conversation', layout: ViewLayoutPB.Chat),
          ViewPB(id: 'table', name: 'Table', layout: ViewLayoutPB.Grid),
        ];
        for (final original in views) {
          // Real persisted item envelopes, decoded at the repository boundary.
          final view = ViewPB.fromBuffer(original.writeToBuffer());
          final bytes = view.writeToBuffer();
          final documents = _Documents({view.id: _document(const [])});
          final reader = FolderGalleryPreviewLoader(
            documentService: documents,
            databasePreviewLoader: _DatabasePreview(),
          );
          final loader = _RecordingLoader(reader.load);
          final repository = _Repository([view]);
          final controller = await _adoptListing(tester, repository, loader);
          final warmed = style == FolderEmbedStyles.list
              ? <String, Future<FolderGalleryPreview>>{}
              : await _warmControllerPreviews(tester, controller, [view]);
          await _mount(
            tester,
            controller,
            appearance: appearance,
            settings: _settings.copyWith(style: style),
            reference: style == FolderEmbedStyles.list ? null : view,
            size: const Size(440, 320),
          );
          if (warmed.isNotEmpty) {
            expect(
              tester
                  .widget<FolderGalleryPreviewThumbnail>(
                    find.byKey(_referenceKey),
                  )
                  .preview,
              same(warmed[view.id]),
            );
            await _paintWarmedPreviews(tester, controller, warmed);
          }
          expect(find.byType(CollectionObjectCard), findsNothing);
          expect(find.byType(CollectionArtwork), findsNothing);
          expect(find.byType(CollectionArtworkGlyph), findsNothing);
          expect(repository.reads, ['root']);
          expect(repository.writes, isEmpty);
          expect(view.writeToBuffer(), bytes);
          expect(
            PaperTheme.isEnabled(
              tester.element(find.byType(FolderEmbedPreview)),
            ),
            appearance == 'paper',
          );
          if (style == FolderEmbedStyles.list) {
            expect(loader.reads, isEmpty);
            expect(documents.reads, isEmpty);
            expect(find.byType(FolderGalleryPreviewThumbnail), findsNothing);
            final identity = tester.widget<WorkspaceItemIcon>(
              find.descendant(
                of: _item(view),
                matching: find.byType(WorkspaceItemIcon),
              ),
            );
            expect(identity.view, same(view));
            expect(identity.showThumbnail, isFalse);
            final glyphs = tester.widgetList<WorkspaceGlyph>(
              find.descendant(
                of: _item(view),
                matching: find.byType(WorkspaceGlyph),
              ),
            );
            expect(glyphs, isNotEmpty);
            expect(glyphs.every((glyph) => glyph.color == null), isTrue);
          } else {
            expect(loader.reads, {view.id: 1});
            expect(
              _contract(tester, _thumbnail(view)),
              _contract(tester, find.byKey(_referenceKey)),
            );
            expect(
              find.descendant(
                of: _item(view),
                matching: find.byType(GalleryCardSurface),
              ),
              style == FolderEmbedStyles.compact
                  ? findsNothing
                  : findsOneWidget,
            );
            expect(
              find.descendant(
                of: _item(view),
                matching: find.byType(GalleryCardFooter),
              ),
              style == FolderEmbedStyles.compact
                  ? findsNothing
                  : findsOneWidget,
            );
            expect(find.byKey(_unavailable), findsNothing);
            expect(find.byKey(_loading), findsNothing);
            final glyph = tester.widget<WorkspaceGlyph>(
              find.descendant(
                of: _thumbnail(view),
                matching: find.byType(WorkspaceGlyph),
              ),
            );
            expect(glyph.size, 64);
            expect(glyph.color, isNull);
            if (view.layout == ViewLayoutPB.Chat) {
              expect(glyph.name, 'ai-chat');
              expect(documents.reads, isEmpty);
            }
            if (view.id == 'folder') expect(glyph.name, 'folder');
            final face = find
                .descendant(
                  of: _thumbnail(view),
                  matching: find.byType(ColoredBox),
                )
                .first;
            expect(
              tester.widget<ColoredBox>(face).color,
              style == FolderEmbedStyles.compact
                  ? GalleryCardPalette.previewSurface(
                      tester.element(_thumbnail(view)),
                    )
                  : GalleryCardPalette.of(tester.element(_thumbnail(view)))
                      .surface,
            );
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '${view.name}, $style',
          );
        }
      });

      _test(
          '$appearance $style: saved emoji/library identity and metadata survive',
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
          final before = view.writeToBuffer();
          final repository = _Repository([view]);
          final loader = _identityLoader();
          final controller = _controller(repository, loader);
          final settings = _settings.copyWith(style: style);
          final settingsBytes = jsonEncode(settings.toJson());
          await _mount(
            tester,
            controller,
            appearance: appearance,
            settings: settings,
            textScale: 2,
          );
          final scope =
              style == FolderEmbedStyles.list ? _item(view) : _thumbnail(view);
          final saved = tester.widget<RawEmojiIconWidget>(
            find.descendant(
              of: scope,
              matching: find.byType(RawEmojiIconWidget),
            ),
          );
          expect(saved.emoji.emoji, icon.value);
          expect(saved.emojiSize, style == FolderEmbedStyles.list ? 16 : 64);
          expect(
            find.descendant(of: scope, matching: find.byType(WorkspaceGlyph)),
            findsNothing,
          );
          if (icon.value.contains('appflowy_vivid')) {
            final svg = tester.widget<FlowySvg>(
              find.descendant(of: scope, matching: find.byType(FlowySvg)),
            );
            expect(svg.blendMode, isNull);
          }
          expect(
            find.descendant(of: _item(view), matching: find.text('Folder')),
            style == FolderEmbedStyles.compact ? findsNothing : findsOneWidget,
          );
          final future =
              style == FolderEmbedStyles.list ? null : _future(tester, view);
          await _mount(
            tester,
            controller,
            appearance: appearance,
            settings: settings.copyWith(showMetadata: false),
            textScale: 2,
          );
          expect(
            find.byKey(const ValueKey('folder-embed-item-metadata')),
            findsNothing,
          );
          if (future != null) expect(_future(tester, view), same(future));
          expect(view.writeToBuffer(), before);
          expect(jsonEncode(settings.toJson()), settingsBytes);
          expect(repository.writes, isEmpty);
          expect(tester.takeException(), isNull);
        }
      });

      _test(
          '$appearance $style: mouse, keyboard and secondary activation are native',
          (tester) async {
        final view = _folder('open', name: 'Exact folder');
        final controller = _controller(_Repository([view]), _identityLoader());
        final opened = <ViewPB>[];
        final menus = <Offset>[];
        final semantics = tester.ensureSemantics();
        try {
          await _mount(
            tester,
            controller,
            appearance: appearance,
            settings: _settings.copyWith(style: style),
            onOpen: opened.add,
            onMenu: menus.add,
          );
          final ink =
              find.descendant(of: _item(view), matching: find.byType(InkWell));
          final node = tester.widget<InkWell>(ink).focusNode!;
          await tester.tap(ink, kind: PointerDeviceKind.mouse);
          expect(opened, [same(view)]);
          node.requestFocus();
          await _flush(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          expect(opened, [same(view), same(view), same(view)]);
          await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.f10);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          final point = tester.getCenter(ink);
          final secondary = await tester.startGesture(
            point,
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await secondary.up();
          await _flush(tester);
          expect(menus, hasLength(3));
          expect(menus.last, point);
          expect(opened, hasLength(3));
          final data = tester
              .getSemantics(
                find
                    .descendant(
                      of: _item(view),
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget is Semantics &&
                            widget.properties.button == true,
                      ),
                    )
                    .first,
              )
              .getSemanticsData();
          expect(data.label, contains(view.name));
          expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }

    _test(
        '$appearance: stored files and document PBs paint real content, not glyphs',
        (tester) async {
      final page = _page('written');
      final text = _file('notes.txt', _textFile.path);
      final markdown = _file('notes.md', _markdownFile.path);
      final documents =
          _Documents({page.id: _writtenDocument('Authored heading')});
      final reader = FolderGalleryPreviewLoader(documentService: documents);
      final loader = _RecordingLoader(reader.load);
      final repository = _Repository([page, text, markdown]);
      final controller = await _adoptListing(tester, repository, loader);
      final warmed = await _warmControllerPreviews(
        tester,
        controller,
        [text, markdown],
      );
      await _mount(
        tester,
        controller,
        appearance: appearance,
        settings: _settings.copyWith(columns: 3),
        size: const Size(1000, 400),
      );
      await _paintWarmedPreviews(tester, controller, warmed);
      expect(find.byKey(_loading), findsNothing);
      expect(find.byKey(_unavailable), findsNothing);
      expect(find.text('Authored heading'), findsOneWidget);
      expect(find.text('Words from the actual stored file'), findsOneWidget);
      expect(find.text('Stored heading'), findsOneWidget);
      expect(find.byType(FolderGalleryRichTextPreview), findsNWidgets(3));
      expect(find.byKey(_fileFace), findsNothing);
      final rich = tester.widget<FolderGalleryRichTextPreview>(
        find.descendant(
          of: _thumbnail(page),
          matching: find.byType(FolderGalleryRichTextPreview),
        ),
      );
      expect(rich.blocks.first.kind, FolderGalleryPreviewBlockKind.heading);
      expect(rich.blocks[1].runs[1].bold, isTrue);
      expect(rich.blocks[2].kind, FolderGalleryPreviewBlockKind.bulletedList);
      expect(documents.reads, [page.id]);
      expect(loader.reads, {page.id: 1, text.id: 1, markdown.id: 1});
      expect(repository.reads, ['root']);
      expect(tester.takeException(), isNull);
    });

    _test(
        '$appearance: counts reuse supplied children, never infer an unread zero',
        (tester) async {
      final unknown = _folder('unknown');
      final listed = _folder('listed')
        ..childViews.addAll([_page('one'), _page('two')]);
      final repository = _Repository([unknown, listed]);
      final documents = _Documents({});
      final reader = FolderGalleryPreviewLoader(documentService: documents);
      final loader = _RecordingLoader(reader.load);
      final controller = _controller(repository, loader);
      await _mount(tester, controller, appearance: appearance, textScale: 2);
      expect(
        find.descendant(
          of: _thumbnail(unknown),
          matching: find.byKey(_count),
        ),
        findsNothing,
      );
      expect(
        tester.widget<Text>(find.byKey(_count)).data,
        LocaleKeys.workspaceFolderExplorer_itemCount.tr(args: ['2']),
      );
      expect(find.byKey(_folderFace), findsNWidgets(2));
      expect(repository.reads, ['root']);
      expect(documents.reads, isEmpty);
      expect(controller.hasLoaded(unknown.id), isFalse);
      expect(controller.hasLoaded(listed.id), isFalse);
      expect(tester.takeException(), isNull);
    });

    for (final style in [
      FolderEmbedStyles.gallery,
      FolderEmbedStyles.compact,
    ]) {
      _test(
          '$appearance $style: saved previewMode controls cover/content precedence',
          (tester) async {
        final view = _page('covered')
          ..extra = ViewCoverCodec.mergeCover(
            '',
            const PageStyleCover(
              type: PageStyleCoverImageType.pureColor,
              value: '#BACDB1',
            ),
          );
        final pending = Completer<FolderGalleryPreview>();
        Future<FolderGalleryPreview> result = pending.future;
        final loader =
            _RecordingLoader(({required view, required item}) => result);
        final controller = _controller(_Repository([view]), loader);
        final settings = _settings.copyWith(style: style);
        await _mount(
          tester,
          controller,
          appearance: appearance,
          settings: settings,
        );
        expect(find.byType(ViewCoverImage), findsOneWidget);
        expect(find.byKey(_loading), findsNothing);
        expect(find.byKey(_fileFace), findsNothing);
        pending.complete(_parsed(view, 'The actual page'));
        await _flush(tester);
        expect(find.byType(ViewCoverImage), findsOneWidget);
        expect(find.text('The actual page'), findsNothing);

        view.extra =
            ViewPreviewModeCodec.merge(view.extra, ViewPreviewMode.content);
        result = Future.value(_parsed(view, 'The actual page'));
        final bytes = view.writeToBuffer();
        await _mount(
          tester,
          controller,
          appearance: appearance,
          settings: settings,
        );
        expect(find.byType(ViewCoverImage), findsNothing);
        expect(find.text('The actual page'), findsOneWidget);
        expect(view.writeToBuffer(), bytes);
        view.extra =
            ViewCoverCodec.mergeCover(view.extra, const PageStyleCover.none());
        await _mount(
          tester,
          controller,
          appearance: appearance,
          settings: settings,
        );
        expect(find.byType(ViewCoverImage), findsNothing);
        expect(find.text('The actual page'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      _test('$appearance $style: compact captions and 2x text stay bounded',
          (tester) async {
        final code = _file('Very long file name.dart', _blankFile.path);
        final table =
            ViewPB(id: 'table', name: 'Real table', layout: ViewLayoutPB.Grid);
        final loader = _RecordingLoader(({required view, required item}) async {
          if (view.id == table.id) return _tableData;
          return _parsed(view, 'void main() {}', type: 'code');
        });
        final controller = _controller(_Repository([code, table]), loader);
        for (final size in [const Size(320, 80), const Size(360, 180)]) {
          for (final preset in [
            CollectionEmbedSize.compact,
            CollectionEmbedSize.medium,
          ]) {
            await _mount(
              tester,
              controller,
              appearance: appearance,
              size: size,
              textScale: 2,
              settings:
                  _settings.copyWith(style: style, size: preset, columns: 8),
            );
            expect(
              find.byType(FolderGalleryPreviewThumbnail),
              findsNWidgets(2),
            );
            for (final view in [code, table]) {
              final box = tester.renderObject<RenderBox>(_thumbnail(view));
              expect(box.hasSize, isTrue);
              expect(box.size.width.isFinite, isTrue);
              expect(box.size.height.isFinite, isTrue);
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '$style $size $preset at 2x',
            );
          }
        }
        expect(loader.reads, {code.id: 1, table.id: 1});
      });

      for (final thrown in [false, true]) {
        _test(
            '$appearance $style: ${thrown ? 'thrown' : 'reported'} failure retries only that child',
            (tester) async {
          final bad = _page('bad');
          final peer = _folder('peer');
          final pending = Completer<FolderGalleryPreview>();
          final recovery = Completer<FolderGalleryPreview>();
          var attempts = 0;
          final loader = _RecordingLoader(({required view, required item}) {
            if (view.id == peer.id) return Future.value(_immediate(view));
            return attempts++ == 0 ? pending.future : recovery.future;
          });
          final repository = _Repository([bad, peer]);
          final controller = _controller(repository, loader);
          var opened = 0;
          await _mount(
            tester,
            controller,
            appearance: appearance,
            settings: _settings.copyWith(style: style),
            onOpen: (_) => opened++,
          );
          expect(find.byKey(_loading), findsOneWidget);
          expect(find.byKey(_fileFace), findsNothing);
          final peerFuture = _future(tester, peer);
          final peerElement = tester.element(_thumbnail(peer));
          if (thrown) {
            pending.completeError(StateError('Private reader details'));
          } else {
            pending.complete(
              FolderGalleryPreviewParser.unavailable(
                view: bad,
                item: WorkspaceExplorerItem.fromView(bad),
              ),
            );
          }
          await _flush(tester);
          expect(find.byKey(_unavailable), findsOneWidget);
          expect(find.byKey(_loading), findsNothing);
          expect(find.byKey(_fileFace), findsNothing);
          expect(find.textContaining('Private reader details'), findsNothing);
          if (thrown) {
            // Focus owns an internal node when TextButton.focusNode is null.
            // Its label is below that Focus; the button's own context is not.
            final retryLabel = find.descendant(
              of: find.byKey(_retry),
              matching: find.text(LocaleKeys.button_retry.tr()),
            );
            expect(retryLabel, findsOneWidget);
            final buttonFocus = Focus.of(
              tester.element(retryLabel),
              createDependency: false,
            );
            expect(
              buttonFocus,
              isNot(
                same(
                  Focus.of(
                    tester.element(find.byKey(_retry)),
                    createDependency: false,
                  ),
                ),
              ),
            );
            buttonFocus.requestFocus();
            await _flush(tester);
            expect(buttonFocus.hasPrimaryFocus, isTrue);
            expect(FocusManager.instance.primaryFocus, same(buttonFocus));
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          } else {
            await tester.tap(find.byKey(_retry), kind: PointerDeviceKind.mouse);
          }
          await _flush(tester);
          expect(opened, 0);
          expect(loader.reads, {bad.id: 2, peer.id: 1});
          expect(repository.reads, ['root']);
          expect(_future(tester, peer), same(peerFuture));
          expect(tester.element(_thumbnail(peer)), same(peerElement));
          expect(find.byKey(_unavailable), findsNothing);
          expect(find.byKey(_loading), findsOneWidget);
          recovery.complete(_parsed(bad, ''));
          await _flush(tester);
          expect(find.byKey(_loading), findsNothing);
          expect(find.byKey(_fileFace), findsOneWidget);
          expect(find.byKey(_unavailable), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }

    _test('$appearance: shared folder embed renderers golden', (tester) async {
      tester.view.physicalSize = const Size(1200, 1080);
      final folder = _folder('fixture-folder', name: 'Research')
        ..childViews.addAll([_page('child-one'), _page('child-two')]);
      final custom = _folder('fixture-custom', name: 'Saved icon')
        ..icon = ViewIconPB(
          ty: ViewIconTypePB.Icon,
          value: jsonEncode({
            'groupName': 'appflowy_vivid_essentials',
            'iconName': 'book',
            'color': '4278255360',
          }),
        );
      // Only the loader boundary is fake. These paths are never opened, and
      // every card/thumbnail/row below is the actual production renderer.
      final empty = _file('Empty.dart', 'fixture/empty.dart');
      final text = _file('Notes.txt', 'fixture/notes.txt');
      final markdown = _file('Readme.md', 'fixture/readme.md');
      final cover = _page('fixture-cover', name: 'Saved cover')
        ..extra = ViewCoverCodec.mergeCover(
          '',
          const PageStyleCover(
            type: PageStyleCoverImageType.pureColor,
            value: '#BACDB1',
          ),
        );
      final views = [folder, custom, empty, text, markdown, cover];
      final before = {for (final view in views) view.id: view.writeToBuffer()};
      final data = <String, FolderGalleryPreview>{
        folder.id: _immediate(folder),
        custom.id: _immediate(custom),
        empty.id: _immediate(empty),
        text.id: _parsed(text, 'Preview text from a file'),
        markdown.id: FolderGalleryPreview(
          kind: FolderGalleryPreviewKind.document,
          blocks: parseMarkdownPreviewBlocks(
            '# Shared note\n\nA **bold** word.\n\n- Actual item',
          ),
          wordCount: 7,
          readingMinutes: 1,
          tags: const [],
          fileTypeLabel: 'MD',
        ),
        cover.id: _parsed(cover, 'Covered content stays hidden'),
      };
      final loader = _RecordingLoader(
        ({required view, required item}) => Future.value(data[view.id]!),
      );
      final repository = _Repository(views);
      final controller = await _adoptListing(tester, repository, loader);
      // Unlike the real-file tests, these futures belong to FakeAsync. Complete
      // them with a pump, never by awaiting them inside runAsync.
      final futures = {
        for (final view in views) view.id: controller.folderPreviewFor(view),
      };
      await tester.pump();
      final icons = ValueNotifier(DefaultIconStyle.vivid);
      try {
        await tester.pumpWidget(
          _app(
            DefaultIconStyleScope(
              styles: icons,
              child: Builder(
                builder: (context) => _goldenBoard(context, controller, views),
              ),
            ),
            appearance: appearance,
            reducedMotion: true,
          ),
        );
        await _flush(tester);
        expect(find.byKey(_loading), findsNothing);
        expect(find.byKey(_unavailable), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await _warmGoldenPictures(tester);
        expect(find.byType(FolderEmbedPreview), findsNWidgets(3));
        expect(find.byType(FolderGalleryCard), findsNWidgets(views.length));
        expect(find.byType(FolderGalleryPreviewThumbnail), findsNWidgets(12));
        expect(find.byType(CollectionObjectCard), findsNothing);
        expect(find.byType(CollectionArtwork), findsNothing);
        expect(find.byType(CollectionArtworkGlyph), findsNothing);
        expect(tester.getSize(find.byKey(_goldenKey)), const Size(1160, 1040));

        for (final style in _styles) {
          final scope = find.byKey(ValueKey('golden-embed-$style'));
          expect(
            PaperTheme.isEnabled(tester.element(scope)),
            appearance == 'paper',
          );
          _expectContained(tester, scope, find.byKey(_goldenKey));
          final scroll = tester.state<ScrollableState>(
            // This is the grid, before any nested file-preview scrollables.
            find.descendant(of: scope, matching: find.byType(Scrollable)).first,
          );
          expect(
            scroll.position.maxScrollExtent,
            0,
            reason: 'The comparison sheet must show every fixture item fully',
          );
          if (style == FolderEmbedStyles.list) {
            expect(
              find.descendant(
                of: scope,
                matching: find.byType(FolderGalleryPreviewThumbnail),
              ),
              findsNothing,
            );
          }
          for (final view in views) {
            final item = find.descendant(of: scope, matching: _item(view));
            expect(item, findsOneWidget);
            _expectContained(tester, item, scope);
            expect(
              find.descendant(of: item, matching: find.text(view.name)),
              findsOneWidget,
            );
            final metadata = find.descendant(
              of: item,
              matching:
                  find.byKey(const ValueKey('folder-embed-item-metadata')),
            );
            if (style == FolderEmbedStyles.compact) {
              expect(metadata, findsNothing);
            } else {
              expect(
                tester.widget<Text>(metadata).data,
                collectionObjectSubtitle(view),
              );
              _expectContained(tester, metadata, item);
            }
            final reference =
                find.byKey(ValueKey('golden-reference-${view.id}'));
            final stage = find.descendant(
              of: reference,
              matching:
                  find.byKey(const ValueKey('folder-gallery-preview-stage')),
            );
            expect(
              tester.widget<FolderGalleryCard>(reference).preview,
              same(futures[view.id]),
            );
            _expectContained(tester, reference, find.byKey(_goldenKey));
            _expectContained(tester, stage, reference);
            if (style == FolderEmbedStyles.list) {
              if (view == custom) {
                final saved = find.descendant(
                  of: item,
                  matching: find.byType(RawEmojiIconWidget),
                );
                final icon = tester.widget<RawEmojiIconWidget>(saved);
                final regular = tester.widget<RawEmojiIconWidget>(
                  find.descendant(
                    of: stage,
                    matching: find.byType(RawEmojiIconWidget),
                  ),
                );
                expect(icon.emoji.type, regular.emoji.type);
                expect(icon.emoji.emoji, custom.icon.value);
                expect(icon.emoji.emoji, regular.emoji.emoji);
                expect(icon.emojiSize, 16);
                expect(regular.emojiSize, 64);
                expect(
                  find.descendant(
                    of: saved,
                    matching: find.byType(SvgPicture),
                  ),
                  findsOneWidget,
                );
                _expectContained(tester, saved, item);
              } else {
                final identity = find.descendant(
                  of: item,
                  matching: find.byType(WorkspaceItemIcon),
                );
                expect(
                  tester.widget<WorkspaceItemIcon>(identity).view,
                  same(view),
                );
                expect(
                  tester.widget<WorkspaceItemIcon>(identity).showThumbnail,
                  isFalse,
                );
                final glyph = tester.widget<WorkspaceGlyph>(
                  find.descendant(
                    of: identity,
                    matching: find.byType(WorkspaceGlyph),
                  ),
                );
                expect(
                  glyph.name,
                  {
                    folder.id: 'folder',
                    empty.id: 'file-code',
                    text.id: 'file-text',
                    markdown.id: 'file-markdown',
                    cover.id: 'file-text',
                  }[view.id],
                );
                expect(glyph.size, 16);
                expect(glyph.color, isNull);
                _expectContained(tester, identity, item);
              }
            } else {
              final thumbnail =
                  find.descendant(of: scope, matching: _thumbnail(view));
              final widget =
                  tester.widget<FolderGalleryPreviewThumbnail>(thumbnail);
              expect(widget.view, same(view));
              expect(widget.preview, same(futures[view.id]));
              expect(widget.previewMode, isNull);
              expect(widget.compact, isTrue);
              expect(_contract(tester, thumbnail), isNotEmpty);
              expect(_contract(tester, thumbnail), _contract(tester, stage));
              _expectContained(tester, thumbnail, item);
              final footer = find.descendant(
                of: item,
                matching: find.byType(GalleryCardFooter),
              );
              expect(
                footer,
                style == FolderEmbedStyles.compact
                    ? findsNothing
                    : findsOneWidget,
              );
              if (style != FolderEmbedStyles.compact) {
                _expectContained(tester, footer, item);
              }
              if (view == custom) {
                expect(
                  find.descendant(
                    of: thumbnail,
                    matching: find.byType(SvgPicture),
                  ),
                  findsOneWidget,
                );
              }
            }
            expect(controller.folderPreviewFor(view), same(futures[view.id]));
            expect(view.writeToBuffer(), before[view.id]);
          }
        }
        expect(find.text('Preview text from a file'), findsNWidgets(3));
        expect(find.text('Shared note'), findsNWidgets(3));
        expect(find.text('A bold word.'), findsNWidgets(3));
        expect(find.text('Covered content stays hidden'), findsNothing);
        expect(find.byType(ViewCoverImage), findsNWidgets(3));
        expect(find.byKey(_fileFace), findsNWidgets(3));
        expect(find.byKey(_count), findsNWidgets(3));
        expect(loader.reads, {for (final view in views) view.id: 1});
        expect(repository.reads, ['root']);
        expect(repository.writes, isEmpty);
        expect(tester.takeException(), isNull);
        // New baselines: the coordinator renders/reviews them, never this fix.
        await expectLater(
          find.byKey(_goldenKey),
          matchesGoldenFile('goldens/folder_embed_shared_$appearance.png'),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        icons.dispose();
      }
    });
  }

  _test(
      'pending and loaded renderers follow sort, size, theme and gallery/strip changes',
      (tester) async {
    final first = _page('first', name: 'Zulu');
    final second = _page('second', name: 'Alpha');
    final pending = Completer<FolderGalleryPreview>();
    final loader = _RecordingLoader(
      ({required view, required item}) => view.id == second.id
          ? pending.future
          : Future.value(_parsed(view, 'Already loaded')),
    );
    final repository = _Repository([first, second]);
    final controller = _controller(repository, loader);
    await _mount(tester, controller);
    final futures = {
      for (final view in [first, second]) view.id: _future(tester, view),
    };
    final elements = {
      for (final view in [first, second])
        view.id: tester.element(_thumbnail(view)),
    };
    final states = {
      for (final view in [first, second]) view.id: tester.state(_item(view)),
    };
    final rich = tester.element(find.byType(FolderGalleryRichTextPreview));
    for (final appearance in _appearances) {
      for (final style in [
        FolderEmbedStyles.compact,
        FolderEmbedStyles.gallery,
      ]) {
        for (final preset in [
          CollectionEmbedSize.compact,
          CollectionEmbedSize.medium,
        ]) {
          await _mount(
            tester,
            controller,
            appearance: appearance,
            size: const Size(590, 300),
            hovered: true,
            settings: _settings.copyWith(
              style: style,
              sort: CollectionEmbedSort.name,
              size: preset,
              columns: 3,
            ),
          );
          for (final view in [first, second]) {
            expect(_future(tester, view), same(futures[view.id]));
            expect(tester.element(_thumbnail(view)), same(elements[view.id]));
            expect(tester.state(_item(view)), same(states[view.id]));
          }
          expect(
            tester.element(find.byType(FolderGalleryRichTextPreview)),
            same(rich),
          );
          expect(find.byKey(_loading), findsOneWidget);
          expect(
            tester.getTopLeft(_item(second)).dx,
            lessThan(tester.getTopLeft(_item(first)).dx),
          );
          expect(tester.takeException(), isNull);
        }
      }
    }
    await _mount(
      tester,
      controller,
      settings: _settings.copyWith(style: FolderEmbedStyles.list),
    );
    expect(find.byType(FolderGalleryPreviewThumbnail), findsNothing);
    pending.complete(_parsed(second, 'Completed while in list mode'));
    await _flush(tester);
    await _mount(tester, controller);
    expect(find.text('Completed while in list mode'), findsOneWidget);
    for (final view in [first, second]) {
      expect(_future(tester, view), same(futures[view.id]));
    }
    expect(loader.reads, {first.id: 1, second.id: 1});
    expect(repository.reads, ['root']);
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    _test('hover/focus are paint-only; reduced motion=$reduced',
        (tester) async {
      final view = _page('quiet');
      final loader = _RecordingLoader(
        ({required view, required item}) async =>
            _parsed(view, 'Stationary real content'),
      );
      final controller = _controller(_Repository([view]), loader);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: const Offset(2, 2));
        await _mount(tester, controller, reducedMotion: reduced);
        final bounds = tester.getRect(_thumbnail(view));
        final itemBounds = tester.getRect(_item(view));
        final renderer =
            tester.element(find.byType(FolderGalleryRichTextPreview));
        final future = _future(tester, view);
        for (final hovered in [true, false, true, false]) {
          await mouse.moveTo(hovered ? itemBounds.center : const Offset(2, 2));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 70));
          expect(tester.getRect(_thumbnail(view)), bounds);
          expect(tester.getRect(_item(view)), itemBounds);
          expect(
            tester.element(find.byType(FolderGalleryRichTextPreview)),
            same(renderer),
          );
          expect(_future(tester, view), same(future));
          await tester.pump(const Duration(milliseconds: 100));
        }
        final ink = tester.widget<InkWell>(
          find.descendant(of: _item(view), matching: find.byType(InkWell)),
        );
        ink.focusNode!.requestFocus();
        await _flush(tester);
        expect(
          tester
              .widget<GalleryCardSurface>(find.byType(GalleryCardSurface))
              .focused,
          isTrue,
        );
        expect(tester.getRect(_thumbnail(view)), bounds);
        expect(tester.getRect(_item(view)), itemBounds);
        expect(loader.reads, {view.id: 1});
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
      }
    });
  }

  _test(
      'an adopted refresh invalidates identical stamps and ignores old pending results',
      (tester) async {
    final first = _page('first');
    final second = _page('second');
    final oldPending = Completer<FolderGalleryPreview>();
    final freshFirst = Completer<FolderGalleryPreview>();
    final freshSecond = Completer<FolderGalleryPreview>();
    var refreshed = false;
    final loader = _RecordingLoader(({required view, required item}) {
      if (refreshed) {
        return view.id == first.id ? freshFirst.future : freshSecond.future;
      }
      return view.id == first.id
          ? Future.value(_parsed(view, 'Before refresh'))
          : oldPending.future;
    });
    final repository = _Repository([first, second]);
    final controller = _controller(repository, loader);
    await _mount(tester, controller);
    final before = _future(tester, first);
    final retained = tester.state(_item(first));
    refreshed = true;
    repository.children = [
      for (final view in [second, first])
        ViewPB.fromBuffer(view.writeToBuffer()),
    ];
    await controller.refresh();
    await _flush(tester);
    expect(_future(tester, first), isNot(same(before)));
    expect(tester.state(_item(first)), same(retained));
    expect(find.text('Before refresh'), findsNothing);
    expect(find.byKey(_loading), findsNWidgets(2));
    oldPending.complete(_parsed(second, 'Obsolete late response'));
    await _flush(tester);
    expect(find.text('Obsolete late response'), findsNothing);
    freshFirst.complete(_parsed(first, 'Current first'));
    freshSecond.complete(_parsed(second, 'Current second'));
    await _flush(tester);
    expect(find.text('Current first'), findsOneWidget);
    expect(find.text('Current second'), findsOneWidget);
    expect(loader.reads, {first.id: 2, second.id: 2});
    expect(repository.reads, ['root', 'root']);
    expect(repository.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  _test('changed view stamps invalidate, including in-place PB updates',
      (tester) async {
    final view = _page('stamped');
    final previous = Completer<FolderGalleryPreview>();
    final current = Completer<FolderGalleryPreview>();
    final loader = _RecordingLoader(
      ({required view, required item}) =>
          view.lastEdited.toInt() == 1 ? previous.future : current.future,
    );
    final controller = _controller(_Repository([view]), loader);
    await _mount(tester, controller);
    final oldFuture = _future(tester, view);
    final element = tester.element(_thumbnail(view));
    view.lastEdited = Int64(2);
    await _mount(tester, controller);
    expect(_future(tester, view), isNot(same(oldFuture)));
    expect(tester.element(_thumbnail(view)), same(element));
    previous.complete(_parsed(view, 'Outdated content'));
    await _flush(tester);
    expect(find.text('Outdated content'), findsNothing);
    expect(find.byKey(_loading), findsOneWidget);
    current.complete(_parsed(view, 'Latest content'));
    await _flush(tester);
    expect(find.text('Latest content'), findsOneWidget);
    expect(loader.reads, {view.id: 2});
    expect(tester.takeException(), isNull);
  });

  _test(
      'controller/root replacement never reuses same-ID state or stale futures',
      (tester) async {
    final view = _page('same-child');
    final pending = [
      for (var index = 0; index < 3; index++) Completer<FolderGalleryPreview>(),
    ];
    final loaders = [
      for (final result in pending)
        _RecordingLoader(({required view, required item}) => result.future),
    ];
    final controllers = [
      for (var index = 0; index < 3; index++)
        _controller(
          _Repository([view]),
          loaders[index],
          root: _folder(index == 0 ? 'root-a' : 'root-b'),
        ),
    ];
    await _mount(tester, controllers[0]);
    final oldState = tester.state(_item(view));
    final oldFuture = _future(tester, view);
    await _mount(tester, controllers[1]);
    expect(oldState.mounted, isFalse);
    expect(controllers[0].hasPreviewListeners, isFalse);
    expect(_future(tester, view), isNot(same(oldFuture)));
    final secondState = tester.state(_item(view));
    // Same root identity, different repository/controller: still a new owner.
    await _mount(tester, controllers[2]);
    expect(secondState.mounted, isFalse);
    expect(controllers[1].hasPreviewListeners, isFalse);
    pending[0].complete(_parsed(view, 'Wrong root'));
    pending[1].complete(_parsed(view, 'Wrong controller'));
    await _flush(tester);
    expect(find.text('Wrong root'), findsNothing);
    expect(find.text('Wrong controller'), findsNothing);
    expect(find.byKey(_loading), findsOneWidget);
    pending[2].complete(_parsed(view, 'Current owner'));
    await _flush(tester);
    expect(find.text('Current owner'), findsOneWidget);
    for (final loader in loaders) {
      expect(loader.reads, {view.id: 1});
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controllers[2].hasPreviewListeners, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  _test(
      'loading, failed root read with native retry, and genuine empty are distinct',
      (tester) async {
    final listing = Completer<FlowyResult<List<ViewPB>, FlowyError>>();
    final retryListing = Completer<FlowyResult<List<ViewPB>, FlowyError>>();
    final repository = _Repository([])..next = listing.future;
    final loader = _identityLoader();
    final controller = _controller(repository, loader);
    await _mount(
      tester,
      controller,
      appearance: 'paper',
      textScale: 2,
      size: const Size(320, 90),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    listing.complete(
      FlowyResult.failure(FlowyError(msg: 'Private listing failure')),
    );
    await _flush(tester);
    expect(
      find.byKey(const ValueKey('folder-embed-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('folder-embed-empty')), findsNothing);
    expect(find.textContaining('Private listing failure'), findsNothing);
    repository.next = retryListing.future;
    await tester
        .ensureVisible(find.byKey(const ValueKey('folder-embed-retry')));
    await tester.tap(find.byKey(const ValueKey('folder-embed-retry')));
    await tester.pump();
    expect(repository.reads, ['root', 'root']);
    retryListing.complete(FlowyResult.success([]));
    await _flush(tester);
    expect(find.byKey(const ValueKey('folder-embed-empty')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('folder-embed-unavailable')),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(loader.reads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  _test(
      'list is read-free; limits/manual order stay intact and the shared cache is bounded',
      (tester) async {
    final views = [
      for (var index = 0; index < 64; index++) _page('page-$index'),
    ];
    final repository = _Repository(views);
    final loader = _identityLoader();
    final controller = _controller(repository, loader);
    await _mount(
      tester,
      controller,
      settings: _settings.copyWith(style: FolderEmbedStyles.list, itemLimit: 2),
    );
    expect(loader.reads, isEmpty);
    expect(_item(views[0]), findsOneWidget);
    expect(_item(views[1]), findsOneWidget);
    expect(_item(views[2]), findsNothing);
    await _mount(
      tester,
      controller,
      settings: _settings.copyWith(itemLimit: 2),
    );
    expect(loader.reads, {views[0].id: 1, views[1].id: 1});
    expect(
      tester.getTopLeft(_item(views[0])).dx,
      lessThan(tester.getTopLeft(_item(views[1])).dx),
    );
    final grid = tester
        .widget<GridView>(find.byKey(const ValueKey('folder-embed-items')));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      2,
    );
    final delegate = grid.childrenDelegate as SliverChildBuilderDelegate;
    expect(
      delegate.findChildIndexCallback!(
        ValueKey('folder-embed-item-${views[1].id}'),
      ),
      1,
    );
    // Exercise the actual controller-owned LRU, not a second test-only cache.
    await tester.pumpWidget(const SizedBox.shrink());
    for (final view in views
        .skip(2)
        .take(CollectionEmbedController.maximumPreviewEntries - 1)) {
      await controller.folderPreviewFor(view);
    }
    await controller.folderPreviewFor(views[0]);
    expect(loader.reads[views[0].id], 2);
    expect(repository.reads, ['root']);
    expect(repository.children, orderedEquals(views));
    expect(repository.writes, isEmpty);
  });

  _test(
      'real decoded image renderer survives sort, resize and gallery/strip changes',
      (tester) async {
    final view = _file('photo.png', _imageFile.path);
    final peer = _folder('other', name: 'AAA');
    final documents = _Documents({});
    final reader = FolderGalleryPreviewLoader(documentService: documents);
    final loader = _RecordingLoader(reader.load);
    final controller = _controller(_Repository([view, peer]), loader);
    final provider = FileImage(_imageFile);
    ImageInfo? cached;
    try {
      cached = await tester.runAsync(() async {
        final decoded = Completer<ImageInfo>();
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (info, _) => decoded.complete(info),
          onError: decoded.completeError,
        );
        try {
          stream.addListener(listener);
          return await decoded.future.timeout(_ioTimeout);
        } finally {
          stream.removeListener(listener);
        }
      });
      await _mount(tester, controller);
      final image =
          find.descendant(of: _thumbnail(view), matching: find.byType(Image));
      final state = tester.state(image);
      final future = _future(tester, view);
      final raw = find.descendant(of: image, matching: find.byType(RawImage));
      final decoded = tester.widget<RawImage>(raw).image!;
      expect(decoded.isCloneOf(cached!.image), isTrue);
      expect(decoded.width, 12);
      expect(decoded.height, 8);
      final pixels =
          await tester.runAsync(() => decoded.toByteData().timeout(_ioTimeout));
      expect(pixels!.getUint8(0), 0xDE);
      expect(pixels.getUint8(1), 0x49);
      for (final appearance in _appearances) {
        for (final style in [
          FolderEmbedStyles.compact,
          FolderEmbedStyles.gallery,
        ]) {
          await _mount(
            tester,
            controller,
            appearance: appearance,
            size: const Size(500, 260),
            settings: _settings.copyWith(
              style: style,
              sort: CollectionEmbedSort.name,
            ),
          );
          expect(tester.state(image), same(state));
          expect(
            tester.widget<RawImage>(raw).image!.isCloneOf(decoded),
            isTrue,
          );
          expect(_future(tester, view), same(future));
          expect(imageCache.statusForKey(provider).pending, isFalse);
          expect(tester.takeException(), isNull);
        }
      }
      expect(documents.reads, isEmpty);
      expect(loader.reads, {view.id: 1, peer.id: 1});
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      cached?.dispose();
      await tester.runAsync(() => provider.evict().timeout(_ioTimeout));
    }
  });

  _test(
      'classified media and uploaded icons reach the real thumbnail unchanged',
      (tester) async {
    for (final (name, kind) in [
      ('photo.png', FolderGalleryPreviewKind.image),
      ('paper.pdf', FolderGalleryPreviewKind.pdf),
      ('movie.mp4', FolderGalleryPreviewKind.video),
    ]) {
      final view = _file(name, _blankFile.path)
        ..icon = ViewIconPB(ty: ViewIconTypePB.Url, value: _imageFile.path);
      view.extra = ViewCoverCodec.mergeCover(
        view.extra,
        const PageStyleCover(
          type: PageStyleCoverImageType.pureColor,
          value: '#C6BAAD',
        ),
      );
      final bytes = view.writeToBuffer();
      final documents = _Documents({});
      final reader = FolderGalleryPreviewLoader(documentService: documents);
      final loader = _RecordingLoader(reader.load);
      final controller = _controller(_Repository([view]), loader);
      // Cover-only avoids instantiating PDF/video engines or the existing
      // uploaded-icon renderer's hardwired UserEventGetUserProfile FFI read.
      // Actual emoji/library rendering is tested above; uploaded transport is
      // intentionally not claimed by this backend-free widget fixture.
      await _mount(
        tester,
        controller,
        settings: _settings.copyWith(size: CollectionEmbedSize.compact),
      );
      final thumbnail =
          tester.widget<FolderGalleryPreviewThumbnail>(_thumbnail(view));
      final preview = await thumbnail.preview;
      expect(preview.kind, kind);
      expect(preview.heroUrl, _blankFile.path);
      expect(thumbnail.view, same(view));
      expect(thumbnail.view.icon.ty, ViewIconTypePB.Url);
      expect(thumbnail.view.icon.value, _imageFile.path);
      expect(thumbnail.previewMode, isNull, reason: 'Use the saved view mode.');
      expect(find.byType(ViewCoverImage), findsOneWidget);
      expect(find.byType(RawEmojiIconWidget), findsNothing);
      expect(documents.reads, isEmpty);
      expect(view.writeToBuffer(), bytes);
      expect(tester.takeException(), isNull);
    }
  });

  for (final kind in [null, CollectionKind.folder]) {
    _test(
        'actual CollectionEmbed frame/definition (${kind?.name ?? 'plain'}) preserves settings, PBs and a draft',
        (tester) async {
      final root = kind == null
          ? _folder('root')
          : ViewPB(
              id: 'root',
              name: 'Folder collection',
              extra: CollectionMetadata.newExtra(kind),
            );
      final view = _page('frame-child');
      final pending = Completer<FolderGalleryPreview>();
      final loader =
          _RecordingLoader(({required view, required item}) => pending.future);
      final repository = _Repository([view]);
      final controller = _controller(repository, loader, root: root);
      final draft = TextEditingController(text: 'Unsaved author draft')
        ..selection = const TextSelection(baseOffset: 2, extentOffset: 8);
      final draftValue = draft.value;
      final changes = <CollectionEmbedSettings>[];
      final rootBytes = root.writeToBuffer();
      final viewBytes = view.writeToBuffer();
      final settingsBytes = jsonEncode(_settings.toJson());
      try {
        Widget frame(bool fullscreen) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 380, child: TextField(controller: draft)),
                SizedBox(
                  width: 700,
                  height: 380,
                  child: CollectionEmbed(
                    collection: root,
                    controller: controller,
                    fullscreen: fullscreen,
                    height: 320,
                    settings: _settings,
                    onSettingsChanged: changes.add,
                    editable: false,
                  ),
                ),
              ],
            );
        await tester.pumpWidget(_app(frame(true)));
        await _flush(tester);
        expect(find.byType(FolderEmbedPreview), findsOneWidget);
        expect(find.byType(FolderGalleryPreviewThumbnail), findsOneWidget);
        final future = _future(tester, view);
        final editor =
            tester.state<EditableTextState>(find.byType(EditableText));
        pending
            .complete(_parsed(view, 'Through the real registered definition'));
        await _flush(tester);
        for (final appearance in _appearances) {
          for (final fullscreen in [false, true]) {
            await tester
                .pumpWidget(_app(frame(fullscreen), appearance: appearance));
            await _flush(tester);
            expect(
              find.text('Through the real registered definition'),
              findsOneWidget,
            );
            expect(_future(tester, view), same(future));
            expect(
              tester.state<EditableTextState>(find.byType(EditableText)),
              same(editor),
            );
            expect(draft.value, draftValue);
            expect(root.writeToBuffer(), rootBytes);
            expect(view.writeToBuffer(), viewBytes);
            expect(jsonEncode(_settings.toJson()), settingsBytes);
            expect(changes, isEmpty);
            expect(repository.writes, isEmpty);
            expect(tester.takeException(), isNull);
          }
        }
        expect(loader.reads, {view.id: 1});
        expect(repository.reads, ['root']);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        draft.dispose();
      }
    });
  }
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        try {
          await HttpOverrides.runZoned(
            () => body(tester),
            createHttpClient: (_) => throw StateError(
              'Network is forbidden in folder embed fixtures',
            ),
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

Future<void> _flush(WidgetTester tester) async {
  // Deliberately bounded: pending thumbnails animate, so pumpAndSettle is wrong.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 180));
}

Future<CollectionEmbedController> _adoptListing(
  WidgetTester tester,
  _Repository repository,
  _RecordingLoader loader,
) async {
  final listing = Completer<FlowyResult<List<ViewPB>, FlowyError>>();
  expect(repository.next, isNull);
  repository.next = listing.future;
  final controller = _controller(repository, loader);
  expect(controller.isLoading, isTrue);
  expect(controller.children, isEmpty);
  expect(repository.reads, [controller.collection.id]);
  expect(loader.reads, isEmpty);
  listing.complete(FlowyResult.success(repository.children));
  await tester.pump();
  // _load clears the preview cache on adoption, even for the initial listing.
  // Prove adoption before the first preview request, not just a time delay.
  expect(controller.isLoading, isFalse);
  expect(controller.error, isNull);
  expect(controller.children, same(repository.children));
  expect(loader.reads, isEmpty);
  return controller;
}

Future<Map<String, Future<FolderGalleryPreview>>> _warmControllerPreviews(
  WidgetTester tester,
  CollectionEmbedController controller,
  List<ViewPB> views,
) async {
  expect(controller.isLoading, isFalse);
  final warmed = <String, Future<FolderGalleryPreview>>{};
  for (final view in views) {
    final data = await tester.runAsync(() {
      final future = controller.folderPreviewFor(view);
      warmed[view.id] = future;
      return future.timeout(_ioTimeout);
    });
    expect(
      data,
      isNotNull,
      reason: 'Warm the actual cached preview: ${view.name}',
    );
    expect(data!.unavailable, isFalse, reason: view.name);
    expect(controller.folderPreviewFor(view), same(warmed[view.id]));
  }
  return warmed;
}

Future<void> _paintWarmedPreviews(
  WidgetTester tester,
  CollectionEmbedController controller,
  Map<String, Future<FolderGalleryPreview>> warmed,
) async {
  expect(controller.isLoading, isFalse);
  expect(controller.error, isNull);
  for (final entry in warmed.entries) {
    final view =
        controller.children.singleWhere((view) => view.id == entry.key);
    // Check identity BEFORE awaiting: a cache miss could start new file IO in
    // FakeAsync, whose future cannot safely be awaited inside runAsync.
    expect(controller.folderPreviewFor(view), same(entry.value));
    expect(_future(tester, view), same(entry.value));
  }
  // Dart _Future._addListener queues late listeners in the source future's
  // zone. These completed runAsync futures therefore need a real microtask
  // turn AFTER FutureBuilder subscribes; fake-clock pumps alone cannot do it.
  await tester.runAsync(() async {
    for (final future in warmed.values) {
      await future.timeout(_ioTimeout);
    }
  });
  await _flush(tester);
}

Widget _goldenBoard(
  BuildContext context,
  CollectionEmbedController controller,
  List<ViewPB> views,
) {
  Widget label(String text) => SizedBox(
        height: 24,
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
  return RepaintBoundary(
    key: _goldenKey,
    child: SizedBox(
      width: 1160,
      height: 1040,
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label('Workspace gallery — shared renderer reference'),
              SizedBox(
                height: 208,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < views.length; index++) ...[
                      if (index > 0) const SizedBox(width: 11),
                      Expanded(
                        child: FolderGalleryCard(
                          key: ValueKey('golden-reference-${views[index].id}'),
                          item: WorkspaceExplorerItem.fromView(views[index]),
                          view: views[index],
                          preview: controller.folderPreviewFor(views[index]),
                          userProfile: null,
                          selected: false,
                          editing: false,
                          canRename: false,
                          onTap: () {},
                          onRename: () {},
                          onRenameSubmitted: (_) async => false,
                          onRenameCancelled: () {},
                          onMore: (_) {},
                          onContextMenu: (_) {},
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              for (final (style, height) in [
                (FolderEmbedStyles.gallery, 236.0),
                // Square preview 128 + caption 50 + top/bottom padding 8/12.
                (FolderEmbedStyles.compact, 198.0),
                (FolderEmbedStyles.list, 224.0),
              ]) ...[
                const SizedBox(height: 12),
                label('Folder embed — $style'),
                SizedBox(
                  height: height,
                  child: FolderEmbedPreview(
                    key: ValueKey('golden-embed-$style'),
                    embed: CollectionEmbedContext(
                      collection: controller.collection,
                      controller: controller,
                      settings: _settings.copyWith(
                        style: style,
                        columns: 6,
                        itemLimit: 6,
                      ),
                      theme: CollectionEmbedTheme.of(context, null),
                      definition: buildFolderEmbedDefinition(),
                      onSettingsChanged: (_) =>
                          throw StateError('Golden must not persist settings'),
                      onOpenObject: (_) {},
                      onOpenCollection: () {},
                      onFullscreen: () {},
                      onRefresh: () =>
                          throw StateError('Golden must not refresh'),
                      onShowMenu: (_) {},
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _warmGoldenPictures(WidgetTester tester) async {
  final pictures = find.byType(SvgPicture).evaluate().toList();
  expect(pictures, isNotEmpty);
  for (final element in pictures) {
    // Compiled defaults and the saved Vivid icon are SVG strings: no asset,
    // file/network loaders or embedded-media engines in this visual fixture.
    expect((element.widget as SvgPicture).bytesLoader, isA<SvgStringLoader>());
  }
  final sizes = await tester.runAsync(() async {
    final sizes = <Size>[];
    for (final element in pictures) {
      final svg = element.widget as SvgPicture;
      final decoded =
          await vg.loadPicture(svg.bytesLoader, element).timeout(_ioTimeout);
      try {
        sizes.add(decoded.size);
      } finally {
        decoded.picture.dispose();
      }
    }
    return sizes;
  });
  expect(sizes, hasLength(pictures.length));
  expect(sizes!.every((size) => size.isFinite && !size.isEmpty), isTrue);
  await tester.pump();
  await tester.pump();
  for (final element in pictures) {
    expect(element.mounted, isTrue);
    // vector_graphics builds this fitted picture only after decoding; its
    // loading placeholder is just a SizedBox. Do not bless blank SVG slots.
    final svg =
        find.byElementPredicate((candidate) => identical(candidate, element));
    expect(
      find.descendant(of: svg, matching: find.byType(FittedBox)),
      findsOneWidget,
    );
    _expectContained(tester, svg, find.byKey(_goldenKey));
  }
}

void _expectContained(WidgetTester tester, Finder child, Finder parent) {
  Rect bounds(Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    expect(box.attached, isTrue);
    expect(box.hasSize, isTrue);
    // Compact embeds can scale the shared thumbnail down. getRect's unscaled
    // size is not the painted rectangle; include the complete ancestor transform.
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    expect(rect.isFinite, isTrue);
    expect(rect.isEmpty, isFalse);
    return rect;
  }

  final outer = bounds(parent);
  final inner = bounds(child);
  const epsilon = 0.000001; // Floating-point transforms only, not layout slack.
  expect(inner.left, greaterThanOrEqualTo(outer.left - epsilon));
  expect(inner.top, greaterThanOrEqualTo(outer.top - epsilon));
  expect(inner.right, lessThanOrEqualTo(outer.right + epsilon));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + epsilon));
}

Future<void> _mount(
  WidgetTester tester,
  CollectionEmbedController controller, {
  CollectionEmbedSettings settings = _settings,
  String appearance = 'light',
  Size size = const Size(720, 360),
  double textScale = 1,
  bool reducedMotion = false,
  bool hovered = false,
  ViewPB? reference,
  ValueChanged<ViewPB>? onOpen,
  ValueChanged<Offset>? onMenu,
}) async {
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) {
          final definition = buildFolderEmbedDefinition(
            kind: controller.collection.collection?.kind,
          );
          final embed = CollectionEmbedContext(
            collection: controller.collection,
            controller: controller,
            settings: settings,
            theme: CollectionEmbedTheme.of(
              context,
              controller.collection.collection?.kind,
            ),
            definition: definition,
            hovered: hovered,
            onSettingsChanged: (_) =>
                throw StateError('Preview must not persist settings'),
            onOpenObject: onOpen ?? (_) {},
            onOpenCollection: () {},
            onFullscreen: () {},
            onRefresh: () => unawaited(controller.refresh()),
            onShowMenu: onMenu ?? (_) {},
          );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size.width,
                height: size.height,
                child: FolderEmbedPreview(embed: embed),
              ),
              if (reference != null)
                SizedBox(
                  width: 240,
                  height: 160,
                  child: GalleryCardSurface(
                    child: FolderGalleryPreviewThumbnail(
                      key: _referenceKey,
                      item: WorkspaceExplorerItem.fromView(reference),
                      view: reference,
                      preview: controller.folderPreviewFor(reference),
                      userProfile: null,
                      height: 160,
                      compact: true,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      appearance: appearance,
      textScale: textScale,
      reducedMotion: reducedMotion,
    ),
  );
  await _flush(tester);
}

Widget _app(
  Widget child, {
  String appearance = 'light',
  double textScale = 1,
  bool reducedMotion = false,
}) =>
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'unused-preloaded-assets',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: DesktopAppearance()
              .getThemeData(
                appearance == 'paper'
                    ? AppTheme.builtins.firstWhere(
                        (theme) => theme.themeName == BuiltInTheme.paper,
                      )
                    : AppTheme.fallback,
                appearance == 'dark' ? Brightness.dark : Brightness.light,
                preferredFontFamily,
                builtInCodeFontFamily,
              )
              .copyWith(platform: TargetPlatform.windows),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  disableAnimations: reducedMotion,
                ),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );

Finder _item(ViewPB view) =>
    find.byKey(ValueKey('folder-embed-item-${view.id}'));
Finder _thumbnail(ViewPB view) =>
    find.byKey(ValueKey('folder-embed-thumbnail-${view.id}'));
Future<FolderGalleryPreview> _future(WidgetTester tester, ViewPB view) =>
    tester.widget<FolderGalleryPreviewThumbnail>(_thumbnail(view)).preview;

List<Object?> _contract(WidgetTester tester, Finder scope) => [
      for (final glyph in tester.widgetList<WorkspaceGlyph>(
        find.descendant(of: scope, matching: find.byType(WorkspaceGlyph)),
      ))
        [glyph.name, glyph.size, glyph.color],
      for (final saved in tester.widgetList<RawEmojiIconWidget>(
        find.descendant(of: scope, matching: find.byType(RawEmojiIconWidget)),
      ))
        [saved.emoji.type, saved.emoji.emoji, saved.emojiSize],
      for (final svg in tester.widgetList<SvgPicture>(
        find.descendant(of: scope, matching: find.byType(SvgPicture)),
      ))
        [svg.bytesLoader, svg.colorFilter],
      for (final cover in tester.widgetList<ViewCoverImage>(
        find.descendant(of: scope, matching: find.byType(ViewCoverImage)),
      ))
        [cover.cover.type, cover.cover.value],
      for (final rich in tester.widgetList<FolderGalleryRichTextPreview>(
        find.descendant(
          of: scope,
          matching: find.byType(FolderGalleryRichTextPreview),
        ),
      ))
        [
          for (final block in rich.blocks)
            [
              block.kind,
              block.plainText,
              block.level,
              block.checked,
              block.language,
              for (final run in block.runs)
                [run.text, run.bold, run.italic, run.inlineCode],
            ],
        ],
      for (final count in tester.widgetList<Text>(
        find.descendant(of: scope, matching: find.byKey(_count)),
      ))
        count.data,
    ];

_TestCollectionEmbedController _controller(
  _Repository repository,
  FolderGalleryPreviewLoader loader, {
  ViewPB? root,
}) {
  final controller = _TestCollectionEmbedController(
    collection: root ?? _folder('root'),
    repository: repository,
    previewLoader: loader,
    listenForUpdates: false,
  );
  _controllers.add(controller);
  return controller;
}

class _TestCollectionEmbedController extends CollectionEmbedController {
  _TestCollectionEmbedController({
    required super.collection,
    required super.repository,
    required super.previewLoader,
    required super.listenForUpdates,
  });

  bool get hasPreviewListeners => hasListeners;
}

ViewPB _folder(String id, {String? name}) => ViewPB(
      id: id,
      name: name ?? id,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );

ViewPB _page(String id, {String? name}) => ViewPB(
      id: id,
      name: name ?? id,
      layout: ViewLayoutPB.Document,
      lastEdited: Int64(1),
    );

ViewPB _file(String name, String path) => ViewPB(
      id: 'file::$name',
      name: name,
      layout: ViewLayoutPB.Document,
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: path,
      ).mergeIntoExtra(''),
    );

DocumentDataPB _document(List<BlockPB> children) => DocumentDataPB(
      pageId: 'document-root',
      blocks: {
        'document-root':
            BlockPB(id: 'document-root', ty: 'page', childrenId: 'children'),
        for (final child in children) child.id: child,
      },
      meta: MetaPB(
        childrenMap: {
          'children': ChildrenPB(children: children.map((child) => child.id)),
        },
      ),
    );

DocumentDataPB _writtenDocument(String heading) => _document([
      BlockPB(
        id: 'heading',
        ty: 'heading',
        data: jsonEncode({
          'level': 2,
          'delta': [
            {'insert': heading},
          ],
        }),
      ),
      BlockPB(
        id: 'body',
        ty: 'paragraph',
        data: jsonEncode({
          'delta': [
            {'insert': 'An '},
            {
              'insert': 'authored',
              'attributes': {'bold': true},
            },
            {'insert': ' paragraph'},
          ],
        }),
      ),
      BlockPB(
        id: 'list',
        ty: 'bulleted_list',
        data: jsonEncode({
          'delta': [
            {'insert': 'An actual list item'},
          ],
        }),
      ),
    ]);

FolderGalleryPreview _parsed(
  ViewPB view,
  String text, {
  String type = 'paragraph',
}) =>
    FolderGalleryPreviewParser.parse(
      view: view,
      item: WorkspaceExplorerItem.fromView(view),
      document: _document([
        BlockPB(
          id: 'text',
          ty: type,
          data: jsonEncode({
            'delta': [
              {'insert': text},
            ],
            if (type == 'code') 'language': 'dart',
          }),
        ),
      ]),
    );

FolderGalleryPreview _immediate(ViewPB view) =>
    FolderGalleryPreviewParser.withoutDocument(
      view: view,
      item: WorkspaceExplorerItem.fromView(view),
    ) ??
    _parsed(view, '');

_RecordingLoader _identityLoader() => _RecordingLoader(
      ({required view, required item}) async => _immediate(view),
    );

class _RecordingLoader extends FolderGalleryPreviewLoader {
  _RecordingLoader(this.read);

  final Future<FolderGalleryPreview> Function({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) read;
  final reads = <String, int>{};

  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) {
    reads.update(view.id, (count) => count + 1, ifAbsent: () => 1);
    return read(view: view, item: item);
  }
}

class _Documents extends DocumentService {
  _Documents(this.documents);
  final Map<String, DocumentDataPB> documents;
  final reads = <String>[];

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> getDocument({
    required String documentId,
  }) async {
    reads.add(documentId);
    final document = documents[documentId];
    if (document == null) {
      throw StateError('Unexpected document read: $documentId');
    }
    return FlowyResult.success(document);
  }
}

const _tableData = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.database,
  blocks: [],
  wordCount: 0,
  readingMinutes: 0,
  tags: [],
  fileTypeLabel: 'TABLE',
  database: FolderGalleryDatabaseSnapshot(
    columns: ['Name', 'Status'],
    rows: [
      ['Actual row', 'Ready'],
    ],
    totalRowCount: 1,
  ),
);

class _DatabasePreview extends FolderGalleryDatabasePreviewLoader {
  @override
  Future<FolderGalleryPreview> load({required ViewPB view}) async =>
      const FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.database,
        blocks: [],
        wordCount: 0,
        readingMinutes: 0,
        tags: [],
        fileTypeLabel: 'TABLE',
        database: FolderGalleryDatabaseSnapshot(
          columns: [],
          rows: [],
          totalRowCount: 0,
        ),
      );
}

class _Repository implements WorkspaceItemRepository {
  _Repository(this.children);

  List<ViewPB> children;
  Future<FlowyResult<List<ViewPB>, FlowyError>>? next;
  final reads = <String>[];
  final writes = <Symbol>[];

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) {
    reads.add(parentViewId);
    final result = next;
    next = null;
    return result ?? Future.value(FlowyResult.success(children));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    writes.add(invocation.memberName);
    throw StateError(
      'Unexpected repository operation: ${invocation.memberName}',
    );
  }
}

class _Translations extends AssetLoader {
  const _Translations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}
