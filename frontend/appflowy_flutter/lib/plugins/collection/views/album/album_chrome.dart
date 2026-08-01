import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/album/album_thumbnail.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

abstract final class AlbumMetrics {
  static const toolbarHeight = 44.0;
  static const gutter = 24.0;
  static const spacing = 10.0;
  static const tileRadius = 10.0;
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
  });

  final AlbumController controller;
  final CollectionPalette palette;
  final Widget child;
  final List<Widget> leading;
  final List<Widget> trailing;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: palette.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: AlbumMetrics.toolbarHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: AlbumMetrics.gutter,
            ),
            child: Row(
              children: [
                Text(
                  albumContentsSummary(controller),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 14),
                ...leading,
                const Spacer(),
                ...trailing,
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: padded
                  ? const EdgeInsets.fromLTRB(
                      AlbumMetrics.gutter,
                      16,
                      AlbumMetrics.gutter,
                      28,
                    )
                  : EdgeInsets.zero,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class AlbumToolbarButton extends StatefulWidget {
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
  State<AlbumToolbarButton> createState() => _AlbumToolbarButtonState();
}

class _AlbumToolbarButtonState extends State<AlbumToolbarButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final enabled = widget.onPressed != null;
    final foreground = !enabled
        ? palette.textMuted
        : widget.selected
            ? palette.accent
            : hovered
                ? palette.textPrimary
                : palette.textSecondary;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: AlbumMetrics.motion,
            curve: AlbumMetrics.curve,
            height: 28,
            margin: const EdgeInsets.only(left: 4),
            padding: EdgeInsets.symmetric(
              horizontal: widget.label == null ? 6 : 9,
            ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? palette.accentSoft
                  : hovered && enabled
                      ? palette.hover
                      : palette.hover.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: foreground),
                if (widget.label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    widget.label!,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
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
class _AnchoredControl extends StatelessWidget {
  const _AnchoredControl({required this.builder});

  final Widget Function(GlobalKey anchor, void Function(ValueChanged<Offset>))
      builder;

  @override
  Widget build(BuildContext context) {
    final anchor = GlobalKey();
    return Builder(
      builder: (context) => builder(anchor, (open) {
        final box = anchor.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) {
          return;
        }
        open(box.localToGlobal(Offset(0, box.size.height + 4)));
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
            Icon(icon, size: 38, color: palette.textMuted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
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
    return MouseRegion(
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
                  borderRadius: BorderRadius.circular(AlbumMetrics.tileRadius),
                  border: widget.selected
                      ? Border.all(color: palette.accent, width: 2)
                      : null,
                ),
                padding: widget.selected ? const EdgeInsets.all(2) : null,
                child: AlbumThumbnail(
                  item: widget.item,
                  palette: palette,
                  decodeWidth: widget.decodeWidth,
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
                child: AnimatedOpacity(
                  duration: AlbumMetrics.motion,
                  opacity: hovered || favourite ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !(hovered || favourite),
                    child: _StarButton(
                      favourite: favourite,
                      onTap: () =>
                          widget.controller.toggleFavourite(widget.item.id),
                    ),
                  ),
                ),
              ),
            ],
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
    return Tooltip(
      message: favourite
          ? LocaleKeys.collections_album_unfavourite.tr()
          : LocaleKeys.collections_album_favourite.tr(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              shape: BoxShape.circle,
            ),
            child: Icon(
              favourite ? Icons.star_rounded : Icons.star_border_rounded,
              size: 15,
              color: favourite ? const Color(0xFFF4C542) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
