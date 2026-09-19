import 'dart:io';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/block_menu/block_menu_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide UploadImageMenu;
import 'package:cross_file/cross_file.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:string_validator/string_validator.dart';

class MultiImageMenu extends StatefulWidget {
  const MultiImageMenu({
    super.key,
    required this.node,
    required this.state,
    required this.indexNotifier,
    this.isLocalMode = true,
    required this.onImageDeleted,
    this.mediaActions = const MediaActionService(),
  });

  final Node node;
  final MultiImageBlockComponentState state;
  final ValueNotifier<int> indexNotifier;
  final bool isLocalMode;
  final VoidCallback onImageDeleted;
  final MediaActionService mediaActions;

  @override
  State<MultiImageMenu> createState() => _MultiImageMenuState();
}

class _MultiImageMenuState extends State<MultiImageMenu> {
  late final _interceptorKey = 'add-image-${identityHashCode(this)}';
  EditorState? _interceptedEditor;

  late final gestureInterceptor = SelectionGestureInterceptor(
    key: _interceptorKey,
    canTap: (details) => false,
  );

  final PopoverController controller = PopoverController();
  final PopoverController layoutController = PopoverController();
  late List<ImageBlockData> images;
  late final EditorState editorState;

  @override
  void initState() {
    super.initState();
    editorState = context.read<EditorState>();
    images = MultiImageData.fromJson(
      widget.node.attributes[MultiImageBlockKeys.images] ?? const [],
    ).images;
  }

