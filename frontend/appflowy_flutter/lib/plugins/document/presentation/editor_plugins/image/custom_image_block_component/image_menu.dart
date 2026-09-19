import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/block_menu/block_menu_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/resizeable_image.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/ignore_parent_gesture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

class ImageMenu extends StatefulWidget {
  const ImageMenu({
    super.key,
    required this.node,
    required this.state,
    required this.imageStateNotifier,
    this.mediaActions = const MediaActionService(),
  });

  final Node node;
  final CustomImageBlockComponentState state;
  final ValueNotifier<ResizableImageState> imageStateNotifier;
  final MediaActionService mediaActions;

  @override
  State<ImageMenu> createState() => _ImageMenuState();
}

class _ImageMenuState extends State<ImageMenu> {
  String? get url {
    final value = widget.node.attributes[CustomImageBlockKeys.url];
    return value is String ? value : null;
  }

  final PopoverController popoverController = PopoverController();

  late final _menuInterceptorKey = 'image-block-menu-${identityHashCode(this)}';
  EditorState? _interceptedEditor;

  late final SelectionGestureInterceptor gestureInterceptor =
      SelectionGestureInterceptor(
    key: _menuInterceptorKey,
    canTap: (details) => false,
  );

  EditorState get editorState => widget.state.editorState;

