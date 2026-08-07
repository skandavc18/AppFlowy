import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/link_to_page_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/collection_items.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/maps/map_metadata.dart';
import 'package:appflowy/workspace/application/slides/slide_metadata.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'slash_menu_item_builder.dart';

/// The readings a table can already be opened as, beyond the three the slash
/// menu has always offered.
///
/// A chart, a map, a slide deck and the shared table views are all the *same*
/// table wearing a mark, so linking one is the ordinary database reference —
/// it only has to carry the mark across, which `insertReferencePage` does.
const _linkedTableViewKinds = [
  WorkspaceTableKind.chart,
  WorkspaceTableKind.map,
  WorkspaceTableKind.slides,
  WorkspaceTableKind.gallery,
  WorkspaceTableKind.timeline,
  WorkspaceTableKind.feed,
  WorkspaceTableKind.form,
  WorkspaceTableKind.mailbox,
];

/// One "Linked …" entry per table reading, so `/linked chart` finds a chart
/// instead of only a grid, a board and a calendar.
List<SelectionMenuItem> linkedTableViewSlashMenuItems() => [
      for (final kind in _linkedTableViewKinds) _linkedTableViewItem(kind),
    ];

SelectionMenuItem _linkedTableViewItem(WorkspaceTableKind kind) {
  final label = workspaceTableKindLabel(kind);
  final name = LocaleKeys.document_slashMenu_name_linkedTo.tr(args: [label]);
  return SelectionMenuItem(
    getName: () => name,
    keywords: [
      'linked',
      'link to',
      'referenced',
      'database',
      label.toLowerCase(),
      kind.name,
    ],
    handler: (editorState, menuService, context) => showLinkToPageMenu(
      editorState,
      menuService,
      customTitle: name,
      // The mark can sit on a grid, a board or a calendar, so the layout is
      // no filter at all here — what a view *is* comes from its mark.
      viewFilter: (view) => _wearsTableMark(view, kind),
      // The filter is narrow, and a chart is rarely in the recent list, so
      // opening on recents alone would look like there are none.
      showAllViewsInitially: true,
    ),
    nameBuilder: slashMenuItemNameBuilder,
    icon: (editorState, isSelected, style) => SelectableIconWidget(
      icon: workspaceTableKindIcon(kind),
      isSelected: isSelected,
      style: style,
    ),
  );
}

bool _wearsTableMark(ViewPB view, WorkspaceTableKind kind) {
  if (kind.charted) {
    return view.isChart;
  }
  if (kind.mapped) {
    return view.isMap;
  }
  if (kind.slided) {
    return view.isSlideDeck;
  }
  final tableView = kind.tableView;
  return tableView != null && view.tableViewKind == tableView;
}

/// One "Linked …" entry per collection type, plus a plain folder.
///
/// Unlike the collection items beside them, these do not create anything:
/// they put a widget on the page showing a collection that already exists.
List<SelectionMenuItem> linkedCollectionSlashMenuItems() => [
      for (final definition in CollectionRegistry.types)
        _linkedCollectionItem(
          label: definition.label,
          icon: definition.icon,
          keywords: definition.searchKeywords,
          accepts: (view) => view.collection?.kind == definition.kind,
        ),
      _linkedCollectionItem(
        label: LocaleKeys.workspaceFolderExplorer_workspaceFolder.tr(),
        icon: Icons.folder_rounded,
        keywords: const ['folder', 'files', 'directory'],
        accepts: (view) => view.isWorkspaceFolder && !view.isCollection,
      ),
    ];

SelectionMenuItem _linkedCollectionItem({
  required String label,
  required IconData icon,
  required List<String> keywords,
  required bool Function(ViewPB view) accepts,
}) {
  final name = LocaleKeys.document_slashMenu_name_linkedTo.tr(args: [label]);
  return SelectionMenuItem(
    getName: () => name,
    keywords: [
      'linked',
      'link to',
      'referenced',
      'collection',
      label.toLowerCase(),
      ...keywords,
    ],
    handler: (editorState, menuService, context) => showLinkToPageMenu(
      editorState,
      menuService,
      customTitle: name,
      viewFilter: accepts,
      showAllViewsInitially: true,
      onSelected: (view, _, editorState, __, replace) =>
          _insertLinkedCollection(view, editorState, replace),
    ),
    nameBuilder: slashMenuItemNameBuilder,
    icon: (editorState, isSelected, style) => SelectableIconWidget(
      icon: icon,
      isSelected: isSelected,
      style: style,
    ),
  );
}

/// A collection is a workspace folder, so it embeds through the widget block
/// the folder already has — nothing new is created.
Future<void> _insertLinkedCollection(
  ViewPB view,
  EditorState editorState,
  (int, int) replace,
) async {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return;
  }
  final node = editorState.getNodeAtPath(selection.start.path);
  if (node != null && replace.$2 > 0) {
    final transaction = editorState.transaction
      ..deleteText(node, replace.$1, replace.$2);
    await editorState.apply(transaction);
  }
  await editorState.insertCollectionBlock(view.id);
}
