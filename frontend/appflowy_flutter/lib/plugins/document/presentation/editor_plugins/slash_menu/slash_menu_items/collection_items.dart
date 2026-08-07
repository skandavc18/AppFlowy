import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/folder_explorer/folder_explorer_block_component.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

import 'slash_menu_item_builder.dart';

/// One slash menu entry per collection type, so `/book` reaches a book
/// without having to know that collections exist.
List<SelectionMenuItem> collectionSlashMenuItems(DocumentBloc documentBloc) => [
      for (final definition in CollectionRegistry.types)
        _collectionSlashMenuItem(documentBloc, definition),
    ];

SelectionMenuItem _collectionSlashMenuItem(
  DocumentBloc documentBloc,
  CollectionTypeDefinition definition,
) {
  return SelectionMenuItem(
    getName: () => definition.label,
    keywords: definition.searchKeywords,
    handler: (editorState, _, __) async {
      final created = await const CollectionService().createCollection(
        parentViewId: documentBloc.documentId,
        kind: definition.kind,
        name: definition.defaultName,
      );
      await created.fold(
        (view) => editorState.insertCollectionBlock(view.id),
        (_) async {},
      );
    },
    nameBuilder: slashMenuItemNameBuilder,
    icon: (_, isSelected, style) => SelectableIconWidget(
      icon: definition.icon,
      isSelected: isSelected,
      style: style,
    ),
  );
}

extension InsertCollectionBlock on EditorState {
  /// A collection is a workspace folder with a purpose, so it embeds through
  /// the folder block it already has.
  Future<void> insertCollectionBlock(String collectionId) async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final path = selection.end.path;
    final currentNode = getNodeAtPath(path);
    if (currentNode == null) {
      return;
    }

    // A new collection appears as the interactive widget, not as a chip: the
    // point of putting one on a page is to see into it.
    final block = folderExplorerNode(folderId: collectionId);
    final transaction = this.transaction;
    final delta = currentNode.delta;
    if (delta != null &&
        delta.isEmpty &&
        currentNode.type == ParagraphBlockKeys.type) {
      transaction
        ..insertNode(path, block)
        ..deleteNode(currentNode);
    } else {
      transaction.insertNode(path.next, block);
    }
    await apply(transaction);
  }
}
