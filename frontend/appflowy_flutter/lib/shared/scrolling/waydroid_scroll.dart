import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:universal_platform/universal_platform.dart';

import 'premium_coast.dart';

/// Logical pixels one raw Waydroid wheel notch scrolls.
///
/// Waydroid's hardware composer turns every 10 px of the host's scroll-axis
/// travel into one REL_WHEEL notch (it divides wl_pointer.axis values by 10
/// and emits whole notches). The desktop app scrolls one pixel per host
/// pixel of trackpad travel, so one notch is 10 px of finger travel: showing
/// it as 10 logical pixels restores the desktop's one-to-one gain.
const double waydroidNotchDistance = 10.0;

/// ViewConfiguration's default scroll factor: one Android scroll unit
/// (AXIS_VSCROLL or AXIS_HSCROLL of 1) is 64 dp, rounded to whole physical
/// pixels, before Flutter's embedding divides by the device pixel ratio.
const double androidScrollFactorDp = 64.0;

/// Logical pixels Flutter reports per Android scroll unit at
/// [devicePixelRatio].
double androidScrollUnit(double devicePixelRatio) {
  if (!devicePixelRatio.isFinite || devicePixelRatio <= 0) {
    return androidScrollFactorDp;
  }
  final physical = (androidScrollFactorDp * devicePixelRatio).roundToDouble();
  return physical / devicePixelRatio;
}

/// Whether AppFlowy runs inside Waydroid, where a laptop touchpad reaches
/// Android as accelerated mouse-wheel notches instead of touch or pan events.
///
/// The answer comes from device_info_plus once, asynchronously: until it
/// arrives, and everywhere other than Android, scrolling is unchanged.
abstract final class WaydroidDetection {
  static bool? _detected;
  static bool _started = false;

  /// Overrides detection in tests.
  @visibleForTesting
  static bool? debugIsWaydroid;

  /// The cached answer; false until detection has finished.
  static bool get isWaydroid => debugIsWaydroid ?? _detected ?? false;

  /// Settles detection from the device information read as the app starts
  /// (ApplicationInfoTask), so that the first pages already scroll for it.
  static void resolve(AndroidDeviceInfo info) {
    _started = true;
    _detected = isWaydroidDevice(
      manufacturer: info.manufacturer,
      brand: info.brand,
      model: info.model,
      product: info.product,
      device: info.device,
      hardware: info.hardware,
    );
  }

  /// Paces touches to the display's frames, as Android paces them for its
  /// own views.
  ///
  /// In Waydroid a touch is a host touchpad's scroll played as a finger, or
  /// the host's touchscreen: the compositor hands it over once per host frame
  /// and Waydroid stamps it on arrival, so moves come 5 to 24 ms apart at
  /// 120 Hz. Flutter asks Android for them unbatched and, dispatched at once,
  /// two landed in one frame and none in the next. Android resamples its own
  /// views' touches 5 ms behind the frame (InputConsumer's RESAMPLE_LATENCY);
  /// Flutter's resampler does the same here. Replayed through it, recorded
  /// two-finger scrolls stood still in 13% of their frames instead of 30%,
  /// changed speed from frame to frame half as much, and never flung the
  /// wrong way, for about 5 ms of lag. Flutter resamples touch only; mouse
  /// and trackpad input is unchanged.
  static void paceTouches() {
    GestureBinding.instance
      ..resamplingEnabled = true
      ..samplingOffset = touchSamplingOffset;
  }

  /// How far behind the frame touches are resampled.
  static const touchSamplingOffset = Duration(milliseconds: -5);

  /// Starts detection on Android, once and without blocking.
  static void ensureStarted() {
    if (_started || !UniversalPlatform.isAndroid) return;
    _started = true;
    DeviceInfoPlugin().androidInfo.then(
          resolve,
          onError: (Object _) => _detected = false,
        );
  }

  /// Waydroid images report themselves in their build properties, for
  /// example manufacturer "Waydroid", model "WayDroid x86_64 Device" and
  /// product "lineage_waydroid_x86_64".
  @visibleForTesting
  static bool isWaydroidDevice({
    String manufacturer = '',
    String brand = '',
    String model = '',
    String product = '',
    String device = '',
    String hardware = '',
  }) =>
      [manufacturer, brand, model, product, device, hardware]
          .any((value) => value.toLowerCase().contains('waydroid'));
}

