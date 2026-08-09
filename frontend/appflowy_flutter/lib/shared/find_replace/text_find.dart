import 'package:flutter/foundation.dart';

/// How a query is turned into a pattern.
///
/// The three switches are the ones a person expects from an editor: match the
/// letter case, match whole words only, and read the query as a regular
/// expression instead of literal text.
@immutable
class FindOptions {
  const FindOptions({
    this.caseSensitive = false,
    this.wholeWord = false,
    this.useRegex = false,
  });

  final bool caseSensitive;
  final bool wholeWord;
  final bool useRegex;

  FindOptions copyWith({
    bool? caseSensitive,
    bool? wholeWord,
    bool? useRegex,
  }) =>
      FindOptions(
        caseSensitive: caseSensitive ?? this.caseSensitive,
        wholeWord: wholeWord ?? this.wholeWord,
        useRegex: useRegex ?? this.useRegex,
      );

  @override
  bool operator ==(Object other) =>
      other is FindOptions &&
      other.caseSensitive == caseSensitive &&
      other.wholeWord == wholeWord &&
      other.useRegex == useRegex;

  @override
  int get hashCode => Object.hash(caseSensitive, wholeWord, useRegex);
}

/// The expression source a query resolves to, before it is compiled.
///
/// Kept separate from [buildFindPattern] so a host that drives someone else's
/// searcher — pdfrx, or the editor's own service — can hand over the same
/// expression instead of reimplementing the rules.
String findPatternSource(String query, FindOptions options) {
  final body = options.useRegex ? query : RegExp.escape(query);
  if (!options.wholeWord) {
    return body;
  }
  // Lookarounds rather than \b: a query that begins or ends with punctuation
  // ("--flag", "()") has no word boundary there, and \b would refuse to match
  // it at all.
  final leading =
      options.useRegex || _startsWithWordCharacter(query) ? r'(?<!\w)' : '';
  final trailing =
      options.useRegex || _endsWithWordCharacter(query) ? r'(?!\w)' : '';
  return '$leading(?:$body)$trailing';
}

/// Compiles [query] into a pattern, or returns null when there is nothing to
/// look for.
///
/// Throws [FormatException] when the person is typing a regular expression
/// that is not valid yet — callers show that as a hint rather than a failure.
RegExp? buildFindPattern(String query, FindOptions options) {
  if (query.isEmpty) {
    return null;
  }
  return RegExp(
    findPatternSource(query, options),
    caseSensitive: options.caseSensitive,
    multiLine: true,
  );
}

/// Every match of [query] in [text], in reading order.
///
/// Zero-width matches are dropped: a pattern such as `a*` matches between
/// every pair of characters, which is noise rather than a result.
List<RegExpMatch> findMatches(
  String text,
  String query,
  FindOptions options,
) {
  final RegExp? pattern;
  try {
    pattern = buildFindPattern(query, options);
  } on FormatException {
    return const [];
  }
  if (pattern == null || text.isEmpty) {
    return const [];
  }
  return matchesOfPattern(text, pattern);
}

/// Every match of an already compiled [pattern], with zero-width hits dropped.
List<RegExpMatch> matchesOfPattern(String text, RegExp pattern) =>
    pattern.allMatches(text).where((match) => match.end > match.start).toList();

/// Whether [query] compiles under [options].
bool isFindQueryValid(String query, FindOptions options) {
  if (query.isEmpty) {
    return true;
  }
  try {
    buildFindPattern(query, options);
    return true;
  } on FormatException {
    return false;
  }
}

/// What one match is replaced with.
///
/// In regular-expression mode the replacement may refer to captured groups —
/// `$1` or `\1` for a numbered group, `$&` for the whole match, `$$` for a
/// literal dollar. In literal mode the replacement is written out as typed,
/// because somebody replacing "cost: $5" did not mean to name a group.
String expandReplacement(
  String replacement,
  RegExpMatch match, {
  required bool useRegex,
}) {
  if (!useRegex || replacement.isEmpty) {
    return replacement;
  }
  final buffer = StringBuffer();
  for (var index = 0; index < replacement.length; index++) {
    final character = replacement[index];
    final isReference = character == r'$' || character == r'\';
    if (!isReference || index == replacement.length - 1) {
      buffer.write(character);
      continue;
    }
    final next = replacement[index + 1];
    if (character == r'$' && next == r'$') {
      buffer.write(r'$');
      index++;
      continue;
    }
    if (character == r'$' && next == '&') {
      buffer.write(match.group(0) ?? '');
      index++;
      continue;
    }
    if (character == r'\' && next == r'\') {
      buffer.write(r'\');
      index++;
      continue;
    }
    final digits = _leadingDigits(replacement, index + 1);
    if (digits.isEmpty) {
      buffer.write(character);
      continue;
    }
    final group = int.parse(digits);
    if (group > match.groupCount) {
      buffer.write(character);
      continue;
    }
    buffer.write(match.group(group) ?? '');
    index += digits.length;
  }
  return buffer.toString();
}

/// [text] with every match of [query] replaced.
String replaceAllMatches(
  String text,
  String query,
  String replacement,
  FindOptions options,
) {
  final matches = findMatches(text, query, options);
  if (matches.isEmpty) {
    return text;
  }
  return replaceMatches(text, matches, replacement, useRegex: options.useRegex);
}

/// [text] with each of [matches] replaced. The matches must be in order and
/// must not overlap, which is what [findMatches] returns.
String replaceMatches(
  String text,
  List<RegExpMatch> matches,
  String replacement, {
  required bool useRegex,
}) {
  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in matches) {
    buffer
      ..write(text.substring(cursor, match.start))
      ..write(expandReplacement(replacement, match, useRegex: useRegex));
    cursor = match.end;
  }
  buffer.write(text.substring(cursor));
  return buffer.toString();
}

/// The match a search should land on when it starts from [offset].
///
/// Searching forward takes the first match at or after the caret and wraps to
/// the top; searching back takes the last match before it and wraps to the
/// bottom. Returns null when there is nothing to go to.
int? matchIndexFrom(
  List<RegExpMatch> matches,
  int offset, {
  bool forward = true,
}) {
  if (matches.isEmpty) {
    return null;
  }
  if (forward) {
    for (var index = 0; index < matches.length; index++) {
      if (matches[index].start >= offset) {
        return index;
      }
    }
    return 0;
  }
  for (var index = matches.length - 1; index >= 0; index--) {
    if (matches[index].end <= offset) {
      return index;
    }
  }
  return matches.length - 1;
}

String _leadingDigits(String value, int start) {
  var end = start;
  while (end < value.length && _isDigit(value.codeUnitAt(end))) {
    end++;
  }
  // Two digits at most: "$12" in a document with one group means group 1
  // followed by a 2 far more often than it means group 12.
  final limit = start + 2;
  return value.substring(start, end > limit ? limit : end);
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

bool _startsWithWordCharacter(String value) =>
    value.isNotEmpty && _isWordCharacter(value.codeUnitAt(0));

bool _endsWithWordCharacter(String value) =>
    value.isNotEmpty && _isWordCharacter(value.codeUnitAt(value.length - 1));

bool _isWordCharacter(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7A) ||
    codeUnit == 0x5F;
