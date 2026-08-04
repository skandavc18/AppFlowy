import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/database/database_chrome.dart';
import 'package:appflowy/plugins/collection/views/database/database_context_menu.dart';
import 'package:appflowy/plugins/collection/views/database/database_host.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/database/database_collection_controller.dart';
import 'package:appflowy/workspace/application/collections/database/database_table.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The whole collection at a glance: every table, what it holds, and the
/// columns that join one to another.
class DatabaseSchemaView extends StatelessWidget {
  const DatabaseSchemaView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  Widget build(BuildContext context) => DatabaseHost(
        collection: collection,
        builder: (context, controller, theme) {
          if (controller.isEmpty) {
            return DatabaseEmptyState(
              theme: theme,
              icon: Icons.schema_rounded,
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
          return _Schema(
            collection: collection,
            controller: controller,
            theme: theme,
          );
        },
      );
}

class _Schema extends StatelessWidget {
  const _Schema({
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final CollectionViewContext collection;
  final DatabaseCollectionController controller;
  final DatabaseTheme theme;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) => showDatabaseBackgroundMenu(
          context: context,
          controller: controller,
          collection: collection,
          position: details.globalPosition,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            DatabaseMetrics.gutter,
            DatabaseMetrics.space2,
            DatabaseMetrics.gutter,
            DatabaseMetrics.space6,
          ),
          child: Wrap(
            spacing: DatabaseMetrics.space3,
            runSpacing: DatabaseMetrics.space3,
            children: [
              for (final table in controller.tables)
                SizedBox(
                  width: DatabaseMetrics.schemaCardWidth,
                  child: _TableCard(
                    table: table,
                    collection: collection,
                    controller: controller,
                    theme: theme,
                  ),
                ),
            ],
          ),
        ),
      );
}

class _TableCard extends StatelessWidget {
  const _TableCard({
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
    final outgoing = controller.relationsFrom(table.id);
    return DatabasePanel(
      padding: const EdgeInsets.all(DatabaseMetrics.space3),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) => showDatabaseTableMenu(
          context: context,
          table: table,
          controller: controller,
          collection: collection,
          position: details.globalPosition,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  databaseLayoutIcon(table.layout),
                  size: 16,
                  color: theme.accent,
                ),
                const SizedBox(width: DatabaseMetrics.space2),
                Expanded(
                  child: Text(
                    table.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.title,
                  ),
                ),
                DatabaseAction(
                  icon: Icons.open_in_full_rounded,
                  tooltip: LocaleKeys.collections_database_openTable.tr(),
                  theme: theme,
                  size: 24,
                  onPressed: () => collection.onOpen(table.view),
                ),
              ],
            ),
            if (summary != null) ...[
              const SizedBox(height: 2),
              Text(
                LocaleKeys.collections_database_tableSummary.tr(
                  args: ['${summary.rowCount}', '${summary.fields.length}'],
                ),
                style: theme.meta,
              ),
              const SizedBox(height: DatabaseMetrics.space3),
              for (final field in summary.fields.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Icon(
                        databaseFieldIcon(field.type),
                        size: 14,
                        color: field.isRelation ? theme.accent : theme.iconRest,
                      ),
                      const SizedBox(width: DatabaseMetrics.space2),
                      Expanded(
                        child: Text(
                          field.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.body,
                        ),
                      ),
                      Text(
                        databaseFieldTypeLabel(field.type),
                        style: theme.meta,
                      ),
                    ],
                  ),
                ),
              if (summary.fields.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    LocaleKeys.collections_database_moreColumns
                        .tr(args: ['${summary.fields.length - 8}']),
                    style: theme.meta,
                  ),
                ),
            ] else ...[
              const SizedBox(height: DatabaseMetrics.space3),
              Text(
                LocaleKeys.collections_database_reading.tr(),
                style: theme.meta,
              ),
            ],
            if (outgoing.isNotEmpty) ...[
              const SizedBox(height: DatabaseMetrics.space3),
              Text(
                LocaleKeys.collections_database_relations.tr().toUpperCase(),
                style: theme.sectionLabel,
              ),
              const SizedBox(height: DatabaseMetrics.space1),
              for (final relation in outgoing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_outward_rounded,
                        size: 13,
                        color: relation.isInternal
                            ? theme.accent
                            : theme.textFaint,
                      ),
                      const SizedBox(width: DatabaseMetrics.space2),
                      Expanded(
                        child: Text(
                          LocaleKeys.collections_database_relationTo.tr(
                            args: [
                              relation.fieldName,
                              _nameOf(relation.toViewId),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.body,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _nameOf(String? viewId) {
    if (viewId == null) {
      return LocaleKeys.collections_database_relationOutside.tr();
    }
    for (final table in controller.tables) {
      if (table.id == viewId) {
        return table.name;
      }
    }
    return LocaleKeys.collections_database_relationOutside.tr();
  }
}
