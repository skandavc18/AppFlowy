import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
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
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_header.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'calendar_test_support.dart';
import 'vivid_icon_test_support.dart' show settleVividIconPictures;

const _id = 'issue5-calendar';
const _cardKey = ValueKey('issue5-card');
const _headerKey = ValueKey('dashboard-card-header-$_id');
const _bodyKey = ValueKey('dashboard-card-body-$_id');
const _managementKey = ValueKey('dashboard-card-management-$_id');
const _databaseSettingsKey = ValueKey('issue5-database-settings');
const _toolbarKey = ValueKey('calendar-month-agenda-toolbar');
const _agendaKey = PageStorageKey('calendar-day-agenda-scroll');
const _outerKey = PageStorageKey('calendar-month-agenda-outer');
const _gridFocusKey = ValueKey('calendar-date-grid-focus');
const _widths = [240.0, 360.0, 680.0, 960.0];
final _today = DateTime(2026, 8, 14);

String _modeKey(String type) =>
    type == 'calendar' ? 'mode' : dashboardDatabaseCalendarModeKey;

Finder _managementButton(String tooltip) => find.descendant(
      of: find.byKey(_managementKey),
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      ),
    );

Finder _configure() =>
    _managementButton(LocaleKeys.dashboard_card_configure.tr());

Finder _more() => _managementButton(LocaleKeys.dashboard_card_more.tr());

Finder _navigation(String tooltip) => find.descendant(
      of: find.byType(CalendarShell),
      matching: find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      ),
    );

CalendarMonthAgendaView _reading(WidgetTester tester) => tester
    .widget<CalendarMonthAgendaView>(find.byType(CalendarMonthAgendaView));

Widget _card(DashboardController controller) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => DashboardCard(
        key: _cardKey,
        controller: controller,
        spec: controller.document.widgetById(_id)!,
        palette: DashboardPalette.of(context),
        selected: controller.selectedWidgetId == _id,
        dragging: false,
      ),
    );

void _screen(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.reset);
}

void _inside(Rect child, Rect parent) {
  expect(child.left, greaterThanOrEqualTo(parent.left - 0.01));
  expect(child.right, lessThanOrEqualTo(parent.right + 0.01));
  expect(child.top, greaterThanOrEqualTo(parent.top - 0.01));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom + 0.01));
}

void _managementVisible(WidgetTester tester, bool visible) {
  final toolbar = find.byKey(_managementKey);
  final opacity = tester.widget<AnimatedOpacity>(
    find.descendant(of: toolbar, matching: find.byType(AnimatedOpacity)).first,
  );
  expect(opacity.opacity, visible ? 1 : 0);
  for (final button in [_configure(), _more()]) {
    expect(button.hitTestable(), visible ? findsOneWidget : findsNothing);
  }
}

