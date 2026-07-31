import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/book/book_views.dart';
import 'package:appflowy/plugins/collection/views/collection_contents_view.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:flutter/material.dart';

/// The adaptive views every collection type has from the start.
///
/// A collection organises objects that already exist, so the baseline view is
/// always the objects themselves. Specialised views — a reader, a filmstrip, a
/// repository tree — register themselves on top of these.
List<CollectionViewDefinition> _contentViews() => [
      CollectionViewDefinition(
        id: CollectionViewIds.gallery,
        labelKey: LocaleKeys.collections_views_gallery,
        icon: Icons.grid_view_rounded,
        builder: (context, collection) => CollectionContentsView(
          collection: collection,
          presentation: FolderExplorerPresentation.gallery,
        ),
      ),
      CollectionViewDefinition(
        id: CollectionViewIds.list,
        labelKey: LocaleKeys.collections_views_list,
        icon: Icons.view_list_rounded,
        builder: (context, collection) => CollectionContentsView(
          collection: collection,
          presentation: FolderExplorerPresentation.tree,
        ),
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
      views: _contentViews(),
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
      views: _contentViews(),
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
      views: _contentViews(),
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
      views: _contentViews(),
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
      views: _contentViews(),
    ),
  );
}
