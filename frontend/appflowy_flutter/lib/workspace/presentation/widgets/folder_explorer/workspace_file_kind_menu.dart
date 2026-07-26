import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:flutter/material.dart';

/// Shows the creatable and uploadable file types anchored at [globalPosition].
///
/// Used by the explorer toolbar, its context menu and the sidebar root button
/// so every surface offers the same set as the `/` slash menu.
Future<WorkspaceFileMenuAction?> showWorkspaceFileKindMenu({
  required BuildContext context,
  required Offset globalPosition,
}) {
  final palette = FolderExplorerPalette.of(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & overlay.size,
  );

  final items = <PopupMenuEntry<WorkspaceFileMenuAction>>[];
  WorkspaceFileSource? section;
  for (final action in workspaceFileMenuActions) {
    if (action.source != section) {
      if (section != null) {
        items.add(const PopupMenuDivider(height: 9));
      }
      section = action.source;
      items.add(
        PopupMenuItem<WorkspaceFileMenuAction>(
          enabled: false,
          height: 26,
          child: Text(
            action.source.heading.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: palette.textMuted,
            ),
          ),
        ),
      );
    }
    items.add(
      PopupMenuItem<WorkspaceFileMenuAction>(
        value: action,
        height: 34,
        child: Row(
          children: [
            Icon(action.icon, size: 17, color: palette.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  return showMenu<WorkspaceFileMenuAction>(
    context: context,
    position: position,
    elevation: 12,
    color: palette.floatingSurface,
    shadowColor: palette.shadow,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
    popUpAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 140),
      reverseDuration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
    ),
    items: items,
  );
}
