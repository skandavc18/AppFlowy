import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/spell_check/language_engine.dart';
import 'package:appflowy/shared/spell_check/spell_check_result.dart';
import 'package:appflowy/shared/spell_check/text_scanner.dart';

/// English grammar, as a short list of things that are plainly wrong.
///
/// Every rule here has one correct answer. Anything that depends on what the
/// writer meant — tone, word choice, sentence shape — is deliberately absent:
/// this is meant to help, not to rewrite.
class EnglishGrammarEngine implements GrammarEngine {
  const EnglishGrammarEngine();

  @override
  String get language => 'en';

  @override
  List<SpellCheckResult> check(
    String text, {
    List<ExcludedRange> excluded = const [],
  }) {
    if (text.trim().isEmpty) {
      return const [];
    }
    final skip = mergeExcludedRanges([...excluded, ...technicalRanges(text)]);
    final found = <SpellCheckResult>[];
    for (final rule in _rules) {
      for (final match in rule.pattern.allMatches(text)) {
        if (isExcluded(skip, match.start, match.end)) {
          continue;
        }
        final issue = rule.build(text, match);
        if (issue != null) {
          found.add(issue);
        }
      }
    }
    found.addAll(_sentenceCapitals(text, skip));
    found.sort((a, b) => a.start.compareTo(b.start));
    return _withoutOverlaps(found);
  }

  /// Two rules firing on the same words would draw two squiggles over one
  /// phrase; the first one wins.
  static List<SpellCheckResult> _withoutOverlaps(List<SpellCheckResult> found) {
    final kept = <SpellCheckResult>[];
    for (final issue in found) {
      if (kept.any((other) => other.overlaps(issue.start, issue.end))) {
        continue;
      }
      kept.add(issue);
    }
    return kept;
  }

  /// A sentence that follows a full stop should begin with a capital.
  ///
  /// Only sentences *inside* a block are judged, and only ones long enough to
  /// be a sentence — a block that opens in lower case is very often a list
  /// item or a note, and correcting those is nagging.
  static Iterable<SpellCheckResult> _sentenceCapitals(
    String text,
    List<ExcludedRange> skip,
  ) sync* {
    final sentences = splitSentences(text);
    for (var index = 1; index < sentences.length; index++) {
      final sentence = sentences[index];
      final body = text.substring(sentence.start, sentence.end);
      final first = body.isEmpty ? '' : body[0];
      if (first.isEmpty ||
          first != first.toLowerCase() ||
          first == first.toUpperCase()) {
        continue;
      }
      if (body.trim().split(RegExp(r'\s+')).length < 3) {
        continue;
      }
      final wordEnd = RegExp('[A-Za-z]+').matchAsPrefix(body)?.end;
      if (wordEnd == null) {
        continue;
      }
      final start = sentence.start;
      final end = start + wordEnd;
      if (isExcluded(skip, start, end)) {
        continue;
      }
      final word = text.substring(start, end);
      yield SpellCheckResult(
        kind: SpellIssueKind.grammar,
        start: start,
        end: end,
        text: word,
        ruleId: 'sentence-capital',
        message: LocaleKeys.document_spellCheck_grammar_sentenceCapital,
        suggestions: [
          Suggestion(word[0].toUpperCase() + word.substring(1)),
        ],
      );
    }
  }
}

typedef _RuleBuilder = SpellCheckResult? Function(String text, RegExpMatch m);

class _GrammarRule {
  const _GrammarRule(this.pattern, this.build);

  final RegExp pattern;
  final _RuleBuilder build;
}

SpellCheckResult _issue(
  String text,
  RegExpMatch match,
  String replacement,
  String ruleId,
  String message,
) =>
    SpellCheckResult(
      kind: SpellIssueKind.grammar,
      start: match.start,
      end: match.end,
      text: text.substring(match.start, match.end),
      ruleId: ruleId,
      message: message,
      suggestions: [Suggestion(replacement)],
    );

/// Keeps a replacement in the shape of what it replaces.
String _likeOriginal(String original, String replacement) {
  if (original.isEmpty || replacement.isEmpty) {
    return replacement;
  }
  if (original[0] == original[0].toUpperCase() &&
      original[0] != original[0].toLowerCase()) {
    return replacement[0].toUpperCase() + replacement.substring(1);
  }
  return replacement;
}

