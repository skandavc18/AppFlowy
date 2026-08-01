import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' as highlight;
import 'package:highlight/languages/all.dart';

const _autoDetectionLanguages = [
  'javascript',
  'typescript',
  'python',
  'cpp',
  'java',
  'kotlin',
  'rust',
  'dart',
  'go',
  'json',
  'xml',
  'css',
  'shell',
  'sql',
  'yaml',
  'markdown',
];

final _autoHighlighter = highlight.Highlight()
  ..registerLanguages({
    for (final language in _autoDetectionLanguages)
      language: allLanguages[language]!,
  });

const _darkPlusSyntaxTheme = <String, TextStyle>{
  'root': TextStyle(color: Color(0xFFD4D4D4)),
  'comment': TextStyle(color: Color(0xFF6A9955), fontStyle: FontStyle.italic),
  'quote': TextStyle(color: Color(0xFF6A9955)),
  'keyword': TextStyle(color: Color(0xFFC586C0)),
  'selector-tag': TextStyle(color: Color(0xFFD7BA7D)),
  'type': TextStyle(color: Color(0xFF4EC9B0)),
  'built_in': TextStyle(color: Color(0xFF4EC9B0)),
  'literal': TextStyle(color: Color(0xFF569CD6)),
  'number': TextStyle(color: Color(0xFFB5CEA8)),
  'string': TextStyle(color: Color(0xFFCE9178)),
  'regexp': TextStyle(color: Color(0xFFD16969)),
  'subst': TextStyle(color: Color(0xFFD4D4D4)),
  'symbol': TextStyle(color: Color(0xFFB5CEA8)),
  'class': TextStyle(color: Color(0xFF4EC9B0)),
  'function': TextStyle(color: Color(0xFFDCDCAA)),
  'title': TextStyle(color: Color(0xFFDCDCAA)),
  'section': TextStyle(color: Color(0xFFDCDCAA)),
  'params': TextStyle(color: Color(0xFF9CDCFE)),
  'variable': TextStyle(color: Color(0xFF9CDCFE)),
  'template-variable': TextStyle(color: Color(0xFF9CDCFE)),
  'attr': TextStyle(color: Color(0xFF9CDCFE)),
  'attribute': TextStyle(color: Color(0xFF9CDCFE)),
  'name': TextStyle(color: Color(0xFF569CD6)),
  'tag': TextStyle(color: Color(0xFF569CD6)),
  'meta': TextStyle(color: Color(0xFFC586C0)),
  'meta-string': TextStyle(color: Color(0xFFCE9178)),
  'addition': TextStyle(color: Color(0xFFB5CEA8)),
  'deletion': TextStyle(color: Color(0xFFCE9178)),
  'bullet': TextStyle(color: Color(0xFFD7BA7D)),
  'link': TextStyle(color: Color(0xFF4FC1FF)),
  'doctag': TextStyle(color: Color(0xFF608B4E)),
};

const _lightSyntaxTheme = <String, TextStyle>{
  'root': TextStyle(color: Color(0xFF24292F)),
  'comment': TextStyle(color: Color(0xFF6E7781), fontStyle: FontStyle.italic),
  'quote': TextStyle(color: Color(0xFF6E7781)),
  'keyword': TextStyle(color: Color(0xFFCF222E)),
  'selector-tag': TextStyle(color: Color(0xFF953800)),
  'type': TextStyle(color: Color(0xFF116329)),
  'built_in': TextStyle(color: Color(0xFF116329)),
  'literal': TextStyle(color: Color(0xFF0550AE)),
  'number': TextStyle(color: Color(0xFF0550AE)),
  'string': TextStyle(color: Color(0xFF0A3069)),
  'regexp': TextStyle(color: Color(0xFFCF222E)),
  'subst': TextStyle(color: Color(0xFF24292F)),
  'symbol': TextStyle(color: Color(0xFF0550AE)),
  'class': TextStyle(color: Color(0xFF116329)),
  'function': TextStyle(color: Color(0xFF8250DF)),
  'title': TextStyle(color: Color(0xFF8250DF)),
  'section': TextStyle(color: Color(0xFF8250DF)),
  'params': TextStyle(color: Color(0xFF953800)),
  'variable': TextStyle(color: Color(0xFF953800)),
  'template-variable': TextStyle(color: Color(0xFF953800)),
  'attr': TextStyle(color: Color(0xFF0550AE)),
  'attribute': TextStyle(color: Color(0xFF0550AE)),
  'name': TextStyle(color: Color(0xFF116329)),
  'tag': TextStyle(color: Color(0xFF116329)),
  'meta': TextStyle(color: Color(0xFF0550AE)),
  'meta-string': TextStyle(color: Color(0xFF0A3069)),
  'addition': TextStyle(color: Color(0xFF1A7F37)),
  'deletion': TextStyle(color: Color(0xFFCF222E)),
  'bullet': TextStyle(color: Color(0xFF953800)),
  'link': TextStyle(color: Color(0xFF0969DA)),
  'doctag': TextStyle(color: Color(0xFF57606A)),
};

