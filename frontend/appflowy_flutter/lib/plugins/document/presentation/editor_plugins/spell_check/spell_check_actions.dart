import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/document_spell_check.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_page_settings.dart';
import 'package:appflowy/shared/spell_check/spell_check.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// Everything a person can do about a mistake, in one place, so the popup and
/// the right click menu cannot drift apart.
class SpellCheckActions {
  const SpellCheckActions({
    required this.editorState,
    required this.controller,
    required this.node,
    required this.issue,
  });

  final EditorState editorState;
  final DocumentSpellCheckController controller;
  final Node node;
  final SpellCheckResult issue;

  String get viewId => controller.viewId;

  /// Whether the flagged words are still where they were found.
  ///
  /// A correction chosen a moment after the text moved must not overwrite
  /// something else.
  bool get isStillThere {
    final delta = node.delta;
    if (delta == null) {
      return false;
    }
    final text = delta.toPlainText();
    if (issue.end > text.length) {
      return false;
    }
    return text.substring(issue.start, issue.end) == issue.text;
  }

  /// Puts [replacement] in place of the flagged words.
  ///
  /// It goes through the editor's own transaction, so the formatting around it
  /// survives, the caret lands after the new words and Ctrl+Z undoes it.
  Future<void> replaceWith(String replacement) async {
    if (!editorState.editable || !isStillThere) {
      return;
    }
    final transaction = editorState.transaction
      ..replaceText(node, issue.start, issue.length, replacement);
    await editorState.apply(transaction);
    controller.recheck(node);
  }

  /// Leaves this one place alone.
  void ignoreOnce() {
    IgnoreRules.instance.ignoreOccurrence(issue, node.id);
    controller.recheck(node);
  }

  /// Leaves these words alone everywhere until AppFlowy is closed.
  void ignoreEverywhere() => IgnoreRules.instance.ignoreEverywhere(issue);

  bool get isIgnoredEverywhere =>
      IgnoreRules.instance.ignoresEverywhere(issue.text);

  /// Leaves these words alone on this page, and remembers it with the page.
  Future<void> ignoreOnThisPage() =>
      SpellCheckPageSettings.instance.ignoreWordOnPage(viewId, issue.text);

  bool get isIgnoredOnThisPage =>
      SpellCheckPageSettings.instance.isIgnoredOnPage(viewId, issue.text);

  /// Adds the word to this person's own dictionary, everywhere and for good.
  Future<void> addToDictionary() =>
      DictionaryService.instance.addWord(issue.text);

  bool get canAddToDictionary =>
      issue.kind.isSpelling &&
      !DictionaryService.instance.isUserWord(issue.text);

  /// The replacements to offer.
  ///
  /// A grammar note brings its own; a spelling works them out here, which is
  /// the first time the expensive search is run.
  List<Suggestion> suggestions({int limit = 5}) => issue.suggestions.isNotEmpty
      ? issue.suggestions
      : SpellCheckService.instance.suggestionsFor(issue.text, limit: limit);
}

/// Finds the mistake under a caret, ready to be acted on.
SpellCheckActions? spellCheckActionsAt(
  EditorState editorState,
  Position position,
) {
  final controller = DocumentSpellCheck.of(editorState);
  if (controller == null || !controller.isEnabled) {
    return null;
  }
  final node = editorState.getNodeAtPath(position.path);
  if (node == null) {
    return null;
  }
  final issue = controller.issueAt(node, position.offset);
  if (issue == null) {
    return null;
  }
  return SpellCheckActions(
    editorState: editorState,
    controller: controller,
    node: node,
    issue: issue,
  );
}
