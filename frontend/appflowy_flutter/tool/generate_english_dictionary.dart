// Builds the bundled English dictionary from the Hunspell sources in
// `tool/english_dictionary/`.
//
// Run with:
//   dart run tool/generate_english_dictionary.dart
//
// It writes two gzipped, newline separated assets:
//   assets/dictionaries/en_us_words.txt.gz   every accepted spelling
//   assets/dictionaries/en_us_common.txt.gz  the same words a person actually
//                                            writes, most used first, so a
//                                            suggestion can be ranked
//
// Expanding the affixes here rather than at runtime keeps the application free
// of a Hunspell implementation: it only ever asks whether a word is in a set.

import 'dart:convert';
import 'dart:io';

const _sourceDirectory = 'tool/english_dictionary';
const _outputDirectory = 'assets/dictionaries';

/// How many of the most used words are kept for ranking suggestions.
const _commonWordLimit = 30000;

void main() {
  // Both spellings of English are accepted. Flagging "colour" or "analyse"
  // as a mistake would be worse than missing the handful of words that only
  // one of the two lists knows.
  final words = <String>{};
  for (final variant in const ['index', 'index-en-GB']) {
    words.addAll(
      _expand(
        File('$_sourceDirectory/$variant.dic').readAsLinesSync(),
        _AffixTable.parse(
          File('$_sourceDirectory/$variant.aff').readAsLinesSync(),
        ),
      ),
    );
  }

  final common = <String>[];
  for (final line in File('$_sourceDirectory/en_50k.txt').readAsLinesSync()) {
    final word = line.split(' ').first.trim().toLowerCase();
    if (word.isEmpty || !words.contains(word)) {
      continue;
    }
    common.add(word);
    if (common.length >= _commonWordLimit) {
      break;
    }
  }

  Directory(_outputDirectory).createSync(recursive: true);
  _write('$_outputDirectory/en_us_words.txt.gz', words.toList()..sort());
  _write('$_outputDirectory/en_us_common.txt.gz', common);

  stdout.writeln('${words.length} spellings, ${common.length} ranked.');
}

void _write(String path, List<String> words) {
  final bytes = gzip.encode(utf8.encode(words.join('\n')));
  File(path).writeAsBytesSync(bytes);
  stdout.writeln('$path — ${(bytes.length / 1024).round()} KB');
}

Set<String> _expand(List<String> lines, _AffixTable affix) {
  final words = <String>{};
  // The first line is the entry count, not an entry.
  for (final line in lines.skip(1)) {
    final entry = line.trim();
    if (entry.isEmpty) {
      continue;
    }
    final slash = entry.indexOf('/');
    final stem = (slash < 0 ? entry : entry.substring(0, slash)).trim();
    final flags = slash < 0 ? '' : entry.substring(slash + 1).trim();
    if (stem.isEmpty || flags.contains(affix.onlyInCompound)) {
      continue;
    }

    _add(words, stem);
    final suffixed = <String>[stem];
    for (final flag in flags.split('')) {
      for (final rule in affix.suffixes[flag] ?? const <_AffixRule>[]) {
        final formed = rule.applyToEnd(stem);
        if (formed == null) {
          continue;
        }
        _add(words, formed);
        if (rule.crossProduct) {
          suffixed.add(formed);
        }
      }
    }
    for (final flag in flags.split('')) {
      for (final rule in affix.prefixes[flag] ?? const <_AffixRule>[]) {
        for (final base in suffixed) {
          // A prefix combines with a suffixed form only when both rules allow
          // it; the bare stem always does.
          if (base != stem && !rule.crossProduct) {
            continue;
          }
          final formed = rule.applyToStart(base);
          if (formed != null) {
            _add(words, formed);
          }
        }
      }
    }
  }
  return words;
}

final _acceptable = RegExp(r"^[a-z]+(?:'[a-z]+)*$");

void _add(Set<String> words, String word) {
  final normalized = word.toLowerCase().replaceAll('\u2019', "'");
  if (_acceptable.hasMatch(normalized)) {
    words.add(normalized);
  }
}

class _AffixTable {
  _AffixTable(this.prefixes, this.suffixes, this.onlyInCompound);

  final Map<String, List<_AffixRule>> prefixes;
  final Map<String, List<_AffixRule>> suffixes;
  final String onlyInCompound;

  static _AffixTable parse(List<String> lines) {
    final prefixes = <String, List<_AffixRule>>{};
    final suffixes = <String, List<_AffixRule>>{};
    var onlyInCompound = '';

    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }
      if (parts.first == 'ONLYINCOMPOUND') {
        onlyInCompound = parts[1];
        continue;
      }
      if (parts.first != 'PFX' && parts.first != 'SFX') {
        continue;
      }
      // A header reads `SFX <flag> <Y|N> <count>`; a rule has four fields
      // after the kind.
      if (parts.length < 5) {
        continue;
      }
      final table = parts.first == 'PFX' ? prefixes : suffixes;
      final flag = parts[1];
      table.putIfAbsent(flag, () => <_AffixRule>[]).add(
            _AffixRule(
              strip: parts[2] == '0' ? '' : parts[2],
              add: parts[3] == '0' ? '' : parts[3],
              condition: parts[4],
              crossProduct: _crossProductOf(lines, parts.first, flag),
            ),
          );
    }
    return _AffixTable(prefixes, suffixes, onlyInCompound);
  }

  static bool _crossProductOf(List<String> lines, String kind, String flag) {
    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 4 && parts[0] == kind && parts[1] == flag) {
        return parts[2] == 'Y';
      }
    }
    return false;
  }
}

class _AffixRule {
  _AffixRule({
    required this.strip,
    required this.add,
    required this.condition,
    required this.crossProduct,
  }) : _condition = condition == '.'
            ? null
            : RegExp('^(?:${_expandCondition(condition)})\$');

  final String strip;
  final String add;
  final String condition;
  final bool crossProduct;
  final RegExp? _condition;

  String? applyToEnd(String stem) {
    if (!_matchesEnd(stem) || !stem.endsWith(strip)) {
      return null;
    }
    return stem.substring(0, stem.length - strip.length) + add;
  }

  String? applyToStart(String stem) {
    if (!_matchesStart(stem) || !stem.startsWith(strip)) {
      return null;
    }
    return add + stem.substring(strip.length);
  }

  bool _matchesEnd(String stem) {
    final pattern = _condition;
    if (pattern == null) {
      return true;
    }
    final width = _conditionWidth(condition);
    if (stem.length < width) {
      return false;
    }
    return pattern.hasMatch(stem.substring(stem.length - width));
  }

  bool _matchesStart(String stem) {
    final pattern = _condition;
    if (pattern == null) {
      return true;
    }
    final width = _conditionWidth(condition);
    if (stem.length < width) {
      return false;
    }
    return pattern.hasMatch(stem.substring(0, width));
  }

  /// A condition is a run of single characters and `[...]` classes, so its
  /// width is the number of those pieces rather than its own length.
  static int _conditionWidth(String condition) {
    var width = 0;
    for (var index = 0; index < condition.length; index++) {
      if (condition[index] == '[') {
        index = condition.indexOf(']', index);
        if (index < 0) {
          break;
        }
      }
      width++;
    }
    return width;
  }

  static String _expandCondition(String condition) => condition;
}
