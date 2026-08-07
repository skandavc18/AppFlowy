import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:flutter/material.dart';

/// Geometry and motion for embedded collection widgets.
///
/// Everything here is theme free so the numbers can be reasoned about — and
/// tested — without a `BuildContext`.
abstract final class CollectionEmbedMetrics {
  /// A widget is softer than a document card: it belongs to the page rather
  /// than floating over it.
  static const double surfaceRadius = 18;
  static const double innerRadius = 12;
  static const double tileRadius = 9;
  static const double controlRadius = 8;

  static const double controlSize = 26;
  static const double controlIconSize = 16;

  static const EdgeInsets surfacePadding = EdgeInsets.fromLTRB(16, 14, 16, 15);
  static const EdgeInsets compactPadding = EdgeInsets.fromLTRB(13, 11, 13, 12);

  /// Hover is a 140ms settle — long enough to read as motion, short enough
  /// that a pointer sweeping the page never feels sticky.
  static const Duration hover = Duration(milliseconds: 140);
  static const Duration settle = Duration(milliseconds: 220);
  static const Duration reveal = Duration(milliseconds: 320);
  static const Duration flip = Duration(milliseconds: 620);
  static const Curve ease = Curves.easeOutCubic;

  /// How far a widget lifts under the pointer.
  static const double hoverLift = 2;
  static const double hoverGrowth = 1.004;

  static const double minWidth = 320;
  static const double defaultWidth = 720;
}

/// The colours an embedded collection widget paints with.
///
/// Derived from [CollectionPalette], so paper, light and dark all resolve
/// without a second set of rules, and every collection type carries its own
/// hue into the page.
@immutable
class CollectionEmbedTheme {
  const CollectionEmbedTheme._({
    required this.palette,
    required this.kind,
    required this.brightness,
    required this.isPaper,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.hairline,
    required this.rowHover,
    required this.textPrimary,
    required this.textBody,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentWash,
    required this.shadow,
  });

  factory CollectionEmbedTheme.of(BuildContext context, CollectionKind? kind) {
    final resolved = kind ?? CollectionKind.database;
    final palette = CollectionPalette.of(context, resolved);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final isPaper = PaperTheme.isEnabled(context);
    final accent = kind == null
        ? palette.base.accent
        : CollectionPalette.of(context, kind).accent;

    // The widget surface is only a whisper away from the page. A widget that
    // contrasts hard with the document reads as a foreign application.
    final surface = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.030 : 0.016),
      palette.surface,
    );
    final raised = Color.alphaBlend(
      (isDark ? Colors.white : Colors.black)
          .withValues(alpha: isDark ? 0.045 : 0.024),
      surface,
    );
    final sunken = Color.alphaBlend(
      (isDark ? Colors.black : Colors.black)
          .withValues(alpha: isDark ? 0.16 : 0.032),
      surface,
    );

    return CollectionEmbedTheme._(
      palette: palette,
      kind: kind,
      brightness: brightness,
      isPaper: isPaper,
      surface: surface,
      raised: raised,
      sunken: sunken,
      hairline: palette.border.withValues(alpha: isDark ? 0.20 : 0.16),
      rowHover: palette.hover,
      textPrimary: palette.textPrimary,
      textBody: Color.lerp(palette.textSecondary, palette.textPrimary, 0.55)!,
      textMuted: palette.textSecondary,
      textFaint: palette.textMuted,
      accent: accent,
      accentWash: Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.18 : 0.11),
        surface,
      ),
      shadow: palette.base.shadow,
    );
  }

  final CollectionPalette palette;
  final CollectionKind? kind;
  final Brightness brightness;
  final bool isPaper;
  final Color surface;
  final Color raised;
  final Color sunken;
  final Color hairline;
  final Color rowHover;
  final Color textPrimary;
  final Color textBody;
  final Color textMuted;
  final Color textFaint;
  final Color accent;
  final Color accentWash;
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  IconData get icon => kind == null
      ? Icons.folder_rounded
      : CollectionRegistry.typeFor(kind!).icon;

  String get typeLabel =>
      kind == null ? '' : CollectionRegistry.typeFor(kind!).label;

  /// A natural shadow: one wide ambient pass, plus a tight contact pass in
  /// light appearances where a black blur actually reads.
  List<BoxShadow> elevation({double prominence = 1}) {
    final ambient = shadow.withValues(
      alpha: (isDark ? 0.30 : 0.085) * prominence,
    );
    return [
      BoxShadow(
        color: ambient,
        blurRadius: 22 * prominence.clamp(0.6, 1.6),
        offset: Offset(0, 7 * prominence.clamp(0.6, 1.6)),
        spreadRadius: -9,
      ),
      if (!isDark)
        BoxShadow(
          color: shadow.withValues(alpha: 0.05 * prominence),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
    ];
  }

  /// Typography for widgets. The face is inherited from the document so a
  /// widget is set in the same voice as the paragraph above it — only size,
  /// colour and tracking change.
  TextStyle face(
    BuildContext context, {
    required double size,
    Color? color,
    double? weightAxis,
    double tracking = 0,
    double height = 1.25,
  }) {
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return base.copyWith(
      fontSize: size,
      color: color ?? textBody,
      height: height,
      letterSpacing: tracking,
      fontVariations: weightAxis == null
          ? base.fontVariations
          : [FontVariation('wght', weightAxis)],
    );
  }

  TextStyle title(BuildContext context, {double size = 14.5}) => face(
        context,
        size: size,
        color: textPrimary,
        weightAxis: 620,
        tracking: -0.15,
      );

  TextStyle body(BuildContext context, {double size = 12.5}) =>
      face(context, size: size, color: textBody, height: 1.35);

  TextStyle caption(BuildContext context, {double size = 11}) =>
      face(context, size: size, color: textFaint, weightAxis: 530);

  TextStyle label(BuildContext context, {double size = 10.5, Color? color}) =>
      face(
        context,
        size: size,
        color: color ?? textFaint,
        weightAxis: 620,
        tracking: 0.5,
      );
}