/// Recovers the raw wheel notches Waydroid sent from the accelerated values
/// Android 13 reports, by replaying Android's wheel acceleration.
///
/// CursorInputMapper scales each REL_WHEEL value with a VelocityControl
/// (WheelVelocityControlParameters scale 1, thresholds 15 and 50, acceleration
/// 4): the speed of the raw accumulated wheel position, in notches/second,
/// leaves a notch as it is below 15, quadruples it from 50 and ramps linearly
/// between. That speed is the slope at the newest sample of an unweighted
/// least-squares quadratic over the samples of the last 100 ms (at most 20);
/// the tracker forgets its samples after 40 ms without a movement and the
/// position resets after 500 ms. With one sample there is no speed and no
/// gain.
///
/// Notches are whole numbers and the gain grows with the count, so exactly
/// one count, replayed through the same tracker, predicts what Android
/// reported. Flutter stamps Android input in whole milliseconds; where that
/// leaves Android's own 40 ms and 100 ms rules ambiguous, both readings are
/// tried and the better prediction wins.
class AndroidWheelAccelerationDecoder {
  AndroidWheelAccelerationDecoder({
    this.scale = 1,
    this.lowThreshold = 15,
    this.highThreshold = 50,
    this.acceleration = 4,
  });

  final double scale;
  final double lowThreshold;
  final double highThreshold;
  final double acceleration;

  static const _stopUs = 500000;
  static const _stoppedUs = 40000;
  static const _horizonUs = 100000;
  static const _historySize = 20;
  static const _stampUncertaintyUs = 1000;
  static const _maxNotches = 64;

  final _samples = <_WheelSample>[];
  int? _lastUs;
  double _position = 0;

  /// The raw notches behind an accelerated wheel [value] (Android scroll
  /// units, signed) stamped [timeUs], in the same sign.
  int decode(int timeUs, double value) {
    if (value == 0 || !value.isFinite) return 0;
    final last = _lastUs;
    if (last != null && (timeUs - last >= _stopUs || timeUs < last)) {
      reset();
    }
    final gap = _lastUs == null ? null : timeUs - _lastUs!;
    final direction = value.sign;
    final magnitude = value.abs();

    final histories = <List<_WheelSample>>[
      if (gap == null || gap < _stoppedUs + _stampUncertaintyUs) _samples,
      if (gap != null && gap > _stoppedUs - _stampUncertaintyUs) const [],
    ];
    final fewest = math.max(
      1,
      (magnitude / (scale * acceleration) * 0.9).floor(),
    );
    final most = math.min(
      _maxNotches,
      math.max(fewest, (magnitude / scale * 1.1).ceil()),
    );
    var bestNotches = fewest;
    var bestHistory = histories.first;
    var bestError = double.infinity;
    for (final history in histories) {
      for (final horizonUs in _horizons(history, timeUs)) {
        for (var notches = fewest; notches <= most; notches++) {
          final velocity = _velocity(
            history,
            timeUs,
            _position + direction * notches,
            horizonUs,
          );
          final predicted = notches * _gain(velocity);
          final error = math.log(predicted / magnitude).abs();
          if (error < bestError - 1e-9) {
            bestError = error;
            bestNotches = notches;
            bestHistory = history;
          }
        }
      }
    }

    if (bestHistory.isEmpty) _samples.clear();
    _position += direction * bestNotches;
    _samples.add(_WheelSample(timeUs, _position));
    if (_samples.length > _historySize) _samples.removeAt(0);
    _lastUs = timeUs;
    return (direction * bestNotches).round();
  }

  void reset() {
    _samples.clear();
    _position = 0;
    _lastUs = null;
  }

  /// The horizons to try: Android's, and where a sample's stamped age is
  /// within the stamps' uncertainty of it, the reading that puts that sample
  /// on the other side.
  Iterable<int> _horizons(List<_WheelSample> history, int timeUs) sync* {
    yield _horizonUs;
    for (var i = history.length - 1; i >= 0; i--) {
      final age = timeUs - history[i].timeUs;
      if ((age - _horizonUs).abs() < _stampUncertaintyUs) {
        yield age > _horizonUs ? age : age - 1;
        return;
      }
    }
  }

