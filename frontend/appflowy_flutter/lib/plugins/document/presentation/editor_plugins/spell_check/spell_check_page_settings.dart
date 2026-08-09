import 'dart:convert';

import 'package:appflowy/shared/spell_check/spell_check.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/foundation.dart';

/// What one page has said about checking its own writing.
///
/// It rides in `ViewPB.extra` beside every other mark a page carries, so the
/// backend knows nothing about it and the choice travels with the page.
@immutable
class SpellCheckPageMark {
  const SpellCheckPageMark({this.enabled, this.ignoredWords = const []});

  static const envelopeKey = 'appflowy_spell_check';
  static const currentVersion = 1;

  /// `null` means the page has not been asked and follows the application.
  final bool? enabled;

  /// Words this page was told to leave alone.
  final List<String> ignoredWords;

  SpellCheckPageMark copyWith({
    bool? enabled,
    List<String>? ignoredWords,
  }) =>
      SpellCheckPageMark(
        enabled: enabled ?? this.enabled,
        ignoredWords: ignoredWords ?? this.ignoredWords,
      );

  bool get isEmpty => enabled == null && ignoredWords.isEmpty;

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        if (enabled != null) 'enabled': enabled,
        if (ignoredWords.isNotEmpty) 'ignored': ignoredWords,
      };

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    if (isEmpty) {
      values.remove(envelopeKey);
    } else {
      values[envelopeKey] = toJson();
    }
    return values.isEmpty ? '' : jsonEncode(values);
  }

  static SpellCheckPageMark fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return const SpellCheckPageMark();
    }
    final values = Map<String, dynamic>.from(envelope);
    final ignored = values['ignored'];
    return SpellCheckPageMark(
      enabled: values['enabled'] is bool ? values['enabled'] as bool : null,
      ignoredWords: ignored is List
          ? ignored.whereType<String>().map((w) => w.toLowerCase()).toList()
          : const [],
    );
  }
}

/// Holds what every open page has said, and writes it back to the page.
///
/// A page and its "..." menu are far apart in the widget tree, so the answer
/// lives here where both can reach it.
class SpellCheckPageSettings extends ChangeNotifier {
  SpellCheckPageSettings._();

  static final SpellCheckPageSettings instance = SpellCheckPageSettings._();

  final Map<String, SpellCheckPageMark> _marks = {};

  /// Reads what a page carries. Called whenever a page is opened or its
  /// details change.
  void adopt(ViewPB view) {
    final mark = SpellCheckPageMark.fromExtra(view.extra);
    if (_marks[view.id] == null ||
        _marks[view.id]!.enabled != mark.enabled ||
        !listEquals(_marks[view.id]!.ignoredWords, mark.ignoredWords)) {
      _marks[view.id] = mark;
      notifyListeners();
    }
  }

  SpellCheckPageMark markFor(String viewId) =>
      _marks[viewId] ?? const SpellCheckPageMark();

  /// Whether this page is checked, with the page's own answer beating the
  /// application's default.
  bool isEnabledFor(String viewId) =>
      markFor(viewId).enabled ?? SpellCheckSettings.instance.spellingEnabled;

  bool isIgnoredOnPage(String viewId, String word) =>
      markFor(viewId).ignoredWords.contains(word.toLowerCase());

  Future<void> setEnabled(String viewId, bool enabled, {String? extra}) =>
      _write(viewId, extra, markFor(viewId).copyWith(enabled: enabled));

  Future<void> ignoreWordOnPage(
    String viewId,
    String word, {
    String? extra,
  }) async {
    final normalized = word.toLowerCase();
    final mark = markFor(viewId);
    if (mark.ignoredWords.contains(normalized)) {
      return;
    }
    await _write(
      viewId,
      extra,
      mark.copyWith(ignoredWords: [...mark.ignoredWords, normalized]),
    );
  }

  Future<void> _write(
    String viewId,
    String? extra,
    SpellCheckPageMark mark,
  ) async {
    _marks[viewId] = mark;
    notifyListeners();
    // The page carries other marks too, so the newest copy of them is read
    // back before this one is folded in.
    final current = extra ?? await _currentExtra(viewId);
    final result = await ViewBackendService.updateView(
      viewId: viewId,
      extra: mark.mergeIntoExtra(current),
    );
    result.onFailure(
      (error) => Log.warn('The page could not remember its spell check '
          'setting: ${error.msg}'),
    );
  }

  Future<String> _currentExtra(String viewId) async {
    final result = await ViewBackendService.getView(viewId);
    return result.fold((view) => view.extra, (_) => '');
  }

  @visibleForTesting
  void seedForTest(String viewId, SpellCheckPageMark mark) {
    _marks[viewId] = mark;
    notifyListeners();
  }
}
