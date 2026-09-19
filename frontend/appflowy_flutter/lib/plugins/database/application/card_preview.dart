import 'dart:async';
import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/foundation.dart';

/// How a card presents its page, cover and title, in menu order.
enum CardPreviewMode {
  /// The row's page, with its title underneath.
  pageAndTitle('page_title'),

  /// The row's cover picture, when it has one.
  cover('cover'),

  /// Only the row's page, without a title footer or row properties.
  pageContent('page'),

  /// No preview: just the row's title on a board.
  none('none'),

  /// A full-card cover, with the title overlaid at its foot.
  portrait('portrait'),

  /// The title and visible row fields, without a cover or page preview.
  titleAndProperties('title_properties');

  const CardPreviewMode(this.id);

  final String id;

  bool get showsRowData => this == CardPreviewMode.titleAndProperties;

  static CardPreviewMode fromId(String? id) {
    for (final mode in CardPreviewMode.values) {
      if (mode.id == id) {
        return mode;
      }
    }
    return CardPreviewMode.cover;
  }
}

/// The card preview a database view was left on.
///
/// The backend knows nothing about this, so it rides in the view's own `extra`
/// beside the other marks a Flutter view keeps there.
@immutable
class CardPreviewSetting {
  const CardPreviewSetting({this.mode = CardPreviewMode.cover});

  static const envelopeKey = 'appflowy_card_preview';
  static const currentVersion = 1;

  final CardPreviewMode mode;

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'mode': mode.id,
      };

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    values[envelopeKey] = toJson();
    return jsonEncode(values);
  }

  static CardPreviewSetting fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return const CardPreviewSetting();
    }
    final values = Map<String, dynamic>.from(envelope);
    final version = values['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      return const CardPreviewSetting();
    }
    final mode = values['mode'];
    return CardPreviewSetting(
      mode: CardPreviewMode.fromId(mode is String ? mode : null),
    );
  }
}

/// The choice, shared between the toolbar that sets it and the cards that
/// answer to it.
///
/// The two sit side by side rather than one above the other, so a notifier per
/// view is what lets a card follow the choice without its host rebuilding.
class CardPreviewRegistry {
  /// Callbacks must throw when a read or write fails. Saves handle the failure,
  /// log it without payloads, and roll back only the latest local selection.
  CardPreviewRegistry({
    CardPreviewBackend backend = const CardPreviewBackend(),
    Future<String> Function(String viewId)? readExtra,
    Future<void> Function(String viewId, String extra)? writeExtra,
  })  : _readExtra = readExtra ?? backend.readExtra,
        _writeExtra = writeExtra ?? backend.writeExtra;

  static final CardPreviewRegistry instance = CardPreviewRegistry();

  final Future<String> Function(String viewId) _readExtra;
  final Future<void> Function(String viewId, String extra) _writeExtra;
  final Map<String, _CardPreviewState> _byView = {};
  final Map<String, Future<void>> _pending = {};

  _CardPreviewState _stateFor(ViewPB view) => _byView.putIfAbsent(
        view.id,
        () => _CardPreviewState(CardPreviewSetting.fromExtra(view.extra).mode),
      );

  ValueNotifier<CardPreviewMode> notifierFor(ViewPB view) =>
      _stateFor(view).notifier;

  CardPreviewMode modeFor(ViewPB view) => notifierFor(view).value;

  Future<void> set(ViewPB view, CardPreviewMode mode) {
    final viewId = view.id;
    final state = _stateFor(view);
    final revision = ++state.revision;
    final previous = _pending[viewId] ?? Future<void>.value();
    late final Future<void> save;
    save = previous
        .then((_) => _save(viewId, state, revision, mode))
        .whenComplete(() {
      if (identical(_pending[viewId], save)) {
        _pending.removeWhere((id, _) => id == viewId);
      }
    });
    // Enqueue before notifying: a listener may immediately choose another mode.
    unawaited(_pending[viewId] = save);
    state.notifier.value = mode;
    return save;
  }

  Future<void> _save(
    String viewId,
    _CardPreviewState state,
    int revision,
    CardPreviewMode mode,
  ) async {
    if (!identical(_byView[viewId], state)) return;
    try {
      final extra = await _readExtra(viewId);
      if (!identical(_byView[viewId], state)) return;
      state.storedMode = CardPreviewSetting.fromExtra(extra).mode;
      await _writeExtra(
        viewId,
        CardPreviewSetting(mode: mode).mergeIntoExtra(extra),
      );
      if (!identical(_byView[viewId], state)) return;
      state.storedMode = mode;
    } on Object catch (_) {
      if (identical(_byView[viewId], state) && state.revision == revision) {
        state.notifier.value = state.storedMode;
      }
      try {
        // Neither backend messages nor extra payloads are safe to log here.
        Log.warn('Could not save card preview settings');
      } on Object catch (_) {
        // Native logging may not yet be available; never poison the save queue.
      }
    }
  }

  @visibleForTesting
  void reset() {
    for (final state in _byView.values) {
      state.notifier.dispose();
    }
    _byView.clear();
    // Keep pending tails until they finish: an already dispatched write cannot
    // be cancelled and must not land after a new selection for the same view.
  }
}

class _CardPreviewState {
  _CardPreviewState(this.storedMode) : notifier = ValueNotifier(storedMode);

  final ValueNotifier<CardPreviewMode> notifier;
  CardPreviewMode storedMode;
  int revision = 0;
}

/// Adapts the folder API responses to the preview's read/write contract.
/// Keeping this boundary injectable also tests response handling, not only the
/// registry's queue with callbacks that have already discarded the response.
class CardPreviewBackend {
  const CardPreviewBackend({
    this.readView = ViewBackendService.getView,
    this.updateView = _updateView,
  });

  final Future<FlowyResult<ViewPB, FlowyError>> Function(String viewId)
      readView;
  final Future<FlowyResult<ViewPB, FlowyError>> Function(
    String viewId,
    String extra,
  ) updateView;

  Future<String> readExtra(String viewId) async =>
      (await readView(viewId)).fold(
        (view) {
          if (view.id != viewId) {
            throw StateError('Card preview read returned a different view');
          }
          return view.extra;
        },
        (_) => throw StateError('Could not read card preview settings'),
      );

  Future<void> writeExtra(String viewId, String extra) async {
    (await updateView(viewId, extra)).fold(
      // Rust's update_view_handler returns Ok(()) with no view payload. The
      // generated Dart event decodes those empty bytes as an empty ViewPB;
      // checking its ID would roll back an update that already succeeded.
      (_) {},
      (_) => throw StateError('Could not write card preview settings'),
    );
  }

  static Future<FlowyResult<ViewPB, FlowyError>> _updateView(
    String viewId,
    String extra,
  ) =>
      ViewBackendService.updateView(viewId: viewId, extra: extra);
}
