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
  accent: DashboardAccent.amber,
  keywords: const [
    'quotes',
    'quotations',
    'sayings',
    'inspiration',
    'commonplace',
    'quote of the day',
    'passages',
  ],
  build: () => [
    TemplatePart(
      key: 'quotes',
      icon: '💬',
      name: () => LocaleKeys.templates_text_theQuotes.tr(),
      blueprint: TemplateDatabase((_) => _quotesTable()),
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
                  'quote_spotlight',
                  w: 8,
                  h: 7,
                  source: table(quotes, name: name),
                ),
                widget(
                  'metric',
                  x: 8,
                  h: 3,
                  title: LocaleKeys.templates_text_collected.tr(),
                  accent: DashboardAccent.amber,
                  settings: const {'aggregate': 'count'},
                  source: table(quotes, name: name, field: quote),
                ),
                widget(
                  'chart',
                  x: 8,
                  y: 3,
                  title: LocaleKeys.templates_text_byTheme.tr(),
                  settings: const {'chart_type': 'donut', 'aggregate': 'count'},
                  source: table(quotes, name: name, groupField: theme),
                ),
              ]),
              section(
                [
                  widget(
                    'quote_wall',
                    w: 12,
                    h: 12,
                    source: table(quotes, name: name),
                  ),
                ],
                title: LocaleKeys.templates_text_theWall.tr(),
              ),
              section(
                [
                  widget(
                    'database',
                    w: 12,
                    h: 9,
                    source: table(quotes, name: name),
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

/// Public-domain passages, long ones included: the dashboard sets a line
/// and a page of prose equally well.
TemplateTable _quotesTable() {
  final work = LocaleKeys.templates_option_work.tr();
  final life = LocaleKeys.templates_option_life.tr();
  final craft = LocaleKeys.templates_option_craft.tr();
  final courage = LocaleKeys.templates_option_courage.tr();
  final stillness = LocaleKeys.templates_option_stillness.tr();
  final today = DateTime.now();
  String added(int days) {
    final date = DateTime(today.year, today.month, today.day - days);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  return TemplateTable(
    columns: [
      TemplateColumn.text(LocaleKeys.templates_column_quote.tr()),
      TemplateColumn.text(LocaleKeys.templates_column_whoSaidIt.tr()),
      TemplateColumn.text(LocaleKeys.templates_column_whereFrom.tr()),
      // One theme a quote, so the donut counts each quote once.
      TemplateColumn.select(
        LocaleKeys.templates_column_theme.tr(),
        [work, life, craft, courage, stillness],
      ),
      TemplateColumn.checkbox(LocaleKeys.templates_column_favourite.tr()),
      TemplateColumn.date(LocaleKeys.templates_column_added.tr()),
    ],
    rows: [
      [
        'I went to the woods because I wished to live deliberately, to front '
            'only the essential facts of life, and see if I could not learn '
            'what it had to teach, and not, when I came to die, discover that '
            'I had not lived. I did not wish to live what was not life, living '
            'is so dear; nor did I wish to practise resignation, unless it was '
            'quite necessary.',
        'Henry David Thoreau',
        'Walden (1854)',
        life,
        'yes',
        added(2),
      ],
      [
        'Where the mind is without fear and the head is held high; where '
            'knowledge is free; where the world has not been broken up into '
            'fragments by narrow domestic walls; where words come out from the '
            'depth of truth; where tireless striving stretches its arms '
            'towards perfection; where the clear stream of reason has not lost '
            'its way into the dreary desert sand of dead habit; where the mind '
            'is led forward by thee into ever-widening thought and action — '
            'into that heaven of freedom, my Father, let my country awake.',
        'Rabindranath Tagore',
        'Gitanjali, 35 (1912)',
        courage,
        'yes',
        added(5),
      ],
      [
        'There are more things, Lucilius, likely to frighten us than there '
            'are to crush us; we suffer more often in imagination than in '
            'reality.',
        'Seneca',
        'Letters to Lucilius, XIII',
        courage,
        'no',
        added(8),
      ],
      [
        'Begin the morning by saying to thyself, I shall meet with the '
            'busy-body, the ungrateful, arrogant, deceitful, envious, '
            'unsocial. All these things happen to them by reason of their '
            'ignorance of what is good and evil.',
        'Marcus Aurelius',
        'Meditations, II.1 (tr. George Long)',
        stillness,
        'no',
        added(11),
      ],
      [
        'To believe your own thought, to believe that what is true for you in '
            'your private heart is true for all men, — that is genius.',
        'Ralph Waldo Emerson',
        'Self-Reliance (1841)',
        craft,
        'no',
        added(15),
      ],
      [
        'Arise, awake, and stop not till the goal is reached.',
        'Swami Vivekananda',
        '',
        courage,
        'yes',
        added(18),
      ],
      [
        'With malice toward none, with charity for all, with firmness in the '
            'right as God gives us to see the right, let us strive on to '
            'finish the work we are in, to bind up the nation\'s wounds.',
        'Abraham Lincoln',
        'Second Inaugural Address (1865)',
        work,
        'no',
        added(23),
      ],
      [
        'The journey of a thousand li commenced with a single step.',
        'Lao Tzu',
        'Tao Te Ching, 64 (tr. James Legge)',
        life,
        'no',
        added(27),
      ],
      [
        'Our life is frittered away by detail. Simplify, simplify.',
        'Henry David Thoreau',
        'Walden (1854)',
        stillness,
        'no',
        added(31),
      ],
      [
        'Well done is better than well said.',
        'Benjamin Franklin',
        "Poor Richard's Almanack",
        work,
        'no',
        added(36),
      ],
    ],
  );
}

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
