import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pdfrx/pdfrx.dart';

const _galleryPreviewHeight = 260.0;

class FolderGalleryPreviewThumbnail extends StatelessWidget {
  const FolderGalleryPreviewThumbnail({
    super.key,
    required this.item,
    required this.view,
    required this.preview,
    required this.userProfile,
    this.height = _galleryPreviewHeight,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.compact = false,
    this.previewMode,
  });

  final WorkspaceExplorerItem item;
  final ViewPB view;
  final Future<FolderGalleryPreview> preview;
  final UserProfilePB? userProfile;
  final double height;
  final BorderRadius borderRadius;
  final bool compact;
  final ViewPreviewMode? previewMode;

  @override
  Widget build(BuildContext context) {
    final cover = view.cover;
    final mode = previewMode ?? view.previewMode;
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        height: height,
        child: mode == ViewPreviewMode.cover && cover != null
            ? ViewCoverImage(
                cover: cover,
                userProfile: userProfile,
                width: double.infinity,
                height: height,
              )
            : FutureBuilder<FolderGalleryPreview>(
                future: preview,
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  if (data == null) {
                    return const _GalleryMediaLoading();
                  }
                  final hasMediaPreview = data.hasHero ||
                      {
                        FolderGalleryPreviewKind.image,
                        FolderGalleryPreviewKind.pdf,
                        FolderGalleryPreviewKind.video,
                      }.contains(data.kind);
                  return hasMediaPreview
                      ? _GalleryMediaPreview(
                          preview: data,
                          userProfile: userProfile,
                        )
                      : _GalleryPreviewStage(
                          item: item,
                          preview: data,
                          userProfile: userProfile,
                          compact: compact,
                        );
                },
              ),
      ),
    );
  }
}

class FolderContentPreviewThumbnail extends StatefulWidget {
  const FolderContentPreviewThumbnail({
    super.key,
    required this.folder,
    required this.userProfile,
    this.repository = const WorkspaceItemService(),
  });

  final ViewPB folder;
  final UserProfilePB? userProfile;
  final WorkspaceItemRepository repository;

  @override
  State<FolderContentPreviewThumbnail> createState() =>
      _FolderContentPreviewThumbnailState();
}

