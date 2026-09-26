import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/database/calendar/application/calendar_view_setting.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_agenda_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the five original names and ordinals are unchanged; new modes append',
      () {
    expect(CalendarViewMode.values.map((mode) => mode.name), [
      'month',
      'week',
      'day',
      'agenda',
      'year',
      'monthAgenda',
      'monthSplit',
    ]);
    expect(
      CalendarViewMode.values.take(5).map((mode) => mode.index),
      [0, 1, 2, 3, 4],
    );
    expect(CalendarViewMode.fromValue(null), CalendarViewMode.month);
    expect(CalendarViewMode.fromValue('future'), CalendarViewMode.month);
  });

  for (final mode in CalendarViewMode.values) {
    test('${mode.name}: real dashboard and editor settings round-trip', () {
      final spec = DashboardWidgetSpec(
        id: 'calendar-settings-fixture',
        type: 'calendar',
        settings: {'mode': mode.name, 'weekends': false, 'week_numbers': true},
      );
      final restored = DashboardWidgetSpec.fromJson(
        Map<String, Object?>.from(jsonDecode(jsonEncode(spec.toJson())) as Map),
      );
      expect(CalendarViewMode.fromValue(restored.setting('mode')), mode);
      expect(restored.settings, spec.settings);
      final extra = CalendarViewSetting(mode).mergeIntoExtra(
        '{"cover":"keep","appflowy_calendar_presentation":{"version":1,"custom":7}}',
      );
      expect(CalendarViewSetting.fromExtra(extra)!.mode, mode);
      final decoded = jsonDecode(extra) as Map;
      expect(decoded['cover'], 'keep');
      expect((decoded[CalendarViewSetting.envelopeKey] as Map)['custom'], 7);
    });
  }

  test('absent, malformed and future editor preferences keep host defaults',
      () {
    for (final extra in [
      '',
      'not json',
      '{}',
      '{"appflowy_calendar_presentation":false}',
      '{"appflowy_calendar_presentation":{"version":2,"mode":"month"}}',
      '{"appflowy_calendar_presentation":{"version":1,"mode":"unknown"}}',
    ]) {
      expect(CalendarViewSetting.fromExtra(extra), isNull);
    }
  });

  test('mode saves serialize and merge fresh extra without native calls',
      () async {
    var extra = '{"cover":"original"}';
    final firstWrite = Completer<void>();
    final writes = <String>[];
    final settings = CalendarViewSettings(
      readExtra: (_) async => extra,
      writeExtra: (_, next) async {
        writes.add(next);
        if (writes.length == 1) await firstWrite.future;
        extra = next;
      },
    );
    final view = ViewPB(id: 'mode-fixture', extra: extra);
    final first = settings.set(view, CalendarViewMode.monthAgenda);
    final second = settings.set(view, CalendarViewMode.monthSplit);
    expect(settings.listenable(view).value, CalendarViewMode.monthSplit);
    await Future<void>.delayed(Duration.zero);
    expect(writes, hasLength(1));
    firstWrite.complete();
    await Future.wait([first, second]);
    expect(writes, hasLength(2));
    expect(
      CalendarViewSetting.fromExtra(extra)!.mode,
      CalendarViewMode.monthSplit,
    );
    expect((jsonDecode(extra) as Map)['cover'], 'original');
    final reopened = CalendarViewSettings();
    expect(
      reopened.listenable(ViewPB(id: view.id, extra: extra)).value,
      CalendarViewMode.monthSplit,
    );
    reopened.reset();
    settings.reset();
  });

  test('failed save rolls back the newest choice, not another view', () async {
    final original =
        CalendarViewSetting(CalendarViewMode.week).mergeIntoExtra('');
    final settings = CalendarViewSettings(
      readExtra: (_) async => original,
      writeExtra: (_, __) async => throw StateError('offline boundary'),
    );
    final view = ViewPB(id: 'failed-mode', extra: original);
    final untouched = ViewPB(
      id: 'another-mode',
      extra: CalendarViewSetting(CalendarViewMode.day).mergeIntoExtra(''),
    );
    settings.listenable(untouched);
    await settings.set(view, CalendarViewMode.monthAgenda);
    expect(settings.listenable(view).value, CalendarViewMode.week);
    expect(settings.listenable(untouched).value, CalendarViewMode.day);
    settings.reset();
  });

  test('received extra adopts a saved mode without writing', () {
    var writes = 0;
    final settings = CalendarViewSettings(
      writeExtra: (_, __) async {
        writes++;
      },
    );
    final view = ViewPB(id: 'remote-mode');
    final choice = settings.listenable(view);
    expect(choice.value, isNull);
    settings.adopt(
      ViewPB(
        id: view.id,
        extra:
            CalendarViewSetting(CalendarViewMode.monthSplit).mergeIntoExtra(''),
      ),
    );
    expect(choice.value, CalendarViewMode.monthSplit);
    expect(writes, 0);
    settings.reset();
  });

  test(
      'a provider read completing after disposal does not notify a retired workspace',
      () async {
    final provider = _PendingCalendarProvider();
    final workspace = CalendarWorkspace(providers: [provider]);
    var notifications = 0;
    workspace.addListener(() => notifications++);
    final pending =
        workspace.load(CalendarWindow(DateTime(2026, 8), DateTime(2026, 9)));
    expect(notifications, 1);
    workspace.dispose();
    provider.done.complete();
    await pending;
    expect(notifications, 1);
  });

  test('month navigation clamps dates and handles both year boundaries', () {
    expect(
      calendarMonthOffset(DateTime(2027, 1, 31), 1),
      DateTime(2027, 2, 28),
    );
    expect(
      calendarMonthOffset(DateTime(2028, 1, 31), 1),
      DateTime(2028, 2, 29),
    );
    expect(
      calendarMonthOffset(DateTime(2026, 12, 31), 1),
      DateTime(2027, 1, 31),
    );
    expect(
      calendarMonthOffset(DateTime(2026, 1, 31), -1),
      DateTime(2025, 12, 31),
    );
    expect(calendarDayOffset(DateTime(2026, 10, 31), 1), DateTime(2026, 11));
  });

  test('five and six weeks keep every civil date in order', () {
    expect(monthGridDays(DateTime(2026, 9)), hasLength(35));
    final six = monthGridDays(DateTime(2026, 8));
    expect(six, hasLength(42));
    for (var index = 1; index < six.length; index++) {
      expect(six[index], calendarDayOffset(six[index - 1], 1));
    }
    expect(
      monthGridDays(DateTime(2026, 8), showWeekends: false),
      hasLength(30),
    );
    expect(
      monthGridDays(DateTime(2026, 8), firstDayOfWeek: DateTime.sunday)
          .first
          .weekday,
      DateTime.sunday,
    );
  });

  test(
      'selected-day and upcoming projections retain real identities and ranges',
      () {
    CalendarEvent event(
      String id,
      DateTime day, {
      DateTime? end,
      bool allDay = false,
    }) =>
        CalendarEvent(
          id: id,
          calendarId: 'projection',
          title: id,
          start: allDay ? ZonedDateTime.allDay(day) : ZonedDateTime.local(day),
          end: end == null
              ? null
              : allDay
                  ? ZonedDateTime.allDay(end)
                  : ZonedDateTime.local(end),
        );
    final trip = event(
      'trip',
      DateTime(2026, 8, 3),
      end: DateTime(2026, 8, 5),
      allDay: true,
    );
    final early = event('early', DateTime(2026, 8, 5, 9));
    final late = event('late', DateTime(2026, 8, 5, 17));
    final tomorrow = event('tomorrow', DateTime(2026, 8, 6, 10));
    final laterAllDay =
        event('later all day', DateTime(2026, 8, 7), allDay: true);
    final source = [laterAllDay, late, early, tomorrow, trip];
    final selected = calendarEventsOnDay(source, DateTime(2026, 8, 5));
    expect(selected, [trip, early, late]);
    expect(selected.first, same(trip));
    expect(
      calendarEventsAfterDay(source, DateTime(2026, 8, 5)),
      [tomorrow, laterAllDay],
    );
    expect(
      source.first,
      same(laterAllDay),
      reason: 'Never reorder the provider list.',
    );
  });
}

class _PendingCalendarProvider extends CalendarProvider {
  final done = Completer<void>();

  @override
  CalendarService get service => CalendarService.local;
  @override
  List<CalendarInfo> get calendars => const [];
  @override
  CalendarCapabilities get capabilities => CalendarCapabilities.readOnly;
  @override
  CalendarSyncStatus get status => CalendarSyncStatus.idle;
  @override
  List<CalendarEvent> get events => const [];
  @override
  Future<void> load(CalendarWindow window) => done.future;
  @override
  Future<void> refresh() async {}
}
