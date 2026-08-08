import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/external_collection_host.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/collection/providers/external_repository_view.dart';
import 'package:appflowy/plugins/collection/providers/git/git_collection_view.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/plugins/collection/views/album/album_views.dart';
import 'package:appflowy/plugins/collection/views/book/book_views.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_views.dart';
import 'package:appflowy/plugins/collection/views/collection_contents_view.dart';
import 'package:appflowy/plugins/collection/views/database/database_views.dart';
import 'package:appflowy/plugins/collection/views/email/email_views.dart';
import 'package:appflowy/plugins/collection/views/folder/folder_collection_views.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_views.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// The adaptive views every collection type has from the start.
///
/// A collection organises objects that already exist, so the baseline view is
/// always the objects themselves. Specialised views — a reader, a filmstrip, a
/// repository tree — register themselves on top of these.
///
/// A type that already shows its media visually turns [includeGallery] off:
/// two card walls in one switcher is one too many. [galleryLabelKey] renames
/// the wall for a type that has no competing view to be told apart from.
/// The plain contents views every collection type carries.
///
/// These two are the only ones that are source aware in one step: they show
/// whatever the collection holds with no opinion about it, so a service's
/// listing can stand in for the workspace's. A type's own views know their
/// subject and read the service themselves.
List<CollectionViewDefinition> _contentViews({
  bool includeGallery = true,
  String galleryLabelKey = LocaleKeys.collections_views_files,
  void Function(CollectionViewContext collection, ViewPB view)? onOpenObject,
}) =>
    [
      if (includeGallery)
        _sourceAware(
          CollectionViewDefinition(
            id: CollectionViewIds.gallery,
            labelKey: galleryLabelKey,
            icon: Icons.grid_view_rounded,
            builder: (context, collection) => CollectionContentsView(
              collection: collection,
              presentation: FolderExplorerPresentation.gallery,
              onOpenObject: onOpenObject,
            ),
          ),
        ),
      _sourceAware(
        CollectionViewDefinition(
          id: CollectionViewIds.list,
          labelKey: LocaleKeys.collections_views_list,
          icon: Icons.view_list_rounded,
          builder: (context, collection) => CollectionContentsView(
            collection: collection,
            presentation: FolderExplorerPresentation.tree,
            onOpenObject: onOpenObject,
          ),
        ),
        layout: ExternalLayout.list,
      ),
    ];

/// The stable identifiers adaptive views are stored under.
///
/// Ids are persisted in the collection envelope, so they must not change once
/// shipped.
abstract final class CollectionViewIds {
  static const gallery = 'gallery';
  static const list = 'list';
}

