import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:flutter/widgets.dart';

import 'ocr_result.dart';

/// A word in reading order. Offsets refer to [OcrFindSession.text], never to a
/// lowercased copy (case folding can change the number of UTF-16 code units).
@immutable
class OcrFindWord {
  const OcrFindWord({
    required this.line,
    required this.text,
    required this.range,
    required this.bounds,
  });

  final int line;
  final String text;
  final TextRange range;
  final Rect bounds;
}

@immutable
class OcrFindMatch {
  const OcrFindMatch({required this.range, required this.wordIndices});

  final TextRange range;
  final List<int> wordIndices;
}

/// Read-only OCR find/selection. Searching and moving never touch a clipboard.
/// The native words are the source of both geometry AND copied selections.
class OcrFindSession extends ChangeNotifier {
  OcrFindSession({String initialQuery = ''})
      : findController = TextEditingController(text: initialQuery) {
    findController.addListener(_queryChanged);
  }

  final TextEditingController findController;
  final FocusNode findFocusNode = FocusNode(debugLabel: 'Image OCR find');
  List<OcrFindWord> _words = const [];
  List<OcrFindMatch> _matches = const [];
  Map<int, List<int>> _lineWords = const {};
  Set<int> _selected = const {};
  String _text = '';
  String _query = '';
  FindOptions _options = const FindOptions();
  int _index = -1;
  bool _invalid = false;
  bool _disposed = false;

  String get text => _text;
  String get query => findController.text;
  FindOptions get options => _options;
  List<OcrFindWord> get words => _words;
  List<OcrFindMatch> get matches => _matches;
  Set<int> get selected => _selected;
  int get index => _index;
  int get displayIndex => _index + 1;
  bool get invalid => _invalid;
  OcrFindMatch? get currentMatch => _index < 0 ? null : _matches[_index];

  set options(FindOptions value) {
    if (_disposed || value == _options) return;
    _options = value;
    _recompute();
  }

