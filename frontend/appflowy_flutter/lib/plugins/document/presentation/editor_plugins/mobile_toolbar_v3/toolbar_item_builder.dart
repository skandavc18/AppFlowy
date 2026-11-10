import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

final _listBlockTypes = [
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
  TodoListBlockKeys.type,
];

final _defaultToolbarItems = [
  addBlockToolbarItem,
  aaToolbarItem,
  todoListToolbarItem,
  bulletedListToolbarItem,
  addAttachmentItem,
  numberedListToolbarItem,
  boldToolbarItem,
  italicToolbarItem,
  underlineToolbarItem,
  strikethroughToolbarItem,
  colorToolbarItem,
  undoToolbarItem,
  redoToolbarItem,
];

final _listToolbarItems = [
  addBlockToolbarItem,
  aaToolbarItem,
  outdentToolbarItem,
  indentToolbarItem,
  todoListToolbarItem,
  bulletedListToolbarItem,
  numberedListToolbarItem,
  boldToolbarItem,
  italicToolbarItem,
  underlineToolbarItem,
  strikethroughToolbarItem,
  colorToolbarItem,
  addAttachmentItem,
  undoToolbarItem,
  redoToolbarItem,
];

final _textToolbarItems = [
  aaToolbarItem,
  boldToolbarItem,
  italicToolbarItem,
  underlineToolbarItem,
  strikethroughToolbarItem,
  colorToolbarItem,
];

/// Calculate the toolbar items based on the current selection.
///
/// Default:
///   Add, Aa, Todo List, Image, Bulleted List, Numbered List, B, I, U, S, Color, Undo, Redo
///
/// Selecting text:
///   Aa, B, I, U, S, Color
///
/// Selecting a list:
///   Add, Aa, Indent, Outdent, Bulleted List, Numbered List, Todo List B, I, U, S
///
/// [showAllBlocks] opens the editor's `/` menu; the add-block sheet offers it
/// so every block `/` has is a tap away from the toolbar too.
List<AppFlowyMobileToolbarItem> buildMobileToolbarItems(
  EditorState editorState,
  Selection? selection, {
  Future<void> Function()? showAllBlocks,
}) {
  if (selection == null) {
    return [];
  }
  List<AppFlowyMobileToolbarItem> withAddBlock(
    List<AppFlowyMobileToolbarItem> items,
  ) =>
      showAllBlocks == null
          ? items
          : [
              for (final item in items)
                identical(item, addBlockToolbarItem)
                    ? buildAddBlockToolbarItem(showAllBlocks: showAllBlocks)
                    : item,
            ];

  if (!selection.isCollapsed) {
    final items = List.of(_textToolbarItems);
    if (onlyShowInSingleSelectionAndTextType(editorState)) {
      items.add(linkToolbarItem);
    }
    return items;
  }

  final allSelectedAreListType = editorState
      .getSelectedNodes(selection: selection)
      .every((node) => _listBlockTypes.contains(node.type));
  if (allSelectedAreListType) {
    return withAddBlock(_listToolbarItems);
  }

  return withAddBlock(_defaultToolbarItems);
}
