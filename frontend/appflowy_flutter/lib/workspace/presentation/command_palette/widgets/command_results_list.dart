import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/command_palette/palette_scope.dart';
import 'package:appflowy/workspace/presentation/command_palette/palette_commands.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_row_surface.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The heading that names a section of the palette. Matches the one the search
/// results and the recent list already use.
class CommandPaletteSectionHeader extends StatelessWidget {
  const CommandPaletteSectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: theme.spacing.s,
        horizontal: theme.spacing.m,
      ),
      child: Text(
        label,
        style: theme.textStyle.body
            .enhanced(color: theme.textColorScheme.secondary)
            .copyWith(letterSpacing: 0.2, height: 22 / 16),
      ),
    );
  }
}

/// The commands themselves, optionally split into their groups.
///
/// Used twice: as the whole body while the palette is in command mode, and as
/// one short section above the pages an ordinary search found.
class CommandResultsList extends StatelessWidget {
  const CommandResultsList({
    super.key,
    required this.commands,
    required this.onRun,
    this.grouped = true,
    this.sectionLabel,
    this.highlightFirst = false,
    this.query = '',
  });

  final List<PaletteCommand> commands;
  final ValueChanged<PaletteCommand> onRun;

  /// Whether each group gets its own heading, or the whole list gets one.
  final bool grouped;
  final String? sectionLabel;

  /// Marks the command Enter would run while the caret is still in the box.
  final bool highlightFirst;

  /// What was typed, so a command handed an argument can show it.
  final String query;

