import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_artwork.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_tiles.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/folder_embed_preview.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_language.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

abstract final class RepositoryEmbedStyles {
  static const overview = 'overview';
  static const files = 'files';
}

CollectionEmbedDefinition buildRepositoryEmbedDefinition() =>
    CollectionEmbedDefinition(
      kind: CollectionKind.repository,
      defaultItemLimit: 8,
      compactHeight: 138,
      mediumHeight: 272,
      styles: const [
        CollectionEmbedStyle(
          id: RepositoryEmbedStyles.overview,
          labelKey: LocaleKeys.collections_embed_styles_repoOverview,
          icon: Icons.insights_rounded,
        ),
        CollectionEmbedStyle(
          id: RepositoryEmbedStyles.files,
          labelKey: LocaleKeys.collections_embed_styles_repoFiles,
          icon: Icons.folder_open_rounded,
        ),
      ],
      builder: (context, embed) => RepositoryEmbedPreview(embed: embed),
    );

class RepositoryEmbedPreview extends StatefulWidget {
  const RepositoryEmbedPreview({super.key, required this.embed});

  final CollectionEmbedContext embed;

  @override
  State<RepositoryEmbedPreview> createState() => _RepositoryEmbedPreviewState();
}

class _RepositoryEmbedPreviewState extends State<RepositoryEmbedPreview> {
  /// The folder currently being browsed, as a chain of view ids from the
  /// repository root. Browsing happens inside the widget — a page should not
  /// have to open the repository to look at one file's neighbours.
  final List<ViewPB> path = <ViewPB>[];

  /// Long lived so moving the pointer down a listing does not re-read a file
  /// that was already previewed.
  final FolderGalleryPreviewCache previewCache = FolderGalleryPreviewCache();

  ViewPB? hovered;

  CollectionEmbedContext get embed => widget.embed;

  List<ViewPB> get currentChildren => path.isEmpty
      ? embed.children
      : embed.controller.childrenOf(path.last.id);

  @override
  void didUpdateWidget(covariant RepositoryEmbedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.embed.collection.id != embed.collection.id) {
      path.clear();
      hovered = null;
      previewCache.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    if (embed.controller.isLoading && embed.children.isEmpty) {
      return const CollectionEmbedSpinner();
    }
    if (embed.children.isEmpty) {
      return CollectionEmbedEmpty(
        theme: theme,
        icon: Icons.code_rounded,
        message: LocaleKeys.collections_embed_empty.tr(),
        compact: embed.size.isCompact,
      );
    }
    return embed.style == RepositoryEmbedStyles.files || path.isNotEmpty
        ? _buildBrowser(context)
        : _buildOverview(context);
  }

