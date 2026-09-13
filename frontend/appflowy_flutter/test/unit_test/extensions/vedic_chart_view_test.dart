import 'dart:ui' as ui;

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/vedic_chart_view.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/text_rendering.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart'
    show defaultFontWeight, defaultLetterSpacing;
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Hand-authored placements only: no astrology engine, native library, location,
// network, or time-dependent ephemeris is loaded by these tests.
const _placements = [
  VedicPlacement(
    name: 'Sun',
    shortName: 'Su',
    body: VedicBody.sun,
    longitude: 10.5,
  ),
  VedicPlacement(
    name: 'Moon',
    shortName: 'Mo',
    body: VedicBody.moon,
    longitude: 41.25,
  ),
];

const _northCenters = [
  Offset(0.5, 0.25),
  Offset(0.25, 1 / 12),
  Offset(1 / 12, 0.25),
  Offset(0.25, 0.5),
  Offset(1 / 12, 0.75),
  Offset(0.25, 11 / 12),
  Offset(0.5, 0.75),
  Offset(0.75, 11 / 12),
  Offset(11 / 12, 0.75),
  Offset(0.75, 0.5),
  Offset(11 / 12, 0.25),
  Offset(0.75, 1 / 12),
];

// Aries through Pisces; independent of the implementation's origin table.
const _southCenters = [
  Offset(0.375, 0.125),
  Offset(0.625, 0.125),
  Offset(0.875, 0.125),
  Offset(0.875, 0.375),
  Offset(0.875, 0.625),
  Offset(0.875, 0.875),
  Offset(0.625, 0.875),
  Offset(0.375, 0.875),
  Offset(0.125, 0.875),
  Offset(0.125, 0.625),
  Offset(0.125, 0.375),
  Offset(0.125, 0.125),
];

Finder get _canvas => find.byKey(const ValueKey('vedic-chart-canvas'));
Finder get _details => find.byKey(const ValueKey('vedic-sign-detail'));
Finder get _hoverDetails =>
    find.byKey(const ValueKey('vedic-chart-hover-details'));

