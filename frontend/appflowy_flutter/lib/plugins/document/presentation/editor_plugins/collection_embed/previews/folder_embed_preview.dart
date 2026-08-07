import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_tiles.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A plain workspace folder, previewed as a visual collection rather than as
/// a file manager: recent objects with their own artwork, not a tree of rows
/// with disclosure triangles.
abstract final class FolderEmbedStyles {
  static const gallery = 'gallery';
  static const compact = 'compact';
  static const list = 'list';
}

CollectionEmbedDefinition buildFolderEmbedDefinition() =>
    CollectionEmbedDefinition(
      kind: null,
      defaultItemLimit: 8,
      compactHeight: 118,
      mediumHeight: 250,
      largeHeight: 396,
      styles: const [
        CollectionEmbedStyle(
          id: FolderEmbedStyles.gallery,
          labelKey: LocaleKeys.collections_embed_styles_gallery,
          icon: Icons.grid_view_rounded,
          supportsColumns: true,
        ),
        CollectionEmbedStyle(
          id: FolderEmbedStyles.compact,
          labelKey: LocaleKeys.collections_embed_styles_compact,
          icon: Icons.view_carousel_rounded,
        ),
        CollectionEmbedStyle(
          id: FolderEmbedStyles.list,
          labelKey: LocaleKeys.collections_embed_styles_list,
          icon: Icons.view_list_rounded,
        ),
      ],
      builder: (context, embed) => FolderEmbedPreview(embed: embed),
    );

class FolderEmbedPreview extends StatelessWidget {
  const FolderEmbedPreview({super.key, required this.embed});

  final CollectionEmbedContext embed;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    if (embed.controller.isLoading && embed.children.isEmpty) {
      return const _EmbedSpinner();
    }
    final views = embed.slice();
    if (views.isEmpty) {
      return CollectionEmbedEmpty(
        theme: theme,
        message: LocaleKeys.collections_embed_empty.tr(),
        icon: Icons.folder_open_rounded,
        compact: embed.size.isCompact,
      );
    }
    return switch (embed.style) {
      FolderEmbedStyles.compact => _Strip(embed: embed, views: views),
      FolderEmbedStyles.list => _List(embed: embed, views: views),
      _ => _Gallery(embed: embed, views: views),
    };
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.embed, required this.views});

  final CollectionEmbedContext embed;
  final List<ViewPB> views;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = embed.settings.columns ??
              (constraints.maxWidth / 168).floor().clamp(2, 6);
          final showCaption = !embed.size.isCompact;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            physics: const ClampingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 11,
              mainAxisSpacing: 12,
              childAspectRatio: showCaption ? 0.86 : 1.28,
            ),
            itemCount: views.length,
            itemBuilder: (context, index) {
              final view = views[index];
              return CollectionObjectCard(
                view: view,
                theme: embed.theme,
                userProfile: embed.userProfile,
                showCaption: showCaption,
                decodeWidth: constraints.maxWidth / columns,
                onTap: () => embed.onOpenObject(view),
                onSecondaryTap: embed.onShowMenu,
              );
            },
          );
        },
      );
}

class _Strip extends StatelessWidget {
  const _Strip({required this.embed, required this.views});

  final CollectionEmbedContext embed;
  final List<ViewPB> views;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final tile = (constraints.maxHeight - 26).clamp(56.0, 148.0);
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            physics: const ClampingScrollPhysics(),
            itemCount: views.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final view = views[index];
              return SizedBox(
                width: tile * 0.92,
                child: CollectionObjectCard(
                  view: view,
                  theme: embed.theme,
                  userProfile: embed.userProfile,
                  aspectRatio: 1,
                  showCaption: tile > 92,
                  decodeWidth: tile,
                  onTap: () => embed.onOpenObject(view),
                  onSecondaryTap: embed.onShowMenu,
                ),
              );
            },
          );
        },
      );
}

class _List extends StatelessWidget {
  const _List({required this.embed, required this.views});

  final CollectionEmbedContext embed;
  final List<ViewPB> views;

  @override
  Widget build(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        physics: const ClampingScrollPhysics(),
        itemCount: views.length,
        itemBuilder: (context, index) {
          final view = views[index];
          return CollectionObjectRow(
            view: view,
            theme: embed.theme,
            subtitle: embed.settings.showMetadata
                ? collectionObjectSubtitle(view)
                : null,
            onTap: () => embed.onOpenObject(view),
            onSecondaryTap: embed.onShowMenu,
          );
        },
      );
}

/// The one loading state every preview shares.
class _EmbedSpinner extends StatelessWidget {
  const _EmbedSpinner();

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 1.6),
        ),
      );
}

/// Shared so every preview shows the same thing while it reads.
class CollectionEmbedSpinner extends StatelessWidget {
  const CollectionEmbedSpinner({super.key});

  @override
  Widget build(BuildContext context) => const _EmbedSpinner();
}
