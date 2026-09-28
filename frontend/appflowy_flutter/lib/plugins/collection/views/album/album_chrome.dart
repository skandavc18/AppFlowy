import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/collection_workspace_surface.dart';
import 'package:appflowy/plugins/collection/views/album/album_thumbnail.dart';
import 'package:appflowy/plugins/collection/views/collection_page_scroll_scope.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

abstract final class AlbumMetrics {
  static const toolbarHeight = 44.0;
  static const gutter = CollectionWorkspaceMetrics.gutter;
  static const spacing = 10.0;
  static const tileRadius = WorkspaceTokens.cardRadius;
  static const motion = Duration(milliseconds: 180);
  static const curve = Curves.easeOutCubic;
}

String albumSortLabel(AlbumSort sort) => switch (sort) {
      AlbumSort.newestFirst =>
        LocaleKeys.collections_album_sorts_newestFirst.tr(),
      AlbumSort.oldestFirst =>
        LocaleKeys.collections_album_sorts_oldestFirst.tr(),
      AlbumSort.name => LocaleKeys.collections_album_sorts_name.tr(),
      AlbumSort.albumOrder =>
        LocaleKeys.collections_album_sorts_albumOrder.tr(),
    };

String albumGroupingLabel(AlbumGrouping grouping) => switch (grouping) {
      AlbumGrouping.none => LocaleKeys.collections_album_groups_none.tr(),
      AlbumGrouping.day => LocaleKeys.collections_album_groups_day.tr(),
      AlbumGrouping.month => LocaleKeys.collections_album_groups_month.tr(),
      AlbumGrouping.year => LocaleKeys.collections_album_groups_year.tr(),
    };

String albumTileSizeLabel(AlbumTileSize size) => switch (size) {
      AlbumTileSize.small => LocaleKeys.collections_album_tileSizes_small.tr(),
      AlbumTileSize.medium =>
        LocaleKeys.collections_album_tileSizes_medium.tr(),
      AlbumTileSize.large => LocaleKeys.collections_album_tileSizes_large.tr(),
    };

String albumTransitionLabel(AlbumSlideshowTransition transition) =>
    switch (transition) {
      AlbumSlideshowTransition.none =>
        LocaleKeys.collections_album_transitions_none.tr(),
      AlbumSlideshowTransition.fade =>
        LocaleKeys.collections_album_transitions_fade.tr(),
      AlbumSlideshowTransition.slide =>
        LocaleKeys.collections_album_transitions_slide.tr(),
      AlbumSlideshowTransition.zoom =>
        LocaleKeys.collections_album_transitions_zoom.tr(),
    };

/// "12 photos · 3 videos", skipping whatever the album does not hold.
String albumContentsSummary(AlbumController controller) {
  final parts = <String>[];
  if (controller.imageCount > 0) {
    parts.add(
      controller.imageCount == 1
          ? LocaleKeys.collections_album_onePhoto.tr()
          : LocaleKeys.collections_album_photoCount
              .tr(args: ['${controller.imageCount}']),
    );
  }
  if (controller.videoCount > 0) {
    parts.add(
      controller.videoCount == 1
          ? LocaleKeys.collections_album_oneVideo.tr()
          : LocaleKeys.collections_album_videoCount
              .tr(args: ['${controller.videoCount}']),
    );
  }
  if (controller.audioCount > 0) {
    parts.add(
      controller.audioCount == 1
          ? LocaleKeys.collections_album_oneAudio.tr()
          : LocaleKeys.collections_album_audioCount
              .tr(args: ['${controller.audioCount}']),
    );
  }
  return parts.join('  ·  ');
}

String albumGroupHeading(DateTime? date, AlbumGrouping grouping) {
  if (date == null) {
    return LocaleKeys.collections_album_undated.tr();
  }
  return switch (grouping) {
    AlbumGrouping.year => DateFormat.y().format(date),
    AlbumGrouping.month => DateFormat.yMMMM().format(date),
    AlbumGrouping.day || AlbumGrouping.none => DateFormat.yMMMMd().format(date),
  };
}

String albumFileSizeLabel(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}

/// The chrome every album view wears: one strip of controls above the media.
class AlbumScaffold extends StatelessWidget {
  const AlbumScaffold({
    super.key,
    required this.controller,
    required this.palette,
    required this.child,
    this.leading = const <Widget>[],
    this.trailing = const <Widget>[],
    this.padded = true,
    this.sliverBody = false,
    this.scrollKey,
  });

