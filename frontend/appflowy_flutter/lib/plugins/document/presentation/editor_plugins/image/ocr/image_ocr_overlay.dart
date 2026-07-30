import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_controls.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ocr_result.dart';
import 'ocr_service.dart';

/// Opens the text scanner over a picture.
Future<void> showImageOcrOverlay(
  BuildContext context, {
  required ImageEditorSource source,
  required String name,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: const Color(0x00000000),
      transitionDuration: ImageEditorMotion.reveal,
      reverseTransitionDuration: ImageEditorMotion.fast,
      pageBuilder: (_, __, ___) => ImageOcrOverlay(source: source, name: name),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: ImageEditorMotion.curve,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class ImageOcrOverlay extends StatefulWidget {
  const ImageOcrOverlay({
    super.key,
    required this.source,
    required this.name,
    this.service,
  });

  final ImageEditorSource source;
  final String name;

  /// Injected by tests; production uses the platform's own engines.
  final OcrService? service;

  @override
  State<ImageOcrOverlay> createState() => _ImageOcrOverlayState();
}

class _ImageOcrOverlayState extends State<ImageOcrOverlay>
    with SingleTickerProviderStateMixin {
  static const double _panelWidth = 300;

  ui.Image? _image;
  OcrResult? _result;
  String? _errorMessage;
  String? _errorHint;
  bool _scanning = true;

  final Set<int> _selected = <int>{};
  int? _hovered;

  /// Drives the acknowledgement for a click-to-copy: a ring around the region
  /// and a short lived pill, both fading on the same timeline.
  late final AnimationController _copyPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  int? _pulsedLine;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  @override
  void dispose() {
    _copyPulse.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _errorMessage = null;
      _errorHint = null;
      _selected.clear();
    });

    File? temporary;
    try {
      final bytes = await widget.source.readBytes();
      final image = _image ?? await decodeEditableImage(bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);

      final local = File(widget.source.url);
      File file;
      if (!widget.source.isRemote && local.existsSync()) {
        file = local;
      } else {
        final directory = await getTemporaryDirectory();
        temporary = File(
          p.join(
            directory.path,
            'appflowy-ocr-${DateTime.now().microsecondsSinceEpoch}'
            '.${imageExtensionFor(sniffImageFormat(bytes))}',
          ),
        );
        await temporary.writeAsBytes(bytes, flush: true);
        file = temporary;
      }

      final service = widget.service ?? OcrService();
      final result = await service.recognize(
        file,
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _scanning = false;
      });
    } on OcrUnavailableException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _errorHint = e.hint;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Text recognition failed.';
          _errorHint = e.toString();
          _scanning = false;
        });
      }
    } finally {
      if (temporary != null) {
        unawaited(temporary.delete().catchError((_) => temporary!));
      }
    }
  }

  List<OcrLine> get _lines => _result?.lines ?? const [];

  bool get _hasText => _lines.isNotEmpty;

  void _setSelection(Iterable<int> indices, {bool additive = false}) {
    setState(() {
      if (!additive) {
        _selected.clear();
      }
      for (final index in indices) {
        if (additive && _selected.contains(index)) {
          _selected.remove(index);
        } else {
          _selected.add(index);
        }
      }
    });
  }

  void _selectAll() => _setSelection(
        List<int>.generate(_lines.length, (index) => index),
      );

  /// A plain click on a region is the fast path: select it, put it on the
  /// clipboard and say so in place, without interrupting with a toast.
  Future<void> _selectAndCopy(int index) async {
    if (index < 0 || index >= _lines.length) {
      return;
    }
    _setSelection([index]);
    final copied = await _copy(_lines[index].text, showToast: false);
    if (!copied || !mounted) {
      return;
    }
    setState(() => _pulsedLine = index);
    unawaited(_copyPulse.forward(from: 0));
  }

  Future<bool> _copy(String text,
      {String? toast, bool showToast = true}) async {
    if (text.isEmpty) {
      return false;
    }
    try {
      await getIt<ClipboardService>().setPlainText(text);
      if (showToast && toast != null && mounted) {
        showToastNotification(message: toast);
      }
      return true;
    } catch (e) {
      if (mounted) {
        showToastNotification(
          message: 'Unable to copy the text.',
          type: ToastificationType.error,
        );
      }
    }
    return false;
  }

  Future<void> _copySelected() => _copy(
        _result?.textOf(_selected) ?? '',
        toast: '${_selected.length} text '
            '${_selected.length == 1 ? 'region' : 'regions'} copied',
      );

  Future<void> _copyAll() =>
      _copy(_result?.text ?? '', toast: 'All text copied');

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final palette = ImageEditorPalette.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            _selectAll,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): _selectAll,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
            unawaited(_selected.isEmpty ? _copyAll() : _copySelected()),
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () =>
            unawaited(_selected.isEmpty ? _copyAll() : _copySelected()),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: ColoredBox(
              color: palette.backdrop,
              child: Column(
                children: [
                  _buildHeader(palette),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildStage(palette)),
                        if (_hasText) _buildPanel(palette),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ImageEditorPalette palette) {
    final String status;
    if (_scanning) {
      status = 'Scanning…';
    } else if (_errorMessage != null) {
      status = 'Nothing was read';
    } else if (!_hasText) {
      status = 'No text found';
    } else {
      final count = _lines.length;
      status = '$count text ${count == 1 ? 'region' : 'regions'}'
          '  ·  ${_result!.engine}';
    }

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.chromeBorder)),
      ),
      child: Row(
        children: [
          ImageEditorIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            palette: palette,
            onPressed: _close,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan text',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (_hasText) ...[
            ImageEditorTextButton(
              label: 'Copy selected',
              palette: palette,
              icon: Icons.content_copy_rounded,
              onPressed:
                  _selected.isEmpty ? null : () => unawaited(_copySelected()),
            ),
            const SizedBox(width: 6),
            ImageEditorTextButton(
              label: 'Copy all text',
              palette: palette,
              filled: true,
              onPressed: () => unawaited(_copyAll()),
            ),
            const SizedBox(width: 6),
          ],
          ImageEditorIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            palette: palette,
            onPressed: _close,
          ),
        ],
      ),
    );
  }

  Widget _buildStage(ImageEditorPalette palette) {
    final image = _image;
    return ColoredBox(
      color: palette.canvas,
      child: Stack(
        children: [
          if (image != null)
            Positioned.fill(
              child: _OcrStage(
                image: image,
                lines: _lines,
                selected: _selected,
                hovered: _hovered,
                palette: palette,
                pulse: _copyPulse,
                pulsedLine: _pulsedLine,
                onHover: (index) {
                  if (index != _hovered) {
                    setState(() => _hovered = index);
                  }
                },
                onSelect: _setSelection,
                onCopyLine: (index) => unawaited(_selectAndCopy(index)),
              ),
            ),
          if (_hasText)
            Positioned(
              left: 0,
              right: 0,
              bottom: 26,
              child: Center(
                  child: _CopiedPill(pulse: _copyPulse, palette: palette)),
            ),
          if (_scanning)
            Positioned.fill(
              child: ColoredBox(
                color: palette.canvas.withValues(alpha: 0.55),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(palette.accent),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Reading the text…',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!_scanning && (_errorMessage != null || !_hasText))
            Positioned.fill(child: _buildEmptyState(palette)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ImageEditorPalette palette) {
    final isError = _errorMessage != null;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: palette.chrome,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.chromeBorder),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 28,
              offset: const Offset(0, 12),
              spreadRadius: -12,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.text_fields_rounded,
              size: 22,
              color: isError ? palette.accent : palette.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              isError ? _errorMessage! : 'No text was found in this picture.',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (_errorHint != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorHint!,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                ImageEditorTextButton(
                  label: 'Try again',
                  palette: palette,
                  filled: true,
                  icon: Icons.refresh_rounded,
                  onPressed: () => unawaited(_scan()),
                ),
                const SizedBox(width: 8),
                ImageEditorTextButton(
                  label: 'Close',
                  palette: palette,
                  onPressed: _close,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel(ImageEditorPalette palette) {
    return Container(
      width: _panelWidth,
      decoration: BoxDecoration(
        color: palette.chrome,
        border: Border(left: BorderSide(color: palette.chromeBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: ImageEditorSectionTitle(
                    label: _selected.isEmpty
                        ? 'Detected text'
                        : '${_selected.length} selected',
                    palette: palette,
                  ),
                ),
                ImageEditorTextButton(
                  label: _selected.length == _lines.length ? 'Clear' : 'All',
                  palette: palette,
                  onPressed: () => _selected.length == _lines.length
                      ? _setSelection(const [])
                      : _selectAll(),
                ),
              ],
            ),
          ),
          Container(height: 1, color: palette.divider),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              itemCount: _lines.length,
              itemBuilder: (context, index) => _OcrLineRow(
                text: _lines[index].text,
                palette: palette,
                selected: _selected.contains(index),
                hovered: _hovered == index,
                onHover: (isHovering) =>
                    setState(() => _hovered = isHovering ? index : null),
                onPressed: () {
                  if (_isMultiSelectHeld) {
                    _setSelection([index], additive: true);
                  } else {
                    unawaited(_selectAndCopy(index));
                  }
                },
              ),
            ),
          ),
          Container(height: 1, color: palette.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Text(
              'Click a highlight to copy it. Hold Ctrl or Shift to pick '
              'several, or drag across the picture.',
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool get _isMultiSelectHeld =>
    HardwareKeyboard.instance.isControlPressed ||
    HardwareKeyboard.instance.isMetaPressed ||
    HardwareKeyboard.instance.isShiftPressed;

/// The picture with its detected regions drawn on top.
class _OcrStage extends StatefulWidget {
  const _OcrStage({
    required this.image,
    required this.lines,
    required this.selected,
    required this.hovered,
    required this.palette,
    required this.pulse,
    required this.pulsedLine,
    required this.onHover,
    required this.onSelect,
    required this.onCopyLine,
  });

  final ui.Image image;
  final List<OcrLine> lines;
  final Set<int> selected;
  final int? hovered;
  final ImageEditorPalette palette;
  final Animation<double> pulse;
  final int? pulsedLine;
  final ValueChanged<int?> onHover;
  final void Function(Iterable<int> indices, {bool additive}) onSelect;
  final ValueChanged<int> onCopyLine;

  @override
  State<_OcrStage> createState() => _OcrStageState();
}

class _OcrStageState extends State<_OcrStage> {
  static const double _padding = 40;

  Rect _pictureRect = Rect.zero;
  Rect? _band;
  Offset? _bandOrigin;

  Rect _fit(Size available) {
    final imageAspect = widget.image.width / widget.image.height;
    final width = math.max(1.0, available.width - _padding * 2);
    final height = math.max(1.0, available.height - _padding * 2);
    var displayWidth = width;
    var displayHeight = width / imageAspect;
    if (displayHeight > height) {
      displayHeight = height;
      displayWidth = height * imageAspect;
    }
    return Rect.fromCenter(
      center: Offset(available.width / 2, available.height / 2),
      width: displayWidth,
      height: displayHeight,
    );
  }

  Rect _boundsOf(int index) {
    final bounds = widget.lines[index].bounds;
    return Rect.fromLTWH(
      _pictureRect.left + bounds.left * _pictureRect.width,
      _pictureRect.top + bounds.top * _pictureRect.height,
      bounds.width * _pictureRect.width,
      bounds.height * _pictureRect.height,
    );
  }

  int? _indexAt(Offset position) {
    for (var index = 0; index < widget.lines.length; index++) {
      if (_boundsOf(index).inflate(2).contains(position)) {
        return index;
      }
    }
    return null;
  }

  bool get _additive => _isMultiSelectHeld;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _pictureRect = _fit(Size(constraints.maxWidth, constraints.maxHeight));
        return MouseRegion(
          cursor: widget.hovered != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.precise,
          onHover: (event) => widget.onHover(_indexAt(event.localPosition)),
          onExit: (_) => widget.onHover(null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final index = _indexAt(details.localPosition);
              if (index == null) {
                widget.onSelect(const <int>[]);
                return;
              }
              // A plain click is "give me that text"; the modifiers are for
              // building a larger selection to copy in one go.
              if (_additive) {
                widget.onSelect([index], additive: true);
              } else {
                widget.onCopyLine(index);
              }
            },
            onPanStart: (details) {
              _bandOrigin = details.localPosition;
              setState(
                () => _band = Rect.fromPoints(
                  details.localPosition,
                  details.localPosition,
                ),
              );
            },
            onPanUpdate: (details) {
              final origin = _bandOrigin;
              if (origin == null) {
                return;
              }
              setState(
                () => _band = Rect.fromPoints(origin, details.localPosition),
              );
            },
            onPanEnd: (_) {
              final band = _band;
              _bandOrigin = null;
              setState(() => _band = null);
              if (band == null || (band.width < 3 && band.height < 3)) {
                return;
              }
              final hit = <int>[];
              for (var index = 0; index < widget.lines.length; index++) {
                if (_boundsOf(index).overlaps(band)) {
                  hit.add(index);
                }
              }
              widget.onSelect(hit, additive: _additive);
            },
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _OcrPainter(
                  image: widget.image,
                  pictureRect: _pictureRect,
                  boxes: [
                    for (var index = 0; index < widget.lines.length; index++)
                      _boundsOf(index),
                  ],
                  selected: widget.selected,
                  hovered: widget.hovered,
                  band: _band,
                  accent: widget.palette.accent,
                  shadow: widget.palette.shadow,
                  pulse: widget.pulse,
                  pulsedLine: widget.pulsedLine,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OcrPainter extends CustomPainter {
  _OcrPainter({
    required this.image,
    required this.pictureRect,
    required this.boxes,
    required this.selected,
    required this.hovered,
    required this.band,
    required this.accent,
    required this.shadow,
    required this.pulse,
    required this.pulsedLine,
  }) : super(repaint: pulse);

  final ui.Image image;
  final Rect pictureRect;
  final List<Rect> boxes;
  final Set<int> selected;
  final int? hovered;
  final Rect? band;
  final Color accent;
  final Color shadow;
  final Animation<double> pulse;
  final int? pulsedLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (pictureRect.isEmpty) {
      return;
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(pictureRect.inflate(1), const Radius.circular(3)),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      pictureRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    for (var index = 0; index < boxes.length; index++) {
      final isSelected = selected.contains(index);
      final isHovered = hovered == index;
      final rect = RRect.fromRectAndRadius(
        boxes[index].inflate(2),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = accent.withValues(
            alpha: isSelected
                ? 0.34
                : isHovered
                    ? 0.2
                    : 0.12,
          ),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = accent.withValues(alpha: isSelected ? 0.95 : 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 1.6 : 1,
      );
    }

    _paintCopyPulse(canvas);

    final selectionBand = band;
    if (selectionBand != null) {
      canvas.drawRect(
        selectionBand,
        Paint()..color = accent.withValues(alpha: 0.14),
      );
      canvas.drawRect(
        selectionBand,
        Paint()
          ..color = accent.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  /// A ring that expands out of the copied region and fades. It is deliberately
  /// short and quiet — an acknowledgement, not a celebration.
  void _paintCopyPulse(Canvas canvas) {
    final index = pulsedLine;
    if (index == null || index < 0 || index >= boxes.length) {
      return;
    }
    final progress = (pulse.value / 0.42).clamp(0.0, 1.0);
    if (progress <= 0 || progress >= 1) {
      return;
    }
    final eased = Curves.easeOutCubic.transform(progress);
    final rect = RRect.fromRectAndRadius(
      boxes[index].inflate(2 + 9 * eased),
      Radius.circular(3 + 4 * eased),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = accent.withValues(alpha: 0.75 * (1 - eased))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * (1 - eased) + 0.8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          boxes[index].inflate(2), const Radius.circular(3)),
      Paint()..color = accent.withValues(alpha: 0.3 * (1 - eased)),
    );
  }

  @override
  bool shouldRepaint(_OcrPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.pictureRect != pictureRect ||
      oldDelegate.boxes.length != boxes.length ||
      !setEquals(oldDelegate.selected, selected) ||
      oldDelegate.hovered != hovered ||
      oldDelegate.band != band ||
      oldDelegate.pulsedLine != pulsedLine;
}

/// The "Copied" acknowledgement that rides the same timeline as the ring.
class _CopiedPill extends StatelessWidget {
  const _CopiedPill({required this.pulse, required this.palette});

  final Animation<double> pulse;
  final ImageEditorPalette palette;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, __) {
        final t = pulse.value;
        if (t <= 0 || t >= 1) {
          return const SizedBox.shrink();
        }
        // Snap in, hold, then drift away.
        final opacity = t < 0.72
            ? (t / 0.08).clamp(0.0, 1.0)
            : (1 - (t - 0.72) / 0.28).clamp(0.0, 1.0);
        return IgnorePointer(
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, 6 * (1 - opacity)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                height: 32,
                decoration: BoxDecoration(
                  color: palette.chrome,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: palette.chromeBorder),
                  boxShadow: [
                    BoxShadow(
                      color: palette.shadow,
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: palette.accent,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Copied',
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OcrLineRow extends StatelessWidget {
  const _OcrLineRow({
    required this.text,
    required this.palette,
    required this.selected,
    required this.hovered,
    required this.onHover,
    required this.onPressed,
  });

  final String text;
  final ImageEditorPalette palette;
  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: AnimatedContainer(
          duration: ImageEditorMotion.instant,
          curve: ImageEditorMotion.curve,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? palette.controlActive
                : hovered
                    ? palette.controlHover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? palette.accent : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 14,
                  color: selected ? palette.accent : palette.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color:
                        selected ? palette.textPrimary : palette.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
