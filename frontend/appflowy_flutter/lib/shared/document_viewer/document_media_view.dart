import 'dart:math' as math;

import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'document_chrome.dart';
import 'document_scroll.dart';
import 'document_typography.dart';
import 'document_viewport.dart';
import 'document_viewer_theme.dart';

/// An immersive image stage: the picture is the only thing on screen.
///
/// Zoom interpolates smoothly, and once the image exceeds the viewport the
/// shared document scrolling takes over, so panning a large photograph feels
/// exactly like scrolling a PDF or a Markdown file.
class DocumentImageStage extends StatefulWidget {
  const DocumentImageStage({
    super.key,
    required this.image,
    required this.controller,
    this.horizontalController,
    this.zoom = 1,
    this.onZoomChanged,
    this.backgroundColor,
  });

  final ImageProvider image;
  final DocumentScrollController controller;
  final ScrollController? horizontalController;

  /// `1` fits the image to the viewport. Larger values magnify.
  final double zoom;
  final ValueChanged<double>? onZoomChanged;
  final Color? backgroundColor;

  static const double minZoom = 0.2;
  static const double maxZoom = 8;

  /// Zoom steps used by the toolbar and keyboard shortcuts.
  static const List<double> zoomStops = [
    0.25,
    0.5,
    0.75,
    1,
    1.5,
    2,
    3,
    4,
    6,
    8,
  ];

  static double nextZoomStop(double current, {required bool increase}) {
    if (increase) {
      for (final stop in zoomStops) {
        if (stop > current + 0.001) {
          return stop;
        }
      }
      return maxZoom;
    }
    for (final stop in zoomStops.reversed) {
      if (stop < current - 0.001) {
        return stop;
      }
    }
    return minZoom;
  }

  @override
  State<DocumentImageStage> createState() => _DocumentImageStageState();
}

class _DocumentImageStageState extends State<DocumentImageStage> {
  late final ScrollController horizontal =
      widget.horizontalController ?? ScrollController();
  bool ownsHorizontal = false;

  @override
  void initState() {
    super.initState();
    ownsHorizontal = widget.horizontalController == null;
  }

  @override
  void dispose() {
    if (ownsHorizontal) {
      horizontal.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return ColoredBox(
      color: widget.backgroundColor ?? theme.canvasEdge,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: GestureDetector(
          onDoubleTap: _toggleZoom,
          child: LayoutBuilder(
            builder: (context, constraints) => DocumentViewport.child(
              controller: widget.controller,
              surface: DocumentSurface.immersive,
              maxContentWidth: double.infinity,
              padding: const EdgeInsets.all(28),
              backgroundColor: Colors.transparent,
              fillViewport: true,
              child: _stage(theme, constraints),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stage(DocumentViewerTheme theme, BoxConstraints constraints) {
    final content = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: widget.zoom),
      duration: AppFlowyMotion.deliberate,
      curve: AppFlowyMotion.standardCurve,
      builder: (context, value, child) => FractionallySizedBox(
        widthFactor: value,
        child: child,
      ),
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(boxShadow: theme.pageShadow),
          child: Image(
            image: widget.image,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
          ),
        ),
      ),
    );

    // Horizontal overflow uses the same physics as the vertical axis.
    return Center(
      child: SingleChildScrollView(
        controller: horizontal,
        scrollDirection: Axis.horizontal,
        physics: const DocumentScrollPhysics(),
        child: SizedBox(
          width:
              math.max(constraints.maxWidth - 56, 0) * math.max(widget.zoom, 1),
          child: content,
        ),
      ),
    );
  }

  void _toggleZoom() {
    widget.onZoomChanged?.call(widget.zoom > 1.001 ? 1 : 2);
  }

  /// Ctrl/Cmd + wheel magnifies; a plain wheel keeps scrolling the document.
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || widget.onZoomChanged == null) {
      return;
    }
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final zooming = pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    if (!zooming) {
      return;
    }
    final next = (widget.zoom * math.exp(-event.scrollDelta.dy / 420)).clamp(
      DocumentImageStage.minZoom,
      DocumentImageStage.maxZoom,
    );
    widget.onZoomChanged!(next);
  }
}

/// Minimal, integrated transport controls for video and audio.
///
/// Nothing here reads as a browser or Material player: a single row of quiet
/// glyphs, a hairline progress track and tabular time.
class DocumentTransportBar extends StatelessWidget {
  const DocumentTransportBar({
    super.key,
    required this.playing,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onSeek,
    this.muted = false,
    this.onToggleMute,
    this.trailing = const [],
    this.overlay = false,
  });

  final bool playing;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final bool muted;
  final VoidCallback? onToggleMute;
  final List<Widget> trailing;

  /// Overlay bars float above video; inline bars sit on the audio surface.
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final typography = DocumentTypography.resolve(theme);
    final foreground = overlay ? const Color(0xFFEDEEF0) : theme.icon;

