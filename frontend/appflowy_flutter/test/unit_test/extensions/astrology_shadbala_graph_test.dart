import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_shadbala_graph.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/shadbala.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Hand-authored ShadbalaRow fixtures only. No chart, calculation engine,
// native library, ephemeris, assets, location, network, or filesystem access.
const _totals = [240.0, 300.0, -120.0, 420.0, 480.0, 0.0, null];
const _required = [300.0, 360.0, 300.0, 420.0, 390.0, 330.0, 300.0];
const _percentages = [
  240 / 300 * 100,
  300 / 360 * 100,
  -40.0,
  100.0,
  480 / 390 * 100,
  0.0,
  null,
];
const _percentageLabels = [
  '80%',
  '83.3%',
  '-40%',
  '100%',
  '123.1%',
  '0%',
  '—',
];
const _epsilon = 0.01;
const _appearances = [
  (name: 'light', brightness: Brightness.light, paper: false),
  (name: 'dark', brightness: Brightness.dark, paper: false),
  (name: 'paper', brightness: Brightness.light, paper: true),
];

void main() {
  group('shared signed geometry', () {
    test(
      'raw totals remain virupas while signed heights share a percentage axis',
      () {
        final geometry = AstrologyShadbalaGraphGeometry(rows: _rows());
        const plot = Rect.fromLTWH(20, 10, 700, 300);
        const maximum = 480 / 390 * 100;
        const span = maximum + 40;
        const zero = 10 + 300 * maximum / span;
        expect(geometry.minimum, -40);
        expect(geometry.maximum, closeTo(maximum, 1e-12));
        expect(geometry.zeroY(plot), closeTo(zero, 1e-9));
        expect(geometry.yFor(maximum, plot), closeTo(10, 1e-9));
        expect(geometry.yFor(-40, plot), closeTo(310, 1e-9));
        for (var index = 0; index < VedicBody.classical.length; index++) {
          final body = VedicBody.classical[index];
          expect(geometry.totalFor(body), _totals[index]);
          expect(geometry.rowFor(body).required, _required[index]);
          expect(geometry.percentageFor(body), _percentages[index]);
          expect(
            geometry.requiredY(body, plot),
            closeTo(10 + 300 * (maximum - 100) / span, 1e-9),
          );
          expect(geometry.requiredY(body, plot), geometry.yFor(100, plot));
        }

        final sun = geometry.barRect(VedicBody.sun, plot)!;
        final moon = geometry.barRect(VedicBody.moon, plot)!;
        final mars = geometry.barRect(VedicBody.mars, plot)!;
        const sunHeight = 300 * (240 / 300 * 100) / span;
        expect(sun.top, closeTo(zero - sunHeight, 1e-9));
        expect(sun.bottom, closeTo(zero, 1e-9));
        expect(
          sun.height,
          closeTo(sunHeight, 1e-9),
          reason: 'Sun: 240 / 300 * 100 = 80% on the shared axis.',
        );
        expect(moon.height, closeTo(300 * (300 / 360 * 100) / span, 1e-9));
        expect(moon.bottom, sun.bottom);
        expect(mars.top, sun.bottom);
        expect(mars.bottom, closeTo(310, 1e-9));
        expect(mars.height, closeTo(300 * 40 / span, 1e-9));
        expect(
          sun.height / mars.height,
          closeTo((240 / 300 * 100) / 40, 1e-9),
          reason: 'Sun 80% / Mars absolute 40% gives a height ratio of 2.',
        );
        expect(sun.width, lessThan(sun.height));
        expect(geometry.barRect(VedicBody.jupiter, plot)!.top, plot.top);
        expect(
          geometry.ticks,
          orderedEquals([0.0, 100.0, -40.0, maximum, -20.0, maximum / 2]),
        );
      },
    );

    test(
      'equal raw totals have planet-specific heights and retain a 100% ceiling',
      () {
        final geometry = AstrologyShadbalaGraphGeometry(
          rows: [for (final body in VedicBody.classical) _row(body)],
        );
        const plot = Rect.fromLTWH(0, 0, 700, 210);
        expect(geometry.minimum, 0);
        expect(
          geometry.maximum,
          100,
          reason: 'Every total is below its minimum.',
        );
        expect(geometry.zeroY(plot), plot.bottom);
        for (var index = 0; index < VedicBody.classical.length; index++) {
          final body = VedicBody.classical[index];
          expect(geometry.totalFor(body), 240);
          expect(
            geometry.percentageFor(body),
            closeTo(240 / _required[index] * 100, 1e-9),
          );
          expect(
            geometry.barRect(body, plot)!.height,
            closeTo(210 * 240 / _required[index], 1e-9),
          );
          expect(geometry.requiredY(body, plot), 0);
        }
        expect(
          geometry.barRect(VedicBody.mars, plot)!.height,
          closeTo(geometry.barRect(VedicBody.sun, plot)!.height, 1e-9),
          reason: 'Sun and Mars both give 240 / 300 * 100 = 80%.',
        );
        expect(geometry.ticks, orderedEquals([0.0, 100.0, 50.0]));
      },
    );

    test(
      'Mars 360 / 300 is 120%, not 360 virupas or a 20% surplus',
      () {
        const plot = Rect.fromLTWH(0, 0, 700, 240);
        for (final sample in const [
          (total: 360.0, percentage: 120.0, maximum: 120.0),
          (total: 300.0, percentage: 100.0, maximum: 100.0),
          (total: 240.0, percentage: 80.0, maximum: 100.0),
          (total: 0.0, percentage: 0.0, maximum: 100.0),
        ]) {
          final geometry = AstrologyShadbalaGraphGeometry(
            rows: [
              for (final body in VedicBody.classical)
                body == VedicBody.mars
                    ? _totalRow(body, sample.total)
                    : _row(body, kala: null),
            ],
          );
          expect(geometry.rowFor(VedicBody.mars).required, 300);
          expect(geometry.totalFor(VedicBody.mars), sample.total);
          expect(geometry.percentageFor(VedicBody.mars), sample.percentage);
          expect(geometry.minimum, 0);
          expect(geometry.maximum, sample.maximum);
          expect(
            geometry.barRect(VedicBody.mars, plot)!.height,
            closeTo(240 * sample.percentage / sample.maximum, 1e-9),
          );
          expect(
            geometry.requiredY(VedicBody.mars, plot),
            closeTo(240 * (sample.maximum - 100) / sample.maximum, 1e-9),
          );
        }
      },
    );

    test(
      'all seven actual minima produce equal heights for equal 120% strengths',
      () {
        const totals = [360.0, 432.0, 360.0, 504.0, 468.0, 396.0, 360.0];
        final geometry = AstrologyShadbalaGraphGeometry(
          rows: [
            for (final body in VedicBody.classical)
              _totalRow(body, totals[body.index]),
          ],
        );
        const plot = Rect.fromLTWH(0, 0, 700, 240);
        expect(geometry.minimum, 0);
        expect(geometry.maximum, closeTo(120, 1e-9));
        for (final body in VedicBody.classical) {
          expect(geometry.rowFor(body).required, _required[body.index]);
          expect(geometry.totalFor(body), totals[body.index]);
          expect(
            geometry.percentageFor(body),
            closeTo(120, 1e-9),
            reason: '${body.label}: ${totals[body.index]} / '
                '${_required[body.index]} = 1.2 (120%).',
          );
          expect(geometry.barRect(body, plot)!.height, closeTo(240, 1e-9));
          expect(geometry.barRect(body, plot)!.bottom, plot.bottom);
          expect(geometry.requiredY(body, plot), closeTo(40, 1e-9));
        }
        expect(geometry.ticks, orderedEquals([0.0, 100.0, 120.0, 60.0]));
      },
    );

    test(
      'zero and 100% ticks keep priority when maxima or midpoints coincide',
      () {
        final zero = AstrologyShadbalaGraphGeometry(
          rows: [for (final body in VedicBody.classical) _totalRow(body, 0)],
        );
        expect(zero.minimum, 0);
        expect(zero.maximum, 100);
        expect(zero.ticks, orderedEquals([0.0, 100.0, 50.0]));
        for (final body in VedicBody.classical) {
          expect(zero.totalFor(body), 0);
          expect(zero.percentageFor(body), 0);
          expect(
            zero.barRect(body, const Rect.fromLTWH(0, 0, 700, 200))!.height,
            0,
          );
        }
        final twice = AstrologyShadbalaGraphGeometry(
          rows: [
            for (final body in VedicBody.classical)
              body == VedicBody.sun
                  ? _totalRow(body, 600)
                  : _row(body, kala: null),
          ],
        );
        expect(
          twice.maximum,
          200,
          reason: 'Sun: 600 / 300 * 100 = 200%; the midpoint is 100%.',
        );
        expect(twice.ticks, orderedEquals([0.0, 100.0, 200.0]));
      },
    );

    test(
      'entirely negative totals still include zero and the shared 100% minimum',
      () {
        final geometry = AstrologyShadbalaGraphGeometry(
          rows: [
            for (final body in VedicBody.classical) _row(body, drik: -370),
          ],
        );
        const plot = Rect.fromLTWH(0, 0, 210, 270);
        const zero = 270 * 100 / 140;
        expect(geometry.minimum, -40);
        expect(geometry.maximum, 100);
        expect(geometry.zeroY(plot), closeTo(zero, 1e-9));
        for (final body in VedicBody.classical) {
          final percentage = -120 / _required[body.index] * 100;
          final bar = geometry.barRect(body, plot)!;
          expect(geometry.totalFor(body), -120);
          expect(geometry.percentageFor(body), closeTo(percentage, 1e-9));
          expect(bar.top, closeTo(zero, 1e-9));
          expect(bar.bottom, closeTo(zero - 270 * percentage / 140, 1e-9));
          expect(geometry.requiredY(body, plot), plot.top);
        }
        expect(geometry.ticks, orderedEquals([0.0, 100.0, -40.0, -20.0, 50.0]));
      },
    );

    test('unavailable totals have no rectangle, unlike a genuine zero', () {
      final mixed = AstrologyShadbalaGraphGeometry(rows: _rows());
      const plot = Rect.fromLTWH(0, 0, 210, 200);
      expect(mixed.totalFor(VedicBody.saturn), isNull);
      expect(mixed.percentageFor(VedicBody.saturn), isNull);
      expect(mixed.barRect(VedicBody.saturn, plot), isNull);
      expect(mixed.totalFor(VedicBody.venus), 0);
      expect(mixed.percentageFor(VedicBody.venus), 0);
      expect(mixed.barRect(VedicBody.venus, plot)!.height, 0);
      expect(
        mixed.barRect(VedicBody.venus, plot)!.top,
        mixed.zeroY(plot),
      );
      final unavailable = AstrologyShadbalaGraphGeometry(
        rows: [
          for (final body in VedicBody.classical) _row(body, kala: null),
        ],
      );
      expect(unavailable.minimum, 0);
      expect(unavailable.maximum, 100);
      expect(unavailable.ticks, orderedEquals([0.0, 100.0, 50.0]));
      for (final body in VedicBody.classical) {
        expect(unavailable.totalFor(body), isNull);
        expect(unavailable.percentageFor(body), isNull);
        expect(unavailable.barRect(body, plot), isNull);
        expect(unavailable.requiredY(body, plot), plot.top);
      }
    });

    test('NaN and infinity cannot poison the common range or become zeros', () {
      final rows = _rows()
        ..[0] = _row(VedicBody.sun, sthana: double.infinity)
        ..[1] = _row(VedicBody.moon, kala: double.nan)
        ..[2] = _row(VedicBody.mars, drik: double.negativeInfinity);
      final geometry = AstrologyShadbalaGraphGeometry(rows: rows);
      expect(geometry.minimum, 0);
      expect(geometry.maximum, closeTo(480 / 390 * 100, 1e-12));
      for (final body in VedicBody.classical.take(3)) {
        expect(geometry.totalFor(body), isNull);
        expect(geometry.percentageFor(body), isNull);
        expect(
          geometry.barRect(body, const Rect.fromLTWH(0, 0, 210, 200)),
          isNull,
        );
      }
    });

    test(
      'huge finite raw totals divide before multiplying and keep finite geometry',
      () {
        final rows = _rows()
          ..[0] = _totalRow(VedicBody.sun, 1.7e308)
          ..[2] = _totalRow(VedicBody.mars, -1.7e308);
        final geometry = AstrologyShadbalaGraphGeometry(rows: rows);
        const plot = Rect.fromLTWH(0, 0, 700, 200);
        const high = 1.7e308 / 300 * 100;
        const low = -1.7e308 / 300 * 100;
        // 1/300 divided by (1/300 + 1/300), without overflowing raw totals.
        const zero = 200 * 300 / (300 + 300);
        expect(geometry.totalFor(VedicBody.sun), 1.7e308);
        expect(geometry.totalFor(VedicBody.mars), -1.7e308);
        expect(geometry.percentageFor(VedicBody.sun), high);
        expect(geometry.percentageFor(VedicBody.mars), low);
        expect(geometry.minimum, low);
        expect(geometry.maximum, high);
        expect(
          geometry.zeroY(plot),
          closeTo(zero, 1e-9),
          reason: 'Sun/Mars minima of 300 put equal opposite totals at y=100.',
        );
        expect(geometry.yFor(high, plot), 0);
        expect(geometry.yFor(low, plot), 200);
        expect(geometry.barRect(VedicBody.sun, plot)!.top, 0);
        expect(geometry.barRect(VedicBody.mars, plot)!.bottom, 200);
        expect(geometry.ticks.every((tick) => tick.isFinite), isTrue);
        for (final body in VedicBody.classical) {
          expect(geometry.requiredY(body, plot), closeTo(zero, 1e-9));
          final bar = geometry.barRect(body, plot);
          if (bar == null) continue;
          for (final coordinate in [bar.left, bar.top, bar.right, bar.bottom]) {
            expect(coordinate.isFinite, isTrue);
          }
          expect(bar.top, greaterThanOrEqualTo(plot.top));
          expect(bar.bottom, lessThanOrEqualTo(plot.bottom));
        }
      },
    );

    test('canonical slots snapshot input without mutating the caller list', () {
      final source = _rows().reversed.toList();
      final original = List.of(source);
      final geometry = AstrologyShadbalaGraphGeometry(rows: source);
      expect(source, orderedEquals(original));
      expect(geometry.rows.map((row) => row.body), VedicBody.classical);
      const plot = Rect.fromLTWH(20, 10, 140, 200);
      for (var index = 0; index < 7; index++) {
        final body = VedicBody.classical[index];
        final slot = geometry.slotRect(body, plot);
        expect(slot, Rect.fromLTWH(20 + index * 20, 10, 20, 200));
        final bar = geometry.barRect(body, plot);
        if (bar != null) {
          expect(bar.center.dx, slot.center.dx);
          expect(bar.left, greaterThan(slot.left));
          expect(bar.right, lessThan(slot.right));
        }
      }
      source.clear();
      expect(geometry.rows, hasLength(7));
      expect(geometry.totalFor(VedicBody.sun), 240);
      expect(() => geometry.rows.clear(), throwsUnsupportedError);
    });

    test('rejects incomplete, duplicate and non-classical row contracts', () {
      for (final rows in [
        <ShadbalaRow>[],
        _rows().take(6).toList(),
        _rows()..[1] = _row(VedicBody.sun),
        _rows()..[6] = _row(VedicBody.rahu),
      ]) {
        expect(
          () => AstrologyShadbalaGraphGeometry(rows: rows),
          throwsArgumentError,
        );
      }
      final geometry = AstrologyShadbalaGraphGeometry(rows: _rows());
      expect(
        () => geometry.slotRect(VedicBody.ketu, Rect.zero),
        throwsArgumentError,
      );
      expect(() => geometry.yFor(double.nan, Rect.zero), throwsArgumentError);
    });
  });

  _widgetTest('owns a finite height under Contents-like unbounded layout', (
    tester,
  ) async {
    final rows = _rows();
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [_graph(rows: rows)],
          ),
        ),
        width: 220,
        height: 100,
      ),
    );
    expect(tester.getSize(_key('shadbala-graph')), const Size(220, 280));
    expect(
      find.descendant(
        of: _key('shadbala-graph'),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    await tester.pumpWidget(
      _app(UnconstrainedBox(child: _graph(rows: rows)), width: null),
    );
    expect(tester.getSize(_key('shadbala-graph')), const Size(360, 280));
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
  });

  _widgetTest('respects tight heights and safely handles zero-sized hosts', (
    tester,
  ) async {
    final rows = _rows();
    for (final size in const [Size(220, 100), Size(220, 260), Size(760, 320)]) {
      await tester.pumpWidget(
        _app(_graph(rows: rows), width: size.width, height: size.height),
      );
      expect(tester.getSize(_key('shadbala-graph')), size);
      expect(tester.takeException(), isNull);
    }
    for (final size in const [Size(0, 280), Size(220, 0)]) {
      await tester.pumpWidget(
        _app(_graph(rows: rows), width: size.width, height: size.height),
      );
      expect(_key('shadbala-graph'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  _widgetTest('rendered bars keep the shared math without per-planet markers', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_graph()));
    final plot = tester.getRect(_key('shadbala-plot'));
    const maximum = 480 / 390 * 100;
    const span = maximum + 40;
    final baseline = plot.top + plot.height * maximum / span;
    for (var index = 0; index < 7; index++) {
      final body = VedicBody.classical[index];
      final percentage = _percentages[index];
      final prefix = 'shadbala-bar-${body.name}';
      final slot = tester.getRect(_bar(body));
      expect(slot.left, closeTo(plot.left + index * plot.width / 7, _epsilon));
      expect(slot.width, closeTo(plot.width / 7, _epsilon));
      if (percentage == null) {
        expect(_key('$prefix-fill'), findsNothing);
        expect(_key('$prefix-unavailable'), findsOneWidget);
      } else {
        final rect = tester.getRect(_key('$prefix-fill'));
        expect(
          rect.top,
          closeTo(
            baseline - math.max(percentage, 0) * plot.height / span,
            _epsilon,
          ),
        );
        expect(
          rect.bottom,
          closeTo(
            baseline - math.min(percentage, 0) * plot.height / span,
            _epsilon,
          ),
        );
        expect(rect.center.dx, closeTo(slot.center.dx, _epsilon));
      }
      final planetPlot = tester.getRect(_key('$prefix-plot'));
      expect(planetPlot.left, closeTo(slot.left, _epsilon));
      expect(planetPlot.right, closeTo(slot.right, _epsilon));
      expect(planetPlot.top, closeTo(plot.top, _epsilon));
      expect(planetPlot.bottom, closeTo(plot.bottom, _epsilon));
      expect(
        tester.getRect(_key('$prefix-label')).top,
        greaterThan(plot.bottom),
      );
      expect(_key('$prefix-marker'), findsNothing);
      expect(
        find.descendant(of: _bar(body), matching: find.byType(CustomPaint)),
        findsNothing,
        reason:
            'Guide lines belong to the shared axis, not individual planets.',
      );
    }
    final localPlot = plot.shift(-tester.getTopLeft(_key('shadbala-graph')));
    for (final tick in [0.0, 100.0]) {
      final y = localPlot.top + (maximum - tick) * localPlot.height / span;
      expect(
        tester.renderObject(_key('shadbala-graph-grid')),
        paints
          ..something((method, arguments) {
            if (method != #drawLine) return false;
            final start = arguments[0] as Offset;
            final end = arguments[1] as Offset;
            final paint = arguments[2] as Paint;
            return (start.dx - localPlot.left).abs() < _epsilon &&
                (end.dx - localPlot.right).abs() < _epsilon &&
                (start.dy - y).abs() < _epsilon &&
                (end.dy - y).abs() < _epsilon &&
                paint.strokeWidth == (tick == 0 ? 1 : 0.5);
          }),
      );
    }
    expect(tester.getSize(_key('shadbala-bar-venus-fill')).height, 0);
  });

  _widgetTest(
    'different raw totals at 120% render equal bars and percentage labels',
    (tester) async {
      const totals = [360.0, 432.0, 360.0, 504.0, 468.0, 396.0, 360.0];
      await tester.pumpWidget(
        _app(
          _graph(
            rows: [
              for (final body in VedicBody.classical)
                _totalRow(body, totals[body.index]),
            ],
          ),
          width: 1100,
        ),
      );
      final plot = tester.getRect(_key('shadbala-plot'));
      for (final body in VedicBody.classical) {
        final bar = tester.getRect(_key('shadbala-bar-${body.name}-fill'));
        expect(bar.top, closeTo(plot.top, _epsilon));
        expect(bar.bottom, closeTo(plot.bottom, _epsilon));
        expect(
          _text(tester, 'shadbala-bar-${body.name}-value'),
          '120%',
          reason: '${body.label}: ${totals[body.index]} / '
              '${_required[body.index]} = 1.2 (120%).',
        );
        expect(
          _semantics(tester, body).value,
          startsWith('Strength (% of minimum): 120%; '),
        );
      }
      expect(
        _text(tester, 'shadbala-graph-caption'),
        'Strength (% of minimum) · 100% = minimum',
      );
      await tester.tap(_bar(VedicBody.mars));
      await tester.pumpAndSettle();
      expect(_hoverValue(tester, VedicBody.mars, 'percentage'), '120%');
      expect(_hoverValue(tester, VedicBody.mars, 'total'), '360.00');
      expect(_hoverValue(tester, VedicBody.mars, 'required'), '300.00');
      expect(_hoverValue(tester, VedicBody.mars, 'ratio'), '1.200');
    },
  );

  _widgetTest(
    'Mars labels distinguish 120%, 100%, 80% and a genuine 0%',
    (tester) async {
      for (final sample in const [
        (total: 360.0, label: '120%'),
        (total: 300.0, label: '100%'),
        (total: 240.0, label: '80%'),
        (total: 0.0, label: '0%'),
      ]) {
        await tester.pumpWidget(
          _app(
            _graph(
              rows: [
                for (final body in VedicBody.classical)
                  body == VedicBody.mars
                      ? _totalRow(body, sample.total)
                      : _row(body, kala: null),
              ],
            ),
            width: 1100,
          ),
        );
        await tester.pumpAndSettle();
        expect(_text(tester, 'shadbala-bar-mars-value'), sample.label);
        expect(_key('shadbala-bar-mars-fill'), findsOneWidget);
        expect(_key('shadbala-bar-mars-unavailable'), findsNothing);
        await tester.tap(_bar(VedicBody.mars));
        await tester.pumpAndSettle();
        expect(_hoverValue(tester, VedicBody.mars, 'percentage'), sample.label);
        expect(
          _hoverValue(tester, VedicBody.mars, 'total'),
          sample.total.toStringAsFixed(2),
        );
      }
    },
  );

  _widgetTest(
    'huge finite totals render finite rectangles on the normalized percent scale',
    (tester) async {
      final rows = _rows()
        ..[0] = _totalRow(VedicBody.sun, 1.7e308)
        ..[2] = _totalRow(VedicBody.mars, -1.7e308);
      await tester.pumpWidget(_app(_graph(rows: rows)));
      final plot = tester.getRect(_key('shadbala-plot'));
      final zero = plot.top + plot.height * 300 / (300 + 300);
      final sun = tester.getRect(_key('shadbala-bar-sun-fill'));
      final mars = tester.getRect(_key('shadbala-bar-mars-fill'));
      expect(sun.top, closeTo(plot.top, _epsilon));
      expect(
        sun.bottom,
        closeTo(zero, _epsilon),
        reason: 'Equal opposite totals / 300 put the baseline halfway down.',
      );
      expect(mars.top, closeTo(zero, _epsilon));
      expect(mars.bottom, closeTo(plot.bottom, _epsilon));
      for (final body in VedicBody.classical.take(6)) {
        final bar = tester.getRect(_key('shadbala-bar-${body.name}-fill'));
        for (final coordinate in [bar.left, bar.top, bar.right, bar.bottom]) {
          expect(coordinate.isFinite, isTrue);
        }
        expect(bar.top, greaterThanOrEqualTo(plot.top - _epsilon));
        expect(bar.bottom, lessThanOrEqualTo(plot.bottom + _epsilon));
      }
      expect(_key('shadbala-bar-saturn-fill'), findsNothing);
      expect(find.textContaining('NaN'), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
    },
  );

  _widgetTest(
      'wide numeric Text keys are optional, but all data stays accessible', (
    tester,
  ) async {
    final rows = _rows();
    await tester.pumpWidget(_app(_graph(rows: rows), width: 1100));
    for (var index = 0; index < 7; index++) {
      final body = VedicBody.classical[index];
      expect(
        _text(tester, 'shadbala-bar-${body.name}-value'),
        _percentageLabels[index],
      );
    }
    expect(find.byType(SelectableText), findsNothing);
    await tester.pumpWidget(_app(_graph(rows: rows), width: 220));
    for (var index = 0; index < 7; index++) {
      final body = VedicBody.classical[index];
      expect(_key('shadbala-bar-${body.name}-value'), findsNothing);
      final data = _semantics(tester, body);
      expect(data.label, '${body.label} relative Shadbala');
      expect(
        data.value,
        startsWith(
          'Strength (% of minimum): '
          '${_totals[index] == null ? 'Unavailable' : _percentageLabels[index]}; ',
        ),
      );
      expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
      expect(data.hasFlag(ui.SemanticsFlag.isFocusable), isTrue);
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
      expect(data.hasFlag(ui.SemanticsFlag.isSelected), body == VedicBody.sun);
      expect(
        data.value,
        contains(
          'Total (virupas): '
          '${_totals[index]?.toStringAsFixed(2) ?? 'Unavailable'}',
        ),
      );
      expect(
        data.value,
        contains(
          'Required (virupas): '
          '${_required[index].toStringAsFixed(2)}',
        ),
      );
      final rawMetrics = {
        'Sthana': rows[index].sthana.toStringAsFixed(2),
        'Dig': '20.00',
        'Kala': body == VedicBody.saturn ? 'Unavailable' : '30.00',
        'Cheshta': '40.00',
        'Naisargika': '60.00',
        'Drik': rows[index].drik.toStringAsFixed(2),
        'Total (rupas)': _totals[index] == null
            ? 'Unavailable'
            : (_totals[index]! / 60).toStringAsFixed(2),
        'Ratio': _totals[index] == null
            ? 'Unavailable'
            : (_totals[index]! / _required[index]).toStringAsFixed(3),
        'Motion': 'Sama',
      };
      for (final entry in rawMetrics.entries) {
        expect(data.value, contains('${entry.key}: ${entry.value}'));
      }
      expect(data.hint, contains('component breakdown below'));
    }
    expect(
      _semantics(tester, VedicBody.venus).value,
      contains('Total (virupas): 0.00'),
    );
    expect(
      _semantics(tester, VedicBody.saturn).value,
      contains('not zero estimates'),
    );
  });

  _widgetTest('all seven real taps select once and drive the parent breakdown',
      (
    tester,
  ) async {
    final rows = _rows();
    final changes = <VedicBody>[];
    var selected = VedicBody.sun;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, rebuild) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _graph(
                rows: rows,
                selected: selected,
                onSelected: (body) {
                  changes.add(body);
                  rebuild(() => selected = body);
                },
              ),
              Text(
                'Selected ${selected.label}',
                key: const ValueKey('breakdown'),
              ),
            ],
          ),
        ),
        width: 220,
      ),
    );
    for (final body in VedicBody.classical) {
      expect(_bar(body).hitTestable(), findsOneWidget);
      await tester.tap(_bar(body));
      await tester.pumpAndSettle();
      expect(changes.last, body);
      expect(changes.length, body.index + 1);
      expect(_text(tester, 'breakdown'), 'Selected ${body.label}');
      expect(_popup(body), findsOneWidget);
      expect(
        _semantics(tester, body).hasFlag(ui.SemanticsFlag.isSelected),
        isTrue,
      );
    }
    expect(changes, VedicBody.classical);
  });

  _widgetTest(
      'selection is controlled, never optimistically stored by the graph', (
    tester,
  ) async {
    final changes = <VedicBody>[];
    await tester.pumpWidget(_app(_graph(onSelected: changes.add)));
    await tester.tap(_bar(VedicBody.moon));
    await tester.pumpAndSettle();
    expect(changes, [VedicBody.moon]);
    expect(
      _semantics(tester, VedicBody.sun).hasFlag(ui.SemanticsFlag.isSelected),
      isTrue,
    );
    expect(
      _semantics(tester, VedicBody.moon).hasFlag(ui.SemanticsFlag.isSelected),
      isFalse,
    );
    expect(_popup(VedicBody.moon), findsOneWidget);
  });

  _widgetTest('nullable selection changes only when the caller supplies it', (
    tester,
  ) async {
    final rows = _rows();
    final changes = <VedicBody>[];
    Widget app(VedicBody? selected) => _app(
          _graph(rows: rows, selected: selected, onSelected: changes.add),
        );
    await tester.pumpWidget(app(null));
    _expectSelection(tester, null);

    VedicBody? selected;
    for (final body in [VedicBody.mars, VedicBody.moon]) {
      await tester.tap(_bar(body));
      await tester.pumpAndSettle();
      expect(changes.last, body);
      _expectSelection(tester, selected);
      await tester.pumpWidget(app(body));
      await tester.pumpAndSettle();
      selected = body;
      _expectSelection(tester, body);
    }
    expect(changes, [VedicBody.mars, VedicBody.moon]);
    await tester.pumpWidget(app(null));
    await tester.pumpAndSettle();
    _expectSelection(tester, null);
  });

  for (final appearance in _appearances) {
    _widgetTest(
      '${appearance.name} hover leaves null selection and planet fills intact',
      (tester) async {
        final changes = <VedicBody>[];
        await tester.pumpWidget(
          _app(
            _graph(selected: null, onSelected: changes.add),
            brightness: appearance.brightness,
            paper: appearance.paper,
          ),
        );
        _expectSelection(tester, null);
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        try {
          for (final body in [VedicBody.sun, VedicBody.moon]) {
            await mouse.moveTo(tester.getCenter(_bar(body)));
            await tester.pumpAndSettle();
            expect(_popup(body), findsOneWidget);
            _expectSelection(tester, null, hovered: body);
          }
          await mouse.moveTo(Offset.zero);
          await tester.pumpAndSettle();
          expect(_popup(VedicBody.sun), findsNothing);
          expect(_popup(VedicBody.moon), findsNothing);
          _expectSelection(tester, null);
          expect(changes, isEmpty);
        } finally {
          await mouse.removePointer();
        }
      },
    );
  }

  _widgetTest('Tab focus from null selects only on Enter or Space', (
    tester,
  ) async {
    final changes = <VedicBody>[];
    await tester.pumpWidget(
      _app(_graph(selected: null, onSelected: changes.add)),
    );
    await _keyPress(tester, LogicalKeyboardKey.tab);
    expect(_focusNode(tester, VedicBody.sun).hasFocus, isTrue);
    expect(_popup(VedicBody.sun), findsOneWidget);
    _expectSelection(tester, null);
    expect(changes, isEmpty);
    await _keyPress(tester, LogicalKeyboardKey.enter);
    expect(changes, [VedicBody.sun]);
    _expectSelection(tester, null);
    await _keyPress(tester, LogicalKeyboardKey.tab);
    expect(_focusNode(tester, VedicBody.moon).hasFocus, isTrue);
    expect(changes, [VedicBody.sun]);
    _expectSelection(tester, null);
    await _keyPress(tester, LogicalKeyboardKey.space);
    expect(changes, [VedicBody.sun, VedicBody.moon]);
    _expectSelection(tester, null);
    _focusNode(tester, VedicBody.moon).unfocus();
    await tester.pumpAndSettle();
    expect(_popup(VedicBody.moon), findsNothing);
    _expectSelection(tester, null);
  });

  _widgetTest('real hover lists all supplied values, follows planets and exits',
      (
    tester,
  ) async {
    final changes = <VedicBody>[];
    await tester.pumpWidget(_app(_graph(onSelected: changes.add)));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    try {
      await mouse.moveTo(tester.getCenter(_bar(VedicBody.sun)));
      await tester.pumpAndSettle();
      expect(_text(tester, 'shadbala-hover-sun-title'), 'Sun · Shadbala');
      const expected = {
        'percentage': '80%',
        'sthana': '100.00',
        'dig': '20.00',
        'kala': '30.00',
        'cheshta': '40.00',
        'naisargika': '60.00',
        'drik': '-10.00',
        'total': '240.00',
        'rupas': '4.00',
        'required': '300.00',
        'ratio': '0.800',
        'motion': 'Motion: Sama',
      };
      for (final entry in expected.entries) {
        expect(
          _hoverValue(tester, VedicBody.sun, entry.key),
          entry.value,
          reason: 'Sun ${entry.key}: ${entry.value}; 240 / 300 = 0.800 (80%).',
        );
      }
      expect(
        find.descendant(
          of: _popup(VedicBody.sun),
          matching: find.text('Strength (% of minimum)'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(_key('shadbala-hover-sun-percentage-value')).dy,
        lessThan(tester.getTopLeft(_key('shadbala-hover-sun-sthana-value')).dy),
      );
      expect(_key('shadbala-hover-sun-unavailable-note'), findsNothing);
      await mouse.moveTo(tester.getCenter(_bar(VedicBody.moon)));
      await tester.pumpAndSettle();
      expect(_popup(VedicBody.sun), findsNothing);
      expect(_hoverValue(tester, VedicBody.moon, 'percentage'), '83.3%');
      expect(_hoverValue(tester, VedicBody.moon, 'total'), '300.00');
      expect(_hoverValue(tester, VedicBody.moon, 'ratio'), '0.833');
      expect(changes, isEmpty);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(_popup(VedicBody.moon), findsNothing);
    } finally {
      await mouse.removePointer();
    }
  });

  _widgetTest('marker-free plots keep full required values and ratios on hover',
      (
    tester,
  ) async {
    final changes = <VedicBody>[];
    await tester.pumpWidget(_app(_graph(onSelected: changes.add)));
    expect(
      _text(tester, 'shadbala-graph-caption'),
      'Strength (% of minimum) · 100% = minimum · — Unavailable',
    );
    final semantics = tester
        .getSemantics(
          find.bySemanticsLabel('Shadbala relative strength comparison'),
        )
        .getSemanticsData();
    expect(semantics.label, 'Shadbala relative strength comparison');
    expect(
      semantics.value,
      'Shared scale -40% to 123.1% of minimum. 100% meets the minimum.',
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    try {
      for (var index = 0; index < VedicBody.classical.length; index++) {
        final body = VedicBody.classical[index];
        final total = _totals[index];
        final required = _required[index];
        expect(_key('shadbala-bar-${body.name}-marker'), findsNothing);
        expect(_key('shadbala-bar-${body.name}-plot'), findsOneWidget);
        await mouse.moveTo(tester.getCenter(_bar(body)));
        await tester.pumpAndSettle();
        expect(_popup(body), findsOneWidget);
        expect(
          _hoverValue(tester, body, 'percentage'),
          total == null ? 'Unavailable' : _percentageLabels[index],
        );
        expect(
          find.descendant(
            of: _popup(body),
            matching: find.text('Required (virupas)'),
          ),
          findsOneWidget,
        );
        expect(
          _hoverValue(tester, body, 'required'),
          required.toStringAsFixed(2),
        );
        expect(
          _hoverValue(tester, body, 'ratio'),
          total == null ? 'Unavailable' : (total / required).toStringAsFixed(3),
        );
        expect(
          _hoverValue(tester, body, 'total'),
          total?.toStringAsFixed(2) ?? 'Unavailable',
        );
        expect(
          _hoverValue(tester, body, 'rupas'),
          total == null ? 'Unavailable' : (total / 60).toStringAsFixed(2),
        );
      }
      expect(changes, isEmpty, reason: 'Hover details remain read-only.');
    } finally {
      await mouse.removePointer();
    }
  });

  _widgetTest(
      'a hover card has no MouseRegion and cannot steal another bar tap', (
    tester,
  ) async {
    final changes = <VedicBody>[];
    await tester.pumpWidget(_app(_graph(onSelected: changes.add), width: 280));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    try {
      await mouse.moveTo(tester.getCenter(_bar(VedicBody.sun)));
      await tester.pumpAndSettle();
      final popup = _popup(VedicBody.sun);
      expect(
        find.descendant(of: popup, matching: find.byType(MouseRegion)),
        findsNothing,
      );
      expect(
        tester
            .widgetList<IgnorePointer>(
              find.ancestor(of: popup, matching: find.byType(IgnorePointer)),
            )
            .any((widget) => widget.ignoring),
        isTrue,
      );
      final card = tester.getRect(popup);
      final candidates = VedicBody.classical
          .skip(1)
          .where(
            (body) =>
                !tester.getRect(_bar(body)).intersect(card).deflate(2).isEmpty,
          )
          .toList();
      expect(
        candidates,
        isNotEmpty,
        reason: 'Exercise a real overlapping column.',
      );
      final destination = candidates.first;
      final overlap =
          tester.getRect(_bar(destination)).intersect(card).deflate(2);
      await tester.tapAt(overlap.center);
      await tester.pumpAndSettle();
      expect(changes, [destination]);
      expect(_popup(destination), findsOneWidget);
    } finally {
      await mouse.removePointer();
    }
  });

  _widgetTest('unavailable details retain all six components and explain Kala',
      (
    tester,
  ) async {
    await tester.pumpWidget(_app(_graph(), width: 220));
    expect(_text(tester, 'shadbala-graph-caption'), contains('Unavailable'));
    await tester.tap(_bar(VedicBody.saturn));
    await tester.pumpAndSettle();
    const expected = {
      'percentage': 'Unavailable',
      'sthana': '100.00',
      'dig': '20.00',
      'kala': 'Unavailable',
      'cheshta': '40.00',
      'naisargika': '60.00',
      'drik': '-10.00',
      'total': 'Unavailable',
      'rupas': 'Unavailable',
      'required': '300.00',
      'ratio': 'Unavailable',
    };
    for (final entry in expected.entries) {
      expect(_hoverValue(tester, VedicBody.saturn, entry.key), entry.value);
    }
    final explanation = _text(tester, 'shadbala-hover-saturn-unavailable-note');
    expect(explanation, contains('sunrise/sunset'));
    expect(explanation, contains('polar day/night'));
    expect(explanation, contains('missing solar events'));
    expect(explanation, contains('not zero estimates'));
    expect(_key('shadbala-bar-saturn-fill'), findsNothing);
    expect(_key('shadbala-bar-saturn-plot'), findsOneWidget);
    expect(_key('shadbala-bar-saturn-marker'), findsNothing);
    expect(_semantics(tester, VedicBody.saturn).value, contains(explanation));
  });

  _widgetTest('every non-finite detail is guarded, including all six strengths',
      (
    tester,
  ) async {
    final rows = _rows()
      ..[0] = _row(
        VedicBody.sun,
        sthana: double.nan,
        dig: double.infinity,
        kala: double.negativeInfinity,
        cheshta: double.nan,
        naisargika: double.infinity,
        drik: double.negativeInfinity,
      );
    await tester.pumpWidget(_app(_graph(rows: rows)));
    await tester.tap(_bar(VedicBody.sun));
    await tester.pumpAndSettle();
    for (final metric in [
      'sthana',
      'dig',
      'kala',
      'cheshta',
      'naisargika',
      'drik',
      'percentage',
      'total',
      'rupas',
      'ratio',
    ]) {
      expect(_hoverValue(tester, VedicBody.sun, metric), 'Unavailable');
    }
    expect(
      _hoverValue(tester, VedicBody.sun, 'required'),
      '300.00',
      reason: 'Sun minimum stays 300 virupas when its total is unavailable.',
    );
    expect(
      _text(tester, 'shadbala-hover-sun-unavailable-note'),
      contains('non-finite'),
    );
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(_key('shadbala-bar-sun-fill'), findsNothing);
    expect(_text(tester, 'shadbala-bar-sun-value'), '—');
    expect(
      _semantics(tester, VedicBody.sun).value,
      startsWith('Strength (% of minimum): Unavailable; '),
    );
  });

  _widgetTest(
      'Tab, Enter, Space and directional arrows operate the actual bars', (
    tester,
  ) async {
    final changes = <VedicBody>[];
    await tester.pumpWidget(_app(_graph(onSelected: changes.add), width: 220));
    await _keyPress(tester, LogicalKeyboardKey.tab);
    expect(_focusNode(tester, VedicBody.sun).hasFocus, isTrue);
    expect(_popup(VedicBody.sun), findsOneWidget);
    expect(changes, isEmpty);
    await _keyPress(tester, LogicalKeyboardKey.enter);
    expect(changes, [VedicBody.sun]);
    await _keyPress(tester, LogicalKeyboardKey.tab);
    expect(_focusNode(tester, VedicBody.moon).hasFocus, isTrue);
    await _keyPress(tester, LogicalKeyboardKey.space);
    expect(changes, [VedicBody.sun, VedicBody.moon]);
    for (final move in const [
      (LogicalKeyboardKey.arrowRight, VedicBody.mars),
      (LogicalKeyboardKey.arrowLeft, VedicBody.moon),
      (LogicalKeyboardKey.arrowUp, VedicBody.sun),
      (LogicalKeyboardKey.arrowLeft, VedicBody.saturn),
      (LogicalKeyboardKey.arrowDown, VedicBody.sun),
    ]) {
      await _keyPress(tester, move.$1);
      expect(_focusNode(tester, move.$2).hasFocus, isTrue);
      expect(_popup(move.$2), findsOneWidget);
      expect(changes, [VedicBody.sun, VedicBody.moon]);
    }
    final highlight =
        tester.widget<AnimatedContainer>(_key('shadbala-bar-sun-highlight'));
    final foreground = highlight.foregroundDecoration! as BoxDecoration;
    final palette = AstrologyPalette.of(tester.element(_bar(VedicBody.sun)));
    expect((foreground.border! as Border).top.color, palette.accent);
  });

  _widgetTest('Tab includes zero and unavailable planets; Shift-Tab reverses', (
    tester,
  ) async {
    final changes = <VedicBody>[];
    await tester.pumpWidget(_app(_graph(onSelected: changes.add), width: 220));
    for (final body in VedicBody.classical) {
      await _keyPress(tester, LogicalKeyboardKey.tab);
      expect(_focusNode(tester, body).hasFocus, isTrue);
      expect(
        _semantics(tester, body).hasFlag(ui.SemanticsFlag.isFocused),
        isTrue,
      );
      expect(_popup(body), findsOneWidget);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(_focusNode(tester, VedicBody.venus).hasFocus, isTrue);
    expect(_hoverValue(tester, VedicBody.venus, 'total'), '0.00');
    expect(changes, isEmpty);
  });

  _widgetTest('Escape and focus loss dismiss details without selecting', (
    tester,
  ) async {
    final changes = <VedicBody>[];
    await tester.pumpWidget(_app(_graph(onSelected: changes.add)));
    await _keyPress(tester, LogicalKeyboardKey.tab);
    await _keyPress(tester, LogicalKeyboardKey.escape);
    expect(_popup(VedicBody.sun), findsNothing);
    expect(_focusNode(tester, VedicBody.sun).hasFocus, isTrue);
    await _keyPress(tester, LogicalKeyboardKey.tab);
    expect(_popup(VedicBody.moon), findsOneWidget);
    _focusNode(tester, VedicBody.moon).unfocus();
    await tester.pumpAndSettle();
    expect(_popup(VedicBody.moon), findsNothing);
    expect(changes, isEmpty);
  });

  _widgetTest(
      'replacement rows dismiss old focus details but retain the focus node', (
    tester,
  ) async {
    final rows = _rows();
    final changes = <VedicBody>[];
    await tester.pumpWidget(_app(_graph(rows: rows, onSelected: changes.add)));
    await _keyPress(tester, LogicalKeyboardKey.tab);
    final node = _focusNode(tester, VedicBody.sun);
    expect(_hoverValue(tester, VedicBody.sun, 'total'), '240.00');
    final replacement = List.of(rows)..[0] = _row(VedicBody.sun, sthana: 160);
    await tester
        .pumpWidget(_app(_graph(rows: replacement, onSelected: changes.add)));
    await tester.pumpAndSettle();
    expect(_focusNode(tester, VedicBody.sun), same(node));
    expect(node.hasFocus, isTrue);
    expect(_popup(VedicBody.sun), findsNothing);
    await _keyPress(tester, LogicalKeyboardKey.enter);
    expect(_hoverValue(tester, VedicBody.sun, 'total'), '300.00');
    expect(
      _hoverValue(tester, VedicBody.sun, 'percentage'),
      '100%',
      reason: 'Sun: 300 / 300 * 100 = 100%.',
    );
    expect(changes, [VedicBody.sun]);
  });

  _widgetTest(
      'replacing a row inside the same input list invalidates hover data', (
    tester,
  ) async {
    final rows = _rows();
    await tester.pumpWidget(_app(_graph(rows: rows)));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    try {
      await mouse.moveTo(tester.getCenter(_bar(VedicBody.sun)));
      await tester.pumpAndSettle();
      expect(_hoverValue(tester, VedicBody.sun, 'total'), '240.00');
      rows[0] = _row(VedicBody.sun, sthana: 160);
      await tester.pumpWidget(_app(_graph(rows: rows)));
      await tester.pumpAndSettle();
      expect(_popup(VedicBody.sun), findsNothing);
      await mouse
          .moveTo(tester.getCenter(_bar(VedicBody.sun)) + const Offset(1, 0));
      await tester.pumpAndSettle();
      expect(_hoverValue(tester, VedicBody.sun, 'total'), '300.00');
      expect(
        _hoverValue(tester, VedicBody.sun, 'percentage'),
        '100%',
        reason: 'Sun: 300 / 300 * 100 = 100%.',
      );
    } finally {
      await mouse.removePointer();
    }
  });

  _widgetTest('unmount removes hover and focus portals with no recurring work',
      (
    tester,
  ) async {
    await tester.pumpWidget(_app(_graph()));
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    try {
      await mouse.moveTo(tester.getCenter(_bar(VedicBody.sun)));
      await tester.pumpAndSettle();
      expect(_popup(VedicBody.sun), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 2));
      expect(_popup(VedicBody.sun), findsNothing);
    } finally {
      await mouse.removePointer();
    }
    await tester.pumpWidget(_app(_graph()));
    await _keyPress(tester, LogicalKeyboardKey.tab);
    expect(_popup(VedicBody.sun), findsOneWidget);
    final node = _focusNode(tester, VedicBody.sun);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));
    expect(_popup(VedicBody.sun), findsNothing);
    expect(node.hasFocus, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  _widgetTest('a selection callback may immediately remove the whole graph', (
    tester,
  ) async {
    final rows = _rows();
    final changes = <VedicBody>[];
    var shown = true;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, rebuild) => shown
              ? _graph(
                  rows: rows,
                  onSelected: (body) {
                    changes.add(body);
                    rebuild(() => shown = false);
                  },
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
    await tester.tap(_bar(VedicBody.moon));
    await tester.pumpAndSettle();
    expect(changes, [VedicBody.moon]);
    expect(find.byType(AstrologyShadbalaGraph), findsNothing);
    expect(_popup(VedicBody.moon), findsNothing);
  });

  _widgetTest('150 ms tween moves the domain, heights and selection together', (
    tester,
  ) async {
    final rows = _rows();
    await tester.pumpWidget(_app(_graph(rows: rows)));
    await tester.pumpAndSettle();
    final replacement = List.of(rows)..[0] = _row(VedicBody.sun, sthana: 460);
    await tester.pumpWidget(
      _app(_graph(rows: replacement, selected: VedicBody.moon)),
    );
    expect(
      tester
          .widget<TweenAnimationBuilder<AstrologyShadbalaGraphGeometry>>(
            find.byType(TweenAnimationBuilder<AstrologyShadbalaGraphGeometry>),
          )
          .duration,
      const Duration(milliseconds: 150),
    );
    await tester.pump(const Duration(milliseconds: 75));
    final plot = tester.getRect(_key('shadbala-plot'));
    // Raw Sun total is 420 halfway through. Interpolate the unrounded percent
    // domain independently; do not ask production geometry for expectations.
    const high = (480 / 390 * 100 + 600 / 300 * 100) / 2;
    const span = high + 40;
    final zero = plot.top + plot.height * high / span;
    final sun = tester.getRect(_key('shadbala-bar-sun-fill'));
    expect(
      sun.height,
      closeTo(plot.height * (420 / 300 * 100) / span, 1e-6),
      reason: 'Sun: 420 / 300 * 100 = 140% halfway through the tween.',
    );
    expect(sun.bottom, closeTo(zero, 1e-6));
    expect(
      tester.getRect(_key('shadbala-bar-moon-fill')).bottom,
      closeTo(zero, _epsilon),
    );
    expect(
      tester.getRect(_key('shadbala-bar-mars-fill')).top,
      closeTo(zero, _epsilon),
    );
    expect(
      tester.getSize(_key('shadbala-bar-mars-fill')).height,
      closeTo(plot.height * 40 / span, 1e-6),
    );
    expect(
      tester.getRect(_key('shadbala-bar-venus-fill')).top,
      closeTo(zero, _epsilon),
    );
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      tester.getSize(_key('shadbala-bar-sun-fill')).height,
      closeTo(plot.height * (600 / 300 * 100) / (600 / 300 * 100 + 40), 1e-6),
      reason: 'Sun 600 / 300 = 200%; with Mars -40%, the span is 240 points.',
    );
    final palette = AstrologyPalette.of(tester.element(_bar(VedicBody.moon)));
    expect(_fillColor(tester, VedicBody.moon), palette.accent);
    expect(
      _fillColor(tester, VedicBody.sun),
      palette.planetColor(VedicBody.sun),
    );
    expect(
      _semantics(tester, VedicBody.moon).hasFlag(ui.SemanticsFlag.isSelected),
      isTrue,
    );
  });

  _widgetTest(
    'the 150 ms tween interpolates a changing negative percentage bound too',
    (tester) async {
      final rows = _rows();
      await tester.pumpWidget(_app(_graph(rows: rows)));
      await tester.pumpAndSettle();
      final replacement = List.of(rows)
        ..[0] = _totalRow(VedicBody.sun, 600)
        ..[2] = _totalRow(VedicBody.mars, -240);
      await tester.pumpWidget(_app(_graph(rows: replacement)));
      await tester.pump(const Duration(milliseconds: 75));
      final plot = tester.getRect(_key('shadbala-plot'));
      const high = (480 / 390 * 100 + 600 / 300 * 100) / 2;
      const span = high + 60;
      final zero = plot.top + plot.height * high / span;
      final sun = tester.getRect(_key('shadbala-bar-sun-fill'));
      final mars = tester.getRect(_key('shadbala-bar-mars-fill'));
      expect(
        sun.height,
        closeTo(plot.height * (420 / 300 * 100) / span, 1e-6),
        reason: 'Sun: 420 / 300 * 100 = 140% halfway through the tween.',
      );
      expect(sun.bottom, closeTo(zero, 1e-6));
      expect(mars.top, closeTo(zero, 1e-6));
      expect(mars.height, closeTo(plot.height * 60 / span, 1e-6));
      await tester.pump(const Duration(milliseconds: 75));
      expect(
        tester.getSize(_key('shadbala-bar-mars-fill')).height,
        closeTo(plot.height * 80 / (600 / 300 * 100 + 80), 1e-6),
        reason: 'Sun 200% and Mars -80% give a 280-point span.',
      );
    },
  );

  _widgetTest('a newly unavailable bar vanishes immediately, not via zero', (
    tester,
  ) async {
    final rows = _rows();
    await tester.pumpWidget(_app(_graph(rows: rows)));
    final replacement = List.of(rows)
      ..[0] = _row(VedicBody.sun, kala: null)
      ..[1] = _row(VedicBody.moon, sthana: 460);
    await tester.pumpWidget(_app(_graph(rows: replacement)));
    expect(_key('shadbala-bar-sun-fill'), findsNothing);
    expect(_key('shadbala-bar-sun-unavailable'), findsOneWidget);
    expect(_key('shadbala-bar-sun-plot'), findsOneWidget);
    expect(_key('shadbala-bar-sun-marker'), findsNothing);
    expect(
      _semantics(tester, VedicBody.sun).value,
      contains('Total (virupas): Unavailable'),
    );
    expect(
      _semantics(tester, VedicBody.sun).value,
      startsWith('Strength (% of minimum): Unavailable; '),
    );
    final plot = tester.getRect(_key('shadbala-plot'));
    // Availability changes now, but the other planets must not snap to target.
    expect(
      tester.getSize(_key('shadbala-bar-moon-fill')).height,
      closeTo(plot.height * (300 / 360 * 100) / (480 / 390 * 100 + 40), 1e-6),
    );
    await tester.pump(const Duration(milliseconds: 75));
    expect(_key('shadbala-bar-sun-fill'), findsNothing);
    // Halfway: Moon is 450 raw virupas / 360 * 100, minimum is still -40%.
    const high = (480 / 390 * 100 + 600 / 360 * 100) / 2;
    const span = high + 40;
    final zero = plot.top + plot.height * high / span;
    final moon = tester.getRect(_key('shadbala-bar-moon-fill'));
    expect(moon.height, closeTo(plot.height * (450 / 360 * 100) / span, 1e-6));
    expect(moon.bottom, closeTo(zero, 1e-6));
    expect(
      tester.getRect(_key('shadbala-bar-mars-fill')).top,
      closeTo(zero, _epsilon),
    );
    expect(
      tester.getRect(_key('shadbala-bar-venus-fill')).top,
      closeTo(zero, _epsilon),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(_key('shadbala-bar-moon-fill')).height,
      closeTo(plot.height * (600 / 360 * 100) / (600 / 360 * 100 + 40), 1e-6),
    );
  });

  for (final settings in const [
    (name: 'disableAnimations', disable: true, accessible: false),
    (name: 'accessibleNavigation', disable: false, accessible: true),
  ]) {
    _widgetTest(
        '${settings.name} snaps geometry and all highlights to the target', (
      tester,
    ) async {
      final rows = _rows();
      Widget app(List<ShadbalaRow> input, VedicBody selected) => _app(
            _graph(rows: input, selected: selected),
            disableAnimations: settings.disable,
            accessibleNavigation: settings.accessible,
          );
      await tester.pumpWidget(app(rows, VedicBody.sun));
      final replacement = List.of(rows)..[0] = _row(VedicBody.sun, sthana: 460);
      await tester.pumpWidget(app(replacement, VedicBody.moon));
      final plot = tester.getRect(_key('shadbala-plot'));
      expect(
        tester.getSize(_key('shadbala-bar-sun-fill')).height,
        closeTo(plot.height * (600 / 300 * 100) / (600 / 300 * 100 + 40), 1e-6),
        reason: 'Sun 600 / 300 = 200%; with Mars -40%, the span is 240 points.',
      );
      final animations = tester.widgetList<ImplicitlyAnimatedWidget>(
        find.descendant(
          of: _key('shadbala-graph'),
          matching: find.byWidgetPredicate(
            (widget) => widget is ImplicitlyAnimatedWidget,
          ),
        ),
      );
      expect(animations, isNotEmpty);
      expect(
        animations.every((widget) => widget.duration == Duration.zero),
        isTrue,
      );
      final palette = AstrologyPalette.of(tester.element(_bar(VedicBody.moon)));
      expect(_fillColor(tester, VedicBody.moon), palette.accent);
      await _keyPress(tester, LogicalKeyboardKey.tab);
      expect(_popup(VedicBody.sun), findsOneWidget);
      expect(_hoverValue(tester, VedicBody.sun, 'total'), '600.00');
      expect(
        _hoverValue(tester, VedicBody.sun, 'percentage'),
        '200%',
        reason: 'Sun: 600 / 300 * 100 = 200%.',
      );
    });
  }

  for (final appearance in _appearances) {
    for (final width in const [220.0, 760.0]) {
      for (final scale in const [1.0, 2.0]) {
        _widgetTest(
            '${appearance.name} at $width px / ${scale}x uses themed, quiet surfaces',
            (
          tester,
        ) async {
          await tester.pumpWidget(
            _app(
              _graph(),
              width: width,
              brightness: appearance.brightness,
              paper: appearance.paper,
              textScaler: TextScaler.linear(scale),
            ),
          );
          await tester.pumpAndSettle();
          final graph = _key('shadbala-graph');
          expect(tester.getSize(graph).width, width);
          expect(tester.getSize(graph).height, inInclusiveRange(260, 320));
          final palette = AstrologyPalette.of(tester.element(graph));
          expect(_fillColor(tester, VedicBody.sun), palette.accent);
          expect(
            tester.renderObject(_key('shadbala-graph-grid')),
            paints..line(color: palette.muted.withValues(alpha: 0.65)),
          );
          expect(
            find.descendant(of: graph, matching: find.byType(ColoredBox)),
            findsNothing,
          );
          for (final body in VedicBody.classical) {
            expect(_bar(body).hitTestable(), findsOneWidget);
            expect(
              _text(tester, 'shadbala-bar-${body.name}-label'),
              body.shortName,
            );
            final number = _key('shadbala-bar-${body.name}-value');
            if (width == 220) {
              expect(number, findsNothing);
            } else if (number.evaluate().isNotEmpty) {
              expect(
                tester.widget<Text>(number).data,
                _percentageLabels[body.index],
              );
            }
            expect(
              _semantics(tester, body).value,
              startsWith(
                'Strength (% of minimum): '
                '${body == VedicBody.saturn ? 'Unavailable' : _percentageLabels[body.index]}; ',
              ),
            );
          }
          final mouse =
              await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          try {
            await mouse.moveTo(tester.getCenter(_bar(VedicBody.moon)));
            await tester.pumpAndSettle();
            final hover = tester
                .widget<AnimatedContainer>(_key('shadbala-bar-moon-highlight'));
            expect((hover.decoration! as BoxDecoration).color, palette.hover);
            final card = tester.widget<DecoratedBox>(_popup(VedicBody.moon));
            expect((card.decoration as BoxDecoration).color, palette.raised);
            expect(_hoverValue(tester, VedicBody.moon, 'percentage'), '83.3%');
            if (appearance.paper) {
              expect(palette.surface, PaperTheme.editorPreviewBackground);
              expect(palette.raised, PaperTheme.popupBackground);
              expect(palette.hover.r, greaterThan(palette.hover.b));
            }
            expect(find.byType(Scrollbar), findsNothing);
            expect(find.byType(RawScrollbar), findsNothing);
          } finally {
            await mouse.removePointer();
          }
        });
      }
    }
  }

  _widgetTest('the details portal stays bounded in a narrow, short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(220, 260);
    await tester.pumpWidget(
      _app(
        _graph(),
        width: 220,
        height: 260,
        textScaler: const TextScaler.linear(2),
      ),
    );
    for (final body in VedicBody.classical) {
      await _keyPress(tester, LogicalKeyboardKey.tab);
      expect(_focusNode(tester, body).hasFocus, isTrue);
    }
    final bounds = tester.getRect(_popup(VedicBody.saturn));
    expect(bounds.left, greaterThanOrEqualTo(12));
    expect(bounds.top, greaterThanOrEqualTo(12));
    expect(bounds.right, lessThanOrEqualTo(208));
    expect(bounds.bottom, lessThanOrEqualTo(248));
    for (final metric in [
      'sthana',
      'dig',
      'kala',
      'cheshta',
      'naisargika',
      'drik',
    ]) {
      expect(_key('shadbala-hover-saturn-$metric-value'), findsOneWidget);
      expect(
        _semantics(tester, VedicBody.saturn).value.toLowerCase(),
        contains(metric),
      );
    }
    expect(_key('shadbala-hover-saturn-unavailable-note'), findsOneWidget);
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.descendant(
            of: _popup(VedicBody.saturn),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    for (var page = 0;
        page < 40 && scroll.offset < scroll.position.maxScrollExtent;
        page++) {
      await _keyPress(tester, LogicalKeyboardKey.pageDown);
    }
    expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, _epsilon));
    expect(
      tester
          .getRect(_key('shadbala-hover-saturn-unavailable-note'))
          .overlaps(bounds),
      isTrue,
    );
    expect(_focusNode(tester, VedicBody.saturn).hasFocus, isTrue);
    final end = scroll.offset;
    await _keyPress(tester, LogicalKeyboardKey.pageUp);
    expect(scroll.offset, lessThan(end));
    expect(find.byType(Scrollbar), findsNothing);
    expect(find.byType(RawScrollbar), findsNothing);
  });

  _widgetTest(
      'labels, painted-axis space and portal preserve real font scaling and axes',
      (
    tester,
  ) async {
    final rows = _rows();
    const scaler = _NonlinearTextScaler();
    const variations = [ui.FontVariation('wght', 325)];
    const features = [ui.FontFeature('kern')];
    await tester.pumpWidget(
      _app(
        _graph(rows: rows),
        weight: FontWeight.w300,
        fontVariations: variations,
        fontFeatures: features,
        textScaler: scaler,
      ),
    );
    expect(tester.getSize(_key('shadbala-graph')).height, 320);
    final label = tester.widget<Text>(_key('shadbala-bar-sun-label'));
    expect(label.style!.fontWeight, FontWeight.w300);
    expect(label.style!.fontVariations, variations);
    expect(
      label.style!.fontFeatures,
      containsAll(
        [
          const ui.FontFeature('kern'),
          const ui.FontFeature.tabularFigures(),
        ],
      ),
    );
    expect(label.textScaler!.scale(11), 22);
    final axisLabel = TextPainter(
      text: TextSpan(text: '-40%', style: label.style!.copyWith(fontSize: 10)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final gutter = tester.getRect(_key('shadbala-plot')).left -
        tester.getRect(_key('shadbala-graph')).left;
    expect(gutter, closeTo(axisLabel.width + 6, _epsilon));
    axisLabel.dispose();
    await _keyPress(tester, LogicalKeyboardKey.tab);
    final valueFinder = _key('shadbala-hover-sun-total-value');
    final value = tester.widget<Text>(valueFinder);
    expect(value.style!.fontWeight, FontWeight.w300);
    expect(value.style!.fontVariations, variations);
    expect(
      value.style!.fontFeatures,
      contains(const ui.FontFeature.tabularFigures()),
    );
    expect(MediaQuery.textScalerOf(tester.element(valueFinder)).scale(12), 30);
    expect(_hoverValue(tester, VedicBody.sun, 'total'), '240.00');
    expect(
      _hoverValue(tester, VedicBody.sun, 'percentage'),
      '80%',
      reason: 'Sun: 240 / 300 * 100 = 80%, independent of font scaling.',
    );
  });

  _widgetTest(
    'sub-percent negative axis labels reserve a decimal and percent sign',
    (tester) async {
      final rows = _rows()..[2] = _totalRow(VedicBody.mars, -1.2);
      await tester.pumpWidget(_app(_graph(rows: rows)));
      final label = tester.widget<Text>(_key('shadbala-bar-sun-label'));
      final axisLabel = TextPainter(
        text: TextSpan(
          text: '-0.4%',
          style: label.style!.copyWith(fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final gutter = tester.getRect(_key('shadbala-plot')).left -
          tester.getRect(_key('shadbala-graph')).left;
      expect(gutter, closeTo(axisLabel.width + 6, _epsilon));
      axisLabel.dispose();
      expect(_text(tester, 'shadbala-bar-mars-value'), '-0.4%');
    },
  );
}

ShadbalaRow _row(
  VedicBody body, {
  double sthana = 100,
  double dig = 20,
  double? kala = 30,
  double cheshta = 40,
  double naisargika = 60,
  double drik = -10,
}) =>
    ShadbalaRow(
      body: body,
      sthana: sthana,
      dig: dig,
      kala: kala,
      cheshta: cheshta,
      naisargika: naisargika,
      drik: drik,
      breakdown: const {},
      motion: 'Sama',
    );

ShadbalaRow _totalRow(VedicBody body, double total) => _row(
      body,
      sthana: total,
      dig: 0,
      kala: 0,
      cheshta: 0,
      naisargika: 0,
      drik: 0,
    );

List<ShadbalaRow> _rows() => [
      _row(VedicBody.sun),
      _row(VedicBody.moon, sthana: 160),
      _row(VedicBody.mars, drik: -370),
      _row(VedicBody.mercury, sthana: 280),
      _row(VedicBody.jupiter, sthana: 340),
      _row(VedicBody.venus, drik: -250),
      _row(VedicBody.saturn, kala: null),
    ];

AstrologyShadbalaGraph _graph({
  List<ShadbalaRow>? rows,
  VedicBody? selected = VedicBody.sun,
  ValueChanged<VedicBody>? onSelected,
}) =>
    AstrologyShadbalaGraph(
      rows: rows ?? _rows(),
      selected: selected,
      onSelected: onSelected ?? _ignoreSelection,
    );

void _ignoreSelection(VedicBody body) {}

Widget _app(
  Widget child, {
  double? width = 760,
  double? height,
  Brightness brightness = Brightness.light,
  bool paper = false,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  FontWeight weight = FontWeight.w400,
  List<ui.FontVariation>? fontVariations,
  List<ui.FontFeature>? fontFeatures,
}) =>
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(
        brightness: brightness,
        extensions: [PaperThemeExtension(enabled: paper)],
      ),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => MediaQuery(
              // Deliberately local: OverlayPortal must retain these overrides,
              // not silently use the Navigator's default text scale or style.
              data: MediaQuery.of(context).copyWith(
                textScaler: textScaler,
                disableAnimations: disableAnimations,
                accessibleNavigation: accessibleNavigation,
              ),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontWeight: weight,
                  fontVariations: fontVariations,
                  fontFeatures: fontFeatures,
                ),
                child: SizedBox(width: width, height: height, child: child),
              ),
            ),
          ),
        ),
      ),
    );

