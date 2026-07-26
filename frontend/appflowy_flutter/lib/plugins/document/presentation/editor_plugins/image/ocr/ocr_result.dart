import 'dart:ui';

import 'package:flutter/foundation.dart';

/// One recognised word and where it sits on the picture.
@immutable
class OcrWord {
  const OcrWord({
    required this.text,
    required this.bounds,
    this.confidence = 1,
  });

  final String text;

  /// Normalized to the picture: 0..1 on both axes.
  final Rect bounds;
  final double confidence;
}

/// A run of words the engine considers one line.
@immutable
class OcrLine {
  const OcrLine({
    required this.text,
    required this.bounds,
    required this.words,
  });

  factory OcrLine.fromWords(List<OcrWord> words, {String? text}) {
    final bounds = words.isEmpty
        ? Rect.zero
        : words.map((word) => word.bounds).reduce(
              (a, b) => a.expandToInclude(b),
            );
    return OcrLine(
      text: text ?? words.map((word) => word.text).join(' '),
      bounds: bounds,
      words: words,
    );
  }

  final String text;

  /// Normalized to the picture: 0..1 on both axes.
  final Rect bounds;
  final List<OcrWord> words;
}

@immutable
class OcrResult {
  const OcrResult({required this.lines, required this.engine});

  static const empty = OcrResult(lines: [], engine: '');

  final List<OcrLine> lines;

  /// Which engine produced this, shown in the overlay's status line.
  final String engine;

  bool get isEmpty => lines.isEmpty;

  String get text => lines.map((line) => line.text).join('\n');

  String textOf(Iterable<int> indices) {
    final ordered = indices.toList()..sort();
    return ordered
        .where((index) => index >= 0 && index < lines.length)
        .map((index) => lines[index].text)
        .join('\n');
  }
}

/// Raised when no engine on this machine can read the picture.
class OcrUnavailableException implements Exception {
  const OcrUnavailableException(this.message, {this.hint});

  final String message;

  /// A concrete next step, e.g. which tool to install.
  final String? hint;

  @override
  String toString() => hint == null ? message : '$message\n$hint';
}
