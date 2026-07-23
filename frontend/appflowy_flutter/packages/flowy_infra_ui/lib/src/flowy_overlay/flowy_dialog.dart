import 'package:flutter/material.dart';

const _overlayContainerPadding = EdgeInsets.symmetric(vertical: 12);
const overlayContainerMaxWidth = 760.0;
const overlayContainerMinWidth = 320.0;
const _defaultInsetPadding =
    EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0);

class FlowyDialog extends StatelessWidget {
  const FlowyDialog({
    super.key,
    required this.child,
    this.title,
    this.shape,
    this.constraints,
    this.padding = _overlayContainerPadding,
    this.backgroundColor,
    this.expandHeight = true,
    this.alignment,
    this.insetPadding,
    this.width,
    this.elevation,
    this.shadowColor,
    this.surfaceTintColor,
  });

  final Widget? title;
  final ShapeBorder? shape;
  final Widget child;
  final BoxConstraints? constraints;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final bool expandHeight;

  // Position of the Dialog
  final Alignment? alignment;

  // Inset of the Dialog
  final EdgeInsets? insetPadding;

  final double? width;
  final double? elevation;
  final Color? shadowColor;
  final Color? surfaceTintColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final windowSize = MediaQuery.of(context).size;
    final size = windowSize * 0.7;
    final effectiveShape = shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    final effectiveShadowColor = shadowColor ?? theme.shadowColor;
    final shadows = (elevation ?? 1) <= 0
        ? const <BoxShadow>[]
        : [
            BoxShadow(
              color: effectiveShadowColor.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
              spreadRadius: -8,
            ),
            BoxShadow(
              color: effectiveShadowColor.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
              spreadRadius: -2,
            ),
          ];

    return Dialog(
      alignment: alignment,
      insetPadding: insetPadding ?? _defaultInsetPadding,
      backgroundColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: effectiveShape,
      clipBehavior: Clip.none,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: backgroundColor ?? theme.cardColor,
          shape: effectiveShape,
          shadows: shadows,
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: effectiveShape,
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: title,
                ),
              Container(
                height: expandHeight ? size.height : null,
                width: width ?? size.width,
                constraints: constraints,
                child: Padding(
                  padding: padding,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