void _widgetTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(
    name,
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1280, 900);
      final semantics = tester.ensureSemantics();
      try {
        await body(tester);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        semantics.dispose();
        tester.view.reset();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _bar(VedicBody body) => _key('shadbala-bar-${body.name}');

Finder _popup(VedicBody body) => _key('shadbala-hover-${body.name}');

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;

String _hoverValue(WidgetTester tester, VedicBody body, String metric) =>
    _text(tester, 'shadbala-hover-${body.name}-$metric-value');

SemanticsData _semantics(WidgetTester tester, VedicBody body) => tester
    .getSemantics(_key('shadbala-bar-${body.name}-semantics'))
    .getSemanticsData();

FocusNode _focusNode(WidgetTester tester, VedicBody body) =>
    tester.widget<FocusableActionDetector>(_bar(body)).focusNode!;

Color? _fillColor(WidgetTester tester, VedicBody body) => (tester
        .widget<DecoratedBox>(_key('shadbala-bar-${body.name}-fill'))
        .decoration as BoxDecoration)
    .color;

void _expectSelection(
  WidgetTester tester,
  VedicBody? selected, {
  VedicBody? hovered,
}) {
  final palette = AstrologyPalette.of(tester.element(_key('shadbala-graph')));
  for (final body in VedicBody.classical) {
    expect(
      _semantics(tester, body).hasFlag(ui.SemanticsFlag.isSelected),
      body == selected,
      reason: '${body.label} selection belongs to the caller.',
    );
    final highlight = tester.widget<AnimatedContainer>(
      _key('shadbala-bar-${body.name}-highlight'),
    );
    expect(
      (highlight.decoration! as BoxDecoration).color,
      body == selected
          ? palette.selection
          : body == hovered
              ? palette.hover
              : palette.surface.withValues(alpha: 0),
    );
    if (_totals[body.index] != null) {
      expect(
        _fillColor(tester, body),
        body == selected ? palette.accent : palette.planetColor(body),
      );
    }
  }
}

Future<void> _keyPress(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize <= 11 ? 2 : 2.5);

  @override
  double get textScaleFactor => 2.5;
}
