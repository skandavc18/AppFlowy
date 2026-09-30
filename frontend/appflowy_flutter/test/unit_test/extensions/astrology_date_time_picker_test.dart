import 'package:appflowy/extensions/dart/built_in/astrology/astrology_date_time_picker.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_time.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/date_picker_calendar.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

const _newYork = AstrologyPlace(
  name: 'New York',
  latitude: 40.7128,
  longitude: -74.006,
  timeZone: 'America/New_York',
);
const _kolkata = AstrologyPlace(
  name: 'Kolkata',
  latitude: 22.5726,
  longitude: 88.3639,
  timeZone: 'Asia/Kolkata',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('wall-clock validation', () {
    test('blank components, strict formats, leap days and ephemeris endpoints',
        () {
      final now = DateTime.utc(2025, 1, 1, 0, 2, 7, 123, 456);
      DateTime parse(String date, String time) => AstrologyTime.parseWallTime(
            date: date,
            time: time,
            now: now,
          );
      expect(parse('', ''), DateTime.utc(2025, 1, 1, 0, 2, 7));
      expect(parse(' ', '9:05'), DateTime.utc(2025, 1, 1, 9, 5));
      expect(parse('2000-02-29', ''), DateTime.utc(2000, 2, 29, 0, 2, 7));
      expect(
        parse(' 2024-02-29 ', ' 09:05:59 '),
        DateTime.utc(2024, 2, 29, 9, 5, 59),
      );
      expect(parse('1800-01-01', '00:00:00'), DateTime.utc(1800));
      expect(
        parse('2399-12-31', '23:59:59'),
        DateTime.utc(2399, 12, 31, 23, 59, 59),
      );

      // A local-flagged DateTime is also just a set of supplied components.
      final wall = AstrologyTime.parseWallTime(
        date: '',
        time: '',
        now: DateTime(2025, 1, 1, 0, 2, 7),
      );
      expect(wall, DateTime.utc(2025, 1, 1, 0, 2, 7));
      expect(wall.isUtc, isTrue);
    });

    test('invalid dates and clocks are rejected rather than normalized', () {
      for (final value in [
        (date: '1900-02-29', time: '12:00', message: 'does not exist'),
        (date: '2023-02-29', time: '12:00', message: 'does not exist'),
        (date: '2000-02-30', time: '12:00', message: 'does not exist'),
        (date: '2000-13-01', time: '12:00', message: 'does not exist'),
        (date: '2000-01-00', time: '12:00', message: 'does not exist'),
        (date: '1799-12-31', time: '12:00', message: '1800–2399'),
        (date: '2400-01-01', time: '12:00', message: '1800–2399'),
        (date: '2024/02/29', time: '12:00', message: 'YYYY-MM-DD'),
        (date: '2024-2-29', time: '12:00', message: 'YYYY-MM-DD'),
        (date: '2024-02-29', time: '24:00', message: 'does not exist'),
        (date: '2024-02-29', time: '12:60', message: 'does not exist'),
        (date: '2024-02-29', time: '12:00:60', message: 'does not exist'),
        (date: '2024-02-29', time: '1:2', message: '24-hour'),
        (date: '2024-02-29', time: '12:00:00.1', message: '24-hour'),
      ]) {
        expect(
          () => AstrologyTime.parseWallTime(
            date: value.date,
            time: value.time,
            now: DateTime.utc(2024),
          ),
          _formatError(value.message),
          reason: '${value.date} ${value.time}',
        );
      }
    });

    test('birth parsing retains DST gap/overlap and explicit-offset behavior',
        () {
      expect(
        () => AstrologyTime.parseBirthTime(
          date: '2024-03-10',
          time: '02:30:45',
          place: _newYork,
          now: DateTime.utc(2024),
        ),
        _formatError('skipped'),
      );
      expect(
        () => AstrologyTime.parseBirthTime(
          date: '2024-11-03',
          time: '01:30:45',
          place: _newYork,
          now: DateTime.utc(2024),
        ),
        _formatError('occurred twice'),
      );
      for (final offset in [-240, -300]) {
        expect(
          AstrologyTime.parseBirthTime(
            date: '2024-11-03',
            time: '01:30:45',
            place: _newYork,
            offsetMinutes: offset,
            now: DateTime.utc(2024),
          ),
          DateTime.utc(2024, 11, 3, offset == -240 ? 5 : 6, 30, 45),
        );
      }
      expect(
        AstrologyTime.parseBirthTime(
          date: '',
          time: '00:15:07',
          place: _kolkata,
          now: DateTime.utc(2024, 12, 31, 20),
        ),
        DateTime.utc(2024, 12, 31, 18, 45, 7),
      );
      // Unlike birth parsing, the picker validator deliberately has no DST rules.
      expect(
        AstrologyTime.parseWallTime(
          date: '2024-03-10',
          time: '02:30:45',
          now: DateTime.utc(2024),
        ),
        DateTime.utc(2024, 3, 10, 2, 30, 45),
      );
    });
  });

  _widgetTest('the calendar browses freely; only a day click chooses',
      (tester) async {
    final host = await _mountHost(tester);
    await _open(tester);
    final popup = tester.getRect(_byId('astrology-date-time-picker'));
    final anchor = tester.getRect(_byId('picker-test-anchor'));
    expect(popup.left, closeTo(anchor.left, 0.01));
    expect(popup.top, closeTo(anchor.bottom + 6, 0.01));
    final calendar = tester.widget<DatePickerCalendar>(_calendar);
    expect(calendar.firstDay, DateTime.utc(1800));
    expect(calendar.lastDay, DateTime.utc(2399, 12, 31));
    expect(calendar.currentDay, DateTime.utc(2024, 2, 28, 12, 34, 7));
    expect(calendar.selectedDay, DateTime.utc(2024, 2, 28));
    _expectMonth('February', '2024');
    expect(host.results, isEmpty);

    await _tapDay(tester, 29);
    expect(_controller(tester, 'date').text, '2024-02-29');
    expect(_controller(tester, 'time').text, '23:45:56');
    await _tap(tester, _inCalendar('date_picker_next'));
    _expectMonth('March', '2024');
    expect(_controller(tester, 'date').text, '2024-02-29');
    await _tap(tester, _inCalendar('date_picker_previous'));
    _expectMonth('February', '2024');

    // The year list jumps without choosing; a day click then chooses.
    await _tap(tester, _inCalendar('date_picker_year_button'));
    expect(_inCalendar('date_picker_days'), findsNothing);
    await _tap(tester, _year(2025));
    _expectMonth('February', '2025');
    expect(_controller(tester, 'date').text, '2024-02-29');
    await _tapDay(tester, 28);
    expect(_controller(tester, 'date').text, '2025-02-28');
    expect(_controller(tester, 'time').text, '23:45:56');

    // The clock is typed, like a date cell's.
    await _enter(tester, 'time', '22:44:57');
    expect(_controller(tester, 'date').text, '2025-02-28');
    expect(host.date, '2024-02-28', reason: 'No live mutation of the caller.');
    expect(host.time, '23:45:56');
    expect(host.results, isEmpty);

    await _tap(tester, _byId('astrology-picker-apply'));
    expect(host.results, hasLength(1));
    expect(host.date, '2025-02-28');
    expect(host.time, '22:44:57');
    expect(_byId('astrology-date-time-picker'), findsNothing);
  });

  _widgetTest('month and year lists jump far without choosing a day',
      (tester) async {
    final host = await _mountHost(tester, date: '2024-03-31');
    await _open(tester);
    _expectMonth('March', '2024');

    // Twenty years back is a page of the year list, not 240 month pages.
    await _tap(tester, _inCalendar('date_picker_year_button'));
    final years = tester.widget<GridView>(
      find.descendant(of: _calendar, matching: find.byType(GridView)),
    );
    expect(
      (years.childrenDelegate as SliverChildBuilderDelegate).childCount,
      600,
    );
    expect(_year(2024), findsOneWidget);
    await _tap(tester, _inCalendar('date_picker_previous'));
    await _tap(tester, _year(2004));
    _expectMonth('March', '2004');
    expect(_controller(tester, 'date').text, '2024-03-31');

    await _tap(tester, _inCalendar('date_picker_month_button'));
    for (var month = 1; month <= 12; month++) {
      expect(_inCalendar('date_picker_month_$month'), findsOneWidget);
    }
    await _tap(tester, _inCalendar('date_picker_month_2'));
    _expectMonth('February', '2004');
    expect(_controller(tester, 'date').text, '2024-03-31');
    await _tapDay(tester, 29);
    expect(_controller(tester, 'date').text, '2004-02-29');
    expect(host.results, isEmpty);

    await _tap(tester, _byId('astrology-picker-apply'));
    expect(host.date, '2004-02-29');
    expect(host.time, '23:45:56');
  });

  _widgetTest('a blank date browses from today at the birthplace',
      (tester) async {
    final host = await _mountHost(tester, date: '');
    await _open(tester);
    _expectMonth('February', '2024');
    expect(tester.widget<DatePickerCalendar>(_calendar).selectedDay, isNull);
    await _tap(tester, _inCalendar('date_picker_year_button'));
    await _tap(tester, _inCalendar('date_picker_previous'));
    await _tap(tester, _inCalendar('date_picker_previous'));
    await _tap(tester, _year(1990));
    _expectMonth('February', '1990');
    expect(_controller(tester, 'date').text, isEmpty);
    await _tap(tester, _byId('astrology-picker-cancel'));
    expect(host.results, [null]);
    expect(host.date, '');
  });

  _widgetTest(
      'unchanged/equivalent Apply retains original strings through exit',
      (tester) async {
    final host = await _mountHost(
      tester,
      date: ' 2024-02-29 ',
      time: '9:05',
    );
    await _open(tester);
    await _tap(tester, _byId('astrology-picker-apply'));
    expect(host.date, ' 2024-02-29 ');
    expect(host.time, '9:05');

    await _open(tester);
    await _enter(tester, 'date', '2024-02-29');
    await _enter(tester, 'time', '09:05:00');
    final controller = _controller(tester, 'date');
    final apply = _byId('astrology-picker-apply');
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pump();
    expect(host.results, hasLength(2));
    expect(host.date, ' 2024-02-29 ');
    expect(host.time, '9:05');
    expect(_byId('astrology-date-time-picker'), findsOneWidget);
    // The host rebuilds on Future resolution, while the route is still fading.
    void listener() {}
    expect(() => controller.addListener(listener), returnsNormally);
    controller.removeListener(listener);
    await tester.pumpAndSettle();
    expect(_byId('astrology-date-time-picker'), findsNothing);
  });

  _widgetTest('Cancel, Escape and the transparent barrier discard the draft',
      (tester) async {
    final host = await _mountHost(tester);
    for (final dismissal in ['cancel', 'escape', 'barrier']) {
      await _open(tester);
      await _enter(tester, 'date', '2000-01-01');
      await _enter(tester, 'time', '01:02:03');
      expect(host.date, '2024-02-28');
      expect(host.time, '23:45:56');
      final route = ModalRoute.of(tester.element(_calendar))!;
      expect(route.barrierColor, Colors.transparent);
      expect(route.barrierDismissible, isTrue);
      if (dismissal == 'cancel') {
        await _tap(tester, _byId('astrology-picker-cancel'));
      } else if (dismissal == 'escape') {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.tapAt(const Offset(2, 2));
      }
      await tester.pumpAndSettle();
      expect(host.results.last, isNull);
      expect(host.date, '2024-02-28');
      expect(host.time, '23:45:56');
      expect(_byId('astrology-date-time-picker'), findsNothing);
    }
    expect(host.results, hasLength(3));
  });

  _widgetTest('blank fallbacks stay blank; Today uses supplied wall midnight',
      (tester) async {
    final host = await _mountHost(
      tester,
      date: '',
      time: '',
      localNow: DateTime.utc(2025, 1, 1, 0, 0, 7),
      timeZoneLabel: 'Pacific/Kiritimati · UTC +14:00',
    );
    await _open(tester);
    final calendar = tester.widget<DatePickerCalendar>(_calendar);
    expect(calendar.selectedDay, isNull);
    expect(calendar.currentDay, DateTime.utc(2025, 1, 1, 0, 0, 7));
    _expectMonth('January', '2025');
    expect(_controller(tester, 'date').text, isEmpty);
    expect(_controller(tester, 'time').text, isEmpty);
    await _tap(tester, _byId('astrology-picker-apply'));
    expect(host.date, isEmpty);
    expect(host.time, isEmpty);

    await _open(tester);
    await _enter(tester, 'time', '01:00:07');
    expect(_controller(tester, 'date').text, isEmpty);
    await _tap(tester, _byId('astrology-picker-cancel'));
    expect(host.date, isEmpty);
    expect(host.time, isEmpty);

    await _open(tester);
    await _tap(tester, _byId('astrology-picker-today'));
    expect(_controller(tester, 'date').text, '2025-01-01');
    expect(_controller(tester, 'time').text, isEmpty);
    await _enter(tester, 'time', '23:59:58');
    await _tap(tester, _byId('astrology-picker-today'));
    expect(_controller(tester, 'time').text, '23:59:58');
    await _tap(tester, _byId('astrology-picker-apply'));
    expect(host.date, '2025-01-01');
    expect(host.time, '23:59:58');
  });

  _widgetTest('invalid manual input stays visible until explicitly corrected',
      (tester) async {
    final host = await _mountHost(tester, date: '2400-01-01');
    await _open(tester);
    expect(_controller(tester, 'date').text, '2400-01-01');
    expect(_byId('astrology-picker-error'), findsNothing);
    for (final entry in [
      (date: '2400-01-01', message: '1800–2399'),
      (date: '1799-12-31', message: '1800–2399'),
      (date: '1900-02-29', message: 'does not exist'),
      (date: '2024/02/29', message: 'YYYY-MM-DD'),
    ]) {
      await _enter(tester, 'date', entry.date);
      await _tap(tester, _byId('astrology-picker-apply'));
      expect(_errorText(tester), contains(entry.message));
      expect(_controller(tester, 'date').text, entry.date);
      expect(_controller(tester, 'time').text, '23:45:56');
      expect(host.results, isEmpty);
    }
    await _enter(tester, 'date', '2000-02-29');
    expect(
      tester.widget<DatePickerCalendar>(_calendar).selectedDay,
      DateTime.utc(2000, 2, 29),
    );
    _expectMonth('February', '2000');
    await _enter(tester, 'time', '12:34:60');
    await _tap(tester, _byId('astrology-picker-apply'));
    expect(_errorText(tester), contains('does not exist'));
    expect(_controller(tester, 'time').text, '12:34:60');
    // Choosing a day does not fix the seconds behind the user's back.
    await _tapDay(tester, 28);
    expect(_controller(tester, 'date').text, '2000-02-28');
    expect(_controller(tester, 'time').text, '12:34:60');
    await _enter(tester, 'time', '12:34:59');
    expect(_byId('astrology-picker-error'), findsNothing);
    await _tap(tester, _byId('astrology-picker-apply'));
    expect(host.date, '2000-02-28');
    expect(host.time, '12:34:59');
  });

  _widgetTest('field-local Backspace, repeat and Ctrl+A beat ancestor commands',
      (tester) async {
    var intercepted = 0;
    final host = await _mountHost(
      tester,
      focusTime: true,
      onIntercept: () => intercepted++,
    );
    final outerOffset = host.scroll.offset;
    await _open(tester);
    final timeField = tester.widget<TextField>(_byId('astrology-picker-time'));
    expect(timeField.focusNode!.hasPrimaryFocus, isTrue);
    expect(find.byType(TextEntryShortcuts), findsNWidgets(2));
    final time = _controller(tester, 'time');
    time.selection = const TextSelection(baseOffset: 6, extentOffset: 8);
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.backspace,
      physicalKey: PhysicalKeyboardKey.backspace,
      platform: 'windows',
    );
    try {
      await tester.pump();
      expect(time.text, '23:45:');
      await tester.sendKeyRepeatEvent(
        LogicalKeyboardKey.backspace,
        physicalKey: PhysicalKeyboardKey.backspace,
        platform: 'windows',
      );
      await tester.pump();
      expect(time.text, '23:45');
    } finally {
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.backspace,
        physicalKey: PhysicalKeyboardKey.backspace,
        platform: 'windows',
      );
    }

    await _tap(tester, _byId('astrology-picker-date'));
    final date = _controller(tester, 'date');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    try {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.pump();
    expect(
      date.selection,
      const TextSelection(baseOffset: 0, extentOffset: 10),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(date.text, isEmpty);
    expect(intercepted, 0);
    expect(host.scroll.offset, outerOffset);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(host.results.single, isNull);
    expect(host.date, '2024-02-28');
    expect(host.time, '23:45:56');
  });

  for (final appearance in [
    (name: 'light', brightness: Brightness.light, paper: false),
    (name: 'dark', brightness: Brightness.dark, paper: false),
    (name: 'paper', brightness: Brightness.light, paper: true),
  ]) {
    _widgetTest(
        '${appearance.name}: local theme, 2x text and gated short window',
        (tester) async {
      tester.view.physicalSize = const Size(280, 240);
      final host = await _mountHost(
        tester,
        theme: _theme(appearance.brightness, appearance.paper),
        textScale: 2,
        alignment: Alignment.bottomRight,
        gateScroll: true,
      );
      final palette =
          AstrologyPalette.of(tester.element(_byId('picker-test-anchor')));
      final outerOffset = host.scroll.offset;
      await _open(tester);
      final root = _byId('astrology-date-time-picker');
      final rect = tester.getRect(root);
      expect(rect.left, greaterThanOrEqualTo(8));
      expect(rect.top, greaterThanOrEqualTo(8));
      expect(rect.right, lessThanOrEqualTo(272));
      expect(rect.bottom, lessThanOrEqualTo(232));
      final material = tester.widget<Material>(root);
      expect(material.color, palette.raised);
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(10));
      expect(shape.side.width, 0.5);
      expect(shape.side.color, palette.line);
      expect(
        Theme.of(tester.element(_calendar)).brightness,
        appearance.brightness,
      );
      for (final part in ['date', 'time']) {
        final field = _byId('astrology-picker-$part');
        expect(MediaQuery.textScalerOf(tester.element(field)).scale(13), 26);
        // One outline around both fields, as in a date cell's picker.
        final decoration = tester.widget<TextField>(field).decoration!;
        expect(decoration.filled, isFalse);
        expect(decoration.enabledBorder, InputBorder.none);
        expect(decoration.focusedBorder, InputBorder.none);
        final fieldRect = tester.getRect(field);
        expect(fieldRect.left, greaterThanOrEqualTo(rect.left));
        expect(fieldRect.right, lessThanOrEqualTo(rect.right));
      }
      Color outline() => ((tester
                  .widget<AnimatedContainer>(_byId('astrology-picker-entry'))
                  .decoration! as BoxDecoration)
              .border! as Border)
          .top
          .color;
      // The date field starts focused, so the shared outline is the accent.
      expect(outline(), palette.accent);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(outline(), palette.line);
      // The shared calendar draws with the picker's own palette.
      final days = find.descendant(
        of: _calendar,
        matching: find.byType(TableCalendar),
      );
      final calendarTheme = Theme.of(tester.element(days));
      expect(calendarTheme.colorScheme.primary, palette.accent);
      expect(calendarTheme.colorScheme.surface, palette.raised);
      expect(calendarTheme.cardColor, palette.raised);
      expect(calendarTheme.hoverColor, palette.hover);
      final apply = tester.widget<TextButton>(_byId('astrology-picker-apply'));
      expect(apply.style!.backgroundColor!.resolve({}), palette.accent);
      expect(apply.style!.foregroundColor!.resolve({}), palette.onAccent);
      final cancel = tester.widget<TextButton>(
        _byId('astrology-picker-cancel'),
      );
      expect(cancel.style!.backgroundColor!.resolve({}), Colors.transparent);
      if (appearance.paper) {
        expect(material.color, PaperTheme.popupBackground);
        expect(palette.raised.r, greaterThan(palette.raised.b));
      }
      final routeSemantics = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Birth date and time',
      );
      expect(
        tester.getSemantics(routeSemantics).getSemanticsData().label,
        'Birth date and time',
      );
      expect(
        find.descendant(
          of: root,
          matching: find.byWidgetPredicate((widget) => widget is RawScrollbar),
        ),
        findsNothing,
      );

      final scroll = _popupScroll(tester).controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final before = scroll.offset;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: rect.topLeft + const Offset(6, 20),
          scrollDelta: const Offset(0, 80),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(before));
      tester
          .widget<TextField>(_byId('astrology-picker-time'))
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      expect(
        host.scroll.offset,
        outerOffset,
        reason: 'Focus and wheel input only move the popup scroll view.',
      );

      // The year list follows the card's text scale and shows no rail.
      await _tap(tester, _inCalendar('date_picker_year_button'));
      final year = _inCalendar('date_picker_year_2024');
      expect(year, findsOneWidget);
      expect(
        MediaQuery.textScalerOf(
          tester
              .element(find.descendant(of: year, matching: find.text('2024'))),
        ).scale(13),
        26,
      );
      expect(
        find.descendant(
          of: root,
          matching: find.byWidgetPredicate((widget) => widget is RawScrollbar),
        ),
        findsNothing,
      );
      final scrollbarTheme = ScrollbarTheme.of(tester.element(year));
      expect(scrollbarTheme.thickness!.resolve({}), 0);
      expect(scrollbarTheme.trackVisibility!.resolve({}), isFalse);
      expect(host.scroll.offset, outerOffset);
      await _tap(tester, _byId('astrology-picker-cancel'));
      expect(host.results.single, isNull);
      expect(host.scroll.offset, outerOffset);
    });
  }

  _widgetTest('resizing and keyboard insets keep a narrow popup reachable',
      (tester) async {
    final host = await _mountHost(
      tester,
      textScale: 2,
      alignment: Alignment.bottomRight,
    );
    await _open(tester);
    tester.view
      ..physicalSize = const Size(220, 160)
      ..viewInsets = const FakeViewPadding(bottom: 48);
    await tester.pumpAndSettle();
    final rect = tester.getRect(_byId('astrology-date-time-picker'));
    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.top, greaterThanOrEqualTo(8));
    expect(rect.right, lessThanOrEqualTo(212));
    expect(rect.bottom, lessThanOrEqualTo(104));
    await _tap(tester, _byId('astrology-picker-apply'));
    expect(host.results, hasLength(1));
    expect(host.date, '2024-02-28');
    expect(host.time, '23:45:56');
  });
}

