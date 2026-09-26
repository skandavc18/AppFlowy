import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_event_details.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_agenda_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_support.dart';

const _modes = [CalendarViewMode.monthAgenda, CalendarViewMode.monthSplit];
const _agendaKey = PageStorageKey('calendar-day-agenda-scroll');
const _outerKey = PageStorageKey('calendar-month-agenda-outer');
const _frameKey = ValueKey('calendar-test-frame');
const _layoutKey = ValueKey('calendar-month-agenda-layout');

Finder _day(DateTime day) =>
    find.byKey(ValueKey('calendar-day-${day.year}-${day.month}-${day.day}'));
Finder _event(String id, {bool skipOffstage = true}) => find.byKey(
      ValueKey('calendar-agenda-event-$id'),
      skipOffstage: skipOffstage,
    );

CalendarMonthAgendaView _reading(WidgetTester tester) => tester
    .widget<CalendarMonthAgendaView>(find.byType(CalendarMonthAgendaView));

void _expectCalendarHitTarget(
  WidgetTester tester,
  Finder target, {
  bool inAgenda = false,
}) {
  var visible = tester.getRect(find.byKey(_frameKey));
  if (inAgenda) {
    visible = visible
        .intersect(tester.getRect(find.byKey(_outerKey)))
        .intersect(tester.getRect(find.byKey(_agendaKey)));
  }
  final rect = tester.getRect(target);
  expect(rect.isEmpty, isFalse);
  expect(
    visible.inflate(0.01).contains(rect.topLeft),
    isTrue,
    reason:
        '$target must start inside the calendar viewport, not just the app.',
  );
  expect(
    visible.inflate(0.01).contains(rect.bottomRight),
    isTrue,
    reason: '$target must end inside the calendar viewport, not just the app.',
  );
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _revealCalendarHitTarget(
  WidgetTester tester,
  Finder target, {
  bool inAgenda = false,
}) async {
  // These small fixtures are already mounted in the sliver cache. Revealing
  // them changes the offsets immediately, but hit geometry needs a new frame.
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  _expectCalendarHitTarget(tester, target, inAgenda: inAgenda);
}

void main() {
  setUpAll(initializeCalendarTests);

  for (final mode in _modes) {
    for (final appearance in ['light', 'dark', 'paper']) {
      for (final scale in [1.0, 2.0]) {
        for (final rtl in [false, true]) {
          for (final month in [DateTime(2026, 9), DateTime(2026, 8)]) {
            for (final size in [
              const Size(400, 300),
              const Size(680, 320),
              const Size(240, 300),
            ]) {
              testWidgets(
                  '${mode.name} $appearance scale=$scale rtl=$rtl month=${month.month} $size',
                  (tester) async {
                final selected = DateTime(month.year, month.month, 14);
                final entry = calendarFixtureEvent(
                  'range',
                  selected,
                  end: calendarDayOffset(selected, 2),
                  allDay: true,
                );
                final provider = CalendarFixtureProvider(events: [entry]);
                final workspace = CalendarWorkspace(providers: [provider]);
                try {
                  await mountCalendarTest(
                    tester,
                    CalendarShell(
                      workspace: workspace,
                      initialMode: mode,
                      initialDate: selected,
                      now: () => selected,
                      showWeekNumbers: true,
                      quiet: true,
                      delegate: CalendarViewDelegate(
                        colorOf: workspace.colorFor,
                        canEdit: false,
                      ),
                    ),
                    appearance: appearance,
                    size: size,
                    textScale: scale,
                    rtl: rtl,
                  );
                  expect(tester.takeException(), isNull);
                  expect(_reading(tester).events.single, same(entry));
                  final days = monthGridDays(month);
                  final rows = days.length ~/ 7;
                  for (var row = 0; row < rows; row++) {
                    expect(
                      find.byKey(ValueKey('calendar-compact-week-$row')),
                      findsOneWidget,
                    );
                  }
                  expect(
                    _day(days.last),
                    findsOneWidget,
                    reason: 'The sixth week must not be omitted.',
                  );
                  final grid = tester.getRect(
                    find.byKey(const ValueKey('calendar-compact-month-grid')),
                  );
                  final last = tester.getRect(_day(days.last));
                  expect(last.bottom, lessThanOrEqualTo(grid.bottom + 0.01));
                  final beside =
                      mode == CalendarViewMode.monthSplit && size.width == 680;
                  expect(
                    tester.widget<Flex>(find.byKey(_layoutKey)).direction,
                    beside ? Axis.horizontal : Axis.vertical,
                  );
                  final agenda = tester.getRect(
                    find.byKey(const ValueKey('calendar-day-agenda')),
                  );
                  if (beside) {
                    expect(agenda.top, closeTo(grid.top, 0.01));
                    expect(
                      rtl ? agenda.right < grid.left : agenda.left > grid.right,
                      isTrue,
                    );
                  } else {
                    expect(agenda.top, greaterThan(grid.bottom));
                  }
                  final context =
                      tester.element(find.byType(CalendarMonthAgendaView));
                  expect(PaperTheme.isEnabled(context), appearance == 'paper');
                  expect(
                    calendarPaletteOf(context).isDark,
                    appearance == 'dark',
                  );
                  if (appearance == 'paper') {
                    final surface = calendarPaletteOf(context).surface;
                    expect(surface.r, greaterThan(surface.b));
                  }
                  await tester.ensureVisible(_day(days.last));
                  await tester.pumpAndSettle();
                  await tester.tap(_day(days.last));
                  await tester.pumpAndSettle();
                  expect(_reading(tester).selectedDay, days.last);
                  expect(tester.takeException(), isNull);
                } finally {
                  await tester.pumpWidget(const SizedBox());
                  workspace.dispose();
                }
              });
            }
          }
        }
      }
    }

    for (final (appearance, size, month) in [
      ('light', const Size(680, 320), 9),
      for (final appearance in ['light', 'dark', 'paper'])
        (appearance, const Size(400, 300), 8),
    ]) {
      testWidgets(
          month == 9
              ? '${mode.name}: dates only select; real events open/menu/add/complete through delegates'
              : '${mode.name} $appearance: six-week 400x300 agenda actions hit the actual viewport',
          (tester) async {
        final selected = DateTime(2026, month, 14);
        final allDay = calendarFixtureEvent('all day', selected, allDay: true);
        final timed = calendarFixtureEvent(
          'meeting',
          DateTime(2026, month, 14, 9, 15),
          end: DateTime(2026, month, 14, 10, 45),
          kind: CalendarEventKind.reminder,
        );
        final tomorrow = calendarFixtureEvent(
          'tomorrow event',
          DateTime(2026, month, 15, 11),
        );
        final provider =
            CalendarFixtureProvider(events: [tomorrow, timed, allDay]);
        final workspace = CalendarWorkspace(providers: [provider]);
        final opens = <CalendarEvent>[];
        final menus = <CalendarEvent>[];
        final completions = <CalendarEvent>[];
        final creates = <(DateTime, bool)>[];
        final dayMenus = <DateTime>[];
        final semantics = tester.ensureSemantics();
        try {
          await mountCalendarTest(
            tester,
            CalendarShell(
              workspace: workspace,
              initialMode: mode,
              initialDate: selected,
              now: () => selected,
              quiet: true,
              delegate: CalendarViewDelegate(
                colorOf: workspace.colorFor,
                onOpenEvent: opens.add,
                onEventMenu: (event, _) => menus.add(event),
                onDayMenu: (day, _) => dayMenus.add(day),
                onCreateAt: (at, {bool hasTime = false}) =>
                    creates.add((at, hasTime)),
                onToggleComplete: completions.add,
              ),
            ),
            appearance: appearance,
            size: size,
          );
          expect(tester.getSize(find.byKey(_frameKey)), size);
          _expectCalendarHitTarget(tester, _day(selected));
          await tester.tap(_day(selected));
          await tester.pumpAndSettle();
          expect(creates, isEmpty);
          final dayNode = tester.getSemantics(_day(selected));
          expect(dayNode.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(dayNode.hasFlag(ui.SemanticsFlag.isSelected), isTrue);
          expect(
            dayNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          expect(
            find.byKey(ValueKey('calendar-day-dots-2026-$month-14')),
            findsOneWidget,
          );
          expect(find.text('09:15–10:45', skipOffstage: false), findsOneWidget);
          expect(
            tester.getTopLeft(_event(allDay.id, skipOffstage: false)).dy,
            lessThan(
              tester.getTopLeft(_event(timed.id, skipOffstage: false)).dy,
            ),
          );
          final list =
              tester.widget<ListView>(find.byKey(_agendaKey)).controller!;
          final outer = tester
              .widget<SingleChildScrollView>(find.byKey(_outerKey))
              .controller!;
          if (month == 8) {
            expect(
              find.byKey(const ValueKey('calendar-compact-week-5')),
              findsOneWidget,
            );
            expect(
              list.position.viewportDimension,
              lessThan(
                tester.getSize(_event(allDay.id, skipOffstage: false)).height +
                    tester
                        .getSize(_event(timed.id, skipOffstage: false))
                        .height,
              ),
            );
            expect(outer.position.maxScrollExtent, greaterThan(0));
            expect(
              tester.getCenter(_event(timed.id, skipOffstage: false)).dy,
              greaterThan(tester.getRect(find.byKey(_frameKey)).bottom),
            );
            expect(
              _event(timed.id, skipOffstage: false).hitTestable(),
              findsNothing,
            );
          }
          await _revealCalendarHitTarget(
            tester,
            _event(timed.id, skipOffstage: false),
            inAgenda: true,
          );
          if (month == 8) {
            expect(list.offset, greaterThan(0));
            expect(outer.offset, greaterThan(0));
          }
          expect(find.text('09:15–10:45'), findsOneWidget);
          await tester.tap(_event(timed.id));
          await tester.pump();
          expect(opens.single, same(timed));
          _expectCalendarHitTarget(tester, _event(timed.id), inAgenda: true);
          final secondary = await tester.startGesture(
            tester.getCenter(_event(timed.id)),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await secondary.up();
          await tester.pump();
          expect(menus.single, same(timed));
          final complete =
              find.byKey(ValueKey('calendar-agenda-complete-${timed.id}'));
          await _revealCalendarHitTarget(tester, complete, inAgenda: true);
          await tester.tap(complete);
          await tester.pump();
          expect(completions.single, same(timed));
          final add = find.byKey(const ValueKey('calendar-agenda-add'));
          await _revealCalendarHitTarget(tester, add);
          await tester.tap(add);
          expect(creates.single, (selected, false));
          await _revealCalendarHitTarget(tester, _day(selected));
          final rightDay = await tester.startGesture(
            tester.getCenter(_day(selected)),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await rightDay.up();
          await tester.pump();
          expect(dayMenus.single, selected);
          await _revealCalendarHitTarget(
            tester,
            _event(tomorrow.id, skipOffstage: false),
            inAgenda: true,
          );
          await tester.tap(_event(tomorrow.id));
          expect(opens, hasLength(2));
          expect(opens.last, same(tomorrow));
          expect(provider.windows, hasLength(1));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          workspace.dispose();
          semantics.dispose();
        }
      });
    }

    testWidgets(
        '${mode.name}: live provider updates and workspace filters drive dots and day lists',
        (tester) async {
      final day = DateTime(2026, 8, 14);
      final before = calendarFixtureEvent(
        'live',
        DateTime(2026, 8, 14, 9),
        title: 'Before',
      );
      final later = calendarFixtureEvent('later', DateTime(2026, 8, 14, 10));
      final provider = CalendarFixtureProvider(events: [before, later]);
      final workspace = CalendarWorkspace(providers: [provider]);
      final opens = <CalendarEvent>[];
      try {
        await mountCalendarTest(
          tester,
          CalendarShell(
            workspace: workspace,
            initialMode: mode,
            initialDate: day,
            quiet: true,
            delegate: CalendarViewDelegate(
              colorOf: workspace.colorFor,
              onOpenEvent: opens.add,
            ),
          ),
        );
        await _revealCalendarHitTarget(
          tester,
          _event(before.id, skipOffstage: false),
          inAgenda: true,
        );
        final state = tester.state(find.byType(CalendarMonthAgendaView));
        final eventElement = tester.element(_event(before.id));
        final buttonState =
            tester.state(find.widgetWithText(TextButton, 'Before'));
        final focus = Focus.of(tester.element(find.text('Before')));
        focus.requestFocus();
        await tester.pump();
        expect(focus.hasPrimaryFocus, isTrue);
        final after = before.copyWith(
          title: 'After',
          start: ZonedDateTime.local(DateTime(2026, 8, 14, 13, 30)),
        );
        provider.publish([later, after]);
        await tester.pump();
        // Reordering moves the focused row below a one-row compact viewport.
        // Check retention BEFORE scrolling, without treating a cached element
        // as visible or re-requesting focus on a potentially new button.
        final retainedEvent = _event(after.id, skipOffstage: false);
        expect(find.text('Before', skipOffstage: false), findsNothing);
        expect(tester.element(retainedEvent), same(eventElement));
        expect(buttonState.mounted, isTrue);
        expect(
          tester.state(
            find.widgetWithText(TextButton, 'After', skipOffstage: false),
          ),
          same(buttonState),
        );
        expect(
          Focus.of(tester.element(find.text('After', skipOffstage: false))),
          same(focus),
        );
        expect(focus.hasPrimaryFocus, isTrue);
        expect(
          tester
              .widget<ListView>(find.byKey(_agendaKey))
              .childrenDelegate
              .findIndexByKey(ValueKey('calendar-agenda-event-${after.id}')),
          1,
        );
        await _revealCalendarHitTarget(tester, retainedEvent, inAgenda: true);
        expect(find.text('After'), findsOneWidget);
        expect(find.text('13:30'), findsOneWidget);
        expect(tester.state(find.byType(CalendarMonthAgendaView)), same(state));
        expect(
          tester.state(find.widgetWithText(TextButton, 'After')),
          same(buttonState),
        );
        expect(focus.hasFocus, isTrue);
        expect(_reading(tester).selectedDay, day);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(opens.single, same(after));
        workspace.setFilter(const CalendarFilter(query: 'no match'));
        await tester.pump();
        expect(find.text('After', skipOffstage: false), findsNothing);
        expect(
          find.byKey(const ValueKey('calendar-day-dots-2026-8-14')),
          findsNothing,
        );
        expect(
          find.text('calendarView.empty.selectedDay'.tr()),
          findsOneWidget,
        );
        workspace.setFilter(const CalendarFilter());
        await tester.pump();
        await _revealCalendarHitTarget(
          tester,
          _event(after.id, skipOffstage: false),
          inAgenda: true,
        );
        expect(find.text('After'), findsOneWidget);
        expect(
          provider.windows,
          hasLength(1),
          reason: 'Filtering does not reload a provider.',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
      }
    });
  }

  for (final initial in CalendarViewMode.values) {
    testWidgets('${initial.name}: the actual chooser exposes all seven modes',
        (tester) async {
      final workspace =
          CalendarWorkspace(providers: [CalendarFixtureProvider()]);
      final changes = <CalendarViewMode>[];
      try {
        await mountCalendarTest(
          tester,
          CalendarShell(
            workspace: workspace,
            initialMode: initial,
            initialDate: DateTime(2026, 9, 14),
            quiet: true,
            onModeChanged: changes.add,
            delegate: CalendarViewDelegate(
              colorOf: workspace.colorFor,
              canEdit: false,
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('calendar-mode-menu')));
        await tester.pumpAndSettle();
        for (final mode in CalendarViewMode.values) {
          expect(
            find
                .widgetWithText(AppMenuRow, calendarViewModeLabel(mode))
                .hitTestable(),
            findsOneWidget,
          );
        }
        final next = initial == CalendarViewMode.monthAgenda
            ? CalendarViewMode.monthSplit
            : CalendarViewMode.monthAgenda;
        await tester
            .tap(find.widgetWithText(AppMenuRow, calendarViewModeLabel(next)));
        await tester.pumpAndSettle();
        expect(changes.single, next);
        expect(
          _reading(tester).sideBySide,
          next == CalendarViewMode.monthSplit,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
      }
    });
  }

  for (final rtl in [false, true]) {
    testWidgets(
        'keyboard dates rtl=$rtl cross months; PageDown clamps; Today selects today',
        (tester) async {
      final workspace =
          CalendarWorkspace(providers: [CalendarFixtureProvider()]);
      final today = DateTime(2027, 5, 17);
      try {
        await mountCalendarTest(
          tester,
          CalendarShell(
            workspace: workspace,
            initialMode: CalendarViewMode.monthSplit,
            initialDate: DateTime(2027, 1, 31),
            now: () => today,
            quiet: true,
            delegate: CalendarViewDelegate(
              colorOf: workspace.colorFor,
              canEdit: false,
            ),
          ),
          rtl: rtl,
        );
        await tester.tap(_day(DateTime(2027, 1, 31)));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
        expect(_reading(tester).selectedDay, DateTime(2027, 2, 28));
        await tester.sendKeyEvent(
          rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight,
        );
        await tester.pumpAndSettle();
        expect(_reading(tester).selectedDay, DateTime(2027, 3));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(_reading(tester).selectedDay, DateTime(2027, 3, 8));
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        expect(_reading(tester).selectedDay.weekday, DateTime.sunday);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        expect(_reading(tester).selectedDay, DateTime(2027, 3, 8));
        await tester.tap(find.byKey(const ValueKey('calendar-go-today')));
        await tester.pumpAndSettle();
        expect(_reading(tester).selectedDay, today);
        await tester.tap(find.byTooltip(LocaleKeys.calendarView_next.tr()));
        await tester.pumpAndSettle();
        expect(_reading(tester).selectedDay, DateTime(2027, 6, 17));
        await tester.tap(find.byTooltip(LocaleKeys.calendarView_previous.tr()));
        await tester.pumpAndSettle();
        expect(_reading(tester).selectedDay, today);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
      }
    });
  }

  testWidgets(
      'hidden weekends and Sunday-first keep visible keyboard selection',
      (tester) async {
    final workspace = CalendarWorkspace(providers: [CalendarFixtureProvider()]);
    try {
      await mountCalendarTest(
        tester,
        CalendarShell(
          workspace: workspace,
          initialMode: CalendarViewMode.monthAgenda,
          initialDate: DateTime(2026, 9, 18),
          firstDayOfWeek: DateTime.sunday,
          showWeekends: false,
          quiet: true,
          delegate: CalendarViewDelegate(
            colorOf: workspace.colorFor,
            canEdit: false,
          ),
        ),
      );
      expect(_day(DateTime(2026, 9, 19)), findsNothing);
      await tester.tap(_day(DateTime(2026, 9, 18)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_reading(tester).selectedDay, DateTime(2026, 9, 21));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(_reading(tester).selectedDay, DateTime(2026, 9, 25));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(_reading(tester).selectedDay, DateTime(2026, 9, 21));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  testWidgets(
      'per-event permission and read-only delegates suppress writes, not selection/open/menu',
      (tester) async {
    final day = DateTime(2026, 9, 14);
    final entry = calendarFixtureEvent(
      'readonly',
      day,
      kind: CalendarEventKind.reminder,
      readOnly: true,
    );
    final provider = CalendarFixtureProvider(events: [entry]);
    final workspace = CalendarWorkspace(providers: [provider]);
    var opened = 0;
    var writes = 0;
    try {
      for (final canEdit in [false, true]) {
        await mountCalendarTest(
          tester,
          CalendarShell(
            workspace: workspace,
            initialMode: CalendarViewMode.monthSplit,
            initialDate: day,
            quiet: true,
            delegate: CalendarViewDelegate(
              colorOf: workspace.colorFor,
              canEdit: canEdit,
              canEditEvent: (_) => false,
              onOpenEvent: (_) => opened++,
              onCreateAt: (_, {bool hasTime = false}) => writes++,
              onToggleComplete: (_) => writes++,
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('calendar-agenda-complete-readonly')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('calendar-agenda-add')),
          canEdit ? findsOneWidget : findsNothing,
        );
        await tester.tap(_day(day));
        await tester.tap(_event(entry.id));
        await tester.pump();
        expect(writes, 0);
      }
      expect(opened, 2);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  testWidgets(
      'mode, width and theme changes retain selected date and agenda scroll state',
      (tester) async {
    final day = DateTime(2026, 8, 14);
    final provider = CalendarFixtureProvider(
      events: [
        for (var i = 0; i < 50; i++)
          calendarFixtureEvent('entry $i', DateTime(2026, 8, 14, 9, i)),
      ],
    );
    final workspace = CalendarWorkspace(providers: [provider]);
    final shell = GlobalKey<CalendarShellState>();
    var mode = CalendarViewMode.monthSplit;
    Widget calendar() => CalendarShell(
          key: shell,
          workspace: workspace,
          initialMode: mode,
          initialDate: day,
          quiet: true,
          onModeChanged: (next) => mode = next,
          delegate: CalendarViewDelegate(colorOf: workspace.colorFor),
        );
    try {
      await mountCalendarTest(tester, calendar());
      final state = tester.state(find.byType(CalendarMonthAgendaView));
      final list = tester.widget<ListView>(find.byKey(_agendaKey)).controller!;
      list.jumpTo(180);
      await tester.pump();
      shell.currentState!.setMode(CalendarViewMode.monthAgenda);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(CalendarMonthAgendaView)), same(state));
      expect(list.offset, 180);
      for (final appearance in ['paper', 'dark', 'light']) {
        await tester.pumpWidget(
          calendarTestApp(
            calendar(),
            size: const Size(240, 300),
            textScale: 2,
            appearance: appearance,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(CalendarMonthAgendaView)), same(state));
        expect(
          tester.widget<ListView>(find.byKey(_agendaKey)).controller,
          same(list),
        );
        expect(list.offset, 180);
        expect(_reading(tester).selectedDay, day);
      }
      mode = CalendarViewMode.monthSplit;
      await tester.pumpWidget(calendarTestApp(calendar()));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(CalendarMonthAgendaView)), same(state));
      expect(list.offset, 180);
      expect(provider.windows, hasLength(1));
      shell.currentState!.setMode(CalendarViewMode.agenda);
      await tester.pumpAndSettle();
      shell.currentState!.setMode(CalendarViewMode.monthSplit);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListView>(find.byKey(_agendaKey)).controller!.offset,
        180,
      );
      expect(_reading(tester).selectedDay, day);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  testWidgets(
      'active calendar search keeps its editor, caret and focus across reflow and data refresh',
      (tester) async {
    final day = DateTime(2026, 9, 14);
    final provider =
        CalendarFixtureProvider(events: [calendarFixtureEvent('meeting', day)]);
    final workspace = CalendarWorkspace(providers: [provider]);
    final shell = GlobalKey<CalendarShellState>();
    Widget calendar() => CalendarShell(
          key: shell,
          workspace: workspace,
          initialMode: CalendarViewMode.monthSplit,
          initialDate: day,
          delegate: CalendarViewDelegate(colorOf: workspace.colorFor),
        );
    try {
      await mountCalendarTest(tester, calendar());
      await tester.tap(find.byTooltip(LocaleKeys.calendarView_search.tr()));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'meeting');
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      final controller = field.controller!;
      controller.selection =
          const TextSelection(baseOffset: 2, extentOffset: 5);
      final selection = controller.selection;
      await tester.pumpWidget(
        calendarTestApp(
          calendar(),
          size: const Size(280, 300),
          textScale: 2,
          appearance: 'paper',
        ),
      );
      await tester.pumpAndSettle();
      provider.publish([calendarFixtureEvent('meeting update', day)]);
      await tester.pump();
      expect(tester.state(find.byType(EditableText)), same(editor));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller,
        same(controller),
      );
      expect(controller.text, 'meeting');
      expect(controller.selection, selection);
      expect(editor.widget.focusNode.hasFocus, isTrue);
      expect(_reading(tester).selectedDay, day);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  testWidgets(
      'rebinding adopts new events/settings and detaches the old workspace listener',
      (tester) async {
    final day = DateTime(2026, 9, 14);
    final oldProvider = CalendarFixtureProvider(
      events: [calendarFixtureEvent('old source', day)],
    );
    final newProvider = CalendarFixtureProvider(
      events: [calendarFixtureEvent('new source', day)],
    );
    final oldWorkspace = CalendarWorkspace(providers: [oldProvider]);
    final newWorkspace = CalendarWorkspace(providers: [newProvider]);
    final key = GlobalKey<CalendarShellState>();
    Widget calendar(CalendarWorkspace workspace, CalendarViewMode mode) =>
        CalendarShell(
          key: key,
          workspace: workspace,
          initialMode: mode,
          initialDate: day,
          quiet: true,
          delegate: CalendarViewDelegate(colorOf: workspace.colorFor),
        );
    try {
      await mountCalendarTest(
        tester,
        calendar(oldWorkspace, CalendarViewMode.monthAgenda),
      );
      final shell = key.currentState;
      final state = tester.state(find.byType(CalendarMonthAgendaView));
      await tester.pumpWidget(
        calendarTestApp(calendar(newWorkspace, CalendarViewMode.monthSplit)),
      );
      await tester.pumpAndSettle();
      expect(key.currentState, same(shell));
      expect(tester.state(find.byType(CalendarMonthAgendaView)), same(state));
      expect(find.text('old source'), findsNothing);
      expect(find.text('new source'), findsOneWidget);
      expect(_reading(tester).sideBySide, isTrue);
      expect(newProvider.windows, hasLength(1));
      final reading = _reading(tester);
      oldProvider.publish([calendarFixtureEvent('stale notification', day)]);
      await tester.pump();
      expect(_reading(tester), same(reading));
      expect(find.text('stale notification'), findsNothing);
      newProvider.publish([calendarFixtureEvent('new notification', day)]);
      await tester.pump();
      expect(find.text('new notification'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      oldWorkspace.dispose();
      newWorkspace.dispose();
    }
  });

  testWidgets(
      'relative labels update across midnight and reduced-motion controls do not animate',
      (tester) async {
    var now = DateTime(2026, 9, 14, 23, 59);
    final workspace = CalendarWorkspace(providers: [CalendarFixtureProvider()]);
    try {
      await mountCalendarTest(
        tester,
        CalendarShell(
          workspace: workspace,
          initialMode: CalendarViewMode.monthAgenda,
          initialDate: now,
          now: () => now,
          quiet: true,
          delegate: CalendarViewDelegate(colorOf: workspace.colorFor),
        ),
        appearance: 'paper',
        accessibleNavigation: false,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('calendar-selected-day')))
            .data,
        startsWith('Today'),
      );
      now = DateTime(2026, 9, 15);
      await tester.pump(const Duration(minutes: 1));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('calendar-selected-day')))
            .data,
        startsWith('Yesterday'),
      );
      for (final box in tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(CalendarMonthAgendaView),
          matching: find.byType(AnimatedContainer),
        ),
      )) {
        expect(box.duration, Duration.zero);
      }
      for (final opacity in tester.widgetList<AnimatedOpacity>(
        find.descendant(
          of: find.byType(PreviewToolbar),
          matching: find.byType(AnimatedOpacity),
        ),
      )) {
        expect(opacity.duration, Duration.zero);
      }
      final glyphs = tester.widgetList<WorkspaceGlyph>(
        find.descendant(
          of: find.byType(CalendarShell),
          matching: find.byType(WorkspaceGlyph),
        ),
      );
      expect(glyphs, isNotEmpty);
      expect(glyphs.map((glyph) => glyph.name), isNot(contains('unknown')));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  testWidgets(
      'keyboard event menu uses the delegate and details show real content without a composer',
      (tester) async {
    final day = DateTime(2026, 9, 14);
    final entry = calendarFixtureEvent(
      'details',
      DateTime(2026, 9, 14, 9),
      description: 'Stored event description',
      location: 'Stored location',
    );
    final workspace = CalendarWorkspace(
      providers: [
        CalendarFixtureProvider(events: [entry]),
      ],
    );
    var menus = 0;
    try {
      await mountCalendarTest(
        tester,
        Builder(
          builder: (context) => CalendarShell(
            workspace: workspace,
            initialMode: CalendarViewMode.monthSplit,
            initialDate: day,
            quiet: true,
            delegate: CalendarViewDelegate(
              colorOf: workspace.colorFor,
              onOpenEvent: (event) {
                unawaited(
                  showCalendarEventDetails(context, event: event),
                );
              },
              onEventMenu: (_, __) => menus++,
            ),
          ),
        ),
      );
      Focus.of(tester.element(find.text(entry.title))).requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(menus, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Stored event description'), findsOneWidget);
      expect(find.text('Stored location'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  testWidgets(
      'a controlled mode adopts a save rollback even when both updates precede a frame',
      (tester) async {
    final workspace = CalendarWorkspace(providers: [CalendarFixtureProvider()]);
    final mode = ValueNotifier(CalendarViewMode.monthAgenda);
    try {
      await mountCalendarTest(
        tester,
        ValueListenableBuilder<CalendarViewMode>(
          valueListenable: mode,
          builder: (_, saved, __) => CalendarShell(
            workspace: workspace,
            mode: saved,
            initialMode: saved,
            initialDate: DateTime(2026, 9, 14),
            quiet: true,
            onModeChanged: (next) {
              mode.value = next;
              mode.value = CalendarViewMode.monthAgenda;
            },
            delegate: CalendarViewDelegate(colorOf: workspace.colorFor),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('calendar-mode-menu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          AppMenuRow,
          calendarViewModeLabel(CalendarViewMode.monthSplit),
        ),
      );
      await tester.pumpAndSettle();
      expect(mode.value, CalendarViewMode.monthAgenda);
      expect(_reading(tester).sideBySide, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      mode.dispose();
      workspace.dispose();
    }
  });

  testWidgets(
      'an external layout change after paging a month selects within the visible month',
      (tester) async {
    final workspace = CalendarWorkspace(providers: [CalendarFixtureProvider()]);
    final key = GlobalKey<CalendarShellState>();
    Widget calendar(CalendarViewMode mode) => CalendarShell(
          key: key,
          workspace: workspace,
          initialMode: mode,
          initialDate: DateTime(2026, 8, 14),
          quiet: true,
          delegate:
              CalendarViewDelegate(colorOf: workspace.colorFor, canEdit: false),
        );
    try {
      await mountCalendarTest(tester, calendar(CalendarViewMode.month));
      await tester.tap(find.text('14'));
      await tester.pump();
      await tester.tap(find.byTooltip(LocaleKeys.calendarView_next.tr()));
      await tester.pumpAndSettle();
      await tester
          .pumpWidget(calendarTestApp(calendar(CalendarViewMode.monthSplit)));
      await tester.pumpAndSettle();
      expect(_reading(tester).month.month, 9);
      expect(_reading(tester).selectedDay, DateTime(2026, 9));
      expect(_day(DateTime(2026, 9)), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  testWidgets('six weeks and the first event fit a compact 400x380 calendar',
      (tester) async {
    final selected = DateTime(2026, 8, 14);
    final workspace = CalendarWorkspace(
      providers: [
        CalendarFixtureProvider(
          events: [calendarFixtureEvent('compact event', selected)],
        ),
      ],
    );
    try {
      await mountCalendarTest(
        tester,
        CalendarShell(
          workspace: workspace,
          initialMode: CalendarViewMode.monthAgenda,
          initialDate: selected,
          quiet: true,
          delegate: CalendarViewDelegate(
            colorOf: workspace.colorFor,
            onOpenEvent: (_) {},
            onCreateAt: (_, {bool hasTime = false}) {},
          ),
        ),
        size: const Size(400, 380),
      );
      final frame =
          tester.getRect(find.byKey(const ValueKey('calendar-test-frame')));
      expect(
        find.byKey(const ValueKey('calendar-compact-week-5')),
        findsOneWidget,
      );
      expect(
        tester.getRect(_event('compact event')).bottom,
        lessThanOrEqualTo(frame.bottom),
      );
      expect(_event('compact event').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-agenda-add')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  testWidgets('keyboard selection reveals the sixth week at 2x text',
      (tester) async {
    final workspace = CalendarWorkspace(providers: [CalendarFixtureProvider()]);
    try {
      await mountCalendarTest(
        tester,
        CalendarShell(
          workspace: workspace,
          initialMode: CalendarViewMode.monthAgenda,
          initialDate: DateTime(2026, 8, 3),
          quiet: true,
          delegate: CalendarViewDelegate(colorOf: workspace.colorFor),
        ),
        size: const Size(240, 300),
        textScale: 2,
      );
      await tester.tap(_day(DateTime(2026, 8, 3)));
      await tester.pump();
      for (var week = 0; week < 4; week++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.pump();
      }
      final selected = _day(DateTime(2026, 8, 31));
      final frame =
          tester.getRect(find.byKey(const ValueKey('calendar-test-frame')));
      expect(_reading(tester).selectedDay, DateTime(2026, 8, 31));
      expect(selected.hitTestable(), findsOneWidget);
      expect(tester.getRect(selected).bottom, lessThanOrEqualTo(frame.bottom));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });
}
