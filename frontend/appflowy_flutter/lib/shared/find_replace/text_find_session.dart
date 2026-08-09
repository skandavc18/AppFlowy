import 'package:flutter/widgets.dart';

import 'text_find.dart';

/// The state one find bar needs while it is open over a piece of text.
///
/// The session never owns the text — a host hands the current string in with
/// [setText] and reads [matches] back — so the same object serves a read-only
/// preview and an editor that is being typed into.
class TextFindSession extends ChangeNotifier {
  TextFindSession({FindOptions options = const FindOptions()})
      : _options = options {
    findController.addListener(_onQueryChanged);
  }

  final TextEditingController findController = TextEditingController();
  final TextEditingController replaceController = TextEditingController();
  final FocusNode findFocusNode = FocusNode();
  final FocusNode replaceFocusNode = FocusNode();

  String _text = '';
  List<RegExpMatch> _matches = const [];
  int _index = -1;
  bool _invalid = false;
  bool _replaceVisible = false;

  FindOptions _options;
  FindOptions get options => _options;
  set options(FindOptions value) {
    if (_options == value) {
      return;
    }
    _options = value;
    _recompute(keepPosition: true);
  }

  bool get replaceVisible => _replaceVisible;
  set replaceVisible(bool value) {
    if (_replaceVisible == value) {
      return;
    }
    _replaceVisible = value;
    notifyListeners();
  }

  String get query => findController.text;
  String get replacement => replaceController.text;
  List<RegExpMatch> get matches => _matches;
  bool get invalid => _invalid;

  /// Zero based; -1 when nothing is selected.
  int get index => _index;

  /// One based, for display.
  int get displayIndex => _index < 0 ? 0 : _index + 1;

  RegExpMatch? get currentMatch =>
      _index >= 0 && _index < _matches.length ? _matches[_index] : null;

  List<TextRange> get ranges => [
        for (final match in _matches)
          TextRange(start: match.start, end: match.end),
      ];

  TextRange? get currentRange {
    final match = currentMatch;
    return match == null ? null : TextRange(start: match.start, end: match.end);
  }

  /// Feeds the text being searched. [caret] biases which match is selected
  /// when the search is first run, so Ctrl+F lands on the match beside the
  /// cursor rather than at the top of the file. Pass `keepPosition: false`
  /// after a replacement, when the caret is the better anchor than the match
  /// that has just been rewritten.
  void setText(String value, {int? caret, bool keepPosition = true}) {
    if (caret != null) {
      _caret = caret;
    }
    if (_text == value && keepPosition) {
      return;
    }
    _text = value;
    _recompute(keepPosition: keepPosition);
  }

  int _caret = 0;

  void next() => _move(forward: true);

  void previous() => _move(forward: false);

  /// Replaces the selected match and moves to the next one.
  ///
  /// Returns the rewritten text, or null when there was nothing to replace —
  /// the host is what actually writes it back.
  String? replaceCurrent() {
    final match = currentMatch;
    if (match == null) {
      return null;
    }
    final replaced = replaceMatches(
      _text,
      [match],
      replacement,
      useRegex: _options.useRegex,
    );
    _caret = match.start +
        expandReplacement(replacement, match, useRegex: _options.useRegex)
            .length;
    return replaced;
  }

  /// Replaces every match. Returns null when there was nothing to replace.
  String? replaceAll() {
    if (_matches.isEmpty) {
      return null;
    }
    return replaceMatches(
      _text,
      _matches,
      replacement,
      useRegex: _options.useRegex,
    );
  }

  void _onQueryChanged() => _recompute(keepPosition: false);

  void _recompute({required bool keepPosition}) {
    final previous = currentMatch;
    _invalid = !isFindQueryValid(query, _options);
    _matches = _invalid ? const [] : findMatches(_text, query, _options);
    if (_matches.isEmpty) {
      _index = -1;
    } else if (keepPosition && previous != null) {
      _index = matchIndexFrom(_matches, previous.start) ?? 0;
    } else {
      _index = matchIndexFrom(_matches, _caret) ?? 0;
    }
    notifyListeners();
  }

  void _move({required bool forward}) {
    if (_matches.isEmpty) {
      return;
    }
    if (_index < 0) {
      _index = matchIndexFrom(_matches, _caret, forward: forward) ?? 0;
    } else if (forward) {
      _index = _index >= _matches.length - 1 ? 0 : _index + 1;
    } else {
      _index = _index <= 0 ? _matches.length - 1 : _index - 1;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    findController.removeListener(_onQueryChanged);
    findController.dispose();
    replaceController.dispose();
    findFocusNode.dispose();
    replaceFocusNode.dispose();
    super.dispose();
  }
}
