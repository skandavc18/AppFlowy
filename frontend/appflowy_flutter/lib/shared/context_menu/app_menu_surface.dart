import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_menu_style.dart';

/// The floating surface every menu in the application is drawn on.
///
/// Bespoke menus that cannot be expressed as a list of entries — colour grids,
/// pickers, panels — should still wrap their content in this so the card,
/// radius, border, shadow and blur are identical everywhere.
class AppMenuSurface extends StatelessWidget {
  const AppMenuSurface({
    super.key,
    required this.child,
    this.style,
    this.width,
    this.constraints,
    this.padding,
  });

  final Widget child;
  final AppMenuStyle? style;
  final double? width;
  final BoxConstraints? constraints;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? AppMenuStyle.of(context);
    final radius = style.borderRadius;

    Widget content = Padding(
      padding: padding ?? AppMenuMetrics.cardPadding,
      child: child,
    );

    if (constraints != null || width != null) {
      content = ConstrainedBox(
        constraints: (constraints ?? const BoxConstraints()).tighten(
          width: width,
        ),
        child: content,
      );
    }

    // The blur is what keeps the card feeling like glass over a document
    // rather than a solid slab dropped on top of it.
    final surface = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: AppMenuMetrics.blurSigma,
          sigmaY: AppMenuMetrics.blurSigma,
        ),
        child: ColoredBox(
          color: style.blurred ? style.translucentSurface : style.surface,
          child: content,
        ),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: style.shadows,
        ),
        // Painted in front of the clip so the hairline is a full, evenly
        // antialiased stroke instead of a half-pixel the clip ate into.
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: style.border, width: 0.8),
        ),
        child: surface,
      ),
    );
  }
}

/// One row of a menu.
///
/// Height, padding, icon slot, typography and hover wash are fixed here, so a
/// row cannot drift between one menu and the next.
class AppMenuRow extends StatefulWidget {
  const AppMenuRow({
    super.key,
    required this.label,
    this.icon,
    this.iconWidget,
    this.subtitle,
    this.shortcut,
    this.trailing,
    this.hasSubmenu = false,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
    this.highlighted = false,
    this.tracksHover = false,
    this.labelColor,
    this.onTap,
    this.onHover,
    this.onExit,
    this.style,
  });

  final String label;
  final IconData? icon;
  final Widget? iconWidget;
  final String? subtitle;
  final String? shortcut;
  final Widget? trailing;
  final bool hasSubmenu;
  final bool enabled;
  final bool selected;
  final bool destructive;

  /// Driven by the keyboard and by the menu's hover intent, not by the row's
  /// own pointer state, so exactly one row is ever emphasised.
  final bool highlighted;

  /// For rows that live outside a menu the application drives — they light up
  /// under their own pointer instead.
  final bool tracksHover;

  /// Overrides the label colour, for the few rows that name their own tone.
  final Color? labelColor;

  final VoidCallback? onTap;
  final ValueChanged<PointerEvent>? onHover;
  final VoidCallback? onExit;
  final AppMenuStyle? style;

  @override
  State<AppMenuRow> createState() => _AppMenuRowState();
}

