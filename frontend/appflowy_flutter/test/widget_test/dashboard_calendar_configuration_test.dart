import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_panel.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/data_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/time_widgets.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_view_setting.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_agenda_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'calendar_test_support.dart';

const _id = 'calendar-configuration-widget';
const _boardSize = Size(1100, 747);
const _listKey = PageStorageKey('calendar-day-agenda-scroll');
const _outerKey = PageStorageKey('calendar-month-agenda-outer');
final _day = DateTime(2026, 8, 14);

String _modeKey(String type) =>
    type == 'calendar' ? 'mode' : dashboardDatabaseCalendarModeKey;

DashboardController _controller(
  String type, {
  DashboardDocument? document,
  bool showTitle = false,
}) =>
    DashboardController(
      // The production controller deliberately never writes an empty view ID.
      viewId: '',
      persistDebounce: const Duration(days: 1),
      document: document ??
          DashboardDocument(
            settings: const DashboardSettings(reduceMotion: true),
            sections: [
              DashboardSection(
                id: 'calendar-configuration-section',
                widgets: [
                  DashboardWidgetSpec(
                    id: _id,
                    type: type,
                    title: 'Keep this title',
                    showTitle: showTitle,
                    source: type == 'database'
                        ? const DashboardDataSource(
                            kind: DashboardSourceKind.database,
                            viewId: 'offline-calendar-table',
                            name:
                                'A long team calendar name that must fit the panel',
                          )
                        : DashboardDataSource.none,
                    settings: {
                      if (type == 'calendar') 'mode': 'month',
                      'unrelated_setting': 'keep',
                    },
                  ),
                ],
              ),
            ],
          ),
    );

Finder _choice(String name) =>
    find.byKey(ValueKey('dashboard-calendar-mode-$name'));

CalendarMonthAgendaView _reading(WidgetTester tester) => tester
    .widget<CalendarMonthAgendaView>(find.byType(CalendarMonthAgendaView));

Widget _panel(DashboardController controller) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Stack(
        children: [
          // Like DashboardPage: horizontal constraints are supplied by the
          // panel itself, not by a tight fixture that could conceal overflow.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: DashboardConfigPanel(
              controller: controller,
              palette: DashboardPalette.of(context),
              spec: controller.document.widgetById(_id)!,
            ),
          ),
        ],
      ),
    );

/// Real card controls and configuration; their overlay never reparents the body.
Widget _board(DashboardController controller) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final palette = DashboardPalette.of(context);
        final spec = controller.document.widgetById(_id)!;
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 720,
              height: 520,
              child: DashboardCard(
                key: const ValueKey('calendar-configuration-card'),
                controller: controller,
                spec: spec,
                palette: palette,
                selected: controller.selectedWidgetId == _id,
                dragging: false,
              ),
            ),
            if (controller.configuringWidgetId == _id)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: DashboardConfigPanel(
                  controller: controller,
                  palette: palette,
                  spec: spec,
                ),
              ),
          ],
        );
      },
    );

/// Only native/service startup is substituted. Both definitions still supply
/// their actual configure schema and renderer declaration. For a table, retain
/// its production scope and size provider, substituting the native tab/Stage
/// startup with a real shell and offline workspace. Native startup is not tested.
DashboardWidgetDefinition _offlineDefinition(
  DashboardWidgetDefinition original,
  CalendarWorkspace workspace,
  CalendarViewSettings tableSettings,
  ViewPB table,
) =>
    DashboardWidgetDefinition(
      type: original.type,
      label: original.label,
      icon: original.icon,
      group: original.group,
      padding: original.padding,
      configure: original.configure,
      builder: (data) {
        final declared = original.builder(data);
        final delegate = CalendarViewDelegate(
          colorOf: workspace.colorFor,
          onOpenEvent: (_) {},
        );
        if (original.type == 'calendar') {
          final calendar = declared as DashboardCalendar;
          return DashboardCalendar(
            key: calendar.key,
            context: calendar.context,
            workspace: workspace,
            delegate: delegate,
            initialDate: _day,
            now: () => _day,
          );
        }
        final scope = declared as DashboardDatabaseCalendarScope;
        final resolver = scope.child as DashboardViewBuilder;
        expect(resolver.viewId, table.id);
        final provider = resolver.builder(data.context, table)
            as Provider<DatabasePluginWidgetBuilderSize>;
        return DashboardDatabaseCalendarScope(
          key: scope.key,
          data: scope.data,
          child: MultiProvider(
            providers: [provider],
            child: ValueListenableBuilder<CalendarViewMode?>(
              valueListenable: tableSettings.listenable(table),
              builder: (context, saved, _) {
                expect(
                  context
                      .read<DatabasePluginWidgetBuilderSize>()
                      .horizontalPadding,
                  0,
                );
                return CalendarShell(
                  workspace: workspace,
                  initialMode: saved ?? CalendarViewMode.month,
                  mode: saved ?? CalendarViewMode.month,
                  onModeChanged: (mode) =>
                      unawaited(tableSettings.set(table, mode)),
                  initialDate: _day,
                  now: () => _day,
                  delegate: delegate,
                );
              },
            ),
          ),
        );
      },
    );

