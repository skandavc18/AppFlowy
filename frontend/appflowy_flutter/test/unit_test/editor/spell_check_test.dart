import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_page_settings.dart';
import 'package:appflowy/shared/spell_check/spell_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what the checker reads as prose', () {
    test('reads ordinary words and where they sit', () {
      final words = scanWords('I recieve the document tommorow.');
      expect(
        words.map((w) => w.text),
        ['I', 'recieve', 'the', 'document', 'tommorow'],
      );
      expect(words[1].start, 2);
      expect(words[1].end, 9);
    });

    test('leaves a function name alone inside a sentence', () {
      final words = scanWords('Use the getUserName() function.');
      expect(words.map((w) => w.text), ['Use', 'the', 'function']);
    });

    test('leaves addresses, mail and paths alone', () {
      const text =
          'Read https://appflowy.io/docs, mail us at hi@appflowy.io or open '
          r'C:\Users\me\notes.md';
      expect(
        scanWords(text).map((w) => w.text),
        ['Read', 'mail', 'us', 'at', 'or', 'open'],
      );
    });

    test('leaves identifiers, versions and namespaces alone', () {
      const text = 'The user_name field of std::vector holds utf8 in v1.2.';
      expect(
        scanWords(text).map((w) => w.text),
        ['The', 'field', 'of', 'holds', 'in'],
      );
    });

    test('a full stop that ends a sentence is not a file name', () {
      expect(scanWords('This is fine.').map((w) => w.text), [
        'This',
        'is',
        'fine',
      ]);
    });

    test('honours the ranges the caller marked as not prose', () {
      const text = 'Run the widget now';
      final words = scanWords(
        text,
        excluded: const [ExcludedRange(8, 14)],
      );
      expect(words.map((w) => w.text), ['Run', 'the', 'now']);
    });

    test('an acronym is not a misspelling', () {
      expect(isAcronym('HTTP'), isTrue);
      expect(isAcronym('Http'), isFalse);
    });

    test('a sentence does not end on an abbreviation or an initial', () {
      final sentences = splitSentences('Ask Dr. Smith. She knows.');
      expect(sentences.length, 2);
    });
  });

  group('English spelling', () {
    late EnglishSpellEngine engine;

    setUp(() {
      DictionaryService.instance.seedForTest(
        words: {
          'receive',
          'received',
          'relieve',
          'the',
          'document',
          'tomorrow',
          'a',
          'lot',
          'separate',
          'colour',
          'color',
        },
        ranks: {'receive': 10, 'the': 0, 'tomorrow': 40, 'relieve': 9000},
      );
      engine = EnglishSpellEngine();
    });

    test('accepts a word that is in the list', () {
      expect(engine.accepts('document'), isTrue);
      expect(engine.accepts('Document'), isTrue);
      expect(engine.accepts('DOCUMENT'), isTrue);
    });

    test('rejects a misspelling', () {
      expect(engine.accepts('recieve'), isFalse);
    });

    test('never flags very short words or acronyms', () {
      expect(engine.accepts('an'), isTrue);
      expect(engine.accepts('SDK'), isTrue);
    });

    test('a possessive of a known word is known', () {
      expect(engine.accepts("document's"), isTrue);
    });

    test('prefers the commonly meant word over a rarer neighbour', () {
      final suggestions = engine.suggest('recieve');
      expect(suggestions.first.replacement, 'receive');
      expect(
        suggestions.map((s) => s.replacement),
        contains('relieve'),
      );
    });

    test('offers two words when one was written as one', () {
      expect(
        engine.suggest('alot').map((s) => s.replacement),
        contains('a lot'),
      );
    });

    test('a replacement takes the shape of the word it replaces', () {
      expect(engine.suggest('Recieve').first.replacement, 'Receive');
      expect(engine.suggest('RECIEVE').first.replacement, 'RECEIVE');
    });

    test('a word somebody added is accepted', () {
      DictionaryService.instance.seedForTest(
        words: const {'the'},
        userWords: const {'appflowy'},
      );
      expect(EnglishSpellEngine().accepts('AppFlowy'), isTrue);
    });
  });

  group('English grammar', () {
    const engine = EnglishGrammarEngine();

    List<String> rulesIn(String text) =>
        engine.check(text).map((issue) => issue.ruleId).toList();

    String firstFix(String text) =>
        engine.check(text).first.suggestions.first.replacement;

    test('catches a subject and verb that do not agree', () {
      expect(rulesIn("He don't like it"), contains('subject-verb'));
      expect(firstFix("He don't like it"), "He doesn't");
    });

    test('leaves a supposition alone', () {
      expect(rulesIn('If it were true'), isNot(contains('subject-verb')));
    });

    test('catches a word written twice', () {
      expect(rulesIn('this is the the answer'), contains('repeated-word'));
      expect(firstFix('this is the the answer'), 'the');
    });

    test('catches the wrong article', () {
      expect(rulesIn('I ate a apple'), contains('article'));
      expect(rulesIn('It took an hour'), isEmpty);
      expect(rulesIn('That is a one time thing'), isEmpty);
    });

    test('catches "would of"', () {
      expect(firstFix('I would of gone'), 'would have');
    });

    test('catches a comparison written with "then"', () {
      expect(firstFix('this is better then that'), 'better than');
    });

    test('capitalises a lonely i', () {
      expect(rulesIn('yesterday i left'), contains('lower-case-i'));
    });

    test('capitalises the start of a second sentence', () {
      expect(
        rulesIn('This is one sentence. this is another one.'),
        contains('sentence-capital'),
      );
    });

    test('leaves a block that simply opens in lower case alone', () {
      expect(rulesIn('a short note'), isNot(contains('sentence-capital')));
    });

    test('never marks the same words twice', () {
      final issues = engine.check("He don't like it");
      for (var i = 0; i < issues.length; i++) {
        for (var j = i + 1; j < issues.length; j++) {
          expect(issues[i].overlaps(issues[j].start, issues[j].end), isFalse);
        }
      }
    });

    test('says nothing about code', () {
      expect(engine.check('const a = a + 1;'), isEmpty);
    });
  });

  group('ignoring', () {
    const issue = SpellCheckResult(
      kind: SpellIssueKind.spelling,
      start: 4,
      end: 11,
      text: 'recieve',
    );

    setUp(IgnoreRules.instance.clear);

    test('ignoring one place leaves the same word elsewhere flagged', () {
      IgnoreRules.instance.ignoreOccurrence(issue, 'block-1');
      expect(IgnoreRules.instance.covers(issue, 'block-1'), isTrue);
      expect(IgnoreRules.instance.covers(issue, 'block-2'), isFalse);
      expect(
        IgnoreRules.instance.covers(issue.shifted(20), 'block-1'),
        isFalse,
      );
    });

    test('ignoring all covers every block', () {
      IgnoreRules.instance.ignoreEverywhere(issue);
      expect(IgnoreRules.instance.covers(issue.shifted(20), 'other'), isTrue);
      expect(IgnoreRules.instance.ignoresEverywhere('RECIEVE'), isTrue);
    });

    test('a grammar rule is ignored as a rule, not as words', () {
      const grammar = SpellCheckResult(
        kind: SpellIssueKind.grammar,
        start: 0,
        end: 3,
        text: 'the',
        ruleId: 'repeated-word',
      );
      IgnoreRules.instance.ignoreEverywhere(grammar);
      expect(IgnoreRules.instance.covers(grammar, 'a'), isTrue);
      expect(
        IgnoreRules.instance.covers(
          const SpellCheckResult(
            kind: SpellIssueKind.spelling,
            start: 0,
            end: 3,
            text: 'the',
          ),
          'a',
        ),
        isFalse,
      );
    });
  });

  group('what a page remembers', () {
    test('a page that has not been asked follows the application', () {
      expect(const SpellCheckPageMark().enabled, isNull);
    });

    test('round trips through the view mark', () {
      const mark = SpellCheckPageMark(
        enabled: false,
        ignoredWords: ['shivaya'],
      );
      final extra = mark.mergeIntoExtra('{"appflowy_collection":{"kind":"a"}}');
      final read = SpellCheckPageMark.fromExtra(extra);
      expect(read.enabled, isFalse);
      expect(read.ignoredWords, ['shivaya']);
      // Nothing else the page carries is disturbed.
      expect(extra, contains('appflowy_collection'));
    });

    test('an empty mark leaves no trace', () {
      expect(const SpellCheckPageMark().mergeIntoExtra(''), '');
    });
  });
}