  /// Replaces the whole index on a scan/retry/source change, even when its text
  /// happens to be identical: the new picture may have different word boxes.
  void setResult(OcrResult? result) {
    if (_disposed) return;
    final words = <OcrFindWord>[];
    final lineWords = <int, List<int>>{};
    final buffer = StringBuffer();
    for (final (lineIndex, line) in (result?.lines ?? <OcrLine>[]).indexed) {
      final nativeWords = (line.words.isEmpty
              ? [OcrWord(text: line.text, bounds: line.bounds)]
              : line.words)
          .where((word) => word.text.trim().isNotEmpty)
          .toList();
      final indices = <int>[];
      // Preserve native spacing/punctuation, including languages that do not
      // separate words with spaces. Fall back to words only if a provider's
      // line text cannot be mapped to its own word sequence.
      final ranges = <TextRange>[];
      var cursor = 0;
      for (final word in nativeWords) {
        final start = line.text.indexOf(word.text, cursor);
        if (start < 0) break;
        cursor = start + word.text.length;
        ranges.add(TextRange(start: start, end: cursor));
      }
      var lineText = line.text;
      if (ranges.length != nativeWords.length) {
        ranges.clear();
        final fallback = StringBuffer();
        for (final word in nativeWords) {
          if (fallback.isNotEmpty) fallback.write(' ');
          final start = fallback.length;
          fallback.write(word.text);
          ranges.add(TextRange(start: start, end: fallback.length));
        }
        lineText = fallback.toString();
      }
      if (nativeWords.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.write('\n');
      final lineStart = buffer.length;
      buffer.write(lineText);
      for (final (index, word) in nativeWords.indexed) {
        indices.add(words.length);
        words.add(
          OcrFindWord(
            line: lineIndex,
            text: word.text,
            range: TextRange(
              start: lineStart + ranges[index].start,
              end: lineStart + ranges[index].end,
            ),
            bounds: word.normalizedBounds,
          ),
        );
      }
      lineWords[lineIndex] = List.unmodifiable(indices);
    }
    _text = buffer.toString();
    _words = List.unmodifiable(words);
    _lineWords = Map.unmodifiable(lineWords);
    _recompute();
  }

  Iterable<int> wordsInLine(int line) => _lineWords[line] ?? const <int>[];

  void next() => selectMatch(_index + 1);
  void previous() => selectMatch(_index - 1);

  void selectMatch(int index) {
    if (_disposed || _matches.isEmpty) return;
    _index = index % _matches.length;
    _selected = Set.unmodifiable(_matches[_index].wordIndices);
    notifyListeners();
  }

  void selectWords(Iterable<int> indices, {bool additive = false}) {
    if (_disposed) return;
    final next = additive ? _selected.toSet() : <int>{};
    for (final index in indices.toSet()) {
      if (index < 0 || index >= _words.length) continue;
      if (!additive || !next.remove(index)) next.add(index);
    }
    _selected = Set.unmodifiable(next);
    notifyListeners();
  }

  void selectAll() => selectWords(Iterable<int>.generate(_words.length));

  /// Original word text/case, in reading order, with line breaks retained.
  /// A partial-word find selects/copies that actual word, not the typed query
  /// and not unrelated words elsewhere on its line.
  String textOfWords(Iterable<int> indices) {
    final ordered = indices.toSet().toList()..sort();
    final buffer = StringBuffer();
    int? previous;
    for (final index in ordered) {
      if (index < 0 || index >= _words.length) continue;
      final word = _words[index];
      if (previous != null) {
        final before = _words[previous];
        buffer.write(
          before.line != word.line
              ? '\n'
              : index == previous + 1
                  ? _text.substring(before.range.end, word.range.start)
                  : ' ',
        );
      }
      buffer.write(word.text);
      previous = index;
    }
    return buffer.toString();
  }

  String get selectedText => textOfWords(_selected);
  String get currentText =>
      textOfWords(currentMatch?.wordIndices ?? const <int>[]);

  List<Rect> boundsOf(Iterable<int> indices) => [
        for (final index in indices)
          if (index >= 0 &&
              index < _words.length &&
              !_words[index].bounds.isEmpty)
            _words[index].bounds,
      ];

  void _queryChanged() {
    // Moving the caret or selecting the query must not reset the current hit.
    if (_disposed || _query == query) return;
    _recompute();
  }

  void _recompute() {
    _query = query;
    _invalid = !isFindQueryValid(_query, _options);
    final matches = <OcrFindMatch>[];
    if (!_invalid && _query.trim().isNotEmpty) {
      // Literal whitespace spans OCR line breaks too. Regexp mode is passed
      // through verbatim; metacharacters in ordinary queries stay literal.
      final pattern = _options.useRegex
          ? buildFindPattern(_query, _options)
          : RegExp(
              findPatternSource(_query, _options)
                  .replaceAll(RegExp(r'\s+'), r'\s+'),
              caseSensitive: _options.caseSensitive,
              multiLine: true,
            );
      if (pattern != null) {
        var firstWord = 0;
        for (final match in pattern.allMatches(_text)) {
          if (match.end <= match.start) continue;
          while (firstWord < _words.length &&
              _words[firstWord].range.end <= match.start) {
            firstWord++;
          }
          final indices = <int>[];
          for (var i = firstWord;
              i < _words.length && _words[i].range.start < match.end;
              i++) {
            indices.add(i);
          }
          if (indices.isNotEmpty) {
            matches.add(
              OcrFindMatch(
                range: TextRange(start: match.start, end: match.end),
                wordIndices: List.unmodifiable(indices),
              ),
            );
          }
        }
      }
    }
    _matches = List.unmodifiable(matches);
    _index = matches.isEmpty ? -1 : 0;
    _selected = matches.isEmpty
        ? const {}
        : Set.unmodifiable(matches.first.wordIndices);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    findController.removeListener(_queryChanged);
    findController.dispose();
    findFocusNode.dispose();
    _words = const [];
    _matches = const [];
    _selected = const {};
    _lineWords = const {};
    _text = '';
    _index = -1;
    super.dispose();
  }
}
