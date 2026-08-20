import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// A block type an extension added.
@immutable
class ExtensionBlockDefinition {
  const ExtensionBlockDefinition({
    required this.extensionId,
    required this.type,
    required this.builder,
    this.parser,
    this.slashName,
    this.slashKeywords = const [],
    this.slashIcon = Icons.extension_rounded,
    this.slashDescription = '',
    this.newNode,
    this.alignable = false,
  });

  final String extensionId;

  /// The node type, which is also what is stored in the document.
  final String type;

  /// Built fresh per editor, because a builder carries that editor's
  /// configuration.
  final BlockComponentBuilder Function(
      BlockComponentConfiguration configuration) builder;

  /// How the block is written to and read from markdown. Without one the block
  /// is dropped on export, so it is worth supplying.
  final NodeParser? parser;

  /// The `/` entry that inserts it, when it has one.
  final String? slashName;
  final List<String> slashKeywords;
  final IconData slashIcon;
  final String slashDescription;

  /// A fresh node, for the slash entry.
  final Node Function()? newNode;

  /// Whether the block option menu should offer left / centre / right.
  ///
  /// ⚠️ Only true if the component actually lays itself out with
  /// `blockEmbedAlignment(node)`, or the menu ticks an alignment nothing uses.
  final bool alignable;

  bool get hasSlashEntry => slashName != null && newNode != null;
}

/// Every block type extensions have added.
///
/// ⚠️ `unregister` is not optional here. Without it an extension cannot be
/// turned off without restarting, and a stale builder would keep drawing for a
/// block whose owner is gone.
abstract final class ExtensionBlockRegistry {
  static final Map<String, ExtensionBlockDefinition> _blocks = {};

  /// Bumped whenever the set changes, so an open editor can be rebuilt.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void register(ExtensionBlockDefinition definition) {
    _blocks[definition.type] = definition;
    _raise();
  }

  static void unregister(String type) {
    if (_blocks.remove(type) != null) {
      _raise();
    }
  }

  static void unregisterAll(String extensionId) {
    final doomed = [
      for (final entry in _blocks.entries)
        if (entry.value.extensionId == extensionId) entry.key,
    ];
    if (doomed.isEmpty) {
      return;
    }
    for (final type in doomed) {
      _blocks.remove(type);
    }
    _raise();
  }

  static List<ExtensionBlockDefinition> all() =>
      List.unmodifiable(_blocks.values);

  static ExtensionBlockDefinition? definitionFor(String type) => _blocks[type];

  /// Merged into the editor's own map, so a registered block draws exactly
  /// like a built-in one.
  static Map<String, BlockComponentBuilder> builders(
    BlockComponentConfiguration configuration,
  ) =>
      {
        for (final block in _blocks.values)
          block.type: block.builder(configuration),
      };

  static Map<String, NodeParser> parsers() => {
        for (final block in _blocks.values)
          if (block.parser != null) block.type: block.parser!,
      };

  /// The block types whose components honour the align attribute.
  static Set<String> alignableTypes() => {
        for (final block in _blocks.values)
          if (block.alignable) block.type,
      };

  static void _raise() => revision.value = revision.value + 1;
}

/// Something an extension can be asked to do, from the slash menu or the
/// command palette.
@immutable
class ExtensionCommand {
  const ExtensionCommand({
    required this.extensionId,
    required this.id,
    required this.name,
    required this.run,
    this.description = '',
    this.keywords = const [],
    this.icon = Icons.bolt_rounded,
  });

  final String extensionId;
  final String id;
  final String name;
  final String description;
  final List<String> keywords;
  final IconData icon;
  final Future<void> Function(BuildContext context) run;
}

abstract final class ExtensionCommandRegistry {
  static final Map<String, ExtensionCommand> _commands = {};

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void register(ExtensionCommand command) {
    _commands['${command.extensionId}/${command.id}'] = command;
    revision.value = revision.value + 1;
  }

  static void unregisterAll(String extensionId) {
    final doomed = [
      for (final entry in _commands.entries)
        if (entry.value.extensionId == extensionId) entry.key,
    ];
    if (doomed.isEmpty) {
      return;
    }
    for (final key in doomed) {
      _commands.remove(key);
    }
    revision.value = revision.value + 1;
  }

  static List<ExtensionCommand> all() => List.unmodifiable(_commands.values);
}

