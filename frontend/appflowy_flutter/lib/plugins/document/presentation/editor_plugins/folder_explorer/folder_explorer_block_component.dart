import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/trash/application/trash_listener.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_creator.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_collection_preview.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_picker_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/trash.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FolderExplorerBlockKeys {
  const FolderExplorerBlockKeys._();

  static const type = 'workspace_folder';
  static const folderId = 'folder_id';
  static const displayMode = 'display_mode';
  static const previewMode = 'preview_mode';
  static const width = 'width';
  static const height = 'height';
  static const globalKey = 'global_key';
}

enum FolderExplorerBlockDisplayMode {
  icon,
  explorer;

  static FolderExplorerBlockDisplayMode fromValue(Object? value) {
    return value == 'icon'
        ? FolderExplorerBlockDisplayMode.icon
        : FolderExplorerBlockDisplayMode.explorer;
  }
}

Node folderExplorerNode({
  String? folderId,
  FolderExplorerBlockDisplayMode displayMode =
      FolderExplorerBlockDisplayMode.explorer,
  ViewPreviewMode previewMode = ViewPreviewMode.cover,
}) {
  return Node(
    type: FolderExplorerBlockKeys.type,
    attributes: {
      FolderExplorerBlockKeys.folderId: folderId,
      FolderExplorerBlockKeys.displayMode: displayMode.name,
      FolderExplorerBlockKeys.previewMode: previewMode.name,
      FolderExplorerBlockKeys.width: 720.0,
      FolderExplorerBlockKeys.height: 390.0,
    },
  );
}

