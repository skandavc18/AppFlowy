import 'dart:async';
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
///
/// Playback follows the input device's own timestamps, not the moment each
/// packet reaches the UI thread. Windows stamps touchpad packets every ~15 ms,
/// but a busy UI thread receives them in bursts: two packets half a
/// millisecond apart after a 30 ms silence. Starting each packet when it
/// arrived replayed every burst as a surge and every silence as a stall. The
/// display instead shows the received motion one interval behind its stamps,
/// plus however late packets have recently been, eases back onto that
/// schedule when a packet comes later still, and never runs past what was
/// received. Motion still buffered when the fingers lift while moving rides
/// on the release coast instead of being jumped to.
class FrameSyncedScrollPan {
  FrameSyncedScrollPan({
    required this.controller,
    required this.position,
    required this.refreshRate,
    required this.directScale,
    required this.onDispose,
    Duration? startedAt,
  }) {
    _owners[position]?.dispose(flush: true);
    _owners[position] = this;
    _clock.start();
    final startUs = startedAt?.inMicroseconds ?? 0;
    _points.add(_InputPoint(startUs, 0));
    _cursorUs = startUs.toDouble();
    _startJitterUs = _jitterUs = initialJitterFrames * _frameUs;
  }

  static final _owners = Expando<FrameSyncedScrollPan>('trackpad frame pacing');
  static final _releases = Expando<FrameSyncedRelease>('trackpad release');

  /// How far behind the newest stamps playback runs, in input intervals,
  /// before allowing for late delivery.
  @visibleForTesting
  static double delayIntervals = 1;

  /// The most extra delay late delivery may add.
  @visibleForTesting
  static double maxJitterUs = 33000;

  /// How quickly the allowance for late delivery fades once packets come on
  /// time again.
  @visibleForTesting
  static double jitterHalfLifeUs = 300000;

  /// The allowance for late delivery a gesture starts with, in display
  /// frames: a gesture usually begins while the app is busiest.
  @visibleForTesting
  static double initialJitterFrames = 1;

  /// How quickly playback eases back onto its schedule: a lag of this much
  /// input time doubles the playback speed.
  @visibleForTesting
  static double catchUpUs = 60000;

  /// The fastest playback may run while it catches up.
  @visibleForTesting
  static double maxCatchUpRate = 3;

  /// Return raw input unchanged unless this exact mounted position has opted
  /// into the current trackpad session. Actual scaling/resistance happens once
  /// in the calling physics, after this function returns.
  static double filterOffset(ScrollMetrics metrics, double offset) =>
      metrics is ScrollPosition
          ? _owners[metrics]?._filter(offset) ?? offset
          : offset;

  /// How the fingers lifted from [metrics], if they lifted while moving.
  /// A coast that will travel its carry takes it with [takeRelease]; left
  /// alone, the carry is shown once the release has been handled.
  static FrameSyncedRelease? releaseOf(ScrollMetrics metrics) =>
      metrics is ScrollPosition ? _releases[metrics] : null;

  /// Hands the release over: only the coast starting from it should use it.
  static FrameSyncedRelease? takeRelease(ScrollMetrics metrics) {
    if (metrics is! ScrollPosition) return null;
    final release = _releases[metrics];
    _releases[metrics] = null;
    return release;
  }

  final ScrollController controller;
  final ScrollPositionWithSingleContext position;
  final double refreshRate;
  final double directScale;
  final VoidCallback onDispose;

  /// Time between the stamps of the packet being delivered and the one
  /// before it.
  int inputIntervalUs = 0;
  int? _incomingStampUs;

  /// The device's reporting interval, smoothed: one short or long gap is
  /// jitter, not a different device.
  double? _meanIntervalUs;

  final Stopwatch _clock = GestureBinding.instance.samplingClock.stopwatch();
  Ticker? _ticker;
  ScrollActivity? _drag;
  bool _applying = false;
  bool _disposed = false;

  /// The received motion as a curve over input time: cumulative distance at
  /// each packet's stamp, straight between them.
  final _points = <_InputPoint>[];
  double _received = 0;
  double _shown = 0;

