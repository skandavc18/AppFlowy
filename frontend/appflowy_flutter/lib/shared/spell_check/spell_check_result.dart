import 'package:flutter/foundation.dart';

/// What kind of mistake was found.
///
/// The two are told apart everywhere — a different underline, a different
/// heading in the popup — because a spelling is a fact and a grammar note is
/// an opinion.
enum SpellIssueKind {
  spelling,
  grammar;

  bool get isSpelling => this == SpellIssueKind.spelling;
}

/// One replacement offered for a mistake.
@immutable
class Suggestion {
  const Suggestion(this.replacement, {this.confidence = 1});

  /// The text that would take the place of the flagged range.
  final String replacement;

  /// How sure the engine is, 0..1. Only used for ordering.
  final double confidence;

  @override
  bool operator ==(Object other) =>
      other is Suggestion &&
      other.replacement == replacement &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(replacement, confidence);

  @override
  String toString() => 'Suggestion($replacement)';
}

/// A mistake found in one piece of natural language text.
///
/// [start] and [end] are character offsets into the text that was checked,
/// which for a page is one block's own text.
@immutable
class SpellCheckResult {
  const SpellCheckResult({
    required this.kind,
    required this.start,
    required this.end,
    required this.text,
    this.suggestions = const [],
    this.message,
    this.ruleId = '',
  });

  final SpellIssueKind kind;
  final int start;
  final int end;

  /// The text that was flagged, exactly as it appears.
  final String text;

  /// Replacements offered without being asked. A spelling leaves this empty
  /// and works its suggestions out only when somebody opens the popup, which
  /// is what keeps typing free of the expensive part.
  final List<Suggestion> suggestions;

  /// A short sentence saying what is wrong, shown for grammar only.
  final String? message;

  /// Identifies the grammar rule, so "ignore" can be about the rule rather
  /// than about the words.
  final String ruleId;

  int get length => end - start;

  bool contains(int offset) => offset >= start && offset <= end;

  bool overlaps(int from, int to) => start < to && end > from;

  SpellCheckResult shifted(int by) => SpellCheckResult(
        kind: kind,
        start: start + by,
        end: end + by,
        text: text,
        suggestions: suggestions,
        message: message,
        ruleId: ruleId,
      );

  @override
  bool operator ==(Object other) =>
      other is SpellCheckResult &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.text == text &&
      other.ruleId == ruleId &&
      listEquals(other.suggestions, suggestions) &&
      other.message == message;

  @override
  int get hashCode => Object.hash(
        kind,
        start,
        end,
        text,
        ruleId,
        message,
        Object.hashAll(suggestions),
      );

  @override
  String toString() => 'SpellCheckResult(${kind.name}, $start..$end, "$text")';
}

/// How far an "ignore" reaches.
enum IgnoreScope {
  /// Only the one place it was dismissed.
  occurrence,

  /// Everywhere, until AppFlowy is closed.
  session,

  /// Everywhere on one page, remembered with the page.
  page,
}

/// A standing instruction not to flag something again.
@immutable
class IgnoreRule {
  const IgnoreRule({
    required this.text,
    required this.scope,
    this.blockId,
    this.offset,
    this.ruleId = '',
  });

  /// The words that were dismissed, compared without regard to case.
  final String text;
  final IgnoreScope scope;

  /// Set for [IgnoreScope.occurrence] only.
  final String? blockId;
  final int? offset;

  /// Set when a grammar note rather than a spelling was dismissed.
  final String ruleId;

  bool covers(SpellCheckResult issue, String blockId) {
    if (ruleId.isNotEmpty && ruleId != issue.ruleId) {
      return false;
    }
    if (text.toLowerCase() != issue.text.toLowerCase()) {
      return false;
    }
    if (scope != IgnoreScope.occurrence) {
      return true;
    }
    return this.blockId == blockId && offset == issue.start;
  }

  @override
  bool operator ==(Object other) =>
      other is IgnoreRule &&
      other.text == text &&
      other.scope == scope &&
      other.blockId == blockId &&
      other.offset == offset &&
      other.ruleId == ruleId;

  @override
  int get hashCode => Object.hash(text, scope, blockId, offset, ruleId);
}
