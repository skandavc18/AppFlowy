import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter/services.dart';

import 'astrology_model.dart';
import 'astrology_style.dart';
import 'shadbala.dart' show ShadbalaRow;

/// Rendering geometry only: no chart calculation, clock, or service access.
///
/// Rows must contain each classical planet exactly once, in any order. The
/// comparison reads Sun through Saturn, using total / minimum * 100 for each
/// planet on one percentage axis. 100% always denotes the required minimum.
/// Missing or non-finite totals have no bar, not a fabricated zero percentage.
@immutable
class AstrologyShadbalaGraphGeometry {
  factory AstrologyShadbalaGraphGeometry({required List<ShadbalaRow> rows}) {
    if (rows.length != VedicBody.classical.length) {
      throw ArgumentError(
        'Provide one Shadbala row for each classical planet.',
      );
    }
    final byBody = <VedicBody, ShadbalaRow>{};
    for (final row in rows) {
      if (!VedicBody.classical.contains(row.body) ||
          byBody.containsKey(row.body)) {
        throw ArgumentError(
          'Shadbala rows must have seven unique classical planets.',
        );
      }
      byBody[row.body] = row;
    }
    final ordered = List<ShadbalaRow>.unmodifiable(
      VedicBody.classical.map((body) => byBody[body]!),
    );
    final totals = List<double?>.unmodifiable(
      ordered.map((row) => _finite(row.total)),
    );
    var minimum = 0.0;
    var maximum = 100.0;
    for (var index = 0; index < ordered.length; index++) {
      final value =
          _percentageOfMinimum(totals[index], ordered[index].required);
      if (value != null) {
        minimum = math.min(minimum, value);
        maximum = math.max(maximum, value);
      }
    }
    return AstrologyShadbalaGraphGeometry._(
      ordered,
      totals,
      minimum,
      maximum,
    );
  }

  const AstrologyShadbalaGraphGeometry._(
    this.rows,
    this._totals,
    this.minimum,
    this.maximum,
  );

  final List<ShadbalaRow> rows;
  final List<double?> _totals;
  final double minimum;
  final double maximum;

  /// Keep zero and the common 100% minimum ahead of other nearby tick labels.
  List<double> get ticks => {
        0.0,
        100.0,
        if (minimum < 0) minimum,
        maximum,
        if (minimum < 0) minimum / 2,
        maximum / 2,
      }.toList(growable: false);

  ShadbalaRow rowFor(VedicBody body) => rows[_index(body)];

  /// Original strength in virupas, retained for numeric/detail consumers.
  double? totalFor(VedicBody body) => _totals[_index(body)];

  double? percentageFor(VedicBody body) =>
      _percentageOfMinimum(totalFor(body), rowFor(body).required);

  double zeroY(Rect plot) => yFor(0, plot);

  /// Screen Y increases downwards. Normalize first so even very large finite
  /// positive/negative percentages cannot overflow the shared range subtraction.
  double yFor(double value, Rect plot) {
    if (!value.isFinite) throw ArgumentError.value(value, 'value');
    final magnitude = math.max(minimum.abs(), maximum.abs());
    final high = maximum / magnitude;
    final low = minimum / magnitude;
    final fraction =
        ((high - value / magnitude) / (high - low)).clamp(0.0, 1.0).toDouble();
    return plot.top + fraction * plot.height;
  }

  Rect slotRect(VedicBody body, Rect plot) {
    final width = plot.width / rows.length;
    return Rect.fromLTWH(
      plot.left + _index(body) * width,
      plot.top,
      width,
      plot.height,
    );
  }

  /// Null is unavailable; a zero-height rectangle is a genuine zero total.
  Rect? barRect(VedicBody body, Rect plot) {
    final percentage = percentageFor(body);
    if (percentage == null) return null;
    final slot = slotRect(body, plot);
    final width = math.min(44.0, slot.width * 0.72);
    final zero = zeroY(plot);
    final end = yFor(percentage, plot);
    return Rect.fromLTRB(
      slot.center.dx - width / 2,
      math.min(zero, end),
      slot.center.dx + width / 2,
      math.max(zero, end),
    );
  }

  /// Every planet's required minimum is at the same 100% coordinate.
  double requiredY(VedicBody body, Rect plot) {
    _index(body);
    return yFor(100, plot);
  }

