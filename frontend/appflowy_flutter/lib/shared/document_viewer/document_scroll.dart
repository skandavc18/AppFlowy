import 'dart:math' as math;

import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// The single kinetic tuning every document renderer scrolls with.
///
/// Flutter scrollables, the embedded web renderers and the PDF matrix viewer
/// all consume this one configuration, which is what makes a wheel notch
/// travel the same distance and decay the same way in every viewer.
const documentScrollConfig = PremiumScrollPhysicsConfig();

/// Exponential fling decay in inverse seconds.
///
/// Lower coasts longer. This produces the long, calm tail of Preview and
/// Safari without feeling sluggish at the start of a flick.
const double documentFlingFriction = 2.8;

/// Critically damped: motion settles exactly and never overshoots.
const SpringDescription documentSettleSpring = SpringDescription(
  mass: 0.5,
  stiffness: 100,
  damping: 14.14213562,
);

/// Scroll physics shared by every Flutter-rendered document surface.
///
/// Platform behaviour is preserved where it is genuinely native — Apple
/// platforms keep rubber-band overscroll, Windows and Linux clamp — while
/// impulse, inertia and deceleration stay identical everywhere.
class DocumentScrollPhysics extends ScrollPhysics {
  const DocumentScrollPhysics({
    super.parent,
    this.flingFriction = documentFlingFriction,
  }) : assert(flingFriction > 0);

  final double flingFriction;

  static ScrollPhysics platformBase([TargetPlatform? platform]) {
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS =>
        const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      _ => const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
    };
  }

  /// Whether the platform provides native overscroll bounce.
  static bool platformBounces([TargetPlatform? platform]) {
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };
  }

  @override
  DocumentScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return DocumentScrollPhysics(
      parent: buildParent(ancestor),
      flingFriction: flingFriction,
    );
  }

  @override
  SpringDescription get spring => documentSettleSpring;

  @override
  double get minFlingVelocity => 40;

  @override
  double get maxFlingVelocity => documentScrollConfig.maxVelocity;

  @override
  double get dragStartDistanceMotionThreshold => 3;

  /// Keeps the reading position stable: focus traversal and semantics never
  /// scroll the document on their own.
  @override
  bool get allowImplicitScrolling => false;

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (platformBounces()) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tolerance = toleranceFor(position);
    if (position.outOfRange) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        position.pixels > position.maxScrollExtent
            ? position.maxScrollExtent
            : position.minScrollExtent,
        math.min(0, velocity),
        tolerance: tolerance,
      );
    }
    if (velocity.abs() < tolerance.velocity ||
        (velocity > 0 && position.pixels >= position.maxScrollExtent) ||
        (velocity < 0 && position.pixels <= position.minScrollExtent)) {
      return null;
    }

    final simulation = FrictionSimulation(
      math.exp(-flingFriction),
      position.pixels,
      velocity,
      tolerance: tolerance,
    );

    // Land smoothly on the document edge rather than colliding with it.
    final endpoint = simulation.finalX;
    if (endpoint > position.maxScrollExtent) {
      return FrictionSimulation.through(
        position.pixels,
        position.maxScrollExtent,
        velocity,
        tolerance.velocity,
      );
    }
    if (endpoint < position.minScrollExtent) {
      return FrictionSimulation.through(
        position.pixels,
        position.minScrollExtent,
        velocity,
        -tolerance.velocity,
      );
    }
    return simulation;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentScrollPhysics &&
          other.flingFriction == flingFriction &&
          other.parent == parent;

  @override
  int get hashCode => Object.hash(flingFriction, parent);
}

/// Applies the shared scrolling stack to every scrollable in a document.
///
/// Renderers keep their own widgets and their own scroll views; this simply
/// hands each of them the same physics and the same overlay scrollbar, which
/// is what makes a text file, a notebook and an archive listing feel like one
/// application rather than three.
class DocumentScrollBehavior extends ScrollBehavior {
  const DocumentScrollBehavior({required this.delegate});

  final ScrollBehavior delegate;

  @override
  Set<PointerDeviceKind> get dragDevices => delegate.dragDevices;

  @override
  Set<LogicalKeyboardKey> get pointerAxisModifiers =>
      delegate.pointerAxisModifiers;

  @override
  TargetPlatform getPlatform(BuildContext context) =>
      delegate.getPlatform(context);

  @override
  MultitouchDragStrategy getMultitouchDragStrategy(BuildContext context) =>
      delegate.getMultitouchDragStrategy(context);

