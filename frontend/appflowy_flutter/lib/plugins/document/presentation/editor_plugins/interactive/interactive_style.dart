import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';

/// The interactive blocks are dressed from the same palette the diagram,
/// mind map and equation blocks already use, so a page never collects two
/// slightly different readings of "a card in a document".
typedef InteractivePalette = VisualBlockPalette;

InteractivePalette interactivePaletteOf(BuildContext context) =>
    VisualBlockPalette.of(context);

/// The geometry and motion every interactive block answers to.
///
/// The numbers are the ones in the design brief: 120-180ms easeOutCubic for
/// hover, a shorter press, rounded corners and hairlines rather than outlines.
abstract final class InteractiveMetrics {
  static const double blockRadius = 16;
  static const double controlRadius = 10;
  static const double fieldRadius = 12;
  static const double chipRadius = 999;

  static const double controlSize = 26;
  static const double fieldHeight = 38;
  static const double rowHeight = 32;

  static const double gutter = 14;
  static const double gap = 10;

  static const Duration hover = Duration(milliseconds: 150);
  static const Duration press = Duration(milliseconds: 90);
  static const Duration reveal = Duration(milliseconds: 180);
  static const Duration settle = Duration(milliseconds: 260);
  static const Curve curve = Curves.easeOutCubic;

  /// The width a block is laid out at for each of the three sizes.
  static const double compactWidth = 340;
  static const double mediumWidth = 560;
}

/// How wide a block sits on the page.
///
/// Not every block is the same shape, so this is a choice rather than a fixed
/// measure: a counter wants to be small, a sticky note usually does not.
enum InteractiveSize {
  compact,
  medium,
  wide;

  static InteractiveSize fromValue(Object? value) => InteractiveSize.values
      .firstWhere((s) => s.name == value, orElse: () => InteractiveSize.medium);

  double get maxWidth => switch (this) {
        InteractiveSize.compact => InteractiveMetrics.compactWidth,
        InteractiveSize.medium => InteractiveMetrics.mediumWidth,
        InteractiveSize.wide => double.infinity,
      };
}

/// The soft colour ways an interactive block can wear.
///
/// They are tones, not brand colours: each resolves to a barely-tinted
/// surface plus a saturated companion for the one element that carries the
/// meaning (a progress fill, a selected radio, a chip's dot).
enum InteractiveAccent {
  paper,
  neutral,
  yellow,
  blue,
  green,
  pink,
  purple,
  orange,
  red;

  static InteractiveAccent fromValue(Object? value) =>
      InteractiveAccent.values.firstWhere(
        (a) => a.name == value,
        orElse: () => InteractiveAccent.neutral,
      );

  /// The seed hue, before it is settled onto the page's own surface.
  Color _seed(bool isDark) => switch (this) {
        InteractiveAccent.paper =>
          isDark ? const Color(0xFFB59B79) : const Color(0xFFB08A55),
        InteractiveAccent.neutral =>
          isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        InteractiveAccent.yellow =>
          isDark ? const Color(0xFFEAB308) : const Color(0xFFD9A100),
        InteractiveAccent.blue =>
          isDark ? const Color(0xFF60A5FA) : const Color(0xFF2F7FE4),
        InteractiveAccent.green =>
          isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
        InteractiveAccent.pink =>
          isDark ? const Color(0xFFF472B6) : const Color(0xFFDB2777),
        InteractiveAccent.purple =>
          isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
        InteractiveAccent.orange =>
          isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
        InteractiveAccent.red =>
          isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
      };

