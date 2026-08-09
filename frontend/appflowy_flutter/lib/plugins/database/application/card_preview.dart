import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// What a card shows above its title.
enum CardPreviewMode {
  /// The row's cover picture, when it has one.
  cover('cover'),

  /// The opening of the row's own page.
  pageContent('page'),

  /// Nothing: the title and its properties, and no more.
  none('none');

  const CardPreviewMode(this.id);

  final String id;

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
    return CardPreviewSetting(
      mode: CardPreviewMode.fromId(values['mode'] as String?),
    );
  }
}

/// The choice, shared between the toolbar that sets it and the cards that
/// answer to it.
///
/// The two sit side by side rather than one above the other, so a notifier per
/// view is what lets a card follow the choice without its host rebuilding.
class CardPreviewRegistry {
  CardPreviewRegistry._();

  static final CardPreviewRegistry instance = CardPreviewRegistry._();

  final Map<String, ValueNotifier<CardPreviewMode>> _byView = {};

  ValueNotifier<CardPreviewMode> notifierFor(ViewPB view) =>
      _byView.putIfAbsent(
        view.id,
        () => ValueNotifier(CardPreviewSetting.fromExtra(view.extra).mode),
      );

  CardPreviewMode modeFor(ViewPB view) => notifierFor(view).value;

  Future<void> set(ViewPB view, CardPreviewMode mode) async {
    notifierFor(view).value = mode;
    await ViewBackendService.updateView(
      viewId: view.id,
      extra: CardPreviewSetting(mode: mode).mergeIntoExtra(view.extra),
    );
  }

  @visibleForTesting
  void reset() {
    for (final notifier in _byView.values) {
      notifier.dispose();
    }
    _byView.clear();
  }
}
