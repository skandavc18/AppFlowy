import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// Popups that take over the window (search and a row's page) dim the page
/// behind them a little, soften it with a slight blur, and float in.
abstract final class FloatingModal {
  /// Gaussian sigma, in logical pixels, once the backdrop is fully shown.
  static const blur = 2.5;
  static const enterDuration = AppFlowyMotion.deliberate;
  static const exitDuration = AppFlowyMotion.standard;

  /// The theme's own scrim (warm in paper mode), lightened to a gentle dim.
  static Color barrierColor(BuildContext context) {
    final theme = Theme.of(context);
    final scrim = PremiumThemeExtension.maybeOf(context)?.scrim ??
        theme.colorScheme.scrim;
    final dark = theme.brightness == Brightness.dark;
    final alpha = math.min(scrim.a * (dark ? 0.5 : 0.32), dark ? 0.32 : 0.16);
    return scrim.withValues(alpha: alpha);
  }

  static bool reducesMotion(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return (media?.disableAnimations ?? false) ||
        (media?.accessibleNavigation ?? false);
  }
}

/// Shows [builder] floating over the whole window, which dims and softens
/// behind it. Theme capture, Escape, barrier dismissal and closed-loop focus
/// are those of an ordinary dialog.
Future<T?> showFloatingDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push<T>(
    _FloatingDialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor: FloatingModal.barrierColor(context),
      reduceMotion: FloatingModal.reducesMotion(context),
    ),
  );
}

/// The barrier of a floating popup: its dim and blur follow the route in and
/// out together, and it still dismisses the popup when clicked.
mixin FloatingModalBarrier<T> on ModalRoute<T> {
  @override
  Widget buildModalBarrier() => _BarrierBlur(
        animation: animation!,
        curve: barrierCurve,
        child: super.buildModalBarrier(),
      );
}

class _BarrierBlur extends StatelessWidget {
  const _BarrierBlur({
    required this.animation,
    required this.curve,
    required this.child,
  });

  final Animation<double> animation;
  final Curve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final sigma = FloatingModal.blur * curve.transform(animation.value);
          return BackdropFilter(
            enabled: sigma > 0,
            filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: child,
          );
        },
      );
}

/// A popup's arrival: it fades in while rising a few pixels and growing from
/// 97%, settling without overshoot. Leaving is quicker and accelerates away.
class FloatingModalEntrance extends StatefulWidget {
  const FloatingModalEntrance({
    super.key,
    required this.animation,
    required this.child,
    this.enabled = true,
    this.alignment = Alignment.center,
    this.offset = const Offset(0, 10),
  });

  final Animation<double> animation;

  /// False holds the popup at rest without changing the widget tree, so a
  /// focused field inside survives an accessibility change mid-route.
  final bool enabled;

  /// The point the popup grows from.
  final Alignment alignment;

  /// Where the popup starts, relative to where it settles.
  final Offset offset;

  final Widget child;

  @override
  State<FloatingModalEntrance> createState() => _FloatingModalEntranceState();
}

class _FloatingModalEntranceState extends State<FloatingModalEntrance> {
  static const _startScale = 0.97;

  late CurvedAnimation _progress = _curve(widget.animation);

  static CurvedAnimation _curve(Animation<double> parent) => CurvedAnimation(
        parent: parent,
        curve: AppFlowyMotion.enterCurve,
        // Reverse runs the parent from 1 to 0; flipping keeps the exit's
        // accelerate shape in real time.
        reverseCurve: AppFlowyMotion.exitCurve.flipped,
      );

  @override
  void didUpdateWidget(FloatingModalEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _progress.dispose();
      _progress = _curve(widget.animation);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _progress,
        child: widget.child,
        builder: (context, child) {
          final remaining = widget.enabled ? 1 - _progress.value : 0.0;
          final scale = 1 - (1 - _startScale) * remaining;
          return Opacity(
            opacity: 1 - remaining,
            child: Transform(
              alignment: widget.alignment,
              transform: Matrix4.translationValues(
                widget.offset.dx * remaining,
                widget.offset.dy * remaining,
                0,
              )..scale(scale, scale, 1.0),
              child: child,
            ),
          );
        },
      );
}

class _FloatingDialogRoute<T> extends DialogRoute<T>
    with FloatingModalBarrier<T> {
  _FloatingDialogRoute({
    required super.context,
    required super.builder,
    required super.themes,
    required super.barrierColor,
    required this.reduceMotion,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  final bool reduceMotion;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : FloatingModal.enterDuration;

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : FloatingModal.exitDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      FloatingModalEntrance(
        animation: animation,
        enabled: !reduceMotion && !FloatingModal.reducesMotion(context),
        child: child,
      );
}
