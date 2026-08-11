import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_composer.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class ReminderBlockKeys {
  const ReminderBlockKeys._();

  static const String type = 'interactive_reminder';

  /// The id of the reminder in the workspace's own reminder store.
  ///
  /// The block holds nothing else: a reminder belongs to the workspace, so
  /// the calendar, the timeline and the notification scheduler already see it.
  static const String reminderId = 'reminder_id';
}

Node reminderBlockNode({String reminderId = ''}) => Node(
      type: ReminderBlockKeys.type,
      attributes: {
        ReminderBlockKeys.reminderId: reminderId,
        InteractiveBlockKeys.size: InteractiveSize.medium.name,
      },
    );

class ReminderBlockComponentBuilder extends BlockComponentBuilder {
  ReminderBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ReminderBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class ReminderBlockComponent extends BlockComponentStatefulWidget {
  const ReminderBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<ReminderBlockComponent> createState() => ReminderBlockComponentState();
}

class ReminderBlockComponentState extends State<ReminderBlockComponent>
    with BlockComponentConfigurable, InteractiveBlockMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final ReminderStore _store = ReminderStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onRemindersChanged);
    _store.start();
  }

  @override
  void dispose() {
    _store.removeListener(_onRemindersChanged);
    super.dispose();
  }

  void _onRemindersChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  AppReminder? get _reminder {
    final id = stringAttribute(ReminderBlockKeys.reminderId);
    return id.isEmpty ? null : _store.byId(id);
  }

  /// Opens the composer. `/reminder` calls it so the block lands ready.
  Future<void> compose() async {
    final existing = _reminder;
    final created = await showReminderComposer(
      context,
      initialText: existing?.title ?? '',
      kind: ReminderKind.block,
    );
    if (created == null) {
      return;
    }
    if (existing != null && existing.id != created.id) {
      await _store.remove(existing.id);
    }
    await writeAttributes({ReminderBlockKeys.reminderId: created.id});
  }

  Future<void> _toggleDone(AppReminder reminder) async {
    await _store.save(
      reminder.isDone
          ? reminder.copyWith(isDone: false)
          : reminder.complete(),
    );
  }

  Future<void> _snooze(AppReminder reminder, SnoozeOption option) =>
      _store.save(reminder.snooze(option));

  Future<void> _detach(AppReminder reminder) async {
    await _store.remove(reminder.id);
    await writeAttributes({ReminderBlockKeys.reminderId: ''});
  }

  List<AppMenuEntry> _menu() {
    final reminder = _reminder;
    return interactiveMenuEntries(
      showAccent: false,
      extra: [
        AppMenuItem(
          label: reminder == null
              ? LocaleKeys.interactive_reminder_set.tr()
              : LocaleKeys.interactive_reminder_edit.tr(),
          icon: Icons.event_rounded,
          enabled: editable,
          onSelected: () => unawaited(compose()),
        ),
        if (reminder != null) ...[
          AppMenuItem(
            label: reminder.isDone
                ? LocaleKeys.interactive_reminder_markUndone.tr()
                : LocaleKeys.interactive_reminder_markDone.tr(),
            icon: reminder.isDone
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            onSelected: () => unawaited(_toggleDone(reminder)),
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_reminder_snooze.tr(),
            icon: Icons.snooze_rounded,
            submenu: [
              for (final option in SnoozeOption.values)
                if (option != SnoozeOption.custom)
                  AppMenuItem(
                    label: _snoozeLabel(option),
                    onSelected: () => unawaited(_snooze(reminder, option)),
                  ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_reminder_remove.tr(),
            icon: Icons.notifications_off_rounded,
            enabled: editable,
            onSelected: () => unawaited(_detach(reminder)),
          ),
        ],
      ],
    );
  }

  static String _snoozeLabel(SnoozeOption option) => switch (option) {
        SnoozeOption.fiveMinutes =>
          LocaleKeys.interactive_reminder_snooze5.tr(),
        SnoozeOption.tenMinutes =>
          LocaleKeys.interactive_reminder_snooze10.tr(),
        SnoozeOption.thirtyMinutes =>
          LocaleKeys.interactive_reminder_snooze30.tr(),
        SnoozeOption.oneHour => LocaleKeys.interactive_reminder_snooze60.tr(),
        SnoozeOption.tomorrow =>
          LocaleKeys.interactive_reminder_snoozeTomorrow.tr(),
        SnoozeOption.custom => '',
      };

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final reminder = _reminder;

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: InteractiveBlockShell(
        node: node,
        size: blockSize,
        semanticsLabel: LocaleKeys.interactive_reminder_name.tr(),
        menuBuilder: _menu,
        child: reminder == null
            ? _buildEmpty(palette)
            : _buildReminder(palette, reminder),
      ),
    );
  }

  Widget _buildEmpty(InteractivePalette palette) {
    return _Card(
      palette: palette,
      accent: palette.textMuted,
      onTap: editable ? () => unawaited(compose()) : null,
      child: Row(
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 18,
            color: palette.textMuted,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              LocaleKeys.interactive_reminder_empty.tr(),
              style: InteractiveType.body(palette)
                  .copyWith(color: palette.textMuted),
            ),
          ),
          Icon(Icons.add_rounded, size: 17, color: palette.textMuted),
        ],
      ),
    );
  }

  Widget _buildReminder(InteractivePalette palette, AppReminder reminder) {
    final overdue = !reminder.isDone &&
        reminder.firesAt.isBefore(DateTime.now());
    final tone = (overdue ? InteractiveAccent.red : InteractiveAccent.blue)
        .resolve(palette);

    return _Card(
      palette: palette,
      accent: reminder.isDone ? palette.textMuted : tone.strong,
      onTap: editable ? () => unawaited(compose()) : null,
      child: Row(
        children: [
          _DoneBox(
            done: reminder.isDone,
            accent: tone.strong,
            palette: palette,
            onTap: () => unawaited(_toggleDone(reminder)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reminder.title.isEmpty
                      ? LocaleKeys.interactive_reminder_untitled.tr()
                      : reminder.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: InteractiveType.strong(palette, size: 13.5).copyWith(
                    decoration:
                        reminder.isDone ? TextDecoration.lineThrough : null,
                    color: reminder.isDone ? palette.textMuted : palette.text,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      reminder.isSnoozed
                          ? Icons.snooze_rounded
                          : Icons.schedule_rounded,
                      size: 12,
                      color: overdue ? tone.strong : palette.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        formatReminderMoment(reminder),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: InteractiveType.caption(palette).copyWith(
                          color: overdue ? tone.strong : palette.textMuted,
                        ),
                      ),
                    ),
                    if (reminder.recurrence.repeats) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.repeat_rounded,
                        size: 12,
                        color: palette.textMuted,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InteractiveIconButton(
            icon: Icons.snooze_rounded,
            tooltip: LocaleKeys.interactive_reminder_snooze.tr(),
            palette: palette,
            iconSize: 15,
            onPressed: reminder.isDone
                ? null
                : () => unawaited(_snooze(reminder, SnoozeOption.tenMinutes)),
          ),
        ],
      ),
    );
  }
}

