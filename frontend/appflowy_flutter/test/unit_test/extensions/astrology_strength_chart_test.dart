import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_shadbala_graph.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_strength_chart.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/shadbala.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Deliberately supplied rows exercise the presentation boundary, including
// negative, zero and missing values. No engine, native library, assets or I/O.
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

void main() {
  _widgetTest(
    'vertical rectangles share a percent axis with one full-width 100% guide',
    (tester) async {
      await tester.pumpWidget(_host(_chart()));
      final plot = tester.getRect(_key('shadbala-plot'));
      const maximum = 480 / 390 * 100;
      const span = maximum + 40;
      final zero = plot.top + plot.height * maximum / span;
      final grid = tester.widget<CustomPaint>(_key('shadbala-graph-grid'));
      expect(grid.painter, isNotNull);
      expect(grid.foregroundPainter, isNull);
      for (var index = 0; index < VedicBody.classical.length; index++) {
        final body = VedicBody.classical[index];
        final prefix = 'shadbala-bar-${body.name}';
        final slot = tester.getRect(_key(prefix));
        expect(slot.width, greaterThanOrEqualTo(44));
        expect(
          slot.left,
          closeTo(plot.left + index * plot.width / 7, _epsilon),
        );
        final total = _totals[index];
        final percentage = _percentages[index];
        if (percentage == null) {
          expect(_key('$prefix-fill'), findsNothing);
          expect(_key('$prefix-unavailable'), findsOneWidget);
        } else {
          final bar = tester.getRect(_key('$prefix-fill'));
          expect(
            bar.top,
            closeTo(
              zero - math.max(percentage, 0) * plot.height / span,
              _epsilon,
            ),
          );
          expect(
            bar.bottom,
            closeTo(
              zero - math.min(percentage, 0) * plot.height / span,
              _epsilon,
            ),
          );
          expect(bar.center.dx, closeTo(slot.center.dx, _epsilon));
          expect(bar.width, lessThanOrEqualTo(44));
        }
        final planetPlot = tester.getRect(_key('$prefix-plot'));
        expect(planetPlot.left, closeTo(slot.left, _epsilon));
        expect(planetPlot.right, closeTo(slot.right, _epsilon));
        expect(planetPlot.top, closeTo(plot.top, _epsilon));
        expect(planetPlot.bottom, closeTo(plot.bottom, _epsilon));
        expect(_text(tester, '$prefix-value'), _percentageLabels[index]);
        expect(_key('$prefix-marker'), findsNothing);
        expect(
          find.descendant(of: _bar(body), matching: find.byType(CustomPaint)),
          findsNothing,
        );
        final semantics =
            tester.getSemantics(_key('$prefix-semantics')).getSemanticsData();
        expect(semantics.label, '${body.label} relative Shadbala');
        expect(
          semantics.value,
          startsWith(
            'Strength (% of minimum): '
            '${total == null ? 'Unavailable' : _percentageLabels[index]}; ',
          ),
        );
        expect(
          semantics.value,
          contains(
            'Total (virupas): ${total?.toStringAsFixed(2) ?? 'Unavailable'}',
          ),
        );
        expect(
          semantics.value,
          contains(
            'Required (virupas): ${_required[index].toStringAsFixed(2)}',
          ),
        );
        expect(
          semantics.value,
          contains(
            'Ratio: ${total == null ? 'Unavailable' : (total / _required[index]).toStringAsFixed(3)}',
          ),
        );
        expect(semantics.hasAction(ui.SemanticsAction.tap), isTrue);
      }
      final localPlot = plot.shift(-tester.getTopLeft(_key('shadbala-graph')));
      final minimumY =
          localPlot.top + localPlot.height * (maximum - 100) / span;
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
                (start.dy - minimumY).abs() < _epsilon &&
                (end.dy - minimumY).abs() < _epsilon &&
                paint.strokeWidth == 0.5;
          }),
      );
      expect(tester.getSize(_key('shadbala-bar-venus-fill')).height, 0);
      expect(
        tester.getSize(_key('shadbala-bar-sun-fill')).height,
        greaterThan(tester.getSize(_key('shadbala-bar-sun-fill')).width),
      );
      expect(_key('shadbala-bar-saturn-plot'), findsOneWidget);
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
    },
  );

  for (final appearance in const [
    (name: 'light', brightness: Brightness.light, paper: false),
    (name: 'dark', brightness: Brightness.dark, paper: false),
    (name: 'paper', brightness: Brightness.light, paper: true),
  ]) {
    for (final scale in [1.0, 2.0]) {
      _widgetTest(
          '220px ${appearance.name} ${scale}x pans and reveals keyboard focus',
          (tester) async {
        final vertical = ScrollController();
        addTearDown(vertical.dispose);
        final changes = <VedicBody>[];
        await tester.pumpWidget(
          _host(
            _chart(onSelected: changes.add),
            size: const Size(220, 380),
            controller: vertical,
            brightness: appearance.brightness,
            paper: appearance.paper,
            textScaler: TextScaler.linear(scale),
          ),
        );
        expect(
          tester.getSize(_key('shadbala-graph')).width,
          scale == 1 ? 568.0 : 1072.0,
          reason: 'Reserve 64px plus seven 72px slots scaled with the text.',
        );
        final scroll = tester.widget<SingleChildScrollView>(
          _key('shadbala-graph-horizontal-scroll'),
        );
        final horizontal = scroll.controller!;
        expect(scroll.primary, isFalse);
        expect(scroll.scrollDirection, Axis.horizontal);
        expect(identical(horizontal, vertical), isFalse);
        expect(horizontal.position.maxScrollExtent, greaterThan(0));
        expect(vertical.position.maxScrollExtent, greaterThan(0));
        vertical.jumpTo(10);
        await tester.pump();
        await tester.drag(
          _key('shadbala-graph-horizontal-scroll'),
          const Offset(-100, 0),
        );
        await tester.pumpAndSettle();
        expect(horizontal.offset, greaterThan(0));
        expect(vertical.offset, 10);
        expect(changes, isEmpty, reason: 'Panning is not a planet selection.');
        horizontal.jumpTo(0);
        await tester.pump();

        _focus(tester, VedicBody.sun).requestFocus();
        await tester.pumpAndSettle();
        final viewport =
            tester.getRect(_key('shadbala-graph-horizontal-scroll'));
        for (final body in VedicBody.classical) {
          if (body != VedicBody.sun) {
            await _press(tester, LogicalKeyboardKey.arrowRight);
          }
          expect(_focus(tester, body).hasPrimaryFocus, isTrue);
          final slot = tester.getRect(_bar(body));
          expect(slot.width, greaterThanOrEqualTo(44));
          expect(slot.left, greaterThanOrEqualTo(viewport.left - _epsilon));
          expect(slot.right, lessThanOrEqualTo(viewport.right + _epsilon));
          expect(_key('shadbala-hover-${body.name}'), findsOneWidget);
          final number = tester.widget<Text>(
            _key('shadbala-bar-${body.name}-value'),
          );
          expect(number.data, _percentageLabels[body.index]);
          final measured = TextPainter(
            text: TextSpan(text: number.data, style: number.style),
            textDirection: TextDirection.ltr,
            textScaler: number.textScaler!,
          )..layout();
          expect(measured.width + 4, lessThanOrEqualTo(slot.width + _epsilon));
          measured.dispose();
          expect(
            _text(tester, 'shadbala-hover-${body.name}-percentage-value'),
            body == VedicBody.saturn
                ? 'Unavailable'
                : _percentageLabels[body.index],
          );
          expect(vertical.offset, 10);
        }
        final farEnd = horizontal.offset;
        expect(farEnd, greaterThan(0));
        for (var step = 0; step < 6; step++) {
          await _press(tester, LogicalKeyboardKey.arrowLeft);
        }
        expect(horizontal.offset, lessThan(farEnd));
        expect(_bar(VedicBody.sun).hitTestable(), findsOneWidget);
        expect(
          changes,
          isEmpty,
          reason: 'Focus shows details without selecting.',
        );
        await _press(tester, LogicalKeyboardKey.enter);
        await _press(tester, LogicalKeyboardKey.arrowRight);
        await _press(tester, LogicalKeyboardKey.space);
        expect(changes, [VedicBody.sun, VedicBody.moon]);

        final palette =
            AstrologyPalette.of(tester.element(_bar(VedicBody.moon)));
        final popup = tester.widget<DecoratedBox>(_key('shadbala-hover-moon'));
        expect((popup.decoration as BoxDecoration).color, palette.raised);
        final highlight = tester.widget<AnimatedContainer>(
          _key('shadbala-bar-moon-highlight'),
        );
        final border =
            (highlight.foregroundDecoration! as BoxDecoration).border!;
        expect((border as Border).top.color, palette.accent);
        final label = tester.widget<Text>(_key('shadbala-bar-moon-label'));
        expect(label.textScaler!.scale(11), closeTo(11 * scale, _epsilon));
        expect(label.style!.fontWeight, FontWeight.w300);
        if (appearance.paper) {
          expect(palette.raised, PaperTheme.popupBackground);
        }
        expect(find.byType(RawScrollbar), findsNothing);
        expect(find.byType(Scrollbar), findsNothing);
      });
    }
  }

  _widgetTest('host forwards nullable selection without selecting on its own', (
    tester,
  ) async {
    final rows = _rows();
    final changes = <VedicBody>[];
    Widget host(VedicBody? selected) => _host(
          _chart(rows: rows, selected: selected, onSelected: changes.add),
        );
    await tester.pumpWidget(
      _host(
        _chart(rows: rows, selected: null, onSelected: changes.add),
      ),
    );
    _expectSelection(tester, null);
    _focus(tester, VedicBody.sun).requestFocus();
    await tester.pumpAndSettle();
    expect(_focus(tester, VedicBody.sun).hasFocus, isTrue);
    _expectSelection(tester, null);
    await _press(tester, LogicalKeyboardKey.tab);
    expect(_focus(tester, VedicBody.moon).hasFocus, isTrue);
    _expectSelection(tester, null);
    expect(changes, isEmpty);
    _focus(tester, VedicBody.moon).unfocus();
    await tester.pumpAndSettle();

    VedicBody? selected;
    for (final body in [VedicBody.mars, VedicBody.moon]) {
      await tester.tap(_bar(body));
      await tester.pumpAndSettle();
      expect(changes.last, body);
      _expectSelection(tester, selected);
      await tester.pumpWidget(host(body));
      await tester.pumpAndSettle();
      selected = body;
      _expectSelection(tester, body);
    }
    expect(changes, [VedicBody.mars, VedicBody.moon]);
    await tester.pumpWidget(host(null));
    await tester.pumpAndSettle();
    _expectSelection(tester, null);
  });

  _widgetTest('floating details cannot intercept a neighboring column tap',
      (tester) async {
    final rows = _rows();
    var selected = VedicBody.sun;
    final changes = <VedicBody>[];
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, rebuild) => _chart(
            rows: rows,
            selected: selected,
            onSelected: (body) {
              changes.add(body);
              rebuild(() => selected = body);
            },
          ),
        ),
        size: const Size(220, 380),
      ),
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    try {
      await mouse.moveTo(tester.getCenter(_bar(VedicBody.sun)));
      await tester.pumpAndSettle();
      final popup = _key('shadbala-hover-sun');
      expect(
        _text(tester, 'shadbala-hover-sun-percentage-value'),
        '80%',
        reason: 'Sun: 240 / 300 * 100 = 80%.',
      );
      expect(
        find.descendant(
          of: popup,
          matching: find.text('Strength (% of minimum)'),
        ),
        findsOneWidget,
      );
      expect(_text(tester, 'shadbala-hover-sun-sthana-value'), '100.00');
      expect(_text(tester, 'shadbala-hover-sun-dig-value'), '20.00');
      expect(_text(tester, 'shadbala-hover-sun-kala-value'), '30.00');
      expect(_text(tester, 'shadbala-hover-sun-cheshta-value'), '40.00');
      expect(_text(tester, 'shadbala-hover-sun-naisargika-value'), '60.00');
      expect(_text(tester, 'shadbala-hover-sun-drik-value'), '-10.00');
      expect(_text(tester, 'shadbala-hover-sun-total-value'), '240.00');
      expect(_text(tester, 'shadbala-hover-sun-rupas-value'), '4.00');
      expect(
        _text(tester, 'shadbala-hover-sun-required-value'),
        '300.00',
        reason: 'Sun minimum is 300 virupas.',
      );
      expect(
        _text(tester, 'shadbala-hover-sun-ratio-value'),
        '0.800',
        reason: 'Sun: 240 / 300 = 0.800 to three decimals.',
      );
      expect(_text(tester, 'shadbala-hover-sun-motion-value'), 'Motion: Sama');
      expect(_key('shadbala-bar-sun-marker'), findsNothing);
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
      final overlap = tester
          .getRect(popup)
          .intersect(tester.getRect(_bar(VedicBody.moon)))
          .intersect(tester.getRect(_key('shadbala-graph-horizontal-scroll')))
          .deflate(2);
      expect(overlap.isEmpty, isFalse);
      await tester.tapAt(overlap.center);
      await tester.pumpAndSettle();
      expect(changes, [VedicBody.moon]);
      expect(selected, VedicBody.moon);
      expect(_key('shadbala-hover-moon'), findsOneWidget);
      expect(_text(tester, 'shadbala-hover-moon-percentage-value'), '83.3%');
      expect(_text(tester, 'shadbala-hover-moon-required-value'), '360.00');
      expect(_text(tester, 'shadbala-hover-moon-ratio-value'), '0.833');
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(selected, VedicBody.moon, reason: 'Selection outlives hover.');
    } finally {
      await mouse.removePointer();
    }
  });

  _widgetTest(
      'replacement and unavailable rows retain their data, never demo zeros',
      (tester) async {
    final rows = _rows();
    await tester.pumpWidget(_host(_chart(rows: rows)));
    final controller = tester
        .widget<SingleChildScrollView>(
          _key('shadbala-graph-horizontal-scroll'),
        )
        .controller!;
    final replacement = List.of(rows)..[0] = _row(VedicBody.sun, sthana: 260);
    await tester.pumpWidget(_host(_chart(rows: replacement)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SingleChildScrollView>(
            _key('shadbala-graph-horizontal-scroll'),
          )
          .controller,
      same(controller),
    );
    _focus(tester, VedicBody.sun).requestFocus();
    await tester.pumpAndSettle();
    expect(_text(tester, 'shadbala-hover-sun-total-value'), '400.00');
    expect(
      _text(tester, 'shadbala-hover-sun-percentage-value'),
      '133.3%',
      reason: 'Sun: 400 / 300 * 100 rounds to 133.3%.',
    );
    final plot = tester.getRect(_key('shadbala-plot'));
    expect(
      tester.getSize(_key('shadbala-bar-sun-fill')).height,
      closeTo(
        plot.height * (400 / 300 * 100) / (400 / 300 * 100 + 40),
        _epsilon,
      ),
      reason:
          'Sun 400 / 300 now exceeds Jupiter 480 / 390 and sets the maximum.',
    );
    final unavailable = [
      for (final body in VedicBody.classical) _row(body, kala: null),
    ];
    await tester.pumpWidget(_host(_chart(rows: unavailable)));
    await tester.pumpAndSettle();
    for (final body in VedicBody.classical) {
      expect(_key('shadbala-bar-${body.name}-fill'), findsNothing);
      expect(_key('shadbala-bar-${body.name}-unavailable'), findsOneWidget);
      expect(_key('shadbala-bar-${body.name}-plot'), findsOneWidget);
      expect(_key('shadbala-bar-${body.name}-marker'), findsNothing);
      expect(_text(tester, 'shadbala-bar-${body.name}-value'), '—');
    }
    await _press(tester, LogicalKeyboardKey.enter);
    for (final metric in ['percentage', 'kala', 'total', 'rupas', 'ratio']) {
      expect(_text(tester, 'shadbala-hover-sun-$metric-value'), 'Unavailable');
    }
    expect(
      _text(tester, 'shadbala-hover-sun-required-value'),
      '300.00',
      reason: 'Sun minimum stays 300 virupas when its total is unavailable.',
    );
    expect(_text(tester, 'shadbala-hover-sun-sthana-value'), '100.00');
    expect(
      _text(tester, 'shadbala-hover-sun-unavailable-note'),
      contains('not zero estimates'),
    );
  });

  _widgetTest(
      'unmount disposes the viewport and leaves no focus portal or timer',
      (tester) async {
    await tester.pumpWidget(_host(_chart()));
    final controller = tester
        .widget<SingleChildScrollView>(
          _key('shadbala-graph-horizontal-scroll'),
        )
        .controller!;
    final node = _focus(tester, VedicBody.sun);
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(_key('shadbala-hover-sun'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 2));
    expect(controller.hasClients, isFalse);
    expect(() => controller.addListener(_noop), throwsFlutterError);
    expect(node.hasFocus, isFalse);
    expect(_key('shadbala-hover-sun'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

ShadbalaRow _row(
  VedicBody body, {
  double sthana = 100,
  double? kala = 30,
  double drik = -10,
}) =>
    ShadbalaRow(
      body: body,
      sthana: sthana,
      dig: 20,
      kala: kala,
      cheshta: 40,
      naisargika: 60,
      drik: drik,
      breakdown: const {},
      motion: 'Sama',
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

AstrologyStrengthChart _chart({
  List<ShadbalaRow>? rows,
  VedicBody? selected = VedicBody.sun,
  ValueChanged<VedicBody>? onSelected,
}) =>
    AstrologyStrengthChart(
      rows: rows ?? _rows(),
      selected: selected,
      onSelected: onSelected ?? (_) {},
    );

Widget _host(
  Widget child, {
  Size size = const Size(760, 540),
  ScrollController? controller,
  Brightness brightness = Brightness.light,
  bool paper = false,
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(
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
            style: const TextStyle(fontWeight: FontWeight.w300),
            child: SizedBox.fromSize(
              size: size,
              child: ScrollConfiguration(
                behavior: const ScrollBehavior().copyWith(scrollbars: false),
                child: SingleChildScrollView(
                  key: const ValueKey('strength-host-scroll'),
                  controller: controller,
                  primary: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 20),
                      child,
                      const SizedBox(height: 500),
                    ],
                  ),
                ),
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
String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;
FocusNode _focus(WidgetTester tester, VedicBody body) =>
    tester.widget<FocusableActionDetector>(_bar(body)).focusNode!;

void _expectSelection(WidgetTester tester, VedicBody? selected) {
  final host = tester.widget<AstrologyStrengthChart>(
    find.byType(AstrologyStrengthChart),
  );
  final graph = tester.widget<AstrologyShadbalaGraph>(
    find.byType(AstrologyShadbalaGraph),
  );
  expect(host.selected, selected);
  expect(graph.selected, selected);
  final palette = AstrologyPalette.of(tester.element(_key('shadbala-graph')));
  for (final body in VedicBody.classical) {
    final prefix = 'shadbala-bar-${body.name}';
    final data =
        tester.getSemantics(_key('$prefix-semantics')).getSemanticsData();
    expect(data.hasFlag(ui.SemanticsFlag.isSelected), body == selected);
    final highlight = tester.widget<AnimatedContainer>(
      _key('$prefix-highlight'),
    );
    expect(
      (highlight.decoration! as BoxDecoration).color,
      body == selected
          ? palette.selection
          : palette.surface.withValues(alpha: 0),
    );
    if (_totals[body.index] != null) {
      final fill = tester.widget<DecoratedBox>(_key('$prefix-fill'));
      expect(
        (fill.decoration as BoxDecoration).color,
        body == selected ? palette.accent : palette.planetColor(body),
      );
    }
  }
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void _noop() {}
