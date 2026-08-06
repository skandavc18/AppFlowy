import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/slides/slide_property_view.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/shared/table_views/row_page_text.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:easy_localization/easy_localization.dart';
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

  Widget _buildBody(SlidePalette palette) {
    final card = widget.card;
    final properties = card.filled;
    final hero = card.coverUrl ?? _heroFrom(properties);
    final rest = properties
        .where(
          (property) => !(hero != null &&
              property.kind == SlidePropertyKind.image &&
              property.value.contains(hero)),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hero != null) _buildCover(palette, hero),
        Padding(
          padding: EdgeInsets.fromLTRB(
            SlideMetrics.cardPadding,
            hero == null ? SlideMetrics.cardPadding : 18,
            SlideMetrics.cardPadding,
            14,
          ),
          child: _buildHead(palette, showIcon: hero == null),
        ),
        Expanded(
          child: widget.showPageContent
              ? _buildPage(palette, rest)
              : rest.isEmpty
                  ? _buildEmpty(palette)
                  : _buildProperties(palette, rest),
        ),
        _buildFooter(palette),
      ],
    );
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
                child: RowPageTextView(
                  documentId: widget.card.documentId,
                  builder: (context, read) {
                    final text = read?.trim() ?? '';
                    if (text.isEmpty) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          LocaleKeys.slides_pageEmpty.tr(),
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textMuted,
                          ),
                        ),
                      );
                    }
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        text,
                        overflow: TextOverflow.fade,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.62,
                          color: palette.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCover(SlidePalette palette, String url) {
    return SizedBox(
      height: SlideMetrics.coverHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.live
              ? SlidePicture(url: url, palette: palette)
              : ColoredBox(color: palette.raised),
          // A scrim so an emoji or a bright picture never fights the title.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.surface.withValues(alpha: 0),
                  palette.surface.withValues(alpha: 0.92),
                ],
                stops: const [0.45, 1],
              ),
            ),
          ),
          if (widget.card.icon != null)
            Positioned(
              left: SlideMetrics.cardPadding,
              bottom: -SlideMetrics.iconSize / 3,
              child: _buildIcon(palette),
            ),
        ],
      ),
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
        borderRadius: BorderRadius.circular(11),
        boxShadow: palette.chromeShadow,
      ),
      child: Text(
        icon,
        style: const TextStyle(fontSize: 21, height: 1),
      ),
    );
  }

  Widget _buildHead(SlidePalette palette, {required bool showIcon}) {
    final card = widget.card;
    final accent =
        card.accent.isEmpty ? palette.accent : palette.swatchFor(card.accent);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showIcon && card.icon != null) ...[
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.22,
                  letterSpacing: -0.4,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              if (card.subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        card.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
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
          style: TextStyle(fontSize: 20, color: palette.textMuted),
        ),
      );

  Widget _buildFooter(SlidePalette palette) {
    final modified = widget.card.lastModified;
    if (modified == null) {
      return const SizedBox(height: SlideMetrics.cardPadding);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SlideMetrics.cardPadding,
        0,
        SlideMetrics.cardPadding,
        16,
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 12,
            color: palette.textMuted.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 6),
          Text(
            _agoOf(modified),
            style: TextStyle(fontSize: 11.5, color: palette.textMuted),
          ),
        ],
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
