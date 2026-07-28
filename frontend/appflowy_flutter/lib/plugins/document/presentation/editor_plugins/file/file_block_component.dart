import 'dart:io';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/show_mobile_bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/widgets/flowy_option_tile.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_drop_manager.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/youtube_embed_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/youtube_video_download.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/appflowy_cloud_auth.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:string_validator/string_validator.dart';
import 'package:universal_platform/universal_platform.dart';

import 'file_block_menu.dart';
import 'archive/archive_explorer.dart';
import 'file_media_player.dart';
import 'file_preview.dart';
import 'file_preview_kind.dart';
import 'file_upload_menu.dart';
import 'office/office_document_view.dart';
import 'pdf_preview.dart';
import 'pdf_preview_scroll_physics.dart';

class FileBlockKeys {
  const FileBlockKeys._();

  static const String type = 'file';

  /// The src of the file.
  ///
  /// The value is a String.
  /// It can be a url for a network file or a local file path.
  ///
  static const String url = 'url';

  /// The name of the file.
  ///
  /// The value is a String.
  ///
  static const String name = 'name';

  /// The type of the url.
  ///
  /// The value is a FileUrlType enum.
  ///
  static const String urlType = 'url_type';

  /// The date of the file upload.
  ///
  /// The value is a timestamp in ms.
  ///
  static const String uploadedAt = 'uploaded_at';

  /// The user who uploaded the file.
  ///
  /// The value is a String, in form of user id.
  ///
  static const String uploadedBy = 'uploaded_by';

  static const String width = 'width';
  static const String height = 'height';
  static const String displayMode = 'display_mode';
  static const String previewMetadata = 'preview_metadata';
  static const String workspaceFileId = 'workspace_file_id';

  /// The GlobalKey of the FileBlockComponentState.
  ///
  /// **Note: This value is used in extraInfos of the Node, not in the attributes.**
  static const String globalKey = 'global_key';
  static const String pickerAllowedExtensions = 'picker_allowed_extensions';
}

enum FileUrlType {
  local,
  network,
  cloud;

  static FileUrlType fromIntValue(int value) {
    switch (value) {
      case 0:
        return FileUrlType.local;
      case 1:
        return FileUrlType.network;
      case 2:
        return FileUrlType.cloud;
      default:
        throw UnimplementedError();
    }
  }

  int toIntValue() {
    switch (this) {
      case FileUrlType.local:
        return 0;
      case FileUrlType.network:
        return 1;
      case FileUrlType.cloud:
        return 2;
    }
  }

  FileUploadTypePB toFileUploadTypePB() {
    switch (this) {
      case FileUrlType.local:
        return FileUploadTypePB.LocalFile;
      case FileUrlType.network:
        return FileUploadTypePB.NetworkFile;
      case FileUrlType.cloud:
        return FileUploadTypePB.CloudFile;
    }
  }
}

Node fileNode({
  required String url,
  FileUrlType type = FileUrlType.local,
  String? name,
}) {
  return Node(
    type: FileBlockKeys.type,
    attributes: {
      FileBlockKeys.url: url,
      FileBlockKeys.urlType: type.toIntValue(),
      FileBlockKeys.name: name,
      FileBlockKeys.uploadedAt: DateTime.now().millisecondsSinceEpoch,
    },
  );
}

Map<String, dynamic> workspaceFileBlockAttributes({
  required WorkspaceFileReference reference,
  required bool showPreview,
  int? embeddedAt,
}) {
  return {
    FileBlockKeys.url: reference.url,
    FileBlockKeys.urlType:
        (reference.isLocal ? FileUrlType.local : FileUrlType.cloud)
            .toIntValue(),
    FileBlockKeys.name: reference.name,
    FileBlockKeys.uploadedAt:
        embeddedAt ?? DateTime.now().millisecondsSinceEpoch,
    FileBlockKeys.displayMode: showPreview ? 'preview' : 'file',
    FileBlockKeys.workspaceFileId: reference.viewId,
  };
}

/// Points [node] at the video that was downloaded for offline viewing.
///
/// This runs after a background download, so the block that started it may
/// already be gone and the document may already be closed.
Future<void> _saveOfflineYoutubeVideo({
  required EditorState editorState,
  required Node node,
  required InternalYoutubeVideo video,
  required bool? showPreview,
}) async {
  // A detached node has an empty path, so updating it would target the root.
  if (editorState.isDisposed || node.parent == null) {
    // Nothing can reference the file any more, don't leave it on disk.
    final file = File(video.path);
    if (await file.exists()) {
      await file.delete();
    }
    return;
  }

  final transaction = editorState.transaction
    ..updateNode(node, {
      FileBlockKeys.url: video.path,
      FileBlockKeys.urlType: FileUrlType.local.toIntValue(),
      FileBlockKeys.name: video.name,
      FileBlockKeys.uploadedAt: DateTime.now().millisecondsSinceEpoch,
      if (showPreview != null)
        FileBlockKeys.displayMode: showPreview ? 'preview' : 'file',
    });
  await editorState.apply(transaction);

  showToastNotification(
    message: LocaleKeys.grid_media_downloadSuccess.tr(),
  );
}