class _FolderContentPreviewThumbnailState
    extends State<FolderContentPreviewThumbnail> {
  final previewCache = FolderGalleryPreviewCache();
  late Future<List<ViewPB>> children = _loadChildren();
  ViewListener? listener;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant FolderContentPreviewThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder.id != widget.folder.id) {
      listener?.stop();
      previewCache.clear();
      children = _loadChildren();
      _listen();
    }
  }

  @override
  void dispose() {
    listener?.stop();
    previewCache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ViewPB>>(
      future: children,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _GalleryUnavailablePreview();
        }
        final views = snapshot.data;
        if (views == null) {
          return const _GalleryMediaLoading();
        }
        if (views.isEmpty) {
          return FolderGalleryCollectionArtwork(
            item: WorkspaceExplorerItem.fromView(widget.folder),
          );
        }
        final visible = views.take(4).toList(growable: false);
        return Padding(
          padding: const EdgeInsets.all(9),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = visible.length == 1 ? 1 : 2;
              final rows = visible.length <= 2 ? 1 : 2;
              const gap = 5.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              final height = (constraints.maxHeight - gap * (rows - 1)) / rows;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final view in visible)
                    SizedBox(
                      width: width,
                      height: height,
                      child: FolderGalleryPreviewThumbnail(
                        item: WorkspaceExplorerItem.fromView(view),
                        view: view,
                        preview: previewCache.previewFor(
                          view: view,
                          item: WorkspaceExplorerItem.fromView(view),
                        ),
                        userProfile: widget.userProfile,
                        height: height,
                        compact: true,
                        borderRadius: BorderRadius.circular(9),
                        previewMode: ViewPreviewMode.content,
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<List<ViewPB>> _loadChildren() async {
    final result = await widget.repository.getChildren(widget.folder.id);
    return result.fold(
      (views) => views,
      (error) => throw StateError(error.msg),
    );
  }

  void _listen() {
    listener = ViewListener(viewId: widget.folder.id)
      ..start(
        onViewChildViewsUpdated: (_) {
          if (mounted) {
            previewCache.clear();
            setState(() => children = _loadChildren());
          }
        },
      );
  }
}

class FolderGallery extends StatefulWidget {
  const FolderGallery({
    super.key,
    required this.controller,
    required this.previewCache,
    required this.userProfile,
    required this.onOpen,
    required this.onNavigate,
    required this.onContextMenu,
    required this.onRequestDelete,
    required this.onRename,
    this.header,
    this.errorBanner,
  });

  final WorkspaceExplorerController controller;
  final FolderGalleryPreviewCache previewCache;
  final UserProfilePB? userProfile;
  final ValueChanged<ViewPB> onOpen;
  final ValueChanged<String> onNavigate;
  final void Function(WorkspaceExplorerItem item, Offset position)
      onContextMenu;
  final VoidCallback onRequestDelete;
  final ValueChanged<String> onRename;
  final Widget? header;
  final Widget? errorBanner;

  @override
  State<FolderGallery> createState() => _FolderGalleryState();
}

class _FolderGalleryState extends State<FolderGallery> {
  final FocusNode focusNode = FocusNode(debugLabel: 'folder-gallery');
  int crossAxisCount = 1;

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final entries = _visibleEntries(controller);
    final draft = controller.draft;
    final showDraft =
        draft != null && draft.parentId == controller.currentFolder.id;
    final itemCount = entries.length + (showDraft ? 1 : 0);

    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event, entries),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          focusNode.requestFocus();
          controller.selection.clear();
        },
        child: CustomScrollView(
          key: const ValueKey('folder-gallery-scroll-view'),
          cacheExtent: 900,
          slivers: [
            if (widget.header != null) SliverToBoxAdapter(child: widget.header),
            if (widget.errorBanner != null)
              SliverToBoxAdapter(child: widget.errorBanner),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final horizontal = KnowledgeGalleryLayout.horizontalPadding(
                  constraints.crossAxisExtent,
                );
                final contentWidth =
                    constraints.crossAxisExtent - horizontal * 2;
                crossAxisCount = _columnCount(contentWidth);
                if (itemCount == 0) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: _GalleryEmptyState(
                      message: controller.query.isEmpty
                          ? LocaleKeys.workspaceFolderExplorer_emptyFolder.tr()
                          : LocaleKeys.workspaceFolderExplorer_noMatchingItems
                              .tr(),
                    ),
                  );
                }
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    8,
                    horizontal,
                    84,
                  ),
                  sliver: SliverMasonryGrid(
                    gridDelegate:
                        SliverSimpleGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                    ),
                    mainAxisSpacing: KnowledgeGalleryLayout.cardSpacing,
                    crossAxisSpacing: KnowledgeGalleryLayout.cardSpacing,
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (showDraft && index == 0) {
                          return _FolderGalleryDraftCard(
                            key: ValueKey(
                              'gallery-draft-${draft.kind}-${draft.parentId}',
                            ),
                            draft: draft,
                            onCancel: controller.cancelEditing,
                            onSubmitted: controller.commitDraft,
                          );
                        }
                        final entryIndex = showDraft ? index - 1 : index;
                        final row = entries[entryIndex];
                        final view = controller.viewForId(row.item.id);
                        if (view == null) {
                          return const SizedBox.shrink();
                        }
                        final card = FolderGalleryCard(
                          key: ValueKey('gallery-card-${view.id}'),
                          item: row.item,
                          view: view,
                          preview: widget.previewCache.previewFor(
                            view: view,
                            item: row.item,
                          ),
                          userProfile: widget.userProfile,
                          selected: controller.selection.contains(view.id),
                          editing: controller.editingId == view.id,
                          searchPath: controller.query.isEmpty
                              ? null
                              : controller.relativePathFor(view.id),
                          onTap: () => _activate(row.item, entries),
                          onRename: () => widget.onRename(view.id),
                          onRenameSubmitted: controller.commitRename,
                          onRenameCancelled: controller.cancelEditing,
                          onMore: (position) {
                            _selectOnly(view.id);
                            widget.onContextMenu(row.item, position);
                          },
                          onContextMenu: (position) {
                            _selectOnly(view.id);
                            widget.onContextMenu(row.item, position);
                          },
                        );
                        return _GalleryDragTarget(
                          key: ValueKey('gallery-drag-${view.id}'),
                          enabled: controller.query.isEmpty,
                          target: view,
                          item: row.item,
                          onAccept: (dragged) {
                            if (row.item.isFolder) {
                              unawaited(
                                controller.moveItem(
                                  itemId: dragged.id,
                                  parentId: view.id,
                                ),
                              );
                            } else {
                              unawaited(
                                controller.moveItem(
                                  itemId: dragged.id,
                                  parentId: view.parentViewId,
                                  previousViewId: controller.previousSiblingId(
                                    view.id,
                                    excludingId: dragged.id,
                                  ),
                                ),
                              );
                            }
                          },
                          child: controller.query.isEmpty
                              ? Draggable<ViewPB>(
                                  data: view,
                                  feedback:
                                      _GalleryDragFeedback(item: row.item),
                                  childWhenDragging: Opacity(
                                    opacity: 0.32,
                                    child: card,
                                  ),
                                  child: card,
                                )
                              : card,
                        );
                      },
                      childCount: itemCount,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<WorkspaceExplorerRow> _visibleEntries(
    WorkspaceExplorerController controller,
  ) {
    final query = controller.query.toLowerCase();
    if (query.isEmpty) {
      return controller.rows.where((row) => row.depth == 0).toList();
    }
    return controller.rows
        .where((row) => row.item.name.toLowerCase().contains(query))
        .toList();
  }

  int _columnCount(double width) {
    if (!width.isFinite || width <= 0) {
      return 1;
    }
    return ((width + KnowledgeGalleryLayout.cardSpacing) /
            (KnowledgeGalleryLayout.minimumCardWidth +
                KnowledgeGalleryLayout.cardSpacing))
        .floor()
        .clamp(1, 5);
  }

  void _activate(
    WorkspaceExplorerItem item,
    List<WorkspaceExplorerRow> entries,
  ) {
    focusNode.requestFocus();
    final visibleIds =
        entries.map((entry) => entry.item.id).toList(growable: false);
    if (HardwareKeyboard.instance.isShiftPressed) {
      widget.controller.selection.selectRange(
        id: item.id,
        visibleIds: visibleIds,
      );
      return;
    } else if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      widget.controller.selection.toggle(item.id);
      return;
    }
    _open(item);
  }

  void _selectOnly(String id) {
    if (!widget.controller.selection.contains(id)) {
      widget.controller.selection.selectOnly(id);
    }
  }

  void _open(WorkspaceExplorerItem item) {
    if (item.isFolder) {
      widget.onNavigate(item.id);
      return;
    }
    final view = widget.controller.viewForId(item.id);
    if (view != null) {
      widget.onOpen(view);
    }
  }

  KeyEventResult _handleKeyEvent(
    KeyEvent event,
    List<WorkspaceExplorerRow> entries,
  ) {
    if (event is! KeyDownEvent || entries.isEmpty) {
      return KeyEventResult.ignored;
    }
    final controller = widget.controller;
    final key = event.logicalKey;
    final command = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final ids = entries.map((entry) => entry.item.id).toList(growable: false);

    if (controller.editingId != null || controller.draft != null) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.escape) {
      controller.cancelEditing();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _moveSelection(ids, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _moveSelection(ids, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(ids, crossAxisCount);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(ids, -crossAxisCount);
      return KeyEventResult.handled;
    }
    if (isWorkspaceRenameShortcut(Theme.of(context).platform, key)) {
      final selected = controller.selection.anchorId;
      if (selected != null) {
        widget.onRename(selected);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      final selected = controller.selection.anchorId;
      final item = selected == null ? null : controller.itemForId(selected);
      if (item != null) {
        _open(item);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      widget.onRequestDelete();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyA) {
      controller.selection.selectAll(ids);
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyC) {
      controller.copySelection();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyX) {
      controller.cutSelection();
      return KeyEventResult.handled;
    }
    if (command && key == LogicalKeyboardKey.keyV) {
      unawaited(controller.paste());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveSelection(List<String> ids, int delta) {
    final current = widget.controller.selection.anchorId;
    final currentIndex = current == null ? -1 : ids.indexOf(current);
    final nextIndex = (currentIndex + delta).clamp(0, ids.length - 1);
    widget.controller.selection.selectOnly(ids[nextIndex]);
  }
}

class FolderGalleryCard extends StatefulWidget {
  const FolderGalleryCard({
    super.key,
    required this.item,
    required this.view,
    required this.preview,
    required this.userProfile,
    required this.selected,
    required this.editing,
    required this.onTap,
    required this.onRename,
    required this.onRenameSubmitted,
    required this.onRenameCancelled,
    required this.onMore,
    required this.onContextMenu,
    this.searchPath,
  });

  final WorkspaceExplorerItem item;
  final ViewPB view;
  final Future<FolderGalleryPreview> preview;
  final UserProfilePB? userProfile;
  final bool selected;
  final bool editing;
  final String? searchPath;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final Future<bool> Function(String) onRenameSubmitted;
  final VoidCallback onRenameCancelled;
  final ValueChanged<Offset> onMore;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<FolderGalleryCard> createState() => _FolderGalleryCardState();
}

class _FolderGalleryCardState extends State<FolderGalleryCard> {
  bool hovered = false;
  bool appeared = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => appeared = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = widget.selected
        ? Color.alphaBlend(
            palette.accent.withValues(alpha: isPaper ? 0.06 : 0.045),
            palette.surface,
          )
        : hovered
            ? Color.alphaBlend(
                palette.accent.withValues(alpha: isDark ? 0.026 : 0.016),
                palette.surface,
              )
            : palette.surface;

    return AnimatedOpacity(
      opacity: appeared ? 1 : 0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: appeared ? 1 : 0.992,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => hovered = true),
          onExit: (_) => setState(() => hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, hovered ? -2.5 : 0, 0),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(
                    alpha: hovered
                        ? isDark
                            ? 0.28
                            : 0.13
                        : isDark
                            ? 0.20
                            : 0.075,
                  ),
                  blurRadius: hovered ? 48 : 38,
                  offset: Offset(0, hovered ? 19 : 15),
                  spreadRadius: hovered ? -16 : -15,
                ),
                BoxShadow(
                  color: palette.shadow.withValues(
                    alpha: hovered
                        ? isDark
                            ? 0.15
                            : 0.075
                        : isDark
                            ? 0.11
                            : 0.045,
                  ),
                  blurRadius: hovered ? 14 : 10,
                  offset: const Offset(0, 5),
                  spreadRadius: -5,
                ),
                if (widget.selected)
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.20),
                    blurRadius: 28,
                    spreadRadius: -5,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                children: [
                  if (isPaper)
                    const Positioned.fill(
                      child: IgnorePointer(child: _PaperTexture()),
                    ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onTap,
                    onSecondaryTapDown: (details) =>
                        widget.onContextMenu(details.globalPosition),
                    child: FutureBuilder<FolderGalleryPreview>(
                      future: widget.preview,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return _GalleryCardSkeleton(
                            item: widget.item,
                            editing: widget.editing,
                            onRename: widget.onRename,
                            onRenameSubmitted: widget.onRenameSubmitted,
                            onRenameCancelled: widget.onRenameCancelled,
                          );
                        }
                        return _GalleryCardContent(
                          item: widget.item,
                          view: widget.view,
                          preview: snapshot.data!,
                          userProfile: widget.userProfile,
                          editing: widget.editing,
                          searchPath: widget.searchPath,
                          onRename: widget.onRename,
                          onRenameSubmitted: widget.onRenameSubmitted,
                          onRenameCancelled: widget.onRenameCancelled,
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 14,
                    right: 14,
                    child: IgnorePointer(
                      ignoring: !hovered,
                      child: AnimatedOpacity(
                        opacity: hovered ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: _GalleryOverflowAction(
                          onMore: widget.onMore,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryCardContent extends StatelessWidget {
  const _GalleryCardContent({
    required this.item,
    required this.view,
    required this.preview,
    required this.userProfile,
    required this.editing,
    required this.onRename,
    required this.onRenameSubmitted,
    required this.onRenameCancelled,
    this.searchPath,
  });

  final WorkspaceExplorerItem item;
  final ViewPB view;
  final FolderGalleryPreview preview;
  final UserProfilePB? userProfile;
  final bool editing;
  final String? searchPath;
  final VoidCallback onRename;
  final Future<bool> Function(String) onRenameSubmitted;
  final VoidCallback onRenameCancelled;

  @override
  Widget build(BuildContext context) {
    final cover = view.cover;
    final previewMode = view.previewMode;
    final hasMediaPreview = preview.hasHero ||
        {
          FolderGalleryPreviewKind.image,
          FolderGalleryPreviewKind.pdf,
          FolderGalleryPreviewKind.video,
        }.contains(preview.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          key: const ValueKey('folder-gallery-preview-stage'),
          height: _galleryPreviewHeight,
          child: previewMode == ViewPreviewMode.cover && cover != null
              ? ViewCoverImage(
                  cover: cover,
                  userProfile: userProfile,
                  width: double.infinity,
                  height: _galleryPreviewHeight,
                )
              : previewMode == ViewPreviewMode.content && item.isFolder
                  ? FolderContentPreviewThumbnail(
                      folder: view,
                      userProfile: userProfile,
                    )
                  : hasMediaPreview
                      ? _GalleryMediaPreview(
                          preview: preview,
                          userProfile: userProfile,
                        )
                      : _GalleryPreviewStage(
                          item: item,
                          preview: preview,
                          userProfile: userProfile,
                        ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 19, 21, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GalleryCardTitle(
                item: item,
                view: view,
                editing: editing,
                searchPath: searchPath,
                onRename: onRename,
                onSubmitted: onRenameSubmitted,
                onCancelled: onRenameCancelled,
              ),
              const SizedBox(height: 15),
              _GalleryMetadata(
                item: item,
                view: view,
                preview: preview,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GalleryPreviewStage extends StatelessWidget {
  const _GalleryPreviewStage({
    required this.item,
    required this.preview,
    required this.userProfile,
    this.compact = false,
  });

  final WorkspaceExplorerItem item;
  final FolderGalleryPreview preview;
  final UserProfilePB? userProfile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final theme = Theme.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final base = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      palette.floatingSurface,
      isPaper: isPaper,
    );
    final start = Color.alphaBlend(
      palette.accent.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.035 : 0.018,
      ),
      base,
    );
    final padding = compact
        ? switch (preview.kind) {
            FolderGalleryPreviewKind.folder => EdgeInsets.zero,
            _ => const EdgeInsets.fromLTRB(13, 14, 13, 12),
          }
        : switch (preview.kind) {
            FolderGalleryPreviewKind.folder => EdgeInsets.zero,
            FolderGalleryPreviewKind.code =>
              const EdgeInsets.fromLTRB(22, 24, 22, 22),
            FolderGalleryPreviewKind.database =>
              const EdgeInsets.fromLTRB(24, 27, 24, 24),
            FolderGalleryPreviewKind.file =>
              const EdgeInsets.fromLTRB(24, 24, 24, 22),
            _ => const EdgeInsets.fromLTRB(27, 30, 27, 24),
          };
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [start, base],
        ),
      ),
      child: Padding(
        padding: padding,
        child: _GalleryPreviewBody(
          item: item,
          preview: preview,
          userProfile: userProfile,
        ),
      ),
    );
  }
}

class _GalleryCardTitle extends StatelessWidget {
  const _GalleryCardTitle({
    required this.item,
    required this.editing,
    required this.onRename,
    required this.onSubmitted,
    required this.onCancelled,
    this.searchPath,
    this.view,
  });

  final WorkspaceExplorerItem item;
  final ViewPB? view;
  final bool editing;
  final String? searchPath;
  final VoidCallback onRename;
  final Future<bool> Function(String) onSubmitted;
  final VoidCallback onCancelled;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final titleStyle = TextStyle(
      color: palette.textPrimary,
      fontFamily: 'Inter',
      fontSize: 17,
      height: 1.24,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.38,
    );
    final title = item.name.isEmpty
        ? LocaleKeys.workspaceFolderExplorer_untitled.tr()
        : item.name;
    final icon = view?.icon.toEmojiIconData();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null && icon.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: RawEmojiIconWidget(
                  emoji: icon,
                  emojiSize: 18,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: WorkspaceInlineEditableText(
                text: title,
                editingValue: item.name,
                editing: editing,
                onSubmitted: onSubmitted,
                onCancelled: onCancelled,
                onDoubleTap: onRename,
                maxLines: 2,
                selectFileStem: item.isFile,
                style: titleStyle,
              ),
            ),
          ],
        ),
        if (searchPath != null && searchPath!.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            searchPath!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textMuted,
              fontFamily: 'Inter',
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _GalleryPreviewBody extends StatelessWidget {
  const _GalleryPreviewBody({
    required this.item,
    required this.preview,
    required this.userProfile,
  });

  final WorkspaceExplorerItem item;
  final FolderGalleryPreview preview;
  final UserProfilePB? userProfile;

  @override
  Widget build(BuildContext context) {
    if (preview.unavailable) {
      return const _GalleryUnavailablePreview();
    }
    return switch (preview.kind) {
      FolderGalleryPreviewKind.folder =>
        FolderGalleryCollectionArtwork(item: item),
      FolderGalleryPreviewKind.database => _GalleryDatabasePreview(
          snapshot: preview.database,
          unavailable: preview.unavailable,
        ),
      FolderGalleryPreviewKind.code => _GalleryCodePreview(preview: preview),
      FolderGalleryPreviewKind.file => _GalleryGenericFilePreview(
          item: item,
          preview: preview,
        ),
      FolderGalleryPreviewKind.document => preview.blocks.isEmpty
          ? _GalleryBlankDocumentPreview(item: item)
          : _GalleryRichDocumentPreview(blocks: preview.blocks),
      FolderGalleryPreviewKind.image ||
      FolderGalleryPreviewKind.pdf ||
      FolderGalleryPreviewKind.video =>
        _GalleryMediaPreview(
          preview: preview,
          userProfile: userProfile,
        ),
    };
  }
}

class _GalleryRichDocumentPreview extends StatelessWidget {
  const _GalleryRichDocumentPreview({required this.blocks});

  final List<FolderGalleryPreviewBlock> blocks;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white,
          Colors.white,
          Colors.white,
          Colors.transparent,
        ],
        stops: [0, 0.72, 0.88, 1],
      ).createShader(bounds),
      child: ClipRect(
        child: ListView.builder(
          primary: false,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: blocks.length,
          itemBuilder: (context, index) => _GalleryDocumentBlock(
            block: blocks[index],
            listIndex: index + 1,
          ),
        ),
      ),
    );
  }
}

class _GalleryDocumentBlock extends StatelessWidget {
  const _GalleryDocumentBlock({
    required this.block,
    required this.listIndex,
  });

  final FolderGalleryPreviewBlock block;
  final int listIndex;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    if (block.kind == FolderGalleryPreviewBlockKind.code) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: _MiniCodeBlock(
          code: block.plainText,
          language: block.language ?? 'auto',
        ),
      );
    }
    if (block.kind == FolderGalleryPreviewBlockKind.math) {
      return Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: EditorSurfaceStyle.calloutBackgroundFor(
            Theme.of(context).brightness,
            palette.hover.withValues(alpha: 0.52),
            isPaper: PaperTheme.isEnabled(context),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'ƒ  ${block.plainText}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.textSecondary,
            fontFamily: 'serif',
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final heading = block.kind == FolderGalleryPreviewBlockKind.heading;
    final headingSize = switch (block.level.clamp(1, 4)) {
      1 => 17.2,
      2 => 15.2,
      3 => 13.6,
      _ => 12.4,
    };
    final prefix = switch (block.kind) {
      FolderGalleryPreviewBlockKind.bulletedList => '•',
      FolderGalleryPreviewBlockKind.numberedList => '$listIndex.',
      FolderGalleryPreviewBlockKind.quote => '│',
      _ => null,
    };
    final body = Text.rich(
      TextSpan(
        children: block.runs
            .map((run) => _textSpan(context, run, heading))
            .toList(growable: false),
      ),
      maxLines: heading ? 2 : 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: palette.textPrimary,
        fontFamily: 'Inter',
        fontSize: heading ? headingSize : 11.6,
        height: heading ? 1.22 : 1.48,
        fontWeight: heading ? FontWeight.w600 : FontWeight.w400,
        letterSpacing: heading ? -0.22 : -0.02,
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: heading ? 10 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (block.kind == FolderGalleryPreviewBlockKind.todo) ...[
            Container(
              width: 13,
              height: 13,
              margin: const EdgeInsets.only(top: 1.5, right: 7),
              decoration: BoxDecoration(
                color: block.checked ? palette.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(3.5),
                border: Border.all(
                  color: block.checked ? palette.accent : palette.textMuted,
                  width: 1.1,
                ),
              ),
              child: block.checked
                  ? Icon(
                      Icons.check_rounded,
                      size: 9,
                      color: Theme.of(context).colorScheme.onPrimary,
                    )
                  : null,
            ),
          ] else if (prefix != null) ...[
            SizedBox(
              width: 17,
              child: Text(
                prefix,
                style: TextStyle(
                  color: block.kind == FolderGalleryPreviewBlockKind.quote
                      ? palette.accent
                      : palette.textSecondary,
                  fontSize: 11.2,
                  height: 1.42,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          Expanded(child: body),
        ],
      ),
    );
  }

  TextSpan _textSpan(
    BuildContext context,
    FolderGalleryTextRun run,
    bool heading,
  ) {
    final palette = FolderExplorerPalette.of(context);
    return TextSpan(
      text: run.text,
      style: TextStyle(
        color: run.inlineCode
            ? EditorSurfaceStyle.inlineCodeForeground(context)
            : palette.textPrimary,
        fontFamily: run.inlineCode ? 'RobotoMono' : 'Inter',
        fontWeight: run.bold || heading ? FontWeight.w600 : FontWeight.w400,
        fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
        backgroundColor: run.inlineCode
            ? EditorSurfaceStyle.inlineCodeBackground(context)
            : null,
      ),
    );
  }
}

class _GalleryCodePreview extends StatelessWidget {
  const _GalleryCodePreview({required this.preview});

  final FolderGalleryPreview preview;

  @override
  Widget build(BuildContext context) {
    final code = preview.blocks
        .map((block) => block.plainText)
        .where((line) => line.trim().isNotEmpty)
        .join('\n');
    return _MiniCodeBlock(
      code: code,
      language: preview.language ?? 'auto',
      expanded: true,
    );
  }
}

class _MiniCodeBlock extends StatelessWidget {
  const _MiniCodeBlock({
    required this.code,
    required this.language,
    this.expanded = false,
  });

  final String code;
  final String language;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final theme = Theme.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final background = EditorSurfaceStyle.codeBlockBackgroundFor(
      theme.brightness,
      theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
      isPaper: isPaper,
    );
    return Container(
      height: expanded ? double.infinity : 88,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: EditorSurfaceStyle.codeBlockHeaderBackgroundFor(
                theme.brightness,
                palette.hover.withValues(alpha: 0.44),
                isPaper: isPaper,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Text(
              language.isEmpty ? 'CODE' : language.toUpperCase(),
              style: TextStyle(
                color: palette.textMuted,
                fontFamily: 'Inter',
                fontSize: 8.8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.7,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: ClipRect(
                child: RichText(
                  maxLines: expanded ? 11 : 4,
                  overflow: TextOverflow.ellipsis,
                  text: buildSyntaxHighlightedTextSpan(
                    code: code,
                    language: language,
                    brightness: theme.brightness,
                    isPaper: isPaper,
                    style: const TextStyle(
                      fontFamily: 'RobotoMono',
                      fontSize: 9.7,
                      height: 1.42,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryMediaPreview extends StatelessWidget {
  const _GalleryMediaPreview({
    required this.preview,
    required this.userProfile,
  });

  final FolderGalleryPreview preview;
  final UserProfilePB? userProfile;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return ColoredBox(
      color: palette.hover.withValues(alpha: 0.26),
      child: switch (preview.kind) {
        FolderGalleryPreviewKind.image => _GalleryImageThumbnail(
            url: preview.heroUrl,
            userProfile: userProfile,
          ),
        FolderGalleryPreviewKind.pdf => _GalleryPdfThumbnail(
            url: preview.heroUrl,
            userProfile: userProfile,
          ),
        FolderGalleryPreviewKind.video => _GalleryVideoThumbnail(
            url: preview.heroUrl,
          ),
        FolderGalleryPreviewKind.document when preview.hasHero =>
          _GalleryImageThumbnail(
            url: preview.heroUrl,
            userProfile: userProfile,
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _GalleryImageThumbnail extends StatelessWidget {
  const _GalleryImageThumbnail({
    required this.url,
    required this.userProfile,
  });

  final String? url;
  final UserProfilePB? userProfile;

  @override
  Widget build(BuildContext context) {
    final source = url;
    if (source == null || source.isEmpty) {
      return const _GalleryMediaFallback(icon: Icons.image_outlined);
    }
    if (_isNetworkUrl(source)) {
      return FlowyNetworkImage(
        url: source,
        width: double.infinity,
        height: double.infinity,
        userProfilePB: userProfile,
        progressIndicatorBuilder: (_, __, ___) => const _GalleryMediaLoading(),
        errorWidgetBuilder: (_, __, ___) =>
            const _GalleryMediaFallback(icon: Icons.broken_image_outlined),
      );
    }
    return Image.file(
      File(source),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const _GalleryMediaFallback(icon: Icons.broken_image_outlined),
    );
  }
}

class _GalleryPdfThumbnail extends StatelessWidget {
  const _GalleryPdfThumbnail({
    required this.url,
    required this.userProfile,
  });

  final String? url;
  final UserProfilePB? userProfile;

  @override
  Widget build(BuildContext context) {
    final source = url;
    if (source == null || source.isEmpty) {
      return const _GalleryMediaFallback(icon: Icons.picture_as_pdf_outlined);
    }
    Widget builder(BuildContext context, PdfDocument? document) {
      if (document == null || document.pages.isEmpty) {
        return const _GalleryMediaLoading();
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 13, 18, 0),
        child: PdfPageView(
          document: document,
          pageNumber: 1,
          maximumDpi: 110,
          decorationBuilder: (context, pageSize, page, pageImage) {
            final palette = FolderExplorerPalette.of(context);
            return Center(
              child: AspectRatio(
                aspectRatio: page.width / page.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: palette.shadow.withValues(alpha: 0.16),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: pageImage ??
                        ColoredBox(
                          color: palette.surface,
                          child: const SizedBox.expand(),
                        ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    if (_isNetworkUrl(source)) {
      final token = userProfile?.authToken;
      return PdfDocumentViewBuilder.uri(
        Uri.parse(source),
        headers: token == null ? null : {'Authorization': 'Bearer $token'},
        builder: builder,
      );
    }
    if (!File(source).existsSync()) {
      return const _GalleryMediaFallback(icon: Icons.picture_as_pdf_outlined);
    }
    return PdfDocumentViewBuilder.file(source, builder: builder);
  }
}

class _GalleryVideoThumbnail extends StatefulWidget {
  const _GalleryVideoThumbnail({required this.url});

  final String? url;

  @override
  State<_GalleryVideoThumbnail> createState() => _GalleryVideoThumbnailState();
}

class _GalleryVideoThumbnailState extends State<_GalleryVideoThumbnail> {
  Player? player;
  VideoController? videoController;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant _GalleryVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      unawaited(_disposePlayer());
      _initialize();
    }
  }

  void _initialize() {
    final source = widget.url;
    if (source == null || source.isEmpty) {
      return;
    }
    final nextPlayer = Player();
    player = nextPlayer;
    videoController = VideoController(nextPlayer);
    unawaited(nextPlayer.open(Media(source), play: false));
  }

  Future<void> _disposePlayer() async {
    final previous = player;
    player = null;
    videoController = null;
    await previous?.dispose();
  }

  @override
  void dispose() {
    unawaited(_disposePlayer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = this.player;
    final controller = videoController;
    if (player == null || controller == null) {
      return const _GalleryMediaFallback(icon: Icons.movie_outlined);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: Colors.black,
          child: Video(
            controller: controller,
            controls: NoVideoControls,
            fit: BoxFit.cover,
          ),
        ),
        const Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x73000000),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(9),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 25,
                color: Colors.white,
              ),
            ),
          ),
        ),
        Positioned(
          left: 9,
          right: 9,
          bottom: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StreamBuilder<Duration>(
                stream: player.stream.duration,
                initialData: player.state.duration,
                builder: (context, snapshot) => _MediaBadge(
                  text: _formatDuration(snapshot.data ?? Duration.zero),
                ),
              ),
              StreamBuilder<VideoParams>(
                stream: player.stream.videoParams,
                initialData: player.state.videoParams,
                builder: (context, snapshot) {
                  final params = snapshot.data;
                  final width = params?.w;
                  final height = params?.h;
                  return width == null || height == null
                      ? const SizedBox.shrink()
                      : _MediaBadge(text: '$width×$height');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:'
            '${seconds.toString().padLeft(2, '0')}'
        : '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _MediaBadge extends StatelessWidget {
  const _MediaBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class FolderGalleryCollectionArtwork extends StatelessWidget {
  const FolderGalleryCollectionArtwork({super.key, required this.item});

  final WorkspaceExplorerItem item;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _CollectionArtworkPainter(
            seed: _stableHash(item.id),
            accent: palette.accent,
            surface: palette.floatingSurface,
            background: palette.surface,
            line: palette.textMuted,
            shadow: palette.shadow,
            isDark: theme.brightness == Brightness.dark,
            isPaper: PaperTheme.isEnabled(context),
          ),
        ),
        Positioned(
          left: 22,
          bottom: 18,
          child: Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.74),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                LocaleKeys.workspaceFolderExplorer_collection
                    .tr()
                    .toUpperCase(),
                style: TextStyle(
                  color: palette.textSecondary.withValues(alpha: 0.76),
                  fontFamily: 'Inter',
                  fontSize: 9.5,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CollectionArtworkPainter extends CustomPainter {
  const _CollectionArtworkPainter({
    required this.seed,
    required this.accent,
    required this.surface,
    required this.background,
    required this.line,
    required this.shadow,
    required this.isDark,
    required this.isPaper,
  });

  final int seed;
  final Color accent;
  final Color surface;
  final Color background;
  final Color line;
  final Color shadow;
  final bool isDark;
  final bool isPaper;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            accent.withValues(alpha: isDark ? 0.18 : 0.10),
            background,
          ),
          Color.alphaBlend(
            accent.withValues(alpha: isPaper ? 0.035 : 0.018),
            surface,
          ),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, backgroundPaint);

    final glowPaint = Paint()
      ..color = accent.withValues(alpha: isDark ? 0.12 : 0.07)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34);
    final shift = (seed % 17) / 17;
    canvas
      ..drawCircle(
        Offset(size.width * (0.18 + shift * 0.08), size.height * 0.22),
        size.shortestSide * 0.31,
        glowPaint,
      )
      ..drawCircle(
        Offset(size.width * 0.83, size.height * (0.47 + shift * 0.08)),
        size.shortestSide * 0.25,
        glowPaint..color = accent.withValues(alpha: isDark ? 0.08 : 0.045),
      );

    final direction = seed.isEven ? 1.0 : -1.0;
    _drawPage(
      canvas,
      Rect.fromLTWH(
        size.width * 0.12,
        size.height * 0.20,
        size.width * 0.40,
        size.height * 0.57,
      ),
      -0.09 * direction,
      0.78,
      0,
    );
    _drawPage(
      canvas,
      Rect.fromLTWH(
        size.width * 0.49,
        size.height * 0.13,
        size.width * 0.39,
        size.height * 0.60,
      ),
      0.075 * direction,
      0.86,
      1,
    );
    _drawPage(
      canvas,
      Rect.fromLTWH(
        size.width * 0.29,
        size.height * 0.22,
        size.width * 0.45,
        size.height * 0.61,
      ),
      -0.012 * direction,
      1,
      2,
    );
  }

  void _drawPage(
    Canvas canvas,
    Rect rect,
    double angle,
    double opacity,
    int variant,
  ) {
    canvas
      ..save()
      ..translate(rect.center.dx, rect.center.dy)
      ..rotate(angle)
      ..translate(-rect.center.dx, -rect.center.dy);
    final page = RRect.fromRectAndRadius(rect, const Radius.circular(13));
    canvas.drawShadow(
      Path()..addRRect(page),
      shadow.withValues(alpha: isDark ? 0.30 : 0.16),
      16,
      false,
    );
    canvas.drawRRect(
      page,
      Paint()..color = surface.withValues(alpha: opacity),
    );

    final left = rect.left + rect.width * 0.13;
    final right = rect.right - rect.width * 0.13;
    final top = rect.top + rect.height * 0.14;
    final titlePaint = Paint()
      ..color = accent.withValues(alpha: 0.28 * opacity)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.2;
    canvas.drawLine(
      Offset(left, top),
      Offset(left + rect.width * (variant == 1 ? 0.44 : 0.56), top),
      titlePaint,
    );

    final linePaint = Paint()
      ..color = line.withValues(alpha: 0.16 * opacity)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;
    for (var index = 0; index < 6; index++) {
      final y = top + 22 + index * 15;
      final widthFactor = switch ((index + variant) % 4) {
        0 => 1.0,
        1 => 0.82,
        2 => 0.91,
        _ => 0.64,
      };
      canvas.drawLine(
        Offset(left, y),
        Offset(left + (right - left) * widthFactor, y),
        linePaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CollectionArtworkPainter oldDelegate) =>
      seed != oldDelegate.seed ||
      accent != oldDelegate.accent ||
      surface != oldDelegate.surface ||
      background != oldDelegate.background ||
      line != oldDelegate.line ||
      shadow != oldDelegate.shadow ||
      isDark != oldDelegate.isDark ||
      isPaper != oldDelegate.isPaper;
}

class _GalleryDatabasePreview extends StatelessWidget {
  const _GalleryDatabasePreview({
    required this.snapshot,
    required this.unavailable,
  });

  final FolderGalleryDatabaseSnapshot? snapshot;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPaper = PaperTheme.isEnabled(context);
    final database = snapshot;
    if (database == null || database.columns.isEmpty || database.rows.isEmpty) {
      return _GalleryEmptyDatabasePreview(unavailable: unavailable);
    }
    final baseSurface = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      palette.floatingSurface,
      isPaper: isPaper,
    );
    final tableSurface = Color.alphaBlend(
      palette.textPrimary.withValues(alpha: isDark ? 0.035 : 0.012),
      baseSurface,
    );
    final headerSurface = Color.alphaBlend(
      palette.accent.withValues(
        alpha: isDark
            ? 0.13
            : isPaper
                ? 0.075
                : 0.06,
      ),
      tableSurface,
    );
    final stripeSurface = Color.alphaBlend(
      palette.textPrimary.withValues(alpha: isDark ? 0.045 : 0.022),
      tableSurface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  palette.accent.withValues(alpha: isDark ? 0.16 : 0.09),
                  baseSurface,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.table_rows_rounded,
                size: 14,
                color: palette.accent.withValues(alpha: isDark ? 0.92 : 0.78),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${database.totalRowCount}',
              style: TextStyle(
                color: palette.textSecondary,
                fontFamily: 'Inter',
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Expanded(
          child: DecoratedBox(
            key: const ValueKey('folder-gallery-database-grid'),
            decoration: BoxDecoration(
              color: tableSurface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(
                    alpha: isDark ? 0.22 : 0.07,
                  ),
                  blurRadius: 20,
                  offset: const Offset(0, 9),
                  spreadRadius: -9,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Column(
                children: [
                  _GalleryDatabaseRow(
                    values: database.columns,
                    header: true,
                    backgroundColor: headerSurface,
                  ),
                  for (var index = 0; index < database.rows.length; index++)
                    Expanded(
                      child: _GalleryDatabaseRow(
                        values: database.rows[index],
                        backgroundColor:
                            index.isOdd ? stripeSurface : Colors.transparent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GalleryDatabaseRow extends StatelessWidget {
  const _GalleryDatabaseRow({
    required this.values,
    this.header = false,
    this.backgroundColor = Colors.transparent,
  });

  final List<String> values;
  final bool header;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      key: header ? const ValueKey('folder-gallery-database-header-row') : null,
      decoration: BoxDecoration(color: backgroundColor),
      child: SizedBox(
        height: header ? 31 : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            children: [
              for (var index = 0; index < values.length; index++) ...[
                if (index > 0) const SizedBox(width: 10),
                Expanded(
                  flex: index == 0 ? 5 : 4,
                  child: Text(
                    values[index].isEmpty ? '-' : values[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: header
                          ? palette.textPrimary.withValues(
                              alpha: isDark ? 0.88 : 0.72,
                            )
                          : values[index].isEmpty
                              ? palette.textMuted.withValues(alpha: 0.48)
                              : palette.textPrimary.withValues(
                                  alpha: isDark ? 0.92 : 0.84,
                                ),
                      fontFamily: 'Inter',
                      fontSize: header ? 10 : 10.5,
                      height: 1.2,
                      fontWeight: header ? FontWeight.w600 : null,
                      letterSpacing: header ? 0.08 : -0.06,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryEmptyDatabasePreview extends StatelessWidget {
  const _GalleryEmptyDatabasePreview({required this.unavailable});

  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final theme = Theme.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final surface = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      palette.floatingSurface,
      isPaper: isPaper,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            key: const ValueKey('folder-gallery-empty-table-artwork'),
            painter: _EmptyTableArtworkPainter(
              accent: palette.accent,
              surface: surface,
              line: palette.textPrimary,
              shadow: palette.shadow,
              isDark: theme.brightness == Brightness.dark,
              isPaper: isPaper,
            ),
          ),
        ),
        if (unavailable)
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  palette.textMuted.withValues(alpha: 0.08),
                  surface,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.cloud_off_rounded,
                size: 14,
                color: palette.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyTableArtworkPainter extends CustomPainter {
  const _EmptyTableArtworkPainter({
    required this.accent,
    required this.surface,
    required this.line,
    required this.shadow,
    required this.isDark,
    required this.isPaper,
  });

  final Color accent;
  final Color surface;
  final Color line;
  final Color shadow;
  final bool isDark;
  final bool isPaper;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.3, size.height * 0.48),
        width: size.width * 0.72,
        height: size.height * 0.68,
      ),
      Paint()
        ..color = accent.withValues(
          alpha: isDark
              ? 0.085
              : isPaper
                  ? 0.055
                  : 0.042,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    final tableRect = Rect.fromLTWH(
      size.width * 0.07,
      size.height * 0.12,
      size.width * 0.86,
      size.height * 0.74,
    );
    final backRect = tableRect.translate(7, 8);
    final back = RRect.fromRectAndRadius(
      backRect,
      const Radius.circular(14),
    );
    canvas.drawRRect(
      back,
      Paint()
        ..color = Color.alphaBlend(
          accent.withValues(alpha: isDark ? 0.12 : 0.065),
          surface,
        ),
    );

    canvas
      ..save()
      ..translate(tableRect.center.dx, tableRect.center.dy)
      ..rotate(-0.018)
      ..translate(-tableRect.center.dx, -tableRect.center.dy);

    final table = RRect.fromRectAndRadius(
      tableRect,
      const Radius.circular(14),
    );
    canvas.drawShadow(
      Path()..addRRect(table),
      shadow.withValues(alpha: isDark ? 0.34 : 0.14),
      20,
      false,
    );
    canvas.drawRRect(table, Paint()..color = surface);

    final headerHeight = tableRect.height * 0.22;
    final header = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        tableRect.left,
        tableRect.top,
        tableRect.width,
        headerHeight,
      ),
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
    );
    canvas.drawRRect(
      header,
      Paint()
        ..color = Color.alphaBlend(
          accent.withValues(alpha: isDark ? 0.16 : 0.09),
          surface,
        ),
    );

    final columnStops = [0.0, 0.48, 0.76, 1.0];
    final separatorPaint = Paint()
      ..color = line.withValues(alpha: isDark ? 0.09 : 0.055)
      ..strokeWidth = 1;
    for (final stop in columnStops.skip(1).take(2)) {
      final x = tableRect.left + tableRect.width * stop;
      canvas.drawLine(
        Offset(x, tableRect.top + 8),
        Offset(x, tableRect.bottom - 8),
        separatorPaint,
      );
    }

    const rowCount = 4;
    final rowHeight = (tableRect.height - headerHeight) / rowCount;
    for (var row = 0; row < rowCount; row++) {
      final top = tableRect.top + headerHeight + row * rowHeight;
      if (row.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(tableRect.left, top, tableRect.width, rowHeight),
          Paint()..color = line.withValues(alpha: isDark ? 0.035 : 0.018),
        );
      }
      if (row > 0) {
        canvas.drawLine(
          Offset(tableRect.left + 10, top),
          Offset(tableRect.right - 10, top),
          separatorPaint,
        );
      }
    }

    for (var column = 0; column < 3; column++) {
      final left = tableRect.left + tableRect.width * columnStops[column] + 11;
      final width =
          tableRect.width * (columnStops[column + 1] - columnStops[column]) -
              22;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left,
            tableRect.top + headerHeight * 0.42,
            width * (column == 0 ? 0.68 : 0.54),
            4,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = line.withValues(alpha: isDark ? 0.42 : 0.26),
      );
    }

    for (var row = 0; row < rowCount; row++) {
      final centerY = tableRect.top + headerHeight + rowHeight * (row + 0.5);
      final firstWidth = tableRect.width * (row.isEven ? 0.25 : 0.31);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            tableRect.left + 11,
            centerY - 2,
            firstWidth,
            4,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = line.withValues(alpha: isDark ? 0.24 : 0.14),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            tableRect.left + tableRect.width * 0.48 + 11,
            centerY - 2,
            tableRect.width * (row.isEven ? 0.12 : 0.16),
            4,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = line.withValues(alpha: isDark ? 0.18 : 0.1),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            tableRect.left + tableRect.width * 0.76 + 11,
            centerY - 6,
            tableRect.width * 0.12,
            12,
          ),
          const Radius.circular(6),
        ),
        Paint()
          ..color = accent.withValues(
            alpha: isDark ? 0.22 + row * 0.018 : 0.12 + row * 0.012,
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmptyTableArtworkPainter oldDelegate) =>
      accent != oldDelegate.accent ||
      surface != oldDelegate.surface ||
      line != oldDelegate.line ||
      shadow != oldDelegate.shadow ||
      isDark != oldDelegate.isDark ||
      isPaper != oldDelegate.isPaper;
}

class _GalleryGenericFilePreview extends StatelessWidget {
  const _GalleryGenericFilePreview({
    required this.item,
    required this.preview,
  });

  final WorkspaceExplorerItem item;
  final FolderGalleryPreview preview;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 126,
          height: 158,
          padding: const EdgeInsets.fromLTRB(17, 20, 17, 16),
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 11),
                spreadRadius: -8,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.fileTypeLabel,
                style: TextStyle(
                  color: palette.accent.withValues(alpha: 0.84),
                  fontFamily: 'Inter',
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.15,
                ),
              ),
              const Spacer(),
              for (final width in [0.92, 0.74, 0.86, 0.55]) ...[
                FractionallySizedBox(
                  widthFactor: width,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.textMuted.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        Positioned(
          top: 29,
          right: 54,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                item.name.isEmpty ? '?' : item.name.characters.first,
                style: TextStyle(
                  color: palette.accent,
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GalleryBlankDocumentPreview extends StatelessWidget {
  const _GalleryBlankDocumentPreview({required this.item});

  final WorkspaceExplorerItem item;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 74,
            height: 7,
            decoration: BoxDecoration(
              color: palette.textPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 15),
          for (final width in [0.92, 0.78, 0.86, 0.56, 0.72, 0.43]) ...[
            FractionallySizedBox(
              widthFactor: width,
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: palette.textMuted.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

class _GalleryMetadata extends StatelessWidget {
  const _GalleryMetadata({
    required this.item,
    required this.view,
    required this.preview,
  });

  final WorkspaceExplorerItem item;
  final ViewPB view;
  final FolderGalleryPreview preview;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final metadata = <String>[
      if (item.lastEdited case final modified?)
        DateFormat.MMMd().format(modified),
      if (preview.readingMinutes > 0)
        LocaleKeys.workspaceFolderExplorer_minuteRead.tr(
          args: [preview.readingMinutes.toString()],
        ),
      if (preview.wordCount > 0)
        LocaleKeys.workspaceFolderExplorer_wordCountShort.tr(
          args: [NumberFormat.compact().format(preview.wordCount)],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview.tags.isNotEmpty) ...[
          Text(
            preview.tags.take(3).map((tag) => '#$tag').join('   '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.accent.withValues(alpha: 0.72),
              fontFamily: 'Inter',
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.04,
            ),
          ),
          const SizedBox(height: 11),
        ],
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.58),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              preview.fileTypeLabel,
              style: TextStyle(
                color: palette.textMuted,
                fontFamily: 'Inter',
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.72,
              ),
            ),
            if (metadata.isNotEmpty) ...[
              Container(
                width: 3,
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: palette.textMuted.withValues(alpha: 0.40),
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  metadata.join('   '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontFamily: 'Inter',
                    fontSize: 10,
                    height: 1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ] else
              const Spacer(),
            if (view.isPinned)
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Tooltip(
                  message: LocaleKeys.workspaceFolderExplorer_pinned.tr(),
                  child: Icon(
                    Icons.push_pin_rounded,
                    size: 11,
                    color: palette.accent.withValues(alpha: 0.74),
                  ),
                ),
              ),
            if (view.isFavorite)
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Icon(
                  Icons.star_rounded,
                  size: 12,
                  color: palette.accent.withValues(alpha: 0.76),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _GalleryOverflowAction extends StatefulWidget {
  const _GalleryOverflowAction({required this.onMore});

  final ValueChanged<Offset> onMore;

  @override
  State<_GalleryOverflowAction> createState() => _GalleryOverflowActionState();
}

class _GalleryOverflowActionState extends State<_GalleryOverflowAction> {
  bool hovered = false;
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Builder(
      builder: (buttonContext) => Semantics(
        button: true,
        label: LocaleKeys.workspaceFolderExplorer_more.tr(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => hovered = true),
          onExit: (_) => setState(() {
            hovered = false;
            pressed = false;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => pressed = true),
            onTapCancel: () => setState(() => pressed = false),
            onTapUp: (_) => setState(() => pressed = false),
            onTap: () {
              final box = buttonContext.findRenderObject() as RenderBox;
              widget.onMore(
                box.localToGlobal(Offset(box.size.width, box.size.height + 5)),
              );
            },
            child: AnimatedScale(
              scale: pressed ? 0.94 : 1,
              duration: const Duration(milliseconds: 90),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: hovered
                          ? palette.floatingSurface.withValues(alpha: 0.96)
                          : palette.floatingSurface.withValues(alpha: 0.84),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: palette.shadow.withValues(alpha: 0.14),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                          spreadRadius: -5,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 18,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryCardSkeleton extends StatelessWidget {
  const _GalleryCardSkeleton({
    required this.item,
    required this.editing,
    required this.onRename,
    required this.onRenameSubmitted,
    required this.onRenameCancelled,
  });

  final WorkspaceExplorerItem item;
  final bool editing;
  final VoidCallback onRename;
  final Future<bool> Function(String) onRenameSubmitted;
  final VoidCallback onRenameCancelled;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: _galleryPreviewHeight,
          padding: const EdgeInsets.fromLTRB(27, 32, 27, 24),
          color: palette.floatingSurface.withValues(alpha: 0.56),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 92,
                height: 11,
                decoration: BoxDecoration(
                  color: palette.textMuted.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 24),
              for (final width in [0.94, 0.76, 0.88, 0.61, 0.82, 0.49]) ...[
                FractionallySizedBox(
                  widthFactor: width,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: palette.textMuted.withValues(alpha: 0.085),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 13),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(21, 19, 21, 22),
          child: _GalleryCardTitle(
            item: item,
            editing: editing,
            onRename: onRename,
            onSubmitted: onRenameSubmitted,
            onCancelled: onRenameCancelled,
          ),
        ),
      ],
    );
  }
}

class _GalleryUnavailablePreview extends StatelessWidget {
  const _GalleryUnavailablePreview();

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 8,
            decoration: BoxDecoration(
              color: palette.textMuted.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(height: 20),
          for (final width in [0.92, 0.76, 0.84, 0.58]) ...[
            FractionallySizedBox(
              widthFactor: width,
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: palette.textMuted.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 11),
          ],
          const Spacer(),
          Text(
            LocaleKeys.workspaceFolderExplorer_previewUnavailable.tr(),
            style: TextStyle(
              color: palette.textMuted,
              fontFamily: 'Inter',
              fontSize: 10.5,
              letterSpacing: 0.08,
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryMediaLoading extends StatelessWidget {
  const _GalleryMediaLoading();

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Center(
      child: SizedBox.square(
        dimension: 17,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

class _GalleryMediaFallback extends StatelessWidget {
  const _GalleryMediaFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Center(
      child: Icon(
        icon,
        size: 34,
        color: palette.textMuted.withValues(alpha: 0.62),
      ),
    );
  }
}

class _GalleryEmptyState extends StatelessWidget {
  const _GalleryEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(
              color: palette.textSecondary,
              fontFamily: 'Inter',
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.42,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            LocaleKeys.workspaceFolderExplorer_emptyCollectionHint.tr(),
            style: TextStyle(
              color: palette.textMuted,
              fontFamily: 'Inter',
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderGalleryDraftCard extends StatelessWidget {
  const _FolderGalleryDraftCard({
    super.key,
    required this.draft,
    required this.onCancel,
    required this.onSubmitted,
  });

  final WorkspaceExplorerDraft draft;
  final VoidCallback onCancel;
  final Future<bool> Function(String) onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final titleStyle = TextStyle(
      color: palette.textPrimary,
      fontFamily: 'Inter',
      fontSize: 17,
      height: 1.24,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.38,
    );
    final item = WorkspaceExplorerItem(
      id: 'draft',
      parentId: draft.parentId,
      name: draft.suggestedName,
      kind: draft.kind == WorkspaceExplorerDraftKind.folder
          ? WorkspaceExplorerItemKind.folder
          : WorkspaceExplorerItemKind.file,
      metadata: null,
      hasChildren: false,
      lastEdited: null,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.16),
            blurRadius: 34,
            offset: const Offset(0, 14),
            spreadRadius: -10,
          ),
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.07),
            blurRadius: 28,
            offset: const Offset(0, 12),
            spreadRadius: -10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _galleryPreviewHeight,
              child: draft.kind == WorkspaceExplorerDraftKind.folder
                  ? FolderGalleryCollectionArtwork(item: item)
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.floatingSurface.withValues(alpha: 0.56),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(27, 30, 27, 24),
                        child: _GalleryBlankDocumentPreview(item: item),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 18, 21, 21),
              child: WorkspaceInlineNameEditor(
                initialValue: draft.suggestedName,
                onSubmitted: onSubmitted,
                onCancelled: onCancel,
                textStyle: titleStyle,
                selectFileStem: draft.kind == WorkspaceExplorerDraftKind.file,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryDragTarget extends StatefulWidget {
  const _GalleryDragTarget({
    super.key,
    required this.enabled,
    required this.target,
    required this.item,
    required this.onAccept,
    required this.child,
  });

  final bool enabled;
  final ViewPB target;
  final WorkspaceExplorerItem item;
  final ValueChanged<ViewPB> onAccept;
  final Widget child;

  @override
  State<_GalleryDragTarget> createState() => _GalleryDragTargetState();
}

class _GalleryDragTargetState extends State<_GalleryDragTarget> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return DragTarget<ViewPB>(
      onWillAcceptWithDetails: (details) {
        final accept = widget.enabled && details.data.id != widget.target.id;
        if (accept) {
          setState(() => hovering = true);
        }
        return accept;
      },
      onLeave: (_) => setState(() => hovering = false),
      onAcceptWithDetails: (details) {
        setState(() => hovering = false);
        widget.onAccept(details.data);
      },
      builder: (context, candidateData, rejectedData) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: hovering
              ? [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.20),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}

class _GalleryDragFeedback extends StatelessWidget {
  const _GalleryDragFeedback({required this.item});

  final WorkspaceExplorerItem item;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Transform.rotate(
      angle: -0.018,
      child: Container(
        width: 260,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 17),
        decoration: BoxDecoration(
          color: palette.floatingSurface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(alpha: 0.24),
              blurRadius: 36,
              offset: const Offset(0, 16),
              spreadRadius: -8,
            ),
          ],
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            color: palette.textPrimary,
            fontFamily: 'Inter',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                LocaleKeys.workspaceFolderExplorer_movingItem.tr(),
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 10.5,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaperTexture extends StatelessWidget {
  const _PaperTexture();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _PaperTexturePainter());
  }
}

class _PaperTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = PaperTheme.grain;
    const spacing = 23.0;
    for (var y = 11.0; y < size.height; y += spacing) {
      for (var x = 8.0; x < size.width; x += spacing) {
        final offset = ((x + y).round() % 7) * 0.37;
        canvas.drawCircle(Offset(x + offset, y - offset), 0.65, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PaperTexturePainter oldDelegate) => false;
}

bool _isNetworkUrl(String source) {
  final uri = Uri.tryParse(source);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

int _stableHash(String value) {
  var hash = 17;
  for (final codeUnit in value.codeUnits) {
    hash = 0x1fffffff & (hash * 37 + codeUnit);
  }
  return hash;
}
