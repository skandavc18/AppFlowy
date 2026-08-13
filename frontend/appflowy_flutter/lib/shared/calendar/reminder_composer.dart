import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_parser.dart';
import 'package:appflowy/shared/calendar/reminder_google_sync.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Make a reminder out of ordinary words, and show what was understood.
///
/// Nothing is ever saved from a guess alone: the parsed date is shown as an
/// editable field, so a wrong reading is a visible one.
Future<AppReminder?> showReminderComposer(
  BuildContext context, {
  String initialText = '',
  String pageId = '',
  String objectId = '',
  ReminderKind kind = ReminderKind.standalone,
  DateTime? initialWhen,
  bool initialHasTime = true,
}) =>
    showDialog<AppReminder>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) => _ReminderComposer(
        initialText: initialText,
        pageId: pageId,
        objectId: objectId,
        kind: kind,
        initialWhen: initialWhen,
        initialHasTime: initialHasTime,
      ),
    );

class _ReminderComposer extends StatefulWidget {
  const _ReminderComposer({
    required this.initialText,
    required this.pageId,
    required this.objectId,
    required this.kind,
    this.initialWhen,
    this.initialHasTime = true,
  });

  final String initialText;
  final String pageId;
  final String objectId;
  final ReminderKind kind;

  /// The moment the composer opens on — a day clicked in a calendar, rather
  /// than a date the person has to say again in words.
  final DateTime? initialWhen;
  final bool initialHasTime;

  @override
  State<_ReminderComposer> createState() => _ReminderComposerState();
}

