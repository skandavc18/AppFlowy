import 'package:appflowy/shared/spell_check/dictionary_service.dart';
import 'package:appflowy/shared/spell_check/english_grammar.dart';
import 'package:appflowy/shared/spell_check/english_spelling.dart';
import 'package:appflowy/shared/spell_check/language_engine.dart';
import 'package:appflowy/shared/spell_check/spell_check_result.dart';
import 'package:appflowy/shared/spell_check/text_scanner.dart';

/// The only language AppFlowy checks today.
///
/// It is a value rather than an assumption so that the day a second language
/// arrives, the editor does not have to learn about it.
const String defaultCheckedLanguage = 'en';

void _registerBuiltInEngines() {
  final engines = LanguageEngines.instance;
  if (engines.spellingFor(defaultCheckedLanguage) == null) {
    engines.registerSpelling(EnglishSpellEngine());
  }
  if (engines.grammarFor(defaultCheckedLanguage) == null) {
    engines.registerGrammar(const EnglishGrammarEngine());
  }
}

/// Reads text for misspellings.
///
/// Everything above this talks to the service, never to an engine, so the
/// engine can be replaced without a single editor file changing.
class SpellCheckService {
  SpellCheckService._();

  static final SpellCheckService instance = SpellCheckService._();

  String language = defaultCheckedLanguage;

  SpellEngine? get _engine {
    _registerBuiltInEngines();
    return LanguageEngines.instance.spellingFor(language);
  }

  bool get isReady => _engine?.isReady ?? false;

  /// Everything the checker needs is loaded here rather than found missing
  /// halfway through a page.
  Future<void> prepare() async {
    await DictionaryService.instance.ensureLoaded();
    await _engine?.prepare();
  }

  /// The misspellings in one piece of prose.
  ///
  /// [excluded] carries the ranges the caller knows are not prose: inline
  /// code, links, mentions, formulas.
  List<SpellCheckResult> check(
    String text, {
    List<ExcludedRange> excluded = const [],
  }) {
    final engine = _engine;
    if (engine == null || !engine.isReady || text.trim().isEmpty) {
      return const [];
    }
    final issues = <SpellCheckResult>[];
    for (final word in scanWords(text, excluded: excluded)) {
      if (engine.accepts(word.text)) {
        continue;
      }
      issues.add(
        SpellCheckResult(
          kind: SpellIssueKind.spelling,
          start: word.start,
          end: word.end,
          text: word.text,
        ),
      );
    }
    return issues;
  }

  /// What the writer probably meant. Worked out on demand, never while typing.
  List<Suggestion> suggestionsFor(String word, {int limit = 5}) =>
      _engine?.suggest(word, limit: limit) ?? const [];

  bool accepts(String word) => _engine?.accepts(word) ?? true;
}

/// Reads text for grammar that is plainly wrong.
class GrammarCheckService {
  GrammarCheckService._();

  static final GrammarCheckService instance = GrammarCheckService._();

  String language = defaultCheckedLanguage;

  GrammarEngine? get _engine {
    _registerBuiltInEngines();
    return LanguageEngines.instance.grammarFor(language);
  }

  List<SpellCheckResult> check(
    String text, {
    List<ExcludedRange> excluded = const [],
  }) =>
      _engine?.check(text, excluded: excluded) ?? const [];
}
