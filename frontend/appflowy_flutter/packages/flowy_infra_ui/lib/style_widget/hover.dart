import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra/time/duration.dart';
import 'package:flutter/material.dart';

typedef HoverBuilder = Widget Function(BuildContext context, bool onHover);

class FlowyHover extends StatefulWidget {
  final HoverStyle? style;
  final HoverBuilder? builder;
  final Widget? child;

  final bool Function()? isSelected;
  final void Function(bool)? onHover;
  final MouseCursor? cursor;

  /// Reset the hover state when the parent widget get rebuild.
  /// Default to true.
  final bool resetHoverOnRebuild;

  /// Determined whether the [builder] should get called when onEnter/onExit
  /// happened
  ///
  /// [FlowyHover] show hover when [MouseRegion]'s onEnter get called
  /// [FlowyHover] hide hover when [MouseRegion]'s onExit get called
  ///
  final bool Function()? buildWhenOnHover;

  const FlowyHover({
    super.key,
    this.builder,
    this.child,
    this.style,
    this.isSelected,
    this.onHover,
    this.cursor,
    this.resetHoverOnRebuild = true,
    this.buildWhenOnHover,
  });

  @override
  State<FlowyHover> createState() => _FlowyHoverState();
}

class _FlowyHoverState extends State<FlowyHover> {
  bool _onHover = false;

  @override
  void didUpdateWidget(covariant FlowyHover oldWidget) {
    if (widget.resetHoverOnRebuild) {
      // Reset the _onHover to false when the parent widget get rebuild.
      _onHover = false;
    }

    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.isSelected?.call() ?? false;
    return MouseRegion(
      cursor: widget.cursor != null ? widget.cursor! : SystemMouseCursors.click,
      opaque: false,
      onHover: (_) => _setOnHover(true),
      onEnter: (_) => _setOnHover(true),
      onExit: (_) => _setOnHover(false),
      child: FlowyHoverContainer(
        style: widget.style ??
            HoverStyle(hoverColor: Theme.of(context).hoverColor),
        applyStyle: _onHover || selected,
        isSelected: selected,
        child: widget.child ?? widget.builder!(context, _onHover),
      ),
    );
  }

  void _setOnHover(bool isHovering) {
    if (isHovering == _onHover) return;

    if (widget.buildWhenOnHover?.call() ?? true) {
      setState(() => _onHover = isHovering);
      if (widget.onHover != null) {
        widget.onHover!(isHovering);
      }
    }
  }
}

class HoverStyle {
  final BoxBorder? border;
  final Color? hoverColor;
  final Color? foregroundColorOnHover;
  final BorderRadius borderRadius;
  final EdgeInsets contentMargin;
  final Color backgroundColor;

  const HoverStyle({
    this.border,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.contentMargin = EdgeInsets.zero,
    this.backgroundColor = Colors.transparent,
    this.hoverColor,
    this.foregroundColorOnHover,
  });

  const HoverStyle.transparent({
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.contentMargin = EdgeInsets.zero,
    this.backgroundColor = Colors.transparent,
    this.foregroundColorOnHover,
  })  : hoverColor = Colors.transparent,
        border = null;
}

class FlowyHoverContainer extends StatelessWidget {
  final HoverStyle style;
  final Widget child;
  final bool applyStyle;

  /// Legacy hover aliases are also used as selected menu/row surfaces. Only
  /// pointer feedback is softened; a persistent selection keeps its color.
  final bool isSelected;

  const FlowyHoverContainer({
    super.key,
    required this.child,
    required this.style,
    this.applyStyle = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.maybeOf(context);
    final reduced = (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
    final requestedColor = style.hoverColor ?? theme.hoverColor;
    final legacy = theme.extension<AFThemeExtension>();
    final isLegacyHover = requestedColor.a == 1 &&
        legacy != null &&
        (requestedColor == legacy.greyHover ||
            requestedColor == legacy.lightGreyHover ||
            requestedColor == legacy.toolbarHoverColor);
    // These aliases have mixed roles in the editor theme. Do not globally
    // turn them transparent: remap only this paint-only hover boundary.
    // Already-translucent custom aliases retain their original alpha/RGB.
    final hoverColor =
        !isSelected && isLegacyHover ? theme.hoverColor : requestedColor;
    final textTheme = theme.textTheme;
    final iconTheme = IconTheme.of(context);
    final restingTheme = theme.copyWith(iconTheme: iconTheme);
    // Hover changes only paint unless a caller explicitly requests new ink.
    // A default onSurface override used to snap secondary/status icons darker.
    final hoverTheme = style.foregroundColorOnHover == null
        ? restingTheme
        : restingTheme.copyWith(
            textTheme: textTheme.copyWith(
              bodyMedium: textTheme.bodyMedium?.copyWith(
                color:
                    style.foregroundColorOnHover ?? theme.colorScheme.onSurface,
              ),
            ),
            iconTheme: iconTheme.copyWith(
              color:
                  style.foregroundColorOnHover ?? theme.colorScheme.onSurface,
            ),
          );

    return AnimatedContainer(
      duration: reduced ? Duration.zero : FlowyDurations.fastest,
      curve: Curves.easeOutCubic,
      margin: style.contentMargin,
      decoration: BoxDecoration(
        border: style.border,
        color: applyStyle
            ? style.backgroundColor.a == 0
                ? hoverColor
                : Color.alphaBlend(hoverColor, style.backgroundColor)
            : style.backgroundColor.a == 0
                ? hoverColor.withValues(alpha: 0)
                : style.backgroundColor,
        borderRadius: style.borderRadius,
      ),
      child: Theme(
        data: applyStyle ? hoverTheme : restingTheme,
        child: child,
      ),
    );
  }
}
