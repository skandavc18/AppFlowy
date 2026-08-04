import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_number.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A chart that answers the pointer.
///
/// Hovering names the value under it and quiets the rest, the legend turns a
/// series off and on, the wheel zooms into a crowded axis and a drag moves
/// along it. A double click puts everything back.
class AppChart extends StatefulWidget {
  const AppChart({
    super.key,
    required this.data,
    required this.spec,
    required this.palette,
    this.onSelected,
    this.animate = true,
    this.allowZoom = true,
  });

  final ChartData data;
  final ChartSpec spec;
  final ChartPalette palette;

  /// What colour each series is drawn in.
  ChartColors get colors => ChartColors.of(palette, spec);

  /// The category and series that were clicked.
  final void Function(String category, String series)? onSelected;
  final bool animate;
  final bool allowZoom;

  @override
  State<AppChart> createState() => _AppChartState();
}

class _AppChartState extends State<AppChart> with TickerProviderStateMixin {
  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: ChartMetrics.revealDuration,
  );
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _revealController,
    curve: ChartMetrics.revealCurve,
  );
  late final AnimationController _emphasisController = AnimationController(
    vsync: this,
    duration: ChartMetrics.hoverDuration,
  );
  late final Animation<double> _emphasis = CurvedAnimation(
    parent: _emphasisController,
    curve: ChartMetrics.hoverCurve,
  );

  final List<ChartHit> _hits = [];
  final Set<int> _hidden = <int>{};
  ChartHit? _hover;
  int? _focusedSeries;
  Offset? _pointer;
  ChartViewport _viewport = ChartViewport.identity;
  Size _plotSize = Size.zero;
  bool _hoveringPlot = false;

  bool get _canZoom =>
      widget.allowZoom &&
      widget.spec.type.isCartesian &&
      !widget.spec.type.isHorizontal;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _revealController.forward();
    } else {
      _revealController.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant AppChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.spec.type != widget.spec.type) {
      if (widget.animate) {
        _revealController.forward(from: 0);
      }
      _hover = null;
    }
    if (oldWidget.data.series.length != widget.data.series.length) {
      _hidden.removeWhere((index) => index >= widget.data.series.length);
      _viewport = ChartViewport.identity;
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    _emphasisController.dispose();
    super.dispose();
  }

  bool get _showsLegend =>
      widget.spec.showLegend &&
      (widget.spec.type.isCircular
          ? widget.data.series.isNotEmpty
          : widget.data.series.length > 1);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _plot()),
          if (_showsLegend) ...[
            const SizedBox(height: ChartMetrics.legendGap),
            _ChartLegend(
              data: widget.data,
              spec: widget.spec,
              palette: widget.palette,
              colors: widget.colors,
              hidden: _hidden,
              focused: _focusedSeries,
              onFocus: _focusSeries,
              onToggle: _toggleSeries,
            ),
          ],
        ],
      );

  Widget _plot() => LayoutBuilder(
        builder: (context, constraints) {
          _plotSize = constraints.biggest;
          return Listener(
            onPointerSignal: _canZoom ? _onScroll : null,
            child: MouseRegion(
              cursor: _viewport.isIdentity
                  ? MouseCursor.defer
                  : SystemMouseCursors.grab,
              onEnter: (_) => setState(() => _hoveringPlot = true),
              onHover: (event) => _updateHover(event.localPosition),
              onExit: (_) {
                setState(() => _hoveringPlot = false);
                _updateHover(null);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _onTap,
                onDoubleTap: _canZoom ? _resetZoom : null,
                onHorizontalDragUpdate:
                    _canZoom && !_viewport.isIdentity ? _onPan : null,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: ChartPainter(
                            data: widget.data,
                            spec: widget.spec,
                            palette: widget.palette,
                            colors: widget.colors,
                            hidden: _hidden,
                            highlight: _hover,
                            focusedSeries: _focusedSeries,
                            reveal: _reveal,
                            emphasis: _emphasis,
                            viewport: _viewport,
                            crosshair: _pointer,
                            hits: _hits,
                          ),
                        ),
                      ),
                    ),
                    if (_hover != null)
                      ChartTooltip(
                        hit: _hover!,
                        data: widget.data,
                        spec: widget.spec,
                        palette: widget.palette,
                        colors: widget.colors,
                        bounds: constraints.biggest,
                        emphasis: _emphasis,
                      ),
                    if (_canZoom)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: _ZoomControls(
                          palette: widget.palette,
                          viewport: _viewport,
                          visible: _hoveringPlot || !_viewport.isIdentity,
                          onZoomIn: () => _zoomBy(1.4),
                          onZoomOut: () => _zoomBy(1 / 1.4),
                          onReset: _resetZoom,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  // -------------------------------------------------------------- pointer

  void _updateHover(Offset? position) {
    if (position == null) {
      if (_hover != null || _pointer != null) {
        setState(() {
          _hover = null;
          _pointer = null;
        });
        _emphasisController.reverse();
      }
      return;
    }

    ChartHit? found;
    // Later shapes are drawn on top, so the last match is the visible one.
    for (final hit in _hits) {
      if (hit.rect.contains(position)) {
        found = hit;
      }
    }
    if (found != _hover || _pointer != position) {
      setState(() {
        _hover = found;
        _pointer = position;
      });
    }
    if (found != null) {
      _emphasisController.forward();
    } else {
      _emphasisController.reverse();
    }
  }

  void _onTap(TapDownDetails details) {
    _updateHover(details.localPosition);
    final hit = _hover;
    if (hit == null) {
      return;
    }
    final series = widget.data.series[hit.seriesIndex];
    final label = hit.pointIndex < series.points.length
        ? series.points[hit.pointIndex].label
        : '';
    widget.onSelected?.call(label, series.name);
  }

  void _onScroll(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _plotSize.width <= 0) {
      return;
    }
    // Only claim the wheel when the reader means to zoom; otherwise the page
    // should keep scrolling underneath.
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) {
      return;
    }
    final focus = (event.localPosition.dx / _plotSize.width).clamp(0.0, 1.0);
    final factor = event.scrollDelta.dy < 0 ? 1.18 : 1 / 1.18;
    final next = _viewport.zoomed(factor, focus);
    if (next != _viewport) {
      setState(() => _viewport = next);
    }
  }

  /// Zooms about the middle, which is what a button press means.
  void _zoomBy(double factor) {
    final next = _viewport.zoomed(factor, 0.5);
    if (next != _viewport) {
      setState(() => _viewport = next);
    }
  }

  void _onPan(DragUpdateDetails details) {
    if (_plotSize.width <= 0) {
      return;
    }
    final next = _viewport.panned(
      -details.delta.dx / (_plotSize.width * _viewport.scale),
    );
    if (next != _viewport) {
      setState(() => _viewport = next);
    }
  }

  void _resetZoom() {
    if (!_viewport.isIdentity) {
      setState(() => _viewport = ChartViewport.identity);
    }
  }

  // --------------------------------------------------------------- legend

  void _focusSeries(int? index) {
    if (_focusedSeries == index) {
      return;
    }
    setState(() => _focusedSeries = index);
    if (index == null) {
      _emphasisController.reverse();
    } else {
      _emphasisController.forward();
    }
  }

  void _toggleSeries(int index) {
    setState(() {
      if (!_hidden.remove(index)) {
        // Never hide the last one; an empty chart says nothing.
        if (_hidden.length < widget.data.series.length - 1) {
          _hidden.add(index);
        }
      }
    });
  }
}