final _paperSyntaxTheme = <String, TextStyle>{
  ..._lightSyntaxTheme,
  'root': TextStyle(color: Color(0xFF302D28)),
  'comment': TextStyle(color: Color(0xFF70695E), fontStyle: FontStyle.italic),
  'quote': TextStyle(color: Color(0xFF70695E), fontStyle: FontStyle.italic),
  'keyword': TextStyle(color: Color(0xFF8F4A73)),
  'selector-tag': TextStyle(color: Color(0xFF8A5935)),
  'type': TextStyle(color: Color(0xFF3F6F63)),
  'built_in': TextStyle(color: Color(0xFF3F6F63)),
  'literal': TextStyle(color: Color(0xFF3E638C)),
  'number': TextStyle(color: Color(0xFF7B5A37)),
  'string': TextStyle(color: Color(0xFF5D6D40)),
  'regexp': TextStyle(color: Color(0xFF9B4D48)),
  'function': TextStyle(color: Color(0xFF345A8A)),
  'title': TextStyle(color: Color(0xFF345A8A)),
  'section': TextStyle(color: Color(0xFF345A8A)),
  'params': TextStyle(color: Color(0xFF7A5538)),
  'variable': TextStyle(color: Color(0xFF7A5538)),
  'template-variable': TextStyle(color: Color(0xFF7A5538)),
  'attr': TextStyle(color: Color(0xFF3E638C)),
  'attribute': TextStyle(color: Color(0xFF3E638C)),
  'name': TextStyle(color: Color(0xFF3F6F63)),
  'tag': TextStyle(color: Color(0xFF3F6F63)),
};

String normalizeCodeLanguage(String language) {
  final normalized = language.trim().toLowerCase();
  if (normalized.isEmpty) {
    return 'auto';
  }

  return switch (normalized) {
    'auto' => 'auto',
    'c++' => 'cpp',
    'c#' || 'csharp' => 'cs',
    'js' => 'javascript',
    'ts' => 'typescript',
    'py' => 'python',
    'sh' || 'bash' => 'shell',
    'htm' => 'html',
    'yml' => 'yaml',
    'md' => 'markdown',
    'objective-c' => 'objectivec',
    'latex' => 'tex',
    'visual basic' => 'vbnet',
    'plain' || 'plaintext' || 'plain text' => 'text',
    _ => normalized,
  };
}

String _grammarForLanguage(String language) => switch (language) {
      'c' => 'cpp',
      'html' => 'xml',
      // highlight.js's `shell` grammar only marks up a console session's
      // prompt. Script files want the bash grammar.
      'shell' => 'bash',
      _ => language,
    };

TextSpan buildSyntaxHighlightedTextSpan({
  required String code,
  required String language,
  required Brightness brightness,
  TextStyle? style,
  bool isPaper = false,
}) {
  final normalizedLanguage = normalizeCodeLanguage(language);
  if (normalizedLanguage == 'text') {
    return TextSpan(text: code, style: style);
  }

  final grammar = _grammarForLanguage(normalizedLanguage);
  final useAutoDetection =
      grammar == 'auto' || !allLanguages.containsKey(grammar);

  final result = useAutoDetection
      ? _autoHighlighter.parse(code, autoDetection: true)
      : highlight.highlight.parse(code, language: grammar);
  final theme = switch (brightness) {
    Brightness.dark => _darkPlusSyntaxTheme,
    Brightness.light when isPaper => _paperSyntaxTheme,
    Brightness.light => _lightSyntaxTheme,
  };
  final rootStyle = (style ?? const TextStyle()).copyWith(
    color: theme['root']?.color,
  );

  return TextSpan(
    style: rootStyle,
    children: _buildSpans(result.nodes, theme) ?? [TextSpan(text: code)],
  );
}

/// A leaf of the parse tree, with the style its whole ancestry resolves to.
class _Token {
  _Token(this.text, this.className, this.style);

  final String text;
  final String? className;
  final TextStyle? style;
}

List<TextSpan>? _buildSpans(
  List<highlight.Node>? nodes,
  Map<String, TextStyle> theme,
) {
  if (nodes == null) {
    return null;
  }

  final tokens = <_Token>[];
  for (final node in nodes) {
    _collectTokens(node, theme, null, null, tokens);
  }

  final spans = <TextSpan>[];
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (!_isCodeContext(token.className)) {
      spans.add(TextSpan(text: token.text, style: token.style));
      continue;
    }

    final split = _markCallees(
      token.text,
      token.style,
      theme['title'],
      spillsIntoArgumentList: _opensArgumentList(tokens, i + 1),
    );
    if (split == null) {
      spans.add(TextSpan(text: token.text, style: token.style));
    } else {
      spans.addAll(split);
    }
  }
  return spans;
}

