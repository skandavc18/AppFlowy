import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

typedef WorkspaceFolderSelected = FutureOr<void> Function(ViewPB folder);
typedef WorkspaceViewSelected = FutureOr<void> Function(ViewPB view);
typedef WorkspaceViewFilter = bool Function(ViewPB view);
typedef WorkspaceViewLeadingBuilder = Widget Function(
  BuildContext context,
  ViewPB view,
  FolderExplorerPalette palette,
);

class WorkspaceFolderPickerMenu extends StatelessWidget {
  const WorkspaceFolderPickerMenu({
    super.key,
    required this.onSelected,
    this.selectedFolderId,
    this.repository = const WorkspaceItemService(),
  });

  final WorkspaceFolderSelected onSelected;
  final String? selectedFolderId;
  final WorkspaceItemRepository repository;

  @override
  Widget build(BuildContext context) {
    return WorkspaceViewPickerMenu(
      contentKey: const ValueKey('workspace-folder-picker-menu'),
      title: LocaleKeys.workspaceFolderExplorer_chooseFolder.tr(),
      searchHint: LocaleKeys.workspaceFolderExplorer_searchFolders.tr(),
      emptyMessage: LocaleKeys.workspaceFolderExplorer_noFoldersFound.tr(),
      errorMessage: LocaleKeys.workspaceFolderExplorer_operationFailed.tr(),
      selectedViewId: selectedFolderId,
      repository: repository,
      viewFilter: (view) => view.isWorkspaceFolder,
      leadingBuilder: (context, view, palette) => WorkspaceItemIcon.fromView(
        view: view,
        size: 17,
        color: palette.accent,
      ),
      onSelected: onSelected,
    );
  }
}

class WorkspaceViewPickerMenu extends StatefulWidget {
  const WorkspaceViewPickerMenu({
    super.key,
    required this.title,
    required this.searchHint,
    required this.emptyMessage,
    required this.errorMessage,
    required this.viewFilter,
    required this.leadingBuilder,
    required this.onSelected,
    this.contentKey,
    this.selectedViewId,
    this.repository = const WorkspaceItemService(),
  });

  final Key? contentKey;
  final String title;
  final String searchHint;
  final String emptyMessage;
  final String errorMessage;
  final WorkspaceViewFilter viewFilter;
  final WorkspaceViewLeadingBuilder leadingBuilder;
  final WorkspaceViewSelected onSelected;
  final String? selectedViewId;
  final WorkspaceItemRepository repository;

  @override
  State<WorkspaceViewPickerMenu> createState() =>
      _WorkspaceViewPickerMenuState();
}

class _WorkspaceViewPickerMenuState extends State<WorkspaceViewPickerMenu> {
  final searchController = TextEditingController();
  List<ViewPB> views = const [];
  Object? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final query = searchController.text.trim().toLowerCase();
    final visibleViews = views
        .where(
          (view) => query.isEmpty || view.name.toLowerCase().contains(query),
        )
        .toList(growable: false);

    return SizedBox(
      key: widget.contentKey,
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Text(
              widget.title,
              style: TextStyle(
                color: palette.textSecondary,
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: palette.hover.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 16,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontFamily: 'Inter',
                        fontSize: 13,
                      ),
                      decoration: InputDecoration.collapsed(
                        hintText: widget.searchHint,
                        hintStyle: TextStyle(
                          color: palette.textMuted,
                          fontFamily: 'Inter',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 242),
            child: _buildViewList(
              context,
              palette,
              visibleViews,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewList(
    BuildContext context,
    FolderExplorerPalette palette,
    List<ViewPB> visibleViews,
  ) {
    if (loading) {
      return const SizedBox(
        height: 76,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
        ),
      );
    }
    if (error != null) {
      return Tooltip(
        message: error.toString(),
        child: SizedBox(
          height: 76,
          child: Center(
            child: Text(
              widget.errorMessage,
              style: TextStyle(
                color: palette.danger,
                fontFamily: 'Inter',
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }
    if (visibleViews.isEmpty) {
      return SizedBox(
        height: 76,
        child: Center(
          child: Text(
            widget.emptyMessage,
            style: TextStyle(
              color: palette.textMuted,
              fontFamily: 'Inter',
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 7),
      itemCount: visibleViews.length,
      itemExtent: 38,
      itemBuilder: (context, index) {
        final view = visibleViews[index];
        return _ViewPickerRow(
          view: view,
          leading: widget.leadingBuilder(context, view, palette),
          selected: view.id == widget.selectedViewId,
          onSelected: () => widget.onSelected(view),
        );
      },
    );
  }

  Future<void> _load() async {
    final result = await widget.repository.getAllViews();
    if (!mounted) {
      return;
    }
    result.fold(
      (loadedViews) {
        views = loadedViews.where(widget.viewFilter).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        loading = false;
        setState(() {});
      },
      (failure) => setState(() {
        loading = false;
        error = failure;
      }),
    );
  }
}

class _ViewPickerRow extends StatefulWidget {
  const _ViewPickerRow({
    required this.view,
    required this.leading,
    required this.selected,
    required this.onSelected,
  });

  final ViewPB view;
  final Widget leading;
  final bool selected;
  final VoidCallback onSelected;

  @override
  State<_ViewPickerRow> createState() => _ViewPickerRowState();
}

class _ViewPickerRowState extends State<_ViewPickerRow> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.selected
                : hovered
                    ? palette.hover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              widget.leading,
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.view.name.isEmpty
                      ? LocaleKeys.menuAppHeader_defaultNewPageName.tr()
                      : widget.view.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (widget.selected)
                Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: palette.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
