import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/built_in/template_pieces.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Money: what it is worth, where it went, and what the market is doing.
void registerFinanceTemplates() {
  TemplateRegistry.register(_stocks);
  TemplateRegistry.register(_assets);
  TemplateRegistry.register(_expenses);
  TemplateRegistry.register(_subscriptions);
}

DashboardWidgetSpec _quote(
  String symbol, {
  int x = 0,
  int y = 0,
  int w = 4,
  int h = 5,
  String range = 'month1',
  bool chart = true,
}) =>
    widget(
      'ext.stock.quote',
      x: x,
      y: y,
      w: w,
      h: h,
      settings: {
        'symbol': symbol,
        'range': range,
        'showChart': chart,
        'showPicker': chart,
        'filled': true,
      },
    );

// --------------------------------------------------------------------- stocks

final _stocks = WorkspaceTemplate(
  id: 'stocks',
  category: TemplateCategory.finance,
  label: () => LocaleKeys.templates_item_stocks.tr(),
  description: () => LocaleKeys.templates_item_stocksHint.tr(),
  icon: Icons.show_chart_rounded,
  accent: DashboardAccent.green,
  keywords: const ['stocks', 'shares', 'market', 'ticker', 'trading', 'crypto'],
  requires: const {'stock'},
  build: () => [
    TemplatePart(
      key: 'board',
      icon: '📈',
      name: () => LocaleKeys.templates_item_stocks.tr(),
      blueprint: TemplateDashboard(
        (created) => document(
          [
            section(
              [
                heading(LocaleKeys.templates_text_indices.tr()),
                _quote('^GSPC', y: 1, range: 'month6'),
                _quote('^IXIC', x: 4, y: 1, range: 'month6'),
                _quote('^NSEI', x: 8, y: 1, range: 'month6'),
              ],
            ),
            section(
              [
                _quote('AAPL', w: 3),
                _quote('MSFT', x: 3, w: 3),
                _quote('NVDA', x: 6, w: 3),
                _quote('BTC-USD', x: 9, w: 3),
              ],
              title: LocaleKeys.templates_text_watchlist.tr(),
            ),
            section(
              [
                _quote('TSLA', w: 8, h: 7, range: 'year1'),
                note(
                  LocaleKeys.templates_text_stocksNote.tr(),
                  x: 8,
                  h: 7,
                  accent: DashboardAccent.amber,
                ),
              ],
              title: LocaleKeys.templates_text_takeACloserLook.tr(),
            ),
          ],
          subtitle: LocaleKeys.templates_item_stocksHint.tr(),
        ),
      ),
    ),
  ],
);

// ------------------------------------------------------------------ portfolio

