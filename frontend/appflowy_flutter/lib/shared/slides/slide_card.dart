import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/slides/slide_property_view.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/shared/table_views/property_values.dart';
import 'package:appflowy/shared/table_views/row_page_preview.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart'
    show TableCoverView;
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart'
    show TableCover, TableCoverKind;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// One row, drawn as something worth looking at.
///
/// The arrangement is decided by what the row actually holds: a picture takes
/// the head, long writing takes a whole line, and the short facts pair up. Two
/// rows of the same table therefore rarely read the same, which is the point.
class SlideCard extends StatefulWidget {
  const SlideCard({
    super.key,
    required this.card,
    required this.palette,
    required this.size,
    this.prominence = 1,
    this.live = false,
    this.showPageContent = false,
    this.viewId = '',
    this.onOpen,
    this.onEdit,
    this.onContextMenu,
  });

  final SlideCardData card;
  final SlidePalette palette;
  final Size size;

  /// How near the middle of the deck this slide is, from 0 to 1.
  final double prominence;

  /// Whether this is the slide being read.
  final bool live;

  /// Whether the writing on the row's own page is read on the slide.
  final bool showPageContent;

  /// The table the row belongs to, so attached files can be read.
  final String viewId;

  final VoidCallback? onOpen;
  final VoidCallback? onEdit;
  final void Function(Offset globalPosition)? onContextMenu;

  @override
  State<SlideCard> createState() => _SlideCardState();
}

