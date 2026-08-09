import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/document_spell_check.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_actions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_popup.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// How far the pointer may travel and still count as a click rather than a
/// drag that selected some words.
const double _clickSlop = 3;

/// Opens the suggestions when somebody clicks a word that has been flagged.
///
/// The pointer is watched rather than the caret, so a click never has to wait
/// for the editor to move the selection first, and the page's own gestures are
/// untouched — this only ever reads.
class SpellCheckGestureRegion extends StatefulWidget {
  const SpellCheckGestureRegion({
    super.key,
    required this.editorState,
    required this.child,
    this.enabled = true,
  });

  final EditorState editorState;
  final Widget child;
  final bool enabled;

  @override
  State<SpellCheckGestureRegion> createState() =>
      _SpellCheckGestureRegionState();
}

class _SpellCheckGestureRegionState extends State<SpellCheckGestureRegion> {
  Offset? _pressedAt;

  @override
  void dispose() {
    dismissSpellSuggestions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _pressedAt = event.buttons & kPrimaryMouseButton != 0
            ? event.position
            : null;
        if (isSpellSuggestionOpen) {
          dismissSpellSuggestions();
          _pressedAt = null;
        }
      },
      onPointerUp: (event) {
        final pressedAt = _pressedAt;
        _pressedAt = null;
        if (!widget.enabled ||
            pressedAt == null ||
            (event.position - pressedAt).distance > _clickSlop) {
          return;
        }
        _open(event.position);
      },
      child: widget.child,
    );
  }

  void _open(Offset globalPosition) {
    final editorState = widget.editorState;
    final controller = DocumentSpellCheck.of(editorState);
    if (controller == null || !controller.isEnabled || !editorState.editable) {
      return;
    }
    final position = editorState.service.selectionService.getPositionInOffset(
      globalPosition,
    );
    if (position == null) {
      return;
    }
    final actions = spellCheckActionsAt(editorState, position);
    if (actions == null) {
      return;
    }
    // Only a click on the underline itself opens the sheet; landing next to a
    // word is somebody placing the caret.
    final rect = spellIssueRect(actions.node, actions.issue);
    if (rect == null || !rect.inflate(2).contains(globalPosition)) {
      return;
    }
    showSpellSuggestions(context, actions: actions, anchor: rect);
  }
}

/// Opens the suggestions for whatever the caret is inside, so a correction can
/// be reached without the pointer.
KeyEventResult showSpellSuggestionsForCaret(
  BuildContext context,
  EditorState editorState,
) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  final actions = spellCheckActionsAt(editorState, selection.end);
  if (actions == null) {
    return KeyEventResult.ignored;
  }
  final rect = spellIssueRect(actions.node, actions.issue);
  if (rect == null) {
    return KeyEventResult.ignored;
  }
  showSpellSuggestions(context, actions: actions, anchor: rect);
  return KeyEventResult.handled;
}