final _assets = WorkspaceTemplate(
  id: 'assets',
  category: TemplateCategory.finance,
  label: () => LocaleKeys.templates_item_assets.tr(),
  description: () => LocaleKeys.templates_item_assetsHint.tr(),
  icon: Icons.account_balance_rounded,
  accent: DashboardAccent.teal,
  keywords: const [
    'assets',
    'portfolio',
    'investments',
    'net worth',
    'holdings',
    'wealth',
  ],
  build: () => [
    TemplatePart(
      key: 'holdings',
      icon: '🏦',
      name: () => LocaleKeys.templates_text_holdings.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_asset.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_ticker.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_kind.tr(), [
              LocaleKeys.templates_option_stock.tr(),
              LocaleKeys.templates_option_fund.tr(),
              LocaleKeys.templates_option_bond.tr(),
              LocaleKeys.templates_option_crypto.tr(),
              LocaleKeys.templates_option_cash.tr(),
              LocaleKeys.templates_option_property.tr(),
            ]),
            TemplateColumn.number(LocaleKeys.templates_column_quantity.tr()),
            TemplateColumn.number(LocaleKeys.templates_column_cost.tr()),
            TemplateColumn.number(LocaleKeys.templates_column_value.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_account.tr(), [
              LocaleKeys.templates_option_brokerage.tr(),
              LocaleKeys.templates_option_retirement.tr(),
              LocaleKeys.templates_option_savings.tr(),
              LocaleKeys.templates_option_wallet.tr(),
            ]),
            TemplateColumn.date(LocaleKeys.templates_column_reviewed.tr()),
            TemplateColumn.text(LocaleKeys.templates_column_notes.tr()),
          ],
          rows: [
            [
              'Apple',
              'AAPL',
              LocaleKeys.templates_option_stock.tr(),
              '25',
              '4200',
              '5600',
              LocaleKeys.templates_option_brokerage.tr(),
              '',
              '',
            ],
            [
              'Global index fund',
              'VT',
              LocaleKeys.templates_option_fund.tr(),
              '120',
              '11000',
              '13400',
              LocaleKeys.templates_option_retirement.tr(),
              '',
              '',
            ],
            [
              'Bitcoin',
              'BTC-USD',
              LocaleKeys.templates_option_crypto.tr(),
              '0.35',
              '9000',
              '12500',
              LocaleKeys.templates_option_wallet.tr(),
              '',
              '',
            ],
            [
              LocaleKeys.templates_text_emergencyFund.tr(),
              '',
              LocaleKeys.templates_option_cash.tr(),
              '1',
              '8000',
              '8000',
              LocaleKeys.templates_option_savings.tr(),
              '',
              '',
            ],
          ],
        ),
      ),
    ),
    TemplatePart(
      key: 'board',
      icon: '💼',
      name: () => LocaleKeys.templates_item_assets.tr(),
      blueprint: TemplateDashboard(
        (created) {
          final holdings = created['holdings'];
          final value = LocaleKeys.templates_column_value.tr();
          final cost = LocaleKeys.templates_column_cost.tr();
          final kind = LocaleKeys.templates_column_kind.tr();
          final account = LocaleKeys.templates_column_account.tr();
          final name = LocaleKeys.templates_text_holdings.tr();
          return document(
            [
              section([
                widget(
                  'metric',
                  w: 3,
                  h: 3,
                  title: LocaleKeys.templates_text_totalValue.tr(),
                  accent: DashboardAccent.teal,
                  settings: const {'aggregate': 'sum', 'prefix': r'$'},
                  source: table(holdings, name: name, field: value),
                ),
                widget(
                  'metric',
                  x: 3,
                  w: 3,
                  h: 3,
                  title: LocaleKeys.templates_text_totalCost.tr(),
                  settings: const {'aggregate': 'sum', 'prefix': r'$'},
                  source: table(holdings, name: name, field: cost),
                ),
                widget(
                  'metric',
                  x: 6,
                  w: 3,
                  h: 3,
                  title: LocaleKeys.templates_text_positions.tr(),
                  settings: const {'aggregate': 'count'},
                  source: table(holdings, name: name, field: value),
                ),
                widget(
                  'metric',
                  x: 9,
                  w: 3,
                  h: 3,
                  title: LocaleKeys.templates_text_largest.tr(),
                  settings: const {'aggregate': 'max', 'prefix': r'$'},
                  source: table(holdings, name: name, field: value),
                ),
              ]),
              section(
                [
                  widget(
                    'chart',
                    w: 6,
                    h: 7,
                    title: LocaleKeys.templates_text_byKind.tr(),
                    accent: DashboardAccent.teal,
                    settings: const {'chart_type': 'donut'},
                    source: table(
                      holdings,
                      name: name,
                      field: value,
                      groupField: kind,
                    ),
                  ),
                  widget(
                    'chart',
                    x: 6,
                    w: 6,
                    h: 7,
                    title: LocaleKeys.templates_text_byAccount.tr(),
                    settings: const {'chart_type': 'bar'},
                    source: table(
                      holdings,
                      name: name,
                      field: value,
                      groupField: account,
                    ),
                  ),
                ],
                title: LocaleKeys.templates_text_allocation.tr(),
              ),
              section(
                [
                  widget(
                    'database',
                    w: 12,
                    h: 9,
                    source: table(holdings, name: name),
                  ),
                ],
                title: name,
              ),
            ],
            subtitle: LocaleKeys.templates_item_assetsHint.tr(),
          );
        },
      ),
    ),
  ],
);

// ------------------------------------------------------------------- expenses

