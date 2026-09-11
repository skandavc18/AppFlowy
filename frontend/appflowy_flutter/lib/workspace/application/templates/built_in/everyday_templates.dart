import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/built_in/template_pieces.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The things somebody opens every day.
void registerEverydayTemplates() {
  TemplateRegistry.register(_tracker);
  TemplateRegistry.register(_newsAndWeather);
  TemplateRegistry.register(_quotes);
  TemplateRegistry.register(_dailyNote);
  TemplateRegistry.register(_travel);
}

Map<String, Object?> _check(String label, {bool done = false}) => {
      'label': label,
      'done': done,
    };

// -------------------------------------------------------------------- tracker

final _tracker = WorkspaceTemplate(
  id: 'tracker',
  category: TemplateCategory.everyday,
  label: () => LocaleKeys.templates_item_tracker.tr(),
  description: () => LocaleKeys.templates_item_trackerHint.tr(),
  icon: Icons.track_changes_rounded,
  accent: DashboardAccent.green,
  keywords: const [
    'tracker',
    'reminder',
    'habits',
    'streak',
    'goals',
    'routine',
    'todo',
  ],
  build: () => [
    TemplatePart(
      key: 'board',
      icon: '🎯',
      name: () => LocaleKeys.templates_item_tracker.tr(),
      blueprint: TemplateDashboard(
        (_) => document(
          [
            section([
              heading(LocaleKeys.templates_text_today.tr()),
              widget(
                'reminders',
                y: 1,
                w: 5,
                h: 7,
                title: LocaleKeys.templates_text_dueNow.tr(),
                accent: DashboardAccent.red,
              ),
              widget(
                'checklist',
                x: 5,
                y: 1,
                h: 7,
                title: LocaleKeys.templates_text_habits.tr(),
                accent: DashboardAccent.green,
                settings: {
                  'items': [
                    _check(LocaleKeys.templates_text_habitMove.tr()),
                    _check(LocaleKeys.templates_text_habitRead.tr()),
                    _check(LocaleKeys.templates_text_habitWater.tr()),
                    _check(LocaleKeys.templates_text_habitSleep.tr()),
                  ],
                },
              ),
              widget(
                'clock',
                x: 9,
                y: 1,
                w: 3,
                h: 3,
                settings: const {'show_date': true},
              ),
              widget(
                'counter',
                x: 9,
                y: 4,
                w: 3,
                title: LocaleKeys.templates_text_streak.tr(),
                accent: DashboardAccent.amber,
                settings: const {'value': 0, 'step': 1},
              ),
            ]),
            section(
              [
                widget(
                  'progress',
                  h: 3,
                  title: LocaleKeys.templates_text_weeklyGoal.tr(),
                  accent: DashboardAccent.green,
                  settings: const {
                    'value': 0,
                    'target': 5,
                    'style': 'ring',
                  },
                ),
                widget(
                  'progress',
                  x: 4,
                  h: 3,
                  title: LocaleKeys.templates_text_monthlyGoal.tr(),
                  accent: DashboardAccent.teal,
                  settings: const {'value': 0, 'target': 20},
                ),
                widget(
                  'countdown',
                  x: 8,
                  h: 3,
                  title: LocaleKeys.templates_text_nextMilestone.tr(),
                  accent: DashboardAccent.purple,
                ),
              ],
              title: LocaleKeys.templates_text_howItIsGoing.tr(),
            ),
            section(
              [
                widget('calendar', w: 8, h: 8),
                note(
                  LocaleKeys.templates_text_trackerNote.tr(),
                  x: 8,
                  h: 8,
                  accent: DashboardAccent.amber,
                ),
              ],
              title: LocaleKeys.templates_text_theMonth.tr(),
            ),
          ],
          subtitle: LocaleKeys.templates_item_trackerHint.tr(),
        ),
      ),
    ),
  ],
);

// ----------------------------------------------------------- news and weather

