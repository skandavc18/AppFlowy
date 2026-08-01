import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// The adaptive view every collection type starts from: the objects it holds,
/// as a card grid or as a list.
///
/// It reuses the workspace explorer so a collection supports the same create,
/// rename, move, duplicate and delete gestures as a folder — a collection
/// organises existing objects, it does not own a second file system.
class CollectionContentsView extends StatelessWidget {
  const CollectionContentsView({
    super.key,
    required this.collection,
    required this.presentation,
    this.onOpenObject,
  });

  final CollectionViewContext collection;
  final FolderExplorerPresentation presentation;

  /// What clicking an object means for this collection type. A repository
  /// hands the file to its own viewer rather than opening a workspace tab.
  final void Function(CollectionViewContext collection, ViewPB view)?
      onOpenObject;

  @override
  Widget build(BuildContext context) {
    return FolderExplorer(
      key: ValueKey(
        'collection-contents-${collection.collectionView.id}-${presentation.name}',
      ),
      rootView: collection.collectionView,
      controller: collection.explorer,
      initialPresentation: presentation,
      showHeader: false,
      showControls: false,
      showFooter: false,
      onOpen: onOpenObject == null
          ? collection.onOpen
          : (view) => onOpenObject!(collection, view),
    );
  }
}
