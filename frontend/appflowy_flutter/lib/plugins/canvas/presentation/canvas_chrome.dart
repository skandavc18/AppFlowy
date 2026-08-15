import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_painters.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_geometry.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The floating chrome a canvas wears. All of it is small, all of it fades in
/// and none of it takes a permanent bite out of the surface.

/// The tool strip.
class CanvasToolbar extends StatelessWidget {
  const CanvasToolbar({
    super.key,
    required this.palette,
    required this.tool,
    required this.onToolChanged,
    required this.onAdd,
    required this.onMore,
    this.compact = false,
  });

  final CanvasPalette palette;
  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolChanged;

  /// Opens the "what would you like to put down?" menu.
  final void Function(Offset globalPosition) onAdd;
  final void Function(Offset globalPosition) onMore;

  /// A narrow canvas keeps only the tools that cannot be reached another way.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget tool_(CanvasTool value, IconData icon, String label) => CanvasButton(
          icon: icon,
          palette: palette,
          selected: tool == value,
          accented: true,
          tooltip: label,
          onPressed: () => onToolChanged(value),
        );

    return CanvasSurface(
      palette: palette,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tool_(
            CanvasTool.select,
            Icons.near_me_rounded,
            LocaleKeys.canvas_toolbar_select.tr(),
          ),
          tool_(
            CanvasTool.hand,
            Icons.pan_tool_alt_rounded,
            LocaleKeys.canvas_toolbar_hand.tr(),
          ),
          _Divider(palette: palette),
          Builder(
            builder: (context) => CanvasButton(
              icon: Icons.add_rounded,
              palette: palette,
              tooltip: LocaleKeys.canvas_toolbar_add.tr(),
              onPressed: () => onAdd(_anchorOf(context)),
            ),
          ),
          tool_(
            CanvasTool.text,
            Icons.text_fields_rounded,
            LocaleKeys.canvas_toolbar_text.tr(),
          ),
          tool_(
            CanvasTool.connect,
            Icons.timeline_rounded,
            LocaleKeys.canvas_toolbar_connect.tr(),
          ),
          tool_(
            CanvasTool.frame,
            Icons.crop_free_rounded,
            LocaleKeys.canvas_toolbar_frame.tr(),
          ),
          if (!compact) ...[
            tool_(
              CanvasTool.draw,
              Icons.draw_rounded,
              LocaleKeys.canvas_toolbar_draw.tr(),
            ),
            tool_(
              CanvasTool.erase,
              Icons.cleaning_services_rounded,
              LocaleKeys.canvas_toolbar_erase.tr(),
            ),
          ],
          _Divider(palette: palette),
          Builder(
            builder: (context) => CanvasButton(
              icon: Icons.more_horiz_rounded,
              palette: palette,
              tooltip: LocaleKeys.canvas_toolbar_more.tr(),
              onPressed: () => onMore(_anchorOf(context)),
            ),
          ),
        ],
      ),
    );
  }

  static Offset _anchorOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return Offset.zero;
    }
    return box.localToGlobal(Offset(0, box.size.height + 6));
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});

  final CanvasPalette palette;

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: CanvasMetrics.space1),
        color: palette.border.withValues(alpha: 0.5),
      );
}

/// Zoom out, the reading, zoom in — and a click on the reading resets it.
class CanvasZoomCluster extends StatelessWidget {
  const CanvasZoomCluster({
    super.key,
    required this.palette,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
    required this.onFit,
  });

  final CanvasPalette palette;
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return CanvasSurface(
      palette: palette,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CanvasButton(
            icon: Icons.remove_rounded,
            palette: palette,
            size: 28,
            iconSize: 16,
            tooltip: LocaleKeys.canvas_zoom_zoomOut.tr(),
            onPressed: zoom > minimumCanvasZoom ? onZoomOut : null,
          ),
          Tooltip(
            message: LocaleKeys.canvas_zoom_reset.tr(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onReset,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 50,
                  height: 28,
                  child: Center(
                    child: Text(
                      formatCanvasZoom(zoom),
                      style: canvasLabelStyle(palette, size: 11.5),
                    ),
                  ),
                ),
              ),
            ),
          ),
          CanvasButton(
            icon: Icons.add_rounded,
            palette: palette,
            size: 28,
            iconSize: 16,
            tooltip: LocaleKeys.canvas_zoom_zoomIn.tr(),
            onPressed: zoom < maximumCanvasZoom ? onZoomIn : null,
          ),
          _Divider(palette: palette),
          CanvasButton(
            icon: Icons.fit_screen_rounded,
            palette: palette,
            size: 28,
            iconSize: 16,
            tooltip: LocaleKeys.canvas_zoom_fit.tr(),
            onPressed: onFit,
          ),
        ],
      ),
    );
  }
}