final _newsAndWeather = WorkspaceTemplate(
  id: 'news_weather',
  category: TemplateCategory.everyday,
  label: () => LocaleKeys.templates_item_newsWeather.tr(),
  description: () => LocaleKeys.templates_item_newsWeatherHint.tr(),
  icon: Icons.newspaper_rounded,
  accent: DashboardAccent.blue,
  keywords: const [
    'news',
    'weather',
    'headlines',
    'rss',
    'morning',
    'briefing',
  ],
  requires: const {'news'},
  build: () => [
    TemplatePart(
      key: 'board',
      icon: '🗞️',
      name: () => LocaleKeys.templates_item_newsWeather.tr(),
      blueprint: TemplateDashboard(
        (_) => document(
          [
            section([
              widget(
                'clock',
                w: 3,
                accent: DashboardAccent.blue,
                settings: const {'show_date': true},
              ),
              widget('weather', x: 3),
              note(
                LocaleKeys.templates_text_briefingNote.tr(),
                x: 7,
                w: 5,
                accent: DashboardAccent.paper,
              ),
            ]),
            section(
              [
                widget(
                  'ext.news.feed',
                  h: 9,
                  settings: const {
                    'url': 'https://feeds.bbci.co.uk/news/world/rss.xml',
                    'label': 'BBC World',
                    'count': 8,
                    'showSummary': false,
                    'showImages': true,
                  },
                ),
                widget(
                  'ext.news.feed',
                  x: 4,
                  h: 9,
                  settings: const {
                    'url':
                        'https://economictimes.indiatimes.com/rssfeedstopstories.cms',
                    'label': 'Economic Times',
                    'count': 8,
                    'showSummary': false,
                    'showImages': true,
                  },
                ),
                widget(
                  'ext.news.feed',
                  x: 8,
                  h: 9,
                  settings: const {
                    'url': 'https://hnrss.org/frontpage',
                    'label': 'Hacker News',
                    'count': 10,
                    'showSummary': false,
                    'showImages': false,
                  },
                ),
              ],
              title: LocaleKeys.templates_text_headlines.tr(),
            ),
          ],
          subtitle: LocaleKeys.templates_item_newsWeatherHint.tr(),
        ),
      ),
    ),
  ],
);

// --------------------------------------------------------------------- quotes

final _quotes = WorkspaceTemplate(
  id: 'quotes',
  category: TemplateCategory.everyday,
  label: () => LocaleKeys.templates_item_quotes.tr(),
  description: () => LocaleKeys.templates_item_quotesHint.tr(),
  icon: Icons.format_quote_rounded,
  accent: DashboardAccent.purple,
  keywords: const [
    'quotes',
    'quotations',
    'sayings',
    'inspiration',
    'commonplace',
  ],
  build: () => [
    TemplatePart(
      key: 'quotes',
      icon: '💬',
      name: () => LocaleKeys.templates_text_theQuotes.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_quote.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_whoSaidIt.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_whereFrom.tr()),
            TemplateColumn.multiSelect(LocaleKeys.templates_column_theme.tr(), [
              LocaleKeys.templates_option_work.tr(),
              LocaleKeys.templates_option_life.tr(),
              LocaleKeys.templates_option_craft.tr(),
              LocaleKeys.templates_option_courage.tr(),
              LocaleKeys.templates_option_stillness.tr(),
            ]),
            TemplateColumn.checkbox(
              LocaleKeys.templates_column_favourite.tr(),
            ),
            TemplateColumn.date(LocaleKeys.templates_column_added.tr()),
          ],
          rows: [
            [
              'The obstacle is the way.',
              'Marcus Aurelius',
              'Meditations',
              LocaleKeys.templates_option_courage.tr(),
              'yes',
              '',
            ],
            [
              'Simplicity is the ultimate sophistication.',
              'Leonardo da Vinci',
              '',
              LocaleKeys.templates_option_craft.tr(),
              'no',
              '',
            ],
            [
              'It does not matter how slowly you go, so long as you do not stop.',
              'Confucius',
              '',
              LocaleKeys.templates_option_life.tr(),
              'no',
              '',
            ],
          ],
        ),
      ),
    ),
    TemplatePart(
      key: 'board',
      icon: '📜',
      name: () => LocaleKeys.templates_item_quotes.tr(),
      blueprint: TemplateDashboard(
        (created) {
          final quotes = created['quotes'];
          final name = LocaleKeys.templates_text_theQuotes.tr();
          final theme = LocaleKeys.templates_column_theme.tr();
          final quote = LocaleKeys.templates_column_quote.tr();
          return document(
            [
              section([
                widget(
                  'quote',
                  w: 8,
                  accent: DashboardAccent.purple,
                  settings: const {
                    'text': 'The obstacle is the way.',
                    'author': 'Marcus Aurelius',
                  },
                ),
                widget(
                  'metric',
                  x: 8,
                  title: LocaleKeys.templates_text_collected.tr(),
                  accent: DashboardAccent.purple,
                  settings: const {'aggregate': 'count'},
                  source: table(quotes, name: name, field: quote),
                ),
              ]),
              section(
                [
                  widget(
                    'database',
                    w: 8,
                    h: 9,
                    source: table(quotes, name: name),
                  ),
                  widget(
                    'chart',
                    x: 8,
                    h: 9,
                    title: LocaleKeys.templates_text_byTheme.tr(),
                    accent: DashboardAccent.purple,
                    settings: const {'chart_type': 'donut'},
                    source: table(
                      quotes,
                      name: name,
                      field: quote,
                      groupField: theme,
                    ),
                  ),
                ],
                title: LocaleKeys.templates_text_theCommonplaceBook.tr(),
              ),
            ],
            subtitle: LocaleKeys.templates_item_quotesHint.tr(),
          );
        },
      ),
    ),
  ],
);