  /// Resolve against the page so the same choice reads correctly in light,
  /// dark and paper without any of them being an inversion of another.
  InteractiveTone resolve(InteractivePalette palette) {
    if (this == InteractiveAccent.neutral) {
      return InteractiveTone(
        surface: palette.isPaper
            ? PaperTheme.controlBackground
            : Color.alphaBlend(
                palette.hover.withValues(alpha: palette.isDark ? 0.7 : 0.9),
                palette.surface,
              ),
        border: palette.border.withValues(alpha: palette.isDark ? 0.5 : 0.34),
        ink: palette.text,
        inkSoft: palette.textSecondary,
        strong: palette.accent,
      );
    }

    if (this == InteractiveAccent.paper && palette.isPaper) {
      return const InteractiveTone(
        surface: PaperTheme.editorPreviewBackground,
        border: PaperTheme.strongBorder,
        ink: PaperTheme.textPrimary,
        inkSoft: PaperTheme.textSecondary,
        strong: PaperTheme.accent,
      );
    }

    final seed = _seed(palette.isDark);
    return InteractiveTone(
      surface: Color.alphaBlend(
        seed.withValues(alpha: palette.isDark ? 0.16 : 0.13),
        palette.surface,
      ),
      border: seed.withValues(alpha: palette.isDark ? 0.34 : 0.28),
      ink: palette.text,
      inkSoft: palette.textSecondary,
      strong: seed,
    );
  }
}

/// One accent, settled onto the surface it will be painted over.
@immutable
class InteractiveTone {
  const InteractiveTone({
    required this.surface,
    required this.border,
    required this.ink,
    required this.inkSoft,
    required this.strong,
  });

  final Color surface;
  final Color border;
  final Color ink;
  final Color inkSoft;

  /// The one saturated colour — a progress fill, a selected dot, a chip.
  final Color strong;

  /// A wash of the accent at the weight a chip or a track wants.
  Color wash(double alpha) => strong.withValues(alpha: alpha);
}

/// Typography for the interactive blocks.
///
/// Nothing here states a `fontWeight` where the surrounding text should be
/// inherited instead — a variable face ignores it and an embedded surface
/// that restates a weight always draws lighter than the paragraph above it.
abstract final class InteractiveType {
  static TextStyle label(InteractivePalette palette) => TextStyle(
        fontSize: 11.5,
        height: 1.2,
        letterSpacing: 0.12,
        color: palette.textSecondary,
      );

  static TextStyle body(InteractivePalette palette) => TextStyle(
        fontSize: 13.5,
        height: 1.35,
        color: palette.text,
      );

  static TextStyle title(InteractivePalette palette) => TextStyle(
        fontSize: 14.5,
        height: 1.3,
        letterSpacing: -0.1,
        color: palette.text,
      );

  /// A heading inside a block.
  ///
  /// The variable axis has to be raised alongside the weight — the bundled
  /// faces are variable, and a face like that ignores `fontWeight` on its own.
  static TextStyle strong(
    InteractivePalette palette, {
    double size = 14.5,
    Color? color,
    FontWeight weight = FontWeight.w600,
  }) =>
      TextStyle(
        fontSize: size,
        height: 1.3,
        letterSpacing: -0.1,
        fontWeight: weight,
        fontVariations: flowyFontVariationsForWeight(weight),
        color: color ?? palette.text,
      );

  static TextStyle caption(InteractivePalette palette) => TextStyle(
        fontSize: 11.5,
        height: 1.25,
        color: palette.textMuted,
      );

  /// A number that is the point of the block — the counter, the percentage.
  static TextStyle figure(InteractivePalette palette, {double size = 30}) =>
      TextStyle(
        fontSize: size,
        height: 1.05,
        letterSpacing: -0.8,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: palette.text,
      );
}

/// How much a control is standing out from the page.
enum InteractiveEmphasis { primary, secondary, ghost, subtle, danger }

/// How big a control is drawn.
enum InteractiveControlSize {
  small,
  medium,
  large;

  static InteractiveControlSize fromValue(Object? value) =>
      InteractiveControlSize.values.firstWhere(
        (s) => s.name == value,
        orElse: () => InteractiveControlSize.medium,
      );