  static int _index(VedicBody body) {
    final index = VedicBody.classical.indexOf(body);
    if (index < 0) throw ArgumentError.value(body, 'body');
    return index;
  }
}

/// A controlled, seven-planet comparison of already-computed Shadbala rows.
///
/// No height wrapper is needed inside a vertical scroll view or a Column:
/// the preferred height is 280 logical pixels, growing to at most 320 with
/// text scaling. Tighter parent constraints are respected; unbounded width
/// falls back to 360. Fonts retain the inherited weight, axes and text scaler.
///
/// Each entire column is a tap/Tab target, including unavailable and zero
/// totals. Arrows move focus, Enter/Space select, and Escape dismisses details.
/// Page Up/Down scroll clipped details without making the overlay interactive.
/// Selection belongs to the caller and can drive the component view below.
class AstrologyShadbalaGraph extends StatefulWidget {
  const AstrologyShadbalaGraph({
    super.key,
    required this.rows,
    required this.selected,
    required this.onSelected,
  });

  final List<ShadbalaRow> rows;
  final VedicBody? selected;
  final ValueChanged<VedicBody> onSelected;

  @override
  State<AstrologyShadbalaGraph> createState() => _AstrologyShadbalaGraphState();
}

class _AstrologyShadbalaGraphState extends State<AstrologyShadbalaGraph> {
  final _focusNodes = {
    for (final body in VedicBody.classical)
      body: FocusNode(debugLabel: 'Shadbala ${body.label}'),
  };
  final _anchors = {
    for (final body in VedicBody.classical) body: GlobalKey(),
  };
  late List<ShadbalaRow> _sourceRows;
  late AstrologyShadbalaGraphGeometry _geometry;
  VedicBody? _hovered;
  VedicBody? _focused;
  VedicBody? _detail;
  OverlayPortalController _portal = OverlayPortalController();
  final _detailScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _readRows();
  }

  void _readRows() {
    _sourceRows = List.of(widget.rows);
    _geometry = AstrologyShadbalaGraphGeometry(rows: _sourceRows);
  }

  @override
  void didUpdateWidget(covariant AstrologyShadbalaGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rows, widget.rows) ||
        !listEquals(_sourceRows, widget.rows)) {
      _readRows();
      _hovered = null;
      _detail = null;
      // Replacing only the portal avoids hiding an overlay during build and
      // preserves the seven interaction widgets and their keyboard focus.
      _portal = OverlayPortalController();
    }
  }

  @override
  void dispose() {
    _detailScroll.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _reveal(VedicBody body) {
    if (_detail == body && _portal.isShowing) return;
    if (_detail != body && _detailScroll.hasClients) _detailScroll.jumpTo(0);
    setState(() => _detail = body);
    _portal.show();
  }

  void _hover(VedicBody body) {
    if (_hovered != body) setState(() => _hovered = body);
    _reveal(body);
  }

  void _dismiss() {
    _portal.hide();
    if (_detail != null) setState(() => _detail = null);
  }

  void _scrollDetails(int direction) {
    if (!_portal.isShowing || !_detailScroll.hasClients) return;
    final position = _detailScroll.position;
    _detailScroll.jumpTo(
      (position.pixels + direction * position.viewportDimension * 0.85)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
  }

  void _leave(VedicBody body) {
    if (_hovered != body) return;
    setState(() => _hovered = null);
    _dismiss();
  }

  void _focusChanged(VedicBody body, bool focused) {
    if (!mounted) return;
    if (focused) {
      setState(() => _focused = body);
      _reveal(body);
    } else {
      if (_focused == body) setState(() => _focused = null);
      if (_detail == body && _hovered != body) _dismiss();
    }
  }

  void _select(VedicBody body) {
    _reveal(body);
    // A pointer tap need not take keyboard focus to be actionable. In
    // particular, moving the mouse away must not leave a focus-owned popup.
    widget.onSelected(body);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final textStyle = _inheritedStyle(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final media = MediaQuery.of(context);
    final duration = media.disableAnimations || media.accessibleNavigation
        ? Duration.zero
        : const Duration(milliseconds: 150);
    final labelStyle = textStyle.copyWith(fontSize: 11, height: 1.25);
    final axisStyle = textStyle.copyWith(fontSize: 10, height: 1.25);
    final caption = 'Strength (% of minimum) · 100% = minimum'
        '${_geometry.rows.any((row) => _geometry.percentageFor(row.body) == null) ? ' · — Unavailable' : ''}';

    Size measure(String text, TextStyle style, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: textScaler,
      )..layout(maxWidth: math.max(0.0, width));
      final size = painter.size;
      painter.dispose();
      return size;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.hasBoundedWidth ? constraints.maxWidth : 360.0;
        final preferredHeight =
            (280 + math.max(0.0, textScaler.scale(12) - 12) * 3)
                .clamp(260.0, 320.0)
                .toDouble();
        final height = constraints.constrainHeight(preferredHeight);
        if (width <= 0 || height <= 0) return const SizedBox.shrink();
        final captionHeight = measure(caption, labelStyle, width).height;
        final axisSizes = [
          for (final tick in _geometry.ticks)
            measure(_axisNumber(tick), axisStyle, double.infinity),
        ];
        final gutter = math.min(
          width * 0.45,
          axisSizes.fold(0.0, (value, size) => math.max(value, size.width)) + 6,
        );
        final tickHeight =
            axisSizes.fold(0.0, (value, size) => math.max(value, size.height));
        final slotWidth = (width - gutter) / VedicBody.classical.length;
        final labelHeight = VedicBody.classical.fold(
          0.0,
          (value, body) => math.max(
            value,
            measure(body.shortName, labelStyle, slotWidth).height,
          ),
        );
        final numberSizes = [
          for (final row in _geometry.rows)
            measure(
              _percentage(_geometry.percentageFor(row.body), unavailable: '—'),
              labelStyle,
              double.infinity,
            ),
        ];
        final showNumbers =
            numberSizes.every((size) => size.width + 4 <= slotWidth);
        final numberHeight = showNumbers
            ? numberSizes.fold(
                  0.0,
                  (value, size) => math.max(value, size.height),
                ) +
                4
            : 0.0;
        final labelBand = 12 + labelHeight + numberHeight;
        final top = math.min(height, captionHeight + tickHeight / 2 + 8);
        final plot = Rect.fromLTWH(
          gutter,
          top,
          width - gutter,
          math.max(0.0, height - labelBand - top),
        );

        return SizedBox(
          key: const ValueKey('shadbala-graph'),
          width: width,
          height: height,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Shadbala relative strength comparison',
            value: 'Shared scale ${_percentage(_geometry.minimum)} to '
                '${_percentage(_geometry.maximum)} of minimum. '
                '100% meets the minimum.',
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: TweenAnimationBuilder<AstrologyShadbalaGraphGeometry>(
                tween: _GeometryTween(_geometry),
                duration: duration,
                builder: (context, geometry, child) => Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          key: const ValueKey('shadbala-graph-grid'),
                          painter: _GridPainter(
                            geometry: geometry,
                            plot: plot,
                            palette: palette,
                            textStyle: axisStyle,
                            textScaler: textScaler,
                            textDirection: direction,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: ExcludeSemantics(
                        child: Text(
                          caption,
                          key: const ValueKey('shadbala-graph-caption'),
                          textScaler: textScaler,
                          style: labelStyle.copyWith(color: palette.muted),
                        ),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: plot,
                      child: const IgnorePointer(
                        child: SizedBox.expand(key: ValueKey('shadbala-plot')),
                      ),
                    ),
                    for (final row in _geometry.rows)
                      Positioned.fromRect(
                        rect: Rect.fromLTRB(
                          geometry.slotRect(row.body, plot).left,
                          plot.top,
                          geometry.slotRect(row.body, plot).right,
                          height,
                        ),
                        child: SizedBox(
                          key: _anchors[row.body],
                          child: _bar(
                            row: row,
                            geometry: geometry,
                            plot: plot,
                            palette: palette,
                            style: labelStyle,
                            textScaler: textScaler,
                            labelHeight: labelHeight,
                            showNumbers: showNumbers,
                            duration: duration,
                          ),
                        ),
                      ),
                    // This permanent anchor is not an interaction layer.
                    // Planet anchors already have sizes before hover/focus,
                    // so showing the portal needs no timer or frame polling.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: OverlayPortal(
                          key: ObjectKey(_portal),
                          controller: _portal,
                          overlayChildBuilder: _overlay,
                          child: const SizedBox.expand(),
                        ),
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

  Widget _bar({
    required ShadbalaRow row,
    required AstrologyShadbalaGraphGeometry geometry,
    required Rect plot,
    required AstrologyPalette palette,
    required TextStyle style,
    required TextScaler textScaler,
    required double labelHeight,
    required bool showNumbers,
    required Duration duration,
  }) {
    final body = row.body;
    final prefix = 'shadbala-bar-${body.name}';
    final selected = widget.selected == body;
    final focused = _focused == body;
    final slot = geometry.slotRect(body, plot);
    // Tween.transform(0) returns the old geometry, including its availability.
    final bar = _geometry.percentageFor(body) == null
        ? null
        : geometry.barRect(body, plot)?.shift(-slot.topLeft);
    final fill = selected ? palette.accent : palette.planetColor(body);
    return FocusTraversalOrder(
      order: NumericFocusOrder(body.index.toDouble()),
      child: FocusableActionDetector(
        key: ValueKey(prefix),
        focusNode: _focusNodes[body],
        includeFocusSemantics: false,
        onFocusChange: (value) => _focusChanged(body, value),
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.enter):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.space):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              const _MoveIntent(-1),
          const SingleActivator(LogicalKeyboardKey.arrowUp):
              const _MoveIntent(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              const _MoveIntent(1),
          const SingleActivator(LogicalKeyboardKey.arrowDown):
              const _MoveIntent(1),
          if (_detail != null)
            const SingleActivator(LogicalKeyboardKey.escape):
                const DismissIntent(),
          if (_detail != null)
            const SingleActivator(LogicalKeyboardKey.pageUp):
                const _DetailsScrollIntent(-1),
          if (_detail != null)
            const SingleActivator(LogicalKeyboardKey.pageDown):
                const _DetailsScrollIntent(1),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _select(body);
              return null;
            },
          ),
          _MoveIntent: CallbackAction<_MoveIntent>(
            onInvoke: (intent) {
              final next =
                  (body.index + intent.delta) % VedicBody.classical.length;
              _focusNodes[VedicBody.classical[next]]!.requestFocus();
              return null;
            },
          ),
          _DetailsScrollIntent: CallbackAction<_DetailsScrollIntent>(
            onInvoke: (intent) {
              _scrollDetails(intent.direction);
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _dismiss();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _hover(body),
          onHover: (_) => _hover(body),
          onExit: (_) => _leave(body),
          child: Semantics(
            key: ValueKey('$prefix-semantics'),
            container: true,
            sortKey: OrdinalSortKey(body.index.toDouble()),
            button: true,
            enabled: true,
            selected: selected,
            focusable: true,
            focused: focused,
            label: '${body.label} relative Shadbala',
            value: _description(row),
            hint: 'Select ${body.label} for the component breakdown below. '
                'Tab or arrows move focus; Enter or Space selects. '
                'Page Up/Down scroll details; Escape closes them.',
            onTap: () => _select(body),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: () => _select(body),
              child: ExcludeSemantics(
                child: AnimatedContainer(
                  key: ValueKey('$prefix-highlight'),
                  duration: duration,
                  decoration: BoxDecoration(
                    color: selected
                        ? palette.selection
                        : _hovered == body
                            ? palette.hover
                            : palette.surface.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: focused
                          ? palette.accent
                          : palette.accent.withValues(alpha: 0),
                    ),
                  ),
                  // Decorations must not inset the data: all columns use
                  // exactly the same plot origin and zero baseline.
                  padding: EdgeInsets.zero,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: plot.height,
                        child: Stack(
                          key: ValueKey('$prefix-plot'),
                          children: [
                            if (bar != null)
                              Positioned.fromRect(
                                rect: bar,
                                child: TweenAnimationBuilder<Color?>(
                                  tween: ColorTween(begin: fill, end: fill),
                                  duration: duration,
                                  builder: (context, color, child) =>
                                      DecoratedBox(
                                    key: ValueKey('$prefix-fill'),
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(
                                          geometry.totalFor(body)! >= 0 ? 4 : 0,
                                        ),
                                        bottom: Radius.circular(
                                          geometry.totalFor(body)! < 0 ? 4 : 0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else
                              Center(
                                child: Text(
                                  '—',
                                  key: ValueKey('$prefix-unavailable'),
                                  textScaler: textScaler,
                                  style: style.copyWith(color: palette.muted),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: plot.height + 8,
                        child: Text(
                          body.shortName,
                          key: ValueKey('$prefix-label'),
                          textAlign: TextAlign.center,
                          textScaler: textScaler,
                          style: style.copyWith(color: fill),
                        ),
                      ),
                      if (showNumbers)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: plot.height + 12 + labelHeight,
                          child: Text(
                            _percentage(
                              _geometry.percentageFor(body),
                              unavailable: '—',
                            ),
                            key: ValueKey('$prefix-value'),
                            textAlign: TextAlign.center,
                            textScaler: textScaler,
                            style: style.copyWith(color: palette.muted),
                          ),
                        ),
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

  Widget _overlay(BuildContext context) {
    final body = _detail;
    final anchor = _anchors[body]?.currentContext?.findRenderObject();
    if (body == null || anchor is! RenderBox || !anchor.hasSize) {
      return const SizedBox.shrink();
    }
    final overlay = Overlay.of(context).context.findRenderObject();
    final target = anchor.localToGlobal(
      anchor.size.center(Offset.zero),
      ancestor: overlay,
    );
    // As in VedicChartView, ignore pointers IN the overlay. Material Tooltip
    // adds an overlay MouseRegion that can otherwise steal another bar's tap.
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          // Every detail is already available on the focusable bar's semantics.
          child: CustomSingleChildLayout(
            delegate: _HoverLayout(target),
            child: _Details(
              row: _geometry.rowFor(body),
              controller: _detailScroll,
            ),
          ),
        ),
      ),
    );
  }
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);

  final int delta;
}

class _DetailsScrollIntent extends Intent {
  const _DetailsScrollIntent(this.direction);

  final int direction;
}

/// Interpolate the shared domain AND all endpoints together. A transition
/// cannot give planets different baselines; an unavailable target disappears
/// immediately rather than animating towards a fabricated zero reading.
class _GeometryTween extends Tween<AstrologyShadbalaGraphGeometry> {
  _GeometryTween(AstrologyShadbalaGraphGeometry target)
      : super(begin: target, end: target);

  @override
  AstrologyShadbalaGraphGeometry lerp(double t) {
    final from = begin!;
    final to = end!;
    if (identical(from, to) || t == 1) return to;
    return AstrologyShadbalaGraphGeometry._(
      to.rows,
      List.generate(to.rows.length, (index) {
        final total = to._totals[index];
        return total == null
            ? null
            : ui.lerpDouble(from._totals[index] ?? 0, total, t);
      }),
      ui.lerpDouble(from.minimum, to.minimum, t)!,
      ui.lerpDouble(from.maximum, to.maximum, t)!,
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.geometry,
    required this.plot,
    required this.palette,
    required this.textStyle,
    required this.textScaler,
    required this.textDirection,
  });

  final AstrologyShadbalaGraphGeometry geometry;
  final Rect plot;
  final AstrologyPalette palette;
  final TextStyle textStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (plot.isEmpty) return;
    final labels = <Rect>[];
    for (final tick in geometry.ticks) {
      final y = geometry.yFor(tick, plot);
      final label = TextPainter(
        text: TextSpan(
          text: _axisNumber(tick),
          style: textStyle.copyWith(color: palette.muted),
        ),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0.0, plot.left - 6));
      final bounds = Rect.fromLTWH(
        plot.left - label.width - 6,
        y - label.height / 2,
        label.width,
        label.height,
      );
      if (!labels.any((other) => other.inflate(3).overlaps(bounds))) {
        labels.add(bounds);
        canvas.drawLine(
          Offset(plot.left, y),
          Offset(plot.right, y),
          Paint()
            ..color = tick == 0
                ? palette.muted.withValues(alpha: 0.65)
                : palette.line.withValues(alpha: 0.45)
            ..strokeWidth = tick == 0 ? 1 : 0.5,
        );
        label.paint(canvas, bounds.topLeft);
      }
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => true;
}

class _HoverLayout extends SingleChildLayoutDelegate {
  const _HoverLayout(this.target);

  final Offset target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.max(0.0, math.min(344.0, constraints.maxWidth - 24));
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(0.0, math.min(520.0, constraints.maxHeight - 24)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final above = target.dy - childSize.height - 12;
    final maxX = math.max(0.0, size.width - childSize.width - 12);
    final maxY = math.max(0.0, size.height - childSize.height - 12);
    return Offset(
      (target.dx - childSize.width / 2).clamp(math.min(12.0, maxX), maxX),
      (above >= 12 ? above : target.dy + 12).clamp(math.min(12.0, maxY), maxY),
    );
  }

  @override
  bool shouldRelayout(covariant _HoverLayout oldDelegate) =>
      target != oldDelegate.target;
}

class _Details extends StatelessWidget {
  const _Details({required this.row, required this.controller});

  final ShadbalaRow row;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final style = _inheritedStyle(context).copyWith(
      fontSize: 12,
      height: 1.4,
      color: palette.ink,
    );
    final prefix = 'shadbala-hover-${row.body.name}';
    final unavailable = _unavailableReason(row);
    return DecoratedBox(
      key: ValueKey(prefix),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.line),
        boxShadow: [
          BoxShadow(
            color: palette.ink.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: controller,
          primary: false,
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${row.body.label} · Shadbala',
                key: ValueKey('$prefix-title'),
                style: style.copyWith(fontSize: 14, color: palette.accent),
              ),
              const SizedBox(height: 4),
              Text(
                'Six strengths · virupas',
                style: style.copyWith(color: palette.muted),
              ),
              Text(
                'Page Up/Down · scroll details',
                style: style.copyWith(color: palette.muted),
              ),
              const SizedBox(height: 8),
              for (final entry in _metrics(row).entries) ...[
                if (entry.key == 'total')
                  Divider(color: palette.line, height: 16),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    Text(
                      entry.value.$1,
                      style: style.copyWith(color: palette.muted),
                    ),
                    Text(
                      _metricNumber(entry.key, entry.value.$2),
                      key: ValueKey('$prefix-${entry.key}-value'),
                      style: style,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Motion: ${row.motion}',
                key: ValueKey('$prefix-motion-value'),
                style: style,
              ),
              if (unavailable.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  unavailable,
                  key: ValueKey('$prefix-unavailable-note'),
                  style: style.copyWith(color: palette.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _inheritedStyle(BuildContext context) {
  final base = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
      .merge(DefaultTextStyle.of(context).style);
  return base.copyWith(
    fontFeatures: [
      ...?base.fontFeatures,
      const ui.FontFeature.tabularFigures(),
    ],
  );
}

double? _finite(double? value) =>
    value != null && value.isFinite ? value : null;

double? _percentageOfMinimum(double? total, double required) {
  if (_finite(total) == null || !required.isFinite || required <= 0) {
    return null;
  }
  // Divide before multiplying so a large finite total does not overflow.
  return _finite(total! / required * 100);
}

String _percentage(double? value, {String unavailable = 'Unavailable'}) {
  final finite = _finite(value);
  if (finite == null) return unavailable;
  final text = finite.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}%';
}

String _number(double? value, {int digits = 2}) =>
    _finite(value)?.toStringAsFixed(digits) ?? 'Unavailable';

String _metricNumber(String key, double? value) => key == 'percentage'
    ? _percentage(value)
    : _number(value, digits: key == 'ratio' ? 3 : 2);

String _axisNumber(double value) =>
    '${value.abs() >= 10000 ? value.toStringAsExponential(1) : value.toStringAsFixed(value != 0 && value.abs() < 1 ? 1 : 0)}%';

Map<String, (String, double?)> _metrics(ShadbalaRow row) => {
      'percentage': (
        'Strength (% of minimum)',
        _percentageOfMinimum(row.total, row.required),
      ),
      'sthana': ('Sthana', row.sthana),
      'dig': ('Dig', row.dig),
      'kala': ('Kala', row.kala),
      'cheshta': ('Cheshta', row.cheshta),
      'naisargika': ('Naisargika', row.naisargika),
      'drik': ('Drik', row.drik),
      'total': ('Total (virupas)', row.total),
      'rupas': ('Total (rupas)', row.rupas),
      'required': ('Required (virupas)', row.required),
      'ratio': ('Ratio', row.ratio),
    };

String _description(ShadbalaRow row) => [
      for (final entry in _metrics(row).entries)
        '${entry.value.$1}: '
            '${_metricNumber(entry.key, entry.value.$2)}',
      'Motion: ${row.motion}',
      if (_unavailableReason(row).isNotEmpty) _unavailableReason(row),
    ].join('; ');

String _unavailableReason(ShadbalaRow row) {
  if (_finite(row.total) != null) return '';
  return '${row.kala == null ? 'Kala is Unavailable: sunrise/sunset could not bracket this instant (polar day/night or missing solar events).' : 'A non-finite component makes the full strength Unavailable.'} '
      'Total, rupas, ratio and percentage are Unavailable; missing or non-finite '
      'components are not zero estimates.';
}
