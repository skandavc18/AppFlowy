import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_board.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_export.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_view_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A canvas as a page of its own.
///
/// Everything a canvas can do is on the board; this wraps it in the pieces a
/// first-class object needs — the view's name, keeping the document in step
/// with the backend, and the ways out of the canvas into the rest of AppFlowy.
class CanvasPage extends StatefulWidget {
  const CanvasPage({
    super.key,
    required this.view,
    this.editable = true,
  });

  final ViewPB view;
  final bool editable;

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage> {
  late CanvasController _controller;
  late ViewListener _listener;
  final GlobalKey<CanvasBoardState> _boardKey = GlobalKey<CanvasBoardState>();

  @override
  void initState() {
    super.initState();
    _controller = CanvasController(
      viewId: widget.view.id,
      document: widget.view.canvas?.document ?? CanvasDocument.blank(),
    );
    _listener = ViewListener(viewId: widget.view.id)
      ..start(
        onViewUpdated: (view) {
          if (!mounted) {
            return;
          }
          _controller.adoptFromView(view);
        },
      );
  }

  @override
  void didUpdateWidget(covariant CanvasPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id) {
      _swapController();
    }
  }

  void _swapController() {
    final previous = _controller;
    _controller = CanvasController(
      viewId: widget.view.id,
      document: widget.view.canvas?.document ?? CanvasDocument.blank(),
    );
    previous.dispose();
    _listener.stop();
    _listener = ViewListener(viewId: widget.view.id)
      ..start(onViewUpdated: (view) => _controller.adoptFromView(view));
  }

  @override
  void dispose() {
    _listener.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = canvasPaletteOf(context, theme: _controller.settings.theme);
    return ColoredBox(
      color: palette.canvas,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => CanvasBoard(
          key: _boardKey,
          controller: _controller,
          editable: widget.editable,
          onOpenView: _openView,
          onPickView: _pickView,
          onCreatePage: _createPage,
          onExport: _export,
        ),
      ),
    );
  }

  void _openView(ViewPB view) {
    context.read<TabsBloc>().openPlugin(view);
  }

  Future<ViewPB?> _pickView(CanvasNodeKind kind) async {
    return showInteractiveViewPicker(
      context,
      filter: (view) => switch (kind) {
        CanvasNodeKind.page =>
          view.layout == ViewLayoutPB.Document && !view.isCanvas,
        CanvasNodeKind.canvas => view.isCanvas,
        CanvasNodeKind.database => const [
            ViewLayoutPB.Grid,
            ViewLayoutPB.Board,
            ViewLayoutPB.Calendar,
          ].contains(view.layout),
        CanvasNodeKind.file => view.isWorkspaceFile,
        _ => true,
      },
    );
  }

  /// Turning a card into a page: the page is real, it lands beside the canvas,
  /// and the canvas keeps its shape by pointing at it.
  Future<ViewPB?> _createPage(String title, String body) async {
    final parent = widget.view.parentViewId;
    if (parent.isEmpty) {
      return null;
    }
    // A page is created WITH its content. Writing into an existing page needs
    // the document to be opened first, which is a great deal of ceremony for
    // something that has nothing in it yet.
    final seed = body.trim().isEmpty
        ? null
        : DocumentDataPBFromTo.fromDocument(customMarkdownToDocument(body))
            ?.writeToBuffer();
    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parent,
      name: title.trim().isEmpty
          ? LocaleKeys.menuAppHeader_defaultNewPageName.tr()
          : title.trim(),
      initialDataBytes: seed,
    );
    final view = result.fold((view) => view, (error) {
      Log.error('Could not turn a canvas card into a page', error);
      return null;
    });
    if (view != null && mounted) {
      showToastNotification(
        message: LocaleKeys.canvas_card_convertedToPage.tr(),
      );
    }
    return view;
  }

  Future<void> _export() async {
    final board = _boardKey.currentState;
    if (board == null) {
      return;
    }
    final palette = canvasPaletteOf(context, theme: _controller.settings.theme);
    final document = _controller.document;
    if (document.isEmpty) {
      showToastNotification(message: LocaleKeys.canvas_export_nothing.tr());
      return;
    }

    final box = context.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? Offset.zero
        : box.localToGlobal(Offset(box.size.width / 2, 120));

    await showAppMenu<void>(
      context: context,
      globalPosition: anchor,
      entries: [
        AppMenuHeader(LocaleKeys.canvas_export_title.tr()),
        for (final scope in CanvasExportScope.values)
          AppMenuItem(
            label: switch (scope) {
              CanvasExportScope.everything =>
                LocaleKeys.canvas_export_everything.tr(),
              CanvasExportScope.viewport =>
                LocaleKeys.canvas_export_viewport.tr(),
              CanvasExportScope.selection =>
                LocaleKeys.canvas_export_selection.tr(),
            },
            enabled: scope != CanvasExportScope.selection ||
                _controller.hasSelection,
            submenu: [
              AppMenuItem(
                label: LocaleKeys.canvas_export_png.tr(),
                icon: Icons.image_rounded,
                onSelected: () => _writePng(scope, palette),
              ),
              AppMenuItem(
                label: LocaleKeys.canvas_export_svg.tr(),
                icon: Icons.polyline_rounded,
                onSelected: () => _writeSvg(scope, palette),
              ),
              AppMenuItem(
                label: LocaleKeys.canvas_export_copyImage.tr(),
                icon: Icons.copy_rounded,
                onSelected: () => _copyPng(scope, palette),
              ),
            ],
          ),
      ],
    );
  }

  Rect? _boundsFor(CanvasExportScope scope) => canvasExportBounds(
        _controller.document,
        scope: scope,
        selection: _controller.selection,
        viewport: _boardKey.currentState?.visibleScene,
      );

  Future<void> _writePng(CanvasExportScope scope, CanvasPalette palette) async {
    final bounds = _boundsFor(scope);
    if (bounds == null) {
      showToastNotification(message: LocaleKeys.canvas_export_nothing.tr());
      return;
    }
    final bytes = await canvasToPng(
      _controller.document,
      palette,
      bounds: bounds,
      baseStyle: DefaultTextStyle.of(context).style,
    );
    if (bytes == null) {
      showToastNotification(
        message: LocaleKeys.canvas_export_failed.tr(),
        type: ToastificationType.error,
      );
      return;
    }
    await saveMediaBytes(bytes: bytes, name: '${_fileName()}.png');
  }

  Future<void> _writeSvg(CanvasExportScope scope, CanvasPalette palette) async {
    final bounds = _boundsFor(scope);
    if (bounds == null) {
      showToastNotification(message: LocaleKeys.canvas_export_nothing.tr());
      return;
    }
    final svg = canvasToSvg(_controller.document, palette, bounds: bounds);
    await saveMediaBytes(
      bytes: Uint8List.fromList(utf8.encode(svg)),
      name: '${_fileName()}.svg',
    );
  }

  Future<void> _copyPng(CanvasExportScope scope, CanvasPalette palette) async {
    final bounds = _boundsFor(scope);
    if (bounds == null) {
      return;
    }
    final bytes = await canvasToPng(
      _controller.document,
      palette,
      bounds: bounds,
      baseStyle: DefaultTextStyle.of(context).style,
    );
    if (bytes == null) {
      return;
    }
    await getIt<ClipboardService>().setData(
      ClipboardServiceData(image: ('png', bytes)),
    );
    showToastNotification(message: LocaleKeys.canvas_export_copied.tr());
  }

  String _fileName() {
    final name = widget.view.name.trim();
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return safe.isEmpty ? 'canvas' : safe;
  }
}
