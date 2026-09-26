import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/collection/collection_icon_button.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart'
    show sidebarViewGlyph;
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart' as db;
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _files = {
  'notes.TXT': 'file-text',
  'report.PDF': 'file-pdf',
  'letter.docx': 'file-doc',
  'sheet.xlsx': 'file-xls',
  'deck.pptx': 'file-ppt',
  'bundle.tar.gz': 'file-zip',
  'bundle.RAR': 'file-zip',
  'main.dart': 'file-code',
  'readme.md': 'file-markdown',
  'index.html': 'file-html',
  'config.json': 'file-json',
  'analysis.ipynb': 'file-notebook',
  'rows.csv': 'file-csv',
  'photo.png': 'image',
  'movie.mp4': 'film-strip',
  'song.flac': 'music-note',
  'unknown.bin': 'file',
};
const _collections = {
  CollectionKind.book: (name: 'book-open', vivid: 'book'),
  CollectionKind.album: (name: 'images', vivid: 'album'),
  CollectionKind.repository: (name: 'git-branch', vivid: 'repository'),
  CollectionKind.folder: (name: 'folder', vivid: 'folder'),
  CollectionKind.database: (name: 'database', vivid: 'database'),
  CollectionKind.bookmark: (name: 'link-simple', vivid: 'bookmark'),
  CollectionKind.email: (name: 'envelope-simple', vivid: 'mail'),
};
const _chatFace = ValueKey('folder-gallery-chat-identity');
const _identity = FolderGalleryPreview(
  kind: FolderGalleryPreviewKind.file,
  blocks: [],
  wordCount: 0,
  readingMinutes: 0,
  tags: [],
  fileTypeLabel: 'FILE',
);

