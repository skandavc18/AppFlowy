import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_kind_menu.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum ExplorerContextAction {
  open,
  reveal,
  rename,
  favorite,
  duplicate,
  copy,
  cut,
  paste,
  delete,
  newFile,
  newFolder,
  copyPath,
  properties,
  togglePreviewMode,
}

Future<ExplorerContextAction?> showExplorerContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required WorkspaceExplorerItem item,
  required bool canPaste,
  required bool isFavorite,
  required bool knowledgeMode,
  ValueChanged<CollectionKind>? onCreateCollection,
  ViewPreviewMode previewMode = ViewPreviewMode.cover,
}) {
  AppMenuItem action(
    ExplorerContextAction value,
    IconData icon,
    String label, {
    bool danger = false,
  }) =>
      AppMenuItem(
        label: label,
        icon: icon,
        value: value,
        destructive: danger,
      );

  return showAppMenu<ExplorerContextAction>(
    context: context,
    globalPosition: globalPosition,
    entries: [
      action(
        ExplorerContextAction.open,
        Icons.open_in_new_rounded,
        LocaleKeys.workspaceFolderExplorer_open.tr(),
      ),
      if (!knowledgeMode)
        action(
          ExplorerContextAction.reveal,
          Icons.manage_search_rounded,
          LocaleKeys.workspaceFolderExplorer_reveal.tr(),
        ),
      if (knowledgeMode)
        action(
          ExplorerContextAction.togglePreviewMode,
          previewMode == ViewPreviewMode.cover
              ? Icons.article_rounded
              : Icons.photo_rounded,
          previewMode == ViewPreviewMode.cover
              ? LocaleKeys.workspaceFolderExplorer_showContentPreview.tr()
              : LocaleKeys.workspaceFolderExplorer_showCoverPreview.tr(),
        ),
      const AppMenuSeparator(),
      action(
        ExplorerContextAction.rename,
        Icons.edit_rounded,
        LocaleKeys.workspaceFolderExplorer_rename.tr(),
      ),
      action(
        ExplorerContextAction.favorite,
        isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
        isFavorite
            ? LocaleKeys.button_removeFromFavorites.tr()
            : LocaleKeys.button_addToFavorites.tr(),
      ),
      action(
        ExplorerContextAction.duplicate,
        Icons.copy_all_rounded,
        LocaleKeys.workspaceFolderExplorer_duplicate.tr(),
      ),
      action(
        ExplorerContextAction.copy,
        Icons.copy_rounded,
        LocaleKeys.workspaceFolderExplorer_copy.tr(),
      ),
      action(
        ExplorerContextAction.cut,
        Icons.content_cut_rounded,
        LocaleKeys.workspaceFolderExplorer_cut.tr(),
      ),
      if (canPaste && item.isFolder)
        action(
          ExplorerContextAction.paste,
          Icons.content_paste_rounded,
          LocaleKeys.workspaceFolderExplorer_paste.tr(),
        ),
      if (item.isFolder) ...[
        const AppMenuSeparator(),
        action(
          ExplorerContextAction.newFile,
          workspaceAddFileIcon,
          LocaleKeys.workspaceFolderExplorer_addFile.tr(),
        ),
        action(
          ExplorerContextAction.newFolder,
          workspaceAddFolderIcon,
          LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
        ),
        if (onCreateCollection != null)
          AppMenuItem(
            label: LocaleKeys.collections_newCollection.tr(),
            icon: collectionAddIcon,
            submenu: collectionKindEntries(onSelected: onCreateCollection),
          ),
      ],
      if (!knowledgeMode) ...[
        const AppMenuSeparator(),
        action(
          ExplorerContextAction.copyPath,
          Icons.link_rounded,
          LocaleKeys.workspaceFolderExplorer_copyPath.tr(),
        ),
        action(
          ExplorerContextAction.properties,
          Icons.info_outline_rounded,
          LocaleKeys.workspaceFolderExplorer_properties.tr(),
        ),
      ],
      const AppMenuSeparator(),
      action(
        ExplorerContextAction.delete,
        Icons.delete_outline_rounded,
        LocaleKeys.workspaceFolderExplorer_delete.tr(),
        danger: true,
      ),
    ],
  );
}
