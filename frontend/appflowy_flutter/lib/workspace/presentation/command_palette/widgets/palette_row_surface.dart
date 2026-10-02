import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:flutter/material.dart';

/// What every palette row sits on: a quiet wash under the pointer and the
/// theme's selection tint on the active row. Both ease in and out, so moving
/// through the list glides instead of blinking.
class PaletteRowSurface extends StatefulWidget {
  const PaletteRowSurface({
    super.key,
    required this.active,
    required this.child,
    this.onHover,
  });

  /// The row being previewed, or the one the keyboard is on.
  final bool active;

  /// Called while the pointer is over the row and it is not yet active.
  final VoidCallback? onHover;

  final Widget child;

  @override
  State<PaletteRowSurface> createState() => _PaletteRowSurfaceState();
}

class _PaletteRowSurfaceState extends State<PaletteRowSurface> {
  bool _hovered = false;

  void _pointer(bool over) {
    if (over && !widget.active) widget.onHover?.call();
    if (over != _hovered) setState(() => _hovered = over);
  }

  @override
  Widget build(BuildContext context) {
    final hover = WorkspaceChrome.hoverColor(context);
    final selected = WorkspaceChrome.selectedColor(context);
    final fill = widget.active
        ? (_hovered ? Color.alphaBlend(hover, selected) : selected)
        // Fade out to the tint's own channels, never through transparent black.
        : (_hovered ? hover : selected.withValues(alpha: 0));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _pointer(true),
      onHover: (_) => _pointer(true),
      onExit: (_) => _pointer(false),
      child: AnimatedContainer(
        duration:
            WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
        curve: WorkspaceTokens.curve,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        ),
        child: widget.child,
      ),
    );
  }
}
