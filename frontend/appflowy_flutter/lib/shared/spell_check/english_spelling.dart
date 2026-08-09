import 'package:appflowy/shared/spell_check/dictionary_service.dart';
import 'package:appflowy/shared/spell_check/language_engine.dart';
import 'package:appflowy/shared/spell_check/spell_check_result.dart';
import 'package:appflowy/shared/spell_check/text_scanner.dart';

/// Misspellings common enough to be worth naming, because an edit distance
/// alone often prefers a rarer word ("relieve" for "recieve").
const Map<String, String> commonEnglishMisspellings = {
  'accomodate': 'accommodate',
  'acheive': 'achieve',
  'accross': 'across',
  'adress': 'address',
  'agressive': 'aggressive',
  'alot': 'a lot',
  'apparant': 'apparent',
  'arguement': 'argument',
  'assasin': 'assassin',
  'basicly': 'basically',
  'becuase': 'because',
  'begining': 'beginning',
  'beleive': 'believe',
  'belive': 'believe',
  'buisness': 'business',
  'calender': 'calendar',
  'cemetary': 'cemetery',
  'changable': 'changeable',
  'cheif': 'chief',
  'collegue': 'colleague',
  'comming': 'coming',
  'commitee': 'committee',
  'commited': 'committed',
  'completly': 'completely',
  'concious': 'conscious',
  'definately': 'definitely',
  'definatly': 'definitely',
  'dependant': 'dependent',
  'diffrent': 'different',
  'dilemna': 'dilemma',
  'dissapear': 'disappear',
  'dissapoint': 'disappoint',
  'embarass': 'embarrass',
  'enviroment': 'environment',
  'existance': 'existence',
  'experiance': 'experience',
  'explaination': 'explanation',
  'familar': 'familiar',
  'finaly': 'finally',
  'foriegn': 'foreign',
  'freind': 'friend',
  'fourty': 'forty',
  'gaurd': 'guard',
  'goverment': 'government',
  'grammer': 'grammar',
  'happend': 'happened',
  'harrass': 'harass',
  'immediatly': 'immediately',
  'independant': 'independent',
  'inteligent': 'intelligent',
  'interupt': 'interrupt',
  'knowlege': 'knowledge',
  'liason': 'liaison',
  'libary': 'library',
  'lisence': 'licence',
  'maintainance': 'maintenance',
  'maintenence': 'maintenance',
  'managable': 'manageable',
  'millenium': 'millennium',
  'miniscule': 'minuscule',
  'mispell': 'misspell',
  'neccessary': 'necessary',
  'necesary': 'necessary',
  'noticable': 'noticeable',
  'occassion': 'occasion',
  'occurance': 'occurrence',
  'occured': 'occurred',
  'occuring': 'occurring',
  'ocurred': 'occurred',
  'oppurtunity': 'opportunity',
  'paralell': 'parallel',
  'parliment': 'parliament',
  'particulary': 'particularly',
  'perseverence': 'perseverance',
  'persistant': 'persistent',
  'personel': 'personnel',
  'posession': 'possession',
  'possesion': 'possession',
  'prefered': 'preferred',
  'primative': 'primitive',
  'privelege': 'privilege',
  'priviledge': 'privilege',
  'probaly': 'probably',
  'proffesional': 'professional',
  'pronounciation': 'pronunciation',
  'publically': 'publicly',
  'realy': 'really',
  'recieve': 'receive',
  'recieved': 'received',
  'recomend': 'recommend',
  'recommand': 'recommend',
  'refered': 'referred',
  'relevent': 'relevant',
  'religous': 'religious',
  'repitition': 'repetition',
  'restaraunt': 'restaurant',
  'rythm': 'rhythm',
  'seperate': 'separate',
  'seperately': 'separately',
  'sieze': 'seize',
  'similiar': 'similar',
  'sincerly': 'sincerely',
  'speach': 'speech',
  'succesful': 'successful',
  'successfull': 'successful',
  'supercede': 'supersede',
  'supress': 'suppress',
  'suprise': 'surprise',
  'tendancy': 'tendency',
  'therefor': 'therefore',
  'threshhold': 'threshold',
  'tommorow': 'tomorrow',
  'tommorrow': 'tomorrow',
  'tomorow': 'tomorrow',
  'truely': 'truly',
  'twelth': 'twelfth',
  'tyrany': 'tyranny',
  'underrate': 'underrate',
  'untill': 'until',
  'unversity': 'university',
  'usualy': 'usually',
  'vaccum': 'vacuum',
  'vacume': 'vacuum',
  'wierd': 'weird',
  'wich': 'which',
  'writting': 'writing',
  'yeild': 'yield',
  'teh': 'the',
  'adn': 'and',
  'taht': 'that',
  'thier': 'their',
  'thre': 'there',
  'wnat': 'want',
  'hte': 'the',
  'nad': 'and',
  'ot': 'to',
  'si': 'is',
};

const String _alphabet = "abcdefghijklmnopqrstuvwxyz'";

