import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/built_in/template_pieces.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Work: what is being built, what is broken, and who was spoken to.
void registerWorkTemplates() {
  TemplateRegistry.register(_meeting);
  TemplateRegistry.register(_brief);
  TemplateRegistry.register(_issues);
  TemplateRegistry.register(_applications);
}

// -------------------------------------------------------------------- meeting

final _meeting = WorkspaceTemplate(
  id: 'meeting',
  category: TemplateCategory.work,
  label: () => LocaleKeys.templates_item_meeting.tr(),
  description: () => LocaleKeys.templates_item_meetingHint.tr(),
  icon: Icons.groups_rounded,
  accent: DashboardAccent.blue,
  keywords: const ['meeting', 'agenda', 'minutes', 'notes', 'standup', '1:1'],
  build: () => [
    TemplatePart(
      key: 'page',
      icon: '📝',
      name: () => LocaleKeys.templates_item_meeting.tr(),
      blueprint: TemplatePage((_) => LocaleKeys.templates_page_meeting.tr()),
    ),
  ],
);

// ---------------------------------------------------------------- project brief

final _brief = WorkspaceTemplate(
  id: 'brief',
  category: TemplateCategory.work,
  label: () => LocaleKeys.templates_item_brief.tr(),
  description: () => LocaleKeys.templates_item_briefHint.tr(),
  icon: Icons.description_rounded,
  accent: DashboardAccent.purple,
  keywords: const ['brief', 'project', 'spec', 'proposal', 'prd', 'plan'],
  build: () => [
    TemplatePart(
      key: 'page',
      icon: '📐',
      name: () => LocaleKeys.templates_item_brief.tr(),
      blueprint: TemplatePage((_) => LocaleKeys.templates_page_brief.tr()),
    ),
  ],
);

// --------------------------------------------------------------------- issues