  double? _velocity(
    List<_WheelSample> history,
    int timeUs,
    double position,
    int horizonUs,
  ) {
    final times = <double>[0];
    final positions = <double>[position];
    for (var i = history.length - 1;
        i >= 0 && times.length < _historySize;
        i--) {
      final age = timeUs - history[i].timeUs;
      if (age > horizonUs) break;
      times.add(-age / Duration.microsecondsPerSecond);
      positions.add(history[i].position);
    }
    if (times.length < 2) return null;
    if (times.length == 2) {
      final span = times[0] - times[1];
      return span > 0 ? (positions[0] - positions[1]) / span : null;
    }
    var sx = 0.0, sx2 = 0.0, sx3 = 0.0, sx4 = 0.0;
    var sy = 0.0, sxy = 0.0, sx2y = 0.0;
    for (var i = 0; i < times.length; i++) {
      final x = times[i];
      final y = positions[i];
      final x2 = x * x;
      sx += x;
      sx2 += x2;
      sx3 += x2 * x;
      sx4 += x2 * x2;
      sy += y;
      sxy += x * y;
      sx2y += x2 * y;
    }
    final n = times.length;
    final sxx = sx2 - sx * sx / n;
    final sxyc = sxy - sx * sy / n;
    final sxx2 = sx3 - sx * sx2 / n;
    final sx2yc = sx2y - sx2 * sy / n;
    final sx2x2 = sx4 - sx2 * sx2 / n;
    final denominator = sxx * sx2x2 - sxx2 * sxx2;
    if (denominator == 0) return null;
    return (sxyc * sx2x2 - sx2yc * sxx2) / denominator;
  }

  double _gain(double? velocity) {
    if (velocity == null) return scale;
    final speed = velocity.abs() * scale;
    if (speed >= highThreshold) return scale * acceleration;
    if (speed > lowThreshold) {
      return scale *
          (1 +
              (speed - lowThreshold) /
                  (highThreshold - lowThreshold) *
                  (acceleration - 1));
    }
    return scale;
  }
}

@immutable
class _WheelSample {
  const _WheelSample(this.timeUs, this.position);

  final int timeUs;
  final double position;
}

/// Plays Waydroid's touchpad notch stream as continuous scrolling, and
/// coasts when the stream stops while the fingers are moving fast.
///
/// A notch marks where the fingers crossed another 10 px of travel, so notches
/// are sparse when the fingers are slow (one every 100 ms at 100 px/s) and
/// come several to a packet when they are fast. The page follows the
/// fingers' path a little over one notch interval behind them, at their speed
/// measured over the last [windowUs], and its velocity responds smoothly
/// ([responseSeconds]): neither sparse nor bunched notches show as steps. A
/// notch arriving late means slower fingers, so past the expected interval
/// the followed speed falls as the silence grows instead of the page running
/// into the notches' end and stalling. Following, the page never moves past
/// what the notches scrolled.
///
/// Waydroid drops the host's lift (axis_stop), so the end of a stream is
/// inferred: a notch is overdue once one interval and half of another (at
/// least [minimumLatenessUs]) have passed. At coasting speeds the page lags
/// just enough to still be at full speed then. If the fingers were moving at
/// least [coastSpeed] and had not slowed below [slowdownRatio] of their recent
/// peak, they lifted while moving: the page coasts on from its own speed on
/// [PremiumCoastSimulation]. Otherwise it glides to rest where the notches
/// took it, on the same physics, or at most half a notch past that: the
/// fingers are somewhere within their next notch, and drifting there beats
/// stopping dead while a slowing stream's last notch is late.
/// A notch that arrives during a coast catches it as a touch-down would: the
/// coast's remaining travel is dropped; in the same direction the page
/// carries on from its speed, the other way it stops first.
class WaydroidScrollMotion {
  WaydroidScrollMotion({
    this.coastFriction = premiumCoastFriction,
    this.coastDeceleration = premiumCoastDeceleration,
  });

  final double coastFriction;
  final double coastDeceleration;

  /// Window over which the fingers' speed is measured.
  @visibleForTesting
  static int windowUs = 50000;

  /// The fewest notches the speed is measured over, so that sparse notches,
  /// quantized to the host's input frames, are averaged too.
  @visibleForTesting
  static int windowNotches = 4;

  /// The span over which the final speed of a stream is measured.
  @visibleForTesting
  static int recentUs = 20000;

  /// A longer silence starts a new measurement: the fingers had stopped.
  @visibleForTesting
  static int streamGapUs = 250000;

  /// The speed assumed for a lone first notch, which arrives without one.
  @visibleForTesting
  static double firstNotchSpeed = 100;

