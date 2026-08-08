import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/slash_menu_item_builder.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_composer.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/reminder_selector.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

const _keywords = [
  'reminder',
  'remind',
  'remind me',
  'alert',
  'notify',
  'task',
];

/// `/reminder` — opens the composer, then leaves a date mention behind so the
/// page itself shows what was set.
SelectionMenuItem reminderSlashMenuItem = SelectionMenuItem(
  getName: () => LocaleKeys.reminders_slashMenu_name.tr(),
  keywords: _keywords,
  nameBuilder: slashMenuItemNameBuilder,
  handler: (editorState, _, context) async =>
      _insertReminder(editorState, context),
  icon: (_, isSelected, style) => SelectableIconWidget(
    icon: Icons.notifications_rounded,
    isSelected: isSelected,
    style: style,
  ),
);

Future<void> _insertReminder(
  EditorState editorState,
  BuildContext context,
) async {
  // Opening a dialog moves focus off the editor and clears the selection, so
  // it has to be captured before the await.
  final selection = editorState.selection;

  final reminder = await showReminderComposer(
    context,
    kind: ReminderKind.block,
  );
  if (reminder == null || selection == null || !selection.isCollapsed) {
    return;
  }

  final node = editorState.getNodeAtPath(selection.end.path);
  if (node == null || node.delta == null) {
    return;
  }

  final transaction = editorState.transaction
    ..replaceText(
      node,
      selection.start.offset,
      0,
      MentionBlockKeys.mentionChar,
      attributes: MentionBlockKeys.buildMentionDateAttributes(
        date: reminder.scheduledAt.toIso8601String(),
        reminderId: reminder.id,
        reminderOption: ReminderOption.atTimeOfEvent.name,
        includeTime: reminder.includeTime,
      ),
    );
  await editorState.apply(transaction);
}
