import 'dart:async';
import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// The colour a board column was given by hand.
///
/// A column normally borrows its colour from its group — the colour of the
/// select option it collects. Choosing one here overrides that, and
/// [plain] keeps a coloured option's column neutral.
@immutable
class BoardColumnColor {
  const BoardColumnColor._(this.tint);

  const BoardColumnColor.tint(SelectOptionColorPB this.tint);

  /// The column wears no colour, whatever its option says.
  static const plain = BoardColumnColor._(null);

  static const _plainId = 'none';

  final SelectOptionColorPB? tint;

  bool get isPlain => tint == null;

  /// How the choice is stored: the colour's protobuf number, or `'none'`.
  /// Numbers rather than names, because a build may strip enum names.
  Object get storedValue => tint?.value ?? _plainId;

  /// Null for anything this version does not recognise, so a colour written
  /// by a later version falls back to the group's own rather than guessing.
  static BoardColumnColor? fromStored(Object? stored) {
    if (stored == _plainId) {
      return plain;
    }
    final tint = stored is int ? SelectOptionColorPB.valueOf(stored) : null;
    return tint == null ? null : BoardColumnColor.tint(tint);
  }

  /// The colour a column shows: what was chosen, else its option's own.
  static SelectOptionColorPB? resolve({
    required BoardColumnColor? chosen,
    required SelectOptionColorPB? optionColor,
  }) =>
      chosen == null ? optionColor : chosen.tint;

  @override
  bool operator ==(Object other) =>
      other is BoardColumnColor && other.tint == tint;

  @override
  int get hashCode => tint.hashCode;

  @override
  String toString() => 'BoardColumnColor($storedValue)';
}

/// The colours chosen for a board's columns, keyed by group id.
///
/// The backend knows nothing about these, so they ride in the board view's
/// own `extra` beside the other marks a Flutter view keeps there.
@immutable
class BoardGroupColors {
  const BoardGroupColors([this._byGroup = const {}]);

  static const envelopeKey = 'appflowy_board_group_colors';
  static const currentVersion = 1;

  final Map<String, BoardColumnColor> _byGroup;

  bool get isEmpty => _byGroup.isEmpty;

  /// What [groupId] was set to, or null when it follows its group.
  BoardColumnColor? operator [](String groupId) => _byGroup[groupId];

  /// [color] null returns the column to its group's own colour.
  BoardGroupColors withColor(String groupId, BoardColumnColor? color) {
    final next = Map<String, BoardColumnColor>.of(_byGroup);
    if (color == null) {
      next.remove(groupId);
    } else {
      next[groupId] = color;
    }
    return BoardGroupColors(Map.unmodifiable(next));
  }

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'groups': {
          for (final entry in _byGroup.entries)
            entry.key: entry.value.storedValue,
        },
      };

  /// Writes these colours into [extra], keeping everything else it carries.
  /// A board with no colours chosen leaves no envelope behind.
  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    if (isEmpty) {
      values.remove(envelopeKey);
    } else {
      values[envelopeKey] = toJson();
    }
    return jsonEncode(values);
  }

  static BoardGroupColors fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return const BoardGroupColors();
    }
    final version = envelope['version'];
    final groups = envelope['groups'];
    if (version is! int ||
        version < 1 ||
        version > currentVersion ||
        groups is! Map) {
      return const BoardGroupColors();
    }
    final colors = <String, BoardColumnColor>{};
    for (final entry in groups.entries) {
      final color = BoardColumnColor.fromStored(entry.value);
      if (entry.key is String && color != null) {
        colors[entry.key as String] = color;
      }
    }
    return BoardGroupColors(Map.unmodifiable(colors));
  }

  @override
  bool operator ==(Object other) =>
      other is BoardGroupColors && mapEquals(other._byGroup, _byGroup);

  @override
  int get hashCode => Object.hashAllUnordered(
        _byGroup.entries.map((entry) => Object.hash(entry.key, entry.value)),
      );
}

