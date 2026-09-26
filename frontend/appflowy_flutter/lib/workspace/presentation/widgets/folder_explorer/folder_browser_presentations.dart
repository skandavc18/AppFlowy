import 'dart:async';

import 'package:appflowy/shared/file_browser/file_browser_items.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// New readings of the existing graph. No repository, new controller, or
/// independent permission model is constructed when the presentation changes.
class FolderBrowserPresentation extends StatelessWidget {
  const FolderBrowserPresentation({
    super.key,
    required this.controller,
    required this.mode,
    required this.onOpen,
    required this.onNavigate,
    required this.onContextMenu,
    required this.onBackgroundContextMenu,
    required this.onRequestDelete,
  });

  final WorkspaceExplorerController controller;
  final FileBrowserViewMode mode;
  final ValueChanged<ViewPB> onOpen;
  final ValueChanged<String> onNavigate;
  final void Function(WorkspaceExplorerItem, Offset) onContextMenu;
  final ValueChanged<Offset> onBackgroundContextMenu;
  final VoidCallback onRequestDelete;

  void _open(FileBrowserEntry entry) {
    if (entry.item.isBrowsable) {
      onNavigate(entry.id);
    } else {
      onOpen(entry.view);
    }
  }

  Widget _items(String folderId, {String? activeChildId}) {
    if (controller.currentFolder.id == folderId &&
        controller.isLoading &&
        !controller.hasLoaded(folderId)) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final query = controller.query.toLowerCase();
    final searching = query.isNotEmpty;
    final views = searching
        ? [
            for (final row in controller.rows)
              if (row.item.name.toLowerCase().contains(query) &&
                  controller.viewForId(row.item.id) != null)
                controller.viewForId(row.item.id)!,
          ]
        : controller.childrenOf(folderId);
    final draft = controller.draft;
    return FileBrowserItems(
      key: ValueKey('folder-browser-items-$folderId'),
      entries: views.map(FileBrowserEntry.fromView).toList(),
      selection: controller.selection,
      details: mode == FileBrowserViewMode.details,
      tiles: mode == FileBrowserViewMode.tiles,
      openOnTap: mode != FileBrowserViewMode.columns,
      autofocus: mode == FileBrowserViewMode.columns &&
          controller.currentFolder.id == folderId,
      activeChildId: activeChildId,
      onActivateColumn: () {
        if (!searching && controller.currentFolder.id != folderId) {
          onNavigate(folderId);
        }
      },
      rowWrapper: (entry, row) => _dragRow(entry, row, searching: searching),
      editingId: controller.editingId,
      onOpen: _open,
      onRename: controller.canWrite
          ? (entry) {
              if (controller.canRename(entry.id)) {
                controller.beginRename(entry.id);
              }
            }
          : null,
      onRenameSubmitted: (entry, name) => controller.canRename(entry.id)
          ? controller.commitRename(name)
          : Future.value(false),
      onRenameCancelled: controller.cancelEditing,
      onContextMenu: (entry, position) {
        // A context action on an ancestor column belongs to that directory,
        // not the previously active rightmost directory.
        if (!searching && controller.currentFolder.id != folderId) {
          onNavigate(folderId);
          controller.selection.selectOnly(entry.id);
        }
        onContextMenu(entry.item, position);
      },
      onBackgroundContextMenu: (position) {
        if (!searching && controller.currentFolder.id != folderId) {
          onNavigate(folderId);
        }
        onBackgroundContextMenu(position);
      },
      onParent: controller.breadcrumbs.length > 1
          ? () => onNavigate(
                controller.breadcrumbs[controller.breadcrumbs.length - 2].id,
              )
          : null,
      onCopy: controller.copySelection,
      onCut: controller.canMutateSelection ? controller.cutSelection : null,
      onPaste: controller.canPaste ? () => unawaited(controller.paste()) : null,
      onDelete: controller.canMutateSelection ? onRequestDelete : null,
      draft: draft?.parentId != folderId
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: WorkspaceInlineNameEditor(
                key: ValueKey('folder-browser-draft-${draft!.parentId}'),
                initialValue: draft.suggestedName,
                onSubmitted: controller.commitDraft,
                onCancelled: controller.cancelEditing,
                selectFileStem: draft.kind == WorkspaceExplorerDraftKind.file,
              ),
            ),
      emptyMessage: searching ? 'No matching items' : 'This folder is empty',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mode != FileBrowserViewMode.columns || controller.query.isNotEmpty) {
      return _items(controller.currentFolder.id);
    }
    final path = controller.breadcrumbs;
    return FileBrowserColumns(
      onNavigate: onNavigate,
      columns: [
        for (var index = 0; index < path.length; index++)
          FileBrowserColumn(
            id: path[index].id,
            label: path[index].name,
            child: _items(
              path[index].id,
              activeChildId:
                  index + 1 < path.length ? path[index + 1].id : null,
            ),
          ),
      ],
    );
  }

  Widget _dragRow(
    FileBrowserEntry entry,
    Widget row, {
    required bool searching,
  }) {
    if (searching ||
        !controller.canWriteTo(entry.id) ||
        entry.item.readsFromService) {
      return row;
    }
    final target = DragTarget<ViewPB>(
      onWillAcceptWithDetails: (details) =>
          details.data.id != entry.id &&
          controller
              .canWriteTo(entry.item.isFolder ? entry.id : entry.item.parentId),
      onAcceptWithDetails: (details) {
        if (!controller.canWriteTo(entry.id) || entry.item.readsFromService) {
          return;
        }
        unawaited(
          controller.moveItem(
            itemId: details.data.id,
            parentId: entry.item.isFolder ? entry.id : entry.item.parentId,
            previousViewId: entry.item.isFolder
                ? null
                : controller.previousSiblingId(
                    entry.id,
                    excludingId: details.data.id,
                  ),
          ),
        );
      },
      builder: (_, __, ___) => row,
    );
    if (controller.editingId == entry.id) return target;
    return Draggable<ViewPB>(
      data: entry.view,
      feedback: Material(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(entry.item.name),
        ),
      ),
      child: Listener(behavior: HitTestBehavior.translucent, child: target),
    );
  }
}
