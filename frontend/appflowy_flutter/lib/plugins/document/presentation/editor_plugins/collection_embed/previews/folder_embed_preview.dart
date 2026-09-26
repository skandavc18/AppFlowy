import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_tiles.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/breadcrumb_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'folder_embed_browser.dart';

/// A plain workspace folder, previewed as a visual collection rather than as
/// a file manager: recent objects with their own artwork, not a tree of rows
/// with disclosure triangles.
abstract final class FolderEmbedStyles {
  static const gallery = FileBrowserViewIds.gallery;
  static const compact = FileBrowserViewIds.thumbnails;
  static const tiles = FileBrowserViewIds.tiles;
  static const list = FileBrowserViewIds.list;
  static const details = FileBrowserViewIds.details;
  static const columns = FileBrowserViewIds.columns;
  static const tree = FileBrowserViewIds.tree;
}

CollectionEmbedDefinition buildFolderEmbedDefinition({CollectionKind? kind}) =>
    CollectionEmbedDefinition(
      kind: kind,
      defaultItemLimit: 8,
      compactHeight: 118,
      mediumHeight: 250,
      largeHeight: 396,
      styles: [
        for (final mode in FileBrowserViewMode.values)
          CollectionEmbedStyle(
            id: mode.id,
            labelKey: mode.labelKey,
            icon: mode.icon,
            supportsColumns: mode == FileBrowserViewMode.gallery,
          ),
      ],
      builder: (context, embed) => FolderEmbedPreview(embed: embed),
    );

class FolderEmbedPreview extends StatelessWidget {
  const FolderEmbedPreview({super.key, required this.embed});

  final CollectionEmbedContext embed;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: embed.controller,
        builder: (context, _) {
          if (const {
            FileBrowserViewMode.tiles,
            FileBrowserViewMode.details,
            FileBrowserViewMode.columns,
            FileBrowserViewMode.tree,
          }.contains(embed.settings.folderViewMode)) {
            return FolderEmbedBrowser(
              key: ValueKey((embed.controller, embed.collection.id)),
              embed: embed,
            );
          }
          final controller = embed.controller;
          final path = controller.folderPath;
          final current = path.last;
          final nested = path.length > 1;
          final views = controller
              .orderedChildren(current.id, embed.settings.sort)
              .where(
                (view) =>
                    controller.folderQuery.isEmpty ||
                    view.name.toLowerCase().contains(controller.folderQuery),
              )
              .take(
                embed.settings.itemLimit ?? embed.definition.defaultItemLimit,
              )
              .toList();
          // Identical child IDs from a replacement root/controller must never
          // inherit the old root's pending preview or keyboard focus.
          final Widget body = controller.loadingChildren(current.id) &&
                  views.isEmpty
              ? const _EmbedSpinner()
              : views.isEmpty || controller.childrenError(current.id) != null
                  ? _FolderEmbedStatus(
                      embed: embed,
                      folderId: nested ? current.id : null,
                    )
                  : _FolderEmbedItems(
                      key: ValueKey((controller, embed.collection.id)),
                      embed: embed,
                      views: views,
                    );
          // Preserve the original renderer depth until browsing actually adds
          // path/filter chrome. Existing root gallery/strip previews are intact.
          if (!nested && !controller.folderFilterActive) return body;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.folderFilterActive)
                FolderEmbedFilter(embed: embed),
              if (nested)
                BreadcrumbBar(
                  items: path.map(WorkspaceExplorerItem.fromView).toList(),
                  onSelected: (id) => controller
                      .navigateFolder(path.firstWhere((view) => view.id == id)),
                ),
              Expanded(child: body),
            ],
          );
        },
      );
}

class _FolderEmbedItems extends StatelessWidget {
  const _FolderEmbedItems({
    super.key,
    required this.embed,
    required this.views,
  });