void _expectGeometry(
  WidgetTester tester, {
  required double width,
  required bool database,
  bool widgetControlsVisible = true,
}) {
  final card = tester.getRect(find.byKey(_cardKey));
  final header = tester.getRect(find.byKey(_headerKey));
  final body = tester.getRect(find.byKey(_bodyKey));
  final toolbar = tester.getRect(find.byKey(_toolbarKey));
  expect(card.width, width);
  _inside(header, card);
  _inside(body, card);
  _inside(toolbar, body);
  expect(header.bottom, lessThanOrEqualTo(body.top));

  final management = [_configure(), _more()];
  final navigation = [
    _navigation(LocaleKeys.calendarView_previous.tr()),
    _navigation(LocaleKeys.calendarView_today.tr()),
    _navigation(LocaleKeys.calendarView_next.tr()),
    find.byKey(const ValueKey('calendar-mode-menu')),
  ];
  for (final button in management) {
    final rect = tester.getRect(button);
    _inside(rect, header);
    expect(rect.bottom, lessThanOrEqualTo(body.top));
    expect(rect.overlaps(body), isFalse);
    // Check the actual native target, including the edge nearest the grip,
    // not just a visible icon whose pointer area could still be obstructed.
    for (final at in [
      Alignment.center,
      Alignment(-1 + 1 / rect.width, 0),
      Alignment(1 - 1 / rect.width, 0),
      Alignment(0, -1 + 1 / rect.height),
      Alignment(0, 1 - 1 / rect.height),
    ]) {
      expect(button.hitTestable(at: at), findsOneWidget);
    }
  }
  for (final button in navigation) {
    _inside(tester.getRect(button), toolbar);
    if (widgetControlsVisible) {
      expect(button.hitTestable(), findsOneWidget);
    }
  }
  final targets = [...management, ...navigation];
  if (database) {
    // The real database path has a tab/settings header BEFORE CalendarShell.
    // The old overlay could cover this header, not necessarily its date row.
    final databaseHeader = tester.getRect(find.byType(DatabaseTabHeaderLayout));
    _inside(databaseHeader, body);
    expect(databaseHeader.bottom, lessThanOrEqualTo(toolbar.top));
    final settings = find.descendant(
      of: find.byKey(_databaseSettingsKey),
      matching: find.byType(IconButton),
    );
    if (widgetControlsVisible) {
      expect(settings.hitTestable(), findsOneWidget);
    }
    _inside(tester.getRect(settings), databaseHeader);
    targets.add(settings);
  }
  for (var i = 0; i < targets.length; i++) {
    for (var j = i + 1; j < targets.length; j++) {
      expect(
        tester.getRect(targets[i]).overlaps(tester.getRect(targets[j])),
        isFalse,
        reason: 'Card management and native calendar/header targets need '
            'distinct layout space at $width, not just opacity or scrolling.',
      );
    }
  }
  for (final chrome in [find.byKey(_managementKey), find.byKey(_toolbarKey)]) {
    expect(
      find.descendant(
        of: chrome,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
  }
}

void main() {
  setUpAll(initializeCalendarTests);

  for (final type in ['calendar', 'database']) {
    for (final appearance in ['light', 'dark', 'paper']) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets(
            '$type $appearance ${textScale}x: real headerless card separates management at 240/360/680/960',
            (tester) async {
          _screen(tester);
          final fixture = _CalendarCardFixture(type);
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(2, 2));
          try {
            await mountCalendarTest(
              tester,
              _card(fixture.controller),
              size: const Size(960, 520),
              appearance: appearance,
              textScale: textScale,
              accessibleNavigation: false,
            );
            final shell = tester.state(find.byType(CalendarShell));
            final reading = tester.state(find.byType(CalendarMonthAgendaView));
            for (final mode in [
              CalendarViewMode.monthSplit,
              CalendarViewMode.monthAgenda,
            ]) {
              fixture.controller.edit(
                (document) => document.withWidget(
                  document
                      .widgetById(_id)!
                      .withSettings({_modeKey(type): mode.name}),
                ),
              );
              for (final width in _widths) {
                FocusManager.instance.primaryFocus?.unfocus();
                fixture.controller.select(null);
                await mouse.moveTo(const Offset(2, 2));
                await tester.pumpWidget(
                  calendarTestApp(
                    _card(fixture.controller),
                    size: Size(width, 520),
                    appearance: appearance,
                    textScale: textScale,
                    accessibleNavigation: false,
                  ),
                );
                await tester.pumpAndSettle();
                final beforeHover = tester.getRect(find.byKey(_bodyKey));
                await mouse.moveTo(tester.getCenter(find.byKey(_toolbarKey)));
                await tester.pumpAndSettle();
                _managementVisible(tester, true);
                _expectGeometry(
                  tester,
                  width: width,
                  database: type == 'database',
                );
                expect(tester.getRect(find.byKey(_bodyKey)), beforeHover);
                expect(tester.state(find.byType(CalendarShell)), same(shell));
                expect(
                  tester.state(find.byType(CalendarMonthAgendaView)),
                  same(reading),
                );
                expect(
                  _reading(tester).sideBySide,
                  mode == CalendarViewMode.monthSplit,
                );

                await mouse.moveTo(const Offset(2, 2));
                await tester.pumpAndSettle();
                _managementVisible(tester, false);
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.pumpAndSettle();
                _managementVisible(tester, true);
                _expectGeometry(
                  tester,
                  width: width,
                  database: type == 'database',
                  // Only management owns focus; the calendar's own quiet
                  // toolbar still retains geometry without intercepting taps.
                  widgetControlsVisible: false,
                );
                expect(tester.getRect(find.byKey(_bodyKey)), beforeHover);
                FocusManager.instance.primaryFocus?.unfocus();
                fixture.controller.select(_id);
                await tester.pumpAndSettle();
                _managementVisible(tester, true);
                _expectGeometry(
                  tester,
                  width: width,
                  database: type == 'database',
                  widgetControlsVisible: false,
                );
                expect(tester.getRect(find.byKey(_bodyKey)), beforeHover);
                fixture.controller.select(null);
                await mouse.moveTo(tester.getCenter(find.byKey(_toolbarKey)));
                await tester.pumpAndSettle();

                // A successful pointer action must reach the calendar rather
                // than Configure/More (the wide screenshot's original fault).
                await tester.tap(
                  _navigation(LocaleKeys.calendarView_next.tr()),
                  kind: PointerDeviceKind.mouse,
                );
                await tester.pumpAndSettle();
                expect(_reading(tester).selectedDay, DateTime(2026, 9, 14));
                expect(fixture.controller.configuringWidgetId, isNull);
                expect(find.byType(AppMenuSurface), findsNothing);
                await tester.tap(
                  _navigation(LocaleKeys.calendarView_previous.tr()),
                  kind: PointerDeviceKind.mouse,
                );
                await tester.pumpAndSettle();
                expect(_reading(tester).selectedDay, _today);
                await tester.tap(
                  _navigation(LocaleKeys.calendarView_today.tr()),
                  kind: PointerDeviceKind.mouse,
                );
                await tester.pumpAndSettle();
                expect(_reading(tester).selectedDay, _today);
                expect(tester.takeException(), isNull);
              }
            }
            // Existing titled dashboards share the same management slot, and
            // their title must grow vertically with the ambient text scale.
            fixture.controller.edit(
              (document) => document.withWidget(
                document.widgetById(_id)!.copyWith(showTitle: true),
              ),
            );
            await tester.pumpWidget(
              calendarTestApp(
                _card(fixture.controller),
                size: const Size(240, 520),
                appearance: appearance,
                textScale: textScale,
                accessibleNavigation: false,
              ),
            );
            await tester.pumpAndSettle();
            await mouse.moveTo(tester.getCenter(find.byKey(_toolbarKey)));
            await tester.pumpAndSettle();
            _expectGeometry(tester, width: 240, database: type == 'database');
            // A long title scrolls inside its header instead of ellipsizing,
            // so Find can still reveal any of it. What is visible, and the
            // line itself, stay inside the header at every text scale.
            final headerRect = tester.getRect(find.byKey(_headerKey));
            final titleRect = tester.getRect(find.text('Calendar title'));
            _inside(
              tester.getRect(
                find
                    .ancestor(
                      of: find.text('Calendar title'),
                      matching: find.byType(SingleChildScrollView),
                    )
                    .first,
              ),
              headerRect,
            );
            expect(titleRect.left, greaterThanOrEqualTo(headerRect.left));
            expect(titleRect.top, greaterThanOrEqualTo(headerRect.top - 0.01));
            expect(
              titleRect.bottom,
              lessThanOrEqualTo(headerRect.bottom + 0.01),
            );
            expect(tester.state(find.byType(CalendarShell)), same(shell));
            expect(
              tester.state(find.byType(CalendarMonthAgendaView)),
              same(reading),
            );
            expect(tester.takeException(), isNull);
            final palette =
                DashboardPalette.of(tester.element(find.byKey(_cardKey)));
            final surface = tester.widget<AnimatedContainer>(
              find
                  .descendant(
                    of: find.byKey(_cardKey),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            );
            expect(
              (surface.decoration! as BoxDecoration).color,
              palette.surface,
            );
            expect(
              tester
                  .widget<DashboardIconButton>(
                    find
                        .descendant(
                          of: find.byKey(_managementKey),
                          matching: find.byType(DashboardIconButton),
                        )
                        .first,
                  )
                  .palette,
              palette,
            );
            if (appearance == 'paper') {
              expect(palette.isPaper, isTrue);
              expect(palette.surface.r, greaterThan(palette.surface.b));
            }
            expect(fixture.tableWrites, 0);
            if (type == 'database') {
              expect(fixture.horizontalPadding, 0);
            }
          } finally {
            await mouse.removePointer();
            await tester.pumpWidget(const SizedBox());
            fixture.dispose();
          }
        });
      }
    }

    testWidgets(
        '$type: hover, native Tab focus and selection reveal management without moving content',
        (tester) async {
      _screen(tester);
      final semantics = tester.ensureSemantics();
      final fixture = _CalendarCardFixture(type);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(2, 2));
      try {
        await mountCalendarTest(
          tester,
          _card(fixture.controller),
          size: const Size(960, 520),
          appearance: 'paper',
          textScale: 2,
          accessibleNavigation: false,
        );
        final body = tester.getRect(find.byKey(_bodyKey));
        final shell = tester.state(find.byType(CalendarShell));
        _managementVisible(tester, false);
        await mouse.moveTo(tester.getCenter(find.byKey(_toolbarKey)));
        await tester.pumpAndSettle();
        _managementVisible(tester, true);
        _expectGeometry(tester, width: 960, database: type == 'database');
        await mouse.moveTo(const Offset(2, 2));
        await tester.pumpAndSettle();
        _managementVisible(tester, false);

        // Hidden actions retain native Tab order; no direct callback/focus
        // injection or accessibleNavigation override makes this test pass.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        _managementVisible(tester, true);
        final configureNode = tester.getSemantics(_configure());
        expect(configureNode.attached, isTrue);
        final configureData = configureNode.getSemanticsData();
        expect(configureData.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(configureData.hasFlag(ui.SemanticsFlag.isFocused), isTrue);
        expect(configureData.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(configureData.tooltip, LocaleKeys.dashboard_card_configure.tr());
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(fixture.controller.configuringWidgetId, _id);
        expect(tester.getRect(find.byKey(_bodyKey)), body);

        fixture.controller.closeSettings();
        fixture.controller.select(null);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        _managementVisible(tester, false);
        fixture.controller.select(_id);
        await tester.pumpAndSettle();
        _managementVisible(tester, true);
        expect(tester.getRect(find.byKey(_bodyKey)), body);
        final moreData = tester.getSemantics(_more()).getSemanticsData();
        expect(moreData.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(moreData.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(moreData.tooltip, LocaleKeys.dashboard_card_more.tr());
        await tester.tap(_more(), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        expect(
          find.widgetWithText(
            AppMenuRow,
            LocaleKeys.dashboard_card_configure.tr(),
          ),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsNothing);
        expect(tester.state(find.byType(CalendarShell)), same(shell));
        expect(tester.getRect(find.byKey(_bodyKey)), body);
        fixture.controller.setReadOnly(true);
        await tester.pumpAndSettle();
        expect(find.byKey(_managementKey), findsNothing);
        expect(tester.state(find.byType(CalendarShell)), same(shell));
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        fixture.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
        '$type: chrome transitions retain selected date, keys, controllers and live events',
        (tester) async {
      _screen(tester);
      final events = [
        for (var i = 0; i < 40; i++)
          calendarFixtureEvent(
            'retained-event-$i',
            DateTime(2026, 9, 18, 9, i),
          ),
      ];
      final fixture = _CalendarCardFixture(type, events: events);
      final controller = fixture.controller;
      try {
        await mountCalendarTest(
          tester,
          _card(controller),
          size: const Size(960, 520),
        );
        await tester.tap(_navigation(LocaleKeys.calendarView_next.tr()));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('calendar-day-2026-9-18')));
        await tester.pumpAndSettle();
        final selected = DateTime(2026, 9, 18);
        expect(_reading(tester).selectedDay, selected);
        final cardState = tester.state(find.byKey(_cardKey));
        final shellState = tester.state(find.byType(CalendarShell));
        final shellKey =
            tester.widget<CalendarShell>(find.byType(CalendarShell)).key;
        final readingState = tester.state(find.byType(CalendarMonthAgendaView));
        final bodyElement = tester.element(find.byKey(_bodyKey));
        final renderer = type == 'calendar'
            ? find.byType(DashboardCalendar)
            : find.byType(DashboardDatabaseCalendarScope);
        final rendererElement = tester.element(renderer);
        final rendererKey = rendererElement.widget.key;
        final agenda =
            tester.widget<ListView>(find.byKey(_agendaKey)).controller!;
        final outer = tester
            .widget<SingleChildScrollView>(find.byKey(_outerKey))
            .controller!;
        final focus =
            tester.widget<Focus>(find.byKey(_gridFocusKey)).focusNode!;
        agenda.jumpTo(120);
        await tester.pump();
        final windows = List.of(fixture.provider.windows);

        void expectRetained() {
          expect(tester.state(find.byKey(_cardKey)), same(cardState));
          expect(tester.element(find.byKey(_bodyKey)), same(bodyElement));
          expect(tester.element(renderer), same(rendererElement));
          expect(tester.element(renderer).widget.key, rendererKey);
          expect(tester.state(find.byType(CalendarShell)), same(shellState));
          final shell =
              tester.widget<CalendarShell>(find.byType(CalendarShell));
          expect(shell.key, shellKey);
          expect(shell.workspace, same(fixture.workspace));
          expect(
            tester.state(find.byType(CalendarMonthAgendaView)),
            same(readingState),
          );
          expect(_reading(tester).selectedDay, selected);
          expect(_reading(tester).month, selected);
          expect(
            tester.widget<ListView>(find.byKey(_agendaKey)).controller,
            same(agenda),
          );
          expect(
            tester
                .widget<SingleChildScrollView>(find.byKey(_outerKey))
                .controller,
            same(outer),
          );
          expect(
            tester.widget<Focus>(find.byKey(_gridFocusKey)).focusNode,
            same(focus),
          );
          expect(agenda.hasClients, isTrue);
          expect(agenda.offset, 120);
          expect(fixture.provider.windows, windows);
          expect(fixture.provider.disposed, isFalse);
          expect(fixture.tableWrites, 0);
          expect(tester.takeException(), isNull);
        }

        for (final appearance in ['paper', 'dark', 'light']) {
          for (final width in _widths) {
            await tester.pumpWidget(
              calendarTestApp(
                _card(controller),
                size: Size(width, 520),
                appearance: appearance,
                textScale: width < 680 ? 2 : 1,
              ),
            );
            await tester.pumpAndSettle();
            expectRetained();
          }
        }
        for (final change in <VoidCallback>[
          () => controller.configure(_id),
          controller.closeSettings,
          () => controller.setMode(DashboardMode.presentation),
          () => controller.setMode(DashboardMode.edit),
          () => controller.setReadOnly(true),
          () => controller.setReadOnly(false),
          () => controller.edit(
                (document) => document.withWidget(
                  document.widgetById(_id)!.copyWith(showTitle: true),
                ),
              ),
          () => controller.edit(
                (document) => document.withWidget(
                  document.widgetById(_id)!.copyWith(showTitle: false),
                ),
              ),
        ]) {
          change();
          await tester.pumpAndSettle();
          expectRetained();
          expect(
            find.byKey(_managementKey),
            controller.isEditable ? findsOneWidget : findsNothing,
          );
        }

        await tester.tap(find.byKey(const ValueKey('calendar-mode-menu')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            AppMenuRow,
            calendarViewModeLabel(CalendarViewMode.monthAgenda),
          ),
        );
        await tester.pumpAndSettle();
        expectRetained();
        expect(_reading(tester).sideBySide, isFalse);
        expect(
          controller.document.widgetById(_id)!.setting(_modeKey(type)),
          'monthAgenda',
        );
        expect(
          controller.document.widgetById(_id)!.setting('unrelated_setting'),
          'keep',
        );
        expect(fixture.table.extra, fixture.tableExtra);
        expect(
          fixture.tableSettings.listenable(fixture.table).value,
          CalendarViewMode.month,
        );

        fixture.provider.publish([
          ...events,
          calendarFixtureEvent('live-provider-event', DateTime(2026, 9, 18, 8)),
        ]);
        agenda.jumpTo(0);
        await tester.pumpAndSettle();
        final event = find.descendant(
          of: find.byKey(
            const ValueKey('calendar-agenda-event-live-provider-event'),
          ),
          matching: find.byType(TextButton),
        );
        expect(event.hitTestable(), findsOneWidget);
        await tester.tap(event);
        expect(fixture.openedEvents.single.id, 'live-provider-event');
        expect(_reading(tester).selectedDay, selected);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        expect(
          fixture.provider.disposed,
          isFalse,
          reason: 'Borrowed calendar sources stay owned by their host.',
        );
        fixture.dispose();
      }
    });
  }

  // Keep the existing compact/2x behavior cases above unchanged. The main
  // runner generates and reviews these six full-card references separately.
  group('golden dashboard calendar chrome', () {
    const reference = ValueKey('dashboard-calendar-chrome-golden');
    const size = Size(960, 520);

    setUpAll(() async {
      // initializeCalendarTests disables fetching but does not load fonts.
      // These are the actual local families used by the desktop theme, not
      // aliases that substitute a different face or depend on system fonts.
      for (final (family, asset) in const [
        ('DM Sans', 'assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
        ('Inter', 'assets/google_fonts/Inter/Inter-Variable.ttf'),
        ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      ]) {
        await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
      }
    });

    for (final type in ['calendar', 'database']) {
      for (final appearance in ['light', 'dark', 'paper']) {
        testWidgets('$type $appearance 960x520', (tester) async {
          _screen(tester);
          final semantics = tester.ensureSemantics();
          final fixture = _CalendarCardFixture(type);
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          try {
            await mouse.addPointer(location: const Offset(2, 2));
            await mountCalendarTest(
              tester,
              Builder(
                builder: (context) => RepaintBoundary(
                  key: reference,
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: _card(fixture.controller),
                  ),
                ),
              ),
              size: size,
              appearance: appearance,
              accessibleNavigation: false,
            );
            _managementVisible(tester, false);
            final body = tester.getRect(find.byKey(_bodyKey));
            await mouse.moveTo(tester.getCenter(find.byKey(_toolbarKey)));
            await tester.pumpAndSettle();
            await settleVividIconPictures(tester);

            _managementVisible(tester, true);
            _expectGeometry(tester, width: 960, database: type == 'database');
            expect(tester.getRect(find.byKey(_bodyKey)), body);
            expect(tester.getSize(find.byKey(reference)), size);
            expect(_reading(tester).selectedDay, _today);
            for (final button in [
              _configure(),
              _more(),
              _navigation(LocaleKeys.calendarView_previous.tr()),
              _navigation(LocaleKeys.calendarView_today.tr()),
              _navigation(LocaleKeys.calendarView_next.tr()),
            ]) {
              final node = tester.getSemantics(button);
              expect(node.attached, isTrue);
              final data = node.getSemanticsData();
              expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
              expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
            }
            expect(tester.takeException(), isNull);
            // Capture while the real pointer still reveals management and
            // native date navigation; do not move it away before comparison.
            await expectLater(
              find.byKey(reference),
              matchesGoldenFile(
                'goldens/dashboard_calendar_chrome/${type}_$appearance.png',
              ),
            );
          } finally {
            await mouse.removePointer();
            await tester.pumpWidget(const SizedBox());
            fixture.dispose();
            semantics.dispose();
          }
        });
      }
    }
  });
}

/// Uses the production definitions, real card, standalone calendar and database
/// presentation scope. Only service/native startup is replaced. The database
/// keeps its real tab-header geometry and tab button above a real CalendarShell;
/// its settings action is an offline native button, not CalendarSettingBar.
/// DatabaseTabBarView/CalendarStage/FFI and remote providers are not started here.
class _CalendarCardFixture {
  _CalendarCardFixture(this.type, {List<CalendarEvent>? events}) {
    original = DashboardWidgetRegistry.definitionFor(type)!;
    provider = CalendarFixtureProvider(
      events: events ?? [calendarFixtureEvent('calendar-event', _today)],
    );
    workspace = CalendarWorkspace(providers: [provider]);
    tableSettings = CalendarViewSettings(
      readExtra: (_) async => tableExtra,
      writeExtra: (_, __) async {
        tableWrites++;
      },
    );
    final spec = original.create().copyWith(
      id: _id,
      title: 'Calendar title',
      showTitle: false,
      source: type == 'database'
          ? DashboardDataSource(
              kind: DashboardSourceKind.database,
              viewId: table.id,
              name: table.name,
            )
          : DashboardDataSource.none,
      settings: {
        _modeKey(type): CalendarViewMode.monthSplit.name,
        'unrelated_setting': 'keep',
      },
    );
    controller = DashboardController(
      // The production controller never persists an empty view identity.
      viewId: '',
      persistDebounce: const Duration(days: 1),
      mode: DashboardMode.edit,
      document: DashboardDocument(
        settings: const DashboardSettings(reduceMotion: true),
        sections: [
          DashboardSection(id: 'issue5-section', widgets: [spec]),
        ],
      ),
    );
    DashboardWidgetRegistry.register(
      DashboardWidgetDefinition(
        type: original.type,
        label: original.label,
        icon: original.icon,
        group: original.group,
        padding: original.padding,
        headerTrailing: original.headerTrailing,
        paintsOwnSurface: original.paintsOwnSurface,
        requiresScrollActivation: original.requiresScrollActivation,
        surface: original.surface,
        identity: original.identity,
        reservesHeader: original.reservesHeader,
        controlsAtStart: original.controlsAtStart,
        configure: original.configure,
        builder: _build,
      ),
    );
  }

  final String type;
  final tableExtra = const CalendarViewSetting(CalendarViewMode.month)
      .mergeIntoExtra('{"unrelated_table_setting":"keep"}');
  late final table = ViewPB(
    id: 'issue5-table',
    name: 'Calendar',
    layout: ViewLayoutPB.Calendar,
    extra: tableExtra,
  );
  late final DashboardWidgetDefinition original;
  late final CalendarFixtureProvider provider;
  late final CalendarWorkspace workspace;
  late final CalendarViewSettings tableSettings;
  late final DashboardController controller;
  final openedEvents = <CalendarEvent>[];
  int tableWrites = 0;
  double? horizontalPadding;

  Widget _build(DashboardWidgetContext data) {
    final declared = original.builder(data);
    final delegate = CalendarViewDelegate(
      colorOf: workspace.colorFor,
      onOpenEvent: openedEvents.add,
    );
    if (type == 'calendar') {
      final calendar = declared as DashboardCalendar;
      return DashboardCalendar(
        key: calendar.key,
        context: calendar.context,
        workspace: workspace,
        delegate: delegate,
        initialDate: _today,
        now: () => _today,
      );
    }
    final scope = declared as DashboardDatabaseCalendarScope;
    final resolver = scope.child as DashboardViewBuilder;
    final sizeProvider = resolver.builder(data.context, table)
        as Provider<DatabasePluginWidgetBuilderSize>;
    // A Provider does not expose its child. Borrow its real sizing value via
    // MultiProvider, substituting only the native database startup below it.
    // Full DatabaseTabBarView wiring is covered by its integration suite.
    return DashboardDatabaseCalendarScope(
      key: scope.key,
      data: scope.data,
      child: MultiProvider(
        providers: [sizeProvider],
        child: PreviewToolbarRegion(
          child: Column(
            key: const ValueKey('issue5-database-frame'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Builder(
                builder: (context) {
                  horizontalPadding = context
                      .read<DatabasePluginWidgetBuilderSize>()
                      .horizontalPadding;
                  final tabWidth =
                      DatabaseViewTabMetrics.widthFor(context, table);
                  return DatabaseTabHeaderLayout(
                    viewCount: 1,
                    naturalTabsWidth:
                        tabWidth + DatabaseViewTabMetrics.addWidth,
                    tabs: Wrap(
                      children: [
                        DatabaseTabBarItem(
                          key: ValueKey(table.id),
                          view: table,
                          width: tabWidth,
                          isSelected: true,
                          onTap: (_) {},
                        ),
                      ],
                    ),
                    settings: PreviewToolbar(
                      child: CalendarControlButton(
                        key: _databaseSettingsKey,
                        icon: Icons.filter_list_rounded,
                        tooltip: 'Database settings',
                        onPressed: () {},
                      ),
                    ),
                  );
                },
              ),
              Expanded(
                child: ValueListenableBuilder<CalendarViewMode?>(
                  valueListenable: tableSettings.listenable(table),
                  builder: (context, saved, _) => CalendarShell(
                    key: const ValueKey('issue5-database-calendar'),
                    workspace: workspace,
                    initialMode: saved ?? CalendarViewMode.month,
                    mode: saved ?? CalendarViewMode.month,
                    onModeChanged: (mode) =>
                        unawaited(tableSettings.set(table, mode)),
                    initialDate: _today,
                    now: () => _today,
                    delegate: delegate,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void dispose() {
    controller.dispose();
    workspace.dispose();
    tableSettings.reset();
    DashboardWidgetRegistry.register(original);
  }
}