/// "Tomorrow · 10:00", "Overdue · 3 Aug", "In 2 hours".
///
/// Pure, so the wording can be tested without a reminder store.
String formatReminderMoment(AppReminder reminder, {DateTime? now}) {
  final at = reminder.firesAt;
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final startOfDay = DateTime(at.year, at.month, at.day);
  final days = startOfDay.difference(startOfToday).inDays;

  final time = reminder.includeTime
      ? '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}'
      : '';

  final day = switch (days) {
    0 => LocaleKeys.interactive_reminder_today.tr(),
    1 => LocaleKeys.interactive_reminder_tomorrow.tr(),
    -1 => LocaleKeys.interactive_reminder_yesterday.tr(),
    _ => '${at.day} ${_month(at.month)}'
        '${at.year == today.year ? '' : ' ${at.year}'}',
  };

  return time.isEmpty ? day : '$day · $time';
}

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _month(int month) => _months[(month - 1).clamp(0, 11)];

class _Card extends StatelessWidget {
  const _Card({
    required this.palette,
    required this.accent,
    required this.child,
    this.onTap,
  });

  final InteractivePalette palette;
  final Color accent;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget body = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(InteractiveMetrics.blockRadius),
        border: Border.all(color: palette.border.withValues(alpha: 0.36)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isDark ? 0.28 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -12,
          ),
        ],
      ),
      child: child,
    );

    body = Stack(
      children: [
        body,
        Positioned(
          left: 0,
          top: 10,
          bottom: 10,
          child: Container(
            width: 3,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.85),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );

    if (onTap == null) {
      return body;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onDoubleTap: onTap,
        child: body,
      ),
    );
  }
}

class _DoneBox extends StatelessWidget {
  const _DoneBox({
    required this.done,
    required this.accent,
    required this.palette,
    required this.onTap,
  });

  final bool done;
  final Color accent;
  final InteractivePalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: done,
      label: LocaleKeys.interactive_reminder_markDone.tr(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: InteractiveMetrics.hover,
            curve: InteractiveMetrics.curve,
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              color: done ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: done ? accent : palette.border.withValues(alpha: 0.65),
                width: 1.5,
              ),
            ),
            child: done
                ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
