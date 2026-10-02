import 'package:appflowy/workspace/application/command_palette/palette_command.dart';

/// The prefix that turns the search box into a question for the assistant,
/// the way `>` turns it into a list of commands.
const paletteAskPrefix = '?';

/// Which part of the palette is being searched. The order is the order the
/// scopes are offered in.
enum PaletteScope {
  /// Pages, commands and settings together, best first.
  all,
  pages,
  commands,
  settings,
  extensions,

  /// A conversation with the assistant instead of a search.
  ai;

  /// Whether the workspace's pages are searched in this scope.
  bool get searchesPages => this == all || this == pages;

  /// Whether typing a prefix may move the palette out of this scope. Inside a
  /// scope that was chosen on purpose, `>` and `?` are only characters.
  bool get acceptsPrefixes => this == all || this == pages;
}

/// What the palette was asked: the part of it, and the words to look for.
class PaletteQuery {
  const PaletteQuery(this.scope, this.text, {this.fromPrefix = false});

  final PaletteScope scope;

  /// The words without any prefix or surrounding spaces.
  final String text;

  /// Whether [scope] came from a typed prefix rather than a chosen scope, so
  /// deleting the prefix returns to where the palette was.
  final bool fromPrefix;

  bool get isEmpty => text.trim().isEmpty;
}

/// The question carried by [raw] when it starts with [paletteAskPrefix], or
/// null when [raw] is something else.
String? paletteAskQuery(String? raw) {
  final trimmed = (raw ?? '').trimLeft();
  if (!trimmed.startsWith(paletteAskPrefix)) {
    return null;
  }
  return trimmed.substring(paletteAskPrefix.length).trim();
}

/// Whether [raw] is answered by the palette itself, with no search of the
/// workspace: a command or a question.
bool isPaletteLocalQuery(String? raw) =>
    paletteCommandModeQuery(raw) != null || paletteAskQuery(raw) != null;

/// Reads [raw] as typed into a palette showing [selected].
///
/// Prefixes only apply where a search is open to them; a scope chosen on
/// purpose keeps everything typed into it.
PaletteQuery parsePaletteQuery(
  String raw, {
  PaletteScope selected = PaletteScope.all,
}) {
  if (selected.acceptsPrefixes) {
    final command = paletteCommandModeQuery(raw);
    if (command != null) {
      return PaletteQuery(PaletteScope.commands, command, fromPrefix: true);
    }
    final question = paletteAskQuery(raw);
    if (question != null) {
      return PaletteQuery(PaletteScope.ai, question, fromPrefix: true);
    }
  }
  return PaletteQuery(selected, raw.trim());
}
