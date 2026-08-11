import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block.dart';
import 'package:appflowy/shared/mermaid/mermaid.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

import 'mermaid_samples.dart';
import 'mermaid_source_editor.dart';

class MermaidBlockKeys {
  const MermaidBlockKeys._();

  static const String type = 'mermaid';

  /// The Mermaid source. Everything the block needs lives here, so the
  /// diagram survives a restart, a copy and a page duplication.
  static const String source = 'source';
  static const String width = 'width';
  static const String height = 'height';
}

Node mermaidNode({String source = '', double? width, double? height}) => Node(
      type: MermaidBlockKeys.type,
      attributes: {
        MermaidBlockKeys.source: source,
        if (width != null) MermaidBlockKeys.width: width,
        if (height != null) MermaidBlockKeys.height: height,
      },
    );

class MermaidBlockComponentBuilder extends BlockComponentBuilder {
  MermaidBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MermaidBlockComponent(
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
  BlockComponentValidate get validate =>
      (node) => node.attributes[MermaidBlockKeys.source] is String;
}

class MermaidBlockComponent extends BlockComponentStatefulWidget {
  const MermaidBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MermaidBlockComponent> createState() => MermaidBlockComponentState();
}

class MermaidBlockComponentState extends State<MermaidBlockComponent>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  static const double _minimumHeight = 160;
  static const double _defaultHeight = 300;
  static const double _minimumWidth = 280;

  /// How much taller the block stands while the source pane is open.
  static const double _sourceEditorHeight = 280;

  final MermaidViewController _viewport = MermaidViewController();
  bool _editingSource = false;

  EditorState get _editorState => context.read<EditorState>();

  bool get _editable => _editorState.editable;

  String get _source =>
      node.attributes[MermaidBlockKeys.source] as String? ?? '';

  double? get _width {
    final stored = node.attributes[MermaidBlockKeys.width];
    return stored is num ? stored.toDouble() : null;
  }

  double get _height {
    final stored = node.attributes[MermaidBlockKeys.height];
    return stored is num ? stored.toDouble() : _defaultHeight;
  }

  @override
  void dispose() {
    _viewport.dispose();
    super.dispose();
  }

  Future<void> _update(Map<String, Object?> attributes) {
    final transaction = _editorState.transaction
      ..updateNode(node, {...node.attributes, ...attributes});
    return _editorState.apply(transaction);
  }

  Future<void> _setSource(String source) => _update(
        {MermaidBlockKeys.source: source},
      );

  /// Opens the source editor for a block that has none yet, so `/mermaid`
  /// lands somewhere useful rather than on an empty card.
  void showEditor() {
    if (!_editable || !mounted) {
      return;
    }
    setState(() => _editingSource = true);
  }

  @override
  Widget build(BuildContext context) {
    final render = renderMermaid(context, _source);
    final palette = VisualBlockPalette.of(context);

    Widget body;
    if (_source.trim().isEmpty) {
      body = VisualBlockPlaceholder(
        icon: Icons.account_tree_rounded,
        title: LocaleKeys.diagrams_mermaid_placeholderTitle.tr(),
        subtitle: LocaleKeys.diagrams_mermaid_placeholderBody.tr(),
        onTap: _editable ? showEditor : null,
      );
    } else {
      body = MouseRegion(
        cursor: _editable ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _editable ? showEditor : null,
          child: MermaidView(
            render: render,
            controller: _viewport,
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
          ),
        ),
      );
    }

    Widget frame = VisualBlockFrame(
      icon: Icons.account_tree_rounded,
      title: LocaleKeys.diagrams_mermaid_name.tr(),
      semanticsHint: _diagramDescription(render),
      onActivate: _editable ? showEditor : null,
      headerActions: [
        if (_source.trim().isNotEmpty) ...[
          VisualBlockButton(
            icon: Icons.zoom_out_rounded,
            tooltip: LocaleKeys.diagrams_common_zoomOut.tr(),
            palette: palette,
            onTap: () => _viewport.zoomBy(1 / 1.25),
          ),
          VisualBlockButton(
            icon: Icons.zoom_in_rounded,
            tooltip: LocaleKeys.diagrams_common_zoomIn.tr(),
            palette: palette,
            onTap: () => _viewport.zoomBy(1.25),
          ),
          VisualBlockButton(
            icon: Icons.fit_screen_rounded,
            tooltip: LocaleKeys.diagrams_common_fitToScreen.tr(),
            palette: palette,
            onTap: _viewport.reset,
          ),
        ],
        if (_editable)
          VisualBlockButton(
            icon: Icons.code_rounded,
            tooltip: LocaleKeys.diagrams_mermaid_editSource.tr(),
            palette: palette,
            selected: _editingSource,
            onTap: () => setState(() => _editingSource = !_editingSource),
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
          onEdit: showEditor,
          editLabel: LocaleKeys.diagrams_mermaid_editSource.tr(),
          onFullscreen: _openFullscreen,
          onCopySource: () => unawaited(
            copyVisualBlockText(menuContext, _source),
          ),
          exports: _exports(menuContext, render),
          onDuplicate: () =>
              unawaited(duplicateVisualBlock(_editorState, node)),
          onDelete: () => unawaited(deleteVisualBlock(_editorState, node)),
        ),
      ),
      footer: _editingSource && _editable
          ? SizedBox(
              height: _sourceEditorHeight,
              child: MermaidSourceEditor(
                source: _source,
                error: render.scene.error,
                expanded: true,
                onChanged: _setSource,
                onClose: () => setState(() => _editingSource = false),
                onInsertSample: (sample) => unawaited(_setSource(sample)),
              ),
            )
          : null,
      child: body,
    );