  double get height => switch (this) {
        InteractiveControlSize.small => 28,
        InteractiveControlSize.medium => 34,
        InteractiveControlSize.large => 42,
      };

  double get horizontalPadding => switch (this) {
        InteractiveControlSize.small => 11,
        InteractiveControlSize.medium => 15,
        InteractiveControlSize.large => 20,
      };

  double get fontSize => switch (this) {
        InteractiveControlSize.small => 12.5,
        InteractiveControlSize.medium => 13.5,
        InteractiveControlSize.large => 15,
      };

  double get iconSize => switch (this) {
        InteractiveControlSize.small => 15,
        InteractiveControlSize.medium => 16,
        InteractiveControlSize.large => 18,
      };
}

/// The corner a control is cut with.
enum InteractiveShape {
  /// The application's usual soft corner.
  rounded,

  /// A full capsule.
  pill,

  /// Barely rounded, for a control that wants to read as a tile.
  square;

  static InteractiveShape fromValue(Object? value) =>
      InteractiveShape.values.firstWhere(
        (s) => s.name == value,
        orElse: () => InteractiveShape.rounded,
      );

  /// The radius for a control of [height].
  double radiusFor(double height) => switch (this) {
        InteractiveShape.rounded => InteractiveMetrics.controlRadius,
        InteractiveShape.pill => height,
        InteractiveShape.square => 4,
      };
}

/// The one button shape the interactive blocks use.
///
/// Restrained on purpose: rounded, a soft background transition, a small
/// contraction while pressed and an accent ring when it holds focus.
class InteractiveButton extends StatefulWidget {
  const InteractiveButton({
    super.key,
    required this.label,
    this.icon,
    this.trailingIcon,
    this.onPressed,
    this.emphasis = InteractiveEmphasis.secondary,
    this.accent,
    this.palette,
    this.expand = false,
    this.dense = false,
    this.tooltip,
    this.size,
    this.shape = InteractiveShape.rounded,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;
  final InteractiveEmphasis emphasis;
  final InteractiveAccent? accent;
  final InteractivePalette? palette;
  final bool expand;

  /// Shorthand for [InteractiveControlSize.small].
  final bool dense;
  final String? tooltip;
  final InteractiveControlSize? size;
  final InteractiveShape shape;

  InteractiveControlSize get resolvedSize =>
      size ?? (dense ? InteractiveControlSize.small : InteractiveControlSize.medium);

  @override
  State<InteractiveButton> createState() => _InteractiveButtonState();
}

class _InteractiveButtonState extends State<InteractiveButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette ?? interactivePaletteOf(context);
    final tone = (widget.accent ?? InteractiveAccent.neutral).resolve(palette);
    final enabled = widget.onPressed != null;
    final accent = switch (widget.emphasis) {
      InteractiveEmphasis.danger =>
        InteractiveAccent.red.resolve(palette).strong,
      _ => widget.accent == null ? palette.accent : tone.strong,
    };

    final (background, foreground, border) = _colours(palette, accent, enabled);
    final metrics = widget.resolvedSize;
    final radius = BorderRadius.circular(widget.shape.radiusFor(metrics.height));

    Widget content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: metrics.iconSize, color: foreground),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: metrics.fontSize,
              height: 1.1,
              letterSpacing: -0.05,
              color: foreground,
            ),
          ),
        ),
        if (widget.trailingIcon != null) ...[
          const SizedBox(width: 6),
          Icon(
            widget.trailingIcon,
            size: metrics.iconSize,
            color: foreground,
          ),
        ],
      ],
    );

    content = AnimatedContainer(
      duration: _pressed ? InteractiveMetrics.press : InteractiveMetrics.hover,
      curve: InteractiveMetrics.curve,
      height: metrics.height,
      padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: border == null ? null : Border.all(color: border),
        boxShadow: widget.emphasis == InteractiveEmphasis.primary &&
                enabled &&
                !_pressed
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: palette.isDark ? 0.28 : 0.20),
                  blurRadius: _hovered ? 12 : 8,
                  offset: Offset(0, _hovered ? 4 : 2),
                  spreadRadius: -3,
                ),
              ]
            : null,
      ),
      child: Center(widthFactor: widget.expand ? null : 1, child: content),
    );

    // A press is a small contraction, never a colour flash.
    content = AnimatedScale(
      duration: InteractiveMetrics.press,
      curve: InteractiveMetrics.curve,
      scale: _pressed && enabled ? 0.975 : 1,
      child: content,
    );

    if (_focused) {
      content = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            widget.shape.radiusFor(metrics.height) + 3,
          ),
          border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.6),
        ),
        padding: const EdgeInsets.all(2),
        child: content,
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(3),
        child: content,
      );
    }

    Widget result = Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel:
              enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: content,
        ),
      ),
    );

    if (widget.tooltip != null) {
      result = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 420),
        child: result,
      );
    }
    return result;
  }

  (Color, Color, Color?) _colours(
    InteractivePalette palette,
    Color accent,
    bool enabled,
  ) {
    if (!enabled) {
      return (
        palette.hover.withValues(alpha: palette.isDark ? 0.35 : 0.55),
        palette.textMuted.withValues(alpha: 0.55),
        null,
      );
    }
    final lift = _pressed ? 0.14 : (_hovered ? 0.08 : 0.0);
    switch (widget.emphasis) {
      case InteractiveEmphasis.primary:
      case InteractiveEmphasis.danger:
        final shade = _pressed
            ? Color.alphaBlend(Colors.black.withValues(alpha: 0.12), accent)
            : accent;
        return (shade, _onColour(accent), null);
      case InteractiveEmphasis.secondary:
        return (
          Color.alphaBlend(
            palette.hover.withValues(alpha: palette.isDark ? 0.8 : 1),
            palette.surface,
          ).withValues(alpha: 1),
          palette.text,
          palette.border.withValues(alpha: 0.36 + lift),
        );
      case InteractiveEmphasis.ghost:
        return (
          accent.withValues(alpha: 0.10 + lift * 0.6),
          accent,
          null,
        );
      case InteractiveEmphasis.subtle:
        return (
          palette.hover.withValues(alpha: _hovered || _pressed ? 0.9 : 0),
          _hovered ? palette.text : palette.textSecondary,
          null,
        );
    }
  }

  static Color _onColour(Color background) =>
      background.computeLuminance() > 0.6
          ? const Color(0xFF1F2430)
          : Colors.white;
}