class FolderExplorerBlockComponentBuilder extends BlockComponentBuilder {
  FolderExplorerBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    final key =
        node.extraInfos?[FolderExplorerBlockKeys.globalKey] as GlobalKey?;
    return FolderExplorerBlockComponent(
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

class FolderExplorerBlockComponent extends BlockComponentStatefulWidget {
  const FolderExplorerBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<FolderExplorerBlockComponent> createState() =>
      FolderExplorerBlockComponentState();
}

class FolderExplorerBlockComponentState
    extends State<FolderExplorerBlockComponent>
    with BlockComponentConfigurable, SelectableMixin {
  static const service = WorkspaceItemService();

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late EditorState editorState =
      Provider.of<EditorState>(context, listen: false);
  final folderBlockKey = GlobalKey(debugLabel: FolderExplorerBlockKeys.type);
  final folderPickerController = PopoverController();
  Future<ViewPB?>? folderFuture;
  ViewListener? viewListener;
  TrashListener? trashListener;
  String? boundFolderId;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  void initState() {
    super.initState();
    trashListener = TrashListener()..start(trashUpdated: _didUpdateTrash);
    _loadFolder();
  }

  @override
  void didUpdateWidget(covariant FolderExplorerBlockComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = node.attributes[FolderExplorerBlockKeys.folderId];
    if (boundFolderId != id) {
      _loadFolder();
    }
  }

  @override
  void dispose() {
    viewListener?.stop();
    trashListener?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final folderId =
        node.attributes[FolderExplorerBlockKeys.folderId] as String?;
    Widget child = FutureBuilder<ViewPB?>(
      future: folderFuture,
      builder: (context, snapshot) {
        if (folderId == null || folderId.isEmpty) {
          return _buildEmpty();
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 72,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          );
        }
        final folder = snapshot.data;
        if (folder == null) {
          return _buildUnavailable();
        }
        return _buildFolder(folder);
      },
    );

    final mode = FolderExplorerBlockDisplayMode.fromValue(
      node.attributes[FolderExplorerBlockKeys.displayMode],
    );
    if (mode == FolderExplorerBlockDisplayMode.icon) {
      child = BlockSelectionContainer(
        node: node,
        delegate: this,
        listenable: editorState.selectionNotifier,
        remoteSelection: editorState.remoteSelections,
        blockColor: editorState.editorStyle.selectionColor,
        supportTypes: const [BlockSelectionType.block],
        child: child,
      );
    }

    child = Padding(
      padding: padding,
      child: RepaintBoundary(key: folderBlockKey, child: child),
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
      controller: folderPickerController,
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
      popupBuilder: (_) => WorkspaceFolderPickerMenu(
        selectedFolderId:
            node.attributes[FolderExplorerBlockKeys.folderId] as String?,
        onSelected: _selectFolder,
      ),
      child: child,
    );
  }

  Future<void> showFolderPicker() async {
    folderPickerController.show();
  }

  Future<void> _selectFolder(ViewPB folder) async {
    folderPickerController.close();
    if (!mounted) {
      return;
    }
    await _updateAttributes({FolderExplorerBlockKeys.folderId: folder.id});
    _loadFolder();
  }

  Widget _buildEmpty() {
    final palette = FolderExplorerPalette.of(context);
    return ViewerCard(
      color: palette.surface,
      borderRadius: BorderRadius.circular(11),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: showFolderPicker,
          child: Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  workspaceAddFolderIcon,
                  size: 22,
                  color: palette.accent,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        LocaleKeys.workspaceFolderExplorer_chooseFolder.tr(),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        LocaleKeys
                            .workspaceFolderExplorer_chooseFolderDescription
                            .tr(),
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: palette.textMuted,
                  size: 19,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnavailable() {
    final palette = FolderExplorerPalette.of(context);
    return ViewerCard(
      color: palette.surface,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.folder_off_rounded, color: palette.textMuted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                LocaleKeys.workspaceFolderExplorer_folderUnavailable.tr(),
                style: TextStyle(color: palette.textSecondary, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: showFolderPicker,
              child: Text(
                LocaleKeys.workspaceFolderExplorer_chooseAnother.tr(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolder(ViewPB folder) {
    final mode = FolderExplorerBlockDisplayMode.fromValue(
      node.attributes[FolderExplorerBlockKeys.displayMode],
    );
    return mode == FolderExplorerBlockDisplayMode.icon
        ? _buildCompact(folder)
        : _buildExplorer(folder);
  }

  Widget _buildCompact(ViewPB folder) {
    final palette = FolderExplorerPalette.of(context);
    final collectionKind = folder.collection?.kind;
    final subtitle = collectionKind == null
        ? LocaleKeys.workspaceFolderExplorer_workspaceFolder.tr()
        : CollectionRegistry.typeFor(collectionKind).label;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onSecondaryTapDown: (details) => unawaited(
          _showBlockContextMenu(folder, details.globalPosition),
        ),
        child: ViewerCard(
          color: palette.surface,
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              hoverColor: palette.hover,
              onTap: () => context.read<TabsBloc>().openPlugin(folder),
              child: Container(
                height: 54,
                padding: const EdgeInsets.only(left: 13, right: 4),
                child: Row(
                  children: [
                    WorkspaceItemIcon.fromView(
                      view: folder,
                      size: 21,
                      color: palette.accent,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            folder.name.isEmpty
                                ? LocaleKeys
                                    .workspaceFolderExplorer_untitledFolder
                                    .tr()
                                : folder.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildMenu(folder),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExplorer(ViewPB folder) {
    final width =
        (node.attributes[FolderExplorerBlockKeys.width] as num?)?.toDouble() ??
            720;
    return ResizableMedia(
      width: width,
      minWidth: 320,
      editable: editorState.editable,
      onResize: (value) =>
          _updateAttributes({FolderExplorerBlockKeys.width: value}),
      child: FolderCollectionPreview(
        key: ValueKey(folder.id),
        folder: folder,
        userProfile: context.read<DocumentBloc>().state.userProfilePB,
        onOpen: () => context.read<TabsBloc>().openPlugin(folder),
        onContextMenu: (position) =>
            unawaited(_showBlockContextMenu(folder, position)),
        hoverControl: _buildMenu(folder),
        previewMode: ViewPreviewMode.fromValue(
          node.attributes[FolderExplorerBlockKeys.previewMode],
        ),
      ),
    );
  }

  Widget _buildMenu(ViewPB folder) {
    return AppMenuIconButton(
      icon: Icons.more_horiz_rounded,
      iconSize: 18,
      tooltip: LocaleKeys.workspaceFolderExplorer_blockOptions.tr(),
      entries: () => _menuItems(folder),
    );
  }

  /// The same list behind the "⋯" button and behind a right click on the
  /// preview, so the block offers one set of options however it is asked.
  List<AppMenuEntry> _menuItems(ViewPB folder, {Offset? position}) {
    final displayMode = FolderExplorerBlockDisplayMode.fromValue(
      node.attributes[FolderExplorerBlockKeys.displayMode],
    );
    final previewMode = ViewPreviewMode.fromValue(
      node.attributes[FolderExplorerBlockKeys.previewMode],
    );

    AppMenuItem item(
      _FolderBlockAction action,
      IconData icon,
      String label,
    ) =>
        AppMenuItem(
          label: label,
          icon: icon,
          onSelected: () =>
              _handleMenuAction(folder, action, position: position),
        );

    return [
      if (editorState.editable) ...[
        item(
          _FolderBlockAction.addFile,
          workspaceAddFileIcon,
          LocaleKeys.workspaceFolderExplorer_addFile.tr(),
        ),
        item(
          _FolderBlockAction.newFolder,
          workspaceAddFolderIcon,
          LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
        ),
        const AppMenuSeparator(),
      ],
      item(
        _FolderBlockAction.open,
        Icons.open_in_new_rounded,
        LocaleKeys.workspaceFolderExplorer_openFolder.tr(),
      ),
      item(
        _FolderBlockAction.toggleMode,
        displayMode == FolderExplorerBlockDisplayMode.icon
            ? Icons.view_agenda_rounded
            : Icons.folder_rounded,
        displayMode == FolderExplorerBlockDisplayMode.icon
            ? LocaleKeys.workspaceFolderExplorer_showEmbeddedExplorer.tr()
            : LocaleKeys.workspaceFolderExplorer_showAsFolderIcon.tr(),
      ),
      if (displayMode == FolderExplorerBlockDisplayMode.explorer)
        item(
          _FolderBlockAction.togglePreview,
          previewMode == ViewPreviewMode.cover
              ? Icons.article_rounded
              : Icons.photo_rounded,
          previewMode == ViewPreviewMode.cover
              ? LocaleKeys.workspaceFolderExplorer_showContentPreview.tr()
              : LocaleKeys.workspaceFolderExplorer_showCoverPreview.tr(),
        ),
      item(
        _FolderBlockAction.changeFolder,
        Icons.swap_horiz_rounded,
        LocaleKeys.workspaceFolderExplorer_changeFolder.tr(),
      ),
    ];
  }

  Future<void> _showBlockContextMenu(ViewPB folder, Offset position) =>
      showAppMenu<void>(
        context: context,
        globalPosition: position,
        entries: _menuItems(folder, position: position),
      );

  Future<void> _handleMenuAction(
    ViewPB folder,
    _FolderBlockAction action, {
    Offset? position,
  }) async {
    switch (action) {
      case _FolderBlockAction.addFile:
        await _addFileToFolder(folder, position);
      case _FolderBlockAction.newFolder:
        await _createSubfolder(folder);
      case _FolderBlockAction.open:
        context.read<TabsBloc>().openPlugin(folder);
      case _FolderBlockAction.toggleMode:
        final current = FolderExplorerBlockDisplayMode.fromValue(
          node.attributes[FolderExplorerBlockKeys.displayMode],
        );
        await _updateAttributes({
          FolderExplorerBlockKeys.displayMode:
              current == FolderExplorerBlockDisplayMode.icon
                  ? FolderExplorerBlockDisplayMode.explorer.name
                  : FolderExplorerBlockDisplayMode.icon.name,
        });
      case _FolderBlockAction.togglePreview:
        final current = ViewPreviewMode.fromValue(
          node.attributes[FolderExplorerBlockKeys.previewMode],
        );
        await _updateAttributes({
          FolderExplorerBlockKeys.previewMode: current == ViewPreviewMode.cover
              ? ViewPreviewMode.content.name
              : ViewPreviewMode.cover.name,
        });
      case _FolderBlockAction.changeFolder:
        await showFolderPicker();
    }
  }

  /// Adds a file straight into the folder this block shows.
  ///
  /// The preview listens to its own child views, so the new card appears
  /// without the page being reloaded.
  Future<void> _addFileToFolder(ViewPB folder, Offset? position) async {
    final anchor = position ?? _blockAnchor();
    final kind = await showWorkspaceFileKindMenu(
      context: context,
      globalPosition: anchor,
      onCreateCollection: (collection) =>
          unawaited(_createCollectionInFolder(folder, collection)),
      onCreateDatabase: (kind) => unawaited(
        createWorkspaceDatabase(parentViewId: folder.id, kind: kind),
      ),
    );
    if (kind == null || !mounted) {
      return;
    }
    final created = await createWorkspaceFile(
      parentViewId: folder.id,
      action: kind,
    );
    if (created == null || !mounted) {
      return;
    }
    created.fold(
      (view) => context.read<TabsBloc>().openPlugin(view),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }

  Future<void> _createCollectionInFolder(
    ViewPB folder,
    CollectionKind kind,
  ) async {
    final created = await const CollectionService().createCollection(
      parentViewId: folder.id,
      kind: kind,
      name: CollectionRegistry.typeFor(kind).defaultName,
    );
    if (!mounted) {
      return;
    }
    created.fold(
      (view) => context.read<TabsBloc>().openPlugin(view),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }

  Future<void> _createSubfolder(ViewPB folder) async {
    const service = WorkspaceItemService();
    final created = await service.createFolder(
      parentViewId: folder.id,
      name: LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
    );
    if (!mounted) {
      return;
    }
    created.fold(
      (_) {},
      (error) => showSnackBarMessage(context, error.msg),
    );
  }

  Offset _blockAnchor() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return Offset.zero;
    }
    return box.localToGlobal(Offset(0, box.size.height));
  }

  void _loadFolder() {
    viewListener?.stop();
    viewListener = null;
    final folderId =
        node.attributes[FolderExplorerBlockKeys.folderId] as String?;
    boundFolderId = folderId;
    if (folderId == null || folderId.isEmpty) {
      folderFuture = Future<ViewPB?>.value();
      if (mounted) {
        setState(() {});
      }
      return;
    }
    folderFuture = _fetchFolder(folderId);
    viewListener = ViewListener(viewId: folderId)
      ..start(
        onViewUpdated: (view) {
          if (mounted && boundFolderId == view.id) {
            setState(() => folderFuture = Future.value(view));
          }
        },
        onViewMoveToTrash: (result) => result.onSuccess(
          (_) => _showFolderUnavailable(stopListening: false),
        ),
        onViewDeleted: (result) => result.onSuccess(
          (_) => _showFolderUnavailable(stopListening: true),
        ),
        onViewRestored: (result) =>
            result.onSuccess((_) => _reloadBoundFolder()),
      );
    if (mounted) {
      setState(() {});
    }
  }

  void _showFolderUnavailable({required bool stopListening}) {
    if (!mounted) {
      return;
    }
    if (stopListening) {
      viewListener?.stop();
      viewListener = null;
    }
    setState(() => folderFuture = Future<ViewPB?>.value());
  }

  Future<ViewPB?> _fetchFolder(String folderId) {
    return service.getView(folderId).then(
          (result) => result.fold((view) => view, (error) {
            Log.error(error);
            return null;
          }),
        );
  }

  void _reloadBoundFolder() {
    final folderId = boundFolderId;
    if (!mounted || folderId == null || folderId.isEmpty) {
      return;
    }
    setState(() => folderFuture = _fetchFolder(folderId));
  }

  void _didUpdateTrash(
    FlowyResult<List<TrashPB>, FlowyError> trashOrFailure,
  ) {
    trashOrFailure.fold(
      (trash) {
        final folderId = boundFolderId;
        if (folderId == null || folderId.isEmpty || !mounted) {
          return;
        }
        if (trash.any((item) => item.id == folderId)) {
          _showFolderUnavailable(stopListening: false);
        } else {
          _reloadBoundFolder();
        }
      },
      Log.error,
    );
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
    final renderBox = folderBlockKey.currentContext?.findRenderObject();
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
    final renderBox = folderBlockKey.currentContext?.findRenderObject();
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

enum _FolderBlockAction {
  addFile,
  newFolder,
  open,
  toggleMode,
  togglePreview,
  changeFolder,
}
