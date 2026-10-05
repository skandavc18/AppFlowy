import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:flutter/widgets.dart';

/// Tables a board reads from memory rather than the database, so a template
/// can be shown with its own rows before anything has been made.
class DashboardSampleTables extends InheritedWidget {
  const DashboardSampleTables({
    super.key,
    required this.tables,
    required super.child,
  });

  /// By the view id the board's widgets are bound to.
  final Map<String, ChartTable> tables;

  /// Safe from `initState`: the samples never change under a mounted board.
  static ChartTable? tableFor(BuildContext context, String viewId) => context
      .getInheritedWidgetOfExactType<DashboardSampleTables>()
      ?.tables[viewId];

  @override
  bool updateShouldNotify(DashboardSampleTables oldWidget) =>
      !identical(tables, oldWidget.tables);
}

/// The table [viewId] names: a sample when one is in scope, else [loadTable]
/// or the database.
ChartSource dashboardChartSource(
  BuildContext context,
  String viewId, {
  Future<ChartTable> Function(String viewId)? loadTable,
}) {
  final sample = DashboardSampleTables.tableFor(context, viewId);
  if (sample != null) {
    return ChartSource(viewId: viewId, loadTable: (_) async => sample);
  }
  return loadTable == null
      ? ChartSource(viewId: viewId)
      : ChartSource(viewId: viewId, loadTable: loadTable);
}
