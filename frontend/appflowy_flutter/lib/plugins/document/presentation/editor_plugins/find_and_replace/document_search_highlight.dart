import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// One place the open search found its query.
typedef DocumentSearchMatch = ({Path path, int start, int end});

/// Where the open search found its words in the page being read.
///
/// The editor paints a page one text run at a time and only knows about the
/// caret, so the marks are held here and applied by the style customizer's
/// span decorator. Nodes are keyed by id rather than by path, so a match
/// survives anything that moves a block about.
class DocumentSearchHighlight {
  DocumentSearchHighlight._();

  static final DocumentSearchHighlight instance = DocumentSearchHighlight._();

  Map<String, List<TextRange>> _ranges = const {};
  String? _currentNodeId;
  TextRange? _currentRange;

  bool get isEmpty => _ranges.isEmpty;

  /// Records what was found and repaints only the blocks that changed.
  void update(
    EditorState editorState,
    List<DocumentSearchMatch> matches,
    int selectedIndex,
  ) {
    final next = <String, List<TextRange>>{};
    String? currentNodeId;
    TextRange? currentRange;
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final node = editorState.getNodeAtPath(match.path);
      if (node == null) {
        continue;
      }
      final range = TextRange(start: match.start, end: match.end);
      next.putIfAbsent(node.id, () => <TextRange>[]).add(range);
      if (index == selectedIndex) {
        currentNodeId = node.id;
        currentRange = range;
      }
    }
    _apply(editorState, next, currentNodeId, currentRange);
  }

  void clear(EditorState editorState) =>
      _apply(editorState, const {}, null, null);

  List<TextRange> rangesOf(Node node) => _ranges[node.id] ?? const [];

  TextRange? currentRangeOf(Node node) =>
      _currentNodeId == node.id ? _currentRange : null;

  void _apply(
    EditorState editorState,
    Map<String, List<TextRange>> next,
    String? currentNodeId,
    TextRange? currentRange,
  ) {
    final touched = <String>{
      ..._ranges.keys,
      ...next.keys,
      if (_currentNodeId != null) _currentNodeId!,
      if (currentNodeId != null) currentNodeId,
    };
    final previous = _ranges;
    final previousCurrentNode = _currentNodeId;
    final previousCurrentRange = _currentRange;
    _ranges = next;
    _currentNodeId = currentNodeId;
    _currentRange = currentRange;
    for (final id in touched) {
      final before = previous[id] ?? const <TextRange>[];
      final after = next[id] ?? const <TextRange>[];
      final currentChanged =
          (previousCurrentNode == id) != (currentNodeId == id) ||
              (currentNodeId == id && previousCurrentRange != currentRange);
      if (!currentChanged && _sameRanges(before, after)) {
        continue;
      }
      _nodeWithId(editorState, id)?.notify();
    }
  }

  Node? _nodeWithId(EditorState editorState, String id) {
    Node? search(Node node) {
      if (node.id == id) {
        return node;
      }
      for (final child in node.children) {
        final found = search(child);
        if (found != null) {
          return found;
        }
      }
      return null;
    }

    for (final child in editorState.document.root.children) {
      final found = search(child);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  static bool _sameRanges(List<TextRange> a, List<TextRange> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}

/// Marks the part of one text run that the search matched.
///
/// [start] is where the run begins in the block's own text, which is what the
/// editor hands the decorator.
InlineSpan decorateWithSearchHighlight(
  BuildContext context,
  Node node,
  int start,
  InlineSpan span,
) {
  if (span is! TextSpan) {
    return span;
  }
  final highlight = DocumentSearchHighlight.instance;
  if (highlight.isEmpty) {
    return span;
  }
  final length = span.toPlainText().length;
  if (length == 0) {
    return span;
  }
  final end = start + length;
  final ranges = <TextRange>[];
  for (final range in highlight.rangesOf(node)) {
    if (range.end <= start || range.start >= end) {
      continue;
    }
    ranges.add(
      TextRange(
        start: (range.start < start ? start : range.start) - start,
        end: (range.end > end ? end : range.end) - start,
      ),
    );
  }
  if (ranges.isEmpty) {
    return span;
  }
  final current = highlight.currentRangeOf(node);
  final brightness = Theme.of(context).brightness;
  return applyFindHighlights(
    span,
    ranges: ranges,
    current: current == null
        ? null
        : TextRange(
            start: current.start - start,
            end: current.end - start,
          ),
    matchStyle: TextStyle(
      backgroundColor: FindHighlightColors.match(brightness),
    ),
    currentStyle: TextStyle(
      backgroundColor: FindHighlightColors.current(brightness),
    ),
  );
}
