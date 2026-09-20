import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/chart_plugin.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/chart_tab_bar_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/chart/chart_block_component.dart';
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _appearances = ['light', 'dark', 'paper'];
const _page = ValueKey('chart-page-pixels');
const _layer = ValueKey('chart-layer-pixels');
const _chosenInk = Color(0xFF4B83B5);
const _table = ChartTable(
  columns: ['Region', 'Revenue', 'Costs'],
  columnIds: ['region', 'revenue', 'costs'],
  rows: [
    ['North', '24', '12'],
    ['South', '36', '22'],
    ['East', '18', '10'],
    ['West', '30', '16'],
  ],
);

ChartSpec _spec([ChartType type = ChartType.bar]) => ChartSpec(
      type: type,
      categoryColumn: 'region',
      valueColumns: const ['revenue', 'costs'],
      palette: ChartPaletteName.ocean,
      colors: const {'Costs': 0xFF4B83B5, 'South': 0xFF4B83B5},
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  for (final appearance in _appearances) {
    for (final customPage in [false, true]) {
      for (final type in [
        ChartType.bar,
        ChartType.line,
        ChartType.pie,
        ChartType.donut,
      ]) {
        testWidgets(
            '$appearance ${type.name}, custom page=$customPage: populated '
            'chart has no canvas fill at rest or hover', (tester) async {
          var reads = 0;
          var writes = 0;
          final source = ChartSource(
            viewId: 'integrated-chart',
            loadTable: (_) async {
              reads++;
              return _table;
            },
          );
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          try {
            await _mount(
              tester,
              appearance,
              ChartStage(
                viewId: source.viewId,
                source: source,
                title: 'Quarterly totals',
                spec: _spec(type),
                onSpecChanged: (_) => writes++,
              ),
              customPage: customPage,
            );
            final chartState = tester.state(find.byType(AppChart));
            final plot = tester.renderObject(_plot);
            final bounds = tester.getRect(_plot);
            final chart = tester.widget<AppChart>(find.byType(AppChart));
            final pageColor = _pageColor(appearance, customPage);
            final palette = chart.palette;
            expect(chart.data.categories, ['North', 'South', 'East', 'West']);
            expect(_painter(tester).hits, hasLength(type.isCircular ? 4 : 8));
            expect(palette.background.a, 1);
            expect(palette.surface.a, 1);
            expect(palette.grid.a, greaterThan(0));
            expect(palette.axis.a, greaterThan(palette.grid.a));
            expect(palette.isDark, appearance == 'dark');
            expect(
              PaperTheme.isEnabled(tester.element(find.byType(AppChart))),
              appearance == 'paper',
            );
            if (appearance == 'paper') {
              expect(palette.background, PaperTheme.editorBackground);
              expect(palette.surface.r, greaterThan(palette.surface.b));
            }
            _expectToolbars(tester, visible: false);
            await _expectPageShowingThrough(tester, pageColor);

            // Check actual plotted pixels, not only an absence of Container.
            final pixels = await _capture(tester, _layer);
            final localPlot =
                bounds.shift(-tester.getTopLeft(find.byKey(_layer)));
            expect(
              pixels.inkPixels(_chosenInk, localPlot),
              greaterThan(20),
              reason: 'The chosen series/slice still paints opaque ink.',
            );
            final legendName = type.isCircular ? 'South' : 'Costs';
            final legend = find.descendant(
              of: find.byType(AppChart),
              matching: find.text(legendName),
            );
            expect(legend, findsOneWidget);
            final legendInk =
                DefaultTextStyle.of(tester.element(legend)).style.color!;
            expect(legendInk, palette.strongLabel);
            expect(_contrast(legendInk, pageColor), greaterThan(4.5));
            expect(_contrast(_chosenInk, pageColor), greaterThan(2.5));
            final swatch = find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).shape ==
                      BoxShape.circle &&
                  (widget.decoration as BoxDecoration).color == _chosenInk,
            );
            expect(swatch, findsOneWidget);
            _expectPixel(
              pixels,
              tester.getCenter(swatch) - tester.getTopLeft(find.byKey(_layer)),
              _chosenInk,
            );

            await mouse.addPointer(location: const Offset(2, 2));
            await _hoverValue(tester, mouse);
            _expectToolbars(tester, visible: true);
            final tooltip =
                tester.widget<ChartTooltip>(find.byType(ChartTooltip));
            expect(tooltip.palette.surface, palette.surface);
            expect(
              tooltip.colors.at(1, legendName),
              _chosenInk,
            );
            expect(
              _contrast(palette.strongLabel, palette.surface),
              greaterThan(4.5),
            );
            expect(_contrast(palette.label, palette.surface), greaterThan(2.5));
            final tooltipCard = find
                .descendant(
                  of: find.byType(ChartTooltip),
                  matching: find.byType(DecoratedBox),
                )
                .first;
            final decoration = tester
                .widget<DecoratedBox>(tooltipCard)
                .decoration as BoxDecoration;
            expect(decoration.color, palette.surface);
            expect(decoration.boxShadow, isNotEmpty);
            final hoveredPixels = await _capture(tester, _page);
            _expectPixel(
              hoveredPixels,
              tester.getTopLeft(tooltipCard) +
                  const Offset(8, 8) -
                  tester.getTopLeft(find.byKey(_page)),
              palette.surface,
            );
            await _expectPageShowingThrough(tester, pageColor);
            expect(tester.state(find.byType(AppChart)), same(chartState));
            expect(tester.renderObject(_plot), same(plot));
            expect(tester.getRect(_plot), bounds);

            await mouse.moveTo(const Offset(2, 2));
            await tester.pumpAndSettle();
            _expectToolbars(tester, visible: false);
            expect(find.byType(ChartTooltip), findsNothing);
            expect(tester.state(find.byType(AppChart)), same(chartState));
            expect(reads, 1, reason: 'Hover must not reload the source.');
            expect(
              writes,
              0,
              reason: 'Appearance must not rewrite saved data.',
            );
            expect(tester.takeException(), isNull);
          } finally {
            await mouse.removePointer();
            await tester.pumpWidget(const SizedBox());
            source.dispose();
          }
        });
      }
    }

    testWidgets(
        '$appearance: integrated stage retains focus, zoom, pan and hidden '
        'series through hover, menus and real source reloads', (tester) async {
      var table = _table;
      var reads = 0;
      var writes = 0;
      final spec = ValueNotifier(_spec());
      final source = ChartSource(
        viewId: 'retained-chart',
        loadTable: (_) async {
          reads++;
          return table;
        },
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<ChartSpec>(
            valueListenable: spec,
            builder: (_, value, __) => ChartStage(
              viewId: source.viewId,
              source: source,
              title: 'Retained chart',
              spec: value,
              onSpecChanged: (next) {
                writes++;
                spec.value = ChartSpec.fromJson(next.toJson());
              },
            ),
          ),
          customPage: true,
        );
        final chartState = tester.state(find.byType(AppChart));
        final stageState = tester.state(find.byType(ChartStage));
        await _tabTo(tester, _icon(LocaleKeys.canvas_zoom_zoomIn.tr()));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(_painter(tester).viewport.scale, closeTo(1.4, 0.0001));
        final focus = FocusManager.instance.primaryFocus;
        await mouse.addPointer(location: const Offset(2, 2));
        await mouse.moveTo(tester.getCenter(_plot));
        await tester.pumpAndSettle();
        await mouse.moveTo(const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, same(focus));

        await tester.tap(
          find.descendant(
            of: find.byType(AppChart),
            matching: find.text('Revenue'),
          ),
        );
        await tester.pumpAndSettle();
        expect(_painter(tester).hidden, {0});
        final beforePan = _painter(tester).viewport;
        final drag = await tester.startGesture(
          tester.getCenter(_plot),
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveBy(const Offset(-8, 0));
        await tester.pump();
        await drag.moveBy(const Offset(-50, 0));
        await tester.pump();
        await drag.up();
        await drag.removePointer();
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
        final viewport = _painter(tester).viewport;
        expect(viewport.offset, greaterThan(beforePan.offset));
        expect(viewport.scale, beforePan.scale);

        table = ChartTable(
          columns: _table.columns,
          columnIds: _table.columnIds,
          rows: [
            ..._table.rows,
            ['North', '5', '3'],
            ['Central', '20', '9'],
          ],
        );
        source.invalidate();
        await tester.pump(source.settle);
        await tester.pumpAndSettle();
        expect(reads, 2);
        expect(_painter(tester).data.categories.last, 'Central');
        expect(_painter(tester).data.series.first.points.first.value, 29);
        expect(_painter(tester).viewport, viewport);
        expect(_painter(tester).hidden, {0});

        await _click(tester, mouse, _icon(LocaleKeys.charts_options.tr()));
        expect(find.byType(AppMenuSurface), findsOneWidget);
        final menuStyle =
            AppMenuStyle.of(tester.element(find.byType(AppMenuSurface)));
        expect(menuStyle.surface.a, 1);
        expect(menuStyle.shadows, isNotEmpty);
        expect(
          _contrast(menuStyle.labelRest, menuStyle.surface),
          greaterThan(4.5),
        );
        await _click(
          tester,
          mouse,
          find.byWidgetPredicate(
            (widget) =>
                widget is AppMenuRow &&
                widget.label == LocaleKeys.charts_showGrid.tr(),
          ),
        );
        expect(writes, 1);
        expect(spec.value.showGrid, isFalse);
        expect(spec.value.colors, _spec().colors);
        expect(_painter(tester).viewport, viewport);
        expect(_painter(tester).hidden, {0});
        await _tabTo(tester, _icon(LocaleKeys.charts_refresh.tr()));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          reads,
          3,
          reason: 'The actual Refresh callback still loads data.',
        );
        expect(_painter(tester).viewport, viewport);
        expect(_painter(tester).hidden, {0});
        expect(tester.state(find.byType(AppChart)), same(chartState));
        expect(tester.state(find.byType(ChartStage)), same(stageState));
        await _expectPageShowingThrough(tester, _pageColor(appearance, true));
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        source.dispose();
        spec.dispose();
      }
    });

    testWidgets(
        '$appearance: explicit fill and opt-in frame remain available without '
        'remounting the chart', (tester) async {
      final source = ChartSource(
        viewId: 'explicit-surface-chart',
        loadTable: (_) async => _table,
      );
      final surface = ValueNotifier<(bool, Color?)>((false, null));
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<(bool, Color?)>(
            valueListenable: surface,
            builder: (_, value, __) => ChartStage(
              viewId: source.viewId,
              source: source,
              spec: _spec(),
              framed: value.$1,
              background: value.$2,
              onSpecChanged: (_) {},
            ),
          ),
        );
        final state = tester.state(find.byType(AppChart));
        await _tabTo(tester, _icon(LocaleKeys.canvas_zoom_zoomIn.tr()));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final viewport = _painter(tester).viewport;
        for (final choice in <(bool, Color?)>[
          (true, null),
          (false, _pageColor(appearance, true)),
          (false, null),
        ]) {
          surface.value = choice;
          await tester.pumpAndSettle();
          final stage = tester.widget<Container>(
            find
                .descendant(
                  of: find.byType(ChartStage),
                  matching: find.byType(Container),
                )
                .first,
          );
          final decoration = stage.decoration! as BoxDecoration;
          expect(
            decoration.boxShadow,
            choice.$1 ? isNotEmpty : isNull,
          );
          expect(decoration.border, choice.$1 ? isNotNull : isNull);
          final expected = choice.$2 ??
              (choice.$1 ? _painter(tester).palette.background : null);
          expect(decoration.color, expected);
          final pixels = await _capture(tester, _layer);
          if (expected == null) {
            expect(pixels.at(const Offset(25, 4)).a, 0);
          } else {
            _expectPixel(pixels, const Offset(25, 4), expected);
          }
          expect(tester.state(find.byType(AppChart)), same(state));
          expect(_painter(tester).viewport, viewport);
          expect(_painter(tester).colors.at(1, 'Costs'), _chosenInk);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        source.dispose();
        surface.dispose();
      }
    });

    for (final accessible in [false, true]) {
      testWidgets(
          '$appearance: reduced-motion hover and accessible navigation=$accessible '
          'keep the integrated chart mounted', (tester) async {
        final source = ChartSource(
          viewId: 'reduced-motion-chart',
          loadTable: (_) async => _table,
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await _mount(
            tester,
            appearance,
            ChartStage(
              viewId: source.viewId,
              source: source,
              spec: _spec(),
              onSpecChanged: (_) {},
            ),
            reducedMotion: true,
            accessibleNavigation: accessible,
          );
          final state = tester.state(find.byType(AppChart));
          _expectToolbars(tester, visible: accessible, duration: Duration.zero);
          await mouse.addPointer(location: const Offset(2, 2));
          await mouse.moveTo(tester.getTopLeft(_plot) + const Offset(4, 4));
          await tester.pump();
          _expectToolbars(tester, visible: true, duration: Duration.zero);
          await mouse.moveTo(const Offset(2, 2));
          await tester.pump();
          _expectToolbars(tester, visible: accessible, duration: Duration.zero);
          expect(tester.state(find.byType(AppChart)), same(state));
          await _expectPageShowingThrough(
            tester,
            _pageColor(appearance, false),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
          source.dispose();
        }
      });
    }

    testWidgets(
        '$appearance: dashboard chart shell is transparent, keeps selection '
        'and respects a saved accent', (tester) async {
      final original = DashboardWidgetRegistry.definitionFor('chart')!;
      final spec = original.create().copyWith(title: 'Dashboard totals');
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(id: 'charts', widgets: [spec]),
          ],
        ),
        mode: DashboardMode.edit,
        persistDebounce: const Duration(days: 1),
      );
      final data = buildChartData(_table, _spec());
      // Replace only the backend-bound body using the registry's existing
      // injection seam. The real card, populated renderer, title, hover
      // controls, selection and resizing shell are exercised, with no FFI.
      DashboardWidgetRegistry.register(
        DashboardWidgetDefinition(
          type: original.type,
          label: original.label,
          icon: original.icon,
          group: original.group,
          paintsOwnSurface: original.paintsOwnSurface,
          padding: original.padding,
          headerTrailing: original.headerTrailing,
          builder: (context) => AppChart(
            data: data,
            spec: _spec(),
            palette: chartPaletteOf(
              context.context,
              background: context.spec.accent == DashboardAccent.neutral
                  ? null
                  : context.tone.surface,
            ),
            animate: false,
            allowZoom: false,
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _mount(
          tester,
          appearance,
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => DashboardCard(
              controller: controller,
              spec: controller.document.allWidgets.first,
              palette: DashboardPalette.of(context),
              selected: controller.selectedWidgetId == spec.id,
              dragging: false,
            ),
          ),
          customPage: true,
        );
        final chartState = tester.state(find.byType(AppChart));
        final titleRect = tester.getRect(find.text('Dashboard totals'));
        await _expectPageShowingThrough(tester, _pageColor(appearance, true));
        await mouse.addPointer(location: const Offset(2, 2));
        await mouse.moveTo(tester.getCenter(_plot));
        await tester.pumpAndSettle();
        await _expectPageShowingThrough(tester, _pageColor(appearance, true));
        expect(
          find.byTooltip(LocaleKeys.dashboard_card_more.tr()).hitTestable(),
          findsOneWidget,
        );
        expect(tester.getRect(find.text('Dashboard totals')), titleRect);
        expect(tester.state(find.byType(AppChart)), same(chartState));

        controller.select(spec.id);
        await tester.pumpAndSettle();
        final shell = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byType(DashboardCard),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        final decoration = shell.decoration! as BoxDecoration;
        expect(decoration.color, isNull);
        expect(decoration.boxShadow, isEmpty);
        final ring = shell.foregroundDecoration! as BoxDecoration;
        expect((ring.border! as Border).top.color.a, greaterThan(0));

        controller.edit(
          (document) => document.withWidget(
            spec.copyWith(accent: DashboardAccent.green),
          ),
        );
        await tester.pumpAndSettle();
        final tone =
            DashboardPalette.of(tester.element(find.byType(DashboardCard)))
                .toneFor(DashboardAccent.green);
        _expectPixel(
          await _capture(tester, _layer),
          const Offset(25, 4),
          tone.surface,
        );
        expect(_painter(tester).palette.background, tone.surface);
        expect(tester.state(find.byType(AppChart)), same(chartState));
        expect(
          controller.document.allWidgets.first.accent,
          DashboardAccent.green,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        DashboardWidgetRegistry.register(original);
      }
    });

    testWidgets('$appearance: non-chart dashboard cards retain their surface',
        (tester) async {
      final spec = DashboardWidgetRegistry.definitionFor('metric')!.create();
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument(
          sections: [
            DashboardSection(id: 'metrics', widgets: [spec]),
          ],
        ),
        mode: DashboardMode.presentation,
      );
      try {
        await _mount(
          tester,
          appearance,
          Builder(
            builder: (context) => DashboardCard(
              controller: controller,
              spec: spec,
              palette: DashboardPalette.of(context),
              selected: false,
              dragging: false,
            ),
          ),
          customPage: true,
        );
        final shell = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byType(DashboardCard),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        final decoration = shell.decoration! as BoxDecoration;
        expect(decoration.boxShadow, isNotEmpty);
        expect(decoration.color!.a, 1);
        _expectPixel(
          await _capture(tester, _layer),
          const Offset(25, 4),
          decoration.color!,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    });

    testWidgets('$appearance: unbound inline chart is integrated before setup',
        (tester) async {
      final node = chartBlockNode(width: 680, height: 380);
      final editor =
          EditorState(document: Document(root: pageNode(children: [node])))
            ..disableSealTimer = true
            ..editable = false;
      try {
        await _mount(
          tester,
          appearance,
          Provider<EditorState>.value(
            value: editor,
            child: ChartBlockComponent(node: node),
          ),
          customPage: true,
        );
        expect(
          find.text(LocaleKeys.charts_pickTable.tr()).hitTestable(),
          findsOneWidget,
        );
        await _expectPageShowingThrough(tester, _pageColor(appearance, true));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        editor.dispose();
      }
    });

    testWidgets(
        '$appearance: standalone and database tab hosts opt into no card',
        (tester) async {
      // Empty ids deliberately avoid native reads. Populated shared-stage
      // pixels and input are covered above; this pins the real host wiring.
      final view = ViewPB(
        name: 'Chart page',
        extra: ChartMetadata(spec: _spec()).mergeIntoExtra(''),
      );
      for (final host in [ChartPage(view: view), ChartTabPage(view: view)]) {
        await _mount(
          tester,
          appearance,
          host,
          preview: false,
          customPage: true,
        );
        expect(
          tester.widget<ChartStage>(find.byType(ChartStage)).framed,
          isFalse,
        );
        expect(
          tester.widget<ChartStage>(find.byType(ChartStage)).background,
          isNull,
        );
        _expectToolbars(tester, visible: true);
        if (host is ChartPage) {
          expect(
            find.text(LocaleKeys.charts_showTable.tr()).hitTestable(),
            findsOneWidget,
          );
          expect(find.text('Chart page'), findsOneWidget);
        }
        await _expectPageShowingThrough(tester, _pageColor(appearance, true));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets(
      'transparent AppChart still selects values and only modifier-wheel zooms',
      (tester) async {
    final selected = <(String, String)>[];
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await _mount(
        tester,
        'paper',
        Builder(
          builder: (context) => AppChart(
            data: buildChartData(_table, _spec()),
            spec: _spec(),
            palette: chartPaletteOf(context),
            animate: false,
            onSelected: (category, series) => selected.add((category, series)),
          ),
        ),
        customPage: true,
      );
      final state = tester.state(find.byType(AppChart));
      await mouse.addPointer(location: const Offset(2, 2));
      final hit = _painter(tester).hits.lastWhere((hit) => hit.pointIndex == 1);
      final position = tester.getTopLeft(_plot) + hit.rect.center;
      await mouse.moveTo(position);
      await mouse.down(position);
      await mouse.up();
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(selected, [('South', 'Costs')]);
      final wheel = PointerScrollEvent(
        position: tester.getCenter(_plot),
        scrollDelta: const Offset(0, -80),
      );
      tester.binding.handlePointerEvent(wheel);
      await tester.pumpAndSettle();
      expect(_painter(tester).viewport.isIdentity, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      try {
        tester.binding.handlePointerEvent(wheel);
        await tester.pumpAndSettle();
      } finally {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }
      expect(_painter(tester).viewport.scale, closeTo(1.18, 0.0001));
      expect(tester.state(find.byType(AppChart)), same(state));
      expect(
        selected,
        hasLength(1),
        reason: 'Zoom is not a selection callback.',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    }
  });
}

Finder get _plot => find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ChartPainter,
    );

ChartPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_plot).painter! as ChartPainter;

Finder _icon(String tooltip) => find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == tooltip,
    );

Future<void> _hoverValue(WidgetTester tester, TestGesture mouse) async {
  final painter = _painter(tester);
  final hit = painter.hits.lastWhere((hit) => hit.pointIndex == 1);
  await mouse.moveTo(tester.getTopLeft(_plot) + hit.rect.center);
  await tester.pumpAndSettle();
  expect(find.byType(ChartTooltip), findsOneWidget);
}

Future<void> _click(
  WidgetTester tester,
  TestGesture mouse,
  Finder target,
) async {
  final position = tester.getCenter(target);
  await mouse.moveTo(position);
  await tester.pumpAndSettle();
  await mouse.down(position);
  await mouse.up();
  // Do not let a stationary pointer accidentally open a submenu beneath it.
  await mouse.moveTo(const Offset(2, 2));
  await tester.pump(kDoubleTapTimeout);
  await tester.pumpAndSettle();
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  Focus.of(tester.element(find.text('Outside chart'))).requestFocus();
  await tester.pump();
  await tester.pump();
  bool inside() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    final element = target.evaluate().single;
    var found = identical(context, element);
    context.visitAncestorElements((ancestor) {
      if (identical(ancestor, element)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  for (var index = 0; index < 30 && !inside(); index++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
  }
  expect(
    inside(),
    isTrue,
    reason: 'Hidden chart actions remain keyboard reachable.',
  );
  await tester.pumpAndSettle();
}

void _expectToolbars(
  WidgetTester tester, {
  required bool visible,
  Duration? duration,
}) {
  final bars = find.byType(PreviewToolbar);
  expect(bars, findsWidgets);
  for (final element in bars.evaluate()) {
    final opacity = find
        .descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(AnimatedOpacity),
        )
        .first;
    expect(tester.widget<AnimatedOpacity>(opacity).opacity, visible ? 1 : 0);
    expect(
      tester.renderObject<RenderAnimatedOpacity>(opacity).opacity.value,
      visible ? 1 : 0,
    );
    if (duration != null) {
      expect(tester.widget<AnimatedOpacity>(opacity).duration, duration);
    }
  }
}

Future<void> _expectPageShowingThrough(
  WidgetTester tester,
  Color pageColor,
) async {
  final layer = await _capture(tester, _layer);
  final page = await _capture(tester, _page);
  final layerOrigin = tester.getTopLeft(find.byKey(_layer));
  final inPage = layerOrigin - tester.getTopLeft(find.byKey(_page));
  final stage = find.byType(ChartStage);
  final resizedFrame = find.byKey(const ValueKey('resizable_media'));
  final surface = stage.evaluate().isNotEmpty
      ? tester.getRect(stage).shift(-layerOrigin)
      : resizedFrame.evaluate().isNotEmpty
          ? tester.getRect(resizedFrame).shift(-layerOrigin)
          : Rect.fromLTWH(
              0,
              0,
              layer.width.toDouble(),
              layer.height.toDouble(),
            );
  final points = [
    surface.topLeft + const Offset(25, 4),
    surface.topRight + const Offset(-25, 4),
    surface.bottomLeft + const Offset(25, -4),
    surface.bottomRight - const Offset(25, 4),
    if (_plot.evaluate().isNotEmpty)
      tester.getTopLeft(_plot) - layerOrigin + const Offset(4, 4),
  ];
  for (final point in points) {
    expect(layer.at(point).a, 0, reason: 'No chart canvas fill at $point.');
    _expectPixel(page, inPage + point, pageColor);
  }
}

class _Pixels {
  const _Pixels(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final ByteData bytes;

  Color at(Offset point) {
    assert(point.dx >= 0 && point.dx < width);
    assert(point.dy >= 0 && point.dy < height);
    final x = point.dx.floor();
    final y = point.dy.floor();
    final index = (y * width + x) * 4;
    return Color.fromARGB(
      bytes.getUint8(index + 3),
      bytes.getUint8(index),
      bytes.getUint8(index + 1),
      bytes.getUint8(index + 2),
    );
  }

  int inkPixels(Color ink, Rect bounds) {
    var found = 0;
    for (var y = bounds.top.ceil(); y < bounds.bottom.floor(); y++) {
      for (var x = bounds.left.ceil(); x < bounds.right.floor(); x++) {
        final pixel = at(Offset(x.toDouble(), y.toDouble()));
        if (pixel.a > 0.95 &&
            (pixel.r - ink.r).abs() < 0.065 &&
            (pixel.g - ink.g).abs() < 0.065 &&
            (pixel.b - ink.b).abs() < 0.065) {
          if (++found > 30) return found;
        }
      }
    }
    return found;
  }
}

Future<_Pixels> _capture(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return _Pixels(
        image.width,
        image.height,
        (await image.toByteData())!,
      );
    } finally {
      image.dispose();
    }
  }))!;
}

