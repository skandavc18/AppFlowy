import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'page_preview.dart';

class PageInspectionPanel extends StatefulWidget {
  const PageInspectionPanel({
    required this.view,
    required this.cachedViews,
    required this.currentUserId,
    required this.onOpen,
    required this.onClose,
    this.onBack,
    super.key,
  });

  final ViewPB view;
  final Map<String, ViewPB> cachedViews;
  final Int64? currentUserId;
  final ValueChanged<ViewPB> onOpen;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  State<PageInspectionPanel> createState() => _PageInspectionPanelState();
}

class _PageInspectionPanelState extends State<PageInspectionPanel> {
  late bool isFavorite;
  bool updatingFavorite = false;
  String? inspectedFolderId;

  @override
  void initState() {
    super.initState();
    isFavorite = widget.view.isFavorite;
    inspectedFolderId = widget.view.isWorkspaceFolder ? widget.view.id : null;
  }

  @override
  void didUpdateWidget(covariant PageInspectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id ||
        oldWidget.view.isWorkspaceFolder != widget.view.isWorkspaceFolder) {
      isFavorite = widget.view.isFavorite;
      updatingFavorite = false;
      inspectedFolderId = widget.view.isWorkspaceFolder ? widget.view.id : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final inspectedView = _inspectedView;
    return Container(
      key: const ValueKey('command-palette-inspection-panel'),
      margin: EdgeInsets.only(right: widget.onBack == null ? 24 : 0),
      decoration: BoxDecoration(
        border: widget.onBack == null
            ? Border(
                right: BorderSide(color: theme.borderColorScheme.primary),
              )
            : null,
      ),
      child: widget.view.isWorkspaceFolder && inspectedView != null
          ? _buildFolderInspection(context, inspectedView)
          : Column(
              children: [
                _buildMetadata(context, widget.view),
                Expanded(
                  child: Center(
                    child: PagePreview(
                      key: ValueKey(widget.view.id),
                      view: widget.view,
                      onViewOpened: () => widget.onOpen(widget.view),
                    ),
                  ),
                ),
                _buildActions(context, widget.view),
              ],
            ),
    );
  }

  ViewPB? get _inspectedView {
    final id = inspectedFolderId;
    if (id == null) {
      return null;
    }
    return id == widget.view.id ? widget.view : widget.cachedViews[id];
  }

