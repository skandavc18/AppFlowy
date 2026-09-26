import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chart_appearance_test_support.dart';

const _hostSize = Size(320, 190);
const _readoutKey = ValueKey('chart-readout');
const _valueKey = ValueKey('chart-readout-value');
const _table = ChartTable(
  columns: ['Category', 'Revenue USD', 'Costs USD', 'Distance km'],
  columnIds: ['category', 'revenue', 'costs', 'units'],
  rows: [
    ['Northwest region', '-1234.5', '-300.25', '-6'],
    ['South', '234.75', '92', '-2'],
    ['East coast', '812.25', '210.5', '3'],
    ['West', '2486.75', '460', '9'],
  ],
);

void main() {
  setUpChartAppearanceFixtures();

  for (final appearance in chartAppearances) {
    for (final type in [
      ChartType.bar,
      ChartType.horizontalBar,
      ChartType.line,
      ChartType.stackedBar,
      ChartType.scatter,
    ]) {
      testWidgets(
        '$appearance ${type.name}: 320x190 / 2x readout excludes axes and zoom',
        (tester) async {
          final spec = chartAppearanceSpec(type);
          final data = buildChartData(_table, spec);
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          Widget app(Widget body) => chartAppearanceApp(
                appearance,
                body,
                textScale: 2,
                reducedMotion: true,
              );

          try {
            // Warm localization before mounting the real chart, as in the
            // shared appearance tests. No synthetic tooltip or minimum size.
            await tester.pumpWidget(app(const SizedBox()));
            await tester.pumpAndSettle();
            await tester.pumpWidget(
              app(
                Padding(
                  padding: const EdgeInsets.only(left: 37, top: 29),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox.fromSize(
                      size: _hostSize,
                      child: Builder(
                        builder: (context) => AppChart(
                          data: data,
                          spec: _table.displaySpec(spec),
                          interactionSpec: spec,
                          palette: chartPaletteOf(context),
                          animate: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.getSize(find.byType(AppChart)), _hostSize);
            expect(
              MediaQuery.textScalerOf(tester.element(chartAppearancePlot))
                  .scale(10),
              20,
            );
            for (var series = 0; series < data.series.length; series++) {
              expect(
                find.byKey(ValueKey(('chart-legend', false, series))),
                findsOneWidget,
              );
            }
            final size = tester.getSize(chartAppearancePlot);
            expect(size.height, lessThan(_hostSize.height));
            final origin = tester.getTopLeft(chartAppearancePlot);
            expect(origin.dx, greaterThan(0));
            expect(origin.dy, greaterThan(0));
            final zoom = find.descendant(
              of: find.byType(AppChart),
              matching: find.byType(PreviewToolbar),
            );
            expect(zoom, type.isHorizontal ? findsNothing : findsOneWidget);
            final localZoom = type.isHorizontal
                ? null
                : chartRenderedRect(tester, zoom).shift(-origin);
            final hits = List<ChartHit>.of(chartAppearancePainter(tester).hits);
            expect(hits, hasLength(8));
            final valuesRead = <double>[];
            await mouse.addPointer(location: const Offset(2, 2));

            for (final original in hits) {
              final before = chartAppearancePainter(tester);
              final hit = before.hits.firstWhere((hit) => hit == original);
              final beforePlot = before.plotBoundsFor(size);
              // A top-right dot can meet the zoom chrome. Use its exposed
              // hit region rather than hovering a button or skipping a mark.
              final position = [
                chartHitPosition(before, hit),
                Offset(hit.rect.center.dx, hit.rect.bottom - 1),
              ].firstWhere(
                (position) =>
                    hit.contains(position) &&
                    beforePlot.contains(position) &&
                    !(localZoom?.contains(position) ?? false),
              );
              expect(hit.contains(position), isTrue);
              expect(beforePlot.contains(position), isTrue);
              // Close line/scatter points may share hit regions. The last
              // painted matching mark, not an invented anchor, owns the read.
              final expected = before.hits.lastWhere(
                (candidate) => candidate.contains(position),
              );
              await mouse.moveTo(origin + position);
              await tester.pumpAndSettle();

              expect(find.byType(ChartTooltip), findsOneWidget);
              final tooltip =
                  tester.widget<ChartTooltip>(find.byType(ChartTooltip));
              expect(tooltip.hit, expected);
              expect(tooltip.emphasis.value, 1);
              final point =
                  data.series[expected.seriesIndex].points[expected.pointIndex];
              valuesRead.add(point.value);
              expect(
                tester.widget<Text>(find.byKey(_valueKey)).data,
                ChartPainter.formatValue(point.value),
              );

              final painter = chartAppearancePainter(tester);
              final localPlot = painter.plotBoundsFor(size);
              // The public bounds must exclude real axis gutters, not merely
              // echo the canvas and make the containment assertions vacuous.
              expect(localPlot.left, greaterThan(0));
              expect(localPlot.top, greaterThan(0));
              expect(localPlot.right, lessThan(size.width));
              expect(localPlot.bottom, lessThan(size.height));
              expect(tooltip.bounds, size);
              expect(tooltip.contentBounds, localPlot);
              final plot = localPlot.shift(origin);
              final readout = find.byKey(_readoutKey);
              expect(readout, findsOneWidget);
              final readoutBounds = chartRenderedRect(tester, readout);
              expectChartRectInside(readoutBounds, plot);
              expect(readoutBounds.width, greaterThan(40));
              expect(readoutBounds.height, greaterThan(12));

              // Inspect descendants through the FittedBox transform: a
              // correctly sized outer box must not conceal zero/tiny paint.
              final fitted = tester.widget<FittedBox>(readout);
              expectChartRectInside(
                chartRenderedRect(tester, find.byWidget(fitted.child!)),
                readoutBounds,
              );
              final valueBounds =
                  chartRenderedRect(tester, find.byKey(_valueKey));
              expect(valueBounds.width, greaterThan(8));
              expect(valueBounds.height, greaterThan(8));
              final ink = find.descendant(
                of: readout,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Text ||
                      widget.key == const ValueKey('chart-readout-swatch'),
                ),
              );
              expect(ink, findsWidgets);
              for (final element in ink.evaluate()) {
                final rendered =
                    chartRenderedRect(tester, find.byWidget(element.widget));
                expectChartRectInside(rendered, readoutBounds);
                expectChartRectInside(rendered, plot);
              }

              if (type.isHorizontal) {
                expect(zoom, findsNothing);
                expect(tooltip.avoidBounds, isNull);
              } else {
                expect(zoom, findsOneWidget);
                expect(tooltip.avoidBounds, isNotNull);
                final reserved = tooltip.avoidBounds!.shift(origin);
                final zoomBounds = chartRenderedRect(tester, zoom);
                expectChartRectInside(zoomBounds, reserved);
                final buttons = find.descendant(
                  of: zoom,
                  matching: find.byWidgetPredicate(
                    (widget) => widget is IconButton || widget is TextButton,
                  ),
                );
                expect(buttons, findsNWidgets(3));
                for (final button in buttons.evaluate()) {
                  expectChartRectInside(
                    chartRenderedRect(tester, find.byWidget(button.widget)),
                    reserved,
                  );
                }
                expect(readoutBounds.overlaps(reserved), isFalse);
                expect(readoutBounds.overlaps(zoomBounds), isFalse);
              }
              expect(tester.takeException(), isNull);
            }
            expect(valuesRead.any((value) => value < 0), isTrue);
            expect(valuesRead.any((value) => value > 0), isTrue);
          } finally {
            await mouse.removePointer();
            await tester.pumpWidget(const SizedBox());
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
