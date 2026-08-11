import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block.dart';
import 'package:appflowy/shared/mind_map/mind_map.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

class MindMapBlockKeys {
  const MindMapBlockKeys._();

  static const String type = 'mind_map';

  /// The whole tree, as JSON. Nothing about the map lives anywhere else, so a
  /// copied block is a working copy of the map.
  static const String data = 'data';
  static const String width = 'width';
  static const String height = 'height';
}

Node mindMapNode({
  MindMapDocument? document,
  double? width,
  double? height,
}) =>
    Node(
      type: MindMapBlockKeys.type,
      attributes: {
        MindMapBlockKeys.data:
            jsonEncode((document ?? MindMapDocument.blank()).toJson()),
        if (width != null) MindMapBlockKeys.width: width,
        if (height != null) MindMapBlockKeys.height: height,
      },
    );

class MindMapBlockComponentBuilder extends BlockComponentBuilder {
  MindMapBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MindMapBlockComponent(
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

class MindMapBlockComponent extends BlockComponentStatefulWidget {
  const MindMapBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MindMapBlockComponent> createState() => MindMapBlockComponentState();
}

class MindMapBlockComponentState extends State<MindMapBlockComponent>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  static const double _minimumHeight = 220;
  static const double _defaultHeight = 380;
  static const double _minimumWidth = 320;

  final GlobalKey<MindMapCanvasState> _canvasKey =
      GlobalKey<MindMapCanvasState>();
  late MindMapController _controller;
  String _lastWritten = '';
  bool _writing = false;

  EditorState get _editorState => context.read<EditorState>();

  bool get _editable => _editorState.editable;

  @override
  void initState() {
    super.initState();
    _lastWritten = _storedJson;
    _controller = MindMapController(
      document: _readDocument(),
      onChanged: _persist,
    );
  }

  @override
  void didUpdateWidget(covariant MindMapBlockComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An undo on the page, or a change made in the fullscreen editor, arrives
    // here as a new attribute. A rebuild that lands while our own write is
    // still in flight would otherwise see the stale attribute and adopt it,
    // throwing the live map away.
    if (_writing) {
      return;
    }
    final stored = _storedJson;
    if (stored != _lastWritten) {
      _lastWritten = stored;
      _controller.adopt(_readDocument());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _storedJson =>
      node.attributes[MindMapBlockKeys.data] as String? ?? '';

  MindMapDocument _readDocument() {
    final stored = _storedJson;
    if (stored.trim().isEmpty) {
      return MindMapDocument.blank();
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is Map) {
        return MindMapDocument.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // A map that cannot be read is better replaced than lost behind an
      // error: the source is still on the node for anyone who wants it.
    }
    return MindMapDocument.blank();
  }

  Future<void> _persist(MindMapDocument document) async {
    if (!mounted || !_editable) {
      return;
    }
    final encoded = jsonEncode(document.toJson());
    if (encoded == _storedJson) {
      return;
    }
    _lastWritten = encoded;
    _writing = true;
    try {
      await _update({MindMapBlockKeys.data: encoded});
    } finally {
      _writing = false;
    }
  }

  Future<void> _update(Map<String, Object?> attributes) {
    final transaction = _editorState.transaction
      ..updateNode(node, {...node.attributes, ...attributes});
    return _editorState.apply(transaction);
  }

  double? get _width {
    final stored = node.attributes[MindMapBlockKeys.width];
    return stored is num ? stored.toDouble() : null;
  }

  double get _height {
    final stored = node.attributes[MindMapBlockKeys.height];
    return stored is num ? stored.toDouble() : _defaultHeight;
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);

    Widget frame = VisualBlockFrame(
      icon: Icons.hub_rounded,
      title: LocaleKeys.diagrams_mindMap_name.tr(),
      semanticsHint: LocaleKeys.diagrams_mindMap_nodeCount
          .tr(args: ['${_controller.document.nodeCount}']),
      background: palette.canvas,
      headerActions: [
        VisualBlockButton(
          icon: Icons.unfold_less_rounded,
          tooltip: LocaleKeys.diagrams_mindMap_collapseAll.tr(),
          palette: palette,
          onTap: () => _controller.setCollapsedEverywhere(collapsed: true),
        ),
        VisualBlockButton(
          icon: Icons.unfold_more_rounded,
          tooltip: LocaleKeys.diagrams_mindMap_expandAll.tr(),
          palette: palette,
          onTap: () => _controller.setCollapsedEverywhere(collapsed: false),
        ),
        VisualBlockButton(
          icon: Icons.open_in_full_rounded,
          tooltip: LocaleKeys.diagrams_common_fullscreen.tr(),
          palette: palette,
          onTap: _openFullscreen,
        ),
      ],
      menuBuilder: (menuContext) => visualBlockMenuEntries(
        VisualBlockActions(
          editable: _editable,
          onFullscreen: _openFullscreen,
          onCopySource: () => unawaited(
            copyVisualBlockText(menuContext, _controller.document.toOutline()),
          ),
          copySourceLabel: LocaleKeys.diagrams_mindMap_copyOutline.tr(),
          exports: _exports(menuContext),
          onDuplicate: () =>
              unawaited(duplicateVisualBlock(_editorState, node)),
          onDelete: () => unawaited(deleteVisualBlock(_editorState, node)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(VisualBlockMetrics.cardRadius),
        ),
        child: MindMapCanvas(
          key: _canvasKey,
          controller: _controller,
          editable: _editable,
          onRequestFullscreen: _openFullscreen,
        ),
      ),
    );

    frame = ResizableMedia(
      width: _width ?? double.infinity,
      minWidth: _minimumWidth,
      height: _height,
      minHeight: _minimumHeight,
      maxHeight: VisualBlockMetrics.maximumEmbedHeight,
      alignment: blockEmbedAlignment(node),
      editable: _editable,
      onResize: (value) => unawaited(_update({MindMapBlockKeys.width: value})),
      onResizeHeight: (value) =>
          unawaited(_update({MindMapBlockKeys.height: value})),
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

  List<VisualBlockExport> _exports(BuildContext context) {
    final palette = MindMapPalette.of(context);
    final base = DefaultTextStyle.of(context).style;

    return [
      VisualBlockExport(
        label: LocaleKeys.diagrams_common_exportPng.tr(),
        icon: Icons.photo_outlined,
        run: () async {
          final bytes =
              await mindMapToPng(_measuredLayout(context), palette, base);
          if (!context.mounted) {
            return;
          }
          await exportVisualBlockBytes(context, bytes, 'mind-map.png');
        },
      ),
      VisualBlockExport(
        label: LocaleKeys.diagrams_common_exportSvg.tr(),
        icon: Icons.image_outlined,
        run: () => exportVisualBlockText(
          context,
          mindMapToSvg(_measuredLayout(context), palette, base),
          'mind-map.svg',
        ),
      ),
      VisualBlockExport(
        label: LocaleKeys.diagrams_common_exportJson.tr(),
        icon: Icons.data_object_rounded,
        run: () => exportVisualBlockText(
          context,
          const JsonEncoder.withIndent('  ').convert(
            _controller.document.toJson(),
          ),
          'mind-map.json',
        ),
      ),
      VisualBlockExport(
        label: LocaleKeys.diagrams_mindMap_exportMermaid.tr(),
        icon: Icons.account_tree_rounded,
        run: () => exportVisualBlockText(
          context,
          _controller.document.toMermaid(),
          'mind-map.mmd',
        ),
      ),
    ];
  }

  /// Lays the map out with real text measurement, so an export matches what
  /// is on screen rather than a guessed node size.
  MindMapLayout _measuredLayout(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    return layoutMindMap(
      _controller.document,
      (node, depth) {
        final painter = TextPainter(
          text: TextSpan(
            text: node.text.isEmpty ? ' ' : node.text,
            style: base.copyWith(
              fontSize: MindMapCanvasMetrics.fontSizeFor(depth),
              fontWeight: MindMapCanvasMetrics.weightFor(depth),
              height: 1.3,
            ),
          ),
          textDirection: ui.TextDirection.ltr,
          maxLines: MindMapCanvasMetrics.maximumNodeLines,
        )..layout(
            maxWidth: MindMapCanvasMetrics.maximumNodeWidth -
                MindMapCanvasMetrics.nodePaddingX * 2,
          );
        final size = Size(
          (painter.width + MindMapCanvasMetrics.nodePaddingX * 2)
              .clamp(MindMapCanvasMetrics.minimumNodeWidth, double.infinity),
          (painter.height + MindMapCanvasMetrics.nodePaddingY * 2)
              .clamp(MindMapCanvasMetrics.minimumNodeHeight, double.infinity),
        );
        painter.dispose();
        return size;
      },
      mode: _controller.mode,
    );
  }

  void _openFullscreen() {
    _controller.flush();
    unawaited(
      showVisualBlockFullscreen<void>(
        context: context,
        icon: Icons.hub_rounded,
        title: LocaleKeys.diagrams_mindMap_name.tr(),
        builder: (dialogContext) => MindMapCanvas(
          controller: _controller,
          editable: _editable,
          autofocus: true,
        ),
      ),
    );
  }
}