  @override
  Widget build(BuildContext context) {
    if (commands.isEmpty) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];
    if (grouped) {
      PaletteCommandGroup? previous;
      for (final command in commands) {
        if (command.group != previous) {
          previous = command.group;
          children.add(
            CommandPaletteSectionHeader(
              label: paletteCommandGroupLabel(command.group),
            ),
          );
        }
        children.add(_cell(command, command == commands.first));
      }
    } else {
      children.add(
        CommandPaletteSectionHeader(
          label: sectionLabel ?? LocaleKeys.commandPalette_commands.tr(),
        ),
      );
      for (final command in commands) {
        children.add(_cell(command, command == commands.first));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _cell(PaletteCommand command, bool isFirst) => PaletteCommandCell(
        key: ValueKey(command.id),
        command: command,
        argument: paletteCommandArgument(command, query) ?? '',
        preselected: highlightFirst && isFirst,
        onRun: () => onRun(command),
      );
}

/// The whole body of the palette while it is in command mode: the commands in
/// their groups, inside the same scroll chrome the other lists use.
class CommandPalettePanel extends StatefulWidget {
  const CommandPalettePanel({
    super.key,
    required this.commands,
    required this.onRun,
    this.query = '',
  });

  final List<PaletteCommand> commands;
  final ValueChanged<PaletteCommand> onRun;
  final String query;

  @override
  State<CommandPalettePanel> createState() => _CommandPalettePanelState();
}

class _CommandPalettePanelState extends State<CommandPalettePanel> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    if (widget.commands.isEmpty) {
      return const NoCommandsHint();
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      // While the caret is still in the search box the first command is the one
      // Enter would run, so it is the one that looks picked.
      onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
      child: ScrollControllerBuilder(
        builder: (context, controller) => FlowyScrollbar(
          controller: controller,
          thumbVisibility: false,
          child: SingleChildScrollView(
            controller: controller,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CommandResultsList(
                    commands: widget.commands,
                    onRun: widget.onRun,
                    highlightFirst: !_hasFocus,
                    query: widget.query,
                  ),
                  const VSpace(16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One command row. Shaped exactly like a recent page row so the palette keeps
/// one rhythm whatever it is listing.
class PaletteCommandCell extends StatefulWidget {
  const PaletteCommandCell({
    super.key,
    required this.command,
    required this.onRun,
    this.preselected = false,
    this.argument = '',
  });

  final PaletteCommand command;
  final VoidCallback onRun;
  final bool preselected;

  /// What the command will be handed, such as the name of the page it makes.
  final String argument;

  @override
  State<PaletteCommandCell> createState() => _PaletteCommandCellState();
}

class _PaletteCommandCellState extends State<PaletteCommandCell> {
  final focusNode = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final command = widget.command;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onRun,
      child: Focus(
        focusNode: focusNode,
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            widget.onRun();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: PaletteRowSurface(
          active: _focused || widget.preselected,
          child: Padding(
            padding: EdgeInsets.all(theme.spacing.l),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: Center(
                    child: WorkspaceGlyph(
                      command.icon,
                      color: theme.iconColorScheme.secondary,
                    ),
                  ),
                ),
                const HSpace(8),
                Flexible(
                  child: Text(
                    command.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textStyle.body
                        .enhanced(color: theme.textColorScheme.primary)
                        .copyWith(height: 22 / 14),
                  ),
                ),
                if (widget.argument.isNotEmpty) ...[
                  const HSpace(6),
                  Flexible(
                    child: Text(
                      '\u201c${widget.argument}\u201d',
                      key: const ValueKey('command-palette-command-argument'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyle.body
                          .enhanced(
                            color: WorkspacePalette.of(context).accent,
                          )
                          .copyWith(height: 22 / 14),
                    ),
                  ),
                ],
                if (command.subtitle.isNotEmpty && widget.argument.isEmpty) ...[
                  const HSpace(8),
                  Flexible(
                    child: Text(
                      command.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyle.caption
                          .standard(color: theme.textColorScheme.tertiary),
                    ),
                  ),
                ],
                if (command.shortcut.isNotEmpty) ...[
                  const HSpace(8),
                  Text(
                    command.shortcut,
                    style: theme.textStyle.caption
                        .standard(color: theme.textColorScheme.tertiary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the command query matches nothing.
class NoCommandsHint extends StatelessWidget {
  const NoCommandsHint({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceGlyph(
            Icons.terminal_rounded,
            size: 24,
            color: theme.iconColorScheme.secondary,
          ),
          const VSpace(8),
          Text(
            LocaleKeys.commandPalette_noCommandsHint.tr(),
            style: theme.textStyle.body
                .enhanced(color: theme.textColorScheme.secondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// What the keys do in each of the palette's modes.
enum PaletteHintMode { search, commands, settings, picker, ai }

/// The quiet line along the bottom of the palette that says what the keys do —
/// and, above all, that `>` and `?` exist at all.
class CommandPaletteHintBar extends StatelessWidget {
  const CommandPaletteHintBar({
    super.key,
    required this.commandMode,
    this.mode,
  });

  final bool commandMode;

  /// Overrides [commandMode] when set.
  final PaletteHintMode? mode;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final style =
        theme.textStyle.caption.standard(color: theme.textColorScheme.tertiary);
    final keyStyle = theme.textStyle.caption
        .enhanced(color: theme.textColorScheme.secondary);
    final mode = this.mode ??
        (commandMode ? PaletteHintMode.commands : PaletteHintMode.search);

    final hints = <(String, String)>[
      if (mode != PaletteHintMode.ai)
        ('\u2191\u2193', LocaleKeys.commandPalette_hintNavigate.tr()),
      (
        '\u21b5',
        switch (mode) {
          PaletteHintMode.search => LocaleKeys.commandPalette_hintOpen.tr(),
          PaletteHintMode.commands => LocaleKeys.commandPalette_hintRun.tr(),
          PaletteHintMode.settings => LocaleKeys.commandPalette_hintChange.tr(),
          PaletteHintMode.picker => LocaleKeys.commandPalette_hintChoose.tr(),
          PaletteHintMode.ai => LocaleKeys.commandPalette_hintAsk.tr(),
        },
      ),
      if (mode == PaletteHintMode.settings)
        ('\u2190\u2192', LocaleKeys.commandPalette_hintAdjust.tr()),
      if (mode == PaletteHintMode.search)
        ('Tab', LocaleKeys.commandPalette_hintAskAI.tr()),
      if (mode == PaletteHintMode.picker || mode == PaletteHintMode.ai)
        ('\u232b', LocaleKeys.commandPalette_hintBack.tr()),
      if (mode == PaletteHintMode.search) ...[
        (paletteCommandPrefix, LocaleKeys.commandPalette_hintCommands.tr()),
        (paletteAskPrefix, LocaleKeys.commandPalette_hintQuestion.tr()),
      ],
    ];

    return Padding(
      padding: EdgeInsets.only(
        top: theme.spacing.s,
        bottom: theme.spacing.m,
        left: theme.spacing.m,
        right: theme.spacing.m,
      ),
      // Wraps rather than overflowing when the palette is narrow or the text
      // is large; every hint stays readable, none is cut off.
      child: Wrap(
        spacing: 12,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (key, label) in hints)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(key, style: keyStyle),
                const HSpace(4),
                Text(label, style: style),
              ],
            ),
        ],
      ),
    );
  }
}
