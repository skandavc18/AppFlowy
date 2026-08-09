import 'package:appflowy/shared/spell_check/spell_check_result.dart';
import 'package:flutter/foundation.dart';

/// The things somebody has said they do not want flagged again.
///
/// Only what lives for the session belongs here. A word ignored for one page
/// is remembered with that page, and a word added to the dictionary belongs to
/// the dictionary — neither is kept in this list.
class IgnoreRules extends ChangeNotifier {
  IgnoreRules._();

  static final IgnoreRules instance = IgnoreRules._();

  final List<IgnoreRule> _rules = [];

  List<IgnoreRule> get rules => List.unmodifiable(_rules);

  /// Stops flagging exactly the one place this was found.
  void ignoreOccurrence(SpellCheckResult issue, String blockId) => _add(
        IgnoreRule(
          text: issue.text,
          scope: IgnoreScope.occurrence,
          blockId: blockId,
          offset: issue.start,
          ruleId: issue.ruleId,
        ),
      );

  /// Stops flagging these words anywhere until AppFlowy is closed.
  void ignoreEverywhere(SpellCheckResult issue) => _add(
        IgnoreRule(
          text: issue.text,
          scope: IgnoreScope.session,
          ruleId: issue.ruleId,
        ),
      );

  bool covers(SpellCheckResult issue, String blockId) =>
      _rules.any((rule) => rule.covers(issue, blockId));

  /// Whether these exact words are already ignored everywhere, which is what
  /// decides whether the menu still offers to.
  bool ignoresEverywhere(String text) => _rules.any(
        (rule) =>
            rule.scope == IgnoreScope.session &&
            rule.text.toLowerCase() == text.toLowerCase(),
      );

  void clear() {
    if (_rules.isEmpty) {
      return;
    }
    _rules.clear();
    notifyListeners();
  }

  void _add(IgnoreRule rule) {
    if (_rules.contains(rule)) {
      return;
    }
    _rules.add(rule);
    notifyListeners();
  }
}
