import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gallery identity classification without native reads', () {
    test('decoded nested folders never read their documents or children',
        () async {
      final documents = _DocumentProbe();
      final loader = FolderGalleryPreviewLoader(documentService: documents);
      for (final id in ['root::nested%2Fone', 'root::nested%2Ftwo']) {
        final encoded = ViewPB(
          id: id,
          parentViewId: 'root',
          name: 'Nested folder',
          layout: ViewLayoutPB.Document,
          extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
          childViews: [ViewPB(id: '$id::unread-page')],
        );
        final view = ViewPB.fromBuffer(encoded.writeToBuffer());
        final item = WorkspaceExplorerItem.fromView(view);
        final preview = await loader.load(view: view, item: item);
        expect(item.id, id);
        expect(item.isFolder, isTrue);
        expect(item.hasChildren, isTrue);
        expect(preview.kind, FolderGalleryPreviewKind.folder);
        expect(preview.fileTypeLabel, 'FOLDER');
        expect(preview.blocks, isEmpty);
        expect(preview.hasHero, isFalse);
        expect(preview.unavailable, isFalse);
      }
      expect(documents.requested, isEmpty);
    });

    test('unpreviewable stored files need neither a document nor a file read',
        () async {
      final documents = _DocumentProbe();
      final loader = FolderGalleryPreviewLoader(documentService: documents);
      for (final name in [
        'Blank.docx',
        'Blank.xlsx',
        'Blank.pptx',
        'Other.bin',
      ]) {
        final preview = await _load(
          loader,
          _storedFile(name, 'not-a-real-directory/$name'),
        );
        expect(preview.kind, FolderGalleryPreviewKind.file);
        expect(preview.hasHero, isFalse);
        expect(preview.blocks, isEmpty);
        expect(preview.unavailable, isFalse);
      }
      expect(documents.requested, isEmpty);
    });

    test('a page stays pending until its actual document read completes',
        () async {
      final response = Completer<FlowyResult<DocumentDataPB, FlowyError>>();
      final documents = _DocumentProbe((_) => response.future);
      final loader = FolderGalleryPreviewLoader(documentService: documents);
      var completed = false;
      final pending = _load(loader, _page()).then((preview) {
        completed = true;
        return preview;
      });
      await Future<void>.value();
      expect(completed, isFalse);
      response.complete(FlowyResult.success(_document([])));
      final preview = await pending;
      expect(completed, isTrue);
      expect(preview.unavailable, isFalse);
      expect(preview.wordCount, 0);
      expect(documents.requested, ['page']);
    });

    for (final throws in [false, true]) {
      test('${throws ? 'thrown' : 'backend'} failures are not empty pages',
          () async {
        final documents = _DocumentProbe((_) async {
          if (throws) throw StateError('synthetic read failure');
          return FlowyResult.failure(FlowyError(msg: 'synthetic read failure'));
        });
        final preview = await _load(
          FolderGalleryPreviewLoader(documentService: documents),
          _page(),
        );
        expect(preview.unavailable, isTrue);
        expect(preview.blocks, isEmpty);
        expect(preview.wordCount, 0);
        expect(preview.readingMinutes, 0);
      });
    }

    test('a retry invalidates only the failed cached preview', () async {
      var fail = true;
      final documents = _DocumentProbe((_) async {
        return fail
            ? FlowyResult.failure(FlowyError(msg: 'synthetic read failure'))
            : FlowyResult.success(_document([_text('Recovered content')]));
      });
      final cache = FolderGalleryPreviewCache(
        loader: FolderGalleryPreviewLoader(documentService: documents),
      );
      final view = _page();
      final item = WorkspaceExplorerItem.fromView(view);
      final first = cache.previewFor(view: view, item: item);
      expect((await first).unavailable, isTrue);
      expect(cache.previewFor(view: view, item: item), same(first));
      fail = false;
      cache.invalidate(view.id);
      final next = cache.previewFor(view: view, item: item);
      expect(next, isNot(same(first)));
      expect((await next).blocks.single.plainText, 'Recovered content');
      expect(documents.requested, ['page', 'page']);
    });

    test('failed database reads retain their type and no invented rows',
        () async {
      final documents = _DocumentProbe();
      final preview = await _load(
        FolderGalleryPreviewLoader(
          documentService: documents,
          databasePreviewLoader: _FailedDatabasePreviewLoader(),
        ),
        ViewPB(id: 'table', name: 'Table', layout: ViewLayoutPB.Grid),
      );
      expect(preview.kind, FolderGalleryPreviewKind.database);
      expect(preview.fileTypeLabel, 'TABLE');
      expect(preview.database, isNull);
      expect(preview.unavailable, isTrue);
      expect(documents.requested, isEmpty);
    });
  });

  group('complete document content versus incomplete payloads', () {
    test(
        'a titled but truly empty page has no invented content or reading time',
        () {
      for (final document in [
        _document([]),
        _document([_text('  \n\t')]),
      ]) {
        final preview = _parse(document);
        expect(preview.unavailable, isFalse);
        expect(preview.blocks, isEmpty);
        expect(preview.wordCount, 0);
        expect(preview.readingMinutes, 0);
        expect(preview.hasHero, isFalse);
        expect(preview.note, FolderGalleryPreviewNote.empty);
      }
    });

    test('a page holding more than empty text is never called empty', () {
      for (final block in [
        BlockPB(id: 'rule', ty: 'divider', data: '{}'),
        BlockPB(id: 'picture', ty: 'image', data: '{}'),
        BlockPB(id: 'grid', ty: 'grid', data: '{}'),
        _text('Words'),
      ]) {
        expect(_parse(_document([block])).note, isNull, reason: block.ty);
      }
    });

    test('populated prose and a leading image retain their real preview', () {
      final preview = _parse(
        _document([
          BlockPB(
            id: 'image',
            ty: 'image',
            data: jsonEncode({'url': 'https://example.test/real.png'}),
          ),
          _text('Actual authored words', bold: true),
        ]),
      );
      expect(preview.unavailable, isFalse);
      expect(preview.heroUrl, 'https://example.test/real.png');
      expect(preview.blocks.single.plainText, 'Actual authored words');
      expect(preview.blocks.single.runs.single.bold, isTrue);
      expect(preview.wordCount, 3);
      expect(preview.readingMinutes, 1);
    });

    test('missing root, listing and referenced blocks are unavailable', () {
      final missingListing = _document([])..meta.childrenMap.clear();
      final missingBlock = _document([_text('Unloaded')])
        ..blocks.remove('text');
      for (final document in [
        DocumentDataPB(),
        missingListing,
        missingBlock,
      ]) {
        expect(_parse(document).unavailable, isTrue);
      }
    });

    test('malformed blocks and deltas never appear as raw preview prose', () {
      for (final data in [
        '{unfinished',
        '[]',
        jsonEncode({'delta': 'unread serialized state'}),
        jsonEncode({
          'delta': {'unexpected': 'not ops'},
        }),
        jsonEncode({
          'delta': [42],
        }),
      ]) {
        final preview = _parse(
          _document([BlockPB(id: 'text', ty: 'paragraph', data: data)]),
        );
        expect(preview.unavailable, isTrue);
        expect(preview.blocks, isEmpty);
        expect(preview.wordCount, 0);
      }
    });

    test('unloaded external text is not treated as an empty paragraph', () {
      final document = _document([
        BlockPB(
          id: 'text',
          ty: 'paragraph',
          data: '{}',
          externalId: 'external-text',
          externalType: 'text',
        ),
      ]);
      expect(_parse(document).unavailable, isTrue);
      document.meta.textMap['external-text'] = jsonEncode([
        {'insert': 'External content'},
      ]);
      final loaded = _parse(document);
      expect(loaded.unavailable, isFalse);
      expect(loaded.blocks.single.plainText, 'External content');
    });

    test('a valid inline delta still recovers malformed external text', () {
      final block = _text('Inline content')
        ..externalId = 'external-text'
        ..externalType = 'text';
      final document = _document([block]);
      document.meta.textMap['external-text'] = '{unfinished';
      final preview = _parse(document);
      expect(preview.unavailable, isFalse);
      expect(preview.blocks.single.plainText, 'Inline content');
    });
  });

  group('stored text file reads', () {
    late Directory temporary;
    late _DocumentProbe documents;
    late FolderGalleryPreviewLoader loader;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('gallery_identity_');
      documents = _DocumentProbe();
      loader = FolderGalleryPreviewLoader(documentService: documents);
    });

    tearDown(() async {
      expect(documents.requested, isEmpty);
      await temporary.delete(recursive: true);
    });

    for (final name in ['Empty.txt', 'Empty.md', 'Empty.dart']) {
      test('$name reads empty bytes without an inline hero', () async {
        final file = await File('${temporary.path}/$name').writeAsString('');
        final preview = await _load(loader, _storedFile(name, file.path));
        expect(preview.unavailable, isFalse);
        expect(preview.blocks, isEmpty);
        expect(preview.wordCount, 0);
        expect(preview.readingMinutes, 0);
        expect(preview.hasHero, isFalse);
        expect(preview.note, FolderGalleryPreviewNote.empty);
      });
    }

    test('file URIs preserve spaces and literal hash characters', () async {
      const name = 'Real # notes.txt';
      final file = await File('${temporary.path}/$name')
          .writeAsString('Actual file content');
      final preview =
          await _load(loader, _storedFile(name, file.uri.toString()));
      expect(preview.unavailable, isFalse);
      expect(preview.blocks.single.plainText, 'Actual file content');
      expect(preview.hasHero, isFalse);
    });

    test('missing paths and unreadable remote text are not empty files',
        () async {
      final remote = <(Uri, int)>[];
      final reader = FolderGalleryPreviewLoader(
        documentService: documents,
        remoteReader: (uri, maxBytes) async {
          remote.add((uri, maxBytes));
          return null;
        },
      );
      for (final path in [
        '',
        'https://example.test/not-downloaded.txt',
      ]) {
        final preview = await _load(reader, _storedFile('Unread.txt', path));
        expect(preview.unavailable, isTrue);
        expect(preview.note, isNull);
        expect(preview.blocks, isEmpty);
        expect(preview.hasHero, isFalse);
      }
      // A file whose bytes are not on this device says so: it is neither
      // empty nor something a retry could bring back.
      final missing = await _load(
        reader,
        _storedFile('Unread.txt', '${temporary.path}/missing.txt'),
      );
      expect(missing.unavailable, isFalse);
      expect(missing.note, FolderGalleryPreviewNote.missing);
      expect(missing.blocks, isEmpty);
      expect(missing.hasHero, isFalse);
      // Only the remote file is asked for, and only its opening bytes.
      expect(
        remote,
        [(Uri.parse('https://example.test/not-downloaded.txt'), 8193)],
      );
    });

    test('remote text previews from its opening bytes, like a local file',
        () async {
      final asked = <Uri>[];
      final reader = FolderGalleryPreviewLoader(
        documentService: documents,
        remoteReader: (uri, maxBytes) async {
          asked.add(uri);
          final source = switch (uri.path) {
            '/blob/README.md' => '# Project\n\nA **real** readme',
            '/blob/main.py' => 'print("hello")\n',
            '/blob/blank.txt' => '',
            _ => '${' ' * (8 * 1024)}Content beyond the preview limit',
          };
          return utf8.encode(source).take(maxBytes).toList();
        },
      );
      final readme = await _load(
        reader,
        _storedFile('README.md', 'http://localhost:8000/blob/README.md'),
      );
      expect(readme.unavailable, isFalse);
      expect(readme.kind, FolderGalleryPreviewKind.document);
      expect(readme.blocks.first.kind, FolderGalleryPreviewBlockKind.heading);
      expect(readme.blocks.first.plainText, 'Project');
      expect(readme.blocks.last.runs.any((run) => run.bold), isTrue);

      final code = await _load(
        reader,
        _storedFile('main.py', 'https://files.example.test/blob/main.py'),
      );
      expect(code.unavailable, isFalse);
      expect(code.kind, FolderGalleryPreviewKind.code);
      expect(code.language, 'py');
      expect(code.blocks.single.plainText, 'print("hello")');

      final blank = await _load(
        reader,
        _storedFile('blank.txt', 'https://files.example.test/blob/blank.txt'),
      );
      expect(blank.unavailable, isFalse);
      expect(blank.blocks, isEmpty);
      expect(blank.note, FolderGalleryPreviewNote.empty);

      // A blank opening is not proof that the rest of the file is blank.
      final long = await _load(
        reader,
        _storedFile('long.txt', 'https://files.example.test/blob/long.txt'),
      );
      expect(long.unavailable, isTrue);
      expect(asked, hasLength(4));
    });

    test('a whitespace-only bounded prefix is not proof of an empty file',
        () async {
      final file = await File('${temporary.path}/long.txt').writeAsString(
        '${' ' * (8 * 1024)}Content beyond the preview limit',
      );
      final preview = await _load(loader, _storedFile('long.txt', file.path));
      expect(preview.unavailable, isTrue);
      expect(preview.blocks, isEmpty);
    });

    test('markdown formatting and code content survive the fallback change',
        () async {
      final markdown = await File('${temporary.path}/notes.md')
          .writeAsString('# Heading\n\nActual **bold** content');
      final code = await File('${temporary.path}/main.dart')
          .writeAsString('void main() {}');
      final prose = await _load(loader, _storedFile('notes.md', markdown.path));
      final source = await _load(loader, _storedFile('main.dart', code.path));
      expect(prose.blocks.first.kind, FolderGalleryPreviewBlockKind.heading);
      expect(prose.blocks.last.runs.any((run) => run.bold), isTrue);
      expect(source.kind, FolderGalleryPreviewKind.code);
      expect(source.blocks.single.plainText, 'void main() {}');
      expect(source.language, 'dart');
      expect(prose.unavailable || source.unavailable, isFalse);
    });
  });
}