  final CollectionEmbedContext embed;
  final List<ViewPB> views;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final thumbnails =
              embed.settings.folderViewMode == FileBrowserViewMode.thumbnails;
          final list =
              embed.settings.folderViewMode == FileBrowserViewMode.list;
          final thumbnailMetrics = GalleryCardMetrics.thumbnails(
            available: math.max(0, constraints.maxWidth - 28),
            compact: true,
            textScale: MediaQuery.textScalerOf(context).scale(13) / 13,
          );
          final showCaption = thumbnails || !embed.size.isCompact;
          final columns = list
              ? 1
              : thumbnails
                  ? thumbnailMetrics.columns
                  : embed.settings.columns ??
                      (constraints.maxWidth / 168).floor().clamp(2, 6);
          final padding = list
              ? const EdgeInsets.fromLTRB(10, 6, 10, 10)
              : thumbnails
                  ? EdgeInsetsDirectional.fromSTEB(
                      14,
                      8,
                      14 +
                          math.max(
                            0,
                            constraints.maxWidth -
                                28 -
                                thumbnailMetrics.gridWidth,
                          ),
                      12,
                    )
                  : const EdgeInsets.fromLTRB(14, 10, 14, 14);
          final width = math.max(
            0.0,
            (constraints.maxWidth - padding.horizontal - 11 * (columns - 1)) /
                columns,
          );
          final scaler = MediaQuery.textScalerOf(context);
          final metadataHeight = embed.settings.showMetadata
              ? (scaler.scale(10.5) * 1.25).ceilToDouble()
              : 0.0;
          final extent = list
              ? math.max(
                  34.0,
                  (scaler.scale(12.5) * 1.25).ceilToDouble() +
                      metadataHeight +
                      4,
                )
              : thumbnails
                  ? thumbnailMetrics.height
                  : math.max(
                      width / (showCaption ? 0.86 : 1.28),
                      showCaption ? 72 + _captionHeight(context, embed) : 0.0,
                    );
          final indices = <Key, int>{
            for (var index = 0; index < views.length; index++)
              ValueKey('folder-embed-item-${views[index].id}'): index,
          };
          // Every face keeps the controller's bounded preview futures. A dense
          // contact sheet is deliberately not the Gallery footer-card face.
          return GridView.builder(
            key: const ValueKey('folder-embed-items'),
            primary: false,
            padding: padding,
            physics: const ClampingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing:
                  list ? 0 : (thumbnails ? thumbnailMetrics.spacing : 11),
              mainAxisSpacing:
                  list ? 0 : (thumbnails ? thumbnailMetrics.spacing : 12),
              mainAxisExtent: extent,
            ),
            itemCount: views.length,
            findChildIndexCallback: (key) => indices[key],
            itemBuilder: (context, index) => _FolderEmbedItem(
              key: ValueKey('folder-embed-item-${views[index].id}'),
              embed: embed,
              view: views[index],
              list: list,
              thumbnails: thumbnails,
              showCaption: showCaption,
            ),
          );
        },
      );
}

double _captionHeight(BuildContext context, CollectionEmbedContext embed) {
  final scaler = MediaQuery.textScalerOf(context);
  return 16 +
      math.max(16.0, scaler.scale(12) * 1.25) +
      (embed.settings.showMetadata ? 2 + scaler.scale(10.5) * 1.25 : 0);
}

class _FolderEmbedItem extends StatefulWidget {
  const _FolderEmbedItem({
    super.key,
    required this.embed,
    required this.view,
    required this.list,
    required this.thumbnails,
    required this.showCaption,
  });

  final CollectionEmbedContext embed;
  final ViewPB view;
  final bool list;
  final bool thumbnails;
  final bool showCaption;

  @override
  State<_FolderEmbedItem> createState() => _FolderEmbedItemState();
}