/// The one surface every collection widget sits on.
///
/// Soft rounded corners, a very light hairline and a natural shadow — and, on
/// hover, a small lift. It never draws a heavy frame, because the page should
/// read straight through into the widget.
class CollectionEmbedSurface extends StatelessWidget {
  const CollectionEmbedSurface({
    super.key,
    required this.theme,
    required this.child,
    this.hovered = false,
    this.padding = EdgeInsets.zero,
    this.radius,
    this.color,
    this.flush = false,
    this.lift = true,
  });

  final CollectionEmbedTheme theme;
  final Widget child;
  final bool hovered;
  final EdgeInsets padding;
  final double? radius;

  /// Overrides the resolved widget surface. `null` keeps the theme's own.
  final Color? color;

  /// A flush widget paints no fill, no shadow and no hairline — the content
  /// simply continues the page. The database embed is flush by design.
  final bool flush;
  final bool lift;

  @override
  Widget build(BuildContext context) {
    final borderRadius =
        BorderRadius.circular(radius ?? CollectionEmbedMetrics.surfaceRadius);
    if (flush) {
      return Padding(padding: padding, child: child);
    }
    return AnimatedContainer(
      duration: CollectionEmbedMetrics.hover,
      curve: CollectionEmbedMetrics.ease,
      transform: Matrix4.translationValues(
        0,
        hovered && lift ? -CollectionEmbedMetrics.hoverLift : 0,
        0,
      ),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (hovered ? theme.raised : theme.surface),
        borderRadius: borderRadius,
        boxShadow: theme.elevation(prominence: hovered ? 1.35 : 1),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: theme.hairline, width: 0.7),
      ),
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }
}

/// A borderless control that only shades under the pointer.
class CollectionEmbedButton extends StatefulWidget {
  const CollectionEmbedButton({
    super.key,
    required this.theme,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = CollectionEmbedMetrics.controlSize,
    this.iconSize = CollectionEmbedMetrics.controlIconSize,
    this.active = false,
  });

  final CollectionEmbedTheme theme;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final bool active;