class FileBlockComponentBuilder extends BlockComponentBuilder {
  FileBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    final extraInfos = node.extraInfos;
    final key = extraInfos?[FileBlockKeys.globalKey] as GlobalKey?;

    return FileBlockComponent(
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

class FileBlockComponent extends BlockComponentStatefulWidget {
  const FileBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  static const uploadDragKey = 'FileUploadMenu';

  @override
  State<FileBlockComponent> createState() => FileBlockComponentState();
}

class FileBlockComponentState extends State<FileBlockComponent>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  late EditorDropManagerState? dropManagerState = UniversalPlatform.isMobile
      ? null
      : context.read<EditorDropManagerState?>();

  final fileKey = GlobalKey();
  final showActionsNotifier = ValueNotifier<bool>(false);
  final controller = PopoverController();
  final menuController = PopoverController();
  final previewScrollController = PdfPreviewScrollController();

  late final editorState = Provider.of<EditorState>(context, listen: false);

  bool alwaysShowMenu = false;
  bool isDragging = false;
  bool isHovering = false;

  /// The real ratio of the playing video, once the decoder has reported it.
  double? videoAspectRatio;

  /// Portrait clips get a phone-sized frame instead of a widescreen one, so
  /// they fill it end to end rather than sitting between black bars.
  double _defaultVideoWidth(double? aspectRatio) =>
      aspectRatio != null && aspectRatio < 1
          ? defaultPortraitMediaWidth
          : defaultVisualMediaWidth;

  void _handleVideoAspectRatio(double aspectRatio) {
    if (!mounted || videoAspectRatio == aspectRatio) {
      return;
    }
    setState(() => videoAspectRatio = aspectRatio);
  }

  @override
  void didChangeDependencies() {
    if (!UniversalPlatform.isMobile) {
      dropManagerState = context.read<EditorDropManagerState?>();
    }
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final url = node.attributes[FileBlockKeys.url];
    final FileUrlType urlType =
        FileUrlType.fromIntValue(node.attributes[FileBlockKeys.urlType] ?? 0);
    final name = node.attributes[FileBlockKeys.name] as String?;
    final mediaKind = fileMediaKind(name, url);
    final isYoutubeVideo = url != null && isYoutubeVideoUrl(url);
    final previewKind = name == null ? null : filePreviewKindFromName(name);
    final officePreview = name != null && isOfficeFile(name);
    final showPreview =
        node.attributes[FileBlockKeys.displayMode] == 'preview' &&
            name != null &&
            supportsEmbeddedFilePreview(name);

    Widget child = isYoutubeVideo
        ? _buildYoutubePlayer(url)
        : mediaKind != null && url?.isNotEmpty == true
            ? _buildMediaPlayer(url!, name ?? '', mediaKind, urlType)
            : showPreview && url?.isNotEmpty == true
                ? officePreview
                    ? _buildOfficePreview(url!, name, urlType)
                    : previewKind == FilePreviewKind.archive
                        ? _buildArchivePreview(url!, name, urlType)
                        : _buildFilePreview(url!, name, previewKind!, urlType)
                : _buildFileChip(context, url, name, urlType);

    if (UniversalPlatform.isDesktopOrWeb) {
      if (url == null || url.isEmpty) {
        child = DropTarget(
          enable: dropManagerState?.isDropEnabled == true ||
              dropManagerState?.contains(FileBlockKeys.type) == true,
          onDragEntered: (_) {
            if (dropManagerState?.isDropEnabled == true) {
              dropManagerState?.add(FileBlockKeys.type);
              setState(() => isDragging = true);
            }
          },
          onDragExited: (_) {
            if (dropManagerState?.contains(FileBlockKeys.type) == true) {
              dropManagerState?.remove(FileBlockKeys.type);
              setState(() => isDragging = false);
            }
          },
          onDragDone: (details) {
            dropManagerState?.remove(FileBlockKeys.type);
            insertFileFromLocal(details.files);
          },
          child: AppFlowyPopover(
            controller: controller,
            direction: PopoverDirection.bottomWithCenterAligned,
            constraints: const BoxConstraints(
              maxWidth: 480,
              maxHeight: 340,
              minHeight: 80,
            ),
            clickHandler: PopoverClickHandler.gestureDetector,
            onOpen: () => dropManagerState?.add(
              FileBlockComponent.uploadDragKey,
            ),
            onClose: () => dropManagerState?.remove(
              FileBlockComponent.uploadDragKey,
            ),
            popupBuilder: (_) => FileUploadMenu(
              onInsertLocalFile: insertFileFromLocal,
              onInsertLocalFileWithOptions: insertFileFromLocal,
              onInsertNetworkFileWithOptions: (url, saveOffline) =>
                  insertNetworkFile(url, saveOffline),
              onInsertNetworkFileWithPreviewOptions:
                  (url, saveOffline, showPreview) =>
                      insertNetworkFile(url, saveOffline, showPreview),
              onInsertWorkspaceFile: (file, showPreview) {
                controller.close();
                return insertFileFromWorkspace(file, showPreview);
              },
              defaultShowPreview:
                  node.attributes[FileBlockKeys.displayMode] == 'preview',
              allowedExtensions: _pickerAllowedExtensions,
            ),
            child: child,
          ),
        );
      }

      final paddedChild = Padding(
        key: fileKey,
        padding: padding,
        child: child,
      );
      child = showPreview
          ? paddedChild
          : BlockSelectionContainer(
              node: node,
              delegate: this,
              listenable: editorState.selectionNotifier,
              blockColor: editorState.editorStyle.selectionColor,
              supportTypes: const [BlockSelectionType.block],
              child: paddedChild,
            );
    } else {
      return Padding(
        key: fileKey,
        padding: padding,
        child: MobileBlockActionButtons(
          node: widget.node,
          editorState: editorState,
          child: child,
        ),
      );
    }

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    if (!UniversalPlatform.isDesktopOrWeb) {
      // show a fixed menu on mobile
      child = MobileBlockActionButtons(
        node: node,
        editorState: editorState,
        extendActionWidgets: _buildExtendActionWidgets(context),
        child: child,
      );
    }

    return child;
  }

  Widget _buildMediaPlayer(
    String url,
    String name,
    FileMediaKind kind,
    FileUrlType urlType,
  ) {
    final width = node.attributes[FileBlockKeys.width]?.toDouble() ??
        (kind == FileMediaKind.audio
            ? defaultAudioMediaWidth
            : _defaultVideoWidth(videoAspectRatio));
    return ResizableMedia(
      width: width,
      minWidth: kind == FileMediaKind.audio ? 320 : 240,
      editable: editorState.editable,
      onResize: _saveMediaWidth,
      child: MouseRegion(
        onEnter: (_) {
          isHovering = true;
          showActionsNotifier.value = true;
        },
        onExit: (_) {
          isHovering = false;
          if (!alwaysShowMenu) {
            showActionsNotifier.value = false;
          }
        },
        child: Stack(
          children: [
            FileMediaPlayer(
              url: url,
              name: name,
              kind: kind,
              httpHeaders: _httpHeadersFor(urlType),
              onAspectRatioChanged: _handleVideoAspectRatio,
            ),
            if (UniversalPlatform.isDesktopOrWeb) _buildFileMenuOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildYoutubePlayer(String url) {
    final width = node.attributes[FileBlockKeys.width]?.toDouble() ??
        _defaultVideoWidth(
          videoAspectRatio ?? initialYoutubeAspectRatio(url),
        );
    return ResizableMedia(
      width: width,
      editable: editorState.editable,
      onResize: _saveMediaWidth,
      child: MouseRegion(
        onEnter: (_) {
          isHovering = true;
          showActionsNotifier.value = true;
        },
        onExit: (_) {
          isHovering = false;
          if (!alwaysShowMenu) {
            showActionsNotifier.value = false;
          }
        },
        child: Stack(
          children: [
            YoutubeEmbedPlayer(
              url: url,
              onAspectRatioChanged: _handleVideoAspectRatio,
            ),
            _buildOfflineDownloadIndicator(),
            if (UniversalPlatform.isDesktopOrWeb) _buildFileMenuOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildFileMenuOverlay() {
    final menuSurface = AppFlowyTheme.of(context).surfaceColorScheme.primary;
    return Positioned(
      top: 8,
      right: 8,
      child: ValueListenableBuilder<bool>(
        valueListenable: showActionsNotifier,
        builder: (_, showActions, __) {
          if (!showActions) {
            return const SizedBox.shrink();
          }
          return AppFlowyPopover(
            controller: menuController,
            triggerActions: PopoverTriggerFlags.none,
            direction: PopoverDirection.bottomWithRightAligned,
            onOpen: () {
              alwaysShowMenu = true;
              showActionsNotifier.value = true;
            },
            onClose: () {
              alwaysShowMenu = false;
              if (!isHovering) {
                showActionsNotifier.value = false;
              }
            },
            popupBuilder: (_) => FileBlockMenu(
              controller: menuController,
              node: node,
              editorState: editorState,
            ),
            child: GestureDetector(
              onTap: _showMediaMenu,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: menuSurface,
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                ),
                child: const FileMenuTrigger(),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Shows how far the background "save for offline viewing" download got,
  /// without ever holding up the embed itself.
  Widget _buildOfflineDownloadIndicator() {
    final download = YoutubeOfflineDownloadManager.instance.progressOf(node.id);
    if (download == null) {
      return const SizedBox.shrink();
    }

    final theme = AppFlowyTheme.of(context);
    final label = LocaleKeys.document_plugins_file_savingForOfflineViewing.tr();
    return Positioned(
      left: 8,
      top: 8,
      child: ValueListenableBuilder<YoutubeOfflineDownloadState>(
        valueListenable: download,
        builder: (_, state, __) {
          final progress = state.progress;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surfaceColorScheme.primary,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress,
                    ),
                  ),
                  const HSpace(6),
                  FlowyText(
                    progress == null
                        ? label
                        : '$label · ${(progress * 100).round()}%',
                    fontSize: 12,
                    color: theme.textColorScheme.primary,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilePreview(
    String url,
    String name,
    FilePreviewKind kind,
    FileUrlType urlType,
  ) {
    final width = node.attributes[FileBlockKeys.width]?.toDouble() ??
        defaultVisualMediaWidth;
    final height = node.attributes[FileBlockKeys.height]?.toDouble() ??
        defaultFilePreviewHeight(kind);
    final preview = ResizableMedia(
      width: width,
      minWidth: kind == FilePreviewKind.code || kind == FilePreviewKind.pdf
          ? 420
          : 320,
      height: height,
      minHeight: switch (kind) {
        FilePreviewKind.code => 260,
        FilePreviewKind.archive => 300,
        _ => 240,
      },
      editable: editorState.editable,
      onResize: _saveMediaWidth,
      onResizeHeight: _saveMediaHeight,
      frameBuilder: kind.usesFrameScrollGuard
          ? (frame) => PremiumScrollExclusion(
                child: PdfEmbedScrollGuard(
                  onPointerSignal: previewScrollController.handlePointerSignal,
                  onPointerPanZoomStart:
                      previewScrollController.handlePointerPanZoomStart,
                  onPointerPanZoomUpdate:
                      previewScrollController.handlePointerPanZoomUpdate,
                  onPointerPanZoomEnd:
                      previewScrollController.handlePointerPanZoomEnd,
                  child: frame,
                ),
              )
          : null,
      child: FutureBuilder<File>(
        future: materializeMediaFile(
          source: url,
          name: name,
          httpHeaders: _httpHeadersFor(urlType),
        ),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final file = snapshot.data;
          if (file == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return FilePreview(
            file: file,
            name: name,
            kind: kind,
            editable: editorState.editable &&
                FileUrlType.fromIntValue(
                      node.attributes[FileBlockKeys.urlType] ?? 0,
                    ) ==
                    FileUrlType.local,
            metadata: Map<String, dynamic>.from(
              node.attributes[FileBlockKeys.previewMetadata] as Map? ??
                  const {},
            ),
            onMetadataChanged: _savePreviewMetadata,
            height: height,
            toolbarTrailing:
                UniversalPlatform.isDesktopOrWeb && kind != FilePreviewKind.pdf
                    ? _buildPreviewMenu()
                    : null,
            pdfMenuBuilder:
                UniversalPlatform.isDesktopOrWeb && kind == FilePreviewKind.pdf
                    ? _buildPdfMenu
                    : null,
            previewScrollController:
                kind.usesFrameScrollGuard ? previewScrollController : null,
          );
        },
      ),
    );
    // A preview can own the keyboard — the code editor, the source editor, a
    // PDF's page field. While it does, the document must not: the editor's
    // backspace command runs before the app's text shortcuts, and a collapsed
    // selection on this deltaless block would delete the whole embed.
    return _wrapInteractivePreview(preview);
  }

  /// An archive embeds as the same wall of cards it fills a window with, in a
  /// frame the reader can size.
  Widget _buildArchivePreview(
    String url,
    String name,
    FileUrlType urlType,
  ) {
    final width = node.attributes[FileBlockKeys.width]?.toDouble() ??
        defaultVisualMediaWidth;
    final height = node.attributes[FileBlockKeys.height]?.toDouble() ??
        defaultFilePreviewHeight(FilePreviewKind.archive);
    return _wrapInteractivePreview(
      ResizableMedia(
        width: width,
        minWidth: 320,
        height: height,
        minHeight: 300,
        editable: editorState.editable,
        onResize: _saveMediaWidth,
        onResizeHeight: _saveMediaHeight,
        child: FutureBuilder<File>(
          future: materializeMediaFile(
            source: url,
            name: name,
            httpHeaders: _httpHeadersFor(urlType),
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final file = snapshot.data;
            if (file == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return ArchiveExplorer(
              key: ValueKey('archive_${node.id}_$url'),
              file: file,
              name: name,
              editable: editorState.editable && urlType == FileUrlType.local,
              toolbarTrailing:
                  UniversalPlatform.isDesktopOrWeb ? _buildPreviewMenu() : null,
            );
          },
        ),
      ),
    );
  }

  Widget _buildOfficePreview(
    String url,
    String name,
    FileUrlType urlType,
  ) {
    final width = node.attributes[FileBlockKeys.width]?.toDouble() ??
        defaultVisualMediaWidth;
    final height = node.attributes[FileBlockKeys.height]?.toDouble() ?? 520.0;
    final preview = ResizableMedia(
      width: width,
      minWidth: 420,
      height: height,
      minHeight: 320,
      editable: editorState.editable,
      onResize: _saveMediaWidth,
      onResizeHeight: _saveMediaHeight,
      footer: UniversalPlatform.isDesktopOrWeb
          ? _buildOfficePreviewFooter(name)
          : null,
      child: MouseRegion(
        onEnter: (_) {
          isHovering = true;
          showActionsNotifier.value = true;
        },
        onExit: (_) {
          isHovering = false;
          if (!alwaysShowMenu) {
            showActionsNotifier.value = false;
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<File>(
              future: materializeMediaFile(
                source: url,
                name: name,
                httpHeaders: _httpHeadersFor(urlType),
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final file = snapshot.data;
                if (file == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return OfficeDocumentView(
                  key: ValueKey('office_${node.id}_${name}_$url'),
                  file: file,
                  name: name,
                  source: url,
                  editable:
                      editorState.editable && urlType != FileUrlType.network,
                  // A CSV can still be read without an Office server.
                  fallbackBuilder: filePreviewKindFromName(name) == null
                      ? null
                      : (context) => FilePreview(
                            file: file,
                            name: name,
                            kind: filePreviewKindFromName(name)!,
                            metadata: Map<String, dynamic>.from(
                              node.attributes[FileBlockKeys.previewMetadata]
                                      as Map? ??
                                  const {},
                            ),
                            onMetadataChanged: _savePreviewMetadata,
                            editable: editorState.editable &&
                                urlType == FileUrlType.local,
                            height: height,
                          ),
                );
              },
            ),
          ],
        ),
      ),
    );
    return _wrapInteractivePreview(preview);
  }

  Widget _buildOfficePreviewFooter(String name) {
    final theme = AppFlowyTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 8),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            Icon(
              fileIconForName(name),
              size: 17,
              color: theme.iconColorScheme.secondary,
            ),
            const HSpace(6),
            Expanded(
              child: FlowyText(
                name,
                overflow: TextOverflow.ellipsis,
                color: theme.textColorScheme.secondary,
              ),
            ),
            _buildPreviewMenu(),
          ],
        ),
      ),
    );
  }

  Widget _wrapInteractivePreview(Widget preview) {
    return FocusScope(
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          editorState.selection = null;
        }
      },
      child: preview,
    );
  }

  Widget _buildPreviewMenu() {
    final theme = AppFlowyTheme.of(context);
    final hoverColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0x12FFFFFF)
        : const Color(0x0F302D28);
    return AppFlowyPopover(
      controller: menuController,
      triggerActions: PopoverTriggerFlags.none,
      direction: PopoverDirection.bottomWithRightAligned,
      popupBuilder: (_) => FileBlockMenu(
        controller: menuController,
        node: node,
        editorState: editorState,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: menuController.show,
        child: Tooltip(
          message: 'More actions',
          child: SizedBox.square(
            dimension: 30,
            child: FlowyHover(
              resetHoverOnRebuild: false,
              style: HoverStyle(
                hoverColor: hoverColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.more_horiz_rounded,
                size: 19,
                color: theme.iconColorScheme.secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPdfMenu(
    BuildContext menuContext,
    VoidCallback closeMenu,
  ) {
    return FileBlockMenu(
      onClose: closeMenu,
      actionContext: context,
      showDownload: false,
      node: node,
      editorState: editorState,
    );
  }

  void _savePreviewMetadata(Map<String, dynamic> metadata) {
    final transaction = editorState.transaction
      ..updateNode(node, {FileBlockKeys.previewMetadata: metadata});
    editorState.apply(transaction);
  }

  void _saveMediaWidth(double width) {
    final transaction = editorState.transaction
      ..updateNode(node, {FileBlockKeys.width: width});
    editorState.apply(transaction);
  }

  void _saveMediaHeight(double height) {
    final transaction = editorState.transaction
      ..updateNode(node, {FileBlockKeys.height: height});
    editorState.apply(transaction);
  }

  void _showMediaMenu() {
    // Keep the anchor mounted before opening the overlay. Waiting for the
    // popover's onOpen callback is too late when the overlay triggers onExit.
    alwaysShowMenu = true;
    showActionsNotifier.value = true;
    menuController.show();
  }

  Future<void> _openFile(
    BuildContext context,
    FileUrlType urlType,
    String url,
  ) async {
    var launchTarget = url;
    if (urlType == FileUrlType.cloud) {
      try {
        final file = await materializeMediaFile(
          source: url,
          name: node.attributes[FileBlockKeys.name] as String? ?? 'file',
          httpHeaders: _httpHeadersFor(urlType),
        );
        launchTarget = file.path;
      } on HttpException catch (error) {
        if (context.mounted) {
          showSnackBarMessage(context, error.message);
        }
        return;
      } on FileSystemException catch (error) {
        if (context.mounted) {
          showSnackBarMessage(context, error.message);
        }
        return;
      } on FormatException catch (error) {
        if (context.mounted) {
          showSnackBarMessage(context, error.message);
        }
        return;
      }
    }
    if (context.mounted) {
      await afLaunchUrlString(launchTarget, context: context);
    }
  }

  Map<String, String> _httpHeadersFor(FileUrlType urlType) =>
      urlType == FileUrlType.cloud
          ? appFlowyCloudAuthHeaders(
              context.read<DocumentBloc>().state.userProfilePB,
            )
          : const {};

  void _openMenu() {
    if (UniversalPlatform.isDesktopOrWeb) {
      controller.show();
      dropManagerState?.add(FileBlockComponent.uploadDragKey);
    } else {
      editorState.updateSelectionWithReason(null, extraInfo: {});
      showUploadFileMobileMenu();
    }
  }

  /// The card a file wears when it is not previewed inline.
  ///
  /// An attachment is one small object in the text, not a band across it: the
  /// card hugs its contents, and the glyph in front of the name says what kind
  /// of file it is. The placeholder keeps its full width, because that is the
  /// target files are dropped onto.
  Widget _buildFileChip(
    BuildContext context,
    String? url,
    String? name,
    FileUrlType urlType,
  ) {
    final palette = FolderExplorerPalette.of(context);
    final hasFile = url != null && url.isNotEmpty;
    final label = hasFile
        ? (name?.isNotEmpty == true ? name! : url)
        : isDragging
            ? LocaleKeys.document_plugins_file_placeholderDragging.tr()
            : LocaleKeys.document_plugins_file_placeholderText.tr();

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      height: hasFile ? 52 : 56,
      padding: EdgeInsets.only(left: 9, right: hasFile ? 9 : 14),
      decoration: BoxDecoration(
        color: isHovering
            ? Color.alphaBlend(palette.hover, palette.surface)
            : palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDragging ? palette.accent : palette.border,
          width: isDragging ? 1.4 : 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: hasFile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Icon(
              fileIconForName(name),
              size: 19,
              color: palette.accent,
            ),
          ),
          const HSpace(11),
          Flexible(
            child: FlowyText(
              label,
              fontSize: 14,
              fontWeight: hasFile ? FontWeight.w500 : FontWeight.w400,
              overflow: TextOverflow.ellipsis,
              color: hasFile ? palette.textPrimary : palette.textMuted,
            ),
          ),
          if (hasFile && UniversalPlatform.isDesktopOrWeb) ...[
            const HSpace(6),
            _buildFileChipMenu(),
          ],
        ],
      ),
    );

    card = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => isHovering = true);
        showActionsNotifier.value = true;
      },
      onExit: (_) {
        setState(() => isHovering = false);
        if (!alwaysShowMenu) {
          showActionsNotifier.value = false;
        }
      },
      opaque: false,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap:
            hasFile ? () async => _openFile(context, urlType, url) : _openMenu,
        child: card,
      ),
    );

    if (!hasFile) {
      return card;
    }
    // Long names ellipsize rather than dragging the card across the page.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: card,
      ),
    );
  }

  /// The three dot menu inside the compact card.
  ///
  /// It always occupies its place and only fades in, so the card does not
  /// change width the moment the pointer arrives.
  Widget _buildFileChipMenu() {
    return ValueListenableBuilder<bool>(
      valueListenable: showActionsNotifier,
      builder: (_, value, child) => AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: value ? 1 : 0,
        child: IgnorePointer(ignoring: !value, child: child),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: menuController.show,
        child: AppFlowyPopover(
          controller: menuController,
          triggerActions: PopoverTriggerFlags.none,
          direction: PopoverDirection.bottomWithRightAligned,
          onClose: () {
            setState(() {
              alwaysShowMenu = false;
              showActionsNotifier.value = false;
            });
          },
          popupBuilder: (_) {
            alwaysShowMenu = true;
            return FileBlockMenu(
              controller: menuController,
              node: node,
              editorState: editorState,
            );
          },
          child: const FileMenuTrigger(),
        ),
      ),
    );
  }

  // only used on mobile platform
  List<Widget> _buildExtendActionWidgets(BuildContext context) {
    final String? url = widget.node.attributes[FileBlockKeys.url];
    if (url == null || url.isEmpty) {
      return [];
    }

    final urlType = FileUrlType.fromIntValue(
      widget.node.attributes[FileBlockKeys.urlType] ?? 0,
    );

    final name =
        widget.node.attributes[FileBlockKeys.name] as String? ?? 'media';
    final shareAsLink =
        urlType == FileUrlType.network && isYoutubeVideoUrl(url);
    final httpHeaders = _httpHeadersFor(urlType);

    return [
      if (supportsEmbeddedFilePreview(name))
        FlowyOptionTile.text(
          showTopBorder: false,
          text: node.attributes[FileBlockKeys.displayMode] == 'preview'
              ? 'Show as file'
              : 'Show preview',
          leftIcon: const Icon(Icons.preview_outlined),
          onTap: () {
            context.pop();
            final mode = node.attributes[FileBlockKeys.displayMode] == 'preview'
                ? 'file'
                : 'preview';
            final transaction = editorState.transaction
              ..updateNode(node, {FileBlockKeys.displayMode: mode});
            editorState.apply(transaction);
          },
        ),
      FlowyOptionTile.text(
        showTopBorder: false,
        text: LocaleKeys.button_download.tr(),
        leftIcon: const FlowySvg(FlowySvgs.download_s),
        onTap: () async {
          context.pop();
          await downloadMedia(
            source: url,
            name: name,
            httpHeaders: httpHeaders,
          );
        },
      ),
      FlowyOptionTile.text(
        showTopBorder: false,
        text: LocaleKeys.editor_copyLink.tr(),
        leftIcon: const FlowySvg(
          FlowySvgs.m_field_copy_s,
        ),
        onTap: () async {
          context.pop();
          await copyMedia(
            source: url,
            name: name,
            shareAsLink: shareAsLink,
            httpHeaders: httpHeaders,
          );
        },
      ),
      FlowyOptionTile.text(
        showTopBorder: false,
        text: LocaleKeys.button_share.tr(),
        leftIcon: const FlowySvg(FlowySvgs.share_s),
        onTap: () async {
          context.pop();
          await shareMedia(
            source: url,
            name: name,
            shareAsLink: shareAsLink,
            httpHeaders: httpHeaders,
          );
        },
      ),
    ];
  }

  void showUploadFileMobileMenu() {
    showMobileBottomSheet(
      context,
      title: LocaleKeys.document_plugins_file_name.tr(),
      showHeader: true,
      showCloseButton: true,
      showDragHandle: true,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.only(top: 12.0),
          constraints: const BoxConstraints(
            maxHeight: 340,
            minHeight: 80,
          ),
          child: FileUploadMenu(
            onInsertLocalFile: (file) async {
              context.pop();
              await insertFileFromLocal(file);
            },
            onInsertLocalFileWithOptions: (file, showPreview) async {
              context.pop();
              await insertFileFromLocal(file, showPreview);
            },
            onInsertNetworkFileWithOptions: (url, saveOffline) async {
              context.pop();
              await insertNetworkFile(url, saveOffline);
            },
            onInsertNetworkFileWithPreviewOptions:
                (url, saveOffline, showPreview) async {
              context.pop();
              await insertNetworkFile(url, saveOffline, showPreview);
            },
            onInsertWorkspaceFile: (file, showPreview) async {
              context.pop();
              await insertFileFromWorkspace(file, showPreview);
            },
            defaultShowPreview:
                node.attributes[FileBlockKeys.displayMode] == 'preview',
            allowedExtensions: _pickerAllowedExtensions,
          ),
        );
      },
    );
  }

  Future<void> insertFileFromLocal(
    List<XFile> files, [
    bool? showPreview,
  ]) async {
    if (files.isEmpty) return;

    final file = files.first;
    if (!fileNameMatchesExtensions(file.name, _pickerAllowedExtensions)) {
      _showUnsupportedFileType(file.name);
      return;
    }
    final path = file.path;
    final documentBloc = context.read<DocumentBloc>();
    final isLocalMode = documentBloc.isLocalMode;
    final urlType = isLocalMode ? FileUrlType.local : FileUrlType.cloud;

    String? url;
    String? errorMsg;
    if (isLocalMode) {
      url = await saveFileToLocalStorage(path);
    } else {
      final result =
          await saveFileToCloudStorage(path, documentBloc.documentId);
      url = result.$1;
      errorMsg = result.$2;
    }

    if (errorMsg != null && mounted) {
      return showSnackBarMessage(context, errorMsg);
    }
    if (url == null) {
      if (mounted) {
        showSnackBarMessage(
          context,
          'AppFlowy could not save ${file.name}.',
        );
      }
      return;
    }

    // Remove the file block from the drop state manager
    dropManagerState?.remove(FileBlockKeys.type);

    final transaction = editorState.transaction;
    transaction.updateNode(widget.node, {
      FileBlockKeys.url: url,
      FileBlockKeys.urlType: urlType.toIntValue(),
      FileBlockKeys.name: file.name,
      FileBlockKeys.uploadedAt: DateTime.now().millisecondsSinceEpoch,
      if (showPreview != null)
        FileBlockKeys.displayMode: showPreview ? 'preview' : 'file',
    });
    await editorState.apply(transaction);
  }

  Future<void> insertFileFromWorkspace(
    ViewPB view,
    bool showPreview,
  ) async {
    final reference = view.workspaceFileReference;
    if (reference == null) {
      return showSnackBarMessage(
        context,
        'This workspace file is no longer available.',
      );
    }
    if (!fileNameMatchesExtensions(
      reference.name,
      _pickerAllowedExtensions,
    )) {
      _showUnsupportedFileType(reference.name);
      return;
    }

    dropManagerState?.remove(FileBlockKeys.type);

    final transaction = editorState.transaction
      ..updateNode(
        widget.node,
        workspaceFileBlockAttributes(
          reference: reference,
          showPreview: showPreview,
        ),
      );
    await editorState.apply(transaction);
  }

  Future<void> insertNetworkFile(
    String url, [
    bool saveOffline = false,
    bool? showPreview,
  ]) async {
    if (url.isEmpty || !isURL(url)) {
      // show error
      return showSnackBarMessage(
        context,
        LocaleKeys.document_plugins_file_networkUrlInvalid.tr(),
      );
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return showSnackBarMessage(
        context,
        LocaleKeys.document_plugins_file_networkUrlInvalid.tr(),
      );
    }

    if (saveOffline && isYoutubeVideoUrl(url)) {
      // Show the embed right away and keep fetching the file in the
      // background, so the editor is never blocked by the download.
      // The callbacks only capture the editor state and the node, never this
      // widget state, because editor blocks are recycled while scrolling.
      final editorState = this.editorState;
      final node = widget.node;
      YoutubeOfflineDownloadManager.instance.start(
        key: node.id,
        url: url,
        onCompleted: (video) => _saveOfflineYoutubeVideo(
          editorState: editorState,
          node: node,
          video: video,
          showPreview: showPreview,
        ),
        onFailed: () => showToastNotification(
          type: ToastificationType.error,
          message: LocaleKeys
              .document_plugins_linkPreview_linkPreviewMenu_downloadFailed
              .tr(),
        ),
      );
    }

    String name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : "";
    if (name.isEmpty && uri.pathSegments.length > 1) {
      name = uri.pathSegments[uri.pathSegments.length - 2];
    } else if (name.isEmpty) {
      name = uri.host;
    }
    if (!fileNameMatchesExtensions(name, _pickerAllowedExtensions)) {
      _showUnsupportedFileType(name);
      return;
    }

    // Remove the file block from the drop state manager
    dropManagerState?.remove(FileBlockKeys.type);

    final transaction = editorState.transaction;
    transaction.updateNode(widget.node, {
      FileBlockKeys.url: url,
      FileBlockKeys.urlType: FileUrlType.network.toIntValue(),
      FileBlockKeys.name: name,
      FileBlockKeys.uploadedAt: DateTime.now().millisecondsSinceEpoch,
      if (showPreview != null)
        FileBlockKeys.displayMode: showPreview ? 'preview' : 'file',
    });
    await editorState.apply(transaction);
  }

  List<String>? get _pickerAllowedExtensions {
    final value = node.extraInfos?[FileBlockKeys.pickerAllowedExtensions];
    if (value is! List) {
      return null;
    }
    final extensions = value.whereType<String>().toList(growable: false);
    return extensions.isEmpty ? null : extensions;
  }

  void _showUnsupportedFileType(String name) {
    final supported = _pickerAllowedExtensions
            ?.map((extension) => '.${extension.toLowerCase()}')
            .join(', ') ??
        '';
    showSnackBarMessage(
      context,
      '$name cannot be used here. Choose a supported file: $supported.',
    );
  }

  @override
  Position start() => Position(path: widget.node.path);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final renderBox = fileKey.currentContext?.findRenderObject();
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
    return rects.firstOrNull;
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
    final renderBox = fileKey.currentContext?.findRenderObject();
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
        path: widget.node.path,
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

@visibleForTesting
class FileMenuTrigger extends StatelessWidget {
  const FileMenuTrigger({super.key});

  @override
  Widget build(BuildContext context) {
    return const FlowyHover(
      resetHoverOnRebuild: false,
      child: Padding(
        padding: EdgeInsets.all(4),
        child: FlowySvg(
          FlowySvgs.three_dots_s,
        ),
      ),
    );
  }
}
