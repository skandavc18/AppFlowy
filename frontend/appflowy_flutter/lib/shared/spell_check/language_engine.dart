import 'package:appflowy/shared/spell_check/spell_check_result.dart';
import 'package:appflowy/shared/spell_check/text_scanner.dart';

/// One language's answer to "is this spelled correctly?".
///
/// Nothing above this interface knows how the answer is reached, so a
/// different engine — another language, a service, a platform checker — can
/// be put in its place without the editor changing at all.
abstract class SpellEngine {
  /// The language this engine reads, as a BCP 47 tag.
  String get language;

  /// Whether the engine has everything it needs to answer.
  bool get isReady;

  /// Loads whatever the engine needs. Safe to call more than once.
  Future<void> prepare();

  /// Whether [word] is spelled correctly. [word] arrives exactly as written.
  bool accepts(String word);

  /// Replacements for a word this engine rejected, best first.
  ///
  /// This is deliberately separate from [accepts]: finding candidates is the
  /// expensive half, and it is only ever asked for when somebody opens the
  /// suggestions.
  List<Suggestion> suggest(String word, {int limit = 5});
}

/// One language's answer to "does this sentence hold together?".
abstract class GrammarEngine {
  String get language;

  /// Reads [text] and reports what is clearly wrong.
  ///
  /// [excluded] marks the parts that are not prose. Implementations are
  /// expected to be conservative: a page covered in coloured squiggles is
  /// worse than one with none.
  List<SpellCheckResult> check(
    String text, {
    List<ExcludedRange> excluded = const [],
  });
}

/// The engines the application knows about, one pair per language.
///
/// English is all that is registered today; adding another language is
/// registering it here and nothing else.
class LanguageEngines {
  LanguageEngines._();

  static final LanguageEngines instance = LanguageEngines._();

  final Map<String, SpellEngine> _spelling = {};
  final Map<String, GrammarEngine> _grammar = {};

  void registerSpelling(SpellEngine engine) =>
      _spelling[engine.language] = engine;

  void registerGrammar(GrammarEngine engine) =>
      _grammar[engine.language] = engine;

  SpellEngine? spellingFor(String language) => _spelling[language];

  GrammarEngine? grammarFor(String language) => _grammar[language];

  Iterable<String> get languages => _spelling.keys;
}