  Widget _buildFolderInspection(BuildContext context, ViewPB folder) {
    final palette = FolderExplorerPalette.of(context);
    final cover = folder.cover;
    final collectionArtwork = FolderGalleryCollectionArtwork(
      item: WorkspaceExplorerItem.fromView(folder),
    );
    final children = widget.cachedViews.values
        .where((view) => view.parentViewId == folder.id)
        .toList(growable: false)
      ..sort((left, right) {
        final folderOrder = (right.isWorkspaceFolder ? 1 : 0) -
            (left.isWorkspaceFolder ? 1 : 0);
        return folderOrder != 0
            ? folderOrder
            : left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: TextButton.icon(
                key: const ValueKey('command-palette-folder-browser-back'),
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label:
                    Text(MaterialLocalizations.of(context).backButtonTooltip),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              height: 142,
              width: double.infinity,
              child: cover == null || cover.isNone
                  ? collectionArtwork
                  : ViewCoverImage(
                      key: const ValueKey('command-palette-folder-cover'),
                      cover: cover,
                      userProfile:
                          context.read<UserWorkspaceBloc?>()?.state.userProfile,
                      width: double.infinity,
                      height: 142,
                      fallback: collectionArtwork,
                    ),
            ),
          ),
        ),
        _FolderInspectionBreadcrumbs(
          root: widget.view,
          current: folder,
          cachedViews: widget.cachedViews,
          onSelected: _inspectFolder,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 18,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.25,
                  ),
                ),
              ),
              Text(
                LocaleKeys.workspaceFolderExplorer_itemCount.tr(
                  args: [children.length.toString()],
                ),
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: children.isEmpty
              ? Center(
                  child: Text(
                    LocaleKeys.workspaceFolderExplorer_emptyCollectionHint.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  itemCount: children.length,
                  itemBuilder: (context, index) {
                    final child = children[index];
                    return _FolderInspectionItem(
                      view: child,
                      typeLabel: _viewTypeLabel(child),
                      onTap: () {
                        if (child.isWorkspaceFolder) {
                          _inspectFolder(child);
                        } else {
                          widget.onOpen(child);
                        }
                      },
                    );
                  },
                ),
        ),
        _buildActions(context, folder),
      ],
    );
  }

  void _inspectFolder(ViewPB folder) {
    setState(() {
      inspectedFolderId = folder.id;
      isFavorite = folder.isFavorite;
      updatingFavorite = false;
    });
  }

  Widget _buildMetadata(BuildContext context, ViewPB view) {
    final theme = AppFlowyTheme.of(context);
    final parent = widget.cachedViews[view.parentViewId];
    final creator = widget.currentUserId != null &&
            view.hasCreatedBy() &&
            view.createdBy == widget.currentUserId
        ? LocaleKeys.commandPalette_me.tr()
        : LocaleKeys.commandPalette_anotherMember.tr();
    final editedAt = DateTime.fromMillisecondsSinceEpoch(
      view.lastEdited.toInt() * 1000,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _layoutIcon(view.layout),
                size: 14,
                color: theme.iconColorScheme.secondary,
              ),
              const HSpace(6),
              Expanded(
                child: Text(
                  parent == null
                      ? _layoutLabel(view.layout)
                      : '${parent.name}  /  ${view.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyle.caption.enhanced(
                    color: theme.textColorScheme.secondary,
                  ),
                ),
              ),
            ],
          ),
          const VSpace(6),
          Text(
            '${LocaleKeys.commandPalette_createdBy.tr()} $creator'
            '  ·  ${LocaleKeys.commandPalette_edited.tr()} '
            '${DateFormat.yMMMd(context.locale.toLanguageTag()).format(editedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textStyle.caption.enhanced(
              color: theme.textColorScheme.tertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ViewPB view) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
      child: Row(
        children: [
          _ActionButton(
            key: const ValueKey('command-palette-open-action'),
            icon: Icons.arrow_forward_rounded,
            label: LocaleKeys.settings_files_open.tr(),
            onTap: () => widget.onOpen(view),
          ),
          const Spacer(),
          if (!view.isWorkspaceRootFolder) ...[
            FlowyTooltip(
              message: LocaleKeys.disclosureAction_openNewTab.tr(),
              child: FlowyIconButton(
                key: const ValueKey('command-palette-open-new-tab-action'),
                width: 32,
                height: 32,
                icon: Icon(
                  Icons.open_in_new_rounded,
                  size: 17,
                  color: theme.iconColorScheme.secondary,
                ),
                onPressed: () {
                  getIt<TabsBloc>().openTab(view);
                  widget.onClose();
                },
              ),
            ),
            const HSpace(4),
          ],
          FlowyTooltip(
            message: isFavorite
                ? LocaleKeys.disclosureAction_unfavorite.tr()
                : LocaleKeys.disclosureAction_favorite.tr(),
            child: FlowyIconButton(
              key: const ValueKey('command-palette-favorite-action'),
              width: 32,
              height: 32,
              icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                size: 18,
                color: isFavorite
                    ? theme.iconColorScheme.warningThick
                    : theme.iconColorScheme.secondary,
              ),
              onPressed: updatingFavorite ? null : () => _toggleFavorite(view),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite(ViewPB view) async {
    setState(() => updatingFavorite = true);
    final result = await ViewBackendService.favorite(viewId: view.id);
    if (!mounted) return;

    result.fold(
      (_) => setState(() {
        isFavorite = !isFavorite;
        updatingFavorite = false;
      }),
      (error) {
        setState(() => updatingFavorite = false);
        showMessageToast(error.toString(), context: context);
      },
    );
  }

  String _layoutLabel(ViewLayoutPB layout) => switch (layout) {
        ViewLayoutPB.Document => LocaleKeys.commandPalette_documents.tr(),
        ViewLayoutPB.Grid => LocaleKeys.commandPalette_grids.tr(),
        ViewLayoutPB.Board => LocaleKeys.commandPalette_boards.tr(),
        ViewLayoutPB.Calendar => LocaleKeys.commandPalette_calendars.tr(),
        ViewLayoutPB.Chat => LocaleKeys.commandPalette_chats.tr(),
        _ => LocaleKeys.commandPalette_allPageTypes.tr(),
      };

  String _viewTypeLabel(ViewPB view) {
    if (view.isWorkspaceFolder) {
      return LocaleKeys.workspaceFolderExplorer_collection.tr();
    }
    if (view.isWorkspaceFile) {
      return LocaleKeys.workspaceFolderExplorer_file.tr();
    }
    return _layoutLabel(view.layout);
  }

  IconData _layoutIcon(ViewLayoutPB layout) => switch (layout) {
        ViewLayoutPB.Grid => Icons.table_chart_outlined,
        ViewLayoutPB.Board => Icons.view_kanban_outlined,
        ViewLayoutPB.Calendar => Icons.calendar_month_outlined,
        ViewLayoutPB.Chat => Icons.chat_bubble_outline_rounded,
        _ => Icons.description_outlined,
      };
}

class _FolderInspectionBreadcrumbs extends StatelessWidget {
  const _FolderInspectionBreadcrumbs({
    required this.root,
    required this.current,
    required this.cachedViews,
    required this.onSelected,
  });

  final ViewPB root;
  final ViewPB current;
  final Map<String, ViewPB> cachedViews;
  final ValueChanged<ViewPB> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final path = <ViewPB>[current];
    var cursor = current;
    final visited = <String>{current.id};
    while (cursor.id != root.id &&
        cursor.parentViewId.isNotEmpty &&
        visited.add(cursor.parentViewId)) {
      final parent = cachedViews[cursor.parentViewId];
      if (parent == null) {
        break;
      }
      path.add(parent);
      cursor = parent;
    }
    if (path.last.id != root.id) {
      path.add(root);
    }
    final ordered = path.reversed.toList(growable: false);

    return SizedBox(
      height: 38,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        scrollDirection: Axis.horizontal,
        itemCount: ordered.length,
        itemBuilder: (context, index) {
          final folder = ordered[index];
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 0)
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.textMuted,
                  size: 15,
                ),
              TextButton(
                onPressed: () => onSelected(folder),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: index == ordered.length - 1
                      ? palette.textPrimary
                      : palette.textSecondary,
                ),
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: index == ordered.length - 1
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FolderInspectionItem extends StatelessWidget {
  const _FolderInspectionItem({
    required this.view,
    required this.typeLabel,
    required this.onTap,
  });

  final ViewPB view;
  final String typeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return InkWell(
      key: ValueKey('command-palette-folder-child-${view.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: palette.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 19,
              child: Center(
                child: view.defaultIcon(size: const Size.square(17)),
              ),
            ),
            const HSpace(9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    view.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const VSpace(3),
                  Text(
                    typeLabel.toUpperCase(),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.75,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              view.isWorkspaceFolder
                  ? Icons.chevron_right_rounded
                  : Icons.open_in_new_rounded,
              size: 16,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return AFOutlinedButton.normal(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      borderRadius: 8,
      onTap: onTap,
      builder: (context, hovering, disabled) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.iconColorScheme.primary),
          const HSpace(5),
          Text(
            label,
            style: theme.textStyle.caption.enhanced(
              color: theme.textColorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