final _issues = WorkspaceTemplate(
  id: 'issues',
  category: TemplateCategory.work,
  label: () => LocaleKeys.templates_item_issues.tr(),
  description: () => LocaleKeys.templates_item_issuesHint.tr(),
  icon: Icons.bug_report_rounded,
  accent: DashboardAccent.red,
  keywords: const ['issues', 'bugs', 'backlog', 'tickets', 'sprint', 'tasks'],
  build: () => [
    TemplatePart(
      key: 'issues',
      icon: '🐞',
      name: () => LocaleKeys.templates_text_theBacklog.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_summary.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_status.tr(), [
              LocaleKeys.templates_option_todo.tr(),
              LocaleKeys.templates_option_doing.tr(),
              LocaleKeys.templates_option_review.tr(),
              LocaleKeys.templates_option_done.tr(),
            ]),
            TemplateColumn.select(LocaleKeys.templates_column_priority.tr(), [
              LocaleKeys.templates_option_urgent.tr(),
              LocaleKeys.templates_option_high.tr(),
              LocaleKeys.templates_option_normal.tr(),
              LocaleKeys.templates_option_low.tr(),
            ]),
            TemplateColumn.select(LocaleKeys.templates_column_kind.tr(), [
              LocaleKeys.templates_option_bug.tr(),
              LocaleKeys.templates_option_feature.tr(),
              LocaleKeys.templates_option_chore.tr(),
            ]),
            TemplateColumn.text(LocaleKeys.templates_column_owner.tr()),
            TemplateColumn.date(LocaleKeys.templates_column_due.tr()),
            TemplateColumn.number(LocaleKeys.templates_column_estimate.tr()),
          ],
          rows: [
            [
              LocaleKeys.templates_text_issueOne.tr(),
              LocaleKeys.templates_option_todo.tr(),
              LocaleKeys.templates_option_high.tr(),
              LocaleKeys.templates_option_bug.tr(),
              '',
              '',
              '2',
            ],
            [
              LocaleKeys.templates_text_issueTwo.tr(),
              LocaleKeys.templates_option_doing.tr(),
              LocaleKeys.templates_option_normal.tr(),
              LocaleKeys.templates_option_feature.tr(),
              '',
              '',
              '5',
            ],
            [
              LocaleKeys.templates_text_issueThree.tr(),
              LocaleKeys.templates_option_done.tr(),
              LocaleKeys.templates_option_low.tr(),
              LocaleKeys.templates_option_chore.tr(),
              '',
              '',
              '1',
            ],
          ],
        ),
      ),
    ),
    TemplatePart(
      key: 'board',
      icon: '🛠️',
      name: () => LocaleKeys.templates_item_issues.tr(),
      blueprint: TemplateDashboard(
        (created) {
          final issues = created['issues'];
          final name = LocaleKeys.templates_text_theBacklog.tr();
          final estimate = LocaleKeys.templates_column_estimate.tr();
          final status = LocaleKeys.templates_column_status.tr();
          final priority = LocaleKeys.templates_column_priority.tr();
          return document(
            [
              section([
                widget(
                  'metric',
                  w: 3,
                  h: 3,
                  title: LocaleKeys.templates_text_open.tr(),
                  accent: DashboardAccent.red,
                  settings: const {'aggregate': 'count'},
                  source: table(issues, name: name, field: estimate),
                ),
                widget(
                  'metric',
                  x: 3,
                  w: 3,
                  h: 3,
                  title: LocaleKeys.templates_text_pointsInFlight.tr(),
                  settings: const {'aggregate': 'sum'},
                  source: table(issues, name: name, field: estimate),
                ),
                widget(
                  'countdown',
                  x: 6,
                  w: 6,
                  h: 3,
                  title: LocaleKeys.templates_text_sprintEnds.tr(),
                  accent: DashboardAccent.purple,
                ),
              ]),
              section([
                widget(
                  'chart',
                  w: 6,
                  h: 6,
                  title: LocaleKeys.templates_text_byStatus.tr(),
                  accent: DashboardAccent.blue,
                  settings: const {'chart_type': 'bar'},
                  source: table(
                    issues,
                    name: name,
                    field: estimate,
                    groupField: status,
                  ),
                ),
                widget(
                  'chart',
                  x: 6,
                  w: 6,
                  h: 6,
                  title: LocaleKeys.templates_text_byPriority.tr(),
                  accent: DashboardAccent.red,
                  settings: const {'chart_type': 'donut'},
                  source: table(
                    issues,
                    name: name,
                    field: estimate,
                    groupField: priority,
                  ),
                ),
              ]),
              section(
                [
                  widget(
                    'database',
                    w: 12,
                    h: 10,
                    source: table(issues, name: name),
                  ),
                ],
                title: name,
              ),
            ],
            subtitle: LocaleKeys.templates_item_issuesHint.tr(),
          );
        },
      ),
    ),
  ],
);

// --------------------------------------------------------------- applications

final _applications = WorkspaceTemplate(
  id: 'applications',
  category: TemplateCategory.work,
  label: () => LocaleKeys.templates_item_applications.tr(),
  description: () => LocaleKeys.templates_item_applicationsHint.tr(),
  icon: Icons.work_outline_rounded,
  accent: DashboardAccent.teal,
  keywords: const ['job', 'applications', 'interview', 'hiring', 'career'],
  build: () => [
    TemplatePart(
      key: 'applications',
      icon: '💼',
      name: () => LocaleKeys.templates_item_applications.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_role.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_company.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_stage.tr(), [
              LocaleKeys.templates_option_saved.tr(),
              LocaleKeys.templates_option_applied.tr(),
              LocaleKeys.templates_option_screening.tr(),
              LocaleKeys.templates_option_interview.tr(),
              LocaleKeys.templates_option_offer.tr(),
              LocaleKeys.templates_option_closed.tr(),
            ]),
            TemplateColumn.date(LocaleKeys.templates_column_appliedOn.tr()),
            TemplateColumn.number(LocaleKeys.templates_column_salary.tr()),
            TemplateColumn.url(LocaleKeys.templates_column_posting.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_contact.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_notes.tr()),
          ],
          rows: [
            [
              '',
              '',
              LocaleKeys.templates_option_saved.tr(),
              '',
              '',
              '',
              '',
              '',
            ],
          ],
        ),
      ),
    ),
  ],
);
