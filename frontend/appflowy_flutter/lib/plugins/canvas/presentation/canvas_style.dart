import 'dart:math' as math;

import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:flutter/material.dart';

/// Every fixed size, duration and curve the canvas is drawn with.
///
/// A canvas is meant to be quiet — the content is the point — so the chrome is
/// small, the shadows are soft and nothing moves for longer than it takes to
/// read as a movement rather than an animation.
abstract final class CanvasMetrics {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 24;

  static const double cardRadius = 14;
  static const double frameRadius = 16;
  static const double chromeRadius = 14;
  static const double controlRadius = 9;

  static const double controlSize = 32;
  static const double toolbarHeight = 44;
  static const double frameHeaderHeight = 30;

  /// The grip a card is resized by, and the ring that says it is selected.
  static const double handleSize = 9;
  static const double selectionRing = 1.8;

  /// How thick a connection is drawn, before zoom.
  static const double edgeWidth = 1.9;
  static const double edgeHitWidth = 14;
  static const double arrowSize = 9;

  /// How near the pointer has to be to a card's edge to start a connection.
  static const double portRadius = 7;

  static const double minimapSize = 168;
  static const double outlineWidth = 232;

  static const Duration hover = Duration(milliseconds: 140);
  static const Duration settle = Duration(milliseconds: 220);
  static const Duration chrome = Duration(milliseconds: 180);

  static const Curve settleCurve = Curves.easeOutCubic;
}

/// The colours a canvas is drawn in.
///
/// Resolved once per build and handed down, so a card, a connection and the
/// minimap cannot drift apart, and so an exported picture is painted from the
/// same values as the screen.
@immutable
class CanvasPalette {
  const CanvasPalette({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.hover,
    required this.border,
    required this.grid,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.shadow,
    required this.guide,
    required this.isDark,
    required this.isPaper,
  });

  /// The infinite plane itself.
  final Color canvas;

  /// The face of a card.
  final Color surface;

  /// A panel standing on a card — a code card's header, a preview strip.
  final Color raised;

  /// A well cut into the canvas: a frame's fill.
  final Color sunken;

  final Color hover;
  final Color border;

  /// The dot, grid or line pattern.
  final Color grid;

  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color shadow;

  /// The line drawn while something is being lined up.
  final Color guide;

  final bool isDark;
  final bool isPaper;

  /// The colours a card, a frame or a connection can be given.
  ///
  /// Kept muted on purpose: a canvas of nine saturated cards is unreadable,
  /// and the colour is meant to group rather than to shout.
  static const List<Color> accents = <Color>[
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF64748B),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
  ];

  /// The colour at [index], or the canvas accent when a card has none.
  Color accentAt(int? index) {
    if (index == null || index < 0) {
      return accent;
    }
    final base = accents[index % accents.length];
    // Lift a colour in the dark: the same hue on a near-black canvas reads a
    // full step darker than it does on white.
    return isDark ? Color.lerp(base, Colors.white, 0.18)! : base;
  }

  /// The face a coloured card is drawn on — a wash, never the full colour, so
  /// the words on it stay readable.
  Color surfaceFor(int? index) {
    if (index == null) {
      return surface;
    }
    return Color.alphaBlend(
      accentAt(index).withValues(alpha: isDark ? 0.2 : 0.11),
      surface,
    );
  }

  Color borderFor(int? index) {
    if (index == null) {
      return border;
    }
    return accentAt(index).withValues(alpha: isDark ? 0.5 : 0.36);
  }

  /// A card's shadow, rising as it is picked up.
  List<BoxShadow> cardShadow({bool raisedCard = false, bool dragging = false}) {
    final depth = dragging ? 1.6 : (raisedCard ? 1.15 : 1.0);
    return <BoxShadow>[
      BoxShadow(
        color: shadow.withValues(alpha: (isDark ? 0.4 : 0.1) * depth),
        blurRadius: 20 * depth,
        spreadRadius: -8,
        offset: Offset(0, 8 * depth),
      ),
      BoxShadow(
        color: shadow.withValues(alpha: (isDark ? 0.26 : 0.055) * depth),
        blurRadius: 5,
        offset: Offset(0, 1.5 * depth),
      ),
    ];
  }

  List<BoxShadow> get chromeShadow => <BoxShadow>[
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.44 : 0.14),
          blurRadius: 22,
          spreadRadius: -6,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.3 : 0.07),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  /// A hover wash that fades from its own hue rather than through grey.
  Color get hoverAtRest => hover.withValues(alpha: 0);
}

