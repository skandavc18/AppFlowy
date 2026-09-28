import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum CoverCorners { rounded, square }

enum CoverImageFit { fit, crop, stretch }

enum CoverPosition { top, center, bottom }

/// Device-local presentation, never an image choice or a workspace migration.
@immutable
class CoverAppearance {
  const CoverAppearance({
    this.corners = CoverCorners.rounded,
    this.aspectRatio,
    this.fit = CoverImageFit.crop,
    this.position = CoverPosition.center,
  });

  static const defaults = CoverAppearance();
  final CoverCorners corners;

  /// Null retains each host's established responsive height.
  final double? aspectRatio;
  final CoverImageFit fit;
  final CoverPosition position;

  double get radius => corners == CoverCorners.rounded ? 16 : 0;
  BoxFit get boxFit => switch (fit) {
        CoverImageFit.fit => BoxFit.contain,
        CoverImageFit.crop => BoxFit.cover,
        CoverImageFit.stretch => BoxFit.fill,
      };
  Alignment get alignment => switch (position) {
        CoverPosition.top => Alignment.topCenter,
        CoverPosition.center => Alignment.center,
        CoverPosition.bottom => Alignment.bottomCenter,
      };

  CoverAppearance copyWith({
    CoverCorners? corners,
    double? aspectRatio,
    bool resetAspectRatio = false,
    CoverImageFit? fit,
    CoverPosition? position,
  }) =>
      CoverAppearance(
        corners: corners ?? this.corners,
        aspectRatio: resetAspectRatio ? null : aspectRatio ?? this.aspectRatio,
        fit: fit ?? this.fit,
        position: position ?? this.position,
      );

  static bool validRatio(double? ratio) =>
      ratio == null || (ratio.isFinite && ratio >= 1 && ratio <= 6);

  static CoverAppearance decode(String? raw) {
    if (raw == null || raw.isEmpty) return defaults;
    try {
      final map = jsonDecode(raw);
      if (map is! Map || map['version'] != 1) return defaults;
      final ratio = map['aspect_ratio'];
      return CoverAppearance(
        corners: map['corners'] == 'square'
            ? CoverCorners.square
            : CoverCorners.rounded,
        aspectRatio: ratio is num && validRatio(ratio.toDouble())
            ? ratio.toDouble()
            : null,
        fit: switch (map['fit']) {
          'fit' => CoverImageFit.fit,
          'stretch' => CoverImageFit.stretch,
          _ => CoverImageFit.crop,
        },
        position: switch (map['position']) {
          'top' => CoverPosition.top,
          'bottom' => CoverPosition.bottom,
          _ => CoverPosition.center,
        },
      );
    } on FormatException {
      return defaults;
    }
  }

  String encode() {
    if (!validRatio(aspectRatio)) throw ArgumentError('Invalid cover ratio');
    return jsonEncode({
      'version': 1,
      'corners': corners.name,
      'aspect_ratio': aspectRatio,
      'fit': fit.name,
      'position': position.name,
    });
  }

  @override
  bool operator ==(Object other) =>
      other is CoverAppearance &&
      corners == other.corners &&
      aspectRatio == other.aspectRatio &&
      fit == other.fit &&
      position == other.position;

  @override
  int get hashCode => Object.hash(corners, aspectRatio, fit, position);
}

enum CoverAppearanceFailure { unavailable, load, save }

/// Invocation-ordered, acknowledged publication using the existing local KV.
/// Failed or early loads are retryable; no writes happen on read or disposal.
class CoverAppearanceStore extends ChangeNotifier {
  CoverAppearanceStore({KeyValueStorage? Function()? resolveStorage})
      : _resolveStorage = resolveStorage ?? _registeredStorage;

  static final instance = CoverAppearanceStore();
  static const storageKey = 'appflowy_cover_appearance';
  final KeyValueStorage? Function() _resolveStorage;
  final _values = ValueNotifier(CoverAppearance.defaults);
  Future<void> _tail = Future<void>.value();
  Future<bool>? _loading;
  KeyValueStorage? _storage;
  bool _loaded = false;
  bool _disposed = false;
  int _pending = 0;
  CoverAppearanceFailure? _failure;

  CoverAppearance get value => _values.value;
  ValueListenable<CoverAppearance> get appearances => _values;
  bool get isSaving => _pending != 0;
  bool get isLoaded => _loaded;
  CoverAppearanceFailure? get failure => _failure;

  static KeyValueStorage? _registeredStorage() =>
      getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null;

  Future<bool> ensureLoaded() {
    if (_disposed) return Future.value(false);
    if (_loaded) return Future.value(true);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<bool> _load() async {
    await Future<void>.value();
    if (_disposed) return false;
    try {
      final storage = _resolveStorage();
      if (storage == null) {
        _failure = CoverAppearanceFailure.unavailable;
        _notify();
        return false;
      }
      final raw = await storage.get(storageKey);
      if (_disposed) return false;
      _storage = storage;
      _loaded = true;
      _failure = null;
      _values.value = CoverAppearance.decode(raw);
      _notify();
      return true;
    } catch (_) {
      _failure = CoverAppearanceFailure.load;
      _notify();
      return false;
    }
  }

  /// A transform runs against the last ACK, not a stale Settings build value.
  Future<bool> update(CoverAppearance Function(CoverAppearance) change) {
    if (_disposed) return Future.value(false);
    _pending++;
    final operation = _tail.then((_) => _write(change));
    _tail = operation.then<void>((_) {});
    _notify();
    return operation;
  }

  Future<bool> reset() => update((_) => CoverAppearance.defaults);

  Future<bool> _write(CoverAppearance Function(CoverAppearance) change) async {
    try {
      if (_disposed || !await ensureLoaded()) return false;
      if (_disposed) return false;
      final next = change(value);
      final raw = next.encode();
      final storage = _storage!;
      if (storage is DartKeyValue) {
        if (!await storage.sharedPreferences.setString(storageKey, raw)) {
          throw StateError('Cover appearance not saved');
        }
      } else {
        await storage.set(storageKey, raw);
      }
      if (!_disposed) _values.value = next;
      _failure = null;
      return true;
    } catch (_) {
      final storage = _storage;
      if (storage is DartKeyValue) {
        try {
          await storage.sharedPreferences.reload();
        } catch (_) {
          // Next explicit action always writes, including reset to last ACK.
        }
      }
      _failure = CoverAppearanceFailure.save;
      return false;
    } finally {
      _pending--;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _values.dispose();
    super.dispose();
  }
}

/// Only dependent cover leaves/layouts rebuild; the router/editor stays put.
class CoverAppearanceScope
    extends InheritedNotifier<ValueNotifier<CoverAppearance>> {
  CoverAppearanceScope({
    super.key,
    required CoverAppearanceStore store,
    required super.child,
  }) : super(notifier: store._values);

  static CoverAppearance of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<CoverAppearanceScope>()
          ?.notifier
          ?.value ??
      CoverAppearanceStore.instance.value;
}
