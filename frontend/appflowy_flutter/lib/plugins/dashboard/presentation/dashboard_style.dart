import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';

/// The colours a dashboard is drawn in.
///
/// Derived from the application's own theme so a dashboard is never a second
/// design language sitting inside AppFlowy: light, dark and paper all come out
/// of the same tokens the editor and the collections already use.
@immutable
class DashboardPalette {
  const DashboardPalette({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.hover,
    required this.border,
    required this.gridLine,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.shadowColor,
    required this.isDark,
    required this.isPaper,
  });

  factory DashboardPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPaper = !isDark && PaperTheme.isEnabled(context);

    if (isPaper) {
      return const DashboardPalette(
        canvas: PaperTheme.editorBackground,
        surface: PaperTheme.editorPreviewBackground,
        raised: PaperTheme.popupBackground,
        sunken: PaperTheme.controlBackground,
        hover: PaperTheme.controlHover,
        border: PaperTheme.strongBorder,
        gridLine: Color(0x14715438),
        textPrimary: PaperTheme.textPrimary,
        textSecondary: PaperTheme.textSecondary,
        textMuted: PaperTheme.textMuted,
        accent: PaperTheme.accent,
        onAccent: PaperTheme.onAccent,
        shadowColor: Color(0x1A6B4B2A),
        isDark: false,
        isPaper: true,
      );
    }

    final accent = premium?.accent ?? theme.colorScheme.primary;
    final border = premium?.border ?? theme.colorScheme.outlineVariant;
    return DashboardPalette(
      canvas: premium?.canvas ?? theme.colorScheme.surface,
      surface: premium?.surface ?? theme.colorScheme.surfaceContainerLowest,
      raised: premium?.floatingSurface ?? theme.colorScheme.surfaceBright,
      sunken: premium?.mutedSurface ?? theme.colorScheme.surfaceContainerLow,
      hover: premium?.hover ?? theme.colorScheme.surfaceContainerHighest,
      border: border,
      gridLine: border.withValues(alpha: isDark ? 0.24 : 0.30),
      textPrimary: premium?.textPrimary ?? theme.colorScheme.onSurface,
      textSecondary:
          premium?.textSecondary ?? theme.colorScheme.onSurfaceVariant,
      textMuted: premium?.textMuted ?? theme.colorScheme.outline,
      accent: accent,
      onAccent: premium?.onAccent ?? theme.colorScheme.onPrimary,
      shadowColor: premium?.shadow ??
          Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
      isDark: isDark,
      isPaper: false,
    );
  }

  final Color canvas;
  final Color surface;
  final Color raised;
  final Color sunken;
  final Color hover;
  final Color border;
  final Color gridLine;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color shadowColor;
  final bool isDark;
  final bool isPaper;

  /// A hover wash that begins at the same hue, so a fade never passes through
  /// grey on its way in.
  Color get hoverBase => hover.withValues(alpha: 0);

  Color get accentSoft => accent.withValues(alpha: isDark ? 0.22 : 0.11);

  /// The card shadow.
  ///
  /// Deliberately tighter than the shadow an embedded card wears on a page: a
  /// dashboard tiles its cards a gutter apart, and a wide shadow reaches over
  /// that gutter and prints a hard-edged smudge across the card next to it.
  List<BoxShadow> cardShadow({bool raised = false, bool dragging = false}) {
    if (dragging) {
      return [
        BoxShadow(
          color: shadowColor.withValues(alpha: isDark ? 0.4 : 0.16),
          blurRadius: 26,
          spreadRadius: -6,
          offset: const Offset(0, 12),
        ),
      ];
    }
    return [
      BoxShadow(
        color: shadowColor.withValues(
          alpha: isDark ? (raised ? 0.32 : 0.24) : (raised ? 0.09 : 0.055),
        ),
        blurRadius: raised ? 14 : 10,
        spreadRadius: -3,
        offset: Offset(0, raised ? 4 : 3),
      ),
      if (isDark)
        BoxShadow(
          color: Colors.white.withValues(alpha: raised ? 0.08 : 0.055),
          spreadRadius: 0.5,
        )
      else
        BoxShadow(
          color: shadowColor.withValues(alpha: raised ? 0.05 : 0.038),
          blurRadius: 2,
          spreadRadius: -1,
          offset: const Offset(0, 1),
        ),
    ];
  }

  /// The ring drawn over a card that is being configured.
  ///
  /// It sits in `foregroundDecoration` so the card's own clip cannot eat half
  /// of it, and it is the ONLY outline a card ever wears.
  BoxDecoration selectionRing({
    required bool selected,
    required double radius,
  }) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? accent.withValues(alpha: 0.38) : Colors.transparent,
          width: 1.2,
        ),
      );

  /// Settle a widget's chosen colour onto the surface it is painted over.
  DashboardTone toneFor(DashboardAccent accent) {
    if (accent == DashboardAccent.neutral) {
      return DashboardTone(
        surface: surface,
        border: border.withValues(alpha: isDark ? 0.5 : 0.34),
        ink: textPrimary,
        inkSoft: textSecondary,
        strong: this.accent,
      );
    }
    if (accent == DashboardAccent.paper && isPaper) {
      return const DashboardTone(
        surface: PaperTheme.editorPreviewBackground,
        border: PaperTheme.strongBorder,
        ink: PaperTheme.textPrimary,
        inkSoft: PaperTheme.textSecondary,
        strong: PaperTheme.accent,
      );
    }
    final seed = _seedFor(accent);
    return DashboardTone(
      surface: Color.alphaBlend(
        seed.withValues(alpha: isDark ? 0.15 : 0.10),
        surface,
      ),
      border: seed.withValues(alpha: isDark ? 0.34 : 0.26),
      ink: textPrimary,
      inkSoft: textSecondary,
      strong: seed,
    );
  }

  Color _seedFor(DashboardAccent accent) => switch (accent) {
        DashboardAccent.neutral =>
          isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        DashboardAccent.paper =>
          isDark ? const Color(0xFFB59B79) : const Color(0xFFB08A55),
        DashboardAccent.blue =>
          isDark ? const Color(0xFF60A5FA) : const Color(0xFF2F7FE4),
        DashboardAccent.green =>
          isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
        DashboardAccent.amber =>
          isDark ? const Color(0xFFEAB308) : const Color(0xFFD9A100),
        DashboardAccent.orange =>
          isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
        DashboardAccent.red =>
          isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
        DashboardAccent.pink =>
          isDark ? const Color(0xFFF472B6) : const Color(0xFFDB2777),
        DashboardAccent.purple =>
          isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
        DashboardAccent.teal =>
          isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
      };

  /// The one saturated colour a widget's chosen accent resolves to.
  Color strongFor(DashboardAccent accent) =>
      accent == DashboardAccent.neutral ? this.accent : _seedFor(accent);

  @override
  bool operator ==(Object other) =>
      other is DashboardPalette &&
      other.canvas == canvas &&
      other.surface == surface &&
      other.accent == accent &&
      other.isDark == isDark &&
      other.isPaper == isPaper;

  @override
  int get hashCode => Object.hash(canvas, surface, accent, isDark, isPaper);
}

