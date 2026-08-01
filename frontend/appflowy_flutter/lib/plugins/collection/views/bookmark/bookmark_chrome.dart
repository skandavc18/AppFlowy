import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/text_rendering.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:flutter/material.dart';

/// The fixed geometry and motion a bookmark library is drawn to.
abstract final class BookmarkMetrics {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;

  static const double gutter = 24;
  static const double toolbarHeight = 40;
  static const double railWidth = 232;

  /// The measure a feed or an article is laid out to.
  static const double readingWidth = 820;
  static const double feedWidth = 940;

  /// Cards.
  static const double cardRadius = EditorSurfaceStyle.embedCornerRadius;
  static const double coverRatio = 16 / 9;
  static const double controlRadius = 9;
  static const double chipRadius = 999;
  static const double faviconSize = 16;

  /// Rows.
  static const double feedRowHeight = 112;
  static const double feedThumbWidth = 168;
  static const double shelfCardWidth = 208;
  static const double timelineRailWidth = 96;
  static const double timelineDotSize = 9;

  /// Typography.
  static const double titleSize = 14.5;
  static const double bodySize = 12.5;
  static const double metaSize = 11.5;
  static const double sectionSize = 10.5;
  static const double tracking = -0.006;
  static const double sectionTracking = 0.07;
  static const double bodyWeightAxis = 545;
  static const double strongWeightAxis = 620;
  static const double sectionWeightAxis = 640;

  static const Duration hover = Duration(milliseconds: 140);
  static const Duration reveal = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;
}

/// Every colour a bookmark library draws with.
@immutable
class BookmarkTheme {
  const BookmarkTheme._({
    required this.palette,
    required this.brightness,
    required this.canvas,
    required this.panel,
    required this.raised,
    required this.sunken,
    required this.hover,
    required this.selected,
    required this.textStrong,
    required this.textBody,
    required this.textSoft,
    required this.textFaint,
    required this.iconRest,
    required this.accent,
    required this.accentSoft,
    required this.accentBorder,
    required this.baseTextStyle,
  });

  factory BookmarkTheme.of(BuildContext context, CollectionPalette palette) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return BookmarkTheme._(
      palette: palette,
      brightness: theme.brightness,
      canvas: palette.background,
      panel: palette.surface,
      raised: palette.floatingSurface,
      sunken: Color.alphaBlend(
        palette.hover.withValues(alpha: isDark ? 0.42 : 0.6),
        palette.background,
      ),
      hover: palette.hover.withValues(alpha: isDark ? 0.62 : 0.8),
      selected: palette.accent.withValues(alpha: isDark ? 0.16 : 0.10),
      textStrong: palette.textPrimary,
      textBody: Color.lerp(palette.textSecondary, palette.textPrimary, 0.5)!,
      textSoft: palette.textSecondary,
      textFaint: palette.textMuted,
      iconRest: palette.textMuted.withValues(alpha: isDark ? 0.92 : 0.86),
      accent: palette.accent,
      accentSoft: palette.accentSoft,
      accentBorder: palette.accentBorder,
      baseTextStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
    );
  }

  final CollectionPalette palette;
  final Brightness brightness;
  final Color canvas;
  final Color panel;
  final Color raised;
  final Color sunken;
  final Color hover;
  final Color selected;
  final Color textStrong;
  final Color textBody;
  final Color textSoft;
  final Color textFaint;
  final Color iconRest;
  final Color accent;
  final Color accentSoft;
  final Color accentBorder;
  final TextStyle baseTextStyle;

  bool get isDark => brightness == Brightness.dark;

  /// A transparent stand-in that keeps a colour's own channels, so a hover
  /// tween never passes through transparent black.
  Color transparentAs(Color color) => color.withValues(alpha: 0);

  List<Shadow> get _underprint =>
      AppTextRendering.rootStyleFor(brightness).shadows ?? const [];

  TextStyle face({
    required double fontSize,
    required Color color,
    double axis = BookmarkMetrics.bodyWeightAxis,
    FontWeight weight = FontWeight.w500,
    double tracking = BookmarkMetrics.tracking,
    double height = 1.0,
  }) =>
      AppTextRendering.polish(
        baseTextStyle.copyWith(
          fontSize: fontSize,
          fontWeight: weight,
          fontVariations: [FontVariation.weight(axis)],
          height: height,
          letterSpacing: fontSize * tracking,
          color: color,
          shadows: _underprint,
          decoration: TextDecoration.none,
        ),
      );

  TextStyle get cardTitle => face(
        fontSize: BookmarkMetrics.titleSize,
        color: textStrong,
        axis: BookmarkMetrics.strongWeightAxis,
        weight: FontWeight.w600,
        height: 1.32,
      );

  TextStyle get body => face(
        fontSize: BookmarkMetrics.bodySize,
        color: textSoft,
        axis: 500,
        weight: FontWeight.w400,
        height: 1.45,
      );

  TextStyle get meta => face(
        fontSize: BookmarkMetrics.metaSize,
        color: textFaint,
        axis: 500,
        weight: FontWeight.w400,
      );

  TextStyle get metaStrong => meta.copyWith(color: textSoft);

  TextStyle get sectionLabel => face(
        fontSize: BookmarkMetrics.sectionSize,
        color: textFaint,
        axis: BookmarkMetrics.sectionWeightAxis,
        weight: FontWeight.w600,
        tracking: BookmarkMetrics.sectionTracking,
      );
}

