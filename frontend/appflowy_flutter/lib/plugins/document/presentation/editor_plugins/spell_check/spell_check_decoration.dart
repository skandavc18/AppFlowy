import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/document_spell_check.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_palette.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/spell_check/spell_check.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Draws the wavy underline under what the checker found.
///
/// The document is never written to: the marks live beside it and are applied
/// to the span the editor is about to paint, exactly as the search highlight
/// is. [start] is where this run begins in the block's own text.
InlineSpan decorateWithSpellCheck(
  BuildContext context,
  EditorState? editorState,
  Node node,
  int start,
  InlineSpan span,
) {
  if (span is! TextSpan) {
    return span;
  }
  final controller = DocumentSpellCheck.of(editorState);
  if (controller == null || !controller.isEnabled) {
    return span;
  }
  final issues = controller.issuesOf(node);
  if (issues.isEmpty) {
    return span;
  }
  final length = span.toPlainText().length;
  if (length == 0) {
    return span;
  }
  final end = start + length;

  final spelling = <TextRange>[];
  final grammar = <TextRange>[];
  for (final issue in issues) {
    if (!issue.overlaps(start, end)) {
      continue;
    }
    final range = TextRange(
      start: (issue.start < start ? start : issue.start) - start,
      end: (issue.end > end ? end : issue.end) - start,
    );
    (issue.kind.isSpelling ? spelling : grammar).add(range);
  }
  if (spelling.isEmpty && grammar.isEmpty) {
    return span;
  }

  final palette = SpellCheckPalette.of(context);
  var decorated = span;
  if (spelling.isNotEmpty) {
    decorated = applyFindHighlights(
      decorated,
      ranges: spelling,
      matchStyle: palette.styleFor(SpellIssueKind.spelling),
    );
  }
  if (grammar.isNotEmpty) {
    decorated = applyFindHighlights(
      decorated,
      ranges: grammar,
      matchStyle: palette.styleFor(SpellIssueKind.grammar),
    );
  }
  return decorated;
}