class _FolderEmbedItemState extends State<_FolderEmbedItem> {
  final _focusNode = FocusNode(debugLabel: 'Folder embed item');
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_syncFocus);
  }

  void _syncFocus() {
    final focused = _focusNode.hasFocus;
    if (mounted && focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_syncFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _showMenu() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      widget.embed.onShowMenu(box.localToGlobal(box.size.center(Offset.zero)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final embed = widget.embed;
    final view = widget.view;
    final title = view.name.isEmpty
        ? LocaleKeys.workspaceFolderExplorer_untitled.tr()
        : view.name;
    return Shortcuts(
      // Resolve before an enclosing editor's commands; the native InkWell (or
      // focused Retry button) still owns its own activation action.
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.contextMenu): _showMenu,
          const SingleActivator(LogicalKeyboardKey.f10, shift: true): _showMenu,
        },
        child: Semantics(
          container: true,
          button: true,
          label: title,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              focusNode: _focusNode,
              onFocusChange: (_) => _syncFocus(),
              onHover: (hovered) => setState(() => _hovered = hovered),
              onTap: () => embed.onOpenObject(view),
              onSecondaryTapDown: (details) =>
                  embed.onShowMenu(details.globalPosition),
              mouseCursor: SystemMouseCursors.click,
              splashFactory: NoSplash.splashFactory,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: widget.list
                  ? _buildRow(context, title)
                  : _buildPreviewFrame(context, title),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, String title) {
    final theme = widget.embed.theme;
    return AnimatedContainer(
      duration: WorkspaceTokens.motion(context, CollectionEmbedMetrics.hover),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _hovered || _focused
            ? theme.rowHover
            : theme.rowHover.withValues(alpha: 0),
        borderRadius:
            BorderRadius.circular(CollectionEmbedMetrics.controlRadius),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(CollectionEmbedMetrics.controlRadius),
        border: _focused
            ? Border.all(color: WorkspacePalette.of(context).focus, width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          _identity(16),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.face(context, size: 12.5, weightAxis: 560),
                  ),
                ),
                if (widget.embed.settings.showMetadata) _metadata(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewFrame(BuildContext context, String title) {
    final palette = FolderExplorerPalette.of(context);
    final card = GalleryCardPalette.of(context);
    final corners = BorderRadius.circular(WorkspaceTokens.cardRadius);
    // Decoration is a sibling, not a changing ancestor of the renderer. A
    // loaded image/document stays mounted across Gallery/Thumbnails switches.
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: corners,
        border: _focused
            ? Border.all(color: palette.accent, width: 1.5)
            : widget.thumbnails
                ? null
                : Border.all(
                    color: _hovered ? card.activeEdge : card.edge,
                    width: galleryCardHairlineWidth,
                  ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: widget.thumbnails
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.hover.withValues(
                          alpha: _hovered ? palette.hover.a : 0,
                        ),
                        borderRadius: corners,
                      ),
                    )
                  : GalleryCardSurface(
                      hovered: _hovered,
                      focused: _focused,
                      child: const SizedBox.expand(),
                    ),
            ),
          ),
          ClipRRect(
            borderRadius: corners,
            child: _buildCard(context, title),
          ),
        ],
      ),
    );
  }

  Widget _identity(double size) {
    final saved = widget.view.icon.toEmojiIconData();
    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: saved.isNotEmpty
            ? RawEmojiIconWidget(emoji: saved, emojiSize: size, lineHeight: 1)
            : WorkspaceItemIcon.fromView(
                view: widget.view,
                size: size,
                showThumbnail: false,
              ),
      ),
    );
  }

  Widget _metadata(BuildContext context) => Text(
        collectionObjectSubtitle(widget.view),
        key: const ValueKey('folder-embed-item-metadata'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.embed.theme.caption(context, size: 10.5),
      );

  Widget _buildCard(BuildContext context, String title) {
    final embed = widget.embed;
    final preview = embed.controller.folderPreviewFor(widget.view);
    final item = WorkspaceExplorerItem.fromView(widget.view);
    return LayoutBuilder(
      builder: (context, constraints) {
        final caption = widget.showCaption &&
            constraints.maxHeight >= _captionHeight(context, embed) + 24;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Always a Column, including captionless compact cards. Keeping
            // this slot at the same depth retains loaded/pending renderers.
            Expanded(
              child: LayoutBuilder(
                builder: (context, slot) {
                  // Tiny/high-column embeds can be smaller than the shared
                  // code/table preview's padding. Fit a bounded real thumbnail,
                  // not replacement artwork; hover never changes this geometry.
                  final scale = math.max(
                    1.0,
                    math.max(
                      144 / math.max(1.0, slot.maxWidth),
                      120 / math.max(1.0, slot.maxHeight),
                    ),
                  );
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: slot.maxWidth * scale,
                      height: slot.maxHeight * scale,
                      child: FolderGalleryPreviewThumbnail(
                        key: ValueKey(
                          'folder-embed-thumbnail-${widget.view.id}',
                        ),
                        item: item,
                        view: widget.view,
                        preview: preview,
                        userProfile: embed.userProfile,
                        height: slot.maxHeight * scale,
                        borderRadius: BorderRadius.zero,
                        compact: true,
                        lightweight: widget.thumbnails,
                        surfaceColor: widget.thumbnails
                            ? null
                            : GalleryCardPalette.of(context).surface,
                        onRetry: () =>
                            embed.controller.retryFolderPreview(widget.view.id),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.thumbnails)
              SizedBox(
                height: 12 +
                    2 *
                        (MediaQuery.textScalerOf(context).scale(13) * 1.4)
                            .ceilToDouble(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: ExcludeSemantics(
                    child: Tooltip(
                      message: title,
                      child: Text(
                        title,
                        key: const ValueKey('folder-embed-thumbnail-name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: embed.theme
                            .face(context, size: 13, weightAxis: 560)
                            .copyWith(height: 1.4),
                      ),
                    ),
                  ),
                ),
              )
            else if (caption)
              GalleryCardFooter(
                padding: EdgeInsets.symmetric(
                  horizontal: math.min(10.0, constraints.maxWidth * 0.12),
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(
                      child: Row(
                        children: [
                          if (constraints.maxWidth >= 96 &&
                              widget.view.icon.value.isNotEmpty) ...[
                            _identity(16),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: embed.theme.face(
                                context,
                                size: 12,
                                weightAxis: 580,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (embed.settings.showMetadata) ...[
                      const SizedBox(height: 2),
                      _metadata(context),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FolderEmbedStatus extends StatelessWidget {
  const _FolderEmbedStatus({required this.embed, this.folderId});

  final CollectionEmbedContext embed;
  final String? folderId;

  @override
  Widget build(BuildContext context) {
    final failed =
        embed.controller.childrenError(folderId ?? embed.collection.id) != null;
    return Center(
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkspaceGlyph.named(failed ? 'warning' : 'folder', size: 24),
            const SizedBox(height: 8),
            Text(
              failed
                  ? LocaleKeys.workspaceFolderExplorer_previewUnavailable.tr()
                  : embed.controller.folderQuery.isNotEmpty
                      ? LocaleKeys.workspaceFolderExplorer_noMatchingItems.tr()
                      : LocaleKeys.collections_embed_empty.tr(),
              key: ValueKey(
                failed ? 'folder-embed-unavailable' : 'folder-embed-empty',
              ),
              textAlign: TextAlign.center,
              style: embed.theme.body(context),
            ),
            if (failed)
              TextButton(
                key: const ValueKey('folder-embed-retry'),
                style: WorkspaceChrome.controlStyle(context),
                onPressed: folderId == null
                    ? embed.onRefresh
                    : () =>
                        unawaited(embed.controller.retryChildren(folderId!)),
                child: Text(LocaleKeys.button_retry.tr()),
              ),
          ],
        ),
      ),
    );
  }
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