// ----------------------------------------------------------------- daily note

final _dailyNote = WorkspaceTemplate(
  id: 'daily_note',
  category: TemplateCategory.everyday,
  label: () => LocaleKeys.templates_item_dailyNote.tr(),
  description: () => LocaleKeys.templates_item_dailyNoteHint.tr(),
  icon: Icons.today_rounded,
  accent: DashboardAccent.amber,
  keywords: const ['daily', 'journal', 'diary', 'note', 'log', 'standup'],
  build: () => [
    TemplatePart(
      key: 'page',
      icon: '📔',
      name: () => LocaleKeys.templates_item_dailyNote.tr(),
      blueprint: TemplatePage(
        (_) => LocaleKeys.templates_page_dailyNote.tr(),
      ),
    ),
  ],
);

// --------------------------------------------------------------------- travel

final _travel = WorkspaceTemplate(
  id: 'travel',
  category: TemplateCategory.everyday,
  label: () => LocaleKeys.templates_item_travel.tr(),
  description: () => LocaleKeys.templates_item_travelHint.tr(),
  icon: Icons.luggage_rounded,
  accent: DashboardAccent.teal,
  keywords: const ['travel', 'trip', 'holiday', 'itinerary', 'packing'],
  build: () => [
    TemplatePart(
      key: 'itinerary',
      icon: '🧳',
      name: () => LocaleKeys.templates_text_itinerary.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_what.tr()),
            TemplateColumn.date(LocaleKeys.templates_column_when.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_where.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_kind.tr(), [
              LocaleKeys.templates_option_flight.tr(),
              LocaleKeys.templates_option_stay.tr(),
              LocaleKeys.templates_option_food.tr(),
              LocaleKeys.templates_option_sight.tr(),
            ]),
            TemplateColumn.number(LocaleKeys.templates_column_amount.tr()),
            TemplateColumn.checkbox(LocaleKeys.templates_column_booked.tr()),
            TemplateColumn.url(LocaleKeys.templates_column_link.tr()),
          ],
          rows: [
            [
              LocaleKeys.templates_text_outboundFlight.tr(),
              '',
              '',
              LocaleKeys.templates_option_flight.tr(),
              '',
              'no',
              '',
            ],
            [
              LocaleKeys.templates_text_firstNight.tr(),
              '',
              '',
              LocaleKeys.templates_option_stay.tr(),
              '',
              'no',
              '',
            ],
          ],
        ),
      ),
    ),
    TemplatePart(
      key: 'board',
      icon: '🗺️',
      name: () => LocaleKeys.templates_item_travel.tr(),
      blueprint: TemplateDashboard(
        (created) {
          final itinerary = created['itinerary'];
          final name = LocaleKeys.templates_text_itinerary.tr();
          final amount = LocaleKeys.templates_column_amount.tr();
          return document(
            [
              section([
                widget(
                  'countdown',
                  title: LocaleKeys.templates_text_untilWeGo.tr(),
                  accent: DashboardAccent.teal,
                ),
                widget('weather', x: 4),
                widget(
                  'metric',
                  x: 8,
                  title: LocaleKeys.templates_text_budgetSoFar.tr(),
                  accent: DashboardAccent.amber,
                  settings: const {'aggregate': 'sum', 'prefix': r'$'},
                  source: table(itinerary, name: name, field: amount),
                ),
              ]),
              section([
                widget(
                  'database',
                  w: 8,
                  h: 9,
                  source: table(itinerary, name: name),
                ),
                widget(
                  'checklist',
                  x: 8,
                  h: 9,
                  title: LocaleKeys.templates_text_packing.tr(),
                  accent: DashboardAccent.teal,
                  settings: {
                    'items': [
                      _check(LocaleKeys.templates_text_packPassport.tr()),
                      _check(LocaleKeys.templates_text_packChargers.tr()),
                      _check(LocaleKeys.templates_text_packMedicine.tr()),
                    ],
                  },
                ),
              ]),
            ],
            subtitle: LocaleKeys.templates_item_travelHint.tr(),
          );
        },
      ),
    ),
  ],
);
