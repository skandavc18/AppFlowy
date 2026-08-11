import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

/// The colours every visual block — diagram, mind map, equation, drawing —
/// is dressed in.
///
/// One reading for the four of them is what stops the page collecting four
/// slightly different cards. Paper mode keeps its warm stationery instead of
/// falling back to a cool grey.
@immutable
class VisualBlockPalette {
  const VisualBlockPalette({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.hover,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.onAccent,
    required this.isDark,
    required this.isPaper,
  });

  factory VisualBlockPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPaper = !isDark && PaperTheme.isEnabled(context);

    if (isPaper) {
      return const VisualBlockPalette(
        canvas: PaperTheme.editorBackground,
        surface: PaperTheme.editorPreviewBackground,
        raised: PaperTheme.popupBackground,
        hover: PaperTheme.controlHover,
        border: PaperTheme.strongBorder,
        text: PaperTheme.textPrimary,
        textSecondary: PaperTheme.textSecondary,
        textMuted: PaperTheme.textMuted,
        accent: PaperTheme.accent,
        accentSoft: Color(0x14715438),
        onAccent: PaperTheme.onAccent,
        isDark: false,
        isPaper: true,
      );
    }

    final accent = premium?.accent ?? theme.colorScheme.primary;
    return VisualBlockPalette(
      canvas: premium?.canvas ?? theme.colorScheme.surface,
      surface: premium?.surface ?? theme.colorScheme.surfaceContainerLowest,
      raised: premium?.floatingSurface ?? theme.colorScheme.surfaceBright,
      hover: premium?.hover ?? theme.colorScheme.surfaceContainerHighest,
      border: premium?.border ?? theme.colorScheme.outlineVariant,
      text: premium?.textPrimary ?? theme.colorScheme.onSurface,
      textSecondary:
          premium?.textSecondary ?? theme.colorScheme.onSurfaceVariant,
      textMuted: premium?.textMuted ?? theme.colorScheme.outline,
      accent: accent,
      accentSoft: accent.withValues(alpha: isDark ? 0.20 : 0.10),
      onAccent: premium?.onAccent ?? theme.colorScheme.onPrimary,
      isDark: isDark,
      isPaper: false,
    );
  }

  final Color canvas;
  final Color surface;
  final Color raised;
  final Color hover;
  final Color border;
  final Color text;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color onAccent;
  final bool isDark;
  final bool isPaper;

  /// A hover wash that starts at the same hue, so a fade never passes through
  /// grey on its way in.
  Color get hoverBase => hover.withValues(alpha: 0);

  @override
  bool operator ==(Object other) =>
      other is VisualBlockPalette &&
      other.canvas == canvas &&
      other.surface == surface &&
      other.accent == accent &&
      other.isDark == isDark &&
      other.isPaper == isPaper;

  @override
  int get hashCode => Object.hash(canvas, surface, accent, isDark, isPaper);
}

/// The geometry and motion the visual blocks share.
abstract final class VisualBlockMetrics {
  /// Matches every other embedded card in a document.
  static double get cardRadius => EditorSurfaceStyle.embedCornerRadius;

  static const double headerHeight = 34;
  static const double controlSize = 26;
  static const double controlRadius = 8;
  static const double gutter = 10;

  static const Duration hover = Duration(milliseconds: 150);
  static const Duration reveal = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;

  /// A block is never taller than this on a page; fullscreen is where a big
  /// drawing belongs.
  static const double maximumEmbedHeight = 900;
}

/// A borderless, 26px control used across the four blocks' headers and
/// toolbars.
class VisualBlockButton extends StatefulWidget {
  const VisualBlockButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.selected = false,
    this.palette,
    this.size = VisualBlockMetrics.controlSize,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool selected;
  final VisualBlockPalette? palette;
  final double size;

  @override
  State<VisualBlockButton> createState() => _VisualBlockButtonState();
}

class _VisualBlockButtonState extends State<VisualBlockButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette ?? VisualBlockPalette.of(context);
    final enabled = widget.onTap != null;
    final background = widget.selected
        ? palette.accentSoft
        : _hovered
            ? palette.hover
            : palette.hoverBase;
    final foreground = !enabled
        ? palette.textMuted.withValues(alpha: 0.5)
        : widget.selected
            ? palette.accent
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
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: VisualBlockMetrics.hover,
              curve: VisualBlockMetrics.curve,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: background,
                borderRadius:
                    BorderRadius.circular(VisualBlockMetrics.controlRadius),
              ),
              child: Icon(widget.icon, size: 16, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact segmented control — Preview | Source, Select | Draw — built from
/// the same tokens as the buttons so nothing reads as a Material widget.
class VisualBlockSegments<T> extends StatelessWidget {
  const VisualBlockSegments({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
    this.palette,
  });

  final T value;
  final List<({T value, IconData icon, String label})> segments;
  final ValueChanged<T> onChanged;
  final VisualBlockPalette? palette;

  @override
  Widget build(BuildContext context) {
    final colours = palette ?? VisualBlockPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colours.hover.withValues(alpha: colours.isDark ? 0.5 : 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final segment in segments)
            _Segment(
              icon: segment.icon,
              label: segment.label,
              selected: segment.value == value,
              palette: colours,
              onTap: () => onChanged(segment.value),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VisualBlockPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: VisualBlockMetrics.hover,
            curve: VisualBlockMetrics.curve,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? palette.raised : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: palette.border.withValues(alpha: 0.30),
                        blurRadius: 6,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: selected ? palette.accent : palette.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? palette.text : palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The empty state a block wears before it has anything to show.
class VisualBlockPlaceholder extends StatelessWidget {
  const VisualBlockPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    return Semantics(
      button: onTap != null,
      label: '$title. $subtitle',
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: palette.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: palette.accent),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