  Widget _buildOverview(BuildContext context) {
    final theme = embed.theme;
    final entries = buildRepoTree(
      rootId: embed.collection.id,
      childrenOf: (id) => id == embed.collection.id
          ? embed.children
          : embed.controller.childrenOf(id),
      maxDepth: 3,
      maxEntries: 400,
    );
    final languages = _languageShare(entries);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (embed.settings.showMetadata && languages.isNotEmpty) ...[
            _LanguageBar(theme: theme, shares: languages),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final entry in languages.take(4))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: entry.$1.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${entry.$1.label} ${(entry.$2 * 100).round()}%',
                        style: theme.caption(context),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _ListingAndPreview(
              embed: embed,
              views: _topLevel(embed.children),
              previewCache: previewCache,
              previewTarget: _previewTarget(embed.children),
              selectedId: hovered?.id,
              onEnterFolder: _enterFolder,
              onHover: _setHovered,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowser(BuildContext context) {
    final theme = embed.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (path.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: Row(
              children: [
                CollectionEmbedButton(
                  theme: theme,
                  icon: Icons.arrow_back_rounded,
                  size: 22,
                  iconSize: 14,
                  onPressed: () => setState(path.removeLast),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    path.map((view) => view.name).join(' / '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.caption(context),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _ListingAndPreview(
            embed: embed,
            views: currentChildren,
            previewCache: previewCache,
            previewTarget: _previewTarget(currentChildren),
            selectedId: hovered?.id,
            onEnterFolder: _enterFolder,
            onHover: _setHovered,
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
          ),
        ),
      ],
    );
  }

  void _setHovered(ViewPB view, bool isHovered) {
    if (isHovered) {
      if (hovered?.id != view.id) {
        setState(() => hovered = view);
      }
      return;
    }
    // Leaving a row keeps its preview up: blanking the pane on the way to the
    // next row makes the whole panel flicker.
  }

  /// What the pane shows: whatever the pointer is on, else the README, else
  /// the first thing in the listing that can actually be previewed.
  ViewPB? _previewTarget(List<ViewPB> views) {
    final current = hovered;
    if (current != null && views.any((view) => view.id == current.id)) {
      return current;
    }
    final readme = _findReadme(views);
    if (readme != null) {
      return readme;
    }
    for (final view in views) {
      if (!view.isWorkspaceFolder && !view.isCollection) {
        return view;
      }
    }
    return null;
  }

  void _enterFolder(ViewPB folder) {
    embed.controller.ensureLoaded(folder.id).ignore();
    setState(() {
      path.add(folder);
      hovered = null;
    });
  }

  List<ViewPB> _topLevel(List<ViewPB> views) {
    final limit = embed.settings.itemLimit ?? embed.definition.defaultItemLimit;
    return views.length <= limit ? views : views.take(limit).toList();
  }

  ViewPB? _findReadme(List<ViewPB> views) {
    for (final view in views) {
      if (view.name.toLowerCase().startsWith('readme')) {
        return view;
      }
    }
    return null;
  }

  /// Which languages the repository is actually written in, by file count.
  List<(RepoLanguage, double)> _languageShare(List<RepoEntry> entries) {
    final counts = <RepoLanguage, int>{};
    var total = 0;
    for (final entry in entries) {
      final language = entry.language;
      if (entry.isFolder || language == null) {
        continue;
      }
      counts[language] = (counts[language] ?? 0) + 1;
      total++;
    }
    if (total == 0) {
      return const [];
    }
    final shares = [
      for (final entry in counts.entries) (entry.key, entry.value / total),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return shares;
  }
}

class _LanguageBar extends StatelessWidget {
  const _LanguageBar({required this.theme, required this.shares});

  final CollectionEmbedTheme theme;
  final List<(RepoLanguage, double)> shares;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 5,
          child: Row(
            children: [
              for (final share in shares.take(6))
                Expanded(
                  flex: (share.$2 * 1000).round().clamp(1, 1000),
                  child: ColoredBox(color: share.$1.color),
                ),
            ],
          ),
        ),
      );
}

/// The listing beside a live preview of whatever the pointer is on.
///
/// Below [_previewBreakpoint] there is no room for two columns, so the pane
/// steps aside and the listing takes the whole widget.
class _ListingAndPreview extends StatelessWidget {
  const _ListingAndPreview({
    required this.embed,
    required this.views,
    required this.previewCache,
    required this.previewTarget,
    required this.selectedId,
    required this.onEnterFolder,
    required this.onHover,
    this.padding = const EdgeInsets.symmetric(vertical: 2),
  });

  static const double _previewBreakpoint = 520;

  final CollectionEmbedContext embed;
  final List<ViewPB> views;
  final FolderGalleryPreviewCache previewCache;
  final ViewPB? previewTarget;
  final String? selectedId;
  final ValueChanged<ViewPB> onEnterFolder;
  final void Function(ViewPB view, bool hovered) onHover;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final listing = _FileList(
      embed: embed,
      views: views,
      selectedId: selectedId,
      onEnterFolder: onEnterFolder,
      onHover: onHover,
      padding: padding,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (embed.size.isCompact ||
            constraints.maxWidth < _previewBreakpoint ||
            previewTarget == null) {
          return listing;
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: listing),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _PreviewPane(
                embed: embed,
                view: previewTarget!,
                previewCache: previewCache,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({
    required this.embed,
    required this.views,
    required this.onEnterFolder,
    this.onHover,
    this.selectedId,
    this.padding = const EdgeInsets.symmetric(vertical: 2),
  });

  final CollectionEmbedContext embed;
  final List<ViewPB> views;
  final ValueChanged<ViewPB> onEnterFolder;
  final void Function(ViewPB view, bool hovered)? onHover;
  final String? selectedId;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (views.isEmpty) {
      return CollectionEmbedEmpty(
        theme: embed.theme,
        icon: Icons.folder_open_rounded,
        message: LocaleKeys.collections_embed_empty.tr(),
        compact: true,
      );
    }
    return ListView.builder(
      padding: padding,
      physics: const ClampingScrollPhysics(),
      itemCount: views.length,
      itemBuilder: (context, index) {
        final view = views[index];
        final isFolder = view.isWorkspaceFolder || view.isCollection;
        return CollectionObjectRow(
          view: view,
          theme: embed.theme,
          height: 30,
          selected: view.id == selectedId,
          trailing: isFolder
              ? Icon(
                  Icons.chevron_right_rounded,
                  size: 15,
                  color: embed.theme.textFaint,
                )
              : null,
          onTap: () =>
              isFolder ? onEnterFolder(view) : embed.onOpenObject(view),
          onSecondaryTap: embed.onShowMenu,
          onHoverChanged: onHover == null
              ? null
              : (hovered) => onHover!(view, hovered),
        );
      },
    );
  }
}

/// A real preview of one file, read the same way the folder gallery reads it.
///
/// The loader takes only the first few kilobytes of a file and renders
/// markdown, code and plain text through the application's own preview
/// blocks, so a README shows its actual words without opening the document.
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.embed,
    required this.view,
    required this.previewCache,
  });

  final CollectionEmbedContext embed;
  final ViewPB view;
  final FolderGalleryPreviewCache previewCache;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    return CollectionEmbedTappable(
      onTap: () => embed.onOpenObject(view),
      onSecondaryTap: embed.onShowMenu,
      lift: 0,
      builder: (context, hovered) => AnimatedContainer(
        duration: CollectionEmbedMetrics.hover,
        curve: CollectionEmbedMetrics.ease,
        decoration: BoxDecoration(
          color: hovered ? theme.raised : theme.sunken,
          borderRadius:
              BorderRadius.circular(CollectionEmbedMetrics.innerRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Icon(
                    collectionObjectGlyph(view),
                    size: 14,
                    color: collectionObjectHue(view.id, dark: theme.isDark),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      view.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.title(context, size: 12),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: hovered ? 1 : 0,
                    duration: CollectionEmbedMetrics.hover,
                    child: Icon(
                      Icons.north_east_rounded,
                      size: 13,
                      color: theme.accent,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = embed.theme;
    return FutureBuilder<FolderGalleryPreview>(
      // The cache hands back the same future for an unchanged file, so this
      // does not start a read on every rebuild.
      future: previewCache.previewFor(
        view: view,
        item: WorkspaceExplorerItem.fromView(view),
      ),
      builder: (context, snapshot) {
        final preview = snapshot.data;
        if (preview == null) {
          return const CollectionEmbedSpinner();
        }
        if (preview.hasHero) {
          return CollectionArtwork(
            view: view,
            theme: theme,
            userProfile: embed.userProfile,
          );
        }
        if (preview.blocks.isEmpty) {
          return CollectionEmbedEmpty(
            theme: theme,
            compact: true,
            icon: collectionObjectGlyph(view),
            message: preview.unavailable
                ? LocaleKeys.collections_embed_previewUnavailable.tr()
                : LocaleKeys.collections_embed_previewEmpty.tr(),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: FolderGalleryRichTextPreview(blocks: preview.blocks),
        );
      },
    );
  }
}
