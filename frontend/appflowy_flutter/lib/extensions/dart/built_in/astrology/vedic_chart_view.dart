import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'astrology_model.dart';
import 'astrology_style.dart';

/// One convex polygon in a normalized, top-left-origin unit square.
/// Signs are zero-based; houses are one-based. Label bounds are *not* hitboxes.
@immutable
class VedicChartCell {
  const VedicChartCell._({
    required this.sign,
    required this.house,
    required this.vertices,
    required this.labelBounds,
  });

  final int sign;
  final int house;
  final List<Offset> vertices;
  final Rect labelBounds;

  Offset get center =>
      vertices.fold(Offset.zero, (a, b) => a + b) / vertices.length.toDouble();

  /// Analytic convex-polygon containment; no ephemeris or engine is involved.
  /// Shared edges are inclusive; the geometry resolves ties in cell order.
  bool contains(Offset point) {
    if (!point.dx.isFinite || !point.dy.isFinite) return false;
    var positive = false;
    var negative = false;
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      final cross =
          (b.dx - a.dx) * (point.dy - a.dy) - (b.dy - a.dy) * (point.dx - a.dx);
      positive = positive || cross > 1e-10;
      negative = negative || cross < -1e-10;
      if (positive && negative) return false;
    }
    return true;
  }

  ui.Path pathIn(Rect bounds) {
    final path = ui.Path();
    for (var i = 0; i < vertices.length; i++) {
      final point = pointIn(vertices[i], bounds);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  Rect labelRectIn(Rect bounds) => Rect.fromLTWH(
        bounds.left + labelBounds.left * bounds.width,
        bounds.top + labelBounds.top * bounds.height,
        labelBounds.width * bounds.width,
        labelBounds.height * bounds.height,
      );

  static Offset pointIn(Offset point, Rect bounds) => Offset(
        bounds.left + point.dx * bounds.width,
        bounds.top + point.dy * bounds.height,
      );
}

/// The single geometry source for painting, pointer hits, and accessibility.
/// North: fixed houses counterclockwise from the top-center ascendant diamond.
/// South: fixed signs clockwise, with Pisces in the top-left corner.
@immutable
class VedicChartGeometry {
  factory VedicChartGeometry({
    required IndianChartStyle style,
    required int ascendantSign,
  }) {
    if (ascendantSign < 0 || ascendantSign >= 12) {
      throw RangeError.range(ascendantSign, 0, 11, 'ascendantSign');
    }
    final cells = <VedicChartCell>[];
    for (var index = 0; index < 12; index++) {
      if (style == IndianChartStyle.north) {
        cells.add(
          VedicChartCell._(
            sign: (ascendantSign + index) % 12,
            house: index + 1,
            vertices: _northVertices[index],
            labelBounds: _northLabels[index],
          ),
        );
      } else {
        final origin = _southOrigins[index] / 4;
        final rect = Rect.fromLTWH(origin.dx, origin.dy, 0.25, 0.25);
        cells.add(
          VedicChartCell._(
            sign: index,
            house: (index - ascendantSign + 12) % 12 + 1,
            vertices: List.unmodifiable([
              rect.topLeft,
              rect.topRight,
              rect.bottomRight,
              rect.bottomLeft,
            ]),
            labelBounds: rect.deflate(0.022),
          ),
        );
      }
    }
    return VedicChartGeometry._(
      style,
      ascendantSign,
      List.unmodifiable(cells),
    );
  }

  const VedicChartGeometry._(this.style, this.ascendantSign, this.cells);

  final IndianChartStyle style;
  final int ascendantSign;
  final List<VedicChartCell> cells;

  VedicChartCell cellForSign(int sign) =>
      cells.firstWhere((cell) => cell.sign == sign);

  VedicChartCell? hitTest(Offset normalizedPoint) {
    if (!normalizedPoint.dx.isFinite ||
        !normalizedPoint.dy.isFinite ||
        normalizedPoint.dx < 0 ||
        normalizedPoint.dy < 0 ||
        normalizedPoint.dx > 1 ||
        normalizedPoint.dy > 1) {
      return null;
    }
    for (final cell in cells) {
      if (cell.contains(normalizedPoint)) return cell;
    }
    return null;
  }

  /// A little breathing room around the traditional square, never stretched.
  static Rect chartBounds(Size size) {
    final side = math.min(size.width, size.height);
    final inset = math.min(10.0, side * 0.03);
    return Rect.fromLTWH(
      (size.width - side) / 2 + inset,
      (size.height - side) / 2 + inset,
      math.max(0.0, side - inset * 2),
      math.max(0.0, side - inset * 2),
    );
  }

  static const _northVertices = <List<Offset>>[
    [Offset(0.5, 0), Offset(0.25, 0.25), Offset(0.5, 0.5), Offset(0.75, 0.25)],
    [Offset(0, 0), Offset(0.25, 0.25), Offset(0.5, 0)],
    [Offset(0, 0), Offset(0, 0.5), Offset(0.25, 0.25)],
    [Offset(0, 0.5), Offset(0.25, 0.75), Offset(0.5, 0.5), Offset(0.25, 0.25)],
    [Offset(0, 0.5), Offset(0, 1), Offset(0.25, 0.75)],
    [Offset(0, 1), Offset(0.5, 1), Offset(0.25, 0.75)],
    [Offset(0.5, 1), Offset(0.75, 0.75), Offset(0.5, 0.5), Offset(0.25, 0.75)],
    [Offset(0.5, 1), Offset(1, 1), Offset(0.75, 0.75)],
    [Offset(1, 1), Offset(1, 0.5), Offset(0.75, 0.75)],
    [Offset(1, 0.5), Offset(0.75, 0.25), Offset(0.5, 0.5), Offset(0.75, 0.75)],
    [Offset(1, 0.5), Offset(1, 0), Offset(0.75, 0.25)],
    [Offset(1, 0), Offset(0.5, 0), Offset(0.75, 0.25)],
  ];

  // Every corner of each label rectangle is strictly inside its polygon.
  // The narrow side triangles deliberately get tall, narrow wrapping areas.
  static const _northLabels = <Rect>[
    Rect.fromLTRB(0.385, 0.135, 0.615, 0.355),
    Rect.fromLTRB(0.135, 0.015, 0.365, 0.130),
    Rect.fromLTRB(0.015, 0.135, 0.130, 0.365),
    Rect.fromLTRB(0.135, 0.385, 0.355, 0.615),
    Rect.fromLTRB(0.015, 0.635, 0.130, 0.865),
    Rect.fromLTRB(0.135, 0.870, 0.365, 0.985),
    Rect.fromLTRB(0.385, 0.645, 0.615, 0.865),
    Rect.fromLTRB(0.635, 0.870, 0.865, 0.985),
    Rect.fromLTRB(0.870, 0.635, 0.985, 0.865),
    Rect.fromLTRB(0.645, 0.385, 0.865, 0.615),
    Rect.fromLTRB(0.870, 0.135, 0.985, 0.365),
    Rect.fromLTRB(0.635, 0.015, 0.865, 0.130),
  ];

  // Indexed by zodiac sign, not by house or row-major grid position.
  static const _southOrigins = <Offset>[
    Offset(1, 0),
    Offset(2, 0),
    Offset(3, 0),
    Offset(3, 1),
    Offset(3, 2),
    Offset(3, 3),
    Offset(2, 3),
    Offset(1, 3),
    Offset(0, 3),
    Offset(0, 2),
    Offset(0, 1),
    Offset(0, 0),
  ];
}

/// Parenthesized retrograde labels stay legible in the chosen chart font.
/// The painter lays out this entire marker as one wrapping token.
String vedicPlanetMarker(VedicPlacement placement) {
  final label = placement.body?.shortName ?? placement.shortName;
  return placement.retrograde ? '($label)' : label;
}

/// Measured center typography, independent of the twelve house polygons.
///
/// Honor the inherited font and text scaler first, then fit the complete text
/// only when the crossing/free center cannot accommodate it. No ellipsis or
/// clipping is used. Call [dispose] after painting or inspecting the layout.
class VedicChartCenterLayout {
  factory VedicChartCenterLayout({
    required Rect bounds,
    required IndianChartStyle style,
    required int division,
    required int ascendantSign,
    required AstrologyPalette palette,
    required TextStyle textStyle,
    required TextScaler textScaler,
    required ui.TextDirection textDirection,
    String centerLabel = '',
  }) {
    final south = style == IndianChartStyle.south;
    final suppliedLabel = centerLabel.trim();
    // Panels supply D-N already. Show one compact division title in either
    // style, without treating custom SAV/BAV labels as division aliases.
    final label =
        suppliedLabel == 'D-$division' || suppliedLabel == 'D$division'
            ? ''
            : suppliedLabel;
    final title = south || label.isEmpty
        ? 'D$division'
        : label.split(RegExp(r'\s+')).join('\n');
    final text = TextPainter(
      text: TextSpan(
        text: title,
        style: textStyle.copyWith(
          fontSize: south ? 22 : 12,
          height: 1.2,
          color: palette.accent,
        ),
        children: [
          if (south)
            TextSpan(
              text: '${label.isEmpty ? '' : '\n$label'}'
                  '\n${zodiacNames[ascendantSign]} rising',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: palette.muted,
              ),
            ),
        ],
      ),
      textDirection: textDirection,
      textScaler: textScaler,
      textAlign: TextAlign.center,
    )..layout();
    // North's nearest house label starts 0.145 sides from the crossing.
    // Keep the circle (including its fine outline) clear of those labels.
    final available =
        math.max(0.0, bounds.shortestSide * (south ? 0.40 : 0.28));
    if (south) {
      // Wrap at word boundaries, never within D10 or a custom label's word.
      text.layout(maxWidth: math.max(available, text.minIntrinsicWidth));
    }
    // Font ascent and bidi tracking can extend word boxes beyond text.size.
    // Fit those extents too, excluding selection-only newline/trailing spaces.
    var measured = Offset.zero & text.size;
    for (final word in RegExp(r'\S+').allMatches(text.plainText)) {
      for (final box in text.getBoxesForSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end),
      )) {
        measured = measured.expandToInclude(box.toRect());
      }
    }
    final diagonal = math.sqrt(
      measured.width * measured.width + measured.height * measured.height,
    );
    final padding = math.min(8.0, available);
    final scale = south
        ? math.min(
            1.0,
            math.min(available / measured.width, available / measured.height),
          )
        : math.min(1.0, (available - padding) / diagonal);
    final textBounds = Rect.fromCenter(
      center: bounds.center,
      width: measured.width * scale,
      height: measured.height * scale,
    );
    return VedicChartCenterLayout._(
      text: text,
      scale: scale,
      textBounds: textBounds,
      paintOffset: textBounds.topLeft - measured.topLeft * scale,
      medallionBounds: south
          ? null
          : Rect.fromCircle(
              center: bounds.center,
              radius: (diagonal * scale + padding) / 2,
            ),
      palette: palette,
      semanticsLabel: '${label.isEmpty ? '' : '$label · '}D-$division'
          '${south ? ' · ${zodiacNames[ascendantSign]} rising' : ''}',
    );
  }

  VedicChartCenterLayout._({
    required this.text,
    required this.scale,
    required this.textBounds,
    required this.paintOffset,
    required this.medallionBounds,
    required AstrologyPalette palette,
    required this.semanticsLabel,
  }) : _palette = palette;

  final TextPainter text;
  final double scale;

  /// Fitted paragraph and word bounds, including font-metric overhangs.
  final Rect textBounds;

  /// Canvas origin for [text], compensating for its measured local overhangs.
  final Offset paintOffset;

  final Rect? medallionBounds;
  final String semanticsLabel;
  final AstrologyPalette _palette;

  void paint(Canvas canvas) {
    final medallion = medallionBounds;
    if (medallion != null) {
      canvas.drawCircle(
        medallion.center,
        medallion.width / 2,
        Paint()..color = _palette.surface,
      );
      canvas.drawCircle(
        medallion.center,
        medallion.width / 2,
        Paint()
          ..color = _palette.line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
    canvas.save();
    canvas.translate(paintOffset.dx, paintOffset.dy);
    canvas.scale(scale);
    text.paint(canvas, Offset.zero);
    canvas.restore();
  }

  void dispose() => text.dispose();
}

/// Native interactive North/South Indian varga chart.
///
/// [onSignSelected] receives a zero-based zodiac sign, including in bindus
/// mode. [bindus], when present, must contain exactly twelve sign-indexed
/// values. Degrees and nakshatra/pada in details retain their original
/// sidereal longitude; only sign allocation is changed by [division].
class VedicChartView extends StatefulWidget {
  const VedicChartView({
    super.key,
    required this.placements,
    required this.ascendant,
    this.style = IndianChartStyle.north,
    this.division = 1,
    this.bindus,
    this.centerLabel = '',
    this.onSignSelected,
  });

  final List<VedicPlacement> placements;
  final double ascendant;
  final IndianChartStyle style;
  final int division;
  final List<int>? bindus;
  final String centerLabel;
  final ValueChanged<int>? onSignSelected;

  @override
  State<VedicChartView> createState() => _VedicChartViewState();
}

class _VedicChartViewState extends State<VedicChartView> {
  int? _hoveredSign;
  int? _selectedSign;
  Timer? _hoverTimer;
  OverlayPortalController _hoverPortal = OverlayPortalController();
  GlobalKey _hoverAnchorKey = GlobalKey();

  @override
  void didUpdateWidget(covariant VedicChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.division != widget.division) {
      _selectedSign = null;
    }
    if (oldWidget.division != widget.division ||
        oldWidget.style != widget.style ||
        oldWidget.ascendant != widget.ascendant ||
        oldWidget.placements != widget.placements ||
        oldWidget.bindus != widget.bindus ||
        oldWidget.centerLabel != widget.centerLabel) {
      _hoverTimer?.cancel();
      _hoveredSign = null;
      _hoverPortal = OverlayPortalController();
      _hoverAnchorKey = GlobalKey();
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    super.dispose();
  }

  List<List<VedicPlacement>> _groupPlacements() {
    final groups = List.generate(12, (_) => <VedicPlacement>[]);
    final ascendantSign = divisionalSign(widget.ascendant, widget.division);
    groups[ascendantSign].add(
      VedicPlacement(
        name: 'Ascendant (Lagna)',
        shortName: 'As',
        longitude: widget.ascendant,
      ),
    );
    for (final placement in widget.placements) {
      // AstrologyChart.placements already includes Lagna. Do not show it twice.
      final isSuppliedLagna = placement.body == null &&
          (placement.shortName.toLowerCase() == 'as' ||
              placement.name.toLowerCase() == 'lagna' ||
              placement.name.toLowerCase() == 'ascendant') &&
          angularDistance(placement.longitude, widget.ascendant).abs() < 1e-8;
      if (isSuppliedLagna) continue;
      groups[divisionalSign(placement.longitude, widget.division)]
          .add(placement);
    }
    return groups;
  }

  void _hover(int? sign) {
    if (_hoveredSign == sign) return;
    _hoverTimer?.cancel();
    setState(() {
      _hoveredSign = sign;
      _hoverPortal = OverlayPortalController();
      _hoverAnchorKey = GlobalKey();
    });
    if (sign != null) {
      _hoverTimer = Timer(const Duration(milliseconds: 400), () {
        if (mounted && _hoveredSign == sign) {
          _hoverPortal.show();
        }
      });
    }
  }

  void _selectSign(int sign) {
    _hoverTimer?.cancel();
    final geometry = VedicChartGeometry(
      style: widget.style,
      ascendantSign: divisionalSign(widget.ascendant, widget.division),
    );
    final entries = _groupPlacements()[sign];
    final palette = AstrologyPalette.of(context);
    final textStyle = _inheritedTextStyle(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final cell = geometry.cellForSign(sign);
    final division = widget.division;
    final points = widget.bindus?[sign];
    final centerLabel = widget.centerLabel;
    setState(() {
      _selectedSign = sign;
      _hoveredSign = null;
    });
    widget.onSignSelected?.call(sign);
    if (!mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Directionality(
            textDirection: textDirection,
            child: _SignDetailsDialog(
              cell: cell,
              entries: entries,
              division: division,
              points: points,
              centerLabel: centerLabel,
              palette: palette,
              textStyle: textStyle,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bindus != null && widget.bindus!.length != 12) {
      throw ArgumentError.value(
        widget.bindus,
        'bindus',
        'Provide exactly twelve values, indexed Aries through Pisces.',
      );
    }
    final geometry = VedicChartGeometry(
      style: widget.style,
      ascendantSign: divisionalSign(widget.ascendant, widget.division),
    );
    final groups = _groupPlacements();
    final palette = AstrologyPalette.of(context);
    final textStyle = _inheritedTextStyle(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        var side = math.min(constraints.maxWidth, constraints.maxHeight);
        if (!side.isFinite) side = 360;
        if (side <= 0) return const SizedBox.shrink();
        final bounds = VedicChartGeometry.chartBounds(Size.square(side));
        int? signAt(Offset local) => geometry
            .hitTest(
              Offset(
                (local.dx - bounds.left) / bounds.width,
                (local.dy - bounds.top) / bounds.height,
              ),
            )
            ?.sign;
        void selectAt(Offset local) {
          final sign = signAt(local);
          if (sign != null) _selectSign(sign);
        }

        final hovered = _hoveredSign;
        return Align(
          alignment: Alignment.topCenter,
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox.square(
            dimension: side,
            child: Stack(
              children: [
                MouseRegion(
                  opaque: false,
                  hitTestBehavior: HitTestBehavior.deferToChild,
                  cursor: hovered == null
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.click,
                  onEnter: (event) => _hover(signAt(event.localPosition)),
                  onHover: (event) => _hover(signAt(event.localPosition)),
                  onExit: (_) => _hover(null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.deferToChild,
                    excludeFromSemantics: true,
                    onTapUp: (event) => selectAt(event.localPosition),
                    onLongPressStart: (event) => selectAt(event.localPosition),
                    child: CustomPaint(
                      key: const ValueKey('vedic-chart-canvas'),
                      size: Size.square(side),
                      painter: _VedicChartPainter(
                        geometry: geometry,
                        side: side,
                        groups: groups,
                        palette: palette,
                        textStyle: textStyle,
                        textScaler: textScaler,
                        textDirection: textDirection,
                        division: widget.division,
                        bindus: widget.bindus,
                        centerLabel: widget.centerLabel,
                        hoveredSign: hovered,
                        selectedSign: _selectedSign,
                        onSelect: _selectSign,
                      ),
                    ),
                  ),
                ),
                if (hovered != null)
                  Positioned.fromRect(
                    rect: geometry.cellForSign(hovered).labelRectIn(bounds),
                    // Only the painter participates in pointer hit testing.
                    // This anchor must never mask another triangular house.
                    child: IgnorePointer(
                      child: OverlayPortal(
                        key: ValueKey('vedic-hover-$hovered'),
                        controller: _hoverPortal,
                        overlayChildBuilder: (context) => _hoverOverlay(
                          context,
                          palette,
                          textStyle,
                          textScaler,
                          _signListing(
                            geometry.cellForSign(hovered),
                            groups[hovered],
                            widget.division,
                            widget.bindus?[hovered],
                            centerLabel: widget.centerLabel,
                            compact: true,
                          ),
                        ),
                        child: SizedBox.expand(key: _hoverAnchorKey),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hoverOverlay(
    BuildContext context,
    AstrologyPalette palette,
    TextStyle textStyle,
    TextScaler textScaler,
    String listing,
  ) {
    final anchor = _hoverAnchorKey.currentContext?.findRenderObject();
    if (anchor is! RenderBox || !anchor.hasSize) {
      return const SizedBox.shrink();
    }
    final overlay = Overlay.of(context).context.findRenderObject();
    final target = anchor.localToGlobal(
      anchor.size.center(Offset.zero),
      ancestor: overlay,
    );
    // Flutter 3.27's Material Tooltip adds a hit-testable overlay mouse region.
    // Ignore pointers *in the overlay*, not just at its chart anchor. Keeping
    // this a normal Text also avoids WidgetSpan's second text-scale transform.
    return Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: CustomSingleChildLayout(
            delegate: _ChartHoverLayout(target),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 120),
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: DecoratedBox(
                key: const ValueKey('vedic-chart-hover-card'),
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
                child: _ChartDetailsScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    listing,
                    key: const ValueKey('vedic-chart-hover-details'),
                    textScaler: textScaler,
                    style: textStyle.copyWith(
                      color: palette.ink,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartDetailsScrollView extends StatelessWidget {
  const _ChartDetailsScrollView({
    required this.padding,
    required this.child,
    this.scrollKey,
  });

  final EdgeInsets padding;
  final Widget child;
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          key: scrollKey,
          padding: padding,
          child: child,
        ),
      );
}

class _ChartHoverLayout extends SingleChildLayoutDelegate {
  const _ChartHoverLayout(this.target);

  final Offset target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(0.0, math.min(344.0, constraints.maxWidth - 24)),
        maxHeight: math.max(0.0, math.min(440.0, constraints.maxHeight - 24)),
      );

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
  bool shouldRelayout(covariant _ChartHoverLayout oldDelegate) =>
      target != oldDelegate.target;
}

TextStyle _inheritedTextStyle(BuildContext context) =>
    (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).merge(
      DefaultTextStyle.of(context).style,
    );

String _bodyName(VedicPlacement placement) =>
    placement.body?.label ?? placement.name;

String _signTitle(VedicChartCell cell) =>
    '${zodiacNames[cell.sign]} · House ${cell.house}';

String _signListing(
  VedicChartCell cell,
  List<VedicPlacement> entries,
  int division,
  int? points, {
  String centerLabel = '',
  bool compact = false,
}) =>
    [
      if (centerLabel.isNotEmpty) centerLabel,
      '${_signTitle(cell)} · D-$division',
      if (points != null) '$points bindus',
      'Tap for full details',
      if (entries.isEmpty) 'No placements in this sign.',
      for (final entry in entries)
        '${_bodyName(entry)}${entry.retrograde ? ' (retrograde)' : ''}'
            '${compact ? ' · ' : '\n'}${entry.formatted}'
            '${compact ? '' : ' · ${entry.nakshatra}, Pada ${entry.pada}'}',
      if (division != 1) 'Degrees / nakshatra use the original D-1 longitude.',
    ].join('\n');

class _VedicChartPainter extends CustomPainter {
  _VedicChartPainter({
    required this.geometry,
    required this.side,
    required this.groups,
    required this.palette,
    required this.textStyle,
    required this.textScaler,
    required this.textDirection,
    required this.division,
    required this.bindus,
    required this.centerLabel,
    required this.hoveredSign,
    required this.selectedSign,
    required this.onSelect,
  });

  final VedicChartGeometry geometry;
  final double side;
  final List<List<VedicPlacement>> groups;
  final AstrologyPalette palette;
  final TextStyle textStyle;
  final TextScaler textScaler;
  final ui.TextDirection textDirection;
  final int division;
  final List<int>? bindus;
  final String centerLabel;
  final int? hoveredSign;
  final int? selectedSign;
  final ValueChanged<int> onSelect;

  @override
  bool hitTest(Offset position) {
    final bounds = VedicChartGeometry.chartBounds(Size.square(side));
    if (bounds.isEmpty) return false;
    return geometry.hitTest(
          Offset(
            (position.dx - bounds.left) / bounds.width,
            (position.dy - bounds.top) / bounds.height,
          ),
        ) !=
        null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = VedicChartGeometry.chartBounds(size);
    if (bounds.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)),
      Paint()..color = palette.surface,
    );

    for (final cell in geometry.cells) {
      final color = cell.sign == selectedSign
          ? palette.selection
          : cell.sign == hoveredSign
              ? palette.hover
              : cell.sign == geometry.ascendantSign
                  ? Color.alphaBlend(
                      palette.accent.withValues(alpha: 0.055),
                      palette.surface,
                    )
                  : palette.surface;
      canvas.drawPath(cell.pathIn(bounds), Paint()..color = color);
    }

    // Paint each shared edge once: no double-dark diagonals or overdraw seams.
    final edges = <(Offset, Offset)>{};
    final grid = ui.Path();
    for (final cell in geometry.cells) {
      for (var i = 0; i < cell.vertices.length; i++) {
        final a = cell.vertices[i];
        final b = cell.vertices[(i + 1) % cell.vertices.length];
        final forward = a.dx < b.dx || (a.dx == b.dx && a.dy < b.dy);
        if (!edges.add(forward ? (a, b) : (b, a))) continue;
        final start = VedicChartCell.pointIn(a, bounds);
        final end = VedicChartCell.pointIn(b, bounds);
        grid
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
      }
    }
    canvas.drawPath(
      grid,
      Paint()
        ..color = palette.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
    for (final sign in {hoveredSign, selectedSign}.whereType<int>()) {
      canvas.drawPath(
        geometry.cellForSign(sign).pathIn(bounds),
        Paint()
          ..color = palette.accent.withValues(
            alpha: sign == selectedSign ? 0.9 : 0.45,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = sign == selectedSign ? 1.6 : 1.1
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (final cell in geometry.cells) {
      _paintCell(canvas, cell, bounds);
    }
    _paintCenter(canvas, bounds);
  }

  TextPainter _text(
    String value,
    TextStyle style,
    double width, {
    int maxLines = 1,
  }) =>
      TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        textAlign: TextAlign.center,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0.0, width));

  void _paintCell(Canvas canvas, VedicChartCell cell, Rect bounds) {
    final rect = cell.labelRectIn(bounds);
    final fontSize = (side / 28).clamp(10.5, 12.5);
    final ascendant = cell.sign == geometry.ascendantSign;
    final labelStyle = textStyle.copyWith(
      fontSize: fontSize - 0.5,
      height: 1.15,
      color: ascendant ? palette.accent : palette.muted,
    );
    final marker = ascendant && bindus != null ? ' ↑' : '';
    final fullTitle = '${cell.sign + 1} ${zodiacShortNames[cell.sign]}$marker';
    var title = _text(fullTitle, labelStyle, rect.width);
    if (title.didExceedMaxLines) {
      title.dispose();
      title = _text('${cell.sign + 1}$marker', labelStyle, rect.width);
    }
    if (title.height > rect.height) {
      title.dispose();
      return;
    }
    canvas.save();
    canvas.clipRect(rect);
    title.paint(canvas, Offset(rect.center.dx - title.width / 2, rect.top));
    final content = Rect.fromLTRB(
      rect.left,
      rect.top + title.height + 3,
      rect.right,
      rect.bottom,
    );
    title.dispose();
    if (!content.isEmpty) {
      final points = bindus?[cell.sign];
      final bodyStyle = textStyle.copyWith(
        fontSize: fontSize,
        height: 1.15,
        color: palette.ink,
      );
      if (points != null) {
        var number = _text(
          '$points',
          bodyStyle.copyWith(fontSize: fontSize * 1.6, color: palette.accent),
          content.width,
        );
        if (number.height > content.height || number.didExceedMaxLines) {
          number.dispose();
          number = _text('$points', bodyStyle, content.width);
        }
        if (number.height <= content.height) {
          number.paint(
            canvas,
            content.center - Offset(number.width, number.height) / 2,
          );
        }
        number.dispose();
      } else {
        _paintWrappedPlacements(canvas, content, groups[cell.sign], bodyStyle);
      }
    }
    canvas.restore();
  }

  void _paintWrappedPlacements(
    Canvas canvas,
    Rect bounds,
    List<VedicPlacement> entries,
    TextStyle style,
  ) {
    final tokens = <TextPainter>[
      if (entries.isEmpty)
        _text('—', style.copyWith(color: palette.muted), double.infinity),
      for (final entry in entries)
        _text(
          vedicPlanetMarker(entry),
          style.copyWith(color: palette.planetColor(entry.body)),
          double.infinity,
        ),
    ];
    const horizontalGap = 4.0;
    const verticalGap = 2.0;
    TextPainter? overflow;
    // Keep the actual accessibility text scale. Remove whole tokens rather
    // than shrinking the font; the +N token and hover/dialog retain everyone.
    for (var count = tokens.length; count >= 0; count--) {
      overflow?.dispose();
      overflow = count < tokens.length
          ? _text(
              '+${tokens.length - count}',
              style.copyWith(color: palette.muted),
              double.infinity,
            )
          : null;
      final visible = [
        ...tokens.take(count),
        if (overflow != null) overflow,
      ];
      // Never ellipsize or split a planet's parenthesized label across rows.
      // An over-wide marker is counted in +N just like a crowded one.
      if (visible.any((token) => token.width > bounds.width)) continue;
      final rows = <List<TextPainter>>[];
      var rowWidth = 0.0;
      for (final token in visible) {
        if (rows.isEmpty ||
            (rows.last.isNotEmpty &&
                rowWidth + horizontalGap + token.width > bounds.width)) {
          rows.add([]);
          rowWidth = 0;
        }
        if (rows.last.isNotEmpty) rowWidth += horizontalGap;
        rows.last.add(token);
        rowWidth += token.width;
      }
      final heights = [
        for (final row in rows)
          row.fold(0.0, (height, token) => math.max(height, token.height)),
      ];
      final height = heights.fold(0.0, (a, b) => a + b) +
          math.max(0, rows.length - 1) * verticalGap;
      if (height > bounds.height) continue;
      var y = bounds.top + (bounds.height - height) / 2;
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final width = row.fold(0.0, (sum, token) => sum + token.width) +
            (row.length - 1) * horizontalGap;
        var x = bounds.left + (bounds.width - width) / 2;
        for (final token in row) {
          token.paint(canvas, Offset(x, y + (heights[i] - token.height) / 2));
          x += token.width + horizontalGap;
        }
        y += heights[i] + verticalGap;
      }
      break;
    }
    overflow?.dispose();
    for (final token in tokens) {
      token.dispose();
    }
  }

  VedicChartCenterLayout _centerLayout(Rect bounds) => VedicChartCenterLayout(
        bounds: bounds,
        style: geometry.style,
        division: division,
        ascendantSign: geometry.ascendantSign,
        palette: palette,
        textStyle: textStyle,
        textScaler: textScaler,
        textDirection: textDirection,
        centerLabel: centerLabel,
      );

  void _paintCenter(Canvas canvas, Rect bounds) {
    final center = _centerLayout(bounds);
    center.paint(canvas);
    center.dispose();
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
        final bounds = VedicChartGeometry.chartBounds(size);
        final center = _centerLayout(bounds);
        final centerSemantics = CustomPainterSemantics(
          key: const ValueKey('vedic-chart-center-label'),
          rect: center.medallionBounds ?? center.textBounds,
          properties: SemanticsProperties(
            label: center.semanticsLabel,
            textDirection: textDirection,
          ),
        );
        center.dispose();
        return [
          centerSemantics,
          for (final cell in geometry.cells)
            CustomPainterSemantics(
              key: ValueKey('vedic-sign-${cell.sign}'),
              rect: cell.labelRectIn(bounds),
              properties: SemanticsProperties(
                label: _signTitle(cell),
                value: _signListing(
                  cell,
                  groups[cell.sign],
                  division,
                  bindus?[cell.sign],
                  centerLabel: centerLabel,
                ),
                textDirection: textDirection,
                button: true,
                selected: cell.sign == selectedSign,
                onTap: () => onSelect(cell.sign),
              ),
            ),
        ];
      };

  @override
  bool shouldRepaint(covariant _VedicChartPainter oldDelegate) => true;

  @override
  bool shouldRebuildSemantics(covariant _VedicChartPainter oldDelegate) => true;
}

class _SignDetailsDialog extends StatelessWidget {
  const _SignDetailsDialog({
    required this.cell,
    required this.entries,
    required this.division,
    required this.points,
    required this.centerLabel,
    required this.palette,
    required this.textStyle,
  });

  final VedicChartCell cell;
  final List<VedicPlacement> entries;
  final int division;
  final int? points;
  final String centerLabel;
  final AstrologyPalette palette;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) => Dialog(
        key: const ValueKey('vedic-sign-detail'),
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: palette.raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.line),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: _ChartDetailsScrollView(
            scrollKey: const ValueKey('vedic-sign-detail-scroll'),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        _signTitle(cell),
                        style: textStyle.copyWith(
                          fontSize: 17,
                          height: 1.3,
                          color: palette.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Close sign details',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: palette.muted),
                    ),
                  ],
                ),
                Text(
                  '${centerLabel.isEmpty ? '' : '$centerLabel · '}D-$division',
                  style: textStyle.copyWith(color: palette.muted, fontSize: 12),
                ),
                if (points != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    '$points bindus',
                    key: const ValueKey('vedic-sign-bindus'),
                    style: textStyle.copyWith(
                      color: palette.accent,
                      fontSize: 18,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (entries.isEmpty)
                  Text(
                    'No placements in this sign.',
                    style: textStyle.copyWith(color: palette.muted),
                  ),
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.control,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _bodyName(entry),
                              style: textStyle.copyWith(
                                color: palette.planetColor(entry.body),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              entry.formatted,
                              style: textStyle.copyWith(
                                color: palette.ink,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${entry.nakshatra} · Pada ${entry.pada}',
                              style: textStyle.copyWith(
                                color: palette.muted,
                                fontSize: 12,
                              ),
                            ),
                            if (entry.retrograde)
                              Text(
                                'Retrograde',
                                style: textStyle.copyWith(
                                  color: palette.danger,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Degrees and nakshatra/pada use the original sidereal '
                  '(D-1) longitude${division == 1 ? '.' : '; signs use D-$division.'}',
                  style: textStyle.copyWith(
                    color: palette.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