/// Makes one view answer for whatever the collection is backed by.
///
/// A collection that holds the workspace's own objects renders exactly as it
/// always did. A collection bound to a service renders the service's content
/// through the same switcher, in the same place, with the same label — which
/// is what makes the provider an implementation detail rather than a second
/// kind of collection.
CollectionViewDefinition _sourceAware(
  CollectionViewDefinition definition, {
  ExternalLayout layout = ExternalLayout.gallery,
}) =>
    CollectionViewDefinition(
      id: definition.id,
      labelKey: definition.labelKey,
      icon: definition.icon,
      builder: (context, collection) {
        if (collection.collectionView.source.isLocal) {
          return definition.builder(context, collection);
        }
        return ExternalCollectionHost(
          collection: collection,
          builder: (context, controller, palette) {
            if (controller == null) {
              return definition.builder(context, collection);
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
        );
      },
    );

void registerBuiltInCollections() {
  CollectionRegistry.register(
    CollectionTypeDefinition(
      kind: CollectionKind.book,
      labelKey: LocaleKeys.collections_kind_book,
      descriptionKey: LocaleKeys.collections_kindDescription_book,
      defaultNameKey: LocaleKeys.collections_defaultName_book,
      icon: Icons.menu_book_rounded,
      accent: const Color(0xFFB4763C),
      searchKeywords: const [
        'book',
        'read',
        'reader',
        'reading',
        'chapter',
        'ebook',
        'novel',
        'library',
        'collection',
      ],
      views: [...bookCollectionViews(), ..._contentViews()],
    ),
  );
  CollectionRegistry.register(
    CollectionTypeDefinition(
      kind: CollectionKind.album,
      labelKey: LocaleKeys.collections_kind_album,
      descriptionKey: LocaleKeys.collections_kindDescription_album,
      defaultNameKey: LocaleKeys.collections_defaultName_album,
      icon: Icons.photo_library_rounded,
      accent: const Color(0xFFA855F7),
      searchKeywords: const [
        'album',
        'photo',
        'photos',
        'picture',
        'gallery',
        'media',
        'video',
        'slideshow',
        'collection',
      ],
      views: [
        // NOT source aware: `AlbumHost` feeds these from the service itself,
        // so the wall, the masonry, the timeline and the places plot all work
        // on a hosted album exactly as they do on a workspace one.
        ...albumCollectionViews(),
        ..._contentViews(includeGallery: false),
      ],
    ),
  );
  CollectionRegistry.register(
    CollectionTypeDefinition(
      kind: CollectionKind.repository,
      labelKey: LocaleKeys.collections_kind_repository,
      descriptionKey: LocaleKeys.collections_kindDescription_repository,
      defaultNameKey: LocaleKeys.collections_defaultName_repository,
      icon: Icons.code_rounded,
      accent: const Color(0xFF3B82F6),
      searchKeywords: const [
        'repository',
        'repo',
        'code',
        'source',
        'project',
        'git',
        'developer',
        'collection',
      ],
      views: [
        // NOT source aware: `RepositoryHost` unpacks a hosted repository onto
        // disk and then feeds these exactly as it feeds a local one, so the
        // browser, tree, symbols, dependencies and docs all work either way.
        ...repositoryCollectionViews(),
        ..._contentViews(
          galleryLabelKey: LocaleKeys.collections_views_gallery,
          onOpenObject: openRepoObject,
        ),
        CollectionViewDefinition(
          id: 'repo_remote',
          labelKey: LocaleKeys.providers_repo_remote,
          icon: Icons.cloud_rounded,
          isAvailable: (source) => source.isRemote,
          builder: (context, collection) => ExternalCollectionHost(
            collection: collection,
            builder: (context, controller, palette) => controller == null
                ? const SizedBox.shrink()
                : ExternalRepositoryView(
                    controller: controller,
                    palette: palette,
                    source: collection.collectionView.source,
                  ),
          ),
        ),
        CollectionViewDefinition(
          id: 'source_control',
          labelKey: LocaleKeys.providers_git_title,
          icon: Icons.account_tree_rounded,
          builder: (context, collection) =>
              GitCollectionView(collection: collection),
        ),
      ],
    ),
  );
  CollectionRegistry.register(
    CollectionTypeDefinition(
      kind: CollectionKind.folder,
      labelKey: LocaleKeys.collections_kind_folder,
      descriptionKey: LocaleKeys.collections_kindDescription_folder,
      defaultNameKey: LocaleKeys.collections_defaultName_folder,
      icon: Icons.folder_copy_rounded,
      accent: const Color(0xFF5B8DEF),
      searchKeywords: const [
        'folder',
        'files',
        'drive',
        'storage',
        'cloud',
        'google drive',
        'onedrive',
        'box',
        'documents',
        'collection',
      ],
      views: folderCollectionViews(),
    ),
  );
  CollectionRegistry.register(
    CollectionTypeDefinition(
      kind: CollectionKind.database,
      labelKey: LocaleKeys.collections_kind_database,
      descriptionKey: LocaleKeys.collections_kindDescription_database,
      defaultNameKey: LocaleKeys.collections_defaultName_database,
      icon: Icons.storage_rounded,
      accent: const Color(0xFF0EA5A4),
      searchKeywords: const [
        'database',
        'tables',
        'records',
        'dataset',
        'collection',
      ],
      views: [
        ...databaseCollectionViews(),
        ..._contentViews(includeGallery: false),
      ],
    ),
  );
  CollectionRegistry.register(
    CollectionTypeDefinition(
      kind: CollectionKind.bookmark,
      labelKey: LocaleKeys.collections_kind_bookmark,
      descriptionKey: LocaleKeys.collections_kindDescription_bookmark,
      defaultNameKey: LocaleKeys.collections_defaultName_bookmark,
      icon: Icons.bookmarks_rounded,
      accent: const Color(0xFFE0475F),
      searchKeywords: const [
        'bookmark',
        'bookmarks',
        'link',
        'links',
        'url',
        'web',
        'article',
        'research',
        'reading list',
        'collection',
      ],
      views: [
        ...bookmarkCollectionViews(),
        ..._contentViews(includeGallery: false),
      ],
    ),
  );
  CollectionRegistry.register(
    CollectionTypeDefinition(
      kind: CollectionKind.email,
      labelKey: LocaleKeys.collections_kind_email,
      descriptionKey: LocaleKeys.collections_kindDescription_email,
      defaultNameKey: LocaleKeys.collections_defaultName_email,
      icon: Icons.mail_rounded,
      accent: const Color(0xFF6366F1),
      searchKeywords: const [
        'email',
        'mail',
        'mailbox',
        'inbox',
        'message',
        'conversation',
        'collection',
      ],
      views: [
        ...emailCollectionViews(),
        ..._contentViews(includeGallery: false),
      ],
    ),
  );
}
