import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// What a folder or collection held, drawn with the folder gallery's own card.
///
/// A version is a snapshot, so the cards are fed a made-up view and a preview
/// of their own rather than the live ones — but they are the SAME cards the
/// folder itself is drawn with, so a remembered folder reads as a folder.
class PageVersionGalleryView extends StatelessWidget {
  const PageVersionGalleryView({
    super.key,
    required this.children,
    this.onOpen,
  });

  final List<PageVersionChild> children;

  /// What to do when one of them is clicked. Without it the cards are a
  /// record and answer nothing.
  final ValueChanged<PageVersionChild>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = GalleryCardMetrics.resolve(
          available: constraints.maxWidth - 28,
          size: GalleryCardSize.small,
          spacing: 14,
        );
        return GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: metrics.columns,
            mainAxisSpacing: metrics.spacing,
            crossAxisSpacing: metrics.spacing,
            mainAxisExtent: metrics.height,
          ),
          itemCount: children.length,
          itemBuilder: (context, index) => _card(children[index]),
        );
      },
    );
  }

  Widget _card(PageVersionChild child) {
    final view = pageVersionChildView(child);
    final item = WorkspaceExplorerItem.fromView(view);
    final open = onOpen;
    final card = FolderGalleryCard(
      item: item,
      view: view,
      preview: SynchronousFuture(pageVersionChildPreview(child)),
      userProfile: null,
      selected: false,
      editing: false,
      onTap: open == null ? () {} : () => open(child),
      onRename: () {},
      onRenameSubmitted: (_) async => false,
      onRenameCancelled: () {},
      onMore: (_) {},
      onContextMenu: (_) {},
    );
    // A remembered folder is a record, so its cards answer nothing unless
    // somebody is listening for it.
    return open == null ? IgnorePointer(child: card) : card;
  }
}

/// The view a stored child would have had.
ViewPB pageVersionChildView(PageVersionChild child, {String parentId = ''}) {
  final layout = ViewLayoutPB.valueOf(child.layout) ?? ViewLayoutPB.Document;
  // ⚠️ Dressing it as a workspace item is what keeps the card from asking the
  // backend for a page that may no longer exist.
  final metadata = child.isFolder
      ? const WorkspaceItemMetadata.folder()
      : const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
        );
  return ViewPB(
    id: child.id.isEmpty ? child.name : child.id,
    parentViewId: parentId,
    name: child.name,
    layout: layout,
    extra: metadata.mergeIntoExtra(''),
    icon: child.icon.isEmpty
        ? null
        : ViewIconPB(
            // The type was not kept, but the newer icons are stored as json
            // and an emoji never is, which tells the two apart.
            ty: child.icon.trimLeft().startsWith('{')
                ? ViewIconTypePB.Icon
                : ViewIconTypePB.Emoji,
            value: child.icon,
          ),
  );
}

/// What a card should say about a stored child.
FolderGalleryPreview pageVersionChildPreview(PageVersionChild child) {
  return FolderGalleryPreview(
    kind: child.isFolder
        ? FolderGalleryPreviewKind.folder
        : FolderGalleryPreviewKind.file,
    blocks: const [],
    wordCount: 0,
    readingMinutes: 0,
    tags: const [],
    fileTypeLabel: '',
  );
}
