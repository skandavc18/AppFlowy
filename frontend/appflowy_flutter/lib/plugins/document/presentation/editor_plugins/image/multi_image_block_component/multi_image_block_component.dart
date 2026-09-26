import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/layouts/multi_image_layouts.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_placeholder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

const kMultiImagePlaceholderKey = 'multiImagePlaceholderKey';

Node multiImageNode({List<ImageBlockData>? images}) => Node(
      type: MultiImageBlockKeys.type,
      attributes: {
        MultiImageBlockKeys.images:
            MultiImageData(images: images ?? []).toJson(),
        MultiImageBlockKeys.layout: MultiImageLayout.browser.toIntValue(),
      },
    );

class MultiImageBlockKeys {
  const MultiImageBlockKeys._();

  static const String type = 'multi_image';

  /// The image data for the block, stored as a JSON encoded list of [ImageBlockData].
  ///
  static const String images = 'images';

  /// The layout of the images.
  ///
  /// The value is a MultiImageLayout enum.
  ///
  static const String layout = 'layout';
}

typedef MultiImageBlockComponentMenuBuilder = Widget Function(
  Node node,
  MultiImageBlockComponentState state,
  ValueNotifier<int> indexNotifier,
  VoidCallback onImageDeleted,
);

class MultiImageBlockComponentBuilder extends BlockComponentBuilder {
  MultiImageBlockComponentBuilder({
    super.configuration,
    this.showMenu = false,
    this.menuBuilder,
    this.ocrService,
    this.ocrSourceBuilder,
  });

  final bool showMenu;
  final MultiImageBlockComponentMenuBuilder? menuBuilder;
  final OcrService? ocrService;
  final ImageOcrSourceBuilder? ocrSourceBuilder;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MultiImageBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
      showMenu: showMenu,
      menuBuilder: menuBuilder,
      ocrService: ocrService,
      ocrSourceBuilder: ocrSourceBuilder,
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class MultiImageBlockComponent extends BlockComponentStatefulWidget {
  const MultiImageBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    this.showMenu = false,
    this.menuBuilder,
    super.configuration = const BlockComponentConfiguration(),
    super.actionBuilder,
    super.actionTrailingBuilder,
    this.ocrService,
    this.ocrSourceBuilder,
  });

  final bool showMenu;

  final MultiImageBlockComponentMenuBuilder? menuBuilder;
  final OcrService? ocrService;
  final ImageOcrSourceBuilder? ocrSourceBuilder;

  @override
  State<MultiImageBlockComponent> createState() =>
      MultiImageBlockComponentState();
}

