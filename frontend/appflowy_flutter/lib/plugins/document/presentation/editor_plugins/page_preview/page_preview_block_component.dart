import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_picker_dialog.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PagePreviewBlockKeys {
  const PagePreviewBlockKeys._();

  static const type = 'page_preview';
  static const viewId = 'view_id';
  static const width = 'width';
  static const previewMode = 'preview_mode';
  static const globalKey = 'global_key';
}

bool isPagePreviewCandidate(
  ViewPB view, {
  String? currentViewId,
}) =>
    view.id.isNotEmpty &&
    view.id != currentViewId &&
    view.parentViewId.isNotEmpty &&
    switch (view.layout) {
      ViewLayoutPB.Document ||
      ViewLayoutPB.Grid ||
      ViewLayoutPB.Board ||
      ViewLayoutPB.Calendar =>
        true,
      _ => false,
    } &&
    !view.isSpace &&
    !view.isWorkspaceItem;

Node pagePreviewNode({
  String? viewId,
  double width = 720,
  ViewPreviewMode previewMode = ViewPreviewMode.cover,
}) {
  return Node(
    type: PagePreviewBlockKeys.type,
    attributes: {
      PagePreviewBlockKeys.viewId: viewId,
      PagePreviewBlockKeys.width: width,
      PagePreviewBlockKeys.previewMode: previewMode.name,
    },
  );
}

