import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/widgets/flowy_option_tile.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/unsupport_image_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_caption.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_placeholder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/resizeable_image.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/custom_image_cache_manager.dart';
import 'package:appflowy/shared/permission/permission_checker.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide ResizableImage;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:string_validator/string_validator.dart';
import 'package:universal_platform/universal_platform.dart';

import '../common.dart';

const kImagePlaceholderKey = 'imagePlaceholderKey';

class CustomImageBlockKeys {
  const CustomImageBlockKeys._();

  static const String type = 'image';

  /// The align data of a image block.
  ///
  /// The value is a String.
  /// left, center, right
  static const String align = 'align';

  /// The image src of a image block.
  ///
  /// The value is a String.
  /// It can be a url or a base64 string(web).
  static const String url = 'url';

  /// The height of a image block.
  ///
  /// The value is a double.
  static const String width = 'width';

  /// The width of a image block.
  ///
  /// The value is a double.
  static const String height = 'height';

  /// The image type of a image block.
  ///
  /// The value is a CustomImageType enum.
  static const String imageType = 'image_type';

  /// The caption shown under the image.
  ///
  /// The value is a String. The attribute is absent when there is no caption.
  static const String caption = 'caption';
}

Node customImageNode({
  required String url,
  String align = 'center',
  double? height,
  double? width,
  CustomImageType type = CustomImageType.local,
}) {
  return Node(
    type: CustomImageBlockKeys.type,
    attributes: {
      CustomImageBlockKeys.url: url,
      CustomImageBlockKeys.align: align,
      CustomImageBlockKeys.height: height,
      CustomImageBlockKeys.width: width,
      CustomImageBlockKeys.imageType: type.toIntValue(),
    },
  );
}

typedef CustomImageBlockComponentMenuBuilder = Widget Function(
  Node node,
  CustomImageBlockComponentState state,
  ValueNotifier<ResizableImageState> imageStateNotifier,
);

class CustomImageBlockComponentBuilder extends BlockComponentBuilder {
  CustomImageBlockComponentBuilder({
    super.configuration,
    this.showMenu = false,
    this.menuBuilder,
  });

  /// Whether to show the menu of this block component.
  final bool showMenu;

  ///
  final CustomImageBlockComponentMenuBuilder? menuBuilder;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CustomImageBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
      showMenu: showMenu,
      menuBuilder: menuBuilder,
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class CustomImageBlockComponent extends BlockComponentStatefulWidget {
  const CustomImageBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
    this.showMenu = false,
    this.menuBuilder,
  });

  /// Whether to show the menu of this block component.
  final bool showMenu;

  final CustomImageBlockComponentMenuBuilder? menuBuilder;

  @override
  State<CustomImageBlockComponent> createState() =>
      CustomImageBlockComponentState();
}

