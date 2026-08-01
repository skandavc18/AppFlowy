import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/album/album_chrome.dart';
import 'package:appflowy/plugins/collection/views/album/album_context_menu.dart';
import 'package:appflowy/plugins/collection/views/album/album_host.dart';
import 'package:appflowy/plugins/collection/views/album/album_lightbox.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

/// How the media is arranged on the wall.
enum AlbumWallLayout {
  /// Every tile the same square, like a contact sheet.
  grid,

  /// Tiles keep their own shape and pack together.
  masonry,

  /// Runs headed by the date they were taken.
  timeline,
}

/// The gallery, masonry and timeline views.
///
/// They differ only in how the tiles are laid out, so they share one wall
/// rather than three near-identical screens.
class AlbumWallView extends StatelessWidget {
  const AlbumWallView({
    super.key,
    required this.collection,
    required this.layout,
  });

  final CollectionViewContext collection;
  final AlbumWallLayout layout;

  @override
  Widget build(BuildContext context) {
    return AlbumHost(
      collection: collection,
      builder: (context, controller, palette) => AlbumScaffold(
        controller: controller,
        palette: palette,
        leading: albumArrangementControls(
          context: context,
          controller: controller,
          palette: palette,
          showGrouping: layout == AlbumWallLayout.timeline,
        ),
        trailing: [
          if (controller.isReadingMetadata)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: palette.textMuted,
                ),
              ),
            ),
          AlbumToolbarButton(
            palette: palette,
            icon: Icons.title_rounded,
            tooltip: LocaleKeys.collections_album_showNames.tr(),
            selected: controller.settings.showNames,
            onPressed: () => controller.updateSettings(
              controller.settings
                  .copyWith(showNames: !controller.settings.showNames),
            ),
          ),
          AlbumToolbarButton(
            palette: palette,
            icon: Icons.slideshow_rounded,
            tooltip: LocaleKeys.collections_album_playSlideshow.tr(),
            onPressed: controller.visual.isEmpty
                ? null
                : () => _open(
                      context,
                      controller,
                      palette,
                      controller.visual.first.id,
                      slideshow: true,
                    ),
          ),
        ],
        child: controller.isEmpty
            ? _background(
                context,
                controller,
                palette,
                AlbumEmptyState(
                  palette: palette,
                  icon: Icons.photo_library_rounded,
                  title: LocaleKeys.collections_album_emptyTitle.tr(),
                  description:
                      LocaleKeys.collections_album_emptyDescription.tr(),
                ),
              )
            : PremiumScrollScope(
                enabled: true,
                child: _background(
                  context,
                  controller,
                  palette,
                  _buildWall(context, controller, palette),
                ),
              ),
      ),
    );
  }

  /// A right click on whatever the tiles do not cover acts on the album.
  Widget _background(
    BuildContext context,
    AlbumController controller,
    CollectionPalette palette,
    Widget child,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => showAlbumBackgroundMenu(
        context: context,
        globalPosition: details.globalPosition,
        controller: controller,
        palette: palette,
        parentViewId: collection.collectionView.id,
        showGrouping: layout == AlbumWallLayout.timeline,
        onSlideshow: () => _open(
          context,
          controller,
          palette,
          controller.visual.first.id,
          slideshow: true,
        ),
      ),
      child: child,
    );
  }

  Widget _buildWall(
    BuildContext context,
    AlbumController controller,
    CollectionPalette palette,
  ) {
    switch (layout) {
      case AlbumWallLayout.grid:
        return _AlbumGrid(
          items: controller.ordered,
          controller: controller,
          palette: palette,
          onOpen: (id) => _open(context, controller, palette, id),
          onContextMenu: (item, position) =>
              _itemMenu(context, controller, palette, item, position),
        );
      case AlbumWallLayout.masonry:
        return _AlbumMasonry(
          items: controller.ordered,
          controller: controller,
          palette: palette,
          onOpen: (id) => _open(context, controller, palette, id),
          onContextMenu: (item, position) =>
              _itemMenu(context, controller, palette, item, position),
        );
      case AlbumWallLayout.timeline:
        return _AlbumTimeline(
          controller: controller,
          palette: palette,
          onOpen: (id) => _open(context, controller, palette, id),
          onContextMenu: (item, position) =>
              _itemMenu(context, controller, palette, item, position),
        );
    }
  }

  void _itemMenu(
    BuildContext context,
    AlbumController controller,
    CollectionPalette palette,
    AlbumMediaItem item,
    Offset position,
  ) {
    showAlbumItemMenu(
      context: context,
      globalPosition: position,
      controller: controller,
      palette: palette,
      item: item,
      onOpen: () => _open(context, controller, palette, item.id),
      onOpenInfo: () =>
          _open(context, controller, palette, item.id, showInfo: true),
      onSlideshowFromHere: () =>
          _open(context, controller, palette, item.id, slideshow: true),
      onOpenInWorkspace: (value) => collection.onOpen(value.view),
    );
  }

  void _open(
    BuildContext context,
    AlbumController controller,
    CollectionPalette palette,
    String id, {
    bool slideshow = false,
    bool showInfo = false,
  }) {
    showAlbumLightbox(
      context: context,
      controller: controller,
      palette: palette,
      startId: id,
      startSlideshow: slideshow,
      startWithInfo: showInfo,
      onOpenInWorkspace: (item) => collection.onOpen(item.view),
    );
  }
}

