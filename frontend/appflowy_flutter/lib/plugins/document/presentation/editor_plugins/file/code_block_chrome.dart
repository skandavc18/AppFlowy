import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

const codeBlockAnimationDuration = AppFlowyMotion.standard;

/// The single surface every code layer paints on.
///
/// The header, the body and the code file editor all share it, so a code block
/// reads as one uniform card instead of a toolbar stacked on a page — and a
/// block in the editor matches a code file opened in the viewer exactly.
Color codeBlockSurfaceColor(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return const Color(0xFF18191D);
  }
  if (PaperTheme.isEnabled(context)) {
    return PaperTheme.codeBlockBackground;
  }
  return PremiumThemeExtension.maybeOf(context)?.surface ??
      const Color(0xFFFAF9F6);
}

class CodeBlockPalette {
  const CodeBlockPalette({
    required this.surface,
    required this.header,
    required this.terminal,
    required this.menu,
    required this.input,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.hover,
    required this.selected,
    required this.accent,
    required this.success,
    required this.error,
    required this.shadows,
  });

  factory CodeBlockPalette.resolve(BuildContext context) {
    final materialTheme = Theme.of(context);
    final appFlowyTheme = AppFlowyTheme.of(context);
    final brightness = materialTheme.brightness;
    final isPaper = PaperTheme.isEnabled(context);
    final premiumPalette = PremiumThemeExtension.maybeOf(context);
    final surface = codeBlockSurfaceColor(context);

    if (brightness == Brightness.dark) {
      return CodeBlockPalette(
        surface: surface,
        header: surface,
        terminal: const Color(0xFF141519),
        menu: const Color(0xFF202126),
        input: const Color(0xFF1E1F24),
        border: const Color(0x24FFFFFF),
        divider: const Color(0x14FFFFFF),
        textPrimary: const Color(0xFFE7E8EC),
        textSecondary: const Color(0xFFB0B3BC),
        textMuted: const Color(0xFF737780),
        hover: const Color(0x12FFFFFF),
        selected: const Color(0x267AA2F7),
        accent: const Color(0xFF8AB4F8),
        success: const Color(0xFF86D9A2),
        error: appFlowyTheme.textColorScheme.error,
        shadows: const [
          BoxShadow(
            color: Color(0x3D000000),
            blurRadius: 18,
            offset: Offset(0, 7),
            spreadRadius: -8,
          ),
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 5,
            offset: Offset(0, 2),
            spreadRadius: -2,
          ),
        ],
      );
    }

    if (isPaper) {
      return CodeBlockPalette(
        surface: surface,
        header: surface,
        terminal: PaperTheme.editorPreviewBackground,
        menu: PaperTheme.popupBackground,
        input: PaperTheme.controlBackground,
        border: PaperTheme.codeBlockBorder,
        divider: PaperTheme.codeBlockBorder.withValues(alpha: 0.7),
        textPrimary: appFlowyTheme.textColorScheme.primary,
        textSecondary: appFlowyTheme.textColorScheme.secondary,
        textMuted: appFlowyTheme.textColorScheme.tertiary,
        hover: PaperTheme.hoverOverlay,
        selected: PaperTheme.selectedOverlay,
        accent: PaperTheme.accent,
        success: const Color(0xFF53734F),
        error: appFlowyTheme.textColorScheme.error,
        shadows: const [
          BoxShadow(
            color: Color(0x123F352A),
            blurRadius: 14,
            offset: Offset(0, 5),
            spreadRadius: -6,
          ),
          BoxShadow(
            color: Color(0x0A3F352A),
            blurRadius: 4,
            offset: Offset(0, 1),
            spreadRadius: -1,
          ),
        ],
      );
    }

    final border =
        premiumPalette?.border ?? appFlowyTheme.borderColorScheme.primary;

