import 'package:flutter/foundation.dart';

/// One word of natural language, with where it sits in the text it came from.
@immutable
class WordToken {
  const WordToken(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is WordToken &&
      other.text == text &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(text, start, end);

  @override
  String toString() => 'WordToken("$text", $start..$end)';
}

/// A half open character range that must not be read as prose.
@immutable
class ExcludedRange {
  const ExcludedRange(this.start, this.end);

  final int start;
  final int end;

  bool overlaps(int from, int to) => start < to && end > from;

  @override
  bool operator ==(Object other) =>
      other is ExcludedRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ExcludedRange($start..$end)';
}

/// Words shorter than this are never flagged.
///
/// Two letter sequences are almost all real words, initials or symbols, and
/// flagging them is the fastest way to make a page look broken.
const int minimumCheckedWordLength = 3;

final RegExp _wordPattern = RegExp(r"[A-Za-z]+(?:['\u2019][A-Za-z]+)*");

/// Everything that is a name for a machine rather than a word for a reader.
///
/// The order matters only in that the ranges are merged afterwards; each
/// pattern is deliberately narrow so ordinary prose is not swallowed.
final List<RegExp> _technicalPatterns = [
  // Web and mail addresses.
  RegExp(r'\b(?:https?|ftp|mailto|file)://\S+', caseSensitive: false),
  RegExp(r'\bwww\.[^\s]+', caseSensitive: false),
  RegExp(r'\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+'),
  // Windows and POSIX paths.
  RegExp(r'\b[A-Za-z]:\\[^\s]*'),
  RegExp(r'\\\\[^\s]+'),
  RegExp(r'(?:\.{1,2})?/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+/?'),
  // A file name carries an extension.
  RegExp(
    r'\b[\w-]+\.(?:dart|js|jsx|ts|tsx|json|ya?ml|toml|md|markdown|html?|css|scss|py|rb|rs|go|java|kt|swift|c|cc|cpp|h|hpp|cs|php|sh|bat|ps1|sql|xml|svg|png|jpe?g|gif|webp|pdf|docx?|xlsx?|pptx?|csv|txt|log|zip|tar|gz|exe|dll|so|lock|env|ini|cfg)\b',
    caseSensitive: false,
  ),
  // Namespaced or dotted identifiers: package.name, std::vector, a->b.
  RegExp(r'\b[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)+\b'),
  RegExp(r'[A-Za-z_$][\w$]*(?:::[A-Za-z_$][\w$]*)+'),
  RegExp(r'[A-Za-z_$][\w$]*(?:->|=>)[A-Za-z_$][\w$]*'),
  // snake_case, SCREAMING_SNAKE and leading underscores.
  RegExp(r'\b\w*_\w+\b'),
  // camelCase and PascalCase runs, which are names rather than words.
  RegExp(r'\b[a-z]+[A-Z]\w*'),
  RegExp(r'\b[A-Z][a-z]+[A-Z]\w*'),
  // Anything with a digit welded to it, including hex and versions.
  RegExp(r'\b\w*\d[\w.]*\b'),
  // A call or an index.
  RegExp(r'\b[A-Za-z_$][\w$]*(?=\s*[(\[<])'),
  // Something spelled out for a machine to copy.
  RegExp(r'\b[A-Za-z_$][\w$]*(?:-[A-Za-z_$][\w$]*){2,}\b'),
  // A handle or a tag.
  RegExp(r'[@#][A-Za-z_][\w-]*'),
  // Mathematics written in line: x = y + 2, a * b, 3 <= n.
  RegExp(r'[A-Za-z0-9_)\]]\s*(?:[=+*/^%<>]|[!<>=]=|\+\+|--)\s*[A-Za-z0-9_(\[]'),
];

/// Finds the parts of [text] that are technical rather than prose.
///
/// Ranges come back sorted and merged.
List<ExcludedRange> technicalRanges(String text) {
  final ranges = <ExcludedRange>[];
  for (final pattern in _technicalPatterns) {
    for (final match in pattern.allMatches(text)) {
      if (match.end > match.start) {
        ranges.add(ExcludedRange(match.start, match.end));
      }
    }
  }
  return mergeExcludedRanges(ranges);
}

/// Sorts and joins overlapping or touching ranges.
List<ExcludedRange> mergeExcludedRanges(List<ExcludedRange> ranges) {
  if (ranges.length < 2) {
    return List.unmodifiable(ranges);
  }
  final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <ExcludedRange>[sorted.first];
  for (final range in sorted.skip(1)) {
    final last = merged.last;
    if (range.start <= last.end) {
      if (range.end > last.end) {
        merged[merged.length - 1] = ExcludedRange(last.start, range.end);
      }
    } else {
      merged.add(range);
    }
  }
  return List.unmodifiable(merged);
}

/// Whether [from]..[to] falls inside anything that must not be checked.
bool isExcluded(List<ExcludedRange> ranges, int from, int to) {
  for (final range in ranges) {
    if (range.overlaps(from, to)) {
      return true;
    }
  }
  return false;
}

/// Reads [text] as prose and returns the words worth checking.
///
/// [excluded] carries the ranges the caller already knows to be off limits —
/// inline code, links, mentions and formulas — and the technical shapes found
/// in the words themselves are added to it.
List<WordToken> scanWords(
  String text, {
  List<ExcludedRange> excluded = const [],
}) {
  if (text.isEmpty) {
    return const [];
  }
  final skip = mergeExcludedRanges([...excluded, ...technicalRanges(text)]);
  final words = <WordToken>[];
  for (final match in _wordPattern.allMatches(text)) {
    if (isExcluded(skip, match.start, match.end)) {
      continue;
    }
    words.add(WordToken(match.group(0)!, match.start, match.end));
  }
  return words;
}

/// Words that are written in capitals on purpose: an acronym, not a mistake.
bool isAcronym(String word) =>
    word.length > 1 && word == word.toUpperCase() && word != word.toLowerCase();

/// Strips the punctuation a spelling should not be judged on.
String normalizeWord(String word) =>
    word.replaceAll('\u2019', "'").toLowerCase();

const Set<String> _abbreviations = {
  'mr',
  'mrs',
  'ms',
  'dr',
  'prof',
  'sr',
  'jr',
  'st',
  'vs',
  'etc',
  'inc',
  'ltd',
  'co',
  'fig',
  'no',
  'approx',
  'dept',
  'est',
  'eg',
  'ie',
  'al',
  'am',
  'pm',
};

/// Splits [text] into sentences, keeping their offsets.
///
/// The full stop after an abbreviation does not end a sentence, and neither
/// does one that is not followed by a space — that is a version number or a
/// name for a machine.
List<ExcludedRange> splitSentences(String text) {
  final sentences = <ExcludedRange>[];
  var start = 0;
  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (char != '.' && char != '!' && char != '?' && char != '\n') {
      continue;
    }
    var end = index + 1;
    while (end < text.length && '.!?'.contains(text[end])) {
      end++;
    }
    if (end < text.length && !_isSpace(text[end])) {
      continue;
    }
    if (char == '.' && _endsWithAbbreviation(text, index)) {
      continue;
    }
    if (end > start) {
      sentences.add(ExcludedRange(start, end));
    }
    start = end;
    while (start < text.length && _isSpace(text[start])) {
      start++;
    }
    index = start - 1;
  }
  if (start < text.length) {
    sentences.add(ExcludedRange(start, text.length));
  }
  return sentences;
}

bool _isSpace(String char) =>
    char == ' ' || char == '\n' || char == '\t' || char == '\r';

bool _endsWithAbbreviation(String text, int dot) {
  var start = dot;
  while (start > 0 && RegExp('[A-Za-z]').hasMatch(text[start - 1])) {
    start--;
  }
  if (start == dot) {
    return false;
  }
  final word = text.substring(start, dot).toLowerCase();
  // A single letter before a stop is an initial, not the end of a sentence.
  return word.length == 1 || _abbreviations.contains(word);
}
