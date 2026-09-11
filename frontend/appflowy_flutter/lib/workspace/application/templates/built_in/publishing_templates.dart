import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Pages written to be read by somebody else.
void registerPublishingTemplates() {
  TemplateRegistry.register(_landing);
  TemplateRegistry.register(_resume);
  TemplateRegistry.register(_changelog);
  TemplateRegistry.register(_announcement);
}

WorkspaceTemplate _page({
  required String id,
  required TemplateCategory category,
  required IconData icon,
  required String Function() label,
  required String Function() description,
  required String Function() body,
  required String emoji,
  DashboardAccent accent = DashboardAccent.neutral,
  List<String> keywords = const [],
}) =>
    WorkspaceTemplate(
      id: id,
      category: category,
      label: label,
      description: description,
      icon: icon,
      accent: accent,
      keywords: keywords,
      build: () => [
        TemplatePart(
          key: 'page',
          icon: emoji,
          name: label,
          blueprint: TemplatePage((_) => body()),
        ),
      ],
    );

final _landing = _page(
  id: 'landing',
  category: TemplateCategory.publishing,
  icon: Icons.rocket_launch_rounded,
  emoji: '🚀',
  accent: DashboardAccent.blue,
  keywords: const [
    'landing',
    'marketing',
    'product',
    'launch',
    'website',
    'pitch',
  ],
  label: () => LocaleKeys.templates_item_landing.tr(),
  description: () => LocaleKeys.templates_item_landingHint.tr(),
  body: () => LocaleKeys.templates_page_landing.tr(),
);

final _resume = _page(
  id: 'resume',
  category: TemplateCategory.publishing,
  icon: Icons.badge_rounded,
  emoji: '📄',
  accent: DashboardAccent.paper,
  keywords: const ['resume', 'cv', 'career', 'job', 'profile'],
  label: () => LocaleKeys.templates_item_resume.tr(),
  description: () => LocaleKeys.templates_item_resumeHint.tr(),
  body: () => LocaleKeys.templates_page_resume.tr(),
);

final _changelog = _page(
  id: 'changelog',
  category: TemplateCategory.publishing,
  icon: Icons.history_rounded,
  emoji: '🧾',
  accent: DashboardAccent.teal,
  keywords: const ['changelog', 'release', 'notes', 'version', 'shipped'],
  label: () => LocaleKeys.templates_item_changelog.tr(),
  description: () => LocaleKeys.templates_item_changelogHint.tr(),
  body: () => LocaleKeys.templates_page_changelog.tr(),
);

final _announcement = _page(
  id: 'announcement',
  category: TemplateCategory.publishing,
  icon: Icons.campaign_rounded,
  emoji: '📣',
  accent: DashboardAccent.orange,
  keywords: const ['announcement', 'memo', 'update', 'broadcast', 'news'],
  label: () => LocaleKeys.templates_item_announcement.tr(),
  description: () => LocaleKeys.templates_item_announcementHint.tr(),
  body: () => LocaleKeys.templates_page_announcement.tr(),
);
