import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/shared/charts/chart_toolbar.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chart_appearance_test_support.dart';

const _sheet = ValueKey('rich-chart-reference');
const _types = [
  ChartType.bar,
  ChartType.donut,
  ChartType.horizontalBar,
  ChartType.stackedBar,
  ChartType.line,
  ChartType.area,
  ChartType.stackedArea,
  ChartType.scatter,
  ChartType.pie,
  ChartType.bubble,
];

// References intentionally require generation and visual review by the main
// validation run. No baseline is silently replaced by these tests.
void main() {
  setUpChartAppearanceFixtures();
  for (final appearance in chartAppearances) {
    testWidgets(
      '$appearance: rich charts, inline readouts and 320px/2x controls',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final sources = [
          for (final type in _types)
            ChartSource(
              viewId: 'appearance-${type.name}',
              loadTable: (_) async => chartAppearanceTable,
            ),
        ];
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await tester
              .pumpWidget(chartAppearanceApp(appearance, const SizedBox()));
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            chartAppearanceApp(
              appearance,
              Builder(
                builder: (context) => RepaintBoundary(
                  key: _sheet,
                  child: ColoredBox(
                    color: PremiumThemeExtension.of(context).canvas,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Charts / ${appearance.toUpperCase()}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Real table values · Transparent plots · Bar: 320px / 2× text',
                          ),
                          const SizedBox(height: 16),
                          for (var row = 0; row < 5; row++) ...[
                            if (row > 0) const SizedBox(height: 12),
                            SizedBox(
                              height: row == 0 ? 360 : 260,
                              child: Row(
                                children: [
                                  for (var column = 0;
                                      column < 2;
                                      column++) ...[
                                    if (column > 0) const SizedBox(width: 24),
                                    Expanded(
                                      child: _stage(
                                        context,
                                        sources[row * 2 + column],
                                        row * 2 + column,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(ChartStage), findsNWidgets(10));
          expect(find.byType(AppChart), findsNWidgets(10));
          // Touch keeps the first annotation while a mouse reads the donut;
          // both use real mark hit-testing, not synthetic tooltip content.
          final barPlot = _plot(ChartType.bar);
          final bar =
              tester.widget<CustomPaint>(barPlot).painter! as ChartPainter;
          final barHit = bar.hits
              .firstWhere((hit) => hit.seriesIndex == 0 && hit.pointIndex == 1);
          await tester.tapAt(tester.getTopLeft(barPlot) + barHit.rect.center);
          await tester.pump(kDoubleTapTimeout);
          await tester.pumpAndSettle();
          final donutPlot = _plot(ChartType.donut);
          final donut =
              tester.widget<CustomPaint>(donutPlot).painter! as ChartPainter;
          final donutHit = donut.hits.firstWhere((hit) => hit.pointIndex == 1);
          await mouse.addPointer(location: const Offset(2, 2));
          await mouse.moveTo(tester.getTopLeft(donutPlot) + donutHit.anchor);
          await tester.pumpAndSettle();
          expect(find.byType(ChartTooltip), findsNWidgets(2));
          for (final tooltip in find.byType(ChartTooltip).evaluate()) {
            final readout = find.descendant(
              of: find.byWidget(tooltip.widget),
              matching: find.byKey(const ValueKey('chart-readout')),
            );
            final type = (tooltip.widget as ChartTooltip).spec.type;
            expectChartRectInside(
              tester.getRect(readout),
              tester.getRect(_plot(type)),
            );
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_sheet),
            matchesGoldenFile('goldens/chart_appearance_$appearance.png'),
          );
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
          for (final source in sources) {
            source.dispose();
          }
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

Widget _stage(BuildContext context, ChartSource source, int index) {
  final type = _types[index];
  return Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: index == 0 ? 320 : double.infinity,
      height: double.infinity,
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(index == 0 ? 2 : 1)),
        child: PreviewToolbarRegion(
          child: ChartStage(
            key: ValueKey('appearance-${type.name}'),
            viewId: source.viewId,
            source: source,
            title: chartTypeLabel(type),
            compactToolbar: index == 0,
            padding: const EdgeInsets.all(12),
            spec: chartAppearanceSpec(type, showControls: index == 0)
                .copyWith(showValues: type == ChartType.pie),
            onSpecChanged: (_) {},
            trailing: [
              if (index == 0)
                TextButton.icon(
                  onPressed: () {},
                  icon:
                      const WorkspaceGlyph(Icons.table_chart_rounded, size: 16),
                  label: Text(LocaleKeys.charts_pickTable.tr()),
                  style: TextButton.styleFrom(
                    textStyle: Theme.of(context)
                        .textTheme
                        .labelLarge!
                        .copyWith(fontSize: 11.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Finder _plot(ChartType type) => find.descendant(
      of: find.byKey(ValueKey('appearance-${type.name}')),
      matching: chartAppearancePlot,
    );