/// The palette for the appearance the application is wearing, unless the
/// canvas has asked for one of its own.
CanvasPalette canvasPaletteOf(
  BuildContext context, {
  CanvasTheme theme = CanvasTheme.auto,
}) {
  final materialTheme = Theme.of(context);
  final premium = materialTheme.extension<PremiumThemeExtension>();
  final appIsDark = materialTheme.brightness == Brightness.dark;
  final appIsPaper = PaperTheme.isEnabled(context);

  switch (theme) {
    case CanvasTheme.paper:
      return _paperPalette();
    case CanvasTheme.dark:
      return _darkPalette();
    case CanvasTheme.blueprint:
      return _blueprintPalette();
    case CanvasTheme.minimal:
      return _minimalPalette(isDark: appIsDark);
    case CanvasTheme.auto:
      break;
  }

  if (appIsPaper) {
    return _paperPalette();
  }
  if (premium == null) {
    final scheme = materialTheme.colorScheme;
    final onSurface = scheme.onSurface;
    return CanvasPalette(
      canvas: scheme.surface,
      surface: scheme.surface,
      raised: onSurface.withValues(alpha: 0.05),
      sunken: onSurface.withValues(alpha: 0.035),
      hover: onSurface.withValues(alpha: 0.06),
      border: materialTheme.dividerColor,
      grid: onSurface.withValues(alpha: appIsDark ? 0.13 : 0.1),
      textPrimary: onSurface,
      textSecondary: onSurface.withValues(alpha: 0.76),
      textMuted: materialTheme.hintColor,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      shadow: Colors.black,
      guide: scheme.primary,
      isDark: appIsDark,
      isPaper: false,
    );
  }

  return CanvasPalette(
    // A canvas sits a shade below the page around it, so the cards on it read
    // as objects standing on a surface rather than as boxes drawn on a page.
    canvas: appIsDark
        ? Color.lerp(premium.canvas, Colors.black, 0.28)!
        : Color.lerp(premium.canvas, const Color(0xFF0B1220), 0.03)!,
    surface: premium.floatingSurface,
    raised: premium.mutedSurface,
    sunken: appIsDark
        ? Colors.white.withValues(alpha: 0.032)
        : Colors.black.withValues(alpha: 0.026),
    hover: premium.hover,
    border: premium.border,
    grid: premium.textMuted.withValues(alpha: appIsDark ? 0.22 : 0.24),
    textPrimary: premium.textPrimary,
    textSecondary: Color.lerp(premium.textMuted, premium.textPrimary, 0.55) ??
        premium.textSecondary,
    textMuted: premium.textMuted,
    accent: premium.accent,
    onAccent: premium.onAccent,
    shadow: premium.shadow,
    guide: premium.accent,
    isDark: appIsDark,
    isPaper: false,
  );
}

CanvasPalette _paperPalette() => CanvasPalette(
      canvas: PaperTheme.editorBackground,
      surface: PaperTheme.popupBackground,
      raised: PaperTheme.controlBackground,
      sunken: PaperTheme.calloutBackground,
      hover: PaperTheme.hoverOverlay,
      border: PaperTheme.codeBlockBorder,
      grid: PaperTheme.textMuted.withValues(alpha: 0.3),
      textPrimary: PaperTheme.textPrimary,
      textSecondary: PaperTheme.textSecondary,
      textMuted: PaperTheme.textMuted,
      accent: PaperTheme.accent,
      onAccent: PaperTheme.onAccent,
      shadow: PaperTheme.shadow,
      guide: PaperTheme.accent,
      isDark: false,
      isPaper: true,
    );