  /// Lag beyond one notch interval, as a share of the interval: a notch this
  /// late slows the page rather than stopping it.
  @visibleForTesting
  static double headroom = 0.3;

  /// Fingers measured below this share of their recent peak speed are
  /// slowing down.
  @visibleForTesting
  static double slowingRatio = 0.9;

  /// Further lag at coasting speeds, so that the page is still at full speed
  /// when a notch becomes overdue and the coast is decided.
  @visibleForTesting
  static double decisionLagSeconds = 0.016;

  /// The share of the expected interval after which a missing notch slows the
  /// followed speed.
  @visibleForTesting
  static double lateShare = 1.1;

  /// How quickly a position error is corrected.
  @visibleForTesting
  static double correctionSeconds = 0.05;

  /// Time constant of the page's velocity response.
  @visibleForTesting
  static double responseSeconds = 0.016;

  /// How quickly the page may stop from its current speed when it reaches
  /// the notches' total, and the least deceleration that allows.
  @visibleForTesting
  static double brakeSeconds = 0.024;
  static const double _minimumBrake = 20000;

  /// How quickly the page moves onto the notches' total when there is no
  /// path to follow, as when the fingers have just turned back.
  @visibleForTesting
  static double settleSeconds = 0.05;

  /// How far past the notches' total the page may drift while a notch is
  /// late: half a notch, the fingers' expected position within it.
  @visibleForTesting
  static double overrunDistance = waydroidNotchDistance / 2;

  /// The least lateness that makes a notch overdue: delivery jitter.
  @visibleForTesting
  static int minimumLatenessUs = 6000;

  /// The slowest finger speed whose sudden end is read as a lift into a
  /// coast. Slower streams that stop have stopped.
  @visibleForTesting
  static double coastSpeed = 450;

  /// Fingers whose final speed has fallen below this share of their recent
  /// peak were slowing to a stop, not lifting off.
  @visibleForTesting
  static double slowdownRatio = 0.75;

  static const _peakWindowUs = 150000;

  /// The most constant deceleration a settle onto the total uses.
  static const _settleDeceleration = 10000.0;
  static const _restDistance = 0.05;
  static const _restVelocity = 5.0;

  double _received = 0;
  double _shown = 0;
  double _velocity = 0;
  final _notches = <_Notch>[];
  double _travel = 0;
  double? _seed;
  _Pace? _pace;
  bool _decided = false;
  bool _released = false;
  bool _carryingOn = false;
  PremiumCoastSimulation? _coast;
  double _coastTime = 0;

  /// Distance the notches have scrolled.
  double get received => _received;

  /// Distance shown so far.
  double get shown => _shown;

  /// The page's velocity, in logical pixels per second.
  double get velocity => _velocity;

  bool get isCoasting => _coast != null;

  /// Whether the coast running is a release, carrying the page on past the
  /// notches' total, rather than a settle onto it.
  bool get isReleased => _coast != null && _released;

  int? get lastStampUs => _notches.isEmpty ? null : _notches.last.stampUs;

  /// Whether frames are needed.
  bool get isActive {
    if (_coast != null || _velocity.abs() > _restVelocity) return true;
    final left = _received - _shown;
    return left.abs() > _restDistance && !_restingPast(left);
  }

  /// Whether the page, [left] short of the notches' total, rests within the
  /// half notch past it it may drift, waiting for the stream's next notch.
  bool _restingPast(double left) {
    final direction = _notches.isEmpty ? 0.0 : _notches.last.distance.sign;
    return left * direction < 0 && left.abs() <= overrunDistance;
  }

  /// Whether a notch stamped [stampUs] continues this stream: the page is
  /// still moving, or the last notch came recently.
  bool continues(int stampUs) {
    final last = lastStampUs;
    return isActive || (last != null && stampUs - last <= streamGapUs);
  }

  /// The fingers' measured speed, signed, if known.
  @visibleForTesting
  double? get fingerVelocity => _pace?.velocity;

