import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flutter/material.dart';

import 'astrology_style.dart';

/// A button in the dashboard's own language: a quiet control with a hover
/// fill, or one filled accent for a primary action. Its icon follows the
/// chosen icon style, so Vivid draws the colored artwork.
class AstrologyButton extends StatelessWidget {
  const AstrologyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.id,
    this.icon,
    this.primary = false,
    this.selected = false,
    this.busy = false,
    this.tooltip,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Keys the actual [TextButton], so finders reach the native control.
  final String? id;
  final IconData? icon;
  final bool primary;
  final bool selected;
  final bool busy;
  final String? tooltip;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final enabled = onPressed != null;
    final ink = !enabled
        ? palette.muted
        : primary
            ? palette.onAccent
            : selected
                ? palette.accent
                : palette.ink;
    final base = WorkspaceChrome.controlStyle(context, selected: selected);
    final button = TextButton(
      key: id == null ? null : ValueKey(id!),
      focusNode: focusNode,
      onPressed: onPressed,
      style: base.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        foregroundColor: WidgetStatePropertyAll(ink),
        iconColor: WidgetStatePropertyAll(ink),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return palette.control;
          final active = states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed);
          if (primary) {
            return active
                ? Color.alphaBlend(
                    palette.ink.withValues(alpha: 0.12),
                    palette.accent,
                  )
                : palette.accent;
          }
          if (selected) {
            return active
                ? Color.alphaBlend(palette.hover, palette.selection)
                : palette.selection;
          }
          return active ? palette.hover : palette.control;
        }),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PremiumTheme.controlRadius),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(strokeWidth: 1.7, color: ink),
            )
          else if (icon != null)
            WorkspaceGlyph(
              icon!,
              size: 16,
              color: ink,
              role: primary || !enabled
                  ? WorkspaceGlyphRole.preserveInk
                  : WorkspaceGlyphRole.standard,
            ),
          if (busy || icon != null) const SizedBox(width: 7),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// One tab of [AstrologyTabs].
@immutable
class AstrologyTab {
  const AstrologyTab({required this.id, required this.label, this.icon});

  final String id;
  final String label;
  final IconData? icon;
}

/// Pill tabs like the rest of the workspace: the chosen one wears a soft
/// accent, the others stay quiet until hovered.
class AstrologyTabs extends StatelessWidget {
  const AstrologyTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<AstrologyTab> tabs;
  final String selected;

  /// Null disables every tab.
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(PremiumTheme.controlRadius + 3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final tab in tabs)
              Flexible(
                child: Semantics(
                  selected: tab.id == selected,
                  inMutuallyExclusiveGroup: true,
                  child: _TabButton(
                    key: ValueKey(tab.id),
                    tab: tab,
                    selected: tab.id == selected,
                    onPressed:
                        onSelected == null ? null : () => onSelected!(tab.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.selected,
    required this.onPressed,
  });

  final AstrologyTab tab;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final enabled = onPressed != null;
    final ink = !enabled
        ? palette.muted
        : selected
            ? palette.ink
            : palette.muted;
    return TextButton(
      onPressed: onPressed,
      style: WorkspaceChrome.controlStyle(context).copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        foregroundColor: WidgetStatePropertyAll(ink),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (selected) return palette.surface;
          return enabled &&
                  (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused))
              ? palette.hover
              : palette.control.withValues(alpha: 0);
        }),
        shadowColor: WidgetStatePropertyAll(palette.shadow),
        elevation: WidgetStatePropertyAll(selected ? 1 : 0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PremiumTheme.controlRadius),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tab.icon != null) ...[
            WorkspaceGlyph(
              tab.icon!,
              size: 16,
              color: ink,
              role: enabled
                  ? WorkspaceGlyphRole.standard
                  : WorkspaceGlyphRole.preserveInk,
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontVariations: [
                  FontVariation.weight(selected ? 600 : 500),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