CanvasPalette _darkPalette() => CanvasPalette(
      canvas: const Color(0xFF141519),
      surface: const Color(0xFF1E2026),
      raised: const Color(0xFF262931),
      sunken: Colors.white.withValues(alpha: 0.03),
      hover: Colors.white.withValues(alpha: 0.06),
      border: Colors.white.withValues(alpha: 0.11),
      grid: Colors.white.withValues(alpha: 0.09),
      textPrimary: const Color(0xFFE9EAEE),
      textSecondary: const Color(0xFFB6B9C2),
      textMuted: const Color(0xFF878B96),
      accent: const Color(0xFF6E8BFF),
      onAccent: Colors.white,
      shadow: Colors.black,
      guide: const Color(0xFF6E8BFF),
      isDark: true,
      isPaper: false,
    );

/// Drawing-board blue, for architecture and wiring.
CanvasPalette _blueprintPalette() => CanvasPalette(
      canvas: const Color(0xFF0E2740),
      surface: const Color(0xFF143352),
      raised: const Color(0xFF1B3F63),
      sunken: Colors.white.withValues(alpha: 0.04),
      hover: Colors.white.withValues(alpha: 0.07),
      border: const Color(0x593FA9FF),
      grid: const Color(0x3D8FD3FF),
      textPrimary: const Color(0xFFE6F2FF),
      textSecondary: const Color(0xFFB8D6F0),
      textMuted: const Color(0xFF89AFCE),
      accent: const Color(0xFF6FD3FF),
      onAccent: const Color(0xFF07223A),
      shadow: Colors.black,
      guide: const Color(0xFF6FD3FF),
      isDark: true,
      isPaper: false,
    );

/// Nothing but paper and ink: no grid, almost no shadow.
CanvasPalette _minimalPalette({required bool isDark}) => isDark
    ? CanvasPalette(
        canvas: const Color(0xFF121212),
        surface: const Color(0xFF181818),
        raised: const Color(0xFF202020),
        sunken: Colors.white.withValues(alpha: 0.025),
        hover: Colors.white.withValues(alpha: 0.05),
        border: Colors.white.withValues(alpha: 0.13),
        grid: Colors.white.withValues(alpha: 0.05),
        textPrimary: const Color(0xFFEDEDED),
        textSecondary: const Color(0xFFB4B4B4),
        textMuted: const Color(0xFF8A8A8A),
        accent: const Color(0xFFEDEDED),
        onAccent: const Color(0xFF121212),
        shadow: Colors.black,
        guide: const Color(0xFF8A8A8A),
        isDark: true,
        isPaper: false,
      )
    : CanvasPalette(
        canvas: const Color(0xFFFCFCFC),
        surface: Colors.white,
        raised: const Color(0xFFF4F4F4),
        sunken: Colors.black.withValues(alpha: 0.022),
        hover: Colors.black.withValues(alpha: 0.045),
        border: Colors.black.withValues(alpha: 0.12),
        grid: Colors.black.withValues(alpha: 0.05),
        textPrimary: const Color(0xFF17171A),
        textSecondary: const Color(0xFF55555C),
        textMuted: const Color(0xFF8A8A93),
        accent: const Color(0xFF17171A),
        onAccent: Colors.white,
        shadow: Colors.black,
        guide: const Color(0xFF8A8A93),
        isDark: false,
        isPaper: false,
      );

/// A small borderless control: the toolbar's tools, a card's own buttons.
class CanvasButton extends StatefulWidget {
  const CanvasButton({
    super.key,
    required this.icon,
    required this.palette,
    this.onPressed,
    this.tooltip,
    this.selected = false,
    this.size = CanvasMetrics.controlSize,
    this.iconSize = 17,
    this.accented = false,
  });

  final IconData icon;
  final CanvasPalette palette;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool selected;
  final double size;
  final double iconSize;

  /// A selected tool is filled rather than washed, because the tool in hand is
  /// the one thing on the toolbar that must be obvious at a glance.
  final bool accented;

  @override
  State<CanvasButton> createState() => _CanvasButtonState();
}

