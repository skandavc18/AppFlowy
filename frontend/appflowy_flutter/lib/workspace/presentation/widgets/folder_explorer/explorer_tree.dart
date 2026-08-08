import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _ExplorerDropPosition {
  before,
  inside,
  after,
}

class ExplorerTree extends StatefulWidget {
  const ExplorerTree({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onNavigate,
    required this.onContextMenu,
    required this.onRequestDelete,
    this.onBackgroundContextMenu,
  });

  final WorkspaceExplorerController controller;
  final ValueChanged<ViewPB> onOpen;
  final ValueChanged<String> onNavigate;
  final void Function(WorkspaceExplorerItem item, Offset position)
      onContextMenu;
  final VoidCallback onRequestDelete;

  /// Raised by a right click on empty space, so a folder can be filled
  /// without hunting for the toolbar.
  final ValueChanged<Offset>? onBackgroundContextMenu;

  @override
  State<ExplorerTree> createState() => _ExplorerTreeState();
}

class _ExplorerTreeState extends State<ExplorerTree> {
  final FocusNode focusNode = FocusNode(debugLabel: 'folder-explorer-tree');

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final rows = controller.rows;
    final draft = controller.draft;
    final insertIndex = _draftInsertIndex(rows, draft);
    final itemCount = rows.length + (draft == null ? 0 : 1);
    final palette = FolderExplorerPalette.of(context);

    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          focusNode.requestFocus();
          controller.selection.clear();
        },
        onSecondaryTapDown: widget.onBackgroundContextMenu == null
            ? null
            : (details) {
                focusNode.requestFocus();
                controller.selection.clear();
                widget.onBackgroundContextMenu!(details.globalPosition);
              },
        child: itemCount == 0
            ? Center(
                child: Text(
                  controller.query.isEmpty
                      ? LocaleKeys.workspaceFolderExplorer_emptyFolder.tr()
                      : LocaleKeys.workspaceFolderExplorer_noMatchingItems.tr(),
                  style: TextStyle(fontSize: 13, color: palette.textMuted),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemExtent: 38,
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (draft != null && index == insertIndex) {
                    final depth = draft.parentId == controller.currentFolder.id
                        ? 0
                        : _depthForParent(rows, draft.parentId);
                    return _ExplorerDraftRow(
                      key: ValueKey('draft-${draft.kind}-${draft.parentId}'),
                      draft: draft,
                      depth: depth,
                      onCancel: controller.cancelEditing,
                      onSubmitted: controller.commitDraft,
                    );
                  }
                  final rowIndex =
                      draft != null && index > insertIndex ? index - 1 : index;
                  final row = rows[rowIndex];
                  final view = controller.viewForId(row.item.id);
                  if (view == null) {
                    return const SizedBox.shrink();
                  }
                  return _ExplorerTreeRow(
                    key: ValueKey(row.item.id),
                    row: row,
                    query: controller.query,
                    selected: controller.selection.contains(row.item.id),
                    editing: controller.editingId == row.item.id,
                    view: view,
                    dragEnabled: controller.query.isEmpty,
                    onTap: () {
                      focusNode.requestFocus();
                      controller.selectRow(
                        row.item.id,
                        toggle: HardwareKeyboard.instance.isControlPressed ||
                            HardwareKeyboard.instance.isMetaPressed,
                        range: HardwareKeyboard.instance.isShiftPressed,
                      );
                    },
                    onDoubleTap: () => _open(row.item),
                    onRename: () => controller.beginRename(row.item.id),
                    onToggle: () => controller.toggleFolder(row.item.id),
                    onContextMenu: (position) {
                      if (controller.query.isNotEmpty &&
                          !row.item.name
                              .toLowerCase()
                              .contains(controller.query.toLowerCase())) {
                        return;
                      }
                      if (!controller.selection.contains(row.item.id)) {
                        controller.selectRow(
                          row.item.id,
                          toggle: false,
                          range: false,
                        );
                      }
                      widget.onContextMenu(row.item, position);
                    },
                    onRenameSubmitted: controller.commitRename,
                    onRenameCancelled: controller.cancelEditing,
                    onMove: (view, position) {
                      switch (position) {
                        case _ExplorerDropPosition.before:
                          unawaited(
                            controller.moveItem(
                              itemId: view.id,
                              parentId: row.item.parentId,
                              previousViewId: controller.previousSiblingId(
                                row.item.id,
                                excludingId: view.id,
                              ),
                            ),
                          );
                        case _ExplorerDropPosition.inside:
                          if (view.parentViewId != row.item.id) {
                            unawaited(
                              controller.moveItem(
                                itemId: view.id,
                                parentId: row.item.id,
                              ),
                            );
                          }
                        case _ExplorerDropPosition.after:
                          unawaited(
                            controller.moveItem(
                              itemId: view.id,
                              parentId: row.item.parentId,
                              previousViewId: row.item.id,
                            ),
                          );
                      }
                    },
                    onAutoExpand: () {
                      if (!row.isExpanded) {
                        controller.toggleFolder(row.item.id);
                      }
                    },
                  );
                },
              ),
      ),
    );
  }

  int _draftInsertIndex(
    List<WorkspaceExplorerRow> rows,
    WorkspaceExplorerDraft? draft,
  ) {
    if (draft == null || draft.parentId == widget.controller.currentFolder.id) {
      return 0;
    }
    final parentIndex = rows.indexWhere((row) => row.item.id == draft.parentId);
    return parentIndex < 0 ? 0 : parentIndex + 1;
  }

  int _depthForParent(List<WorkspaceExplorerRow> rows, String parentId) {
    final index = rows.indexWhere((row) => row.item.id == parentId);
    return index < 0 ? 0 : rows[index].depth + 1;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final controller = widget.controller;
    final key = event.logicalKey;
    final command = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (controller.editingId != null || controller.draft != null) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      controller.cancelEditing();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      controller.moveSelection(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      controller.moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(controller.expandSelection());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      controller.collapseSelection();
      return KeyEventResult.handled;
    }
    if (isWorkspaceRenameShortcut(Theme.of(context).platform, key)) {
      final selected = controller.selection.anchorId;
      if (selected != null) {
        controller.beginRename(selected);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      final selected = controller.selection.anchorId;
      final item = selected == null ? null : controller.itemForId(selected);
      if (item != null) {
        _open(item);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      widget.onRequestDelete();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyA) {
      controller.selectAll();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyC) {
      controller.copySelection();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyX) {
      controller.cutSelection();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyV) {
      unawaited(controller.paste());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _open(WorkspaceExplorerItem item) {
    // A collection is a folder with a purpose, and a bound folder's contents
    // live in a service, so both open as themselves rather than being browsed
    // into as plain workspace contents.
    if (item.isBrowsable) {
      widget.onNavigate(item.id);
      return;
    }
    final view = widget.controller.viewForId(item.id);
    if (view != null) {
      widget.onOpen(view);
    }
  }
}

class _ExplorerTreeRow extends StatefulWidget {
  const _ExplorerTreeRow({
    super.key,
    required this.row,
    required this.query,
    required this.selected,
    required this.editing,
    required this.view,
    required this.dragEnabled,
    required this.onTap,
    required this.onDoubleTap,
    required this.onRename,
    required this.onToggle,
    required this.onContextMenu,
    required this.onRenameSubmitted,
    required this.onRenameCancelled,
    required this.onMove,
    required this.onAutoExpand,
  });

  final WorkspaceExplorerRow row;
  final String query;
  final bool selected;
  final bool editing;
  final ViewPB view;
  final bool dragEnabled;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onRename;
  final VoidCallback onToggle;
  final ValueChanged<Offset> onContextMenu;
  final Future<bool> Function(String) onRenameSubmitted;
  final VoidCallback onRenameCancelled;
  final void Function(ViewPB view, _ExplorerDropPosition position) onMove;
  final VoidCallback onAutoExpand;

  @override
  State<_ExplorerTreeRow> createState() => _ExplorerTreeRowState();
}

class _ExplorerTreeRowState extends State<_ExplorerTreeRow> {
  bool hovered = false;
  _ExplorerDropPosition? dropPosition;
  Timer? autoExpandTimer;

  @override
  void dispose() {
    autoExpandTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final row = widget.row;
    final nameStyle = TextStyle(
      color: palette.textPrimary,
      fontSize: 14,
      fontWeight: row.item.isFolder ? FontWeight.w600 : FontWeight.w400,
    );
    Widget content = MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: dropPosition == _ExplorerDropPosition.inside
              ? palette.accent.withValues(alpha: 0.14)
              : widget.selected
                  ? palette.selected
                  : hovered
                      ? palette.hover
                      // Fading from Colors.transparent runs through
                      // transparent black and flashes dark on the way in.
                      : palette.hover.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(6),
          border: switch (dropPosition) {
            _ExplorerDropPosition.before => Border(
                top: BorderSide(color: palette.accent, width: 2),
              ),
            _ExplorerDropPosition.inside => Border.all(
                color: palette.accent.withValues(alpha: 0.55),
              ),
            _ExplorerDropPosition.after => Border(
                bottom: BorderSide(color: palette.accent, width: 2),
              ),
            null => null,
          },
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapDown: (details) =>
              widget.onContextMenu(details.globalPosition),
          child: Row(
            children: [
              const SizedBox(width: 7),
              ...List.generate(
                row.depth,
                (_) => Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.only(right: 17),
                  color: palette.border.withValues(alpha: 0.5),
                ),
              ),
              if (row.item.isFolder)
                InkWell(
                  onTap: widget.onToggle,
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox.square(
                    dimension: 20,
                    child: row.isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(5),
                            child: CircularProgressIndicator(strokeWidth: 1.3),
                          )
                        : AnimatedRotation(
                            turns: row.isExpanded ? 0.25 : 0,
                            duration: const Duration(milliseconds: 165),
                            curve: Curves.easeOutCubic,
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 17,
                              color: palette.textMuted,
                            ),
                          ),
                  ),
                )
              else
                const SizedBox(width: 20),
              const SizedBox(width: 3),
              WorkspaceItemIcon(
                item: row.item,
                expanded: row.isExpanded,
                color: row.item.isFolder
                    ? palette.accent.withValues(alpha: 0.86)
                    : null,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: WorkspaceInlineEditableText(
                  text: row.item.name,
                  editing: widget.editing,
                  onSubmitted: widget.onRenameSubmitted,
                  onCancelled: widget.onRenameCancelled,
                  onDoubleTap: widget.onRename,
                  selectFileStem: row.item.isFile,
                  style: nameStyle,
                  display: _HighlightedName(
                    name: row.item.name,
                    query: widget.query,
                    color: palette.textPrimary,
                    highlightColor: palette.accent,
                    bold: row.item.isFolder,
                  ),
                ),
              ),
              if (hovered && !widget.editing)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    _kindLabel(row.item.kind),
                    style: TextStyle(fontSize: 11, color: palette.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    content = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 4),
          child: child,
        ),
      ),
      child: content,
    );

    if (!widget.dragEnabled) {
      return content;
    }

    final targetChild = content;
    content = DragTarget<ViewPB>(
      onWillAcceptWithDetails: (details) =>
          details.data.id != widget.row.item.id,
      onMove: (details) {
        final renderBox = context.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) {
          return;
        }
        final local = renderBox.globalToLocal(details.offset);
        final third = renderBox.size.height / 3;
        final nextPosition = local.dy < third
            ? _ExplorerDropPosition.before
            : local.dy > third * 2 || !row.item.isFolder
                ? _ExplorerDropPosition.after
                : _ExplorerDropPosition.inside;
        if (dropPosition != nextPosition) {
          setState(() => dropPosition = nextPosition);
        }
        if (nextPosition == _ExplorerDropPosition.inside) {
          autoExpandTimer ??= Timer(
            const Duration(milliseconds: 650),
            widget.onAutoExpand,
          );
        } else {
          autoExpandTimer?.cancel();
          autoExpandTimer = null;
        }
      },
      onLeave: (_) {
        autoExpandTimer?.cancel();
        autoExpandTimer = null;
        if (dropPosition != null) {
          setState(() => dropPosition = null);
        }
      },
      onAcceptWithDetails: (details) {
        autoExpandTimer?.cancel();
        autoExpandTimer = null;
        final acceptedPosition = dropPosition ?? _ExplorerDropPosition.after;
        setState(() => dropPosition = null);
        widget.onMove(details.data, acceptedPosition);
      },
      builder: (_, __, ___) => targetChild,
    );

    if (!widget.editing) {
      content = Draggable<ViewPB>(
        data: widget.view,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: palette.floatingSurface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: palette.border),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WorkspaceItemIcon(item: row.item, size: 17),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    row.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: content),
        child: content,
      );
    }

    return content;
  }

  String _kindLabel(WorkspaceExplorerItemKind kind) => switch (kind) {
        WorkspaceExplorerItemKind.folder =>
          LocaleKeys.workspaceFolderExplorer_folder.tr(),
        WorkspaceExplorerItemKind.file =>
          LocaleKeys.workspaceFolderExplorer_file.tr(),
        WorkspaceExplorerItemKind.document =>
          LocaleKeys.workspaceFolderExplorer_page.tr(),
        WorkspaceExplorerItemKind.database =>
          LocaleKeys.workspaceFolderExplorer_database.tr(),
      };
}

