import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/external_collection_host.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/plugins/collection/views/collection_contents_view.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:flutter/material.dart';

/// The identifiers the folder collection's views are stored under.
abstract final class FolderCollectionViewIds {
  static const gallery = 'folder_gallery';
  static const thumbnail = 'folder_thumbnail';
  static const list = 'folder_list';
  static const compact = 'folder_compact';
}

/// A Folder collection: files and folders, wherever they live.
///
/// Every one of these views takes the same shape whether the folder is the
/// workspace's own or a Google Drive, OneDrive or Box folder — the local case
/// goes to the workspace explorer, the remote case to [ExternalContentView],
/// and the switcher above them cannot tell the difference.
List<CollectionViewDefinition> folderCollectionViews() => [
      _view(
        id: FolderCollectionViewIds.gallery,
        labelKey: LocaleKeys.providers_layout_gallery,
        icon: Icons.grid_view_rounded,
        layout: ExternalLayout.gallery,
        presentation: FolderExplorerPresentation.gallery,
      ),
      _view(
        id: FolderCollectionViewIds.thumbnail,
        labelKey: LocaleKeys.providers_layout_thumbnail,
        icon: Icons.apps_rounded,
        layout: ExternalLayout.thumbnail,
        presentation: FolderExplorerPresentation.gallery,
      ),
      _view(
        id: FolderCollectionViewIds.list,
        labelKey: LocaleKeys.providers_layout_list,
        icon: Icons.view_list_rounded,
        layout: ExternalLayout.list,
        presentation: FolderExplorerPresentation.tree,
      ),
      _view(
        id: FolderCollectionViewIds.compact,
        labelKey: LocaleKeys.providers_layout_compact,
        icon: Icons.reorder_rounded,
        layout: ExternalLayout.compact,
        presentation: FolderExplorerPresentation.tree,
      ),
    ];

CollectionViewDefinition _view({
  required String id,
  required String labelKey,
  required IconData icon,
  required ExternalLayout layout,
  required FolderExplorerPresentation presentation,
}) =>
    CollectionViewDefinition(
      id: id,
      labelKey: labelKey,
      icon: icon,
      builder: (context, collection) => ExternalCollectionHost(
        collection: collection,
        builder: (context, controller, palette) {
          if (controller == null) {
            return CollectionContentsView(
              collection: collection,
              presentation: presentation,
            );
          }
          return ExternalContentView(
            controller: controller,
            palette: palette,
            layout: layout,
            header: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(
                children: [
                  ProviderBadge(
                    source: collection.collectionView.source,
                    palette: palette,
                    detail: controller.originLabel,
                  ),
                  const Spacer(),
                  ProviderSyncStrip(
                    palette: palette,
                    status: controller.status,
                    lastSyncedAt: controller.lastSyncedAt,
                    canSync: controller.capabilities.canSync,
                    onSync: () => unawaited(controller.resync()),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
