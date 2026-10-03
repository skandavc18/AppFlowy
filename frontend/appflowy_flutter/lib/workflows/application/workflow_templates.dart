import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';

import 'workflow_model.dart';
import 'workflow_schedule.dart';

/// A ready-made workflow to start from.
class WorkflowTemplate {
  const WorkflowTemplate({
    required this.id,
    required this.titleKey,
    required this.descriptionKey,
    required this.build,
  });

  final String id;
  final String titleKey;
  final String descriptionKey;

  /// Makes a fresh draft named [name]. Text a template writes into pages is
  /// in the reader's language at the time it is used.
  final Workflow Function(String name) build;

  String get title => titleKey.tr();
  String get description => descriptionKey.tr();
}

WorkflowStep _step(
  int number,
  WorkflowStepKind kind,
  Map<String, Object?> config,
) {
  var step = WorkflowStep.create('step$number', kind);
  for (final entry in config.entries) {
    step = step.withValue(entry.key, entry.value);
  }
  return step;
}

Workflow _draft(
  String name, {
  required WorkflowTrigger trigger,
  required List<WorkflowStep> steps,
}) =>
    Workflow.create(name: name, trigger: trigger, steps: steps)
        .copyWith(stepCounter: steps.length);

final List<WorkflowTemplate> workflowTemplates = [
  WorkflowTemplate(
    id: 'daily-journal',
    titleKey: LocaleKeys.workflows_templates_dailyJournal_title,
    descriptionKey: LocaleKeys.workflows_templates_dailyJournal_description,
    build: (name) => _draft(
      name,
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.schedule)
          .withSchedule(const WorkflowSchedule(minuteOfDay: 8 * 60)),
      steps: [
        _step(1, WorkflowStepKind.createPage, {
          'title': '{{trigger.date}} · {{trigger.weekday}}',
          'content': [
            '## ${LocaleKeys.workflows_templates_dailyJournal_today.tr()}',
            '- [ ] ',
            '## ${LocaleKeys.workflows_templates_dailyJournal_notes.tr()}',
            '',
          ].join('\n\n'),
        }),
      ],
    ),
  ),
  WorkflowTemplate(
    id: 'webhook-to-table',
    titleKey: LocaleKeys.workflows_templates_webhookToTable_title,
    descriptionKey: LocaleKeys.workflows_templates_webhookToTable_description,
    build: (name) => _draft(
      name,
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.webhook),
      steps: [
        _step(1, WorkflowStepKind.addRow, {
          'values': const [
            WorkflowPair('Name', '{{trigger.body.name}}'),
          ],
        }),
      ],
    ),
  ),
  WorkflowTemplate(
    id: 'feed-digest',
    titleKey: LocaleKeys.workflows_templates_feedDigest_title,
    descriptionKey: LocaleKeys.workflows_templates_feedDigest_description,
    build: (name) => _draft(
      name,
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.feed),
      steps: [
        _step(1, WorkflowStepKind.appendToPage, {
          'content': '- [{{trigger.title}}]({{trigger.link}})',
        }),
      ],
    ),
  ),
  WorkflowTemplate(
    id: 'stretch-break',
    titleKey: LocaleKeys.workflows_templates_stretchBreak_title,
    descriptionKey: LocaleKeys.workflows_templates_stretchBreak_description,
    build: (name) => _draft(
      name,
      trigger:
          WorkflowTrigger.create(WorkflowTriggerKind.schedule).withSchedule(
        const WorkflowSchedule(mode: WorkflowScheduleMode.interval),
      ),
      steps: [
        _step(1, WorkflowStepKind.notify, {
          'title': LocaleKeys.workflows_templates_stretchBreak_notifyTitle.tr(),
          'body': LocaleKeys.workflows_templates_stretchBreak_notifyBody.tr(),
        }),
      ],
    ),
  ),
  WorkflowTemplate(
    id: 'row-alert',
    titleKey: LocaleKeys.workflows_templates_rowAlert_title,
    descriptionKey: LocaleKeys.workflows_templates_rowAlert_description,
    build: (name) => _draft(
      name,
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.databaseRow),
      steps: [
        _step(1, WorkflowStepKind.notify, {
          'title': LocaleKeys.workflows_templates_rowAlert_notifyTitle.tr(),
          'body': '{{trigger.fields}}',
        }),
      ],
    ),
  ),
  WorkflowTemplate(
    id: 'weekly-review',
    titleKey: LocaleKeys.workflows_templates_weeklyReview_title,
    descriptionKey: LocaleKeys.workflows_templates_weeklyReview_description,
    build: (name) => _draft(
      name,
      trigger:
          WorkflowTrigger.create(WorkflowTriggerKind.schedule).withSchedule(
        const WorkflowSchedule(
          mode: WorkflowScheduleMode.weekly,
          minuteOfDay: 16 * 60,
          weekdays: {DateTime.friday},
        ),
      ),
      steps: [
        _step(1, WorkflowStepKind.createPage, {
          'title':
              '${LocaleKeys.workflows_templates_weeklyReview_pageTitle.tr()}'
                  ' · {{trigger.date}}',
          'content': [
            '## ${LocaleKeys.workflows_templates_weeklyReview_wins.tr()}',
            '- ',
            '## ${LocaleKeys.workflows_templates_weeklyReview_lessons.tr()}',
            '- ',
            '## ${LocaleKeys.workflows_templates_weeklyReview_next.tr()}',
            '- [ ] ',
          ].join('\n\n'),
        }),
        _step(2, WorkflowStepKind.notify, {
          'title': LocaleKeys.workflows_templates_weeklyReview_notifyTitle.tr(),
          'body': '{{step1.name}}',
        }),
      ],
    ),
  ),
  WorkflowTemplate(
    id: 'page-to-chat',
    titleKey: LocaleKeys.workflows_templates_pageToChat_title,
    descriptionKey: LocaleKeys.workflows_templates_pageToChat_description,
    build: (name) => _draft(
      name,
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.newPage),
      steps: [
        _step(1, WorkflowStepKind.httpRequest, {
          'fields': [
            WorkflowPair(
              'text',
              LocaleKeys.workflows_templates_pageToChat_message.tr(
                args: ['{{trigger.name}}'],
              ),
            ),
          ],
        }),
      ],
    ),
  ),
  WorkflowTemplate(
    id: 'start-of-day',
    titleKey: LocaleKeys.workflows_templates_startOfDay_title,
    descriptionKey: LocaleKeys.workflows_templates_startOfDay_description,
    build: (name) => _draft(
      name,
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.appStart),
      steps: [
        _step(1, WorkflowStepKind.storage, {
          'operation': 'increment',
          'key': 'launches',
          'value': '',
        }),
        _step(2, WorkflowStepKind.notify, {
          'title': LocaleKeys.workflows_templates_startOfDay_notifyTitle.tr(),
          'body': LocaleKeys.workflows_templates_startOfDay_notifyBody.tr(
            args: ['{{storage.launches}}'],
          ),
        }),
      ],
    ),
  ),
];
