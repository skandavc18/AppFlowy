import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A dashboard somebody can start from.
///
/// A template is only a starting arrangement — nothing in it is special and
/// everything in it can be moved, reconfigured or thrown away, because it is
/// built out of exactly the same widgets the "Add" panel offers.
@immutable
class DashboardTemplate {
  const DashboardTemplate({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.build,
    this.accent = DashboardAccent.neutral,
  });

  final String id;
  final String Function() label;
  final String Function() description;
  final IconData icon;
  final DashboardAccent accent;
  final DashboardDocument Function() build;
}

/// Every template AppFlowy ships.
List<DashboardTemplate> dashboardTemplates() => [
      _blank,
      _personal,
      _project,
      _weeklyPlanner,
      _finance,
      _developer,
      _study,
      _habits,
      _crm,
      _contentCalendar,
      _team,
      _executive,
    ];

DashboardTemplate? dashboardTemplateFor(String id) =>
    dashboardTemplates().where((template) => template.id == id).firstOrNull;

// ---------------------------------------------------------------- the pieces

DashboardWidgetSpec _widget(
  String type, {
  int x = 0,
  int y = 0,
  int w = 4,
  int h = 4,
  String title = '',
  bool showTitle = true,
  DashboardAccent accent = DashboardAccent.neutral,
  Map<String, Object?> settings = const {},
  List<DashboardAction> actions = const [],
  Map<String, String> bindings = const {},
}) =>
    DashboardWidgetSpec(
      id: newDashboardId('w'),
      type: type,
      placement:
          DashboardPlacement(column: x, row: y, columnSpan: w, rowSpan: h),
      title: title,
      showTitle: showTitle && title.isNotEmpty,
      accent: accent,
      settings: settings,
      actions: actions,
      bindings: bindings,
    );

DashboardSection _section(
  List<DashboardWidgetSpec> widgets, {
  String title = '',
}) =>
    DashboardSection(
      id: newDashboardId('section'),
      title: title,
      widgets: widgets,
    );

DashboardDocument _document(
  List<DashboardSection> sections, {
  List<DashboardVariable> variables = const [],
  DashboardSettings settings = const DashboardSettings(),
  String subtitle = '',
}) =>
    DashboardDocument(
      sections: sections,
      variables: variables,
      settings: settings,
      subtitle: subtitle,
    );

DashboardOption _option(String label) =>
    DashboardOption(id: newDashboardId('o'), label: label);

// ------------------------------------------------------------------ templates

final _blank = DashboardTemplate(
  id: 'blank',
  label: () => LocaleKeys.dashboard_template_blank.tr(),
  description: () => LocaleKeys.dashboard_template_blankHint.tr(),
  icon: Icons.dashboard_customize_rounded,
  build: DashboardDocument.blank,
);

final _personal = DashboardTemplate(
  id: 'personal',
  label: () => LocaleKeys.dashboard_template_personal.tr(),
  description: () => LocaleKeys.dashboard_template_personalHint.tr(),
  icon: Icons.home_rounded,
  accent: DashboardAccent.blue,
  build: () => _document(
    [
      _section([
        _widget(
          'heading',
          w: 12,
          h: 1,
          settings: {'text': LocaleKeys.dashboard_template_goodDay.tr()},
        ),
        _widget('clock', y: 1, w: 3, h: 3, accent: DashboardAccent.blue),
        _widget('weather', x: 3, y: 1, w: 3, h: 3),
        _widget(
          'reminders',
          x: 6,
          y: 1,
          w: 6,
          h: 6,
          title: LocaleKeys.dashboard_template_upNext.tr(),
        ),
        _widget(
          'checklist',
          y: 4,
          w: 6,
          h: 6,
          title: LocaleKeys.dashboard_template_today.tr(),
          accent: DashboardAccent.green,
        ),
      ]),
      _section(
        [
          _widget('calendar', w: 5, h: 7),
          _widget(
            'sticky_note',
            x: 5,
            w: 3,
            h: 7,
            settings: {'text': LocaleKeys.dashboard_template_noteHint.tr()},
          ),
          _widget(
            'page_link',
            x: 8,
            h: 2,
            settings: {},
          ),
          _widget('page_link', x: 8, y: 2, h: 2, settings: {}),
          _widget(
            'countdown',
            x: 8,
            y: 4,
            h: 3,
            title: LocaleKeys.dashboard_template_lookingForwardTo.tr(),
            accent: DashboardAccent.purple,
          ),
        ],
        title: LocaleKeys.dashboard_template_thisWeek.tr(),
      ),
      _section(
        [
          _widget(
            'input',
            w: 12,
            h: 2,
            settings: {'search_workspace': true},
          ),
          _widget(
            'progress',
            y: 2,
            h: 3,
            title: LocaleKeys.dashboard_template_thisMonth.tr(),
            accent: DashboardAccent.green,
            settings: {'value': 0, 'target': 20, 'style': 'ring'},
          ),
          _widget(
            'counter',
            x: 4,
            y: 2,
            h: 3,
            title: LocaleKeys.dashboard_template_daysInARow.tr(),
            accent: DashboardAccent.amber,
            settings: {'value': 0, 'step': 1},
          ),
          _widget(
            'quote',
            x: 8,
            y: 2,
            h: 3,
            accent: DashboardAccent.paper,
            settings: {
              'text': LocaleKeys.dashboard_template_homeQuote.tr(),
              'author': 'Annie Dillard',
            },
          ),
        ],
        title: LocaleKeys.dashboard_template_keepAnEyeOn.tr(),
      ),
    ],
    subtitle: LocaleKeys.dashboard_template_personalHint.tr(),
  ),
);

