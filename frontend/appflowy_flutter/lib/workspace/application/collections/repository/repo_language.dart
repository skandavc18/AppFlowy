import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A programming or markup language a repository can hold.
///
/// The catalog is deliberately data only: the outline reader, the import
/// reader, the language bar and the syntax highlighter all resolve through
/// [repoLanguageForName], so adding a language is one entry here rather than a
/// change in five places.
@immutable
class RepoLanguage {
  const RepoLanguage({
    required this.id,
    required this.label,
    required this.color,
    required this.extensions,
    this.lineComment = '//',
    this.blockComment,
    this.isMarkup = false,
    this.isData = false,
  });

  /// The highlight.js grammar key, so the existing highlighter can be reused.
  final String id;
  final String label;
  final Color color;
  final Set<String> extensions;
  final String lineComment;

  /// Opening and closing delimiters, when the language has block comments.
  final (String, String)? blockComment;

  /// Prose rather than code: counted separately in the language bar.
  final bool isMarkup;

  /// Configuration or data rather than code.
  final bool isData;

  bool get isCode => !isMarkup && !isData;
}

/// The languages AppFlowy can read structure out of.
///
/// Colours follow GitHub Linguist so a repository looks familiar.
const List<RepoLanguage> repoLanguages = [
  RepoLanguage(
    id: 'dart',
    label: 'Dart',
    color: Color(0xFF00B4AB),
    extensions: {'dart'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'typescript',
    label: 'TypeScript',
    color: Color(0xFF3178C6),
    extensions: {'ts', 'tsx', 'mts', 'cts'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'javascript',
    label: 'JavaScript',
    color: Color(0xFFF1E05A),
    extensions: {'js', 'jsx', 'mjs', 'cjs'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'python',
    label: 'Python',
    color: Color(0xFF3572A5),
    extensions: {'py', 'pyi', 'pyw'},
    lineComment: '#',
  ),
  RepoLanguage(
    id: 'rust',
    label: 'Rust',
    color: Color(0xFFDEA584),
    extensions: {'rs'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'go',
    label: 'Go',
    color: Color(0xFF00ADD8),
    extensions: {'go'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'java',
    label: 'Java',
    color: Color(0xFFB07219),
    extensions: {'java'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'kotlin',
    label: 'Kotlin',
    color: Color(0xFFA97BFF),
    extensions: {'kt', 'kts'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'swift',
    label: 'Swift',
    color: Color(0xFFF05138),
    extensions: {'swift'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'cpp',
    label: 'C++',
    color: Color(0xFFF34B7D),
    extensions: {'cpp', 'cxx', 'cc', 'hpp', 'hxx', 'hh'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'c',
    label: 'C',
    color: Color(0xFF555555),
    extensions: {'c', 'h'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'csharp',
    label: 'C#',
    color: Color(0xFF178600),
    extensions: {'cs'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'ruby',
    label: 'Ruby',
    color: Color(0xFF701516),
    extensions: {'rb', 'rake'},
    lineComment: '#',
  ),
  RepoLanguage(
    id: 'php',
    label: 'PHP',
    color: Color(0xFF4F5D95),
    extensions: {'php'},
    blockComment: ('/*', '*/'),
  ),
  RepoLanguage(
    id: 'bash',
    label: 'Shell',
    color: Color(0xFF89E051),
    extensions: {'sh', 'bash', 'zsh'},
    lineComment: '#',
  ),
  RepoLanguage(
    id: 'powershell',
    label: 'PowerShell',
    color: Color(0xFF012456),
    extensions: {'ps1', 'psm1'},
    lineComment: '#',
  ),
  RepoLanguage(
    id: 'sql',
    label: 'SQL',
    color: Color(0xFFE38C00),
    extensions: {'sql'},
    lineComment: '--',
    isData: true,
  ),
  RepoLanguage(
    id: 'css',
    label: 'CSS',
    color: Color(0xFF563D7C),
    extensions: {'css', 'scss', 'sass', 'less'},
    blockComment: ('/*', '*/'),
    isMarkup: true,
  ),
  RepoLanguage(
    id: 'xml',
    label: 'HTML',
    color: Color(0xFFE34C26),
    extensions: {'html', 'htm', 'xml', 'svg'},
    lineComment: '',
    blockComment: ('<!--', '-->'),
    isMarkup: true,
  ),
  RepoLanguage(
    id: 'markdown',
    label: 'Markdown',
    color: Color(0xFF7B8794),
    extensions: {'md', 'markdown', 'mdx', 'rst', 'adoc'},
    lineComment: '',
    isMarkup: true,
  ),
  RepoLanguage(
    id: 'json',
    label: 'JSON',
    color: Color(0xFF959DA5),
    extensions: {'json', 'jsonc'},
    lineComment: '',
    isData: true,
  ),
  RepoLanguage(
    id: 'yaml',
    label: 'YAML',
    color: Color(0xFFCB171E),
    extensions: {'yaml', 'yml'},
    lineComment: '#',
    isData: true,
  ),
  RepoLanguage(
    id: 'ini',
    label: 'Config',
    color: Color(0xFF6E7681),
    extensions: {'toml', 'ini', 'cfg', 'conf', 'properties', 'env'},
    lineComment: '#',
    isData: true,
  ),
  RepoLanguage(
    id: 'plaintext',
    label: 'Text',
    color: Color(0xFF8B949E),
    extensions: {'txt', 'log', 'csv', 'tsv'},
    lineComment: '',
    isData: true,
  ),
];

/// The file names that name a language without carrying an extension.
const Map<String, String> _repoLanguageByFileName = {
  'dockerfile': 'bash',
  'makefile': 'bash',
  'cmakelists.txt': 'bash',
  'gemfile': 'ruby',
  'rakefile': 'ruby',
  'podfile': 'ruby',
  'brewfile': 'ruby',
  'procfile': 'ini',
};

final Map<String, RepoLanguage> _byExtension = {
  for (final language in repoLanguages)
    for (final extension in language.extensions) extension: language,
};

final Map<String, RepoLanguage> _byId = {
  for (final language in repoLanguages) language.id: language,
};

RepoLanguage? repoLanguageById(String id) => _byId[id];

/// The language [name] is written in, or null when it is not source at all.
RepoLanguage? repoLanguageForName(String name) {
  final lower = name.toLowerCase();
  final byName = _repoLanguageByFileName[lower];
  if (byName != null) {
    return _byId[byName];
  }
  final dot = lower.lastIndexOf('.');
  if (dot < 0) {
    return null;
  }
  return _byExtension[lower.substring(dot + 1)];
}
