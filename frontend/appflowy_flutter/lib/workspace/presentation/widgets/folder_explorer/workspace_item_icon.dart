import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_thumbnail.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// Automatic fallback only. Hosts render a chosen IconPB first; neither this
/// renderer nor a device style change edits the item's stored identity.
class WorkspaceItemIcon extends StatelessWidget {
  const WorkspaceItemIcon({
    super.key,
    required this.item,
    this.view,
    this.expanded = false,
    this.size = 18,
    this.color,
    this.showThumbnail = true,
  });

  factory WorkspaceItemIcon.fromView({
    Key? key,
    required ViewPB view,
    bool expanded = false,
    double size = 18,
    Color? color,
    bool showThumbnail = true,
  }) {
    return WorkspaceItemIcon(
      key: key,
      item: WorkspaceExplorerItem.fromView(view),
      view: view,
      expanded: expanded,
      size: size,
      color: color,
      showThumbnail: showThumbnail,
    );
  }

  final WorkspaceExplorerItem item;
  // Optional for legacy item-only callers. Layout/marks must come from the
  // actual view, never from a guessed filename or an invented item kind.
  final ViewPB? view;
  final bool expanded;
  final double size;
  final Color? color;
  final bool showThumbnail;

  /// Whether this item shows a preview rather than a glyph, so hosts can skip
  /// the dimming they apply to icons.
  static bool showsThumbnail(ViewPB view) =>
      WorkspaceItemThumbnail.localSourceFor(
        WorkspaceExplorerItem.fromView(view),
      ) !=
      null;

  @override
  Widget build(BuildContext context) {
    final view = this.view;
    if (view != null &&
        !item.isFolder &&
        !item.isFile &&
        !item.isCollection &&
        !view.isWorkspaceItem) {
      return WorkspaceGlyph.adapt(
        view.defaultIcon(size: Size.square(size)),
        size: size,
        color: color,
      );
    }
    final collectionKind = item.collection?.kind;
    if (collectionKind != null) {
      return WorkspaceGlyph.collection(
        collectionKind,
        size: size,
        color: color,
      );
    }

    // A saved link has no bytes on disk, so the file glyph would name it by an
    // extension it does not have.
    if (item.isBookmark) {
      return WorkspaceGlyph(
        Icons.link_rounded,
        size: size,
        color: color,
      );
    }

    final icon = item.isFile
        ? WorkspaceGlyph.file(item.name, size: size, color: color)
        : WorkspaceGlyph.named(
            switch (item.kind) {
              WorkspaceExplorerItemKind.folder =>
                expanded ? 'folder-open' : 'folder',
              WorkspaceExplorerItemKind.database => 'table',
              _ => 'file-text',
            },
            size: size,
            color: color,
          );

    final source =
        showThumbnail ? WorkspaceItemThumbnail.localSourceFor(item) : null;
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
