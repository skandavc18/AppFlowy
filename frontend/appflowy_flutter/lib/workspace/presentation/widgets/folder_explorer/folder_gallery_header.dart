import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/features/workspace/presentation/widgets/workspace_cover_actions.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/_sidebar_workspace_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/snap_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

class FolderGalleryHeader extends StatefulWidget {
  const FolderGalleryHeader({
    super.key,
    required this.controller,
    required this.searchController,
    required this.onSearchChanged,
    required this.onNavigate,
    required this.onAddFile,
    required this.onCreateCollection,
    required this.onCreateDatabase,
    required this.onMore,
    this.userProfile,
    this.workspace,
  });

  final WorkspaceExplorerController controller;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onNavigate;
  final ValueChanged<WorkspaceFileMenuAction> onAddFile;
  final ValueChanged<CollectionKind> onCreateCollection;
  final ValueChanged<WorkspaceTableKind> onCreateDatabase;
  final ValueChanged<Offset> onMore;
  final UserProfilePB? userProfile;
  final UserWorkspacePB? workspace;

  @override
  State<FolderGalleryHeader> createState() => _FolderGalleryHeaderState();
}

class _FolderGalleryHeaderState extends State<FolderGalleryHeader> {
  final FocusNode searchFocusNode = FocusNode(
    debugLabel: 'knowledge-gallery-search',
  );
  bool searchExpanded = false;
  bool decorationRegionHovered = false;
  bool hasWorkspaceCoverOverride = false;
  String? workspaceCoverOverrideId;
  PageStyleCover? workspaceCoverOverride;