  /// A notch event stamped [stampUs] scrolled [distance] logical pixels.
  void addNotches(int stampUs, double distance) {
    if (distance == 0 || !distance.isFinite) return;
    final direction = distance.sign;
    final previous = _notches.isEmpty ? null : _notches.last;
    final paused = previous == null ||
        stampUs - previous.stampUs > streamGapUs ||
        stampUs < previous.stampUs;
    if (paused &&
        _coast == null &&
        previous != null &&
        (_received - _shown) * previous.distance.sign < 0) {
      // Fingers starting afresh drop what the page drifted past the last
      // stream's total.
      _received = _shown;
    }
    if (previous != null && (paused || previous.distance.sign != direction)) {
      _notches.clear();
    }
    if (_notches.isEmpty) {
      _travel = 0;
      _seed = null;
    }
    var carryOn = false;
    if (_coast != null) {
      _coast = null;
      if (_velocity.sign != direction) {
        _velocity = 0;
        _received = _shown;
        _carryingOn = false;
      } else if (_notches.isEmpty) {
        _seed = _velocity;
        _received = _shown;
        carryOn = true;
      } else {
        // A late notch of the same stream: nothing it scrolled is lost, and
        // what the coast already showed beyond the half notch the page may
        // drift is not shown twice.
        _received = direction > 0
            ? math.max(_received, _shown - overrunDistance)
            : math.min(_received, _shown + overrunDistance);
      }
    }
    _received += distance;
    _travel += distance;
    _notches.add(_Notch(stampUs, distance, _travel));
    while (_notches.length > windowNotches &&
        stampUs - _notches.first.stampUs > _peakWindowUs) {
      _notches.removeAt(0);
    }
    _decided = false;
    final pace = _pace = _measure();
    // Kept until the next frame, when the time is known: later notches in the
    // same frame belong to the stream picked up.
    _carryingOn = _carryingOn || carryOn;
    if (pace != null && pace.points >= 3) {
      _notches.last.speed = pace.velocity.abs();
    }
  }

  /// Advances to input time [nowUs] by a frame of [seconds], returning the
  /// distance to scroll in it.
  double advance(int nowUs, double seconds) {
    if (seconds <= 0) return 0;
    final before = _shown;
    final pace = _pace;
    if (_coast == null &&
        !_decided &&
        _notches.isNotEmpty &&
        nowUs - _notches.last.stampUs >= (pace?.dueUs ?? streamGapUs)) {
      _decided = true;
      if (pace != null && _releasedMoving(pace)) {
        _startCoast();
      } else {
        _settle();
      }
    }

    final coast = _coast;
    if (coast != null) {
      _coastTime += seconds;
      _shown = coast.x(_coastTime);
      _velocity = coast.dx(_coastTime);
      if (coast.isDone(_coastTime)) {
        _coast = null;
        _velocity = 0;
        _received = _shown;
      }
      return _shown - before;
    }

    if (_carryingOn) {
      _carryingOn = false;
      if (pace != null) {
        // The page keeps its speed: the lag a stream at that speed keeps is
        // put in place, less what its path has advanced since the notch, so
        // the page neither lurches nor stalls.
        final direction = pace.velocity.sign;
        final travel = _travelSince(nowUs, pace).$1;
        final lead = pace.lag - travel;
        if (lead > (_received - _shown) * direction) {
          _received = _shown + direction * lead;
        }
      }
    }
    final remaining = _received - _shown;
    final direction =
        _notches.isEmpty ? remaining.sign : _notches.last.distance.sign;
    // The fingers are somewhere within their next notch: rather than stopping
    // dead at the total while a slowing stream's notch is late, the page may
    // drift up to [overrunDistance] past it, and never comes back for that.
    final reach = remaining * direction >= -overrunDistance
        ? remaining + direction * overrunDistance
        : remaining;
    final desired = _clampToStop(_desiredVelocity(nowUs, remaining), reach);
    final response = 1 - math.exp(-seconds / responseSeconds);
    _velocity = _clampToStop(
      _velocity + (desired - _velocity) * response,
      reach,
    );
    var step = _velocity * seconds;
    if (step.sign == reach.sign && step.abs() >= reach.abs()) {
      step = reach;
    }
    _shown += step;
    final left = _received - _shown;
    if (_velocity.abs() <= _restVelocity) {
      if (left.abs() <= _restDistance) {
        _shown = _received;
        _velocity = 0;
      } else if (_restingPast(left)) {
        // A further notch absorbs the drift; a new stream drops it.
        _velocity = 0;
      }
    }
    return _shown - before;
  }

  /// [unapplied] of the last frame's distance could not be scrolled: the page
  /// rests against an edge, and notches into it are dropped.
  void hitEdge(double unapplied) {
    _shown -= unapplied;
    _received = _shown;
    _velocity = 0;
    _coast = null;
  }