    // The source pane sits under the diagram inside the same frame, so the
    // block grows by its height while it is open. The handle still resizes
    // the diagram, which is what the drag is aimed at.
    final sourcePane = _editingSource && _editable ? _sourceEditorHeight : 0.0;

    frame = ResizableMedia(
      width: _width ?? double.infinity,
      minWidth: _minimumWidth,
      height: _height + sourcePane,
      minHeight: _minimumHeight + sourcePane,
      maxHeight: VisualBlockMetrics.maximumEmbedHeight + sourcePane,
      alignment: blockEmbedAlignment(node),
      editable: _editable,
      onResize: (value) => unawaited(_update({MermaidBlockKeys.width: value})),
      onResizeHeight: (value) {
        final diagram = (value - sourcePane).clamp(
          _minimumHeight,
          VisualBlockMetrics.maximumEmbedHeight,
        );
        unawaited(_update({MermaidBlockKeys.height: diagram}));
      },
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

  List<VisualBlockExport> _exports(
    BuildContext context,
    MermaidRender render,
  ) =>
      [
        VisualBlockExport(
          label: LocaleKeys.diagrams_common_exportSvg.tr(),
          icon: Icons.image_outlined,
          run: () => exportVisualBlockText(
            context,
            mermaidSceneToSvg(render.scene, render.palette, render.typography),
            'diagram.svg',
          ),
        ),
        VisualBlockExport(
          label: LocaleKeys.diagrams_common_exportPng.tr(),
          icon: Icons.photo_outlined,
          run: () async {
            final bytes = await mermaidSceneToPng(
              render.scene,
              render.palette,
              render.typography,
            );
            if (!context.mounted) {
              return;
            }
            await exportVisualBlockBytes(context, bytes, 'diagram.png');
          },
        ),
        VisualBlockExport(
          label: LocaleKeys.diagrams_common_exportSource.tr(),
          icon: Icons.description_outlined,
          run: () => exportVisualBlockText(context, _source, 'diagram.mmd'),
        ),
      ];

  void _openFullscreen() {
    unawaited(
      showVisualBlockFullscreen<void>(
        context: context,
        icon: Icons.account_tree_rounded,
        title: LocaleKeys.diagrams_mermaid_name.tr(),
        builder: (dialogContext) => _MermaidFullscreen(
          source: _source,
          editable: _editable,
          onChanged: _setSource,
        ),
      ),
    );
  }

  String _diagramDescription(MermaidRender render) {
    final kind = render.document.kind;
    final nodes = render.document.graph?.nodes.length;
    final name = switch (kind) {
      MermaidDiagramKind.flowchart => 'flowchart',
      MermaidDiagramKind.sequence => 'sequence diagram',
      MermaidDiagramKind.classDiagram => 'class diagram',
      MermaidDiagramKind.state => 'state diagram',
      MermaidDiagramKind.entityRelationship => 'entity relationship diagram',
      MermaidDiagramKind.pie => 'pie chart',
      MermaidDiagramKind.mindmap => 'mind map',
      MermaidDiagramKind.timeline => 'timeline',
      MermaidDiagramKind.journey => 'user journey',
      MermaidDiagramKind.gantt => 'gantt chart',
      MermaidDiagramKind.unsupported => 'diagram',
    };
    return nodes == null ? name : '$name, $nodes nodes';
  }
}

/// The fullscreen reading: the diagram on the left, its source beside it.
class _MermaidFullscreen extends StatefulWidget {
  const _MermaidFullscreen({
    required this.source,
    required this.editable,
    required this.onChanged,
  });

  final String source;
  final bool editable;
  final ValueChanged<String> onChanged;

  @override
  State<_MermaidFullscreen> createState() => _MermaidFullscreenState();
}

class _MermaidFullscreenState extends State<_MermaidFullscreen> {
  late String _source = widget.source;
  final MermaidViewController _viewport = MermaidViewController();
  bool _showSource = false;

  @override
  void dispose() {
    _viewport.dispose();
    super.dispose();
  }

  void _apply(String source) {
    setState(() => _source = source);
    widget.onChanged(source);
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    final render = renderMermaid(context, _source);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: MermaidView(
                  render: render,
                  controller: _viewport,
                  padding: const EdgeInsets.all(28),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: palette.raised,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: palette.border.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VisualBlockButton(
                        icon: Icons.zoom_out_rounded,
                        tooltip: LocaleKeys.diagrams_common_zoomOut.tr(),
                        palette: palette,
                        onTap: () => _viewport.zoomBy(1 / 1.25),
                      ),
                      VisualBlockButton(
                        icon: Icons.fit_screen_rounded,
                        tooltip: LocaleKeys.diagrams_common_fitToScreen.tr(),
                        palette: palette,
                        onTap: _viewport.reset,
                      ),
                      VisualBlockButton(
                        icon: Icons.zoom_in_rounded,
                        tooltip: LocaleKeys.diagrams_common_zoomIn.tr(),
                        palette: palette,
                        onTap: () => _viewport.zoomBy(1.25),
                      ),
                      if (widget.editable)
                        VisualBlockButton(
                          icon: Icons.code_rounded,
                          tooltip: LocaleKeys.diagrams_mermaid_editSource.tr(),
                          palette: palette,
                          selected: _showSource,
                          onTap: () =>
                              setState(() => _showSource = !_showSource),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_showSource && widget.editable)
          SizedBox(
            width: 380,
            child: MermaidSourceEditor(
              source: _source,
              error: render.scene.error,
              expanded: true,
              onChanged: _apply,
              onClose: () => setState(() => _showSource = false),
              onInsertSample: _apply,
            ),
          ),
      ],
    );
  }
}

/// The examples offered when a block is still empty.
List<MermaidSample> get mermaidSamples => kMermaidSamples;
