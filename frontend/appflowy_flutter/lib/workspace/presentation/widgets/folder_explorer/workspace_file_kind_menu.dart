import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_kind_menu.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The one shape every "add a file" menu wears.
///
/// The sidebar submenu, the explorer toolbar, the gallery header and every
/// context menu render these entries, so a file type is named with the same
/// glyph and the same row wherever it is offered.
abstract final class WorkspaceFileKindMenuStyle {
  static const width = 248.0;

  /// Constraints for a popover hosting the menu, so the popover neither
  /// squeezes nor stretches the card.
  static const popoverConstraints = BoxConstraints(
    minWidth: width,
    maxWidth: width,
    maxHeight: 640,
  );
}

/// The creatable and uploadable file types, as menu entries.
///
/// [onSelected] is optional: a menu opened with `showAppMenu` reads the row's
/// value instead, while a submenu inside a popover needs the callback.
///
/// Pass [onCreateCollection] wherever a container can also hold a collection,
/// and [onCreateDatabase] wherever it can hold a table, so "add something
/// here" means the same thing everywhere it is offered.
///
/// [kinds] narrows the list to the types a particular container will hold —
/// a collection knows what it is for and offers only that. Leave it null for
/// a plain folder, which holds anything.
List<AppMenuEntry> workspaceFileKindEntries({
  ValueChanged<WorkspaceFileMenuAction>? onSelected,
  ValueChanged<CollectionKind>? onCreateCollection,
  ValueChanged<WorkspaceTableKind>? onCreateDatabase,
  ValueChanged<ProviderServiceInfo>? onImportFromService,
  ValueChanged<ProviderServiceInfo>? onMountService,
  Set<WorkspaceFileKind>? kinds,
}) {
  final entries = <AppMenuEntry>[];
  WorkspaceFileSource? section;
  for (final action in workspaceFileMenuActions) {
    if (kinds != null && !kinds.contains(action.kind)) {
      continue;
    }
    if (action.source != section) {
      section = action.source;
      entries
        ..add(const AppMenuSeparator())
        ..add(AppMenuHeader(action.source.heading));
    }
    entries.add(
      AppMenuItem(
        label: action.label,
        icon: action.icon,
        value: action,
        onSelected: onSelected == null ? null : () => onSelected(action),
      ),
    );
  }
  if (onImportFromService != null) {
    final services = ProviderServices.importable();
    if (services.isNotEmpty) {
      entries
        ..add(const AppMenuSeparator())
        ..add(AppMenuHeader(LocaleKeys.providers_import_heading.tr()));
      for (final info in services) {
        entries.add(
          AppMenuItem(
            label: info.label,
            icon: info.icon,
            onSelected: () => onImportFromService(info),
          ),
        );
      }
    }
  }
  if (onMountService != null) {
    final services = ProviderServices.mountable();
    if (services.isNotEmpty) {
      entries
        ..add(const AppMenuSeparator())
        ..add(AppMenuHeader(LocaleKeys.providers_mount_heading.tr()));
      for (final info in services) {
        entries.add(
          AppMenuItem(
            label: info.label,
            icon: Icons.drive_folder_upload_rounded,
            subtitle: LocaleKeys.providers_mount_subtitle.tr(),
            onSelected: () => onMountService(info),
          ),
        );
      }
    }
  }
  if (onCreateDatabase != null) {
    entries
      ..add(const AppMenuSeparator())
      ..add(AppMenuHeader(LocaleKeys.collections_database_tables.tr()))
      ..addAll(databaseLayoutEntries(onSelected: onCreateDatabase));
  }
  if (onCreateCollection != null) {
    entries
      ..add(const AppMenuSeparator())
      ..add(AppMenuHeader(LocaleKeys.collections_plural.tr()))
      ..addAll(collectionKindEntries(onSelected: onCreateCollection));
  }
  return entries;
}

/// Shows the creatable and uploadable file types anchored at [globalPosition].
///
/// Returns null when a collection or a table was picked instead — that
/// callback has already run by then.
Future<WorkspaceFileMenuAction?> showWorkspaceFileKindMenu({
  required BuildContext context,
  required Offset globalPosition,
  ValueChanged<CollectionKind>? onCreateCollection,
  ValueChanged<WorkspaceTableKind>? onCreateDatabase,
  ValueChanged<ProviderServiceInfo>? onImportFromService,
  ValueChanged<ProviderServiceInfo>? onMountService,
  Set<WorkspaceFileKind>? kinds,
}) =>
    showAppMenu<WorkspaceFileMenuAction>(
      context: context,
      globalPosition: globalPosition,
      entries: workspaceFileKindEntries(
        onCreateCollection: onCreateCollection,
        onCreateDatabase: onCreateDatabase,
        onImportFromService: onImportFromService,
        onMountService: onMountService,
        kinds: kinds,
      ),
      width: WorkspaceFileKindMenuStyle.width,
    );