class _ReminderComposerState extends State<_ReminderComposer> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initialText);

  late ParsedReminder _parsed;
  DateTime? _when;
  bool _hasTime = true;
  CalendarRecurrence _recurrence = CalendarRecurrence.none;
  ReminderPriority _priority = ReminderPriority.none;
  bool _playsSound = true;
  bool _saving = false;

  /// Only offered once an account that can take an event is connected.
  bool _googleAvailable = false;
  bool _syncToGoogle = false;

  @override
  void initState() {
    super.initState();
    _reparse(widget.initialText, adopt: true);
    final when = widget.initialWhen;
    if (when != null) {
      _when = when;
      _hasTime = widget.initialHasTime;
    }
    unawaited(_checkGoogle());
  }

  Future<void> _checkGoogle() async {
    final available = await ReminderGoogleSync.canWrite();
    if (mounted && available) {
      setState(() => _googleAvailable = true);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Re-read the line. [adopt] takes what was found; without it the date the
  /// person has already adjusted by hand is left alone.
  void _reparse(String value, {bool adopt = false}) {
    final parsed = parseReminderText(value);
    setState(() {
      _parsed = parsed;
      if (adopt || _when == null) {
        _when = parsed.when;
        _hasTime = parsed.hasTime;
        if (parsed.recurrence.repeats) {
          _recurrence = parsed.recurrence;
        }
      }
    });
  }

  String get _title =>
      _parsed.title.trim().isEmpty ? _text.text.trim() : _parsed.title.trim();

  bool get _canSave => _title.isNotEmpty && _when != null && !_saving;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: palette.cardShadow(lift: 4),
          ),
          padding: const EdgeInsets.all(CalendarMetrics.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.notifications_rounded,
                    size: 18,
                    color: palette.accent,
                  ),
                  const SizedBox(width: CalendarMetrics.space2),
                  Text(
                    LocaleKeys.reminders_newReminder.tr(),
                    style: TextStyle(
                      fontSize: 15,
                      height: 1,
                      letterSpacing: -0.2,
                      color: palette.textPrimary,
                      fontVariations: const [FontVariation.weight(660)],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CalendarMetrics.space4),
              _Field(
                controller: _text,
                hint: LocaleKeys.reminders_titleHint.tr(),
                helper: LocaleKeys.reminders_quickHint.tr(),
                autofocus: true,
                onChanged: (value) => _reparse(value, adopt: true),
                onSubmitted: (_) => _canSave ? _save() : null,
              ),
              const SizedBox(height: CalendarMetrics.space4),
              _ReadAs(
                parsed: _parsed,
                when: _when,
                hasTime: _hasTime,
              ),
              const SizedBox(height: CalendarMetrics.space4),
              Row(
                children: [
                  Expanded(
                    child: _PickerButton(
                      icon: Icons.calendar_today_rounded,
                      label: _when == null
                          ? LocaleKeys.reminders_noDate.tr()
                          : DateFormat.yMMMEd().format(_when!),
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: CalendarMetrics.space2),
                  Expanded(
                    child: _PickerButton(
                      icon: Icons.schedule_rounded,
                      label: _hasTime && _when != null
                          ? TimeOfDay.fromDateTime(_when!).format(context)
                          : LocaleKeys.reminders_allDay.tr(),
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CalendarMetrics.space2),
              Row(
                children: [
                  Expanded(
                    child: _ChoiceButton<CalendarRecurrenceKind>(
                      icon: Icons.repeat_rounded,
                      value: _recurrence.kind,
                      label: _repeatLabel(_recurrence.kind),
                      options: CalendarRecurrenceKind.values
                          .where((k) => k != CalendarRecurrenceKind.custom)
                          .toList(),
                      labelOf: _repeatLabel,
                      onChanged: (kind) => setState(
                        () => _recurrence = CalendarRecurrence(kind: kind),
                      ),
                    ),
                  ),
                  const SizedBox(width: CalendarMetrics.space2),
                  Expanded(
                    child: _ChoiceButton<ReminderPriority>(
                      icon: Icons.flag_rounded,
                      value: _priority,
                      label: _priorityLabel(_priority),
                      options: ReminderPriority.values,
                      labelOf: _priorityLabel,
                      onChanged: (value) => setState(() => _priority = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CalendarMetrics.space3),
              _SoundToggle(
                value: _playsSound,
                onChanged: (value) => setState(() => _playsSound = value),
              ),
              if (_googleAvailable) ...[
                const SizedBox(height: CalendarMetrics.space2),
                _ToggleRow(
                  icon: Icons.calendar_month_rounded,
                  label: LocaleKeys.reminders_syncToGoogle.tr(),
                  value: _syncToGoogle,
                  onChanged: (value) => setState(() => _syncToGoogle = value),
                ),
              ],
              const SizedBox(height: CalendarMetrics.space5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _TextButton(
                    label: LocaleKeys.reminders_cancel.tr(),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: CalendarMetrics.space2),
                  _PrimaryButton(
                    label: LocaleKeys.reminders_save.tr(),
                    enabled: _canSave,
                    onTap: _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _repeatLabel(CalendarRecurrenceKind kind) => switch (kind) {
        CalendarRecurrenceKind.none => LocaleKeys.reminders_repeats_none.tr(),
        CalendarRecurrenceKind.daily => LocaleKeys.reminders_repeats_daily.tr(),
        CalendarRecurrenceKind.weekdays =>
          LocaleKeys.reminders_repeats_weekdays.tr(),
        CalendarRecurrenceKind.weekly =>
          LocaleKeys.reminders_repeats_weekly.tr(),
        CalendarRecurrenceKind.monthly =>
          LocaleKeys.reminders_repeats_monthly.tr(),
        CalendarRecurrenceKind.yearly =>
          LocaleKeys.reminders_repeats_yearly.tr(),
        CalendarRecurrenceKind.custom =>
          LocaleKeys.reminders_repeats_custom.tr(),
      };

  static String _priorityLabel(ReminderPriority priority) => switch (priority) {
        ReminderPriority.none => LocaleKeys.reminders_priorities_none.tr(),
        ReminderPriority.low => LocaleKeys.reminders_priorities_low.tr(),
        ReminderPriority.medium => LocaleKeys.reminders_priorities_medium.tr(),
        ReminderPriority.high => LocaleKeys.reminders_priorities_high.tr(),
      };

  Future<void> _pickDate() async {
    final base = _when ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 5),
      lastDate: DateTime(base.year + 10),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _when = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _hasTime ? base.hour : 9,
        _hasTime ? base.minute : 0,
      );
    });
  }

  Future<void> _pickTime() async {
    final base = _when ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _hasTime = true;
      _when = DateTime(
        base.year,
        base.month,
        base.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _save() async {
    final when = _when;
    if (when == null || _title.isEmpty) {
      return;
    }
    setState(() => _saving = true);
    final reminder = await ReminderStore.instance.create(
      buildReminder(
        title: _title,
        when: when,
        includeTime: _hasTime,
        recurrence: _recurrence,
        priority: _priority,
        kind: widget.kind,
        objectId: widget.objectId.isEmpty ? widget.pageId : widget.objectId,
        playsSound: _playsSound,
      ),
    );
    // The copy on Google is a courtesy, not a condition: the reminder is
    // already saved and will still speak if this fails.
    if (reminder != null && _syncToGoogle) {
      await ReminderGoogleSync.push(reminder);
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(reminder);
  }
}

/// What the parser made of the line, shown plainly so a wrong reading is
/// obvious before anything is saved.
class _ReadAs extends StatelessWidget {
  const _ReadAs({
    required this.parsed,
    required this.when,
    required this.hasTime,
  });

  final ParsedReminder parsed;
  final DateTime? when;
  final bool hasTime;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    final title = parsed.title.trim();
    return Container(
      padding: const EdgeInsets.all(CalendarMetrics.space3),
      decoration: BoxDecoration(
        color: palette.sunken.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(CalendarMetrics.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CalendarSectionLabel(text: LocaleKeys.reminders_understood.tr()),
          const SizedBox(height: CalendarMetrics.space2),
          Row(
            children: [
              Icon(
                Icons.notifications_rounded,
                size: 13,
                color: palette.accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title.isEmpty ? '—' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    color: palette.textPrimary,
                    fontVariations: const [FontVariation.weight(600)],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            when == null
                ? LocaleKeys.reminders_noDate.tr()
                : hasTime
                    ? DateFormat.yMMMEd().add_jm().format(when!)
                    : DateFormat.yMMMEd().format(when!),
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              color: when == null ? palette.textMuted : palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.helper,
    required this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final String helper;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          autofocus: autofocus,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(400)],
          style: TextStyle(fontSize: 14, color: palette.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: palette.sunken.withValues(alpha: 0.55),
            hintText: hint,
            hintStyle: TextStyle(fontSize: 14, color: palette.textMuted),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CalendarMetrics.cardRadius),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CalendarMetrics.cardRadius),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CalendarMetrics.cardRadius),
              borderSide: BorderSide(color: palette.accent, width: 1.2),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          helper,
          style: TextStyle(fontSize: 11.5, color: palette.textMuted),
        ),
      ],
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: palette.sunken.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(CalendarMetrics.cardRadius),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: palette.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: palette.textPrimary,
                    fontVariations: const [FontVariation.weight(570)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceButton<T> extends StatelessWidget {
  const _ChoiceButton({
    required this.icon,
    required this.value,
    required this.label,
    required this.options,
    required this.labelOf,
    required this.onChanged,
  });

  final IconData icon;
  final T value;
  final String label;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return PopupMenuButton<T>(
      tooltip: '',
      position: PopupMenuPosition.under,
      color: palette.surface,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<T>(
            value: option,
            height: 34,
            child: Text(
              labelOf(option),
              style: TextStyle(fontSize: 12.5, color: palette.textPrimary),
            ),
          ),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: palette.sunken.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(CalendarMetrics.cardRadius),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: palette.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: palette.textPrimary,
                  fontVariations: const [FontVariation.weight(570)],
                ),
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 15,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SoundToggle extends StatelessWidget {
  const _SoundToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _ToggleRow(
        icon: value ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        label: LocaleKeys.reminders_sound.tr(),
        value: value,
        onChanged: onChanged,
      );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: palette.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: palette.textSecondary,
              fontVariations: const [FontVariation.weight(580)],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedOpacity(
          duration: CalendarMetrics.hover,
          opacity: enabled ? 1 : 0.45,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius:
                  BorderRadius.circular(CalendarMetrics.controlRadius),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1,
                color: Colors.white,
                fontVariations: [FontVariation.weight(620)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
