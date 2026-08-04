import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/database/database_chrome.dart';
import 'package:appflowy/workspace/application/collections/database/database_collection_controller.dart';
import 'package:appflowy/workspace/application/collections/database/database_schema.dart';
import 'package:appflowy/workspace/application/collections/database/database_table.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What one table holds: its columns, and the tables it is joined to.
class DatabaseSchemaPanel extends StatelessWidget {
  const DatabaseSchemaPanel({
    super.key,
    required this.table,
    required this.controller,
    required this.theme,
  });

  final DatabaseTable table;
  final DatabaseCollectionController controller;
  final DatabaseTheme theme;

  @override
  Widget build(BuildContext context) {
    final summary = controller.summaryFor(table.id);
    if (summary == null) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: theme.accent),
        ),
      );
    }

    final outgoing = controller.relationsFrom(table.id);
    final incoming = controller.relationsTo(table.id);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        DatabaseMetrics.space4,
        0,
        DatabaseMetrics.space4,
        DatabaseMetrics.space5,
      ),
      children: [
        Text(
          LocaleKeys.collections_database_columns.tr().toUpperCase(),
          style: theme.sectionLabel,
        ),
        const SizedBox(height: DatabaseMetrics.space2),
        for (final field in summary.fields)
          _FieldRow(field: field, controller: controller, theme: theme),
        if (outgoing.isNotEmpty || incoming.isNotEmpty) ...[
          const SizedBox(height: DatabaseMetrics.space5),
          Text(
            LocaleKeys.collections_database_relations.tr().toUpperCase(),
            style: theme.sectionLabel,
          ),
          const SizedBox(height: DatabaseMetrics.space2),
          for (final relation in outgoing)
            _RelationRow(
              relation: relation,
              controller: controller,
              theme: theme,
              outgoing: true,
            ),
          for (final relation in incoming)
            _RelationRow(
              relation: relation,
              controller: controller,
              theme: theme,
              outgoing: false,
            ),
        ],
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.controller,
    required this.theme,
  });

  final DatabaseFieldSummary field;
  final DatabaseCollectionController controller;
  final DatabaseTheme theme;

  @override
  Widget build(BuildContext context) => DatabaseRow(
        theme: theme,
        child: Row(
          children: [
            Icon(
              databaseFieldIcon(field.type),
              size: 15,
              color: field.isRelation ? theme.accent : theme.iconRest,
            ),
            const SizedBox(width: DatabaseMetrics.space2),
            Expanded(
              child: Text(
                field.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.face(
                  fontSize: DatabaseMetrics.bodySize + 1,
                  color: theme.textBody,
                  axis: field.isPrimary
                      ? DatabaseMetrics.strongWeightAxis
                      : DatabaseMetrics.bodyWeightAxis,
                ),
              ),
            ),
            const SizedBox(width: DatabaseMetrics.space2),
            Text(databaseFieldTypeLabel(field.type), style: theme.meta),
          ],
        ),
      );
}

class _RelationRow extends StatelessWidget {
  const _RelationRow({
    required this.relation,
    required this.controller,
    required this.theme,
    required this.outgoing,
  });

  final DatabaseRelation relation;
  final DatabaseCollectionController controller;
  final DatabaseTheme theme;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final otherId = outgoing ? relation.toViewId : relation.fromViewId;
    final other = otherId == null
        ? null
        : controller.tables.where((table) => table.id == otherId).firstOrNull;
    final label =
        other?.name ?? LocaleKeys.collections_database_relationOutside.tr();
    return DatabaseRow(
      theme: theme,
      onTap: other == null ? null : () => controller.openTable(other.id),
      child: Row(
        children: [
          Icon(
            outgoing ? Icons.arrow_outward_rounded : Icons.south_west_rounded,
            size: 15,
            color: other == null ? theme.textFaint : theme.accent,
          ),
          const SizedBox(width: DatabaseMetrics.space2),
          Expanded(
            child: Text(
              outgoing
                  ? LocaleKeys.collections_database_relationTo
                      .tr(args: [relation.fieldName, label])
                  : LocaleKeys.collections_database_relationFrom
                      .tr(args: [label, relation.fieldName]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.face(
                fontSize: DatabaseMetrics.bodySize + 1,
                color: theme.textBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
