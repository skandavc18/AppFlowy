import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// What the application has been told about checking writing.
///
/// This is the default every new page starts from; a page can then say
/// otherwise for itself.
class SpellCheckSettings extends ChangeNotifier {
  SpellCheckSettings._();

  static final SpellCheckSettings instance = SpellCheckSettings._();

  static const spellingStorageKey = 'appflowy_spell_check_enabled';
  static const grammarStorageKey = 'appflowy_grammar_check_enabled';

  bool _spellingEnabled = true;
  bool _grammarEnabled = true;
  Future<void>? _loading;

  bool get spellingEnabled => _spellingEnabled;

  bool get grammarEnabled => _grammarEnabled;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      final storage = getIt<KeyValueStorage>();
      final spelling = await storage.get(spellingStorageKey);
      final grammar = await storage.get(grammarStorageKey);
      _spellingEnabled = spelling != 'false';
      _grammarEnabled = grammar != 'false';
      notifyListeners();
    } on Object catch (error) {
      Log.warn('The spell check settings could not be read: $error');
    }
  }

  Future<void> setSpellingEnabled(bool value) =>
      _set(spellingStorageKey, value, (v) => _spellingEnabled = v);

  Future<void> setGrammarEnabled(bool value) =>
      _set(grammarStorageKey, value, (v) => _grammarEnabled = v);

  Future<void> _set(
    String key,
    bool value,
    void Function(bool) apply,
  ) async {
    apply(value);
    notifyListeners();
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      await getIt<KeyValueStorage>().set(key, value.toString());
    } on Object catch (error) {
      Log.warn('The spell check settings could not be stored: $error');
    }
  }

  @visibleForTesting
  void seedForTest({bool spelling = true, bool grammar = true}) {
    _spellingEnabled = spelling;
    _grammarEnabled = grammar;
    _loading = Future<void>.value();
  }
}
