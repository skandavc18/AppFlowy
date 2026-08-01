import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_chrome.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_views.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_controller.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_state.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_creator.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a right click on one file or folder offers.
enum RepoEntryAction {
  reveal,
  openInWorkspace,
  copyPath,
  refresh,
}

/// What a right click on the repository itself offers.
enum RepoBackgroundAction {
  showHidden,
  showIgnored,
  refresh,
}

/// The actions for [entry], shared by every repository view.
Future<void> showRepoEntryMenu({
  required BuildContext context,
  required CollectionViewContext collection,
  required RepositoryController controller,
  required RepoEntry entry,
  required Offset position,
  VoidCallback? onOpen,
}) async {
  final action = await showAppMenu<RepoEntryAction>(
    context: context,
    globalPosition: position,
    entries: [
      AppMenuItem(
        label: LocaleKeys.collections_repository_openInTree.tr(),
        icon: Icons.account_tree_rounded,
        value: RepoEntryAction.reveal,
        enabled: !entry.isFolder,
      ),
      AppMenuItem(
        label: LocaleKeys.collections_repository_openInWorkspace.tr(),
        icon: Icons.open_in_new_rounded,
        value: RepoEntryAction.openInWorkspace,
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_repository_copyPath.tr(),
        icon: Icons.link_rounded,
        value: RepoEntryAction.copyPath,
      ),
      AppMenuItem(
        label: LocaleKeys.collections_repository_refresh.tr(),
        icon: Icons.refresh_rounded,
        value: RepoEntryAction.refresh,
      ),
    ],
  );
  if (action == null) {
    return;
  }

  switch (action) {
    case RepoEntryAction.reveal:
      controller
        ..expandTo(entry.path)
        ..openFile(entry.id)
        ..flush();
      if (onOpen != null) {
        onOpen();
      } else {
        collection.onOpenView(RepositoryViewIds.tree);
      }
    case RepoEntryAction.openInWorkspace:
      collection.onOpen(entry.view);
    case RepoEntryAction.copyPath:
      await Clipboard.setData(ClipboardData(text: entry.path));
      if (context.mounted) {
        _notify(context, LocaleKeys.collections_repository_pathCopied.tr());
      }
    case RepoEntryAction.refresh:
      controller.source.invalidate(entry.id);
      await controller.ensureAnalysis(entry);
  }
}

Future<void> showRepoBackgroundMenu({
  required BuildContext context,
  required CollectionViewContext collection,
  required RepositoryController controller,
  required Offset position,
  String parentPath = '',
}) async {
  RepoSort? sort;
  WorkspaceFileMenuAction? file;
  CollectionKind? collectionKind;
  var newFolder = false;

  final action = await showAppMenu<RepoBackgroundAction>(
    context: context,
    globalPosition: position,
    entries: [
      AppMenuItem(
        label: LocaleKeys.workspaceFolderExplorer_addFile.tr(),
        icon: workspaceAddFileIcon,
        submenu: workspaceFileKindEntries(
          onSelected: (selected) => file = selected,
          onCreateCollection: (kind) => collectionKind = kind,
        ),
      ),
      AppMenuItem(
        label: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
        icon: workspaceAddFolderIcon,
        onSelected: () => newFolder = true,
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_repository_sort.tr(),
        icon: Icons.swap_vert_rounded,
        submenu: [
          for (final value in RepoSort.values)
            AppMenuItem(
              label: repoSortLabel(value),
              selected: value == controller.settings.sort,
              onSelected: () => sort = value,
            ),
        ],
      ),
      AppMenuItem(
        label: LocaleKeys.collections_repository_showHidden.tr(),
        icon: Icons.visibility_rounded,
        selected: controller.settings.showHidden,
        value: RepoBackgroundAction.showHidden,
      ),
      AppMenuItem(
        label: LocaleKeys.collections_repository_showIgnored.tr(),
        icon: Icons.inventory_2_rounded,
        selected: controller.settings.showIgnored,
        value: RepoBackgroundAction.showIgnored,
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_repository_refresh.tr(),
        icon: Icons.refresh_rounded,
        value: RepoBackgroundAction.refresh,
      ),
    ],
  );

  final parentId = repoParentIdFor(collection, controller, parentPath);
  if (file != null) {
    await createWorkspaceFile(parentViewId: parentId, action: file!);
    return;
  }
  if (collectionKind != null) {
    await createRepoCollection(collection, parentId, collectionKind!);
    return;
  }
  if (newFolder) {
    await const WorkspaceItemService().createFolder(
      parentViewId: parentId,
      name: LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
    );
    return;
  }
  if (sort != null) {
    controller.updateSettings(controller.settings.copyWith(sort: sort));
    return;
  }
  if (action == null) {
    return;
  }

  switch (action) {
    case RepoBackgroundAction.showHidden:
      controller.updateSettings(
        controller.settings
            .copyWith(showHidden: !controller.settings.showHidden),
      );
    case RepoBackgroundAction.showIgnored:
      controller.updateSettings(
        controller.settings
            .copyWith(showIgnored: !controller.settings.showIgnored),
      );
    case RepoBackgroundAction.refresh:
      controller.source.clear();
      await controller.analyseAll();
  }
}

