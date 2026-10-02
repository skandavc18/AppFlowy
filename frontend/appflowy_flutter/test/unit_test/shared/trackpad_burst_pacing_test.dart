import 'dart:math' as math;

import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A touchpad packet as Windows delivered it: stamped by the embedder every
/// ~15 ms, then handed to a busy UI thread [lagMs] later. Times are
/// milliseconds from the gesture's start stamp.
class _Packet {
  const _Packet(this.stampMs, this.lagMs, this.dy);

  final double stampMs;
  final double lagMs;
  final double dy;

  double get arrivalMs => stampMs + lagMs;
}

class _Gesture {
  const _Gesture(
    this.packets, {
    required this.endStampMs,
    this.startLagMs = 1,
    this.endLagMs = 1,
    this.frozenFromMs,
    this.frozenToMs,
  });

  final List<_Packet> packets;
  final double startLagMs;
  final double endStampMs;
  final double endLagMs;

  /// No frames are produced while the UI thread is busy.
  final double? frozenFromMs;
  final double? frozenToMs;

  double get distance => packets.fold(0.0, (sum, p) => sum + p.dy);
}

/// Two gestures recorded live on a 120 Hz Windows laptop: packets were
/// stamped ~15 ms apart, but pairs reached the UI thread half a millisecond
/// apart after 30 ms silences.
const _recordedGestures = [
  _Gesture(
    [
      _Packet(9.35, 18.45, -15.57),
      _Packet(24.72, 3.82, -21.73),
      _Packet(40.45, 3.52, -27.35),
      _Packet(54.29, 26.62, -55.98),
      _Packet(68.94, 12.46, -42.72),
      _Packet(83.42, 27.28, -44.24),
      _Packet(99.83, 11.23, -63.42),
      _Packet(115.54, 1.53, -36.04),
    ],
    startLagMs: 25.92,
    endStampMs: 117.95,
    endLagMs: 89.05,
  ),
  _Gesture(
    [
      _Packet(12.93, 4.96, -17.05),
      _Packet(28.16, 0.83, -20.85),
      _Packet(46.48, 15.51, -34.09),
      _Packet(61.21, 1.10, -36.22),
      _Packet(77.44, 0.76, -23.96),
      _Packet(92.96, 5.07, -31.01),
      _Packet(110.81, 0.93, -12.83),
    ],
    startLagMs: 16.81,
    endStampMs: 119.81,
    endLagMs: 7.76,
  ),
];

_Gesture _steadyGesture(List<double> lags) => _Gesture(
      [
        for (var i = 1; i <= 40; i++)
          _Packet(i * 15.6, lags[i % lags.length], -30),
      ],
      endStampMs: 40 * 15.6 + 2,
    );

const _frameUs = 8333;

