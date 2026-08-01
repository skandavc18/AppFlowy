import 'package:appflowy/workspace/application/collections/repository/repo_language.dart';
import 'package:flutter/foundation.dart';

/// What a declaration found in source is.
enum SymbolKind {
  module,
  classType,
  interfaceType,
  enumType,
  structType,
  traitType,
  mixinType,
  extensionType,
  typeAlias,
  function,
  constant,
  property,
  heading,
  section;

  /// Whether the symbol can hold other symbols, so an outline can nest.
  bool get isContainer => switch (this) {
        SymbolKind.module ||
        SymbolKind.classType ||
        SymbolKind.interfaceType ||
        SymbolKind.enumType ||
        SymbolKind.structType ||
        SymbolKind.traitType ||
        SymbolKind.mixinType ||
        SymbolKind.extensionType ||
        SymbolKind.heading =>
          true,
        _ => false,
      };
}

/// One declaration, at the line it was written on.
@immutable
class SourceSymbol {
  const SourceSymbol({
    required this.kind,
    required this.name,
    required this.line,
    required this.depth,
    this.detail = '',
  });

  final SymbolKind kind;
  final String name;

  /// 1-based, so it can be shown next to the source.
  final int line;

  /// Nesting level within the file's own outline.
  final int depth;

  /// The rest of the declaration, trimmed — a signature or a base class.
  final String detail;

  @override
  String toString() => '$kind $name:$line';
}

@immutable
class _OutlineRule {
  const _OutlineRule(this.kind, this.pattern);

  final SymbolKind kind;
  final RegExp pattern;
}

/// Statements that open a block but declare nothing.
const Set<String> _controlKeywords = {
  'if',
  'else',
  'for',
  'while',
  'switch',
  'case',
  'catch',
  'do',
  'try',
  'return',
  'throw',
  'with',
  'when',
  'match',
  'lock',
  'using',
  'foreach',
  'unless',
  'elif',
  'except',
  'finally',
  'assert',
  'await',
  'yield',
  'new',
  'delete',
  'sizeof',
  'print',
  'super',
  'this',
  'defer',
  'go',
  'select',
};

