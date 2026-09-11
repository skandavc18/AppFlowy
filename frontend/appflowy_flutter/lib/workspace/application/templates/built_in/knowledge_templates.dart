import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/built_in/template_pieces.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Things worth keeping: what has been read, cooked, learned, or is still to be.
void registerKnowledgeTemplates() {
  TemplateRegistry.register(_reading);
  TemplateRegistry.register(_recipes);
  TemplateRegistry.register(_research);
}

// -------------------------------------------------------------------- reading

final _reading = WorkspaceTemplate(
  id: 'reading',
  category: TemplateCategory.knowledge,
  label: () => LocaleKeys.templates_item_reading.tr(),
  description: () => LocaleKeys.templates_item_readingHint.tr(),
  icon: Icons.menu_book_rounded,
  accent: DashboardAccent.amber,
  keywords: const ['reading', 'books', 'library', 'shelf', 'to read'],
  build: () => [
    TemplatePart(
      key: 'books',
      icon: '📚',
      name: () => LocaleKeys.templates_text_theShelf.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_title.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_author.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_status.tr(), [
              LocaleKeys.templates_option_toRead.tr(),
              LocaleKeys.templates_option_reading.tr(),
              LocaleKeys.templates_option_finished.tr(),
              LocaleKeys.templates_option_abandoned.tr(),
            ]),
            TemplateColumn.number(LocaleKeys.templates_column_rating.tr()),
            TemplateColumn.number(LocaleKeys.templates_column_pages.tr()),
            TemplateColumn.multiSelect(LocaleKeys.templates_column_theme.tr(), [
              LocaleKeys.templates_option_fiction.tr(),
              LocaleKeys.templates_option_history.tr(),
              LocaleKeys.templates_option_science.tr(),
              LocaleKeys.templates_option_craft.tr(),
            ]),
            TemplateColumn.date(LocaleKeys.templates_column_finishedOn.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_notes.tr()),
          ],
          rows: [
            [
              '',
              '',
              LocaleKeys.templates_option_toRead.tr(),
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
    TemplatePart(
      key: 'board',
      icon: '📖',
      name: () => LocaleKeys.templates_item_reading.tr(),
      blueprint: TemplateDashboard(
        (created) {
          final books = created['books'];
          final name = LocaleKeys.templates_text_theShelf.tr();
          final pages = LocaleKeys.templates_column_pages.tr();
          final status = LocaleKeys.templates_column_status.tr();
          return document(
            [
              section([
                widget(
                  'progress',
                  h: 3,
                  title: LocaleKeys.templates_text_thisYear.tr(),
                  accent: DashboardAccent.amber,
                  settings: const {
                    'value': 0,
                    'target': 24,
                    'style': 'ring',
                  },
                ),
                widget(
                  'metric',
                  x: 4,
                  h: 3,
                  title: LocaleKeys.templates_text_onTheShelf.tr(),
                  settings: const {'aggregate': 'count'},
                  source: table(books, name: name, field: pages),
                ),
                widget(
                  'metric',
                  x: 8,
                  h: 3,
                  title: LocaleKeys.templates_text_pagesRead.tr(),
                  accent: DashboardAccent.teal,
                  settings: const {'aggregate': 'sum'},
                  source: table(books, name: name, field: pages),
                ),
              ]),
              section([
                widget(
                  'database',
                  w: 8,
                  h: 9,
                  source: table(books, name: name),
                ),
                widget(
                  'chart',
                  x: 8,
                  h: 9,
                  title: LocaleKeys.templates_text_byStatus.tr(),
                  accent: DashboardAccent.amber,
                  settings: const {'chart_type': 'donut'},
                  source: table(
                    books,
                    name: name,
                    field: pages,
                    groupField: status,
                  ),
                ),
              ]),
            ],
            subtitle: LocaleKeys.templates_item_readingHint.tr(),
          );
        },
      ),
    ),
  ],
);

// -------------------------------------------------------------------- recipes

final _recipes = WorkspaceTemplate(
  id: 'recipes',
  category: TemplateCategory.knowledge,
  label: () => LocaleKeys.templates_item_recipes.tr(),
  description: () => LocaleKeys.templates_item_recipesHint.tr(),
  icon: Icons.restaurant_rounded,
  accent: DashboardAccent.orange,
  keywords: const ['recipes', 'cooking', 'food', 'kitchen', 'meals'],
  build: () => [
    TemplatePart(
      key: 'recipes',
      icon: '🍳',
      name: () => LocaleKeys.templates_item_recipes.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_dish.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_course.tr(), [
              LocaleKeys.templates_option_breakfast.tr(),
              LocaleKeys.templates_option_lunch.tr(),
              LocaleKeys.templates_option_dinner.tr(),
              LocaleKeys.templates_option_pudding.tr(),
            ]),
            TemplateColumn.number(LocaleKeys.templates_column_minutes.tr()),
            TemplateColumn.number(LocaleKeys.templates_column_serves.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_effort.tr(), [
              LocaleKeys.templates_option_easy.tr(),
              LocaleKeys.templates_option_someWork.tr(),
              LocaleKeys.templates_option_project.tr(),
            ]),
            TemplateColumn.checkbox(LocaleKeys.templates_column_favourite.tr()),
            TemplateColumn.url(LocaleKeys.templates_column_link.tr()),
          ],
          rows: [
            [
              '',
              LocaleKeys.templates_option_dinner.tr(),
              '30',
              '2',
              LocaleKeys.templates_option_easy.tr(),
              'no',
              '',
            ],
          ],
        ),
      ),
    ),
  ],
);

// ------------------------------------------------------------------- research

final _research = WorkspaceTemplate(
  id: 'research',
  category: TemplateCategory.knowledge,
  label: () => LocaleKeys.templates_item_research.tr(),
  description: () => LocaleKeys.templates_item_researchHint.tr(),
  icon: Icons.science_rounded,
  accent: DashboardAccent.purple,
  keywords: const ['research', 'sources', 'notes', 'study', 'literature'],
  build: () => [
    TemplatePart(
      key: 'page',
      icon: '🔬',
      name: () => LocaleKeys.templates_item_research.tr(),
      blueprint: TemplatePage((_) => LocaleKeys.templates_page_research.tr()),
    ),
    TemplatePart(
      key: 'sources',
      icon: '🗂️',
      name: () => LocaleKeys.templates_text_sources.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_title.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_author.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_kind.tr(), [
              LocaleKeys.templates_option_paper.tr(),
              LocaleKeys.templates_option_book.tr(),
              LocaleKeys.templates_option_article.tr(),
              LocaleKeys.templates_option_talk.tr(),
            ]),
            TemplateColumn.number(LocaleKeys.templates_column_year.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_status.tr(), [
              LocaleKeys.templates_option_toRead.tr(),
              LocaleKeys.templates_option_reading.tr(),
              LocaleKeys.templates_option_finished.tr(),
            ]),
            TemplateColumn.url(LocaleKeys.templates_column_link.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_takeaway.tr()),
          ],
          rows: [
            [
              '',
              '',
              LocaleKeys.templates_option_paper.tr(),
              '',
              LocaleKeys.templates_option_toRead.tr(),
              '',
              '',
            ],
          ],
        ),
      ),
    ),
  ],
);
