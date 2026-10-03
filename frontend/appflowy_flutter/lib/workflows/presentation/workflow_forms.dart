import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/workflows/application/workflow_format.dart';
import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_schedule.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'workflow_inputs.dart';
import 'workflow_style.dart';

const _gap = SizedBox(height: 16);

/// "Every 2 hours", "Every day at 09:00", "Mon, Wed at 16:00".
String describeWorkflowSchedule(WorkflowSchedule schedule) {
  final clock = _clock(schedule.minuteOfDay);
  switch (schedule.mode) {
    case WorkflowScheduleMode.interval:
      return LocaleKeys.workflows_schedule_summaryInterval.tr(
        args: ['${schedule.every}', _unitName(schedule.unit)],
      );
    case WorkflowScheduleMode.daily:
      return LocaleKeys.workflows_schedule_summaryDaily.tr(args: [clock]);
    case WorkflowScheduleMode.weekly:
      final days =
          (schedule.weekdays.toList()..sort()).map(_weekdayShort).join(', ');
      return LocaleKeys.workflows_schedule_summaryWeekly.tr(
        args: [days, clock],
      );
    case WorkflowScheduleMode.monthly:
      return LocaleKeys.workflows_schedule_summaryMonthly.tr(
        args: ['${schedule.dayOfMonth}', clock],
      );
  }
}

/// One line saying what starts a workflow, for its card.
String describeWorkflowTrigger(WorkflowTrigger trigger) =>
    switch (trigger.kind) {
      WorkflowTriggerKind.schedule =>
        describeWorkflowSchedule(trigger.schedule),
      WorkflowTriggerKind.feed when trigger.url.isNotEmpty =>
        Uri.tryParse(trigger.url)?.host ?? trigger.url,
      WorkflowTriggerKind.databaseRow when trigger.viewName.isNotEmpty =>
        '${WorkflowVisuals.triggerName(trigger.kind)} · ${trigger.viewName}',
      WorkflowTriggerKind.newPage when trigger.parentName.isNotEmpty =>
        '${WorkflowVisuals.triggerName(trigger.kind)} · ${trigger.parentName}',
      _ => WorkflowVisuals.triggerName(trigger.kind),
    };

String _clock(int minuteOfDay) =>
    '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:'
    '${(minuteOfDay % 60).toString().padLeft(2, '0')}';

String _unitName(WorkflowIntervalUnit unit) => switch (unit) {
      WorkflowIntervalUnit.minutes =>
        LocaleKeys.workflows_schedule_unit_minutes.tr(),
      WorkflowIntervalUnit.hours =>
        LocaleKeys.workflows_schedule_unit_hours.tr(),
      WorkflowIntervalUnit.days => LocaleKeys.workflows_schedule_unit_days.tr(),
    };

/// Monday is 1. 2024-01-01 was a Monday.
String _weekdayShort(int weekday) =>
    DateFormat.E().format(DateTime(2024, 1, weekday));