  /// Stops all motion where it is, as a touch-down would.
  void stop() {
    _received = _shown;
    _velocity = 0;
    _coast = null;
    _carryingOn = false;
    _notches.clear();
    _travel = 0;
    _seed = null;
    _pace = null;
  }

  double _desiredVelocity(int nowUs, double remaining) {
    final pace = _pace;
    if (pace != null &&
        remaining * pace.velocity < 0 &&
        remaining.abs() <= overrunDistance) {
      return 0;
    }
    if (pace == null ||
        _notches.isEmpty ||
        (remaining != 0 && remaining.sign != pace.velocity.sign)) {
      return remaining / settleSeconds;
    }
    final direction = pace.velocity.sign;
    // The fingers' path, a lag behind them along the line fitted through
    // their recent notches, never past the notches' total.
    final (travel, rate) = _travelSince(nowUs, pace);
    final free = _received + pace.offset + direction * (travel - pace.lag);
    // Once the stream has ended without a coast, the page settles onto the
    // notches' total.
    final reached = _decided || (free - _received) * direction >= 0;
    final target = reached ? _received : free;
    final speed = reached ? 0.0 : rate;
    // Ahead of the path, the page eases off to half the fingers' pace rather
    // than stopping and starting again.
    final correction = math.max(
      (target - _shown) / correctionSeconds * direction,
      -speed / 2,
    );
    final desired = direction * (speed + correction);
    return desired.sign == direction ? desired : 0;
  }

  /// How far the followed path has moved since the newest notch by input
  /// time [nowUs], and how fast it moves then: at the fingers' speed, falling
  /// once the next notch is late.
  (double, double) _travelSince(int nowUs, _Pace pace) {
    final speed = pace.follow;
    final sinceUs = math.max(0, nowUs - _notches.last.stampUs).toDouble();
    if (sinceUs <= pace.lateUs) {
      return (speed * sinceUs / Duration.microsecondsPerSecond, speed);
    }
    return (
      speed *
          pace.lateUs /
          Duration.microsecondsPerSecond *
          (1 + math.log(sinceUs / pace.lateUs)),
      speed * pace.lateUs / sinceUs,
    );
  }

  /// [velocity], limited so that the page can still stop within [reach]
  /// instead of passing it.
  double _clampToStop(double velocity, double reach) {
    if (reach == 0) return 0;
    if (velocity == 0 || velocity.sign != reach.sign) return velocity;
    final brake = math.max(_minimumBrake, _velocity.abs() / brakeSeconds);
    final limit = math.sqrt(2 * brake * reach.abs());
    return velocity.abs() > limit ? reach.sign * limit : velocity;
  }

  /// Whether a stream that has gone quiet ended with the fingers lifting
  /// while moving fast, rather than slowing to a stop.
  ///
  /// The final speed is measured over the last [recentUs] or more, which
  /// spans a couple of notches even at the fastest cadence: a stop shows as
  /// that speed falling below [slowdownRatio] of the stream's recent peak.
  bool _releasedMoving(_Pace pace) {
    final count = _notches.length;
    if (count < 3) return false;
    if (pace.velocity.abs() < coastSpeed ||
        _velocity.sign != pace.velocity.sign ||
        _velocity.abs() < coastSpeed / 2) {
      return false;
    }
    // Fingers lifting part-way through the host's input frame leave a last
    // packet that is on time but short, so then the speed up to the notch
    // before counts as well. Slowing fingers' notches come late instead.
    final lastIntervalUs =
        _notches[count - 1].stampUs - _notches[count - 2].stampUs;
    final onTime = lastIntervalUs <= pace.meanUs * 1.25;
    final recent = math.max(
      _speedEndingAt(count - 1) ?? 0,
      onTime ? _speedEndingAt(count - 2) ?? 0 : 0,
    );
    var peak = pace.velocity.abs();
    for (final notch in _notches) {
      peak = math.max(peak, notch.speed ?? 0);
    }
    return recent >= coastSpeed && recent >= peak * slowdownRatio;
  }

  /// The fingers' average speed over at least [recentUs] up to notch [end].
  double? _speedEndingAt(int end) {
    if (end < 1) return null;
    final last = _notches[end];
    var from = end - 1;
    while (from > 0 && last.stampUs - _notches[from].stampUs < recentUs) {
      from--;
    }
    final spanUs = last.stampUs - _notches[from].stampUs;
    if (spanUs <= 0) return null;
    return (last.travel - _notches[from].travel).abs() /
        spanUs *
        Duration.microsecondsPerSecond;
  }