  /// The input time currently on screen.
  double _cursorUs = 0;

  /// Smallest (arrival - stamp) seen: maps input time onto this clock with
  /// the fastest delivery observed, so a late packet is recognised as late.
  int? _offsetUs;

  /// How much later than the fastest delivery packets have lately arrived.
  double _jitterUs = 0;
  double _startJitterUs = 0;
  int? _firstArrivalUs;

  /// Recent packets' (arrival, arrival - stamp). How late a packet was is
  /// only known once the fastest delivery has been seen, possibly after it.
  final _deliveries = <(int, int)>[];

  /// The stamp of the newest packet that moved.
  int? _movedUs;
  int? _tickBaseUs;
  int? _lastFrameUs;

  // Read the real activity only to avoid writing through an interrupted drag.
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  ScrollActivity? get _activity => position.activity;

  bool get _valid =>
      !_disposed &&
      controller.positions.contains(position) &&
      (position.context.notificationContext?.mounted ?? false) &&
      identical(_activity, _drag) &&
      _drag is DragScrollActivity;

  int get _horizonUs => _points.last.stampUs;

  double get _frameUs => Duration.microsecondsPerSecond / refreshRate;

  double get _intervalUs => _meanIntervalUs ?? inputIntervalUs.toDouble();

  double get _delayUs =>
      delayIntervals * _intervalUs.clamp(_frameUs, _nominalUs.toDouble()) +
      math.min(_jitterUs, maxJitterUs);

  /// The span a packet's motion is spread over: the time since the packet
  /// before it, unless the input had paused, when it moved only lately.
  int _spanOf(int intervalUs) =>
      intervalUs > 0 && intervalUs <= _longestSpanUs ? intervalUs : _nominalUs;

  /// The packet now being delivered was stamped [stamp], [intervalUs] after
  /// the one before it. Its distance reaches the physics right after this.
  void receive(Duration stamp, int intervalUs) {
    if (_disposed) return;
    final unclaimed = _incomingStampUs;
    if (unclaimed != null) {
      // The previous packet carried no distance: the fingers rested until it
      // was stamped.
      _addPoint(unclaimed, _received);
    }
    inputIntervalUs = intervalUs;
    if (intervalUs > 0 && intervalUs <= _longestSpanUs) {
      final mean = _meanIntervalUs;
      _meanIntervalUs =
          mean == null ? intervalUs.toDouble() : mean + (intervalUs - mean) / 4;
    }
    _incomingStampUs = stamp.inMicroseconds;
  }

  double _filter(double offset) {
    if (_applying || _disposed) return offset;
    final activity = _activity;
    if (activity is! DragScrollActivity ||
        (_drag != null && !identical(activity, _drag))) {
      dispose();
      return offset;
    }
    _drag = activity;
    final stampUs = _incomingStampUs ?? _horizonUs + inputIntervalUs;
    _incomingStampUs = null;
    _movedUs = stampUs;
    final pending = _received - _shown;
    final total = pending + offset;
    final target = position.pixels - total * directScale;
    final reversing = pending != 0 && offset.sign != pending.sign;
    if (_intervalUs <= 1.25e6 / refreshRate ||
        reversing ||
        position.outOfRange ||
        target <= position.minScrollExtent ||
        target >= position.maxScrollExtent) {
      // High-rate input needs no buffering. Boundary resistance and reversals
      // remain synchronous, consuming the remainder exactly once. Never write
      // position.pixels inside this physics callback: its caller already read
      // the old pixels and would overwrite such a nested position update.
      _received += offset;
      _settleAt(math.max(stampUs, _horizonUs));
      return total;
    }

    final start = stampUs - _spanOf(inputIntervalUs);
    if (start > _horizonUs) _addPoint(start, _received);
    _received += offset;
    _addPoint(stampUs, _received);
    final arrivedUs = _clock.elapsedMicroseconds;
    final lateness = arrivedUs - stampUs;
    final fastest = _offsetUs = math.min(_offsetUs ?? lateness, lateness);
    _deliveries
      ..removeWhere((d) => arrivedUs - d.$1 > 4 * jitterHalfLifeUs)
      ..add((arrivedUs, lateness));
    double fade(int ageUs) =>
        math.pow(0.5, ageUs / jitterHalfLifeUs).toDouble();
    final startedUs = _firstArrivalUs ??= arrivedUs;
    var jitter = _startJitterUs * fade(arrivedUs - startedUs);
    for (final (atUs, late) in _deliveries) {
      jitter = math.max(jitter, (late - fastest) * fade(arrivedUs - atUs));
    }
    _jitterUs = jitter;
    _ticker ??= position.context.vsync.createTicker(_tick);
    if (!_ticker!.isActive) {
      _lastFrameUs = _clock.elapsedMicroseconds;
      _ticker!.start();
    }
    return 0;
  }