  @override
  void dispose() {
    _allowMenuClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = url;
    final isPlaceholder = source == null || source.isEmpty;
    final canCopyAndShare = isValidImageBlockSource(source);
    final userProfile = context.select<UserWorkspaceBloc?, UserProfilePB?>(
          (bloc) => bloc?.state.userProfile,
        ) ??
        context.select<DocumentBloc?, UserProfilePB?>(
          (bloc) => bloc?.state.userProfilePB,
        );
    final theme = Theme.of(context);
    // The menu is never gated on the load state: a local file reports no
    // progress at all, and a download without a Content-Length never reaches
    // 100%, so waiting for "loaded" hid the menu forever.
    return Padding(
      // The shared badge paints above its buttons. Keep that paint inside the
      // image, including at larger text scales, without growing the 32px bar.
      padding: EdgeInsets.only(
        top: canCopyAndShare
            ? MediaQuery.textScalerOf(context).scale(10) * 1.2 + 6
            : 0,
      ),
      child: Container(
        key: const ValueKey('image-menu-toolbar'),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: EditorSurfaceStyle.previewBackgroundFor(
            theme.brightness,
            theme.cardColor,
            isPaper: PaperTheme.isEnabled(context),
          ),
          // Floating chrome over a photograph: depth, never an outline.
          boxShadow: EditorSurfaceStyle.embedShadow(context, raised: true),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isPlaceholder) ...[
              _MenuIconButton(
                tooltip: 'Scan text',
                icon: Icons.document_scanner_rounded,
                onTap: scanText,
              ),
              const HSpace(2),
            ],
            if (canCopyAndShare) ...[
              MediaActionButtons(
                source: MediaActionSource.image(
                  ImageBlockData(url: source!, type: _imageType),
                  userProfile: userProfile,
                ),
                actions: widget.mediaActions,
                decorated: false,
                buttonSize: 24,
              ),
              const HSpace(2),
            ],
            _buildMoreMenu(isPlaceholder: isPlaceholder),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreMenu({required bool isPlaceholder}) {
    return IgnoreParentGestureWidget(
      child: Builder(
        builder: (buttonContext) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showMoreMenu(buttonContext, isPlaceholder),
          child: const MenuBlockButton(
            tooltip: 'More actions',
            iconData: FlowySvgs.three_dots_s,
          ),
        ),
      ),
    );
  }

  Future<void> _showMoreMenu(
    BuildContext buttonContext,
    bool isPlaceholder,
  ) async {
    _preventMenuClose();
    try {
      await showAppMenuForWidget<void>(
        context: buttonContext,
        entries: _menuEntries(isPlaceholder: isPlaceholder),
      );
    } finally {
      _allowMenuClose();
    }
  }

  List<AppMenuEntry> _menuEntries({required bool isPlaceholder}) {
    final editable = editorState.editable;
    return [
      if (editable && !isPlaceholder) ...[
        AppMenuItem(
          label: LocaleKeys.document_plugins_optionAction_left.tr(),
          icon: Icons.format_align_left_rounded,
          onSelected: () => _onAlignChanged(leftAlignmentKey),
        ),
        AppMenuItem(
          label: LocaleKeys.document_plugins_optionAction_center.tr(),
          icon: Icons.format_align_center_rounded,
          onSelected: () => _onAlignChanged(centerAlignmentKey),
        ),
        AppMenuItem(
          label: LocaleKeys.document_plugins_optionAction_right.tr(),
          icon: Icons.format_align_right_rounded,
          onSelected: () => _onAlignChanged(rightAlignmentKey),
        ),
        const AppMenuSeparator(),
      ],
      if (!isPlaceholder) ...[
        if (editable)
          AppMenuItem(
            label: 'Edit image',
            icon: Icons.tune_rounded,
            onSelected: editImage,
          ),
        AppMenuItem(
          label: 'Scan text',
          icon: Icons.document_scanner_rounded,
          onSelected: scanText,
        ),
        if (editable)
          AppMenuItem(
            label: 'Add a caption',
            icon: Icons.closed_caption_off_rounded,
            onSelected: widget.state.requestCaptionFocus,
          ),
        AppMenuItem(
          label: LocaleKeys.document_imageBlock_openFullScreen.tr(),
          icon: Icons.open_in_full_rounded,
          onSelected: openFullScreen,
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.editor_copy.tr(),
          icon: Icons.copy_rounded,
          onSelected: copyImage,
        ),
        if (editable)
          AppMenuItem(
            label: LocaleKeys.editor_cut.tr(),
            icon: Icons.content_cut_rounded,
            onSelected: cutBlock,
          ),
        AppMenuItem(
          label: LocaleKeys.button_download.tr(),
          icon: Icons.download_rounded,
          onSelected: downloadImage,
        ),
        AppMenuItem(
          label: LocaleKeys.button_share.tr(),
          icon: Icons.ios_share_rounded,
          onSelected: shareImage,
        ),
        if (editable) const AppMenuSeparator(),
      ],
      if (editable)
        AppMenuItem(
          label: LocaleKeys.button_delete.tr(),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: deleteImage,
        ),
    ];
  }

  void _preventMenuClose() {
    if (!mounted || _interceptedEditor != null) {
      return;
    }
    widget.state.alwaysShowMenu = true;
    final editor = _interceptedEditor = editorState;
    editor.service.selectionService.registerGestureInterceptor(
      gestureInterceptor,
    );
  }

  void _allowMenuClose() {
    final editor = _interceptedEditor;
    if (editor == null) {
      return;
    }
    _interceptedEditor = null;
    widget.state.alwaysShowMenu = false;
    // Cleanup also runs after a route completes or a block has been removed.
    // Never resolve an ancestor or notify a disposed hover notifier here.
    if (!editor.isDisposed) {
      editor.service.selectionService.unregisterGestureInterceptor(
        _menuInterceptorKey,
      );
    }
  }

  void _onAlignChanged(String align) {
    final transaction = editorState.transaction
      ..updateNode(widget.node, {CustomImageBlockKeys.align: align});
    unawaited(editorState.apply(transaction));
  }

  String get _imageName {
    final source = url;
    if (source == null || source.isEmpty) {
      return 'appflowy-image.png';
    }
    final name = p.basename(Uri.tryParse(source)?.path ?? source);
    return name.isEmpty ? 'appflowy-image.png' : name;
  }

  /// The stored name, given an extension that matches the actual payload when
  /// the source URL carries none.
  String _fileNameFor(String? format) {
    final name = _imageName;
    if (p.extension(name).isNotEmpty) {
      return name;
    }
    return '$name.${imageExtensionFor(format)}';
  }

  CustomImageType get _imageType => CustomImageType.fromIntValue(
        widget.node.attributes[CustomImageBlockKeys.imageType] ?? 2,
      );

  UserProfilePB? get _userProfile =>
      context.read<UserWorkspaceBloc?>()?.state.userProfile ??
      context.read<DocumentBloc?>()?.state.userProfilePB;

  MediaActionSource get _mediaSource => MediaActionSource.image(
        ImageBlockData(url: url ?? '', type: _imageType),
        userProfile: _userProfile,
      );

  /// The picture's own bytes.
  ///
  /// Rasterising the block instead would bake in the hover chrome and the
  /// on-screen scale; the stored file is both clean and full resolution.
  Future<Uint8List> _readImageBytes() {
    final source = url;
    if (source == null || source.isEmpty) {
      return Future.value(Uint8List(0));
    }
    final uri = Uri.tryParse(source);
    return ImageEditorSource(
      url: uri?.isScheme('file') == true ? File.fromUri(uri!).path : source,
      type: _imageType,
      userProfile: _imageType == CustomImageType.internal ? _userProfile : null,
    ).readBytes();
  }

  Future<void> copyImage() async {
    if (url?.isNotEmpty != true) {
      return;
    }

    try {
      await widget.mediaActions.copy(_mediaSource);

      if (mounted) {
        showToastNotification(
          message: LocaleKeys.message_copy_success.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        showToastNotification(
          message: LocaleKeys.message_copy_fail.tr(),
          type: ToastificationType.error,
        );
      }
    }
  }

  /// Puts the whole block on the clipboard — as a pasteable AppFlowy node and
  /// as a bitmap for other apps — and then removes it from the document.
  Future<void> cutBlock() async {
    final document = Document.blank()..insert([0], [widget.node.deepCopy()]);

    try {
      await getIt<ClipboardService>().setData(
        ClipboardServiceData(
          plainText: url ?? '',
          inAppJson: jsonEncode(document.toJson()),
          image: await encodeForClipboard(await _readImageBytes()),
        ),
      );
    } catch (e) {
      if (mounted) {
        showToastNotification(
          message: LocaleKeys.message_copy_fail.tr(),
          type: ToastificationType.error,
        );
      }
      return;
    }

    await deleteImage();
  }

  /// Opens the text scanner over this picture.
  Future<void> scanText() async {
    final source = url;
    if (source == null || source.isEmpty) {
      return;
    }

    widget.state.alwaysShowMenu = true;
    try {
      await showImageOcrOverlay(
        context,
        source: ImageEditorSource(
          url: source,
          type: _imageType,
          userProfile: _userProfile,
        ),
        name: _imageName,
      );
    } finally {
      widget.state.alwaysShowMenu = false;
    }
  }

  /// Opens the fullscreen editor and writes the result back into the block.
  Future<void> editImage() async {
    final source = url;
    if (source == null || source.isEmpty) {
      return;
    }

    // The block can be removed or rebound while the editor is open, so capture
    // everything the save callback needs up front.
    final documentBloc = context.read<DocumentBloc>();
    final userProfile = context.read<UserWorkspaceBloc?>()?.state.userProfile ??
        documentBloc.state.userProfilePB;
    final node = widget.node;
    final capturedEditorState = editorState;

    widget.state.alwaysShowMenu = true;
    try {
      await showImageEditor(
        context,
        source: ImageEditorSource(
          url: source,
          type: _imageType,
          userProfile: userProfile,
        ),
        name: _imageName,
        onSave: (bytes) => _persistEditedImage(
          bytes: bytes,
          node: node,
          editorState: capturedEditorState,
          documentBloc: documentBloc,
        ),
      );
    } finally {
      widget.state.alwaysShowMenu = false;
    }
  }

  Future<bool> _persistEditedImage({
    required Uint8List bytes,
    required Node node,
    required EditorState editorState,
    required DocumentBloc documentBloc,
  }) async {
    final directory = await getTemporaryDirectory();
    final temporaryFile = File(
      p.join(
        directory.path,
        'appflowy-image-${DateTime.now().millisecondsSinceEpoch}.png',
      ),
    );
    await temporaryFile.writeAsBytes(bytes, flush: true);

    try {
      String? path;
      String? errorMessage;
      var type = CustomImageType.local;

      if (documentBloc.isLocalMode) {
        path = await saveImageToLocalStorage(temporaryFile.path);
      } else {
        (path, errorMessage) = await saveImageToCloudStorage(
          temporaryFile.path,
          documentBloc.documentId,
        );
        type = CustomImageType.internal;
      }

      if (path == null) {
        showToastNotification(
          message: errorMessage ??
              LocaleKeys.document_imageBlock_error_invalidImage.tr(),
          type: ToastificationType.error,
        );
        return false;
      }

      final transaction = editorState.transaction
        ..updateNode(node, {
          CustomImageBlockKeys.url: path,
          CustomImageBlockKeys.imageType: type.toIntValue(),
          // Cropping changes the aspect ratio, so a previously framed height
          // would letterbox the new picture.
          CustomImageBlockKeys.height: null,
        });
      await editorState.apply(transaction);
      return true;
    } finally {
      unawaited(temporaryFile.delete().catchError((_) => temporaryFile));
    }
  }

  Future<void> deleteImage() async {
    final node = widget.node;
    final transaction = editorState.transaction;
    transaction.deleteNode(node);
    transaction.afterSelection = null;
    await editorState.apply(transaction);
  }

  Future<void> downloadImage() async {
    try {
      final bytes = await _readImageBytes();
      final saved = await saveMediaBytes(
        name: _fileNameFor(sniffImageFormat(bytes)),
        bytes: bytes,
      );
      if (saved && mounted) {
        showToastNotification(
          message: LocaleKeys.grid_media_downloadSuccess.tr(),
        );
      }
    } catch (e) {
      if (mounted) {
        showToastNotification(
          message: LocaleKeys.document_imageBlock_error_invalidImage.tr(),
          type: ToastificationType.error,
        );
      }
    }
  }

  Future<void> shareImage() async {
    if (url?.isNotEmpty != true) {
      return;
    }
    try {
      final box = context.findRenderObject();
      await widget.mediaActions.share(
        _mediaSource,
        sharePositionOrigin: box is RenderBox && box.hasSize
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      );
    } catch (_) {
      if (mounted) {
        showToastNotification(
          message: LocaleKeys.mediaActions_shareFailed.tr(),
          type: ToastificationType.error,
        );
      }
    }
  }

  void openFullScreen() {
    showDialog(
      context: context,
      builder: (_) => InteractiveImageViewer(
        userProfile: _userProfile,
        imageProvider: AFBlockImageProvider(
          images: [ImageBlockData(url: url!, type: _imageType)],
          onDeleteImage: editorState.editable
              ? (_) async {
                  final transaction = editorState.transaction;
                  transaction.deleteNode(widget.node);
                  await editorState.apply(transaction);
                }
              : null,
        ),
      ),
    );
  }
}

/// The same shell as [MenuBlockButton] for icons that have no Flowy SVG yet.
class _MenuIconButton extends StatelessWidget {
  const _MenuIconButton({
    required this.tooltip,
    required this.icon,
    this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FlowyButton(
      useIntrinsicWidth: true,
      onTap: onTap,
      text: FlowyTooltip(
        message: tooltip,
        child: Icon(
          icon,
          size: 16,
          color: Theme.of(context).iconTheme.color,
        ),
      ),
    );
  }
}