/// The whole canvas, small, with a window showing where you are looking.
class CanvasMinimap extends StatelessWidget {
  const CanvasMinimap({
    super.key,
    required this.document,
    required this.palette,
    required this.camera,
    required this.viewport,
    required this.onJump,
    required this.onHide,
  });

  final CanvasDocument document;
  final CanvasPalette palette;
  final CanvasCamera camera;
  final Size viewport;

  /// Where in the scene the pointer landed.
  final ValueChanged<Offset> onJump;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final content = document.bounds;
    if (content.isEmpty) {
      return const SizedBox.shrink();
    }
    final visible = camera.visibleScene(viewport);
    // A little air round the drawing, so the window is not clipped when you
    // are looking past the edge of what exists.
    final box = content.expandToInclude(visible).inflate(48);

    return CanvasSurface(
      palette: palette,
      padding: const EdgeInsets.all(CanvasMetrics.space2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: CanvasMetrics.minimapSize,
            height: CanvasMetrics.minimapSize * 0.68,
            child: Builder(
              builder: (context) => MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      _jump(context, details.localPosition, box),
                  onPanUpdate: (details) =>
                      _jump(context, details.localPosition, box),
                  child: CustomPaint(
                    painter: CanvasMinimapPainter(
                      document: document,
                      palette: palette,
                      content: box,
                      viewport: visible,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: CanvasMetrics.space1),
          Row(
            children: [
              Text(
                '${document.objectCount}',
                style: canvasLabelStyle(palette, size: 10.5),
              ),
              const Spacer(),
              CanvasButton(
                icon: Icons.close_rounded,
                palette: palette,
                size: 20,
                iconSize: 13,
                tooltip: LocaleKeys.canvas_minimap_hide.tr(),
                onPressed: onHide,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _jump(BuildContext context, Offset local, Rect box) {
    final render = context.findRenderObject() as RenderBox?;
    if (render == null || !render.hasSize || box.isEmpty) {
      return;
    }
    final size = render.size;
    final scale = (size.width / box.width) < (size.height / box.height)
        ? size.width / box.width
        : size.height / box.height;
    final origin = Offset(
      (size.width - box.width * scale) / 2,
      (size.height - box.height * scale) / 2,
    );
    onJump(box.topLeft + (local - origin) / scale);
  }
}

/// A list of the frames and named cards, so a large canvas can be navigated
/// by reading rather than by hunting.
class CanvasOutlinePanel extends StatelessWidget {
  const CanvasOutlinePanel({
    super.key,
    required this.palette,
    required this.entries,
    required this.onGoTo,
    required this.onHide,
    this.selected = const <String>{},
  });

  final CanvasPalette palette;
  final List<CanvasSearchHit> entries;
  final ValueChanged<String> onGoTo;
  final VoidCallback onHide;
  final Set<String> selected;

  @override
  Widget build(BuildContext context) {
    return CanvasSurface(
      palette: palette,
      padding: const EdgeInsets.fromLTRB(
        CanvasMetrics.space2,
        CanvasMetrics.space2,
        CanvasMetrics.space2,
        CanvasMetrics.space2,
      ),
      child: SizedBox(
        width: CanvasMetrics.outlineWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: CanvasMetrics.space1),
                Text(
                  LocaleKeys.canvas_outline_title.tr(),
                  style: canvasLabelStyle(
                    palette,
                    size: 11,
                    weight: FontWeight.w600,
                    color: palette.textMuted,
                  ),
                ),
                const Spacer(),
                CanvasButton(
                  icon: Icons.close_rounded,
                  palette: palette,
                  size: 22,
                  iconSize: 14,
                  tooltip: LocaleKeys.canvas_outline_hide.tr(),
                  onPressed: onHide,
                ),
              ],
            ),
            const SizedBox(height: CanvasMetrics.space1),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(CanvasMetrics.space3),
                child: Text(
                  LocaleKeys.canvas_outline_empty.tr(),
                  style: canvasLabelStyle(
                    palette,
                    size: 11.5,
                    color: palette.textMuted,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _OutlineRow(
                      palette: palette,
                      entry: entry,
                      selected: selected.contains(entry.id),
                      onTap: () => onGoTo(entry.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OutlineRow extends StatefulWidget {
  const _OutlineRow({
    required this.palette,
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final CanvasPalette palette;
  final CanvasSearchHit entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_OutlineRow> createState() => _OutlineRowState();
}

class _OutlineRowState extends State<_OutlineRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final isFrame = widget.entry.kind == CanvasHitKind.frame;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: CanvasMetrics.hover,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: EdgeInsets.only(
            left: isFrame ? CanvasMetrics.space2 : CanvasMetrics.space4,
            right: CanvasMetrics.space2,
            top: 5,
            bottom: 5,
          ),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.accent.withValues(alpha: 0.12)
                : _hovered
                    ? Color.alphaBlend(palette.hover, palette.hoverAtRest)
                    : palette.hoverAtRest,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(
                isFrame ? Icons.crop_free_rounded : Icons.circle,
                size: isFrame ? 13 : 5,
                color: palette.textMuted,
              ),
              const SizedBox(width: CanvasMetrics.space2),
              Expanded(
                child: Text(
                  widget.entry.label.trim().isEmpty
                      ? LocaleKeys.canvas_frame_untitled.tr()
                      : widget.entry.label.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: canvasLabelStyle(
                    palette,
                    weight: isFrame ? FontWeight.w600 : FontWeight.w500,
                    color: widget.selected
                        ? palette.accent
                        : palette.textSecondary,
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

/// Find on this canvas.
class CanvasSearchBar extends StatefulWidget {
  const CanvasSearchBar({
    super.key,
    required this.palette,
    required this.query,
    required this.hits,
    required this.index,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  });

  final CanvasPalette palette;
  final String query;
  final List<CanvasSearchHit> hits;
  final int index;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;

  @override
  State<CanvasSearchBar> createState() => _CanvasSearchBarState();
}

class _CanvasSearchBarState extends State<CanvasSearchBar> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.query);
  final FocusNode _focus = FocusNode(debugLabel: 'canvas_search');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final hits = widget.hits;
    return CanvasSurface(
      palette: palette,
      padding: const EdgeInsets.symmetric(
        horizontal: CanvasMetrics.space3,
        vertical: CanvasMetrics.space1,
      ),
      child: SizedBox(
        width: 340,
        height: 34,
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 16, color: palette.textMuted),
            const SizedBox(width: CanvasMetrics.space2),
            Expanded(
              child: TextEntryShortcuts(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  style: canvasLabelStyle(
                    palette,
                    size: 13,
                    color: palette.textPrimary,
                  ),
                  cursorColor: palette.accent,
                  onChanged: widget.onQueryChanged,
                  onSubmitted: (_) => widget.onNext(),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    hintText: LocaleKeys.canvas_search_placeholder.tr(),
                    hintStyle: canvasLabelStyle(
                      palette,
                      size: 13,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.query.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  hits.isEmpty
                      ? LocaleKeys.canvas_search_noResults.tr()
                      : LocaleKeys.canvas_search_counter.tr(
                          args: ['${widget.index + 1}', '${hits.length}'],
                        ),
                  style: canvasLabelStyle(
                    palette,
                    size: 11,
                    color: palette.textMuted,
                  ),
                ),
              ),
            CanvasButton(
              icon: Icons.keyboard_arrow_up_rounded,
              palette: palette,
              size: 24,
              iconSize: 16,
              tooltip: LocaleKeys.canvas_search_previous.tr(),
              onPressed: hits.isEmpty ? null : widget.onPrevious,
            ),
            CanvasButton(
              icon: Icons.keyboard_arrow_down_rounded,
              palette: palette,
              size: 24,
              iconSize: 16,
              tooltip: LocaleKeys.canvas_search_next.tr(),
              onPressed: hits.isEmpty ? null : widget.onNext,
            ),
            CanvasButton(
              icon: Icons.close_rounded,
              palette: palette,
              size: 24,
              iconSize: 15,
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// What an empty canvas says, and the one thing it offers.
class CanvasEmptyState extends StatelessWidget {
  const CanvasEmptyState({
    super.key,
    required this.palette,
    required this.onUseTemplate,
  });

  final CanvasPalette palette;
  final VoidCallback onUseTemplate;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              LocaleKeys.canvas_empty_title.tr(),
              style: canvasLabelStyle(
                palette,
                size: 16,
                weight: FontWeight.w600,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: CanvasMetrics.space2),
            Text(
              LocaleKeys.canvas_empty_body.tr(),
              textAlign: TextAlign.center,
              style: canvasLabelStyle(
                palette,
                size: 12.5,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: CanvasMetrics.space4),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onUseTemplate,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CanvasMetrics.space4,
                    vertical: CanvasMetrics.space2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(CanvasMetrics.controlRadius),
                  ),
                  child: Text(
                    LocaleKeys.canvas_empty_action.tr(),
                    style: canvasLabelStyle(
                      palette,
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: palette.accent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The line that says what the tool in hand is waiting for.
class CanvasHintBar extends StatelessWidget {
  const CanvasHintBar({
    super.key,
    required this.palette,
    required this.message,
    required this.onDismiss,
  });

  final CanvasPalette palette;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return CanvasSurface(
      palette: palette,
      padding: const EdgeInsets.only(
        left: CanvasMetrics.space3,
        right: CanvasMetrics.space1,
        top: CanvasMetrics.space1,
        bottom: CanvasMetrics.space1,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: canvasLabelStyle(palette)),
          const SizedBox(width: CanvasMetrics.space2),
          CanvasButton(
            icon: Icons.close_rounded,
            palette: palette,
            size: 22,
            iconSize: 14,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
