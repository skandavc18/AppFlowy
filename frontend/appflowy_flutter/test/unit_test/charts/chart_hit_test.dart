import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _palette = ChartPalette(
  background: Color(0xFFFBF5E9),
  surface: Color(0xFFFFFAF0),
  grid: Color(0x115B4938),
  axis: Color(0x335B4938),
  label: Color(0xFF735C47),
  strongLabel: Color(0xFF3E3025),
  series: ChartPalette.defaultSeries,
  baseTextStyle: TextStyle(),
  shadow: Color(0x12604F3E),
  border: Color(0x225B4938),
  chip: Color(0x115B4938),
  chipHover: Color(0x225B4938),
  isDark: false,
);
const _table = ChartTable(
  columns: [
    'Category',
    'First',
    'Second',
    'X',
  ],
  rows: [
    ['A', '9', '2', '1'],
    ['B', '5', '12', '2'],
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final type in [
    ChartType.bar,
    ChartType.horizontalBar,
    ChartType.stackedBar,
  ]) {
    for (final size in [const Size(320, 240), const Size(900, 360)]) {
      test(
          '${type.name} $size: hit rectangles belong to marks, not category lanes',
          () {
        final painter = _paint(type, size: size);
        expect(painter.hits, hasLength(4));
        for (final hit in painter.hits) {
          final matches = painter.hits
              .where((candidate) => candidate.contains(hit.rect.center))
              .toList();
          expect(
            matches,
            [hit],
            reason: 'Grouped/stacked neighbours cannot steal this point.',
          );
          final thickness =
              type.isHorizontal ? hit.rect.height : hit.rect.width;
          expect(thickness, lessThanOrEqualTo(ChartMetrics.maximumBarWidth));
          expect(thickness, greaterThanOrEqualTo(ChartMetrics.minimumBarWidth));
          expect(hit.path, isNotNull);
        }
        final last = painter.hits.last;
        final blank = type.isHorizontal
            ? Offset(last.rect.right + 2, last.rect.center.dy)
            : Offset(last.rect.center.dx, last.rect.top - 2);
        expect(
          painter.hits.where((hit) => hit.contains(blank)),
          isEmpty,
          reason: 'Empty plot space is not an invisible extension of a bar.',
        );
      });
    }
  }

  for (final type in [ChartType.pie, ChartType.donut]) {
    for (final progress in [0.25, 0.6, 1.0]) {
      for (final hovered in [false, true]) {
        test('${type.name}: exact sectors at reveal=$progress hover=$hovered',
            () {
          const data = ChartData(
            categories: ['Small', 'Large', 'Tail'],
            minimum: 0,
            maximum: 7,
            series: [
              ChartSeries(
                name: 'Total',
                points: [
                  ChartPoint(label: 'Small', value: 1),
                  ChartPoint(label: 'Large', value: 7),
                  ChartPoint(label: 'Tail', value: 2),
                ],
              ),
            ],
          );
          for (final size in [const Size(180, 140), const Size(320, 240)]) {
            final painter = _paint(
              type,
              data: data,
              size: size,
              progress: progress,
              highlight: hovered
                  ? const ChartHit(
                      seriesIndex: 0,
                      pointIndex: 1,
                      rect: Rect.zero,
                      anchor: Offset.zero,
                    )
                  : null,
            );
            final centre = size.center(Offset.zero);
            final outer = math.min(size.width, size.height) / 2 - 12;
            var preceding = 0.0;
            for (var index = 0; index < 3; index++) {
              final value = data.series.single.points[index].value;
              final angle = -math.pi / 2 +
                  (preceding + value / 2) / 10 * math.pi * 2 * progress;
              final direction = Offset(math.cos(angle), math.sin(angle));
              final shift = hovered && index == 1 ? direction * 6 : Offset.zero;
              final hit = painter.hits[index];
              for (final radius in type == ChartType.donut
                  ? [0.60, 0.80, 0.97]
                  : [0.10, 0.45, 0.95]) {
                final point = centre + shift + direction * (outer * radius);
                expect(
                  hit.contains(point),
                  isTrue,
                  reason: 'The whole sector, including its edges, must answer.',
                );
                expect(
                  painter.hits
                      .where((candidate) => candidate.contains(point))
                      .toList(),
                  [hit],
                );
              }
              expect(
                hit.contains(centre + shift + direction * (outer + 8)),
                isFalse,
              );
              expect(
                (hit.anchor - (centre + shift + direction * (outer * 0.72)))
                    .distance,
                lessThan(0.000001),
              );
              preceding += value;
            }
            if (type == ChartType.donut) {
              expect(
                painter.hits.where((hit) => hit.contains(centre)),
                isEmpty,
              );
            }
          }
        });
      }
    }
  }

  for (final type in [ChartType.line, ChartType.area, ChartType.stackedArea]) {
    test('${type.name}: unrevealed endpoints have no hit target', () {
      final complete = _paint(type);
      for (final progress in [0.001, 0.1, 0.5, 0.999]) {
        final partial = _paint(type, progress: progress);
        expect(partial.hits, hasLength(2));
        expect(partial.hits.every((hit) => hit.pointIndex == 0), isTrue);
        for (final future
            in complete.hits.where((hit) => hit.pointIndex == 1)) {
          expect(
            partial.hits.where((hit) => hit.contains(future.rect.center)),
            isEmpty,
          );
        }
      }
      expect(complete.hits, hasLength(4));
    });
  }

  for (final type in ChartType.values) {
    test('${type.name}: an unrevealed or entirely hidden plot has no hits', () {
      expect(_paint(type, progress: 0).hits, isEmpty);
      expect(_paint(type, hidden: {0, 1}).hits, isEmpty);
    });
  }

  test('mark lighting never replaces custom alpha with an opaque surface', () {
    const ink = Color(0x59367CBB);
    for (final amount in [-0.075, 0.025, 0.04]) {
      final shaded = chartMarkShade(ink, amount);
      expect(shaded.a, closeTo(ink.a, 0.000001));
      expect(
        HSLColor.fromColor(shaded).hue,
        closeTo(HSLColor.fromColor(ink).hue, 0.8),
      );
    }
    for (final palette in ChartPaletteName.values) {
      final colors = ChartColors.of(
        _palette,
        ChartSpec(
          palette: palette,
          colors: const {'First': 0x59367CBB},
        ),
      );
      expect(colors.at(0, 'First'), ink);
      expect(colors.at(1, 'Second'), ChartPalette.sets[palette]![1]);
    }
  });

  test(
      'negative bars anchor their actual growing end; zero remains inspectable',
      () {
    const data = ChartData(
      categories: ['Negative', 'Zero', 'Positive'],
      minimum: -4,
      maximum: 4,
      series: [
        ChartSeries(
          name: 'Value',
          points: [
            ChartPoint(label: 'Negative', value: -4),
            ChartPoint(label: 'Zero', value: 0),
            ChartPoint(label: 'Positive', value: 4),
          ],
        ),
      ],
    );
    for (final type in [ChartType.bar, ChartType.horizontalBar]) {
      final hits = _paint(type, data: data).hits;
      expect(hits, hasLength(3));
      expect(hits[1].contains(hits[1].rect.center), isTrue);
      expect(
        hits[0].anchor,
        type.isHorizontal ? hits[0].rect.centerLeft : hits[0].rect.bottomCenter,
      );
      expect(
        hits[2].anchor,
        type.isHorizontal ? hits[2].rect.centerRight : hits[2].rect.topCenter,
      );
    }
  });
}

ChartPainter _paint(
  ChartType type, {
  Size size = const Size(400, 280),
  ChartData? data,
  double progress = 1,
  ChartHit? highlight,
  Set<int> hidden = const {},
}) {
  final spec = ChartSpec(
    type: type,
    categoryColumn: 'Category',
    valueColumns: const ['First', 'Second'],
    xColumn: type.drawsPoints ? 'X' : null,
    sizeColumn: type.sizesPoints ? 'Second' : null,
    showLegend: false,
  );
  final painter = ChartPainter(
    data: data ?? buildChartData(_table, spec),
    spec: spec,
    palette: _palette,
    colors: ChartColors.of(_palette, spec),
    hidden: hidden,
    highlight: highlight,
    focusedSeries: null,
    reveal: AlwaysStoppedAnimation(progress),
    emphasis: const AlwaysStoppedAnimation(1),
    viewport: ChartViewport.identity,
    crosshair: null,
    hits: [],
  );
  final recorder = ui.PictureRecorder();
  try {
    painter.paint(Canvas(recorder), size);
  } finally {
    recorder.endRecording().dispose();
  }
  return painter;
}
