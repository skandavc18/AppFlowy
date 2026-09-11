import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_templates.dart';
import 'package:appflowy/workspace/application/canvas/canvas_templates.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/built_in/everyday_templates.dart';
import 'package:appflowy/workspace/application/templates/built_in/finance_templates.dart';
import 'package:appflowy/workspace/application/templates/built_in/knowledge_templates.dart';
import 'package:appflowy/workspace/application/templates/built_in/publishing_templates.dart';
import 'package:appflowy/workspace/application/templates/built_in/work_templates.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Everything AppFlowy ships to start somebody from.
///
/// The dashboards and canvases that already existed are folded in here rather
/// than rewritten, so there is one gallery and not three — a canvas template
/// used to be reachable only by somebody who had already made a canvas.
void registerBuiltInTemplates() {
  registerEverydayTemplates();
  registerWorkTemplates();
  registerFinanceTemplates();
  registerKnowledgeTemplates();
  registerPublishingTemplates();
  _registerExistingDashboards();
  _registerExistingCanvases();
}

/// Which shelf each dashboard that already existed belongs on.
const _dashboardShelves = <String, TemplateCategory>{
  'personal': TemplateCategory.everyday,
  'weekly': TemplateCategory.everyday,
  'habits': TemplateCategory.everyday,
  'project': TemplateCategory.work,
  'developer': TemplateCategory.work,
  'crm': TemplateCategory.work,
  'content': TemplateCategory.work,
  'team': TemplateCategory.work,
  'executive': TemplateCategory.work,
  'finance': TemplateCategory.finance,
  'study': TemplateCategory.knowledge,
};

void _registerExistingDashboards() {
  for (final template in dashboardTemplates()) {
    final shelf = _dashboardShelves[template.id];
    if (shelf == null) {
      // 'blank' is not somewhere to start from; it is the absence of one.
      continue;
    }
    TemplateRegistry.register(
      WorkspaceTemplate(
        id: 'board_${template.id}',
        category: shelf,
        label: template.label,
        description: template.description,
        icon: template.icon,
        accent: template.accent,
        keywords: [template.id, 'dashboard'],
        build: () => [
          TemplatePart(
            key: 'board',
            name: template.label,
            blueprint: TemplateDashboard((_) => template.build()),
          ),
        ],
      ),
    );
  }
}

const _canvasShelves = <String, (TemplateCategory, IconData)>{
  'mind_map': (TemplateCategory.knowledge, Icons.account_tree_rounded),
  'study': (TemplateCategory.knowledge, Icons.school_rounded),
  'research': (TemplateCategory.knowledge, Icons.travel_explore_rounded),
  'brainstorm': (TemplateCategory.work, Icons.lightbulb_rounded),
  'project': (TemplateCategory.work, Icons.view_kanban_rounded),
  'architecture': (TemplateCategory.work, Icons.schema_rounded),
  'journey': (TemplateCategory.work, Icons.route_rounded),
  'swot': (TemplateCategory.work, Icons.grid_view_rounded),
  'kanban': (TemplateCategory.work, Icons.view_column_rounded),
  'meeting': (TemplateCategory.work, Icons.forum_rounded),
  'roadmap': (TemplateCategory.work, Icons.timeline_rounded),
};

void _registerExistingCanvases() {
  for (final template in canvasTemplates()) {
    final shelf = _canvasShelves[template.id];
    if (shelf == null) {
      continue;
    }
    TemplateRegistry.register(
      WorkspaceTemplate(
        id: 'canvas_${template.id}',
        category: shelf.$1,
        label: () => template.nameKey.tr(),
        description: () => template.descriptionKey.tr(),
        icon: shelf.$2,
        accent: DashboardAccent.paper,
        keywords: [template.id, 'canvas', 'whiteboard', 'diagram'],
        build: () => [
          TemplatePart(
            key: 'canvas',
            name: () => template.nameKey.tr(),
            blueprint: TemplateCanvas((_) => template.build()),
          ),
        ],
      ),
    );
  }
}

/// Named so the gallery can lead with the one somebody most likely wants.
const featuredTemplateIds = <String>[
  'board_personal',
  'tracker',
  'stocks',
  'assets',
  'news_weather',
  'landing',
  'quotes',
  'issues',
];

extension TemplateCategoryLabel on TemplateCategory {
  String get label => switch (this) {
        TemplateCategory.everyday =>
          LocaleKeys.templates_category_everyday.tr(),
        TemplateCategory.work => LocaleKeys.templates_category_work.tr(),
        TemplateCategory.finance => LocaleKeys.templates_category_finance.tr(),
        TemplateCategory.knowledge =>
          LocaleKeys.templates_category_knowledge.tr(),
        TemplateCategory.publishing =>
          LocaleKeys.templates_category_publishing.tr(),
      };

  IconData get icon => switch (this) {
        TemplateCategory.everyday => Icons.wb_sunny_rounded,
        TemplateCategory.work => Icons.work_rounded,
        TemplateCategory.finance => Icons.payments_rounded,
        TemplateCategory.knowledge => Icons.school_rounded,
        TemplateCategory.publishing => Icons.public_rounded,
      };
}

extension TemplateKindLabel on TemplateKind {
  String get label => switch (this) {
        TemplateKind.dashboard => LocaleKeys.templates_kind_dashboard.tr(),
        TemplateKind.page => LocaleKeys.templates_kind_page.tr(),
        TemplateKind.database => LocaleKeys.templates_kind_database.tr(),
        TemplateKind.canvas => LocaleKeys.templates_kind_canvas.tr(),
        TemplateKind.bundle => LocaleKeys.templates_kind_bundle.tr(),
      };

  IconData get icon => switch (this) {
        TemplateKind.dashboard => Icons.dashboard_rounded,
        TemplateKind.page => Icons.article_rounded,
        TemplateKind.database => Icons.table_chart_rounded,
        TemplateKind.canvas => Icons.gesture_rounded,
        TemplateKind.bundle => Icons.folder_copy_rounded,
      };
}