final _project = DashboardTemplate(
  id: 'project',
  label: () => LocaleKeys.dashboard_template_project.tr(),
  description: () => LocaleKeys.dashboard_template_projectHint.tr(),
  icon: Icons.rocket_launch_rounded,
  accent: DashboardAccent.purple,
  build: () {
    const projectKey = 'project';
    return _document(
      [
        _section([
          _widget(
            'metric',
            w: 3,
            h: 3,
            title: LocaleKeys.dashboard_template_openTasks.tr(),
            accent: DashboardAccent.purple,
            bindings: const {'filter': projectKey},
          ),
          _widget(
            'metric',
            x: 3,
            w: 3,
            h: 3,
            title: LocaleKeys.dashboard_template_dueThisWeek.tr(),
            accent: DashboardAccent.orange,
          ),
          _widget(
            'progress',
            x: 6,
            w: 6,
            h: 3,
            title: LocaleKeys.dashboard_template_completion.tr(),
            accent: DashboardAccent.green,
            settings: const {'style': 'bar', 'target': 100},
          ),
        ]),
        _section(
          [
            _widget(
              'database',
              w: 8,
              h: 9,
              title: LocaleKeys.dashboard_template_tasks.tr(),
              bindings: const {'filter': projectKey},
            ),
            _widget(
              'chart',
              x: 8,
              h: 5,
              title: LocaleKeys.dashboard_template_byStatus.tr(),
            ),
            _widget(
              'reminders',
              x: 8,
              y: 5,
              title: LocaleKeys.dashboard_template_milestones.tr(),
            ),
          ],
          title: LocaleKeys.dashboard_template_work.tr(),
        ),
      ],
      variables: [
        DashboardVariable(
          key: projectKey,
          label: LocaleKeys.dashboard_template_project.tr(),
          options: [
            _option('Alpha'),
            _option('Beta'),
            _option('Gamma'),
          ],
        ),
        const DashboardVariable(
          key: 'period',
          label: 'Period',
          kind: DashboardVariableKind.period,
        ),
      ],
    );
  },
);

final _weeklyPlanner = DashboardTemplate(
  id: 'weekly',
  label: () => LocaleKeys.dashboard_template_weekly.tr(),
  description: () => LocaleKeys.dashboard_template_weeklyHint.tr(),
  icon: Icons.view_week_rounded,
  accent: DashboardAccent.teal,
  build: () => _document([
    _section([
      _widget('calendar', h: 7),
      _widget(
        'checklist',
        x: 4,
        h: 7,
        title: LocaleKeys.dashboard_template_priorities.tr(),
        accent: DashboardAccent.teal,
      ),
      _widget(
        'reminders',
        x: 8,
        h: 7,
        title: LocaleKeys.dashboard_template_upNext.tr(),
      ),
    ]),
    _section(
      [
        for (var day = 0; day < 4; day++)
          _widget(
            'checklist',
            x: day * 3,
            w: 3,
            h: 6,
          ),
      ],
      title: LocaleKeys.dashboard_template_days.tr(),
    ),
  ]),
);

final _finance = DashboardTemplate(
  id: 'finance',
  label: () => LocaleKeys.dashboard_template_finance.tr(),
  description: () => LocaleKeys.dashboard_template_financeHint.tr(),
  icon: Icons.savings_rounded,
  accent: DashboardAccent.green,
  build: () => _document([
    _section([
      _widget(
        'metric',
        w: 3,
        h: 3,
        title: LocaleKeys.dashboard_template_balance.tr(),
        accent: DashboardAccent.green,
        settings: const {'prefix': r'$'},
      ),
      _widget(
        'metric',
        x: 3,
        w: 3,
        h: 3,
        title: LocaleKeys.dashboard_template_spent.tr(),
        accent: DashboardAccent.red,
        settings: const {'prefix': r'$'},
      ),
      _widget(
        'progress',
        x: 6,
        w: 6,
        h: 3,
        title: LocaleKeys.dashboard_template_budget.tr(),
        settings: const {'style': 'ring'},
      ),
    ]),
    _section([
      _widget(
        'chart',
        w: 7,
        h: 7,
        title: LocaleKeys.dashboard_template_spending.tr(),
      ),
      _widget(
        'database',
        x: 7,
        w: 5,
        h: 7,
        title: LocaleKeys.dashboard_template_transactions.tr(),
      ),
    ]),
  ]),
);

