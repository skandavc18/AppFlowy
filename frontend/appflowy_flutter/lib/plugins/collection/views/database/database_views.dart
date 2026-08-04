import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/database/database_chart_view.dart';
import 'package:appflowy/plugins/collection/views/database/database_schema_view.dart';
import 'package:appflowy/plugins/collection/views/database/database_workbench_view.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:flutter/material.dart';

/// The stable identifiers a database collection's views are stored under.
abstract final class DatabaseViewIds {
  static const tables = 'database_tables';
  static const chart = 'database_chart';
  static const schema = 'database_schema';
}

/// The views a database collection ships with.
List<CollectionViewDefinition> databaseCollectionViews() => [
      CollectionViewDefinition(
        id: DatabaseViewIds.tables,
        labelKey: LocaleKeys.collections_database_tables,
        icon: Icons.table_chart_rounded,
        builder: (context, collection) =>
            DatabaseWorkbenchView(collection: collection),
      ),
      CollectionViewDefinition(
        id: DatabaseViewIds.chart,
        labelKey: LocaleKeys.charts_chart,
        icon: Icons.bar_chart_rounded,
        builder: (context, collection) =>
            DatabaseChartView(collection: collection),
      ),
      CollectionViewDefinition(
        id: DatabaseViewIds.schema,
        labelKey: LocaleKeys.collections_database_schema,
        icon: Icons.schema_rounded,
        builder: (context, collection) =>
            DatabaseSchemaView(collection: collection),
      ),
    ];