  /// Glides onto the notches' total from the page's own speed, on the coast
  /// physics with just the constant deceleration that rests there, or within
  /// the half notch past it it may drift. A page too close to stop gently is
  /// left to the follower.
  void _settle() {
    final remaining = _received - _shown;
    if (_velocity.abs() <= _restVelocity || _velocity * remaining <= 0) return;
    for (final distance in [
      remaining.abs(),
      remaining.abs() + overrunDistance,
    ]) {
      final deceleration = premiumCoastDecelerationToRest(
        velocity: _velocity,
        distance: distance,
        friction: coastFriction,
      );
      // Too slow to get there on friction alone: the follower brings it in.
      if (deceleration <= 0) return;
      if (deceleration <= _settleDeceleration) {
        _released = false;
        _coast = PremiumCoastSimulation(
          position: _shown,
          velocity: _velocity,
          friction: coastFriction,
          deceleration: deceleration,
        );
        _coastTime = 0;
        return;
      }
    }
  }

  void _startCoast() {
    final remaining = _received - _shown;
    var launch = _velocity;
    final travel = premiumCoastDistance(
      launch,
      friction: coastFriction,
      deceleration: coastDeceleration,
    );
    if (remaining.sign == launch.sign && remaining.abs() > travel.abs()) {
      launch = premiumCoastVelocity(
        remaining,
        friction: coastFriction,
        deceleration: coastDeceleration,
      );
    }
    _released = true;
    _coast = PremiumCoastSimulation(
      position: _shown,
      velocity: launch,
      friction: coastFriction,
      deceleration: coastDeceleration,
    );
    _coastTime = 0;
  }

  /// The fingers' pace: a least-squares slope through the notches of the
  /// last [windowUs], and at least the last [windowNotches] of the stream.
  _Pace? _measure() {
    final count = _notches.length;
    if (count == 0) return null;
    final newest = _notches.last;
    final direction = newest.distance.sign;
    if (count == 1) {
      final seed = _seed;
      final speed = seed?.abs() ?? firstNotchSpeed;
      final intervalUs =
          newest.distance.abs() / speed * Duration.microsecondsPerSecond;
      return _paceOf(
        direction * speed,
        intervalUs,
        intervalUs,
        pickedUp: seed == null ? 0 : 1,
      );
    }
    var first = count - 1;
    while (first > 0 &&
        (count - first < windowNotches ||
            newest.stampUs - _notches[first - 1].stampUs <= windowUs)) {
      first--;
    }
    final spanUs = newest.stampUs - _notches[first].stampUs;
    if (spanUs <= 0) return null;
    final points = count - first;
    var meanT = 0.0;
    var meanY = 0.0;
    var longestUs = 0;
    for (var i = first; i < count; i++) {
      meanT += (_notches[i].stampUs - newest.stampUs) / 1e6;
      meanY += _notches[i].travel;
      if (i > first) {
        longestUs = math.max(
          longestUs,
          _notches[i].stampUs - _notches[i - 1].stampUs,
        );
      }
    }
    meanT /= points;
    meanY /= points;
    var stt = 0.0;
    var sty = 0.0;
    for (var i = first; i < count; i++) {
      final t = (_notches[i].stampUs - newest.stampUs) / 1e6 - meanT;
      stt += t * t;
      sty += t * (_notches[i].travel - meanY);
    }
    if (stt <= 0 || sty.sign != direction) return null;
    var velocity = sty / stt;
    final lastUs = newest.stampUs - _notches[count - 2].stampUs;
    if (count - first > 2) {
      final (shortestUs, longestUs) = _intervalRange(first, count - 2);
      // A notch later than any recent one by more than an input frame (the
      // shortest recent gap) came clearly late: it measures how far the
      // fingers have slowed more directly than the average.
      if (lastUs > math.max(longestUs * 1.2, longestUs + shortestUs)) {
        final slower = newest.distance.abs() / lastUs * 1e6;
        if (slower < velocity.abs()) velocity = direction * slower;
      }
    }
    final seed = _seed;
    var pickedUp = 0.0;
    if (seed != null && points < windowNotches) {
      // A stream picked up from a coast starts at the page's speed: its
      // first one or two intervals alone are too coarse to override it, and
      // may slow it but not hurry it.
      pickedUp = 1 - (points - 1) / (windowNotches - 1);
      final measured = direction * math.min(velocity.abs(), seed.abs());
      velocity = measured + (seed - measured) * pickedUp;
    }
    return _paceOf(
      velocity,
      spanUs / (points - 1),
      longestUs.toDouble(),
      // Where the fitted line puts the fingers at the newest notch, relative
      // to it: following the line, rather than restarting from each notch,
      // keeps notches quantized to the host's frames from jolting the page.
      offset: meanY - velocity * meanT - newest.travel,
      points: points,
      pickedUp: pickedUp,
    );
  }

