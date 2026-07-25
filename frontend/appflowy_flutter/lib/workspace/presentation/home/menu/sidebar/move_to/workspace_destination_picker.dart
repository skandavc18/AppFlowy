import 'dart:math' as math;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_transfer_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_root_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum WorkspaceDestinationOperation {
  move,
  copy,
}

Future<String?> showWorkspaceDestinationPicker({
  required BuildContext context,
  required List<ViewPB> sourceViews,
  required String rootId,
  required String rootName,
  String? rootIcon,
  required WorkspaceDestinationOperation operation,
  WorkspaceItemRepository repository = const WorkspaceItemService(),
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (_) => WorkspaceDestinationPicker(
      sourceViews: sourceViews,
      rootId: rootId,
      rootName: rootName,
      rootIcon: rootIcon,
      operation: operation,
      repository: repository,
    ),
  );
}

class WorkspaceDestinationPicker extends StatefulWidget {
  const WorkspaceDestinationPicker({
    super.key,
    required this.sourceViews,
    required this.rootId,
    required this.rootName,
    this.rootIcon,
    required this.operation,
    this.repository = const WorkspaceItemService(),
  });

  final List<ViewPB> sourceViews;
  final String rootId;
  final String rootName;
  final String? rootIcon;
  final WorkspaceDestinationOperation operation;
  final WorkspaceItemRepository repository;

  @override
  State<WorkspaceDestinationPicker> createState() =>
      _WorkspaceDestinationPickerState();
}

