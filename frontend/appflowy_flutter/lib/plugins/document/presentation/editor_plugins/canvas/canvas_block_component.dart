import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_board.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_view_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/canvas/canvas_service.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CanvasBlockKeys {
  const CanvasBlockKeys._();

  static const String type = 'canvas_embed';

  /// The canvas this block shows. A block ALWAYS points at a real canvas view
  /// rather than holding a document of its own, so the same canvas can be
  /// embedded in several pages and edited from any of them.
  static const String viewId = 'view_id';

  static const String width = 'width';
  static const String height = 'height';
  static const String collapsed = 'collapsed';
}

Node canvasEmbedNode({
  String? viewId,
  double width = 720,
  double height = 460,
}) =>
    Node(
      type: CanvasBlockKeys.type,
      attributes: {
        CanvasBlockKeys.viewId: viewId,
        CanvasBlockKeys.width: width,
        CanvasBlockKeys.height: height,
      },
    );

class CanvasBlockComponentBuilder extends BlockComponentBuilder {
  CanvasBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CanvasBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class CanvasBlockComponent extends BlockComponentStatefulWidget {
  const CanvasBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<CanvasBlockComponent> createState() => _CanvasBlockComponentState();
}

class _CanvasBlockComponentState extends State<CanvasBlockComponent>
    with BlockComponentConfigurable {
  @override
  Node get node => widget.node;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  CanvasController? _controller;
  ViewListener? _listener;
  ViewPB? _view;
  bool _missing = false;
  bool _loading = false;
  String? _boundViewId;

  String? get _viewId {
    final value = node.attributes[CanvasBlockKeys.viewId];
    return value is String && value.isNotEmpty ? value : null;
  }

  double get _width =>
      (node.attributes[CanvasBlockKeys.width] as num?)?.toDouble() ?? 720;

  double get _height =>
      (node.attributes[CanvasBlockKeys.height] as num?)?.toDouble() ?? 460;

  bool get _collapsed => node.attributes[CanvasBlockKeys.collapsed] == true;

  @override
  void initState() {
    super.initState();
    unawaited(_bind());
  }

  @override
  void didUpdateWidget(covariant CanvasBlockComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_viewId != _boundViewId) {
      unawaited(_bind());
    }
  }

  @override
  void dispose() {
    _listener?.stop();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _bind() async {
    final previous = _listener;
    if (previous != null) {
      unawaited(previous.stop());
    }
    _listener = null;
    _controller?.dispose();
    _controller = null;
    _view = null;
    _missing = false;
    _boundViewId = _viewId;

    final viewId = _viewId;
    if (viewId == null) {
      if (mounted) {
        setState(() {});
      }
      return;
    }

    setState(() => _loading = true);
    final result = await ViewBackendService.getView(viewId);
    if (!mounted) {
      return;
    }
    result.fold(
      (view) {
        _view = view;
        _controller = CanvasController(
          viewId: view.id,
          document: view.canvas?.document ?? CanvasDocument.blank(),
        );
        _listener = ViewListener(viewId: view.id)
          ..start(
            onViewUpdated: (updated) {
              if (!mounted) {
                return;
              }
              _controller?.adoptFromView(updated);
              setState(() => _view = updated);
            },
          );
      },
      (_) => _missing = true,
    );
    setState(() => _loading = false);
  }

  void _write(String key, Object? value) {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction..updateNode(node, {key: value});
    editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    final palette = canvasPaletteOf(
      context,
      theme: _controller?.settings.theme ?? CanvasTheme.auto,
    );
    final editorState = context.read<EditorState>();

    Widget child = _body(palette, editorState);

    child = ResizableMedia(
      width: _width,
      minWidth: 320,
      height: _collapsed ? null : _height,
      minHeight: 220,
      maxHeight: 900,
      editable: editorState.editable,
      onResize: (width) => _write(CanvasBlockKeys.width, width),
      onResizeHeight: _collapsed
          ? null
          : (height) => _write(CanvasBlockKeys.height, height),
      child: child,
    );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }
    return child;
  }