Matcher _formatError(String message) => throwsA(
      isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains(message),
      ),
    );

void _widgetTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(
    name,
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1000, 900);
      final semantics = tester.ensureSemantics();
      try {
        await body(tester);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        } finally {
          semantics.dispose();
          tester.view.reset();
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Finder _byId(String id) => find.byKey(ValueKey(id));
Finder get _calendar => _byId('astrology-picker-calendar');
Finder _inCalendar(String id) =>
    find.descendant(of: _calendar, matching: _byId(id));
Finder _year(int year) => _inCalendar('date_picker_year_$year').hitTestable();

/// A day of the month on screen: neither a neighbouring month's spill-over
/// nor a cell on the calendar's off-screen neighbouring pages.
Finder _day(int day) {
  final days = find.descendant(
    of: _calendar,
    matching: find.byType(TableCalendar),
  );
  final cells =
      find.descendant(of: days, matching: find.text('$day')).hitTestable();
  return day < 15 ? cells.first : cells.last;
}

void _expectMonth(String month, String year) {
  expect(
    find.descendant(
      of: _inCalendar('date_picker_month_button'),
      matching: find.text(month),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: _inCalendar('date_picker_year_button'),
      matching: find.text(year),
    ),
    findsOneWidget,
  );
}

TextEditingController _controller(WidgetTester tester, String part) =>
    tester.widget<TextField>(_byId('astrology-picker-$part')).controller!;

String _errorText(WidgetTester tester) =>
    tester.widget<Text>(_byId('astrology-picker-error')).data!;

SingleChildScrollView _popupScroll(WidgetTester tester) =>
    tester.widget<SingleChildScrollView>(
      find
          .descendant(
            of: _byId('astrology-date-time-picker'),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_byId('picker-test-anchor'));
  await tester.pumpAndSettle();
  expect(_byId('astrology-date-time-picker'), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Reveals the calendar rather than the day: revealing a day cell would
/// scroll the calendar's own month pages sideways.
Future<void> _tapDay(WidgetTester tester, int day) async {
  await tester.ensureVisible(_calendar);
  await tester.pumpAndSettle();
  await tester.tap(_day(day));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String part, String value) async {
  final field = _byId('astrology-picker-$part');
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

ThemeData _theme(Brightness brightness, bool paper) =>
    DesktopAppearance().getThemeData(
      paper
          ? AppTheme.builtins.firstWhere(
              (theme) => theme.themeName == BuiltInTheme.paper,
            )
          : AppTheme.fallback,
      brightness,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

Future<_PickerHostState> _mountHost(
  WidgetTester tester, {
  String date = '2024-02-28',
  String time = '23:45:56',
  DateTime? localNow,
  String timeZoneLabel = 'Birthplace · UTC +05:30',
  bool focusTime = false,
  ThemeData? theme,
  double textScale = 1,
  Alignment alignment = Alignment.topLeft,
  bool gateScroll = false,
  VoidCallback? onIntercept,
}) async {
  final hostKey = UniqueKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      themeAnimationDuration: Duration.zero,
      // A global gate/shortcut override reaches the new route too. The picker
      // must override those locally, not accidentally rely on a friendly host.
      builder: (context, navigator) => Focus(
        onKeyEvent: (_, event) {
          if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            onIntercept?.call();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Actions(
          actions: {
            DeleteCharacterIntent: CallbackAction<DeleteCharacterIntent>(
              onInvoke: (_) {
                onIntercept?.call();
                return null;
              },
            ),
          },
          child: ScrollConfiguration(
            behavior: gateScroll
                ? const _InactiveScrollBehavior()
                : const MaterialScrollBehavior(),
            child: navigator!,
          ),
        ),
      ),
      home: Theme(
        // Intentionally BELOW the navigator: this theme and card-local text
        // scale are only available to the popup if explicitly captured.
        data: theme ?? ThemeData(platform: TargetPlatform.windows),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: _PickerHost(
              key: hostKey,
              date: date,
              time: time,
              localNow: localNow ?? DateTime.utc(2024, 2, 28, 12, 34, 7),
              timeZoneLabel: timeZoneLabel,
              focusTime: focusTime,
              alignment: alignment,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.state<_PickerHostState>(find.byType(_PickerHost));
}

class _InactiveScrollBehavior extends MaterialScrollBehavior {
  const _InactiveScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const NeverScrollableScrollPhysics();
}

class _PickerHost extends StatefulWidget {
  const _PickerHost({
    super.key,
    required this.date,
    required this.time,
    required this.localNow,
    required this.timeZoneLabel,
    required this.focusTime,
    required this.alignment,
  });

  final String date;
  final String time;
  final DateTime localNow;
  final String timeZoneLabel;
  final bool focusTime;
  final Alignment alignment;

  @override
  State<_PickerHost> createState() => _PickerHostState();
}

class _PickerHostState extends State<_PickerHost> {
  final scroll = ScrollController(initialScrollOffset: 80);
  final results = <AstrologyDateTimeSelection?>[];
  late String date;
  late String time;

  @override
  void initState() {
    super.initState();
    date = widget.date;
    time = widget.time;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      body: SingleChildScrollView(
        controller: scroll,
        child: SizedBox(
          height: size.height + 400,
          child: Stack(
            children: [
              Positioned(
                left: 16 + (size.width - 180) * (widget.alignment.x + 1) / 2,
                top: 96 + (size.height - 76) * (widget.alignment.y + 1) / 2,
                child: SizedBox(
                  width: 148,
                  height: 44,
                  child: Builder(
                    builder: (anchor) => TextButton(
                      key: const ValueKey('picker-test-anchor'),
                      onPressed: () async {
                        final result = await showAstrologyDateTimePicker(
                          context: anchor,
                          date: date,
                          time: time,
                          localNow: widget.localNow,
                          timeZoneLabel: widget.timeZoneLabel,
                          focusTime: widget.focusTime,
                        );
                        if (!mounted) return;
                        setState(() {
                          results.add(result);
                          if (result != null) {
                            date = result.date;
                            time = result.time;
                          }
                        });
                      },
                      child: const Text(
                        'Open picker',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
