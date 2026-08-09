import 'dart:convert';
import 'dart:io' show gzip;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the bundled English word lists live.
const String englishWordListAsset = 'assets/dictionaries/en_us_words.txt.gz';
const String englishCommonWordsAsset = 'assets/dictionaries/en_us_common.txt.gz';

/// The words AppFlowy accepts: the bundled language, plus everything the
/// person writing has added.
///
/// The bundled list is read once, off the interface thread, and then only ever
/// asked yes or no questions. The words somebody adds are kept beside it and
/// persist between sessions.
class DictionaryService extends ChangeNotifier {
  DictionaryService._();

  static final DictionaryService instance = DictionaryService._();

  static const userDictionaryStorageKey = 'appflowy_spell_check_dictionary';

  Set<String> _words = const {};
  Map<String, int> _ranks = const {};
  Set<String> _userWords = <String>{};
  Future<void>? _loading;
  bool _isReady = false;

  /// Whether the bundled list has been read.
  bool get isReady => _isReady;

  /// The words this person added, in the order they read best.
  List<String> get userWords => _userWords.toList()..sort();

  int get bundledWordCount => _words.length;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    await _readUserWords();
    try {
      final words = await rootBundle.load(englishWordListAsset);
      final common = await rootBundle.load(englishCommonWordsAsset);
      final decoded = await compute(
        _decodeWordLists,
        _WordListBytes(
          words.buffer.asUint8List(
            words.offsetInBytes,
            words.lengthInBytes,
          ),
          common.buffer.asUint8List(
            common.offsetInBytes,
            common.lengthInBytes,
          ),
        ),
      );
      _words = decoded.words;
      _ranks = decoded.ranks;
      _isReady = true;
      notifyListeners();
    } on Object catch (error) {
      // A missing word list must not break writing; it only means nothing is
      // ever flagged.
      Log.warn('The English dictionary could not be read: $error');
    }
  }

  /// Whether [word] is a word, already lowercased by the caller.
  bool contains(String word) =>
      _words.contains(word) || _userWords.contains(word);

  /// How common [word] is, lower being more common; `null` when it is not in
  /// the ranked list at all.
  int? rankOf(String word) => _ranks[word];

  bool isUserWord(String word) => _userWords.contains(word.toLowerCase());

  Future<void> addWord(String word) async {
    final normalized = word.trim().toLowerCase();
    if (normalized.isEmpty || !_userWords.add(normalized)) {
      return;
    }
    notifyListeners();
    await _writeUserWords();
  }

  Future<void> removeWord(String word) async {
    if (!_userWords.remove(word.trim().toLowerCase())) {
      return;
    }
    notifyListeners();
    await _writeUserWords();
  }

  Future<void> _readUserWords() async {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      final stored = await getIt<KeyValueStorage>().get(
        userDictionaryStorageKey,
      );
      if (stored == null || stored.isEmpty) {
        return;
      }
      final decoded = jsonDecode(stored);
      if (decoded is List) {
        _userWords = decoded
            .whereType<String>()
            .map((word) => word.toLowerCase())
            .toSet();
      }
    } on Object catch (error) {
      Log.warn('The personal dictionary could not be read: $error');
    }
  }

  Future<void> _writeUserWords() async {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      await getIt<KeyValueStorage>().set(
        userDictionaryStorageKey,
        jsonEncode(_userWords.toList()..sort()),
      );
    } on Object catch (error) {
      Log.warn('The personal dictionary could not be stored: $error');
    }
  }

  /// Replaces the bundled list. Only used by tests, which have no assets.
  @visibleForTesting
  void seedForTest({
    required Set<String> words,
    Map<String, int> ranks = const {},
    Set<String> userWords = const {},
  }) {
    _words = words;
    _ranks = ranks;
    _userWords = {...userWords};
    _isReady = true;
    _loading = Future<void>.value();
    notifyListeners();
  }
}

@immutable
class _WordListBytes {
  const _WordListBytes(this.words, this.common);

  final Uint8List words;
  final Uint8List common;
}

class _WordLists {
  const _WordLists(this.words, this.ranks);

  final Set<String> words;
  final Map<String, int> ranks;
}

/// Runs in a background isolate: a hundred thousand strings is not something
/// to build while somebody is typing.
_WordLists _decodeWordLists(_WordListBytes bytes) {
  final words = const LineSplitter()
      .convert(utf8.decode(gzip.decode(bytes.words)))
      .where((word) => word.isNotEmpty)
      .toSet();
  final ranks = <String, int>{};
  final common = const LineSplitter().convert(
    utf8.decode(gzip.decode(bytes.common)),
  );
  for (var index = 0; index < common.length; index++) {
    final word = common[index];
    if (word.isNotEmpty) {
      ranks.putIfAbsent(word, () => index);
    }
  }
  return _WordLists(words, ranks);
}
