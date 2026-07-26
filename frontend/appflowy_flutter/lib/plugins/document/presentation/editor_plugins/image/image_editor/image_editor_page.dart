import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'image_edit_pipeline.dart';
import 'image_edit_settings.dart';
import 'image_editor_controls.dart';
import 'image_editor_source.dart';
import 'image_editor_theme.dart';
import 'image_editor_viewport.dart';

/// Opens the fullscreen editor. Resolves to `true` when the edit was saved
/// back into the document.
Future<bool?> showImageEditor(
  BuildContext context, {
  required ImageEditorSource source,
  required String name,
  required Future<bool> Function(Uint8List bytes) onSave,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder<bool>(
      opaque: false,
      barrierColor: const Color(0x00000000),
      transitionDuration: ImageEditorMotion.reveal,
      reverseTransitionDuration: ImageEditorMotion.fast,
      pageBuilder: (_, __, ___) => ImageEditorPage(
        source: source,
        name: name,
        onSave: onSave,
      ),
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

enum _PanelTab {
  adjust('Adjust', Icons.tune_rounded),
  crop('Crop', Icons.crop_rounded),
  filters('Filters', Icons.auto_awesome_outlined),
  annotate('Mark up', Icons.draw_outlined);

  const _PanelTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

const List<Color> _annotationColors = [
  Color(0xFFFF4D4F),
  Color(0xFFFFB020),
  Color(0xFF34C759),
  Color(0xFF3B82F6),
  Color(0xFFAF52DE),
  Color(0xFFFFFFFF),
  Color(0xFF111111),
];

class ImageEditorPage extends StatefulWidget {
  const ImageEditorPage({
    super.key,
    required this.source,
    required this.name,
    required this.onSave,
  });

  final ImageEditorSource source;
  final String name;
  final Future<bool> Function(Uint8List bytes) onSave;

  @override
  State<ImageEditorPage> createState() => _ImageEditorPageState();
}

class _ImageEditorPageState extends State<ImageEditorPage> {
  static const double _panelWidth = 312;

  final GlobalKey<ImageEditorViewportState> _viewportKey = GlobalKey();

  ui.Image? _image;
  String? _loadError;

  final List<ImageEditSettings> _history = [ImageEditSettings.pristine];
  int _historyIndex = 0;
  ImageEditSettings _current = ImageEditSettings.pristine;

  _PanelTab _tab = _PanelTab.adjust;
  bool _panelOpen = true;
  bool _saving = false;
  bool _exporting = false;
  double _displayScale = 1;

  ImageAnnotationTool _tool = ImageAnnotationTool.arrow;
  Color _annotationColor = _annotationColors.first;
  double _annotationStroke = 0.005;
  final TextEditingController _annotationTextController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _annotationTextController.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.source.readBytes();
      final image = await decodeEditableImage(bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = e.toString());
      }
    }
  }

  // ------------------------------------------------------------------ history

  bool get _canUndo => _historyIndex > 0;

  bool get _canRedo => _historyIndex < _history.length - 1;

  void _update(ImageEditSettings next) => setState(() => _current = next);

  void _commit() {
    if (_current == _history[_historyIndex]) {
      return;
    }
    setState(() {
      _history.removeRange(_historyIndex + 1, _history.length);
      _history.add(_current);
      _historyIndex = _history.length - 1;
    });
  }

  void _updateAndCommit(ImageEditSettings next) {
    _update(next);
    _commit();
  }

  void _undo() {
    if (!_canUndo) {
      return;
    }
    setState(() {
      _historyIndex -= 1;
      _current = _history[_historyIndex];
    });
  }

  void _redo() {
    if (!_canRedo) {
      return;
    }
    setState(() {
      _historyIndex += 1;
      _current = _history[_historyIndex];
    });
  }

  void _resetAll() => _updateAndCommit(ImageEditSettings.pristine);

  // ------------------------------------------------------------------- saving

  Future<Uint8List?> _render() async {
    final image = _image;
    if (image == null) {
      return null;
    }
    return encodeEditedImage(image, _current);
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final bytes = await _render();
      if (bytes == null) {
        return;
      }
      final saved = await widget.onSave(bytes);
      if (saved && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showToastNotification(
          message: 'Unable to save the edited image: $e',
          type: ToastificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _export() async {
    if (_exporting) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final bytes = await _render();
      if (bytes == null) {
        return;
      }
      final exported = await saveMediaBytes(
        bytes: bytes,
        name: _exportName,
      );
      if (exported && mounted) {
        showToastNotification(message: 'Image exported');
      }
    } catch (e) {
      if (mounted) {
        showToastNotification(
          message: 'Unable to export the image: $e',
          type: ToastificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  String get _exportName {
    final base = widget.name.contains('.')
        ? widget.name.substring(0, widget.name.lastIndexOf('.'))
        : widget.name;
    return '${base.isEmpty ? 'image' : base}-edited.png';
  }

  Size? get _outputSize {
    final image = _image;
    if (image == null) {
      return null;
    }
    return ImageEditGeometry.forImage(image, _current.transform).outputSize;
  }

  @override
  Widget build(BuildContext context) {
    final palette = ImageEditorPalette.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ): _redo,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
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
                        _buildPanel(palette),
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

  void _close() => Navigator.of(context).maybePop();

  // ------------------------------------------------------------------- header

  Widget _buildHeader(ImageEditorPalette palette) {
    final size = _outputSize;
    final image = _image;
    final dimensions = image == null
        ? 'Loading…'
        : size == null
            ? '${image.width} × ${image.height}'
            : '${size.width.round()} × ${size.height.round()}'
                '${_current.transform.isIdentity ? '' : '  ·  cropped'}';

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
                  widget.name.isEmpty ? 'Image' : widget.name,
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
                  dimensions,
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
          ImageEditorIconButton(
            icon: Icons.undo_rounded,
            tooltip: 'Undo',
            palette: palette,
            onPressed: _canUndo ? _undo : null,
          ),
          ImageEditorIconButton(
            icon: Icons.redo_rounded,
            tooltip: 'Redo',
            palette: palette,
            onPressed: _canRedo ? _redo : null,
          ),
          ImageEditorIconButton(
            icon: Icons.restart_alt_rounded,
            tooltip: 'Reset all edits',
            palette: palette,
            onPressed: _current.isPristine ? null : _resetAll,
          ),
          _headerDivider(palette),
          ImageEditorIconButton(
            icon: _panelOpen
                ? Icons.chevron_right_rounded
                : Icons.chevron_left_rounded,
            tooltip: _panelOpen ? 'Hide panel' : 'Show panel',
            palette: palette,
            onPressed: () => setState(() => _panelOpen = !_panelOpen),
          ),
          _headerDivider(palette),
          ImageEditorTextButton(
            label: 'Export',
            palette: palette,
            icon: Icons.ios_share_rounded,
            busy: _exporting,
            onPressed: _image == null ? null : _export,
          ),
          const SizedBox(width: 6),
          ImageEditorTextButton(
            label: 'Save',
            palette: palette,
            filled: true,
            busy: _saving,
            onPressed:
                _image == null || _current.isPristine ? null : _save,
          ),
          const SizedBox(width: 6),
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

  Widget _headerDivider(ImageEditorPalette palette) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Container(width: 1, height: 20, color: palette.divider),
      );

  // -------------------------------------------------------------------- stage

  Widget _buildStage(ImageEditorPalette palette) {
    final image = _image;
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Unable to open this image.\n$_loadError',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textSecondary, fontSize: 13),
          ),
        ),
      );
    }
    if (image == null) {
      return Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(palette.textMuted),
          ),
        ),
      );
    }

    return ColoredBox(
      color: palette.canvas,
      child: Stack(
        children: [
          Positioned.fill(
            child: ImageEditorViewport(
              key: _viewportKey,
              image: image,
              settings: _current,
              mode: switch (_tab) {
                _PanelTab.crop => ImageEditorMode.crop,
                _PanelTab.annotate => ImageEditorMode.annotate,
                _ => ImageEditorMode.view,
              },
              palette: palette,
              annotationTool: _tool,
              annotationColor: _annotationColor,
              annotationStrokeWidth: _annotationStroke,
              annotationText: _annotationTextController.text,
              onCropChanged: (crop) => _update(
                _current.copyWith(
                  transform: _current.transform.copyWith(crop: crop),
                ),
              ),
              onAnnotationAdded: (annotation) => _update(
                _current.copyWith(
                  annotations: [
                    ..._current.annotations,
                    annotation.tool == ImageAnnotationTool.marker
                        ? annotation.copyWith(
                            markerNumber: _current.annotations
                                    .where(
                                      (a) =>
                                          a.tool == ImageAnnotationTool.marker,
                                    )
                                    .length +
                                1,
                          )
                        : annotation,
                  ],
                ),
              ),
              onInteractionEnd: _commit,
              onZoomChanged: (scale) {
                if ((scale - _displayScale).abs() > 0.001) {
                  setState(() => _displayScale = scale);
                }
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Center(child: _buildZoomPill(palette)),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomPill(ImageEditorPalette palette) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      height: 40,
      decoration: BoxDecoration(
        color: palette.chrome,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.chromeBorder),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 22,
            offset: const Offset(0, 8),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ImageEditorIconButton(
            icon: Icons.remove_rounded,
            tooltip: 'Zoom out',
            palette: palette,
            dimension: 28,
            iconSize: 16,
            onPressed: () => _viewportKey.currentState?.zoomBy(1 / 1.25),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${(_displayScale * 100).round()}%',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
          ImageEditorIconButton(
            icon: Icons.add_rounded,
            tooltip: 'Zoom in',
            palette: palette,
            dimension: 28,
            iconSize: 16,
            onPressed: () => _viewportKey.currentState?.zoomBy(1.25),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(width: 1, height: 16, color: palette.divider),
          ),
          ImageEditorIconButton(
            icon: Icons.fit_screen_outlined,
            tooltip: 'Fit to screen',
            palette: palette,
            dimension: 28,
            iconSize: 16,
            onPressed: () => _viewportKey.currentState?.fit(),
          ),
          ImageEditorIconButton(
            icon: Icons.crop_free_rounded,
            tooltip: 'Actual size',
            palette: palette,
            dimension: 28,
            iconSize: 16,
            onPressed: () => _viewportKey.currentState?.zoomToActualPixels(),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- panel

  Widget _buildPanel(ImageEditorPalette palette) {
    return ClipRect(
      child: AnimatedContainer(
        duration: ImageEditorMotion.normal,
        curve: ImageEditorMotion.curve,
        width: _panelOpen ? _panelWidth : 0,
        decoration: BoxDecoration(
          color: palette.chrome,
          border: Border(left: BorderSide(color: palette.chromeBorder)),
        ),
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: _panelWidth,
          maxWidth: _panelWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    for (final tab in _PanelTab.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _PanelTabButton(
                            tab: tab,
                            palette: palette,
                            selected: _tab == tab,
                            onPressed: () => setState(() => _tab = tab),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(height: 1, color: palette.divider),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: switch (_tab) {
                    _PanelTab.adjust => _buildAdjustSection(palette),
                    _PanelTab.crop => _buildCropSection(palette),
                    _PanelTab.filters => _buildFilterSection(palette),
                    _PanelTab.annotate => _buildAnnotateSection(palette),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAdjustSection(ImageEditorPalette palette) {
    return [
      ImageEditorSectionTitle(
        label: 'Light',
        palette: palette,
        trailing: ImageEditorTextButton(
          label: 'Reset',
          palette: palette,
          onPressed: _current.adjustments.isNeutral
              ? null
              : () => _updateAndCommit(
                    _current.copyWith(adjustments: ImageAdjustments.none),
                  ),
        ),
      ),
      for (final adjustment in const [
        ImageAdjustment.exposure,
        ImageAdjustment.brightness,
        ImageAdjustment.contrast,
        ImageAdjustment.highlights,
        ImageAdjustment.shadows,
      ])
        _slider(palette, adjustment),
      const SizedBox(height: 18),
      ImageEditorSectionTitle(label: 'Colour', palette: palette),
      for (final adjustment in const [
        ImageAdjustment.temperature,
        ImageAdjustment.tint,
        ImageAdjustment.saturation,
        ImageAdjustment.vibrance,
      ])
        _slider(palette, adjustment),
      const SizedBox(height: 18),
      ImageEditorSectionTitle(label: 'Detail', palette: palette),
      for (final adjustment in const [
        ImageAdjustment.sharpness,
        ImageAdjustment.blur,
      ])
        _slider(palette, adjustment),
    ];
  }

  Widget _slider(ImageEditorPalette palette, ImageAdjustment adjustment) {
    return ImageEditorSlider(
      label: adjustment.label,
      palette: palette,
      value: _current.adjustments.valueOf(adjustment),
      min: adjustment.minValue,
      max: adjustment.maxValue,
      neutral: adjustment.isUnipolar ? 0 : 0,
      onChanged: (value) => _update(
        _current.copyWith(
          adjustments: _current.adjustments.withValue(adjustment, value),
        ),
      ),
      onChangeEnd: _commit,
    );
  }

  List<Widget> _buildCropSection(ImageEditorPalette palette) {
    final image = _image;
    final orientedSize = image == null
        ? const Size(1, 1)
        : ImageEditGeometry.forImage(image, _current.transform).orientedSize;

    return [
      ImageEditorSectionTitle(
        label: 'Aspect ratio',
        palette: palette,
        trailing: ImageEditorTextButton(
          label: 'Reset',
          palette: palette,
          onPressed: _current.transform.isIdentity
              ? null
              : () => _updateAndCommit(
                    _current.copyWith(transform: ImageTransform.identity),
                  ),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final ratio in ImageCropRatio.values)
            ImageEditorChip(
              label: ratio.label,
              palette: palette,
              selected: _current.transform.ratio == ratio,
              onPressed: () {
                final resolved = ratio.resolve(orientedSize.aspectRatio);
                _updateAndCommit(
                  _current.copyWith(
                    transform: _current.transform.copyWith(
                      ratio: ratio,
                      crop: ratio == ImageCropRatio.free
                          ? _current.transform.crop
                          : ImageEditorViewportState.centeredCropForRatio(
                              orientedSize,
                              resolved,
                            ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      const SizedBox(height: 22),
      ImageEditorSectionTitle(label: 'Orientation', palette: palette),
      Row(
        children: [
          _iconAction(
            palette,
            Icons.rotate_90_degrees_ccw_outlined,
            'Rotate left',
            () => _updateAndCommit(
              _current.copyWith(transform: _current.transform.rotated(-1)),
            ),
          ),
          _iconAction(
            palette,
            Icons.rotate_90_degrees_cw_outlined,
            'Rotate right',
            () => _updateAndCommit(
              _current.copyWith(transform: _current.transform.rotated(1)),
            ),
          ),
          _iconAction(
            palette,
            Icons.flip_rounded,
            'Flip horizontally',
            () => _updateAndCommit(
              _current.copyWith(
                transform: _current.transform.copyWith(
                  flipHorizontal: !_current.transform.flipHorizontal,
                ),
              ),
            ),
            isActive: _current.transform.flipHorizontal,
          ),
          Transform.rotate(
            angle: 1.5707963267948966,
            child: _iconAction(
              palette,
              Icons.flip_rounded,
              'Flip vertically',
              () => _updateAndCommit(
                _current.copyWith(
                  transform: _current.transform.copyWith(
                    flipVertical: !_current.transform.flipVertical,
                  ),
                ),
              ),
              isActive: _current.transform.flipVertical,
            ),
          ),
        ],
      ),
      const SizedBox(height: 22),
      Text(
        'Drag the corners on the photo to set the crop. Drag outside the frame '
        'to pan.',
        style: TextStyle(
          color: palette.textMuted,
          fontSize: 11.5,
          height: 1.45,
        ),
      ),
    ];
  }

  Widget _iconAction(
    ImageEditorPalette palette,
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool isActive = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ImageEditorIconButton(
        icon: icon,
        tooltip: tooltip,
        palette: palette,
        isActive: isActive,
        onPressed: onPressed,
        dimension: 36,
        iconSize: 19,
      ),
    );
  }

  List<Widget> _buildFilterSection(ImageEditorPalette palette) {
    final image = _image;
    return [
      ImageEditorSectionTitle(label: 'Looks', palette: palette),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final preset in ImageFilterPreset.values)
            _FilterTile(
              preset: preset,
              palette: palette,
              image: image,
              transform: _current.transform,
              adjustments: _current.adjustments,
              selected: _current.filter == preset,
              onPressed: () =>
                  _updateAndCommit(_current.copyWith(filter: preset)),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Text(
        'Looks stay subtle on purpose — they finish a photo instead of '
        'restyling it.',
        style: TextStyle(
          color: palette.textMuted,
          fontSize: 11.5,
          height: 1.45,
        ),
      ),
    ];
  }

  List<Widget> _buildAnnotateSection(ImageEditorPalette palette) {
    return [
      ImageEditorSectionTitle(
        label: 'Tool',
        palette: palette,
        trailing: ImageEditorTextButton(
          label: 'Clear',
          palette: palette,
          onPressed: _current.annotations.isEmpty
              ? null
              : () => _updateAndCommit(
                    _current.copyWith(annotations: const []),
                  ),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tool in ImageAnnotationTool.values)
            ImageEditorChip(
              label: tool.label,
              palette: palette,
              icon: _toolIcon(tool),
              selected: _tool == tool,
              onPressed: () => setState(() => _tool = tool),
            ),
        ],
      ),
      const SizedBox(height: 22),
      ImageEditorSectionTitle(label: 'Colour', palette: palette),
      Row(
        children: [
          for (final color in _annotationColors)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ColorSwatch(
                color: color,
                palette: palette,
                selected: _annotationColor == color,
                onPressed: () => setState(() => _annotationColor = color),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      ImageEditorSlider(
        label: 'Stroke',
        palette: palette,
        value: _annotationStroke,
        min: 0.002,
        max: 0.02,
        neutral: 0.002,
        onChanged: (value) => setState(() => _annotationStroke = value),
      ),
      if (_tool == ImageAnnotationTool.text) ...[
        const SizedBox(height: 14),
        ImageEditorSectionTitle(label: 'Label', palette: palette),
        _AnnotationTextField(
          controller: _annotationTextController,
          palette: palette,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          'Type the label, then click on the photo to place it.',
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11.5,
            height: 1.45,
          ),
        ),
      ],
      const SizedBox(height: 22),
      ImageEditorSectionTitle(
        label: 'Marks (${_current.annotations.length})',
        palette: palette,
      ),
      if (_current.annotations.isEmpty)
        Text(
          'Nothing drawn yet.',
          style: TextStyle(color: palette.textMuted, fontSize: 11.5),
        )
      else
        for (final annotation in _current.annotations.reversed)
          _AnnotationRow(
            annotation: annotation,
            palette: palette,
            icon: _toolIcon(annotation.tool),
            onRemove: () => _updateAndCommit(
              _current.copyWith(
                annotations: _current.annotations
                    .where((item) => item.id != annotation.id)
                    .toList(),
              ),
            ),
          ),
    ];
  }

  IconData _toolIcon(ImageAnnotationTool tool) => switch (tool) {
        ImageAnnotationTool.arrow => Icons.north_east_rounded,
        ImageAnnotationTool.rectangle => Icons.crop_square_rounded,
        ImageAnnotationTool.ellipse => Icons.circle_outlined,
        ImageAnnotationTool.freehand => Icons.gesture_rounded,
        ImageAnnotationTool.highlight => Icons.highlight_alt_rounded,
        ImageAnnotationTool.text => Icons.text_fields_rounded,
        ImageAnnotationTool.blur => Icons.blur_on_rounded,
        ImageAnnotationTool.marker => Icons.filter_1_rounded,
      };
}

class _PanelTabButton extends StatefulWidget {
  const _PanelTabButton({
    required this.tab,
    required this.palette,
    required this.selected,
    required this.onPressed,
  });

  final _PanelTab tab;
  final ImageEditorPalette palette;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_PanelTabButton> createState() => _PanelTabButtonState();
}

class _PanelTabButtonState extends State<_PanelTabButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final foreground =
        widget.selected ? palette.textPrimary : palette.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: ImageEditorMotion.instant,
          curve: ImageEditorMotion.curve,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.controlActive
                : _hovering
                    ? palette.controlHover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.tab.icon, size: 17, color: foreground),
              const SizedBox(height: 4),
              Text(
                widget.tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.preset,
    required this.palette,
    required this.image,
    required this.transform,
    required this.adjustments,
    required this.selected,
    required this.onPressed,
  });

  final ImageFilterPreset preset;
  final ImageEditorPalette palette;
  final ui.Image? image;
  final ImageTransform transform;
  final ImageAdjustments adjustments;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const size = 76.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: size,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: ImageEditorMotion.instant,
                height: size,
                width: size,
                decoration: BoxDecoration(
                  color: palette.control,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: selected ? palette.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: image == null
                      ? const SizedBox.shrink()
                      : CustomPaint(
                          painter: _FilterPreviewPainter(
                            image: image!,
                            settings: ImageEditSettings(
                              adjustments: adjustments,
                              filter: preset,
                              transform: ImageTransform(
                                quarterTurns: transform.quarterTurns,
                                flipHorizontal: transform.flipHorizontal,
                                flipVertical: transform.flipVertical,
                                crop: _squareCrop(image!, transform),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                preset.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? palette.textPrimary : palette.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Rect _squareCrop(ui.Image image, ImageTransform transform) {
    final oriented =
        ImageEditGeometry.forImage(image, transform).orientedSize;
    return ImageEditorViewportState.centeredCropForRatio(oriented, 1);
  }
}

class _FilterPreviewPainter extends CustomPainter {
  const _FilterPreviewPainter({required this.image, required this.settings});

  final ui.Image image;
  final ImageEditSettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    paintEditedImage(
      canvas,
      image,
      Offset.zero & size,
      settings,
      includeAnnotations: false,
      filterQuality: FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_FilterPreviewPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.settings != settings;
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.palette,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final ImageEditorPalette palette;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: AnimatedContainer(
          duration: ImageEditorMotion.instant,
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? palette.accent : palette.chromeBorder,
              width: selected ? 2.5 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnotationRow extends StatelessWidget {
  const _AnnotationRow({
    required this.annotation,
    required this.palette,
    required this.icon,
    required this.onRemove,
  });

  final ImageAnnotation annotation;
  final ImageEditorPalette palette;
  final IconData icon;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: annotation.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 14, color: palette.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              annotation.text?.isNotEmpty == true
                  ? annotation.text!
                  : annotation.tool.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
          ImageEditorIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Remove',
            palette: palette,
            dimension: 24,
            iconSize: 14,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _AnnotationTextField extends StatelessWidget {
  const _AnnotationTextField({
    required this.controller,
    required this.palette,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ImageEditorPalette palette;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.control,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.chromeBorder),
      ),
      child: Center(
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          cursorColor: palette.accent,
          cursorWidth: 1.5,
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 12.5,
            height: 1.2,
          ),
          decoration: InputDecoration.collapsed(
            hintText: 'Label',
            hintStyle: TextStyle(
              color: palette.textMuted,
              fontSize: 12.5,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
