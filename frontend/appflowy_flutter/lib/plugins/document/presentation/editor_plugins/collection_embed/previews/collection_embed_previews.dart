import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/album_embed_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/book_embed_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/bookmark_embed_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/database_embed_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/email_embed_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/folder_embed_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/repository_embed_preview.dart';

/// Every collection type's own way of appearing inside a page.
///
/// Registration is lazy — [CollectionEmbedRegistry] calls this the first time
/// a widget is built — so a preview can import the registry back without a
/// top-level import cycle.
import 'package:appflowy/workspace/application/collections/collection.dart';

void registerBuiltInCollectionEmbeds() {
  CollectionEmbedRegistry.register(buildFolderEmbedDefinition());
  // A folder collection reads exactly as a plain folder does inside a page;
  // the difference is only where its contents come from.
  CollectionEmbedRegistry.register(
    buildFolderEmbedDefinition(kind: CollectionKind.folder),
  );
  CollectionEmbedRegistry.register(buildBookEmbedDefinition());
  CollectionEmbedRegistry.register(buildAlbumEmbedDefinition());
  CollectionEmbedRegistry.register(buildBookmarkEmbedDefinition());
  CollectionEmbedRegistry.register(buildDatabaseEmbedDefinition());
  CollectionEmbedRegistry.register(buildEmailEmbedDefinition());
  CollectionEmbedRegistry.register(buildRepositoryEmbedDefinition());
}
