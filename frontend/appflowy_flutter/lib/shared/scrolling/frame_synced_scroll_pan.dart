import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A short-lived input buffer owned by a mounted premium scroll region.
///
/// The original gesture arena and DragScrollActivity retain ownership. Only
/// offsets that reach the winning position's physics are queued. No predicted
/// distance, synthetic pointer events, extra ballistic activity, or paint-only
/// transforms are used. The position comes from its controller, never from a
/// retained ScrollMetrics argument to the physics callback.
class FrameSyncedScrollPan {
  FrameSyncedScrollPan({
    required this.controller,
    required this.position,
    required this.refreshRate,
    required this.directScale,
    required this.onDispose,
  }) {
    _owners[position]?.dispose(flush: true);
    _owners[position] = this;
    _clock.start();
  }

  static final _owners = Expando<FrameSyncedScrollPan>('trackpad frame pacing');

  /// Return raw input unchanged unless this exact mounted position has opted
  /// into the current trackpad session. Actual scaling/resistance happens once
  /// in the calling physics, after this function returns.
  static double filterOffset(ScrollMetrics metrics, double offset) =>
      metrics is ScrollPosition
          ? _owners[metrics]?._filter(offset) ?? offset
          : offset;

  final ScrollController controller;
  final ScrollPositionWithSingleContext position;
  final double refreshRate;
  final double directScale;
  final VoidCallback onDispose;

  int inputIntervalUs = 0;
  final Stopwatch _clock = GestureBinding.instance.samplingClock.stopwatch();
  Ticker? _ticker;
  ScrollActivity? _drag;
  double _remaining = 0;
  final _segments = <_PanSegment>[];
  bool _applying = false;
  bool _disposed = false;

  // Read the real activity only to avoid writing through an interrupted drag.
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ScrollActivity? get _activity => position.activity;

  bool get _valid =>
      !_disposed &&
      controller.positions.contains(position) &&
      (position.context.notificationContext?.mounted ?? false) &&
      identical(_activity, _drag) &&
      _drag is DragScrollActivity;

  double _filter(double offset) {
    if (_applying || _disposed) return offset;
    final activity = _activity;
    if (activity is! DragScrollActivity ||
        (_drag != null && !identical(activity, _drag))) {
      dispose();
      return offset;
    }
    _drag = activity;
    final total = _remaining + offset;
    final target = position.pixels - total * directScale;
    final reversing = _remaining != 0 && offset.sign != _remaining.sign;
    if (inputIntervalUs <= 1.25e6 / refreshRate ||
        inputIntervalUs > 40000 ||
        reversing ||
        position.outOfRange ||
        target <= position.minScrollExtent ||
        target >= position.maxScrollExtent ||
        total.abs() * directScale > 96 ||
        _segments.length >= 4) {
      // High-rate input needs no buffering. Boundary resistance and reversals
      // remain synchronous, consuming the remainder exactly once. Never write
      // position.pixels inside this physics callback: its caller already read
      // the old pixels and would overwrite such a nested position update.
      _takeRemaining();
      return total;
    }

    _remaining = total;
    _segments.add(
      _PanSegment(
        distance: offset,
        startUs: _clock.elapsedMicroseconds,
        durationUs: math.min(inputIntervalUs, 16667),
      ),
    );
    _ticker ??= position.context.vsync.createTicker(_tick);
    if (!_ticker!.isActive) _ticker!.start();
    return 0;
  }

  void _tick(Duration _) {
    if (!_valid) {
      dispose();
      return;
    }
    final now = _clock.elapsedMicroseconds;
    var delta = 0.0;
    for (final segment in _segments) {
      delta += segment.sample(now);
    }
    _segments.removeWhere((segment) => segment.complete);
    _remaining -= delta;
    if (delta != 0) _apply(delta);
    if (_segments.isEmpty) _takeRemaining();
  }

  void _apply(double offset) {
    _applying = true;
    try {
      // Keep real scroll notifications, semantics, lazy viewport layout,
      // direction, scaling and elastic boundaries in the original position.
      position.applyUserOffset(offset);
    } finally {
      _applying = false;
    }
  }

  double _takeRemaining() {
    final pending = _remaining;
    _remaining = 0;
    _segments.clear();
    _ticker?.stop();
    return pending;
  }

  /// End-of-pointer delivery occurs before DragScrollController.end changes
  /// its notification details. Flush there, not from goBallistic or a delayed
  /// ScrollEndNotification. On takeover/unmount discard stale pending work.
  void dispose({bool flush = false}) {
    if (_disposed) return;
    final pending = _takeRemaining();
    final shouldFlush = flush && pending != 0 && _valid;
    // Flushing notifies scroll listeners synchronously. A listener may dispose
    // this buffer again, so latch first and always release resources once.
    _disposed = true;
    try {
      if (shouldFlush) _apply(pending);
    } finally {
      _ticker?.dispose();
      _ticker = null;
      _clock.stop();
      if (identical(_owners[position], this)) _owners[position] = null;
      onDispose();
    }
  }
}

class _PanSegment {
  _PanSegment(
      {required this.distance,
      required this.startUs,
      required this.durationUs});

  final double distance;
  final int startUs;
  final int durationUs;
  double _delivered = 0;
  bool complete = false;

  double sample(int nowUs) {
    final fraction = ((nowUs - startUs) / durationUs).clamp(0.0, 1.0);
    final delivered = distance * fraction;
    final delta = delivered - _delivered;
    _delivered = delivered;
    complete = fraction == 1;
    return delta;
  }
}
