import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unchanged code reuses spans across rebuilds and font size changes', () {
    const code = 'final result = cachedCompute(42);';
    final first = _highlight(code, style: const TextStyle(fontSize: 12));
    final second = _highlight(code, style: const TextStyle(fontSize: 24));
    expect(identical(first.children, second.children), isTrue);
    expect(first.style!.fontSize, 12);
    expect(second.style!.fontSize, 24);
    expect(second.toPlainText(), code);
  });

  test('equivalent language aliases share cached highlighting', () {
    const code = 'const aliasResult = aliasCompute(1);';
    final first = _highlight(code, language: 'js');
    final second = _highlight(code, language: ' JavaScript ');
    expect(identical(first.children, second.children), isTrue);
  });

  test('theme, language and source changes never reuse stale spans', () {
    const code = 'final themedResult = themedCompute(42);';
    final dark = _highlight(code);
    final light = _highlight(code, brightness: Brightness.light);
    final paper = _highlight(code, brightness: Brightness.light, isPaper: true);
    final edited = _highlight('$code\n// changed');
    final language = _highlight(code, language: 'python');

    expect(dark.style!.color, isNot(light.style!.color));
    expect(paper.style!.color, isNot(light.style!.color));
    expect(identical(dark.children, light.children), isFalse);
    expect(identical(paper.children, light.children), isFalse);
    expect(identical(dark.children, language.children), isFalse);
    expect(edited.toPlainText(), '$code\n// changed');
    expect(_highlight(code).toPlainText(), code);
    expect(identical(_highlight(code).children, dark.children), isTrue);
  });

  test('cached span collections cannot be mutated by a consumer', () {
    final span = _highlight('final immutableResult = compute(42);');
    expect(() => span.children!.clear(), throwsUnsupportedError);
  });

  test('old entries are evicted instead of retaining every visited block', () {
    const code = 'final evictedResult = compute(42);';
    final first = _highlight(code);
    for (var index = 0; index < 40; index++) {
      _highlight('final eviction$index = compute($index);');
    }
    final reloaded = _highlight(code);
    expect(identical(first.children, reloaded.children), isFalse);
    expect(reloaded.toPlainText(), code);
  });

  test('cache hits refresh recency', () {
    const code = 'final recentResult = compute(42);';
    final first = _highlight(code);
    for (var index = 0; index < 40; index++) {
      _highlight('final recency$index = compute($index);');
      expect(identical(_highlight(code).children, first.children), isTrue);
    }
  });

  test('aggregate source size evicts entries before the count limit', () {
    final code = '// first ${'x' * 100000}';
    final first = _highlight(code);
    _highlight('// second ${'x' * 100000}');
    _highlight('// third ${'x' * 100000}');
    expect(identical(_highlight(code).children, first.children), isFalse);
  });

  test('invalid language and auto share the same fallback result', () {
    const code = 'const fallbackResult = compute(42);';
    final first = _highlight(code, language: 'not-a-real-grammar');
    final second = _highlight(code, language: 'auto');
    expect(identical(first.children, second.children), isTrue);
    expect(second.toPlainText(), code);
  });

  test('oversized code is rendered intact without displacing small entries',
      () {
    const code = 'final smallResult = compute(42);';
    final small = _highlight(code);
    final large = '// ${'x' * (256 * 1024)}';
    final first = _highlight(large);
    final second = _highlight(large);
    expect(first.toPlainText(), large);
    expect(second.toPlainText(), large);
    expect(identical(first.children, second.children), isFalse);
    expect(identical(_highlight(code).children, small.children), isTrue);
  });
}

TextSpan _highlight(
  String code, {
  String language = 'dart',
  Brightness brightness = Brightness.dark,
  bool isPaper = false,
  TextStyle? style,
}) =>
    buildSyntaxHighlightedTextSpan(
      code: code,
      language: language,
      brightness: brightness,
      isPaper: isPaper,
      style: style,
    );