  final AlbumController controller;
  final CollectionPalette palette;
  final Widget child;
  final List<Widget> leading;
  final List<Widget> trailing;
  final bool padded;
  final bool sliverBody;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) {
    final toolbar = CollectionWorkspaceToolbar(
      identity: Text(
        albumContentsSummary(controller),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: collectionWorkspaceLabel(context, size: 12),
      ),
      keepVisible: true,
      actions: [...leading, ...trailing],
    );
    if (sliverBody) {
      return PreviewToolbarRegion(
        child: CollectionWorkspaceSurface(
          padding: EdgeInsets.zero,
          child: PremiumScrollScope(
            enabled: true,
            child: FileBrowserScrollView(
              controller: CollectionPageScrollScope.maybeOf(context),
              scrollKey: scrollKey,
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (FileBrowserPageHeader.maybeOf(context) case final header?)
                    header,
                  const SizedBox(height: CollectionWorkspaceMetrics.topGap),
                  toolbar,
                ],
              ),
              slivers: [
                SliverPadding(
                  padding: padded
                      ? CollectionWorkspaceMetrics.bodyInsets
                      : EdgeInsets.zero,
                  sliver: child,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return PreviewToolbarRegion(
      child: CollectionWorkspaceSurface(
        padding: EdgeInsets.zero,
        child: FileBrowserScrollView(
          controller: CollectionPageScrollScope.maybeOf(context),
          scrollKey: scrollKey,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (FileBrowserPageHeader.maybeOf(context) case final header?)
                header,
              const SizedBox(height: CollectionWorkspaceMetrics.topGap),
              toolbar,
            ],
          ),
          slivers: [
            // Filmstrip and Places remain finite stages. Only their chrome
            // scrolls away; neither images nor the horizontal shelf become
            // unbounded or borrow the primary vertical controller.
            SliverLayoutBuilder(
              builder: (context, constraints) => SliverToBoxAdapter(
                child: SizedBox(
                  height: constraints.viewportMainAxisExtent,
                  child: Padding(
                    padding: padded
                        ? CollectionWorkspaceMetrics.bodyInsets
                        : EdgeInsets.zero,
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AlbumToolbarButton extends StatelessWidget {
  const AlbumToolbarButton({
    super.key,
    required this.palette,
    required this.icon,
    required this.tooltip,
    this.label,
    this.onPressed,
    this.selected = false,
  });

  final CollectionPalette palette;
  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => CollectionWorkspaceAction(
        icon: icon,
        tooltip: tooltip,
        label: label,
        onPressed: onPressed,
        selected: selected,
        color: palette.textSecondary,
      );
}

/// The sort, grouping and tile size controls, shared by the wall views.
List<Widget> albumArrangementControls({
  required BuildContext context,
  required AlbumController controller,
  required CollectionPalette palette,
  bool showGrouping = false,
  bool showTileSize = true,
}) {
  Future<void> pick<T>({
    required List<T> values,
    required T selected,
    required String Function(T value) labelOf,
    required ValueChanged<T> onSelected,
    required Offset position,
  }) async {
    final choice = await showAppMenu<T>(
      context: context,
      globalPosition: position,
      entries: [
        for (final value in values)
          AppMenuItem(
            label: labelOf(value),
            value: value,
            selected: value == selected,
          ),
      ],
    );
    if (choice != null) {
      onSelected(choice);
    }
  }

  return [
    _AnchoredControl(
      builder: (anchor, open) => AlbumToolbarButton(
        key: anchor,
        palette: palette,
        icon: Icons.swap_vert_rounded,
        tooltip: LocaleKeys.collections_album_sort.tr(),
        label: albumSortLabel(controller.settings.sort),
        onPressed: () => open(
          (position) => pick<AlbumSort>(
            values: AlbumSort.values,
            selected: controller.settings.sort,
            labelOf: albumSortLabel,
            position: position,
            onSelected: (value) => controller
                .updateSettings(controller.settings.copyWith(sort: value)),
          ),
        ),
      ),
    ),
    if (showGrouping)
      _AnchoredControl(
        builder: (anchor, open) => AlbumToolbarButton(
          key: anchor,
          palette: palette,
          icon: Icons.calendar_month_rounded,
          tooltip: LocaleKeys.collections_album_group.tr(),
          label: albumGroupingLabel(controller.settings.grouping),
          onPressed: () => open(
            (position) => pick<AlbumGrouping>(
              values: AlbumGrouping.values,
              selected: controller.settings.grouping,
              labelOf: albumGroupingLabel,
              position: position,
              onSelected: (value) => controller.updateSettings(
                controller.settings.copyWith(grouping: value),
              ),
            ),
          ),
        ),
      ),
    if (showTileSize)
      _AnchoredControl(
        builder: (anchor, open) => AlbumToolbarButton(
          key: anchor,
          palette: palette,
          icon: Icons.grid_view_rounded,
          tooltip: LocaleKeys.collections_album_tileSize.tr(),
          onPressed: () => open(
            (position) => pick<AlbumTileSize>(
              values: AlbumTileSize.values,
              selected: controller.settings.tileSize,
              labelOf: albumTileSizeLabel,
              position: position,
              onSelected: (value) => controller.updateSettings(
                controller.settings.copyWith(tileSize: value),
              ),
            ),
          ),
        ),
      ),
  ];
}

/// Opens a menu underneath whatever button asked for it.
class _AnchoredControl extends StatefulWidget {
  const _AnchoredControl({required this.builder});

  final Widget Function(
    GlobalKey anchor,
    void Function(FutureOr<void> Function(Offset)),
  ) builder;

  @override
  State<_AnchoredControl> createState() => _AnchoredControlState();
}

class _AnchoredControlState extends State<_AnchoredControl> {
  final anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => widget.builder(anchor, (open) async {
        final box = anchor.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) {
          return;
        }
        final release = PreviewToolbarRegion.hold(context);
        try {
          await open(box.localToGlobal(Offset(0, box.size.height + 4)));
        } finally {
          release();
        }
      }),
    );
  }
}

class AlbumEmptyState extends StatelessWidget {
  const AlbumEmptyState({
    super.key,
    required this.palette,
    required this.icon,
    required this.title,
    required this.description,
  });

  final CollectionPalette palette;
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkspaceGlyph(icon, size: 38, color: palette.textMuted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tile in a wall: the media, its hover state, and its star.
class AlbumTile extends StatefulWidget {
  const AlbumTile({
    super.key,
    required this.item,
    required this.palette,
    required this.controller,
    required this.onOpen,
    this.onContextMenu,
    this.decodeWidth,
    this.showName = false,
    this.selected = false,
  });

  final AlbumMediaItem item;
  final CollectionPalette palette;
  final AlbumController controller;
  final VoidCallback onOpen;
  final void Function(AlbumMediaItem item, Offset position)? onContextMenu;
  final double? decodeWidth;
  final bool showName;
  final bool selected;

  @override
  State<AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<AlbumTile> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final favourite = widget.controller.state.isFavourite(widget.item.id);
    return PreviewToolbarRegion(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => hovered = true);
          unawaitedMetadata();
        },
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen,
          onSecondaryTapDown: widget.onContextMenu == null
              ? null
              : (details) =>
                  widget.onContextMenu!(widget.item, details.globalPosition),
          child: AnimatedScale(
            duration: AlbumMetrics.motion,
            curve: AlbumMetrics.curve,
            scale: hovered ? 1.012 : 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(AlbumMetrics.tileRadius),
                    border: widget.selected
                        ? Border.all(color: palette.accent, width: 2)
                        : null,
                  ),
                  padding: widget.selected ? const EdgeInsets.all(2) : null,
                  child: AlbumThumbnail(
                    item: widget.item,
                    palette: palette,
                    decodeWidth: widget.decodeWidth,
                    radius: AlbumMetrics.tileRadius,
                  ),
                ),
                if (widget.showName)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _TileCaption(name: widget.item.name),
                  ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: PreviewToolbar(
                    keepVisible: favourite,
                    child: _StarButton(
                      favourite: favourite,
                      onTap: () =>
                          widget.controller.toggleFavourite(widget.item.id),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void unawaitedMetadata() {
    widget.controller.ensureMetadata(widget.item);
  }
}

class _TileCaption extends StatelessWidget {
  const _TileCaption({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AlbumMetrics.tileRadius),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.62),
          ],
        ),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StarButton extends StatelessWidget {
  const _StarButton({required this.favourite, required this.onTap});

  final bool favourite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: favourite
          ? LocaleKeys.collections_album_unfavourite.tr()
          : LocaleKeys.collections_album_favourite.tr(),
      onPressed: onTap,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(28),
        padding: const EdgeInsets.all(6),
        backgroundColor: Colors.black.withValues(alpha: 0.42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        ),
      ),
      icon: WorkspaceGlyph(
        Icons.star_rounded,
        size: 15,
        color: favourite ? const Color(0xFFF4C542) : Colors.white,
      ),
    );
  }
}