  @override
  void didUpdateWidget(covariant FolderGalleryHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace?.workspaceId != widget.workspace?.workspaceId) {
      hasWorkspaceCoverOverride = false;
      workspaceCoverOverrideId = null;
      workspaceCoverOverride = null;
      return;
    }
    if (oldWidget.workspace?.cover != widget.workspace?.cover &&
        WorkspaceCoverCodec.decode(widget.workspace?.cover ?? '') ==
            workspaceCoverOverride) {
      hasWorkspaceCoverOverride = false;
      workspaceCoverOverrideId = null;
      workspaceCoverOverride = null;
    }
  }

  @override
  void dispose() {
    searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = FolderExplorerPalette.of(context);
    final folder = controller.currentFolder;
    final folderView = controller.viewForId(folder.id);
    final isWorkspaceRoot = widget.workspace?.workspaceId == folder.id;
    final rootWorkspace = isWorkspaceRoot ? widget.workspace : null;
    final storedWorkspaceCover = !isWorkspaceRoot
        ? null
        : WorkspaceCoverCodec.decode(widget.workspace!.cover);
    final generatedWorkspaceCover =
        isWorkspaceRoot && widget.workspace!.cover.trim().isEmpty
            ? AutomaticViewCover.forWorkspace(name: widget.workspace!.name)
            : null;
    final workspaceCover = hasWorkspaceCoverOverride &&
            workspaceCoverOverrideId == rootWorkspace?.workspaceId
        ? workspaceCoverOverride
        : storedWorkspaceCover ?? generatedWorkspaceCover;
    final stats = [
      LocaleKeys.workspaceFolderExplorer_noteCount.tr(
        args: [controller.visibleFileCount.toString()],
      ),
      LocaleKeys.workspaceFolderExplorer_collectionCount.tr(
        args: [controller.visibleFolderCount.toString()],
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal =
            KnowledgeGalleryLayout.horizontalPadding(constraints.maxWidth);
        final compact = constraints.maxWidth < 760;
        final cover = isWorkspaceRoot ? workspaceCover : folderView?.cover;
        return MouseRegion(
          onEnter: (_) => _setDecorationRegionHovered(true),
          onExit: (_) => _setDecorationRegionHovered(false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cover != null && !cover.isNone)
                Padding(
                  padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: KnowledgeGalleryLayout.maxContentWidth,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          height: compact ? 168 : 218,
                          width: double.infinity,
                          child: ViewCoverImage(
                            cover: cover,
                            userProfile: widget.userProfile,
                            width: double.infinity,
                            height: compact ? 168 : 218,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  cover == null || cover.isNone ? 34 : 22,
                  horizontal,
                  30,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: KnowledgeGalleryLayout.maxContentWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (controller.breadcrumbs.length > 1) ...[
                        _GalleryBreadcrumbs(
                          items: controller.breadcrumbs,
                          onSelected: widget.onNavigate,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (rootWorkspace case final workspace?) ...[
                        WorkspaceCoverActions(
                          workspace: workspace,
                          userProfile: widget.userProfile,
                          generateDefaultWhenMissing: true,
                          onCoverChanged: (cover) =>
                              _setWorkspaceCoverOverride(workspace, cover),
                        ),
                      ] else if (folderView != null) ...[
                        ViewDecorationActions(
                          view: folderView,
                          userProfile: widget.userProfile,
                          onViewChanged: controller.updateView,
                          visible: !UniversalPlatform.isDesktopOrWeb ||
                              decorationRegionHovered,
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (compact) ...[
                        _GalleryHeading(
                          folder: folder,
                          view: folderView,
                          workspace: rootWorkspace,
                          stats: stats,
                          editing: controller.editingId == folder.id,
                          onRename: () => controller.beginRename(folder.id),
                          onSubmitted: rootWorkspace == null
                              ? controller.commitRename
                              : _renameWorkspace,
                          onCancelled: controller.cancelEditing,
                          onViewChanged: controller.updateView,
                        ),
                        const SizedBox(height: 22),
                        _buildActions(context, palette),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: _GalleryHeading(
                                folder: folder,
                                view: folderView,
                                workspace: rootWorkspace,
                                stats: stats,
                                editing: controller.editingId == folder.id,
                                onRename: () =>
                                    controller.beginRename(folder.id),
                                onSubmitted: rootWorkspace == null
                                    ? controller.commitRename
                                    : _renameWorkspace,
                                onCancelled: controller.cancelEditing,
                                onViewChanged: controller.updateView,
                              ),
                            ),
                            const SizedBox(width: 36),
                            _buildActions(context, palette),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _setDecorationRegionHovered(bool value) {
    if (decorationRegionHovered == value) {
      return;
    }
    setState(() => decorationRegionHovered = value);
  }

  void _setWorkspaceCoverOverride(
    UserWorkspacePB workspace,
    PageStyleCover? cover,
  ) {
    if (!mounted) {
      return;
    }
    setState(() {
      hasWorkspaceCoverOverride = true;
      workspaceCoverOverrideId = workspace.workspaceId;
      workspaceCoverOverride = cover;
    });
  }

  Future<bool> _renameWorkspace(String rawName) async {
    final workspace = widget.workspace;
    final name = rawName.trim();
    if (workspace == null || name.isEmpty) {
      return false;
    }
    if (workspace.name == name) {
      widget.controller.cancelEditing();
      return true;
    }

    final bloc = context.read<UserWorkspaceBloc>();
    final completion = bloc.stream.firstWhere(
      (state) =>
          state.actionResult?.actionType == WorkspaceActionType.rename &&
          state.actionResult?.isLoading == false,
    );
    bloc.add(
      UserWorkspaceEvent.renameWorkspace(
        workspaceId: workspace.workspaceId,
        name: name,
      ),
    );
    final result = (await completion).actionResult?.result;
    if (!mounted) {
      return false;
    }
    return result?.fold(
          (_) {
            widget.controller.cancelEditing();
            return true;
          },
          (error) {
            showSnapBar(context, error.msg);
            return false;
          },
        ) ??
        false;
  }

  Widget _buildActions(
    BuildContext context,
    FolderExplorerPalette palette,
  ) {
    final showSearch = searchExpanded || widget.controller.query.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          width: showSearch ? 238 : 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDark
                ? Color.alphaBlend(
                    palette.accent.withValues(alpha: 0.10),
                    palette.surface,
                  )
                : palette.hover.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(13),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Row(
              children: [
                _GalleryControl(
                  icon: Icons.search_rounded,
                  semanticLabel:
                      LocaleKeys.workspaceFolderExplorer_searchCollection.tr(),
                  foregroundColor: isDark ? palette.accent : null,
                  onPressed: _showSearch,
                ),
                if (showSearch)
                  Expanded(
                    child: TextField(
                      controller: widget.searchController,
                      focusNode: searchFocusNode,
                      onChanged: widget.onSearchChanged,
                      onTapOutside: (_) => _collapseSearch(),
                      cursorColor: palette.accent,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontFamily: 'Inter',
                        fontSize: 13,
                        height: 1.2,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        hintText: LocaleKeys
                            .workspaceFolderExplorer_searchCollection
                            .tr(),
                        hintStyle: TextStyle(
                          color: palette.textMuted,
                          fontFamily: 'Inter',
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                if (showSearch && widget.searchController.text.isNotEmpty)
                  _GalleryControl(
                    icon: Icons.close_rounded,
                    semanticLabel:
                        LocaleKeys.workspaceFolderExplorer_cancel.tr(),
                    onPressed: _clearSearch,
                    compact: true,
                  ),
              ],
            ),
          ),
        ),
        Builder(
          builder: (buttonContext) => _GalleryControl(
            icon: Icons.add_rounded,
            label: LocaleKeys.workspaceFolderExplorer_addFile.tr(),
            semanticLabel: LocaleKeys.workspaceFolderExplorer_addFile.tr(),
            primary: true,
            onPressed: () async {
              final box = buttonContext.findRenderObject() as RenderBox?;
              if (box == null) {
                return;
              }
              final action = await showWorkspaceFileKindMenu(
                context: buttonContext,
                globalPosition:
                    box.localToGlobal(Offset(0, box.size.height + 4)),
                onCreateCollection: widget.onCreateCollection,
                onCreateDatabase: widget.onCreateDatabase,
              );
              if (action != null) {
                widget.onAddFile(action);
              }
            },
          ),
        ),
        Builder(
          builder: (buttonContext) => _GalleryControl(
            icon: Icons.more_horiz_rounded,
            semanticLabel: LocaleKeys.workspaceFolderExplorer_more.tr(),
            onPressed: () {
              final box = buttonContext.findRenderObject() as RenderBox;
              widget.onMore(
                box.localToGlobal(Offset(box.size.width, box.size.height)),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showSearch() {
    if (!searchExpanded) {
      setState(() => searchExpanded = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          searchFocusNode.requestFocus();
        }
      });
      return;
    }
    searchFocusNode.requestFocus();
  }

  void _collapseSearch() {
    if (widget.searchController.text.isEmpty && searchExpanded) {
      setState(() => searchExpanded = false);
    }
  }

  void _clearSearch() {
    widget.searchController.clear();
    widget.onSearchChanged('');
    searchFocusNode.requestFocus();
    setState(() {});
  }
}

class _GalleryHeading extends StatelessWidget {
  const _GalleryHeading({
    required this.folder,
    required this.view,
    required this.workspace,
    required this.stats,
    required this.editing,
    required this.onRename,
    required this.onSubmitted,
    required this.onCancelled,
    required this.onViewChanged,
  });

  final WorkspaceExplorerItem folder;
  final ViewPB? view;
  final UserWorkspacePB? workspace;
  final List<String> stats;
  final bool editing;
  final VoidCallback onRename;
  final Future<bool> Function(String name) onSubmitted;
  final VoidCallback onCancelled;
  final ValueChanged<ViewPB> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final titleStyle = TextStyle(
      color: palette.textPrimary,
      fontFamily: 'Inter',
      fontSize: 32,
      height: 1.08,
      fontWeight: FontWeight.w600,
      letterSpacing: -1.05,
    );
    final rawTitle = workspace?.name ?? folder.name;
    final title = rawTitle.isEmpty
        ? LocaleKeys.workspaceFolderExplorer_untitledFolder.tr()
        : rawTitle;
    final icon = view?.icon.toEmojiIconData();
    final Widget? titleIcon;
    if (workspace case final currentWorkspace?) {
      titleIcon = WorkspaceIcon(
        key: const ValueKey('workspace-gallery-icon'),
        workspaceIcon: currentWorkspace.icon,
        workspaceName: currentWorkspace.name,
        iconSize: 48,
        isEditable: true,
        fontSize: 25,
        emojiSize: 39,
        borderRadius: 14,
        figmaLineHeight: 40,
        showBorder: false,
        onSelected: (result) => context.read<UserWorkspaceBloc>().add(
              UserWorkspaceEvent.updateWorkspaceIcon(
                workspaceId: currentWorkspace.workspaceId,
                icon: result.emoji,
              ),
            ),
      );
    } else if (view case final currentView?) {
      titleIcon = ViewIconPicker(
        view: currentView,
        onViewChanged: onViewChanged,
        child: SizedBox.square(
          key: const ValueKey('folder-gallery-title-icon'),
          dimension: 48,
          child: Center(
            child: icon != null && icon.isNotEmpty
                ? RawEmojiIconWidget(
                    emoji: icon,
                    emojiSize: 42,
                    lineHeight: 1,
                  )
                : WorkspaceItemIcon.fromView(
                    view: currentView,
                    size: 40,
                    color: palette.accent,
                  ),
          ),
        ),
      );
    } else {
      titleIcon = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(
            children: [
              if (titleIcon != null) ...[
                titleIcon,
                const SizedBox(width: 14),
              ],
              Expanded(
                child: WorkspaceInlineEditableText(
                  key: const ValueKey('folder-gallery-title'),
                  text: title,
                  editingValue: rawTitle,
                  editing: editing,
                  onSubmitted: onSubmitted,
                  onCancelled: onCancelled,
                  onTap: onRename,
                  maxLines: 2,
                  style: titleStyle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 11),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < stats.length; index++) ...[
              if (index > 0)
                Container(
                  width: 3,
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: palette.textMuted.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                stats[index],
                style: TextStyle(
                  color: palette.textMuted,
                  fontFamily: 'Inter',
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.08,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _GalleryBreadcrumbs extends StatelessWidget {
  const _GalleryBreadcrumbs({
    required this.items,
    required this.onSelected,
  });

  final List<WorkspaceExplorerItem> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (items.length <= 1) {
      return const SizedBox.shrink();
    }
    final ancestors = items.sublist(0, items.length - 1);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < ancestors.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: FolderExplorerPalette.of(context)
                      .textMuted
                      .withValues(alpha: 0.52),
                ),
              ),
            _GalleryBreadcrumb(
              item: ancestors[index],
              current: false,
              onPressed: () => onSelected(ancestors[index].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _GalleryBreadcrumb extends StatefulWidget {
  const _GalleryBreadcrumb({
    required this.item,
    required this.current,
    required this.onPressed,
  });

  final WorkspaceExplorerItem item;
  final bool current;
  final VoidCallback onPressed;

  @override
  State<_GalleryBreadcrumb> createState() => _GalleryBreadcrumbState();
}

class _GalleryBreadcrumbState extends State<_GalleryBreadcrumb> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return MouseRegion(
      cursor:
          widget.current ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.current ? null : widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: widget.current
                  ? palette.textSecondary
                  : hovered
                      ? palette.textPrimary
                      : palette.textMuted,
              fontFamily: 'Inter',
              fontSize: 11.5,
              height: 1.2,
              fontWeight: widget.current ? FontWeight.w500 : FontWeight.w400,
            ),
            child: Text(
              widget.item.name.isEmpty
                  ? LocaleKeys.workspaceFolderExplorer_untitledFolder.tr()
                  : widget.item.name,
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryControl extends StatefulWidget {
  const _GalleryControl({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.label,
    this.primary = false,
    this.compact = false,
    this.foregroundColor,
  });

  final IconData icon;
  final String? label;
  final String semanticLabel;
  final VoidCallback onPressed;
  final bool primary;
  final bool compact;
  final Color? foregroundColor;

  @override
  State<_GalleryControl> createState() => _GalleryControlState();
}

class _GalleryControlState extends State<_GalleryControl> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final foreground = widget.primary
        ? PaperTheme.isEnabled(context)
            ? PaperTheme.onAccent
            : Theme.of(context).colorScheme.onPrimary
        : widget.foregroundColor ?? palette.textSecondary;
    final background = widget.primary
        ? hovered
            ? Color.alphaBlend(
                Colors.black.withValues(alpha: 0.08),
                palette.accent,
              )
            : palette.accent
        : hovered
            ? palette.hover.withValues(alpha: 0.78)
            : Colors.transparent;
    final horizontal = widget.label == null ? 0.0 : 15.0;

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() {
          hovered = false;
          pressed = false;
        }),
        child: GestureDetector(
          onTap: widget.onPressed,
          onTapDown: (_) => setState(() => pressed = true),
          onTapCancel: () => setState(() => pressed = false),
          onTapUp: (_) => setState(() => pressed = false),
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: pressed ? 0.97 : 1,
            duration: const Duration(milliseconds: 90),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              height: widget.compact ? 32 : 40,
              width: widget.label == null
                  ? widget.compact
                      ? 32
                      : 40
                  : null,
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(widget.primary ? 13 : 12),
                boxShadow: widget.primary && !pressed
                    ? [
                        BoxShadow(
                          color: palette.accent.withValues(alpha: 0.16),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                          spreadRadius: -6,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, size: 17, color: foreground),
                  if (widget.label != null) ...[
                    const SizedBox(width: 7),
                    Text(
                      widget.label!,
                      style: TextStyle(
                        color: foreground,
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.08,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
