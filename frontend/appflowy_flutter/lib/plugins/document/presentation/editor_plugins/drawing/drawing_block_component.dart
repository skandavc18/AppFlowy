import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block.dart';
import 'package:appflowy/shared/drawing/excalidraw.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

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

  DrawScene get _scene => DrawScene.decode(_sceneJson) ?? DrawScene.empty();

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

  Future<void> _setScene(String scene) {
    if (scene == _sceneJson) {
      return Future<void>.value();
    }
    return _update({DrawingBlockKeys.scene: scene});
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
    unawaited(
      showVisualBlockFullscreen<void>(
        context: context,
        icon: Icons.draw_rounded,
        title: LocaleKeys.diagrams_drawing_name.tr(),
        subtitle: LocaleKeys.diagrams_drawing_poweredBy.tr(),
        builder: (dialogContext) => _DrawingEditorStage(
          scene: _sceneJson,
          editable: _editable,
          onSceneChanged: (scene) => unawaited(_setScene(scene)),
        ),
      ),
    );
  }
}

/// The fullscreen editing stage: the Excalidraw canvas plus a save affordance.
class _DrawingEditorStage extends StatefulWidget {
  const _DrawingEditorStage({
    required this.scene,
    required this.editable,
    required this.onSceneChanged,
  });

  final String scene;
  final bool editable;
  final ValueChanged<String> onSceneChanged;

  @override
  State<_DrawingEditorStage> createState() => _DrawingEditorStageState();
}

class _DrawingEditorStageState extends State<_DrawingEditorStage> {
  final ExcalidrawEditorController _controller = ExcalidrawEditorController();
  String? _latest;
  Timer? _autosave;
  bool _saving = false;
  bool _pulling = false;

  @override
  void initState() {
    super.initState();
    _latest = widget.scene;
    if (widget.editable) {
      // The editor reports its own changes, but a drawing is worth a second
      // route home: every few seconds the scene is asked for outright.
      _autosave = Timer.periodic(
        const Duration(seconds: 4),
        (_) => unawaited(_pull()),
      );
    }
  }

  @override
  void dispose() {
    _autosave?.cancel();
    // Whatever the editor last reported is written even if the window is
    // closed without pressing anything.
    final latest = _latest;
    if (latest != null && latest != widget.scene) {
      widget.onSceneChanged(latest);
    }
    super.dispose();
  }

  /// Asks the editor for its scene and writes it if it has moved on.
  Future<void> _pull() async {
    if (_pulling || !_controller.isAttached) {
      return;
    }
    _pulling = true;
    try {
      final scene = await _controller.requestScene();
      if (scene == null || scene.isEmpty || !mounted || scene == _latest) {
        return;
      }
      _latest = scene;
      widget.onSceneChanged(scene);
    } finally {
      _pulling = false;
    }
  }

  Future<void> _saveNow() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    await _pull();
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<void> _exportImage(String format) async {
    final data = await _controller.exportImage(format);
    if (!mounted) {
      return;
    }
    if (data == null || data.isEmpty) {
      await exportVisualBlockBytes(context, null, 'drawing.$format');
      return;
    }
    if (format == 'svg') {
      await exportVisualBlockText(context, data, 'drawing.svg');
      return;
    }
    await exportVisualBlockBytes(context, decodeDataUrl(data), 'drawing.png');
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    return Column(
      children: [
        Expanded(
          child: ExcalidrawEditorView(
            controller: _controller,
            scene: widget.scene,
            editable: widget.editable,
            onSceneChanged: (scene) {
              _latest = scene;
              widget.onSceneChanged(scene);
            },
            onReady: () {
              if (mounted) {
                setState(() {});
              }
            },
          ),
        ),
        _SaveBar(
          palette: palette,
          editable: widget.editable,
          saving: _saving,
          onSave: _saveNow,
          onExportPng: () => unawaited(_exportImage('png')),
          onExportSvg: () => unawaited(_exportImage('svg')),
        ),
      ],
    );
  }
}

/// The strip under the canvas: what has been saved, and how to take it away.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.palette,
    required this.editable,
    required this.saving,
    required this.onSave,
    required this.onExportPng,
    required this.onExportSvg,
  });

  final VisualBlockPalette palette;
  final bool editable;
  final bool saving;
  final Future<void> Function() onSave;
  final VoidCallback onExportPng;
  final VoidCallback onExportSvg;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Icon(
            saving ? Icons.sync_rounded : Icons.cloud_done_outlined,
            size: 15,
            color: palette.textMuted,
          ),
          const SizedBox(width: 7),
          Text(
            saving
                ? LocaleKeys.diagrams_drawing_saving.tr()
                : LocaleKeys.diagrams_drawing_saved.tr(),
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
          const Spacer(),
          _BarButton(
            palette: palette,
            icon: Icons.photo_outlined,
            label: LocaleKeys.diagrams_common_exportPng.tr(),
            onTap: onExportPng,
          ),
          const SizedBox(width: 6),
          _BarButton(
            palette: palette,
            icon: Icons.image_outlined,
            label: LocaleKeys.diagrams_common_exportSvg.tr(),
            onTap: onExportSvg,
          ),
          if (editable) ...[
            const SizedBox(width: 10),
            _BarButton(
              palette: palette,
              icon: Icons.check_rounded,
              label: LocaleKeys.button_save.tr(),
              primary: true,
              onTap: () => unawaited(onSave()),
            ),
          ],
        ],
      ),
    );
  }
}

class _BarButton extends StatefulWidget {
  const _BarButton({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final VisualBlockPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final background = widget.primary
        ? (_hovered ? palette.accent.withValues(alpha: 0.88) : palette.accent)
        : (_hovered ? palette.hover : palette.raised);
    final ink = widget.primary
        ? palette.onAccent
        : (_hovered ? palette.text : palette.textSecondary);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: VisualBlockMetrics.hover,
          curve: VisualBlockMetrics.curve,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: ink),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

/// Reads a data URL produced by the editor's own exporter.
Uint8List? decodeDataUrl(String value) {
  final comma = value.indexOf(',');
  if (comma < 0) {
    return null;
  }
  final payload = value.substring(comma + 1);
  try {
    return base64Decode(payload);
  } catch (_) {
    return null;
  }
}