void main() {
  testWidgets(
    'a recorded burst-delivered swipe moves without surges',
    (tester) async {
      for (final gesture in _recordedGestures) {
        final replay = await _replayed(tester, gesture);
        final steps = replay.drag;
        final median = _median(steps);
        // Arrival time used to start every packet's motion, so each burst
        // played at double speed: up to 5.7 times the typical frame.
        expect(steps.reduce(math.max), lessThan(median * 2), reason: '$steps');
        expect(_largestRise(steps), lessThan(2.5), reason: '$steps');
        _expectSmoothRelease(replay);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final (name, lags) in const [
    ('punctual', <double>[1]),
    ('slightly late', <double>[0.6, 3.8, 1.1, 2.4, 0.8, 4.9, 1.5, 0.9, 3.1]),
    ('paired', <double>[1, 12, 1, 0.5, 14, 0.8, 1, 2]),
  ]) {
    testWidgets(
      'evenly stamped packets delivered $name scroll evenly',
      (tester) async {
        final replay = await _replayed(tester, _steadyGesture(lags));
        final steps = replay.drag;
        final median = _median(steps);
        // Skip the start: the allowance for late delivery settles there.
        for (final step in steps.skip(6)) {
          expect(step, closeTo(median, median * 0.12), reason: '$steps');
        }
        _expectSmoothRelease(replay, steady: true);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'after the UI thread stalls, scrolling eases back instead of lurching',
    (tester) async {
      final gesture = _Gesture(
        [
          for (var i = 1; i <= 30; i++)
            _Packet(
              i * 15.6,
              // Packets 10 to 15 are handed over together when it frees up.
              i >= 10 && i <= 15 ? (15 * 15.6 + 1) - i * 15.6 : 1,
              -30,
            ),
        ],
        endStampMs: 30 * 15.6 + 2,
        frozenFromMs: 10 * 15.6,
        frozenToMs: 15 * 15.6 + 1,
      );
      final replay = await _replayed(tester, gesture);
      final steps = replay.drag;
      final median = _median(steps);
      expect(steps.reduce(math.max), lessThan(median * 1.5), reason: '$steps');
      expect(steps.where((step) => step < 0.01), isEmpty, reason: '$steps');
      _expectSmoothRelease(replay, steady: true);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

double get _gain =>
    const PremiumScrollPhysicsConfig().desktopDirectManipulationScale;

/// Replays [gesture] at 120 Hz and returns how far each frame moved, per
/// 120 Hz frame: while the fingers were down, from the first moving frame to
/// the last, and in the three frames after they lifted. Also checks that the
/// content travels at least every bit of distance the fingers did.
Future<_Replay> _replayed(WidgetTester tester, _Gesture gesture) async {
  tester.view.display.refreshRate = 120;
  addTearDown(tester.view.display.resetRefreshRate);
  final controller = ScrollController(initialScrollOffset: 1000);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: PremiumScrollScope(
        enabled: true,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: ListView.builder(
              key: const ValueKey('list'),
              controller: controller,
              itemCount: 2000,
              itemExtent: 40,
              itemBuilder: (_, index) => Text('Row $index'),
            ),
          ),
        ),
      ),
    ),
  );
  final point = tester.getCenter(find.byKey(const ValueKey('list')));
  final startOffset = controller.offset;

  int us(double ms) => (ms * 1000).round();
  final actions = <(int, int, Object)>[];
  void add(int at, Object action) => actions.add((at, actions.length, action));
  add(us(gesture.startLagMs), 'start');
  for (final packet in gesture.packets) {
    add(us(packet.arrivalMs), packet);
  }
  final endAt = us(gesture.endStampMs + gesture.endLagMs);
  add(endAt, 'end');
  for (var t = 3100; t < endAt + 4 * _frameUs; t += _frameUs) {
    final frozen = gesture.frozenFromMs != null &&
        t >= us(gesture.frozenFromMs!) &&
        t < us(gesture.frozenToMs!);
    if (!frozen) add(t, 'frame');
  }
  // Inputs before a frame at the same instant; otherwise in the order they
  // were stamped (List.sort is not stable).
  actions.sort((a, b) {
    final byTime = a.$1.compareTo(b.$1);
    if (byTime != 0) return byTime;
    final byKind = (a.$3 == 'frame' ? 1 : 0).compareTo(b.$3 == 'frame' ? 1 : 0);
    return byKind != 0 ? byKind : a.$2.compareTo(b.$2);
  });

  var now = 0;
  var pan = 0.0;
  var released = 0;
  final frames = <(int, double)>[];
  for (final (at, _, action) in actions) {
    final wait = Duration(microseconds: at - now);
    now = at;
    if (action == 'frame') {
      await tester.pump(wait);
      frames.add((at, controller.offset));
      continue;
    }
    await tester.binding.delayed(wait);
    final PointerEvent event;
    if (action == 'start') {
      event = PointerPanZoomStartEvent(
        pointer: 71,
        device: 71,
        position: point,
      );
    } else if (action == 'end') {
      event = PointerPanZoomEndEvent(
        pointer: 71,
        device: 71,
        position: point,
        timeStamp: Duration(microseconds: us(gesture.endStampMs)),
      );
    } else {
      final packet = action as _Packet;
      pan += packet.dy;
      event = PointerPanZoomUpdateEvent(
        pointer: 71,
        device: 71,
        position: point,
        pan: Offset(0, pan),
        panDelta: Offset(0, packet.dy),
        timeStamp: Duration(microseconds: us(packet.stampMs)),
      );
    }
    await tester.sendEventToBinding(event);
    if (action == 'end') released = frames.length;
  }
  await tester.pumpAndSettle();
  expect(
    controller.offset - startOffset,
    greaterThanOrEqualTo(-gesture.distance * _gain - 0.01),
    reason: 'what the fingers moved is all shown, never dropped',
  );

  final steps = <double>[];
  for (var i = 1; i < frames.length; i++) {
    final elapsed = frames[i].$1 - frames[i - 1].$1;
    // A frozen stretch shows as one long frame: compare per 120 Hz frame.
    steps.add((frames[i].$2 - frames[i - 1].$2).abs() * _frameUs / elapsed);
  }
  // steps[i] ends at frames[i + 1]: the first after release is released - 1.
  final drag = steps.sublist(0, released - 1);
  final first = drag.indexWhere((step) => step > 0.01);
  final last = drag.lastIndexWhere((step) => step > 0.01);
  return (
    drag: drag.sublist(first, last + 1),
    drained: last < drag.length - 1,
    coast: steps.sublist(released - 1, released + 2),
  );
}

/// Frame movement while the fingers were down, and in the three frames after
/// they lifted; [drained] if the display had caught up before they lifted.
typedef _Replay = ({List<double> drag, bool drained, List<double> coast});

/// Lifting the fingers neither jumps nor holds still for a frame. Showing
/// the buffered motion at once made the release frame up to 5.8 times the
/// frame before it. Fingers lifting at a [steady] speed keep that speed, the
/// coast only slightly faster for also travelling what was not yet shown.
void _expectSmoothRelease(_Replay replay, {bool steady = false}) {
  final drag = replay.drag;
  final pace = drag.sublist(math.max(0, drag.length - 6)).reduce(math.max);
  final reason = '${replay.drag} | ${replay.coast}';
  expect(replay.coast.reduce(math.max), lessThan(pace * 1.3), reason: reason);
  if (replay.drained) return;
  expect(replay.coast.first, greaterThan(drag.last * 0.3), reason: reason);
  if (steady) {
    expect(
      replay.coast.first,
      inInclusiveRange(drag.last, drag.last * 1.25),
      reason: reason,
    );
  }
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// The largest frame-to-frame growth in movement, from frames that already
/// moved at a quarter of the typical pace: starting from rest is no surge.
double _largestRise(List<double> steps) {
  final floor = _median(steps) / 4;
  var rise = 0.0;
  for (var i = 1; i < steps.length; i++) {
    if (steps[i - 1] > floor) rise = math.max(rise, steps[i] / steps[i - 1]);
  }
  return rise;
}