  Widget _body(CanvasPalette palette, EditorState editorState) {
    final corners = BorderRadius.circular(CanvasMetrics.chromeRadius);
    return Container(
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: corners,
        border: Border.all(color: palette.border.withValues(alpha: 0.5)),
        boxShadow: palette.cardShadow(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(palette),
          if (!_collapsed) Expanded(child: _stage(palette, editorState)),
        ],
      ),
    );
  }

  Widget _header(CanvasPalette palette) {
    final name = _view?.name.trim();
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: CanvasMetrics.space3, right: 4),
      color: palette.surface,
      child: Row(
        children: [
          Icon(
            Icons.dashboard_customize_rounded,
            size: 15,
            color: palette.textMuted,
          ),
          const SizedBox(width: CanvasMetrics.space2),
          Expanded(
            child: Text(
              name == null || name.isEmpty
                  ? LocaleKeys.canvas_embed_title.tr()
                  : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: canvasLabelStyle(
                palette,
                size: 12.5,
                weight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
          ),
          CanvasButton(
            icon: _collapsed
                ? Icons.unfold_more_rounded
                : Icons.unfold_less_rounded,
            palette: palette,
            size: 26,
            iconSize: 15,
            tooltip: _collapsed
                ? LocaleKeys.canvas_embed_expand.tr()
                : LocaleKeys.canvas_embed_collapse.tr(),
            onPressed: () => _write(CanvasBlockKeys.collapsed, !_collapsed),
          ),
          if (_controller != null) ...[
            CanvasButton(
              icon: Icons.open_in_full_rounded,
              palette: palette,
              size: 26,
              iconSize: 15,
              tooltip: LocaleKeys.canvas_embed_fullscreen.tr(),
              onPressed: _openFullscreen,
            ),
            CanvasButton(
              icon: Icons.arrow_outward_rounded,
              palette: palette,
              size: 26,
              iconSize: 15,
              tooltip: LocaleKeys.canvas_openStandalone.tr(),
              onPressed: _openStandalone,
            ),
          ],
        ],
      ),
    );
  }

  Widget _stage(CanvasPalette palette, EditorState editorState) {
    if (_loading) {
      return const SizedBox.shrink();
    }
    final controller = _controller;
    if (controller == null) {
      return _picker(palette, editorState);
    }
    // The canvas takes the keyboard while it is being worked in, so the
    // editor's own Backspace and arrow commands must not reach it. Clearing
    // the selection makes every editor shortcut return `ignored`.
    return FocusScope(
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          editorState.selection = null;
        }
      },
      child: CanvasBoard(
        controller: controller,
        editable: editorState.editable,
        embedded: true,
        onOpenView: (view) => context.read<TabsBloc>().openPlugin(view),
        onPickView: (kind) => showInteractiveViewPicker(context),
        onOpenStandalone: _openStandalone,
      ),
    );
  }

  Widget _picker(CanvasPalette palette, EditorState editorState) {
    if (_missing) {
      return Center(
        child: Text(
          LocaleKeys.canvas_embed_missing.tr(),
          style:
              canvasLabelStyle(palette, size: 12.5, color: palette.textMuted),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            LocaleKeys.canvas_embed_empty.tr(),
            style: canvasLabelStyle(
              palette,
              size: 13,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: CanvasMetrics.space3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PickerButton(
                palette: palette,
                label: LocaleKeys.canvas_embed_createNew.tr(),
                icon: Icons.add_rounded,
                primary: true,
                onPressed: editorState.editable ? _createNew : null,
              ),
              const SizedBox(width: CanvasMetrics.space2),
              _PickerButton(
                palette: palette,
                label: LocaleKeys.canvas_embed_embedExisting.tr(),
                icon: Icons.link_rounded,
                onPressed: editorState.editable ? _chooseExisting : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A canvas made from a page belongs to that page: it is created as a child
  /// view, so it is reachable from the sidebar and can be opened on its own.
  Future<void> _createNew() async {
    final documentId = context.read<DocumentBloc?>()?.documentId;
    if (documentId == null || documentId.isEmpty) {
      return;
    }
    final view = await CanvasService.create(parentViewId: documentId);
    if (view == null || !mounted) {
      return;
    }
    _write(CanvasBlockKeys.viewId, view.id);
  }

  Future<void> _chooseExisting() async {
    final view = await showInteractiveViewPicker(
      context,
      filter: (candidate) => candidate.isCanvas,
    );
    if (view == null || !mounted) {
      return;
    }
    _write(CanvasBlockKeys.viewId, view.id);
  }

  void _openStandalone() {
    final view = _view;
    if (view != null) {
      context.read<TabsBloc>().openPlugin(view);
    }
  }

  Future<void> _openFullscreen() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final tabs = context.read<TabsBloc>();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) {
        final palette = canvasPaletteOf(
          context,
          theme: controller.settings.theme,
        );
        return Dialog(
          insetPadding: const EdgeInsets.all(28),
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CanvasMetrics.chromeRadius),
            child: ColoredBox(
              color: palette.canvas,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BlocProvider<TabsBloc>.value(
                      value: tabs,
                      // The same controller, so what is drawn in the dialog is
                      // the same canvas the page is showing — not a copy that
                      // has to be reconciled afterwards.
                      child: CanvasBoard(controller: controller),
                    ),
                  ),
                  Positioned(
                    right: CanvasMetrics.space3,
                    top: CanvasMetrics.space3,
                    child: CanvasSurface(
                      palette: palette,
                      child: CanvasButton(
                        icon: Icons.close_fullscreen_rounded,
                        palette: palette,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.palette,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final CanvasPalette palette;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CanvasMetrics.space3,
            vertical: CanvasMetrics.space2,
          ),
          decoration: BoxDecoration(
            color: primary
                ? palette.accent.withValues(alpha: enabled ? 0.14 : 0.06)
                : palette.raised,
            borderRadius: BorderRadius.circular(CanvasMetrics.controlRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: primary ? palette.accent : palette.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: canvasLabelStyle(
                  palette,
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: primary ? palette.accent : palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
