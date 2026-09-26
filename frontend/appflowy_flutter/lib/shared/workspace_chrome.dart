import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_layout.dart';
import 'package:flutter/material.dart';

/// Shared hierarchy for workspace chrome, not a replacement theme or renderer.
abstract final class WorkspaceChrome {
  static const controlHeight = WorkspaceTokens.controlHeight;
  static const controlRadius = WorkspaceTokens.controlRadius;
  static const headerVerticalPadding = 4.0;

  /// Preserve the chosen face and fallbacks. Set both the ordinary weight and
  /// the variable axis, so a title does not inherit the body's lighter axis.
  static TextStyle title(BuildContext context, {bool compact = false}) {
    return WorkspaceTypography.style(
      context,
      WorkspaceTextRole.pageTitle,
      compact: compact,
    );
  }

  static Color hoverColor(BuildContext context) =>
      PremiumThemeExtension.maybeOf(context)?.subtleHover ??
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04);

  static ButtonStyle controlStyle(
    BuildContext context, {
    Color? accent,
    bool selected = false,
  }) {
    final theme = Theme.of(context);
    final palette = PremiumThemeExtension.maybeOf(context);
    final ink =
        accent ?? palette?.textSecondary ?? theme.colorScheme.onSurfaceVariant;
    final focus = palette?.accent ?? theme.colorScheme.primary;
    final hover = hoverColor(context);
    final pressed =
        palette?.subtlePressed ?? hover.withValues(alpha: hover.a * 1.6);
    final selectedFill =
        palette?.selectedOverlay ?? focus.withValues(alpha: focus.a * 0.12);
    final disabled = palette?.textMuted ?? theme.disabledColor;
    final foreground = WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.disabled) ? disabled : ink,
    );
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, controlHeight)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
      foregroundColor: foreground,
      iconColor: foreground,
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? hover.withValues(alpha: 0)
            : states.contains(WidgetState.pressed)
                ? pressed
                : selected
                    ? selectedFill
                    : states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.focused)
                        ? hover
                        : hover.withValues(alpha: 0),
      ),
      overlayColor: WidgetStatePropertyAll(hover.withValues(alpha: 0)),
      splashFactory: NoSplash.splashFactory,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: !states.contains(WidgetState.disabled) &&
                  states.contains(WidgetState.focused)
              ? focus
              : focus.withValues(alpha: 0),
        ),
      ),
      textStyle: WidgetStatePropertyAll(
        theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          height: 1.2,
          fontWeight: FontWeight.w500,
          fontVariations: const [FontVariation.weight(500)],
        ),
      ),
      animationDuration:
          WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
    );
  }
}

/// Shared native control for file/code/archive chrome. The button retains its
/// focus and semantics when its glyph or label changes; no animated duplicate
/// action is inserted. Saved/custom artwork is deliberately not adapted here.
class WorkspaceControlButton extends StatelessWidget {
  const WorkspaceControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.selected = false,
    this.foregroundColor,
    this.iconRole,
    this.height = 28,
    this.iconSize = 16,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final String? label;
  final bool selected;
  final Color? foregroundColor;

  /// Distinguishes decorative emphasis from an explicit status color.
  /// Disabled ink always wins; existing status-colored callers stay unchanged.
  final WorkspaceGlyphRole? iconRole;
  final double height;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: TextButton(
          onPressed: onPressed,
          style: WorkspaceChrome.controlStyle(
            context,
            accent: foregroundColor,
            selected: selected,
          ).copyWith(
            minimumSize: WidgetStatePropertyAll(Size(height, height)),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: label == null ? 6 : 8,
                vertical: 4,
              ),
            ),
          ),
          child: Semantics(
            label: tooltip,
            selected: selected,
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(
                  builder: (context) => WorkspaceGlyph(
                    icon,
                    size: iconSize,
                    color: IconTheme.of(context).color,
                    role: onPressed == null
                        ? WorkspaceGlyphRole.preserveInk
                        : iconRole ??
                            (foregroundColor != null
                                ? WorkspaceGlyphRole.preserveInk
                                : WorkspaceGlyphRole.standard),
                  ),
                ),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(label!),
                ],
              ],
            ),
          ),
        ),
      );
}

/// Identity leads; tools move below it in a narrow pane. The tree stays the same
/// across breakpoints so resizing does not recreate a focused search field.
class WorkspaceHeaderLayout extends StatelessWidget {
  const WorkspaceHeaderLayout({
    super.key,
    required this.identity,
    required this.actions,
  });

  final Widget identity;
  final Widget actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final geometry = WorkspaceHeaderGeometry.resolve(
            availableWidth: WorkspaceLayout.availableWidth(
              constraints,
              fallbackWidth: MediaQuery.maybeSizeOf(context)?.width ??
                  WorkspaceLayout.headerBreakpoint,
            ),
            textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
          );
          // Always constrain the Wrap, including under unbounded hosts. The
          // same SizedBoxes retain their children at every width/text scale.
          return SizedBox(
            width: geometry.width,
            child: Wrap(
              spacing: WorkspaceHeaderGeometry.gap,
              runSpacing: WorkspaceHeaderGeometry.runGap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: geometry.identityWidth, child: identity),
                SizedBox(width: geometry.actionsWidth, child: actions),
              ],
            ),
          );
        },
      );
}