  @override
  void dispose() {
    allowMenuClose();
    controller.close();
    layoutController.close();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MultiImageMenu oldWidget) {
    images = MultiImageData.fromJson(
      widget.node.attributes[MultiImageBlockKeys.images] ?? const [],
    ).images;

    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final layout = MultiImageLayout.fromIntValue(
      widget.node.attributes[MultiImageBlockKeys.layout] ?? 0,
    );
    final userProfile = context.select<UserWorkspaceBloc?, UserProfilePB?>(
          (bloc) => bloc?.state.userProfile,
        ) ??
        context.select<DocumentBloc?, UserProfilePB?>(
          (bloc) => bloc?.state.userProfilePB,
        );
    return ValueListenableBuilder<int>(
      valueListenable: widget.indexNotifier,
      builder: (_, index, __) {
        final selectedImage = images.isEmpty
            ? null
            : images[index.clamp(0, images.length - 1).toInt()];
        final canCopyAndShare = layout == MultiImageLayout.browser &&
            selectedImage != null &&
            isValidImageBlockSource(selectedImage.url);
        return ValueListenableBuilder<bool>(
          valueListenable: widget.state.showActionsNotifier,
          builder: (_, visible, __) => MediaActionReveal(
            visible: visible,
            child: Padding(
              // Keep the scaled feedback badge inside the photo without
              // changing the placement of grid/empty-gallery controls.
              padding: EdgeInsets.only(
                top: canCopyAndShare
                    ? MediaQuery.textScalerOf(context).scale(10) * 1.2 + 6
                    : 0,
              ),
              child: ValueListenableBuilder<bool>(
                valueListenable: editorState.editableNotifier,
                builder: (_, editable, __) => _buildToolbar(
                  context,
                  layout: layout,
                  editable: editable,
                  selectedImage: selectedImage,
                  canCopyAndShare: canCopyAndShare,
                  userProfile: userProfile,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar(
    BuildContext context, {
    required MultiImageLayout layout,
    required bool editable,
    required ImageBlockData? selectedImage,
    required bool canCopyAndShare,
    required UserProfilePB? userProfile,
  }) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('multi-image-menu-toolbar'),
      height: 32,
      decoration: BoxDecoration(
        color: EditorSurfaceStyle.previewBackgroundFor(
          theme.brightness,
          theme.cardColor,
          isPaper: PaperTheme.isEnabled(context),
        ),
        boxShadow: EditorSurfaceStyle.embedShadow(context, raised: true),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HSpace(4),
          if (editable) ...[
            AppFlowyPopover(
              controller: controller,
              direction: PopoverDirection.bottomWithRightAligned,
              onClose: allowMenuClose,
              constraints: const BoxConstraints(
                maxWidth: 540,
                maxHeight: 360,
                minHeight: 80,
              ),
              offset: const Offset(0, 10),
              popupBuilder: (context) {
                preventMenuClose();
                return UploadImageMenu(
                  allowMultipleImages: true,
                  supportTypes: const [
                    UploadImageType.local,
                    UploadImageType.url,
                    UploadImageType.unsplash,
                  ],
                  onSelectedLocalImages: insertLocalImages,
                  onSelectedAIImage: insertAIImage,
                  onSelectedNetworkImage: insertNetworkImage,
                  onSelectedWorkspaceImage: insertWorkspaceImage,
                );
              },
              child: MenuBlockButton(
                tooltip: LocaleKeys
                    .document_plugins_photoGallery_addImageTooltip
                    .tr(),
                iconData: FlowySvgs.add_s,
                onTap: () {},
              ),
            ),
            const HSpace(4),
            AppFlowyPopover(
              controller: layoutController,
              onClose: allowMenuClose,
              direction: PopoverDirection.bottomWithRightAligned,
              offset: const Offset(0, 10),
              constraints: const BoxConstraints(
                maxHeight: 300,
                maxWidth: 300,
              ),
              popupBuilder: (context) {
                preventMenuClose();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LayoutSelector(
                      selectedLayout: layout,
                      onSelected: (layout) {
                        allowMenuClose();
                        layoutController.close();
                        final transaction = editorState.transaction;
                        transaction.updateNode(widget.node, {
                          MultiImageBlockKeys.images: widget
                              .node.attributes[MultiImageBlockKeys.images],
                          MultiImageBlockKeys.layout: layout.toIntValue(),
                        });
                        editorState.apply(transaction);
                      },
                    ),
                  ],
                );
              },
              child: MenuBlockButton(
                tooltip: LocaleKeys
                    .document_plugins_photoGallery_changeLayoutTooltip
                    .tr(),
                iconData: FlowySvgs.edit_layout_s,
                onTap: () {},
              ),
            ),
            const HSpace(4),
          ],
          MenuBlockButton(
            tooltip: LocaleKeys.document_imageBlock_openFullScreen.tr(),
            iconData: FlowySvgs.full_view_s,
            onTap: images.isEmpty ? null : openFullScreen,
          ),
          if (canCopyAndShare) ...[
            const HSpace(4),
            MediaActionButtons(
              key: const ValueKey('multi-image-media-actions'),
              source: MediaActionSource.image(
                selectedImage!,
                userProfile: userProfile,
              ),
              actions: widget.mediaActions,
              decorated: false,
              buttonSize: 24,
            ),
          ],
          if (editable) ...[
            const _Divider(),
            MenuBlockButton(
              tooltip: LocaleKeys
                  .document_plugins_photoGallery_deleteBlockTooltip
                  .tr(),
              iconData: FlowySvgs.delete_s,
              onTap: deleteImage,
            ),
          ],
          const HSpace(4),
        ],
      ),
    );
  }

  Future<void> deleteImage() async {
    if (!editorState.editable) {
      return;
    }
    final node = widget.node;
    final transaction = editorState.transaction;
    transaction.deleteNode(node);
    transaction.afterSelection = null;
    await editorState.apply(transaction);
  }

  void openFullScreen() {
    if (images.isEmpty) {
      return;
    }
    final userProfile = context.read<UserWorkspaceBloc?>()?.state.userProfile ??
        context.read<DocumentBloc?>()?.state.userProfilePB;
    showDialog(
      context: context,
      builder: (_) => InteractiveImageViewer(
        userProfile: userProfile,
        imageProvider: AFBlockImageProvider(
          images: images,
          initialIndex:
              widget.indexNotifier.value.clamp(0, images.length - 1).toInt(),
          onDeleteImage: editorState.editable
              ? (index) async {
                  final transaction = editorState.transaction;
                  final newImages = List<ImageBlockData>.from(images);
                  newImages.removeAt(index);

                  images = newImages;
                  widget.onImageDeleted();

                  final imagesJson =
                      newImages.map((image) => image.toJson()).toList();
                  transaction.updateNode(widget.node, {
                    MultiImageBlockKeys.images: imagesJson,
                    MultiImageBlockKeys.layout:
                        widget.node.attributes[MultiImageBlockKeys.layout],
                  });

                  await editorState.apply(transaction);
                }
              : null,
        ),
      ),
    );
  }

  void preventMenuClose() {
    if (!mounted || _interceptedEditor != null) {
      return;
    }
    widget.state.alwaysShowMenu = true;
    final editor = _interceptedEditor = editorState;
    editor.service.selectionService.registerGestureInterceptor(
      gestureInterceptor,
    );
  }

  void allowMenuClose() {
    final editor = _interceptedEditor;
    if (editor == null) {
      return;
    }
    _interceptedEditor = null;
    widget.state.alwaysShowMenu = false;
    if (!editor.isDisposed) {
      editor.service.selectionService.unregisterGestureInterceptor(
        _interceptorKey,
      );
    }
  }

  Future<void> insertLocalImages(List<XFile> files) async {
    controller.close();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final urls = files
          .map((file) => file.path)
          .where((path) => path.isNotEmpty)
          .toList();

      if (urls.isEmpty || urls.every((url) => url.isEmpty)) {
        return;
      }

      final transaction = editorState.transaction;
      final uploadedImages =
          await extractAndUploadImages(context, urls, widget.isLocalMode);
      if (uploadedImages.isEmpty) {
        return;
      }

      final newImages = [...images, ...uploadedImages];
      final imagesJson = newImages.map((i) => i.toJson()).toList();
      transaction.updateNode(widget.node, {
        MultiImageBlockKeys.images: imagesJson,
        MultiImageBlockKeys.layout:
            widget.node.attributes[MultiImageBlockKeys.layout],
      });

      await editorState.apply(transaction);
      if (mounted) {
        setState(() => images = newImages);
      }
    });
  }

  Future<void> insertAIImage(String url) async {
    controller.close();

    if (url.isEmpty || !isURL(url)) {
      // show error
      return showSnackBarMessage(
        context,
        LocaleKeys.document_imageBlock_error_invalidImage.tr(),
      );
    }

    final path = await getIt<ApplicationDataStorage>().getPath();
    final imagePath = p.join(path, 'images');
    try {
      // create the directory if not exists
      final directory = Directory(imagePath);
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      final uri = Uri.parse(url);
      final copyToPath = p.join(
        imagePath,
        '${uuid()}${p.extension(uri.path)}',
      );

      final response = await get(uri);
      await File(copyToPath).writeAsBytes(response.bodyBytes);
      await insertLocalImages([XFile(copyToPath)]);
      await File(copyToPath).delete();
    } catch (e) {
      Log.error('cannot save image file', e);
    }
  }

  Future<void> insertWorkspaceImage(ViewPB view) async {
    controller.close();
    final reference = view.workspaceFileReference;
    if (reference == null) {
      return showSnackBarMessage(
        context,
        'This workspace image is no longer available.',
      );
    }

    final newImages = [
      ...images,
      ImageBlockData(
        url: reference.url,
        type: reference.isLocal
            ? CustomImageType.local
            : CustomImageType.internal,
        workspaceFileId: reference.viewId,
      ),
    ];
    final transaction = editorState.transaction
      ..updateNode(widget.node, {
        MultiImageBlockKeys.images:
            newImages.map((image) => image.toJson()).toList(),
        MultiImageBlockKeys.layout:
            widget.node.attributes[MultiImageBlockKeys.layout],
      });
    await editorState.apply(transaction);
    setState(() => images = newImages);
  }

  Future<void> insertNetworkImage(String url) async {
    controller.close();

    if (url.isEmpty || !isURL(url)) {
      // show error
      return showSnackBarMessage(
        context,
        LocaleKeys.document_imageBlock_error_invalidImage.tr(),
      );
    }

    final transaction = editorState.transaction;

    final newImages = [
      ...images,
      ImageBlockData(url: url, type: CustomImageType.external),
    ];

    final imagesJson = newImages.map((image) => image.toJson()).toList();
    transaction.updateNode(widget.node, {
      MultiImageBlockKeys.images: imagesJson,
      MultiImageBlockKeys.layout:
          widget.node.attributes[MultiImageBlockKeys.layout],
    });

    await editorState.apply(transaction);
    setState(() => images = newImages);
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(width: 1, color: Colors.grey),
    );
  }
}

class _LayoutSelector extends StatelessWidget {
  const _LayoutSelector({
    required this.selectedLayout,
    required this.onSelected,
  });

  final MultiImageLayout selectedLayout;
  final Function(MultiImageLayout) onSelected;

  @override
  Widget build(BuildContext context) {
    return SeparatedRow(
      separatorBuilder: () => const HSpace(6),
      mainAxisSize: MainAxisSize.min,
      children: MultiImageLayout.values
          .map(
            (layout) => MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onSelected(layout),
                child: Container(
                  height: 80,
                  width: 80,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      width: 2,
                      color: selectedLayout == layout
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).dividerColor,
                    ),
                    borderRadius: Corners.s8Border,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FlowySvg(
                        layout.icon,
                        color: AFThemeExtension.of(context).strongText,
                        size: const Size.square(24),
                      ),
                      const VSpace(6),
                      FlowyText(layout.label),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
