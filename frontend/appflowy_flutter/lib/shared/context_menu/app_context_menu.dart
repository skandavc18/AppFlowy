import 'package:flutter/material.dart';

import 'app_menu_entry.dart';
import 'app_menu_overlay.dart';
import 'app_menu_style.dart';

export 'app_menu_entry.dart';
export 'app_menu_overlay.dart'
    show AppMenuPlacement, AppMenuScope, showAppMenu, showAppMenuForWidget;
export 'app_menu_style.dart' show AppMenuMetrics, AppMenuStyle;
export 'app_menu_surface.dart'
    show AppMenuRow, AppMenuSectionLabel, AppMenuSeparatorLine, AppMenuSurface;

/// Builds a menu's entries the moment it is opened, so rows can reflect the
/// state of the thing that was clicked.
typedef AppMenuEntriesBuilder = List<AppMenuEntry> Function();

/// Wraps any widget with the application's right-click menu.
///
/// The child keeps every gesture it already had — the menu is hung off the
/// secondary tap, which nothing else in the application uses.
class AppContextMenuRegion extends StatelessWidget {
  const AppContextMenuRegion({
    super.key,
    required this.child,
    required this.entries,
    this.enabled = true,
    this.width,
    this.behavior = HitTestBehavior.deferToChild,
    this.onOpened,
    this.onClosed,
  });

  final Widget child;
  final AppMenuEntriesBuilder entries;
  final bool enabled;
  final double? width;
  final HitTestBehavior behavior;
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;

  Future<void> _show(BuildContext context, Offset globalPosition) async {
    final items = entries();
    if (items.isEmpty) {
      return;
    }
    onOpened?.call();
    await showAppMenu<void>(
      context: context,
      entries: items,
      globalPosition: globalPosition,
      width: width,
    );
    onClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: behavior,
      onSecondaryTapDown:
          enabled ? (details) => _show(context, details.globalPosition) : null,
      onLongPressStart: enabled
          ? (details) => _show(context, details.globalPosition)
          : null,
      child: child,
    );
  }
}

/// The trigger every three-dot, chevron and overflow button uses.
///
/// It owns its own hover wash and keeps the menu's open state, so the button
/// stays lit while its menu is up.
class AppMenuIconButton extends StatefulWidget {
  const AppMenuIconButton({
    super.key,
    required this.icon,
    required this.entries,
    this.tooltip,
    this.size = 26,
    this.iconSize = 17,
    this.radius = 8,
    this.iconColor,
    this.enabled = true,
    this.placement = AppMenuPlacement.belowEnd,
    this.width,
    this.onVisibilityChanged,
  });

  final IconData icon;
  final AppMenuEntriesBuilder entries;
  final String? tooltip;
  final double size;
  final double iconSize;
  final double radius;
  final Color? iconColor;
  final bool enabled;
  final AppMenuPlacement placement;
  final double? width;
  final ValueChanged<bool>? onVisibilityChanged;

  @override
  State<AppMenuIconButton> createState() => _AppMenuIconButtonState();
}

class _AppMenuIconButtonState extends State<AppMenuIconButton> {
  bool _hovered = false;
  bool _open = false;

  Future<void> _show() async {
    final items = widget.entries();
    if (items.isEmpty) {
      return;
    }
    setState(() => _open = true);
    widget.onVisibilityChanged?.call(true);
    await showAppMenuForWidget<void>(
      context: context,
      entries: items,
      placement: widget.placement,
      width: widget.width,
    );
    if (mounted) {
      setState(() => _open = false);
    }
    widget.onVisibilityChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final style = AppMenuStyle.of(context);
    final active = _hovered || _open;
    final button = MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _show : null,
        child: AnimatedContainer(
          duration: AppMenuMetrics.hoverDuration,
          curve: AppMenuMetrics.hoverCurve,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            // Keeps the hover colour's channels while transparent, so the
            // wash never fades through transparent black.
            color: active ? style.hover : style.hoverBase,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          alignment: Alignment.center,
          child: TweenAnimationBuilder<Color?>(
            duration: AppMenuMetrics.hoverDuration,
            curve: AppMenuMetrics.hoverCurve,
            tween: ColorTween(
              end: widget.enabled
                  ? widget.iconColor ?? (active ? style.iconStrong : style.icon)
                  : style.iconMuted.withValues(alpha: 0.5),
            ),
            builder: (context, color, _) => Icon(
              widget.icon,
              size: widget.iconSize,
              color: color,
            ),
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
