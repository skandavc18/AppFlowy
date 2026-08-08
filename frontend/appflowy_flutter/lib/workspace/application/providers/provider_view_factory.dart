import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// One object out of an external service, dressed as a workspace item.
///
/// This is the whole trick. Every view AppFlowy already has — the album wall,
/// the folder gallery, the repository tree, the file preview — draws from a
/// [ViewPB] plus a [WorkspaceExplorerItem]. Giving a remote object the same
/// shape means a Google Drive folder is rendered by exactly the same cards as
/// a workspace folder, with no second implementation and no branch anywhere in
/// the presentation layer.
///
/// The same idea already carries the inside of a zip archive, which is why the
/// identifiers here follow the same `<root>::<path>` shape.
@immutable
class ProviderItemView {
  const ProviderItemView({
    required this.node,
    required this.view,
    required this.item,
  });

  final ProviderNode node;
  final ViewPB view;
  final WorkspaceExplorerItem item;

  String get id => view.id;
}

/// Builds workspace items for the contents of an external collection.
class ProviderViewFactory {
  ProviderViewFactory({
    required this.collectionId,
    required this.source,
  });

  /// The collection the remote objects hang under. A synthetic id always
  /// starts with it, so nothing can be confused with a real workspace view.
  final String collectionId;

  final CollectionSource source;

  /// The synthetic view id for one remote object.
  ///
  /// It is derived from the remote id rather than generated, so the same object
  /// keeps the same id across refreshes and selection, expansion and scroll
  /// position all survive a sync.
  String viewIdFor(String remoteId) =>
      remoteId.isEmpty ? collectionId : '$collectionId::$remoteId';

  /// Reads a remote id back out of a synthetic view id, or null when the view
  /// is a real workspace one.
  String? remoteIdOf(String viewId) {
    final marker = '$collectionId::';
    return viewId.startsWith(marker) ? viewId.substring(marker.length) : null;
  }

  ProviderItemView viewFor(
    ProviderNode node, {
    String? localPath,
    String? thumbnailPath,
  }) {
    final view = node.isFolder
        ? _view(
            id: viewIdFor(node.id),
            parentId: viewIdFor(node.parentId ?? ''),
            name: node.name,
            metadata: const WorkspaceItemMetadata.folder(),
          )
        : _view(
            id: viewIdFor(node.id),
            parentId: viewIdFor(node.parentId ?? ''),
            name: node.name,
            metadata: WorkspaceItemMetadata.file(
              // Always binary: a remote object is bytes we fetched, never a
              // collaborative document, and the gallery only skips a backend
              // read for a binary item.
              contentKind: WorkspaceFileContentKind.binary,
              mimeType: node.mimeType,
              storageUrl: localPath ?? thumbnailPath ?? node.downloadUrl,
              size: node.byteSize,
              modifiedAt: node.modifiedAt,
            ),
          );

    return ProviderItemView(
      node: node,
      view: view,
      item: WorkspaceExplorerItem.fromView(view),
    );
  }

  List<ProviderItemView> viewsFor(
    Iterable<ProviderNode> nodes, {
    Map<String, String> localPaths = const <String, String>{},
    Map<String, String> thumbnails = const <String, String>{},
  }) =>
      [
        for (final node in nodes)
          viewFor(
            node,
            localPath: localPaths[node.id],
            thumbnailPath: thumbnails[node.id],
          ),
      ];

  /// The view that stands for the collection's own root, used by tree walkers
  /// that expect a folder above the first level.
  ViewPB rootView(String name) => _view(
        id: collectionId,
        parentId: '',
        name: name,
        metadata: const WorkspaceItemMetadata.folder(),
      );

  ViewPB _view({
    required String id,
    required String parentId,
    required String name,
    required WorkspaceItemMetadata metadata,
  }) =>
      ViewPB(
        id: id,
        parentViewId: parentId,
        name: name.trim().isEmpty ? 'Untitled' : name,
        layout: ViewLayoutPB.Document,
        extra: metadata.mergeIntoExtra(''),
      );
}

/// Whether a view id belongs to an external object rather than the workspace.
///
/// Anything that can be handed a view from a collection — a context menu, a
/// drag, "open in workspace" — asks this before offering an action that only
/// makes sense for something the workspace actually stores.
bool isProviderView(String viewId) => viewId.contains('::');
