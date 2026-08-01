import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_thumbnail.dart';
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

  /// Whether this item shows a preview rather than a glyph, so hosts can skip
  /// the dimming they apply to icons.
  static bool showsThumbnail(ViewPB view) =>
      WorkspaceItemThumbnail.localSourceFor(
        WorkspaceExplorerItem.fromView(view),
      ) !=
      null;

  @override
  Widget build(BuildContext context) {
    final collectionKind = item.collection?.kind;
    if (collectionKind != null) {
      final definition = CollectionRegistry.typeFor(collectionKind);
      return Icon(
        definition.icon,
        size: size,
        color: color ?? CollectionPalette.of(context, collectionKind).accent,
      );
    }

    // A saved link has no bytes on disk, so the file glyph would name it by an
    // extension it does not have.
    if (item.isBookmark) {
      return Icon(
        Icons.link_rounded,
        size: size,
        color: color ??
            CollectionPalette.of(context, CollectionKind.bookmark).accent,
      );
    }

    final resolvedColor = color ??
        switch (item.metadata?.contentKind) {
          WorkspaceFileContentKind.binary =>
            Theme.of(context).colorScheme.tertiary,
          _ => Theme.of(context).colorScheme.onSurfaceVariant,
        };

    final icon = Icon(
      switch (item.kind) {
        WorkspaceExplorerItemKind.folder =>
          expanded ? Icons.folder_open_rounded : Icons.folder_rounded,
        WorkspaceExplorerItemKind.file => fileIconForName(item.name),
        WorkspaceExplorerItemKind.document => Icons.description_rounded,
        WorkspaceExplorerItemKind.database => Icons.table_chart_rounded,
      },
      size: size,
      color: resolvedColor,
    );

    final source = WorkspaceItemThumbnail.localSourceFor(item);
    if (source == null) {
      return icon;
    }
    return WorkspaceItemThumbnail(
      path: source,
      isVideo: WorkspaceItemThumbnail.isVideoName(item.name),
      size: size,
      fallback: icon,
    );
  }
}