/// One accent, settled onto the surface it will be painted over.
@immutable
class DashboardTone {
  const DashboardTone({
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
  final Color strong;

  Color wash(double alpha) => strong.withValues(alpha: alpha);
}

/// The geometry and motion every dashboard surface answers to.
abstract final class DashboardMetrics {
  static const double cardRadius = 16;
  static const double controlRadius = 10;
  static const double chipRadius = 999;

  static const double controlSize = 28;
  static const double headerHeight = 30;

  /// The strip along a card's edge that resizes it.
  static const double resizeHandle = 14;
  static const double cornerHandle = 20;

  static const double gutter = 14;
  static const double sectionGap = 26;

  /// The configuration panel that slides in from the right.
  static const double panelWidth = 336;

  static const Duration hover = Duration(milliseconds: 150);
  static const Duration settle = Duration(milliseconds: 220);
  static const Duration reveal = Duration(milliseconds: 180);
  static const Curve curve = Curves.easeOutCubic;

  /// The smallest a widget may be made, in grid units.
  static const int minimumColumnSpan = 1;
  static const int minimumRowSpan = 1;
}

/// Typography for the dashboard.
///
/// Nothing states a weight where the surrounding text should be inherited
/// instead; where a weight IS wanted the variable axis is raised alongside it,
/// because the bundled faces ignore `fontWeight` on its own.
abstract final class DashboardType {
  static TextStyle title(DashboardPalette palette, {double size = 22}) =>
      TextStyle(
        fontSize: size,
        height: 1.2,
        letterSpacing: -0.4,
        fontWeight: FontWeight.w600,
        fontVariations: flowyFontVariationsForWeight(FontWeight.w600),
        color: palette.textPrimary,
      );

  static TextStyle sectionLabel(DashboardPalette palette) => TextStyle(
        fontSize: 12,
        height: 1.2,
        letterSpacing: 0.5,
        fontWeight: FontWeight.w600,
        fontVariations: flowyFontVariationsForWeight(FontWeight.w600),
        color: palette.textMuted,
      );

  static TextStyle cardTitle(DashboardPalette palette, {Color? color}) =>
      TextStyle(
        fontSize: 13,
        height: 1.25,
        letterSpacing: -0.05,
        fontWeight: FontWeight.w600,
        fontVariations: flowyFontVariationsForWeight(FontWeight.w600),
        color: color ?? palette.textSecondary,
      );

  static TextStyle body(DashboardPalette palette, {Color? color}) => TextStyle(
        fontSize: 13.5,
        height: 1.4,
        color: color ?? palette.textPrimary,
      );

  static TextStyle caption(DashboardPalette palette, {Color? color}) =>
      TextStyle(
        fontSize: 11.5,
        height: 1.25,
        color: color ?? palette.textMuted,
      );

  /// A number that is the point of the widget.
  static TextStyle figure(DashboardPalette palette, {double size = 34}) =>
      TextStyle(
        fontSize: size,
        height: 1.05,
        letterSpacing: -1,
        fontWeight: FontWeight.w600,
        fontVariations: flowyFontVariationsForWeight(FontWeight.w600),
        fontFeatures: const [FontFeature.tabularFigures()],
        color: palette.textPrimary,
      );
}

/// A small borderless control: the card's menu, the toolbar's buttons.
class DashboardIconButton extends StatefulWidget {
  const DashboardIconButton({
    super.key,
    required this.icon,
    required this.palette,
    this.tooltip,
    this.onPressed,
    this.size = DashboardMetrics.controlSize,
    this.iconSize = 16,
    this.selected = false,
    this.color,
  });

  final IconData icon;
  final DashboardPalette palette;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool selected;
  final Color? color;

  @override
  State<DashboardIconButton> createState() => _DashboardIconButtonState();
}

class _DashboardIconButtonState extends State<DashboardIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final enabled = widget.onPressed != null;
    final ink = widget.color ??
        (widget.selected
            ? palette.accent
            : (_hovered ? palette.textPrimary : palette.textSecondary));

    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.accent.withValues(alpha: 0.14)
                : (_hovered && enabled ? palette.hover : palette.hoverBase),
            borderRadius:
                BorderRadius.circular(DashboardMetrics.controlRadius - 2),
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: enabled ? ink : palette.textMuted.withValues(alpha: 0.5),
          ),
        ),
      ),
    );

    final tooltip = widget.tooltip;
    return tooltip == null || tooltip.isEmpty
        ? button
        : Tooltip(message: tooltip, child: button);
  }
}

