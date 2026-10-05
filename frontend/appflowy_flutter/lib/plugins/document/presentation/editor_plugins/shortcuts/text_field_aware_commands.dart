import 'package:appflowy/plugins/document/presentation/editor_plugins/base/cover_title_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shortcuts/command_shortcuts.dart';
import 'package:appflowy/shared/text_field_focus.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// An editor command that stands aside while a text field inside the editor
/// has the keyboard.
///
/// The editor's key handlers sit above every block. Without this, Backspace in
/// a field inside a block deletes from the page — or deletes the whole block —
/// and Ctrl+V pastes into the page instead of the field.
///
/// Everything but the handler is the wrapped command's own, so a shortcut
/// customized in settings still applies.
class TextFieldAwareCommand extends CommandShortcutEvent {
  TextFieldAwareCommand(this.inner)
      : super(
          key: inner.key,
          command: inner.command,
          getDescription: () => inner.description ?? '',
          handler: (editorState) => textFieldHasFocus()
              ? KeyEventResult.ignored
              : inner.handler(editorState),
        );

  final CommandShortcutEvent inner;

  @override
  String get command => inner.command;

  @override
  set command(String value) => inner.command = value;

  @override
  List<Keybinding> get keybindings => inner.keybindings;

  @override
  void updateCommand({
    String? command,
    String? windowsCommand,
    String? macOSCommand,
    String? linuxCommand,
  }) =>
      inner.updateCommand(
        command: command,
        windowsCommand: windowsCommand,
        macOSCommand: macOSCommand,
        linuxCommand: linuxCommand,
      );

  @override
  void clearCommand() => inner.clearCommand();

  @override
  bool canRespondToRawKeyEvent(KeyEvent event) =>
      inner.canRespondToRawKeyEvent(event);
}

/// [events], each standing aside while a text field inside the editor has the
/// keyboard.
List<CommandShortcutEvent> standAsideForTextFields(
  Iterable<CommandShortcutEvent> events,
) =>
    [
      for (final event in events)
        event is TextFieldAwareCommand ? event : TextFieldAwareCommand(event),
    ];

/// The page's own commands, for blocks shown outside a page — on a canvas or a
/// dashboard — so they copy, paste, undo and delete the way they do in one.
///
/// The commands that move the caret up into a page's title are left out: the
/// blocks have no title, and inside a page they would reach for its title.
List<CommandShortcutEvent> embeddedBlocksCommandShortcuts() =>
    standAsideForTextFields(
      commandShortcutEvents.where(
        (event) =>
            event != backspaceToTitle &&
            event != arrowUpToTitle &&
            event != arrowLeftToTitle,
      ),
    );
