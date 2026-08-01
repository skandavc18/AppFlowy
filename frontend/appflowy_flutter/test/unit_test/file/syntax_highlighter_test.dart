import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colour every theme reserves for a function name.
const _darkFunction = Color(0xFFDCDCAA);
const _lightFunction = Color(0xFF8250DF);
const _lightKeyword = Color(0xFFCF222E);

Map<String, Set<Color?>> _colorsByToken(
  String code,
  String language, {
  Brightness brightness = Brightness.dark,
}) {
  final span = buildSyntaxHighlightedTextSpan(
    code: code,
    language: language,
    brightness: brightness,
  );
  final colors = <String, Set<Color?>>{};
  void walk(InlineSpan span, Color? inherited) {
    if (span is! TextSpan) {
      return;
    }
    final color = span.style?.color ?? inherited;
    final text = span.text;
    if (text != null && text.isNotEmpty) {
      colors.putIfAbsent(text, () => <Color?>{}).add(color);
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, color);
    }
  }

  walk(span, null);
  return colors;
}

void main() {
  group('syntax highlighting of functions', () {
    test('colours a call site the grammar leaves unclassified', () {
      final colors = _colorsByToken(
        'void main() {\n  final x = compute(1, 2);\n  x.render();\n}',
        'dart',
      );

      expect(colors['main'], {_darkFunction});
      expect(colors['compute'], {_darkFunction});
      expect(colors['render'], {_darkFunction});
    });

    test('colours calls in every supported language', () {
      expect(
        _colorsByToken('x = helper(a) + b', 'python')['helper'],
        {_darkFunction},
      );
      expect(
        _colorsByToken('obj.render(1);', 'javascript')['render'],
        {_darkFunction},
      );
      expect(
        _colorsByToken('let x = compute(1);', 'rust')['compute'],
        {_darkFunction},
      );
      expect(
        _colorsByToken('int y = sum(a, b);', 'cpp')['sum'],
        {_darkFunction},
      );
      expect(
        _colorsByToken('y := sum(a)', 'go')['sum'],
        {_darkFunction},
      );
    });

    test('colours a call nested in a parameter list', () {
      final colors =
          _colorsByToken('def run(a=fallback(1)):\n    pass', 'python');

      expect(colors['fallback'], {_darkFunction});
    });

    test('leaves control flow as a keyword', () {
      final colors = _colorsByToken(
        'if (ready) {\n  while (busy) {}\n}',
        'javascript',
      );

      expect(colors['if'], isNot(contains(_darkFunction)));
      expect(colors['while'], isNot(contains(_darkFunction)));
    });

    test('leaves text inside strings and comments alone', () {
      final colors = _colorsByToken(
        '// call compute(1) later\nvar s = "compute(2)";',
        'javascript',
      );

      expect(colors.keys.where((key) => key == 'compute'), isEmpty);
    });

    test('separates functions from keywords in the light theme', () {
      final colors = _colorsByToken(
        'const x = compute(1);',
        'javascript',
        brightness: Brightness.light,
      );

      expect(colors['compute'], {_lightFunction});
      expect(colors['const'], {_lightKeyword});
    });

    test('keeps the text intact so the editor can still place a caret', () {
      const samples = {
        'dart': 'void main() {\n  final x = compute(1, 2);\n  x.render();\n}',
        'python': 'def run(a=fallback(1)):\n    return helper(a)\n',
        'rust': 'fn main() {\n    println!("{}", compute(1));\n}',
        'javascript': 'const f = (a) => obj.render(a); // call render(0)\n',
      };

      for (final sample in samples.entries) {
        expect(
          buildSyntaxHighlightedTextSpan(
            code: sample.value,
            language: sample.key,
            brightness: Brightness.dark,
          ).toPlainText(),
          sample.value,
          reason: sample.key,
        );
      }
    });
  });
}