/// The view a new object belongs under: a folder in the tree, or the
/// repository itself when nothing is open.
String repoParentIdFor(
  CollectionViewContext collection,
  RepositoryController controller,
  String path,
) =>
    (path.isEmpty ? null : controller.entryForPath(path)?.id) ??
    collection.collectionView.id;

Future<void> createRepoCollection(
  CollectionViewContext collection,
  String parentId,
  CollectionKind kind,
) async {
  await const CollectionService().createCollection(
    parentViewId: parentId,
    kind: kind,
    name: CollectionRegistry.typeFor(kind).defaultName,
  );
}

/// Writes the document that explains the project, at the repository root.
Future<void> createRepoReadme({
  required CollectionViewContext collection,
  required RepositoryController controller,
}) async {
  await const WorkspaceItemService().createBlankFile(
    parentViewId: collection.collectionView.id,
    kind: WorkspaceFileKind.markdown,
    name: 'README.md',
    content: Uint8List.fromList(
      utf8.encode('# ${collection.collectionView.name}\n'),
    ),
  );
}

/// The `+` that adds a file, a folder or a nested collection to a repository.
class RepoAddButton extends StatelessWidget {
  const RepoAddButton({
    super.key,
    required this.theme,
    required this.collection,
    required this.controller,
    required this.parentPath,
    this.primary = false,
  });

  final RepoTheme theme;
  final CollectionViewContext collection;
  final RepositoryController controller;

  /// The folder the new object lands in; empty for the repository root.
  final String parentPath;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return RepoAnchored(
      builder: (anchor, open) => RepoAction(
        key: anchor,
        theme: theme,
        icon: Icons.add_rounded,
        tooltip: LocaleKeys.collections_repository_addHere.tr(),
        label: primary ? LocaleKeys.collections_repository_add.tr() : null,
        trailingIcon: primary ? Icons.expand_more_rounded : null,
        primary: primary,
        onPressed: () => open((position) => _show(context, position)),
      ),
    );
  }

  Future<void> _show(BuildContext context, Offset position) async {
    WorkspaceFileMenuAction? file;
    CollectionKind? collectionKind;
    var newFolder = false;

    await showAppMenu<void>(
      context: context,
      globalPosition: position,
      width: WorkspaceFileKindMenuStyle.width,
      entries: [
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
          icon: workspaceAddFolderIcon,
          onSelected: () => newFolder = true,
        ),
        ...workspaceFileKindEntries(
          onSelected: (selected) => file = selected,
          onCreateCollection: (kind) => collectionKind = kind,
        ),
      ],
    );

    final parentId = repoParentIdFor(collection, controller, parentPath);
    if (newFolder) {
      await const WorkspaceItemService().createFolder(
        parentViewId: parentId,
        name: LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
      );
      return;
    }
    if (collectionKind != null) {
      await createRepoCollection(collection, parentId, collectionKind!);
      return;
    }
    if (file != null) {
      await createWorkspaceFile(parentViewId: parentId, action: file!);
    }
  }
}

void _notify(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}
