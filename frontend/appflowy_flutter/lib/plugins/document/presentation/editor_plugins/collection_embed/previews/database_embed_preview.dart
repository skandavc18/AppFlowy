import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_tiles.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/folder_embed_preview.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/database/database_table.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

abstract final class DatabaseEmbedStyles {
  static const table = 'table';
  static const schema = 'schema';
}

/// A database embed is deliberately **flush**: no card, no border, no second
/// toolbar. It is the application's own table continuing straight into the
/// page, because wrapping a database in an embed card is what made it read as
/// a miniature application in a box.
CollectionEmbedDefinition buildDatabaseEmbedDefinition() =>
    CollectionEmbedDefinition(
      kind: CollectionKind.database,
      defaultItemLimit: 8,
      compactHeight: 220,
      mediumHeight: 420,
      largeHeight: 640,
      flush: true,
      showsHeading: false,
      supportsItemLimit: false,
      styles: const [
        CollectionEmbedStyle(
          id: DatabaseEmbedStyles.table,
          labelKey: LocaleKeys.collections_embed_styles_table,
          icon: Icons.table_rows_rounded,
        ),
        CollectionEmbedStyle(
          id: DatabaseEmbedStyles.schema,
          labelKey: LocaleKeys.collections_embed_styles_schema,
          icon: Icons.schema_rounded,
        ),
      ],
      builder: (context, embed) => DatabaseEmbedPreview(embed: embed),
    );

class DatabaseEmbedPreview extends StatefulWidget {
  const DatabaseEmbedPreview({super.key, required this.embed});

  final CollectionEmbedContext embed;

  @override
  State<DatabaseEmbedPreview> createState() => _DatabaseEmbedPreviewState();
}

class _DatabaseEmbedPreviewState extends State<DatabaseEmbedPreview> {
  String? activeId;

  CollectionEmbedContext get embed => widget.embed;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    if (embed.controller.isLoading && embed.children.isEmpty) {
      return const CollectionEmbedSpinner();
    }
    final tables = databaseTablesFrom(embed.children);
    if (tables.isEmpty) {
      return CollectionEmbedEmpty(
        theme: theme,
        icon: Icons.table_chart_rounded,
        message: LocaleKeys.collections_embed_noTables.tr(),
        compact: embed.size.isCompact,
      );
    }
    if (embed.style == DatabaseEmbedStyles.schema) {
      return _Schema(embed: embed, tables: tables);
    }

    final active = tables.firstWhere(
      (table) => table.id == activeId,
      orElse: () => tables.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The table tabs, which only appear when there is more than one table
        // to move between. One table needs no navigation at all.
        if (tables.length > 1)
          _TableTabs(
            embed: embed,
            tables: tables,
            activeId: active.id,
            onSelected: (id) => setState(() => activeId = id),
          ),
        Expanded(child: _Stage(table: active)),
      ],
    );
  }
}

/// Hosts AppFlowy's real database view.
///
/// Everything a table can do — grid, board, calendar, chart, map, timeline,
/// feed, form, gallery, slides, its own view tabs, filters, sorts, row
/// editing and selection — comes with it. There is deliberately no second
/// implementation here.
class _Stage extends StatelessWidget {
  const _Stage({required this.table});

  final DatabaseTable table;

  @override
  Widget build(BuildContext context) => Provider(
        // The grid, board and calendar read their gutter from this; a table
        // hosted outside the database plugin has to be given one.
        create: (_) => DatabasePluginWidgetBuilderSize(
          horizontalPadding: GridSize.horizontalHeaderPadding,
          verticalPadding: 8,
        ),
        child: DatabaseTabBarView(
          // A different table must not reuse the previous one's controllers,
          // or the page keeps showing the database that was there before.
          key: ValueKey(table.id),
          view: table.view,
          shrinkWrap: false,
          showActions: false,
        ),
      );
}

class _TableTabs extends StatelessWidget {
  const _TableTabs({
    required this.embed,
    required this.tables,
    required this.activeId,
    required this.onSelected,
  });

  final CollectionEmbedContext embed;
  final List<DatabaseTable> tables;
  final String activeId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 2, 76, 2),
        physics: const ClampingScrollPhysics(),
        itemCount: tables.length,
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemBuilder: (context, index) {
          final table = tables[index];
          final active = table.id == activeId;
          return CollectionEmbedTappable(
            onTap: () => onSelected(table.id),
            onSecondaryTap: embed.onShowMenu,
            lift: 0,
            builder: (context, hovered) => AnimatedContainer(
              duration: CollectionEmbedMetrics.hover,
              curve: CollectionEmbedMetrics.ease,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: active
                    ? theme.accentWash
                    : hovered
                        ? theme.rowHover
                        : theme.rowHover.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(
                  CollectionEmbedMetrics.controlRadius,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    collectionObjectGlyph(table.view),
                    size: 13,
                    color: active ? theme.accent : theme.textFaint,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    table.name,
                    style: theme.face(
                      context,
                      size: 12,
                      color: active ? theme.accent : theme.textBody,
                      weightAxis: active ? 640 : 550,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Every table at a glance, for a page that wants the shape of the database
/// rather than its rows.
class _Schema extends StatelessWidget {
  const _Schema({required this.embed, required this.tables});

  final CollectionEmbedContext embed;
  final List<DatabaseTable> tables;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = embed.settings.columns ??
            (constraints.maxWidth / 220).floor().clamp(1, 4);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          physics: const ClampingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            mainAxisExtent: 62,
          ),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final table = tables[index];
            return CollectionEmbedTappable(
              onTap: () => embed.onOpenObject(table.view),
              onSecondaryTap: embed.onShowMenu,
              lift: 1.5,
              builder: (context, hovered) => AnimatedContainer(
                duration: CollectionEmbedMetrics.hover,
                curve: CollectionEmbedMetrics.ease,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: hovered ? theme.raised : theme.sunken,
                  borderRadius: BorderRadius.circular(
                    CollectionEmbedMetrics.innerRadius,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      collectionObjectGlyph(table.view),
                      size: 17,
                      color: theme.accent,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            table.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.title(context, size: 12.5),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            table.layout.name,
                            style: theme.caption(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