/// A labelled control: the mode switch, "Add widget", a template's name.
class DashboardButton extends StatefulWidget {
  const DashboardButton({
    super.key,
    required this.label,
    required this.palette,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.selected = false,
    this.tooltip,
  });

  final String label;
  final DashboardPalette palette;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool selected;
  final String? tooltip;

  @override
  State<DashboardButton> createState() => _DashboardButtonState();
}

class _DashboardButtonState extends State<DashboardButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final enabled = widget.onPressed != null;

    final Color background;
    final Color ink;
    if (widget.primary) {
      background = enabled
          ? (_hovered
              ? Color.alphaBlend(
                  Colors.black.withValues(alpha: palette.isDark ? 0 : 0.08),
                  palette.accent,
                )
              : palette.accent)
          : palette.accent.withValues(alpha: 0.4);
      ink = palette.onAccent;
    } else if (widget.selected) {
      background = palette.accent.withValues(alpha: 0.13);
      ink = palette.accent;
    } else {
      background = _hovered && enabled ? palette.hover : palette.hoverBase;
      ink = enabled ? palette.textSecondary : palette.textMuted;
    }

    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          height: 30,
          padding: EdgeInsets.symmetric(
            horizontal: widget.icon == null ? 13 : 11,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius:
                BorderRadius.circular(DashboardMetrics.controlRadius - 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 15, color: ink),
                const SizedBox(width: 6),
              ],
              // A button often carries a name it was handed — a page, a
              // place — so the label gives way rather than overflowing.
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardType.cardTitle(palette, color: ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final tooltip = widget.tooltip;
    return tooltip == null || tooltip.isEmpty
        ? button
        : Tooltip(message: tooltip, child: button);
  }
}

/// The quiet dot grid a dashboard is built on while it is being arranged.
class DashboardGridBackdrop extends StatelessWidget {
  const DashboardGridBackdrop({
    super.key,
    required this.palette,
    required this.step,
    required this.child,
    this.visible = true,
  });

  final DashboardPalette palette;
  final double step;
  final Widget child;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible || step <= 0) {
      return child;
    }
    return CustomPaint(
      painter: _DotGridPainter(color: palette.gridLine, step: step),
      child: child,
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color, required this.step});

  final Color color;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    if (step < 8) {
      return;
    }
    final paint = Paint()..color = color;
    for (var x = step / 2; x < size.width; x += step) {
      for (var y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.step != step;
}

/// What a widget shows when it has nothing to show yet.
class DashboardPlaceholder extends StatelessWidget {
  const DashboardPlaceholder({
    super.key,
    required this.palette,
    required this.icon,
    required this.message,
    this.action,
    this.onAction,
  });

  final DashboardPalette palette;
  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: palette.textMuted),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: DashboardType.caption(palette),
              ),
              if (action != null && onAction != null) ...[
                const SizedBox(height: 10),
                DashboardButton(
                  label: action!,
                  palette: palette,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      );
}