final _typeRules = <String, List<_OutlineRule>>{
  'dart': [
    _OutlineRule(
      SymbolKind.classType,
      RegExp(
        r'^\s*(?:abstract\s+|base\s+|final\s+|sealed\s+|interface\s+)*class\s+([A-Za-z_$][\w$]*)',
      ),
    ),
    _OutlineRule(
      SymbolKind.mixinType,
      RegExp(r'^\s*(?:base\s+)?mixin\s+([A-Za-z_$][\w$]*)'),
    ),
    _OutlineRule(
      SymbolKind.extensionType,
      RegExp(r'^\s*extension\s+(?:type\s+)?([A-Za-z_$][\w$]*)'),
    ),
    _OutlineRule(SymbolKind.enumType, RegExp(r'^\s*enum\s+([A-Za-z_$][\w$]*)')),
    _OutlineRule(
      SymbolKind.typeAlias,
      RegExp(r'^\s*typedef\s+(?:[\w<>,\s?]+\s+)?([A-Za-z_$][\w$]*)\s*[=<(]'),
    ),
  ],
  'typescript': [
    _OutlineRule(
      SymbolKind.classType,
      RegExp(r'^\s*(?:export\s+)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)'),
    ),
    _OutlineRule(
      SymbolKind.interfaceType,
      RegExp(r'^\s*(?:export\s+)?interface\s+([A-Za-z_$][\w$]*)'),
    ),
    _OutlineRule(
      SymbolKind.enumType,
      RegExp(r'^\s*(?:export\s+)?(?:const\s+)?enum\s+([A-Za-z_$][\w$]*)'),
    ),
    _OutlineRule(
      SymbolKind.typeAlias,
      RegExp(r'^\s*(?:export\s+)?type\s+([A-Za-z_$][\w$]*)\s*[=<]'),
    ),
    _OutlineRule(
      SymbolKind.function,
      RegExp(
        r'^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)',
      ),
    ),
    _OutlineRule(
      SymbolKind.function,
      RegExp(
        r'^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)[^=]*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>',
      ),
    ),
    _OutlineRule(
      SymbolKind.constant,
      RegExp(r'^\s*export\s+const\s+([A-Za-z_$][\w$]*)\s*[:=]'),
    ),
  ],
  'python': [
    _OutlineRule(
      SymbolKind.classType,
      RegExp(r'^\s*class\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.function,
      RegExp(r'^\s*(?:async\s+)?def\s+([A-Za-z_][\w]*)'),
    ),
  ],
  'rust': [
    _OutlineRule(
      SymbolKind.structType,
      RegExp(r'^\s*(?:pub(?:\([^)]*\))?\s+)?struct\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.enumType,
      RegExp(r'^\s*(?:pub(?:\([^)]*\))?\s+)?enum\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.traitType,
      RegExp(
          r'^\s*(?:pub(?:\([^)]*\))?\s+)?(?:unsafe\s+)?trait\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.extensionType,
      RegExp(
          r'^\s*impl(?:<[^>]*>)?\s+(?:[\w:<>, ]+\s+for\s+)?([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.module,
      RegExp(r'^\s*(?:pub(?:\([^)]*\))?\s+)?mod\s+([A-Za-z_][\w]*)\s*\{'),
    ),
    _OutlineRule(
      SymbolKind.function,
      RegExp(
        r'^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?(?:extern\s+"[^"]*"\s+)?fn\s+([A-Za-z_][\w]*)',
      ),
    ),
    _OutlineRule(
      SymbolKind.typeAlias,
      RegExp(r'^\s*(?:pub(?:\([^)]*\))?\s+)?type\s+([A-Za-z_][\w]*)\s*='),
    ),
    _OutlineRule(
      SymbolKind.constant,
      RegExp(
          r'^\s*(?:pub(?:\([^)]*\))?\s+)?(?:const|static)\s+([A-Za-z_][\w]*)\s*:'),
    ),
  ],
  'go': [
    _OutlineRule(
      SymbolKind.structType,
      RegExp(r'^\s*type\s+([A-Za-z_][\w]*)\s+struct\b'),
    ),
    _OutlineRule(
      SymbolKind.interfaceType,
      RegExp(r'^\s*type\s+([A-Za-z_][\w]*)\s+interface\b'),
    ),
    _OutlineRule(
      SymbolKind.typeAlias,
      RegExp(r'^\s*type\s+([A-Za-z_][\w]*)\s+(?!struct\b|interface\b)\S'),
    ),
    _OutlineRule(
      SymbolKind.function,
      RegExp(r'^\s*func\s+(?:\([^)]*\)\s*)?([A-Za-z_][\w]*)\s*\('),
    ),
  ],
  'java': [
    _OutlineRule(
      SymbolKind.classType,
      RegExp(
        r'^\s*(?:public\s+|private\s+|protected\s+|abstract\s+|final\s+|static\s+|sealed\s+)*class\s+([A-Za-z_$][\w$]*)',
      ),
    ),
    _OutlineRule(
      SymbolKind.interfaceType,
      RegExp(
        r'^\s*(?:public\s+|private\s+|protected\s+|abstract\s+|static\s+|sealed\s+)*interface\s+([A-Za-z_$][\w$]*)',
      ),
    ),
    _OutlineRule(
      SymbolKind.enumType,
      RegExp(
        r'^\s*(?:public\s+|private\s+|protected\s+|static\s+|final\s+)*enum\s+([A-Za-z_$][\w$]*)',
      ),
    ),
    _OutlineRule(
      SymbolKind.structType,
      RegExp(
        r'^\s*(?:public\s+|private\s+|protected\s+|static\s+|final\s+)*record\s+([A-Za-z_$][\w$]*)',
      ),
    ),
  ],
  'kotlin': [
    _OutlineRule(
      SymbolKind.classType,
      RegExp(
        r'^\s*(?:public\s+|private\s+|internal\s+|protected\s+|abstract\s+|open\s+|final\s+|sealed\s+|data\s+|inner\s+|value\s+|annotation\s+|enum\s+)*class\s+([A-Za-z_][\w]*)',
      ),
    ),
    _OutlineRule(
      SymbolKind.interfaceType,
      RegExp(r'^\s*(?:\w+\s+)*interface\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.module,
      RegExp(r'^\s*object\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.function,
      RegExp(
          r'^\s*(?:\w+\s+)*fun\s+(?:<[^>]*>\s*)?(?:[\w.<>]+\.)?([A-Za-z_][\w]*)\s*\('),
    ),
    _OutlineRule(
      SymbolKind.constant,
      RegExp(r'^\s*(?:const\s+)?val\s+([A-Za-z_][\w]*)\s*[:=]'),
    ),
  ],
  'swift': [
    _OutlineRule(
      SymbolKind.classType,
      RegExp(r'^\s*(?:\w+\s+)*class\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.structType,
      RegExp(r'^\s*(?:\w+\s+)*struct\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.enumType,
      RegExp(r'^\s*(?:\w+\s+)*enum\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.traitType,
      RegExp(r'^\s*(?:\w+\s+)*protocol\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.extensionType,
      RegExp(r'^\s*extension\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.function,
      RegExp(r'^\s*(?:\w+\s+)*func\s+([A-Za-z_][\w]*)'),
    ),
  ],
  'cpp': [
    _OutlineRule(
      SymbolKind.module,
      RegExp(r'^\s*namespace\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.classType,
      RegExp(r'^\s*(?:template\s*<[^>]*>\s*)?class\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.structType,
      RegExp(r'^\s*(?:template\s*<[^>]*>\s*)?struct\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.enumType,
      RegExp(r'^\s*enum(?:\s+class)?\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.typeAlias,
      RegExp(r'^\s*using\s+([A-Za-z_][\w]*)\s*='),
    ),
  ],
  'csharp': [
    _OutlineRule(
      SymbolKind.module,
      RegExp(r'^\s*namespace\s+([A-Za-z_][\w.]*)'),
    ),
    _OutlineRule(
      SymbolKind.classType,
      RegExp(r'^\s*(?:\w+\s+)*class\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.interfaceType,
      RegExp(r'^\s*(?:\w+\s+)*interface\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.structType,
      RegExp(r'^\s*(?:\w+\s+)*(?:struct|record)\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.enumType,
      RegExp(r'^\s*(?:\w+\s+)*enum\s+([A-Za-z_][\w]*)'),
    ),
  ],
  'ruby': [
    _OutlineRule(
      SymbolKind.classType,
      RegExp(r'^\s*class\s+([A-Za-z_][\w:]*)'),
    ),
    _OutlineRule(
      SymbolKind.module,
      RegExp(r'^\s*module\s+([A-Za-z_][\w:]*)'),
    ),
    _OutlineRule(
      SymbolKind.function,
      RegExp(r'^\s*def\s+(?:self\.)?([A-Za-z_][\w?!=]*)'),
    ),
  ],
  'php': [
    _OutlineRule(
      SymbolKind.classType,
      RegExp(r'^\s*(?:\w+\s+)*class\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.interfaceType,
      RegExp(r'^\s*interface\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.traitType,
      RegExp(r'^\s*trait\s+([A-Za-z_][\w]*)'),
    ),
    _OutlineRule(
      SymbolKind.function,
      RegExp(r'^\s*(?:\w+\s+)*function\s+&?\s*([A-Za-z_][\w]*)\s*\('),
    ),
  ],
  'bash': [
    _OutlineRule(
      SymbolKind.function,
      RegExp(r'^\s*(?:function\s+)?([A-Za-z_][\w-]*)\s*\(\s*\)\s*\{'),
    ),
  ],
  'powershell': [
    _OutlineRule(
      SymbolKind.function,
      RegExp(r'^\s*function\s+([A-Za-z_][\w-]*)', caseSensitive: false),
    ),
  ],
  'sql': [
    _OutlineRule(
      SymbolKind.structType,
      RegExp(
        r'^\s*create\s+(?:or\s+replace\s+)?table\s+(?:if\s+not\s+exists\s+)?([\w."`\[\]]+)',
        caseSensitive: false,
      ),
    ),
    _OutlineRule(
      SymbolKind.function,
      RegExp(
        r'^\s*create\s+(?:or\s+replace\s+)?(?:function|procedure)\s+([\w."`\[\]]+)',
        caseSensitive: false,
      ),
    ),
    _OutlineRule(
      SymbolKind.typeAlias,
      RegExp(
        r'^\s*create\s+(?:or\s+replace\s+)?view\s+([\w."`\[\]]+)',
        caseSensitive: false,
      ),
    ),
  ],
  'css': [
    _OutlineRule(
      SymbolKind.section,
      RegExp(r'^\s*([.#@][\w-][^{;,]*?)\s*\{'),
    ),
  ],
};

/// The languages whose callables are found by the shared brace heuristic.
const Set<String> _braceCallableLanguages = {
  'dart',
  'typescript',
  'javascript',
  'java',
  'csharp',
  'cpp',
  'c',
};

final _braceCallable = RegExp(
  r'^[ \t]*(?:@[\w.]+(?:\([^)]*\))?[ \t]*)*'
  r'(?:(?:public|private|protected|internal|static|final|abstract|virtual|override|async|external|factory|const|inline|explicit|friend|constexpr|synchronized|native|default|sealed|partial|unsafe|operator|export)[ \t]+)*'
  r'(?:[A-Za-z_$][\w$.<>,\[\] ]*?[ \t?*&]+)?'
  r'(?:get[ \t]+|set[ \t]+)?'
  r'([A-Za-z_$~][\w$]*)[ \t]*(?:<[^<>()]*>)?[ \t]*\(',
);

/// Declaration heads end in a body, an arrow, an abstract semicolon or a
/// constructor initialiser — a call statement does not.
final _declarationTail = RegExp(
  r'(?:\{|=>|;|:|\)\s*(?:const|final|override|noexcept|throws?\b[\w\s,.]*|async\*?|sync\*)?\s*)$',
);

final _markdownHeading = RegExp(r'^(#{1,6})\s+(.+?)\s*#*$');
final _markdownSetext = RegExp(r'^(=+|-+)\s*$');
final _rstHeading = RegExp(r'^([=\-~^"#*+`]{3,})\s*$');
final _iniSection = RegExp(r'^\s*\[([^\]]+)\]\s*$');
final _yamlKey = RegExp(r'^([A-Za-z_][\w.\- ]*):\s*(?:#.*)?$');

/// Reads the declarations out of [source].
///
/// This is a heuristic outline, not a compiler: it matches the declaration
/// forms a file is normally written in, which is what an explorer needs and
/// what can be done without a language server for every language at once.
List<SourceSymbol> parseSourceOutline(RepoLanguage? language, String source) {
  if (source.isEmpty) {
    return const [];
  }
  final lines = source.split('\n');
  if (language == null) {
    return const [];
  }
  return switch (language.id) {
    'markdown' => _parseMarkdownOutline(lines),
    'yaml' => _parseKeyedOutline(lines, _yamlKey, SymbolKind.property),
    'ini' => _parseKeyedOutline(lines, _iniSection, SymbolKind.section),
    'json' || 'plaintext' || 'xml' => const [],
    _ => _parseCodeOutline(language, lines),
  };
}

List<SourceSymbol> _parseCodeOutline(
    RepoLanguage language, List<String> lines) {
  final rules = _typeRules[language.id] ?? const <_OutlineRule>[];
  final findsCallables = _braceCallableLanguages.contains(language.id);
  if (rules.isEmpty && !findsCallables) {
    return const [];
  }
  final block = language.blockComment;
  final lineComment = language.lineComment;
  final symbols = <SourceSymbol>[];
  final indents = <int>[];
  var inBlockComment = false;

  for (var index = 0; index < lines.length; index++) {
    var line = lines[index];
    if (block != null) {
      if (inBlockComment) {
        final close = line.indexOf(block.$2);
        if (close < 0) {
          continue;
        }
        inBlockComment = false;
        line = ' ' * (close + block.$2.length) +
            line.substring(close + block.$2.length);
      }
      final open = line.indexOf(block.$1);
      if (open >= 0 && !line.substring(0, open).contains(lineComment)) {
        final close = line.indexOf(block.$2, open + block.$1.length);
        if (close < 0) {
          inBlockComment = true;
          line = line.substring(0, open);
        } else {
          line =
              line.substring(0, open) + line.substring(close + block.$2.length);
        }
      }
    }
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (lineComment.isNotEmpty && trimmed.startsWith(lineComment)) {
      continue;
    }

    final match = _firstMatch(rules, line);
    var kind = match?.$1;
    var name = match?.$2;
    if (name == null && findsCallables) {
      final callable = _matchCallable(line, trimmed);
      if (callable != null) {
        kind = SymbolKind.function;
        name = callable;
      }
    }
    if (kind == null || name == null || name.isEmpty) {
      continue;
    }

    final indent = _indentWidth(line);
    while (indents.isNotEmpty && indent <= indents.last) {
      indents.removeLast();
    }
    symbols.add(
      SourceSymbol(
        kind: kind,
        name: name,
        line: index + 1,
        depth: indents.length,
        detail: _detailFor(trimmed, name),
      ),
    );
    indents.add(indent);
  }
  return symbols;
}

(SymbolKind, String)? _firstMatch(List<_OutlineRule> rules, String line) {
  for (final rule in rules) {
    final match = rule.pattern.firstMatch(line);
    final name = match?.group(1);
    if (name != null && name.isNotEmpty) {
      return (rule.kind, name);
    }
  }
  return null;
}

String? _matchCallable(String line, String trimmed) {
  if (!_declarationTail.hasMatch(trimmed)) {
    return null;
  }
  final match = _braceCallable.firstMatch(line);
  final name = match?.group(1);
  if (name == null || _controlKeywords.contains(name)) {
    return null;
  }
  // `foo();` on its own is a call, not a declaration.
  if (trimmed.endsWith(';') && !trimmed.contains(')')) {
    return null;
  }
  if (trimmed.startsWith('return ') || trimmed.startsWith('=')) {
    return null;
  }
  return name;
}

/// The declaration after its name, so a list can show `(int a) => bool`.
String _detailFor(String trimmed, String name) {
  final start = trimmed.indexOf(name);
  if (start < 0) {
    return '';
  }
  var tail = trimmed.substring(start + name.length).trim();
  if (tail.endsWith('{')) {
    tail = tail.substring(0, tail.length - 1).trimRight();
  }
  return tail.length > 90 ? '${tail.substring(0, 90)}…' : tail;
}

List<SourceSymbol> _parseMarkdownOutline(List<String> lines) {
  final symbols = <SourceSymbol>[];
  var inFence = false;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      continue;
    }
    final heading = _markdownHeading.firstMatch(trimmed);
    if (heading != null) {
      symbols.add(
        SourceSymbol(
          kind: SymbolKind.heading,
          name: heading.group(2)!.trim(),
          line: index + 1,
          depth: heading.group(1)!.length - 1,
        ),
      );
      continue;
    }
    // Setext headings underline the previous line; reStructuredText may also
    // overline it, which the same check handles because the title still sits
    // directly above a rule.
    if (index > 0 &&
        (_markdownSetext.hasMatch(trimmed) || _rstHeading.hasMatch(trimmed))) {
      final title = lines[index - 1].trim();
      if (title.isEmpty || symbols.any((symbol) => symbol.line == index)) {
        continue;
      }
      symbols.add(
        SourceSymbol(
          kind: SymbolKind.heading,
          name: title,
          line: index,
          depth: trimmed.startsWith('=') ? 0 : 1,
        ),
      );
    }
  }
  return symbols;
}

List<SourceSymbol> _parseKeyedOutline(
  List<String> lines,
  RegExp pattern,
  SymbolKind kind,
) {
  final symbols = <SourceSymbol>[];
  for (var index = 0; index < lines.length; index++) {
    final match = pattern.firstMatch(lines[index]);
    final name = match?.group(1);
    if (name == null) {
      continue;
    }
    symbols.add(
      SourceSymbol(
        kind: kind,
        name: name.trim(),
        line: index + 1,
        depth: 0,
      ),
    );
  }
  return symbols;
}

int _indentWidth(String line) {
  var width = 0;
  for (final unit in line.codeUnits) {
    if (unit == 0x20) {
      width += 1;
    } else if (unit == 0x09) {
      width += 4;
    } else {
      break;
    }
  }
  return width;
}
