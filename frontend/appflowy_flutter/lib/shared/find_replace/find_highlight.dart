import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';

/// The two colours every search in the application marks with: yellow for
/// each occurrence, orange for the one being read.
///
/// They are deliberately the same everywhere — a page, a source file, a
/// rendered preview and a PDF all answer to the same reading.
abstract final class FindHighlightColors {
  static const _lightMatch = Color(0x8CFFD54F);
  static const _lightCurrent = Color(0xCCFF9A3D);
  static const _darkMatch = Color(0x73FFD54F);
  static const _darkCurrent = Color(0xC2FF8F2E);

  static Color match(Brightness brightness) =>
      brightness == Brightness.dark ? _darkMatch : _lightMatch;

  static Color current(Brightness brightness) =>
      brightness == Brightness.dark ? _darkCurrent : _lightCurrent;
}

/// Paints a background behind the character ranges a search found, without
/// disturbing the styling already on the text.
///
/// The span tree is rebuilt rather than replaced, so syntax highlighting keeps
/// its colours and `toPlainText()` still returns the original string — which
/// matters because an editable surface uses that span to place its caret.
TextSpan applyFindHighlights(
  TextSpan source, {
  required List<TextRange> ranges,
  required TextStyle matchStyle,
  TextRange? current,
  TextStyle? currentStyle,
}) {
  if (ranges.isEmpty) {
    return source;
  }
  return _FindHighlighter(
    ranges: ranges,
    matchStyle: matchStyle,
    current: current,
    currentStyle: currentStyle ?? matchStyle,
  ).visit(source);
}

class _FindHighlighter {
  _FindHighlighter({
    required this.ranges,
    required this.matchStyle,
    required this.current,
    required this.currentStyle,
  });

  final List<TextRange> ranges;
  final TextStyle matchStyle;
  final TextRange? current;
  final TextStyle currentStyle;

  int offset = 0;
  int cursor = 0;

  TextSpan visit(TextSpan span) {
    final text = span.text;
    final pieces = <InlineSpan>[];
    if (text != null && text.isNotEmpty) {
      pieces.addAll(_split(text));
    }
    final children = span.children;
    final rebuiltChildren = <InlineSpan>[];
    if (children != null) {
      for (final child in children) {
        if (child is TextSpan) {
          rebuiltChildren.add(visit(child));
        } else {
          rebuiltChildren.add(child);
          offset += child.toPlainText().length;
        }
      }
    }
    if (pieces.length <= 1 && rebuiltChildren.isEmpty) {
      return span;
    }
    if (pieces.length <= 1) {
      return TextSpan(
        text: text,
        style: span.style,
        recognizer: span.recognizer,
        children: rebuiltChildren,
      );
    }
    // A span cannot carry both a split text and its own children, so the text
    // moves into the front of the child list.
    return TextSpan(
      style: span.style,
      recognizer: span.recognizer,
      children: [...pieces, ...rebuiltChildren],
    );
  }

  List<InlineSpan> _split(String text) {
    final start = offset;
    final end = offset + text.length;
    offset = end;
    // Ranges are in order, so the scan never walks back over what it passed.
    while (cursor < ranges.length && ranges[cursor].end <= start) {
      cursor++;
    }
    if (cursor >= ranges.length || ranges[cursor].start >= end) {
      return [TextSpan(text: text)];
    }
    final pieces = <InlineSpan>[];
    var position = start;
    for (var index = cursor; index < ranges.length; index++) {
      final range = ranges[index];
      if (range.start >= end) {
        break;
      }
      final from = range.start > position ? range.start : position;
      final to = range.end < end ? range.end : end;
      if (to <= from) {
        continue;
      }
      if (from > position) {
        pieces.add(
          TextSpan(text: text.substring(position - start, from - start)),
        );
      }
      pieces.add(
        TextSpan(
          text: text.substring(from - start, to - start),
          style: _isCurrent(range) ? currentStyle : matchStyle,
        ),
      );
      position = to;
    }
    if (position < end) {
      pieces.add(TextSpan(text: text.substring(position - start)));
    }
    return pieces;
  }

  bool _isCurrent(TextRange range) =>
      current != null &&
      current!.start == range.start &&
      current!.end == range.end;
}
