import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_codec.dart'
    show parseDelimitedText;
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:easy_localization/easy_localization.dart'
    show StringTranslateExtension;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chart_appearance_test_support.dart';

const _draft = ValueKey('chart-stage-draft');
const _plotSlot = ValueKey('chart-stage-plot');
const _duplicateLabel = 'same, "point"\nfirst';
const _exportRows = [
  [_duplicateLabel, '0', '0', '', '-2'],
  [_duplicateLabel, '0', '', '-5', ''],
  ['negative', '-2', '-3', '4', '0'],
  ['line\nlabel', '5', '', '8', '-4'],
  ['missing X', '', '99', '100', '1'],
  ['missing Y', '3', '', '', '2'],
  ['short', '8', '6'],
  ['duplicate', '9', '2', '3', '1'],
  ['duplicate', '9', '4', '', ''],
];

void main() {
  setUpChartAppearanceFixtures();

  for (final appearance in chartAppearances) {
    for (final emptyKind in ['rows', 'schema', 'points']) {
      testWidgets(
          '$appearance / $emptyKind: empty live results retain the plot, '
          'controllers and interactions until fresh rows return',
          (tester) async {
        var table = chartAppearanceTable;
        Completer<ChartTable>? pending;
        var writes = 0;
        final source = ChartSource(
          viewId: 'empty-live-chart',
          loadTable: (_) => pending?.future ?? Future.value(table),
        );
        final measured = emptyKind == 'points';
        final spec = chartAppearanceSpec(
          measured ? ChartType.line : ChartType.bar,
        ).copyWith(xColumn: measured ? 'units' : null);
        final direction = ValueNotifier(TextDirection.ltr);
        final draft = TextEditingController();
        final draftFocus = FocusNode();
        final semantics = tester.ensureSemantics();
        try {
          await _mount(
            tester,
            appearance,
            ValueListenableBuilder<TextDirection>(
              valueListenable: direction,
              builder: (_, value, __) => Directionality(
                textDirection: value,
                child: _stage(
                  source,
                  spec,
                  onChanged: (_) => writes++,
                  trailing: [
                    SizedBox(
                      width: 150,
                      child: TextField(
                        key: _draft,
                        controller: draft,
                        focusNode: draftFocus,
                        decoration: const InputDecoration(isDense: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          final chart = find.byType(AppChart, skipOffstage: false);
          await tester.tap(_legend(chart, 'Revenue USD'));
          await tester.pumpAndSettle();
          await tester.tap(_zoomIn(chart));
          await tester.pump(kDoubleTapTimeout);
          await tester.pumpAndSettle();
          final state = tester.state(chart);
          final element = tester.element(chart);
          final plot = tester.renderObject<RenderCustomPaint>(_plot(chart));
          final switcher = tester.state(_switcher);
          final slot =
              tester.renderObject<RenderOffstage>(find.byKey(_plotSlot));
          final reveal = _painter(tester, chart).reveal as CurvedAnimation;
          final revealController = reveal.parent;
          final emphasis = _painter(tester, chart).emphasis;
          final viewport = _painter(tester, chart).viewport;
          expect(viewport.scale, closeTo(1.4, 0.000001));
          expect(_painter(tester, chart).hidden, {0});
          expect(revealController, isA<AnimationController>());
          await tester.enterText(find.byKey(_draft), 'unsaved chart note');
          draft.selection = const TextSelection(baseOffset: 2, extentOffset: 9);
          final draftValue = draft.value;
          final draftState = tester.state(find.byType(EditableText));

          table = emptyKind == 'schema'
              ? ChartTable.empty
              : ChartTable(
                  columns: chartAppearanceTable.columns,
                  columnIds: chartAppearanceTable.columnIds,
                  rows: measured
                      ? const [
                          ['No X', '24', '12', '2026-09-01', '', '4'],
                        ]
                      : const [],
                );
          expect(buildChartData(table, spec).isEmpty, isTrue);
          if (measured) expect(table.isEmpty, isFalse);
          source.invalidate();
          await tester.pump(source.settle);
          await tester.pumpAndSettle();

          void expectRetained() {
            expect(chart, findsOneWidget);
            expect(tester.state(chart), same(state));
            expect(tester.element(chart), same(element));
            expect(tester.renderObject(_plot(chart)), same(plot));
            expect(plot.attached, isTrue);
            expect(tester.state(_switcher), same(switcher));
            expect(
              tester.renderObject(find.byKey(_plotSlot)),
              same(slot),
            );
            expect(_painter(tester, chart).viewport, viewport);
            expect(_painter(tester, chart).hidden, {0});
            expect(_painter(tester, chart).reveal, same(reveal));
            expect(reveal.parent, same(revealController));
            expect(_painter(tester, chart).emphasis, same(emphasis));
            expect(tester.state(find.byType(EditableText)), same(draftState));
            expect(draft.value, draftValue);
            expect(draftFocus.hasFocus, isTrue);
          }

          expectRetained();
          expect(find.byType(AppChart), findsNothing);
          expect(find.byType(ChartEmptyState), findsOneWidget);
          expect(slot.offstage, isTrue);
          expect(TickerMode.of(tester.element(chart)), isFalse);
          expect(tester.widget<AppChart>(chart).data.isEmpty, isFalse);
          expect(tester.widget<AppChart>(chart).data.measuresX, measured);
          expect(_legend(chart, 'Revenue USD').hitTestable(), findsNothing);
          expect(find.semantics.byLabel('Revenue USD'), findsNothing);
          final hiddenFocus = Focus.of(
            tester.element(_legend(chart, 'Revenue USD')),
          );
          expect(hiddenFocus.canRequestFocus, isFalse);
          hiddenFocus.requestFocus();
          await tester.pump();
          await tester.pump();
          expect(draftFocus.hasFocus, isTrue);

          direction.value = TextDirection.rtl;
          await tester.pumpAndSettle();
          expectRetained();
          expect(Directionality.of(tester.element(chart)), TextDirection.rtl);

          // Also keep the slot through the loading frame after an empty read.
          // Do not settle while the loading skeleton's ticker is running.
          pending = Completer<ChartTable>();
          final reload = source.load();
          await tester.pump();
          expect(source.isLoading, isTrue);
          expect(find.byType(AppChart), findsNothing);
          expectRetained();
          table = ChartTable(
            columns: chartAppearanceTable.columns,
            columnIds: chartAppearanceTable.columnIds,
            rows: [
              ['North', '124.5', '112', '2026-09-01', '4', '4'],
              ...chartAppearanceTable.rows.skip(1),
              ['Fifth', '42', '21', '2026-09-05', '12', '8'],
            ],
          );
          pending.complete(table);
          await reload;
          pending = null;
          await tester.pumpAndSettle();
          expectRetained();
          expect(find.byType(AppChart), findsOneWidget);
          expect(find.byType(ChartEmptyState), findsNothing);
          expect(slot.offstage, isFalse);
          expect(TickerMode.of(tester.element(chart)), isTrue);
          final data = _painter(tester, chart).data;
          expect(data.series.first.points, hasLength(5));
          expect(
            data.series.first.points
                .firstWhere((p) => p.label == 'North')
                .value,
            124.5,
          );
          expect(data.series.first.points.last.label, 'Fifth');
          expect(data.series.first.points.last.value, 42);
          if (measured) expect(data.series.first.points.last.x, 12);
          expect(_painter(tester, chart).spec.type, spec.type);
          expect(_legend(chart, 'Revenue USD').hitTestable(), findsOneWidget);
          expect(find.semantics.byLabel('Revenue USD'), findsOneWidget);
          await tester.tap(_legend(chart, 'Revenue USD'));
          await tester.pumpAndSettle();
          expect(_painter(tester, chart).hidden, isEmpty);
          expect(writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          if (pending != null && !pending.isCompleted) pending.complete(table);
          await tester.pumpWidget(const SizedBox());
          source.dispose();
          direction.dispose();
          draft.dispose();
          draftFocus.dispose();
          semantics.dispose();
        }
      });
    }

    for (final accessible in [false, true]) {
      testWidgets(
          '$appearance / accessible=$accessible: midfade motion changes hide '
          'outgoing paint without replacing the current chart', (tester) async {
        final source = ChartSource(
          viewId: 'midfade-chart',
          loadTable: (_) async => chartAppearanceTable,
        );
        final settings = ValueNotifier(
          (
            spec: chartAppearanceSpec(ChartType.bar),
            reduced: false,
          ),
        );
        try {
          await _mount(
            tester,
            appearance,
            ValueListenableBuilder<({ChartSpec spec, bool reduced})>(
              valueListenable: settings,
              builder: (context, value, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: value.reduced && !accessible,
                  accessibleNavigation: value.reduced && accessible,
                ),
                child: _stage(source, value.spec),
              ),
            ),
          );
          final outgoing = _chart(ChartType.bar);
          final outgoingState = tester.state(outgoing);
          final switcherState = tester.state(_switcher);
          final builder =
              tester.widget<AnimatedSwitcher>(_switcher).transitionBuilder;
          settings.value = (
            spec: settings.value.spec.copyWith(type: ChartType.line),
            reduced: false,
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          final current = _chart(ChartType.line);
          final currentState = tester.state(current);
          final plot = tester.renderObject(_plot(current));
          final fade =
              tester.renderObject<RenderAnimatedOpacity>(_fade(current));
          final switchAnimation =
              tester.widget<FadeTransition>(_fade(current)).opacity;
          final reveal = _painter(tester, current).reveal as CurvedAnimation;
          expect(switchAnimation.value, inExclusiveRange(0, 1));
          expect(
            tester.widget<FadeTransition>(_fade(outgoing)).opacity.value,
            inExclusiveRange(0, 1),
          );
          _expectOutgoing(tester, outgoing);

          // Keyboard activation changes real interactions without advancing
          // the clock far enough to accidentally finish the crossfade.
          Focus.of(tester.element(_legend(current, 'Revenue USD')))
              .requestFocus();
          await tester.pump();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          final zoomFocus = Focus.of(
            tester.element(
              find.descendant(
                of: _zoomIn(current),
                matching: find.byType(WorkspaceGlyph),
              ),
            ),
          );
          zoomFocus.requestFocus();
          await tester.pump();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          final viewport = _painter(tester, current).viewport;
          expect(viewport.scale, closeTo(1.4, 0.000001));
          expect(_painter(tester, current).hidden, {0});
          expect(zoomFocus.hasPrimaryFocus, isTrue);

          settings.value = (spec: settings.value.spec, reduced: true);
          await tester.pump();
          await tester.pump();
          expect(tester.state(current), same(currentState));
          expect(tester.renderObject(_plot(current)), same(plot));
          expect(tester.renderObject(_fade(current)), same(fade));
          expect(tester.state(_switcher), same(switcherState));
          expect(
            tester.widget<AnimatedSwitcher>(_switcher).transitionBuilder,
            builder,
          );
          expect(
            tester.widget<AnimatedSwitcher>(_switcher).duration,
            Duration.zero,
          );
          expect(
            tester.widget<FadeTransition>(_fade(current)).opacity.value,
            1,
          );
          expect(
            tester.widget<FadeTransition>(_fade(outgoing)).opacity.value,
            0,
          );
          expect(
            outgoingState.mounted,
            isTrue,
            reason:
                'The old duration is still in progress, but is not painted.',
          );
          expect(_painter(tester, current).reveal.value, 1);
          expect(reveal.parent.value, 1);
          expect(_painter(tester, current).viewport, viewport);
          expect(_painter(tester, current).hidden, {0});
          expect(FocusManager.instance.primaryFocus, same(zoomFocus));
          _expectOutgoing(tester, outgoing);
          expect(_zoomIn(current).hitTestable(), findsOneWidget);

          await tester.pump(
            ChartMetrics.morphDuration + const Duration(microseconds: 1),
          );
          expect(outgoingState.mounted, isFalse);
          settings.value = (spec: settings.value.spec, reduced: false);
          await tester.pumpAndSettle();
          expect(tester.state(current), same(currentState));
          expect(tester.renderObject(_plot(current)), same(plot));
          expect(tester.renderObject(_fade(current)), same(fade));
          expect(
            tester.widget<FadeTransition>(_fade(current)).opacity,
            same(switchAnimation),
          );
          expect(_painter(tester, current).reveal, same(reveal));
          expect(_painter(tester, current).viewport, viewport);
          expect(_painter(tester, current).hidden, {0});
          await tester.tap(_legend(current, 'Revenue USD'));
          await tester.pumpAndSettle();
          expect(_painter(tester, current).hidden, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          settings.dispose();
          source.dispose();
        }
      });
    }
  }

  testWidgets(
      'first data keeps the existing entrance; replacing the source '
      'with an empty one cannot revive the previous plot', (tester) async {
    final pending = Completer<ChartTable>();
    final first = ChartSource(
      viewId: 'first-reading',
      loadTable: (_) => pending.future,
    );
    var secondTable = ChartTable.empty;
    final second = ChartSource(
      viewId: 'second-reading',
      loadTable: (_) async => secondTable,
    );
    final selected = ValueNotifier(first);
    try {
      await _mount(
        tester,
        'light',
        ValueListenableBuilder<ChartSource>(
          valueListenable: selected,
          builder: (_, source, __) => _stage(
            source,
            chartAppearanceSpec(ChartType.bar),
          ),
        ),
        settle: false,
      );
      expect(first.isLoading, isTrue);
      expect(find.byType(AppChart, skipOffstage: false), findsNothing);
      pending.complete(chartAppearanceTable);
      await tester.pump();
      await tester.pump();
      final chart = _chart(ChartType.bar);
      expect(tester.widget<FadeTransition>(_fade(chart)).opacity.value, 1);
      await tester.pumpAndSettle();
      await tester.tap(_legend(chart, 'Revenue USD'));
      await tester.pumpAndSettle();
      await tester.tap(_zoomIn(chart));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      final state = tester.state(chart);
      expect(_painter(tester, chart).hidden, {0});
      expect(_painter(tester, chart).viewport.isIdentity, isFalse);

      selected.value = second;
      await tester.pumpAndSettle();
      expect(find.byType(AppChart, skipOffstage: false), findsNothing);
      expect(find.byType(ChartEmptyState), findsOneWidget);
      expect(state.mounted, isFalse);
      await first.load();
      await tester.pumpAndSettle();
      expect(find.byType(AppChart, skipOffstage: false), findsNothing);
      secondTable = chartAppearanceTable;
      await second.load();
      await tester.pumpAndSettle();
      expect(tester.state(chart), isNot(same(state)));
      expect(_painter(tester, chart).hidden, isEmpty);
      expect(_painter(tester, chart).viewport.isIdentity, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) pending.complete(ChartTable.empty);
      await tester.pumpWidget(const SizedBox());
      selected.dispose();
      first.dispose();
      second.dispose();
    }
  });

  testWidgets(
      'outgoing charts lose keyboard, pointer and semantics at the '
      'switch, before the first reverse tick', (tester) async {
    final source = ChartSource(
      viewId: 'outgoing-chart',
      loadTable: (_) async => chartAppearanceTable,
    );
    final spec = ValueNotifier(chartAppearanceSpec(ChartType.bar));
    final semantics = tester.ensureSemantics();
    try {
      await _mount(
        tester,
        'light',
        ValueListenableBuilder<ChartSpec>(
          valueListenable: spec,
          builder: (_, value, __) => _stage(source, value),
        ),
      );
      final outgoing = _chart(ChartType.bar);
      final outgoingElement = tester.element(outgoing);
      final oldState = tester.state(outgoing);
      final oldLegend = _legend(outgoing, 'Revenue USD');
      final oldPosition = tester.getCenter(oldLegend);
      final oldFocus = Focus.of(tester.element(oldLegend));
      oldFocus.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(oldFocus.hasPrimaryFocus, isTrue);
      final oldSemantics =
          find.semantics.byLabel('Revenue USD').evaluate().single;
      expect(oldSemantics.attached, isTrue);
      spec.value = spec.value.copyWith(type: ChartType.pie);
      await tester.pump();
      await tester.pump();
      expect(oldState.mounted, isTrue);
      expect(tester.widget<FadeTransition>(_fade(outgoing)).opacity.value, 1);
      _expectOutgoing(tester, outgoing);
      expect(oldFocus.canRequestFocus, isFalse);
      expect(oldFocus.hasFocus, isFalse);
      expect(find.semantics.byLabel('Revenue USD'), findsNothing);
      expect(oldSemantics.attached, isFalse);

      Focus.of(tester.element(find.text('Outside chart'))).requestFocus();
      await tester.pump();
      await tester.pump();
      oldFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      for (var index = 0; index < 8; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.pump();
        expect(_focusInside(outgoingElement), isFalse);
      }
      await tester.pump(const Duration(milliseconds: 80));
      expect(oldLegend.hitTestable(), findsNothing);
      await tester.tapAt(oldPosition, kind: PointerDeviceKind.mouse);
      await tester.pump(kDoubleTapTimeout);
      expect(oldState.mounted, isTrue);
      expect(_painter(tester, outgoing).hidden, isEmpty);
      _expectOutgoing(tester, outgoing);
      expect(_painter(tester, _chart(ChartType.pie)).spec.type, ChartType.pie);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      source.dispose();
      spec.dispose();
      semantics.dispose();
    }
  });

  testWidgets('rapid A to B to A excludes the older same-key chart',
      (tester) async {
    final source = ChartSource(
      viewId: 'rapid-chart',
      loadTable: (_) async => chartAppearanceTable,
    );
    final spec = ValueNotifier(chartAppearanceSpec(ChartType.bar));
    final semantics = tester.ensureSemantics();
    try {
      await _mount(
        tester,
        'paper',
        ValueListenableBuilder<ChartSpec>(
          valueListenable: spec,
          builder: (_, value, __) => _stage(source, value),
        ),
      );
      final firstState = tester.state(_chart(ChartType.bar));
      spec.value = spec.value.copyWith(type: ChartType.line);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      spec.value = spec.value.copyWith(type: ChartType.bar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final bars = _chart(ChartType.bar);
      expect(bars, findsNWidgets(2));
      expect(
        tester.widget<AppChart>(bars.first).key,
        tester.widget<AppChart>(bars.last).key,
      );
      expect(tester.state(bars.first), same(firstState));
      expect(tester.state(bars.last), isNot(same(firstState)));
      _expectOutgoing(tester, bars.first);
      _expectOutgoing(tester, _chart(ChartType.line));
      expect(
        tester.widget<IgnorePointer>(_guard(bars.last, IgnorePointer)).ignoring,
        isFalse,
      );
      expect(_legend(bars.last, 'Revenue USD').hitTestable(), findsOneWidget);
      expect(find.semantics.byLabel('Revenue USD'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(firstState.mounted, isFalse);
      expect(_painter(tester, _chart(ChartType.bar)).spec.type, ChartType.bar);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      spec.dispose();
      source.dispose();
      semantics.dispose();
    }
  });

  testWidgets(
      'direction changes retain state; a real type change while empty '
      'uses the requested type when data returns', (tester) async {
    var table = chartAppearanceTable;
    final source =
        ChartSource(viewId: 'chart-direction', loadTable: (_) async => table);
    final settings = ValueNotifier(
      (
        spec: chartAppearanceSpec(ChartType.bar),
        direction: TextDirection.ltr,
      ),
    );
    try {
      await _mount(
        tester,
        'dark',
        ValueListenableBuilder<({ChartSpec spec, TextDirection direction})>(
          valueListenable: settings,
          builder: (_, value, __) => Directionality(
            textDirection: value.direction,
            child: _stage(source, value.spec),
          ),
        ),
      );
      final chart = _chart(ChartType.bar);
      await tester.tap(_legend(chart, 'Revenue USD'));
      await tester.pumpAndSettle();
      await tester.tap(_zoomIn(chart));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      final state = tester.state(chart);
      final render = tester.renderObject(_plot(chart));
      final viewport = _painter(tester, chart).viewport;
      settings.value =
          (spec: settings.value.spec, direction: TextDirection.rtl);
      await tester.pumpAndSettle();
      expect(tester.state(chart), same(state));
      expect(tester.renderObject(_plot(chart)), same(render));
      expect(_painter(tester, chart).viewport, viewport);
      expect(_painter(tester, chart).hidden, {0});
      expect(_painter(tester, chart).spec.type, ChartType.bar);

      table = ChartTable.empty;
      await source.load();
      await tester.pumpAndSettle();
      settings.value = (
        spec: settings.value.spec.copyWith(type: ChartType.horizontalBar),
        direction: TextDirection.rtl,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppChart), findsNothing);
      expect(
        tester.state(_chart(ChartType.bar, skipOffstage: false)),
        same(state),
      );
      table = chartAppearanceTable;
      await source.load();
      await tester.pumpAndSettle();
      final horizontal = _chart(ChartType.horizontalBar);
      expect(horizontal, findsOneWidget);
      expect(state.mounted, isFalse);
      expect(_painter(tester, horizontal).spec.type, ChartType.horizontalBar);
      expect(_painter(tester, horizontal).viewport.isIdentity, isTrue);
      expect(_painter(tester, horizontal).hidden, isEmpty);
      expect(_zoomIn(horizontal), findsNothing);
      expect(_painter(tester, horizontal).hits, hasLength(8));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
      source.dispose();
    }
  });

  for (final type in [
    ChartType.line,
    ChartType.area,
    ChartType.scatter,
    ChartType.bubble,
  ]) {
    testWidgets(
        '${type.name}: export uses current field names and every XY '
        'point, preserving missing values, labels, sizes and CSV quoting',
        (tester) async {
      var table = const ChartTable(
        columns: ['Old label', 'Old X', 'Old first', 'Old second', 'Old size'],
        columnIds: ['label-id', 'x-id', 'first-id', 'second-id', 'size-id'],
        rows: _exportRows,
      );
      var writes = 0;
      final source =
          ChartSource(viewId: 'export-xy', loadTable: (_) async => table);
      final spec = ChartSpec(
        type: type,
        categoryColumn: 'label-id',
        xColumn: 'x-id',
        valueColumns: const ['first-id', 'second-id'],
        sizeColumn: 'size-id',
      );
      final clipboard = _Clipboard(tester);
      try {
        await _mount(
          tester,
          'paper',
          _stage(source, spec, onChanged: (_) => writes++),
        );
        final chart = _chart(type);
        expect(tester.widget<AppChart>(chart).data.categories, isEmpty);
        await tester.tap(_legend(chart, 'Old first'));
        await tester.pumpAndSettle();
        final state = tester.state(chart);
        await _openExport(tester);
        table = ChartTable(
          columns: const [
            'Point, "label"',
            'X,\n"km"',
            'Y, "first"',
            'Y\nsecond',
            'Weight "kg"',
          ],
          columnIds: table.columnIds,
          rows: [
            ..._exportRows,
            ['Refreshed\r\npoint', '10', '-7', '0', '0'],
          ],
        );
        await source.load();
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        expect(tester.state(chart), same(state));
        expect(_painter(tester, chart).hidden, {0});
        await _selectExport(tester);
        final rows = parseDelimitedText(clipboard.text!, delimiter: ',');
        final sized = type.sizesPoints;
        expect(rows.first, [
          'X,\n"km"',
          'Point, "label"',
          'Y, "first"',
          'Y\nsecond',
          if (sized) 'Weight "kg"',
        ]);
        expect(
          rows.skip(1),
          unorderedEquals([
            ['-2.0', 'negative', '-3.0', '', if (sized) '0.0'],
            ['0.0', _duplicateLabel, '0.0', '', if (sized) '-2.0'],
            ['8.0', 'short', '6.0', '', if (sized) ''],
            ['9.0', 'duplicate', '2.0', '', if (sized) '1.0'],
            ['9.0', 'duplicate', '4.0', '', if (sized) ''],
            ['10.0', 'Refreshed\r\npoint', '-7.0', '', if (sized) '0.0'],
            ['-2.0', 'negative', '', '4.0', if (sized) '0.0'],
            ['0.0', _duplicateLabel, '', '-5.0', if (sized) ''],
            ['5.0', 'line\nlabel', '', '8.0', if (sized) '-4.0'],
            ['9.0', 'duplicate', '', '3.0', if (sized) '1.0'],
            ['10.0', 'Refreshed\r\npoint', '', '0.0', if (sized) '0.0'],
          ]),
        );
        expect(clipboard.text, contains('"same, ""point""\nfirst"'));
        expect(clipboard.text, contains('"Refreshed\r\npoint"'));
        expect(clipboard.text, isNot(contains('Old X')));
        expect(clipboard.text, isNot(contains('missing X')));
        expect(clipboard.text, isNot(contains('missing Y')));
        expect(writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        source.dispose();
        clipboard.dispose();
      }
    });
  }

  testWidgets(
      'measured export without point labels contains X and Y, not '
      'an invented category column', (tester) async {
    const table = ChartTable(
      columns: ['X', 'Y'],
      rows: [
        ['0', '-2'],
        ['-3', '0'],
        ['4', ''],
      ],
    );
    final source =
        ChartSource(viewId: 'export-no-label', loadTable: (_) async => table);
    final clipboard = _Clipboard(tester);
    try {
      await _mount(
        tester,
        'light',
        _stage(
          source,
          const ChartSpec(
            type: ChartType.scatter,
            xColumn: 'X',
            valueColumns: ['Y'],
          ),
        ),
      );
      await _openExport(tester);
      await _selectExport(tester);
      expect(parseDelimitedText(clipboard.text!, delimiter: ','), [
        ['X', 'Y'],
        ['-3.0', '0.0'],
        ['0.0', '-2.0'],
      ]);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      source.dispose();
      clipboard.dispose();
    }
  });

  testWidgets(
      'categorical export keeps rows and zero/negative values quoted; '
      'an empty result never exports the retained plot', (tester) async {
    var table = const ChartTable(
      columns: ['Group, "name"', 'Value\none', 'Value two'],
      rows: [
        ['A\nB', '0', '-3.25'],
        ['C,"D"', '-4', ''],
      ],
    );
    final source =
        ChartSource(viewId: 'export-categories', loadTable: (_) async => table);
    final clipboard = _Clipboard(tester);
    try {
      await _mount(
        tester,
        'light',
        _stage(
          source,
          const ChartSpec(
            categoryColumn: 'Group, "name"',
            valueColumns: ['Value\none', 'Value two'],
          ),
        ),
      );
      await _openExport(tester);
      await _selectExport(tester);
      expect(parseDelimitedText(clipboard.text!, delimiter: ','), [
        ['Group, "name"', 'Value\none', 'Value two'],
        ['A\nB', '0.0', '-3.25'],
        ['C,"D"', '-4.0', '0.0'],
      ]);
      final state = tester.state(find.byType(AppChart));
      await _openExport(tester);
      table = ChartTable(columns: table.columns, rows: const []);
      await source.load();
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(AppChart, skipOffstage: false)),
        same(state),
      );
      expect(find.byType(AppChart), findsNothing);
      await _selectExport(tester);
      expect(parseDelimitedText(clipboard.text!, delimiter: ','), [
        ['Group, "name"'],
      ]);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      source.dispose();
      clipboard.dispose();
    }
  });
}

Finder _chart(ChartType type, {bool skipOffstage = true}) =>
    find.byWidgetPredicate(
      (widget) => widget is AppChart && widget.spec.type == type,
      skipOffstage: skipOffstage,
    );

Finder _plot(Finder chart) => find.descendant(
      of: chart,
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is ChartPainter,
        skipOffstage: false,
      ),
      skipOffstage: false,
    );

ChartPainter _painter(WidgetTester tester, Finder chart) =>
    tester.widget<CustomPaint>(_plot(chart)).painter! as ChartPainter;

Finder _legend(Finder chart, String label) => find.descendant(
      of: chart,
      matching: find.text(label, skipOffstage: false),
      skipOffstage: false,
    );

Finder _zoomIn(Finder chart) => find.descendant(
      of: chart,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == LocaleKeys.canvas_zoom_zoomIn.tr(),
        skipOffstage: false,
      ),
      skipOffstage: false,
    );

Finder get _switcher => find.descendant(
      of: find.byType(ChartStage),
      matching: find.byType(AnimatedSwitcher, skipOffstage: false),
      skipOffstage: false,
    );

Finder _guard(Finder chart, Type type) => find
    .ancestor(
      of: chart,
      matching: find.byType(type, skipOffstage: false),
    )
    .first;

Finder _fade(Finder chart) => _guard(chart, FadeTransition);

void _expectOutgoing(WidgetTester tester, Finder chart) {
  expect(
    tester.widget<ExcludeFocus>(_guard(chart, ExcludeFocus)).excluding,
    isTrue,
  );
  expect(
    tester.widget<ExcludeSemantics>(_guard(chart, ExcludeSemantics)).excluding,
    isTrue,
  );
  final pointer = _guard(chart, IgnorePointer);
  expect(tester.widget<IgnorePointer>(pointer).ignoring, isTrue);
  // Check the outgoing subtree's own hit path, not merely occlusion by the
  // new chart. It must stay inert even where the incoming chart is transparent.
  final render = tester.renderObject<RenderIgnorePointer>(pointer);
  final result = BoxHitTestResult();
  expect(
    render.hitTest(result, position: render.size.center(Offset.zero)),
    isFalse,
  );
  expect(result.path, isEmpty);
}

bool _focusInside(Element element) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var inside = identical(context, element);
  context.visitAncestorElements((ancestor) {
    if (identical(ancestor, element)) inside = true;
    return !inside;
  });
  return inside;
}

Widget _stage(
  ChartSource source,
  ChartSpec spec, {
  List<Widget> trailing = const [],
  ValueChanged<ChartSpec>? onChanged,
}) =>
    ChartStage(
      viewId: source.viewId,
      source: source,
      spec: spec,
      onSpecChanged: onChanged ?? (_) {},
      trailing: trailing,
    );

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  Widget child, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(chartAppearanceApp(appearance, const SizedBox()));
  await tester.pumpAndSettle();
  await tester.pumpWidget(
    chartAppearanceApp(
      appearance,
      Column(
        children: [
          TextButton(onPressed: () {}, child: const Text('Outside chart')),
          SizedBox(width: 800, height: 420, child: child),
        ],
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> _openExport(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('chart-more-controls')),
      matching: find.byType(TextButton),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(AppMenuSurface), findsOneWidget);
}

Future<void> _selectExport(WidgetTester tester) async {
  final export = find.byWidgetPredicate(
    (widget) =>
        widget is AppMenuRow && widget.label == LocaleKeys.charts_export.tr(),
  );
  await tester.ensureVisible(export);
  await tester.pumpAndSettle();
  await tester.tap(export);
  await tester.pumpAndSettle();
  expect(find.byType(AppMenuSurface), findsNothing);
}

class _Clipboard {
  _Clipboard(this.tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          text = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.getData') return {'text': text};
        return null;
      },
    );
  }

  final WidgetTester tester;
  String? text;

  void dispose() =>
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
}
