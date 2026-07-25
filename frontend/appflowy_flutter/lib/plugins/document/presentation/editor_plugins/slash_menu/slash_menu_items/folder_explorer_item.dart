import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/folder_explorer/folder_explorer_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'slash_menu_items.dart';

final folderLinkSlashMenuItem = _buildFolderSlashMenuItem(
  name: LocaleKeys.workspaceFolderExplorer_folder,
  keywords: const ['folder', 'directory', 'project', 'link'],
  mode: FolderExplorerBlockDisplayMode.icon,
);

final folderExplorerSlashMenuItem = _buildFolderSlashMenuItem(
  name: LocaleKeys.workspaceFolderExplorer_folderExplorer,
  keywords: const [
    'folder',
    'directory',
    'preview',
    'collection',
    'explorer',
    'project',
    'files',
  ],
  mode: FolderExplorerBlockDisplayMode.explorer,
);

SelectionMenuItem _buildFolderSlashMenuItem({
  required String name,
  required List<String> keywords,
  required FolderExplorerBlockDisplayMode mode,
}) {
  return SelectionMenuItem(
    getName: name.tr,
    keywords: keywords,
    handler: (editorState, _, __) =>
        editorState.insertFolderExplorerBlock(mode),
    nameBuilder: slashMenuItemNameBuilder,
    icon: (_, isSelected, style) => SelectableSvgWidget(
      data: FlowySvgs.folder_m,
      isSelected: isSelected,
      style: style,
    ),
  );
}

extension InsertFolderExplorerBlock on EditorState {
  Future<void> insertFolderExplorerBlock(
    FolderExplorerBlockDisplayMode mode,
  ) async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final path = selection.end.path;
    final currentNode = getNodeAtPath(path);
    final delta = currentNode?.delta;
    if (currentNode == null || delta == null) {
      return;
    }

    final key = GlobalKey<FolderExplorerBlockComponentState>();
    final folderNode = folderExplorerNode(displayMode: mode)
      ..extraInfos = {FolderExplorerBlockKeys.globalKey: key};
    final transaction = this.transaction;
    if (delta.isEmpty && currentNode.type == ParagraphBlockKeys.type) {
      transaction
        ..insertNode(path, folderNode)
        ..deleteNode(currentNode);
    } else {
      transaction.insertNode(path.next, folderNode);
    }
    await apply(transaction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      key.currentState?.showFolderPicker();
    });
  }
}
