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
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
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
import 'package:share_plus/share_plus.dart';

const _menuInterceptorKey = 'image-block-menu';

class ImageMenu extends StatefulWidget {
  const ImageMenu({
    super.key,
    required this.node,
    required this.state,
    required this.imageStateNotifier,
  });

  final Node node;
  final CustomImageBlockComponentState state;
  final ValueNotifier<ResizableImageState> imageStateNotifier;

  @override
  State<ImageMenu> createState() => _ImageMenuState();
}

class _ImageMenuState extends State<ImageMenu> {
  late final String? url = widget.node.attributes[CustomImageBlockKeys.url];

  final PopoverController popoverController = PopoverController();

  final SelectionGestureInterceptor gestureInterceptor =
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
    final isPlaceholder = url == null || url!.isEmpty;
    final theme = Theme.of(context);
    // The menu is never gated on the load state: a local file reports no
    // progress at all, and a download without a Content-Length never reaches
    // 100%, so waiting for "loaded" hid the menu forever.
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.cardColor,
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
              icon: Icons.document_scanner_outlined,
              onTap: scanText,
            ),
            const HSpace(2),
            MenuBlockButton(
              tooltip: LocaleKeys.editor_copy.tr(),
              iconData: FlowySvgs.copy_s,
              onTap: copyImage,
            ),
            const HSpace(2),
          ],
          _buildMoreMenu(isPlaceholder: isPlaceholder),
        ],
      ),
    );
  }

  Widget _buildMoreMenu({required bool isPlaceholder}) {
    return IgnoreParentGestureWidget(
      child: AppFlowyPopover(
        controller: popoverController,
        onClose: _allowMenuClose,
        direction: PopoverDirection.bottomWithRightAligned,
        constraints: const BoxConstraints(maxWidth: 220),
        offset: const Offset(0, 8),
        popupBuilder: (_) {
          _preventMenuClose();
          return _buildMenuItems(isPlaceholder: isPlaceholder);
        },
        child: const MenuBlockButton(
          tooltip: 'More actions',
          iconData: FlowySvgs.three_dots_s,
        ),
      ),
    );
  }

  Widget _buildMenuItems({required bool isPlaceholder}) {
    final editable = editorState.editable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (editable && !isPlaceholder) ...[
          _item(
            icon: const FlowySvg(FlowySvgs.align_left_s),
            label: LocaleKeys.document_plugins_optionAction_left.tr(),
            onTap: () => _onAlignChanged(leftAlignmentKey),
          ),
          _item(
            icon: const FlowySvg(FlowySvgs.align_center_s),
            label: LocaleKeys.document_plugins_optionAction_center.tr(),
            onTap: () => _onAlignChanged(centerAlignmentKey),
          ),
          _item(
            icon: const FlowySvg(FlowySvgs.align_right_s),
            label: LocaleKeys.document_plugins_optionAction_right.tr(),
            onTap: () => _onAlignChanged(rightAlignmentKey),
          ),
          const _MenuDivider(),
        ],
        if (!isPlaceholder) ...[
          if (editable)
            _item(
              icon: const Icon(Icons.tune_rounded, size: 17),
              label: 'Edit image',
              onTap: editImage,
            ),
          _item(
            icon: const Icon(Icons.document_scanner_outlined, size: 16),
            label: 'Scan text',
            onTap: scanText,
          ),
          if (editable)
            _item(
              icon: const Icon(Icons.closed_caption_off_rounded, size: 17),
              label: 'Add a caption',
              onTap: widget.state.requestCaptionFocus,
            ),
          _item(
            icon: const FlowySvg(FlowySvgs.full_view_s),
            label: LocaleKeys.document_imageBlock_openFullScreen.tr(),
            onTap: openFullScreen,
          ),
          const _MenuDivider(),
          _item(
            icon: const FlowySvg(FlowySvgs.copy_s),
            label: LocaleKeys.editor_copy.tr(),
            onTap: copyImage,
          ),
          if (editable)
            _item(
              icon: const Icon(Icons.content_cut_rounded, size: 16),
              label: LocaleKeys.editor_cut.tr(),
              onTap: cutBlock,
            ),
          _item(
            icon: const FlowySvg(FlowySvgs.download_s),
            label: LocaleKeys.button_download.tr(),
            onTap: downloadImage,
          ),
          _item(
            icon: const FlowySvg(FlowySvgs.share_s),
            label: LocaleKeys.button_share.tr(),
            onTap: shareImage,
          ),
          if (editable) const _MenuDivider(),
        ],
        if (editable)
          _item(
            icon: const FlowySvg(FlowySvgs.trash_s),
            label: LocaleKeys.button_delete.tr(),
            onTap: deleteImage,
          ),
      ],
    );
  }

  Widget _item({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: HoverButton(
        itemHeight: 20,
        leftIcon: icon,
        name: label,
        onTap: () {
          _closeMenu();
          onTap();
        },
      ),
    );
  }

  void _closeMenu() {
    popoverController.close();
    _allowMenuClose();
  }

  void _preventMenuClose() {
    widget.state.alwaysShowMenu = true;
    editorState.service.selectionService.registerGestureInterceptor(
      gestureInterceptor,
    );
  }

  void _allowMenuClose() {
    widget.state.alwaysShowMenu = false;
    editorState.service.selectionService.unregisterGestureInterceptor(
      _menuInterceptorKey,
    );
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

  late final UserProfilePB? _userProfile =
      context.read<UserWorkspaceBloc?>()?.state.userProfile ??
          context.read<DocumentBloc>().state.userProfilePB;

  /// The picture's own bytes.
  ///
  /// Rasterising the block instead would bake in the hover chrome and the
  /// on-screen scale; the stored file is both clean and full resolution.
  Future<Uint8List> _readImageBytes() {
    final source = url;
    if (source == null || source.isEmpty) {
      return Future.value(Uint8List(0));
    }
    return ImageEditorSource(
      url: source,
      type: _imageType,
      userProfile: _userProfile,
    ).readBytes();
  }

  Future<void> copyImage() async {
    if (url == null) {
      return;
    }

    try {
      // Hand over the picture itself for other apps, plus the link for
      // anything that only understands text.
      final image = await encodeForClipboard(await _readImageBytes());
      await getIt<ClipboardService>().setData(
        ClipboardServiceData(
          plainText: url!,
          image: image,
        ),
      );

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

    // The hover menu is torn down as soon as the pointer leaves the block, so
    // everything the save callback needs is captured up front.
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
    final bytes = await _readImageBytes();
    final name = _fileNameFor(sniffImageFormat(bytes));
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], fileNameOverrides: [name]);
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

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        height: 1,
        color: EditorSurfaceStyle.embedBorder(context),
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
