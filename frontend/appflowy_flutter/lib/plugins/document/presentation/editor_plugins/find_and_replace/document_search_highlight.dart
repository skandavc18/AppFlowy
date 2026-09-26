import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// One place the open search found its query.
typedef DocumentSearchMatch = ({Path path, int start, int end});

/// Where the open search found its words in the page being read.
///
/// Marks are scoped to an editor/session and keyed by Node identity. Paths can
/// move, and two documents may contain the same node id; neither should paint
/// the wrong text. Releasing an old session cannot clear its successor.
class DocumentSearchHighlight extends ChangeNotifier {
  DocumentSearchHighlight._();

  static final DocumentSearchHighlight instance = DocumentSearchHighlight._();

  final Map<EditorState, _DocumentHighlights> _documents = Map.identity();

  bool get isEmpty => _documents.values.every((marks) => marks.ranges.isEmpty);

  /// Records what was found and repaints only the blocks that changed.
  void update(
    EditorState editorState,
    List<DocumentSearchMatch> matches,
    int selectedIndex, {
    Object? owner,
    String titleText = '',
    List<TextRange> titleMatches = const [],
    TextRange? currentTitleMatch,
  }) {
    if (editorState.isDisposed) {
      return;
    }
    final next = <Node, List<TextRange>>{};
    Node? currentNode;
    TextRange? currentRange;
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final node = editorState.getNodeAtPath(match.path);
      final length = node?.delta?.toPlainText().length ?? 0;
      if (node == null ||
          match.start < 0 ||
          match.end <= match.start ||
          match.end > length) {
        continue;
      }
      final range = TextRange(start: match.start, end: match.end);
      next.putIfAbsent(node, () => <TextRange>[]).add(range);
      if (index == selectedIndex) {
        currentNode = node;
        currentRange = range;
      }
    }
    final previous = _documents[editorState];
    _documents[editorState] = _DocumentHighlights(
      owner,
      next,
      currentNode,
      currentRange,
      titleText: titleText,
      titleMatches: titleMatches,
      currentTitleMatch: currentTitleMatch,
    );
    if (previous?.titleText != titleText ||
        !_sameRanges(previous?.titleMatches ?? const [], titleMatches) ||
        previous?.currentTitleMatch != currentTitleMatch) {
      _notifyTitle();
    }
    final touched = <Node>{...?previous?.ranges.keys, ...next.keys};
    _notify(
      editorState,
      touched.where((node) {
        final currentChanged =
            (previous?.currentNode == node) != (currentNode == node) ||
                (currentNode == node && previous?.currentRange != currentRange);
        return currentChanged ||
            !_sameRanges(
              previous?.ranges[node] ?? const [],
              next[node] ?? const [],
            );
      }).toList(),
    );
  }

  /// Remove ownership now; defer only repainting during widget teardown.
  /// A queued callback must never clear the state of a newly opened menu.
  void clear(
    EditorState editorState, {
    Object? owner,
    bool deferNotification = false,
  }) {
    final previous = _documents[editorState];
    if (previous == null ||
        (owner != null && !identical(previous.owner, owner))) {
      return;
    }
    _documents.remove(editorState);
    _notify(
      editorState,
      previous.ranges.keys.toList(),
      defer: deferNotification,
    );
    if (previous.titleMatches.isNotEmpty) {
      _notifyTitle(defer: deferNotification);
    }
  }

  void _notifyTitle({bool defer = false}) {
    if (defer ||
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }
  }

  List<TextRange> rangesOf(Node node) {
    for (final marks in _documents.values) {
      final ranges = marks.ranges[node];
      if (ranges != null) {
        return ranges;
      }
    }
    return const [];
  }

  TextRange? currentRangeOf(Node node) {
    for (final marks in _documents.values) {
      if (identical(marks.currentNode, node)) {
        return marks.currentRange;
      }
    }
    return null;
  }

  void _notify(EditorState editor, Iterable<Node> nodes, {bool defer = false}) {
    void repaint() {
      if (editor.isDisposed) {
        return;
      }
      for (final node in nodes) {
        if (editor.isDisposed) {
          return;
        }
        if (identical(editor.getNodeAtPath(node.path), node)) {
          node.notify();
        }
      }
    }

    if (defer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => repaint());
    } else {
      repaint();
    }
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