  /// The shortest and longest intervals between the notches from [first] to
  /// [end].
  (int, int) _intervalRange(int first, int end) {
    var shortest = 1 << 30;
    var longest = 0;
    for (var i = first + 1; i <= end; i++) {
      final interval = _notches[i].stampUs - _notches[i - 1].stampUs;
      shortest = math.min(shortest, interval);
      longest = math.max(longest, interval);
    }
    return (shortest, longest);
  }

  /// The pace of fingers moving at [velocity] whose notches come every
  /// [meanUs] on average and at most [longestUs] apart lately.
  _Pace _paceOf(
    double velocity,
    double meanUs,
    double longestUs, {
    double offset = 0,
    int points = 1,
    double pickedUp = 0,
  }) {
    final speed = velocity.abs();
    // Waiting for the longest recent gap keeps the regular unevenness of
    // notches quantized to the host's frames from reading as slowing.
    final expectedUs = math.max(meanUs, longestUs);
    final expected = expectedUs / Duration.microsecondsPerSecond;
    var peak = speed;
    for (final notch in _notches) {
      peak = math.max(peak, notch.speed ?? 0);
    }
    var dueUs = expectedUs + math.max(meanUs / 2, minimumLatenessUs);
    final coasting =
        ((speed - coastSpeed / 2) / (coastSpeed / 2)).clamp(0.0, 1.0);
    final slowing = speed < peak * slowingRatio;
    // A late notch from slow or slowing fingers means they are slowing
    // further; fast, steady ones keep their speed until the stream's end is
    // judged, so that a coast launches at it.
    var lateUs = slowing
        ? expectedUs * lateShare
        : expectedUs * lateShare +
            math.max(0.0, dueUs - expectedUs * lateShare) * coasting;
    if (points < 3) {
      // One or two intervals, quantized to the host's input frames, say
      // little about when the next notch is due.
      dueUs = math.max(dueUs, 3 * expectedUs);
      lateUs = math.max(lateUs, 2 * expectedUs);
    }
    return _Pace(
      velocity: velocity,
      // Clearly slowing fingers are followed as if they keep slowing as they
      // have, so the page eases off before running out of notches.
      follow: speed * math.min(1, speed / peak / slowdownRatio),
      // A stream picked up from a coast has yet to show whether the fingers
      // are slower than the page, so it keeps more in hand to slow down over.
      lag: speed *
          (expected * (1 + headroom) +
              decisionLagSeconds * (coasting + pickedUp)),
      lateUs: lateUs,
      dueUs: dueUs,
      offset: offset,
      points: points,
      meanUs: meanUs,
    );
  }
}

class _Notch {
  _Notch(this.stampUs, this.distance, this.travel);

  final int stampUs;
  final double distance;

  /// Distance the stream has scrolled up to and including this notch.
  final double travel;

  /// The fingers' speed measured when this notch arrived.
  double? speed;
}

@immutable
class _Pace {
  const _Pace({
    required this.velocity,
    required this.follow,
    required this.lag,
    required this.lateUs,
    required this.dueUs,
    this.offset = 0,
    this.points = 1,
    this.meanUs = 0,
  });

  /// Where the fitted line puts the fingers at the newest notch, relative to
  /// the notches' total.
  final double offset;

  /// The mean interval between recent notches.
  final double meanUs;

  /// How many notches the speed was measured over.
  final int points;

  /// The fingers' velocity, in logical pixels per second.
  final double velocity;

  /// The speed the page follows them at.
  final double follow;

  /// How far behind the notches' total the page follows, just after a notch.
  final double lag;

  /// Microseconds after a notch from which a missing next one slows the pace.
  final double lateUs;

  /// Microseconds after a notch at which a missing next one ends the stream.
  final double dueUs;
}
