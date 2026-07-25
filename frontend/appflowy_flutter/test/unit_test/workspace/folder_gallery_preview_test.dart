import 'dart:convert';

import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FolderGalleryPreviewParser', () {
    test('builds a bounded rich preview with document metadata', () {
      final view = ViewPB(
        id: 'document',
        name: 'Project brief',
        layout: ViewLayoutPB.Document,
        extra: jsonEncode({
          'tags': ['planning', '#launch'],
        }),
      );
      final document = _document([
        _block(
          'heading',
          'heading',
          delta: [
            {
              'insert': 'Launch plan',
              'attributes': {'bold': true},
            },
          ],
          attributes: {'level': 2},
        ),
        _block(
          'paragraph',
          'paragraph',
          delta: [
            {'insert': 'Ship the '},
            {
              'insert': 'gallery',
              'attributes': {'italic': true, 'inlineCode': true},
            },
            {'insert': ' experience #premium'},
          ],
        ),
        _block(
          'todo',
          'todo_list',
          delta: [
            {'insert': 'Polish interactions'},
          ],
          attributes: {'checked': true},
        ),
        _block(
          'code',
          'code',
          delta: [
            {'insert': 'void main() {}'},
          ],
          attributes: {'language': 'dart'},
        ),
        _block(
          'math',
          'math_equation',
          attributes: {'formula': 'E = mc^2'},
        ),
        for (var index = 0; index < 8; index++)
          _block(
            'paragraph-$index',
            'paragraph',
            delta: [
              {'insert': 'Additional preview line $index'},
            ],
          ),
      ]);

      final preview = FolderGalleryPreviewParser.parse(
        view: view,
        item: WorkspaceExplorerItem.fromView(view),
        document: document,
      );

      expect(
        preview.blocks,
        hasLength(FolderGalleryPreviewParser.maximumPreviewBlocks),
      );
      expect(preview.blocks.first.kind, FolderGalleryPreviewBlockKind.heading);
      expect(preview.blocks.first.level, 2);
      expect(preview.blocks[1].runs[1].italic, isTrue);
      expect(preview.blocks[1].runs[1].inlineCode, isTrue);
      expect(preview.blocks[2].checked, isTrue);
      expect(preview.blocks[3].language, 'dart');
      expect(preview.blocks[4].plainText, 'E = mc^2');
      expect(preview.wordCount, greaterThan(20));
      expect(preview.readingMinutes, 1);
      expect(preview.tags, containsAll(['planning', 'launch', 'premium']));
      expect(preview.fileTypeLabel, 'PAGE');
    });

    test('uses only a leading image as the document hero', () {
      final view = ViewPB(
        id: 'document',
        name: 'Visual notes',
        layout: ViewLayoutPB.Document,
      );
      final leadingImage = FolderGalleryPreviewParser.parse(
        view: view,
        item: WorkspaceExplorerItem.fromView(view),
        document: _document([
          _block(
            'image',
            'image',
            attributes: {'url': 'https://example.test/hero.png'},
          ),
          _block(
            'paragraph',
            'paragraph',
            delta: [
              {'insert': 'Recognizable document content'},
            ],
          ),
        ]),
      );
      final laterImage = FolderGalleryPreviewParser.parse(
        view: view,
        item: WorkspaceExplorerItem.fromView(view),
        document: _document([
          _block(
            'paragraph',
            'paragraph',
            delta: [
              {'insert': 'Content before the image'},
            ],
          ),
          _block(
            'image',
            'image',
            attributes: {'url': 'https://example.test/later.png'},
          ),
        ]),
      );

      expect(leadingImage.heroUrl, 'https://example.test/hero.png');
      expect(leadingImage.hasHero, isTrue);
      expect(laterImage.heroUrl, isNull);
    });

    test('classifies binary media without loading a document', () {
      final view = ViewPB(
        id: 'pdf',
        name: 'Research.pdf',
        layout: ViewLayoutPB.Document,
        extra: WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          mimeType: 'application/pdf',
          storageUrl: 'https://example.test/research.pdf',
          size: 4096,
        ).mergeIntoExtra(''),
      );

      final preview = FolderGalleryPreviewParser.withoutDocument(
        view: view,
        item: WorkspaceExplorerItem.fromView(view),
      );

      expect(preview, isNotNull);
      expect(preview!.kind, FolderGalleryPreviewKind.pdf);
      expect(preview.fileTypeLabel, 'PDF');
      expect(preview.heroUrl, 'https://example.test/research.pdf');
      expect(preview.unavailable, isFalse);
    });
  });

  group('FolderGalleryPreviewCache', () {
    test('reuses matching entries, invalidates stale stamps, and evicts LRU',
        () async {
      final loader = _CountingPreviewLoader();
      final cache = FolderGalleryPreviewCache(
        loader: loader,
        maximumEntries: 2,
      );
      final first = _documentView('first', 1);
      final second = _documentView('second', 1);
      final third = _documentView('third', 1);

      await _load(cache, first);
      await _load(cache, second);
      await _load(cache, first);
      expect(loader.loads['first'], 1);

      await _load(cache, third);
      await _load(cache, second);
      expect(loader.loads['second'], 2);

      final changed = _documentView('first', 2);
      await _load(cache, changed);
      expect(loader.loads['first'], 2);

      cache.invalidate('first');
      await _load(cache, changed);
      expect(loader.loads['first'], 3);
    });
  });
}

Future<FolderGalleryPreview> _load(
  FolderGalleryPreviewCache cache,
  ViewPB view,
) {
  return cache.previewFor(
    view: view,
    item: WorkspaceExplorerItem.fromView(view),
  );
}

ViewPB _documentView(String id, int lastEdited) => ViewPB(
      id: id,
      name: id,
      layout: ViewLayoutPB.Document,
      lastEdited: Int64(lastEdited),
    );

DocumentDataPB _document(List<BlockPB> children) {
  const pageId = 'page';
  const childrenId = 'page-children';
  return DocumentDataPB(
    pageId: pageId,
    blocks: {
      pageId: BlockPB(
        id: pageId,
        ty: 'page',
        childrenId: childrenId,
      ),
      for (final child in children) child.id: child,
    },
    meta: MetaPB(
      childrenMap: {
        childrenId: ChildrenPB(
          children: children.map((block) => block.id),
        ),
      },
    ),
  );
}

BlockPB _block(
  String id,
  String type, {
  List<Map<String, Object?>>? delta,
  Map<String, Object?> attributes = const {},
}) {
  return BlockPB(
    id: id,
    ty: type,
    data: jsonEncode({
      ...attributes,
      if (delta != null) 'delta': delta,
    }),
  );
}

class _CountingPreviewLoader extends FolderGalleryPreviewLoader {
  final Map<String, int> loads = {};

  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async {
    loads.update(view.id, (value) => value + 1, ifAbsent: () => 1);
    return const FolderGalleryPreview(
      kind: FolderGalleryPreviewKind.document,
      blocks: [],
      wordCount: 0,
      readingMinutes: 0,
      tags: [],
      fileTypeLabel: 'PAGE',
    );
  }
}