  @override
  State<CollectionEmbedButton> createState() => _CollectionEmbedButtonState();
}

class _CollectionEmbedButtonState extends State<CollectionEmbedButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled = widget.onPressed != null;
    // Never fade from Colors.transparent: the tween would pass through grey.
    final resting = widget.active
        ? theme.accent.withValues(alpha: theme.isDark ? 0.20 : 0.12)
        : theme.rowHover.withValues(alpha: 0);
    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: CollectionEmbedMetrics.hover,
          curve: CollectionEmbedMetrics.ease,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: hovered && enabled ? theme.rowHover : resting,
            borderRadius:
                BorderRadius.circular(CollectionEmbedMetrics.controlRadius),
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: !enabled
                ? theme.textFaint.withValues(alpha: 0.45)
                : widget.active
                    ? theme.accent
                    : hovered
                        ? theme.textPrimary
                        : theme.textMuted,
          ),
        ),
      ),
    );
    final tooltip = widget.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// A small piece of metadata: no fill, no outline, just a dot and a word.
class CollectionEmbedMeta extends StatelessWidget {
  const CollectionEmbedMeta({
    super.key,
    required this.theme,
    required this.label,
    this.icon,
    this.color,
  });

  final CollectionEmbedTheme theme;
  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color ?? theme.textFaint),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.caption(context).copyWith(color: color),
            ),
          ),
        ],
      );
}

/// The 3px separator between two pieces of metadata.
class CollectionEmbedMetaDot extends StatelessWidget {
  const CollectionEmbedMetaDot({super.key, required this.theme});

  final CollectionEmbedTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: theme.textFaint.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
        ),
      );
}

/// Minimal chrome: the collection's glyph, its name, one line of facts, and
/// whatever controls the preview wants on the right.
class CollectionEmbedHeading extends StatelessWidget {
  const CollectionEmbedHeading({
    super.key,
    required this.theme,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.dense = false,
  });

  final CollectionEmbedTheme theme;
  final String title;
  final Widget? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final leading = Row(
      children: [
        Icon(
          icon ?? theme.icon,
          size: dense ? 15 : 17,
          color: theme.accent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.title(context, size: dense ? 13 : 14),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                DefaultTextStyle.merge(
                  style: theme.caption(context),
                  child: subtitle!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return Row(
      children: [
        Expanded(
          child: onTap == null
              ? leading
              : MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTap,
                    child: leading,
                  ),
                ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

/// What a widget shows when the collection has nothing in it yet.
class CollectionEmbedEmpty extends StatelessWidget {
  const CollectionEmbedEmpty({
    super.key,
    required this.theme,
    required this.message,
    this.icon,
    this.action,
    this.onAction,
    this.compact = false,
  });

  final CollectionEmbedTheme theme;
  final String message;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? theme.icon,
                size: compact ? 20 : 26,
                color: theme.textFaint.withValues(alpha: 0.6),
              ),
              SizedBox(height: compact ? 7 : 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme
                    .body(context, size: compact ? 11.5 : 12.5)
                    .copyWith(color: theme.textMuted),
              ),
              if (action != null && onAction != null) ...[
                const SizedBox(height: 10),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: onAction,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.accentWash,
                        borderRadius: BorderRadius.circular(
                          CollectionEmbedMetrics.controlRadius,
                        ),
                      ),
                      child: Text(
                        action!,
                        style: theme
                            .body(context, size: 12)
                            .copyWith(color: theme.accent),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

/// A thin progress rail, used by books, reading lists and downloads.
class CollectionEmbedProgress extends StatelessWidget {
  const CollectionEmbedProgress({
    super.key,
    required this.theme,
    required this.value,
    this.height = 3,
    this.color,
  });

  final CollectionEmbedTheme theme;
  final double value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: theme.textFaint.withValues(alpha: 0.18),
                ),
              ),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                child: AnimatedContainer(
                  duration: CollectionEmbedMetrics.settle,
                  curve: CollectionEmbedMetrics.ease,
                  color: color ?? theme.accent,
                ),
              ),
            ],
          ),
        ),
      );
}