  void _addPoint(int stampUs, double total) {
    final last = _points.last;
    if (stampUs <= last.stampUs) {
      // Out of order or a repeated stamp: it belongs with the newest packet.
      _points[_points.length - 1] = _InputPoint(last.stampUs, total);
    } else {
      _points.add(_InputPoint(stampUs, total));
    }
  }

  /// Cumulative received distance at input time [atUs].
  double _totalAt(double atUs) {
    if (atUs <= _points.first.stampUs) return _points.first.total;
    for (var i = 1; i < _points.length; i++) {
      final end = _points[i];
      if (atUs >= end.stampUs) continue;
      final start = _points[i - 1];
      final fraction = (atUs - start.stampUs) / (end.stampUs - start.stampUs);
      return start.total + (end.total - start.total) * fraction;
    }
    return _points.last.total;
  }

  /// Moves [cursorUs] across input time in which nothing moved, up to
  /// [limitUs]: a pause costs no playback time.
  double _skipStillness(double cursorUs, double limitUs) {
    var cursor = cursorUs;
    for (var i = 1; i < _points.length && cursor < limitUs; i++) {
      final end = _points[i];
      if (cursor >= end.stampUs) continue;
      if (end.total != _points[i - 1].total) break;
      cursor = math.min(limitUs, end.stampUs.toDouble());
    }
    return cursor;
  }

  void _tick(Duration elapsed) {
    if (!_valid) {
      dispose();
      return;
    }
    final offset = _offsetUs;
    if (offset == null) return;
    // Frame timestamps tick evenly even when this callback runs late.
    final baseUs =
        _tickBaseUs ??= _clock.elapsedMicroseconds - elapsed.inMicroseconds;
    final nowUs = baseUs + elapsed.inMicroseconds;
    final frameUs = (nowUs - (_lastFrameUs ?? nowUs)).toDouble();
    _lastFrameUs = nowUs;
    if (frameUs <= 0) return;

    final horizon = _horizonUs.toDouble();
    final targetUs = nowUs - offset - _delayUs;
    var cursor = _skipStillness(_cursorUs, math.min(targetUs, horizon));
    // On schedule the cursor moves exactly one frame of input time. Behind it
    // (a packet came later than the delay allows) it speeds up in proportion
    // to the lag, easing back rather than jumping.
    final lag = targetUs - frameUs - cursor;
    final rate = (1 + lag / catchUpUs).clamp(_minPlaybackRate, maxCatchUpRate);
    cursor = math.min(horizon, cursor + frameUs * rate);
    _cursorUs = cursor;
    final total = cursor >= horizon ? _received : _totalAt(cursor);
    final delta = total - _shown;
    _shown = total;
    _forgetBefore(cursor);
    if (delta != 0) _apply(delta);
    if (_disposed) return;
    if (_cursorUs >= horizon && _shown == _received) _idle();
  }