final _developer = DashboardTemplate(
  id: 'developer',
  label: () => LocaleKeys.dashboard_template_developer.tr(),
  description: () => LocaleKeys.dashboard_template_developerHint.tr(),
  icon: Icons.terminal_rounded,
  accent: DashboardAccent.purple,
  build: () => _document([
    _section([
      _widget(
        'metric',
        w: 3,
        h: 3,
        title: LocaleKeys.dashboard_template_openIssues.tr(),
        accent: DashboardAccent.orange,
      ),
      _widget(
        'metric',
        x: 3,
        w: 3,
        h: 3,
        title: LocaleKeys.dashboard_template_pullRequests.tr(),
        accent: DashboardAccent.purple,
      ),
      _widget(
        'list',
        x: 6,
        w: 6,
        h: 6,
        title: LocaleKeys.dashboard_template_repositories.tr(),
      ),
    ]),
    _section([
      _widget(
        'database',
        w: 6,
        h: 8,
        title: LocaleKeys.dashboard_template_backlog.tr(),
      ),
      _widget(
        'checklist',
        x: 6,
        w: 3,
        h: 8,
        title: LocaleKeys.dashboard_template_today.tr(),
      ),
      _widget(
        'bookmark',
        x: 9,
        w: 3,
        h: 2,
        settings: const {'url': 'https://github.com'},
      ),
      _widget('clock', x: 9, y: 2, w: 3, h: 3),
    ]),
  ]),
);

final _study = DashboardTemplate(
  id: 'study',
  label: () => LocaleKeys.dashboard_template_study.tr(),
  description: () => LocaleKeys.dashboard_template_studyHint.tr(),
  icon: Icons.school_rounded,
  accent: DashboardAccent.blue,
  build: () => _document(
    [
      _section([
        _widget(
          'countdown',
          w: 3,
          h: 3,
          title: LocaleKeys.dashboard_template_nextExam.tr(),
          accent: DashboardAccent.orange,
        ),
        _widget(
          'progress',
          x: 3,
          w: 5,
          h: 3,
          title: LocaleKeys.dashboard_template_syllabus.tr(),
        ),
        _widget('clock', x: 8, h: 3),
      ]),
      _section([
        _widget(
          'list',
          h: 8,
          title: LocaleKeys.dashboard_template_notes.tr(),
          bindings: const {'filter': 'subject'},
        ),
        _widget(
          'checklist',
          x: 4,
          h: 8,
          title: LocaleKeys.dashboard_template_revision.tr(),
        ),
        _widget('calendar', x: 8, h: 8),
      ]),
    ],
    variables: [
      DashboardVariable(
        key: 'subject',
        label: LocaleKeys.dashboard_template_subject.tr(),
        options: [_option('Maths'), _option('Physics'), _option('History')],
      ),
    ],
  ),
);

final _habits = DashboardTemplate(
  id: 'habits',
  label: () => LocaleKeys.dashboard_template_habits.tr(),
  description: () => LocaleKeys.dashboard_template_habitsHint.tr(),
  icon: Icons.local_fire_department_rounded,
  accent: DashboardAccent.orange,
  build: () => _document([
    _section([
      _widget(
        'counter',
        w: 3,
        h: 3,
        title: LocaleKeys.dashboard_template_streak.tr(),
        accent: DashboardAccent.orange,
      ),
      _widget(
        'progress',
        x: 3,
        w: 5,
        h: 3,
        title: LocaleKeys.dashboard_template_thisWeek.tr(),
        settings: const {'style': 'ring'},
      ),
      _widget('clock', x: 8, h: 3),
    ]),
    _section([
      _widget(
        'checklist',
        h: 7,
        title: LocaleKeys.dashboard_template_morning.tr(),
      ),
      _widget(
        'checklist',
        x: 4,
        h: 7,
        title: LocaleKeys.dashboard_template_evening.tr(),
      ),
      _widget(
        'chart',
        x: 8,
        h: 7,
        title: LocaleKeys.dashboard_template_history.tr(),
      ),
    ]),
  ]),
);