/// A whole appearance an extension supplies.
///
/// ⚠️ This is where a Dart extension earns its keep: because it is compiled,
/// a theme can be CODE — a real `ThemeData` with its own surfaces, shaders and
/// backdrop filters. A "glass" theme is achievable here and would not have
/// been in a scripting tier, where a per-widget callback at 120 Hz is
/// impossible.
@immutable
class ExtensionTheme {
  const ExtensionTheme({
    required this.extensionId,
    required this.id,
    required this.name,
    required this.brightness,
    required this.build,
  });

  final String extensionId;
  final String id;
  final String name;
  final Brightness brightness;

  /// Given the theme the app would otherwise use, return the one to use.
  /// Rewriting `PremiumThemeExtension` and `PaperThemeExtension` is what makes
  /// every surface in the app follow along.
  final ThemeData Function(ThemeData base) build;
}

abstract final class ExtensionThemeRegistry {
  static final Map<String, ExtensionTheme> _themes = {};

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// `<extensionId>/<themeId>`, or empty for "use AppFlowy's own theme".
  static final ValueNotifier<String> selected = ValueNotifier<String>('');

  /// Fires when the chosen theme changes or the set of themes does, so whoever
  /// builds `MaterialApp` can rebuild.
  static final Listenable changes = Listenable.merge([revision, selected]);

  static void register(ExtensionTheme theme) {
    _themes['${theme.extensionId}/${theme.id}'] = theme;
    revision.value = revision.value + 1;
  }

  static void unregisterAll(String extensionId) {
    final doomed = [
      for (final entry in _themes.entries)
        if (entry.value.extensionId == extensionId) entry.key,
    ];
    if (doomed.isEmpty) {
      return;
    }
    for (final key in doomed) {
      _themes.remove(key);
    }
    revision.value = revision.value + 1;
  }

  static List<ExtensionTheme> all() => List.unmodifiable(_themes.values);

  static ExtensionTheme? byKey(String key) => _themes[key];

  static String keyOf(ExtensionTheme theme) =>
      '${theme.extensionId}/${theme.id}';

  /// The chosen theme laid over [base], or [base] itself.
  ///
  /// Returns [base] unchanged when nothing is chosen, when the chosen theme's
  /// extension has since been turned off, or when the theme is for the other
  /// brightness — a dark theme forced onto a light app fights every surface.
  static ThemeData apply(ThemeData base, Brightness brightness) {
    final theme = _themes[selected.value];
    if (theme == null || theme.brightness != brightness) {
      return base;
    }
    try {
      return theme.build(base);
    } on Object catch (error, stack) {
      // ⚠️ A theme that throws must not take the whole app down: there would be
      // no UI left to turn the extension off with.
      debugPrint('Extension theme ${selected.value} failed to build: $error');
      debugPrintStack(stackTrace: stack);
      return base;
    }
  }
}

/// A new way of reading a table, supplied by an extension.
///
/// ⚠️ This is deliberately a *table view*, not a new page type. `ViewLayoutPB`
/// is a protobuf enum owned by the Rust backend, so a genuinely new page kind
/// cannot be added from Dart at all — the server would reject the layout code.
/// A table view is the extensible seam: it rides on an existing Grid and lives
/// entirely in the view's `extra` JSON, which the backend never interprets.
/// Timeline, feed, form, gallery and mailbox are all built with the same trick.
@immutable
class ExtensionTableView {
  const ExtensionTableView({
    required this.extensionId,
    required this.id,
    required this.name,
    required this.buildTabBar,
    this.icon = Icons.table_chart_rounded,
  });

  final String extensionId;
  final String id;
  final String name;
  final IconData icon;

  /// Built fresh each time, because a builder may hold per-view resources it
  /// disposes of.
  final DatabaseTabBarItemBuilder Function() buildTabBar;

  /// Namespaced so an extension can never collide with a built-in envelope or
  /// with another extension.
  String get envelopeKey => 'ext.$extensionId.$id';
}

abstract final class ExtensionTableViewRegistry {
  static final Map<String, ExtensionTableView> _views = {};

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void register(ExtensionTableView view) {
    _views[view.envelopeKey] = view;
    revision.value = revision.value + 1;
  }

  static void unregisterAll(String extensionId) {
    final doomed = [
      for (final entry in _views.entries)
        if (entry.value.extensionId == extensionId) entry.key,
    ];
    if (doomed.isEmpty) {
      return;
    }
    for (final key in doomed) {
      _views.remove(key);
    }
    revision.value = revision.value + 1;
  }

  static List<ExtensionTableView> all() => List.unmodifiable(_views.values);

  static ExtensionTableView? byEnvelopeKey(String key) => _views[key];

  static Iterable<String> envelopeKeys() => _views.keys;
}