ViewPB _page() => ViewPB(
      id: 'page',
      name: 'A title is not document content',
      layout: ViewLayoutPB.Document,
    );

ViewPB _storedFile(String name, String path) => ViewPB(
      id: 'synthetic::$name',
      name: name,
      layout: ViewLayoutPB.Document,
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: path,
        // A stored size can be stale; actual reads still decide emptiness.
        size: 0,
      ).mergeIntoExtra(''),
    );

Future<FolderGalleryPreview> _load(
  FolderGalleryPreviewLoader loader,
  ViewPB view,
) =>
    loader.load(view: view, item: WorkspaceExplorerItem.fromView(view));

FolderGalleryPreview _parse(DocumentDataPB document) {
  final view = _page();
  return FolderGalleryPreviewParser.parse(
    view: view,
    item: WorkspaceExplorerItem.fromView(view),
    document: document,
  );
}

DocumentDataPB _document(List<BlockPB> children) => DocumentDataPB(
      pageId: 'root',
      blocks: {
        'root': BlockPB(id: 'root', ty: 'page', childrenId: 'root-children'),
        for (final child in children) child.id: child,
      },
      meta: MetaPB(
        childrenMap: {
          'root-children':
              ChildrenPB(children: children.map((child) => child.id)),
        },
      ),
    );

BlockPB _text(String text, {bool bold = false}) => BlockPB(
      id: 'text',
      ty: 'paragraph',
      data: jsonEncode({
        'delta': [
          {
            'insert': text,
            if (bold) 'attributes': {'bold': true},
          },
        ],
      }),
    );

class _DocumentProbe extends DocumentService {
  _DocumentProbe([this.read]);

  final Future<FlowyResult<DocumentDataPB, FlowyError>> Function(String)? read;
  final requested = <String>[];

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> getDocument({
    required String documentId,
  }) async {
    requested.add(documentId);
    final handler = read;
    if (handler == null) throw StateError('Unexpected document read');
    return handler(documentId);
  }
}

class _FailedDatabasePreviewLoader extends FolderGalleryDatabasePreviewLoader {
  @override
  Future<FolderGalleryPreview> load({required ViewPB view}) async =>
      throw StateError('synthetic cell read failure');
}
