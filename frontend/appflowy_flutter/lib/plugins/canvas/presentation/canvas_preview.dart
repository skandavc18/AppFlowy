import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_board.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_export.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_preview.dart'
    show BoardPreviewEmptyNote;
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A canvas as it really looks, framed to show everything on it, read only.
///
/// The real board is built against a controller with an empty view id, which
/// never writes, and the stored camera is set aside so the preview opens on
/// the whole canvas rather than wherever it was last left. Nothing inside takes
/// the pointer or the keyboard.
class CanvasLivePreview extends StatefulWidget {
  const CanvasLivePreview({super.key, required this.document});

  final CanvasDocument document;

  @override
  State<CanvasLivePreview> createState() => _CanvasLivePreviewState();
}

class _CanvasLivePreviewState extends State<CanvasLivePreview> {
  late CanvasController _controller = _controllerFor(widget.document);

  static CanvasController _controllerFor(CanvasDocument document) =>
      CanvasController(
        viewId: '',
        document: document.copyWith(
          settings: document.settings.copyWith(
            viewport: const CanvasViewport(),
          ),
        ),
      );

  @override
  void didUpdateWidget(covariant CanvasLivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      final previous = _controller;
      _controller = _controllerFor(widget.document);
      // The board detaches from the old controller while it rebuilds.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final board = ExcludeFocus(
      child: IgnorePointer(
        child: CanvasBoard(
          key: const ValueKey('canvas-preview-board'),
          controller: _controller,
          editable: false,
          embedded: true,
          showChrome: false,
          // A preview pane is small: the page's roomy margin would leave the
          // canvas a postage stamp in the middle of it.
          fitPadding: 20,
          refitOnResize: true,
        ),
      ),
    );
    if (!widget.document.isEmpty) return board;
    return Stack(
      fit: StackFit.expand,
      children: [
        board,
        BoardPreviewEmptyNote(
          key: const ValueKey('canvas-preview-empty'),
          icon: Icons.dashboard_customize_rounded,
          message: LocaleKeys.viewLibrary_emptyCanvas.tr(),
        ),
      ],
    );
  }
}

/// A canvas drawn small: its frames, connections, cards and their words.
///
/// It paints with the same still renderer the PNG export uses, so it reads no
/// page, database or picture and costs one paint for a wall of cards.
class CanvasMiniature extends StatelessWidget {
  const CanvasMiniature({super.key, required this.document});

  final CanvasDocument document;

  @override
  Widget build(BuildContext context) {
    final bounds = canvasExportBounds(document);
    if (bounds == null) {
      return BoardPreviewEmptyNote(
        key: const ValueKey('canvas-miniature-empty'),
        icon: Icons.dashboard_customize_rounded,
        message: LocaleKeys.viewLibrary_emptyCanvas.tr(),
        compact: true,
      );
    }
    final palette = canvasPaletteOf(context, theme: document.settings.theme);
    return CustomPaint(
      key: const ValueKey('canvas-miniature'),
      size: Size.infinite,
      painter: _CanvasStillPainter(
        document: document,
        palette: palette,
        bounds: bounds,
        baseStyle: DefaultTextStyle.of(context).style,
      ),
    );
  }
}

class _CanvasStillPainter extends CustomPainter {
  const _CanvasStillPainter({
    required this.document,
    required this.palette,
    required this.bounds,
    required this.baseStyle,
  });

  final CanvasDocument document;
  final CanvasPalette palette;
  final Rect bounds;
  final TextStyle baseStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    paintCanvasStill(
      canvas,
      document,
      palette,
      bounds,
      size,
      baseStyle: baseStyle,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CanvasStillPainter oldDelegate) =>
      oldDelegate.document != document ||
      oldDelegate.bounds != bounds ||
      oldDelegate.palette.canvas != palette.canvas ||
      oldDelegate.palette.surface != palette.surface ||
      oldDelegate.palette.textPrimary != palette.textPrimary;
}
