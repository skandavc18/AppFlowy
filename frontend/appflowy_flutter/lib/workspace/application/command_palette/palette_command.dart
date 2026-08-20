import 'dart:async';

import 'package:flutter/widgets.dart';

/// The prefix that turns the search box into a command-only palette, the way
/// `>` does in VS Code.
const paletteCommandPrefix = '>';

/// How many commands a plain search shows alongside the pages it found.
const paletteInlineCommandLimit = 4;

/// The part of the palette a command belongs to. Purely presentational
/// grouping — the order here is the order the sections are offered in.
enum PaletteCommandGroup {
  create,
  navigate,
  view,
  workspace,
  extensions,
  ai,
}

/// Everything the palette hands a command when it is run.
class PaletteCommandContext {
  const PaletteCommandContext({
    required this.query,
    required this.dismiss,
  });

  /// What was typed after the command prefix, with no leading `>`.
  final String query;

  /// Closes the palette. A command that opens a route of its own must call
  /// this first, or popping afterwards would close that route instead.
  final VoidCallback dismiss;
}

/// One entry of the command palette.
class PaletteCommand {
  const PaletteCommand({
    required this.id,
    required this.title,
    required this.icon,
    required this.group,
    required this.run,
    this.subtitle = '',
    this.keywords = const <String>[],
    this.shortcut = '',
  });

  /// Stable identity, used as the widget key and by the tests.
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final PaletteCommandGroup group;

  /// Extra words the command answers to, so "dark" finds "Switch appearance".
  final List<String> keywords;

  /// The keyboard shortcut that does the same thing, shown on the right.
  final String shortcut;

  final FutureOr<void> Function(PaletteCommandContext context) run;
}

/// The command-only query carried by [raw], or null when [raw] is an ordinary
/// search.
String? paletteCommandModeQuery(String? raw) {
  final trimmed = (raw ?? '').trimLeft();
  if (!trimmed.startsWith(paletteCommandPrefix)) {
    return null;
  }
  return trimmed.substring(paletteCommandPrefix.length).trim();
}

/// The commands matching [query], best first.
///
/// A title beats a keyword, a whole match beats a prefix and a prefix beats a
/// mention anywhere; commands that match the same way keep the order they were
/// declared in, which is the order they read best in. An empty query keeps the
/// whole list as declared. Pure, so the ranking can be tested on its own.
List<PaletteCommand> rankPaletteCommands(
  List<PaletteCommand> commands,
  String query, {
  int limit = 40,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return commands.take(limit).toList(growable: false);
  }

  final scored = <(int, int, PaletteCommand)>[];
  for (var index = 0; index < commands.length; index++) {
    final command = commands[index];
    final rank = _rankOf(command, needle);
    if (rank != null) {
      scored.add((rank, index, command));
    }
  }

  scored.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
  });

  return scored.take(limit).map((entry) => entry.$3).toList(growable: false);
}

int? _rankOf(PaletteCommand command, String needle) {
  final title = command.title.toLowerCase();
  final titleRank = _matchRank(title, needle);
  if (titleRank != null) {
    return titleRank;
  }

  var best = 4;
  var matchedKeyword = false;
  for (final keyword in command.keywords) {
    final rank = _matchRank(keyword.toLowerCase(), needle);
    if (rank != null) {
      matchedKeyword = true;
      best = best < 4 + rank ? best : 4 + rank;
    }
  }
  if (matchedKeyword) {
    return best;
  }

  // "settings ai" should still find "AI settings": every word has to appear
  // somewhere, but not in the order it was typed.
  final haystack = '$title ${command.subtitle.toLowerCase()} '
      '${command.keywords.join(' ').toLowerCase()}';
  final words = needle.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.length > 1 && words.every(haystack.contains)) {
    return 8;
  }
  return null;
}

/// 0 the whole thing, 1 the opening, 2 the start of a word, 3 anywhere.
int? _matchRank(String text, String needle) {
  if (text.isEmpty) {
    return null;
  }
  if (text == needle) {
    return 0;
  }
  final at = text.indexOf(needle);
  if (at < 0) {
    return null;
  }
  if (at == 0) {
    return 1;
  }
  return _startsAWord(text, at) ? 2 : 3;
}

bool _startsAWord(String text, int at) {
  final before = text.codeUnitAt(at - 1);
  return before == 0x20 || // space
      before == 0x2D || // -
      before == 0x5F || // _
      before == 0x2E || // .
      before == 0x2F; // /
}
