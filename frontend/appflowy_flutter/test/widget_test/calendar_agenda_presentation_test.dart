import 'dart:ui' as ui;

import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_agenda_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'calendar_test_support.dart';
import 'vivid_icon_test_support.dart' show settleVividIconPictures;

const _modes = [CalendarViewMode.monthAgenda, CalendarViewMode.monthSplit];
const _appearances = ['light', 'dark', 'paper'];
const _wideSize = Size(1697, 747);
const _compactSheetSize = Size(1128, 428);
const _gridKey = 'calendar-compact-month-grid';
const _layoutKey = 'calendar-month-agenda-layout';
const _agendaKey = 'calendar-day-agenda';
const _outerKey = PageStorageKey('calendar-month-agenda-outer');
const _listKey = PageStorageKey('calendar-day-agenda-scroll');
const _referenceKey = ValueKey('calendar-agenda-reference');
final _selected = DateTime(2026, 8, 14);
final _loadedFontFamilies = <String>{};

String _dateKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

Finder _key(String key, {Finder? within}) {
  final finder = find.byKey(ValueKey(key));
  return within == null
      ? finder
      : find.descendant(of: within, matching: finder);
}

Finder _day(DateTime day, {Finder? within}) =>
    _key('calendar-day-${_dateKey(day)}', within: within);

Finder _event(String id, {Finder? within}) =>
    _key('calendar-agenda-event-$id', within: within);

BoxDecoration _dayDecoration(
  WidgetTester tester,
  String part,
  DateTime day,
) =>
    tester
        .widget<AnimatedContainer>(_key('calendar-day-$part-${_dateKey(day)}'))
        .decoration! as BoxDecoration;

void _expectDateDensity(
  WidgetTester tester,
  DateTime day, {
  required double fontSize,
  required double badgeExtent,
  required Size targetSize,
  required Size focusSize,
}) {
  final target = tester.getRect(_day(day));
  final badge = tester.getRect(_key('calendar-day-badge-${_dateKey(day)}'));
  final focus = tester.getRect(_key('calendar-day-focus-${_dateKey(day)}'));
  // Global-coordinate subtraction introduces roundoff, not a layout change.
  expect(target.width, closeTo(targetSize.width, 1e-8));
  expect(target.height, closeTo(targetSize.height, 1e-8));
  expect(badge.width, closeTo(badgeExtent, 1e-8));
  expect(badge.height, closeTo(badgeExtent, 1e-8));
  expect(badge.center.dx, closeTo(target.center.dx, 1e-8));
  expect(badge.center.dy, closeTo(target.center.dy, 1e-8));
  expect(focus.width, closeTo(focusSize.width, 1e-8));
  expect(focus.height, closeTo(focusSize.height, 1e-8));
  expect(
    tester
        .widget<Text>(
          find.descendant(of: _day(day), matching: find.text('${day.day}')),
        )
        .style!
        .fontSize,
    fontSize,
  );
}

