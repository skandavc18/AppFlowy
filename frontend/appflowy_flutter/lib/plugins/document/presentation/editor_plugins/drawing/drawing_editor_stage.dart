import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block.dart';
import 'package:appflowy/shared/drawing/excalidraw_scene.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'excalidraw_editor_view.dart';

/// Opens a drawing in the real Excalidraw editor at window size.
///
/// The drawing block and a canvas drawing card both come through here, so a
/// drawing is kept the same way wherever it was made: every change the editor
/// reports, a read every few seconds, and one last read before the window goes.
Future<void> showDrawingEditor(
  BuildContext context, {
  required String title,
  required String scene,
  required bool editable,
  required ValueChanged<String> onSceneChanged,
}) {
  if (!canRunExcalidrawEditor) {
    return Future<void>.value();
  }
  final opened = scene.trim().isEmpty ? DrawScene.empty().encode() : scene;
  return showVisualBlockFullscreen<void>(
    context: context,
    icon: Icons.draw_rounded,
    title: title,
    subtitle: LocaleKeys.diagrams_drawing_poweredBy.tr(),
    builder: (_) => DrawingEditorStage(
      scene: opened,
      editable: editable,
      onSceneChanged: onSceneChanged,
    ),
  );
}

/// The fullscreen editing stage: the Excalidraw canvas plus a save affordance.
///
/// ⚠️ The editor reports a change only after a pause, and it lives in a web
/// view that is gone once the window has closed. So closing is held back for
/// the moment it takes to ask the editor for its scene outright — otherwise
/// whatever was drawn just before closing is silently lost.
class DrawingEditorStage extends StatefulWidget {
  const DrawingEditorStage({
    super.key,
    required this.scene,
    required this.editable,
    required this.onSceneChanged,
    this.controller,
    this.pullInterval = const Duration(seconds: 4),
    this.closeTimeout = const Duration(milliseconds: 1500),
    this.editorBuilder,
  });

  /// The `.excalidraw` document the editor opens with.
  final String scene;
  final bool editable;

  /// Called with the whole scene whenever it has moved on. It may be called
  /// once more after the stage has gone, with the scene read on the way out.
  final ValueChanged<String> onSceneChanged;

  final ExcalidrawEditorController? controller;

  /// How often the scene is asked for outright while the editor is open.
  final Duration pullInterval;

  /// The longest closing waits for the editor to hand over its scene.
  final Duration closeTimeout;

  /// Builds the editor itself; tests stand a fake in for the web view.
  @visibleForTesting
  final Widget Function(
    BuildContext context,
    ExcalidrawEditorController controller,
    ValueChanged<String> onSceneChanged,
  )? editorBuilder;

  @override
  State<DrawingEditorStage> createState() => _DrawingEditorStageState();
}

class _DrawingEditorStageState extends State<DrawingEditorStage> {
  late final ExcalidrawEditorController _controller =
      widget.controller ?? ExcalidrawEditorController();

  /// The scene the editor is last known to hold. Everything accepted is
  /// handed on at once, so this is also what the host has been told.
  late String _latest;

  /// Kept for a scene that arrives after the stage has been taken down.
  late ValueChanged<String> _report;

  Timer? _autosave;
  Future<void>? _pulling;
  Animation<double>? _route;
  bool _saving = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _latest = widget.scene;
    _report = widget.onSceneChanged;
    if (widget.editable) {
      // The editor reports its own changes, but a drawing is worth a second
      // route home: every few seconds the scene is asked for outright.
      _autosave = Timer.periodic(
        widget.pullInterval,
        (_) => unawaited(_pull()),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // However the window is taken away — not only by its own close button —
    // the editor is still there for the exit animation: read it once more.
    final route = ModalRoute.of(context)?.animation;
    if (!identical(route, _route)) {
      _route?.removeStatusListener(_onRouteStatus);
      _route = route?..addStatusListener(_onRouteStatus);
    }
  }

  @override
  void didUpdateWidget(covariant DrawingEditorStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _report = widget.onSceneChanged;
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _route?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse && widget.editable) {
      unawaited(_pull());
    }
  }

  /// Takes a scene from the editor and hands it on if it has moved on.
  void _accept(String? scene) {
    if (scene == null || scene.isEmpty || scene == _latest) {
      return;
    }
    _latest = scene;
    _report(scene);
  }

  /// Asks the editor for its scene. Overlapping asks share one read.
  Future<void> _pull() {
    final running = _pulling;
    if (running != null) {
      return running;
    }
    final done = Completer<void>();
    _pulling = done.future;
    unawaited(() async {
      try {
        if (_controller.isAttached) {
          _accept(await _controller.requestScene());
        }
      } on Object catch (error) {
        Log.warn('The drawing could not be read from the editor: $error');
      } finally {
        _pulling = null;
        done.complete();
      }
    }());
    return done.future;
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

  /// Closing, held back until the editor has handed over its last strokes.
  Future<void> _close() async {
    if (_closing) {
      return;
    }
    _closing = true;
    setState(() => _saving = true);
    // A web view that never answers must not keep the window open.
    await _pull().timeout(widget.closeTimeout, onTimeout: () {});
    if (!mounted) {
      return;
    }
    // Something opened over the editor meanwhile — an export — is not what
    // was asked to close. The scene is kept; closing can simply be asked again.
    if (ModalRoute.of(context)?.isCurrent != true) {
      _closing = false;
      setState(() => _saving = false);
      return;
    }
    Navigator.of(context).pop();
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
    final editor = widget.editorBuilder?.call(context, _controller, _accept) ??
        ExcalidrawEditorView(
          controller: _controller,
          scene: widget.scene,
          editable: widget.editable,
          onSceneChanged: _accept,
          onReady: () {
            if (mounted) {
              setState(() {});
            }
          },
        );
    return PopScope(
      // A read-only drawing has nothing to keep.
      canPop: !widget.editable,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_close());
        }
      },
      child: Column(
        children: [
          Expanded(child: editor),
          _SaveBar(
            palette: palette,
            editable: widget.editable,
            saving: _saving,
            onSave: _saveNow,
            onExportPng: () => unawaited(_exportImage('png')),
            onExportSvg: () => unawaited(_exportImage('svg')),
          ),
        ],
      ),
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
