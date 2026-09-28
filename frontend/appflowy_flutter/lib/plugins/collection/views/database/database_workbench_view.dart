import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_workspace_surface.dart';
import 'package:appflowy/plugins/collection/views/database/database_chrome.dart';
import 'package:appflowy/plugins/collection/views/database/database_context_menu.dart';
import 'package:appflowy/plugins/collection/views/database/database_host.dart';
import 'package:appflowy/plugins/collection/views/database/database_schema_panel.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
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
        builder: (context, controller, theme) => DatabaseWorkbenchBody(
          collection: collection,
          controller: controller,
          theme: theme,
        ),
      );
}

/// The production rail/stage composition, independent of native data loading.
/// [tableBuilder] replaces only the native table boundary in offline fixtures.
class DatabaseWorkbenchBody extends StatelessWidget {
  const DatabaseWorkbenchBody({
    super.key,
    required this.collection,
    required this.controller,
    required this.theme,
    this.tableBuilder,
  });

  final CollectionViewContext collection;
  final DatabaseCollectionController controller;
  final DatabaseTheme theme;
  final Widget Function(BuildContext context, DatabaseTable table)?
      tableBuilder;

  @override
  Widget build(BuildContext context) {
    if (controller.isEmpty) {
      return DatabaseEmptyState(
        theme: theme,
        icon: Icons.table_chart_rounded,
        title: LocaleKeys.collections_database_empty.tr(),
        message: LocaleKeys.collections_database_emptyDescription.tr(),
        action: Wrap(
          spacing: DatabaseMetrics.space2,
          runSpacing: DatabaseMetrics.space2,
          alignment: WrapAlignment.center,
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
    return PreviewToolbarRegion(
      child: CollectionWorkspaceSurface(
        child: CollectionWorkspaceSplit(
          navigationVisible: controller.state.showRail,
          minimumStageWidth: 600,
          navigation: DatabaseTableRail(
            collection: collection,
            controller: controller,
            theme: theme,
          ),
          compactNavigation: const SizedBox.shrink(),
          headerBuilder: (context, railVisible) => active == null
              ? const SizedBox.shrink()
              : _StageHeader(
                  table: active,
                  collection: collection,
                  controller: controller,
                  theme: theme,
                  railVisible: railVisible,
                ),
          child: active == null
              ? const SizedBox.shrink()
              : _RetainedTableStage(
                  key: ValueKey('collection-table-${active.id}'),
                  table: active,
                  controller: controller,
                  theme: theme,
                  tableBuilder: tableBuilder,
                ),
        ),
      ),
    );
  }
}

/// Mount each reading only on first use, then keep it at the same depth. A
/// schema-only visit must not acquire a live table editor behind the scenes.
class _RetainedTableStage extends StatefulWidget {
  const _RetainedTableStage({
    super.key,
    required this.table,
    required this.controller,
    required this.theme,
    this.tableBuilder,
  });

  final DatabaseTable table;
  final DatabaseCollectionController controller;
  final DatabaseTheme theme;
  final Widget Function(BuildContext context, DatabaseTable table)?
      tableBuilder;

  @override
  State<_RetainedTableStage> createState() => _RetainedTableStageState();
}

class _RetainedTableStageState extends State<_RetainedTableStage> {
  bool _tableOpened = false;
  bool _schemaOpened = false;

  @override
  Widget build(BuildContext context) {
    final schema = widget.controller.state.showSchema;
    _tableOpened |= !schema;
    _schemaOpened |= schema;
    return IndexedStack(
      index: schema ? 1 : 0,
      sizing: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: schema,
          child: TickerMode(
            enabled: !schema,
            child: _tableOpened
                ? widget.tableBuilder?.call(context, widget.table) ??
                    _Stage(table: widget.table)
                : const SizedBox.shrink(),
          ),
        ),
        ExcludeFocus(
          excluding: !schema,
          child: TickerMode(
            enabled: schema,
            child: _schemaOpened
                ? DatabaseSchemaPanel(
                    table: widget.table,
                    controller: widget.controller,
                    theme: widget.theme,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
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
    required this.railVisible,
  });

  final DatabaseTable table;
  final CollectionViewContext collection;
  final DatabaseCollectionController controller;
  final DatabaseTheme theme;
  final bool railVisible;

  @override
  Widget build(BuildContext context) {
    final summary = controller.summaryFor(table.id);
    final showSchema = controller.state.showSchema;
    return CollectionWorkspaceToolbar(
      // Match the actual grid's required header inset rather than inventing a
      // second nested-card gutter. Grid sizing/controllers remain untouched.
      padding: EdgeInsets.fromLTRB(
        GridSize.horizontalHeaderPadding,
        0,
        GridSize.horizontalHeaderPadding,
        DatabaseMetrics.space2,
      ),
      // Navigation must not depend on hovering the stage or opening a picker.
      // Keep this identity slot at the same depth across responsive collapse.
      identity: Row(
        children: [
          DatabaseAction(
            key: const ValueKey('database-workbench-tables-toggle'),
            icon: Icons.table_chart_rounded,
            tooltip: railVisible
                ? LocaleKeys.collections_database_hideTables.tr()
                : LocaleKeys.collections_database_showTables.tr(),
            theme: theme,
            active: railVisible,
            onPressed: () => controller.setRailVisible(!railVisible),
          ),
          const SizedBox(width: DatabaseMetrics.space1),
          Expanded(
            child: railVisible
                ? Text(
                    summary == null
                        ? ''
                        : LocaleKeys.collections_database_tableSummary.tr(
                            args: [
                              '${summary.rowCount}',
                              '${summary.fields.length}'
                            ],
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.meta,
                  )
                : CollectionWorkspacePicker(
                    label: table.name,
                    tooltip: LocaleKeys.collections_database_showTables.tr(),
                    icon: databaseLayoutIcon(table.layout),
                    entries: [
                      for (final item in controller.tables)
                        AppMenuItem(
                          label: item.name,
                          icon: databaseLayoutIcon(item.layout),
                          selected: item.id == table.id,
                          onSelected: () => controller.openTable(item.id),
                        ),
                      const AppMenuSeparator(),
                      AppMenuItem(
                        label: LocaleKeys.collections_database_showTables.tr(),
                        icon: Icons.menu_open_rounded,
                        selected: controller.state.showRail,
                        onSelected: () => controller.setRailVisible(true),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      keepVisible: showSchema,
      actions: [
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
    );
  }
}

class DatabaseTableRail extends StatelessWidget {
  const DatabaseTableRail({
    super.key,
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
    return CollectionWorkspaceSurface(
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
            CollectionWorkspaceRailHeader(
              label: LocaleKeys.collections_database_tables.tr(),
              actions: [
                DatabaseAction(
                  icon: Icons.view_column_rounded,
                  tooltip: LocaleKeys.collections_database_columns.tr(),
                  theme: theme,
                  active: controller.state.showSchema,
                  size: 24,
                  onPressed: () =>
                      controller.setSchemaVisible(!controller.state.showSchema),
                ),
                if (active != null)
                  Builder(
                    builder: (anchor) => DatabaseAction(
                      icon: Icons.more_horiz_rounded,
                      tooltip: LocaleKeys.collections_database_moreActions.tr(),
                      theme: theme,
                      size: 24,
                      onPressed: () => showDatabaseTableMenu(
                        context: anchor,
                        table: active,
                        controller: controller,
                        collection: collection,
                      ),
                    ),
                  ),
                Builder(
                  builder: (anchor) => DatabaseAction(
                    icon: Icons.add_rounded,
                    tooltip: LocaleKeys.collections_database_newTable.tr(),
                    theme: theme,
                    size: 24,
                    onPressed: () => showDatabaseBackgroundMenu(
                      context: context,
                      controller: controller,
                      collection: collection,
                      position: _anchorOf(anchor),
                    ),
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
            Expanded(
              child: ListView.builder(
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: controller.tables.length,
                itemBuilder: (context, index) {
                  final table = controller.tables[index];
                  final relations = controller.relationsFrom(table.id).length +
                      controller.relationsTo(table.id).length;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: DatabaseRow(
                      key: ValueKey('collection-table-row-${table.id}'),
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
                          WorkspaceGlyph(
                            databaseLayoutIcon(table.layout),
                            size: 15,
                            color: theme.iconRest,
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
