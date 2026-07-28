import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
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
  ViewPreviewMode previewMode = ViewPreviewMode.cover,
}) {
  final palette = FolderExplorerPalette.of(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & overlay.size,
  );
  const iconSize = 17.0;

  PopupMenuItem<ExplorerContextAction> action(
    ExplorerContextAction value,
    IconData icon,
    String label, {
    bool danger = false,
  }) {
    return PopupMenuItem(
      value: value,
      height: 34,
      child: Row(
        children: [
          Icon(
            icon,
            size: iconSize,
            color: danger ? palette.danger : palette.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: danger ? palette.danger : palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<ExplorerContextAction> gap() => const PopupMenuItem(
        enabled: false,
        height: 6,
        child: SizedBox.shrink(),
      );

  return showMenu<ExplorerContextAction>(
    context: context,
    position: position,
    elevation: 12,
    color: palette.floatingSurface,
    shadowColor: palette.shadow,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    constraints: const BoxConstraints(minWidth: 190, maxWidth: 230),
    popUpAnimationStyle: AnimationStyle(
      duration: Duration(milliseconds: 140),
      reverseDuration: Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
    ),
    items: [
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
              ? Icons.article_outlined
              : Icons.photo_outlined,
          previewMode == ViewPreviewMode.cover
              ? LocaleKeys.workspaceFolderExplorer_showContentPreview.tr()
              : LocaleKeys.workspaceFolderExplorer_showCoverPreview.tr(),
        ),
      gap(),
      action(
        ExplorerContextAction.rename,
        Icons.edit_outlined,
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
        Icons.copy_all_outlined,
        LocaleKeys.workspaceFolderExplorer_duplicate.tr(),
      ),
      action(
        ExplorerContextAction.copy,
        Icons.copy_outlined,
        LocaleKeys.workspaceFolderExplorer_copy.tr(),
      ),
      action(
        ExplorerContextAction.cut,
        Icons.content_cut_outlined,
        LocaleKeys.workspaceFolderExplorer_cut.tr(),
      ),
      if (canPaste && item.isFolder)
        action(
          ExplorerContextAction.paste,
          Icons.content_paste_outlined,
          LocaleKeys.workspaceFolderExplorer_paste.tr(),
        ),
      if (item.isFolder) ...[
        gap(),
        action(
          ExplorerContextAction.newFile,
          workspaceAddFileIcon,
          LocaleKeys.workspaceFolderExplorer_addFile.tr(),
        ),
        action(
          ExplorerContextAction.newFolder,
          knowledgeMode
              ? Icons.auto_awesome_mosaic_outlined
              : workspaceAddFolderIcon,
          knowledgeMode
              ? LocaleKeys.workspaceFolderExplorer_newCollection.tr()
              : LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
        ),
      ],
      if (!knowledgeMode) ...[
        gap(),
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
      gap(),
      action(
        ExplorerContextAction.delete,
        Icons.delete_outline_rounded,
        LocaleKeys.workspaceFolderExplorer_delete.tr(),
        danger: true,
      ),
    ],
  );
}