final _expenses = WorkspaceTemplate(
  id: 'expenses',
  category: TemplateCategory.finance,
  label: () => LocaleKeys.templates_item_expenses.tr(),
  description: () => LocaleKeys.templates_item_expensesHint.tr(),
  icon: Icons.receipt_long_rounded,
  accent: DashboardAccent.orange,
  keywords: const ['expenses', 'spending', 'budget', 'money', 'costs'],
  build: () => [
    TemplatePart(
      key: 'spend',
      icon: '🧾',
      name: () => LocaleKeys.templates_text_spending.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_what.tr()),
            TemplateColumn.number(LocaleKeys.templates_column_amount.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_category.tr(), [
              LocaleKeys.templates_option_home.tr(),
              LocaleKeys.templates_option_food.tr(),
              LocaleKeys.templates_option_travel.tr(),
              LocaleKeys.templates_option_health.tr(),
              LocaleKeys.templates_option_fun.tr(),
              LocaleKeys.templates_option_otherKind.tr(),
            ]),
            TemplateColumn.date(LocaleKeys.templates_column_when.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_paidWith.tr(), [
              LocaleKeys.templates_option_card.tr(),
              LocaleKeys.templates_option_cashPayment.tr(),
              LocaleKeys.templates_option_transfer.tr(),
            ]),
            TemplateColumn.checkbox(LocaleKeys.templates_column_recurring.tr()),
          ],
          rows: [
            [
              LocaleKeys.templates_text_rent.tr(),
              '1200',
              LocaleKeys.templates_option_home.tr(),
              '',
              LocaleKeys.templates_option_transfer.tr(),
              'yes',
            ],
            [
              LocaleKeys.templates_text_groceries.tr(),
              '86',
              LocaleKeys.templates_option_food.tr(),
              '',
              LocaleKeys.templates_option_card.tr(),
              'no',
            ],
            [
              LocaleKeys.templates_text_trainTicket.tr(),
              '32',
              LocaleKeys.templates_option_travel.tr(),
              '',
              LocaleKeys.templates_option_card.tr(),
              'no',
            ],
          ],
        ),
      ),
    ),
    TemplatePart(
      key: 'board',
      icon: '💸',
      name: () => LocaleKeys.templates_item_expenses.tr(),
      blueprint: TemplateDashboard(
        (created) {
          final spend = created['spend'];
          final amount = LocaleKeys.templates_column_amount.tr();
          final category = LocaleKeys.templates_column_category.tr();
          final name = LocaleKeys.templates_text_spending.tr();
          return document(
            [
              section([
                widget(
                  'metric',
                  h: 3,
                  title: LocaleKeys.templates_text_spentSoFar.tr(),
                  accent: DashboardAccent.orange,
                  settings: const {'aggregate': 'sum', 'prefix': r'$'},
                  source: table(spend, name: name, field: amount),
                ),
                widget(
                  'progress',
                  x: 4,
                  h: 3,
                  title: LocaleKeys.templates_text_monthlyBudget.tr(),
                  accent: DashboardAccent.green,
                  settings: const {
                    'aggregate': 'sum',
                    'target': 2000,
                    'style': 'ring',
                  },
                  source: table(spend, name: name, field: amount),
                ),
                widget(
                  'metric',
                  x: 8,
                  h: 3,
                  title: LocaleKeys.templates_text_biggest.tr(),
                  settings: const {'aggregate': 'max', 'prefix': r'$'},
                  source: table(spend, name: name, field: amount),
                ),
              ]),
              section([
                widget(
                  'chart',
                  w: 6,
                  h: 7,
                  title: LocaleKeys.templates_text_whereItGoes.tr(),
                  accent: DashboardAccent.orange,
                  settings: const {'chart_type': 'donut'},
                  source: table(
                    spend,
                    name: name,
                    field: amount,
                    groupField: category,
                  ),
                ),
                widget(
                  'database',
                  x: 6,
                  w: 6,
                  h: 7,
                  source: table(spend, name: name),
                ),
              ]),
            ],
            subtitle: LocaleKeys.templates_item_expensesHint.tr(),
          );
        },
      ),
    ),
  ],
);

// -------------------------------------------------------------- subscriptions

final _subscriptions = WorkspaceTemplate(
  id: 'subscriptions',
  category: TemplateCategory.finance,
  label: () => LocaleKeys.templates_item_subscriptions.tr(),
  description: () => LocaleKeys.templates_item_subscriptionsHint.tr(),
  icon: Icons.autorenew_rounded,
  accent: DashboardAccent.purple,
  keywords: const ['subscriptions', 'recurring', 'bills', 'renewals'],
  build: () => [
    TemplatePart(
      key: 'subscriptions',
      icon: '🔁',
      name: () => LocaleKeys.templates_item_subscriptions.tr(),
      blueprint: TemplateDatabase(
        (_) => TemplateTable(
          columns: [
            TemplateColumn.text(LocaleKeys.templates_column_service.tr()),
            TemplateColumn.number(LocaleKeys.templates_column_amount.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_billing.tr(), [
              LocaleKeys.templates_option_monthly.tr(),
              LocaleKeys.templates_option_yearly.tr(),
            ]),
            TemplateColumn.date(LocaleKeys.templates_column_renews.tr()),
            TemplateColumn.select(LocaleKeys.templates_column_category.tr(), [
              LocaleKeys.templates_option_work.tr(),
              LocaleKeys.templates_option_fun.tr(),
              LocaleKeys.templates_option_home.tr(),
            ]),
            TemplateColumn.checkbox(LocaleKeys.templates_column_keeping.tr()),
            TemplateColumn.url(LocaleKeys.templates_column_manage.tr()),
          ],
          rows: [
            [
              'Music',
              '11',
              LocaleKeys.templates_option_monthly.tr(),
              '',
              LocaleKeys.templates_option_fun.tr(),
              'yes',
              '',
            ],
            [
              'Cloud storage',
              '99',
              LocaleKeys.templates_option_yearly.tr(),
              '',
              LocaleKeys.templates_option_work.tr(),
              'yes',
              '',
            ],
          ],
        ),
      ),
    ),
  ],
);