void _expectPixel(_Pixels pixels, Offset point, Color expected) {
  final actual = pixels.at(point);
  expect(actual.a, closeTo(expected.a, 1 / 255), reason: 'alpha at $point');
  expect(actual.r, closeTo(expected.r, 1 / 255), reason: 'red at $point');
  expect(actual.g, closeTo(expected.g, 1 / 255), reason: 'green at $point');
  expect(actual.b, closeTo(expected.b, 1 / 255), reason: 'blue at $point');
}

double _contrast(Color ink, Color background) {
  final foreground = Color.alphaBlend(ink, background).computeLuminance();
  final back = background.computeLuminance();
  return (math.max(foreground, back) + 0.05) /
      (math.min(foreground, back) + 0.05);
}

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      '',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Color _pageColor(String appearance, bool custom) {
  if (custom) {
    return switch (appearance) {
      'dark' => const Color(0xFF28302E),
      'paper' => const Color(0xFFE5D2B6),
      _ => const Color(0xFFE9DACA),
    };
  }
  return _theme(appearance).extension<PremiumThemeExtension>()!.canvas;
}

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  Widget child, {
  bool customPage = false,
  bool preview = true,
  bool reducedMotion = false,
  bool accessibleNavigation = false,
}) async {
  final theme = _theme(appearance);
  Widget app(Widget body) => EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        saveLocale: false,
        assetLoader: const TestBundleAssetLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: const Locale('en', 'US'),
            localizationsDelegates: context.localizationDelegates,
            theme: theme,
            themeAnimationDuration: Duration.zero,
            builder: (context, navigator) => AppFlowyTheme(
              data: PremiumTheme.appFlowyTheme(
                base: appearance == 'dark'
                    ? AppFlowyDefaultTheme().dark()
                    : AppFlowyDefaultTheme().light(),
                palette: theme.extension<PremiumThemeExtension>()!,
                brightness: theme.brightness,
              ),
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: reducedMotion,
                  accessibleNavigation: accessibleNavigation,
                ),
                child: TooltipVisibility(visible: false, child: navigator!),
              ),
            ),
            home: Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {},
                    child: const Text('Outside chart'),
                  ),
                  Center(
                    child: SizedBox(
                      width: 760,
                      height: 500,
                      child: RepaintBoundary(
                        key: _page,
                        // Do not retint the theme for a custom page: an opaque
                        // theme-colored rectangle must fail these pixels.
                        child: ColoredBox(
                          color: _pageColor(appearance, customPage),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: RepaintBoundary(
                              key: _layer,
                              child: preview
                                  ? PreviewToolbarRegion(child: body)
                                  : body,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  await tester.pumpWidget(app(const SizedBox()));
  await tester.pumpAndSettle();
  await tester.pumpWidget(app(child));
  await tester.pumpAndSettle();
}