/// The chosen colours, shared between the column menu that sets them and the
/// board that paints them.
///
/// The menu and the columns are built by different parts of the board package,
/// so a notifier per view is what lets the board repaint the moment a colour
/// is picked.
class BoardGroupColorRegistry {
  /// Callbacks must throw when a read or write fails. Saves handle the failure,
  /// log it without payloads, and fall back to what is actually stored.
  BoardGroupColorRegistry({
    Future<String> Function(String viewId)? readExtra,
    Future<void> Function(String viewId, String extra)? writeExtra,
  })  : _readExtra = readExtra ?? _readViewExtra,
        _writeExtra = writeExtra ?? _writeViewExtra;

  static final BoardGroupColorRegistry instance = BoardGroupColorRegistry();

  final Future<String> Function(String viewId) _readExtra;
  final Future<void> Function(String viewId, String extra) _writeExtra;
  final Map<String, _BoardGroupColorState> _byView = {};
  final Map<String, Future<void>> _pending = {};

  _BoardGroupColorState _stateFor(ViewPB view) => _byView.putIfAbsent(
        view.id,
        () => _BoardGroupColorState(BoardGroupColors.fromExtra(view.extra)),
      );

  ValueNotifier<BoardGroupColors> notifierFor(ViewPB view) =>
      _stateFor(view).notifier;

  BoardGroupColors colorsFor(ViewPB view) => notifierFor(view).value;

  /// Gives [groupId] the colour [color]; null returns it to its group's own.
  Future<void> set(ViewPB view, String groupId, BoardColumnColor? color) {
    final viewId = view.id;
    final state = _stateFor(view);
    final revision = ++state.revision;
    final previous = _pending[viewId] ?? Future<void>.value();
    late final Future<void> save;
    save = previous
        .then((_) => _save(viewId, state, revision, groupId, color))
        .whenComplete(() {
      if (identical(_pending[viewId], save)) {
        _pending.removeWhere((id, _) => id == viewId);
      }
    });
    // Enqueue before notifying: a listener may immediately choose again.
    unawaited(_pending[viewId] = save);
    state.notifier.value = state.notifier.value.withColor(groupId, color);
    return save;
  }

  Future<void> _save(
    String viewId,
    _BoardGroupColorState state,
    int revision,
    String groupId,
    BoardColumnColor? color,
  ) async {
    if (!identical(_byView[viewId], state)) return;
    try {
      // Merge into what is stored now, not into what this window last saw:
      // the extra also carries every other mark the view wears.
      final extra = await _readExtra(viewId);
      if (!identical(_byView[viewId], state)) return;
      state.stored = BoardGroupColors.fromExtra(extra);
      final next = state.stored.withColor(groupId, color);
      await _writeExtra(viewId, next.mergeIntoExtra(extra));
      if (!identical(_byView[viewId], state)) return;
      state.stored = next;
      if (state.revision == revision) {
        state.notifier.value = next;
      }
    } on Object catch (_) {
      if (identical(_byView[viewId], state) && state.revision == revision) {
        state.notifier.value = state.stored;
      }
      try {
        // Neither backend messages nor extra payloads are safe to log here.
        Log.warn('Could not save board column colours');
      } on Object catch (_) {
        // Native logging may not yet be available; never poison the queue.
      }
    }
  }

  @visibleForTesting
  void reset() {
    for (final state in _byView.values) {
      state.notifier.dispose();
    }
    _byView.clear();
    // Keep pending tails until they finish: a dispatched write cannot be
    // cancelled and must not land after a newer choice for the same view.
  }
}

class _BoardGroupColorState {
  _BoardGroupColorState(this.stored) : notifier = ValueNotifier(stored);

  final ValueNotifier<BoardGroupColors> notifier;
  BoardGroupColors stored;
  int revision = 0;
}

Future<String> _readViewExtra(String viewId) async =>
    (await ViewBackendService.getView(viewId)).fold(
      (view) {
        if (view.id != viewId) {
          throw StateError('Board colours read returned a different view');
        }
        return view.extra;
      },
      (_) => throw StateError('Could not read board colours'),
    );

Future<void> _writeViewExtra(String viewId, String extra) async {
  (await ViewBackendService.updateView(viewId: viewId, extra: extra)).fold(
    // Rust's update_view_handler answers Ok(()) with no view payload, which
    // the generated event decodes as an empty ViewPB: do not check its id.
    (_) {},
    (_) => throw StateError('Could not write board colours'),
  );
}