/// Columns that fit the target tile width without leaving a ragged edge.
int albumColumnsFor(double available, double target) {
  if (!available.isFinite || available <= 0) {
    return 1;
  }
  final columns =
      ((available + AlbumMetrics.spacing) / (target + AlbumMetrics.spacing))
          .round();
  return math.max(1, columns);
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({
    required this.items,
    required this.controller,
    required this.palette,
    required this.onOpen,
    required this.onContextMenu,
  });

  final List<AlbumMediaItem> items;
  final AlbumController controller;
  final CollectionPalette palette;
  final ValueChanged<String> onOpen;
  final void Function(AlbumMediaItem item, Offset position) onContextMenu;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = albumColumnsFor(
          constraints.maxWidth,
          controller.settings.tileSize.targetWidth,
        );
        final tileWidth =
            (constraints.maxWidth - AlbumMetrics.spacing * (columns - 1)) /
                columns;
        return GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AlbumMetrics.spacing,
            crossAxisSpacing: AlbumMetrics.spacing,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) => AlbumTile(
            item: items[index],
            palette: palette,
            controller: controller,
            decodeWidth: tileWidth,
            showName: controller.settings.showNames,
            onOpen: () => onOpen(items[index].id),
            onContextMenu: onContextMenu,
          ),
        );
      },
    );
  }
}

class _AlbumMasonry extends StatelessWidget {
  const _AlbumMasonry({
    required this.items,
    required this.controller,
    required this.palette,
    required this.onOpen,
    required this.onContextMenu,
  });

  final List<AlbumMediaItem> items;
  final AlbumController controller;
  final CollectionPalette palette;
  final ValueChanged<String> onOpen;
  final void Function(AlbumMediaItem item, Offset position) onContextMenu;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = albumColumnsFor(
          constraints.maxWidth,
          controller.settings.tileSize.targetWidth,
        );
        final tileWidth =
            (constraints.maxWidth - AlbumMetrics.spacing * (columns - 1)) /
                columns;
        return MasonryGridView.count(
          padding: EdgeInsets.zero,
          crossAxisCount: columns,
          mainAxisSpacing: AlbumMetrics.spacing,
          crossAxisSpacing: AlbumMetrics.spacing,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final metadata = controller.metadataFor(item);
            // The shape comes from the header, so the wall settles as soon as
            // the metadata pass reaches each picture.
            final ratio = item.kind == AlbumMediaKind.audio
                ? 1.0
                : metadata.aspectRatio.clamp(0.5, 2.2);
            return SizedBox(
              height: tileWidth / ratio,
              child: AlbumTile(
                item: item,
                palette: palette,
                controller: controller,
                decodeWidth: tileWidth,
                showName: controller.settings.showNames,
                onOpen: () => onOpen(item.id),
                onContextMenu: onContextMenu,
              ),
            );
          },
        );
      },
    );
  }
}

class _AlbumTimeline extends StatelessWidget {
  const _AlbumTimeline({
    required this.controller,
    required this.palette,
    required this.onOpen,
    required this.onContextMenu,
  });

  final AlbumController controller;
  final CollectionPalette palette;
  final ValueChanged<String> onOpen;
  final void Function(AlbumMediaItem item, Offset position) onContextMenu;

  @override
  Widget build(BuildContext context) {
    final groups = controller.groups();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = albumColumnsFor(
          constraints.maxWidth,
          controller.settings.tileSize.targetWidth,
        );
        final tileWidth =
            (constraints.maxWidth - AlbumMetrics.spacing * (columns - 1)) /
                columns;
        return CustomScrollView(
          slivers: [
            for (final group in groups) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 18, 0, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        albumGroupHeading(
                          group.date,
                          controller.settings.grouping,
                        ),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        group.items.length == 1
                            ? LocaleKeys.collections_album_onePhoto.tr()
                            : LocaleKeys.collections_album_itemCount
                                .tr(args: ['${group.items.length}']),
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: AlbumMetrics.spacing,
                  crossAxisSpacing: AlbumMetrics.spacing,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = group.items[index];
                    return AlbumTile(
                      item: item,
                      palette: palette,
                      controller: controller,
                      decodeWidth: tileWidth,
                      showName: controller.settings.showNames,
                      onOpen: () => onOpen(item.id),
                      onContextMenu: onContextMenu,
                    );
                  },
                  childCount: group.items.length,
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        );
      },
    );
  }
}
