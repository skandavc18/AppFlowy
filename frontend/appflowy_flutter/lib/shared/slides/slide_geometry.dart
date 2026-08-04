import 'dart:math' as math;

import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Where one slide sits, and how it is turned, for a given deck position.
///
/// Everything the renderer needs to draw a slide is worked out here as plain
/// numbers, so the arrangement can be tested without a screen.
@immutable
class SlidePlacement {
  const SlidePlacement({
    required this.index,
    required this.offset,
    required this.dx,
    required this.scale,
    required this.opacity,
    required this.tilt,
  });

  /// Which slide this is.
  final int index;

  /// How many slides away from the middle it is, with a sign.
  final double offset;

  /// Where its middle sits, measured from the middle of the stage.
  final double dx;

  final double scale;
  final double opacity;

  /// How far it is turned away from the reader, in radians.
  final double tilt;

  /// How near the middle it is, from 0 at the edge of the deck to 1.
  double get prominence => (1 - (offset.abs() / 2.4)).clamp(0.0, 1.0);

  bool get isActive => offset.abs() < 0.5;

  @override
  bool operator ==(Object other) =>
      other is SlidePlacement &&
      other.index == index &&
      other.offset == offset &&
      other.dx == dx &&
      other.scale == scale &&
      other.opacity == opacity &&
      other.tilt == tilt;

  @override
  int get hashCode => Object.hash(index, offset, dx, scale, opacity, tilt);
}

/// The arrangement of a deck: how big a slide is, where its neighbours go, and
/// which of them are worth building at all.
@immutable
class SlideDeckLayout {
  const SlideDeckLayout({
    required this.viewport,
    this.flow = SlideFlow.deck,
    this.wrap = false,
  });

  final Size viewport;
  final SlideFlow flow;
  final bool wrap;

  static const double minimumCardWidth = 300;
  static const double maximumCardWidth = 660;
  static const double minimumCardHeight = 240;
  static const double maximumCardHeight = 620;

  /// The gap between two slides standing side by side.
  static const double spacing = 26;

  /// How far a neighbour is turned away in cover flow.
  static const double maximumTilt = 0.62;

  /// The furthest a slide can be from the middle and still be built.
  static const int maximumSpan = 4;

  Size get cardSize {
    final width = (viewport.width * 0.52)
        .clamp(minimumCardWidth, maximumCardWidth)
        .toDouble();
    final height = (viewport.height * 0.9)
        .clamp(minimumCardHeight, maximumCardHeight)
        .toDouble();
    // A slide should never be taller than it is useful; past this it reads as
    // a column of whitespace.
    return Size(width, math.min(height, width * 1.32));
  }

  /// How far apart two neighbouring slides sit.
  double get step => switch (flow) {
        SlideFlow.deck => cardSize.width + spacing,
        SlideFlow.coverFlow => cardSize.width * 0.52 + spacing,
      };

  /// How many neighbours each side are worth building.
  int get span {
    if (viewport.width <= 0) {
      return 1;
    }
    final reach = (viewport.width / (2 * step)).ceil() + 1;
    return reach.clamp(1, maximumSpan);
  }

  /// Every slide near enough to the middle to be drawn, furthest first so a
  /// painter can lay them down in order and leave the active one on top.
  List<SlidePlacement> placements(double position, int count) {
    if (count <= 0 || viewport.isEmpty) {
      return const [];
    }
    final middle = position.round();
    final reach = span;
    final placements = <SlidePlacement>[];
    for (var step = -reach; step <= reach; step++) {
      final raw = middle + step;
      final index = wrap ? raw % count : raw;
      if (!wrap && (index < 0 || index >= count)) {
        continue;
      }
      final at = index < 0 ? index + count : index;
      final offset = slideOffset(raw.toDouble(), position);
      if (offset.abs() > reach + 0.5) {
        continue;
      }
      placements.add(_place(at, offset));
    }
    placements.sort((a, b) => b.offset.abs().compareTo(a.offset.abs()));
    return placements;
  }

  SlidePlacement _place(int index, double offset) {
    final distance = offset.abs();
    return switch (flow) {
      SlideFlow.deck => SlidePlacement(
          index: index,
          offset: offset,
          dx: offset * step,
          scale: 1 - 0.075 * math.min(distance, 2.6),
          opacity: math.max(0.1, 1 - 0.3 * math.min(distance, 2.6)),
          tilt: 0,
        ),
      SlideFlow.coverFlow => _coverFlow(index, offset),
    };
  }

  SlidePlacement _coverFlow(int index, double offset) {
    final distance = offset.abs();
    final sign = offset.isNegative ? -1.0 : 1.0;
    final near = math.min(distance, 1.0);
    final far = math.max(distance - 1, 0.0);
    return SlidePlacement(
      index: index,
      offset: offset,
      // The first neighbour steps clear of the active slide; the ones behind
      // it stack more tightly, which is what gives the rack its depth.
      dx: sign * (near * step + far * step * 0.58),
      scale: 1 - 0.13 * math.min(distance, 2.6),
      opacity: math.max(0.08, 1 - 0.26 * math.min(distance, 3.0)),
      tilt: -sign * near * maximumTilt,
    );
  }

  /// The slide the deck would settle on from here.
  int settledIndex(double position, int count) {
    if (count <= 0) {
      return 0;
    }
    final rounded = position.round();
    if (!wrap) {
      return rounded.clamp(0, count - 1);
    }
    final wrapped = rounded % count;
    return wrapped < 0 ? wrapped + count : wrapped;
  }

  /// Keeps a position inside the deck, allowing a little give at the ends so a
  /// drag past the last slide still feels like something rather than a wall.
  double clampPosition(double position, int count, {double give = 0}) {
    if (count <= 0) {
      return 0;
    }
    if (wrap) {
      return position;
    }
    return position.clamp(-give, (count - 1) + give).toDouble();
  }
}

/// How far a slide sits from the middle, taking the shorter way round when the
/// deck wraps.
double slideOffset(double index, double position) => index - position;

/// The position that shows [target], taking the shorter way round a deck that
/// wraps.
double slideTargetPosition({
  required double from,
  required int target,
  required int count,
  required bool wrap,
}) {
  if (count <= 0) {
    return 0;
  }
  if (!wrap) {
    return target.toDouble();
  }
  final current = from % count;
  var forward = (target - current) % count;
  if (forward < 0) {
    forward += count;
  }
  final backward = forward - count;
  return from + (forward.abs() <= backward.abs() ? forward : backward);
}