    final bar = Row(
      children: [
        DocumentToolbarButton(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: onPlayPause,
          iconSize: 19,
        ),
        const SizedBox(width: 6),
        Text(
          formatMediaTime(position),
          style: typography.caption.copyWith(
            color: foreground,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DocumentProgressTrack(
            value: duration.inMilliseconds == 0
                ? 0
                : position.inMilliseconds / duration.inMilliseconds,
            onSeek: (fraction) => onSeek(
              Duration(
                milliseconds: (duration.inMilliseconds * fraction).round(),
              ),
            ),
            overlay: overlay,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          formatMediaTime(duration),
          style: typography.caption.copyWith(
            color:
                overlay ? foreground.withValues(alpha: 0.7) : theme.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (onToggleMute != null) ...[
          const SizedBox(width: 4),
          DocumentToolbarButton(
            icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            tooltip: muted ? 'Unmute' : 'Mute',
            onPressed: onToggleMute,
          ),
        ],
        ...trailing,
      ],
    );

    if (!overlay) {
      return bar;
    }
    return DocumentToolbar(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      children: [Expanded(child: bar)],
    );
  }
}

/// A hairline scrub track with a soft handle. No Material [Slider].
class DocumentProgressTrack extends StatefulWidget {
  const DocumentProgressTrack({
    super.key,
    required this.value,
    required this.onSeek,
    this.overlay = false,
  });

  final double value;
  final ValueChanged<double> onSeek;
  final bool overlay;

  @override
  State<DocumentProgressTrack> createState() => _DocumentProgressTrackState();
}

class _DocumentProgressTrackState extends State<DocumentProgressTrack> {
  bool hovering = false;
  double? dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final progress = (dragValue ?? widget.value).clamp(0.0, 1.0);
    final active = widget.overlay ? const Color(0xFFF2F3F5) : theme.accent;
    final track = widget.overlay ? const Color(0x40FFFFFF) : theme.divider;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _seek(details.localPosition.dx),
        onHorizontalDragStart: (details) => _drag(details.localPosition.dx),
        onHorizontalDragUpdate: (details) => _drag(details.localPosition.dx),
        onHorizontalDragEnd: (_) {
          if (dragValue != null) {
            widget.onSeek(dragValue!);
            setState(() => dragValue = null);
          }
        },
        child: SizedBox(
          height: 22,
          child: Center(
            child: AnimatedContainer(
              duration: AppFlowyMotion.fast,
              curve: AppFlowyMotion.standardCurve,
              height: hovering || dragValue != null ? 5 : 3,
              decoration: BoxDecoration(
                color: track,
                borderRadius: BorderRadius.circular(999),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: active,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _drag(double dx) {
    final width = context.size?.width ?? 0;
    if (width <= 0) {
      return;
    }
    setState(() => dragValue = (dx / width).clamp(0.0, 1.0));
  }

  void _seek(double dx) {
    final width = context.size?.width ?? 0;
    if (width <= 0) {
      return;
    }
    widget.onSeek((dx / width).clamp(0.0, 1.0));
  }
}

/// `1:04` / `1:02:03`, never `0:01:04`.
String formatMediaTime(Duration duration) {
  final total = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final paddedSeconds = seconds.toString().padLeft(2, '0');
  if (hours == 0) {
    return '$minutes:$paddedSeconds';
  }
  return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
}

/// A dimmed backdrop that reveals overlay controls while the pointer moves.
class DocumentMediaOverlay extends StatefulWidget {
  const DocumentMediaOverlay({
    super.key,
    required this.child,
    required this.controls,
    this.alwaysVisible = false,
  });

  final Widget child;
  final Widget controls;
  final bool alwaysVisible;

  static const Duration idleDelay = Duration(milliseconds: 1800);

  @override
  State<DocumentMediaOverlay> createState() => _DocumentMediaOverlayState();
}

class _DocumentMediaOverlayState extends State<DocumentMediaOverlay> {
  bool visible = true;
  DateTime lastActivity = DateTime.now();

  void _wake() {
    lastActivity = DateTime.now();
    if (!visible) {
      setState(() => visible = true);
    }
    Future<void>.delayed(DocumentMediaOverlay.idleDelay, () {
      if (!mounted) {
        return;
      }
      final idle = DateTime.now().difference(lastActivity);
      if (idle >= DocumentMediaOverlay.idleDelay && visible) {
        setState(() => visible = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _wake(),
      onExit: (_) => setState(() => visible = widget.alwaysVisible),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: AnimatedOpacity(
              duration: AppFlowyMotion.gentle,
              curve: AppFlowyMotion.standardCurve,
              opacity: widget.alwaysVisible || visible ? 1 : 0,
              child: IgnorePointer(
                ignoring: !(widget.alwaysVisible || visible),
                child: widget.controls,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
