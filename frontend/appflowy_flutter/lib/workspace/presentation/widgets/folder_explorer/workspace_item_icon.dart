import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

class WorkspaceItemIcon extends StatelessWidget {
  const WorkspaceItemIcon({
    super.key,
    required this.item,
    this.expanded = false,
    this.size = 18,
    this.color,
  });

  factory WorkspaceItemIcon.fromView({
    Key? key,
    required ViewPB view,
    bool expanded = false,
    double size = 18,
    Color? color,
  }) {
    return WorkspaceItemIcon(
      key: key,
      item: WorkspaceExplorerItem.fromView(view),
      expanded: expanded,
      size: size,
      color: color,
    );
  }

  final WorkspaceExplorerItem item;
  final bool expanded;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.kind) {
      WorkspaceExplorerItemKind.folder =>
        expanded ? Icons.folder_open_rounded : Icons.folder_rounded,
      WorkspaceExplorerItemKind.file => fileIconForName(item.name),
      WorkspaceExplorerItemKind.document => Icons.description_outlined,
      WorkspaceExplorerItemKind.database => Icons.table_chart_outlined,
    };
    final resolvedColor = color ??
        switch (item.metadata?.contentKind) {
          WorkspaceFileContentKind.binary =>
            Theme.of(context).colorScheme.tertiary,
          _ => Theme.of(context).colorScheme.onSurfaceVariant,
        };
    return Icon(icon, size: size, color: resolvedColor);
  }
}