/// The floating card that names what the pointer is over.
class ChartTooltip extends StatelessWidget {
  const ChartTooltip({
    super.key,
    required this.hit,
    required this.data,
    required this.spec,
    required this.palette,
    required this.colors,
    required this.bounds,
    required this.emphasis,
  });

  final ChartHit hit;
  final ChartData data;
  final ChartSpec spec;
  final ChartPalette palette;
  final ChartColors colors;
  final Size bounds;
  final Animation<double> emphasis;

  static const _width = 216.0;

  @override
  Widget build(BuildContext context) {
    if (hit.seriesIndex >= data.series.length) {
      return const SizedBox.shrink();
    }
    final series = data.series[hit.seriesIndex];
    if (hit.pointIndex >= series.points.length) {
      return const SizedBox.shrink();
    }
    final point = series.points[hit.pointIndex];

    // A tooltip that covers what it explains is no help; flip it when close
    // to an edge.
    final flipX = hit.anchor.dx + _width / 2 > bounds.width - 8;
    final flipLeft = hit.anchor.dx - _width / 2 < 8;
    final left = flipX
        ? bounds.width - _width - 8
        : flipLeft
            ? 8.0
            : hit.anchor.dx - _width / 2;
    final above = hit.anchor.dy > 96;

    return Positioned(
      left: left,
      top: above ? null : hit.anchor.dy + 16,
      bottom: above ? bounds.height - hit.anchor.dy + 12 : null,
      width: _width,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: emphasis,
          child: AnimatedBuilder(
            animation: emphasis,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, (1 - emphasis.value) * (above ? 4 : -4)),
              child: child,
            ),
            child: _card(point, series),
          ),
        ),
      ),
    );
  }

  Widget _card(ChartPoint point, ChartSeries series) => DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(ChartMetrics.tooltipRadius),
          border: Border.all(color: palette.border),
          boxShadow: chartTooltipShadow(palette),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                point.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: palette.text(
                  size: 11,
                  color: palette.label,
                  weight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 7),
              _row(
                color: spec.type.isCircular
                    ? colors.at(hit.pointIndex, point.label)
                    : colors.at(hit.seriesIndex, series.name),
                name: series.name.isEmpty ? _valueCaption() : series.name,
                value: ChartPainter.formatValue(point.value),
                strong: true,
              ),
              if (point.x != null) ...[
                const SizedBox(height: 4),
                _row(
                  color: null,
                  name: spec.xColumn ?? '',
                  value: ChartPainter.formatValue(point.x!),
                ),
              ],
              if (point.size != null && spec.type.sizesPoints) ...[
                const SizedBox(height: 4),
                _row(
                  color: null,
                  name: spec.sizeColumn ?? '',
                  value: ChartPainter.formatValue(point.size!),
                ),
              ],
              if (spec.type.isCircular) ...[
                const SizedBox(height: 4),
                _row(
                  color: null,
                  name: 'Share',
                  value: series.total <= 0
                      ? '—'
                      : '${(point.value.abs() / series.total * 100).toStringAsFixed(1)}%',
                ),
              ],
            ],
          ),
        ),
      );

  String _valueCaption() =>
      spec.valueColumns.isEmpty ? 'Rows' : spec.valueColumns.first;

  Widget _row({
    required Color? color,
    required String name,
    required String value,
    bool strong = false,
  }) =>
      Row(
        children: [
          if (color != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(width: 7),
          ] else
            const SizedBox(width: 15),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: palette.text(
                size: 11.5,
                color: palette.label,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: palette.text(
              size: strong ? 13 : 11.5,
              color: strong ? palette.strongLabel : palette.label,
              weight: strong ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      );
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({
    required this.data,
    required this.spec,
    required this.palette,
    required this.colors,
    required this.hidden,
    required this.focused,
    required this.onFocus,
    required this.onToggle,
  });

  final ChartData data;
  final ChartSpec spec;
  final ChartPalette palette;
  final ChartColors colors;
  final Set<int> hidden;
  final int? focused;
  final ValueChanged<int?> onFocus;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    // A pie's legend names its slices; everything else names its series.
    final circular = spec.type.isCircular;
    final entries = circular
        ? [
            for (var index = 0;
                index < data.series.first.points.length;
                index++)
              (index, data.series.first.points[index].label),
          ]
        : [
            for (var index = 0; index < data.series.length; index++)
              (index, data.series[index].name),
          ];

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      alignment: WrapAlignment.center,
      children: [
        for (final entry in entries)
          _LegendChip(
            label: entry.$2.isEmpty ? _fallbackName() : entry.$2,
            color: colors.at(entry.$1, entry.$2),
            palette: palette,
            muted: !circular && hidden.contains(entry.$1),
            dimmed: focused != null && focused != entry.$1 && !circular,
            onEnter: circular ? null : () => onFocus(entry.$1),
            onExit: circular ? null : () => onFocus(null),
            onTap: circular ? null : () => onToggle(entry.$1),
          ),
      ],
    );
  }

  String _fallbackName() =>
      spec.valueColumns.isEmpty ? 'Rows' : spec.valueColumns.first;
}

