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
  templates,
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
    this.argument = '',
    this.askAI,
  });

  /// What was typed after the command prefix, with no leading `>`.
  final String query;

  /// What followed the command's own name, for a command that takes one:
  /// "Meeting notes" from "new page Meeting notes". Empty otherwise.
  final String argument;

  /// Closes the palette. A command that opens a route of its own must call
  /// this first, or popping afterwards would close that route instead.
  final VoidCallback dismiss;

  /// Turns the palette into a conversation and asks [question] there, when
  /// the palette can hold one. Null where it cannot.
  final void Function(String question)? askAI;
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
    this.takesArgument = false,
    this.argumentPhrases = const <String>[],
    this.searchOnly = false,
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

  /// Whether words typed after the command's name are handed to it, the way
  /// "new page Meeting notes" names the page it creates.
  final bool takesArgument;

  /// Other ways of starting the command when it takes an argument, besides
  /// its title: "create page" and "add page" lead to "New page" too.
  final List<String> argumentPhrases;

  /// Whether the command waits to be searched for instead of being listed
  /// before anything is typed. The long tail — every file type, every
  /// template — would otherwise bury the commands people reach for.
  final bool searchOnly;

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

/// What follows [command]'s name in [query] when the command takes an
/// argument: "Meeting notes" from "new page Meeting notes". Null when the
/// command takes none, or nothing but its name was typed.
///
/// The name has to be followed by a space or a colon, so "new pages" is not
/// "New page" called "s".
String? paletteCommandArgument(PaletteCommand command, String query) {
  if (!command.takesArgument) {
    return null;
  }
  final typed = query.trimLeft();
  for (final phrase in [command.title, ...command.argumentPhrases]) {
    final lead = phrase.trim().toLowerCase();
    if (lead.isEmpty || typed.length <= lead.length) {
      continue;
    }
    if (typed.substring(0, lead.length).toLowerCase() != lead) {
      continue;
    }
    final separator = typed.codeUnitAt(lead.length);
    if (separator != 0x20 && separator != 0x3A) {
      continue;
    }
    final argument = typed.substring(lead.length + 1).trim();
    if (argument.isNotEmpty) {
      return argument;
    }
  }
  return null;
}

/// The commands matching [query], best first.
///
/// A title beats a keyword, a whole match beats a prefix and a prefix beats a
/// mention anywhere; commands that match the same way keep the order they were
/// declared in, which is the order they read best in. An empty query keeps the
/// whole list as declared, apart from the [PaletteCommand.searchOnly] ones. A
/// command that was named and then handed an argument ("new page Ideas") is
/// as good a match as there is. Pure, so the ranking can be tested on its own.
List<PaletteCommand> rankPaletteCommands(
  List<PaletteCommand> commands,
  String query, {
  int limit = 40,
}) {
  if (query.trim().isEmpty) {
    return commands
        .where((command) => !command.searchOnly)
        .take(limit)
        .toList(growable: false);
  }
  return rankPaletteMatches(
    commands,
    query,
    limit: limit,
    title: (command) => command.title,
    subtitle: (command) => command.subtitle,
    keywords: (command) => command.keywords,
    boost: (command) =>
        paletteCommandArgument(command, query) == null ? null : 0,
  );
}

/// [items] matching [query], best first, judged the way commands are: by
/// [title], then by [keywords], then by every typed word appearing somewhere
/// in the title, [subtitle] or keywords. [boost] may claim a rank of its own
/// for an item, which wins when it is better.
///
/// Items that match equally keep their given order; an empty query keeps them
/// all, as given.
List<T> rankPaletteMatches<T>(
  List<T> items,
  String query, {
  required String Function(T item) title,
  String Function(T item)? subtitle,
  Iterable<String> Function(T item)? keywords,
  int? Function(T item)? boost,
  int limit = 40,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return items.take(limit).toList(growable: false);
  }

  final scored = <(int, int, T)>[];
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final matched = paletteMatchRank(
      needle,
      title: title(item),
      subtitle: subtitle?.call(item) ?? '',
      keywords: keywords?.call(item) ?? const <String>[],
    );
    final boosted = boost?.call(item);
    final rank = matched == null
        ? boosted
        : boosted == null || matched <= boosted
            ? matched
            : boosted;
    if (rank != null) {
      scored.add((rank, index, item));
    }
  }

  scored.sort((a, b) {
    final byRank = a.$1.compareTo(b.$1);
    return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
  });

  return scored.take(limit).map((entry) => entry.$3).toList(growable: false);
}

/// How well the lower-cased [needle] names something called [title]. Lower is
/// better: 0–3 for the title, 4–7 for a keyword, 8 for every word appearing
/// somewhere. Null when it does not match at all.
int? paletteMatchRank(
  String needle, {
  required String title,
  String subtitle = '',
  Iterable<String> keywords = const <String>[],
}) {
  final lowerTitle = title.toLowerCase();
  final titleRank = _matchRank(lowerTitle, needle);
  if (titleRank != null) {
    return titleRank;
  }

  var best = 4;
  var matchedKeyword = false;
  for (final keyword in keywords) {
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
  final haystack = '$lowerTitle ${subtitle.toLowerCase()} '
      '${keywords.join(' ').toLowerCase()}';
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