/// A region of the library, drawn as the application's own card.
class BookmarkPanel extends StatelessWidget {
  const BookmarkPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.elevation = ViewerCardElevation.resting,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final ViewerCardElevation elevation;
  final Color? color;

  @override
  Widget build(BuildContext context) => ViewerCard(
        reactsToPointer: false,
        elevation: elevation,
        // The card shadow is drawn behind the whole rounded rect, so a
        // surface that is left transparent shows the blur through itself.
        color: color ?? bookmarkThemeOf(context).panel,
        child: Padding(padding: padding, child: child),
      );
}

/// The whitespace between one region and the next. Nothing is separated by a
/// drawn line.
class BookmarkGap extends StatelessWidget {
  const BookmarkGap({super.key, this.size = BookmarkMetrics.space3});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}

/// A borderless control: the toolbar buttons, the card actions, the menus.
class BookmarkAction extends StatefulWidget {
  const BookmarkAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.theme,
    this.label,
    this.onPressed,
    this.active = false,
    this.size = 28,
  });

  final IconData icon;
  final String tooltip;
  final BookmarkTheme theme;
  final String? label;
  final VoidCallback? onPressed;
  final bool active;
  final double size;

  @override
  State<BookmarkAction> createState() => _BookmarkActionState();
}

class _BookmarkActionState extends State<BookmarkAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled = widget.onPressed != null;
    final tint = widget.active
        ? theme.accent
        : enabled
            ? theme.iconRest
            : theme.textFaint.withValues(alpha: 0.5);
    final fill = widget.active
        ? theme.accent.withValues(alpha: theme.isDark ? 0.18 : 0.11)
        : _hovered
            ? theme.hover
            : theme.transparentAs(theme.hover);

    final label = widget.label;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: Opacity(
            opacity: _pressed ? 0.6 : 1,
            child: AnimatedContainer(
              duration: BookmarkMetrics.hover,
              curve: BookmarkMetrics.curve,
              height: widget.size,
              padding: EdgeInsets.symmetric(
                horizontal: label == null ? 0 : BookmarkMetrics.space2 + 2,
              ),
              constraints: BoxConstraints(
                minWidth: label == null ? widget.size : 0,
              ),
              decoration: BoxDecoration(
                color: fill,
                borderRadius:
                    BorderRadius.circular(BookmarkMetrics.controlRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 16, color: tint),
                  if (label != null) ...[
                    const SizedBox(width: BookmarkMetrics.space1 + 2),
                    Text(
                      label,
                      style: theme.face(
                        fontSize: BookmarkMetrics.metaSize + 0.5,
                        color: widget.active ? theme.accent : theme.textBody,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tag, a site or a state, shown as a soft pill.
class BookmarkChip extends StatelessWidget {
  const BookmarkChip({
    super.key,
    required this.label,
    required this.theme,
    this.icon,
    this.selected = false,
    this.count,
    this.onTap,
    this.onRemove,
  });

  final String label;
  final BookmarkTheme theme;
  final IconData? icon;
  final bool selected;
  final int? count;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? theme.accent : theme.textSoft;
    final chip = Container(
      height: 22,
      padding: EdgeInsets.only(
        left: icon == null ? BookmarkMetrics.space2 : 6,
        right: onRemove == null ? BookmarkMetrics.space2 : 4,
      ),
      decoration: BoxDecoration(
        color: selected
            ? theme.accent.withValues(alpha: theme.isDark ? 0.18 : 0.11)
            : theme.sunken,
        borderRadius: BorderRadius.circular(BookmarkMetrics.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: theme.face(
              fontSize: BookmarkMetrics.metaSize,
              color: foreground,
              axis: selected
                  ? BookmarkMetrics.strongWeightAxis
                  : BookmarkMetrics.bodyWeightAxis,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 5),
            Text(
              '$count',
              style: theme.face(
                fontSize: BookmarkMetrics.metaSize - 0.5,
                color: theme.textFaint,
                axis: 500,
                weight: FontWeight.w400,
              ),
            ),
          ],
          if (onRemove != null) ...[
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onRemove,
              child:
                  Icon(Icons.close_rounded, size: 12, color: theme.textFaint),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return chip;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: chip),
    );
  }
}

/// A site's own icon, falling back to its first letter on its own hue.
///
/// A letter tile is deliberate: a broken image icon on every card is worse
/// than no icon, and the tile is still recognisable at a glance.
class BookmarkFavicon extends StatelessWidget {
  const BookmarkFavicon({
    super.key,
    required this.entry,
    required this.theme,
    this.size = BookmarkMetrics.faviconSize,
  });

  final BookmarkEntry entry;
  final BookmarkTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final host = entry.host ?? '?';
    final fallback = _letterTile(host);
    final url = entry.metadata.faviconUrl;
    if (url == null || url.isEmpty || url.endsWith('.svg')) {
      return fallback;
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }

  Widget _letterTile(String host) {
    final hue = siteHue(host);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hue.withValues(alpha: theme.isDark ? 0.32 : 0.18),
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Text(
        host.isEmpty ? '?' : host.characters.first.toUpperCase(),
        style: theme.face(
          fontSize: size * 0.58,
          color: theme.isDark ? Color.lerp(hue, Colors.white, 0.5)! : hue,
          axis: BookmarkMetrics.sectionWeightAxis,
          weight: FontWeight.w700,
          tracking: 0,
        ),
      ),
    );
  }
}

const _siteHues = <Color>[
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFFEF4444),
  Color(0xFFF59E0B),
  Color(0xFF22C55E),
  Color(0xFF14B8A6),
  Color(0xFF6366F1),
];

/// A stable hue per site, so the same domain always reads the same colour.
Color siteHue(String host) {
  var hash = 0x811C9DC5;
  for (final unit in host.codeUnits) {
    hash = (hash ^ unit) * 0x01000193 & 0xFFFFFFFF;
  }
  return _siteHues[hash % _siteHues.length];
}

/// The illustration on a card, with a woven fallback when there is none.
class BookmarkCover extends StatelessWidget {
  const BookmarkCover({
    super.key,
    required this.entry,
    required this.theme,
    this.fit = BoxFit.cover,
  });

  final BookmarkEntry entry;
  final BookmarkTheme theme;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = entry.metadata.imageUrl;
    if (url == null || url.isEmpty) {
      return BookmarkCoverFallback(entry: entry, theme: theme);
    }
    return Image.network(
      url,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          BookmarkCoverFallback(entry: entry, theme: theme),
      frameBuilder: (context, child, frame, wasSynchronous) {
        if (wasSynchronous || frame != null) {
          return child;
        }
        return ColoredBox(color: theme.sunken, child: const SizedBox.expand());
      },
    );
  }
}

/// What a card shows when the page offered no picture: the site's own hue,
/// its initial, and nothing pretending to be a photograph.
class BookmarkCoverFallback extends StatelessWidget {
  const BookmarkCoverFallback({
    super.key,
    required this.entry,
    required this.theme,
  });

  final BookmarkEntry entry;
  final BookmarkTheme theme;

  @override
  Widget build(BuildContext context) {
    final host = entry.host ?? '';
    final hue = siteHue(host);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              hue.withValues(alpha: theme.isDark ? 0.26 : 0.15),
              theme.panel,
            ),
            Color.alphaBlend(
              hue.withValues(alpha: theme.isDark ? 0.10 : 0.06),
              theme.panel,
            ),
          ],
        ),
      ),
      child: Center(
        child: Text(
          host.isEmpty ? '—' : host.characters.first.toUpperCase(),
          style: theme.face(
            fontSize: 34,
            color: hue.withValues(alpha: theme.isDark ? 0.72 : 0.5),
            axis: 700,
            weight: FontWeight.w700,
            tracking: 0,
          ),
        ),
      ),
    );
  }
}

