import 'dart:async';

import 'package:appflowy/plugins/dashboard/presentation/dashboard_sample_tables.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/shared/market/market_data.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/material.dart';

/// Where finance widgets read their tables from. Tests replace it with
/// tables of their own; the app reads the database.
@visibleForTesting
Future<ChartTable> Function(String viewId)? financeTableLoader;

/// What a finance widget draws from: its table, a second table when it has
/// one, and the live market.
@immutable
class FinanceFeed {
  const FinanceFeed({
    required this.table,
    required this.secondary,
    required this.market,
    required this.bound,
    required this.loading,
    required this.error,
  });

  final ChartTable table;

  /// A history table, for widgets that draw a trend beside their figures.
  final ChartTable secondary;
  final MarketWatch market;

  /// Whether a table is chosen at all.
  final bool bound;

  /// Whether the first read is still under way.
  final bool loading;
  final String? error;
}

/// Reads a widget's table and keeps it fresh, owns its claim on the market,
/// and rebuilds whenever either changes.
class FinanceView extends StatefulWidget {
  const FinanceView({
    super.key,
    required this.data,
    required this.builder,
    this.secondaryViewId = '',
  });

  final DashboardWidgetContext data;
  final String secondaryViewId;
  final Widget Function(BuildContext context, FinanceFeed feed) builder;

  @override
  State<FinanceView> createState() => _FinanceViewState();
}

class _FinanceViewState extends State<FinanceView> {
  ChartSource? _source;
  ChartSource? _secondary;
  late final MarketWatch _market = MarketWatch()..addListener(_changed);

  @override
  void initState() {
    super.initState();
    _source = _bind(null, widget.data.spec.source.viewId);
    _secondary = _bind(null, widget.secondaryViewId);
  }

  @override
  void didUpdateWidget(FinanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final refreshed = oldWidget.data.refreshToken != widget.data.refreshToken;
    final viewId = widget.data.spec.source.viewId;
    if (refreshed || _source?.viewId != viewId) {
      _source = _bind(_source, viewId);
    }
    if (refreshed || (_secondary?.viewId ?? '') != widget.secondaryViewId) {
      _secondary = _bind(_secondary, widget.secondaryViewId);
    }
    if (refreshed) {
      unawaited(_market.provider?.refresh(force: true));
    }
  }

  ChartSource? _bind(ChartSource? previous, String viewId) {
    previous?.removeListener(_changed);
    previous?.dispose();
    if (viewId.isEmpty) {
      return null;
    }
    final source = dashboardChartSource(
      context,
      viewId,
      loadTable: financeTableLoader,
    )..addListener(_changed);
    unawaited(source.load());
    return source;
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _source?.removeListener(_changed);
    _source?.dispose();
    _secondary?.removeListener(_changed);
    _secondary?.dispose();
    _market
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final table = source?.table ?? ChartTable.empty;
    return widget.builder(
      context,
      FinanceFeed(
        table: table,
        secondary: _secondary?.table ?? ChartTable.empty,
        market: _market,
        bound: source != null,
        loading: source != null && source.isLoading && table.columns.isEmpty,
        error: source?.error,
      ),
    );
  }
}

/// Whether [view] is a table a finance widget can read.
bool financeIsDatabase(ViewPB view) => const [
      ViewLayoutPB.Grid,
      ViewLayoutPB.Board,
      ViewLayoutPB.Calendar,
    ].contains(view.layout);

/// Asks which table a widget reads, right where it was pressed.
Future<void> financePickTable(DashboardWidgetContext data) => data.pickSource(
      kind: DashboardSourceKind.database,
      filter: financeIsDatabase,
    );
