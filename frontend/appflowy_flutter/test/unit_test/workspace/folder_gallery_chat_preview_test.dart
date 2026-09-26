import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Chat is identified before either database or document preview IO',
      () async {
    final documents = _Documents();
    final databases = _Databases();
    final loader = FolderGalleryPreviewLoader(
      documentService: documents,
      databasePreviewLoader: databases,
    );
    final view = ViewPB.fromBuffer(_chat().writeToBuffer());
    final bytes = view.writeToBuffer();
    // Pin the real coarse model which caused the bug, rather than inventing a
    // ProviderNodeKind or changing a fixture to make the reader look correct.
    expect(
      WorkspaceExplorerItem.fromView(view).kind,
      WorkspaceExplorerItemKind.database,
    );
    for (final kind in WorkspaceExplorerItemKind.values) {
      final item = WorkspaceExplorerItem(
        id: view.id,
        parentId: view.parentViewId,
        name: view.name,
        kind: kind,
        metadata: null,
        hasChildren: false,
        lastEdited: null,
      );
      _expectChat(await loader.load(view: view, item: item));
      _expectChat(
        FolderGalleryPreviewParser.withoutDocument(view: view, item: item)!,
      );
      _expectChat(
        FolderGalleryPreviewParser.unavailable(view: view, item: item),
      );
      _expectChat(
        FolderGalleryPreviewParser.parse(
          view: view,
          item: item,
          document: DocumentDataPB(pageId: 'not-a-chat-transcript'),
        ),
      );
    }
    expect(documents.reads, isEmpty);
    expect(databases.reads, isEmpty);
    expect(view.writeToBuffer(), bytes);
  });

  test('cached table preview cannot survive a layout change to Chat', () async {
    final documents = _Documents();
    final databases = _Databases();
    final cache = FolderGalleryPreviewCache(
      loader: FolderGalleryPreviewLoader(
        documentService: documents,
        databasePreviewLoader: databases,
      ),
    );
    final table = _chat()..layout = ViewLayoutPB.Grid;
    final tablePreview = cache.previewFor(
      view: table,
      item: WorkspaceExplorerItem.fromView(table),
    );
    expect((await tablePreview).kind, FolderGalleryPreviewKind.database);
    final chat = ViewPB.fromBuffer(table.writeToBuffer())
      ..layout = ViewLayoutPB.Chat;
    final chatPreview = cache.previewFor(
      view: chat,
      item: WorkspaceExplorerItem.fromView(chat),
    );
    expect(chatPreview, isNot(same(tablePreview)));
    _expectChat(await chatPreview);
    expect(
      cache.previewFor(view: chat, item: WorkspaceExplorerItem.fromView(chat)),
      same(chatPreview),
    );
    expect(databases.reads, [chat.id]);
    expect(documents.reads, isEmpty);
    cache.clear();
  });
}

ViewPB _chat() => ViewPB(
      id: 'synthetic-chat',
      name: 'Research conversation',
      layout: ViewLayoutPB.Chat,
      icon: EmojiIconData.emoji('🌿').toViewIcon(),
      extra: ViewCoverCodec.mergeCover(
        '{"unrelated":42,"tags":["research"]}',
        const PageStyleCover(
          type: PageStyleCoverImageType.pureColor,
          value: '#B8C6AF',
        ),
      ),
    );

void _expectChat(FolderGalleryPreview preview) {
  expect(preview.kind, FolderGalleryPreviewKind.chat);
  expect(preview.fileTypeLabel, 'AI CHAT');
  expect(preview.blocks, isEmpty);
  expect(preview.database, isNull);
  expect(preview.heroUrl, isNull);
  expect(preview.wordCount, 0);
  expect(preview.readingMinutes, 0);
  expect(preview.tags, ['research']);
  expect(preview.unavailable, isFalse);
}

class _Documents extends DocumentService {
  final reads = <String>[];

  @override
  Future<FlowyResult<DocumentDataPB, FlowyError>> getDocument({
    required String documentId,
  }) async {
    reads.add(documentId);
    throw StateError('Chat must not open a document');
  }
}

class _Databases extends FolderGalleryDatabasePreviewLoader {
  final reads = <String>[];

  @override
  Future<FolderGalleryPreview> load({required ViewPB view}) async {
    reads.add(view.id);
    return const FolderGalleryPreview(
      kind: FolderGalleryPreviewKind.database,
      blocks: [],
      wordCount: 0,
      readingMinutes: 0,
      tags: [],
      fileTypeLabel: 'TABLE',
    );
  }
}