class CustomImageBlockComponentState extends State<CustomImageBlockComponent>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final imageKey = GlobalKey();
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  late final editorState = Provider.of<EditorState>(context, listen: false);

  final showActionsNotifier = ValueNotifier<bool>(false);
  final imageStateNotifier =
      ValueNotifier<ResizableImageState>(ResizableImageState.loading);

  /// Bumped by the block menu to move the caret into the caption field.
  final captionFocusRequest = ValueNotifier<int>(0);

  bool alwaysShowMenu = false;

  void requestCaptionFocus() => captionFocusRequest.value++;

  @override
  void dispose() {
    showActionsNotifier.dispose();
    imageStateNotifier.dispose();
    captionFocusRequest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final attributes = node.attributes;
    final src = attributes[CustomImageBlockKeys.url];

    final alignment = AlignmentExtension.fromString(
      attributes[CustomImageBlockKeys.align] ?? 'center',
    );
    final width =
        attributes[CustomImageBlockKeys.width]?.toDouble() ?? defaultImageWidth;
    final height = attributes[CustomImageBlockKeys.height]?.toDouble();
    final rawImageType = attributes[CustomImageBlockKeys.imageType] ?? 0;
    final imageType = CustomImageType.fromIntValue(rawImageType);

    final imagePlaceholderKey = node.extraInfos?[kImagePlaceholderKey];
    final hasHoverMenu = UniversalPlatform.isDesktopOrWeb &&
        widget.showMenu &&
        widget.menuBuilder != null;

    Widget child;
    // Only a real picture can dock the menu to its own corner; the placeholder
    // and the unsupported card fall back to the block's top right.
    var menuIsDocked = false;
    if (src.isEmpty) {
      child = ImagePlaceholder(
        key: imagePlaceholderKey is GlobalKey ? imagePlaceholderKey : null,
        node: node,
      );
    } else if (imageType != CustomImageType.internal &&
        !_checkIfURLIsValid(src)) {
      child = const UnsupportedImageWidget();
    } else {
      menuIsDocked = hasHoverMenu;
      child = ResizableImage(
        src: src,
        width: width,
        height: height,
        editable: editorState.editable,
        alignment: alignment,
        type: imageType,
        overlay: menuIsDocked ? _buildHoverMenu() : null,
        caption: ImageCaption(
          node: node,
          editorState: editorState,
          editable: editorState.editable,
          isHovering: showActionsNotifier,
          focusRequest: captionFocusRequest,
        ),
        onStateChange: (state) => imageStateNotifier.value = state,
        onDoubleTap: () => showDialog(
          context: context,
          builder: (_) => InteractiveImageViewer(
            userProfile: context.read<DocumentBloc>().state.userProfilePB,
            imageProvider: AFBlockImageProvider(
              images: [ImageBlockData(url: src, type: imageType)],
              onDeleteImage: (_) async {
                final transaction = editorState.transaction..deleteNode(node);
                await editorState.apply(transaction);
              },
            ),
          ),
        ),
        onResize: (width) {
          final transaction = editorState.transaction
            ..updateNode(node, {CustomImageBlockKeys.width: width});
          editorState.apply(transaction);
        },
        onResizeHeight: (height) {
          final transaction = editorState.transaction
            ..updateNode(node, {CustomImageBlockKeys.height: height});
          editorState.apply(transaction);
        },
      );
    }

    child = Padding(
      padding: padding,
      child: RepaintBoundary(
        key: imageKey,
        child: child,
      ),
    );

    if (UniversalPlatform.isDesktopOrWeb) {
      child = BlockSelectionContainer(
        node: node,
        delegate: this,
        listenable: editorState.selectionNotifier,
        blockColor: editorState.editorStyle.selectionColor,
        selectionAboveBlock: true,
        supportTypes: const [BlockSelectionType.block],
        child: child,
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

    // show a hover menu on desktop or web
    if (UniversalPlatform.isDesktopOrWeb) {
      if (hasHoverMenu) {
        child = MouseRegion(
          onEnter: (_) => showActionsNotifier.value = true,
          onExit: (_) {
            if (!alwaysShowMenu) {
              showActionsNotifier.value = false;
            }
          },
          hitTestBehavior: HitTestBehavior.opaque,
          opaque: false,
          child: ValueListenableBuilder<bool>(
            valueListenable: showActionsNotifier,
            builder: (_, value, child) {
              return Stack(
                children: [
                  editorState.editable
                      ? BlockSelectionContainer(
                          node: node,
                          delegate: this,
                          listenable: editorState.selectionNotifier,
                          cursorColor: editorState.editorStyle.cursorColor,
                          selectionColor:
                              editorState.editorStyle.selectionColor,
                          child: child!,
                        )
                      : child!,
                  if (value && !menuIsDocked)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: widget.menuBuilder!(
                        widget.node,
                        this,
                        imageStateNotifier,
                      ),
                    ),
                ],
              );
            },
            child: child,
          ),
        );
      }
    } else {
      // show a fixed menu on mobile
      child = MobileBlockActionButtons(
        showThreeDots: false,
        node: node,
        editorState: editorState,
        extendActionWidgets: _buildExtendActionWidgets(context),
        child: child,
      );
    }

    return child;
  }

  /// The hover chrome that rides in the picture's own top-right corner.
  Widget _buildHoverMenu() {
    return ValueListenableBuilder<bool>(
      valueListenable: showActionsNotifier,
      builder: (_, showActions, __) {
        if (!showActions) {
          return const SizedBox.shrink();
        }
        return widget.menuBuilder!(widget.node, this, imageStateNotifier);
      },
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
  Rect getBlockRect({
    bool shiftWithBaseOffset = false,
  }) {
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (imageBox is RenderBox) {
      return padding.topLeft & imageBox.size;
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
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && imageBox is RenderBox) {
      return [
        imageBox.localToGlobal(Offset.zero, ancestor: parentBox) &
            imageBox.size,
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

  // only used on mobile platform
  List<Widget> _buildExtendActionWidgets(BuildContext context) {
    final String url = widget.node.attributes[CustomImageBlockKeys.url];
    if (!_checkIfURLIsValid(url)) {
      return [];
    }

    return [
      FlowyOptionTile.text(
        showTopBorder: false,
        text: LocaleKeys.button_download.tr(),
        leftIcon: const FlowySvg(FlowySvgs.download_s),
        onTap: () async {
          context.pop();
          await downloadMedia(source: url, name: _mediaName(url));
        },
      ),
      FlowyOptionTile.text(
        showTopBorder: false,
        text: LocaleKeys.editor_copy.tr(),
        leftIcon: const FlowySvg(
          FlowySvgs.m_field_copy_s,
        ),
        onTap: () async {
          context.pop();
          showToastNotification(
            message: LocaleKeys.document_plugins_image_copiedToPasteBoard.tr(),
          );
          await copyMedia(
            source: url,
            name: _mediaName(url),
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
            name: _mediaName(url),
          );
        },
      ),
      FlowyOptionTile.text(
        showTopBorder: false,
        text: LocaleKeys.document_imageBlock_saveImageToGallery.tr(),
        leftIcon: const FlowySvg(
          FlowySvgs.image_placeholder_s,
          size: Size.square(20),
        ),
        onTap: () async {
          context.pop();
          // save the image to the photo library
          await _saveImageToGallery(url);
        },
      ),
    ];
  }

  String _mediaName(String source) {
    final name = Uri.tryParse(source)?.pathSegments.lastOrNull;
    return name == null || name.isEmpty ? 'appflowy-image.png' : name;
  }

  bool _checkIfURLIsValid(dynamic url) {
    if (url is! String) {
      return false;
    }

    if (url.isEmpty) {
      return false;
    }

    if (!isURL(url) && !File(url).existsSync()) {
      return false;
    }

    return true;
  }

  Future<void> _saveImageToGallery(String url) async {
    final permission = await PermissionChecker.checkPhotoPermission(context);
    if (!permission) {
      return;
    }

    final imageFile = await CustomImageCacheManager().getSingleFile(url);
    if (imageFile.existsSync()) {
      final result = await SaverGallery.saveImage(
        imageFile.readAsBytesSync(),
        fileName: imageFile.basename,
        skipIfExists: false,
      );
      if (mounted) {
        showToastNotification(
          message: result.isSuccess
              ? LocaleKeys.document_imageBlock_successToAddImageToGallery.tr()
              : LocaleKeys.document_imageBlock_failedToAddImageToGallery.tr(),
        );
      }
    }
  }
}