/// English spelling, answered from the bundled word list.
///
/// Deciding whether a word is a word is a set lookup, so it costs nothing to
/// run while somebody types. Working out what they meant instead is a search,
/// so it only runs when the suggestions are opened.
class EnglishSpellEngine implements SpellEngine {
  EnglishSpellEngine({DictionaryService? dictionary})
      : _dictionary = dictionary ?? DictionaryService.instance;

  final DictionaryService _dictionary;

  @override
  String get language => 'en';

  @override
  bool get isReady => _dictionary.isReady;

  @override
  Future<void> prepare() => _dictionary.ensureLoaded();

  @override
  bool accepts(String word) {
    if (!isReady) {
      return true;
    }
    if (word.length < minimumCheckedWordLength || isAcronym(word)) {
      return true;
    }
    final normalized = normalizeWord(word);
    if (_dictionary.contains(normalized)) {
      return true;
    }
    // A possessive or a contraction of a word already known is known.
    final apostrophe = normalized.lastIndexOf("'");
    if (apostrophe > 0) {
      final stem = normalized.substring(0, apostrophe);
      final tail = normalized.substring(apostrophe + 1);
      if (const {'s', 'd', 'll', 're', 've', 'm', 't'}.contains(tail) &&
          _dictionary.contains(stem)) {
        return true;
      }
    }
    return false;
  }

  @override
  List<Suggestion> suggest(String word, {int limit = 5}) {
    if (!isReady) {
      return const [];
    }
    final normalized = normalizeWord(word);
    final candidates = <String, double>{};

    final named = commonEnglishMisspellings[normalized];
    if (named != null) {
      candidates[named] = 1;
    }

    for (final candidate in _knownEdits(_edits(normalized))) {
      candidates.putIfAbsent(candidate, () => 0.8);
    }

    final split = _splitInTwo(normalized);
    if (split != null) {
      candidates.putIfAbsent(split, () => 0.7);
    }

    if (candidates.isEmpty && normalized.length <= 11) {
      for (final near in _edits(normalized)) {
        for (final candidate in _knownEdits(_edits(near))) {
          candidates.putIfAbsent(candidate, () => 0.45);
          if (candidates.length > 60) {
            break;
          }
        }
        if (candidates.length > 60) {
          break;
        }
      }
    }

    candidates.remove(normalized);
    if (candidates.isEmpty) {
      return const [];
    }

    final ranked = candidates.keys.toList()
      ..sort((a, b) => _score(b, normalized, candidates[b]!)
          .compareTo(_score(a, normalized, candidates[a]!)),);

    return [
      for (final candidate in ranked.take(limit))
        Suggestion(
          _matchCase(word, candidate),
          confidence: candidates[candidate]!,
        ),
    ];
  }

  /// Higher is better. Confidence leads, then how common the word is, then
  /// whether it starts the same way — a typo very rarely changes the first
  /// letter.
  double _score(String candidate, String word, double confidence) {
    final rank = _dictionary.rankOf(candidate);
    final commonness = rank == null ? 0.0 : 1 - (rank / 30000);
    final sameStart = candidate.isNotEmpty &&
            word.isNotEmpty &&
            candidate[0] == word[0]
        ? 0.35
        : 0.0;
    final lengthPenalty = (candidate.length - word.length).abs() * 0.03;
    return confidence * 2 + commonness + sameStart - lengthPenalty;
  }

  Iterable<String> _knownEdits(Iterable<String> edits) sync* {
    for (final edit in edits) {
      if (edit.length >= 2 && _dictionary.contains(edit)) {
        yield edit;
      }
    }
  }

  /// Every string one edit away from [word].
  List<String> _edits(String word) {
    final results = <String>[];
    for (var index = 0; index <= word.length; index++) {
      final head = word.substring(0, index);
      final tail = word.substring(index);
      if (tail.isNotEmpty) {
        results.add(head + tail.substring(1));
        if (tail.length > 1) {
          results.add(head + tail[1] + tail[0] + tail.substring(2));
        }
      }
      for (var letter = 0; letter < _alphabet.length; letter++) {
        final char = _alphabet[letter];
        results.add(head + char + tail);
        if (tail.isNotEmpty) {
          results.add(head + char + tail.substring(1));
        }
      }
    }
    return results;
  }

  /// Two words written as one: "alot", "eventhough".
  String? _splitInTwo(String word) {
    for (var index = 2; index < word.length - 1; index++) {
      final left = word.substring(0, index);
      final right = word.substring(index);
      if (right.length >= 2 &&
          _dictionary.contains(left) &&
          _dictionary.contains(right)) {
        return '$left $right';
      }
    }
    return null;
  }

  /// Gives a replacement the shape of the word it replaces.
  static String _matchCase(String original, String candidate) {
    if (original.isEmpty || candidate.isEmpty) {
      return candidate;
    }
    if (original == original.toUpperCase() &&
        original != original.toLowerCase()) {
      return candidate.toUpperCase();
    }
    if (original[0] == original[0].toUpperCase() &&
        original[0] != original[0].toLowerCase()) {
      return candidate[0].toUpperCase() + candidate.substring(1);
    }
    return candidate;
  }
}