int? _parseClock(String text) {
  final match =
      RegExp(r'^\s*(\d{1,2})(?::|\.|h)?(\d{2})?\s*$').firstMatch(text);
  if (match == null) {
    return null;
  }
  final hour = int.parse(match.group(1)!);
  final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
  if (hour > 23 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

List<WorkflowOption<int>> _pollOptions(List<int> minutes) => [
      for (final value in minutes)
        WorkflowOption(
          value,
          LocaleKeys.workflows_feed_minutes.tr(args: ['$value']),
        ),
    ];

/// One line saying what a step will do, for its card.
String describeWorkflowStep(WorkflowStep step) {
  String short(String text) {
    final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length > 60 ? '${line.substring(0, 60)}…' : line;
  }

  switch (step.kind) {
    case WorkflowStepKind.httpRequest:
      final url = step.text('url').trim();
      final host = Uri.tryParse(url)?.host ?? '';
      final method = step.text('method').isEmpty ? 'GET' : step.text('method');
      return url.isEmpty ? '' : '$method ${host.isEmpty ? short(url) : host}';
    case WorkflowStepKind.createPage:
      return short(step.text('title'));
    case WorkflowStepKind.appendToPage:
      return short(step.text('pageName'));
    case WorkflowStepKind.addRow:
      return short(step.text('viewName'));
    case WorkflowStepKind.notify:
      return short(
        step.text('title').isEmpty ? step.text('body') : step.text('title'),
      );
    case WorkflowStepKind.reminder:
      final when = step.text('when').trim();
      return short(
        [step.text('title').trim(), if (when.isNotEmpty) when].join(' · '),
      );
    case WorkflowStepKind.filter:
      final conditions = step.conditions;
      if (conditions.isEmpty || conditions.first.left.isEmpty) {
        return '';
      }
      final first = conditions.first;
      final more = conditions.length > 1 ? ' +${conditions.length - 1}' : '';
      return short(
        '${first.left} ${_operatorName(first.operator)}'
        '${first.operator.needsValue ? ' ${first.right}' : ''}$more',
      );
    case WorkflowStepKind.delay:
      return '${step.number('amount', fallback: 10)} '
          '${_unitName(WorkflowIntervalUnit.parse(step.config['unit']))}';
    case WorkflowStepKind.formatter:
      return _formatName(
        WorkflowFormatOperation.parse(step.config['operation']),
      );
    case WorkflowStepKind.code:
      return 'JavaScript';
    case WorkflowStepKind.storage:
      return short(step.text('key'));
  }
}

/// Sets up what starts a workflow.
class WorkflowTriggerForm extends StatelessWidget {
  const WorkflowTriggerForm({
    super.key,
    required this.trigger,
    required this.onChanged,
    required this.webhookAddress,
  });

  final WorkflowTrigger trigger;
  final ValueChanged<WorkflowTrigger> onChanged;
  final String webhookAddress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TriggerKinds(
          selected: trigger.kind,
          onChanged: (kind) {
            if (kind != trigger.kind) {
              onChanged(WorkflowTrigger.create(kind));
            }
          },
        ),
        const SizedBox(height: 12),
        WorkflowHint(WorkflowVisuals.triggerAbout(trigger.kind), glyph: 'info'),
        _gap,
        ...switch (trigger.kind) {
          WorkflowTriggerKind.schedule => [
              _ScheduleForm(
                schedule: trigger.schedule,
                onChanged: (schedule) =>
                    onChanged(trigger.withSchedule(schedule)),
              ),
            ],
          WorkflowTriggerKind.webhook => [
              _WebhookForm(
                address: webhookAddress,
                onRegenerate: () => onChanged(
                  trigger.withValue('token', newWorkflowToken()),
                ),
              ),
            ],
          WorkflowTriggerKind.feed => [
              WorkflowTextInput(
                label: LocaleKeys.workflows_feed_url.tr(),
                hint: LocaleKeys.workflows_feed_urlHint.tr(),
                value: trigger.text('url'),
                keyboardType: TextInputType.url,
                onChanged: (text) => onChanged(trigger.withValue('url', text)),
              ),
              _gap,
              WorkflowChoice<int>(
                label: LocaleKeys.workflows_feed_every.tr(),
                value: trigger.pollInterval.inMinutes,
                options: _pollOptions(const [5, 15, 30, 60, 180]),
                onChanged: (value) =>
                    onChanged(trigger.withValue('poll', value)),
              ),
            ],
          WorkflowTriggerKind.databaseRow => [
              WorkflowViewPicker(
                label: LocaleKeys.workflows_table_table.tr(),
                emptyLabel: LocaleKeys.workflows_table_choose.tr(),
                viewId: trigger.viewId,
                kind: WorkflowViewKind.table,
                onChanged: (id, name) => onChanged(
                  trigger.withValue('viewId', id).withValue('viewName', name),
                ),
              ),
              const SizedBox(height: 10),
              WorkflowCheckRow(
                value: trigger.includeUpdates,
                label: LocaleKeys.workflows_table_updates.tr(),
                onChanged: (value) =>
                    onChanged(trigger.withValue('updates', value)),
              ),
              _gap,
              WorkflowChoice<int>(
                label: LocaleKeys.workflows_table_every.tr(),
                value: trigger.pollInterval.inMinutes,
                options: _pollOptions(const [1, 2, 5, 15, 60]),
                onChanged: (value) =>
                    onChanged(trigger.withValue('poll', value)),
              ),
            ],
          WorkflowTriggerKind.newPage => [
              WorkflowViewPicker(
                label: LocaleKeys.workflows_page_parent.tr(),
                emptyLabel: LocaleKeys.workflows_page_chooseParent.tr(),
                viewId: trigger.parentId,
                kind: WorkflowViewKind.parent,
                onChanged: (id, name) => onChanged(
                  trigger
                      .withValue('parentId', id)
                      .withValue('parentName', name),
                ),
              ),
              _gap,
              WorkflowChoice<int>(
                label: LocaleKeys.workflows_table_every.tr(),
                value: trigger.pollInterval.inMinutes,
                options: _pollOptions(const [1, 2, 5, 15, 60]),
                onChanged: (value) =>
                    onChanged(trigger.withValue('poll', value)),
              ),
            ],
          _ => const <Widget>[],
        },
      ],
    );
  }
}

class _TriggerKinds extends StatelessWidget {
  const _TriggerKinds({required this.selected, required this.onChanged});