    return CodeBlockPalette(
      surface: surface,
      header: surface,
      terminal: EditorSurfaceStyle.previewBackgroundFor(
        brightness,
        premiumPalette?.canvas ?? const Color(0xFFF1F0EC),
        isPaper: isPaper,
      ),
      menu: premiumPalette?.floatingSurface ??
          appFlowyTheme.surfaceColorScheme.primary,
      input: premiumPalette?.mutedSurface ??
          appFlowyTheme.fillColorScheme.contentHover,
      border: border,
      divider: border.withValues(alpha: 0.7),
      textPrimary: appFlowyTheme.textColorScheme.primary,
      textSecondary: appFlowyTheme.textColorScheme.secondary,
      textMuted: appFlowyTheme.textColorScheme.tertiary,
      hover:
          premiumPalette?.hover ?? appFlowyTheme.fillColorScheme.contentHover,
      selected:
          premiumPalette?.selected ?? appFlowyTheme.fillColorScheme.themeSelect,
      accent:
          premiumPalette?.accent ?? appFlowyTheme.fillColorScheme.themeThick,
      success: appFlowyTheme.textColorScheme.success,
      error: appFlowyTheme.textColorScheme.error,
      shadows: [
        BoxShadow(
          color: premiumPalette?.shadow ?? const Color(0x123F352A),
          blurRadius: 12,
          offset: const Offset(0, 4),
          spreadRadius: -5,
        ),
        BoxShadow(
          color: (premiumPalette?.shadow ?? const Color(0x123F352A))
              .withValues(alpha: 0.04),
          blurRadius: 7,
          offset: const Offset(0, 1),
          spreadRadius: -1,
        ),
      ],
    );
  }

  final Color surface;
  final Color header;
  final Color terminal;
  final Color menu;
  final Color input;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color hover;
  final Color selected;
  final Color accent;
  final Color success;
  final Color error;
  final List<BoxShadow> shadows;
}

TextStyle codeUiTextStyle({
  required Color color,
  required double fontSize,
  required FontWeight fontWeight,
}) =>
    getGoogleFontSafely(
      'JetBrains Mono',
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontColor: color,
      letterSpacing: -0.1,
    ).copyWith(
      fontFamilyFallback: const ['Geist Mono', 'RobotoMono', 'monospace'],
    );

class CodeHoverSurface extends StatefulWidget {
  const CodeHoverSurface({
    super.key,
    required this.palette,
    required this.child,
  });

  final CodeBlockPalette palette;
  final Widget child;

  @override
  State<CodeHoverSurface> createState() => _CodeHoverSurfaceState();
}

class _CodeHoverSurfaceState extends State<CodeHoverSurface> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: AnimatedContainer(
        duration: codeBlockAnimationDuration,
        curve: AppFlowyMotion.standardCurve,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: hovering ? widget.palette.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: widget.child,
      ),
    );
  }
}

/// The one control every code surface uses.
///
/// Material's `IconButton` brings its own metrics and ripples, which read as a
/// bootstrap form dropped into the code shell.
class CodeToolbarButton extends StatefulWidget {
  const CodeToolbarButton({
    super.key,
    required this.palette,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.label,
    this.selected = false,
    this.foregroundColor,
  });

  final CodeBlockPalette palette;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? label;
  final bool selected;
  final Color? foregroundColor;

  @override
  State<CodeToolbarButton> createState() => _CodeToolbarButtonState();
}

class _CodeToolbarButtonState extends State<CodeToolbarButton> {
  bool hovering = false;
  bool focused = false;
  bool pressing = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final foreground = widget.foregroundColor ?? widget.palette.textSecondary;
    final background = pressing
        ? Color.alphaBlend(
            widget.palette.textPrimary.withValues(alpha: 0.06),
            widget.palette.hover,
          )
        : widget.selected
            ? widget.palette.selected
            : hovering || focused
                ? widget.palette.hover
                : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        child: AnimatedOpacity(
          duration: codeBlockAnimationDuration,
          opacity: enabled ? 1 : 0.42,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              onHover:
                  enabled ? (value) => setState(() => hovering = value) : null,
              onFocusChange:
                  enabled ? (value) => setState(() => focused = value) : null,
              onHighlightChanged:
                  enabled ? (value) => setState(() => pressing = value) : null,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              borderRadius: BorderRadius.circular(7),
              child: AnimatedContainer(
                duration: codeBlockAnimationDuration,
                curve: AppFlowyMotion.standardCurve,
                height: 28,
                padding: EdgeInsets.symmetric(
                  horizontal: widget.label == null ? 7 : 8,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: AnimatedSwitcher(
                  duration: codeBlockAnimationDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: Row(
                    key: ValueKey((widget.icon, widget.label)),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 15, color: foreground),
                      if (widget.label != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          widget.label!,
                          style: codeUiTextStyle(
                            color: foreground,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CodeHeaderDivider extends StatelessWidget {
  const CodeHeaderDivider({super.key, required this.palette});

  final CodeBlockPalette palette;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 14,
        child: VerticalDivider(
          width: 0.5,
          thickness: 0.5,
          color: palette.divider,
        ),
      );
}