class _LegendChip extends StatefulWidget {
  const _LegendChip({
    required this.label,
    required this.color,
    required this.palette,
    required this.muted,
    required this.dimmed,
    this.onEnter,
    this.onExit,
    this.onTap,
  });

  final String label;
  final Color color;
  final ChartPalette palette;
  final bool muted;
  final bool dimmed;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  final VoidCallback? onTap;

  @override
  State<_LegendChip> createState() => _LegendChipState();
}

class _LegendChipState extends State<_LegendChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final quiet = widget.muted || widget.dimmed;
    return MouseRegion(
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onEnter?.call();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onExit?.call();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: ChartMetrics.hoverDuration,
          curve: ChartMetrics.hoverCurve,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? palette.chip : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: ChartMetrics.hoverDuration,
                curve: ChartMetrics.hoverCurve,
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.color.withValues(
                    alpha: quiet ? 0.3 : 1,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 168),
                child: AnimatedDefaultTextStyle(
                  duration: ChartMetrics.hoverDuration,
                  curve: ChartMetrics.hoverCurve,
                  style: palette.text(
                    size: 11.5,
                    color: widget.muted
                        ? palette.label.withValues(alpha: palette.label.a * 0.5)
                        : quiet
                            ? palette.label
                            : palette.strongLabel,
                    weight: FontWeight.w500,
                  ),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// The cluster that zooms the chart, and says how far in it is.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.palette,
    required this.viewport,
    required this.visible,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final ChartPalette palette;
  final ChartViewport viewport;
  final bool visible;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: ChartMetrics.hoverDuration,
        curve: ChartMetrics.hoverCurve,
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.border),
              boxShadow: chartCardShadow(palette),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ZoomButton(
                  icon: Icons.remove_rounded,
                  palette: palette,
                  enabled: !viewport.isIdentity,
                  onTap: onZoomOut,
                ),
                GestureDetector(
                  onTap: viewport.isIdentity ? null : onReset,
                  child: MouseRegion(
                    cursor: viewport.isIdentity
                        ? MouseCursor.defer
                        : SystemMouseCursors.click,
                    child: SizedBox(
                      width: 40,
                      height: 24,
                      child: Center(
                        child: Text(
                          '${formatChartNumber(viewport.scale)}×',
                          style: palette.text(
                            size: 10.5,
                            color: viewport.isIdentity
                                ? palette.label
                                : palette.strongLabel,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _ZoomButton(
                  icon: Icons.add_rounded,
                  palette: palette,
                  enabled: viewport.scale < 40,
                  onTap: onZoomIn,
                ),
              ],
            ),
          ),
        ),
      );
}

class _ZoomButton extends StatefulWidget {
  const _ZoomButton({
    required this.icon,
    required this.palette,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final ChartPalette palette;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<_ZoomButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: ChartMetrics.hoverDuration,
          curve: ChartMetrics.hoverCurve,
          width: 26,
          height: 24,
          decoration: BoxDecoration(
            color: _hovered && widget.enabled
                ? palette.chipHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            widget.icon,
            size: 14,
            color: widget.enabled
                ? (_hovered ? palette.strongLabel : palette.label)
                : palette.label.withValues(alpha: palette.label.a * 0.4),
          ),
        ),
      ),
    );
  }
}
