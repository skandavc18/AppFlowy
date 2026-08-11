import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mermaid_layout.dart';
import 'mermaid_model.dart';
import 'mermaid_painter.dart';
import 'mermaid_parser.dart';
import 'mermaid_scene.dart';
import 'mermaid_theme.dart';

/// A parsed and laid-out diagram, kept together so a view can hand the whole
/// thing to an exporter without doing the work twice.
@immutable
class MermaidRender {
  const MermaidRender({
    required this.document,
    required this.scene,
    required this.palette,
    required this.typography,
  });

  final MermaidDocument document;
  final MermaidScene scene;
  final MermaidPalette palette;
  final MermaidTypography typography;
}

/// Builds a render for the given source in the current theme.
///
/// Parsing and layout are pure and fast — a few hundred microseconds for a
/// normal diagram — so this is safe to call from a build, but callers that
/// re-render while somebody types should debounce first.
MermaidRender renderMermaid(
  BuildContext context,
  String source, {
  TextStyle? baseStyle,
}) {
  final palette = mermaidPaletteOf(context);
  final base = (baseStyle ?? DefaultTextStyle.of(context).style).copyWith(
    color: palette.text,
    decoration: TextDecoration.none,
  );
  final typography = MermaidTypography(
    base: base,
    mono: base.copyWith(
      fontFamily: 'RobotoMono',
      fontFamilyFallback: const [
        'JetBrains Mono',
        'Consolas',
        'Menlo',
        'monospace',
      ],
    ),
  );
  final document = parseMermaid(source);
  final scene = layoutMermaid(document, mermaidMeasurer(typography));
  return MermaidRender(
    document: document,
    scene: scene,
    palette: palette,
    typography: typography,
  );
}

/// Draws a diagram, scaled to fit its box and pannable once it is zoomed.
///
/// The whole thing is Flutter paint — there is no browser anywhere — so it
/// takes the page's colours, exports cleanly and costs one repaint.
class MermaidView extends StatefulWidget {
  const MermaidView({
    super.key,
    required this.render,
    this.interactive = true,
    this.padding = const EdgeInsets.all(8),
    this.maximumScale = 4,
    this.fit = true,
    this.controller,
  });

  final MermaidRender render;

  /// Whether the pointer can zoom and pan the drawing.
  final bool interactive;
  final EdgeInsets padding;
  final double maximumScale;

  /// Scale the diagram down so the whole of it is visible. Turning this off
  /// draws it at its natural size and lets the viewport scroll.
  final bool fit;

  final MermaidViewController? controller;

  @override
  State<MermaidView> createState() => _MermaidViewState();
}

/// Lets a host reset or step the zoom of a [MermaidView].
class MermaidViewController extends ChangeNotifier {
  double _requestedScale = 0;
  int _resetToken = 0;

  double get requestedScale => _requestedScale;
  int get resetToken => _resetToken;

  void reset() {
    _requestedScale = 0;
    _resetToken += 1;
    notifyListeners();
  }

  void zoomBy(double factor) {
    _requestedScale = factor;
    notifyListeners();
  }
}

class _MermaidViewState extends State<MermaidView> {
  final TransformationController _transform = TransformationController();
  int _lastReset = 0;
  double _fitScale = 1;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant MermaidView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
    if (oldWidget.render.scene != widget.render.scene) {
      _transform.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    _transform.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final controller = widget.controller;
    if (controller == null) {
      return;
    }
    if (controller.resetToken != _lastReset) {
      _lastReset = controller.resetToken;
      _transform.value = Matrix4.identity();
      return;
    }
    final factor = controller.requestedScale;
    if (factor != 0) {
      final current = _transform.value.getMaxScaleOnAxis();
      final next = (current * factor).clamp(0.4, widget.maximumScale);
      _transform.value = Matrix4.diagonal3Values(next, next, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.render.scene;
    if (scene.error != null) {
      return _MermaidNotice(
          message: scene.error!, palette: widget.render.palette);
    }
    if (scene.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = Size(
          math.max(1, constraints.maxWidth - widget.padding.horizontal),
          math.max(
            1,
            constraints.hasBoundedHeight
                ? constraints.maxHeight - widget.padding.vertical
                : scene.size.height,
          ),
        );
        _fitScale = widget.fit
            ? math.min(
                1.0,
                math.min(
                  available.width / scene.size.width,
                  available.height / scene.size.height,
                ),
              )
            : 1.0;

        final drawing = SizedBox(
          width: scene.size.width * _fitScale,
          height: scene.size.height * _fitScale,
          child: FittedBox(
            child: SizedBox(
              width: scene.size.width,
              height: scene.size.height,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: scene.size,
                  painter: MermaidPainter(
                    scene: scene,
                    palette: widget.render.palette,
                    typography: widget.render.typography,
                  ),
                ),
              ),
            ),
          ),
        );

        final body = Padding(
          padding: widget.padding,
          child: Center(child: drawing),
        );

        if (!widget.interactive) {
          return body;
        }

        return InteractiveViewer(
          transformationController: _transform,
          minScale: 0.4,
          maxScale: widget.maximumScale,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          clipBehavior: Clip.none,
          trackpadScrollCausesScale: true,
          child: body,
        );
      },
    );
  }
}

/// The quiet card shown when a source could not be read.
class _MermaidNotice extends StatelessWidget {
  const _MermaidNotice({required this.message, required this.palette});

  final String message;
  final MermaidPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_rounded,
              size: 22,
              color: palette.textMuted,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps the wheel inside a diagram from stealing the page's scroll.
///
/// The canvas only claims a pointer signal while a modifier is held, which is
/// the same bargain the rest of the application strikes with embedded
/// canvases.
class MermaidScrollGuard extends StatelessWidget {
  const MermaidScrollGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) {
            return;
          }
          final pressed = HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          if (!pressed) {
            // Let the page have it.
            return;
          }
          GestureBinding.instance.pointerSignalResolver.register(event, (_) {});
        },
        child: child,
      );
}