  /// Drops points the cursor has fully passed, keeping the one it is past.
  void _forgetBefore(double cursorUs) {
    var keep = 0;
    while (keep + 1 < _points.length && _points[keep + 1].stampUs <= cursorUs) {
      keep++;
    }
    if (keep > 0) _points.removeRange(0, keep);
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

  void _idle() {
    _ticker?.stop();
    _tickBaseUs = null;
    _lastFrameUs = null;
  }

  /// Marks everything received as shown, with nothing left to play.
  double _settleAt(int stampUs) {
    final pending = _received - _shown;
    _shown = _received;
    _points
      ..clear()
      ..add(_InputPoint(stampUs, _received));
    _cursorUs = stampUs.toDouble();
    _idle();
    return pending;
  }

  /// The fingers lifted at [stamp]. If they were still moving, what they did
  /// that is not yet on screen is left for the release coast to travel:
  /// jumping to it showed several frames of motion in one, a surge on every
  /// flick. After a rest, or when too little is left for a coast to travel,
  /// the remainder is shown at once.
  void release(Duration stamp) {
    if (_disposed) return;
    final movedUs = _movedUs;
    if (!_valid ||
        movedUs == null ||
        stamp.inMicroseconds - movedUs > _longestSpanUs) {
      dispose(flush: true);
      return;
    }
    final pending = -(_received - _shown) * directScale;
    final carry = pending.abs() < _minCarry ? 0.0 : pending;
    if (carry != 0) _settleAt(_horizonUs);
    final scrolled = position;
    dispose(flush: true);
    _releases[scrolled] = FrameSyncedRelease._(
      carry: carry,
      // The last paced frame already moved; the coast's first frame, which a
      // new animation shows at its start, would otherwise hold still.
      lead: 1 / refreshRate,
    );
    // The release coast takes it while this same pointer event is handled.
    // Should nothing take it, show the carried distance rather than lose it.
    scheduleMicrotask(() {
      final left = takeRelease(scrolled)?.carry ?? 0;
      if (left == 0 ||
          !controller.positions.contains(scrolled) ||
          !(scrolled.context.notificationContext?.mounted ?? false) ||
          // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
          scrolled.activity is! IdleScrollActivity) {
        return;
      }
      scrolled.jumpTo(
        (scrolled.pixels + left)
            .clamp(scrolled.minScrollExtent, scrolled.maxScrollExtent),
      );
    });
  }

  /// End-of-pointer delivery occurs before DragScrollController.end changes
  /// its notification details. Flush there, not from goBallistic or a delayed
  /// ScrollEndNotification. On takeover/unmount discard stale pending work.
  void dispose({bool flush = false}) {
    if (_disposed) return;
    final pending = _settleAt(_horizonUs);
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

/// A packet's motion is never spread over more than this: past it the input
/// had paused, and the packet moved only in its last moments.
const _longestSpanUs = 40000;

/// The input interval this pacing exists for: 60 Hz touchpad reporting.
const _nominalUs = 16667;

/// Playback never slows below this while it waits for the schedule.
const _minPlaybackRate = 0.5;

/// Pixels below which a release coast would stop before travelling them.
const _minCarry = 2.0;

/// A frame-paced pan's hand-over to the coast that follows it.
@immutable
class FrameSyncedRelease {
  const FrameSyncedRelease._({required this.carry, required this.lead});

  /// Pixels the fingers moved that are not yet on screen.
  final double carry;

  /// Seconds of coast already due by the coast's first frame.
  final double lead;

  /// [velocity] raised so that a coast decaying exponentially at [friction]
  /// also travels [carry], from what is on screen instead of jumping to it.
  double launch(double velocity, double friction) =>
      velocity + carry * friction;

  /// [coast], [lead] seconds on. A new animation shows its start on its
  /// first frame; a coast taking over from paced dragging would otherwise
  /// hold still for a frame between the drag's last movement and its own.
  Simulation leading(Simulation coast) =>
      lead > 0 ? _LeadingSimulation(coast, lead) : coast;
}

class _LeadingSimulation extends Simulation {
  _LeadingSimulation(this.inner, this.lead) : super(tolerance: inner.tolerance);

  final Simulation inner;
  final double lead;

  @override
  double x(double time) => inner.x(time + lead);

  @override
  double dx(double time) => inner.dx(time + lead);

  @override
  bool isDone(double time) => inner.isDone(time + lead);
}

@immutable
class _InputPoint {
  const _InputPoint(this.stampUs, this.total);

  final int stampUs;
  final double total;
}