/// A 26px borderless control, the same shape the visual blocks use in their
/// headers, so a counter's minus and a diagram's fullscreen read alike.
class InteractiveIconButton extends StatefulWidget {
  const InteractiveIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
    this.palette,
    this.size = InteractiveMetrics.controlSize,
    this.iconSize = 16,
    this.accent,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final InteractivePalette? palette;
  final double size;
  final double iconSize;
  final Color? accent;

  @override
  State<InteractiveIconButton> createState() => _InteractiveIconButtonState();
}

class _InteractiveIconButtonState extends State<InteractiveIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette ?? interactivePaletteOf(context);
    final accent = widget.accent ?? palette.accent;
    final enabled = widget.onPressed != null;
    final background = widget.selected
        ? accent.withValues(alpha: palette.isDark ? 0.22 : 0.12)
        : (_hovered && enabled)
            ? palette.hover
            : palette.hoverBase;
    final foreground = !enabled
        ? palette.textMuted.withValues(alpha: 0.45)
        : widget.selected
            ? accent
            : _hovered
                ? palette.text
                : palette.textSecondary;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 420),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        selected: widget.selected,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel:
                enabled ? () => setState(() => _pressed = false) : null,
            onTap: widget.onPressed,
            child: AnimatedScale(
              duration: InteractiveMetrics.press,
              curve: InteractiveMetrics.curve,
              scale: _pressed && enabled ? 0.9 : 1,
              child: AnimatedContainer(
                duration: InteractiveMetrics.hover,
                curve: InteractiveMetrics.curve,
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(
                    InteractiveMetrics.controlRadius,
                  ),
                ),
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: foreground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill carrying one selected value — a tag, an option, a file.
class InteractiveChip extends StatelessWidget {
  const InteractiveChip({
    super.key,
    required this.label,
    this.accent = InteractiveAccent.neutral,
    this.icon,
    this.onRemove,
    this.onTap,
    this.palette,
    this.dense = false,
  });

  final String label;
  final InteractiveAccent accent;
  final IconData? icon;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  final InteractivePalette? palette;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colours = palette ?? interactivePaletteOf(context);
    final tone = accent.resolve(colours);

    Widget body = Container(
      padding: EdgeInsets.fromLTRB(
        icon == null ? (dense ? 8 : 10) : (dense ? 6 : 8),
        dense ? 3 : 4,
        onRemove == null ? (dense ? 8 : 10) : (dense ? 4 : 5),
        dense ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: tone.surface,
        borderRadius: BorderRadius.circular(InteractiveMetrics.chipRadius),
        border: Border.all(color: tone.border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 13, color: tone.strong),
            const SizedBox(width: 5),
          ] else if (accent != InteractiveAccent.neutral) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: tone.strong,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 11.5 : 12.5,
                height: 1.2,
                color: tone.ink,
              ),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 3),
            InteractiveIconButton(
              icon: Icons.close_rounded,
              tooltip: label,
              onPressed: onRemove,
              palette: colours,
              size: dense ? 16 : 18,
              iconSize: dense ? 11 : 12,
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      body = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: body,
        ),
      );
    }
    return body;
  }
}

