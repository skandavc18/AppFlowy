import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';

/// How a place is written into a location cell.
enum LocationFormat {
  address('address'),
  coordinates('coordinates');

  const LocationFormat(this.value);

  final String value;
}

/// Tells a column that it holds a place.
///
/// A location column is a text column wearing a note, so everything that
/// already reads text — sorting, filtering, export, the grid itself — keeps
/// working, and the map knows which column to plot without being told twice.
class LocationBackendService {
  const LocationBackendService();

  static Future<FlowyResult<void, FlowyError>> setLocationField({
    required String viewId,
    required String fieldId,
    required bool enabled,
    LocationFormat format = LocationFormat.address,
  }) {
    final payload = LocationFieldPB()
      ..viewId = viewId
      ..fieldId = fieldId
      ..enabled = enabled
      ..format = format.value;

    return DatabaseEventSetLocationField(payload).send();
  }

  /// The columns of a view that hold a place.
  static Future<List<String>> locationFieldIds({required String viewId}) {
    final payload = DatabaseViewIdPB()..value = viewId;
    return DatabaseEventGetLocationFields(payload).send().fold(
      (fields) => fields.items.map((field) => field.fieldId).toList(),
      (error) {
        Log.warn('Could not read the location columns of $viewId: $error');
        return const <String>[];
      },
    );
  }
}

/// Remembers which columns of a view hold a place.
///
/// The field type list and the field's own panel both need this answer, and
/// they need to agree the moment either of them changes it, so the answer
/// lives in one place instead of being fetched twice and drifting apart.
class LocationFieldRegistry {
  LocationFieldRegistry._();

  static final LocationFieldRegistry instance = LocationFieldRegistry._();

  final Map<String, ValueNotifier<Set<String>>> _views = {};
  final Set<String> _loading = {};

  /// Bumped whenever any view's location columns change.
  ///
  /// A map is its own view with its own id, so it cannot listen to the grid
  /// the column was marked in; this is how it hears about it anyway.
  final ValueNotifier<int> revision = ValueNotifier(0);

  ValueNotifier<Set<String>> listenable(String viewId) {
    final notifier =
        _views.putIfAbsent(viewId, () => ValueNotifier(const <String>{}));
    unawaited(refresh(viewId));
    return notifier;
  }

  bool isLocation(String viewId, String fieldId) =>
      _views[viewId]?.value.contains(fieldId) ?? false;

  Future<void> refresh(String viewId) async {
    if (!_loading.add(viewId)) {
      return;
    }
    try {
      final ids = await LocationBackendService.locationFieldIds(viewId: viewId);
      final notifier = _views[viewId];
      if (notifier != null && !setEquals(notifier.value, ids.toSet())) {
        notifier.value = ids.toSet();
        revision.value++;
      }
    } finally {
      _loading.remove(viewId);
    }
  }

  Future<void> setLocation({
    required String viewId,
    required String fieldId,
    required bool enabled,
    LocationFormat format = LocationFormat.address,
  }) async {
    final notifier = _views[viewId];
    if (notifier != null) {
      final next = Set<String>.of(notifier.value);
      enabled ? next.add(fieldId) : next.remove(fieldId);
      notifier.value = next;
    }
    await LocationBackendService.setLocationField(
      viewId: viewId,
      fieldId: fieldId,
      enabled: enabled,
      format: format,
    );
    // Read it back: a mark that did not stick must not leave a tick behind.
    _loading.remove(viewId);
    await refresh(viewId);
    revision.value++;
  }
}