void _collectTokens(
  highlight.Node node,
  Map<String, TextStyle> theme,
  String? inheritedClass,
  TextStyle? inheritedStyle,
  List<_Token> out,
) {
  final className = node.className ?? inheritedClass;
  final own = node.className == null ? null : theme[node.className];
  final style =
      own == null ? inheritedStyle : inheritedStyle?.merge(own) ?? own;

  final text = node.value;
  if (text != null && text.isNotEmpty) {
    out.add(_Token(text, className, style));
  }
  for (final child in node.children ?? const <highlight.Node>[]) {
    _collectTokens(child, theme, className, style, out);
  }
}

/// Whether a token's text is live code rather than prose, a string or a
/// comment, so a callee inside it is worth marking.
bool _isCodeContext(String? className) =>
    className == null || className == 'params' || className == 'subst';

/// Whether the code after [from] opens an argument list, which a grammar
/// often splits into its own node - `foo` and `(bar)` arrive separately.
bool _opensArgumentList(List<_Token> tokens, int from) {
  for (var i = from; i < tokens.length; i++) {
    final rest = tokens[i].text.replaceFirst(RegExp(r'^[ \t]+'), '');
    if (rest.isNotEmpty) {
      return rest.startsWith('(');
    }
  }
  return false;
}

/// highlight.js only names a function where a grammar declares one, so calls
/// - and definitions in grammars that skip them, such as Dart's - come back as
/// unclassified text. Colour the name in front of an argument list so a call
/// reads the same as a declaration.
final _calleePattern = RegExp(r'([A-Za-z_$][A-Za-z0-9_$]*)(?=!?[ \t]*\()');

/// The same name, where the argument list lands in the following token.
final _trailingCalleePattern = RegExp(r'([A-Za-z_$][A-Za-z0-9_$]*)!?[ \t]*$');

/// Words that take a parenthesised clause without being a call.
const _nonCallableWords = {
  'and',
  'as',
  'assert',
  'await',
  'base',
  'begin',
  'case',
  'catch',
  'class',
  'const',
  'declare',
  'def',
  'defer',
  'del',
  'delete',
  'do',
  'elif',
  'else',
  'elseif',
  'elsif',
  'end',
  'ensure',
  'enum',
  'except',
  'export',
  'extends',
  'finally',
  'fn',
  'for',
  'foreach',
  'from',
  'fun',
  'func',
  'function',
  'go',
  'if',
  'implements',
  'import',
  'in',
  'instanceof',
  'interface',
  'is',
  'lambda',
  'let',
  'lock',
  'loop',
  'match',
  'module',
  'namespace',
  'new',
  'not',
  'operator',
  'or',
  'package',
  'private',
  'protected',
  'public',
  'raise',
  'record',
  'repeat',
  'rescue',
  'rethrow',
  'return',
  'select',
  'self',
  'static',
  'struct',
  'sub',
  'super',
  'switch',
  'template',
  'then',
  'this',
  'throw',
  'try',
  'typeof',
  'unless',
  'until',
  'using',
  'val',
  'var',
  'when',
  'where',
  'while',
  'with',
  'yield',
};

/// Returns the split spans, or null when nothing in [text] is a call.
List<TextSpan>? _markCallees(
  String text,
  TextStyle? baseStyle,
  TextStyle? titleStyle, {
  required bool spillsIntoArgumentList,
}) {
  if (titleStyle == null || (!text.contains('(') && !spillsIntoArgumentList)) {
    return null;
  }

  final calleeStyle = baseStyle?.merge(titleStyle) ?? titleStyle;
  List<TextSpan>? spans;
  var start = 0;

  void take(int at, String name) {
    spans ??= <TextSpan>[];
    if (at > start) {
      spans!.add(TextSpan(text: text.substring(start, at), style: baseStyle));
    }
    spans!.add(TextSpan(text: name, style: calleeStyle));
    start = at + name.length;
  }

  for (final match in _calleePattern.allMatches(text)) {
    final name = match.group(1)!;
    if (!_nonCallableWords.contains(name)) {
      take(match.start, name);
    }
  }

  if (spillsIntoArgumentList) {
    final tail = _trailingCalleePattern.firstMatch(text);
    final name = tail?.group(1);
    if (tail != null &&
        name != null &&
        tail.start >= start &&
        !_nonCallableWords.contains(name)) {
      take(tail.start, name);
    }
  }

  if (spans == null) {
    return null;
  }
  if (start < text.length) {
    spans!.add(TextSpan(text: text.substring(start), style: baseStyle));
  }
  return spans;
}