class PagePreviewBlockComponentBuilder extends BlockComponentBuilder {
  PagePreviewBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    final key = node.extraInfos?[PagePreviewBlockKeys.globalKey] as GlobalKey?;
    return PagePreviewBlockComponent(
      key: key ?? node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class PagePreviewBlockComponent extends BlockComponentStatefulWidget {
  const PagePreviewBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<PagePreviewBlockComponent> createState() =>
      PagePreviewBlockComponentState();
}

class PagePreviewBlockComponentState extends State<PagePreviewBlockComponent>
    with BlockComponentConfigurable, SelectableMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late final EditorState editorState =
      Provider.of<EditorState>(context, listen: false);
  final pageBlockKey = GlobalKey(debugLabel: PagePreviewBlockKeys.type);
  final pagePickerController = PopoverController();
  final previewCache = FolderGalleryPreviewCache();
  Future<ViewPB?>? page;
  ViewListener? listener;
  String? boundViewId;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;
  String get currentViewId =>
      Provider.of<ViewBloc>(context, listen: false).state.view.id;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void didUpdateWidget(covariant PagePreviewBlockComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (boundViewId != node.attributes[PagePreviewBlockKeys.viewId]) {
      _loadPage();
    }
  }

  @override
  void dispose() {
    listener?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width =
        (node.attributes[PagePreviewBlockKeys.width] as num?)?.toDouble() ??
            720;
    final viewId = node.attributes[PagePreviewBlockKeys.viewId] as String?;
    final previewMode = ViewPreviewMode.fromValue(
      node.attributes[PagePreviewBlockKeys.previewMode],
    );
    Widget child;
    if (viewId == null || viewId.isEmpty) {
      child = _PagePreviewPlaceholder(onSelect: showPagePicker);
    } else {
      child = FutureBuilder<ViewPB?>(
        future: page,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 210,
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            );
          }
          final view = snapshot.data;
          if (view == null) {
            return _UnavailablePagePreview(onSelect: showPagePicker);
          }
          return ResizableMedia(
            width: width,
            minWidth: 300,
            alignment: blockEmbedAlignment(node),
            editable: editorState.editable,
            onResize: (value) => _updateWidth(value),
            child: PagePreviewCard(
              view: view,
              userProfile: context.read<DocumentBloc>().state.userProfilePB,
              previewCache: previewCache,
              onOpen: () => context.read<TabsBloc>().openPlugin(view),
              previewMode: previewMode,
              onChangePage: showPagePicker,
              onPreviewModeChanged: (mode) => _updateAttributes({
                PagePreviewBlockKeys.previewMode: mode.name,
              }),
            ),
          );
        },
      );
    }

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: Padding(
        padding: padding,
        child: RepaintBoundary(key: pageBlockKey, child: child),
      ),
    );
    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }
    return AppFlowyPopover(
      controller: pagePickerController,
      triggerActions: PopoverTriggerFlags.none,
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 8),
      margin: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 400,
        maxWidth: 400,
        maxHeight: 330,
      ),
      animationDuration: const Duration(milliseconds: 140),
      beginScaleFactor: 0.98,
      asBarrier: true,
      popupBuilder: (_) => WorkspaceViewPickerMenu(
        contentKey: const ValueKey('page-preview-picker-menu'),
        title: LocaleKeys.commandPalette_pagePreview.tr(),
        searchHint: LocaleKeys.search_label.tr(),
        emptyMessage: LocaleKeys.inlineActions_noResults.tr(),
        errorMessage: LocaleKeys.document_mobilePageSelector_failedToLoad.tr(),
        selectedViewId: viewId,
        viewFilter: (view) => isPagePreviewCandidate(
          view,
          currentViewId: currentViewId,
        ),
        leadingBuilder: _buildPagePickerIcon,
        onSelected: _selectPage,
      ),
      child: child,
    );
  }

  Widget _buildPagePickerIcon(
    BuildContext context,
    ViewPB view,
    FolderExplorerPalette palette,
  ) {
    final icon = view.icon.toEmojiIconData();
    return SizedBox.square(
      dimension: 18,
      child: icon.isNotEmpty
          ? RawEmojiIconWidget(
              emoji: icon,
              emojiSize: 17,
              lineHeight: 1,
            )
          : view.defaultIcon(size: const Size.square(17)),
    );
  }

  void showPagePicker() => pagePickerController.show();

  Future<void> _selectPage(ViewPB selectedPage) async {
    pagePickerController.close();
    if (!isPagePreviewCandidate(
      selectedPage,
      currentViewId: currentViewId,
    )) {
      Log.warn(
        'Rejected invalid page preview target ${selectedPage.id}',
      );
      return;
    }

    pageMemorizer[selectedPage.id] = selectedPage;
    final transaction = editorState.transaction
      ..updateNode(node, {PagePreviewBlockKeys.viewId: selectedPage.id});
    await editorState.apply(transaction);
    if (mounted) {
      setState(_loadPage);
    }
  }

  void _loadPage() {
    listener?.stop();
    final viewId = node.attributes[PagePreviewBlockKeys.viewId] as String?;
    boundViewId = viewId;
    if (viewId == null || viewId.isEmpty) {
      page = Future.value();
      return;
    }
    page = _fetchPage(viewId);
    listener = ViewListener(viewId: viewId)
      ..start(
        onViewUpdated: (updated) {
          if (!mounted || updated.id != boundViewId) {
            return;
          }
          if (!isPagePreviewCandidate(
            updated,
            currentViewId: currentViewId,
          )) {
            _markUnavailable();
            return;
          }
          pageMemorizer[updated.id] = updated;
          previewCache.invalidate(updated.id);
          setState(() => page = Future.value(updated));
        },
        onViewDeleted: (_) => _markUnavailable(),
        onViewMoveToTrash: (_) => _markUnavailable(),
        onViewRestored: (_) {
          if (mounted) {
            setState(() => page = _fetchPage(viewId));
          }
        },
      );
  }

  Future<ViewPB?> _fetchPage(String viewId) async {
    final result = await ViewBackendService.getView(viewId);
    return result.fold(
      (view) {
        if (!isPagePreviewCandidate(
          view,
          currentViewId: currentViewId,
        )) {
          Log.warn('Rejected invalid page preview target ${view.id}');
          return null;
        }
        pageMemorizer[view.id] = view;
        return view;
      },
      (_) => null,
    );
  }

  void _markUnavailable() {
    if (mounted) {
      setState(() => page = Future.value());
    }
  }

  Future<void> _updateWidth(double width) {
    return _updateAttributes({PagePreviewBlockKeys.width: width});
  }

  Future<void> _updateAttributes(Map<String, Object?> attributes) {
    final transaction = editorState.transaction..updateNode(node, attributes);
    return editorState.apply(transaction);
  }

  @override
  Position start() => Position(path: node.path);

  @override
  Position end() => Position(path: node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final renderBox = pageBlockKey.currentContext?.findRenderObject();
    if (renderBox is RenderBox) {
      return padding.topLeft & renderBox.size;
    }
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final rects = getRectsInSelection(Selection.collapsed(position));
    return rects.isEmpty ? null : rects.first;
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) {
      return [];
    }
    final parentBox = context.findRenderObject();
    final renderBox = pageBlockKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && renderBox is RenderBox) {
      return [
        renderBox.localToGlobal(Offset.zero, ancestor: parentBox) &
            renderBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox!.localToGlobal(offset);
}

class PagePreviewCard extends StatefulWidget {
  const PagePreviewCard({
    super.key,
    required this.view,
    required this.userProfile,
    required this.previewCache,
    required this.onOpen,
    this.previewMode = ViewPreviewMode.cover,
    this.onPreviewModeChanged,
    this.onChangePage,
    this.thumbnailHeight = 224,
  });

  final ViewPB view;
  final UserProfilePB? userProfile;
  final FolderGalleryPreviewCache previewCache;
  final VoidCallback onOpen;
  final ViewPreviewMode previewMode;
  final ValueChanged<ViewPreviewMode>? onPreviewModeChanged;
  final VoidCallback? onChangePage;

  /// How tall the picture above the name is. A card on a dashboard is given
  /// whatever height the widget has, not the editor's fixed measure.
  final double thumbnailHeight;

  @override
  State<PagePreviewCard> createState() => _PagePreviewCardState();
}

class _PagePreviewCardState extends State<PagePreviewCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = FolderExplorerPalette.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final item = WorkspaceExplorerItem.fromView(widget.view);
    final base = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      palette.surface,
      isPaper: isPaper,
    );
    final surface = hovered
        ? Color.alphaBlend(
            palette.accent.withValues(alpha: 0.025),
            base,
          )
        : base;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: AnimatedContainer(
          key: const ValueKey('page-preview-card'),
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
          child: ViewerCard(
            color: surface,
            reactsToPointer: false,
            elevation: hovered
                ? ViewerCardElevation.raised
                : ViewerCardElevation.resting,
            child: LayoutBuilder(
              // Hosts that hand the card a height — a dashboard widget, a
              // narrow embed — get a picture that fits it instead of one that
              // spills past the bottom.
              builder: (context, constraints) {
                const footer = 66.0;
                final picture = constraints.hasBoundedHeight
                    ? (constraints.maxHeight - footer)
                        .clamp(48.0, widget.thumbnailHeight)
                    : widget.thumbnailHeight;
                return Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FolderGalleryPreviewThumbnail(
                          item: item,
                          view: widget.view,
                          preview: widget.previewCache.previewFor(
                            view: widget.view,
                            item: item,
                          ),
                          userProfile: widget.userProfile,
                          height: picture,
                          compact: true,
                          borderRadius: BorderRadius.zero,
                          previewMode: widget.previewMode,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(17, 12, 17, 12),
                            child: Row(
                              children: [
                                _PageIdentityIcon(view: widget.view),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.view.nameOrDefault,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.textPrimary,
                                          fontFamily: 'Inter',
                                          fontSize: 15,
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.22,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        LocaleKeys.commandPalette_pagePreview
                                            .tr(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.textMuted,
                                          fontFamily: 'Inter',
                                          fontSize: 10.5,
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                AnimatedOpacity(
                                  opacity: hovered ? 1 : 0,
                                  duration: const Duration(milliseconds: 140),
                                  child: Icon(
                                    Icons.arrow_outward_rounded,
                                    color: palette.textMuted,
                                    size: 17,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.onPreviewModeChanged != null ||
                        widget.onChangePage != null)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: IgnorePointer(
                          ignoring: !hovered,
                          child: AnimatedOpacity(
                            opacity: hovered ? 1 : 0,
                            duration: const Duration(milliseconds: 140),
                            child: _PagePreviewMenu(
                              previewMode: widget.previewMode,
                              onOpen: widget.onOpen,
                              onChangePage: widget.onChangePage,
                              onPreviewModeChanged: widget.onPreviewModeChanged,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PagePreviewMenu extends StatelessWidget {
  const _PagePreviewMenu({
    required this.previewMode,
    required this.onOpen,
    required this.onChangePage,
    required this.onPreviewModeChanged,
  });

  final ViewPreviewMode previewMode;
  final VoidCallback onOpen;
  final VoidCallback? onChangePage;
  final ValueChanged<ViewPreviewMode>? onPreviewModeChanged;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return AppMenuIconButton(
      key: const ValueKey('page-preview-options'),
      icon: Icons.more_horiz_rounded,
      iconSize: 18,
      iconColor: palette.textSecondary,
      tooltip: LocaleKeys.workspaceFolderExplorer_blockOptions.tr(),
      entries: () => [
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_open.tr(),
          icon: Icons.open_in_new_rounded,
          onSelected: onOpen,
        ),
        if (onPreviewModeChanged != null)
          AppMenuItem(
            label: previewMode == ViewPreviewMode.cover
                ? LocaleKeys.workspaceFolderExplorer_showContentPreview.tr()
                : LocaleKeys.workspaceFolderExplorer_showCoverPreview.tr(),
            icon: previewMode == ViewPreviewMode.cover
                ? Icons.article_rounded
                : Icons.photo_rounded,
            onSelected: () => onPreviewModeChanged?.call(
              previewMode == ViewPreviewMode.cover
                  ? ViewPreviewMode.content
                  : ViewPreviewMode.cover,
            ),
          ),
        if (onChangePage != null)
          AppMenuItem(
            label: LocaleKeys.workspaceFolderExplorer_chooseAnother.tr(),
            icon: Icons.swap_horiz_rounded,
            onSelected: () => onChangePage?.call(),
          ),
      ],
    );
  }
}

class _PageIdentityIcon extends StatelessWidget {
  const _PageIdentityIcon({required this.view});

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    final icon = view.icon.toEmojiIconData();
    return SizedBox.square(
      dimension: 22,
      child: icon.isNotEmpty
          ? RawEmojiIconWidget(
              emoji: icon,
              emojiSize: 22,
              lineHeight: 1,
            )
          : view.defaultIcon(size: const Size.square(20)),
    );
  }
}

class _PagePreviewPlaceholder extends StatelessWidget {
  const _PagePreviewPlaceholder({required this.onSelect});

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return _PagePreviewSelectionSurface(
      icon: Icons.article_rounded,
      title: LocaleKeys.document_mobilePageSelector_title.tr(),
      subtitle: LocaleKeys.commandPalette_pagePreview.tr(),
      onSelect: onSelect,
    );
  }
}

class _UnavailablePagePreview extends StatelessWidget {
  const _UnavailablePagePreview({required this.onSelect});

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return _PagePreviewSelectionSurface(
      icon: Icons.error_outline_rounded,
      title: LocaleKeys.workspaceFolderExplorer_previewUnavailable.tr(),
      subtitle: LocaleKeys.document_mobilePageSelector_title.tr(),
      onSelect: onSelect,
    );
  }
}

class _PagePreviewSelectionSurface extends StatelessWidget {
  const _PagePreviewSelectionSurface({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onSelect,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return ViewerCard(
      color: palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelect,
          hoverColor: palette.hover,
          child: Container(
            height: 88,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(icon, size: 21, color: palette.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontFamily: 'Inter',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
