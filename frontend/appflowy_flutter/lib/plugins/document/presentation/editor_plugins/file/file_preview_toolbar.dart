import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

class FilePreviewToolbar extends StatelessWidget {
  const FilePreviewToolbar({
    super.key,
    required this.leading,
    this.actions = const [],
  });

  final Widget leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final appFlowyTheme = AppFlowyTheme.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final backgroundColor = EditorSurfaceStyle.previewBackgroundFor(
      materialTheme.brightness,
      appFlowyTheme.fillColorScheme.content,
      isPaper: isPaper,
    );
    final borderColor = EditorSurfaceStyle.codeBlockBorderFor(
      materialTheme.brightness,
      appFlowyTheme.borderColorScheme.primary,
      isPaper: isPaper,
    );

    return Material(
      color: backgroundColor,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: borderColor,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: leading),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class FilePreviewToolbarButton extends StatefulWidget {
  const FilePreviewToolbarButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  State<FilePreviewToolbarButton> createState() =>
      _FilePreviewToolbarButtonState();
}

class _FilePreviewToolbarButtonState extends State<FilePreviewToolbarButton> {
  bool hovering = false;
  bool focused = false;
  bool pressing = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final materialTheme = Theme.of(context);
    final enabled = widget.onPressed != null;
    final premiumPalette = PremiumThemeExtension.maybeOf(context);
    final isLightPaper = materialTheme.brightness == Brightness.light &&
        PaperTheme.isEnabled(context);
    final hoverColor = isLightPaper
        ? PaperTheme.hoverOverlay
        : materialTheme.brightness == Brightness.dark
            ? const Color(0x12FFFFFF)
            : premiumPalette?.hover ?? theme.fillColorScheme.contentHover;
    final backgroundColor = pressing
        ? premiumPalette?.pressed ?? theme.fillColorScheme.contentVisibleHover
        : widget.selected
            ? isLightPaper
                ? PaperTheme.selectedOverlay
                : premiumPalette?.selected ?? theme.fillColorScheme.themeSelect
            : hovering || focused
                ? hoverColor
                : Colors.transparent;
    final focusBorder = isLightPaper
        ? PaperTheme.codeBlockBorder
        : theme.borderColorScheme.primary;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        child: AnimatedOpacity(
          duration: AppFlowyMotion.fast,
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
                duration: AppFlowyMotion.fast,
                curve: AppFlowyMotion.standardCurve,
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(7),
                  border: focused
                      ? Border.all(
                          color: focusBorder,
                          width: 0.75,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Icon(
                  widget.icon,
                  size: 16,
                  color: enabled
                      ? theme.iconColorScheme.secondary
                      : theme.iconColorScheme.quaternary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FilePreviewToolbarDivider extends StatelessWidget {
  const FilePreviewToolbarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: VerticalDivider(
        width: 1,
        color: AppFlowyTheme.of(context).borderColorScheme.primary,
      ),
    );
  }
}
