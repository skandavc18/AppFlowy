import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _appearances = ['light', 'dark', 'paper'];
const _size = Size(400, 280);
const _ink = Color(0xFF367CBB);
const _categories = ['Alpha', 'Beta', 'Gamma'];
const _revenue = ChartSeries(
  name: 'Revenue',
  points: [
    ChartPoint(label: 'Alpha', value: 4, x: 2, size: 4),
    ChartPoint(label: 'Beta', value: 4, x: 5, size: 9),
    ChartPoint(label: 'Gamma', value: 4, x: 8, size: 16),
  ],
);
const _costs = ChartSeries(
  name: 'Costs',
  points: [
    ChartPoint(label: 'Alpha', value: 2, x: 2, size: 4),
    ChartPoint(label: 'Beta', value: 2, x: 5, size: 9),
    ChartPoint(label: 'Gamma', value: 2, x: 8, size: 16),
  ],
);
const _negativeCosts = ChartSeries(
  name: 'Costs',
  points: [
    ChartPoint(label: 'Alpha', value: -2),
    ChartPoint(label: 'Beta', value: -2),
    ChartPoint(label: 'Gamma', value: -2),
  ],
);

ChartSpec _spec(ChartType type) => ChartSpec(
      type: type,
      categoryColumn: 'Category',
      valueColumns: const ['Revenue', 'Costs'],
      xColumn: type.drawsPoints ? 'X' : null,
      sizeColumn: type.sizesPoints ? 'Size' : null,
      palette: ChartPaletteName.ocean,
      colors: const {'Revenue': 0xFF367CBB, 'Alpha': 0xFF367CBB},
      showGrid: false,
      showLegend: false,
    );