class _ExplorerDraftRow extends StatelessWidget {
  const _ExplorerDraftRow({
    super.key,
    required this.draft,
    required this.depth,
    required this.onCancel,
    required this.onSubmitted,
  });

  final WorkspaceExplorerDraft draft;
  final int depth;
  final VoidCallback onCancel;
  final Future<bool> Function(String) onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      padding: EdgeInsets.only(left: 30 + depth * 18, right: 8),
      decoration: BoxDecoration(
        color: palette.selected,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(
            draft.kind == WorkspaceExplorerDraftKind.folder
                ? workspaceAddFolderIcon
                : workspaceAddFileIcon,
            size: 18,
            color: palette.accent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: WorkspaceInlineNameEditor(
              initialValue: draft.suggestedName,
              onSubmitted: onSubmitted,
              onCancelled: onCancel,
              textStyle: TextStyle(
                color: palette.textPrimary,
                fontSize: 13,
                fontWeight: draft.kind == WorkspaceExplorerDraftKind.folder
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
              selectFileStem: draft.kind == WorkspaceExplorerDraftKind.file,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightedName extends StatelessWidget {
  const _HighlightedName({
    required this.name,
    required this.query,
    required this.color,
    required this.highlightColor,
    required this.bold,
  });

  final String name;
  final String query;
  final Color color;
  final Color highlightColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: color,
      fontSize: 13,
      fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
    );
    final normalizedQuery = query.trim().toLowerCase();
    final index = name.toLowerCase().indexOf(normalizedQuery);
    if (normalizedQuery.isEmpty || index < 0) {
      return Text(
        name.isEmpty ? LocaleKeys.workspaceFolderExplorer_untitled.tr() : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: name.substring(0, index)),
          TextSpan(
            text: name.substring(index, index + normalizedQuery.length),
            style: style.copyWith(
              color: highlightColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: name.substring(index + normalizedQuery.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
