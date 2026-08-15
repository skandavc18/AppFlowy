import 'dart:convert';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show Document, Node;
import 'package:nanoid/nanoid.dart';

/// Reading and writing the blocks of a page.
///
/// A page is a tree of blocks, and everything a person can put in one — a
/// heading, a picture, a code block, a mind map, an embedded table — is a block
/// with a type and some attributes. One insert therefore covers every kind of
/// content there is, which is why there is no tool per embed.
class DocumentToolkit {
  DocumentToolkit();

  final DocumentService _documents = DocumentService();

  /// Opens a page's document for reading AND writing, creating it when it has
  /// never been written to.
  ///
  /// ⚠️⚠️ This must be `openDocument`, never `getDocument`. `getDocument` hands
  /// back a throwaway copy, so a page reads fine while every write to it is
  /// refused with "Call open document first" — which surfaces as a block that
  /// silently never arrives. Only an opened document is editable.
  ///
  /// ⚠️ A database row's page does not exist until somebody types in it: the
  /// row only carries the id it WOULD have. Opening it then fails with "lack of
  /// document required data", which is not a permission problem and must not be
  /// reported as one — the document simply has to be made first.
  Future<DocumentDataPB?> open(String pageId) async {
    final first = await _documents.openDocument(documentId: pageId);
    final opened = first.fold((data) => data, (_) => null);
    if (opened != null) {
      return opened;
    }

    await _create(pageId);
    final second = await _documents.openDocument(documentId: pageId);
    return second.fold((data) => data, (_) => null);
  }

  Future<void> _create(String pageId) async {
    final existing = await ViewBackendService.getView(pageId);
    final view = existing.fold((found) => found, (_) => null);

    // A row's page has no view of its own until it is asked for.
    final target = view ??
        (await ViewBackendService.createOrphanView(
          viewId: pageId,
          name: '',
          layoutType: ViewLayoutPB.Document,
        ))
            .fold((created) => created, (_) => null);
    if (target == null) {
      return;
    }
    await _documents.createDocument(view: target);
  }

  /// A flat reading of the block tree, with the ids needed to change it.
  List<BlockSummary> outline(DocumentDataPB data) {
    final document = data.toDocument();
    if (document == null) {
      return const [];
    }
    final summaries = <BlockSummary>[];
    void walk(Node node, int depth) {
      for (final child in node.children) {
        summaries.add(
          BlockSummary(
            id: child.id,
            type: child.type,
            depth: depth,
            text: child.delta?.toPlainText() ?? '',
            attributes: child.attributes,
          ),
        );
        walk(child, depth + 1);
      }
    }

    walk(document.root, 0);
    return summaries;
  }

  /// The last block sitting directly under the page, which appended content
  /// follows. A nested block is no use here: it would name a stranger's sibling.
  String? lastTopLevelBlockId(DocumentDataPB data) {
    final top = outline(data).where((block) => block.depth == 0).toList();
    return top.isEmpty ? null : top.last.id;
  }

  Document parseMarkdown(String markdown) => customMarkdownToDocument(markdown);

  /// Writes [nodes] into [pageId] under [parentId], after [previousId].
  ///
  /// A block's rich text is stored beside it under an id the block points at,
  /// so the text has to exist before the block that names it.
  Future<int> insert({
    required String pageId,
    required Iterable<Node> nodes,
    required String parentId,
    String? previousId,
  }) async {
    final actions = <BlockActionPB>[];
    var previous = previousId;

    for (final node in nodes) {
      final action = await _insertAction(
        pageId: pageId,
        node: node,
        parentId: parentId,
        previousId: previous,
      );
      if (action == null) {
        continue;
      }
      actions.add(action);
      previous = node.id;
    }

    if (actions.isEmpty) {
      return 0;
    }
    final applied =
        await _documents.applyAction(documentId: pageId, actions: actions);
    return applied.fold((_) => actions.length, (_) => 0);
  }