/// The surface a text field is set on: a soft fill and a focus ring, never a
/// heavy outline.
class InteractiveFieldSurface extends StatelessWidget {
  const InteractiveFieldSurface({
    super.key,
    required this.child,
    required this.focused,
    this.palette,
    this.height = InteractiveMetrics.fieldHeight,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
    this.accent,
    this.fill,
    this.radius,
    this.hovered = false,
  });

  final Widget child;
  final bool focused;
  final InteractivePalette? palette;
  final double? height;
  final EdgeInsets padding;

  /// The colour of the focus ring and its halo.
  final Color? accent;

  /// The resting fill. Absent means the neutral one derived from the page.
  final Color? fill;

  final double? radius;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final colours = palette ?? interactivePaletteOf(context);
    final ring = accent ?? colours.accent;
    final base = fill ??
        Color.alphaBlend(
          colours.hover.withValues(alpha: colours.isDark ? 0.7 : 0.95),
          colours.surface,
        );
    return AnimatedContainer(
      duration: InteractiveMetrics.hover,
      curve: InteractiveMetrics.curve,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: hovered && !focused
            ? Color.alphaBlend(colours.hover.withValues(alpha: 0.5), base)
            : base,
        borderRadius:
            BorderRadius.circular(radius ?? InteractiveMetrics.fieldRadius),
        border: Border.all(
          color: focused
              ? ring.withValues(alpha: 0.62)
              : colours.border.withValues(alpha: hovered ? 0.42 : 0.28),
          width: focused ? 1.4 : 1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: ring.withValues(alpha: 0.16),
                  spreadRadius: 3,
                ),
                BoxShadow(
                  color: ring.withValues(alpha: colours.isDark ? 0.22 : 0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// The quiet caption a block prints above itself.
class InteractiveLabel extends StatelessWidget {
  const InteractiveLabel({super.key, required this.text, this.palette});

  final String text;
  final InteractivePalette? palette;

  @override
  Widget build(BuildContext context) {
    final colours = palette ?? interactivePaletteOf(context);
    return Text(
      text,
      style: InteractiveType.label(colours),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
