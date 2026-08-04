import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/database/database_chrome.dart';
import 'package:appflowy/plugins/collection/views/database/database_context_menu.dart';
import 'package:appflowy/plugins/collection/views/database/database_host.dart';
import 'package:appflowy/plugins/collection/views/database/database_schema_panel.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/database/database_collection_controller.dart';
import 'package:appflowy/workspace/application/collections/database/database_table.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Several tables in one place, each shown the way it is meant to be.
///
/// A table is an ordinary AppFlowy database, so the stage hosts the real
/// [DatabaseTabBarView] — which brings that database's own Grid, Board and
/// Calendar tabs with it. The collection supplies the tables; the database
/// supplies the views.
class DatabaseWorkbenchView extends StatelessWidget {
  const DatabaseWorkbenchView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  Widget build(BuildContext context) => DatabaseHost(
        collection: collection,
        builder: (context, controller, theme) => _Workbench(
          collection: collection,
          controller: controller,
          theme: theme,
        ),
      );
}

class _Workbench extends StatelessWidget {
  const _Workbench({
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final CollectionViewContext collection;
  final DatabaseCollectionController controller;
  final DatabaseTheme theme;

  @override
  Widget build(BuildContext context) {
    if (controller.isEmpty) {
      return DatabaseEmptyState(
        theme: theme,
        icon: Icons.table_chart_rounded,
        title: LocaleKeys.collections_database_empty.tr(),
        message: LocaleKeys.collections_database_emptyDescription.tr(),
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DatabaseAction(
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
            const SizedBox(width: DatabaseMetrics.space2),
            DatabaseAction(
              icon: Icons.playlist_add_rounded,
              tooltip: LocaleKeys.collections_database_addExisting.tr(),
              label: LocaleKeys.collections_database_addExisting.tr(),
              theme: theme,
              onPressed: () => showExistingDatabasePicker(
                context: context,
                collection: collection,
                controller: controller,
              ),
            ),
          ],
        ),
      );
    }

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
          if (controller.state.showRail) ...[
            SizedBox(
              width: DatabaseMetrics.railWidth,
              child: _TableRail(
                collection: collection,
                controller: controller,
                theme: theme,
              ),
            ),
            const DatabaseGap(),
          ],
          Expanded(
            child: DatabasePanel(
              child: active == null
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StageHeader(
                          table: active,
                          collection: collection,
                          controller: controller,
                          theme: theme,
                        ),
                        Expanded(
                          child: controller.state.showSchema
                              ? DatabaseSchemaPanel(
                                  table: active,
                                  controller: controller,
                                  theme: theme,
                                )
                              : _Stage(table: active),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The real database, with its own layout tabs and toolbar.
class _Stage extends StatelessWidget {
  const _Stage({required this.table});

  final DatabaseTable table;

  @override
  Widget build(BuildContext context) => Provider(
        // The grid, board and calendar all read their gutter from this; the
        // database plugin supplies it when a table is its own page, and the
        // collection has to supply it when the table is hosted here. It may
        // not go below the grid's own header padding — the row width is
        // budgeted from this value while the cells still inset by that.
        create: (_) => DatabasePluginWidgetBuilderSize(
          horizontalPadding: GridSize.horizontalHeaderPadding,
          verticalPadding: DatabaseMetrics.space2,
        ),
        child: DatabaseTabBarView(
          // Rebuilding for a different table must not reuse the last one's
          // controllers, or the grid keeps showing the previous database.
          key: ValueKey(table.id),
          view: table.view,
          shrinkWrap: false,
          showActions: false,
        ),
      );
}

class _StageHeader extends StatelessWidget {
  const _StageHeader({
    required this.table,
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final DatabaseTable table;
  final CollectionViewContext collection;
  final DatabaseCollectionController controller;
  final DatabaseTheme theme;

  @override
  Widget build(BuildContext context) {
    final summary = controller.summaryFor(table.id);
    final showSchema = controller.state.showSchema;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DatabaseMetrics.space4,
        DatabaseMetrics.space3,
        DatabaseMetrics.space2,
        DatabaseMetrics.space2,
      ),
      child: Row(
        children: [
          if (!controller.state.showRail) ...[
            DatabaseAction(
              icon: Icons.menu_open_rounded,
              tooltip: LocaleKeys.collections_database_showTables.tr(),
              theme: theme,
              onPressed: () => controller.setRailVisible(true),
            ),
            const SizedBox(width: DatabaseMetrics.space2),
          ],
          Expanded(
            child: Row(
              children: [
                Icon(
                  databaseLayoutIcon(table.layout),
                  size: 17,
                  color: theme.accent,
                ),
                const SizedBox(width: DatabaseMetrics.space2),
                Flexible(
                  child: Text(
                    table.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.title,
                  ),
                ),
                if (summary != null) ...[
                  const SizedBox(width: DatabaseMetrics.space3),
                  Text(
                    LocaleKeys.collections_database_tableSummary.tr(
                      args: [
                        '${summary.rowCount}',
                        '${summary.fields.length}',
                      ],
                    ),
                    style: theme.meta,
                  ),
                ],
              ],
            ),
          ),
          DatabaseAction(
            icon: Icons.view_column_rounded,
            tooltip: LocaleKeys.collections_database_columns.tr(),
            theme: theme,
            active: showSchema,
            onPressed: () => controller.setSchemaVisible(!showSchema),
          ),
          DatabaseAction(
            icon: Icons.open_in_full_rounded,
            tooltip: LocaleKeys.collections_database_openTable.tr(),
            theme: theme,
            onPressed: () => collection.onOpen(table.view),
          ),
          DatabaseAction(
            icon: Icons.more_horiz_rounded,
            tooltip: LocaleKeys.collections_database_moreActions.tr(),
            theme: theme,
            onPressed: () => showDatabaseTableMenu(
              context: context,
              table: table,
              controller: controller,
              collection: collection,
            ),
          ),
        ],
      ),
    );
  }
}

class _TableRail extends StatelessWidget {
  const _TableRail({
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
    return DatabasePanel(
      padding: const EdgeInsets.all(DatabaseMetrics.space2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) => showDatabaseBackgroundMenu(
          context: context,
          controller: controller,
          collection: collection,
          position: details.globalPosition,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DatabaseMetrics.space2,
                DatabaseMetrics.space2,
                DatabaseMetrics.space1,
                DatabaseMetrics.space2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      LocaleKeys.collections_database_tables.tr().toUpperCase(),
                      style: theme.sectionLabel,
                    ),
                  ),
                  DatabaseAction(
                    icon: Icons.add_rounded,
                    tooltip: LocaleKeys.collections_database_newTable.tr(),
                    theme: theme,
                    size: 24,
                    onPressed: () => showDatabaseBackgroundMenu(
                      context: context,
                      controller: controller,
                      collection: collection,
                      position: _anchorOf(context),
                    ),
                  ),
                  DatabaseAction(
                    icon: Icons.menu_open_rounded,
                    tooltip: LocaleKeys.collections_database_hideTables.tr(),
                    theme: theme,
                    size: 24,
                    onPressed: () => controller.setRailVisible(false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: controller.tables.length,
                itemBuilder: (context, index) {
                  final table = controller.tables[index];
                  final relations = controller.relationsFrom(table.id).length +
                      controller.relationsTo(table.id).length;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: DatabaseRow(
                      theme: theme,
                      selected: table.id == active?.id,
                      onTap: () => controller.openTable(table.id),
                      onContextMenu: (position) => showDatabaseTableMenu(
                        context: context,
                        table: table,
                        controller: controller,
                        collection: collection,
                        position: position,
                      ),
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
                                axis: table.id == active?.id
                                    ? DatabaseMetrics.strongWeightAxis
                                    : DatabaseMetrics.bodyWeightAxis,
                              ),
                            ),
                          ),
                          // A count of the links this table has with the
                          // others, so a related set reads as one thing.
                          if (relations > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text('$relations', style: theme.meta),
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
    );
  }
}

Offset _anchorOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) {
    return Offset.zero;
  }
  return box.localToGlobal(box.size.bottomLeft(Offset.zero));
}
