import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/database/database_chrome.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/database/database_collection_controller.dart';
import 'package:appflowy/workspace/application/collections/database/database_table.dart';
import 'package:appflowy/workspace/application/collections/database/database_table_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_transfer_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_picker_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Creates a table in [collection] and opens it.
Future<void> createDatabaseTable({
  required CollectionViewContext collection,
  required DatabaseCollectionController controller,
  required ViewLayoutPB layout,
  bool charted = false,
}) async {
  final created = await const DatabaseTableService().createTable(
    parentViewId: collection.collectionView.id,
    layout: layout,
    name: charted ? LocaleKeys.charts_chart.tr() : databaseLayoutLabel(layout),
  );
  await created.fold(
    (view) async {
      if (charted) {
        // A chart is a table wearing a note that says how to draw it.
        await ViewBackendService.updateView(
          viewId: view.id,
          extra: ChartMetadata.newExtra(),
        );
      }
      controller.openTable(view.id);
      controller.flush();
    },
    (_) async {},
  );
}

/// Creates a table in whichever reading [kind] names, and opens it.
///
/// Every reading the workspace offers is a table, so a database collection
/// offers all of them rather than the three original layouts.
Future<void> createDatabaseTableOfKind({
  required CollectionViewContext collection,
  required DatabaseCollectionController controller,
  required WorkspaceTableKind kind,
}) async {
  final view = await createWorkspaceDatabase(
    parentViewId: collection.collectionView.id,
    kind: kind,
  );
  if (view == null) {
    return;
  }
  controller
    ..openTable(view.id)
    ..flush();
}

/// The menu behind a right click on a table, and behind its overflow button.
Future<void> showDatabaseTableMenu({
  required BuildContext context,
  required DatabaseTable table,
  required DatabaseCollectionController controller,
  required CollectionViewContext collection,
  Offset? position,
}) async {
  await showAppMenu<void>(
    context: context,
    globalPosition: position,
    entries: [
      AppMenuItem(
        label: LocaleKeys.collections_database_openTable.tr(),
        icon: Icons.open_in_new_rounded,
        onSelected: () => collection.onOpen(table.view),
      ),
      AppMenuItem(
        label: LocaleKeys.collections_database_columns.tr(),
        icon: Icons.view_column_rounded,
        onSelected: () {
          controller.openTable(table.id);
          controller.setSchemaVisible(true);
        },
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_database_rename.tr(),
        icon: Icons.drive_file_rename_outline_rounded,
        onSelected: () => _renameTable(context, table),
      ),
      AppMenuItem(
        label: LocaleKeys.collections_database_duplicate.tr(),
        icon: Icons.copy_rounded,
        onSelected: () => const DatabaseTableService().duplicate(table.view),
      ),
      AppMenuItem(
        label: LocaleKeys.collections_database_refresh.tr(),
        icon: Icons.refresh_rounded,
        onSelected: () => controller.refreshTable(table.id),
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_database_delete.tr(),
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onSelected: () => _deleteTable(context, table),
      ),
    ],
  );
}

/// The menu behind a right click on empty space in the table rail.
Future<void> showDatabaseBackgroundMenu({
  required BuildContext context,
  required DatabaseCollectionController controller,
  required CollectionViewContext collection,
  required Offset position,
}) async {
  await showAppMenu<void>(
    context: context,
    globalPosition: position,
    entries: [
      AppMenuHeader(LocaleKeys.collections_database_newTable.tr()),
      for (final kind in WorkspaceTableKind.values)
        AppMenuItem(
          label: workspaceTableKindLabel(kind),
          icon: workspaceTableKindIcon(kind),
          onSelected: () => createDatabaseTableOfKind(
            collection: collection,
            controller: controller,
            kind: kind,
          ),
        ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_database_addExisting.tr(),
        icon: Icons.playlist_add_rounded,
        onSelected: () => showExistingDatabasePicker(
          context: context,
          collection: collection,
          controller: controller,
        ),
      ),
      AppMenuItem(
        label: LocaleKeys.collections_database_refreshAll.tr(),
        icon: Icons.refresh_rounded,
        enabled: controller.tables.isNotEmpty,
        onSelected: () => controller.readSummaries(force: true),
      ),
    ],
  );
}

/// Moves a table that already lives elsewhere in the workspace into this
/// collection. A view belongs to one folder, so this is a move, not a copy.
Future<void> showExistingDatabasePicker({
  required BuildContext context,
  required CollectionViewContext collection,
  required DatabaseCollectionController controller,
}) async {
  final collectionId = collection.collectionView.id;
  final present = controller.tables.map((table) => table.id).toSet();
  final theme = databaseThemeOf(context);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DatabasePanel(
          child: WorkspaceViewPickerMenu(
            contentKey: const ValueKey('database-existing-table-picker'),
            title: LocaleKeys.collections_database_addExisting.tr(),
            searchHint: LocaleKeys.collections_database_searchTables.tr(),
            emptyMessage: LocaleKeys.collections_database_noTablesFound.tr(),
            errorMessage:
                LocaleKeys.workspaceFolderExplorer_operationFailed.tr(),
            maxListHeight: 320,
            viewFilter: (view) =>
                isDatabaseTable(view) && !present.contains(view.id),
            leadingBuilder: (context, view, palette) => Icon(
              databaseLayoutIcon(view.layout),
              size: 17,
              color: theme.accent,
            ),
            onSelected: (view) async {
              Navigator.of(dialogContext).pop();
              final moved = await WorkspaceItemTransferService().moveTo(
                views: [view],
                destinationId: collectionId,
              );
              moved.onSuccess((_) {
                controller.openTable(view.id);
                controller.flush();
              });
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> _renameTable(BuildContext context, DatabaseTable table) async {
  final name = await showAFTextFieldDialog(
    context: context,
    title: LocaleKeys.collections_database_renameTable.tr(),
    initialValue: table.view.name,
  );
  final trimmed = name?.trim();
  if (trimmed != null && trimmed.isNotEmpty && trimmed != table.view.name) {
    await const DatabaseTableService().rename(viewId: table.id, name: trimmed);
  }
}

Future<void> _deleteTable(BuildContext context, DatabaseTable table) async {
  await showCustomConfirmDialog(
    context: context,
    title: LocaleKeys.collections_database_deleteTable.tr(),
    description: LocaleKeys.collections_database_deleteTableDescription.tr(),
    builder: (_) => const SizedBox.shrink(),
    style: ConfirmPopupStyle.cancelAndOk,
    confirmLabel: LocaleKeys.collections_database_delete.tr(),
    onConfirm: () => const DatabaseTableService().delete(table.id),
  );
}