class _AppMenuRowState extends State<AppMenuRow> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? AppMenuStyle.of(context);
    final enabled = widget.enabled;
    final active =
        enabled && (widget.highlighted || (widget.tracksHover && _hovered));

    // A row answers the pointer with its background and nothing else. Moving
    // the label and the icon to a stronger ink at the same time reads as the
    // whole row changing, which is louder than a hover should ever be.
    final labelColor = widget.labelColor ??
        style.labelColorFor(
          enabled: enabled,
          destructive: widget.destructive,
        );
    final iconColor = style.iconColorFor(
      enabled: enabled,
      destructive: widget.destructive,
      selected: widget.selected,
    );

    // Every resting colour keeps the hover colour's own channels, because a
    // tween that starts at [Colors.transparent] passes through transparent
    // *black* and flashes dark before it settles.
    final Color background;
    if (!enabled) {
      background = style.hoverBase;
    } else if (_pressed) {
      background = style.pressed;
    } else if (active) {
      background = widget.selected
          ? Color.alphaBlend(style.hover, style.selected)
          : style.hover;
    } else if (widget.selected) {
      background = style.selected;
    } else {
      background = style.hoverBase;
    }

    final leading = widget.iconWidget ??
        (widget.icon == null
            ? null
            : Icon(widget.icon, size: AppMenuMetrics.iconSize));

    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final Widget? trailing = widget.trailing ??
        (widget.hasSubmenu
            ? Icon(
                Icons.chevron_right_rounded,
                size: AppMenuMetrics.submenuArrowSize,
                color: enabled
                    ? style.iconMuted
                    : style.iconMuted.withValues(alpha: 0.5),
              )
            : widget.shortcut != null
                ? Text(
                    widget.shortcut!,
                    style: style.shortcutStyle.copyWith(
                      color: enabled
                          ? style.textMuted
                          : style.textMuted.withValues(alpha: 0.5),
                    ),
                  )
                // A checked row says so on the right, leaving the leading slot
                // for the row's own glyph.
                : widget.selected
                    ? Icon(
                        Icons.check_rounded,
                        size: AppMenuMetrics.submenuArrowSize,
                        color: style.accent,
                      )
                    : null);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (event) {
        if (widget.tracksHover) {
          setState(() => _hovered = true);
        }
        widget.onHover?.call(event);
      },
      onHover: widget.onHover,
      onExit: (_) {
        if (_pressed || _hovered) {
          setState(() {
            _pressed = false;
            _hovered = false;
          });
        }
        widget.onExit?.call();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled
            ? () {
                setState(() => _pressed = false);
                widget.onTap?.call();
              }
            : null,
        child: AnimatedContainer(
          duration: AppMenuMetrics.hoverDuration,
          curve: AppMenuMetrics.hoverCurve,
          height: widget.subtitle == null
              ? AppMenuMetrics.rowHeight
              : AppMenuMetrics.rowHeightWithSubtitle,
          padding: const EdgeInsets.symmetric(
            horizontal: AppMenuMetrics.rowHorizontalPadding,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: style.rowBorderRadius,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                SizedBox(
                  width: AppMenuMetrics.iconSlot,
                  height: AppMenuMetrics.iconSlot,
                  child: Center(
                    child: TweenAnimationBuilder<Color?>(
                      duration: AppMenuMetrics.hoverDuration,
                      curve: AppMenuMetrics.hoverCurve,
                      tween: ColorTween(end: iconColor),
                      builder: (context, color, child) => IconTheme.merge(
                        data: IconThemeData(
                          color: color,
                          size: AppMenuMetrics.iconSize,
                        ),
                        child: child!,
                      ),
                      child: leading,
                    ),
                  ),
                ),
                const SizedBox(width: AppMenuMetrics.iconGap),
              ],
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: AppMenuMetrics.hoverDuration,
                  curve: AppMenuMetrics.hoverCurve,
                  style: style.labelStyle.copyWith(color: labelColor),
                  child: widget.subtitle == null
                      ? label
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label,
                            const SizedBox(height: 3),
                            Text(
                              widget.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style.subtitleStyle,
                            ),
                          ],
                        ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 16),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The hairline that groups rows.
class AppMenuSeparatorLine extends StatelessWidget {
  const AppMenuSeparatorLine({super.key, this.style});

  final AppMenuStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? AppMenuStyle.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppMenuMetrics.separatorInset,
        vertical: AppMenuMetrics.separatorSpacing,
      ),
      child: SizedBox(
        height: AppMenuMetrics.separatorThickness,
        child: ColoredBox(color: style.separator),
      ),
    );
  }
}

/// The small uppercase label naming a group of rows.
class AppMenuSectionLabel extends StatelessWidget {
  const AppMenuSectionLabel({super.key, required this.label, this.style});

  final String label;
  final AppMenuStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? AppMenuStyle.of(context);
    return Padding(
      padding: AppMenuMetrics.headerPadding,
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style.headerStyle,
      ),
    );
  }
}
