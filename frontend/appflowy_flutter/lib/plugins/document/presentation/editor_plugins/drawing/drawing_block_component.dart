import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block.dart';
import 'package:appflowy/shared/drawing/excalidraw.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

import 'drawing_editor_stage.dart';
import 'excalidraw_editor_view.dart';

class DrawingBlockKeys {
  const DrawingBlockKeys._();

  static const String type = 'excalidraw';

  /// The whole `.excalidraw` scene — elements, app state and files — as JSON.
  ///
  /// Never a flattened picture: the block always keeps something that can be
  /// reopened and carried on with.
  static const String scene = 'scene';
  static const String width = 'width';
  static const String height = 'height';
}

Node drawingNode({String scene = '', double? width, double? height}) => Node(
      type: DrawingBlockKeys.type,
      attributes: {
        DrawingBlockKeys.scene:
            scene.isEmpty ? DrawScene.empty().encode() : scene,
        if (width != null) DrawingBlockKeys.width: width,
        if (height != null) DrawingBlockKeys.height: height,
      },
    );

class DrawingBlockComponentBuilder extends BlockComponentBuilder {
  DrawingBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return DrawingBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (_, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => true;
}

class DrawingBlockComponent extends BlockComponentStatefulWidget {
  const DrawingBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<DrawingBlockComponent> createState() => DrawingBlockComponentState();
}

class DrawingBlockComponentState extends State<DrawingBlockComponent>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  static const double _minimumHeight = 200;
  static const double _defaultHeight = 360;
  static const double _minimumWidth = 300;

  EditorState get _editorState => context.read<EditorState>();

  bool get _editable => _editorState.editable;

  String get _sceneJson =>
      node.attributes[DrawingBlockKeys.scene] as String? ?? '';

  DrawScene get _scene =>
      DrawScene.decodeCached(_sceneJson) ?? DrawScene.empty();

  double? get _width {
    final stored = node.attributes[DrawingBlockKeys.width];
    return stored is num ? stored.toDouble() : null;
  }

  double get _height {
    final stored = node.attributes[DrawingBlockKeys.height];
    return stored is num ? stored.toDouble() : _defaultHeight;
  }

  Future<void> _update(Map<String, Object?> attributes) {
    final transaction = _editorState.transaction
      ..updateNode(node, {...node.attributes, ...attributes});
    return _editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    final scene = _scene;

    Widget body;
    if (scene.isEmpty) {
      body = VisualBlockPlaceholder(
        icon: Icons.draw_rounded,
        title: LocaleKeys.diagrams_drawing_placeholderTitle.tr(),
        subtitle: LocaleKeys.diagrams_drawing_placeholderBody.tr(),
        onTap: _editable ? openEditor : null,
      );
    } else {
      body = MouseRegion(
        cursor: _editable ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _editable ? openEditor : null,
          child: DrawScenePreview(scene: scene),
        ),
      );
    }

    Widget frame = VisualBlockFrame(
      icon: Icons.draw_rounded,
      title: LocaleKeys.diagrams_drawing_name.tr(),
      semanticsHint: LocaleKeys.diagrams_drawing_shapeCount
          .tr(args: ['${scene.visible.length}']),
      onActivate: _editable ? openEditor : null,
      background: palette.canvas,
      headerActions: [
        VisualBlockButton(
          icon: Icons.edit_rounded,
          tooltip: LocaleKeys.diagrams_drawing_openEditor.tr(),
          palette: palette,
          onTap: openEditor,
        ),
      ],
      menuBuilder: (menuContext) => visualBlockMenuEntries(
        VisualBlockActions(
          editable: _editable,
          onEdit: openEditor,
          editLabel: LocaleKeys.diagrams_drawing_openEditor.tr(),
          onFullscreen: openEditor,
          onCopySource: () => unawaited(
            copyVisualBlockText(
              menuContext,
              _sceneJson,
              message: LocaleKeys.diagrams_drawing_copiedScene.tr(),
            ),
          ),
          copySourceLabel: LocaleKeys.diagrams_drawing_copyScene.tr(),
          exports: _exports(menuContext, scene),
          onDuplicate: () =>
              unawaited(duplicateVisualBlock(_editorState, node)),
          onDelete: () => unawaited(deleteVisualBlock(_editorState, node)),
        ),
      ),
      child: body,
    );

