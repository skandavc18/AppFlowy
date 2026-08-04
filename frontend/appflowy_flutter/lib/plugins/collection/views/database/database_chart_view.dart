import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/database/database_chrome.dart';
import 'package:appflowy/plugins/collection/views/database/database_context_menu.dart';
import 'package:appflowy/plugins/collection/views/database/database_host.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/database/database_collection_controller.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The collection's tables, plotted.
///
/// The chart is a reading of a table, not a thing of its own: pick a table on
/// the left, and the columns on the right decide what is drawn.
class DatabaseChartView extends StatelessWidget {
  const DatabaseChartView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  Widget build(BuildContext context) => DatabaseHost(
        collection: collection,
        builder: (context, controller, theme) {
          if (controller.isEmpty) {
            return DatabaseEmptyState(
              theme: theme,
              icon: Icons.insert_chart_outlined_rounded,
              title: LocaleKeys.collections_database_empty.tr(),
              message: LocaleKeys.collections_database_emptyDescription.tr(),
              action: DatabaseAction(
                icon: Icons.add_rounded,
                tooltip: LocaleKeys.collections_database_newTable.tr(),
                label: LocaleKeys.collections_database_newTable.tr(),
                theme: theme,
                active: true,
                onPressed: () => createDatabaseTable(
                  collection: collection,
                  controller: controller,
                  layout: ViewLayoutPB.Grid,
                ),
              ),
            );
          }
          return _Charts(
            collection: collection,
            controller: controller,
            theme: theme,
          );
        },
      );
}

class _Charts extends StatelessWidget {
  const _Charts({
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final CollectionViewContext collection;
  final DatabaseCollectionController controller;
  final DatabaseTheme theme;

  @override
  Widget build(BuildContext context) {
    final active = controller.activeTable;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DatabaseMetrics.gutter,
        DatabaseMetrics.space1,
        DatabaseMetrics.gutter,
        DatabaseMetrics.space4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: DatabaseMetrics.railWidth,
            child: DatabasePanel(
              padding: const EdgeInsets.all(DatabaseMetrics.space2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DatabaseMetrics.space2,
                      DatabaseMetrics.space2,
                      DatabaseMetrics.space2,
                      DatabaseMetrics.space2,
                    ),
                    child: Text(
                      LocaleKeys.collections_database_tables.tr().toUpperCase(),
                      style: theme.sectionLabel,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: controller.tables.length,
                      itemBuilder: (context, index) {
                        final table = controller.tables[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: DatabaseRow(
                            theme: theme,
                            selected: table.id == active?.id,
                            onTap: () => controller.openTable(table.id),
                            child: Row(
                              children: [
                                Icon(
                                  databaseLayoutIcon(table.layout),
                                  size: 15,
                                  color: table.id == active?.id
                                      ? theme.accent
                                      : theme.iconRest,
                                ),
                                const SizedBox(width: DatabaseMetrics.space2),
                                Expanded(
                                  child: Text(
                                    table.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.face(
                                      fontSize: DatabaseMetrics.bodySize + 1,
                                      color: table.id == active?.id
                                          ? theme.textStrong
                                          : theme.textBody,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const DatabaseGap(),
          Expanded(
            child: active == null
                ? const SizedBox.shrink()
                : ChartStage(
                    key: ValueKey(active.id),
                    viewId: active.id,
                    title: active.name,
                    background: theme.panel,
                    spec: controller.chartSpecFor(active.id),
                    onSpecChanged: (spec) =>
                        controller.setChartSpec(active.id, spec),
                    padding: const EdgeInsets.fromLTRB(
                      DatabaseMetrics.space5,
                      DatabaseMetrics.space4,
                      DatabaseMetrics.space5,
                      DatabaseMetrics.space4,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A chart's settings live beside the table they read.
extension DatabaseChartSpecs on DatabaseCollectionController {
  ChartSpec chartSpecFor(String viewId) =>
      ChartSpec.fromJson(state.chartSpecs[viewId] ?? const {});

  void setChartSpec(String viewId, ChartSpec spec) =>
      setChartSpecJson(viewId, spec.toJson());
}
