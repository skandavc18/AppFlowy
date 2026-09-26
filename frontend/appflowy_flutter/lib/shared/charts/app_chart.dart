import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_number.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
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
    this.interactionSpec,
    this.onSelected,
    this.animate = true,
    this.allowZoom = true,
  });

  final ChartData data;
  final ChartSpec spec;
  final ChartPalette palette;

  /// The resolved column identities behind [spec]'s display labels. A host
  /// supplies the available value columns so a rename preserves interactions,
  /// while removing or replacing a plotted column cannot reuse hidden indices.
  final ChartSpec? interactionSpec;

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
  AnimationController? _revealController;
  CurvedAnimation? _revealCurve;
  AnimationController? _emphasisController;
  CurvedAnimation? _emphasisCurve;
  bool _motionEnabled = false;
  bool _started = false;

  Animation<double> get _reveal =>
      _motionEnabled ? _revealCurve! : kAlwaysCompleteAnimation;
  Animation<double> get _emphasis => _motionEnabled
      ? _emphasisCurve!
      : _hover != null || _focusedSeries != null
          ? kAlwaysCompleteAnimation
          : kAlwaysDismissedAnimation;

  final List<ChartHit> _hits = [];
  final Set<int> _hidden = <int>{};
  ChartHit? _hover;
  int? _focusedSeries;
  Offset? _pointer;
  ChartViewport _viewport = ChartViewport.identity;
  Size _plotSize = Size.zero;

  bool get _canZoom =>
      widget.allowZoom &&
      widget.spec.type.isCartesian &&
      !widget.spec.type.isHorizontal;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureMotion();
    if (!_started) {
      _started = true;
      _playReveal();
    }
  }

  void _configureMotion() {
    _motionEnabled = widget.animate &&
        WorkspaceTokens.motion(context, ChartMetrics.revealDuration) !=
            Duration.zero;
    if (!_motionEnabled) {
      _revealController?.stop();
      _emphasisController?.stop();
      _revealController?.value = 1;
      _emphasisController?.value =
          _hover != null || _focusedSeries != null ? 1 : 0;
      return;
    }
    _revealController ??= AnimationController(
      vsync: this,
      value: 1,
      duration: ChartMetrics.revealDuration,
    );
    _revealCurve ??= CurvedAnimation(
      parent: _revealController!,
      curve: ChartMetrics.revealCurve,
    );
    _emphasisController ??= AnimationController(
      vsync: this,
      value: _hover != null || _focusedSeries != null ? 1 : 0,
      duration: ChartMetrics.hoverDuration,
    );
    _emphasisCurve ??= CurvedAnimation(
      parent: _emphasisController!,
      curve: ChartMetrics.hoverCurve,
    );
  }

  void _playReveal() {
    if (_motionEnabled) _revealController!.forward(from: 0);
  }

  void _emphasize(bool active) {
    if (!_motionEnabled) return;
    if (active) {
      _emphasisController!.forward();
    } else {
      _emphasisController!.reverse();
    }
  }

  @override
  void didUpdateWidget(covariant AppChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configureMotion();
    final before = oldWidget.interactionSpec ?? oldWidget.spec;
    final after = widget.interactionSpec ?? widget.spec;
    // Fresh rows may add, remove or reorder buckets without changing what the
    // reader asked to plot. Reset for a new reading, not for each live reload.
    final resetInteraction = before.type != after.type ||
        before.categoryColumn != after.categoryColumn ||
        before.xColumn != after.xColumn ||
        before.sizeColumn != after.sizeColumn ||
        before.aggregate != after.aggregate ||
        before.sort != after.sort ||
        before.categoryLimit != after.categoryLimit ||
        !listEquals(before.valueColumns, after.valueColumns) ||
        oldWidget.data.measuresX != widget.data.measuresX ||
        oldWidget.data.series.length != widget.data.series.length ||
        (widget.interactionSpec == null &&
            !listEquals(
              oldWidget.data.series.map((series) => series.name).toList(),
              widget.data.series.map((series) => series.name).toList(),
            ));
    // A fresh projection on theme/toolbar/refresh-start rebuilds is not new
    // data. Do not restart the drawing or discard its readout for that.
    if (!_sameChartData(oldWidget.data, widget.data) || resetInteraction) {
      _playReveal();
      _hover = null;
      _pointer = null;
      _hits.clear();
    }
    if (resetInteraction) {
      _hidden.clear();
      _focusedSeries = null;
      _viewport = ChartViewport.identity;
      _emphasisController?.value = 0;
    }
    if (!widget.spec.showLegend && _focusedSeries != null) {
      // MouseRegion does not report exit when a hovered legend is removed.
      // Hidden legend chrome must not leave the remaining marks dimmed.
      _focusedSeries = null;
      _emphasize(_hover != null);
    }
  }

  @override
  void dispose() {
    _revealCurve?.dispose();
    _emphasisCurve?.dispose();
    _revealController?.dispose();
    _emphasisController?.dispose();
    super.dispose();
  }

  bool get _showsLegend =>
      widget.spec.showLegend &&
      (widget.spec.type.isCircular
          ? widget.data.series.isNotEmpty
          : widget.data.series.length > 1);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _plot()),
            if (_showsLegend) ...[
              const SizedBox(height: ChartMetrics.legendGap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _legendHeight(context, constraints.maxHeight),
                ),
                child: SingleChildScrollView(
                  primary: false,
                  child: _ChartLegend(
                    data: widget.data,
                    spec: widget.spec,
                    palette: widget.palette,
                    colors: widget.colors,
                    hidden: _hidden,
                    focused: _focusedSeries,
                    onFocus: _focusSeries,
                    onToggle: _toggleSeries,
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  double _legendHeight(BuildContext context, double height) {
    // Allocate whole wrapped rows, not 30% of a row cut through its labels.
    // The scroll view and keyed buttons themselves stay at a stable depth.
    final row = MediaQuery.textScalerOf(context).scale(11.5) * 1.2 + 8;
    final rows = (height * 0.4 / (row + 2)).floor().clamp(1, 3);
    return math.max(
      0,
      math.min(height - ChartMetrics.legendGap, (row + 2) * rows - 2),
    );
  }

  Widget _plot() => LayoutBuilder(
        builder: (context, constraints) {
          if (_plotSize != constraints.biggest) {
            _plotSize = constraints.biggest;
            // A new paint owns the resized geometry; keep viewport/focus,
            // but never use a stale point anchor from the old dimensions.
            _hover = null;
            _pointer = null;
          }
          final painter = ChartPainter(
            data: widget.data,
            spec: widget.spec,
            palette: widget.palette,
            colors: widget.colors,
            hidden: Set<int>.of(_hidden),
            highlight: _hover,
            focusedSeries: _focusedSeries,
            reveal: _reveal,
            emphasis: _emphasis,
            viewport: _viewport,
            crosshair: _pointer,
            hits: _hits,
            textScaler: MediaQuery.textScalerOf(context),
          );
          return Listener(
            onPointerSignal: _canZoom ? _onScroll : null,
            child: MouseRegion(
              cursor: _viewport.isIdentity
                  ? MouseCursor.defer
                  : SystemMouseCursors.grab,
              onHover: (event) => _updateHover(event.localPosition),
              onExit: (_) {
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
                          painter: painter,
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
                        contentBounds:
                            painter.plotBoundsFor(constraints.biggest),
                        emphasis: _emphasis,
                        avoidBounds: _canZoom
                            ? _ZoomControls.boundsFor(
                                context,
                                constraints.biggest,
                              )
                            : null,
                      ),
                    if (_canZoom)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: _ZoomControls(
                          palette: widget.palette,
                          viewport: _viewport,
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
        _emphasize(_focusedSeries != null);
      }
      return;
    }

    ChartHit? found;
    // Later shapes are drawn on top, so the last match is the visible one.
    for (final hit in _hits) {
      if (hit.contains(position)) {
        found = hit;
      }
    }
    // The guide follows a point, not every pixel of pointer travel. Animation
    // ticks repaint directly; moving within an unchanged mark needs no build.
    if (found != _hover ||
        found?.anchor != _hover?.anchor ||
        found?.rect != _hover?.rect) {
      setState(() {
        _hover = found;
        _pointer = found == null ? null : position;
      });
    }
    _emphasize(found != null || _focusedSeries != null);
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
    _setViewport(next);
  }

  /// Zooms about the middle, which is what a button press means.
  void _zoomBy(double factor) {
    final next = _viewport.zoomed(factor, 0.5);
    _setViewport(next);
  }

  void _onPan(DragUpdateDetails details) {
    if (_plotSize.width <= 0) {
      return;
    }
    final next = _viewport.panned(
      -details.delta.dx / (_plotSize.width * _viewport.scale),
    );
    _setViewport(next);
  }

  void _resetZoom() => _setViewport(ChartViewport.identity);

  void _setViewport(ChartViewport next) {
    if (next == _viewport) return;
    setState(() {
      _viewport = next;
      _hover = null;
      _pointer = null;
      _hits.clear();
    });
    _emphasize(_focusedSeries != null);
  }

  // --------------------------------------------------------------- legend

  void _focusSeries(int? index) {
    if (_hidden.contains(index)) index = null;
    if (_focusedSeries == index) {
      return;
    }
    setState(() => _focusedSeries = index);
    _emphasize(index != null || _hover != null);
  }

  void _toggleSeries(int index) {
    setState(() {
      if (!_hidden.remove(index)) {
        // Never hide the last one; an empty chart says nothing.
        if (_hidden.length < widget.data.series.length - 1) {
          _hidden.add(index);
        }
      }
      if (_hidden.contains(_focusedSeries)) _focusedSeries = null;
      _hover = null;
      _pointer = null;
    });
    _emphasize(_focusedSeries != null);
  }
}

bool _sameChartData(ChartData a, ChartData b) {
  if (identical(a, b)) return true;
  if (a.minimum != b.minimum ||
      a.maximum != b.maximum ||
      a.xMinimum != b.xMinimum ||
      a.xMaximum != b.xMaximum ||
      a.sizeMaximum != b.sizeMaximum ||
      a.measuresX != b.measuresX ||
      !listEquals(a.categories, b.categories) ||
      a.series.length != b.series.length) {
    return false;
  }
  for (var index = 0; index < a.series.length; index++) {
    final before = a.series[index];
    final after = b.series[index];
    if (before.name != after.name ||
        before.points.length != after.points.length) {
      return false;
    }
    for (var point = 0; point < before.points.length; point++) {
      final x = before.points[point];
      final y = after.points[point];
      if (x.label != y.label ||
          x.value != y.value ||
          x.x != y.x ||
          x.size != y.size) {
        return false;
      }
    }
  }
  return true;
}

/// A compact annotation on the plot, not a floating surface. The historical
/// name remains for callers; full numbers are never ellipsized.
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
    this.avoidBounds,
    this.contentBounds,
  });

  final ChartHit hit;
  final ChartData data;
  final ChartSpec spec;
  final ChartPalette palette;
  final ChartColors colors;
  final Size bounds;
  final Animation<double> emphasis;

  /// Reserved top-right chrome in plot coordinates, never a tooltip surface.
  final Rect? avoidBounds;

  /// Plot coordinates after axes have reserved their label gutters.
  final Rect? contentBounds;

  @override
  Widget build(BuildContext context) {
    if (hit.seriesIndex < 0 ||
        hit.seriesIndex >= data.series.length ||
        bounds.isEmpty) {
      return const SizedBox.shrink();
    }
    final series = data.series[hit.seriesIndex];
    if (hit.pointIndex < 0 || hit.pointIndex >= series.points.length) {
      return const SizedBox.shrink();
    }
    final point = series.points[hit.pointIndex];
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final hole = (math.min(bounds.width, bounds.height) / 2 - 12) * 0.58;
    final centered = spec.type == ChartType.donut && hole >= 58 * scale;
    var available = (contentBounds ?? (Offset.zero & bounds))
        .intersect(Offset.zero & bounds);
    final inset = math.min(8.0, available.shortestSide / 2).clamp(0.0, 8.0);
    available = available.deflate(inset);
    final avoid = avoidBounds;
    if (avoid != null && available.overlaps(avoid)) {
      available = Rect.fromLTRB(
        available.left,
        math.min(available.bottom, avoid.bottom + inset),
        available.right,
        available.bottom,
      );
    }
    final width = math.max(
      0.0,
      math.min(
        available.width,
        centered ? hole * math.sqrt2 - 8 : 280 * scale,
      ),
    );
    final height = math.max(
      0.0,
      math.min(
        available.height,
        centered ? hole * math.sqrt2 - 8 : bounds.height,
      ),
    );
    final name = series.name.isEmpty ? _valueCaption() : series.name;
    final value = ChartPainter.formatValue(point.value);
    final share = !spec.type.isCircular
        ? null
        : series.total <= 0
            ? '—'
            : '${(point.value.abs() / series.total * 100).toStringAsFixed(1)}%';
    final details = <String>[
      if (point.x != null)
        '${spec.xColumn ?? ''} ${ChartPainter.formatValue(point.x!)}',
      if (point.size != null && spec.type.sizesPoints)
        '${spec.sizeColumn ?? ''} ${ChartPainter.formatValue(point.size!)}',
    ];
    final color = spec.type.isCircular
        ? colors.at(hit.pointIndex, point.label)
        : colors.at(hit.seriesIndex, series.name);

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: _ChartReadoutLayout(
            anchor: hit.anchor,
            centered: centered,
            top: spec.type == ChartType.pie,
            maximum: Size(width, height),
            available: available,
          ),
          child: FadeTransition(
            opacity: emphasis,
            child: Semantics(
              label: '${point.label}, $name: $value'
                  '${share == null ? '' : ', $share'}'
                  '${details.isEmpty ? '' : ', ${details.join(', ')}'}',
              excludeSemantics: true,
              // Very short hosts may not fit a scaled readout. Scale the
              // complete annotation only as a last resort, not its numbers.
              child: FittedBox(
                key: const ValueKey('chart-readout'),
                fit: BoxFit.scaleDown,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: centered
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: centered
                            ? WrapAlignment.center
                            : WrapAlignment.start,
                        children: [
                          Container(
                            key: const ValueKey('chart-readout-swatch'),
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            value,
                            key: const ValueKey('chart-readout-value'),
                            style: _ink(16, strong: true),
                          ),
                          if (share != null)
                            Text(
                              share,
                              key: const ValueKey('chart-readout-share'),
                              style: _ink(11.5),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${point.label} · $name',
                        key: const ValueKey('chart-readout-label'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign:
                            centered ? TextAlign.center : TextAlign.start,
                        style: _ink(11.5),
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(details.join(' · '), style: _ink(11)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _ink(double size, {bool strong = false}) => palette
          .text(
        size: size,
        color: strong ? palette.strongLabel : palette.label,
        weight: strong ? FontWeight.w600 : FontWeight.w500,
      )
          .copyWith(
        // Separation belongs to the glyphs, never an opaque plot rectangle.
        shadows: [Shadow(color: palette.background, blurRadius: 3)],
      );

  String _valueCaption() =>
      spec.countsRows ? LocaleKeys.charts_rows.tr() : spec.valueColumns.first;
}

class _ChartReadoutLayout extends SingleChildLayoutDelegate {
  const _ChartReadoutLayout({
    required this.anchor,
    required this.centered,
    required this.top,
    required this.maximum,
    required this.available,
  });

  final Offset anchor;
  final bool centered;
  final bool top;
  final Size maximum;
  final Rect available;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(maximum);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (centered || top ? available.center.dx : anchor.dx) -
        childSize.width / 2;
    final above = anchor.dy - childSize.height - 10;
    final below = anchor.dy + 10;
    final y = centered
        ? available.center.dy - childSize.height / 2
        : top
            ? available.top
            : above >= available.top
                ? above
                : below + childSize.height <= available.bottom
                    ? below
                    : available.top;
    return Offset(
      x.clamp(
        available.left,
        math.max(available.left, available.right - childSize.width),
      ),
      y.clamp(
        available.top,
        math.max(available.top, available.bottom - childSize.height),
      ),
    );
  }

  @override
  bool shouldRelayout(_ChartReadoutLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      centered != oldDelegate.centered ||
      top != oldDelegate.top ||
      available != oldDelegate.available ||
      maximum != oldDelegate.maximum;
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
            key: ValueKey(('chart-legend', circular, entry.$1)),
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
      spec.countsRows ? LocaleKeys.charts_rows.tr() : spec.valueColumns.first;
}

class _LegendChip extends StatefulWidget {
  const _LegendChip({
    super.key,
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
  bool _focused = false;

  Widget _button(ChartPalette palette, Widget child) {
    // Circular legends name slices; they have never toggled series. Do not
    // turn those labels into disabled buttons just to share their appearance.
    if (widget.onTap == null) return child;
    return TextButton(
      onPressed: widget.onTap,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) {
          widget.onEnter?.call();
        } else if (!_hovered) {
          widget.onExit?.call();
        }
      },
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: palette.strongLabel,
      ).copyWith(
        animationDuration:
            WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final quiet = widget.muted || widget.dimmed;
    final duration =
        WorkspaceTokens.motion(context, ChartMetrics.hoverDuration);
    return MouseRegion(
      cursor:
          widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onEnter?.call();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        if (!_focused) widget.onExit?.call();
      },
      child: _button(
        palette,
        Semantics(
          toggled: widget.onTap == null ? null : !widget.muted,
          child: AnimatedContainer(
            duration: duration,
            curve: ChartMetrics.hoverCurve,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: palette.chipHover.withValues(
                alpha: _hovered || _focused ? palette.chipHover.a : 0,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: ChartMetrics.hoverCurve,
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(
                      alpha: widget.color.a * (quiet ? 0.3 : 1),
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 168),
                    child: AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: ChartMetrics.hoverCurve,
                      style: palette.text(
                        size: 11.5,
                        color: widget.muted
                            ? palette.label
                                .withValues(alpha: palette.label.a * 0.5)
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
                ),
              ],
            ),
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
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final ChartPalette palette;
  final ChartViewport viewport;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  static Size sizeOf(BuildContext context) => Size(
        52 + math.max(40, MediaQuery.textScalerOf(context).scale(30)),
        math.max(24, MediaQuery.textScalerOf(context).scale(16)),
      );

  static Rect boundsFor(BuildContext context, Size plot) {
    final size = sizeOf(context);
    return Offset(plot.width - size.width, 0) & size;
  }

  @override
  Widget build(BuildContext context) => PreviewToolbar(
        keepVisible: !viewport.isIdentity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                palette.chipHover.withValues(alpha: palette.chipHover.a * 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ZoomButton(
                icon: Icons.remove_rounded,
                tooltip: LocaleKeys.canvas_zoom_zoomOut.tr(),
                palette: palette,
                enabled: !viewport.isIdentity,
                onTap: onZoomOut,
              ),
              Tooltip(
                message: LocaleKeys.canvas_zoom_reset.tr(),
                child: SizedBox(
                  width: sizeOf(context).width - 52,
                  height: sizeOf(context).height,
                  child: TextButton(
                    onPressed: viewport.isIdentity ? null : onReset,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: palette.strongLabel,
                    ),
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
              _ZoomButton(
                icon: Icons.add_rounded,
                tooltip: LocaleKeys.canvas_zoom_zoomIn.tr(),
                palette: palette,
                enabled: viewport.scale < 40,
                onTap: onZoomIn,
              ),
            ],
          ),
        ),
      );
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.tooltip,
    required this.palette,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final ChartPalette palette;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 24,
      child: IconButton(
        tooltip: tooltip,
        onPressed: enabled ? onTap : null,
        icon: WorkspaceGlyph(
          icon,
          size: 14,
          role: enabled ? null : WorkspaceGlyphRole.preserveInk,
          color: enabled
              ? palette.label
              : palette.label.withValues(alpha: palette.label.a * 0.4),
        ),
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(26, 24),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: palette.label,
          disabledForegroundColor:
              palette.label.withValues(alpha: palette.label.a * 0.4),
          hoverColor: palette.chipHover,
          focusColor: palette.chipHover,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
          ),
        ),
      ),
    );
  }
}