    frame = ResizableMedia(
      width: _width ?? double.infinity,
      minWidth: _minimumWidth,
      height: _height,
      minHeight: _minimumHeight,
      maxHeight: VisualBlockMetrics.maximumEmbedHeight,
      alignment: blockEmbedAlignment(node),
      editable: _editable,
      onResize: (value) => unawaited(_update({DrawingBlockKeys.width: value})),
      onResizeHeight: (value) =>
          unawaited(_update({DrawingBlockKeys.height: value})),
      child: frame,
    );

    Widget child = Padding(padding: padding, child: frame);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    if (UniversalPlatform.isMobile) {
      child = MobileBlockActionButtons(
        node: node,
        editorState: _editorState,
        child: child,
      );
    }

    return child;
  }

  List<VisualBlockExport> _exports(BuildContext context, DrawScene scene) {
    final brightness = Theme.of(context).brightness;
    return [
      VisualBlockExport(
        label: LocaleKeys.diagrams_drawing_exportScene.tr(),
        icon: Icons.data_object_rounded,
        run: () => exportVisualBlockText(
          context,
          scene.encode(pretty: true),
          'drawing.excalidraw',
        ),
      ),
      VisualBlockExport(
        label: LocaleKeys.diagrams_common_exportPng.tr(),
        icon: Icons.photo_outlined,
        run: () async {
          final bytes = await drawSceneToPng(scene, brightness);
          if (!context.mounted) {
            return;
          }
          await exportVisualBlockBytes(context, bytes, 'drawing.png');
        },
      ),
      VisualBlockExport(
        label: LocaleKeys.diagrams_common_exportSvg.tr(),
        icon: Icons.image_outlined,
        run: () => exportVisualBlockText(
          context,
          drawSceneToSvg(scene, brightness),
          'drawing.svg',
        ),
      ),
    ];
  }

  /// Opens the real Excalidraw editor at window size.
  ///
  /// It is only started here — a page full of drawings shows previews and
  /// boots no browser at all.
  void openEditor() {
    if (!canRunExcalidrawEditor) {
      return;
    }
    // Captured now: the scene may arrive after this block has been rebuilt or
    // scrolled away, and it still belongs to the same node.
    final editorState = _editorState;
    final node = this.node;
    unawaited(
      showDrawingEditor(
        context,
        title: LocaleKeys.diagrams_drawing_name.tr(),
        scene: _sceneJson,
        editable: _editable,
        onSceneChanged: (scene) =>
            unawaited(writeDrawingScene(editorState, node, scene)),
      ),
    );
  }
}

/// Writes [scene] into the drawing block [node] of [editorState].
///
/// Deliberately not tied to the block's widget: the editor reports its final
/// scene as it closes, and by then the block may have been rebuilt. The node
/// is what carries the drawing, so it is written as long as it is still in
/// the document.
@visibleForTesting
Future<void> writeDrawingScene(
  EditorState editorState,
  Node node,
  String scene,
) async {
  if (node.attributes[DrawingBlockKeys.scene] == scene) {
    return;
  }
  if (editorState.getNodeAtPath(node.path) != node) {
    // The block was deleted while its drawing was open.
    return;
  }
  try {
    final transaction = editorState.transaction
      ..updateNode(node, {...node.attributes, DrawingBlockKeys.scene: scene});
    await editorState.apply(transaction);
  } on Object catch (error) {
    Log.warn('The drawing could not be written to its block: $error');
  }
}

/// Draws a stored scene without starting the editor.
///
/// This is what a page shows: the same elements, painted by Flutter, so twenty
/// drawings in a document cost twenty pictures rather than twenty browsers.
class DrawScenePreview extends StatelessWidget {
  const DrawScenePreview({
    super.key,
    required this.scene,
    this.padding = const EdgeInsets.fromLTRB(14, 4, 14, 14),
  });

  final DrawScene scene;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final bounds = scene.contentBounds;
    if (bounds == null || bounds.isEmpty) {
      return const SizedBox.shrink();
    }
    final frame = bounds.inflate(16);
    return Padding(
      padding: padding,
      child: RepaintBoundary(
        child: FittedBox(
          child: SizedBox(
            width: frame.width,
            height: frame.height,
            child: CustomPaint(
              painter: _PreviewPainter(
                scene: scene,
                origin: frame.topLeft,
                brightness: Theme.of(context).brightness,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({
    required this.scene,
    required this.origin,
    required this.brightness,
  });

  final DrawScene scene;
  final Offset origin;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-origin.dx, -origin.dy);
    DrawScenePainter(scene: scene, brightness: brightness).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter oldDelegate) =>
      oldDelegate.scene != scene ||
      oldDelegate.origin != origin ||
      oldDelegate.brightness != brightness;
}