  @override
  GestureVelocityTrackerBuilder velocityTrackerBuilder(BuildContext context) =>
      delegate.velocityTrackerBuilder(context);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const DocumentScrollPhysics().applyTo(delegate.getScrollPhysics(context));

  /// Delegated so the premium wheel dispatcher stays installed.
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      delegate.buildOverscrollIndicator(context, child, details);

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    // Without a controller the overlay thumb has nothing to attach to, so the
    // platform scrollbar remains the safer choice.
    if (details.controller == null) {
      return delegate.buildScrollbar(context, child, details);
    }
    return DocumentScrollbar(controller: details.controller, child: child);
  }

  @override
  bool shouldNotify(covariant ScrollBehavior oldDelegate) =>
      oldDelegate is! DocumentScrollBehavior ||
      oldDelegate.delegate.runtimeType != delegate.runtimeType ||
      delegate.shouldNotify(oldDelegate.delegate);
}

/// Installs the shared scrolling stack for a document subtree.
///
/// When the host already provides premium scrolling the kinetic scope steps
/// aside: nesting two behaviours would square the desktop manipulation scale
/// and make trackpad panning crawl.
class DocumentScrollScope extends StatelessWidget {
  const DocumentScrollScope({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // The premium behaviour must be installed first so the document behaviour
    // can delegate to it, keeping the shared wheel dispatcher intact.
    final scoped = Builder(
      builder: (context) => ScrollConfiguration(
        behavior: DocumentScrollBehavior(
          delegate: ScrollConfiguration.of(context),
        ),
        child: child,
      ),
    );
    if (!enabled || ScrollConfiguration.of(context) is PremiumScrollBehavior) {
      return scoped;
    }
    return PremiumScrollScope(enabled: enabled, child: scoped);
  }
}

/// A thin overlay scrollbar that occupies no layout space.
///
/// It fades in while the document moves, fades out when it settles, and
/// thickens slightly when the pointer rests in the gutter so it stays an easy
/// drag target without ever shifting content.
class DocumentScrollbar extends StatefulWidget {
  const DocumentScrollbar({
    super.key,
    required this.controller,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final ScrollController? controller;
  final Widget child;

  /// Insets the thumb so it clears the floating chrome.
  final EdgeInsets padding;

  static const double thickness = 6;
  static const double hoveredThickness = 9;

  /// Width of the invisible hover target along the trailing edge.
  static const double gutterWidth = 22;

  static const Duration fadeDuration = AppFlowyMotion.deliberate;
  static const Duration timeToFade = Duration(milliseconds: 900);

  @override
  State<DocumentScrollbar> createState() => _DocumentScrollbarState();
}

class _DocumentScrollbarState extends State<DocumentScrollbar> {
  bool gutterHovered = false;

  @override
  Widget build(BuildContext context) {
    final thumb = DocumentViewportScrollThumb.colorOf(context);
    final thickness = gutterHovered
        ? DocumentScrollbar.hoveredThickness
        : DocumentScrollbar.thickness;

    return MouseRegion(
      opaque: false,
      onHover: _handleHover,
      onExit: (_) => _setHovered(false),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: thickness),
        duration: AppFlowyMotion.fast,
        curve: AppFlowyMotion.standardCurve,
        builder: (context, value, child) => RawScrollbar(
          controller: widget.controller,
          thumbColor: thumb,
          thickness: value,
          radius: Radius.circular(value / 2),
          minThumbLength: 42,
          mainAxisMargin: 6,
          crossAxisMargin: 4,
          padding: widget.padding,
          interactive: true,
          fadeDuration: DocumentScrollbar.fadeDuration,
          timeToFade: DocumentScrollbar.timeToFade,
          child: child!,
        ),
        child: widget.child,
      ),
    );
  }

  void _handleHover(PointerHoverEvent event) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return;
    }
    final distance = box.size.width - box.globalToLocal(event.position).dx;
    _setHovered(
      distance >= 0 && distance <= DocumentScrollbar.gutterWidth,
    );
  }

  void _setHovered(bool value) {
    if (gutterHovered != value) {
      setState(() => gutterHovered = value);
    }
  }
}

/// Resolves the overlay thumb colour without importing the whole style.
abstract final class DocumentViewportScrollThumb {
  static Color colorOf(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? const Color(0x59FFFFFF)
        : const Color(0x520F172A);
  }
}