void main() {
  group('normalized Vedic chart geometry', () {
    test('North fixes all 12 houses and rotates all 12 ascendant signs', () {
      for (var ascendant = 0; ascendant < 12; ascendant++) {
        final geometry = VedicChartGeometry(
          style: IndianChartStyle.north,
          ascendantSign: ascendant,
        );
        expect(geometry.cells, hasLength(12));
        expect(geometry.cells.map((cell) => cell.sign).toSet(), hasLength(12));
        expect(
          geometry.cells.map((cell) => cell.vertices.length),
          [4, 3, 3, 4, 3, 3, 4, 3, 3, 4, 3, 3],
        );
        for (var house = 0; house < 12; house++) {
          final cell = geometry.hitTest(_northCenters[house]);
          expect(cell, isNotNull);
          expect(cell!.house, house + 1);
          expect(cell.sign, (ascendant + house) % 12);
          expect(cell.center.dx, closeTo(_northCenters[house].dx, 1e-9));
          expect(cell.center.dy, closeTo(_northCenters[house].dy, 1e-9));
        }
        expect(
          geometry.cells.fold(0.0, (area, cell) => area + _area(cell)),
          closeTo(1, 1e-9),
        );
      }
    });

    test('North tiles the square without gaps or overlapping interiors', () {
      final geometry = VedicChartGeometry(
        style: IndianChartStyle.north,
        ascendantSign: 0,
      );
      for (var x = 0; x < 37; x++) {
        for (var y = 0; y < 37; y++) {
          // Non-symmetric offsets avoid the intentionally shared edges.
          final point = Offset((x + 0.37) / 37, (y + 0.61) / 37);
          expect(
            geometry.cells.where((cell) => cell.contains(point)),
            hasLength(1),
            reason: 'Exactly one polygon must contain $point',
          );
        }
      }
      // These points lie inside overlapping polygon *bounding rectangles*.
      expect(geometry.hitTest(const Offset(0.44, 0.14))!.house, 1);
      expect(geometry.hitTest(const Offset(0.24, 0.07))!.house, 2);
      expect(geometry.hitTest(const Offset(0.07, 0.24))!.house, 3);
    });

    test('South fixes clockwise sign cells, beginning with Pisces top-left',
        () {
      for (final ascendant in [0, 5, 11]) {
        final geometry = VedicChartGeometry(
          style: IndianChartStyle.south,
          ascendantSign: ascendant,
        );
        for (var sign = 0; sign < 12; sign++) {
          final cell = geometry.hitTest(_southCenters[sign]);
          expect(cell!.sign, sign);
          expect(cell.house, (sign - ascendant + 12) % 12 + 1);
          expect(cell.center, _southCenters[sign]);
          expect(cell.vertices, hasLength(4));
          expect(_area(cell), closeTo(1 / 16, 1e-9));
        }
        expect(geometry.hitTest(const Offset(0.5, 0.5)), isNull);
        expect(geometry.hitTest(const Offset(0.3, 0.3)), isNull);
        expect(geometry.hitTest(const Offset(0.7, 0.7)), isNull);
        expect(
          geometry.cells.fold(0.0, (area, cell) => area + _area(cell)),
          closeTo(0.75, 1e-9),
        );
      }
    });

    test('labels are disjoint and strictly inset within their own polygons',
        () {
      for (final style in IndianChartStyle.values) {
        final geometry = VedicChartGeometry(style: style, ascendantSign: 8);
        for (final cell in geometry.cells) {
          final rect = cell.labelBounds;
          for (final corner in [
            rect.topLeft,
            rect.topRight,
            rect.bottomRight,
            rect.bottomLeft,
          ]) {
            expect(cell.contains(corner), isTrue);
            expect(geometry.hitTest(corner)!.sign, cell.sign);
          }
          for (final other in geometry.cells) {
            if (other.sign != cell.sign) {
              expect(rect.overlaps(other.labelBounds), isFalse);
              expect(
                cell
                    .pathIn(const Rect.fromLTWH(0, 0, 1, 1))
                    .contains(other.center),
                isFalse,
              );
            }
          }
          expect(
            cell.pathIn(const Rect.fromLTWH(0, 0, 1, 1)).contains(cell.center),
            isTrue,
          );
        }
        for (final outside in [
          const Offset(-0.01, 0.5),
          const Offset(1.01, 0.5),
          const Offset(0.5, -0.01),
          const Offset(0.5, 1.01),
          const Offset(double.nan, 0.5),
        ]) {
          expect(geometry.hitTest(outside), isNull);
        }
      }
    });
  });

  test('planet markers parenthesize only retrograde bodies', () {
    for (final body in VedicBody.values) {
      for (final retrograde in [false, true]) {
        final placement = VedicPlacement(
          name: body.label,
          shortName: 'Ignored in favor of the body abbreviation',
          body: body,
          longitude: 1,
          speed: retrograde ? -0.1 : 0.1,
        );
        final marker = vedicPlanetMarker(placement);
        expect(marker, retrograde ? '(${body.shortName})' : body.shortName);
        expect(marker.codeUnits, everyElement(inInclusiveRange(0, 127)));
        expect(marker, isNot(contains('Rx')));
        expect(marker, isNot(contains('℞')));
      }
    }
    for (final (name, shortName) in [
      ('Special lagna', 'SL'),
      ('Ascendant (Lagna)', 'As'),
    ]) {
      for (final speed in [-0.1, 0.0, 0.1]) {
        final placement = VedicPlacement(
          name: name,
          shortName: shortName,
          longitude: 1,
          speed: speed,
        );
        expect(placement.retrograde, isFalse);
        expect(vedicPlanetMarker(placement), shortName);
      }
    }
  });

  testWidgets('measured centers fit every division and custom label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _chartApp(
        weight: FontWeight.w300,
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            fontFamily: 'Inherited chart face',
            fontFamilyFallback: ['Ahem'],
          ),
          child: const VedicChartView(placements: [], ascendant: 1),
        ),
      ),
    );
    final context = tester.element(_canvas);
    final palette = AstrologyPalette.of(context);
    final textStyle = _chartTextStyle(context);
    for (final style in IndianChartStyle.values) {
      final geometry = VedicChartGeometry(style: style, ascendantSign: 8);
      for (final side in [220.0, 360.0, 600.0]) {
        final bounds = VedicChartGeometry.chartBounds(Size.square(side));
        for (final scale in [1.0, 2.0]) {
          for (final direction in ui.TextDirection.values) {
            for (final division in astrologyDivisions.keys) {
              for (final (label, customLabel) in [
                ('', ''),
                ('D-$division', ''),
                (' D$division ', ''),
                ('SAV', 'SAV'),
                ('Mercury BAV', 'Mercury BAV'),
                ('Saturn BAV', 'Saturn BAV'),
                ('D-$division Mercury BAV', 'D-$division Mercury BAV'),
              ]) {
                final reason = '$style D-$division "$label" '
                    'at $side / ${scale}x / $direction';
                final layout = VedicChartCenterLayout(
                  bounds: bounds,
                  style: style,
                  division: division,
                  ascendantSign: 8,
                  palette: palette,
                  textStyle: textStyle,
                  textScaler: TextScaler.linear(scale),
                  textDirection: direction,
                  centerLabel: label,
                );
                try {
                  final span = layout.text.text! as TextSpan;
                  final plain = span.toPlainText();
                  expect(span.style!.fontFamily, 'Inherited chart face');
                  expect(span.style!.fontFamilyFallback, ['Ahem']);
                  expect(span.style!.fontWeight, FontWeight.w300);
                  expect(layout.text.textScaler.scale(12), 12 * scale);
                  expect(layout.text.textDirection, direction);
                  expect(layout.text.maxLines, isNull);
                  expect(layout.text.ellipsis, isNull);
                  expect(layout.text.didExceedMaxLines, isFalse);
                  expect(layout.scale, greaterThan(0), reason: reason);
                  expect(layout.scale, lessThanOrEqualTo(1), reason: reason);
                  expect(
                    layout.textBounds.center.dx,
                    closeTo(bounds.center.dx, 1e-9),
                  );
                  expect(
                    layout.textBounds.center.dy,
                    closeTo(bounds.center.dy, 1e-9),
                  );
                  _expectRectInside(layout.textBounds, bounds, reason);
                  expect(
                    layout.semanticsLabel,
                    '${customLabel.isEmpty ? '' : '$customLabel · '}D-$division'
                    '${style == IndianChartStyle.south ? ' · Sagittarius rising' : ''}',
                    reason: reason,
                  );
                  if (customLabel.isNotEmpty) {
                    expect(plain.replaceAll('\n', ' '), contains(customLabel));
                  }
                  if (style == IndianChartStyle.north) {
                    expect(
                      plain,
                      customLabel.isEmpty
                          ? 'D$division'
                          : customLabel.replaceAll(' ', '\n'),
                    );
                    expect(
                      layout.text.computeLineMetrics(),
                      hasLength(
                        customLabel.isEmpty ? 1 : customLabel.split(' ').length,
                      ),
                    );
                    final medallion = layout.medallionBounds!;
                    expect(medallion.width, closeTo(medallion.height, 1e-9));
                    expect(
                      medallion.width,
                      lessThanOrEqualTo(bounds.shortestSide * 0.28 + 1e-9),
                      reason: reason,
                    );
                    _expectRectInside(medallion.inflate(0.4), bounds, reason);
                    for (final cell in geometry.cells) {
                      expect(
                        medallion
                            .inflate(0.4)
                            .overlaps(cell.labelRectIn(bounds)),
                        isFalse,
                        reason: reason,
                      );
                    }
                  } else {
                    expect(layout.medallionBounds, isNull);
                    expect(
                      plain,
                      'D$division${customLabel.isEmpty ? '' : '\n$customLabel'}'
                      '\nSagittarius rising',
                      reason: reason,
                    );
                    expect(
                      layout.text
                          .getLineBoundary(const TextPosition(offset: 0))
                          .textInside(plain)
                          .trim(),
                      'D$division',
                      reason: reason,
                    );
                    final subtitle = span.children!.single as TextSpan;
                    expect(subtitle.style!.color, palette.muted);
                    expect(
                      subtitle.style!.fontSize,
                      lessThan(span.style!.fontSize!),
                    );
                    _expectRectInside(
                      layout.textBounds,
                      Rect.fromCenter(
                        center: bounds.center,
                        width: bounds.width / 2,
                        height: bounds.height / 2,
                      ),
                      reason,
                    );
                  }
                  // Measure shaped words, excluding selection-only boxes for
                  // newlines and trailing whitespace beyond a wrapped line.
                  final boxes = RegExp(r'\S+').allMatches(plain).expand(
                        (word) => layout.text.getBoxesForSelection(
                          TextSelection(
                            baseOffset: word.start,
                            extentOffset: word.end,
                          ),
                        ),
                      );
                  expect(boxes, isNotEmpty, reason: reason);
                  for (final box in boxes) {
                    final painted = Rect.fromLTRB(
                      layout.paintOffset.dx + box.left * layout.scale,
                      layout.paintOffset.dy + box.top * layout.scale,
                      layout.paintOffset.dx + box.right * layout.scale,
                      layout.paintOffset.dy + box.bottom * layout.scale,
                    );
                    _expectRectInside(
                      painted,
                      layout.textBounds.inflate(0.01),
                      reason,
                    );
                    final medallion = layout.medallionBounds;
                    if (medallion != null) {
                      for (final corner in [
                        painted.topLeft,
                        painted.topRight,
                        painted.bottomLeft,
                        painted.bottomRight,
                      ]) {
                        expect(
                          (corner - medallion.center).distance,
                          lessThanOrEqualTo(medallion.width / 2),
                          reason: reason,
                        );
                      }
                    }
                  }
                } finally {
                  layout.dispose();
                }
              }
            }
          }
        }
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('center pixels and semantics retain warm, legible typography', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      for (final (brightness, paper) in [
        (Brightness.light, false),
        (Brightness.light, true),
        (Brightness.dark, false),
      ]) {
        for (final style in IndianChartStyle.values) {
          for (final (side, scale, division, label) in [
            (220.0, 2.0, 1, 'D-1'),
            (220.0, 2.0, 9, 'D-9'),
            (220.0, 2.0, 10, 'D-10'),
            (220.0, 2.0, 30, 'D-30'),
            (220.0, 2.0, 10, ''),
            (220.0, 2.0, 10, 'Mercury BAV'),
            (360.0, 1.0, 10, 'SAV'),
            (600.0, 2.0, 10, 'Saturn BAV'),
          ]) {
            await tester.pumpWidget(
              _chartApp(
                size: Size.square(side),
                brightness: brightness,
                paper: paper,
                textScaler: TextScaler.linear(scale),
                child: VedicChartView(
                  placements: const [],
                  ascendant: 1,
                  style: style,
                  division: division,
                  centerLabel: label,
                  bindus: label == 'SAV' || label.endsWith('BAV')
                      ? List.filled(12, 4)
                      : null,
                ),
              ),
            );
            final palette = AstrologyPalette.of(tester.element(_canvas));
            final layout = _centerLayout(tester);
            try {
              final nodes = _semanticsBelow(tester.getSemantics(_canvas))
                  .map((node) => node.getSemanticsData())
                  .toList();
              final center = nodes.singleWhere(
                (node) => node.label == layout.semanticsLabel,
              );
              expect(center.hasFlag(ui.SemanticsFlag.isButton), isFalse);
              expect(center.hasAction(ui.SemanticsAction.tap), isFalse);
              expect(
                nodes.where((node) => node.hasFlag(ui.SemanticsFlag.isButton)),
                hasLength(12),
              );
              final painter = tester.widget<CustomPaint>(_canvas).painter!;
              final pixels = await _rasterize(
                tester,
                Size.square(side),
                (canvas) => painter.paint(canvas, Size.square(side)),
              );
              final ink = _pixelsIn(pixels, side.toInt(), layout.textBounds);
              expect(ink, contains(_rgba(palette.accent)));
              expect(
                _contrast(palette.accent, palette.surface),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                tester.renderObject(_canvas),
                isNot(paints..rrect(color: palette.raised)),
              );
              if (palette.surface != Colors.white) {
                expect(
                  _pixelsIn(
                    pixels,
                    side.toInt(),
                    layout.medallionBounds ?? layout.textBounds,
                  ),
                  isNot(contains(_rgba(Colors.white))),
                );
              }
              if (style == IndianChartStyle.north) {
                final medallion = layout.medallionBounds!;
                // Sample real negative space between the shaped text and rim.
                final sample = Offset(
                  medallion.center.dx,
                  (medallion.top + layout.textBounds.top) / 2,
                );
                expect(
                  _pixelAt(pixels, side.toInt(), sample),
                  _rgba(palette.surface),
                );
                // path() checks the next path, not the next matching color.
                // Consume all twelve house fills before the grid stroke.
                final paintPattern = paints;
                for (var cell = 0; cell < 12; cell++) {
                  paintPattern.path(style: PaintingStyle.fill);
                }
                expect(
                  tester.renderObject(_canvas),
                  paintPattern
                    ..path(color: palette.line, strokeWidth: 1)
                    ..circle(
                      x: medallion.center.dx,
                      y: medallion.center.dy,
                      radius: medallion.width / 2,
                      color: palette.surface,
                      style: PaintingStyle.fill,
                    )
                    ..circle(
                      x: medallion.center.dx,
                      y: medallion.center.dy,
                      radius: medallion.width / 2,
                      color: palette.line,
                      style: PaintingStyle.stroke,
                      // The matcher compares Paint's float32 width exactly.
                      strokeWidth: (Paint()..strokeWidth = 0.8).strokeWidth,
                    ),
                );
              } else {
                expect(ink, contains(_rgba(palette.muted)));
                expect(
                  _contrast(palette.muted, palette.surface),
                  greaterThanOrEqualTo(4.5),
                );
                expect(tester.renderObject(_canvas), isNot(paints..circle()));
              }
            } finally {
              layout.dispose();
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    } finally {
      handle.dispose();
    }
  });

  testWidgets('painted parentheses stay whole in rows, wraps and overflow', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      const retrogrades = [
        VedicPlacement(
          name: 'Saturn',
          shortName: 'Sa',
          body: VedicBody.saturn,
          longitude: 91,
          speed: -0.1,
        ),
        VedicPlacement(
          name: 'Mercury',
          shortName: 'Me',
          body: VedicBody.mercury,
          longitude: 91,
          speed: -0.1,
        ),
      ];
      final exercised = <String>{};
      for (final style in IndianChartStyle.values) {
        // 1° Aries and 1° Cancer retain their signs in both D-1 and D-9.
        for (final division in [1, 9]) {
          for (final side in [220.0, 360.0, 600.0]) {
            for (final scale in [1.0, 2.0]) {
              final reason = '${style.name} D-$division at $side / ${scale}x';
              await tester.pumpWidget(
                _chartApp(
                  theme: ThemeData(fontFamily: 'Ahem'),
                  size: Size.square(side),
                  textScaler: TextScaler.linear(scale),
                  child: VedicChartView(
                    placements: retrogrades,
                    ascendant: 1,
                    style: style,
                    division: division,
                  ),
                ),
              );
              final context = tester.element(_canvas);
              final palette = AstrologyPalette.of(context);
              final size = tester.getSize(_canvas);
              final cell = VedicChartGeometry(
                style: style,
                ascendantSign: 0,
              ).cellForSign(3);
              final rect =
                  cell.labelRectIn(VedicChartGeometry.chartBounds(size));
              final fontSize = (side / 28).clamp(10.5, 12.5);
              final bodyStyle = _chartTextStyle(context).copyWith(
                fontSize: fontSize,
                height: 1.15,
              );
              TextPainter measure(
                      String value, TextStyle style, double width) =>
                  TextPainter(
                    text: TextSpan(text: value, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    ellipsis: '…',
                  )..layout(maxWidth: width);
              final title = measure(
                '4 Cn',
                bodyStyle.copyWith(
                  fontSize: fontSize - 0.5,
                  color: palette.muted,
                ),
                rect.width,
              );
              final content = Rect.fromLTRB(
                rect.left,
                rect.top + title.height + 3,
                rect.right,
                rect.bottom,
              );
              title.dispose();
              // Literal expectations deliberately do not use vedicPlanetMarker.
              final markers = [
                measure(
                  '(Sa)',
                  bodyStyle.copyWith(
                    color: palette.planetColor(VedicBody.saturn),
                  ),
                  double.infinity,
                ),
                measure(
                  '(Me)',
                  bodyStyle.copyWith(
                    color: palette.planetColor(VedicBody.mercury),
                  ),
                  double.infinity,
                ),
              ];
              final overflow = measure(
                '+2',
                bodyStyle.copyWith(color: palette.muted),
                double.infinity,
              );
              try {
                // Measure Ahem; the shorter tokens can now share the 600px row.
                expect(markers.first.width, markers.last.width);
                expect(markers.first.height, markers.last.height);
                final rowWidth = markers.first.width + markers.last.width + 4;
                final singleRow = rowWidth <= content.width;
                final fits = markers.first.width <= content.width;
                final height = singleRow
                    ? markers.first.height
                    : markers.first.height + markers.last.height + 2;
                if (fits) {
                  expect(
                    height,
                    lessThanOrEqualTo(content.height),
                    reason: reason,
                  );
                }
                final fitsOverflow = overflow.width <= content.width &&
                    overflow.height <= content.height;
                exercised.add(
                  fits
                      ? (singleRow ? 'row' : 'wrap')
                      : (fitsOverflow ? 'overflow' : 'empty'),
                );
                final painter = tester.widget<CustomPaint>(_canvas).painter!;
                final actual = await _rasterize(
                  tester,
                  size,
                  (canvas) => painter.paint(canvas, size),
                );
                final expected = await _rasterize(tester, size, (canvas) {
                  canvas.drawRect(
                    Offset.zero & size,
                    Paint()..color = palette.surface,
                  );
                  if (fits) {
                    var x = content.center.dx - rowWidth / 2;
                    var y = content.center.dy - height / 2;
                    for (final marker in markers) {
                      marker.paint(
                        canvas,
                        Offset(
                          singleRow ? x : content.center.dx - marker.width / 2,
                          y,
                        ),
                      );
                      if (singleRow) {
                        x += marker.width + 4;
                      } else {
                        y += marker.height + 2;
                      }
                    }
                  } else if (fitsOverflow) {
                    overflow.paint(
                      canvas,
                      content.center -
                          Offset(overflow.width, overflow.height) / 2,
                    );
                  }
                });
                expect(
                  _pixelsIn(actual, side.toInt(), content),
                  orderedEquals(_pixelsIn(expected, side.toInt(), content)),
                  reason: 'Complete parenthesized markers: $reason',
                );
                final listing = _semanticsBelow(tester.getSemantics(_canvas))
                    .map((node) => node.getSemanticsData())
                    .singleWhere((node) => node.label == 'Cancer · House 4')
                    .value;
                expect(listing, contains('Saturn (retrograde)'),
                    reason: reason);
                expect(listing, contains('Mercury (retrograde)'),
                    reason: reason);
                expect(listing, contains('D-$division'), reason: reason);
              } finally {
                overflow.dispose();
                for (final marker in markers) {
                  marker.dispose();
                }
              }
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
      expect(exercised, containsAll(['row', 'wrap', 'overflow']));
    } finally {
      handle.dispose();
    }
  });

  group('bundled chart typography', () {
    // Separate registration names keep the Ahem layout/raster tests isolated.
    const fonts = {
      'Vedic DM Sans regression':
          'assets/google_fonts/DM_Sans/DMSans-Variable.ttf',
      'Vedic Inter regression': 'assets/google_fonts/Inter/Inter-Variable.ttf',
    };
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final font in fonts.entries) {
        final loader = FontLoader(font.key)
          ..addFont(rootBundle.load(font.value));
        await loader.load();
      }
    });

    testWidgets('parentheses wrap legibly with active axes and tracking', (
      tester,
    ) async {
      for (final (body, expected) in [
        (VedicBody.saturn, '(Sa)'),
        (VedicBody.mercury, '(Me)'),
      ]) {
        final value = vedicPlanetMarker(
          VedicPlacement(
            name: body.label,
            shortName: body.shortName,
            body: body,
            longitude: 7.5,
            speed: -0.1,
          ),
        );
        expect(value, expected);
        expect(
          [value.codeUnitAt(0), value.codeUnitAt(value.length - 1)],
          [0x28, 0x29],
        );
        for (final family in fonts.keys) {
          for (final weight in [
            FontWeight.w300,
            defaultFontWeight,
            FontWeight.w700,
          ]) {
            for (final fontSize in [10.5, 12.5]) {
              for (final scale in [1.0, 2.0]) {
                for (final direction in ui.TextDirection.values) {
                  final reason = '$family $weight $value at $fontSize / '
                      '${scale}x / $direction';
                  final textStyle = _activeChartFont(family, weight).copyWith(
                    fontSize: fontSize,
                    height: 1.15,
                    color: Colors.black,
                  );
                  final marker = TextPainter(
                    text: TextSpan(text: value, style: textStyle),
                    textDirection: direction,
                    textScaler: TextScaler.linear(scale),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    ellipsis: '…',
                  )..layout();
                  final wrapped = TextPainter(
                    text: TextSpan(text: '$value $value', style: textStyle),
                    textDirection: direction,
                    textScaler: TextScaler.linear(scale),
                    textAlign: TextAlign.center,
                  )..layout(maxWidth: marker.width * 1.25);
                  try {
                    expect(marker.didExceedMaxLines, isFalse, reason: reason);
                    expect(marker.computeLineMetrics(), hasLength(1));
                    expect(wrapped.didExceedMaxLines, isFalse, reason: reason);
                    expect(
                      wrapped.computeLineMetrics(),
                      hasLength(2),
                      reason: reason,
                    );
                    Rect advanceBox(int offset) {
                      final boxes = wrapped.getBoxesForSelection(
                        TextSelection(
                          baseOffset: offset,
                          extentOffset: offset + 1,
                        ),
                      );
                      expect(boxes, hasLength(1), reason: reason);
                      return boxes.single.toRect();
                    }

                    // Supersample shaped ink, not just advance boxes. Wrapping
                    // must leave both parentheses and both letters readable.
                    const density = 8.0;
                    final size = Size(
                      (wrapped.width + 4) * density,
                      (wrapped.height + 4) * density,
                    );
                    final pixels = await _rasterize(tester, size, (canvas) {
                      canvas.scale(density);
                      wrapped.paint(canvas, const Offset(2, 2));
                    });
                    // Font ink can extend outside selection-line metrics,
                    // especially for RTL brackets. Segment the actual empty
                    // space between painted rows, not the advance-box bands.
                    final inkRows = _inkRows(pixels, size.width.ceil());
                    expect(inkRows, hasLength(2), reason: reason);
                    Rect? previousLineInk;
                    for (final (line, start) in [0, value.length + 1].indexed) {
                      expect(
                        wrapped
                            .getLineBoundary(TextPosition(offset: start + 1))
                            .textInside(wrapped.plainText)
                            .trim(),
                        value,
                        reason: reason,
                      );
                      // Sa/Me remain strong L runs in an RTL paragraph, while
                      // the neutral brackets can swap sides and mirror.
                      final parentheses = [
                        advanceBox(start),
                        advanceBox(start + value.length - 1),
                      ]..sort((a, b) => a.left.compareTo(b.left));
                      final boxes = [
                        parentheses.first,
                        advanceBox(start + 1),
                        advanceBox(start + 2),
                        parentheses.last,
                      ];
                      // SkParagraph run bounds are float32; independently
                      // accumulated bidi offsets can differ by a few ULPs.
                      const geometryTolerance = 1e-4;
                      for (var index = 0; index < boxes.length; index++) {
                        final rect = boxes[index];
                        expect(rect.width, greaterThan(0), reason: reason);
                        expect(
                          rect.top,
                          closeTo(boxes.first.top, geometryTolerance),
                          reason: reason,
                        );
                        if (index > 0) {
                          expect(
                            boxes[index - 1].right,
                            lessThanOrEqualTo(rect.left + geometryTolerance),
                            reason: reason,
                          );
                        }
                      }
                      // Selection boxes describe advances, not ink ownership:
                      // tracking at bidi-run boundaries can put a neighbouring
                      // glyph inside one. Find the four connected glyphs in the
                      // full painted row without changing shaping or direction.
                      final ink = _inkComponentsIn(
                        pixels,
                        size.width.ceil(),
                        inkRows[line],
                      );
                      expect(ink, hasLength(4), reason: reason);
                      expect(
                        ink.first.right,
                        lessThan(ink[1].left),
                        reason: reason,
                      );
                      expect(
                        ink[1].right,
                        lessThanOrEqualTo(ink[2].left),
                        reason: reason,
                      );
                      expect(
                        ink[2].right,
                        lessThan(ink.last.left),
                        reason: reason,
                      );
                      expect(
                        ink.first.top,
                        closeTo(ink.last.top, density / 2),
                        reason: reason,
                      );
                      expect(
                        ink.first.height,
                        closeTo(ink.last.height, density / 2),
                        reason: reason,
                      );
                      expect(
                        ink.first.width,
                        closeTo(ink.last.width, density / 2),
                        reason: reason,
                      );
                      for (final parenthesis in [ink.first, ink.last]) {
                        expect(
                          parenthesis.height,
                          greaterThan(ink[1].height),
                          reason: reason,
                        );
                        expect(
                          parenthesis.top,
                          lessThanOrEqualTo(ink[1].top),
                          reason: reason,
                        );
                        expect(
                          parenthesis.bottom,
                          greaterThanOrEqualTo(ink[2].bottom),
                          reason: reason,
                        );
                      }
                      // Capital S/M must not collapse into the lower-case a/e
                      // or a fallback box, even with the active tracking.
                      expect(ink[1].top, lessThan(ink[2].top), reason: reason);
                      expect(
                        ink[1].height,
                        greaterThan(ink[2].height),
                        reason: reason,
                      );
                      final lineInk =
                          ink.reduce((a, b) => a.expandToInclude(b));
                      if (previousLineInk != null) {
                        expect(
                          previousLineInk.bottom,
                          lessThan(lineInk.top),
                          reason: reason,
                        );
                      }
                      previousLineInk = lineInk;
                    }
                  } finally {
                    wrapped.dispose();
                    marker.dispose();
                  }
                }
              }
            }
          }
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('small varga centers preserve real fonts and whole words', (
      tester,
    ) async {
      for (final family in fonts.keys) {
        final inherited = _activeChartFont(family, defaultFontWeight);
        await tester.pumpWidget(
          _chartApp(
            child: DefaultTextStyle.merge(
              style: inherited,
              child: const VedicChartView(placements: [], ascendant: 1),
            ),
          ),
        );
        final context = tester.element(_canvas);
        for (final style in IndianChartStyle.values) {
          final geometry = VedicChartGeometry(style: style, ascendantSign: 8);
          for (final side in [160.0, 220.0, 360.0]) {
            final bounds = VedicChartGeometry.chartBounds(Size.square(side))
                .shift(const Offset(13, 7));
            for (final scale in [1.0, 2.0]) {
              for (final division in [1, 9, 10, 30]) {
                for (final label in ['D-$division', 'Mercury BAV']) {
                  final reason = '$family $style "$label" '
                      'at $side / ${scale}x';
                  final layout = VedicChartCenterLayout(
                    bounds: bounds,
                    style: style,
                    division: division,
                    ascendantSign: 8,
                    palette: AstrologyPalette.of(context),
                    textStyle: _chartTextStyle(context),
                    textScaler: TextScaler.linear(scale),
                    textDirection: Directionality.of(context),
                    centerLabel: label,
                  );
                  try {
                    final span = layout.text.text! as TextSpan;
                    expect(span.style!.fontFamily, family);
                    expect(
                      span.style!.fontVariations,
                      inherited.fontVariations,
                    );
                    expect(span.style!.fontFeatures, inherited.fontFeatures);
                    expect(span.style!.letterSpacing, inherited.letterSpacing);
                    expect(layout.scale, greaterThan(0), reason: reason);
                    expect(layout.scale, lessThanOrEqualTo(1), reason: reason);
                    expect(layout.text.maxLines, isNull);
                    expect(layout.text.ellipsis, isNull);
                    expect(layout.text.didExceedMaxLines, isFalse);
                    final north = style == IndianChartStyle.north;
                    expect(
                      span.text,
                      north && label == 'Mercury BAV'
                          ? 'Mercury\nBAV'
                          : 'D$division',
                      reason: reason,
                    );
                    final freeCenter = Rect.fromCenter(
                      center: bounds.center,
                      width: bounds.width * (north ? 0.28 : 0.40),
                      height: bounds.height * (north ? 0.28 : 0.40),
                    );
                    _expectRectInside(
                      layout.textBounds,
                      freeCenter.inflate(1e-6),
                      reason,
                    );
                    // Bounds alone must not hide an uncorrected paint origin.
                    expect(
                      layout.paint,
                      paints
                        ..translate(
                          x: layout.paintOffset.dx,
                          y: layout.paintOffset.dy,
                        )
                        ..scale(x: layout.scale)
                        ..paragraph(),
                      reason: reason,
                    );
                    final plain = span.toPlainText();
                    for (final word in RegExp(r'\S+').allMatches(plain)) {
                      final boxes = layout.text.getBoxesForSelection(
                        TextSelection(
                          baseOffset: word.start,
                          extentOffset: word.end,
                        ),
                      );
                      expect(
                        boxes,
                        hasLength(1),
                        reason: '$reason: ${word.group(0)}',
                      );
                      final box = boxes.single;
                      final painted = Rect.fromLTRB(
                        layout.paintOffset.dx + box.left * layout.scale,
                        layout.paintOffset.dy + box.top * layout.scale,
                        layout.paintOffset.dx + box.right * layout.scale,
                        layout.paintOffset.dy + box.bottom * layout.scale,
                      );
                      _expectRectInside(
                        painted,
                        layout.textBounds.inflate(0.01),
                        reason,
                      );
                      _expectRectInside(
                        painted,
                        freeCenter.inflate(0.01),
                        reason,
                      );
                      final medallion = layout.medallionBounds;
                      if (medallion != null) {
                        for (final corner in [
                          painted.topLeft,
                          painted.topRight,
                          painted.bottomLeft,
                          painted.bottomRight,
                        ]) {
                          expect(
                            (corner - medallion.center).distance,
                            lessThan(medallion.width / 2),
                            reason: reason,
                          );
                        }
                      }
                    }
                    for (final cell in geometry.cells) {
                      expect(
                        (layout.medallionBounds ?? layout.textBounds)
                            .inflate(0.4)
                            .overlaps(cell.labelRectIn(bounds)),
                        isFalse,
                        reason: reason,
                      );
                    }
                  } finally {
                    layout.dispose();
                  }
                }
              }
            }
          }
        }
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('North center medallion does not mask the crossing hit', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      _chartApp(
        size: const Size.square(220),
        textScaler: const TextScaler.linear(2),
        child: VedicChartView(
          placements: const [],
          ascendant: 1,
          division: 10,
          centerLabel: 'Mercury BAV',
          onSignSelected: selected.add,
        ),
      ),
    );
    await tester.tapAt(_chartPoint(tester, const Offset(0.5, 0.5)));
    await tester.pumpAndSettle();
    expect(selected, [0]);
    expect(find.text('Mercury BAV · D-10'), findsOneWidget);
    await _closeDetails(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'chart details hide desktop scrollbars without disabling scrolling', (
    tester,
  ) async {
    final crowded = [
      for (var index = 0; index < 24; index++)
        VedicPlacement(
          name: 'Placement $index',
          shortName: 'P$index',
          longitude: 7.5,
        ),
      const VedicPlacement(
        name: 'Saturn',
        shortName: 'Sa',
        body: VedicBody.saturn,
        longitude: 7.5,
        speed: -0.1,
      ),
    ];
    await tester.pumpWidget(
      _chartApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        child: SingleChildScrollView(
          key: const ValueKey('outside-chart-scroll'),
          child: VedicChartView(
            placements: crowded,
            ascendant: 7.5,
            division: 9,
            centerLabel: 'Saturn BAV',
          ),
        ),
      ),
    );
    final scrollbars =
        find.byWidgetPredicate((widget) => widget is RawScrollbar);
    final outside = find.byKey(const ValueKey('outside-chart-scroll'));
    expect(find.descendant(of: outside, matching: scrollbars), findsOneWidget);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(_chartPoint(tester, _northCenters.first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 410));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('vedic-chart-hover-card'));
    expect(find.descendant(of: card, matching: scrollbars), findsNothing);
    final hoverScroll = tester.state<ScrollableState>(
      find.descendant(of: card, matching: find.byType(Scrollable)),
    );
    expect(hoverScroll.position.maxScrollExtent, greaterThan(0));
    expect(
      tester.widget<Text>(_hoverDetails).data,
      contains('Saturn (retrograde)'),
    );
    expect(tester.widget<Text>(_hoverDetails).data, contains('D-9'));
    await tester.tapAt(_chartPoint(tester, _northCenters.first));
    await tester.pumpAndSettle();
    expect(find.descendant(of: _details, matching: scrollbars), findsNothing);
    expect(find.text('Retrograde'), findsOneWidget);
    expect(find.text('Saturn BAV · D-9'), findsOneWidget);
    final detailsScroll = tester.state<ScrollableState>(
      find.descendant(of: _details, matching: find.byType(Scrollable)),
    );
    await tester.drag(
      find.byKey(const ValueKey('vedic-sign-detail-scroll')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(detailsScroll.position.pixels, greaterThan(0));
    Navigator.of(tester.element(_details)).pop();
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(find.descendant(of: outside, matching: scrollbars), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real taps select all twelve North signs in house order', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      _chartApp(
        child: VedicChartView(
          placements: _placements,
          ascendant: 151,
          onSignSelected: selected.add,
        ),
      ),
    );
    for (var house = 0; house < 12; house++) {
      final sign = (5 + house) % 12;
      await tester.tapAt(_chartPoint(tester, _northCenters[house]));
      await tester.pumpAndSettle();
      expect(selected.last, sign);
      expect(_details, findsOneWidget);
      expect(
        find.text('${zodiacNames[sign]} · House ${house + 1}'),
        findsOneWidget,
      );
      await _closeDetails(tester);
    }
    expect(selected, [5, 6, 7, 8, 9, 10, 11, 0, 1, 2, 3, 4]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real taps select all twelve fixed South cells', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      _chartApp(
        child: VedicChartView(
          placements: _placements,
          ascendant: 151,
          style: IndianChartStyle.south,
          onSignSelected: selected.add,
        ),
      ),
    );
    for (var sign = 0; sign < 12; sign++) {
      await tester.tapAt(_chartPoint(tester, _southCenters[sign]));
      await tester.pumpAndSettle();
      expect(selected.last, sign);
      expect(
        find.text('${zodiacNames[sign]} · House ${(sign - 5 + 12) % 12 + 1}'),
        findsOneWidget,
      );
      await _closeDetails(tester);
    }
    expect(selected, List.generate(12, (sign) => sign));
    expect(tester.takeException(), isNull);
  });

  testWidgets('triangle bounding rectangles never steal a neighboring tap', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      _chartApp(
        child: VedicChartView(
          placements: _placements,
          ascendant: 1,
          onSignSelected: selected.add,
        ),
      ),
    );
    for (final point in [
      const Offset(0.44, 0.14),
      const Offset(0.24, 0.07),
      const Offset(0.07, 0.24),
    ]) {
      await tester.tapAt(_chartPoint(tester, point));
      await tester.pumpAndSettle();
      await _closeDetails(tester);
    }
    expect(selected, [0, 1, 2]);
  });

  testWidgets('tap details show full names, degrees, nakshatra and pada', (
    tester,
  ) async {
    await tester.pumpWidget(
      _chartApp(
        weight: FontWeight.w300,
        // Local scaling must survive moving details into the Navigator overlay.
        child: const MediaQuery(
          data: MediaQueryData(
            size: Size(800, 600),
            textScaler: TextScaler.linear(1.4),
          ),
          child: VedicChartView(placements: _placements, ascendant: 1),
        ),
      ),
    );
    await tester.tapAt(_chartPoint(tester, _northCenters.first));
    await tester.pumpAndSettle();
    expect(find.text('Sun'), findsOneWidget);
    expect(find.text('Ascendant (Lagna)'), findsOneWidget);
    expect(find.text(formatZodiacLongitude(10.5)), findsOneWidget);
    expect(find.text('Ashwini · Pada 4'), findsOneWidget);
    final sun = tester.widget<Text>(find.text('Sun'));
    expect(sun.style!.fontWeight, FontWeight.w300);
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('Sun'))).scale(10),
      14,
    );
    await _closeDetails(tester);
    final palette = AstrologyPalette.of(tester.element(_canvas));
    expect(
      tester.renderObject(_canvas),
      paints..path(color: palette.selection),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection survives a parent rebuilding the placements list', (
    tester,
  ) async {
    var placements = _placements;
    int? selected;
    await tester.pumpWidget(
      _chartApp(
        child: StatefulBuilder(
          builder: (context, rebuild) => VedicChartView(
            placements: placements,
            ascendant: 1,
            onSignSelected: (sign) {
              selected = sign;
              rebuild(() => placements = List.of(placements));
            },
          ),
        ),
      ),
    );
    await tester.tapAt(_chartPoint(tester, _northCenters.first));
    await tester.pumpAndSettle();
    expect(selected, 0);
    await _closeDetails(tester);
    final palette = AstrologyPalette.of(tester.element(_canvas));
    expect(
      tester.renderObject(_canvas),
      paints..path(color: palette.selection),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('real mouse hover follows polygons and reveals a full listing', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(
      _chartApp(
        paper: true,
        child: VedicChartView(
          placements: _placements,
          ascendant: 1,
          onSignSelected: selected.add,
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(_chartPoint(tester, _northCenters[1]));
    await tester.pump();
    final palette = AstrologyPalette.of(tester.element(_canvas));
    expect(
      tester.renderObject(_canvas),
      paints
        ..path()
        ..path(color: palette.hover),
    );
    await tester.pump(const Duration(milliseconds: 410));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(_hoverDetails).data, contains('Taurus'));
    expect(tester.widget<Text>(_hoverDetails).data, contains('Moon'));
    expect(selected, isEmpty);

    await mouse.moveTo(_chartPoint(tester, _northCenters.first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 410));
    await tester.pumpAndSettle();
    final listing = tester.widget<Text>(_hoverDetails).data!;
    expect(listing, contains('Aries'));
    expect(listing, contains('Sun'));
    expect(listing, contains(formatZodiacLongitude(10.5)));
    expect(listing, isNot(contains('Moon')));
    // Click directly through the painted hover card into a chart polygon.
    final frame = VedicChartGeometry.chartBounds(tester.getSize(_canvas))
        .shift(tester.getTopLeft(_canvas));
    final cardFinder = find.byKey(const ValueKey('vedic-chart-hover-card'));
    final decoration =
        tester.widget<DecoratedBox>(cardFinder).decoration as BoxDecoration;
    expect(decoration.color, PaperTheme.popupBackground);
    final card = tester.getRect(cardFinder);
    final overlap = card.intersect(frame);
    expect(overlap.isEmpty, isFalse);
    final tap = overlap.center;
    final expected = VedicChartGeometry(
      style: IndianChartStyle.north,
      ascendantSign: 0,
    ).hitTest(
      Offset(
        (tap.dx - frame.left) / frame.width,
        (tap.dy - frame.top) / frame.height,
      ),
    )!;
    await tester.tapAt(tap);
    await tester.pumpAndSettle();
    expect(selected, [expected.sign]);
    await _closeDetails(tester);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(_hoverDetails, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('South empty center and outer inset pass taps through', (
    tester,
  ) async {
    var backgroundTaps = 0;
    final selected = <int>[];
    await tester.pumpWidget(
      _chartApp(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => backgroundTaps++,
                child: const SizedBox.expand(),
              ),
            ),
            VedicChartView(
              placements: _placements,
              ascendant: 1,
              style: IndianChartStyle.south,
              centerLabel: 'Natal chart',
              onSignSelected: selected.add,
            ),
          ],
        ),
      ),
    );
    await tester.tapAt(_chartPoint(tester, const Offset(0.5, 0.5)));
    await tester.tapAt(tester.getTopLeft(_canvas) + const Offset(1, 1));
    await tester.pump();
    expect(backgroundTaps, 2);
    expect(selected, isEmpty);
    expect(_details, findsNothing);
    await tester.tapAt(_chartPoint(tester, _southCenters.first));
    await tester.pumpAndSettle();
    expect(selected, [0]);
    expect(backgroundTaps, 2);
    await _closeDetails(tester);
  });

  for (final style in IndianChartStyle.values) {
    testWidgets('${style.name} maps both planets and ascendant through D-9', (
      tester,
    ) async {
      final selected = <int>[];
      await tester.pumpWidget(
        _chartApp(
          child: VedicChartView(
            placements: const [
              VedicPlacement(
                name: 'Sun',
                shortName: 'Su',
                body: VedicBody.sun,
                longitude: 13,
              ),
              VedicPlacement(name: 'Lagna', shortName: 'As', longitude: 33),
            ],
            ascendant: 33,
            division: 9,
            style: style,
            onSignSelected: selected.add,
          ),
        ),
      );
      // 33° is D-1 Taurus, but D-9 Capricorn (9). 13° becomes Cancer (3).
      final ascendantCenter =
          style == IndianChartStyle.north ? _northCenters[0] : _southCenters[9];
      final sunCenter =
          style == IndianChartStyle.north ? _northCenters[6] : _southCenters[3];
      await tester.tapAt(_chartPoint(tester, ascendantCenter));
      await tester.pumpAndSettle();
      expect(selected.last, 9);
      expect(find.text('Ascendant (Lagna)'), findsOneWidget);
      expect(find.text('Lagna'), findsNothing);
      expect(find.text(formatZodiacLongitude(33)), findsOneWidget);
      expect(find.text('Sun'), findsNothing);
      await _closeDetails(tester);

      await tester.tapAt(_chartPoint(tester, sunCenter));
      await tester.pumpAndSettle();
      expect(selected.last, 3);
      expect(find.text('Sun'), findsOneWidget);
      expect(find.text(formatZodiacLongitude(13)), findsOneWidget);
      expect(find.textContaining('signs use D-9.'), findsOneWidget);
      await _closeDetails(tester);
    });

    testWidgets('${style.name} bindus remain sign-indexed and interactive', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        final points = List.generate(12, (sign) => sign * 2 + 1);
        final selected = <int>[];
        await tester.pumpWidget(
          _chartApp(
            child: VedicChartView(
              placements: _placements,
              ascendant: 61,
              style: style,
              bindus: points,
              onSignSelected: selected.add,
            ),
          ),
        );
        final nodes = _semanticsBelow(tester.getSemantics(_canvas))
            .map((node) => node.getSemanticsData())
            .toList();
        for (var sign = 0; sign < 12; sign++) {
          final label =
              '${zodiacNames[sign]} · House ${(sign - 2 + 12) % 12 + 1}';
          final data = nodes.singleWhere((node) => node.label == label);
          expect(data.value, contains('${points[sign]} bindus'));
        }
        final pisces = style == IndianChartStyle.north
            ? _northCenters[9]
            : _southCenters[11];
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(_chartPoint(tester, pisces));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 410));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(_hoverDetails).data, contains('23 bindus'));
        final palette = AstrologyPalette.of(tester.element(_canvas));
        final paintPattern = paints;
        final precedingCells = style == IndianChartStyle.north ? 9 : 11;
        for (var cell = 0; cell < precedingCells; cell++) {
          paintPattern.path();
        }
        expect(
          tester.renderObject(_canvas),
          paintPattern..path(color: palette.hover),
        );
        await tester.tapAt(_chartPoint(tester, pisces));
        await tester.pumpAndSettle();
        expect(selected, [11]);
        expect(find.text('23 bindus'), findsOneWidget);
        await _closeDetails(tester);
        await mouse.removePointer();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('${style.name} fits the smaller bounded axis without flex', (
      tester,
    ) async {
      for (final size in [
        const Size(280, 500),
        const Size(500, 280),
        const Size(500, 500),
        const Size(160, 90),
      ]) {
        await tester.pumpWidget(
          _chartApp(
            size: size,
            child: VedicChartView(
              placements: _placements,
              ascendant: 1,
              style: style,
              centerLabel: 'A long chart title that must stay within its seal',
            ),
          ),
        );
        expect(tester.getSize(_canvas), Size.square(size.shortestSide));
        expect(tester.takeException(), isNull, reason: '$style at $size');
      }
      await tester.pumpWidget(
        _chartApp(
          size: const Size(280, 500),
          child: SingleChildScrollView(
            child: VedicChartView(
              placements: _placements,
              ascendant: 1,
              style: style,
            ),
          ),
        ),
      );
      expect(tester.getSize(_canvas), const Size.square(280));
      await tester.pumpWidget(
        _chartApp(
          size: const Size(500, 500),
          child: UnconstrainedBox(
            child: VedicChartView(
              placements: _placements,
              ascendant: 1,
              style: style,
            ),
          ),
        ),
      );
      expect(tester.getSize(_canvas), const Size.square(360));
      expect(tester.takeException(), isNull);
    });

    testWidgets('${style.name} crowded conjunctions keep full accessible data',
        (
      tester,
    ) async {
      final crowded = [
        for (final body in VedicBody.values)
          VedicPlacement(
            // Deliberately abbreviated name: details must use the body name.
            name: body.shortName,
            shortName: body.shortName,
            body: body,
            longitude: 7.5,
            speed: body == VedicBody.saturn ? -0.1 : 0.1,
          ),
        const VedicPlacement(
          name: 'A special lagna with a deliberately long descriptive name',
          shortName: 'LongAbbreviation',
          longitude: 7.5,
        ),
      ];
      for (final side in [280.0, 360.0, 500.0]) {
        for (final scale in [1.0, 1.6, 2.0]) {
          await tester.pumpWidget(
            _chartApp(
              size: Size.square(side),
              textScaler: TextScaler.linear(scale),
              child: VedicChartView(
                placements: crowded,
                ascendant: 331,
                style: style,
              ),
            ),
          );
          expect(tester.getSize(_canvas), Size.square(side));
          expect(tester.takeException(), isNull);
        }
      }
      // Aries is a small North triangle, not the roomy ascendant diamond.
      final point =
          style == IndianChartStyle.north ? _northCenters[1] : _southCenters[0];
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(_chartPoint(tester, point));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 410));
      await tester.pumpAndSettle();
      final listing = tester.widget<Text>(_hoverDetails).data!;
      for (final body in VedicBody.values) {
        expect(listing, contains(body.label));
      }
      expect(listing, contains(crowded.last.name));
      await tester.tapAt(_chartPoint(tester, point));
      await tester.pumpAndSettle();
      for (final body in VedicBody.values) {
        expect(find.text(body.label), findsOneWidget);
      }
      expect(find.text('Retrograde'), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('vedic-sign-detail-scroll')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(find.text(crowded.last.name), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The close button scrolls with the content; Escape/back stays native.
      Navigator.of(tester.element(_details)).pop();
      await tester.pumpAndSettle();
      await mouse.removePointer();
      await tester.pumpAndSettle();
    });
  }

  testWidgets('paper, light and dark surfaces work without AppFlowyTheme', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final paper in [false, true]) {
        await tester.pumpWidget(
          _chartApp(
            brightness: brightness,
            paper: paper,
            child: const VedicChartView(placements: _placements, ascendant: 1),
          ),
        );
        final context = tester.element(_canvas);
        final theme = Theme.of(context);
        final palette = AstrologyPalette.of(context);
        expect(
          palette.surface,
          EditorSurfaceStyle.previewBackgroundFor(
            brightness,
            theme.colorScheme.surface,
            isPaper: paper,
          ),
        );
        expect(
          tester.renderObject(_canvas),
          paints..rrect(color: palette.surface),
        );
        if (paper && brightness == Brightness.light) {
          expect(palette.raised, PaperTheme.popupBackground);
          expect(palette.control, PaperTheme.controlBackground);
          expect(palette.hover, PaperTheme.controlHover);
          expect(palette.selection, PaperTheme.controlSelectedHover);
          for (final color in [
            palette.surface,
            palette.raised,
            palette.control,
            palette.hover,
            palette.selection,
          ]) {
            expect(color.r, greaterThan(color.b));
          }
        } else {
          expect(palette.surface, theme.colorScheme.surface);
          expect(palette.raised, theme.colorScheme.surfaceContainerLow);
          expect(palette.control, theme.colorScheme.surfaceContainer);
        }
        expect(palette.planetColor(null), palette.accent);
        for (final body in VedicBody.values) {
          expect(
            _contrast(palette.planetColor(body), palette.surface),
            greaterThanOrEqualTo(4.5),
          );
        }
        await tester.tapAt(_chartPoint(tester, _northCenters.first));
        await tester.pumpAndSettle();
        expect(tester.widget<Dialog>(_details).backgroundColor, palette.raised);
        final surfaces = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: _details,
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .map((decoration) => decoration.color);
        expect(surfaces, contains(palette.control));
        await _closeDetails(tester);
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('premium tokens are used, but cannot cool a paper surface', (
    tester,
  ) async {
    final appTheme = AppTheme.fallback;
    final premium = PremiumTheme.resolve(
      appTheme: appTheme,
      legacy: appTheme.lightTheme,
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xFFF8EEDB),
      floatingSurface: const Color(0xFFFCF3E3),
      mutedSurface: const Color(0xFFECE0CD),
    );
    for (final paper in [false, true]) {
      await tester.pumpWidget(
        _chartApp(
          theme: ThemeData(
            extensions: [premium, PaperThemeExtension(enabled: paper)],
          ),
          child: const VedicChartView(placements: _placements, ascendant: 1),
        ),
      );
      final palette = AstrologyPalette.of(tester.element(_canvas));
      expect(
        palette.surface,
        paper ? PaperTheme.editorPreviewBackground : premium.surface,
      );
      expect(
        palette.raised,
        paper ? PaperTheme.popupBackground : premium.floatingSurface,
      );
      expect(
        palette.control,
        paper ? PaperTheme.controlBackground : premium.mutedSurface,
      );
      expect(palette.ink, paper ? PaperTheme.textPrimary : premium.textPrimary);
      expect(palette.accent, paper ? PaperTheme.accent : premium.accent);
      expect(palette.line, paper ? PaperTheme.codeBlockBorder : premium.border);
      expect(palette.hover, paper ? PaperTheme.controlHover : premium.hover);
      expect(
        palette.selection,
        paper ? PaperTheme.controlSelectedHover : premium.selected,
      );
    }
  });

  testWidgets('rejects incomplete bindus and accepts zero available height', (
    tester,
  ) async {
    await tester.pumpWidget(
      _chartApp(
        child: VedicChartView(
          placements: const [],
          ascendant: 0,
          bindus: List.filled(11, 0),
        ),
      ),
    );
    expect(tester.takeException(), isArgumentError);
    await tester.pumpWidget(
      _chartApp(
        size: const Size(280, 0),
        child: const VedicChartView(placements: [], ascendant: 0),
      ),
    );
    expect(_canvas, findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _chartApp({
  required Widget child,
  Size size = const Size.square(360),
  Brightness brightness = Brightness.light,
  bool paper = false,
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  FontWeight weight = FontWeight.w400,
}) =>
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: theme ??
          ThemeData(
            brightness: brightness,
            extensions: [PaperThemeExtension(enabled: paper)],
          ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: DefaultTextStyle.merge(
            style: TextStyle(fontWeight: weight),
            child: SizedBox.fromSize(size: size, child: child),
          ),
        ),
      ),
    );

Offset _chartPoint(WidgetTester tester, Offset normalized) {
  final rect = VedicChartGeometry.chartBounds(tester.getSize(_canvas));
  return tester.getTopLeft(_canvas) + VedicChartCell.pointIn(normalized, rect);
}

TextStyle _chartTextStyle(BuildContext context) =>
    (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).merge(
      DefaultTextStyle.of(context).style,
    );

TextStyle _activeChartFont(String family, FontWeight weight) =>
    AppTextRendering.rootStyleFor(Brightness.light).copyWith(
      fontFamily: family,
      fontFamilyFallback: const ['Ahem'],
      fontSize: 14,
      fontWeight: weight,
      fontVariations: flowyFontVariationsForWeight(weight),
      // The canvas inherits bodyMedium's tracking before choosing cell sizes.
      letterSpacing: 14 * defaultLetterSpacing,
    );

VedicChartCenterLayout _centerLayout(WidgetTester tester) {
  final view = tester.widget<VedicChartView>(find.byType(VedicChartView));
  final context = tester.element(_canvas);
  return VedicChartCenterLayout(
    bounds: VedicChartGeometry.chartBounds(tester.getSize(_canvas)),
    style: view.style,
    division: view.division,
    ascendantSign: divisionalSign(view.ascendant, view.division),
    palette: AstrologyPalette.of(context),
    textStyle: _chartTextStyle(context),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: Directionality.of(context),
    centerLabel: view.centerLabel,
  );
}

void _expectRectInside(Rect inner, Rect outer, String reason) {
  expect(inner.left, greaterThanOrEqualTo(outer.left), reason: reason);
  expect(inner.top, greaterThanOrEqualTo(outer.top), reason: reason);
  expect(inner.right, lessThanOrEqualTo(outer.right), reason: reason);
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom), reason: reason);
}

Future<ByteData> _rasterize(
  WidgetTester tester,
  Size size,
  void Function(Canvas) paint,
) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      paint(Canvas(recorder));
      final picture = recorder.endRecording();
      final image =
          await picture.toImage(size.width.ceil(), size.height.ceil());
      try {
        return (await image.toByteData())!;
      } finally {
        image.dispose();
        picture.dispose();
      }
    }))!;

Iterable<int> _pixelsIn(ByteData pixels, int width, Rect rect) sync* {
  for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
    for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
      yield pixels.getUint32((y * width + x) * 4);
    }
  }
}

List<Rect> _inkRows(ByteData pixels, int width) {
  final rows = <Rect>[];
  int? first;
  final height = pixels.lengthInBytes ~/ (width * 4);
  for (var y = 0; y <= height; y++) {
    var hasInk = false;
    if (y < height) {
      for (var x = 0; x < width && !hasInk; x++) {
        hasInk = pixels.getUint8((y * width + x) * 4 + 3) >= 32;
      }
    }
    if (hasInk) {
      first ??= y;
    } else if (first != null) {
      rows.add(
          Rect.fromLTRB(0, first.toDouble(), width.toDouble(), y.toDouble()));
      first = null;
    }
  }
  return rows;
}

List<Rect> _inkComponentsIn(ByteData pixels, int width, Rect rect) {
  final left = rect.left.floor();
  final right = rect.right.ceil();
  final top = rect.top.floor();
  final bottom = rect.bottom.ceil();
  final visited = <int>{};
  final components = <Rect>[];
  // Keep the existing cutoff for faint underprint and antialias fringe.
  bool isInk(int pixel) => pixels.getUint8(pixel * 4 + 3) >= 32;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final origin = y * width + x;
      if (!isInk(origin) || !visited.add(origin)) continue;
      final pending = [origin];
      var bounds = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
      while (pending.isNotEmpty) {
        final pixel = pending.removeLast();
        final px = pixel % width;
        final py = pixel ~/ width;
        bounds = bounds.expandToInclude(
          Rect.fromLTWH(px.toDouble(), py.toDouble(), 1, 1),
        );
        // Eight-connected ink preserves diagonal and curved glyph strokes.
        for (var ny = py - 1; ny <= py + 1; ny++) {
          if (ny < top || ny >= bottom) continue;
          for (var nx = px - 1; nx <= px + 1; nx++) {
            if (nx < left || nx >= right) continue;
            final neighbour = ny * width + nx;
            if (isInk(neighbour) && visited.add(neighbour)) {
              pending.add(neighbour);
            }
          }
        }
      }
      components.add(bounds);
    }
  }
  return components..sort((a, b) => a.left.compareTo(b.left));
}

int _pixelAt(ByteData pixels, int width, Offset point) =>
    pixels.getUint32((point.dy.floor() * width + point.dx.floor()) * 4);

int _rgba(Color color) {
  int channel(double value) => (value.clamp(0.0, 1.0) * 255).round();
  return (channel(color.r) << 24) |
      (channel(color.g) << 16) |
      (channel(color.b) << 8) |
      channel(color.a);
}

Future<void> _closeDetails(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Close sign details'));
  await tester.pumpAndSettle();
}

double _area(VedicChartCell cell) {
  var twiceArea = 0.0;
  for (var index = 0; index < cell.vertices.length; index++) {
    final a = cell.vertices[index];
    final b = cell.vertices[(index + 1) % cell.vertices.length];
    twiceArea += a.dx * b.dy - b.dx * a.dy;
  }
  return twiceArea.abs() / 2;
}

Iterable<SemanticsNode> _semanticsBelow(SemanticsNode node) sync* {
  yield node;
  final children = <SemanticsNode>[];
  node.visitChildren((child) {
    children.add(child);
    return true;
  });
  for (final child in children) {
    yield* _semanticsBelow(child);
  }
}

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}
