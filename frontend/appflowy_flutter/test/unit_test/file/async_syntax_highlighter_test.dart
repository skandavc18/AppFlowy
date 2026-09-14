import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brightness in Brightness.values) {
    for (final paper in [false, true]) {
      test('worker output matches synchronous styling: $brightness/$paper',
          () async {
        const code = '// worker parity\nconst value = compute("hello", 42);';
        const style = TextStyle(fontSize: 18, fontFamily: 'RobotoMono');
        final span = await loadSyntaxHighlightedTextSpan(
          code: code,
          language: 'javascript',
          brightness: brightness,
          isPaper: paper,
          style: style,
        );
        final expected = buildSyntaxHighlightedTextSpan(
          code: code,
          language: 'javascript',
          brightness: brightness,
          isPaper: paper,
          style: style,
        );
        expect(span, expected);
        expect(span!.toPlainText(), code);
        expect(span.style!.fontSize, 18);
      });
    }
  }

  test('cancelled queued work never populates the cache', () async {
    const code = 'const cancelledHighlight = "never parsed";';
    final result = await loadSyntaxHighlightedTextSpan(
      code: code,
      language: 'auto',
      brightness: Brightness.light,
      isCancelled: () => true,
    );
    expect(result, isNull);
    expect(
      cachedSyntaxHighlightedTextSpan(
        code: code,
        language: 'auto',
        brightness: Brightness.light,
      ),
      isNull,
    );
  });

  test('large uncached parsing yields to the main event loop', () async {
    final code = List.generate(
      160,
      (i) => 'final asynchronousValue$i = calculate($i);',
    ).join('\n');
    var eventHandled = false;
    Timer.run(() => eventHandled = true);
    final span = await loadSyntaxHighlightedTextSpan(
      code: code,
      language: 'auto',
      brightness: Brightness.dark,
    );
    expect(eventHandled, isTrue);
    expect(span!.toPlainText(), code);
  });
}
