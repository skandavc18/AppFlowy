import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/options_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/portfolio_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/trend_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/wealth_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/quote_widgets.dart';

/// Money and the quotes that keep somebody going.
///
/// Portfolios and watchlists, an options book with its payoffs and the live
/// chain, a balance sheet with loans, and a commonplace book of quotes. Each
/// reads an ordinary table, guessing its columns from their names, so a
/// table somebody built by hand works as well as one a template made.
void registerDashboardFinanceWidgets() {
  registerPortfolioWidgets();
  registerTrendWidgets();
  registerOptionsWidgets();
  registerWealthWidgets();
  registerQuoteWidgets();
}