void main() {
  setUpAll(prepareVividIconTestAssets);
  setUp(() {
    resetIconPacksForTesting();
    WorkspaceGlyphs.clearUnknownMappings();
  });

  test('file identities refine shared action glyphs without changing them', () {
    for (final entry in _files.entries) {
      expect(WorkspaceGlyphs.nameForFile(entry.key), entry.value);
      expect(WorkspaceGlyphs.vividNameFor(entry.value), isNotNull);
      expect(defaultIconSvg(entry.value), isNotNull);
    }
    expect(WorkspaceGlyphs.nameForIcon(Icons.table_chart_rounded), 'table');
    expect(WorkspaceGlyphs.nameForIcon(Icons.code_rounded), 'code');
    expect(WorkspaceGlyphs.nameForFile(null), 'file');
    expect(WorkspaceGlyphs.nameForFile(''), 'file');
    expect(WorkspaceGlyphs.nameForFile(r'C:\notes #1\a.b.XLSX'), 'file-xls');
    expect(
      WorkspaceGlyphs.nameForFile('https://example.invalid/report.PDF?q=.txt'),
      'file-pdf',
    );
    expect(
      WorkspaceGlyphs.nameForFile('file:///C:/notes%20here/a.MD'),
      'file-markdown',
    );
  });

  test('collection identities do not redefine shared action glyphs', () {
    expect(_collections.keys, unorderedEquals(CollectionKind.values));
    for (final kind in CollectionKind.values) {
      final expected = _collections[kind]!;
      expect(WorkspaceGlyphs.nameForCollection(kind), expected.name);
      expect(WorkspaceGlyph.collection(kind).name, expected.name);
      expect(sidebarCollectionIcon(kind).name, expected.name);
      expect(WorkspaceGlyphs.vividNameFor(expected.name), expected.vivid);
      expect(defaultIconSvg(expected.name), isNotNull);
      expect(vividIconSvg(expected.vivid), isNotNull);
    }
    for (final (kind, icon, action) in [
      (CollectionKind.repository, Icons.code_rounded, 'code'),
      (CollectionKind.folder, Icons.folder_copy_rounded, 'copy'),
      (CollectionKind.bookmark, Icons.bookmarks_rounded, 'bookmarks'),
    ]) {
      expect(CollectionRegistry.typeFor(kind).icon, icon);
      expect(WorkspaceGlyphs.nameForIcon(icon), action);
    }
    _expectUtilityArtwork('code');
    expect(vividIconSvg('utility-code'), isNot(vividIconSvg('repository')));
    expect(WorkspaceGlyphs.unknownMappings, isEmpty);
  });

  test('line-number states have distinct outlines; numbered lists stay named',
      () {
    expect(
      WorkspaceGlyphs.nameForIcon(Icons.format_list_numbered_rounded),
      'line-numbers',
    );
    expect(
      WorkspaceGlyphs.nameForIcon(Icons.subject_rounded),
      'line-numbers-off',
    );
    expect(
      defaultIconSvg('line-numbers'),
      isNot(defaultIconSvg('line-numbers-off')),
    );
    expect(
      WorkspaceGlyphs.nameForSvg(FlowySvgs.slash_menu_icon_numbered_list_s),
      'numbered-list',
    );
    for (final name in ['line-numbers', 'line-numbers-off', 'numbered-list']) {
      _expectUtilityArtwork(name);
    }
    expect(
      vividIconSvg('utility-line-numbers'),
      isNot(vividIconSvg('utility-line-numbers-off')),
    );
  });

  for (final appearance in vividIconTestAppearances) {
    for (final style in DefaultIconStyle.values) {
      testWidgets('$appearance/$style media labels retain authoritative types',
          (tester) async {
        final styles = ValueNotifier(style);
        try {
          for (final (name, type, expected) in [
            ('Sheet.xlsx', db.MediaFileTypePB.Other, 'file-xls'),
            ('Source.py', db.MediaFileTypePB.Text, 'file-code'),
            ('Misleading.png', db.MediaFileTypePB.Archive, 'file-zip'),
            ('Misleading.png', db.MediaFileTypePB.Audio, 'music-note'),
            ('Misleading.png', db.MediaFileTypePB.Document, 'file-text'),
            ('Web.html', db.MediaFileTypePB.Link, 'link-simple'),
          ]) {
            final file = db.MediaFilePB(
              id: 'synthetic',
              name: name,
              url: 'https://example.invalid/download',
              fileType: type,
            )..freeze();
            final bytes = file.writeToBuffer();
            await tester.pumpWidget(
              _app(
                appearance,
                styles,
                SizedBox(
                  width: 80,
                  child: IntrinsicHeight(child: MediaFileLabel(file: file)),
                ),
                scale: 2,
              ),
            );
            await settleVividIconPictures(tester);
            expect(file.displayGlyphName, expected);
            _expectArtwork(
              tester,
              find.byType(WorkspaceGlyph),
              expected,
              style,
            );
            expect(find.byType(Image), findsNothing);
            expect(file.writeToBuffer(), bytes);
            expect(tester.takeException(), isNull);
          }
        } finally {
          await tester.pumpWidget(const SizedBox());
          styles.dispose();
        }
      });

      testWidgets(
          '$appearance/$style file defaults agree in folder and archive',
          (tester) async {
        final styles = ValueNotifier(style);
        try {
          for (final entry in _files.entries) {
            final view = _file(entry.key);
            final archive = ViewPB.fromBuffer(view.writeToBuffer())
              ..id = 'archive-fixture::${entry.key}';
            await tester.pumpWidget(
              _app(
                appearance,
                styles,
                Wrap(
                  children: [
                    WorkspaceItemIcon.fromView(
                      key: const ValueKey('row'),
                      view: view,
                      showThumbnail: false,
                    ),
                    _thumbnail(view, key: const ValueKey('folder')),
                    _thumbnail(archive, key: const ValueKey('archive')),
                  ],
                ),
              ),
            );
            await settleVividIconPictures(tester);
            for (final slot in ['row', 'folder', 'archive']) {
              final glyph = find.descendant(
                of: find.byKey(ValueKey(slot)),
                matching: find.byType(WorkspaceGlyph),
              );
              _expectArtwork(tester, glyph, entry.value, style);
            }
            expect(find.byType(Image), findsNothing);
            expect(WorkspaceGlyphs.unknownMappings, isEmpty);
            expect(tester.takeException(), isNull);
          }
        } finally {
          await tester.pumpWidget(const SizedBox());
          styles.dispose();
        }
      });

      testWidgets('$appearance/$style collection defaults use exact identities',
          (tester) async {
        final styles = ValueNotifier(style);
        var writes = 0;
        try {
          for (final kind in CollectionKind.values) {
            final view = _collection(kind)..freeze();
            final item = WorkspaceExplorerItem.fromView(view);
            final expected = _collections[kind]!;
            final bytes = view.writeToBuffer();
            await tester.pumpWidget(
              _app(
                appearance,
                styles,
                Wrap(
                  children: [
                    WorkspaceItemIcon.fromView(
                      key: const ValueKey('row'),
                      view: view,
                      size: 56,
                      showThumbnail: false,
                    ),
                    WorkspaceItemIcon(
                      key: const ValueKey('item-only'),
                      item: item,
                      size: 56,
                      showThumbnail: false,
                    ),
                    _thumbnail(
                      view,
                      key: const ValueKey('gallery'),
                      preview: SynchronousFuture(
                        FolderGalleryPreviewParser.withoutDocument(
                          view: view,
                          item: item,
                        )!,
                      ),
                    ),
                    SizedBox(
                      key: const ValueKey('gallery-item-only'),
                      width: 120,
                      height: 102,
                      child: FolderGalleryCollectionArtwork(item: item),
                    ),
                    CollectionIconButton(
                      key: const ValueKey('header'),
                      view: view,
                      iconSize: 56,
                      onViewChanged: (_) => writes++,
                    ),
                    Builder(
                      key: const ValueKey('sidebar'),
                      builder: (context) => sidebarViewGlyph(context, view),
                    ),
                  ],
                ),
              ),
            );
            await settleVividIconPictures(tester);
            expect(
              WorkspaceGlyphs.vividNameFor(expected.name),
              expected.vivid,
            );
            for (final slot in [
              'row',
              'item-only',
              'gallery',
              'gallery-item-only',
              'header',
              'sidebar',
            ]) {
              final glyph = find.descendant(
                of: find.byKey(ValueKey(slot)),
                matching: find.byType(WorkspaceGlyph),
              );
              _expectArtwork(
                tester,
                glyph,
                expected.name,
                style,
                ink: slot == 'header'
                    ? CollectionPalette.of(tester.element(glyph), kind).accent
                    : null,
              );
            }
            expect(writes, 0);
            expect(view.writeToBuffer(), bytes);
            expect(WorkspaceGlyphs.unknownMappings, isEmpty);
            expect(tester.takeException(), isNull);
          }
        } finally {
          await tester.pumpWidget(const SizedBox());
          styles.dispose();
        }
      });

      testWidgets(
          '$appearance/$style Chat fits tiny scaled thumbnails honestly',
          (tester) async {
        final styles = ValueNotifier(style);
        final semantics = tester.ensureSemantics();
        final view = _chat();
        final pending = Completer<FolderGalleryPreview>();
        try {
          for (final size in [const Size(280, 180), const Size(48, 32)]) {
            await tester.pumpWidget(
              _app(
                appearance,
                styles,
                _thumbnail(view, size: size, preview: pending.future),
                scale: 2,
              ),
            );
            await settleVividIconPictures(tester);
            expect(find.byKey(_chatFace), findsOneWidget);
            _expectArtwork(
              tester,
              find.byType(WorkspaceGlyph),
              'ai-chat',
              style,
            );
            expect(find.byType(FolderGalleryRichTextPreview), findsNothing);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(
              find.byKey(const ValueKey('folder-gallery-child-count')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('folder-gallery-database-grid')),
              findsNothing,
            );
            final data =
                tester.getSemantics(find.byKey(_chatFace)).getSemanticsData();
            expect(data.label, 'AI Chat');
            expect(data.hasFlag(ui.SemanticsFlag.isImage), isTrue);
            expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
            final glyph =
                tester.renderObject<RenderBox>(find.byType(WorkspaceGlyph));
            final painted = MatrixUtils.transformRect(
              glyph.getTransformTo(null),
              Offset.zero & glyph.size,
            );
            final bounds =
                tester.getRect(find.byType(FolderGalleryPreviewThumbnail));
            expect(bounds.inflate(.01).contains(painted.topLeft), isTrue);
            expect(bounds.inflate(.01).contains(painted.bottomRight), isTrue);
            expect(tester.takeException(), isNull);
          }
          // A stale non-chat result cannot relabel it.
          pending.complete(_identity);
          await tester.pump();
          expect(find.byKey(_chatFace), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox());
          semantics.dispose();
          styles.dispose();
        }
      });
    }

    testWidgets('$appearance saved collection icons outrank typed defaults',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      var writes = 0;
      try {
        for (final kind in CollectionKind.values) {
          final view = _collection(kind)
            ..icon = IconsData(vividIconTestGroup, 'rocket', '4278255360')
                .toEmojiIconData()
                .toViewIcon()
            ..freeze();
          final bytes = view.writeToBuffer();
          await tester.pumpWidget(
            _app(
              appearance,
              styles,
              Wrap(
                children: [
                  _thumbnail(view),
                  CollectionIconButton(
                    view: view,
                    onViewChanged: (_) => writes++,
                  ),
                ],
              ),
            ),
          );
          await settleVividIconPictures(tester);
          final saved = find.byType(RawEmojiIconWidget);
          expect(saved, findsNWidgets(2));
          final states = tester.stateList(saved).toList();
          for (final style in DefaultIconStyle.values) {
            styles.value = style;
            await settleVividIconPictures(tester);
            expect(tester.stateList(saved), orderedEquals(states));
            expect(find.byType(WorkspaceGlyph), findsNothing);
            expect(find.byType(FlowySvg), findsNWidgets(2));
            for (final svg in tester.widgetList<FlowySvg>(
              find.byType(FlowySvg),
            )) {
              expect(svg.svgString, vividIconSvg('rocket'));
              expect(svg.color, isNull);
              expect(svg.blendMode, isNull);
            }
            expect(writes, 0);
            expect(view.writeToBuffer(), bytes);
            expect(tester.takeException(), isNull);
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });

    testWidgets('$appearance saved Chat cover/icon outrank every default style',
        (tester) async {
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final view = _chat()
        ..icon = IconsData('appflowy_vivid_essentials', 'book', '4278255360')
            .toEmojiIconData()
            .toViewIcon();
      final bytes = view.writeToBuffer();
      try {
        await tester.pumpWidget(_app(appearance, styles, _thumbnail(view)));
        await settleVividIconPictures(tester);
        final savedState = tester.state(find.byType(RawEmojiIconWidget));
        for (final style in DefaultIconStyle.values) {
          styles.value = style;
          await settleVividIconPictures(tester);
          expect(
            tester.state(find.byType(RawEmojiIconWidget)),
            same(savedState),
          );
          expect(find.byType(WorkspaceGlyph), findsNothing);
          final svg = tester.widget<FlowySvg>(find.byType(FlowySvg));
          expect(svg.svgString, vividIconSvg('book'));
          expect(svg.color, isNull);
          expect(svg.blendMode, isNull);
        }
        final covered = ViewPB.fromBuffer(bytes)
          ..extra = ViewCoverCodec.mergeCover(
            view.extra,
            const PageStyleCover(
              type: PageStyleCoverImageType.pureColor,
              value: '#B8C6AF',
            ),
          );
        await tester.pumpWidget(_app(appearance, styles, _thumbnail(covered)));
        await tester.pumpAndSettle();
        expect(find.byType(ViewCoverImage), findsOneWidget);
        expect(find.byKey(_chatFace), findsNothing);
        final content = ViewPB.fromBuffer(covered.writeToBuffer())
          ..extra = ViewPreviewModeCodec.merge(
            covered.extra,
            ViewPreviewMode.content,
          );
        await tester.pumpWidget(_app(appearance, styles, _thumbnail(content)));
        await settleVividIconPictures(tester);
        expect(find.byType(ViewCoverImage), findsNothing);
        expect(find.byKey(_chatFace), findsOneWidget);
        expect(find.byType(RawEmojiIconWidget), findsOneWidget);
        expect(view.writeToBuffer(), bytes);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });
  }

  testWidgets(
      'Chat card activates once per input and preserves its rename draft',
      (tester) async {
    final styles = ValueNotifier(DefaultIconStyle.monochrome);
    final view = _chat();
    final pending = Completer<FolderGalleryPreview>();
    var editing = false;
    var opened = 0;
    var writes = 0;
    late StateSetter rebuild;
    try {
      await tester.pumpWidget(
        _app(
          'paper',
          styles,
          StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              return SizedBox(
                width: 220,
                height: 320,
                child: FolderGalleryCard(
                  item: WorkspaceExplorerItem.fromView(view),
                  view: view,
                  preview: pending.future,
                  userProfile: null,
                  selected: false,
                  editing: editing,
                  onTap: () => opened++,
                  onRename: () => rebuild(() => editing = true),
                  onRenameSubmitted: (_) async {
                    writes++;
                    return true;
                  },
                  onRenameCancelled: () => rebuild(() => editing = false),
                  onMore: (_) {},
                  onContextMenu: (_) {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cardState = tester.state(find.byType(FolderGalleryCard));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(opened, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      final editor = find.byKey(const ValueKey('workspace-inline-name-editor'));
      await tester.enterText(editor, 'Unfinished AI chat name');
      final field = tester.widget<EditableText>(editor);
      final state = tester.state(editor);
      field.controller.selection =
          const TextSelection(baseOffset: 2, extentOffset: 8);
      final draft = field.controller.value;
      styles.value = DefaultIconStyle.vivid;
      pending.complete(_identity);
      await tester.pumpAndSettle();
      expect(tester.state(editor), same(state));
      expect(field.controller.value, draft);
      expect(field.focusNode.hasFocus, isTrue);
      expect(tester.state(find.byType(FolderGalleryCard)), same(cardState));
      expect(find.byKey(_chatFace), findsOneWidget);
      expect(writes, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final face = find.byKey(_chatFace);
      expect(
        find.ancestor(
          of: face,
          matching: find.byWidgetPredicate(
            (widget) => widget is IgnorePointer && widget.ignoring,
          ),
        ),
        findsOneWidget,
      );
      expect(opened, 1);
      // The passive preview is deliberately excluded from hit testing. Tap
      // its measured position to exercise the owning card's onTap instead.
      await tester.tapAt(
        tester.getCenter(face),
        kind: PointerDeviceKind.mouse,
      );
      expect(opened, 2);
      await tester.pumpAndSettle();
      expect(opened, 2);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      styles.dispose();
    }
  });
}

ViewPB _collection(CollectionKind kind) => ViewPB(
      id: 'collection-${kind.name}',
      name: kind.name,
      layout: ViewLayoutPB.Document,
      extra: CollectionMetadata.newExtra(kind),
    );

ViewPB _chat() => ViewPB(
      id: 'chat',
      name: 'Research conversation',
      layout: ViewLayoutPB.Chat,
    );

ViewPB _file(String name) => ViewPB(
      id: 'file-$name',
      name: name,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
      ).mergeIntoExtra(''),
    );

Widget _thumbnail(
  ViewPB view, {
  Key? key,
  Size size = const Size(120, 102),
  Future<FolderGalleryPreview>? preview,
}) =>
    SizedBox(
      key: key,
      width: size.width,
      height: size.height,
      child: FolderGalleryPreviewThumbnail(
        item: WorkspaceExplorerItem.fromView(view),
        view: view,
        preview: preview ?? SynchronousFuture(_identity),
        userProfile: null,
        height: size.height,
      ),
    );

Widget _app(
  String appearance,
  ValueNotifier<DefaultIconStyle> styles,
  Widget child, {
  double scale = 1,
}) =>
    vividIconTestApp(
      appearance,
      DefaultIconStyleScope(
        styles: styles,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: child,
        ),
      ),
    );

void _expectUtilityArtwork(String name) {
  expect(WorkspaceGlyphs.vividNameFor(name), 'utility-$name');
  final outline = defaultIconSvg(name)!;
  final artwork = vividIconSvg('utility-$name')!;
  expect(artwork, contains('viewBox="0 0 32 32"'));
  expect(artwork, contains('<linearGradient id="utility"'));
  expect(
    artwork,
    contains(
      outline
          .substring(outline.indexOf('>') + 1, outline.lastIndexOf('</svg>'))
          .replaceAll('currentColor', 'url(#utility)'),
    ),
  );
}

void _expectArtwork(
  WidgetTester tester,
  Finder glyph,
  String name,
  DefaultIconStyle style, {
  Color? ink,
}) {
  expect(glyph, findsOneWidget);
  expect(tester.widget<WorkspaceGlyph>(glyph).name, name);
  final picture = tester.widget<SvgPicture>(
    find.descendant(of: glyph, matching: find.byType(SvgPicture)),
  );
  final vivid = WorkspaceGlyphs.vividNameFor(name)!;
  final source = style == DefaultIconStyle.vivid
      ? vividIconSvg(vivid)!
      : defaultIconSvg(name)!;
  final loader = picture.bytesLoader as SvgStringLoader;
  expect(
    loader,
    SvgStringLoader(
      source,
      theme: loader.theme,
      colorMapper: loader.colorMapper,
    ),
  );
  expect(
    picture.colorFilter,
    style == DefaultIconStyle.vivid
        ? null
        : ColorFilter.mode(
            ink ?? workspaceGlyphInk(tester.element(glyph)),
            BlendMode.srcIn,
          ),
  );
}