Future<void> _revealAgendaEvent(WidgetTester tester, String id) async {
  await tester.scrollUntilVisible(
    _event(id),
    48,
    scrollable: find.descendant(
      of: find.byKey(_listKey),
      matching: find.byType(Scrollable),
    ),
    maxScrolls: 20,
  );
  // ensureVisible can jump offsets; hit geometry needs the following frame.
  await tester.pumpAndSettle();
  final visible = tester
      .getRect(find.byKey(_listKey))
      .intersect(tester.getRect(find.byKey(_outerKey)))
      .intersect(tester.getRect(_key('calendar-test-frame')));
  final row = tester.getRect(_event(id));
  expect(_event(id).hitTestable(), findsOneWidget);
  expect(row.top, greaterThanOrEqualTo(visible.top - 1e-8));
  expect(row.bottom, lessThanOrEqualTo(visible.bottom + 1e-8));
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<CalendarEvent> _events(DateTime day) => [
      calendarFixtureEvent(
        'all-day',
        calendarDayOffset(day, -1),
        end: calendarDayOffset(day, 1),
        allDay: true,
        title: 'Release window',
      ),
      calendarFixtureEvent(
        'timed',
        DateTime(day.year, day.month, day.day, 9, 15),
        end: DateTime(day.year, day.month, day.day, 10, 45),
        title: 'Planning session',
      ).copyWith(color: const Color(0xFF5288B8)),
      calendarFixtureEvent(
        'reminder',
        DateTime(day.year, day.month, day.day, 16, 30),
        title: 'Confirm release notes',
        kind: CalendarEventKind.reminder,
      ).copyWith(color: const Color(0xFFB88942)),
      calendarFixtureEvent(
        'completed',
        DateTime(day.year, day.month, day.day, 17),
        title: 'Publish checklist',
        kind: CalendarEventKind.task,
      ).copyWith(isCompleted: true),
      calendarFixtureEvent(
        'upcoming',
        DateTime(day.year, day.month, day.day + 3, 11),
        end: DateTime(day.year, day.month, day.day + 3, 11, 45),
        title: 'Partner review',
        readOnly: true,
      ).copyWith(color: const Color(0xFF9773B8)),
    ];

CalendarShell _calendar(
  CalendarWorkspace workspace,
  CalendarViewMode mode, {
  Key? key,
  DateTime? selected,
  DateTime Function()? now,
  bool quiet = true,
  bool embedded = false,
  bool weekends = true,
  int firstDayOfWeek = DateTime.monday,
  CalendarViewDelegate? delegate,
}) =>
    CalendarShell(
      key: key,
      workspace: workspace,
      initialMode: mode,
      initialDate: selected ?? _selected,
      now: now ?? () => DateTime(2026, 8, 17, 12),
      quiet: quiet,
      embedded: embedded,
      showWeekNumbers: true,
      showWeekends: weekends,
      firstDayOfWeek: firstDayOfWeek,
      delegate: delegate ??
          CalendarViewDelegate(
            colorOf: workspace.colorFor,
            onOpenEvent: (_) {},
            onEventMenu: (_, __) {},
            onCreateAt: (_, {bool hasTime = false}) {},
            onToggleComplete: (_) {},
          ),
    );

/// Load the actual resolved family, as the Vivid fixtures do, from the bundled
/// variable face. No installed/system font or runtime download is required.
Future<void> _loadFonts(WidgetTester tester) async {
  final theme = Theme.of(tester.element(find.byType(CalendarShell).first));
  final families = {
    theme.textTheme.bodyMedium?.fontFamily,
    theme.textTheme.labelLarge?.fontFamily,
  }.whereType<String>();
  await tester.runAsync(() async {
    for (final family in families) {
      if (_loadedFontFamilies.contains(family)) continue;
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
      _loadedFontFamilies.add(family);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  Size size = _wideSize,
  String appearance = 'light',
  double scale = 1,
  bool rtl = false,
}) async {
  await mountCalendarTest(
    tester,
    child,
    size: size,
    appearance: appearance,
    textScale: scale,
    rtl: rtl,
  );
  await _loadFonts(tester);
}

Widget _reference(Widget child) => RepaintBoundary(
      key: _referenceKey,
      child: Builder(
        builder: (context) => ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: child,
        ),
      ),
    );

void main() {
  setUpAll(initializeCalendarTests);

  for (final mode in _modes) {
    for (final appearance in _appearances) {
      for (final month in [DateTime(2026, 8), DateTime(2026, 9)]) {
        testWidgets(
            'wide geometry ${mode.name} $appearance month=${month.month} at 1697x747',
            (tester) async {
          _viewport(tester, _wideSize);
          final selected = DateTime(month.year, month.month, 14);
          final workspace = CalendarWorkspace(
            providers: [CalendarFixtureProvider(events: _events(selected))],
          );
          try {
            await _mount(
              tester,
              _calendar(
                workspace,
                mode,
                selected: selected,
                now: () => DateTime(month.year, month.month, 17, 12),
                quiet: false,
              ),
              appearance: appearance,
            );
            final frame = tester.getRect(_key('calendar-test-frame'));
            final layout = tester.getRect(_key(_layoutKey));
            final grid = tester.getRect(_key(_gridKey));
            final agenda = tester.getRect(_key(_agendaKey));
            final toolbar =
                tester.getRect(_key('calendar-month-agenda-toolbar'));
            final split = mode == CalendarViewMode.monthSplit;
            expect(frame.size, _wideSize);
            expect(toolbar.width, 1673);
            expect(layout.width, toolbar.width - 24);
            expect(layout.width, 1649);
            expect(layout.width / frame.width, greaterThan(0.95));
            expect(layout.center.dx, closeTo(frame.center.dx, 0.01));
            expect(toolbar.center.dx, closeTo(layout.center.dx, 0.01));
            expect(grid.width, split ? 1007.5 : 1649);
            expect(
              grid.height,
              closeTo(split ? layout.height : layout.height * 0.58, 0.01),
            );
            expect(layout.bottom, closeTo(frame.bottom - 4, 0.01));
            if (split) {
              expect(agenda.width, 617.5);
              expect(agenda.height, layout.height);
              expect(agenda.top, grid.top);
              expect(agenda.left - grid.right, 24);
            } else {
              expect(agenda.left, grid.left + 26);
              expect(agenda.right, grid.right);
              expect(agenda.top - grid.bottom, 16);
            }
            expect(
              tester.getRect(_key('calendar-agenda-add')).right,
              agenda.right,
            );
            final days = monthGridDays(month);
            final weeks = month.month == 8
                ? [31, 32, 33, 34, 35, 36]
                : [36, 37, 38, 39, 40];
            expect(days.length, month.month == 8 ? 42 : 35);
            expect(
              find.descendant(
                of: _key(_gridKey),
                matching: find.byType(TextButton),
              ),
              findsNWidgets(days.length),
            );
            for (var row = 0; row < weeks.length; row++) {
              expect(
                tester.getSize(_key('calendar-compact-week-$row')).height,
                closeTo((grid.height - 20) / weeks.length, 0.01),
              );
              expect(
                tester.getSize(_key('calendar-compact-week-$row')).height,
                inInclusiveRange(60, 135),
              );
              expect(
                tester.widget<Text>(_key('calendar-week-number-$row')).data,
                '${weeks[row]}',
              );
            }
            // Six stacked weeks have 61.53px rows; five weeks and both split
            // months have room for the larger 64px square native target.
            final targetExtent = split || month.month == 9 ? 64.0 : 56.0;
            for (final day in days) {
              expect(_day(day).hitTestable(), findsOneWidget);
              final target = tester.getRect(_day(day));
              expect(target.width, closeTo(targetExtent, 1e-8));
              expect(target.height, closeTo(targetExtent, 1e-8));
              expect(target.bottom, lessThanOrEqualTo(grid.bottom + 0.01));
            }
            final stride = tester.getCenter(_day(days[1])).dx -
                tester.getCenter(_day(days.first)).dx;
            expect(stride, closeTo((grid.width - 26) / 7, 0.01));
            expect(
              stride / tester.getSize(_key('calendar-compact-week-0')).height,
              lessThan(4),
              reason: 'Wide pages must not return to 1600px by 30px rows.',
            );
            expect(tester.widget<Text>(_key('calendar-weekday-1')).data, 'Mon');
            _expectDateDensity(
              tester,
              selected,
              fontSize: 18,
              badgeExtent: 44,
              targetSize: Size.square(targetExtent),
              focusSize: const Size.square(56),
            );
            expect(find.text('09:15–10:45'), findsOneWidget);
            expect(find.text('calendarView.allDay'.tr()), findsOneWidget);
            expect(
              tester
                  .widget<Text>(find.text('Planning session'))
                  .style!
                  .fontSize,
              16,
            );
            final list = tester.getRect(find.byKey(_listKey));
            for (final id in ['all-day', 'timed', 'reminder', 'completed']) {
              expect(_event(id).hitTestable(), findsOneWidget);
              expect(tester.getRect(_event(id)).height, closeTo(48, 1e-8));
              expect(
                tester.getRect(_event(id)).bottom,
                lessThanOrEqualTo(list.bottom + 1e-8),
                reason: 'All four selected-day fixture events remain visible.',
              );
            }
            if (split) {
              expect(_event('upcoming').hitTestable(), findsOneWidget);
              expect(
                tester.getRect(_event('upcoming')).bottom,
                lessThanOrEqualTo(list.bottom + 1e-8),
              );
            } else {
              // Larger page rows keep the grid geometry unchanged. Upcoming
              // remains reachable through the same lazy agenda, not fake data.
              await _revealAgendaEvent(tester, 'upcoming');
              expect(
                tester
                    .widget<ListView>(find.byKey(_listKey))
                    .controller!
                    .offset,
                greaterThan(0),
              );
            }
            expect(
              tester.getRect(_event('upcoming')).height,
              closeTo(48, 1e-8),
            );
            expect(
              tester
                  .widget<SingleChildScrollView>(find.byKey(_outerKey))
                  .controller!
                  .position
                  .maxScrollExtent,
              0,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            workspace.dispose();
          }
        });
      }

      testWidgets(
          '${mode.name} $appearance: today, selection, focus and hover differ',
          (tester) async {
        _viewport(tester, _wideSize);
        final today = DateTime(2026, 8, 17);
        final weekend = DateTime(2026, 8, 15);
        final workspace = CalendarWorkspace(
          providers: [CalendarFixtureProvider(events: _events(_selected))],
        );
        final semantics = tester.ensureSemantics();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await _mount(
            tester,
            _calendar(workspace, mode),
            appearance: appearance,
          );
          final palette = calendarPaletteOf(tester.element(_day(_selected)));
          expect(
            _dayDecoration(tester, 'badge', _selected).color,
            palette.daySelected,
          );
          expect(
            _dayDecoration(tester, 'badge', _selected).shape,
            BoxShape.circle,
          );
          expect(
            (_dayDecoration(tester, 'badge', today).border! as Border)
                .top
                .color,
            palette.accent,
          );
          expect(
            _dayDecoration(tester, 'badge', today).color,
            palette.todayWash,
          );
          expect(
            (_dayDecoration(tester, 'focus', _selected).border! as Border)
                .top
                .color
                .a,
            0,
          );
          // This is outside the 44px badge but inside the native day button.
          final target = tester.getRect(_day(_selected));
          await tester.tapAt(Offset(target.left + 2, target.center.dy));
          await tester.pumpAndSettle();
          final node = tester.getSemantics(_day(_selected)).getSemanticsData();
          expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(node.hasFlag(ui.SemanticsFlag.isSelected), isTrue);
          expect(node.hasAction(ui.SemanticsAction.tap), isTrue);
          expect(
            (_dayDecoration(tester, 'focus', _selected).border! as Border)
                .top
                .color,
            palette.accent,
          );
          expect(
            find.descendant(
              of: _key('calendar-day-dots-2026-8-14'),
              matching: find.byType(CalendarColorDot),
            ),
            findsNWidgets(3),
          );
          expect(
            tester.getSemantics(_day(today)).getSemanticsData().value,
            contains('Today'),
          );
          await mouse.moveTo(tester.getCenter(_day(weekend)));
          await tester.pumpAndSettle();
          final hover = _key('calendar-day-focus-${_dateKey(weekend)}');
          expect(tester.getSize(hover), const Size.square(56));
          expect(
            _dayDecoration(tester, 'focus', weekend).color,
            palette.dayHover,
          );
          expect(
            _dayDecoration(tester, 'badge', _selected).color,
            palette.daySelected,
          );
          await tester.tap(_day(today));
          await tester.pumpAndSettle();
          expect(
            _dayDecoration(tester, 'badge', today).color,
            palette.daySelected,
          );
          expect(
            (_dayDecoration(tester, 'badge', today).border! as Border)
                .top
                .color,
            palette.accent,
          );
          expect(
            (_dayDecoration(tester, 'focus', today).border! as Border)
                .top
                .color,
            palette.accent,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
          workspace.dispose();
          semantics.dispose();
        }
      });
    }

    for (final size in [const Size(400, 380), const Size(680, 340)]) {
      testWidgets(
          '${mode.name} compact $size keeps six weeks and real events reachable',
          (tester) async {
        final workspace = CalendarWorkspace(
          providers: [CalendarFixtureProvider(events: _events(_selected))],
        );
        final opens = <String>[];
        try {
          await _mount(
            tester,
            _calendar(
              workspace,
              mode,
              delegate: CalendarViewDelegate(
                colorOf: workspace.colorFor,
                onOpenEvent: (event) => opens.add(event.id),
                onCreateAt: (_, {bool hasTime = false}) {},
              ),
            ),
            size: size,
          );
          final frame = tester.getRect(_key('calendar-test-frame'));
          final grid = tester.getRect(_key(_gridKey));
          final list = tester.getRect(find.byKey(_listKey));
          expect(grid.height, 212);
          expect(grid.height, lessThanOrEqualTo(240));
          expect(_day(DateTime(2026, 9, 6)).hitTestable(), findsOneWidget);
          expect(
            tester.widget<Flex>(_key(_layoutKey)).direction,
            mode == CalendarViewMode.monthSplit && size.width == 680
                ? Axis.horizontal
                : Axis.vertical,
          );
          _expectDateDensity(
            tester,
            _selected,
            fontSize: 14,
            badgeExtent: 32,
            targetSize: Size(
              size.width == 400
                  ? 50
                  : mode == CalendarViewMode.monthSplit
                      ? 48.76571428571429
                      : 56,
              32,
            ),
            focusSize: const Size(44, 32),
          );
          expect(
            tester.widget<Text>(find.text('Release window')).style!.fontSize,
            14,
          );
          expect(tester.getRect(_event('all-day')).height, closeTo(40, 1e-8));
          // A 400x380 stack and a 680x340 split show TWO complete event rows,
          // without scrolling. A shorter 680x340 stack still scrolls its list.
          if (size.width == 400 || mode == CalendarViewMode.monthSplit) {
            for (final id in ['all-day', 'timed']) {
              expect(_event(id).hitTestable(), findsOneWidget);
              expect(
                tester.getRect(_event(id)).bottom,
                lessThanOrEqualTo(list.bottom + 0.01),
              );
              expect(
                tester.getRect(_event(id)).bottom,
                lessThanOrEqualTo(frame.bottom),
              );
            }
          }
          for (final id in ['all-day', 'timed']) {
            if (_event(id).evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                _event(id),
                24,
                scrollable: find.descendant(
                  of: find.byKey(_listKey),
                  matching: find.byType(Scrollable),
                ),
                maxScrolls: 20,
              );
            }
            await tester.ensureVisible(_event(id));
            await tester.pumpAndSettle();
            expect(_event(id).hitTestable(), findsOneWidget);
            await tester.tap(_event(id));
          }
          expect(opens, ['all-day', 'timed']);
          expect(find.text('09:15–10:45'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          workspace.dispose();
        }
      });
    }

    for (final rtl in [false, true]) {
      for (final weekends in [false, true]) {
        testWidgets(
            '${mode.name} 320x300 at 2x rtl=$rtl weekends=$weekends reveals final week',
            (tester) async {
          final workspace =
              CalendarWorkspace(providers: [CalendarFixtureProvider()]);
          try {
            await _mount(
              tester,
              _calendar(
                workspace,
                mode,
                selected: DateTime(2026, 8, 3),
                weekends: weekends,
                firstDayOfWeek: DateTime.sunday,
              ),
              size: const Size(320, 300),
              scale: 2,
              rtl: rtl,
              appearance: 'paper',
            );
            final days = monthGridDays(
              DateTime(2026, 8),
              firstDayOfWeek: DateTime.sunday,
              showWeekends: weekends,
            );
            expect(days.length, weekends ? 42 : 30);
            for (final day in days) {
              expect(_day(day), findsOneWidget);
              expect(tester.getSize(_day(day)).width, greaterThanOrEqualTo(32));
            }
            expect(
              _day(DateTime(2026, 8, 29)),
              weekends ? findsOneWidget : findsNothing,
            );
            final agenda = tester.getRect(_key(_agendaKey));
            final grid = tester.getRect(_key(_gridKey));
            expect(
              rtl ? grid.right - agenda.right : agenda.left - grid.left,
              48,
            );
            await tester.tap(_day(DateTime(2026, 8, 3)));
            await tester.pump();
            for (var week = 0; week < 4; week++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await tester.pump();
              await tester.pump();
            }
            final last = _day(DateTime(2026, 8, 31));
            final frame = tester.getRect(_key('calendar-test-frame'));
            expect(last.hitTestable(), findsOneWidget);
            expect(
              tester.getRect(last).bottom,
              lessThanOrEqualTo(frame.bottom),
            );
            expect(
              tester
                  .widget<CalendarMonthAgendaView>(
                    find.byType(CalendarMonthAgendaView),
                  )
                  .selectedDay,
              DateTime(2026, 8, 31),
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            workspace.dispose();
          }
        });
      }
    }

    testWidgets(
        '${mode.name} empty and read-only transitions keep the agenda gutter and header stable',
        (tester) async {
      _viewport(tester, _wideSize);
      final entries = _events(_selected);
      final provider = CalendarFixtureProvider(events: entries);
      final workspace = CalendarWorkspace(providers: [provider]);
      try {
        await _mount(tester, _calendar(workspace, mode));
        final state = tester.state(find.byType(CalendarMonthAgendaView));
        final agenda = tester.getRect(_key(_agendaKey));
        final firstTop = tester.getRect(_event('all-day')).top;
        final list = tester.widget<ListView>(find.byKey(_listKey)).controller;
        provider.publish([]);
        await tester.pumpAndSettle();
        expect(tester.getRect(_key(_agendaKey)), agenda);
        expect(_event('all-day'), findsNothing);
        expect(
          find.text('calendarView.empty.selectedDay'.tr()),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _key('calendar-empty-day'),
            matching: find.byType(WorkspaceGlyph),
          ),
          findsOneWidget,
        );
        expect(tester.getRect(_key('calendar-empty-day')).top, firstTop);
        expect(
          tester.getSize(_key('calendar-empty-day')).height,
          greaterThanOrEqualTo(48),
        );
        provider.publish(entries);
        await tester.pumpWidget(
          calendarTestApp(
            _calendar(
              workspace,
              mode,
              delegate: CalendarViewDelegate(
                colorOf: workspace.colorFor,
                canEdit: false,
              ),
            ),
            size: _wideSize,
          ),
        );
        await tester.pumpAndSettle();
        expect(_key('calendar-agenda-add'), findsNothing);
        expect(tester.getRect(_event('all-day')).top, firstTop);
        expect(tester.state(find.byType(CalendarMonthAgendaView)), same(state));
        expect(
          tester.widget<ListView>(find.byKey(_listKey)).controller,
          same(list),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
      }
    });
  }

  for (final mode in _modes) {
    testWidgets(
        '${mode.name}: explicit card density and full-page constraints retain the reading',
        (tester) async {
      _viewport(tester, _wideSize);
      final workspace = CalendarWorkspace(
        providers: [
          CalendarFixtureProvider(
            events: [
              for (var index = 0; index < 40; index++)
                calendarFixtureEvent('entry-$index', _selected),
            ],
          ),
        ],
      );
      try {
        await _mount(tester, _calendar(workspace, mode, quiet: false));
        final state = tester.state(find.byType(CalendarMonthAgendaView));
        final flex = tester.element(_key(_layoutKey));
        final focus =
            tester.widget<Focus>(_key('calendar-date-grid-focus')).focusNode;
        final scroll =
            tester.widget<ListView>(find.byKey(_listKey)).controller!;
        scroll.jumpTo(120);
        await tester.pump();
        for (final embedded in [true, false]) {
          await tester.pumpWidget(
            calendarTestApp(
              _calendar(workspace, mode, quiet: false, embedded: embedded),
              size: _wideSize,
              appearance: 'paper',
            ),
          );
          await tester.pumpAndSettle();
          final split = mode == CalendarViewMode.monthSplit;
          expect(
            tester.getSize(_key(_gridKey)).width,
            embedded ? (split ? 600 : 696) : (split ? 1007.5 : 1649),
          );
          expect(
            tester.getSize(_key('calendar-compact-week-0')).height,
            embedded ? 44 : greaterThan(60),
          );
          _expectDateDensity(
            tester,
            _selected,
            fontSize: embedded ? 14 : 18,
            badgeExtent: embedded ? 36 : 44,
            targetSize:
                embedded ? const Size(56, 44) : Size.square(split ? 64 : 56),
            focusSize: Size.square(embedded ? 44 : 56),
          );
          expect(
            tester.state(find.byType(CalendarMonthAgendaView)),
            same(state),
          );
          expect(tester.element(_key(_layoutKey)), same(flex));
          expect(
            tester.widget<Focus>(_key('calendar-date-grid-focus')).focusNode,
            same(focus),
          );
          expect(
            tester.widget<ListView>(find.byKey(_listKey)).controller,
            same(scroll),
          );
          expect(scroll.offset, 120);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
      }
    });

    for (final appearance in _appearances) {
      for (final rtl in [false, true]) {
        testWidgets(
            '${mode.name}: full page $appearance at 2x rtl=$rtl keeps weekdays and actions',
            (tester) async {
          _viewport(tester, _wideSize);
          final workspace = CalendarWorkspace(
            providers: [CalendarFixtureProvider(events: _events(_selected))],
          );
          try {
            await _mount(
              tester,
              _calendar(
                workspace,
                mode,
                quiet: false,
                weekends: false,
                firstDayOfWeek: DateTime.sunday,
              ),
              appearance: appearance,
              scale: 2,
              rtl: rtl,
            );
            final grid = tester.getRect(_key(_gridKey));
            final agenda = tester.getRect(_key(_agendaKey));
            expect(grid.width, greaterThan(900));
            expect(_day(DateTime(2026, 8, 15)), findsNothing);
            expect(_day(DateTime(2026, 9, 4)).hitTestable(), findsOneWidget);
            expect(_event('all-day').hitTestable(), findsOneWidget);
            expect(_key('calendar-agenda-add').hitTestable(), findsOneWidget);
            _expectDateDensity(
              tester,
              _selected,
              fontSize: 18,
              badgeExtent: 46,
              targetSize: Size.square(
                mode == CalendarViewMode.monthSplit ? 64 : 56,
              ),
              focusSize: const Size.square(56),
            );
            expect(
              tester
                  .widget<Text>(find.text('Planning session'))
                  .style!
                  .fontSize,
              16,
            );
            expect(tester.getRect(_event('all-day')).height, greaterThan(48));
            if (mode == CalendarViewMode.monthAgenda) {
              expect(
                rtl ? grid.right - agenda.right : agenda.left - grid.left,
                48,
              );
            } else {
              expect(
                rtl ? grid.left - agenda.right : agenda.left - grid.right,
                24,
              );
            }
            // Scaled text may need inner/outer scrolling, but no fixture event
            // disappears or gets squeezed back to compact typography.
            await _revealAgendaEvent(tester, 'upcoming');
            final focus = tester
                .widget<Focus>(_key('calendar-date-grid-focus'))
                .focusNode!;
            await tester.tap(_day(_selected));
            await tester.pump();
            await tester.sendKeyEvent(
              rtl
                  ? LogicalKeyboardKey.arrowLeft
                  : LogicalKeyboardKey.arrowRight,
            );
            await tester.pumpAndSettle();
            expect(focus.hasFocus, isTrue);
            expect(
              tester
                  .widget<CalendarMonthAgendaView>(
                    find.byType(CalendarMonthAgendaView),
                  )
                  .selectedDay,
              DateTime(2026, 8, 17),
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
            workspace.dispose();
          }
        });
      }
    }
  }

  testWidgets(
      'wide/compact/2x and mode reflow keep the actual Flex, focus and both scroll positions',
      (tester) async {
    _viewport(tester, _wideSize);
    final provider = CalendarFixtureProvider(
      events: [
        for (var index = 0; index < 50; index++)
          calendarFixtureEvent('entry-$index', DateTime(2026, 8, 14, 9, index)),
      ],
    );
    final workspace = CalendarWorkspace(providers: [provider]);
    final key = GlobalKey<CalendarShellState>();
    try {
      await _mount(
        tester,
        _calendar(workspace, CalendarViewMode.monthSplit, key: key),
      );
      await tester.tap(_day(_selected));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(CalendarMonthAgendaView));
      final flex = tester.element(_key(_layoutKey));
      final focus =
          tester.widget<Focus>(_key('calendar-date-grid-focus')).focusNode!;
      final outer = tester
          .widget<SingleChildScrollView>(find.byKey(_outerKey))
          .controller!;
      final list = tester.widget<ListView>(find.byKey(_listKey)).controller!;
      final outerScrollable = find
          .descendant(
            of: find.byKey(_outerKey),
            matching: find.byType(Scrollable),
          )
          .first;
      final listScrollable = find.descendant(
        of: find.byKey(_listKey),
        matching: find.byType(Scrollable),
      );
      final outerState = tester.state<ScrollableState>(outerScrollable);
      final listState = tester.state<ScrollableState>(listScrollable);
      list.jumpTo(160);
      await tester.pump();
      for (final (size, scale, mode) in [
        (const Size(400, 380), 1.0, CalendarViewMode.monthAgenda),
        (const Size(680, 340), 1.0, CalendarViewMode.monthSplit),
        (const Size(320, 300), 2.0, CalendarViewMode.monthSplit),
        (_wideSize, 1.0, CalendarViewMode.monthAgenda),
        (_wideSize, 1.0, CalendarViewMode.monthSplit),
      ]) {
        await tester.pumpWidget(
          calendarTestApp(
            _calendar(workspace, mode, key: key),
            size: size,
            textScale: scale,
            appearance: 'paper',
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(CalendarMonthAgendaView)), same(state));
        expect(tester.element(_key(_layoutKey)), same(flex));
        expect(
          tester.widget<Focus>(_key('calendar-date-grid-focus')).focusNode,
          same(focus),
        );
        expect(focus.hasFocus, isTrue);
        expect(
          tester
              .widget<SingleChildScrollView>(find.byKey(_outerKey))
              .controller,
          same(outer),
        );
        expect(
          tester.widget<ListView>(find.byKey(_listKey)).controller,
          same(list),
        );
        // Theme changes can replace and absorb ScrollPositions. The same
        // scrollable owners, controllers and logical offsets must survive.
        expect(
          tester.state<ScrollableState>(outerScrollable),
          same(outerState),
        );
        expect(tester.state<ScrollableState>(listScrollable), same(listState));
        expect(outer.offset, 0);
        expect(list.offset, 160);
        expect(
          tester
              .widget<CalendarMonthAgendaView>(
                find.byType(CalendarMonthAgendaView),
              )
              .selectedDay,
          _selected,
        );
      }
      expect(provider.windows, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  testWidgets(
      'full-page primary scroll ownership survives mode, width and theme reflow',
      (tester) async {
    _viewport(tester, _wideSize);
    final pageScroll = ScrollController();
    final workspace = CalendarWorkspace(
      providers: [
        CalendarFixtureProvider(
          events: [
            for (var index = 0; index < 40; index++)
              calendarFixtureEvent('page-event-$index', _selected),
          ],
        ),
      ],
    );
    Widget page(CalendarViewMode mode) =>
        Provider<DatabasePluginWidgetBuilderSize>.value(
          value: const DatabasePluginWidgetBuilderSize(
            horizontalPadding: 0,
            coordinateVerticalScroll: true,
          ),
          child: PrimaryScrollController(
            controller: pageScroll,
            child: _calendar(workspace, mode, quiet: false),
          ),
        );
    final outerScrollable = find
        .descendant(
          of: find.byKey(_outerKey),
          matching: find.byType(Scrollable),
        )
        .first;
    try {
      await _mount(tester, page(CalendarViewMode.monthSplit));
      final owner = tester.state<ScrollableState>(outerScrollable);
      final reading = tester.state(find.byType(CalendarMonthAgendaView));
      final agenda = tester.widget<ListView>(find.byKey(_listKey)).controller!;
      agenda.jumpTo(120);
      await tester.pump();
      for (final (size, scale, mode) in [
        (const Size(1000, 560), 1.0, CalendarViewMode.monthAgenda),
        (const Size(320, 300), 2.0, CalendarViewMode.monthSplit),
        (_wideSize, 1.0, CalendarViewMode.monthSplit),
      ]) {
        await tester.pumpWidget(
          calendarTestApp(
            page(mode),
            size: size,
            textScale: scale,
            appearance: 'paper',
          ),
        );
        await tester.pumpAndSettle();
        final outer =
            tester.widget<SingleChildScrollView>(find.byKey(_outerKey));
        expect(outer.primary, isTrue);
        expect(outer.controller, isNull);
        expect(pageScroll.positions, hasLength(1));
        expect(tester.state<ScrollableState>(outerScrollable), same(owner));
        expect(owner.position, same(pageScroll.position));
        expect(
          tester.state(find.byType(CalendarMonthAgendaView)),
          same(reading),
        );
        expect(
          tester.widget<ListView>(find.byKey(_listKey)).controller,
          same(agenda),
        );
        expect(agenda.offset, 120);
        expect(agenda.position, isNot(same(pageScroll.position)));
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      pageScroll.dispose();
    }
  });

  testWidgets(
      'minute clock moves the today ring without changing selection or scroll ownership',
      (tester) async {
    var now = DateTime(2026, 8, 14, 23, 59);
    final workspace = CalendarWorkspace(providers: [CalendarFixtureProvider()]);
    try {
      await _mount(
        tester,
        _calendar(workspace, CalendarViewMode.monthAgenda, now: () => now),
        size: const Size(400, 380),
      );
      final list = tester.widget<ListView>(find.byKey(_listKey)).controller;
      now = DateTime(2026, 8, 15);
      await tester.pump(const Duration(minutes: 1));
      final palette = calendarPaletteOf(tester.element(_day(_selected)));
      expect(
        _dayDecoration(tester, 'badge', _selected).color,
        palette.daySelected,
      );
      expect(
        (_dayDecoration(tester, 'badge', _selected).border! as Border)
            .top
            .color
            .a,
        0,
      );
      expect(
        (_dayDecoration(tester, 'badge', now).border! as Border).top.color,
        palette.accent,
      );
      expect(
        tester.widget<ListView>(find.byKey(_listKey)).controller,
        same(list),
      );
      expect(
        tester.widget<Text>(_key('calendar-selected-day')).data,
        startsWith('Yesterday'),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  // Full-page typography deliberately changes these existing references;
  // compact references must stay unchanged.
  // Leave the PNGs untouched for the coordinator to render and review, then
  // compare normally. These are real shells with an offline provider, not
  // hand-drawn reconstructions or live workspace/provider data.
  for (final appearance in _appearances) {
    for (final mode in _modes) {
      testWidgets('golden wide ${mode.name} $appearance 1697x747',
          (tester) async {
        _viewport(tester, _wideSize);
        final workspace = CalendarWorkspace(
          providers: [CalendarFixtureProvider(events: _events(_selected))],
        );
        try {
          await _mount(
            tester,
            _reference(_calendar(workspace, mode, quiet: false)),
            appearance: appearance,
          );
          await settleVividIconPictures(tester);
          expect(tester.getSize(find.byKey(_referenceKey)), _wideSize);
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_referenceKey),
            matchesGoldenFile(
              'goldens/calendar_agenda_wide_${mode.name}_$appearance.png',
            ),
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          workspace.dispose();
        }
      });
    }

    testWidgets(
        'golden compact $appearance: actual 400x380 stack and 680x340 split',
        (tester) async {
      _viewport(tester, _compactSheetSize);
      final workspaces = [
        for (var index = 0; index < 2; index++)
          CalendarWorkspace(
            providers: [CalendarFixtureProvider(events: _events(_selected))],
          ),
      ];
      try {
        await _mount(
          tester,
          _reference(
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    key: const ValueKey('compact-stacked-shell'),
                    width: 400,
                    height: 380,
                    child:
                        _calendar(workspaces[0], CalendarViewMode.monthAgenda),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    key: const ValueKey('compact-split-shell'),
                    width: 680,
                    height: 340,
                    child:
                        _calendar(workspaces[1], CalendarViewMode.monthSplit),
                  ),
                ],
              ),
            ),
          ),
          size: _compactSheetSize,
          appearance: appearance,
        );
        await settleVividIconPictures(tester);
        for (final key in ['compact-stacked-shell', 'compact-split-shell']) {
          final root = _key(key);
          expect(
            _day(DateTime(2026, 9, 6), within: root).hitTestable(),
            findsOneWidget,
          );
          expect(_event('timed', within: root).hitTestable(), findsOneWidget);
          expect(
            tester.getRect(_event('timed', within: root)).bottom,
            lessThanOrEqualTo(tester.getRect(root).bottom),
          );
        }
        expect(tester.getSize(find.byKey(_referenceKey)), _compactSheetSize);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(_referenceKey),
          matchesGoldenFile('goldens/calendar_agenda_compact_$appearance.png'),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final workspace in workspaces) {
          workspace.dispose();
        }
      }
    });
  }
}
