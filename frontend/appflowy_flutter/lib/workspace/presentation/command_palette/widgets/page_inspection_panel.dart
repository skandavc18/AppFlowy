import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart' show AppFlowyMotion;
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'page_preview.dart';
import 'search_icon.dart';

class PageInspectionPanel extends StatefulWidget {
  const PageInspectionPanel({
    required this.view,
    required this.cachedViews,
    required this.currentUserId,
    required this.onOpen,
    required this.onClose,
    this.onBack,
    this.query,
    this.matchingSnippet,
    this.contentSearch = false,
    this.metadataOnly = false,
    this.canUseView,
    super.key,
  });

  final ViewPB view;
  final Map<String, ViewPB> cachedViews;
  final Int64? currentUserId;
  final ValueChanged<ViewPB> onOpen;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final String? query;
  final String? matchingSnippet;
  final bool contentSearch;
  final bool metadataOnly;
  final bool Function(String id)? canUseView;

  @override
  State<PageInspectionPanel> createState() => _PageInspectionPanelState();
}

class _PageInspectionPanelState extends State<PageInspectionPanel> {
  /// How long the pointer rests on a row before its preview is built, so a
  /// sweep across the list never builds the preview of every row it crosses.
  static const _settleDelay = Duration(milliseconds: 80);

  /// The view on show, which trails [PageInspectionPanel.view] while it moves.
  late ViewPB _view;
  String? _snippet;
  Timer? _settle;

  /// Bumped to drop the outgoing preview at once instead of fading it.
  int _cut = 0;
  late bool isFavorite;
  bool updatingFavorite = false;
  int favoriteRequest = 0;
  String? inspectedFolderId;

  @override
  void initState() {
    super.initState();
    _show(widget.view);
  }

  void _show(ViewPB view) {
    _view = view;
    _snippet = widget.matchingSnippet;
    isFavorite = view.isFavorite;
    updatingFavorite = false;
    favoriteRequest++;
    inspectedFolderId = view.isWorkspaceFolder ? view.id : null;
  }

  @override
  void didUpdateWidget(covariant PageInspectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.view;
    if (next.id == _view.id) {
      _settle?.cancel();
      if (next.isWorkspaceFolder != _view.isWorkspaceFolder) {
        _show(next);
      } else {
        _view = next;
        _snippet = widget.matchingSnippet;
      }
      return;
    }
    _settle?.cancel();
    if (_available(_view)) {
      _settle = Timer(_settleDelay, () {
        if (mounted) setState(() => _show(widget.view));
      });
    } else {
      // A view that was removed or lost its access must not linger, even
      // while fading out.
      _cut++;
      _show(next);
    }
  }

