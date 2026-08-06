import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/collections/database/database_table_service.dart';
import 'package:appflowy/workspace/application/maps/map_metadata.dart';
import 'package:appflowy/workspace/application/slides/slide_metadata.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The tables offered wherever something new can be added.
///
/// A chart belongs here beside the grid and the board because it is the same
/// thing: a table, shown a different way. Choosing one makes a real table that
/// simply opens as a picture of itself.
enum WorkspaceTableKind {
  table(ViewLayoutPB.Grid),
  board(ViewLayoutPB.Board),
  calendar(ViewLayoutPB.Calendar),
  gallery(ViewLayoutPB.Grid, tableView: TableViewKind.gallery),
  timeline(ViewLayoutPB.Grid, tableView: TableViewKind.timeline),
  feed(ViewLayoutPB.Grid, tableView: TableViewKind.feed),
  form(ViewLayoutPB.Grid, tableView: TableViewKind.form),
  mailbox(ViewLayoutPB.Grid, tableView: TableViewKind.mailbox),
  chart(ViewLayoutPB.Grid, charted: true),
  map(ViewLayoutPB.Grid, mapped: true),
  slides(ViewLayoutPB.Grid, slided: true);

  const WorkspaceTableKind(
    this.layout, {
    this.charted = false,
    this.mapped = false,
    this.slided = false,
    this.tableView,
  });

  final ViewLayoutPB layout;

  /// Whether the new table opens as a chart.
  final bool charted;

  /// Whether the new table opens as a map.
  final bool mapped;

  /// Whether the new table opens as a stack of slides.
  final bool slided;

  /// Which of the shared readings the new table opens as, if any.
  final TableViewKind? tableView;
}

/// The database layouts offered wherever something new can be added.
///
/// A table is not a file and not a collection, so it is its own group in the
/// add menu — but it is created the same way everywhere it is offered.
const List<ViewLayoutPB> workspaceDatabaseLayouts = [
  ViewLayoutPB.Grid,
  ViewLayoutPB.Board,
  ViewLayoutPB.Calendar,
];

String workspaceTableKindLabel(WorkspaceTableKind kind) => switch (kind) {
      WorkspaceTableKind.board => LocaleKeys.collections_database_board.tr(),
      WorkspaceTableKind.calendar =>
        LocaleKeys.collections_database_calendar.tr(),
      WorkspaceTableKind.chart => LocaleKeys.charts_chart.tr(),
      WorkspaceTableKind.map => LocaleKeys.map_name.tr(),
      WorkspaceTableKind.slides => LocaleKeys.slides_name.tr(),
      WorkspaceTableKind.gallery => LocaleKeys.gallery_name.tr(),
      WorkspaceTableKind.timeline => LocaleKeys.timeline_name.tr(),
      WorkspaceTableKind.feed => LocaleKeys.feed_name.tr(),
      WorkspaceTableKind.form => LocaleKeys.form_name.tr(),
      WorkspaceTableKind.mailbox => LocaleKeys.mailbox_name.tr(),
      WorkspaceTableKind.table => LocaleKeys.collections_database_table.tr(),
    };

IconData workspaceTableKindIcon(WorkspaceTableKind kind) => switch (kind) {
      WorkspaceTableKind.board => Icons.view_kanban_rounded,
      WorkspaceTableKind.calendar => Icons.calendar_month_rounded,
      WorkspaceTableKind.chart => Icons.bar_chart_rounded,
      WorkspaceTableKind.map => Icons.map_rounded,
      WorkspaceTableKind.slides => Icons.view_carousel_rounded,
      WorkspaceTableKind.gallery => Icons.grid_view_rounded,
      WorkspaceTableKind.timeline => Icons.timeline_rounded,
      WorkspaceTableKind.feed => Icons.article_rounded,
      WorkspaceTableKind.form => Icons.assignment_rounded,
      WorkspaceTableKind.mailbox => Icons.mark_email_unread_rounded,
      WorkspaceTableKind.table => Icons.table_rows_rounded,
    };

String workspaceDatabaseLayoutLabel(ViewLayoutPB layout) => switch (layout) {
      ViewLayoutPB.Board => LocaleKeys.collections_database_board.tr(),
      ViewLayoutPB.Calendar => LocaleKeys.collections_database_calendar.tr(),
      _ => LocaleKeys.collections_database_table.tr(),
    };

IconData workspaceDatabaseLayoutIcon(ViewLayoutPB layout) => switch (layout) {
      ViewLayoutPB.Board => Icons.view_kanban_rounded,
      ViewLayoutPB.Calendar => Icons.calendar_month_rounded,
      _ => Icons.table_rows_rounded,
    };

/// The table rows of the add menu.
List<AppMenuEntry> databaseLayoutEntries({
  required ValueChanged<WorkspaceTableKind> onSelected,
}) =>
    [
      for (final kind in WorkspaceTableKind.values)
        AppMenuItem(
          label: workspaceTableKindLabel(kind),
          icon: workspaceTableKindIcon(kind),
          value: kind,
          onSelected: () => onSelected(kind),
        ),
    ];

/// Creates a table under [parentViewId] and hands back the view.
Future<ViewPB?> createWorkspaceDatabase({
  required String parentViewId,
  required WorkspaceTableKind kind,
  ViewSectionPB? section,
}) async {
  final created = await const DatabaseTableService().createTable(
    parentViewId: parentViewId,
    layout: kind.layout,
    name: workspaceTableKindLabel(kind),
    section: section,
  );
  final view = created.fold((view) => view, (_) => null);
  if (view == null) {
    return view;
  }
  // A chart, a map or a deck is a table wearing a note that says how to show
  // it.
  if (kind.charted) {
    await ViewBackendService.updateView(
      viewId: view.id,
      extra: ChartMetadata.newExtra(),
    );
  } else if (kind.mapped) {
    await ViewBackendService.updateView(
      viewId: view.id,
      extra: MapMetadata.newExtra(),
    );
  } else if (kind.slided) {
    await ViewBackendService.updateView(
      viewId: view.id,
      extra: SlideMetadata.newExtra(),
    );
  } else if (kind.tableView != null) {
    await ViewBackendService.updateView(
      viewId: view.id,
      extra: TableViewMark.newExtra(kind.tableView!),
    );
  }
  return view;
}
