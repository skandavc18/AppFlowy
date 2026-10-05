import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';

/// A template's tables as its board will read them, before any is made: each
/// under a stand-in view id that the board's widgets are bound to.
({TemplateContext ids, Map<String, ChartTable> tables}) templateSamples(
  WorkspaceTemplate template,
) {
  final ids = <String, String>{};
  final tables = <String, ChartTable>{};
  for (final part in template.parts) {
    if (part.blueprint case TemplateDatabase(:final build)) {
      final viewId = 'sample:${template.id}:${part.key}';
      final table = build(Map.unmodifiable(ids));
      ids[part.key] = viewId;
      tables[viewId] = ChartTable.fromRows(
        [
          [for (final column in table.columns) column.name],
          ...table.rows,
        ],
        rowIds: [
          for (var index = 0; index < table.rows.length; index++)
            '$viewId/$index',
        ],
      );
    }
  }
  return (ids: ids, tables: tables);
}

/// [document] without its embedded tables, which open a real database and
/// so cannot be drawn from samples. The tables are shown on their own.
DashboardDocument withoutEmbeddedTables(DashboardDocument document) =>
    document.copyWith(
      sections: [
        for (final section in document.sections)
          if (section.widgets.any((widget) => widget.type != 'database'))
            section.copyWith(
              widgets: [
                for (final widget in section.widgets)
                  if (widget.type != 'database') widget,
              ],
            ),
      ],
    );