  bool _available(ViewPB view) =>
      widget.cachedViews.containsKey(view.id) &&
      (widget.canUseView?.call(view.id) ?? true);

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final inspectedView = _inspectedView;
    final content = view.isWorkspaceFolder && inspectedView != null
        ? _buildFolderInspection(context, inspectedView)
        : Column(
            children: [
              if (widget.onBack != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey(
                      'command-palette-content-preview-back',
                    ),
                    onPressed: widget.onBack,
                    icon: const WorkspaceGlyph(
                      Icons.arrow_back_rounded,
                      size: 16,
                    ),
                    label: Text(
                      MaterialLocalizations.of(context).backButtonTooltip,
                    ),
                  ),
                ),
              Expanded(
                child: PagePreview(
                  key: ValueKey(view.id),
                  view: view,
                  query: widget.query,
                  matchingSnippet: _snippet,
                  contentSearch: widget.contentSearch,
                  metadataOnly: widget.metadataOnly,
                  onViewOpened: () => widget.onOpen(view),
                ),
              ),
              _buildMetadata(context, view),
              _buildActions(context, view),
            ],
          );
    return ColoredBox(
      key: const ValueKey('command-palette-inspection-panel'),
      color: WorkspacePalette.of(context).elevatedSurface,
      child: AnimatedSwitcher(
        key: ValueKey(_cut),
        duration: WorkspaceTokens.motion(
          context,
          WorkspaceTokens.transitionDuration,
        ),
        reverseDuration:
            WorkspaceTokens.motion(context, WorkspaceTokens.exitDuration),
        switchInCurve: AppFlowyMotion.enterCurve,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) =>
            _PreviewTransition(animation: animation, child: child),
        child: KeyedSubtree(key: ValueKey(view.id), child: content),
      ),
    );
  }

  ViewPB? get _inspectedView {
    final id = inspectedFolderId;
    if (id == null) {
      return null;
    }
    return id == _view.id ? _view : widget.cachedViews[id];
  }

  Widget _buildFolderInspection(BuildContext context, ViewPB folder) {
    final palette = WorkspacePalette.of(context);
    final cover = widget.metadataOnly ? null : folder.cover;
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
                icon: const WorkspaceGlyph(Icons.arrow_back_rounded, size: 16),
                label:
                    Text(MaterialLocalizations.of(context).backButtonTooltip),
              ),
            ),
          ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(WorkspaceTokens.cardRadius),
                        child: SizedBox(
                          height: 128,
                          width: double.infinity,
                          child: cover == null || cover.isNone
                              ? collectionArtwork
                              : ViewCoverImage(
                                  key: const ValueKey(
                                    'command-palette-folder-cover',
                                  ),
                                  cover: cover,
                                  userProfile: context
                                      .read<UserWorkspaceBloc?>()
                                      ?.state
                                      .userProfile,
                                  width: double.infinity,
                                  height: 128,
                                  fallback: collectionArtwork,
                                ),
                        ),
                      ),
                    ),
                    _FolderInspectionBreadcrumbs(
                      root: _view,
                      current: folder,
                      cachedViews: widget.cachedViews,
                      onSelected: _inspectFolder,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              folder.nameOrDefault,
                              style: WorkspaceTypography.style(
                                context,
                                WorkspaceTextRole.section,
                              ),
                            ),
                          ),
                          const VSpace(WorkspaceTokens.space2),
                          Text(
                            LocaleKeys.workspaceFolderExplorer_itemCount.tr(
                              args: [children.length.toString()],
                            ),
                            style: WorkspaceTypography.style(
                              context,
                              WorkspaceTextRole.metadata,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (children.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(WorkspaceTokens.space6),
                      child: Text(
                        LocaleKeys.workspaceFolderExplorer_emptyCollectionHint
                            .tr(),
                        textAlign: TextAlign.center,
                        style: WorkspaceTypography.style(
                          context,
                          WorkspaceTextRole.body,
                          color: palette.secondaryText,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
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
                      childCount: children.length,
                    ),
                  ),
                ),
            ],
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
      favoriteRequest++;
    });
  }

  Widget _buildMetadata(BuildContext context, ViewPB view) {
    final palette = WorkspacePalette.of(context);
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
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WorkspaceGlyph(
                _layoutIcon(view.layout),
                size: 14,
                color: palette.secondaryText,
              ),
              const HSpace(6),
              Expanded(
                child: Text(
                  parent == null
                      ? _layoutLabel(view.layout)
                      : '${parent.name}  /  ${view.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.metadata,
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                WorkspaceTypography.style(context, WorkspaceTextRole.metadata),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ViewPB view) {
    final palette = WorkspacePalette.of(context);
    final iconStyle = IconButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
      ),
    ).copyWith(
      animationDuration:
          WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: WorkspaceTokens.space2,
        runSpacing: WorkspaceTokens.space2,
        children: [
          _ActionButton(
            key: const ValueKey('command-palette-open-action'),
            icon: Icons.arrow_forward_rounded,
            label: LocaleKeys.settings_files_open.tr(),
            onTap: () => widget.onOpen(view),
          ),
          if (!widget.contentSearch)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!view.isWorkspaceRootFolder)
                  IconButton(
                    key: const ValueKey('command-palette-open-new-tab-action'),
                    tooltip: LocaleKeys.disclosureAction_openNewTab.tr(),
                    style: iconStyle,
                    color: palette.secondaryText,
                    icon: const WorkspaceGlyph(
                      Icons.open_in_new_rounded,
                    ),
                    onPressed: () {
                      if (!(widget.canUseView?.call(view.id) ?? true)) return;
                      getIt<TabsBloc>().openTab(view);
                      widget.onClose();
                    },
                  ),
                Semantics(
                  toggled: isFavorite,
                  child: IconButton(
                    key: const ValueKey('command-palette-favorite-action'),
                    style: iconStyle,
                    tooltip: isFavorite
                        ? LocaleKeys.disclosureAction_unfavorite.tr()
                        : LocaleKeys.disclosureAction_favorite.tr(),
                    color: isFavorite ? palette.accent : palette.secondaryText,
                    icon: WorkspaceGlyph(
                      isFavorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                    ),
                    onPressed:
                        updatingFavorite ? null : () => _toggleFavorite(view),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite(ViewPB view) async {
    if (!(widget.canUseView?.call(view.id) ?? true)) return;
    final request = ++favoriteRequest;
    setState(() => updatingFavorite = true);
    final result = await ViewBackendService.favorite(viewId: view.id);
    if (!mounted || request != favoriteRequest) return;

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
        ViewLayoutPB.Grid => Icons.table_chart_rounded,
        ViewLayoutPB.Board => Icons.view_kanban_rounded,
        ViewLayoutPB.Calendar => Icons.calendar_month_rounded,
        ViewLayoutPB.Chat => Icons.chat_bubble_outline_rounded,
        _ => Icons.description_rounded,
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
    final palette = WorkspacePalette.of(context);
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
                WorkspaceGlyph(
                  Icons.chevron_right_rounded,
                  color: palette.mutedText,
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
                      ? palette.primaryText
                      : palette.secondaryText,
                ),
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.metadata,
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
    final palette = WorkspacePalette.of(context);
    return TextButton(
      key: ValueKey('command-palette-folder-child-${view.id}'),
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: palette.primaryText,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        ),
      ).copyWith(
        animationDuration:
            WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
        overlayColor: WidgetStatePropertyAll(palette.hover),
      ),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 19,
            child: Center(
              child: view.buildIcon(context),
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
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.cardTitle,
                  ),
                ),
                const VSpace(3),
                Text(
                  typeLabel,
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.metadata,
                  ),
                ),
              ],
            ),
          ),
          WorkspaceGlyph(
            view.isWorkspaceFolder
                ? Icons.chevron_right_rounded
                : Icons.open_in_new_rounded,
            size: 16,
            color: palette.mutedText,
          ),
        ],
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
    final palette = WorkspacePalette.of(context);
    return TextButton.icon(
      onPressed: onTap,
      icon: WorkspaceGlyph(icon),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: palette.accent,
        backgroundColor: palette.selected,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: WorkspaceTypography.style(context, WorkspaceTextRole.body),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        ),
      ).copyWith(
        animationDuration:
            WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
      ),
    );
  }
}

/// The next preview rises a few pixels as it fades in; the one leaving only
/// fades, and stops taking input the moment it starts to go.
class _PreviewTransition extends AnimatedWidget {
  const _PreviewTransition({
    required Animation<double> animation,
    required this.child,
  }) : super(listenable: animation);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    final leaving = animation.status == AnimationStatus.reverse ||
        animation.status == AnimationStatus.dismissed;
    final progress = animation.value;
    return IgnorePointer(
      ignoring: leaving,
      child: ExcludeSemantics(
        excluding: leaving,
        child: Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, leaving ? 0 : 8 * (1 - progress)),
            child: child,
          ),
        ),
      ),
    );
  }
}