/// A borderless search field.
class BookmarkSearchField extends StatelessWidget {
  const BookmarkSearchField({
    super.key,
    required this.theme,
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.width,
  });

  final BookmarkTheme theme;
  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = SizedBox(
      height: 34,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        cursorColor: theme.accent,
        style: theme.face(
          fontSize: BookmarkMetrics.bodySize + 0.5,
          color: theme.textStrong,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: theme.sunken,
          hoverColor: theme.sunken,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 16,
            color: theme.textFaint,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 32),
          hintText: hintText,
          hintStyle: theme.face(
            fontSize: BookmarkMetrics.bodySize + 0.5,
            color: theme.textFaint,
          ),
          border: _border,
          enabledBorder: _border,
          focusedBorder: _border,
        ),
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }

  OutlineInputBorder get _border => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      );
}

/// What a view shows when there is nothing to show.
class BookmarkEmptyState extends StatelessWidget {
  const BookmarkEmptyState({
    super.key,
    required this.theme,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final BookmarkTheme theme;
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(BookmarkMetrics.space8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 30,
                color: theme.textFaint.withValues(alpha: 0.7),
              ),
              const SizedBox(height: BookmarkMetrics.space3),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.face(
                  fontSize: BookmarkMetrics.titleSize,
                  color: theme.textBody,
                  axis: BookmarkMetrics.strongWeightAxis,
                  weight: FontWeight.w600,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: BookmarkMetrics.space2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: theme.body,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: BookmarkMetrics.space4),
                action!,
              ],
            ],
          ),
        ),
      );
}

/// A thin overlay scrollbar, the same one every collection uses.
class BookmarkScrollArea extends StatelessWidget {
  const BookmarkScrollArea({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: controller,
        thumbVisibility: false,
        trackVisibility: false,
        interactive: true,
        thickness: 3,
        radius: const Radius.circular(999),
        child: child,
      );
}

/// The palette a bookmark library resolves from.
BookmarkTheme bookmarkThemeOf(BuildContext context) => BookmarkTheme.of(
      context,
      CollectionPalette.of(context, CollectionKind.bookmark),
    );
