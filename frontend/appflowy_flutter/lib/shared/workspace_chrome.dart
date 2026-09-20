import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_layout.dart';
import 'package:flutter/material.dart';

/// Shared hierarchy for workspace chrome, not a replacement theme or renderer.
abstract final class WorkspaceChrome {
  static const controlHeight = 32.0;
  static const controlRadius = 8.0;
  static const headerVerticalPadding = 4.0;

  /// Preserve the chosen face and fallbacks. Set both the ordinary weight and
  /// the variable axis, so a title does not inherit the body's lighter axis.
  static TextStyle title(BuildContext context, {bool compact = false}) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: PremiumThemeExtension.maybeOf(context)?.textPrimary ??
          theme.colorScheme.onSurface,
      fontSize: compact ? 26 : 38,
      height: compact ? 1.2 : 1.12,
      fontWeight: compact ? FontWeight.w600 : FontWeight.w700,
      fontVariations: [FontVariation.weight(compact ? 650 : 700)],
      letterSpacing: compact ? -0.45 : -0.9,
    );
  }

  static ButtonStyle controlStyle(BuildContext context, {Color? accent}) {
    final theme = Theme.of(context);
    final palette = PremiumThemeExtension.maybeOf(context);
    final ink =
        accent ?? palette?.textSecondary ?? theme.colorScheme.onSurfaceVariant;
    final focus = palette?.accent ?? theme.colorScheme.primary;
    final hover = palette?.hover ?? theme.colorScheme.surfaceContainer;
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
      foregroundColor: WidgetStatePropertyAll(ink),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? accent?.withValues(alpha: 0.16) ?? hover
            : accent?.withValues(alpha: 0.10) ?? hover.withValues(alpha: 0),
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.focused)
              ? focus
              : focus.withValues(alpha: 0),
        ),
      ),
      textStyle: WidgetStatePropertyAll(
        theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          height: 1.2,
          fontWeight: FontWeight.w500,
          fontVariations: const [FontVariation.weight(550)],
        ),
      ),
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 140),
    );
  }
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