class _CanvasButtonState extends State<CanvasButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final enabled = widget.onPressed != null;
    final filled = widget.selected && widget.accented;

    final background = filled
        ? palette.accent
        : widget.selected
            ? palette.accent.withValues(alpha: 0.14)
            : _hovered && enabled
                ? Color.alphaBlend(palette.hover, palette.hoverAtRest)
                : palette.hoverAtRest;

    final ink = !enabled
        ? palette.textMuted.withValues(alpha: 0.45)
        : filled
            ? palette.onAccent
            : widget.selected
                ? palette.accent
                : palette.textSecondary;

    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: CanvasMetrics.hover,
          curve: CanvasMetrics.settleCurve,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(CanvasMetrics.controlRadius),
          ),
          child: Center(
            widthFactor: 1,
            child: Icon(widget.icon, size: widget.iconSize, color: ink),
          ),
        ),
      ),
    );

    final tooltip = widget.tooltip;
    return tooltip == null || tooltip.isEmpty
        ? button
        : Tooltip(
            message: tooltip,
            waitDuration: CanvasMetrics.chrome,
            child: button,
          );
  }
}

/// The floating card every piece of canvas chrome sits on.
class CanvasSurface extends StatelessWidget {
  const CanvasSurface({
    super.key,
    required this.palette,
    required this.child,
    this.padding = const EdgeInsets.all(CanvasMetrics.space1),
    this.radius,
  });

  final CanvasPalette palette;
  final Widget child;
  final EdgeInsets padding;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final corners = BorderRadius.circular(radius ?? CanvasMetrics.chromeRadius);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: corners,
        boxShadow: palette.chromeShadow,
      ),
      // The hairline goes on the foreground so the card's own clip cannot eat
      // half of it.
      foregroundDecoration: BoxDecoration(
        borderRadius: corners,
        border: Border.all(
          color: palette.border.withValues(alpha: palette.isDark ? 0.4 : 0.28),
          width: 0.7,
        ),
      ),
      child: child,
    );
  }
}

/// A quiet reading of a size, used by the zoom readout and the frame counts.
TextStyle canvasLabelStyle(
  CanvasPalette palette, {
  double size = 12,
  FontWeight weight = FontWeight.w500,
  Color? color,
}) =>
    TextStyle(
      fontSize: size,
      fontWeight: weight,
      height: 1.25,
      letterSpacing: -0.1,
      color: color ?? palette.textSecondary,
    );

/// A percentage the way a person reads one.
String formatCanvasZoom(double zoom) => '${(zoom * 100).round()}%';

/// A colour swatch row, shared by the card menu, the frame menu and the
/// connection menu so a colour means the same thing everywhere.
class CanvasSwatchRow extends StatelessWidget {
  const CanvasSwatchRow({
    super.key,
    required this.palette,
    required this.onPicked,
    this.selected,
  });

  final CanvasPalette palette;
  final ValueChanged<int?> onPicked;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: CanvasMetrics.space3,
        vertical: CanvasMetrics.space2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Swatch(
            colour: palette.textMuted.withValues(alpha: 0.35),
            selected: selected == null,
            onTap: () => onPicked(null),
            crossed: true,
            palette: palette,
          ),
          for (var index = 0; index < CanvasPalette.accents.length; index++)
            _Swatch(
              colour: palette.accentAt(index),
              selected: selected == index,
              onTap: () => onPicked(index),
              palette: palette,
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colour,
    required this.selected,
    required this.onTap,
    required this.palette,
    this.crossed = false,
  });

  final Color colour;
  final bool selected;
  final VoidCallback onTap;
  final CanvasPalette palette;
  final bool crossed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: SizedBox(
            width: 20,
            height: 22,
            child: Center(
              child: AnimatedContainer(
                duration: CanvasMetrics.hover,
                width: selected ? 17 : 15,
                height: selected ? 17 : 15,
                decoration: BoxDecoration(
                  color: crossed ? Colors.transparent : colour,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? palette.textPrimary : colour,
                    width: selected ? 1.6 : (crossed ? 1.4 : 0.5),
                  ),
                ),
                child: crossed
                    ? Center(
                        child: Transform.rotate(
                          angle: -math.pi / 4,
                          child: Container(
                            width: 12,
                            height: 1.3,
                            color: palette.textMuted,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