ChartData _data(
  ChartType type, {
  List<ChartSeries> series = const [_revenue],
  bool measured = false,
}) =>
    ChartData(
      categories: _categories,
      series: series,
      minimum: 0,
      maximum: 8,
      xMaximum: 10,
      sizeMaximum: 16,
      measuresX: type.drawsPoints || measured,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontFetching = GoogleFonts.config.allowRuntimeFetching;
  final families = <String>{'DM Sans'};
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final appearance in _appearances) {
      families.add(_theme(appearance).textTheme.bodyMedium!.fontFamily!);
    }
    // Use the same checked-in font as the integrated chart goldens, including
    // the aliases used by the actual desktop themes. Never fetch a test font.
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);

  for (final appearance in _appearances) {
    for (final type in ChartType.values) {
      testWidgets('$appearance ${type.name}: local shadow pixels at DPR 1/2',
          (tester) async {
        final palette = await _palette(tester, appearance);
        expect(families, contains(palette.baseTextStyle.fontFamily));
        final shadow = ChartMarkShadow.of(palette);
        expect(shadow.blurSigma, 1.2);
        expect(shadow.offset, const Offset(0, 1));
        expect(shadow.color.a, greaterThan(0));
        expect(shadow.color.a, lessThanOrEqualTo(palette.isDark ? 0.14 : 0.10));
        expect(shadow.color.r, palette.shadow.r);
        expect(shadow.color.g, palette.shadow.g);
        expect(shadow.color.b, palette.shadow.b);
        if (appearance == 'paper') {
          expect(palette.background, PaperTheme.editorBackground);
          expect(palette.shadow, PaperTheme.shadow);
          expect(shadow.color.r, greaterThan(shadow.color.b));
        }

        final data = _data(type);
        final spec = _spec(type);
        for (final dpr in [1.0, 2.0]) {
          final flat = await _render(
            tester,
            _withoutShadow(palette),
            type,
            data: data,
            spec: spec,
            dpr: dpr,
          );
          final raised = await _render(
            tester,
            palette,
            type,
            data: data,
            spec: spec,
            dpr: dpr,
          );
          final halo = _halo(type, raised);
          expect(flat.alphaSum(halo), 0, reason: 'Probe is outside the mark.');
          expect(
            raised.alphaSum(halo),
            greaterThan(0),
            reason: '$type at $dpr',
          );
          expect(
            raised.maxAlpha(halo),
            lessThanOrEqualTo((shadow.color.a * 255).ceil() + 1),
            reason: 'A local shadow must stay below its already quiet ink.',
          );
          final meanAlpha =
              raised.alphaSum(halo) / raised.indices(halo).length / 255;
          expect(meanAlpha, inExclusiveRange(0, shadow.color.a / 2));
          debugPrint(
            'MARK_SHADOW $appearance ${type.name} DPR=$dpr '
            'ink=${shadow.color.a.toStringAsFixed(4)} '
            'mean=${meanAlpha.toStringAsFixed(4)} '
            'peak=${raised.maxAlpha(halo)}/255',
          );
          if (appearance == 'paper' && type == ChartType.bar) {
            final plot = _plot(palette, type, _size);
            final foot = Rect.fromLTWH(
              raised.hits.first.anchor.dx - 8,
              (plot.bottom * dpr).ceil() / dpr,
              16,
              4,
            );
            expect(flat.alphaSum(foot), 0);
            var red = 0;
            var blue = 0;
            for (final index in raised.indices(foot)) {
              red += raised.bytes[index];
              blue += raised.bytes[index + 2];
            }
            expect(
              red,
              greaterThan(blue),
              reason: 'Warm shadow pixels, not black.',
            );
          }
          _expectClearCorners(raised);
          _expectSameHits(raised, flat);
          _expectFixtureGeometry(raised, type);
          _expectSamePixels(raised, flat, bounds: _interior(type, raised));
          _expectChosenInk(raised, type);
          expect(identical(raised.painter.data, data), isTrue);
          expect(identical(raised.painter.spec, spec), isTrue);
          expect(raised.painter.colors.at(0, 'Revenue'), _ink);
          expect(raised.painter.colors.at(0, 'Alpha'), _ink);
          expect(
            raised.painter.colors.at(1, 'Costs'),
            palette.withSet(ChartPaletteName.ocean).colorAt(1),
          );
          expect(
            raised.painter.shouldRepaint(flat.painter),
            isTrue,
            reason: 'Shadow-only theme changes must invalidate the painter.',
          );
        }
      });

      testWidgets(
          '$appearance ${type.name}: hidden/reveal/focus leave no ghosts',
          (tester) async {
        final palette = await _palette(tester, appearance);
        final flatPalette = _withoutShadow(palette);
        final rest = await _render(tester, palette, type);
        final probe = _halo(type, rest);
        final hidden = await _render(tester, palette, type, hidden: {0});
        expect(hidden.hits, isEmpty);
        expect(hidden.alphaSum(hidden.bounds), 0);

        final zero = await _render(tester, palette, type, progress: 0);
        final flatZero = await _render(tester, flatPalette, type, progress: 0);
        // Axis text and the donut's existing centre caption are not shadows.
        _expectSamePixels(zero, flatZero);
        expect(zero.hits, isEmpty);

        final partial = await _render(tester, palette, type, progress: 0.1);
        final flatPartial = await _render(
          tester,
          flatPalette,
          type,
          progress: 0.1,
        );
        _expectSameHits(partial, flatPartial);
        _expectClearCorners(partial);
        expect(
          partial.alphaSum(probe),
          0,
          reason: 'No shadow at the final extent of an unrevealed mark.',
        );

        // A real second series receives focus; the probe stays next to the
        // first series, away from the second series' geometry.
        final multi = _data(type, series: const [_revenue, _costs]);
        final full = await _render(tester, palette, type, data: multi);
        final muted = await _render(
          tester,
          palette,
          type,
          data: multi,
          focusedSeries: 1,
          emphasis: 1,
        );
        final flatMuted = await _render(
          tester,
          flatPalette,
          type,
          data: multi,
          focusedSeries: 1,
          emphasis: 1,
        );
        final focusProbe = _focusHalo(type, full);
        expect(flatMuted.alphaSum(focusProbe), 0);
        expect(full.alphaSum(focusProbe), greaterThan(0));
        expect(
          muted.alphaSum(focusProbe),
          lessThan(full.alphaSum(focusProbe)),
          reason: 'A muted series must not retain a full-strength shadow.',
        );
        _expectSameHits(muted, full);
        _expectSameHits(muted, flatMuted);

        // Hiding one series must not change the remaining series' palette
        // index, data, geometry or hit ordering. Compare with a data set that
        // never contained it, keeping the same axis domain.
        final onlyRevenue = await _render(
          tester,
          palette,
          type,
          data: multi,
          hidden: {1},
        );
        _expectSamePixels(onlyRevenue, rest);
        _expectSameHits(onlyRevenue, rest);

        final onlyCosts = await _render(
          tester,
          palette,
          type,
          data: multi,
          hidden: {0},
        );
        expect(onlyCosts.hits.every((hit) => hit.seriesIndex == 1), isTrue);
        expect(
          onlyCosts.painter.colors.at(1, 'Costs'),
          palette.withSet(ChartPaletteName.ocean).colorAt(1),
        );
        if (!type.isCircular) {
          expect(
            onlyCosts.alphaSum(focusProbe),
            0,
            reason: 'The removed first series leaves no shadow behind.',
          );
        }

        final hover = await _render(
          tester,
          palette,
          type,
          highlight: rest.hits.first,
          emphasis: 1,
        );
        final flatHover = await _render(
          tester,
          flatPalette,
          type,
          highlight: rest.hits.first,
          emphasis: 1,
        );
        _expectSameHits(hover, flatHover);
        _expectSamePixels(hover, flatHover, bounds: _interior(type, hover));
        _expectClearCorners(hover);
      });

      testWidgets(
          '$appearance ${type.name}: finite narrow/zoomed clips at DPR 1/2',
          (tester) async {
        final palette = await _palette(tester, appearance);
        for (final dpr in [1.0, 2.0]) {
          for (final size in [const Size(60, 60), const Size(180, 80)]) {
            const viewport = ChartViewport(scale: 8, offset: 0.43);
            final raised = await _render(
              tester,
              palette,
              type,
              size: size,
              dpr: dpr,
              viewport: viewport,
            );
            final flat = await _render(
              tester,
              _withoutShadow(palette),
              type,
              size: size,
              dpr: dpr,
              viewport: viewport,
            );
            _expectSameHits(raised, flat);
            for (final hit in raised.hits) {
              expect(hit.anchor.dx.isFinite && hit.anchor.dy.isFinite, isTrue);
              expect(hit.rect.isFinite, isTrue);
            }
            final clip = type.isCircular
                ? Rect.fromCircle(
                    center: size.center(Offset.zero),
                    radius: math.min(size.width, size.height) / 2 - 12,
                  ).inflate(6)
                : _plot(palette, type, size).inflate(9);
            _expectSamePixels(
              raised,
              flat,
              // clipRect is antialiased: a pixel centred on the bottom edge
              // still has half its area inside. Require exact equality for
              // every pixel whose entire physical footprint is outside.
              where: (point) => !clip.overlaps(
                Rect.fromCenter(center: point, width: 1 / dpr, height: 1 / dpr),
              ),
              reason: 'Shadows stay inside the existing local paint bounds: '
                  '$size DPR=$dpr clip=$clip.',
            );
          }
        }
      });
    }

    for (final type in [ChartType.stackedBar, ChartType.stackedArea]) {
      testWidgets('$appearance ${type.name}: no darkening at muted stack seams',
          (tester) async {
        final palette = await _palette(tester, appearance);
        final plot = _plot(palette, type, _size);
        for (final negative in [false, true]) {
          final data = _data(
            type,
            series: [_revenue, negative ? _negativeCosts : _costs],
          );
          for (final focus in <int?>[null, 1]) {
            final raised = await _render(
              tester,
              palette,
              type,
              data: data,
              focusedSeries: focus,
              emphasis: 1,
              dpr: 2,
            );
            final flat = await _render(
              tester,
              _withoutShadow(palette),
              type,
              data: data,
              focusedSeries: focus,
              emphasis: 1,
              dpr: 2,
            );
            final first = raised.hits.first;
            final lineY = negative
                ? plot.bottom - plot.height * 0.2
                : first.anchor.dy +
                    (type.fillsArea ? ChartMetrics.pointHoverRadius : 0);
            final centreX = type.fillsArea
                ? (first.anchor.dx + raised.hits[1].anchor.dx) / 2
                : first.anchor.dx;
            _expectSamePixels(
              raised,
              flat,
              bounds: Rect.fromCenter(
                center: Offset(centreX, lineY),
                width: 20,
                height: 10,
              ),
              reason: 'No shadow inside stacked ink (negative=$negative).',
            );
            _expectSameHits(raised, flat);
          }
        }
      });

      testWidgets('$appearance ${type.name}: positive and negative silhouettes',
          (tester) async {
        final palette = await _palette(tester, appearance);
        // The fixed -8..8 domain gives ticks -10,-5,0,5,10. Derive the
        // baseline and stack seam independently of the painter and its hits.
        const top = ChartMetrics.plotHeadroom;
        final bottom = _size.height -
            ChartMetrics.axisLabelSize -
            ChartMetrics.axisGap -
            4;
        final height = bottom - top;
        final zero = (top + bottom) / 2;
        for (final sign in [-1, 1]) {
          final data = ChartData(
            categories: _categories,
            series: [
              for (final series in [_revenue, _costs])
                ChartSeries(
                  name: series.name,
                  points: [
                    for (final point in series.points)
                      ChartPoint(label: point.label, value: point.value * sign),
                  ],
                ),
            ],
            minimum: -8,
            maximum: 8,
          );
          for (final focus in <int?>[null, 1]) {
            for (final dpr in [1.0, 2.0]) {
              final raised = await _render(
                tester,
                palette,
                type,
                data: data,
                focusedSeries: focus,
                emphasis: 1,
                dpr: dpr,
              );
              final flat = await _render(
                tester,
                _withoutShadow(palette),
                type,
                data: data,
                focusedSeries: focus,
                emphasis: 1,
                dpr: dpr,
              );
              final first = raised.hits.first;
              // Sample the downward exterior of a signed bar stack. A faint,
              // muted lateral blur can round below one alpha unit at DPR 1;
              // the displaced bottom edge still has measurable coverage.
              final foot = sign < 0 ? zero + height * 0.3 : zero;
              final halo = type.drawsBars
                  ? Rect.fromLTWH(
                      first.anchor.dx - 8,
                      (foot * dpr).ceil() / dpr,
                      16,
                      4,
                    )
                  : Rect.fromLTWH(
                      (raised.hits[2].anchor.dx * dpr).ceil() / dpr,
                      zero - sign * height * 0.1 - 5,
                      4,
                      10,
                    );
              expect(flat.alphaSum(halo), 0);
              expect(
                raised.alphaSum(halo),
                greaterThan(0),
                reason: 'Visible signed-stack shadow outside the foreground: '
                    'sign=$sign focus=$focus DPR=$dpr halo=$halo.',
              );
              expect(
                raised.maxAlpha(halo),
                lessThanOrEqualTo(
                  (ChartMarkShadow.of(palette).color.a * 255).ceil(),
                ),
              );
              _expectSamePixels(
                raised,
                flat,
                bounds: Rect.fromCenter(
                  center: Offset(
                    type.drawsBars
                        ? first.anchor.dx
                        : (first.anchor.dx + raised.hits[1].anchor.dx) / 2,
                    zero - sign * height * 0.2,
                  ),
                  width: 20,
                  height: 10,
                ),
                reason: 'A signed stack seam is foreground, not shadow: '
                    'sign=$sign focus=$focus DPR=$dpr.',
              );
              _expectSameHits(raised, flat);
            }
          }
        }
      });
    }

    for (final type in [ChartType.pie, ChartType.donut]) {
      testWidgets(
          '$appearance ${type.name}: one exterior silhouette, even on hover',
          (tester) async {
        final palette = await _palette(tester, appearance);
        const size = Size(96, 96);
        const centre = Offset(48, 48);
        const outer = 36.0;
        for (final dpr in [1.0, 2.0]) {
          _Raster? single;
          for (final count in [1, 3, 12]) {
            final data = _data(
              type,
              series: [
                ChartSeries(
                  name: 'Revenue',
                  points: [
                    for (var index = 0; index < count; index++)
                      ChartPoint(label: 'Part $index', value: 1),
                  ],
                ),
              ],
            );
            final image = await _render(
              tester,
              palette,
              type,
              data: data,
              size: size,
              dpr: dpr,
            );
            if (single == null) {
              single = image;
            } else {
              _expectSamePixels(
                image,
                single,
                where: (point) => (point - centre).distance > outer + 2,
                reason: 'More slices must not multiply the exterior shadow: '
                    'count=$count DPR=$dpr.',
              );
            }
            if (type == ChartType.donut) {
              _expectClearDisc(image, centre, outer * 0.58 - 1);
            }
          }

          final rest = await _render(tester, palette, type, dpr: dpr);
          // The second equal slice points down; its unchanged 6px hover lift
          // moves the silhouette and shadow together, not the hit rectangles.
          final hover = await _render(
            tester,
            palette,
            type,
            highlight: rest.hits[1],
            emphasis: 1,
            dpr: dpr,
          );
          final flatHover = await _render(
            tester,
            _withoutShadow(palette),
            type,
            highlight: rest.hits[1],
            emphasis: 1,
            dpr: dpr,
          );
          final shiftedHalo = _halo(type, rest).shift(const Offset(0, 6));
          expect(flatHover.alphaSum(shiftedHalo), 0);
          expect(hover.alphaSum(shiftedHalo), greaterThan(0));
          _expectSameHits(hover, rest);
          _expectSameHits(hover, flatHover);
          _expectSamePixels(hover, flatHover, bounds: _interior(type, rest));
          _expectClearCorners(hover);

          final partial = await _render(
            tester,
            palette,
            type,
            size: size,
            progress: 0.25,
            emphasis: 1,
            highlight: rest.hits[1],
            dpr: dpr,
          );
          expect(partial.alphaSum(const Rect.fromLTWH(4, 35, 12, 25)), 0);
          if (type == ChartType.donut) {
            // This small donut has no centre caption: every hole pixel must
            // really be transparent, not just painted in the page's colour.
            _expectClearDisc(partial, centre, outer * 0.58 - 1);
          }
        }
      });
    }

    testWidgets(
        '$appearance: dense and measured lines shadow the curve, not dots',
        (tester) async {
      final palette = await _palette(tester, appearance);
      for (final measured in [false, true]) {
        final data = ChartData(
          categories: [for (var index = 0; index < 60; index++) '$index'],
          series: [
            ChartSeries(
              name: 'Revenue',
              points: [
                for (var index = 0; index < 60; index++)
                  ChartPoint(label: '$index', value: 4, x: index / 6),
              ],
            ),
          ],
          minimum: 0,
          maximum: 8,
          xMaximum: 10,
          measuresX: measured,
        );
        final raised = await _render(
          tester,
          palette,
          ChartType.line,
          data: data,
          dpr: 2,
        );
        final flat = await _render(
          tester,
          _withoutShadow(palette),
          ChartType.line,
          data: data,
          dpr: 2,
        );
        final y = raised.hits[20].anchor.dy + ChartMetrics.pointHoverRadius;
        final x = raised.hits[20].anchor.dx;
        final probe = Rect.fromLTWH(x, y + 1.75, 40, 3);
        expect(flat.alphaSum(probe), 0);
        expect(raised.alphaSum(probe), greaterThan(0));
        _expectSameHits(raised, flat);
        _expectRawInk(raised, Offset(x + 10, y), _ink);
        // >40 points suppress all resting dots, so the 5.2px point halo is
        // absent above the stroke even at the point's own x coordinate.
        expect(flat.alphaAt(Offset(x, y - 4)), 0);
      }
    });

    testWidgets('$appearance: collapsed areas still shadow their visible line',
        (tester) async {
      final palette = await _palette(tester, appearance);
      for (final type in [ChartType.area, ChartType.stackedArea]) {
        final data = _data(
          type,
          series: [
            ChartSeries(
              name: 'Revenue',
              points: [
                for (final label in _categories)
                  ChartPoint(label: label, value: 0),
              ],
            ),
          ],
        );
        final raised = await _render(tester, palette, type, data: data, dpr: 2);
        final flat = await _render(
          tester,
          _withoutShadow(palette),
          type,
          data: data,
          dpr: 2,
        );
        final halo = _halo(ChartType.line, raised);
        expect(flat.alphaSum(halo), 0);
        expect(raised.alphaSum(halo), greaterThan(0));
        _expectSameHits(raised, flat);
        _expectSamePixels(
          raised,
          flat,
          bounds: _interior(ChartType.line, raised),
        );
      }
    });

    for (final type in [
      ChartType.line,
      ChartType.area,
      ChartType.stackedArea,
    ]) {
      testWidgets('$appearance ${type.name}: muted stroke interiors retain ink',
          (tester) async {
        final palette = await _palette(tester, appearance);
        for (final count in [3, 60]) {
          for (final dpr in [1.0, 2.0]) {
            final data = ChartData(
              categories: [
                for (var index = 0; index < count; index++) '$index',
              ],
              series: [
                for (final series in [_revenue, _costs])
                  ChartSeries(
                    name: series.name,
                    points: [
                      for (var index = 0; index < count; index++)
                        ChartPoint(
                          label: '$index',
                          value: series.points.first.value,
                        ),
                    ],
                  ),
              ],
              minimum: 0,
              maximum: 8,
            );
            final raised = await _render(
              tester,
              palette,
              type,
              data: data,
              focusedSeries: 1,
              emphasis: 1,
              dpr: dpr,
            );
            final flat = await _render(
              tester,
              _withoutShadow(palette),
              type,
              data: data,
              focusedSeries: 1,
              emphasis: 1,
              dpr: dpr,
            );
            final y = flat.hits.first.anchor.dy + ChartMetrics.pointHoverRadius;
            final x =
                (flat.hits.first.anchor.dx + flat.hits[count - 1].anchor.dx) /
                    2;
            // The pixel row containing the centre of a 2px stroke is wholly
            // covered at either DPR. Stay between sparse dots, not inside an
            // opaque point halo that would conceal a tinted, muted curve.
            final between = count == 3
                ? (flat.hits[0].anchor.dx + flat.hits[1].anchor.dx) / 2
                : x;
            final interior = Rect.fromLTWH(
              between - 8,
              (y * dpr).floor() / dpr,
              16,
              1 / dpr,
            );
            expect(flat.alphaSum(interior), greaterThan(0));
            _expectSamePixels(
              raised,
              flat,
              bounds: interior,
              reason: 'Muted curve ink must not composite over its shadow: '
                  'count=$count DPR=$dpr.',
            );
            _expectSameHits(raised, flat);
          }
        }
      });
    }

    testWidgets('$appearance: measured areas and negative/zero bars retain ink',
        (tester) async {
      final palette = await _palette(tester, appearance);
      for (final type in [
        ChartType.bar,
        ChartType.horizontalBar,
        ChartType.area,
      ]) {
        final data = type.fillsArea
            ? _data(type, measured: true)
            : ChartData(
                categories: _categories,
                series: const [
                  ChartSeries(
                    name: 'Revenue',
                    points: [
                      ChartPoint(label: 'Alpha', value: -4),
                      ChartPoint(label: 'Beta', value: 0),
                      ChartPoint(label: 'Gamma', value: 4),
                    ],
                  ),
                ],
                minimum: -4,
                maximum: 8,
              );
        final raised = await _render(tester, palette, type, data: data, dpr: 2);
        final flat = await _render(
          tester,
          _withoutShadow(palette),
          type,
          data: data,
          dpr: 2,
        );
        _expectSameHits(raised, flat);
        _expectClearCorners(raised);
        expect(_differentPixels(raised, flat), greaterThan(0));
        if (type.drawsBars) {
          final zero = raised.hits[1];
          _expectSamePixels(
            raised,
            flat,
            bounds: Rect.fromCenter(center: zero.anchor, width: 16, height: 16),
            reason: 'A zero-height/width bar must not cast a phantom shadow.',
          );
        } else {
          _expectSamePixels(raised, flat, bounds: _interior(type, raised));
          expect(raised.alphaSum(_halo(type, raised)), greaterThan(0));
        }
      }
    });

    testWidgets(
        '$appearance: translucent curved and measured strokes retain ink',
        (tester) async {
      final palette = await _palette(tester, appearance);
      final flatPalette = _withoutShadow(palette);
      final translucent = _spec(ChartType.line).copyWith(
        colors: const {'Revenue': 0x59367CBB},
      );
      final plot = _plot(palette, ChartType.line, _size).deflate(12);
      for (final count in [3, 60]) {
        for (final measured in [false, true]) {
          final data = ChartData(
            categories: [for (var index = 0; index < count; index++) '$index'],
            series: [
              ChartSeries(
                name: 'Revenue',
                points: [
                  for (var index = 0; index < count; index++)
                    ChartPoint(
                      label: '$index',
                      value: 2 + 4 * math.sin(index / (count - 1) * math.pi),
                      x: index / (count - 1) * 10,
                    ),
                ],
              ),
            ],
            minimum: 0,
            maximum: 8,
            xMaximum: 10,
            measuresX: measured,
          );
          for (final dpr in [1.0, 2.0]) {
            final coverage = await _render(
              tester,
              flatPalette,
              ChartType.line,
              data: data,
              dpr: dpr,
            );
            final flat = await _render(
              tester,
              flatPalette,
              ChartType.line,
              data: data,
              spec: translucent,
              dpr: dpr,
            );
            final raised = await _render(
              tester,
              palette,
              ChartType.line,
              data: data,
              spec: translucent,
              dpr: dpr,
            );
            // An opaque control locates fully covered stroke pixels on real
            // cubic curves, without reimplementing path geometry in the test.
            expect(
              coverage
                  .indices(plot)
                  .where((index) => coverage.bytes[index + 3] == 255)
                  .length,
              greaterThan(100),
            );
            _expectSamePixels(
              raised,
              flat,
              bounds: plot,
              where: (point) => coverage.alphaAt(point) == 255,
              reason: 'Translucent cubic interiors are unchanged: '
                  'count=$count measured=$measured DPR=$dpr.',
            );
            expect(
              _differentPixels(raised, flat, bounds: plot),
              greaterThan(0),
            );
            _expectSameHits(raised, flat);
          }
        }
      }
    });
  }

  testWidgets('paper-only theme extension still supplies warm mark shadow ink',
      (tester) async {
    late ChartPalette palette;
    await tester.pumpWidget(
      Theme(
        data: ThemeData.light().copyWith(
          extensions: const [PaperThemeExtension(enabled: true)],
        ),
        child: Builder(
          builder: (context) {
            palette = chartPaletteOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(palette.shadow, PaperTheme.shadow);
    expect(ChartMarkShadow.of(palette).color.r, greaterThan(0));
    expect(ChartMarkShadow.of(palette).color.b, lessThan(palette.shadow.r));
  });
}

ThemeData _theme(String appearance) => DesktopAppearance().getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );

Future<ChartPalette> _palette(WidgetTester tester, String appearance) async {
  late ChartPalette palette;
  await tester.pumpWidget(
    Theme(
      data: _theme(appearance),
      child: Builder(
        builder: (context) {
          expect(PaperTheme.isEnabled(context), appearance == 'paper');
          palette = chartPaletteOf(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return palette;
}

// An ordinary palette with transparent shadow ink is the control, not a
// renderer/debug switch. Every foreground paint operation still runs.
ChartPalette _withoutShadow(ChartPalette palette) => ChartPalette(
      background: palette.background,
      surface: palette.surface,
      grid: palette.grid,
      axis: palette.axis,
      label: palette.label,
      strongLabel: palette.strongLabel,
      series: palette.series,
      baseTextStyle: palette.baseTextStyle,
      shadow: palette.shadow.withValues(alpha: 0),
      border: palette.border,
      chip: palette.chip,
      chipHover: palette.chipHover,
      isDark: palette.isDark,
    );

Future<_Raster> _render(
  WidgetTester tester,
  ChartPalette palette,
  ChartType type, {
  ChartData? data,
  ChartSpec? spec,
  Size size = _size,
  double dpr = 1,
  double progress = 1,
  double emphasis = 0,
  Set<int> hidden = const {},
  int? focusedSeries,
  ChartHit? highlight,
  ChartViewport viewport = ChartViewport.identity,
}) async =>
    (await tester.runAsync(() async {
      final chartSpec = spec ?? _spec(type);
      final painter = ChartPainter(
        data: data ?? _data(type),
        spec: chartSpec,
        palette: palette,
        colors: ChartColors.of(palette, chartSpec),
        hidden: hidden,
        highlight: highlight,
        focusedSeries: focusedSeries,
        reveal: AlwaysStoppedAnimation(progress),
        emphasis: AlwaysStoppedAnimation(emphasis),
        viewport: viewport,
        crosshair: null,
        hits: [],
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(dpr);
      final saves = canvas.getSaveCount();
      ui.Picture? picture;
      ui.Image? image;
      try {
        painter.paint(canvas, size);
        expect(canvas.getSaveCount(), saves, reason: 'No leaked shadow clips.');
        picture = recorder.endRecording();
        image = await picture.toImage(
          (size.width * dpr).round(),
          (size.height * dpr).round(),
        );
        final bytes = (await image.toByteData())!;
        return _Raster(
          painter,
          size,
          dpr,
          image.width,
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      } finally {
        image?.dispose();
        picture?.dispose();
        if (recorder.isRecording) {
          recorder.endRecording().dispose();
        }
      }
    }))!;

class _Raster {
  const _Raster(this.painter, this.size, this.dpr, this.width, this.bytes);

  final ChartPainter painter;
  final Size size;
  final double dpr;
  final int width;
  final Uint8List bytes;

  List<ChartHit> get hits => painter.hits;
  Rect get bounds => Offset.zero & size;

  Iterable<int> indices(Rect rect) sync* {
    final clipped = rect.intersect(bounds);
    for (var y = (clipped.top * dpr).ceil();
        y < (clipped.bottom * dpr).floor();
        y++) {
      for (var x = (clipped.left * dpr).ceil();
          x < (clipped.right * dpr).floor();
          x++) {
        yield (y * width + x) * 4;
      }
    }
  }

  Offset pointAt(int index) => Offset(
        ((index ~/ 4) % width + 0.5) / dpr,
        ((index ~/ 4) ~/ width + 0.5) / dpr,
      );

  int indexAt(Offset point) =>
      ((point.dy * dpr).floor() * width + (point.dx * dpr).floor()) * 4;

  int alphaAt(Offset point) => bytes[indexAt(point) + 3];

  int alphaSum(Rect rect) =>
      indices(rect).fold(0, (sum, index) => sum + bytes[index + 3]);

  int maxAlpha(Rect rect) => indices(rect)
      .fold(0, (value, index) => math.max(value, bytes[index + 3]));
}

// This fixture's fixed domains produce ticks 0,2,...10 and 0,2.5,...12.5.
// Pin the public hit geometry independently of the renderer's private layout.
Rect _plot(ChartPalette palette, ChartType type, Size size) {
  var widest = 16.0;
  if (!type.isHorizontal) {
    for (final tick in ['0', '2', '4', '6', '8', '10']) {
      final text = TextPainter(
        text: TextSpan(
          text: tick,
          style: palette.text(size: ChartMetrics.axisLabelSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      widest = math.max(widest, text.width);
      text.dispose();
    }
  }
  return Rect.fromLTRB(
    widest + ChartMetrics.axisGap,
    math.min(ChartMetrics.plotHeadroom, size.height * 0.12),
    size.width - ChartMetrics.plotSideroom,
    size.height - ChartMetrics.axisLabelSize - ChartMetrics.axisGap - 4,
  );
}

void _expectFixtureGeometry(_Raster image, ChartType type) {
  expect(image.hits, hasLength(3));
  final plot = _plot(image.painter.palette, type, image.size);
  final centre = image.size.center(Offset.zero);
  final outer = math.min(image.size.width, image.size.height) / 2 - 12;
  final y = plot.bottom - plot.height * 0.4;
  for (var index = 0; index < 3; index++) {
    final hit = image.hits[index];
    expect(hit.seriesIndex, 0);
    expect(hit.pointIndex, index);
    late Offset anchor;
    late Rect rect;
    if (type.isCircular) {
      final middle = -math.pi / 2 + (index + 0.5) * math.pi * 2 / 3;
      final direction = Offset(math.cos(middle), math.sin(middle));
      anchor = centre + direction * (outer * 0.72);
      rect = Rect.fromCircle(
        center: centre + direction * (outer * 0.7),
        radius: math.max(outer * 0.22, 10),
      );
    } else if (type.drawsPoints) {
      final x = plot.left + [2, 5, 8][index] / 12.5 * plot.width;
      final radius = type.sizesPoints
          ? ChartMetrics.bubbleMinimumRadius +
              math.sqrt([4, 9, 16][index] / 16) *
                  (ChartMetrics.bubbleMaximumRadius -
                      ChartMetrics.bubbleMinimumRadius)
          : ChartMetrics.pointRadius + 0.6;
      anchor = Offset(x, y - radius);
      rect = Rect.fromCircle(center: Offset(x, y), radius: math.max(radius, 9));
    } else if (type.isHorizontal) {
      final span = plot.height / 3;
      final at = plot.top + span * (index + 0.5);
      anchor = Offset(plot.left + plot.width * 0.4, at);
      rect = Rect.fromLTRB(plot.left, at - span / 2, plot.right, at + span / 2);
    } else {
      final span = plot.width / 3;
      final x = plot.left + span * (index + 0.5);
      anchor =
          Offset(x, y - (type.drawsLine ? ChartMetrics.pointHoverRadius : 0));
      rect = type.drawsBars
          ? Rect.fromLTRB(x - span / 2, plot.top, x + span / 2, plot.bottom)
          : Rect.fromCircle(center: Offset(x, y), radius: 12);
    }
    expect((hit.anchor - anchor).distance, lessThan(0.000001));
    expect((hit.rect.topLeft - rect.topLeft).distance, lessThan(0.000001));
    expect(
      (hit.rect.bottomRight - rect.bottomRight).distance,
      lessThan(0.000001),
    );
  }
}

Rect _halo(ChartType type, _Raster image) {
  final first = image.hits.first;
  final plot = _plot(image.painter.palette, type, image.size);
  // Begin at the next whole physical pixel outside the known silhouette,
  // rather than accidentally sampling an antialiased foreground edge.
  double outside(double edge) => (edge * image.dpr).ceil() / image.dpr;
  if (type.isCircular) {
    final centre = image.size.center(Offset.zero);
    final outer = math.min(image.size.width, image.size.height) / 2 - 12;
    // Pie separators extend one pixel beyond the disc; the donut's stroke
    // stops at outer. This probe is clear in both foregrounds.
    return Rect.fromLTWH(
      centre.dx - 6,
      outside(centre.dy + outer + 1),
      12,
      4,
    );
  }
  if (type.drawsPoints) {
    final centre = first.rect.center;
    final radius = centre.dy - first.anchor.dy;
    final stroke = type.sizesPoints ? 0.6 : 0.5;
    return Rect.fromLTWH(
      centre.dx - 1.5,
      outside(centre.dy + radius + stroke),
      3,
      4,
    );
  }
  if (type.isHorizontal) {
    return Rect.fromLTWH(
      (plot.left + first.anchor.dx) / 2 - 5,
      outside(first.anchor.dy + ChartMetrics.maximumBarWidth / 2),
      10,
      4,
    );
  }
  if (type.drawsBars) {
    return Rect.fromLTWH(
      outside(first.anchor.dx + ChartMetrics.maximumBarWidth / 2),
      (first.anchor.dy + plot.bottom) / 2 - 5,
      4,
      10,
    );
  }
  final y = first.anchor.dy + ChartMetrics.pointHoverRadius;
  if (type.fillsArea) {
    return Rect.fromLTWH(
      outside(image.hits[2].anchor.dx),
      (y + plot.bottom) / 2 - 5,
      4,
      10,
    );
  }
  return Rect.fromLTWH(
    (first.anchor.dx + image.hits[1].anchor.dx) / 2 - 8,
    outside(y + ChartMetrics.lineWidth / 2),
    16,
    4,
  );
}

Rect _focusHalo(ChartType type, _Raster image) {
  final first = image.hits.first;
  final plot = _plot(image.painter.palette, type, image.size);
  if (type.fillsArea) {
    final y = first.anchor.dy + ChartMetrics.pointHoverRadius;
    // Above Costs' unstacked area and below its stacked area. In particular,
    // avoid the second series' endpoint dot at half of Revenue's height.
    return Rect.fromLTWH(
      (image.hits[2].anchor.dx * image.dpr).ceil() / image.dpr,
      y + (plot.bottom - y) * 0.25 - 5,
      4,
      10,
    );
  }
  if (!type.drawsBars) {
    return _halo(type, image);
  }
  final span = (type.isHorizontal ? plot.height : plot.width) / 3;
  final lanes = type.isStacked ? 1 : 2;
  final group = math.min(
    span * ChartMetrics.barGroupFill,
    ChartMetrics.maximumBarWidth * lanes +
        ChartMetrics.barInnerGap * (lanes - 1),
  );
  final width = (group - ChartMetrics.barInnerGap * (lanes - 1)) / lanes;
  // Use the outward side of the first grouped bar, not the gap between it
  // and the second bar. A neighbour's shadow should not mask a fading one.
  final left = ((first.anchor.dx - width / 2) * image.dpr).floor() / image.dpr;
  return type.isHorizontal
      ? Rect.fromLTWH(
          (first.anchor.dx * image.dpr).ceil() / image.dpr,
          first.anchor.dy - 2,
          4,
          4,
        )
      : Rect.fromLTWH(
          left - 3,
          first.anchor.dy + (plot.bottom - first.anchor.dy) * 0.25 - 5,
          3,
          10,
        );
}

Rect _interior(ChartType type, _Raster image) {
  final first = image.hits.first;
  final plot = _plot(image.painter.palette, type, image.size);
  if (type.isCircular) {
    final centre = image.size.center(Offset.zero);
    final point = centre + (first.anchor - centre) * (0.8 / 0.72);
    return Rect.fromCenter(center: point, width: 4, height: 4);
  }
  if (type.drawsPoints) {
    return Rect.fromCenter(center: first.rect.center, width: 4, height: 4);
  }
  if (type.drawsBars) {
    final point = first.anchor +
        (type.isHorizontal ? const Offset(-8, 0) : const Offset(0, 8));
    return Rect.fromCenter(center: point, width: 4, height: 4);
  }
  final y = first.anchor.dy + ChartMetrics.pointHoverRadius;
  if (type.fillsArea) {
    return Rect.fromLTRB(
      first.anchor.dx + 12,
      y + 12,
      image.hits[2].anchor.dx - 12,
      plot.bottom - 12,
    );
  }
  return Rect.fromCenter(
    center: Offset(first.anchor.dx, y),
    width: 4,
    height: 4,
  );
}

void _expectChosenInk(_Raster image, ChartType type) {
  var point = _interior(type, image).center;
  var ink = _ink;
  if (type.drawsLine) {
    point = image.hits.first.anchor +
        const Offset(0, ChartMetrics.pointHoverRadius);
  } else if (type.drawsPoints) {
    ink = ink.withValues(alpha: type.sizesPoints ? 0.55 : 0.9);
  }
  _expectRawInk(image, point, ink, tolerance: type.drawsBars ? 4 : 1);
}

void _expectRawInk(
  _Raster image,
  Offset point,
  Color ink, {
  int tolerance = 1,
}) {
  final index = image.indexAt(point);
  final expected = [ink.r * ink.a, ink.g * ink.a, ink.b * ink.a, ink.a];
  for (var channel = 0; channel < 4; channel++) {
    expect(
      image.bytes[index + channel],
      closeTo(expected[channel] * 255, tolerance),
    );
  }
}

void _expectClearCorners(_Raster image) {
  for (final point in [
    const Offset(3, 3),
    Offset(image.size.width - 4, 3),
    Offset(3, image.size.height - 4),
    Offset(image.size.width - 4, image.size.height - 4),
  ]) {
    expect(image.alphaAt(point), 0, reason: 'Page shows through at $point.');
  }
}

void _expectClearDisc(_Raster image, Offset centre, double radius) {
  var ink = 0;
  for (final index
      in image.indices(Rect.fromCircle(center: centre, radius: radius))) {
    if ((image.pointAt(index) - centre).distance < radius) {
      ink += image.bytes[index + 3];
    }
  }
  expect(ink, 0, reason: 'The donut hole contains no fill or inward shadow.');
}

void _expectSameHits(_Raster actual, _Raster expected) {
  // ChartHit.operator== intentionally compares only ids, not its geometry.
  expect(
    actual.hits
        .map((hit) => (hit.seriesIndex, hit.pointIndex, hit.rect, hit.anchor)),
    expected.hits
        .map((hit) => (hit.seriesIndex, hit.pointIndex, hit.rect, hit.anchor)),
  );
}

int _differentPixels(
  _Raster actual,
  _Raster expected, {
  Rect? bounds,
  bool Function(Offset)? where,
  int tolerance = 0,
}) {
  expect(actual.size, expected.size);
  expect(actual.dpr, expected.dpr);
  var changed = 0;
  for (final index in actual.indices(bounds ?? actual.bounds)) {
    if (where != null && !where(actual.pointAt(index))) {
      continue;
    }
    for (var channel = 0; channel < 4; channel++) {
      if ((actual.bytes[index + channel] - expected.bytes[index + channel])
              .abs() >
          tolerance) {
        changed++;
        break;
      }
    }
  }
  return changed;
}

void _expectSamePixels(
  _Raster actual,
  _Raster expected, {
  Rect? bounds,
  bool Function(Offset)? where,
  int tolerance = 0,
  String? reason,
}) {
  final changed = _differentPixels(
    actual,
    expected,
    bounds: bounds,
    where: where,
    tolerance: tolerance,
  );
  final samples = <String>[];
  if (changed > 0) {
    for (final index in actual.indices(bounds ?? actual.bounds)) {
      final point = actual.pointAt(index);
      if (where != null && !where(point)) {
        continue;
      }
      if (const [0, 1, 2, 3].any(
        (channel) =>
            (actual.bytes[index + channel] - expected.bytes[index + channel])
                .abs() >
            tolerance,
      )) {
        samples.add(
          '$point: ${actual.bytes.sublist(index, index + 4)} vs '
          '${expected.bytes.sublist(index, index + 4)}',
        );
        if (samples.length == 8) {
          break;
        }
      }
    }
  }
  expect(
    changed,
    0,
    reason: '${reason ?? 'Foreground pixels are unchanged by mark shadows.'}'
        '${samples.isEmpty ? '' : '\n${samples.join('\n')}'}',
  );
}