final _crm = DashboardTemplate(
  id: 'crm',
  label: () => LocaleKeys.dashboard_template_crm.tr(),
  description: () => LocaleKeys.dashboard_template_crmHint.tr(),
  icon: Icons.handshake_rounded,
  accent: DashboardAccent.teal,
  build: () => _document(
    [
      _section([
        _widget(
          'metric',
          w: 3,
          h: 3,
          title: LocaleKeys.dashboard_template_openDeals.tr(),
        ),
        _widget(
          'metric',
          x: 3,
          w: 3,
          h: 3,
          title: LocaleKeys.dashboard_template_pipeline.tr(),
          accent: DashboardAccent.teal,
          settings: const {'prefix': r'$'},
        ),
        _widget(
          'chart',
          x: 6,
          w: 6,
          h: 6,
          title: LocaleKeys.dashboard_template_byStage.tr(),
        ),
      ]),
      _section([
        _widget(
          'database',
          w: 12,
          h: 9,
          title: LocaleKeys.dashboard_template_contacts.tr(),
          bindings: const {'filter': 'stage'},
        ),
      ]),
    ],
    variables: [
      DashboardVariable(
        key: 'stage',
        label: LocaleKeys.dashboard_template_stage.tr(),
        options: [_option('Lead'), _option('Proposal'), _option('Won')],
      ),
    ],
  ),
);

final _contentCalendar = DashboardTemplate(
  id: 'content',
  label: () => LocaleKeys.dashboard_template_content.tr(),
  description: () => LocaleKeys.dashboard_template_contentHint.tr(),
  icon: Icons.edit_calendar_rounded,
  accent: DashboardAccent.pink,
  build: () => _document([
    _section([
      _widget(
        'database',
        w: 8,
        h: 9,
        title: LocaleKeys.dashboard_template_pipelineBoard.tr(),
      ),
      _widget('calendar', x: 8, h: 6),
      _widget(
        'counter',
        x: 8,
        y: 6,
        h: 3,
        title: LocaleKeys.dashboard_template_published.tr(),
        accent: DashboardAccent.pink,
      ),
    ]),
  ]),
);

final _team = DashboardTemplate(
  id: 'team',
  label: () => LocaleKeys.dashboard_template_team.tr(),
  description: () => LocaleKeys.dashboard_template_teamHint.tr(),
  icon: Icons.groups_rounded,
  accent: DashboardAccent.blue,
  build: () => _document(
    [
      _section([
        _widget(
          'callout',
          w: 12,
          h: 2,
          accent: DashboardAccent.blue,
          settings: {
            'icon': '📣',
            'text': LocaleKeys.dashboard_template_announcement.tr(),
          },
        ),
      ]),
      _section([
        _widget(
          'database',
          w: 7,
          h: 8,
          title: LocaleKeys.dashboard_template_workload.tr(),
          bindings: const {'filter': 'person'},
        ),
        _widget(
          'list',
          x: 7,
          w: 5,
          title: LocaleKeys.dashboard_template_documents.tr(),
        ),
        _widget(
          'reminders',
          x: 7,
          y: 4,
          w: 5,
          title: LocaleKeys.dashboard_template_deadlines.tr(),
        ),
      ]),
    ],
    variables: [
      DashboardVariable(
        key: 'person',
        label: LocaleKeys.dashboard_template_person.tr(),
        options: [_option('Everyone')],
      ),
    ],
  ),
);

final _executive = DashboardTemplate(
  id: 'executive',
  label: () => LocaleKeys.dashboard_template_executive.tr(),
  description: () => LocaleKeys.dashboard_template_executiveHint.tr(),
  icon: Icons.insights_rounded,
  accent: DashboardAccent.purple,
  build: () => _document(
    [
      _section([
        for (var index = 0; index < 4; index++)
          _widget(
            'metric',
            x: index * 3,
            w: 3,
            h: 3,
            title: LocaleKeys.dashboard_template_keyFigure.tr(),
            accent: DashboardAccent
                .values[(index * 2 + 2) % DashboardAccent.values.length],
          ),
      ]),
      _section([
        _widget(
          'chart',
          w: 8,
          h: 7,
          title: LocaleKeys.dashboard_template_trend.tr(),
        ),
        _widget(
          'progress',
          x: 8,
          h: 3,
          title: LocaleKeys.dashboard_template_target.tr(),
          settings: const {'style': 'ring'},
        ),
        _widget(
          'list',
          x: 8,
          y: 3,
          title: LocaleKeys.dashboard_template_reports.tr(),
        ),
      ]),
    ],
    variables: [
      const DashboardVariable(
        key: 'period',
        label: 'Period',
        kind: DashboardVariableKind.period,
      ),
    ],
  ),
);
