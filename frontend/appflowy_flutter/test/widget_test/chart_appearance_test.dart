import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_color_menu.dart';
import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/charts/chart_toolbar.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chart_appearance_test_support.dart';

const _host = ValueKey('chart-appearance-host');
const _ink = ValueKey('chart-appearance-ink');
const _more = ValueKey('chart-more-controls');
const _pick = ValueKey('appearance-pick-table');
const _draft = ValueKey('chart-retained-draft');
const _chosen = 0xFF4B83B5;

void main() {
  setUpChartAppearanceFixtures();

  for (final appearance in chartAppearances) {
    for (final width in [320.0, 480.0, 900.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$appearance: complete toolbar at $width / ${scale}x',
            (tester) async {
          var reads = 0;
          var picks = 0;
          var writes = 0;
          final source = ChartSource(
            viewId: 'responsive-chart',
            loadTable: (_) async {
              reads++;
              return chartAppearanceTable;
            },
          );
          final spec = chartAppearanceSpec(ChartType.bar, showControls: true);
          try {
            await _mount(
              tester,
              appearance,
              _stage(
                source,
                spec,
                width: width,
                onChanged: (_) => writes++,
                trailing: [_pickAction(() => picks++)],
              ),
              textScale: scale,
            );
            final host = tester.getRect(find.byKey(_host));
            final toolbar = find.byType(ChartToolbar);
            final buttons = find.descendant(
              of: toolbar,
              matching: find.byWidgetPredicate(
                (widget) => widget is TextButton || widget is IconButton,
              ),
            );
            expect(buttons, findsWidgets);
            for (final button in buttons.evaluate()) {
              final finder = find.byWidget(button.widget);
              expectChartRectInside(tester.getRect(finder), host);
              expect(
                finder.hitTestable(),
                findsOneWidget,
                reason: 'No clipped or half-visible toolbar buttons.',
              );
            }
            expect(
              find.descendant(
                of: toolbar,
                matching: find.byType(SingleChildScrollView),
              ),
              findsNothing,
            );
            expect(tester.getSize(chartAppearancePlot).height, greaterThan(60));
            expect(
              chartAppearancePainter(tester).data.categories,
              ['North', 'South', 'East', 'West'],
            );
            expect(
              chartAppearancePainter(tester)
                  .data
                  .series
                  .first
                  .points
                  .first
                  .value,
              24.5,
            );
            expect(
              chartAppearancePainter(tester).spec.valueColumns,
              ['Revenue USD', 'Costs USD'],
            );
            expect(
              find.descendant(
                of: toolbar,
                matching: find.byType(WorkspaceGlyph),
              ),
              findsWidgets,
            );

            await tester.tap(find.byKey(_pick));
            await tester.pumpAndSettle();
            expect(picks, 1);
            await tester.tap(_icon(LocaleKeys.charts_refresh.tr()));
            await tester.pumpAndSettle();
            expect(reads, 2);
            final chartState = tester.state(find.byType(AppChart));
            await tester.tap(_chipButton(_more));
            await tester.pumpAndSettle();
            // Every primary setting is reachable, whether on the first line
            // or in More. Exercise the actual nested menu with the keyboard.
            for (final label in [
              LocaleKeys.charts_chartType.tr(),
              LocaleKeys.charts_xAxis.tr(),
              LocaleKeys.charts_yAxis.tr(),
              LocaleKeys.charts_colors.tr(),
              LocaleKeys.charts_display.tr(),
            ]) {
              expect(_menuRow(label), findsOneWidget);
            }
            await _keyboardChoose(tester, LocaleKeys.charts_yAxis.tr());
            expect(_menuRow('Revenue USD'), findsOneWidget);
            expect(_menuRow('Costs USD'), findsOneWidget);
            expect(_menuRow(LocaleKeys.charts_countRows.tr()), findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byType(AppMenuSurface), findsNothing);
            expect(tester.state(find.byType(AppChart)), same(chartState));
            expect(writes, 0);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            source.dispose();
          }
        });
      }
    }

    testWidgets(
        '$appearance: compact 320x220 at 2x preserves the plot and table actions',
        (tester) async {
      var picks = 0;
      var reads = 0;
      final source = ChartSource(
        viewId: 'small-embed',
        loadTable: (_) async {
          reads++;
          return chartAppearanceTable;
        },
      );
      final layout = ValueNotifier(
        (
          spec: chartAppearanceSpec(ChartType.bar, showControls: true),
          height: 220.0,
        ),
      );
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<({ChartSpec spec, double height})>(
            valueListenable: layout,
            builder: (_, value, __) => _stage(
              source,
              value.spec,
              width: 320,
              height: value.height,
              compact: true,
              onChanged: (next) =>
                  layout.value = (spec: next, height: layout.value.height),
              trailing: [_pickAction(() => picks++)],
            ),
          ),
          textScale: 2,
        );

        void expectReading(ChartType type) {
          expect(tester.takeException(), isNull);
          expect(tester.getSize(chartAppearancePlot).height, greaterThan(60));
          final painter = chartAppearancePainter(tester);
          expect(painter.spec.type, type);
          expect(painter.hits, hasLength(type.isCircular ? 4 : 8));
          expect(painter.data.categories, ['North', 'South', 'East', 'West']);
          expect(
            painter.data.series.map((series) => series.name),
            ['Revenue USD', 'Costs USD'],
          );
          expect(
            painter.data.series.first.points.map((point) => point.value),
            [24.5, 36, 18, 30],
          );
          expect(
            painter.data.series.last.points.map((point) => point.value),
            [12, 22, 10, 16],
          );
          expect(layout.value.spec.valueColumns, ['revenue', 'costs']);
        }

        expectReading(ChartType.bar);
        for (final action in [
          find.byKey(_pick),
          _icon(LocaleKeys.charts_refresh.tr()),
          _chipButton(_more),
        ]) {
          expect(action.hitTestable(), findsOneWidget);
          expectChartRectInside(
            tester.getRect(action),
            tester.getRect(find.byKey(_host)),
          );
        }
        expect(
          find.descendant(
            of: find.byType(ChartToolbar),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
          reason: 'Controls stay in More, not a clipped horizontal strip.',
        );
        final chartState = tester.state(find.byType(AppChart));
        final plot =
            tester.renderObject<RenderCustomPaint>(chartAppearancePlot);
        final plotSize = plot.size;
        final scrollable = Scrollable.of(tester.element(chartAppearancePlot));
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        await tester.drag(find.byKey(_host), const Offset(0, -80));
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(0));
        expect(tester.renderObject(chartAppearancePlot), same(plot));
        expect(
          plot.size,
          plotSize,
          reason: 'Scrolling must not stretch the drawing as chrome leaves.',
        );
        expectReading(ChartType.bar);

        layout.value = (spec: layout.value.spec, height: 480);
        await tester.pumpAndSettle();
        expect(scrollable.position.maxScrollExtent, 0);
        expect(tester.state(find.byType(AppChart)), same(chartState));
        expect(tester.renderObject(chartAppearancePlot), same(plot));
        layout.value = (spec: layout.value.spec, height: 220);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(AppChart)), same(chartState));
        expect(tester.renderObject(chartAppearancePlot), same(plot));
        expect(
          Scrollable.of(tester.element(chartAppearancePlot)),
          same(scrollable),
        );
        expect(plot.size, plotSize);
        expectReading(ChartType.bar);

        await tester.ensureVisible(find.byKey(_pick));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_pick));
        await tester.pumpAndSettle();
        expect(picks, 1);
        await tester.tap(_icon(LocaleKeys.charts_refresh.tr()));
        await tester.pumpAndSettle();
        expect(reads, 2);
        expect(tester.state(find.byType(AppChart)), same(chartState));
        expectReading(ChartType.bar);

        for (final type in [ChartType.pie, ChartType.donut]) {
          // Slivers outside the viewport stay mounted but are not onstage.
          await tester.ensureVisible(_chipButton(_more, skipOffstage: false));
          await tester.pumpAndSettle();
          expect(_chipButton(_more).hitTestable(), findsOneWidget);
          await tester.tap(_chipButton(_more));
          await tester.pumpAndSettle();
          for (final label in [
            LocaleKeys.charts_chartType.tr(),
            layout.value.spec.type.isCircular
                ? LocaleKeys.charts_groupBy.tr()
                : LocaleKeys.charts_xAxis.tr(),
            LocaleKeys.charts_yAxis.tr(),
            LocaleKeys.charts_colors.tr(),
            LocaleKeys.charts_display.tr(),
          ]) {
            expect(_menuRow(label), findsOneWidget);
          }
          await _keyboardChoose(tester, LocaleKeys.charts_chartType.tr());
          expect(_menuRow(chartTypeLabel(ChartType.pie)), findsOneWidget);
          await _keyboardChoose(tester, chartTypeLabel(type));
          expect(find.byType(AppMenuSurface), findsNothing);
          expectReading(type);
          final circularSize = tester.getSize(chartAppearancePlot);
          await tester.drag(find.byKey(_host), const Offset(0, -80));
          await tester.pumpAndSettle();
          expect(scrollable.position.pixels, greaterThan(0));
          expect(tester.getSize(chartAppearancePlot), circularSize);
          expectReading(type);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        layout.dispose();
        source.dispose();
      }
    });

    testWidgets(
        '$appearance: failed refresh shows its failure without losing the last reading',
        (tester) async {
      var fail = false;
      final source = ChartSource(
        viewId: 'refresh-failure',
        loadTable: (_) async {
          if (fail) throw StateError('synthetic refresh failure');
          return chartAppearanceTable;
        },
      );
      try {
        await _mount(
          tester,
          appearance,
          _stage(source, chartAppearanceSpec(ChartType.bar), width: 480),
        );
        await tester.tap(find.text('Revenue USD'));
        await tester.pumpAndSettle();
        await tester.tap(_icon(LocaleKeys.canvas_zoom_zoomIn.tr()));
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
        final state = tester.state(find.byType(AppChart));
        final viewport = chartAppearancePainter(tester).viewport;
        fail = true;
        await source.load();
        await tester.pumpAndSettle();
        final refresh = tester.widget<ChartIconAction>(
          find.byKey(const ValueKey('chart-refresh')),
        );
        expect(refresh.icon, Icons.error_outline_rounded);
        expect(refresh.tooltip, contains('synthetic refresh failure'));
        expect(tester.state(find.byType(AppChart)), same(state));
        expect(chartAppearancePainter(tester).viewport, viewport);
        expect(chartAppearancePainter(tester).hidden, {0});
        fail = false;
        await source.load();
        await tester.pumpAndSettle();
        expect(_icon(LocaleKeys.charts_refresh.tr()), findsOneWidget);
        expect(tester.state(find.byType(AppChart)), same(state));
        expect(chartAppearancePainter(tester).viewport, viewport);
        expect(chartAppearancePainter(tester).hidden, {0});
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        source.dispose();
      }
    });

    testWidgets(
        '$appearance: hiding a hovered legend clears emphasis, not chosen visibility',
        (tester) async {
      final source = ChartSource(
        viewId: 'legend-display',
        loadTable: (_) async => chartAppearanceTable,
      );
      final spec = ValueNotifier(chartAppearanceSpec(ChartType.bar));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<ChartSpec>(
            valueListenable: spec,
            builder: (_, value, __) => _stage(source, value, width: 480),
          ),
        );
        await tester.tap(find.text('Revenue USD'));
        await tester.pumpAndSettle();
        expect(chartAppearancePainter(tester).hidden, {0});
        await mouse.addPointer(location: const Offset(2, 2));
        await mouse.moveTo(tester.getCenter(find.text('Costs USD')));
        await tester.pumpAndSettle();
        expect(chartAppearancePainter(tester).focusedSeries, 1);
        final state = tester.state(find.byType(AppChart));
        spec.value = spec.value.copyWith(showLegend: false);
        await tester.pumpAndSettle();
        expect(chartAppearancePainter(tester).focusedSeries, isNull);
        expect(chartAppearancePainter(tester).hidden, {0});
        expect(tester.state(find.byType(AppChart)), same(state));
        expect(
          find.byKey(const ValueKey(('chart-legend', false, 1))),
          findsNothing,
        );
        spec.value = spec.value.copyWith(showLegend: true);
        await tester.pumpAndSettle();
        expect(chartAppearancePainter(tester).hidden, {0});
        expect(find.text('Costs USD').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        spec.dispose();
        source.dispose();
      }
    });

    testWidgets(
        '$appearance: a focused axis keeps its element through narrowing',
        (tester) async {
      final width = ValueNotifier(1280.0);
      final source = ChartSource(
        viewId: 'axis-focus',
        loadTable: (_) async => chartAppearanceTable,
      );
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, value, __) => _stage(
              source,
              chartAppearanceSpec(ChartType.bar, showControls: true),
              width: value,
            ),
          ),
        );
        const axisKey = ValueKey('chart-horizontal-column');
        final axisState = tester.state(find.byKey(axisKey));
        _focusButton(tester, _chipButton(axisKey));
        await tester.pump();
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus;
        width.value = 320;
        await tester.pumpAndSettle();
        expect(tester.state(find.byKey(axisKey)), same(axisState));
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(_chipButton(axisKey).hitTestable(), findsOneWidget);
        expectChartRectInside(
          tester.getRect(_chipButton(axisKey)),
          tester.getRect(find.byKey(_host)),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(_menuRow('Category'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        width.dispose();
        source.dispose();
      }
    });

    testWidgets(
        '$appearance: More holds preview controls across resize and outside click',
        (tester) async {
      final width = ValueNotifier(900.0);
      final source = ChartSource(
        viewId: 'menu-hold',
        loadTable: (_) async => chartAppearanceTable,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _mount(
          tester,
          appearance,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton(
                onPressed: () {},
                child: const Text('Outside chart'),
              ),
              ValueListenableBuilder<double>(
                valueListenable: width,
                builder: (_, value, __) => _stage(
                  source,
                  chartAppearanceSpec(ChartType.bar, showControls: true),
                  width: value,
                  preview: true,
                ),
              ),
            ],
          ),
        );
        expect(_toolbarOpacity(tester), 0);
        final toolbarState = tester.state(find.byType(ChartToolbar));
        final moreState = tester.state(find.byKey(_more));
        final chartState = tester.state(find.byType(AppChart));
        await mouse.addPointer(location: const Offset(2, 2));
        await mouse.moveTo(
          tester.getTopLeft(chartAppearancePlot) + const Offset(4, 4),
        );
        await tester.pumpAndSettle();
        await tester.tap(_chipButton(_more), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        await mouse.moveTo(const Offset(2, 2));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AppMenuSurface), findsOneWidget);
        expect(
          _toolbarOpacity(tester),
          1,
          reason: 'Menu owns a hold outside the preview.',
        );
        width.value = 320;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ChartToolbar)), same(toolbarState));
        expect(tester.state(find.byKey(_more)), same(moreState));
        expect(tester.state(find.byType(AppChart)), same(chartState));
        expect(_toolbarOpacity(tester), 1);
        expect(find.byType(AppMenuSurface), findsOneWidget);
        await tester.tapAt(
          const Offset(1340, 880),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsNothing);
        Focus.of(tester.element(find.text('Outside chart'))).requestFocus();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(
          _toolbarOpacity(tester),
          0,
          reason: 'Outside dismissal releases the hold.',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        width.dispose();
        source.dispose();
      }
    });

    testWidgets(
        '$appearance: date refresh retains zoom, hidden series, choices and input draft',
        (tester) async {
      var table = chartAppearanceTable;
      Completer<ChartTable>? pending;
      var writes = 0;
      final source = ChartSource(
        viewId: 'retained-date-chart',
        loadTable: (_) => pending?.future ?? Future.value(table),
      );
      final settings = chartAppearanceSpec(
        ChartType.line,
        showControls: true,
        colors: const {'Costs USD': _chosen},
      ).copyWith(xColumn: 'day', palette: ChartPaletteName.berry);
      final environment =
          ValueNotifier((width: 900.0, appearance: appearance, scale: 1.0));
      final controller = TextEditingController();
      final focus = FocusNode();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<
              ({double width, String appearance, double scale})>(
            valueListenable: environment,
            builder: (context, value, _) => Theme(
              data: chartAppearanceTheme(value.appearance),
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(value.scale)),
                child: _stage(
                  source,
                  settings,
                  width: value.width,
                  height: 480,
                  onChanged: (_) => writes++,
                  trailing: [
                    SizedBox(
                      key: const ValueKey('draft-slot'),
                      width: 130,
                      child: TextField(
                        key: _draft,
                        controller: controller,
                        focusNode: focus,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        final state = tester.state(find.byType(AppChart));
        final legend = find.descendant(
          of: find.byKey(const ValueKey(('chart-legend', false, 0))),
          matching: find.byType(TextButton),
        );
        _focusButton(tester, legend);
        await tester.pump();
        await tester.pump();
        expect(chartAppearancePainter(tester).focusedSeries, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(chartAppearancePainter(tester).hidden, {0});
        await tester.tap(_icon(LocaleKeys.canvas_zoom_zoomIn.tr()));
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
        final viewport = chartAppearancePainter(tester).viewport;
        expect(viewport.scale, closeTo(1.4, 0.000001));
        await tester.enterText(find.byKey(_draft), 'unsaved chart note');
        controller.selection =
            const TextSelection(baseOffset: 2, extentOffset: 9);
        final draft = controller.value;
        final fieldState = tester.state(find.byType(EditableText));
        await mouse.addPointer(location: const Offset(2, 2));
        for (final next in chartAppearances) {
          environment.value =
              (width: next == 'dark' ? 1280 : 320, appearance: next, scale: 2);
          await tester.pumpAndSettle();
          final painter = chartAppearancePainter(tester);
          final hit = painter.hits.lastWhere((hit) => !hit.rect.isEmpty);
          await mouse.moveTo(
            tester.getTopLeft(chartAppearancePlot) +
                chartHitPosition(painter, hit),
          );
          await tester.pumpAndSettle();
          expect(focus.hasFocus, isTrue);
          expect(controller.value, draft);
          expect(tester.state(find.byType(EditableText)), same(fieldState));
          expect(tester.state(find.byType(AppChart)), same(state));
          expect(chartAppearancePainter(tester).viewport, viewport);
          expect(chartAppearancePainter(tester).hidden, {0});
        }
        pending = Completer<ChartTable>();
        final reload = source.load();
        await tester.pump();
        expect(source.isLoading, isTrue);
        expect(focus.hasFocus, isTrue);
        expect(controller.value, draft);
        table = ChartTable(
          columns: table.columns,
          columnIds: table.columnIds,
          rows: [
            ...table.rows,
            ['Fifth', '42', '21', '2026-09-05T00:00:00Z', '8', '8'],
          ],
        );
        pending.complete(table);
        await reload;
        pending = null;
        await tester.pumpAndSettle();
        final painter = chartAppearancePainter(tester);
        expect(painter.data.series.first.points, hasLength(5));
        expect(painter.data.series.first.points.last.value, 42);
        expect(
          painter.data.series.first.points.last.x,
          DateTime.utc(2026, 9, 5).millisecondsSinceEpoch / 1000,
        );
        expect(painter.spec.xColumn, 'Day');
        expect(painter.viewport, viewport);
        expect(painter.hidden, {0});
        expect(painter.colors.at(1, 'Costs USD'), const Color(_chosen));
        expect(
          tester.widget<ChartToolbar>(find.byType(ChartToolbar)).spec,
          settings,
        );
        expect(tester.state(find.byType(AppChart)), same(state));
        expect(tester.state(find.byType(EditableText)), same(fieldState));
        expect(focus.hasFocus, isTrue);
        expect(controller.value, draft);
        expect(writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        source.dispose();
        environment.dispose();
        controller.dispose();
        focus.dispose();
      }
    });

    testWidgets(
        '$appearance: keyboard colour menus preserve explicit ink and glyph independence',
        (tester) async {
      final source = ChartSource(
        viewId: 'chart-colors',
        loadTable: (_) async => chartAppearanceTable,
      );
      final spec = ValueNotifier(
        chartAppearanceSpec(
          ChartType.bar,
          showControls: true,
          colors: const {'Costs USD': _chosen},
        ),
      );
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      try {
        await _mount(
          tester,
          appearance,
          DefaultIconStyleScope(
            styles: styles,
            child: ValueListenableBuilder<ChartSpec>(
              valueListenable: spec,
              builder: (_, value, __) => _stage(
                source,
                value,
                width: 480,
                onChanged: (next) =>
                    spec.value = ChartSpec.fromJson(next.toJson()),
              ),
            ),
          ),
        );
        final state = tester.state(find.byType(AppChart));
        await tester.tap(_chipButton(_more));
        await tester.pumpAndSettle();
        await _keyboardChoose(tester, LocaleKeys.charts_colors.tr());
        await _keyboardChoose(
          tester,
          chartPaletteLabel(ChartPaletteName.ocean),
        );
        expect(spec.value.palette, ChartPaletteName.ocean);
        expect(spec.value.colors, {'Costs USD': _chosen});
        await tester.tap(_chipButton(_more));
        await tester.pumpAndSettle();
        await _keyboardChoose(tester, LocaleKeys.charts_colors.tr());
        await _keyboardChoose(tester, 'Revenue USD');
        await _keyboardChoose(tester, '#3FBFA0');
        expect(
          spec.value.colors,
          {'Costs USD': _chosen, 'Revenue USD': 0xFF3FBFA0},
        );
        expect(
          chartAppearancePainter(tester).colors.at(0, 'Revenue USD'),
          const Color(0xFF3FBFA0),
        );
        styles.value = DefaultIconStyle.vivid;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(AppChart)), same(state));
        expect(
          chartAppearancePainter(tester).colors.at(1, 'Costs USD'),
          const Color(_chosen),
        );
        expect(
          tester
              .widget<ChartChip>(
                find.byKey(
                  const ValueKey('chart-colors'),
                  skipOffstage: false,
                ),
              )
              .swatch,
          const Color(0xFF3FBFA0),
        );
        await tester.tap(_chipButton(_more));
        await tester.pumpAndSettle();
        await _keyboardChoose(tester, LocaleKeys.charts_colors.tr());
        await _keyboardChoose(tester, 'Revenue USD');
        await _keyboardChoose(tester, LocaleKeys.charts_resetColor.tr());
        expect(spec.value.colors, {'Costs USD': _chosen});
        expect(spec.value.palette, ChartPaletteName.ocean);
        spec.value = spec.value.copyWith(
          type: ChartType.pie,
          colors: {...spec.value.colors, 'North': _chosen},
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ChartChip>(
                find.byKey(
                  const ValueKey('chart-colors'),
                  skipOffstage: false,
                ),
              )
              .swatch,
          const Color(_chosen),
          reason:
              'A pie trigger previews its first slice, not its series name.',
        );
        expect(
          find.descendant(
            of: find.byType(AppChart),
            matching: find.byType(TextButton),
          ),
          findsNothing,
          reason: 'Circular legend labels are not disabled toggle buttons.',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        source.dispose();
        spec.dispose();
        styles.dispose();
      }
    });

    for (final type in ChartType.values) {
      testWidgets(
          '$appearance ${type.name}: transparent plot, rich ink and real hover values',
          (tester) async {
        final spec = chartAppearanceSpec(type, showLegend: false);
        final data = buildChartData(chartAppearanceTable, spec);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await _mount(tester, appearance, _plotHost(data, spec));
          final painter = chartAppearancePainter(tester);
          expect(identical(painter.data, data), isTrue);
          expect(painter.hits, hasLength(type.isCircular ? 4 : 8));
          final pixels = await _capture(tester, _ink);
          for (final point in [
            const Offset(3, 3),
            const Offset(416, 3),
            const Offset(3, 296),
            const Offset(416, 296),
          ]) {
            expect(
              pixels.alpha(point),
              0,
              reason: 'No plot background at $point.',
            );
          }
          final hues = <int>{};
          var saturated = 0;
          for (var index = 0; index < pixels.bytes.lengthInBytes; index += 4) {
            if (pixels.bytes.getUint8(index + 3) < 70) continue;
            final hsv = HSVColor.fromColor(
              Color.fromARGB(
                255,
                pixels.bytes.getUint8(index),
                pixels.bytes.getUint8(index + 1),
                pixels.bytes.getUint8(index + 2),
              ),
            );
            if (hsv.saturation > 0.45) {
              saturated++;
              hues.add((hsv.hue / 30).floor());
            }
          }
          expect(
            saturated,
            greaterThan(50),
            reason: 'Vibrance must be in rendered marks.',
          );
          expect(hues.length, greaterThanOrEqualTo(2));
          final hit = painter.hits.last;
          final point = data.series[hit.seriesIndex].points[hit.pointIndex];
          await mouse.addPointer(location: const Offset(2, 2));
          await mouse.moveTo(
            tester.getTopLeft(chartAppearancePlot) +
                chartHitPosition(painter, hit),
          );
          await tester.pumpAndSettle();
          final tooltip =
              tester.widget<ChartTooltip>(find.byType(ChartTooltip));
          expect(tooltip.hit, hit);
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('chart-readout-value')),
                )
                .data,
            ChartPainter.formatValue(point.value),
          );
          expectChartRectInside(
            tester.getRect(find.byKey(const ValueKey('chart-readout'))),
            tester.getRect(chartAppearancePlot),
          );
          expect(
            find.descendant(
              of: find.byType(ChartTooltip),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is DecoratedBox &&
                    widget.decoration is BoxDecoration &&
                    ((widget.decoration as BoxDecoration).border != null ||
                        (widget.decoration as BoxDecoration).boxShadow != null),
              ),
            ),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
        }
      });
    }

    for (final mode in ['reduced', 'accessible', 'static']) {
      testWidgets(
          '$appearance $mode: no entrance/hover ticker and safe disposal',
          (tester) async {
        final spec = chartAppearanceSpec(ChartType.bar, showLegend: false);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await _mount(
            tester,
            appearance,
            _plotHost(
              buildChartData(chartAppearanceTable, spec),
              spec,
              animate: mode != 'static',
            ),
            reducedMotion: mode == 'reduced',
            accessibleNavigation: mode == 'accessible',
          );
          expect(chartAppearancePainter(tester).reveal.value, 1);
          expect(tester.binding.transientCallbackCount, 0);
          final painter = chartAppearancePainter(tester);
          await mouse.addPointer(location: const Offset(2, 2));
          await mouse.moveTo(
            tester.getTopLeft(chartAppearancePlot) +
                painter.hits.first.rect.center,
          );
          await tester.pump();
          expect(chartAppearancePainter(tester).emphasis.value, 1);
          expect(tester.binding.transientCallbackCount, 0);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
        }
        expect(tester.takeException(), isNull);
        expect(tester.binding.transientCallbackCount, 0);
      });
    }

    testWidgets(
        '$appearance: reduced-motion pending load disposes without creating a ticker',
        (tester) async {
      final loaded = Completer<ChartTable>();
      final source =
          ChartSource(viewId: 'pending-chart', loadTable: (_) => loaded.future);
      await _mount(
        tester,
        appearance,
        _stage(source, const ChartSpec(), width: 320),
        reducedMotion: true,
      );
      expect(source.isLoading, isTrue);
      expect(find.byType(AppChart), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      source.dispose();
      loaded.complete(chartAppearanceTable);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets(
        '$appearance: live reveal repaints without rebuilding and stops for reduced motion',
        (tester) async {
      final spec = chartAppearanceSpec(ChartType.line, showLegend: false);
      final data = ValueNotifier(buildChartData(chartAppearanceTable, spec));
      final reduced = ValueNotifier(false);
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<bool>(
            valueListenable: reduced,
            builder: (context, value, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: value),
              child: ValueListenableBuilder<ChartData>(
                valueListenable: data,
                builder: (_, value, __) =>
                    _plotHost(value, spec, animate: true),
              ),
            ),
          ),
        );
        final state = tester.state(find.byType(AppChart));
        data.value = buildChartData(
          ChartTable(
            columns: chartAppearanceTable.columns,
            columnIds: chartAppearanceTable.columnIds,
            rows: [
              ...chartAppearanceTable.rows,
              ['Fifth', '42', '21', '2026-09-05T00:00:00Z', '8', '8'],
            ],
          ),
          spec,
        );
        await tester.pump();
        final painter = chartAppearancePainter(tester);
        await tester.pump(const Duration(milliseconds: 100));
        expect(chartAppearancePainter(tester), same(painter));
        expect(painter.reveal.value, inExclusiveRange(0, 1));
        reduced.value = true;
        await tester.pump();
        await tester.pump();
        expect(chartAppearancePainter(tester).reveal.value, 1);
        expect(tester.state(find.byType(AppChart)), same(state));
        expect(tester.binding.transientCallbackCount, 0);
      } finally {
        await tester.pumpWidget(const SizedBox());
        data.dispose();
        reduced.dispose();
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final type in [
    ChartType.bar,
    ChartType.bubble,
    ChartType.pie,
    ChartType.donut,
  ]) {
    for (final size in [const Size(320, 240), const Size(180, 96)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            '${type.name}: full readout fits all corners of $size at ${scale}x',
            (tester) async {
          final spec = ChartSpec(
            type: type,
            valueColumns: const ['Revenue USD'],
            xColumn: type.drawsPoints ? 'Distance km' : null,
            sizeColumn: type.sizesPoints ? 'Weight kg' : null,
            showLegend: false,
            colors: const {'Revenue USD': _chosen, 'North': _chosen},
          );
          final data = ChartData(
            categories: const ['North', 'South'],
            minimum: 0,
            maximum: 2469,
            measuresX: type.drawsPoints,
            xMaximum: 10,
            sizeMaximum: 9.75,
            series: [
              ChartSeries(
                name: 'Revenue USD',
                points: [
                  ChartPoint(
                    label: 'North',
                    value: 1234.5,
                    x: type.drawsPoints ? 6.25 : null,
                    size: type.sizesPoints ? 9.75 : null,
                  ),
                  const ChartPoint(label: 'South', value: 2469),
                ],
              ),
            ],
          );
          var anchor = Offset.zero;
          late StateSetter change;
          try {
            await _mount(
              tester,
              'paper',
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: _host,
                  width: size.width,
                  height: size.height,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      change = setState;
                      final palette = chartPaletteOf(context);
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: AppChart(
                              data: data,
                              spec: spec,
                              palette: palette,
                              animate: false,
                            ),
                          ),
                          ChartTooltip(
                            hit: ChartHit(
                              seriesIndex: 0,
                              pointIndex: 0,
                              rect: anchor & const Size(1, 1),
                              anchor: anchor,
                            ),
                            data: data,
                            spec: spec,
                            palette: palette,
                            colors: ChartColors.of(palette, spec),
                            bounds: size,
                            emphasis: kAlwaysCompleteAnimation,
                            avoidBounds: type.isCircular
                                ? null
                                : Rect.fromLTWH(
                                    size.width - (scale == 1 ? 92 : 112),
                                    0,
                                    scale == 1 ? 92 : 112,
                                    scale == 1 ? 24 : 32,
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              textScale: scale,
            );
            for (final corner in [
              Offset.zero,
              Offset(size.width, 0),
              Offset(0, size.height),
              Offset(size.width, size.height),
            ]) {
              change(() => anchor = corner);
              await tester.pump();
              final readout = find.byKey(const ValueKey('chart-readout'));
              expectChartRectInside(
                tester.getRect(readout),
                tester.getRect(find.byKey(_host)),
              );
              if (!type.isCircular) {
                final zoom = find.descendant(
                  of: find.byType(AppChart),
                  matching: find.byType(PreviewToolbar),
                );
                expect(
                  tester.getRect(readout).overlaps(tester.getRect(zoom)),
                  isFalse,
                  reason:
                      'A bounded readout must not be hidden under zoom controls.',
                );
              }
              for (final text in find
                  .descendant(of: readout, matching: find.byType(Text))
                  .evaluate()) {
                expectChartRectInside(
                  chartRenderedRect(tester, find.byWidget(text.widget)),
                  chartRenderedRect(tester, readout),
                );
              }
              expect(
                tester
                    .widget<Text>(
                      find.byKey(const ValueKey('chart-readout-value')),
                    )
                    .data,
                '1234.5',
              );
              expect(
                tester
                    .widget<Text>(
                      find.byKey(const ValueKey('chart-readout-label')),
                    )
                    .data,
                'North · Revenue USD',
              );
              if (type.isCircular) {
                expect(
                  tester
                      .widget<Text>(
                        find.byKey(const ValueKey('chart-readout-share')),
                      )
                      .data,
                  '33.3%',
                );
              }
              if (type.sizesPoints) {
                expect(
                  find.text('Distance km 6.25 · Weight kg 9.75'),
                  findsOneWidget,
                );
              }
              final swatch = tester.widget<Container>(
                find.byKey(const ValueKey('chart-readout-swatch')),
              );
              expect(
                (swatch.decoration! as BoxDecoration).color,
                const Color(_chosen),
              );
              expect(tester.takeException(), isNull);
            }
          } finally {
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }
  }

  for (final type in [
    ChartType.bar,
    ChartType.horizontalBar,
    ChartType.stackedBar,
    ChartType.pie,
    ChartType.donut,
  ]) {
    testWidgets(
        '${type.name}: actual marks select the exact category and series',
        (tester) async {
      final spec = chartAppearanceSpec(type, showLegend: false);
      final data = buildChartData(chartAppearanceTable, spec);
      final selected = <(String, String)>[];
      try {
        await _mount(
          tester,
          'light',
          _plotHost(
            data,
            spec,
            onSelected: (category, series) => selected.add((category, series)),
          ),
        );
        final hits = List<ChartHit>.of(chartAppearancePainter(tester).hits);
        for (final original in hits) {
          final painter = chartAppearancePainter(tester);
          final hit = painter.hits.firstWhere((hit) => hit == original);
          final position = tester.getTopLeft(chartAppearancePlot) +
              chartHitPosition(painter, hit);
          await tester.tapAt(position, kind: PointerDeviceKind.mouse);
          await tester.pump(kDoubleTapTimeout);
          await tester.pumpAndSettle();
          final series = data.series[hit.seriesIndex];
          expect(
            selected.last,
            (series.points[hit.pointIndex].label, series.name),
          );
        }
        expect(selected, hasLength(hits.length));
        if (type == ChartType.donut) {
          await tester.tapAt(
            tester.getCenter(chartAppearancePlot),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          expect(
            selected,
            hasLength(hits.length),
            reason: 'The donut hole is not a slice.',
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}

Widget _stage(
  ChartSource source,
  ChartSpec spec, {
  required double width,
  double height = 360,
  bool preview = false,
  bool compact = false,
  List<Widget> trailing = const [],
  ValueChanged<ChartSpec>? onChanged,
}) =>
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        key: _host,
        width: width,
        height: height,
        child: PreviewToolbarRegion(
          enabled: preview,
          child: ChartStage(
            viewId: source.viewId,
            source: source,
            spec: spec,
            compactToolbar: compact,
            onSpecChanged: onChanged ?? (_) {},
            trailing: trailing,
          ),
        ),
      ),
    );

Widget _pickAction(VoidCallback onPick) => Builder(
      builder: (context) => TextButton.icon(
        key: _pick,
        onPressed: onPick,
        icon: const WorkspaceGlyph(Icons.table_chart_rounded, size: 16),
        label: Text(LocaleKeys.charts_pickTable.tr()),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 11.5, height: 1.2),
        ),
      ),
    );

Widget _plotHost(
  ChartData data,
  ChartSpec spec, {
  bool animate = false,
  void Function(String, String)? onSelected,
}) =>
    Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 420,
        height: 300,
        child: RepaintBoundary(
          key: _ink,
          child: Builder(
            builder: (context) => AppChart(
              data: data,
              spec: chartAppearanceTable.displaySpec(spec),
              interactionSpec: spec,
              palette: chartPaletteOf(context),
              animate: animate,
              allowZoom: false,
              onSelected: onSelected,
            ),
          ),
        ),
      ),
    );

Finder _chipButton(Key key, {bool skipOffstage = true}) => find.descendant(
      of: find.byKey(key, skipOffstage: skipOffstage),
      matching: find.byType(TextButton, skipOffstage: skipOffstage),
      skipOffstage: skipOffstage,
    );

Finder _icon(String tooltip) => find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == tooltip,
    );

Finder _menuRow(String label) => find.byWidgetPredicate(
      (widget) => widget is AppMenuRow && widget.label == label,
    );

void _focusButton(WidgetTester tester, Finder button) {
  final label = find.descendant(of: button, matching: find.byType(Text)).first;
  Focus.of(tester.element(label)).requestFocus();
}

double _toolbarOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find
          .descendant(
            of: find.byType(ChartToolbar),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

Future<void> _keyboardChoose(WidgetTester tester, String label) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.home);
  await tester.pump();
  bool highlighted() => tester
      .widgetList<AppMenuRow>(
        find.descendant(
          of: find.byType(AppMenuSurface).last,
          matching: find.byType(AppMenuRow),
        ),
      )
      .any((row) => row.label == label && row.highlighted);
  for (var index = 0; index < 50 && !highlighted(); index++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }
  expect(highlighted(), isTrue, reason: '$label must be keyboard reachable.');
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  Widget body, {
  double textScale = 1,
  bool reducedMotion = false,
  bool accessibleNavigation = false,
}) async {
  tester.view.physicalSize = const Size(1360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Widget app(Widget child) => chartAppearanceApp(
        appearance,
        child,
        textScale: textScale,
        reducedMotion: reducedMotion,
        accessibleNavigation: accessibleNavigation,
      );
  await tester.pumpWidget(app(const SizedBox()));
  await tester.pumpAndSettle();
  await tester.pumpWidget(app(body));
  await tester.pumpAndSettle();
}

class _Pixels {
  const _Pixels(this.width, this.bytes);
  final int width;
  final ByteData bytes;
  int alpha(Offset point) =>
      bytes.getUint8((point.dy.floor() * width + point.dx.floor()) * 4 + 3);
}

Future<_Pixels> _capture(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return _Pixels(image.width, (await image.toByteData())!);
    } finally {
      image.dispose();
    }
  }))!;
}