  Future<BlockActionPB?> _insertAction({
    required String pageId,
    required Node node,
    required String parentId,
    required String? previousId,
  }) async {
    String? textId;
    final delta = node.delta;
    if (delta != null) {
      textId = nanoid(6);
      final created = await _documents.createExternalText(
        documentId: pageId,
        textId: textId,
        delta: jsonEncode(delta.toJson()),
      );
      if (created.isFailure) {
        return null;
      }
    }

    final payload = BlockActionPayloadPB()
      ..block = node.toBlock(
        parentId: parentId,
        childrenId: nanoid(6),
        externalId: textId,
        externalType: textId != null ? 'text' : null,
        attributes: {...node.attributes}..remove('delta'),
      )
      ..parentId = parentId;
    if (previousId != null && previousId.isNotEmpty) {
      payload.prevId = previousId;
    }
    if (textId != null) {
      payload.textId = textId;
    }

    return BlockActionPB()
      ..action = BlockActionTypePB.Insert
      ..payload = payload;
  }

  /// Changes a block's type, attributes and/or text.
  Future<bool> update({
    required String pageId,
    required DocumentDataPB data,
    required String blockId,
    String? type,
    Map<String, dynamic>? attributes,
    String? text,
  }) async {
    final block = data.blocks[blockId];
    if (block == null) {
      return false;
    }

    final merged = <String, dynamic>{
      ..._decode(block.data),
      ...?attributes,
    };

    var textId = block.externalId;
    if (text != null) {
      // The whole line is being rewritten, so it is given a fresh store rather
      // than a patch against whatever was there.
      textId = nanoid(6);
      await _documents.createExternalText(
        documentId: pageId,
        textId: textId,
        delta: jsonEncode([
          {'insert': text},
        ]),
      );
      merged.remove('delta');
    }

    final updated = BlockPB()
      ..id = block.id
      ..ty = type ?? block.ty
      ..data = jsonEncode(merged)
      ..parentId = block.parentId
      ..childrenId = block.childrenId
      ..externalId = textId
      ..externalType = textId.isEmpty ? '' : 'text';

    final payload = BlockActionPayloadPB()
      ..block = updated
      ..parentId = block.parentId;
    if (text != null) {
      payload.textId = textId;
    }

    final result = await _documents.applyAction(
      documentId: pageId,
      actions: [
        BlockActionPB()
          ..action = BlockActionTypePB.Update
          ..payload = payload,
      ],
    );
    return result.isSuccess;
  }

  Future<bool> delete({
    required String pageId,
    required DocumentDataPB data,
    required String blockId,
  }) async {
    final block = data.blocks[blockId];
    if (block == null) {
      return false;
    }
    final result = await _documents.applyAction(
      documentId: pageId,
      actions: [
        BlockActionPB()
          ..action = BlockActionTypePB.Delete
          ..payload = (BlockActionPayloadPB()
            ..block = block
            ..parentId = block.parentId),
      ],
    );
    return result.isSuccess;
  }

  /// Moves a block so it sits after [afterBlockId], or first when that is null.
  Future<bool> move({
    required String pageId,
    required DocumentDataPB data,
    required String blockId,
    String? afterBlockId,
  }) async {
    final block = data.blocks[blockId];
    if (block == null) {
      return false;
    }
    final payload = BlockActionPayloadPB()
      ..block = block
      ..parentId = block.parentId;
    if (afterBlockId != null && afterBlockId.isNotEmpty) {
      payload.prevId = afterBlockId;
    }

    final result = await _documents.applyAction(
      documentId: pageId,
      actions: [
        BlockActionPB()
          ..action = BlockActionTypePB.Move
          ..payload = payload,
      ],
    );
    return result.isSuccess;
  }

  static Map<String, dynamic> _decode(String data) {
    if (data.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(data);
      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

/// One block, as an agent needs to see it.
class BlockSummary {
  const BlockSummary({
    required this.id,
    required this.type,
    required this.depth,
    required this.text,
    required this.attributes,
  });

  final String id;
  final String type;
  final int depth;
  final String text;
  final Map<String, dynamic> attributes;

  String describe() {
    final indent = '  ' * depth;
    final body = text.trim().isEmpty
        ? _interesting()
        : '"${text.length > 80 ? '${text.substring(0, 80)}…' : text}"';
    return '$indent- [$id] $type $body';
  }

  /// For a block with no words, the attribute that says what it holds.
  String _interesting() {
    for (final key in const [
      'url',
      'name',
      'view_id',
      'folder_id',
      'language',
      'formula',
      'content',
      'checked',
      'level',
      'icon',
    ]) {
      final value = attributes[key];
      if (value != null && '$value'.isNotEmpty) {
        return '$key=$value';
      }
    }
    return '';
  }
}