/// The word before [start], lowercased, or an empty string.
String _wordBefore(String text, int start) {
  var end = start;
  while (end > 0 && _isSpaceChar(text[end - 1])) {
    end--;
  }
  var from = end;
  while (from > 0 && RegExp("[A-Za-z']").hasMatch(text[from - 1])) {
    from--;
  }
  return text.substring(from, end).toLowerCase();
}

bool _isSpaceChar(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r';

/// Pronoun and verb pairs that never go together.
const Map<String, Map<String, String>> _agreement = {
  'he': {
    "don't": "doesn't",
    'do': 'does',
    'have': 'has',
    'are': 'is',
    'am': 'is',
    'were': 'was',
  },
  'she': {
    "don't": "doesn't",
    'do': 'does',
    'have': 'has',
    'are': 'is',
    'am': 'is',
    'were': 'was',
  },
  'it': {
    "don't": "doesn't",
    'do': 'does',
    'have': 'has',
    'are': 'is',
    'am': 'is',
  },
  'i': {'is': 'am', 'are': 'am', 'has': 'have', 'does': 'do'},
  'they': {'is': 'are', 'was': 'were', 'has': 'have', "doesn't": "don't"},
  'we': {'is': 'are', 'was': 'were', 'has': 'have', "doesn't": "don't"},
  'you': {'is': 'are', 'was': 'were', 'has': 'have', "doesn't": "don't"},
};

/// A wish or a supposition takes a verb that would otherwise look wrong.
const Set<String> _subjunctiveLeadIns = {
  'if',
  'wish',
  'wishes',
  'wished',
  'though',
  'that',
  'lest',
  'whether',
  'suppose',
  'supposing',
};

/// Words that begin with a vowel letter but a consonant sound.
final RegExp _soundsLikeConsonant = RegExp(
  r'^(?:o(?:ne|nce)|eu\w|ewe)',
  caseSensitive: false,
);

/// Words that begin with a consonant letter but a vowel sound.
final RegExp _soundsLikeVowel = RegExp(
  '^(?:hour|honest|honou?r|heir)',
  caseSensitive: false,
);

/// Words that are repeated on purpose.
const Set<String> _repeatable = {'had', 'that', 'no', 'blah', 'ha', 'very'};

final List<_GrammarRule> _rules = [
  // "the the"
  _GrammarRule(
    RegExp(r"\b([A-Za-z']+)([ \t]+)(\1)\b", caseSensitive: false),
    (text, match) {
      final word = match.group(1)!;
      if (_repeatable.contains(word.toLowerCase())) {
        return null;
      }
      return _issue(
        text,
        match,
        word,
        'repeated-word',
        LocaleKeys.document_spellCheck_grammar_repeatedWord,
      );
    },
  ),
  // "a apple"
  _GrammarRule(
    RegExp(r"\b(a)([ \t]+)([aeioAEIO][A-Za-z']*)"),
    (text, match) {
      final word = match.group(3)!;
      if (_soundsLikeConsonant.hasMatch(word)) {
        return null;
      }
      return _issue(
        text,
        match,
        '${_likeOriginal(match.group(1)!, 'an')}${match.group(2)}$word',
        'article',
        LocaleKeys.document_spellCheck_grammar_article,
      );
    },
  ),
  // "an book"
  _GrammarRule(
    RegExp(
      r"\b(an)([ \t]+)([bcdfgjklmnpqrstvwxyz][A-Za-z']*)",
      caseSensitive: false,
    ),
    (text, match) {
      final word = match.group(3)!;
      if (_soundsLikeVowel.hasMatch(word)) {
        return null;
      }
      return _issue(
        text,
        match,
        '${_likeOriginal(match.group(1)!, 'a')}${match.group(2)}$word',
        'article',
        LocaleKeys.document_spellCheck_grammar_article,
      );
    },
  ),
  // "he don't"
  _GrammarRule(
    RegExp(
      r"\b(he|she|it|i|they|we|you)([ \t]+)(don't|doesn't|do|does|have|has|is|are|am|was|were)\b",
      caseSensitive: false,
    ),
    (text, match) {
      final subject = match.group(1)!.toLowerCase();
      final verb = match.group(3)!.toLowerCase();
      final fix = _agreement[subject]?[verb];
      if (fix == null) {
        return null;
      }
      if ((verb == 'were' || verb == 'was' || verb == 'do') &&
          _subjunctiveLeadIns.contains(_wordBefore(text, match.start))) {
        return null;
      }
      return _issue(
        text,
        match,
        '${match.group(1)}${match.group(2)}'
            '${_likeOriginal(match.group(3)!, fix)}',
        'subject-verb',
        LocaleKeys.document_spellCheck_grammar_subjectVerb,
      );
    },
  ),
  // "would of"
  _GrammarRule(
    RegExp(
      r'\b(would|should|could|must|might)([ \t]+)of\b',
      caseSensitive: false,
    ),
    (text, match) => _issue(
      text,
      match,
      '${match.group(1)}${match.group(2)}have',
      'would-of',
      LocaleKeys.document_spellCheck_grammar_wouldOf,
    ),
  ),
  // "your welcome"
  _GrammarRule(
    RegExp(
      r'\b(your)([ \t]+)(welcome|going|coming|doing|being|right|wrong|correct)\b',
      caseSensitive: false,
    ),
    (text, match) => _issue(
      text,
      match,
      '${_likeOriginal(match.group(1)!, "you're")}'
          '${match.group(2)}${match.group(3)}',
      'your-youre',
      LocaleKeys.document_spellCheck_grammar_yourYoure,
    ),
  ),
  // "you're own"
  _GrammarRule(
    RegExp(r"\b(you're)([ \t]+)(own)\b", caseSensitive: false),
    (text, match) => _issue(
      text,
      match,
      '${_likeOriginal(match.group(1)!, 'your')}'
          '${match.group(2)}${match.group(3)}',
      'your-youre',
      LocaleKeys.document_spellCheck_grammar_yourYoure,
    ),
  ),
  // "their is"
  _GrammarRule(
    RegExp(
      r'\b(their)([ \t]+)(is|are|was|were)\b',
      caseSensitive: false,
    ),
    (text, match) => _issue(
      text,
      match,
      '${_likeOriginal(match.group(1)!, 'there')}'
          '${match.group(2)}${match.group(3)}',
      'there-their',
      LocaleKeys.document_spellCheck_grammar_thereTheir,
    ),
  ),
  // "there own"
  _GrammarRule(
    RegExp(r'\b(there)([ \t]+)(own)\b', caseSensitive: false),
    (text, match) => _issue(
      text,
      match,
      '${_likeOriginal(match.group(1)!, 'their')}'
          '${match.group(2)}${match.group(3)}',
      'there-their',
      LocaleKeys.document_spellCheck_grammar_thereTheir,
    ),
  ),
  // "better then"
  _GrammarRule(
    RegExp(
      r'\b(better|worse|more|less|fewer|greater|rather|other|larger|smaller|'
      'bigger|older|younger|faster|slower|higher|lower|longer|shorter|'
      r'stronger|weaker|earlier|later)([ \t]+)then\b',
      caseSensitive: false,
    ),
    (text, match) => _issue(
      text,
      match,
      '${match.group(1)}${match.group(2)}than',
      'then-than',
      LocaleKeys.document_spellCheck_grammar_thenThan,
    ),
  ),
  // "its a"
  _GrammarRule(
    RegExp(
      r'\b(its)([ \t]+)(a|an|the|not|been|going|important|possible|clear|true)\b',
      caseSensitive: false,
    ),
    (text, match) => _issue(
      text,
      match,
      "${_likeOriginal(match.group(1)!, "it's")}"
          '${match.group(2)}${match.group(3)}',
      'its-it-is',
      LocaleKeys.document_spellCheck_grammar_itsItIs,
    ),
  ),
  // "it's own"
  _GrammarRule(
    RegExp(r"\b(it's)([ \t]+)(own)\b", caseSensitive: false),
    (text, match) => _issue(
      text,
      match,
      '${_likeOriginal(match.group(1)!, 'its')}'
          '${match.group(2)}${match.group(3)}',
      'its-it-is',
      LocaleKeys.document_spellCheck_grammar_itsItIs,
    ),
  ),
  // "to much"
  _GrammarRule(
    RegExp(
      r'\b(to)([ \t]+)(much|many|late|early|big|small|hard|easy|often|late)\b',
      caseSensitive: false,
    ),
    (text, match) => _issue(
      text,
      match,
      '${_likeOriginal(match.group(1)!, 'too')}'
          '${match.group(2)}${match.group(3)}',
      'to-too',
      LocaleKeys.document_spellCheck_grammar_toToo,
    ),
  ),
  // a lonely lower case "i"
  _GrammarRule(
    RegExp('(?<![A-Za-z])i(?![A-Za-z])'),
    (text, match) => _issue(
      text,
      match,
      'I',
      'lower-case-i',
      LocaleKeys.document_spellCheck_grammar_capitalI,
    ),
  ),
];
