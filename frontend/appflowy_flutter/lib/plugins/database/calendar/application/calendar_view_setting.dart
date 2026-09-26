import 'dart:async';
import 'dart:convert';

import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// Presentation only. The backend's day/week/month layout enum is untouched.
@immutable
class CalendarViewSetting {
  const CalendarViewSetting(this.mode);

  static const envelopeKey = 'appflowy_calendar_presentation';
  static const version = 1;

  final CalendarViewMode mode;

  Map<String, Object?> toJson() => {'version': version, 'mode': mode.name};

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    final previous = values[envelopeKey];
    values[envelopeKey] = {
      if (previous is Map) ...Map<String, dynamic>.from(previous),
      ...toJson(),
    };
    return jsonEncode(values);
  }

  /// An absent setting retains the host's existing desktop/mobile default.
  static CalendarViewSetting? fromExtra(String extra) {
    final value = decodeViewExtra(extra)[envelopeKey];
    if (value is! Map || value['version'] != version) return null;
    for (final mode in CalendarViewMode.values) {
      if (mode.name == value['mode']) return CalendarViewSetting(mode);
    }
    return null;
  }
}

/// A view and its editor embeds share one choice. Writes are serialized and
/// merge into freshly read extra so changing a mode never erases another mark.
/// Read/write callbacks allow offline verification without a native backend.
class CalendarViewSettings {
  CalendarViewSettings({
    Future<String> Function(String viewId)? readExtra,
    Future<void> Function(String viewId, String extra)? writeExtra,
  })  : _readExtra = readExtra ?? _read,
        _writeExtra = writeExtra ?? _write;

  static final instance = CalendarViewSettings();

  final Future<String> Function(String viewId) _readExtra;
  final Future<void> Function(String viewId, String extra) _writeExtra;
  final Map<String, _ModeState> _states = {};
  final Map<String, Future<void>> _pending = {};

  _ModeState _state(ViewPB view) => _states.putIfAbsent(
        view.id,
        () => _ModeState(CalendarViewSetting.fromExtra(view.extra)?.mode),
      );

  ValueListenable<CalendarViewMode?> listenable(ViewPB view) =>
      _state(view).value;

  void adopt(ViewPB view) {
    if (_pending.containsKey(view.id)) return;
    final state = _state(view);
    state.saved = CalendarViewSetting.fromExtra(view.extra)?.mode;
    state.value.value = state.saved;
  }

  Future<void> set(ViewPB view, CalendarViewMode mode) {
    final state = _state(view);
    final revision = ++state.revision;
    final previous = _pending[view.id] ?? Future<void>.value();
    late final Future<void> save;
    save = previous.then((_) async {
      if (view.id.isEmpty || !identical(_states[view.id], state)) return;
      try {
        final extra = await _readExtra(view.id);
        if (!identical(_states[view.id], state)) return;
        state.saved = CalendarViewSetting.fromExtra(extra)?.mode;
        await _writeExtra(
          view.id,
          CalendarViewSetting(mode).mergeIntoExtra(extra),
        );
        if (identical(_states[view.id], state)) state.saved = mode;
      } on Object catch (_) {
        if (identical(_states[view.id], state) && state.revision == revision) {
          state.value.value = state.saved;
        }
        // Do not include view data or backend error payloads in the log.
        try {
          Log.warn('Could not save calendar presentation settings');
        } on Object catch (_) {
          // Logging need not be available before native startup.
        }
      }
    }).whenComplete(() {
      if (identical(_pending[view.id], save)) {
        _pending.removeWhere((id, _) => id == view.id);
      }
    });
    unawaited(_pending[view.id] = save);
    state.value.value = mode;
    return save;
  }

  static Future<String> _read(String viewId) async =>
      (await ViewBackendService.getView(viewId)).fold(
        (view) {
          if (view.id != viewId) throw StateError('Calendar view changed');
          return view.extra;
        },
        (_) => throw StateError('Could not read calendar settings'),
      );

  static Future<void> _write(String viewId, String extra) async {
    (await ViewBackendService.updateView(viewId: viewId, extra: extra)).fold(
      // UpdateView acknowledges with an empty payload, not a populated view.
      (_) {},
      (_) => throw StateError('Could not save calendar settings'),
    );
  }

  @visibleForTesting
  void reset() {
    for (final state in _states.values) {
      state.value.dispose();
    }
    _states.clear();
    // Already-dispatched writes cannot be cancelled; retain their queue tails.
  }
}

class _ModeState {
  _ModeState(this.saved) : value = ValueNotifier(saved);

  CalendarViewMode? saved;
  final ValueNotifier<CalendarViewMode?> value;
  int revision = 0;
}
