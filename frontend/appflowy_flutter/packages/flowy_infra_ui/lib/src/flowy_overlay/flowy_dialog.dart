import 'package:flutter/material.dart';

const _overlayContainerPadding = EdgeInsets.symmetric(vertical: 12);
const overlayContainerMaxWidth = 760.0;
const overlayContainerMinWidth = 320.0;
const _defaultInsetPadding =
    EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0);

/// The same native dialog route for legacy overlays and newer app dialogs.
/// Theme capture, closed-loop focus traversal and barrier/Escape semantics
/// remain Flutter's; only the scrim and optional motion differ.
Future<T?> showFlowyDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final theme = Theme.of(context);
  final media = MediaQuery.maybeOf(context);
  return navigator.push<T>(
    _FlowyDialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ??
          theme.colorScheme.surface.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.38 : 0.68,
          ),
      reduceMotion: (media?.disableAnimations ?? false) ||
          (media?.accessibleNavigation ?? false),
    ),
  );
}

class _FlowyDialogRoute<T> extends DialogRoute<T> {
  _FlowyDialogRoute({
    required super.context,
    required super.builder,
    required super.themes,
    required super.barrierDismissible,
    required super.barrierColor,
    required this.reduceMotion,
    super.traversalEdgeBehavior = TraversalEdgeBehavior.closedLoop,
  });

  final bool reduceMotion;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 120);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final media = MediaQuery.maybeOf(context);
    if (reduceMotion ||
        (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false)) {
      return child;
    }
    return super
        .buildTransitions(context, animation, secondaryAnimation, child);
  }
}

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
    final media = MediaQuery.of(context);
    final windowSize = media.size;
    final size = windowSize * 0.7;
    final effectiveShape = shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));
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
      insetAnimationDuration:
          media.disableAnimations || media.accessibleNavigation
              ? Duration.zero
              : const Duration(milliseconds: 100),
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
          color: backgroundColor ?? theme.dialogBackgroundColor,
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
              Flexible(
                child: Container(
                  height: expandHeight ? size.height : null,
                  width: width ?? size.width,
                  constraints: constraints,
                  child: Padding(
                    padding: padding,
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