class _DocumentHighlights {
  const _DocumentHighlights(
    this.owner,
    this.ranges,
    this.currentNode,
    this.currentRange, {
    this.titleText = '',
    this.titleMatches = const [],
    this.currentTitleMatch,
  });

  final Object? owner;
  final Map<Node, List<TextRange>> ranges;
  final Node? currentNode;
  final TextRange? currentRange;
  final String titleText;
  final List<TextRange> titleMatches;
  final TextRange? currentTitleMatch;
}

/// The title is ViewPB.name/native field text, not a synthetic document node.
TextSpan decorateDocumentTitleWithSearchHighlight(
  BuildContext context,
  EditorState editor,
  String text,
  TextSpan span,
) {
  final marks = DocumentSearchHighlight.instance._documents[editor];
  if (marks == null || marks.titleText != text || marks.titleMatches.isEmpty) {
    return span;
  }
  final brightness = Theme.of(context).brightness;
  return _DocumentSpanHighlighter(
    ranges: marks.titleMatches,
    current: marks.currentTitleMatch,
    matchStyle:
        TextStyle(backgroundColor: FindHighlightColors.match(brightness)),
    currentStyle:
        TextStyle(backgroundColor: FindHighlightColors.current(brightness)),
  ).visit(span) as TextSpan;
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
  final length = span.toPlainText(includeSemanticsLabels: false).length;
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
  return _DocumentSpanHighlighter(
    ranges: ranges,
    current: current == null || current.end <= start || current.start >= end
        ? null
        : TextRange(
            start: (current.start < start ? start : current.start) - start,
            end: (current.end > end ? end : current.end) - start,
          ),
    matchStyle: TextStyle(
      backgroundColor: FindHighlightColors.match(brightness),
    ),
    currentStyle: TextStyle(
      backgroundColor: FindHighlightColors.current(brightness),
    ),
  ).visit(span);
}

/// Unlike a generic span splitter, retain a highlight when the entire run is
/// matched (including each half of a word split by bold/italic attributes).
class _DocumentSpanHighlighter {
  _DocumentSpanHighlighter({
    required this.ranges,
    required this.current,
    required this.matchStyle,
    required this.currentStyle,
  });

  final List<TextRange> ranges;
  final TextRange? current;
  final TextStyle matchStyle;
  final TextStyle currentStyle;
  int offset = 0;

  InlineSpan visit(InlineSpan source) {
    if (source is! TextSpan) {
      offset += source.toPlainText(includeSemanticsLabels: false).length;
      return source;
    }
    final pieces = <InlineSpan>[];
    final text = source.text ?? '';
    final start = offset;
    final end = start + text.length;
    var cursor = start;

    void append(int from, int to, [TextStyle? style]) {
      if (to <= from) {
        return;
      }
      pieces.add(
        TextSpan(
          text: text.substring(from - start, to - start),
          style: style,
          recognizer: source.recognizer,
          mouseCursor: source.mouseCursor,
          onEnter: source.onEnter,
          onExit: source.onExit,
          // The original span still supplies its semantic label once.
          semanticsLabel: source.semanticsLabel == null ? null : '',
        ),
      );
    }

    for (final range in ranges) {
      final from = range.start > cursor ? range.start : cursor;
      final to = range.end < end ? range.end : end;
      if (to <= from) {
        continue;
      }
      append(cursor, from);
      append(from, to, range == current ? currentStyle : matchStyle);
      cursor = to;
    }
    append(cursor, end);
    offset = end;
    for (final child in source.children ?? const <InlineSpan>[]) {
      pieces.add(visit(child));
    }
    return TextSpan(
      text: source.text == null ? null : '',
      style: source.style,
      children: pieces,
      recognizer: source.recognizer,
      mouseCursor: source.mouseCursor,
      onEnter: source.onEnter,
      onExit: source.onExit,
      semanticsLabel: source.semanticsLabel,
      locale: source.locale,
      spellOut: source.spellOut,
    );
  }
}