  final WorkflowTriggerKind selected;
  final ValueChanged<WorkflowTriggerKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final kind in WorkflowTriggerKind.values)
          Semantics(
            selected: kind == selected,
            button: true,
            child: InkWell(
              key: ValueKey('workflow-trigger-kind-${kind.name}'),
              onTap: () => onChanged(kind),
              borderRadius: BorderRadius.circular(10),
              hoverColor: palette.hover.withValues(alpha: 0.6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: kind == selected
                      ? palette.accentSoft
                      : palette.accentSoft.withValues(alpha: 0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: kind == selected
                        ? palette.accent.withValues(alpha: 0.55)
                        : palette.border.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WorkflowGlyphTile(
                      glyph: WorkflowVisuals.triggerGlyph(kind),
                      accent: WorkflowVisuals.triggerAccent,
                      size: 20,
                      radius: 6,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      WorkflowVisuals.triggerName(kind),
                      style: DashboardType.body(
                        palette,
                        color: kind == selected
                            ? palette.textPrimary
                            : palette.textSecondary,
                      ).copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScheduleForm extends StatelessWidget {
  const _ScheduleForm({required this.schedule, required this.onChanged});

  final WorkflowSchedule schedule;
  final ValueChanged<WorkflowSchedule> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final time = _ClockInput(
      key: ValueKey('clock-${schedule.mode.name}'),
      minuteOfDay: schedule.minuteOfDay,
      onChanged: (minute) => onChanged(schedule.copyWith(minuteOfDay: minute)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkflowSegmented<WorkflowScheduleMode>(
          expand: true,
          values: WorkflowScheduleMode.values,
          selected: schedule.mode,
          labelOf: (mode) => switch (mode) {
            WorkflowScheduleMode.interval =>
              LocaleKeys.workflows_schedule_mode_interval.tr(),
            WorkflowScheduleMode.daily =>
              LocaleKeys.workflows_schedule_mode_daily.tr(),
            WorkflowScheduleMode.weekly =>
              LocaleKeys.workflows_schedule_mode_weekly.tr(),
            WorkflowScheduleMode.monthly =>
              LocaleKeys.workflows_schedule_mode_monthly.tr(),
          },
          onChanged: (mode) => onChanged(schedule.copyWith(mode: mode)),
        ),
        _gap,
        if (schedule.mode == WorkflowScheduleMode.interval)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 92,
                child: WorkflowTextInput(
                  label: LocaleKeys.workflows_schedule_every.tr(),
                  value: '${schedule.every}',
                  keyboardType: TextInputType.number,
                  onChanged: (text) {
                    final value = int.tryParse(text.trim());
                    if (value != null && value >= 1 && value <= 1000) {
                      onChanged(schedule.copyWith(every: value));
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WorkflowChoice<WorkflowIntervalUnit>(
                  value: schedule.unit,
                  options: [
                    for (final unit in WorkflowIntervalUnit.values)
                      WorkflowOption(unit, _unitName(unit)),
                  ],
                  onChanged: (unit) => onChanged(schedule.copyWith(unit: unit)),
                ),
              ),
            ],
          ),
        if (schedule.mode == WorkflowScheduleMode.weekly) ...[
          WorkflowLabel(LocaleKeys.workflows_schedule_on.tr()),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                _DayChip(
                  label: _weekdayShort(day),
                  selected: schedule.weekdays.contains(day),
                  onTap: () {
                    final next = {...schedule.weekdays};
                    if (!next.remove(day)) {
                      next.add(day);
                    }
                    onChanged(schedule.copyWith(weekdays: next));
                  },
                ),
            ],
          ),
          if (schedule.weekdays.isEmpty) ...[
            const SizedBox(height: 8),
            WorkflowHint(
              LocaleKeys.workflows_schedule_noDays.tr(),
              glyph: 'warning',
              accent: DashboardAccent.red,
            ),
          ],
          _gap,
        ],
        if (schedule.mode == WorkflowScheduleMode.monthly) ...[
          WorkflowChoice<int>(
            label: LocaleKeys.workflows_schedule_day.tr(),
            value: schedule.dayOfMonth,
            options: [
              for (var day = 1; day <= 31; day++) WorkflowOption(day, '$day'),
            ],
            onChanged: (day) => onChanged(schedule.copyWith(dayOfMonth: day)),
          ),
          _gap,
        ],
        if (schedule.mode != WorkflowScheduleMode.interval) time,
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: palette.accentSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              WorkflowGlyphTile(
                glyph: 'clock',
                accent: WorkflowVisuals.triggerAccent,
                size: 22,
                radius: 6,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  describeWorkflowSchedule(schedule),
                  style: DashboardType.body(palette).copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 44,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.accent : palette.sunken,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? palette.onAccent : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// "09:00", accepted as typed as soon as it reads as a time.
class _ClockInput extends StatefulWidget {
  const _ClockInput({
    super.key,
    required this.minuteOfDay,
    required this.onChanged,
  });

  final int minuteOfDay;
  final ValueChanged<int> onChanged;

  @override
  State<_ClockInput> createState() => _ClockInputState();
}

class _ClockInputState extends State<_ClockInput> {
  bool _invalid = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 140,
          child: WorkflowTextInput(
            label: LocaleKeys.workflows_schedule_at.tr(),
            value: _clock(widget.minuteOfDay),
            hint: '09:00',
            keyboardType: TextInputType.datetime,
            onChanged: (text) {
              final minute = _parseClock(text);
              setState(() => _invalid = minute == null);
              if (minute != null) {
                widget.onChanged(minute);
              }
            },
          ),
        ),
        if (_invalid) ...[
          const SizedBox(height: 6),
          WorkflowHint(
            LocaleKeys.workflows_schedule_badTime.tr(),
            glyph: 'warning',
            accent: DashboardAccent.red,
          ),
        ],
      ],
    );
  }
}

class _WebhookForm extends StatelessWidget {
  const _WebhookForm({required this.address, required this.onRegenerate});

  final String address;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final example = 'curl -X POST "$address" \\\n'
        '  -H "Content-Type: application/json" \\\n'
        '  -d \'{"name": "Ada", "message": "Hello"}\'';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkflowTextInput(
          key: ValueKey(address),
          label: LocaleKeys.workflows_webhook_address.tr(),
          value: address,
          readOnly: true,
          monospace: true,
          onChanged: (_) {},
          trailing: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: WorkflowIconButton(
              glyph: 'copy',
              tooltip: LocaleKeys.workflows_webhook_copy.tr(),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: address));
                if (context.mounted) {
                  showSnackBarMessage(
                    context,
                    LocaleKeys.workflows_webhook_copied.tr(),
                  );
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        WorkflowHint(LocaleKeys.workflows_webhook_hint.tr()),
        const SizedBox(height: 6),
        WorkflowHint(
          LocaleKeys.workflows_webhook_localOnly.tr(),
          glyph: 'lock',
        ),
        _gap,
        WorkflowLabel(LocaleKeys.workflows_webhook_example.tr()),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: palette.sunken,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            example,
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Cascadia Code', 'Consolas'],
              fontSize: 11.5,
              height: 1.45,
              color: palette.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: WorkflowButton(
            label: LocaleKeys.workflows_webhook_regenerate.tr(),
            glyph: 'refresh',
            kind: WorkflowButtonKind.quiet,
            tooltip: LocaleKeys.workflows_webhook_regenerated.tr(),
            onPressed: onRegenerate,
          ),
        ),
      ],
    );
  }
}

