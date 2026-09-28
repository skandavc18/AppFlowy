import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/af_user_profile_extension.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_find_projection.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_size.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart'
    show FieldType;
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.lightweight = false,
    this.surfaceColor,
    this.previewMode,
    this.onRetry,
  });

  final WorkspaceExplorerItem item;
  final ViewPB view;
  final Future<FolderGalleryPreview> preview;
  final UserProfilePB? userProfile;
  final double height;
  final BorderRadius borderRadius;
  final bool compact;

  /// Dense contact sheets share cached text/image previews but never start a
  /// PDF document or video player per square. Those files retain their real
  /// saved identity/cover until opened in their native viewer.
  final bool lightweight;
  final Color? surfaceColor;
  final ViewPreviewMode? previewMode;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cover = view.cover;
    final mode = previewMode ?? view.previewMode;
    return _GalleryPreviewSurface(
      color: surfaceColor ?? GalleryCardPalette.previewSurface(context),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(
          height: height,
          child: mode == ViewPreviewMode.cover && cover != null && !cover.isNone
              ? IgnorePointer(
                  child: ViewCoverImage(
                    cover: cover,
                    userProfile: userProfile,
                    width: double.infinity,
                    height: height,
                  ),
                )
              : FutureBuilder<FolderGalleryPreview>(
                  future: preview,
                  builder: (context, snapshot) {
                    if (view.layout == ViewLayoutPB.Chat) {
                      return IgnorePointer(
                        child: _GalleryChatPreview(item: item, view: view),
                      );
                    }
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const _GalleryMediaLoading();
                    }
                    final data = snapshot.data;
                    if (snapshot.hasError || data == null || data.unavailable) {
                      return _GalleryUnavailablePreview(onRetry: onRetry);
                    }
                    if (lightweight &&
                        (data.kind == FolderGalleryPreviewKind.pdf ||
                            data.kind == FolderGalleryPreviewKind.video)) {
                      return IgnorePointer(
                        child: _GalleryIdentityPreview(
                          key:
                              const ValueKey('folder-thumbnail-media-identity'),
                          glyph: _GalleryIdentityGlyph(item: item, view: view),
                        ),
                      );
                    }
                    final hasMediaPreview = data.hasHero ||
                        {
                          FolderGalleryPreviewKind.image,
                          FolderGalleryPreviewKind.pdf,
                          FolderGalleryPreviewKind.video,
                        }.contains(data.kind);
                    // This is an activation thumbnail, not the opened viewer.
                    // Keep the failure/retry branch above outside this boundary.
                    return IgnorePointer(
                      child: hasMediaPreview
                          ? _GalleryMediaPreview(
                              preview: data,
                              userProfile: userProfile,
                            )
                          : FolderGalleryFindScope(
                              view: view,
                              preview: data,
                              child: _GalleryPreviewStage(
                                item: item,
                                view: view,
                                preview: data,
                                userProfile: userProfile,
                                compact: compact,
                              ),
                            ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// A folder's identity, not a speculative contact sheet. Counts come from an
/// already-loaded listing; painting this face never reads children/documents.
class FolderContentPreviewThumbnail extends StatelessWidget {
  const FolderContentPreviewThumbnail({
    super.key,
    required this.folder,
    required this.userProfile,
    this.repository = const WorkspaceItemService(),
    this.childCount,
  });

  final ViewPB folder;
  final UserProfilePB? userProfile;

  // Retained for source compatibility. Identity artwork has no repository IO.
  final WorkspaceItemRepository repository;
  final int? childCount;

  @override
  Widget build(BuildContext context) {
    return FolderGalleryCollectionArtwork(
      item: WorkspaceExplorerItem.fromView(folder),
      view: folder,
      childCount: childCount,
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
    this.onBackgroundContextMenu,
    this.header,
    this.errorBanner,
    this.thumbnails = false,
    this.horizontalPadding,
    this.scrollController,
    this.footer,
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

  /// Raised by a right click on empty space, so a collection can be filled
  /// without hunting for the toolbar.
  final ValueChanged<Offset>? onBackgroundContextMenu;
  final Widget? header;
  final Widget? errorBanner;
  final bool thumbnails;

  /// A folder shell already provides the shared reading inset. Standalone
  /// gallery callers can continue to use the existing gallery geometry.
  final double? horizontalPadding;
  final ScrollController? scrollController;
  final Widget? footer;

  @override
  State<FolderGallery> createState() => _FolderGalleryState();
}

class _FolderGalleryState extends State<FolderGallery> {
  final FocusNode focusNode = FocusNode(debugLabel: 'folder-gallery');
  int crossAxisCount = 1;

  @override
  void initState() {
    super.initState();
    unawaited(GalleryCardSizeStore.ensureLoaded());
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GalleryCardSize>(
      valueListenable: GalleryCardSizeStore.notifier,
      builder: (context, cardSize, _) => _buildGallery(context, cardSize),
    );
  }

  Widget _buildGallery(BuildContext context, GalleryCardSize cardSize) {
    final controller = widget.controller;
    final entries = _visibleEntries(controller);
    final draft = controller.draft;
    final showDraft =
        draft != null && draft.parentId == controller.currentFolder.id;
    final itemCount = entries.length + (showDraft ? 1 : 0);
    // A loaded renderer (or rename draft) follows its item through a reorder;
    // it must not be rebuilt as a new card at the old sliver index.
    final childIndices = <Key, int>{
      if (showDraft)
        ValueKey('gallery-draft-${draft.kind}-${draft.parentId}'): 0,
      for (var index = 0; index < entries.length; index++)
        ValueKey('gallery-drag-${entries[index].item.id}'):
            index + (showDraft ? 1 : 0),
    };

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
        onSecondaryTapDown: widget.onBackgroundContextMenu == null
            ? null
            : (details) {
                focusNode.requestFocus();
                controller.selection.clear();
                widget.onBackgroundContextMenu!(details.globalPosition);
              },
        child: FileBrowserScrollView(
          scrollKey: const ValueKey('folder-gallery-scroll-view'),
          controller: widget.scrollController,
          header: widget.header,
          footer: widget.footer,
          cacheExtent: 900,
          slivers: [
            if (widget.errorBanner != null)
              SliverToBoxAdapter(child: widget.errorBanner),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final horizontal = widget.horizontalPadding ??
                    KnowledgeGalleryLayout.horizontalPadding(
                      constraints.crossAxisExtent,
                    );
                final contentWidth =
                    constraints.crossAxisExtent - horizontal * 2;
                final metrics = widget.thumbnails
                    ? GalleryCardMetrics.thumbnails(
                        available: contentWidth,
                        textScale:
                            MediaQuery.textScalerOf(context).scale(13) / 13,
                      )
                    : GalleryCardMetrics.resolve(
                        available: contentWidth,
                        size: cardSize,
                        spacing: KnowledgeGalleryLayout.cardSpacing,
                        maximumColumns: null,
                        fillRow: false,
                        textScale:
                            MediaQuery.textScalerOf(context).scale(15) / 15,
                      );
                crossAxisCount = metrics.columns;
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
                  padding: EdgeInsetsDirectional.fromSTEB(
                    horizontal,
                    8,
                    horizontal +
                        (contentWidth - metrics.gridWidth)
                            .clamp(0.0, double.infinity),
                    84,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: metrics.columns,
                      mainAxisSpacing: metrics.spacing,
                      crossAxisSpacing: metrics.spacing,
                      mainAxisExtent: metrics.height,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (showDraft && index == 0) {
                          return _FolderGalleryDraftCard(
                            key: ValueKey(
                              'gallery-draft-${draft.kind}-${draft.parentId}',
                            ),
                            draft: draft,
                            thumbnail: widget.thumbnails,
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
                          thumbnail: widget.thumbnails,
                          item: row.item,
                          view: view,
                          preview: widget.previewCache.previewFor(
                            view: view,
                            item: row.item,
                          ),
                          userProfile: widget.userProfile,
                          selected: controller.selection.contains(view.id),
                          editing: controller.editingId == view.id,
                          childCount: row.item.isFolder &&
                                  !row.item.readsFromService &&
                                  controller.hasLoaded(view.id)
                              ? controller.childrenOf(view.id).length
                              : null,
                          onRetry: () {
                            widget.previewCache.invalidate(view.id);
                            setState(() {});
                          },
                          searchPath: controller.query.isEmpty
                              ? null
                              : controller.relativePathFor(view.id),
                          onTap: () => _activate(row.item, entries),
                          canRename: controller.canRename(view.id),
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
                          enabled: controller.query.isEmpty &&
                              controller.canWriteTo(
                                row.item.isFolder ? view.id : view.parentViewId,
                              ),
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
                          child: controller.query.isEmpty &&
                                  controller.canWriteTo(view.id)
                              ? _GalleryDraggable(
                                  data: view,
                                  feedback:
                                      _GalleryDragFeedback(item: row.item),
                                  childWhenDragging: Opacity(
                                    opacity: 0.32,
                                    child: card,
                                  ),
                                  // Same wrapper at rest and during a drag:
                                  // dim paint without remounting the media.
                                  child: Opacity(opacity: 1, child: card),
                                )
                              : card,
                        );
                      },
                      childCount: itemCount,
                      findChildIndexCallback: (key) => childIndices[key],
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
    // A collection is a folder with a purpose, and a bound folder's contents
    // live in a service, so both open as themselves rather than being browsed
    // into as plain workspace contents.
    if (item.isBrowsable) {
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
    // Keep list navigation for a focused card, but let native header/overflow
    // buttons and text fields reach their own Shortcuts/Actions. In particular,
    // swallowing Enter here prevents the Gallery button from opening its menu.
    if (!focusNode.hasPrimaryFocus) {
      final primary = FocusManager.instance.primaryFocus;
      final card =
          primary?.context?.findAncestorStateOfType<_FolderGalleryCardState>();
      if (card == null || primary != card._focusNode) {
        return KeyEventResult.ignored;
      }
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
    this.canRename = true,
    this.childCount,
    this.onRetry,
    this.thumbnail = false,
  });

  final WorkspaceExplorerItem item;
  final ViewPB view;
  final Future<FolderGalleryPreview> preview;
  final UserProfilePB? userProfile;
  final bool selected;
  final bool editing;
  final bool canRename;
  final bool thumbnail;
  final String? searchPath;
  final int? childCount;
  final VoidCallback? onRetry;
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
  final _focusNode = FocusNode(debugLabel: 'Folder gallery card');
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_syncFocus);
  }

  void _syncFocus() {
    final focused = _focusNode.hasFocus;
    if (mounted && _focused != focused) {
      setState(() => _focused = focused);
    }
  }

  void _setHovered(bool hovered) {
    if (_hovered != hovered) {
      setState(() => _hovered = hovered);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_syncFocus);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPaper = PaperTheme.isEnabled(context);
    final content = Semantics(
      button: true,
      selected: widget.selected,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isPaper && !widget.thumbnail)
            const Positioned.fill(
              child: IgnorePointer(child: _PaperTexture()),
            ),
          GestureDetector(
            key: const ValueKey('folder-gallery-card-content'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onSecondaryTapDown: (details) =>
                widget.onContextMenu(details.globalPosition),
            child: widget.thumbnail
                ? _buildThumbnail(context)
                : FutureBuilder<FolderGalleryPreview>(
                    future: widget.preview,
                    builder: (context, snapshot) {
                      // Loading changes the preview, never an active editor.
                      return _GalleryCardContent(
                        item: widget.item,
                        view: widget.view,
                        preview:
                            snapshot.connectionState == ConnectionState.done
                                ? snapshot.data
                                : null,
                        previewFailed:
                            snapshot.connectionState == ConnectionState.done &&
                                (snapshot.hasError || snapshot.data == null),
                        childCount: widget.childCount,
                        onRetry: widget.onRetry,
                        userProfile: widget.userProfile,
                        editing: widget.editing,
                        searchPath: widget.searchPath,
                        onTap: widget.onTap,
                        onRename: widget.canRename ? widget.onRename : null,
                        onRenameSubmitted: widget.onRenameSubmitted,
                        onRenameCancelled: widget.onRenameCancelled,
                      );
                    },
                  ),
          ),
          PositionedDirectional(
            top: WorkspaceTokens.space2,
            end: WorkspaceTokens.space2,
            child: PreviewToolbar(
              keepVisible: widget.selected || widget.editing || _focused,
              child: _GalleryOverflowAction(onMore: widget.onMore),
            ),
          ),
        ],
      ),
    );
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: !widget.editing,
      // A removed editor can detach before onFocusChange(false). Reconcile
      // against the settled focus tree as well as ordinary focus callbacks.
      onFocusChange: (_) => _syncFocus(),
      onKeyEvent: _handleKeyEvent,
      child: PreviewToolbarRegion(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHovered(true),
          onHover: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: widget.thumbnail
              ? content
              : GalleryCardSurface(
                  selected: widget.selected,
                  focused: _focused,
                  hovered: _hovered,
                  child: content,
                ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final title = widget.item.name.isEmpty
        ? LocaleKeys.workspaceFolderExplorer_untitled.tr()
        : widget.item.name;
    return FolderThumbnailTile(
      selected: widget.selected,
      focused: _focused,
      hovered: _hovered,
      preview: FolderGalleryPreviewThumbnail(
        item: widget.item,
        view: widget.view,
        preview: widget.preview,
        userProfile: widget.userProfile,
        height: double.infinity,
        compact: true,
        lightweight: true,
        borderRadius: BorderRadius.zero,
        onRetry: widget.onRetry,
      ),
      name: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkspaceItemIcon(
            item: widget.item,
            view: widget.view,
            size: 14,
            showThumbnail: false,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: [
                title,
                if (widget.searchPath != null) widget.searchPath!
              ].join('\n'),
              excludeFromSemantics: true,
              child: WorkspaceInlineEditableText(
                key: const ValueKey('folder-thumbnail-name'),
                text: title,
                editingValue: widget.item.name,
                editing: widget.editing,
                onSubmitted: widget.onRenameSubmitted,
                onCancelled: widget.onRenameCancelled,
                onTap: widget.onTap,
                onDoubleTap: widget.canRename ? widget.onRename : null,
                maxLines: 2,
                selectFileStem: widget.item.isFile,
                style:
                    WorkspaceTypography.style(context, WorkspaceTextRole.body)
                        .copyWith(fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // The title editor and native overflow button keep their own key bindings.
    if (!node.hasPrimaryFocus || widget.editing || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (isWorkspaceRenameShortcut(Theme.of(context).platform, key)) {
      if (widget.canRename) widget.onRename();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu ||
        (key == LogicalKeyboardKey.f10 &&
            HardwareKeyboard.instance.isShiftPressed)) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        widget.onContextMenu(box.localToGlobal(box.size.center(Offset.zero)));
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// A square contact-sheet preview and a plain name below it. No Gallery footer,
/// fabricated metadata, elevation, or additional gesture/focus owner.
class FolderThumbnailTile extends StatelessWidget {
  const FolderThumbnailTile({
    super.key,
    required this.preview,
    required this.name,
    this.selected = false,
    this.focused = false,
    this.hovered = false,
  });

  final Widget preview;
  final Widget name;
  final bool selected;
  final bool focused;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final corners = BorderRadius.circular(10);
    return Container(
      key: const ValueKey('folder-thumbnail-surface'),
      decoration: BoxDecoration(
        color: selected
            ? palette.selected
            : palette.hover.withValues(alpha: hovered ? palette.hover.a : 0),
        borderRadius: corners,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: corners,
        border: focused ? Border.all(color: palette.accent, width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            key: const ValueKey('folder-thumbnail-square'),
            aspectRatio: 1,
            child: ClipRRect(borderRadius: corners, child: preview),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: name,
            ),
          ),
        ],
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
    required this.onTap,
    required this.onRename,
    required this.onRenameSubmitted,
    required this.onRenameCancelled,
    required this.previewFailed,
    this.childCount,
    this.onRetry,
    this.searchPath,
  });

  final WorkspaceExplorerItem item;
  final ViewPB view;
  final FolderGalleryPreview? preview;
  final bool previewFailed;
  final int? childCount;
  final VoidCallback? onRetry;
  final UserProfilePB? userProfile;
  final bool editing;
  final String? searchPath;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final Future<bool> Function(String) onRenameSubmitted;
  final VoidCallback onRenameCancelled;

  @override
  Widget build(BuildContext context) {
    final cover = view.cover;
    final previewMode = view.previewMode;
    final isChat = view.layout == ViewLayoutPB.Chat;
    final data = isChat ? FolderGalleryPreviewParser.chat(view) : preview;
    final showsCover =
        previewMode == ViewPreviewMode.cover && cover != null && !cover.isNone;
    final showsFailure = !showsCover &&
        !isChat &&
        (previewFailed || (data?.unavailable ?? false));
    final hasMediaPreview = data != null &&
        (data.hasHero ||
            {
              FolderGalleryPreviewKind.image,
              FolderGalleryPreviewKind.pdf,
              FolderGalleryPreviewKind.video,
            }.contains(data.kind));
    return LayoutBuilder(
      builder: (context, constraints) {
        final density = GalleryCardDensity.forWidth(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: KeyedSubtree(
                key: const ValueKey('folder-gallery-preview-stage'),
                // Only the thumbnail is inert. The title, overflow menu and
                // recovery button must still own their respective gestures.
                child: IgnorePointer(
                  ignoring: !showsFailure,
                  child: showsCover
                      ? ViewCoverImage(
                          cover: cover,
                          userProfile: userProfile,
                          width: double.infinity,
                        )
                      : showsFailure
                          ? _GalleryUnavailablePreview(onRetry: onRetry)
                          : data == null
                              ? const _GalleryCardSkeleton()
                              : previewMode == ViewPreviewMode.content &&
                                      item.isFolder
                                  ? FolderContentPreviewThumbnail(
                                      folder: view,
                                      userProfile: userProfile,
                                      childCount: childCount,
                                    )
                                  : hasMediaPreview
                                      ? _GalleryMediaPreview(
                                          preview: data,
                                          userProfile: userProfile,
                                        )
                                      : _GalleryPreviewStage(
                                          item: item,
                                          view: view,
                                          childCount: childCount,
                                          preview: data,
                                          userProfile: userProfile,
                                        ),
                ),
              ),
            ),
            GalleryCardFooter(
              key: const ValueKey('folder-gallery-footer'),
              padding: density.footerPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GalleryCardTitle(
                    item: item,
                    view: view,
                    editing: editing,
                    searchPath: searchPath,
                    density: density,
                    onTap: onTap,
                    onRename: onRename,
                    onSubmitted: onRenameSubmitted,
                    onCancelled: onRenameCancelled,
                  ),
                  if (data != null) ...[
                    SizedBox(height: density.titleGap),
                    _GalleryMetadata(
                      item: item,
                      view: view,
                      preview: data,
                      density: density,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GalleryPreviewStage extends StatelessWidget {
  const _GalleryPreviewStage({
    required this.item,
    required this.preview,
    required this.userProfile,
    this.compact = false,
    this.view,
    this.childCount,
  });

  final WorkspaceExplorerItem item;
  final ViewPB? view;
  final int? childCount;
  final FolderGalleryPreview preview;
  final UserProfilePB? userProfile;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (preview.kind == FolderGalleryPreviewKind.chat ||
        view?.layout == ViewLayoutPB.Chat) {
      return _GalleryChatPreview(item: item, view: view);
    }
    if (preview.kind == FolderGalleryPreviewKind.folder) {
      return FolderGalleryCollectionArtwork(
        item: item,
        view: view,
        childCount: childCount,
      );
    }
    if (!preview.unavailable &&
        !preview.hasHero &&
        {
          FolderGalleryPreviewKind.document,
          FolderGalleryPreviewKind.code,
          FolderGalleryPreviewKind.file,
        }.contains(preview.kind) &&
        preview.blocks.every((block) => block.plainText.trim().isEmpty)) {
      return _GalleryIdentityPreview(
        key: const ValueKey('folder-gallery-file-identity'),
        glyph: _GalleryIdentityGlyph(item: item, view: view),
      );
    }
    final database = preview.database;
    if (!preview.unavailable &&
        preview.kind == FolderGalleryPreviewKind.database &&
        database != null &&
        database.totalRowCount == 0 &&
        database.rows.isEmpty) {
      return _GalleryIdentityPreview(
        key: const ValueKey('folder-gallery-empty-table-artwork'),
        glyph: _GalleryIdentityGlyph(item: item, view: view),
      );
    }
    final base = _galleryIdentitySurface(context);
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
    return ColoredBox(
      color: base,
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
    required this.onTap,
    required this.onRename,
    required this.onSubmitted,
    required this.onCancelled,
    required this.density,
    this.searchPath,
    this.view,
  });

  final WorkspaceExplorerItem item;
  final ViewPB? view;
  final bool editing;
  final String? searchPath;
  final GalleryCardDensity density;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final Future<bool> Function(String) onSubmitted;
  final VoidCallback onCancelled;

  @override
  Widget build(BuildContext context) {
    final titleStyle = WorkspaceTypography.style(
      context,
      WorkspaceTextRole.cardTitle,
    ).copyWith(
      fontSize: density.titleSize,
      letterSpacing: density.titleSpacing,
    );
    final title = item.name.isEmpty
        ? LocaleKeys.workspaceFolderExplorer_untitled.tr()
        : item.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: WorkspaceItemIcon(
                item: item,
                view: view,
                size: density.emojiSize,
                showThumbnail: false,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: title,
                excludeFromSemantics: true,
                child: WorkspaceInlineEditableText(
                  text: title,
                  editingValue: item.name,
                  editing: editing,
                  onSubmitted: onSubmitted,
                  onCancelled: onCancelled,
                  onTap: onTap,
                  onDoubleTap: onRename,
                  // The display opens a page; only the actual name editor
                  // should advertise the text cursor.
                  display: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                  maxLines: 2,
                  selectFileStem: item.isFile,
                  style: titleStyle,
                ),
              ),
            ),
          ],
        ),
        if (searchPath != null && searchPath!.isNotEmpty) ...[
          const SizedBox(height: WorkspaceTokens.space1),
          Tooltip(
            message: searchPath!,
            excludeFromSemantics: true,
            child: Text(
              searchPath!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.metadata,
              ).copyWith(fontSize: density.metadataSize),
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
      FolderGalleryPreviewKind.chat => _GalleryChatPreview(item: item),
      FolderGalleryPreviewKind.folder =>
        FolderGalleryCollectionArtwork(item: item),
      FolderGalleryPreviewKind.database => _GalleryDatabasePreview(
          snapshot: preview.database,
          unavailable: preview.unavailable,
        ),
      FolderGalleryPreviewKind.code => _GalleryCodePreview(preview: preview),
      FolderGalleryPreviewKind.file ||
      FolderGalleryPreviewKind.document =>
        FolderGalleryRichTextPreview(blocks: preview.blocks),
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

/// Renders preview blocks — headings, lists, quotes, code — as a compact
/// card of text. Shared by the gallery card and the search preview so a file
/// reads the same wherever it is previewed.
class FolderGalleryRichTextPreview extends StatelessWidget {
  const FolderGalleryRichTextPreview({super.key, required this.blocks});

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
            palette.hover.withValues(alpha: palette.hover.a * 0.52),
            isPaper: PaperTheme.isEnabled(context),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: FolderGalleryFindText(
          text: 'ƒ  ${block.plainText}',
          contentStart: 3,
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
          Expanded(
            child: FolderGalleryFindText(text: block.plainText, child: body),
          ),
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
                palette.hover.withValues(alpha: palette.hover.a * 0.44),
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
                child: FolderGalleryFindText(
                  text: code,
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
      color: palette.hover.withValues(alpha: palette.hover.a * 0.26),
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
      return const _GalleryMediaFallback(icon: Icons.image_rounded);
    }
    if (_isNetworkUrl(source)) {
      return FlowyNetworkImage(
        url: source,
        width: double.infinity,
        height: double.infinity,
        userProfilePB: userProfile,
        progressIndicatorBuilder: (_, __, ___) => const _GalleryMediaLoading(),
        errorWidgetBuilder: (_, __, ___) => const _GalleryUnavailablePreview(),
      );
    }
    return Image.file(
      File(source),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _GalleryUnavailablePreview(),
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
      return const _GalleryMediaFallback(icon: Icons.picture_as_pdf_rounded);
    }
    Widget builder(BuildContext context, PdfDocument? document) {
      if (document == null) {
        return const _GalleryMediaLoading();
      }
      if (document.pages.isEmpty) {
        return const _GalleryUnavailablePreview();
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
      return const _GalleryUnavailablePreview();
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
      return const _GalleryMediaFallback(icon: Icons.movie_rounded);
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
  const FolderGalleryCollectionArtwork({
    super.key,
    required this.item,
    this.view,
    this.childCount,
  });

  final WorkspaceExplorerItem item;
  final ViewPB? view;

  /// Null means unknown, not zero. Never enumerate children just for artwork.
  final int? childCount;

  @override
  Widget build(BuildContext context) {
    // A protobuf listing can omit children until that folder is opened. Only
    // a supplied loaded count may say zero; service-backed listings are not
    // represented by childViews at all.
    final listed = view?.childViews;
    final count = childCount ??
        (!item.readsFromService && listed != null && listed.isNotEmpty
            ? listed.length
            : null);
    return _GalleryIdentityPreview(
      key: const ValueKey('folder-gallery-folder-identity'),
      glyph: _GalleryIdentityGlyph(item: item, view: view),
      caption: count == null
          ? null
          : LocaleKeys.workspaceFolderExplorer_itemCount.tr(args: ['$count']),
    );
  }
}

class _GalleryIdentityGlyph extends StatelessWidget {
  const _GalleryIdentityGlyph({
    required this.item,
    this.view,
    this.defaultName,
  });

  final WorkspaceExplorerItem item;
  final ViewPB? view;
  final String? defaultName;

  @override
  Widget build(BuildContext context) {
    final saved = view?.icon.toEmojiIconData();
    if (saved != null && saved.isNotEmpty) {
      return MediaQuery.withNoTextScaling(
        child: RawEmojiIconWidget(emoji: saved, emojiSize: 64, lineHeight: 1),
      );
    }
    final name = defaultName;
    if (name != null) return WorkspaceGlyph.named(name, size: 64);
    final collectionKind = item.collection?.kind;
    if (collectionKind != null) {
      return WorkspaceGlyph.collection(collectionKind, size: 64);
    }
    return WorkspaceItemIcon(
      item: item,
      view: view,
      size: 64,
      showThumbnail: false,
    );
  }
}

class _GalleryChatPreview extends StatelessWidget {
  const _GalleryChatPreview({required this.item, this.view});

  final WorkspaceExplorerItem item;
  final ViewPB? view;

  @override
  Widget build(BuildContext context) => Semantics(
        key: const ValueKey('folder-gallery-chat-identity'),
        image: true,
        label: LocaleKeys.chat_newChat.tr(),
        child: ExcludeSemantics(
          child: _GalleryIdentityPreview(
            glyph: _GalleryIdentityGlyph(
              item: item,
              view: view,
              defaultName: 'ai-chat',
            ),
            caption: LocaleKeys.chat_newChat.tr(),
            captionKey: const ValueKey('folder-gallery-chat-label'),
          ),
        ),
      );
}

/// One bounded identity slot for empty/unpreviewable content, never a mock
/// document. Fitting the whole group also keeps real counts safe at 2x text.
class _GalleryIdentityPreview extends StatelessWidget {
  const _GalleryIdentityPreview({
    super.key,
    required this.glyph,
    this.caption,
    this.captionKey = const ValueKey('folder-gallery-child-count'),
  });

  final Widget glyph;
  final String? caption;
  final Key captionKey;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _galleryIdentitySurface(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(dimension: 64, child: glyph),
                if (caption != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    caption!,
                    key: captionKey,
                    style: WorkspaceTypography.style(
                      context,
                      WorkspaceTextRole.metadata,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Color _galleryIdentitySurface(BuildContext context) {
  return context
          .dependOnInheritedWidgetOfExactType<_GalleryPreviewSurface>()
          ?.color ??
      GalleryCardPalette.previewSurface(context);
}

class _GalleryPreviewSurface extends InheritedWidget {
  const _GalleryPreviewSurface({required this.color, required super.child});

  final Color color;

  @override
  bool updateShouldNotify(_GalleryPreviewSurface oldWidget) =>
      color != oldWidget.color;
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
    if (database == null ||
        (database.totalRowCount > 0 &&
            (database.columns.isEmpty || database.rows.isEmpty))) {
      return const _GalleryUnavailablePreview();
    }
    if (database.rows.isEmpty) {
      return _GalleryEmptyDatabasePreview(unavailable: unavailable);
    }
    final baseSurface = _galleryIdentitySurface(context);
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
              child: WorkspaceGlyph(
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
                        fieldTypes: database.fieldTypes,
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
    this.fieldTypes = const [],
  });

  final List<String> values;
  final bool header;
  final Color backgroundColor;
  final List<FieldType> fieldTypes;

  bool _findable(int index) =>
      header ||
      (index < fieldTypes.length &&
          const {
            FieldType.RichText,
            FieldType.Number,
            FieldType.Summary,
            FieldType.Translate,
            FieldType.SingleSelect,
            FieldType.MultiSelect,
            FieldType.Checklist,
            FieldType.DateTime,
            FieldType.CreatedTime,
            FieldType.LastEditedTime,
          }.contains(fieldTypes[index]));

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
                  child: FolderGalleryFindText(
                    text: values[index],
                    enabled: values[index].isNotEmpty && _findable(index),
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
    return unavailable
        ? const _GalleryUnavailablePreview()
        : const _GalleryIdentityPreview(
            key: ValueKey('folder-gallery-empty-table-artwork'),
            glyph: WorkspaceGlyph(Icons.table_chart_rounded, size: 64),
          );
  }
}

class _GalleryMetadata extends StatelessWidget {
  const _GalleryMetadata({
    required this.item,
    required this.view,
    required this.preview,
    required this.density,
  });

  final WorkspaceExplorerItem item;
  final ViewPB view;
  final FolderGalleryPreview preview;
  final GalleryCardDensity density;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final size = item.metadata?.size;
    final metadata = <String>[
      if (preview.fileTypeLabel.isNotEmpty) preview.fileTypeLabel,
      if (size != null && size >= 0)
        '${NumberFormat.decimalPattern().format(size)} B',
      if (item.lastEdited case final modified?)
        DateFormat.MMMd().format(modified),
      ...preview.tags.map((tag) => '#$tag'),
    ];
    final details = <String>[
      ...metadata,
      if (preview.readingMinutes > 0)
        LocaleKeys.workspaceFolderExplorer_minuteRead.tr(
          args: [preview.readingMinutes.toString()],
        ),
      if (preview.wordCount > 0)
        LocaleKeys.workspaceFolderExplorer_wordCountShort.tr(
          args: [NumberFormat.compact().format(preview.wordCount)],
        ),
    ];
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: details.join(' · '),
            excludeFromSemantics: true,
            child: Semantics(
              label: details.join(' · '),
              excludeSemantics: true,
              child: Text(
                metadata.join(' · '),
                key: const ValueKey('folder-gallery-metadata'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.metadata,
                ).copyWith(fontSize: density.metadataSize),
              ),
            ),
          ),
        ),
        if (view.isPinned)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 5),
            child: Tooltip(
              message: LocaleKeys.workspaceFolderExplorer_pinned.tr(),
              child: Icon(
                Icons.push_pin_rounded,
                size: 12,
                color: palette.accent,
              ),
            ),
          ),
        if (view.isFavorite)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 5),
            child: Icon(Icons.star_rounded, size: 12, color: palette.accent),
          ),
      ],
    );
  }
}

class _GalleryOverflowAction extends StatelessWidget {
  const _GalleryOverflowAction({required this.onMore});

  final ValueChanged<Offset> onMore;

  @override
  Widget build(BuildContext context) {
    final label = LocaleKeys.workspaceFolderExplorer_more.tr();
    return Shortcuts(
      // Resolve activation before the gallery's selection/navigation handler.
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: IconButton(
          key: const ValueKey('folder-gallery-more'),
          style: WorkspaceChrome.controlStyle(context).copyWith(
            minimumSize: const WidgetStatePropertyAll(Size.square(40)),
            tapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            backgroundColor: WidgetStatePropertyAll(
              WorkspacePalette.of(context).elevatedSurface,
            ),
          ),
          onPressed: () {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null && box.hasSize) {
              onMore(
                box.localToGlobal(Offset(box.size.width, box.size.height + 5)),
              );
            }
          },
          icon: Semantics(
            label: label,
            child: const WorkspaceGlyph(Icons.more_horiz_rounded),
          ),
        ),
      ),
    );
  }
}

class _GalleryCardSkeleton extends StatelessWidget {
  const _GalleryCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('folder-gallery-preview-loading'),
      color: _galleryIdentitySurface(context),
      child: const Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: WorkspaceGlyph.named('hourglass', size: 28),
        ),
      ),
    );
  }
}

class _GalleryUnavailablePreview extends StatelessWidget {
  const _GalleryUnavailablePreview({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('folder-gallery-preview-unavailable'),
      color: _galleryIdentitySurface(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 180,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const WorkspaceGlyph.named('warning', size: 32),
                  const SizedBox(height: 10),
                  Text(
                    LocaleKeys.workspaceFolderExplorer_previewUnavailable.tr(),
                    textAlign: TextAlign.center,
                    style: WorkspaceTypography.style(
                      context,
                      WorkspaceTextRole.metadata,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey('folder-gallery-preview-retry'),
                      style: WorkspaceChrome.controlStyle(context),
                      onPressed: onRetry,
                      child: Text(LocaleKeys.button_retry.tr()),
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

class _GalleryMediaLoading extends StatelessWidget {
  const _GalleryMediaLoading();

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return ColoredBox(
      key: const ValueKey('folder-gallery-preview-loading'),
      color: _galleryIdentitySurface(context),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox.square(
            dimension: 17,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: palette.textMuted,
            ),
          ),
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
    return _GalleryIdentityPreview(
      glyph: WorkspaceGlyph(icon, size: 64),
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
    this.thumbnail = false,
  });

  final WorkspaceExplorerDraft draft;
  final VoidCallback onCancel;
  final Future<bool> Function(String) onSubmitted;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
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
    if (thumbnail) {
      return FolderThumbnailTile(
        selected: true,
        preview: _GalleryIdentityPreview(
          glyph: _GalleryIdentityGlyph(item: item),
        ),
        name: WorkspaceInlineNameEditor(
          initialValue: draft.suggestedName,
          onSubmitted: onSubmitted,
          onCancelled: onCancel,
          textStyle: WorkspaceTypography.style(context, WorkspaceTextRole.body)
              .copyWith(fontSize: 13, height: 1.4),
          selectFileStem: draft.kind == WorkspaceExplorerDraftKind.file,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final density = GalleryCardDensity.forWidth(constraints.maxWidth);
        return GalleryCardSurface(
          selected: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: draft.kind == WorkspaceExplorerDraftKind.folder
                    ? FolderGalleryCollectionArtwork(item: item)
                    : _GalleryIdentityPreview(
                        glyph: _GalleryIdentityGlyph(item: item),
                      ),
              ),
              GalleryCardFooter(
                key: const ValueKey('folder-gallery-footer'),
                padding: density.footerPadding,
                child: WorkspaceInlineNameEditor(
                  initialValue: draft.suggestedName,
                  onSubmitted: onSubmitted,
                  onCancelled: onCancel,
                  textStyle: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.cardTitle,
                  ).copyWith(fontSize: density.titleSize),
                  selectFileStem: draft.kind == WorkspaceExplorerDraftKind.file,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Keep Flutter's drag/drop lifecycle, but do not turn ordinary mouse wobble
/// into a drag. ImmediateMultiDragGestureRecognizer uses a 1px mouse slop,
/// whereas the card/title tap recognizers allow 18px. Accepting at 1px cancels
/// those taps and swaps in childWhenDragging before a click can complete.
class _GalleryDraggable extends Draggable<ViewPB> {
  const _GalleryDraggable({
    required super.data,
    required super.feedback,
    required super.childWhenDragging,
    required super.child,
  }) : super(
          // The hover region returns a non-opaque hit. deferToChild omits the
          // Draggable's Listener from that path even though the card is hit.
          hitTestBehavior: HitTestBehavior.translucent,
        );

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      _GalleryDragGestureRecognizer()..onStart = onStart;
}

class _GalleryDragGestureRecognizer
    extends ImmediateMultiDragGestureRecognizer {
  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      return super.createNewPointerState(event);
    }
    return _GalleryMouseDragState(
      event.position,
      event.kind,
      gestureSettings,
    );
  }
}

class _GalleryMouseDragState extends MultiDragPointerState {
  _GalleryMouseDragState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );

  static const _dragSlop = 4.0;

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > _dragSlop) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
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
        duration: WorkspaceTokens.motion(context, galleryCardHoverDuration),
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