class MultiImageBlockComponentState extends State<MultiImageBlockComponent>
    with SelectableMixin, BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final multiImageKey = GlobalKey();
  final _findContentKey = GlobalKey();
  PointerEvent? _findPointer;
  DocumentBloc? _documentBloc;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  late final editorState = Provider.of<EditorState>(context, listen: false);

  final showActionsNotifier = ValueNotifier<bool>(false);

  ValueNotifier<int> indexNotifier = ValueNotifier(0);

  bool alwaysShowMenu = false;

  late final _interceptorKey =
      'multi-image-block-interceptor-${identityHashCode(this)}';

  late final interceptor = SelectionGestureInterceptor(
    key: _interceptorKey,
    canTap: (details) => _isTapInBounds(details.globalPosition),
    canPanStart: (details) => _isTapInBounds(details.globalPosition),
  );

  @override
  void initState() {
    super.initState();
    _documentBloc = context.read<DocumentBloc?>();
    editorState.selectionService.registerGestureInterceptor(interceptor);
  }

  @override
  void dispose() {
    if (!editorState.isDisposed) {
      editorState.selectionService
          .unregisterGestureInterceptor(_interceptorKey);
    }
    showActionsNotifier.dispose();
    indexNotifier.dispose();
    super.dispose();
  }

  bool get _canFindImage =>
      mounted &&
      !editorState.isDisposed &&
      _documentBloc?.isClosed != true &&
      node.parent != null &&
      identical(editorState.getNodeAtPath(node.path), node);

  bool _selectedForFind() {
    if (!_canFindImage) return false;
    final selection = editorState.selection;
    return selection != null &&
        listEquals(selection.start.path, node.path) &&
        listEquals(selection.end.path, node.path);
  }

  ImageEditorSource _ocrSource(ImageBlockData image) {
    final uri = Uri.tryParse(image.url);
    return widget.ocrSourceBuilder?.call(image) ??
        ImageEditorSource(
          url: image.type == CustomImageType.local &&
                  uri?.isScheme('file') == true
              ? File.fromUri(uri!).path
              : image.url,
          type: image.type,
          userProfile: image.type == CustomImageType.internal
              ? _documentBloc?.state.userProfilePB
              : null,
        );
  }

  bool _sourceIsCurrent(ImageEditorSource source) {
    if (!_canFindImage) return false;
    final images = MultiImageData.fromJson(
      node.attributes[MultiImageBlockKeys.images] ?? const [],
    ).images;
    final index = indexNotifier.value;
    if (index < 0 || index >= images.length) return false;
    final current = _ocrSource(images[index]);
    return current.url == source.url &&
        current.type == source.type &&
        current.userProfile == source.userProfile;
  }

  ImageEditorSource? _findSource(List<ImageBlockData> renderedImages) {
    if (!_canFindImage || renderedImages.isEmpty) return null;
    final pointer = _findPointer;
    ImageBlockData? hovered;
    if (pointer != null) {
      final hit = HitTestResult();
      RendererBinding.instance
          .hitTestInView(hit, pointer.position, pointer.viewId);
      final hitObjects = hit.path.map((entry) => entry.target).toSet();
      // The existing layouts own all their images/drag/drop/actions and expose
      // no builder hook. Inspect ONLY this gallery's mounted image units, once
      // on Find (never on a hover frame), and require an actual painted hit.
      var ordinal = 0;
      final grid = node.attributes[MultiImageBlockKeys.layout] ==
          MultiImageLayout.grid.toIntValue();
      void visit(Element element) {
        final unit = element.widget;
        String? url;
        if (unit is FlowyNetworkImage) {
          url = unit.url;
        } else if (unit is Image) {
          final provider = unit.image;
          if (provider is FileImage) url = provider.file.path;
          if (provider is NetworkImage) url = provider.url;
        }
        if (url != null) {
          // Grid units are in reading order. Browser units are the hero first,
          // then its visible thumbnails. This also distinguishes duplicate URLs.
          final imageIndex = grid
              ? ordinal
              : ordinal == 0
                  ? indexNotifier.value
                  : ordinal - 1;
          ordinal++;
          if (imageIndex < 0 ||
              imageIndex >= renderedImages.length ||
              renderedImages[imageIndex].url != url) {
            return;
          }
          void inspect(RenderObject object) {
            if (hovered != null) return;
            if (object is RenderImage &&
                object.attached &&
                object.hasSize &&
                object.image != null &&
                hitObjects.contains(object)) {
              final image = object.image!;
              final fitted = applyBoxFit(
                object.fit ?? BoxFit.scaleDown,
                Size(image.width / object.scale, image.height / object.scale),
                object.size,
              );
              final alignment =
                  object.alignment.resolve(Directionality.of(element));
              final painted = alignment.inscribe(
                fitted.destination,
                Offset.zero & object.size,
              );
              if (painted.contains(object.globalToLocal(pointer.position))) {
                hovered = renderedImages[imageIndex];
              }
            } else {
              object.visitChildren(inspect);
            }
          }

          final render = element.findRenderObject();
          if (render != null) inspect(render);
          return;
        }
        element.visitChildElements(visit);
      }

      _findContentKey.currentContext?.visitChildElements(visit);
      // A gap/letterbox or overlaid action is not a different selected photo.
      if (hovered == null) return null;
    }
    final candidate = hovered ??
        renderedImages[indexNotifier.value.clamp(0, renderedImages.length - 1)];
    final images = MultiImageData.fromJson(
      node.attributes[MultiImageBlockKeys.images] ?? const [],
    ).images;
    var index = renderedImages.indexOf(candidate);
    bool same(ImageBlockData image) =>
        image.url == candidate.url &&
        image.type == candidate.type &&
        image.workspaceFileId == candidate.workspaceFileId;
    if (index < 0 || index >= images.length || !same(images[index])) {
      index = images.indexWhere(same);
    }
    if (index < 0) return null;
    // Activation selects the nearest IMAGE unit, without stealing the editor's
    // caret during passive hover or persisting any document change.
    setState(() => indexNotifier.value = index);
    return _ocrSource(images[index]);
  }

  bool _isTapInBounds(Offset offset) {
    if (_renderBox == null) {
      // We shouldn't block any actions if the render box is not available.
      // This has the potential to break taps on the editor completely if we
      // accidentally return false here.
      return true;
    }

    final localPosition = _renderBox!.globalToLocal(offset);
    return !_renderBox!.paintBounds.contains(localPosition);
  }

  @override
  Widget build(BuildContext context) {
    final data = MultiImageData.fromJson(
      node.attributes[MultiImageBlockKeys.images] ?? const [],
    );
    // A remote update or a deletion can shorten the gallery while its menu is
    // mounted. Normalize before either the renderer or menu reads the index.
    indexNotifier.value = data.images.isEmpty
        ? 0
        : indexNotifier.value.clamp(0, data.images.length - 1).toInt();

    Widget child;
    if (data.images.isEmpty) {
      final multiImagePlaceholderKey =
          node.extraInfos?[kMultiImagePlaceholderKey];

      child = MultiImagePlaceholder(
        key: multiImagePlaceholderKey is GlobalKey
            ? multiImagePlaceholderKey
            : null,
        node: node,
      );
    } else {
      child = MouseRegion(
        opaque: false,
        onEnter: (event) => _findPointer = event,
        onHover: (event) => _findPointer = event,
        onExit: (_) => _findPointer = null,
        child: ImageOcrFindRegion(
          source: _ocrSource(data.images[indexNotifier.value]),
          name: 'Photo gallery — image text',
          service: widget.ocrService,
          isAvailable: () => _canFindImage,
          isSelected: _selectedForFind,
          resolveSource: () => _findSource(data.images),
          isSourceCurrent: _sourceIsCurrent,
          debugLabel: 'Photo gallery content',
          child: ImageLayoutRender(
            key: _findContentKey,
            node: node,
            images: data.images,
            editorState: editorState,
            indexNotifier: indexNotifier,
            isLocalMode: context.read<DocumentBloc?>()?.isLocalMode ?? true,
            onIndexChanged: (index) {
              if (_canFindImage) setState(() => indexNotifier.value = index);
            },
          ),
        ),
      );
    }

    if (UniversalPlatform.isDesktopOrWeb) {
      child = BlockSelectionContainer(
        node: node,
        delegate: this,
        listenable: editorState.selectionNotifier,
        blockColor: editorState.editorStyle.selectionColor,
        supportTypes: const [BlockSelectionType.block],
        child: Padding(key: multiImageKey, padding: padding, child: child),
      );
    } else {
      child = Padding(key: multiImageKey, padding: padding, child: child);
    }

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    if (UniversalPlatform.isDesktopOrWeb) {
      if (widget.showMenu && widget.menuBuilder != null) {
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
            builder: (context, _, child) {
              return Stack(
                clipBehavior: Clip.none,
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
                  // The builder owns its Positioned wrapper; the menu reveals
                  // inside it so hover exit never disposes an active operation.
                  if (data.images.isNotEmpty)
                    widget.menuBuilder!(
                      widget.node,
                      this,
                      indexNotifier,
                      () => setState(
                        () => indexNotifier.value = indexNotifier.value > 0
                            ? indexNotifier.value - 1
                            : 0,
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
        child: child,
      );
    }

    return child;
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
    final imageBox = multiImageKey.currentContext?.findRenderObject();
    if (imageBox is RenderBox) {
      return Offset.zero & imageBox.size;
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
    final imageBox = multiImageKey.currentContext?.findRenderObject();
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
}

/// The data for a multi-image block, primarily used for
/// serializing and deserializing the block's images.
///
class MultiImageData {
  factory MultiImageData.fromJson(List<dynamic> json) {
    final images = json
        .map((e) => ImageBlockData.fromJson(e as Map<String, dynamic>))
        .toList();
    return MultiImageData(images: images);
  }

  MultiImageData({required this.images});

  final List<ImageBlockData> images;

  List<dynamic> toJson() => images.map((e) => e.toJson()).toList();
}

enum MultiImageLayout {
  browser,
  grid;

  int toIntValue() {
    switch (this) {
      case MultiImageLayout.browser:
        return 0;
      case MultiImageLayout.grid:
        return 1;
    }
  }

  static MultiImageLayout fromIntValue(int value) {
    switch (value) {
      case 0:
        return MultiImageLayout.browser;
      case 1:
        return MultiImageLayout.grid;
      default:
        throw UnimplementedError();
    }
  }

  String get label => switch (this) {
        browser => LocaleKeys.document_plugins_photoGallery_browserLayout.tr(),
        grid => LocaleKeys.document_plugins_photoGallery_gridLayout.tr(),
      };

  FlowySvgData get icon => switch (this) {
        browser => FlowySvgs.photo_layout_browser_s,
        grid => FlowySvgs.photo_layout_grid_s,
      };
}