/// Sets up one step.
class WorkflowStepForm extends StatelessWidget {
  const WorkflowStepForm({
    super.key,
    required this.step,
    required this.onChanged,
    required this.dataGroups,
  });

  final WorkflowStep step;
  final ValueChanged<WorkflowStep> onChanged;
  final List<WorkflowDataGroup> dataGroups;

  Widget _text(
    String key,
    String label, {
    String? hint,
    int lines = 1,
    bool data = true,
    bool monospace = false,
  }) =>
      WorkflowTextInput(
        label: label,
        hint: hint,
        value: step.text(key),
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 8,
        monospace: monospace,
        dataGroups: data ? dataGroups : null,
        onChanged: (text) => onChanged(step.withValue(key, text)),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: switch (step.kind) {
        WorkflowStepKind.httpRequest => _request(),
        WorkflowStepKind.createPage => [
            WorkflowViewPicker(
              label: LocaleKeys.workflows_page_parent.tr(),
              viewId: step.text('parentId'),
              kind: WorkflowViewKind.parent,
              clearable: true,
              clearedLabel: LocaleKeys.workflows_fields_topLevel.tr(),
              onChanged: (id, name) => onChanged(
                step.withValue('parentId', id).withValue('parentName', name),
              ),
            ),
            _gap,
            _text('title', LocaleKeys.workflows_page_title.tr()),
            _gap,
            _text(
              'content',
              LocaleKeys.workflows_page_content.tr(),
              hint: LocaleKeys.workflows_page_contentHint.tr(),
              lines: 5,
            ),
          ],
        WorkflowStepKind.appendToPage => [
            _PageTarget(
              step: step,
              dataGroups: dataGroups,
              onChanged: onChanged,
            ),
            _gap,
            _text(
              'content',
              LocaleKeys.workflows_page_content.tr(),
              hint: LocaleKeys.workflows_page_contentHint.tr(),
              lines: 4,
            ),
          ],
        WorkflowStepKind.addRow => [
            WorkflowViewPicker(
              label: LocaleKeys.workflows_table_table.tr(),
              emptyLabel: LocaleKeys.workflows_table_choose.tr(),
              viewId: step.text('viewId'),
              kind: WorkflowViewKind.table,
              onChanged: (id, name) => onChanged(
                step.withValue('viewId', id).withValue('viewName', name),
              ),
            ),
            if (step.text('viewId').isNotEmpty) ...[
              _gap,
              _RowValues(
                key: ValueKey(step.text('viewId')),
                viewId: step.text('viewId'),
                values: step.pairs('values'),
                dataGroups: dataGroups,
                onChanged: (pairs) =>
                    onChanged(step.withValue('values', pairs)),
              ),
            ],
          ],
        WorkflowStepKind.notify => [
            _text('title', LocaleKeys.workflows_notify_title.tr()),
            _gap,
            _text('body', LocaleKeys.workflows_notify_body.tr(), lines: 3),
            const SizedBox(height: 8),
            WorkflowHint(LocaleKeys.workflows_notify_hint.tr()),
          ],
        WorkflowStepKind.reminder => [
            _text('title', LocaleKeys.workflows_reminder_title.tr()),
            _gap,
            _text('message', LocaleKeys.workflows_reminder_note.tr(), lines: 2),
            _gap,
            _text(
              'when',
              LocaleKeys.workflows_reminder_when.tr(),
              hint: LocaleKeys.workflows_reminder_whenHint.tr(),
            ),
          ],
        WorkflowStepKind.filter => [
            _FilterForm(
              step: step,
              dataGroups: dataGroups,
              onChanged: onChanged,
            ),
          ],
        WorkflowStepKind.delay => [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 92,
                  child: WorkflowTextInput(
                    label: LocaleKeys.workflows_delay_for.tr(),
                    value: '${step.number('amount', fallback: 10)}',
                    keyboardType: TextInputType.number,
                    onChanged: (text) {
                      final value = int.tryParse(text.trim());
                      if (value != null && value > 0) {
                        onChanged(step.withValue('amount', value));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: WorkflowChoice<String>(
                    value: WorkflowIntervalUnit.parse(step.config['unit']).name,
                    options: [
                      for (final unit in WorkflowIntervalUnit.values)
                        WorkflowOption(unit.name, _unitName(unit)),
                    ],
                    onChanged: (unit) =>
                        onChanged(step.withValue('unit', unit)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            WorkflowHint(LocaleKeys.workflows_delay_hint.tr(), glyph: 'info'),
          ],
        WorkflowStepKind.formatter => [
            _FormatterForm(
              step: step,
              dataGroups: dataGroups,
              onChanged: onChanged,
            ),
          ],
        WorkflowStepKind.code => [
            _text(
              'code',
              LocaleKeys.workflows_code_code.tr(),
              lines: 10,
              data: false,
              monospace: true,
            ),
            const SizedBox(height: 8),
            WorkflowHint(LocaleKeys.workflows_code_hint.tr(), glyph: 'shield'),
          ],
        WorkflowStepKind.storage => _storage(),
      },
    );
  }

  List<Widget> _request() {
    final method = step.text('method').isEmpty ? 'GET' : step.text('method');
    final bodyKind =
        step.text('bodyKind').isEmpty ? 'json' : step.text('bodyKind');
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 112,
            child: WorkflowChoice<String>(
              label: LocaleKeys.workflows_http_method.tr(),
              value: method,
              options: [
                for (final verb in const [
                  'GET',
                  'POST',
                  'PUT',
                  'PATCH',
                  'DELETE',
                ])
                  WorkflowOption(verb, verb),
              ],
              onChanged: (verb) => onChanged(step.withValue('method', verb)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _text(
              'url',
              LocaleKeys.workflows_http_url.tr(),
              hint: 'https://',
            ),
          ),
        ],
      ),
      _gap,
      WorkflowPairsEditor(
        label: LocaleKeys.workflows_http_query.tr(),
        pairs: step.pairs('query'),
        dataGroups: dataGroups,
        onChanged: (pairs) => onChanged(step.withValue('query', pairs)),
      ),
      _gap,
      WorkflowPairsEditor(
        label: LocaleKeys.workflows_http_headers.tr(),
        keyHint: 'Authorization',
        pairs: step.pairs('headers'),
        dataGroups: dataGroups,
        onChanged: (pairs) => onChanged(step.withValue('headers', pairs)),
      ),
      if (method != 'GET') ...[
        _gap,
        WorkflowLabel(LocaleKeys.workflows_http_body.tr()),
        WorkflowSegmented<String>(
          values: const ['json', 'form', 'raw', 'none'],
          selected: bodyKind,
          labelOf: (kind) => switch (kind) {
            'form' => LocaleKeys.workflows_http_bodyKind_form.tr(),
            'raw' => LocaleKeys.workflows_http_bodyKind_raw.tr(),
            'none' => LocaleKeys.workflows_http_bodyKind_none.tr(),
            _ => LocaleKeys.workflows_http_bodyKind_json.tr(),
          },
          onChanged: (kind) => onChanged(step.withValue('bodyKind', kind)),
        ),
        const SizedBox(height: 10),
        if (bodyKind == 'json' || bodyKind == 'form')
          WorkflowPairsEditor(
            pairs: step.pairs('fields'),
            dataGroups: dataGroups,
            onChanged: (pairs) => onChanged(step.withValue('fields', pairs)),
          ),
        if (bodyKind == 'raw')
          _text('body', LocaleKeys.workflows_http_raw.tr(), lines: 5),
      ],
      const SizedBox(height: 12),
      WorkflowCheckRow(
        value: step.flag('failOnError', fallback: true),
        label: LocaleKeys.workflows_http_failOnError.tr(),
        onChanged: (value) => onChanged(step.withValue('failOnError', value)),
      ),
    ];
  }

  List<Widget> _storage() {
    final operation =
        step.text('operation').isEmpty ? 'set' : step.text('operation');
    return [
      WorkflowChoice<String>(
        label: LocaleKeys.workflows_storage_operation.tr(),
        value: operation,
        options: [
          WorkflowOption('set', LocaleKeys.workflows_storage_op_set.tr()),
          WorkflowOption(
            'increment',
            LocaleKeys.workflows_storage_op_increment.tr(),
          ),
          WorkflowOption('append', LocaleKeys.workflows_storage_op_append.tr()),
          WorkflowOption('get', LocaleKeys.workflows_storage_op_get.tr()),
          WorkflowOption('remove', LocaleKeys.workflows_storage_op_remove.tr()),
        ],
        onChanged: (value) => onChanged(step.withValue('operation', value)),
      ),
      _gap,
      _text('key', LocaleKeys.workflows_storage_key.tr(), data: false),
      if (operation != 'get' && operation != 'remove') ...[
        _gap,
        _text(
          'value',
          LocaleKeys.workflows_storage_value.tr(),
          hint: operation == 'increment' ? '1' : null,
        ),
      ],
      const SizedBox(height: 8),
      WorkflowHint(LocaleKeys.workflows_storage_hint.tr()),
    ];
  }
}

/// The page an "Add to page" step writes into: chosen, or read from data.
class _PageTarget extends StatelessWidget {
  const _PageTarget({
    required this.step,
    required this.dataGroups,
    required this.onChanged,
  });

  final WorkflowStep step;
  final List<WorkflowDataGroup> dataGroups;
  final ValueChanged<WorkflowStep> onChanged;

  @override
  Widget build(BuildContext context) {
    final pageId = step.text('pageId');
    final fromData = step.flag('pageFromData') || pageId.contains('{{');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fromData)
          WorkflowTextInput(
            label: LocaleKeys.workflows_page_page.tr(),
            hint: '{{step1.id}}',
            value: pageId,
            dataGroups: dataGroups,
            onChanged: (text) => onChanged(step.withValue('pageId', text)),
          )
        else
          WorkflowViewPicker(
            label: LocaleKeys.workflows_page_page.tr(),
            emptyLabel: LocaleKeys.workflows_page_choosePage.tr(),
            viewId: pageId,
            kind: WorkflowViewKind.page,
            onChanged: (id, name) => onChanged(
              step.withValue('pageId', id).withValue('pageName', name),
            ),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: WorkflowButton(
            kind: WorkflowButtonKind.quiet,
            glyph: fromData ? 'file-text' : 'brackets',
            label: fromData
                ? LocaleKeys.workflows_page_choosePage.tr()
                : LocaleKeys.workflows_fields_useData.tr(),
            onPressed: () => onChanged(
              step.withValue('pageFromData', !fromData).withValue('pageId', ''),
            ),
          ),
        ),
      ],
    );
  }
}