class _WorkspaceDestinationPickerState
    extends State<WorkspaceDestinationPicker> {
  late final Future<List<ViewPB>> _views = _loadViews();
  final TextEditingController searchController = TextEditingController();
  String? currentFolderId;
  String query = '';

  Future<List<ViewPB>> _loadViews() async {
    final result = await widget.repository.getAllViews();
    return result.fold(
      (views) => views,
      (error) => throw _DestinationLoadException(error.msg),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final theme = Theme.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final viewport = MediaQuery.sizeOf(context);
    final width = math.min(720.0, viewport.width - 48);
    final height = math.min(610.0, viewport.height - 64);
    final background = EditorSurfaceStyle.canvasBackgroundFor(
      theme.brightness,
      palette.surface,
      isPaper: isPaper,
    );

    return Dialog(
      key: const ValueKey('workspace-destination-picker'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      backgroundColor: Colors.transparent,
      shadowColor: palette.shadow.withValues(alpha: 0.28),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.34 : 0.14,
              ),
              blurRadius: 44,
              offset: const Offset(0, 20),
              spreadRadius: -12,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<List<ViewPB>>(
          future: _views,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator.adaptive());
            }
            if (snapshot.hasError) {
              return _DestinationError(
                message: switch (snapshot.error) {
                  _DestinationLoadException(:final message) => message,
                  _ => LocaleKeys.workspaceFolderExplorer_operationFailed.tr(),
                },
              );
            }
            return _buildContent(context, snapshot.data!);
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<ViewPB> views) {
    final palette = FolderExplorerPalette.of(context);
    final viewsById = {for (final view in views) view.id: view};
    final sourceScopes = widget.sourceViews
        .map(
          (view) => workspaceTransferScopeId(
            view: view,
            allViews: views,
          ),
        )
        .toSet();
    final sourceScopeId = sourceScopes.length == 1 ? sourceScopes.single : null;
    final scopeRoot = sourceScopeId == null ? null : viewsById[sourceScopeId];
    final rootId = scopeRoot?.id ?? widget.rootId;
    final rootName = scopeRoot?.nameOrDefault ?? widget.rootName;
    final selectedFolderId = currentFolderId ?? rootId;
    final invalidIds = workspaceInvalidDestinationIds(
      sources: widget.sourceViews,
      allViews: views,
    );
    final items = views
        .where(
          (view) =>
              !view.isSpace &&
              workspaceTransferScopeId(view: view, allViews: views) ==
                  sourceScopeId,
        )
        .toList(growable: false);
    final normalizedQuery = query.trim().toLowerCase();
    final visibleItems = normalizedQuery.isEmpty
        ? items
            .where((view) => view.parentViewId == selectedFolderId)
            .toList(growable: false)
        : items
            .where(
              (view) =>
                  view.nameOrDefault.toLowerCase().contains(normalizedQuery),
            )
            .toList(growable: false);
    visibleItems.sort(
      (left, right) {
        final containerOrder = (right.canContainWorkspaceItems ? 1 : 0)
            .compareTo(left.canContainWorkspaceItems ? 1 : 0);
        return containerOrder != 0
            ? containerOrder
            : left.nameOrDefault
                .toLowerCase()
                .compareTo(right.nameOrDefault.toLowerCase());
      },
    );
    final currentName = selectedFolderId == rootId
        ? rootName
        : viewsById[selectedFolderId]?.nameOrDefault ??
            LocaleKeys.workspaceFolderExplorer_folder.tr();
    final canSubmit = sourceScopes.length == 1 &&
        !invalidIds.contains(selectedFolderId) &&
        !(_isMove &&
            widget.sourceViews.isNotEmpty &&
            widget.sourceViews.every(
              (view) => view.parentViewId == selectedFolderId,
            ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 18, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      LocaleKeys.workspaceFolderExplorer_chooseDestinationHint
                          .tr(),
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.close_rounded,
                  color: palette.textSecondary,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _DestinationSearchField(
            controller: searchController,
            onChanged: (value) => setState(() => query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 17, 24, 12),
          child: _DestinationBreadcrumbs(
            currentFolderId: selectedFolderId,
            rootId: rootId,
            rootName: rootName,
            rootIcon: rootId == widget.rootId ? widget.rootIcon : null,
            viewsById: viewsById,
            onSelected: (id) => setState(() {
              currentFolderId = id;
              query = '';
              searchController.clear();
            }),
          ),
        ),
        Expanded(
          child: visibleItems.isEmpty
              ? _DestinationEmptyState(searching: normalizedQuery.isNotEmpty)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  itemCount: visibleItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 3),
                  itemBuilder: (context, index) {
                    final item = visibleItems[index];
                    final canOpen = item.canContainWorkspaceItems &&
                        !invalidIds.contains(item.id);
                    return _DestinationItemTile(
                      view: item,
                      canOpen: canOpen,
                      path: normalizedQuery.isEmpty
                          ? null
                          : _itemPath(
                              item,
                              viewsById,
                              rootName: rootName,
                              rootId: rootId,
                            ),
                      onTap: canOpen
                          ? () => setState(() {
                                currentFolderId = item.id;
                                query = '';
                                searchController.clear();
                              })
                          : null,
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  LocaleKeys.workspaceFolderExplorer_destination.tr(
                    namedArgs: {'name': currentName},
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  LocaleKeys.workspaceFolderExplorer_cancel.tr(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('workspace-destination-confirm'),
                onPressed: canSubmit
                    ? () => Navigator.of(context).pop(selectedFolderId)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(_confirmLabel),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool get _isMove => widget.operation == WorkspaceDestinationOperation.move;

  String get _title => _isMove
      ? LocaleKeys.workspaceFolderExplorer_moveToFolder.tr()
      : LocaleKeys.workspaceFolderExplorer_copyToFolder.tr();

  String get _confirmLabel => _isMove
      ? LocaleKeys.workspaceFolderExplorer_moveHere.tr()
      : LocaleKeys.workspaceFolderExplorer_copyHere.tr();
}

class _DestinationSearchField extends StatelessWidget {
  const _DestinationSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final background = EditorSurfaceStyle.previewBackgroundFor(
      Theme.of(context).brightness,
      palette.floatingSurface,
      isPaper: isPaper,
    );
    return TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      style: TextStyle(color: palette.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: LocaleKeys.workspaceFolderExplorer_searchFolders.tr(),
        hintStyle: TextStyle(color: palette.textMuted, fontSize: 14),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: palette.textMuted,
          size: 19,
        ),
        filled: true,
        fillColor: background,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(
            color: palette.accent.withValues(alpha: 0.48),
          ),
        ),
      ),
    );
  }
}

class _DestinationBreadcrumbs extends StatelessWidget {
  const _DestinationBreadcrumbs({
    required this.currentFolderId,
    required this.rootId,
    required this.rootName,
    required this.rootIcon,
    required this.viewsById,
    required this.onSelected,
  });

  final String currentFolderId;
  final String rootId;
  final String rootName;
  final String? rootIcon;
  final Map<String, ViewPB> viewsById;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final path = <({String id, String name})>[
      (id: rootId, name: rootName),
    ];
    if (currentFolderId != rootId) {
      final folders = <ViewPB>[];
      var current = viewsById[currentFolderId];
      final visited = <String>{};
      while (current != null && visited.add(current.id)) {
        folders.add(current);
        if (current.parentViewId == rootId) {
          break;
        }
        current = viewsById[current.parentViewId];
      }
      path.addAll(
        folders.reversed.map(
          (view) => (id: view.id, name: view.nameOrDefault),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < path.length; index++) ...[
            if (index > 0)
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: palette.textMuted,
              ),
            TextButton(
              onPressed: () => onSelected(path[index].id),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: index == path.length - 1
                    ? palette.textPrimary
                    : palette.textSecondary,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index == 0) ...[
                    if (rootIcon != null)
                      WorkspaceIcon(
                        key: const ValueKey('workspace-root-icon'),
                        workspaceIcon: rootIcon!,
                        workspaceName: rootName,
                        iconSize: 19,
                        isEditable: false,
                        fontSize: 10,
                        emojiSize: 16,
                        borderRadius: 5.5,
                        figmaLineHeight: 16,
                        showBorder: false,
                        onSelected: (_) {},
                      )
                    else
                      const WorkspaceRootIcon(size: 19),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    path[index].name,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: index == path.length - 1
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DestinationItemTile extends StatelessWidget {
  const _DestinationItemTile({
    required this.view,
    required this.canOpen,
    required this.onTap,
    this.path,
  });

  final ViewPB view;
  final bool canOpen;
  final VoidCallback? onTap;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Opacity(
      opacity: canOpen ? 1 : 0.62,
      child: InkWell(
        key: ValueKey('workspace-destination-${view.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        hoverColor: canOpen ? palette.hover : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              ViewCoverThumbnail(
                cover: view.cover,
                userProfile:
                    context.read<UserWorkspaceBloc?>()?.state.userProfile,
                width: 36,
                height: 28,
                borderRadius: 7,
                fallback: SizedBox(
                  width: 36,
                  height: 28,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox.square(
                      dimension: 20,
                      child: WorkspaceItemIcon.fromView(
                        view: view,
                        color:
                            canOpen ? palette.textSecondary : palette.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.nameOrDefault,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (path != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        path!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _itemKindLabel(view),
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (canOpen) ...[
                const SizedBox(width: 5),
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.textMuted,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _itemKindLabel(ViewPB view) {
  return switch (WorkspaceExplorerItem.fromView(view).kind) {
    WorkspaceExplorerItemKind.folder =>
      LocaleKeys.workspaceFolderExplorer_collection.tr(),
    WorkspaceExplorerItemKind.file =>
      LocaleKeys.workspaceFolderExplorer_file.tr(),
    WorkspaceExplorerItemKind.document =>
      LocaleKeys.workspaceFolderExplorer_page.tr(),
    WorkspaceExplorerItemKind.database =>
      LocaleKeys.workspaceFolderExplorer_database.tr(),
  };
}

class _DestinationEmptyState extends StatelessWidget {
  const _DestinationEmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Center(
      child: Text(
        searching
            ? LocaleKeys.workspaceFolderExplorer_noFoldersFound.tr()
            : LocaleKeys.workspaceFolderExplorer_noChildFolders.tr(),
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      ),
    );
  }
}

class _DestinationError extends StatelessWidget {
  const _DestinationError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary),
        ),
      ),
    );
  }
}

class _DestinationLoadException implements Exception {
  const _DestinationLoadException(this.message);

  final String message;
}

String _itemPath(
  ViewPB item,
  Map<String, ViewPB> viewsById, {
  required String rootName,
  required String rootId,
}) {
  final names = <String>[item.nameOrDefault];
  var current = item;
  final visited = <String>{item.id};
  while (current.parentViewId.isNotEmpty &&
      current.parentViewId != rootId &&
      visited.add(current.parentViewId)) {
    final parent = viewsById[current.parentViewId];
    if (parent == null) {
      break;
    }
    names.add(parent.nameOrDefault);
    current = parent;
  }
  return [rootName, ...names.reversed].join(' / ');
}