class _SlideCardState extends State<SlideCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final lift = _hovered && widget.live ? SlideMetrics.hoverLift : 0.0;

    return MouseRegion(
      opaque: false,
      cursor:
          widget.onOpen == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        onDoubleTap: widget.onEdit,
        onSecondaryTapUp: widget.onContextMenu == null
            ? null
            : (details) => widget.onContextMenu!(details.globalPosition),
        child: AnimatedContainer(
          duration: SlideMetrics.hover,
          curve: SlideMetrics.enterCurve,
          transform: Matrix4.translationValues(0, -lift, 0),
          width: widget.size.width,
          height: widget.size.height,
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(SlideMetrics.cardRadius),
            boxShadow: palette.cardShadow(widget.prominence, lift: lift),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SlideMetrics.cardRadius),
            child: _buildBody(palette),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered != hovered && mounted) {
      setState(() => _hovered = hovered);
    }
  }

  /// What a short slide keeps back for its facts before the head is trimmed.
  static const double _minimumBody = 56;
  static const double _footerHeight = 34;

  Widget _buildBody(SlidePalette palette) {
    final card = widget.card;
    final properties = card.filled;
    final picture = card.cover == null ? _heroFrom(properties) : null;
    final cover = card.cover ??
        (picture == null
            ? card.fallbackCover
            : TableCover(kind: TableCoverKind.picture, value: picture));
    final hero = cover?.kind == TableCoverKind.picture ? cover!.value : null;
    final lead = _leadOf(properties);
    final rest = properties
        .where(
          (property) =>
              !identical(property, lead) &&
              !(hero != null &&
                  !property.isMedia &&
                  property.kind == SlidePropertyKind.image &&
                  property.value.contains(hero)),
        )
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        // A short deck gives up the cover's height, the title's second line
        // and the footer, in that order, rather than spilling out of the card.
        final tight = height < 380;
        final coverHeight =
            cover == null ? 0.0 : _coverHeightFor(cover, height);
        final showFooter = !tight && card.lastModified != null;
        final headRoom = math.max(
          0.0,
          height -
              coverHeight -
              (showFooter ? _footerHeight : 12) -
              _minimumBody,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cover != null)
              SizedBox(
                height: coverHeight,
                child: _buildCover(palette, cover),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: headRoom),
              // Trims a head that cannot fit instead of overflowing the card,
              // without adding a scroll view the facts below would share.
              child: UnconstrainedBox(
                constrainedAxis: Axis.horizontal,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: _buildHead(
                  palette,
                  lead: lead,
                  hasCover: cover != null,
                  tight: tight,
                ),
              ),
            ),
            Expanded(
              child: widget.showPageContent
                  ? _buildPage(palette, rest)
                  : rest.isEmpty
                      ? _buildEmpty(palette)
                      : _buildProperties(palette, rest),
            ),
            if (showFooter)
              _buildFooter(palette, card.lastModified!)
            else
              const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  /// A picture earns the most room; a colour or gradient is a band.
  static double _coverHeightFor(TableCover cover, double height) {
    final band = cover.kind == TableCoverKind.colour ||
        cover.kind == TableCoverKind.gradient;
    return band
        ? math.min(SlideMetrics.bandHeight, height * 0.18)
        : math.min(SlideMetrics.coverHeight, height * 0.3);
  }

  /// The status (or the people) shown under the title, and so not repeated
  /// among the facts below it.
  SlideProperty? _leadOf(List<SlideProperty> properties) {
    if (widget.card.subtitle.isEmpty) {
      return null;
    }
    for (final property in properties) {
      if (property.kind == SlidePropertyKind.badge ||
          property.kind == SlidePropertyKind.person) {
        return property.value == widget.card.subtitle ? property : null;
      }
    }
    return null;
  }

  /// The row's own page, with the short facts kept above it.
  Widget _buildPage(SlidePalette palette, List<SlideProperty> properties) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (properties.isNotEmpty)
              ConstrainedBox(
                // The facts take only what they need, up to their share; the
                // page is what the rest of the slide is for.
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.42,
                ),
                child: _buildProperties(palette, properties),
              ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(
                  SlideMetrics.cardPadding,
                  0,
                  SlideMetrics.cardPadding,
                  4,
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                decoration: BoxDecoration(
                  color: palette.sunken.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: RowPagePreview(
                  documentId: widget.card.documentId,
                  scale: 0.72,
                  emptyBuilder: (context) => Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      LocaleKeys.slides_pageEmpty.tr(),
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                  textBuilder: (context, text) => Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      text ?? '',
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.62,
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCover(SlidePalette palette, TableCover cover) {
    final picture = cover.kind == TableCoverKind.picture ||
        cover.kind == TableCoverKind.asset;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        // Only a fetched picture waits for the slide in front; a bundled one,
        // a colour or a gradient costs nothing to draw on every slide.
        if (widget.live || cover.kind != TableCoverKind.picture)
          TableCoverView(cover: cover, palette: palette)
        else
          PropertyPicturePlaceholder(ink: palette),
        if (picture)
          // A soft foot so a bright picture settles into the slide.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    palette.surface.withValues(alpha: 0),
                    palette.surface.withValues(alpha: 0.4),
                  ],
                  stops: const [0.6, 1],
                ),
              ),
            ),
          ),
        if (widget.card.icon != null)
          Positioned(
            left: SlideMetrics.cardPadding,
            bottom: -SlideMetrics.iconSize / 2,
            child: _buildIcon(palette),
          ),
      ],
    );
  }

  Widget _buildIcon(SlidePalette palette) {
    final icon = widget.card.icon;
    if (icon == null || icon.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: SlideMetrics.iconSize,
      height: SlideMetrics.iconSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: palette.chromeShadow,
      ),
      child: Text(
        icon,
        style: const TextStyle(fontSize: 22, height: 1),
      ),
    );
  }

  Widget _buildHead(
    SlidePalette palette, {
    required SlideProperty? lead,
    required bool hasCover,
    required bool tight,
  }) {
    final card = widget.card;
    final accent =
        card.accent.isEmpty ? palette.accent : palette.swatchFor(card.accent);
    final iconOnCover = hasCover && card.icon != null;
    final top = iconOnCover
        ? SlideMetrics.iconSize / 2 + 10
        : hasCover
            ? 16.0
            : (tight ? 18.0 : SlideMetrics.cardPadding);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        SlideMetrics.cardPadding,
        top,
        SlideMetrics.cardPadding,
        tight ? 8 : 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasCover && card.icon != null) ...[
            _buildIcon(palette),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  card.title.trim().isEmpty ? '—' : card.title,
                  maxLines: tight ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: tight ? 20 : 24,
                    height: 1.2,
                    letterSpacing: -0.5,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                if (card.subtitle.isNotEmpty) ...[
                  SizedBox(height: tight ? 6 : 9),
                  if (lead?.kind == SlidePropertyKind.person)
                    PropertyPeople(
                      names: slidePartsOf(card.subtitle),
                      initialsOf: slideInitialsOf,
                      ink: palette,
                    )
                  else
                    PropertyPill(
                      label: card.subtitle,
                      colour: accent,
                      ink: palette,
                      dense: true,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProperties(
    SlidePalette palette,
    List<SlideProperty> properties,
  ) {
    final rows = <Widget>[];
    var pending = <SlideProperty>[];

    void flushPending() {
      if (pending.isEmpty) {
        return;
      }
      final pair = pending;
      pending = <SlideProperty>[];
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < pair.length; i++) ...[
              if (i > 0) const SizedBox(width: SlideMetrics.propertyGap),
              Expanded(
                child: SlidePropertyView(
                  property: pair[i],
                  palette: palette,
                  live: widget.live,
                  viewId: widget.viewId,
                  rowId: widget.card.rowId,
                ),
              ),
            ],
            // A lone short fact keeps to its half so the column stays straight.
            if (pair.length == 1) ...[
              const SizedBox(width: SlideMetrics.propertyGap),
              const Expanded(child: SizedBox.shrink()),
            ],
          ],
        ),
      );
    }

    for (final property in properties) {
      if (property.isWide) {
        flushPending();
        rows.add(
          SlidePropertyView(
            property: property,
            palette: palette,
            live: widget.live,
            viewId: widget.viewId,
            rowId: widget.card.rowId,
          ),
        );
        continue;
      }
      pending.add(property);
      if (pending.length == 2) {
        flushPending();
      }
    }
    flushPending();

    return Listener(
      // Let the scrollable (or an embedded map) consume a wheel first, but
      // keep vertical input here even at its edge. Reaching the bottom of a
      // property list must not unexpectedly turn the next wheel into a slide.
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()) {
          GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
        }
      },
      child: _propertyScroller(rows),
    );
  }

  Widget _propertyScroller(List<Widget> rows) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.fromLTRB(
          SlideMetrics.cardPadding,
          2,
          SlideMetrics.cardPadding,
          10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: SlideMetrics.propertyGap),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(SlidePalette palette) => Center(
        child: Text(
          '—',
          style: TextStyle(
            fontSize: 18,
            color: palette.textMuted.withValues(alpha: 0.6),
          ),
        ),
      );

  Widget _buildFooter(SlidePalette palette, DateTime modified) {
    return SizedBox(
      height: _footerHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SlideMetrics.cardPadding,
          4,
          SlideMetrics.cardPadding,
          12,
        ),
        child: Row(
          children: [
            WorkspaceGlyph(
              Icons.schedule_rounded,
              size: 13,
              color: palette.textMuted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _agoOf(modified),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: palette.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The first picture on the slide stands in for a cover when there is none.
  String? _heroFrom(List<SlideProperty> properties) {
    for (final property in properties) {
      if (property.kind != SlidePropertyKind.image) {
        continue;
      }
      for (final part in slidePartsOf(property.value)) {
        if (looksLikeSlideImage(part)) {
          return part;
        }
      }
    }
    return null;
  }

  static String _agoOf(DateTime when) {
    final gap = DateTime.now().difference(when);
    if (gap.inMinutes < 1) {
      return 'just now';
    }
    if (gap.inHours < 1) {
      return '${gap.inMinutes}m ago';
    }
    if (gap.inDays < 1) {
      return '${gap.inHours}h ago';
    }
    if (gap.inDays < 30) {
      return '${gap.inDays}d ago';
    }
    return '${when.year}-${_two(when.month)}-${_two(when.day)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