/// One value per column of the chosen table.
class _RowValues extends StatefulWidget {
  const _RowValues({
    super.key,
    required this.viewId,
    required this.values,
    required this.dataGroups,
    required this.onChanged,
  });

  final String viewId;
  final List<WorkflowPair> values;
  final List<WorkflowDataGroup> dataGroups;
  final ValueChanged<List<WorkflowPair>> onChanged;

  @override
  State<_RowValues> createState() => _RowValuesState();
}

class _RowValuesState extends State<_RowValues> {
  static const _writable = {
    FieldType.RichText,
    FieldType.Number,
    FieldType.Checkbox,
    FieldType.URL,
    FieldType.SingleSelect,
    FieldType.MultiSelect,
    FieldType.DateTime,
    FieldType.Time,
  };

  List<FieldPB>? _fields;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final result = await FieldBackendService.getFields(viewId: widget.viewId);
    if (!mounted) {
      return;
    }
    setState(() {
      _fields = result.fold(
        (fields) => [
          for (final field in fields)
            if (_writable.contains(field.fieldType)) field,
        ],
        (_) => const [],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final fields = _fields;
    if (fields == null) {
      return WorkflowHint(LocaleKeys.workflows_table_loading.tr());
    }
    if (fields.isEmpty) {
      return WorkflowHint(
        LocaleKeys.workflows_table_noColumns.tr(),
        glyph: 'warning',
      );
    }
    String valueFor(String column) {
      for (final pair in widget.values) {
        if (pair.key.trim().toLowerCase() == column.trim().toLowerCase()) {
          return pair.value;
        }
      }
      return '';
    }

    final pairs = [
      for (final field in fields)
        WorkflowPair(field.name, valueFor(field.name)),
    ];
    return WorkflowPairsEditor(
      label: LocaleKeys.workflows_table_columns.tr(),
      fixedKeys: true,
      pairs: pairs,
      dataGroups: widget.dataGroups,
      onChanged: (next) => widget.onChanged([
        for (final pair in next)
          if (pair.value.isNotEmpty) pair,
      ]),
    );
  }
}

String _operatorName(WorkflowOperator operator) => switch (operator) {
      WorkflowOperator.equals =>
        LocaleKeys.workflows_filter_operator_equals.tr(),
      WorkflowOperator.notEquals =>
        LocaleKeys.workflows_filter_operator_notEquals.tr(),
      WorkflowOperator.contains =>
        LocaleKeys.workflows_filter_operator_contains.tr(),
      WorkflowOperator.notContains =>
        LocaleKeys.workflows_filter_operator_notContains.tr(),
      WorkflowOperator.startsWith =>
        LocaleKeys.workflows_filter_operator_startsWith.tr(),
      WorkflowOperator.endsWith =>
        LocaleKeys.workflows_filter_operator_endsWith.tr(),
      WorkflowOperator.greaterThan =>
        LocaleKeys.workflows_filter_operator_greaterThan.tr(),
      WorkflowOperator.lessThan =>
        LocaleKeys.workflows_filter_operator_lessThan.tr(),
      WorkflowOperator.isEmpty =>
        LocaleKeys.workflows_filter_operator_isEmpty.tr(),
      WorkflowOperator.isNotEmpty =>
        LocaleKeys.workflows_filter_operator_isNotEmpty.tr(),
    };

class _FilterForm extends StatelessWidget {
  const _FilterForm({
    required this.step,
    required this.dataGroups,
    required this.onChanged,
  });

  final WorkflowStep step;
  final List<WorkflowDataGroup> dataGroups;
  final ValueChanged<WorkflowStep> onChanged;

  void _set(List<WorkflowCondition> conditions) =>
      onChanged(step.withValue('conditions', conditions));

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final conditions = step.conditions;
    final all = step.flag('all', fallback: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkflowLabel(LocaleKeys.workflows_filter_match.tr()),
        WorkflowSegmented<bool>(
          values: const [true, false],
          selected: all,
          labelOf: (value) => value
              ? LocaleKeys.workflows_filter_all.tr()
              : LocaleKeys.workflows_filter_any.tr(),
          onChanged: (value) => onChanged(step.withValue('all', value)),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < conditions.length; index++)
          Container(
            key: ValueKey('condition-$index-${conditions.length}'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WorkflowTextInput(
                        label: LocaleKeys.workflows_filter_value.tr(),
                        hint: '{{trigger.title}}',
                        value: conditions[index].left,
                        dataGroups: dataGroups,
                        onChanged: (text) => _set([
                          for (var i = 0; i < conditions.length; i++)
                            i == index
                                ? conditions[i].copyWith(left: text)
                                : conditions[i],
                        ]),
                      ),
                      const SizedBox(height: 8),
                      WorkflowChoice<WorkflowOperator>(
                        value: conditions[index].operator,
                        options: [
                          for (final operator in WorkflowOperator.values)
                            WorkflowOption(operator, _operatorName(operator)),
                        ],
                        onChanged: (operator) => _set([
                          for (var i = 0; i < conditions.length; i++)
                            i == index
                                ? conditions[i].copyWith(operator: operator)
                                : conditions[i],
                        ]),
                      ),
                      if (conditions[index].operator.needsValue) ...[
                        const SizedBox(height: 8),
                        WorkflowTextInput(
                          hint: LocaleKeys.workflows_filter_compare.tr(),
                          value: conditions[index].right,
                          dataGroups: dataGroups,
                          onChanged: (text) => _set([
                            for (var i = 0; i < conditions.length; i++)
                              i == index
                                  ? conditions[i].copyWith(right: text)
                                  : conditions[i],
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                WorkflowIconButton(
                  glyph: 'x',
                  tooltip: LocaleKeys.workflows_fields_remove.tr(),
                  onPressed: conditions.length <= 1
                      ? null
                      : () => _set([...conditions]..removeAt(index)),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: WorkflowButton(
            kind: WorkflowButtonKind.quiet,
            glyph: 'plus',
            label: LocaleKeys.workflows_filter_add.tr(),
            onPressed: () => _set([...conditions, const WorkflowCondition()]),
          ),
        ),
      ],
    );
  }
}

String _formatName(WorkflowFormatOperation operation) => switch (operation) {
      WorkflowFormatOperation.trim =>
        LocaleKeys.workflows_formatter_op_trim.tr(),
      WorkflowFormatOperation.uppercase =>
        LocaleKeys.workflows_formatter_op_uppercase.tr(),
      WorkflowFormatOperation.lowercase =>
        LocaleKeys.workflows_formatter_op_lowercase.tr(),
      WorkflowFormatOperation.titleCase =>
        LocaleKeys.workflows_formatter_op_titleCase.tr(),
      WorkflowFormatOperation.replace =>
        LocaleKeys.workflows_formatter_op_replace.tr(),
      WorkflowFormatOperation.truncate =>
        LocaleKeys.workflows_formatter_op_truncate.tr(),
      WorkflowFormatOperation.split =>
        LocaleKeys.workflows_formatter_op_split.tr(),
      WorkflowFormatOperation.extractNumber =>
        LocaleKeys.workflows_formatter_op_extractNumber.tr(),
      WorkflowFormatOperation.extractEmail =>
        LocaleKeys.workflows_formatter_op_extractEmail.tr(),
      WorkflowFormatOperation.extractUrl =>
        LocaleKeys.workflows_formatter_op_extractUrl.tr(),
      WorkflowFormatOperation.stripHtml =>
        LocaleKeys.workflows_formatter_op_stripHtml.tr(),
      WorkflowFormatOperation.urlEncode =>
        LocaleKeys.workflows_formatter_op_urlEncode.tr(),
      WorkflowFormatOperation.wordCount =>
        LocaleKeys.workflows_formatter_op_wordCount.tr(),
      WorkflowFormatOperation.defaultValue =>
        LocaleKeys.workflows_formatter_op_defaultValue.tr(),
      WorkflowFormatOperation.formatDate =>
        LocaleKeys.workflows_formatter_op_formatDate.tr(),
      WorkflowFormatOperation.addTime =>
        LocaleKeys.workflows_formatter_op_addTime.tr(),
      WorkflowFormatOperation.math =>
        LocaleKeys.workflows_formatter_op_math.tr(),
      WorkflowFormatOperation.round =>
        LocaleKeys.workflows_formatter_op_round.tr(),
      WorkflowFormatOperation.parseJson =>
        LocaleKeys.workflows_formatter_op_parseJson.tr(),
    };

String _timeUnitName(String unit) => switch (unit) {
      'minutes' => LocaleKeys.workflows_formatter_units_minutes.tr(),
      'hours' => LocaleKeys.workflows_formatter_units_hours.tr(),
      'weeks' => LocaleKeys.workflows_formatter_units_weeks.tr(),
      'months' => LocaleKeys.workflows_formatter_units_months.tr(),
      _ => LocaleKeys.workflows_formatter_units_days.tr(),
    };

String _formatGroup(WorkflowFormatOperation operation) => switch (operation) {
      WorkflowFormatOperation.extractNumber ||
      WorkflowFormatOperation.math ||
      WorkflowFormatOperation.round =>
        LocaleKeys.workflows_formatter_group_numbers.tr(),
      WorkflowFormatOperation.formatDate ||
      WorkflowFormatOperation.addTime =>
        LocaleKeys.workflows_formatter_group_dates.tr(),
      WorkflowFormatOperation.parseJson ||
      WorkflowFormatOperation.defaultValue =>
        LocaleKeys.workflows_formatter_group_data.tr(),
      _ => LocaleKeys.workflows_formatter_group_text.tr(),
    };

class _FormatterForm extends StatelessWidget {
  const _FormatterForm({
    required this.step,
    required this.dataGroups,
    required this.onChanged,
  });

  final WorkflowStep step;
  final List<WorkflowDataGroup> dataGroups;
  final ValueChanged<WorkflowStep> onChanged;

  Widget _option(String key, String label, {String? hint, bool data = true}) =>
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: WorkflowTextInput(
          label: label,
          hint: hint,
          value: step.text(key),
          dataGroups: data ? dataGroups : null,
          onChanged: (text) => onChanged(step.withValue(key, text)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final operation = WorkflowFormatOperation.parse(step.config['operation']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkflowChoice<WorkflowFormatOperation>(
          label: LocaleKeys.workflows_formatter_operation.tr(),
          value: operation,
          options: [
            for (final value in WorkflowFormatOperation.values)
              WorkflowOption(
                value,
                _formatName(value),
                subtitle: _formatGroup(value),
              ),
          ],
          onChanged: (value) =>
              onChanged(step.withValue('operation', value.name)),
        ),
        _gap,
        WorkflowTextInput(
          label: LocaleKeys.workflows_formatter_input.tr(),
          hint: '{{trigger.title}}',
          value: step.text('input'),
          dataGroups: dataGroups,
          onChanged: (text) => onChanged(step.withValue('input', text)),
        ),
        ...switch (operation) {
          WorkflowFormatOperation.replace => [
              _option('find', LocaleKeys.workflows_formatter_find.tr()),
              _option(
                'replaceWith',
                LocaleKeys.workflows_formatter_replaceWith.tr(),
              ),
            ],
          WorkflowFormatOperation.truncate => [
              _option(
                'length',
                LocaleKeys.workflows_formatter_length.tr(),
                hint: '100',
                data: false,
              ),
            ],
          WorkflowFormatOperation.split => [
              _option(
                'separator',
                LocaleKeys.workflows_formatter_separator.tr(),
                hint: ',',
                data: false,
              ),
              _option(
                'index',
                LocaleKeys.workflows_formatter_index.tr(),
                hint: LocaleKeys.workflows_formatter_indexHint.tr(),
                data: false,
              ),
            ],
          WorkflowFormatOperation.defaultValue => [
              _option('fallback', LocaleKeys.workflows_formatter_fallback.tr()),
            ],
          WorkflowFormatOperation.formatDate => [
              _option(
                'pattern',
                LocaleKeys.workflows_formatter_pattern.tr(),
                hint: LocaleKeys.workflows_formatter_patternHint.tr(),
                data: false,
              ),
            ],
          WorkflowFormatOperation.addTime => [
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 92,
                      child: WorkflowTextInput(
                        label: LocaleKeys.workflows_formatter_amount.tr(),
                        value: step.text('amount'),
                        hint: '1',
                        onChanged: (text) =>
                            onChanged(step.withValue('amount', text)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: WorkflowChoice<String>(
                        value: step.text('unit').isEmpty
                            ? 'days'
                            : step.text('unit'),
                        options: [
                          for (final unit in const [
                            'minutes',
                            'hours',
                            'days',
                            'weeks',
                            'months',
                          ])
                            WorkflowOption(unit, _timeUnitName(unit)),
                        ],
                        onChanged: (unit) =>
                            onChanged(step.withValue('unit', unit)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          WorkflowFormatOperation.math => [
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 92,
                      child: WorkflowChoice<String>(
                        label: LocaleKeys.workflows_formatter_operator.tr(),
                        value: step.text('operator').isEmpty
                            ? '+'
                            : step.text('operator'),
                        options: const [
                          WorkflowOption('+', '+'),
                          WorkflowOption('-', '−'),
                          WorkflowOption('*', '×'),
                          WorkflowOption('/', '÷'),
                        ],
                        onChanged: (value) =>
                            onChanged(step.withValue('operator', value)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: WorkflowTextInput(
                        label: LocaleKeys.workflows_formatter_operand.tr(),
                        value: step.text('operand'),
                        dataGroups: dataGroups,
                        onChanged: (text) =>
                            onChanged(step.withValue('operand', text)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          WorkflowFormatOperation.round => [
              _option(
                'decimals',
                LocaleKeys.workflows_formatter_decimals.tr(),
                hint: '0',
                data: false,
              ),
            ],
          _ => const <Widget>[],
        },
      ],
    );
  }
}
