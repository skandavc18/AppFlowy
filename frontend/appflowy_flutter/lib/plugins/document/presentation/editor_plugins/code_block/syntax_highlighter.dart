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
  'keyword': TextStyle(color: Color(0xFF8250DF)),
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
    children: result.nodes
            ?.map((node) => _convertHighlightNode(node, theme))
            .toList() ??
        [TextSpan(text: code)],
  );
}

TextSpan _convertHighlightNode(
  highlight.Node node,
  Map<String, TextStyle> theme,
) {
  return TextSpan(
    text: node.value,
    style: node.className == null ? null : theme[node.className],
    children: node.children
        ?.map((child) => _convertHighlightNode(child, theme))
        .toList(),
  );
}