/// The nested "Add file" entry, which reveals every supported file type.
///
/// Shared by the sidebar `+` button, the folder header and the sidebar
/// background menu so a submenu is never a second design.
class WorkspaceFileAddAction extends PopoverActionCell {
  WorkspaceFileAddAction({
    required this.onCreate,
    this.onCreateCollection,
    this.onCreateDatabase,
    this.onImportFromService,
    this.onMountService,
  });

  final void Function(WorkspaceFileMenuAction action) onCreate;
  final ValueChanged<CollectionKind>? onCreateCollection;
  final ValueChanged<WorkspaceTableKind>? onCreateDatabase;
  final ValueChanged<ProviderServiceInfo>? onImportFromService;
  final ValueChanged<ProviderServiceInfo>? onMountService;

  @override
  Widget? leftIcon(Color iconColor) => Icon(
        workspaceAddFileIcon,
        color: iconColor,
        size: AppMenuMetrics.iconSize,
      );

  @override
  String get name => LocaleKeys.workspaceFolderExplorer_addFile.tr();

  @override
  bool get openOnHover => true;

  @override
  BoxConstraints? get popoverConstraints =>
      WorkspaceFileKindMenuStyle.popoverConstraints;

  @override
  PopoverActionCellBuilder get builder =>
      (context, parentController, controller) => WorkspaceFileKindList(
            onSelected: (action) {
              controller.close();
              parentController.close();
              onCreate(action);
            },
            onCreateCollection: onCreateCollection == null
                ? null
                : (kind) {
                    controller.close();
                    parentController.close();
                    onCreateCollection!(kind);
                  },
            onCreateDatabase: onCreateDatabase == null
                ? null
                : (kind) {
                    controller.close();
                    parentController.close();
                    onCreateDatabase!(kind);
                  },
            onImportFromService: onImportFromService == null
                ? null
                : (info) {
                    controller.close();
                    parentController.close();
                    onImportFromService!(info);
                  },
            onMountService: onMountService == null
                ? null
                : (info) {
                    controller.close();
                    parentController.close();
                    onMountService!(info);
                  },
          );
}

/// The file-type rows on their own, for a popover that supplies the card.
class WorkspaceFileKindList extends StatelessWidget {
  const WorkspaceFileKindList({
    super.key,
    required this.onSelected,
    this.onCreateCollection,
    this.onCreateDatabase,
    this.onImportFromService,
    this.onMountService,
  });

  final ValueChanged<WorkspaceFileMenuAction> onSelected;
  final ValueChanged<CollectionKind>? onCreateCollection;
  final ValueChanged<WorkspaceTableKind>? onCreateDatabase;
  final ValueChanged<ProviderServiceInfo>? onImportFromService;
  final ValueChanged<ProviderServiceInfo>? onMountService;

  @override
  Widget build(BuildContext context) {
    final entries = normalizeAppMenuEntries(
      workspaceFileKindEntries(
        onCreateCollection: onCreateCollection,
        onCreateDatabase: onCreateDatabase,
        onImportFromService: onImportFromService,
        onMountService: onMountService,
      ),
    );
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            switch (entry) {
              AppMenuSeparator() => const AppMenuSeparatorLine(),
              AppMenuHeader(:final label) => AppMenuSectionLabel(label: label),
              AppMenuCustom(:final builder) => Builder(builder: builder),
              // A row that carries its own callback owns its answer; the rest
              // are told apart by the type of the value they hold.
              AppMenuItem() => AppMenuRow(
                  label: entry.label,
                  icon: entry.icon,
                  tracksHover: true,
                  onTap: entry.onSelected ??
                      () => switch (entry.value) {
                            final WorkspaceFileMenuAction action =>
                              onSelected(action),
                            final CollectionKind kind =>
                              onCreateCollection?.call(kind),
                            final WorkspaceTableKind kind =>
                              onCreateDatabase?.call(kind),
                            _ => null,
                          },
                ),
            },
        ],
      ),
    );
  }
}