void _expectVisibleChoice(WidgetTester tester, CalendarViewMode mode) {
  final tile = _choice(mode.name);
  final panel = find.byType(DashboardConfigPanel);
  final list = find.descendant(of: panel, matching: find.byType(ListView));
  final visible = tester.getRect(list).intersect(tester.getRect(panel));
  final rect = tester.getRect(tile);
  expect(visible.inflate(0.01).contains(rect.topLeft), isTrue);
  expect(visible.inflate(0.01).contains(rect.bottomRight), isTrue);
  expect(tile.hitTestable(), findsOneWidget);
  final title = find.descendant(of: tile, matching: find.byType(Text));
  final text = tester.widget<Text>(title);
  expect(text.data, calendarViewModeLabel(mode));
  expect(text.data, isNot(startsWith('calendarView.')));
  expect(text.maxLines, isNull);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: title, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
  final semantics = tester.getSemantics(tile);
  expect(semantics.attached, isTrue);
  final data = semantics.getSemanticsData();
  expect(data.label, contains(calendarViewModeLabel(mode)));
  expect(data.hasFlag(ui.SemanticsFlag.hasCheckedState), isTrue);
  expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
}

void main() {
  setUpAll(initializeCalendarTests);

  for (final type in ['calendar', 'database']) {
    for (final appearance in ['light', 'dark', 'paper']) {
      testWidgets(
          '$type $appearance: Configure exposes both compositions, updates live and reopens saved choice',
          (tester) async {
        tester.view.physicalSize = _boardSize;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        final original = DashboardWidgetRegistry.definitionFor(type)!;
        final provider = CalendarFixtureProvider(
          events: [
            for (var index = 0; index < 40; index++)
              calendarFixtureEvent('configuration-event-$index', _day),
          ],
        );
        final workspace = CalendarWorkspace(providers: [provider]);
        final extra = const CalendarViewSetting(CalendarViewMode.monthSplit)
            .mergeIntoExtra('{"another_table_setting":"keep"}');
        final table = ViewPB(
          id: 'offline-calendar-table',
          layout: ViewLayoutPB.Calendar,
          extra: extra,
        );
        var tableWrites = 0;
        final settings = CalendarViewSettings(
          readExtra: (_) async => extra,
          writeExtra: (_, __) async => tableWrites++,
        );
        var controller = _controller(type);
        DashboardWidgetRegistry.register(
          _offlineDefinition(original, workspace, settings, table),
        );
        try {
          await mountCalendarTest(
            tester,
            _board(controller),
            size: _boardSize,
            appearance: appearance,
          );
          final shell = tester.state(find.byType(CalendarShell));
          final card = tester.state(find.byType(DashboardCard));
          await tester
              .tap(find.byTooltip(LocaleKeys.dashboard_card_configure.tr()));
          await tester.pumpAndSettle();
          expect(find.byType(DashboardConfigPanel), findsOneWidget);
          expect(controller.configuringWidgetId, _id);
          expect(find.byType(AppMenuSurface), findsNothing);
          expect(
            find.byType(RadioListTile<String>),
            findsNWidgets(type == 'calendar' ? 7 : 8),
          );
          for (final mode in [
            CalendarViewMode.monthAgenda,
            CalendarViewMode.monthSplit,
          ]) {
            _expectVisibleChoice(tester, mode);
          }

          await tester.tap(_choice('monthAgenda'));
          await tester.pumpAndSettle();
          expect(_reading(tester).sideBySide, isFalse);
          final reading = tester.state(find.byType(CalendarMonthAgendaView));
          final flex = tester.element(
            find.byKey(const ValueKey('calendar-month-agenda-layout')),
          );
          final gridFocus = tester
              .widget<Focus>(
                find.byKey(const ValueKey('calendar-date-grid-focus')),
              )
              .focusNode;
          final agenda =
              tester.widget<ListView>(find.byKey(_listKey)).controller!;
          final outer = tester
              .widget<SingleChildScrollView>(find.byKey(_outerKey))
              .controller!;
          agenda.jumpTo(120);
          await tester.pump();
          await tester.tap(_choice('monthSplit'));
          await tester.pumpAndSettle();
          expect(_reading(tester).sideBySide, isTrue);
          expect(_reading(tester).selectedDay, _day);
          expect(tester.state(find.byType(CalendarShell)), same(shell));
          expect(tester.state(find.byType(DashboardCard)), same(card));
          expect(
            tester.state(find.byType(CalendarMonthAgendaView)),
            same(reading),
          );
          expect(
            tester.element(
              find.byKey(const ValueKey('calendar-month-agenda-layout')),
            ),
            same(flex),
          );
          expect(
            tester
                .widget<Focus>(
                  find.byKey(const ValueKey('calendar-date-grid-focus')),
                )
                .focusNode,
            same(gridFocus),
          );
          expect(
            tester.widget<ListView>(find.byKey(_listKey)).controller,
            same(agenda),
          );
          expect(
            tester
                .widget<SingleChildScrollView>(find.byKey(_outerKey))
                .controller,
            same(outer),
          );
          expect(agenda.offset, 120);
          expect(provider.windows, hasLength(1));
          final saved = controller.document.widgetById(_id)!;
          expect(saved.setting(_modeKey(type)), 'monthSplit');
          expect(saved.setting('unrelated_setting'), 'keep');
          expect(saved.title, 'Keep this title');
          expect(
            tester.widget<RadioListTile<String>>(_choice('monthSplit')).checked,
            isTrue,
          );

          await tester.tap(
            find.descendant(
              of: find.byType(DashboardConfigPanel),
              matching: find.byTooltip(LocaleKeys.button_close.tr()),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DashboardConfigPanel), findsNothing);
          await tester
              .tap(find.byTooltip(LocaleKeys.dashboard_card_configure.tr()));
          await tester.pumpAndSettle();
          _expectVisibleChoice(tester, CalendarViewMode.monthSplit);
          expect(
            tester.widget<RadioListTile<String>>(_choice('monthSplit')).checked,
            isTrue,
          );
          expect(
            tester.state(find.byType(CalendarMonthAgendaView)),
            same(reading),
          );
          expect(agenda.offset, 120);

          final reopened = DashboardDocument.fromJson(
            Map<String, Object?>.from(
              jsonDecode(jsonEncode(controller.document.toJson())) as Map,
            ),
          );
          await controller.flush();
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          controller = _controller(type, document: reopened)..configure(_id);
          await mountCalendarTest(
            tester,
            _board(controller),
            size: _boardSize,
            appearance: appearance,
          );
          expect(_reading(tester).sideBySide, isTrue);
          expect(
            tester.widget<RadioListTile<String>>(_choice('monthSplit')).checked,
            isTrue,
          );
          _expectVisibleChoice(tester, CalendarViewMode.monthSplit);
          expect(table.extra, extra);
          expect(settings.listenable(table).value, CalendarViewMode.monthSplit);
          expect(
            tableWrites,
            0,
            reason: 'A card choice must not write the source table page.',
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          workspace.dispose();
          settings.reset();
          DashboardWidgetRegistry.register(original);
          semantics.dispose();
        }
      });

      for (final rtl in [false, true]) {
        testWidgets(
            '$type $appearance: narrow 280x420 configuration at 2x rtl=$rtl has complete keyboard choices',
            (tester) async {
          const size = Size(280, 420);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final controller = _controller(type);
          final semantics = tester.ensureSemantics();
          try {
            await mountCalendarTest(
              tester,
              _panel(controller),
              size: size,
              textScale: 2,
              rtl: rtl,
              appearance: appearance,
            );
            expect(
              tester.getSize(find.byType(DashboardConfigPanel)).width,
              280,
            );
            for (final mode in [
              CalendarViewMode.monthAgenda,
              CalendarViewMode.monthSplit,
            ]) {
              final tile = _choice(mode.name);
              await tester.ensureVisible(tile);
              await tester.pumpAndSettle();
              _expectVisibleChoice(tester, mode);
              final title =
                  find.descendant(of: tile, matching: find.byType(Text));
              expect(tester.getSize(title).height, greaterThan(27));
              Focus.of(tester.element(title)).requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.space);
              await tester.pumpAndSettle();
              expect(
                controller.document.widgetById(_id)!.setting(_modeKey(type)),
                mode.name,
              );
              expect(
                tester.widget<RadioListTile<String>>(tile).checked,
                isTrue,
              );
              expect(
                tester
                    .getSemantics(tile)
                    .getSemanticsData()
                    .hasFlag(ui.SemanticsFlag.isChecked),
                isTrue,
              );
              expect(find.byType(AppMenuSurface), findsNothing);
            }
            final palette = DashboardPalette.of(
              tester.element(find.byType(DashboardConfigPanel)),
            );
            final material = tester.widget<Material>(
              find.descendant(
                of: find
                    .byKey(const ValueKey('dashboard-calendar-view-choices')),
                matching: find.byType(Material),
              ),
            );
            expect(material.color, palette.sunken);
            if (appearance == 'paper') {
              expect(material.color!.r, greaterThan(material.color!.b));
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            semantics.dispose();
          }
        });
      }
    }
  }

  testWidgets(
      'database default follows the source, runtime selection belongs to the card and read-only stays local',
      (tester) async {
    tester.view.physicalSize = _boardSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final original = DashboardWidgetRegistry.definitionFor('database')!;
    final workspace = CalendarWorkspace(providers: [CalendarFixtureProvider()]);
    var extra = const CalendarViewSetting(CalendarViewMode.monthAgenda)
        .mergeIntoExtra('');
    final table = ViewPB(
      id: 'offline-calendar-table',
      layout: ViewLayoutPB.Calendar,
      extra: extra,
    );
    var writes = 0;
    final settings = CalendarViewSettings(
      readExtra: (_) async => extra,
      writeExtra: (_, value) async {
        writes++;
        extra = value;
      },
    );
    // This case exercises runtime navigation too. Use the supported titled
    // card so its floating card controls do not cover the calendar's toolbar.
    // The Configure-path tests above deliberately retain the untitled cards.
    final controller = _controller('database', showTitle: true);
    DashboardWidgetRegistry.register(
      _offlineDefinition(original, workspace, settings, table),
    );
    try {
      await mountCalendarTest(tester, _board(controller), size: _boardSize);
      expect(_reading(tester).sideBySide, isFalse);
      expect(
        controller.document
            .widgetById(_id)!
            .settings
            .containsKey(dashboardDatabaseCalendarModeKey),
        isFalse,
      );
      final reading = tester.state(find.byType(CalendarMonthAgendaView));
      final received = ViewPB(
        id: table.id,
        extra: const CalendarViewSetting(CalendarViewMode.monthSplit)
            .mergeIntoExtra(''),
      );
      settings.adopt(received);
      await tester.pumpAndSettle();
      expect(_reading(tester).sideBySide, isTrue);
      expect(tester.state(find.byType(CalendarMonthAgendaView)), same(reading));
      await tester.tap(find.byKey(const ValueKey('calendar-mode-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          AppMenuRow,
          calendarViewModeLabel(CalendarViewMode.monthAgenda),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        controller.document
            .widgetById(_id)!
            .setting(dashboardDatabaseCalendarModeKey),
        'monthAgenda',
      );
      expect(settings.listenable(table).value, CalendarViewMode.monthSplit);
      expect(writes, 0);

      await tester
          .tap(find.byTooltip(LocaleKeys.dashboard_card_configure.tr()));
      await tester.pumpAndSettle();
      await tester.tap(_choice('source'));
      await tester.pumpAndSettle();
      expect(_reading(tester).sideBySide, isTrue);
      expect(
        controller.document
            .widgetById(_id)!
            .settings
            .containsKey(dashboardDatabaseCalendarModeKey),
        isFalse,
      );
      expect(
        tester.widget<RadioListTile<String>>(_choice('source')).checked,
        isTrue,
      );
      final field = DashboardWidgetRegistry.definitionFor('database')!
          .configure!(
            DashboardWidgetContext(
              context: tester.element(find.byType(DashboardConfigPanel)),
              controller: controller,
              spec: controller.document.widgetById(_id)!,
              palette: DashboardPalette.of(
                tester.element(find.byType(DashboardConfigPanel)),
              ),
            ),
          )
          .whereType<DashboardConfigCalendarView>()
          .single;
      controller.setReadOnly(true);
      field.onChanged('monthAgenda');
      await tester.pumpAndSettle();
      expect(
        controller.document
            .widgetById(_id)!
            .settings
            .containsKey(dashboardDatabaseCalendarModeKey),
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-mode-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          AppMenuRow,
          calendarViewModeLabel(CalendarViewMode.monthAgenda),
        ),
      );
      await tester.pumpAndSettle();
      expect(_reading(tester).sideBySide, isFalse);
      expect(tester.state(find.byType(CalendarMonthAgendaView)), same(reading));
      expect(
        controller.document
            .widgetById(_id)!
            .settings
            .containsKey(dashboardDatabaseCalendarModeKey),
        isFalse,
      );
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      workspace.dispose();
      settings.reset();
      DashboardWidgetRegistry.register(original);
    }
  });
}
