import 'dart:async';
import 'dart:ui' show PointerDeviceKind, SemanticsFlag;

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_birth_form.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_location.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_time.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _london = AstrologyPlace(
  name: 'London, England',
  latitude: 51.5074,
  longitude: -0.1278,
  timeZone: 'Europe/London',
);
const _york = AstrologyPlace(
  name: 'York, England',
  latitude: 53.959,
  longitude: -1.0815,
  timeZone: 'Europe/London',
);
const _newYork = AstrologyPlace(
  name: 'New York, United States',
  latitude: 40.7128,
  longitude: -74.006,
  timeZone: 'America/New_York',
);
const _kolkata = AstrologyPlace(
  name: 'Kolkata, India',
  latitude: 22.5726,
  longitude: 88.3639,
  timeZone: 'Asia/Kolkata',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('birth form calendar and clock integration', () {
    for (final opener in const [
      (id: 'astrology-date', focus: 'date'),
      (id: 'astrology-time', focus: 'time'),
      (id: 'astrology-pick-date', focus: 'date'),
      (id: 'astrology-pick-time', focus: 'time'),
    ]) {
      _formTest('${opener.id} opens one popup on its first mouse click',
          (tester, h) async {
        await h.mount(tester);
        final date = _controller(tester, 'astrology-date');
        final time = _controller(tester, 'astrology-time');
        for (final id in ['astrology-date', 'astrology-time']) {
          final field = tester.widget<TextField>(_id(id));
          expect(field.readOnly, isFalse);
          expect(field.enabled, isTrue);
          expect(field.onTap, isNotNull);
          expect(_editable(tester, id).focusNode.hasPrimaryFocus, isFalse);
        }

        await _openClock(tester, opener: opener.id);

        expect(
          find.byKey(
            const ValueKey('astrology-date-time-picker'),
            skipOffstage: false,
          ),
          findsOneWidget,
          reason: 'The field and its suffix must not push two routes.',
        );
        expect(
          _editable(tester, 'astrology-picker-${opener.focus}')
              .focusNode
              .hasPrimaryFocus,
          isTrue,
        );
        expect(_id('astrology-picker-calendar'), findsOneWidget);
        expect(find.text('Local time · Europe/London'), findsOneWidget);
        expect(_controller(tester, 'astrology-date'), same(date));
        expect(_controller(tester, 'astrology-time'), same(time));
        expect(date.text, isEmpty);
        expect(time.text, isEmpty);
        expect(_now(tester).value, isTrue);
        _expectNoSubmission(h);
        await _finishClock(tester, 'cancel');
        expect(date.text, isEmpty);
        expect(time.text, isEmpty);
        expect(h.service.queries, isEmpty);
      });
    }

    _formTest('calendar and seconds Apply preserves the other dirty fields',
        (tester, h) async {
      h.input = AstrologyInput(
        name: 'Stored name',
        utc: DateTime.utc(2024, 2, 28, 4, 5, 56, 123, 456),
        place: _kolkata,
      );
      await h.mount(tester);
      await _enter(tester, 'astrology-name', '  Private edited name  ');
      await _tap(tester, 'astrology-advanced');
      await _enter(tester, 'astrology-utc-offset', '+05:30');
      await _changeChoice(
        tester,
        'astrology-ayanamsa',
        AstrologyAyanamsa.raman,
      );
      await _changeChoice(tester, 'astrology-rahu', true);
      await _changeChoice(tester, 'astrology-dasha-year', 360.0);
      await _changeChoice(
        tester,
        'astrology-chart-style',
        IndianChartStyle.south,
      );
      final before = _draft(tester);
      expect(find.byType(TextEntryShortcuts), findsNWidgets(8));

      await _openClock(tester);
      await _tapFinder(
        tester,
        find
            .descendant(
              of: _id('astrology-picker-calendar'),
              matching: find.text('29'),
            )
            .hitTestable(),
      );
      await _chooseSecond(tester, 57);
      expect(_text(tester, 'astrology-picker-date'), '2024-02-29');
      expect(_text(tester, 'astrology-picker-time'), '09:35:57');
      expect(_draft(tester), before, reason: 'Browsing is an isolated draft.');
      _expectNoSubmission(h);

      await _finishClock(tester, 'apply');
      final expectedDraft = Map<String, Object?>.of(before)
        ..['astrology-date'] = '2024-02-29'
        ..['astrology-time'] = '09:35:57'
        ..['now'] = false;
      expect(_draft(tester), expectedDraft);
      expect(find.byType(TextEntryShortcuts), findsNWidgets(8));
      _expectNoSubmission(h);
      expect(_id('astrology-success'), findsNothing);

      final expected = AstrologyInput(
        name: 'Private edited name',
        utc: DateTime.utc(2024, 2, 29, 4, 5, 57),
        place: _kolkata,
        utcOffsetMinutes: 330,
        ayanamsa: AstrologyAyanamsa.raman,
        trueNode: true,
        dashaYearDays: 360,
        style: IndianChartStyle.south,
      );
      await _tap(tester, 'astrology-generate');
      expect(h.generated.single.toJson(), expected.toJson());
      expect(h.generated.single.place, same(_kolkata));
      expect(h.saved, isEmpty);
      await _tap(tester, 'astrology-save');
      expect(h.saved.single.toJson(), expected.toJson());
      expect(h.generated, hasLength(1));
      expect(h.service.queries, isEmpty);
    });

    for (final dismissal in [
      'cancel',
      'escape',
      'barrier',
      'unchanged apply',
    ]) {
      _formTest('$dismissal preserves blank fields and live Now',
          (tester, h) async {
        await h.mount(tester);
        final before = _draft(tester);
        await _openClock(tester);
        if (dismissal != 'unchanged apply') {
          await _tap(tester, 'astrology-picker-today');
          await _enter(tester, 'astrology-picker-time', '01:02:03');
          expect(_text(tester, 'astrology-picker-date'), isNotEmpty);
          expect(_draft(tester), before);
        }
        if (dismissal == 'escape') {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        } else if (dismissal == 'barrier') {
          await tester.tapAt(const Offset(2, 2), kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
        } else {
          await _finishClock(
            tester,
            dismissal == 'cancel' ? 'cancel' : 'apply',
          );
        }
        expect(_id('astrology-date-time-picker'), findsNothing);
        expect(_draft(tester), before);
        expect(_now(tester).value, isTrue);
        _expectNoSubmission(h);
        await _tap(tester, 'astrology-generate');
        expect(h.generated.single.utc, isNull);
        expect(h.saved, isEmpty);
        expect(h.service.queries, isEmpty);
      });
    }

    for (final occurrence in [
      (utcHour: 5, equivalentEdit: false),
      (utcHour: 6, equivalentEdit: true),
    ]) {
      _formTest(
          'unchanged ${occurrence.equivalentEdit ? 'equivalent ' : ''}Apply '
          'preserves DST occurrence ${occurrence.utcHour} and microseconds',
          (tester, h) async {
        h.input = AstrologyInput(
          name: 'Stored fold',
          utc: DateTime.utc(2024, 11, 3, occurrence.utcHour, 30, 45, 123, 456),
          place: _newYork,
          ayanamsa: AstrologyAyanamsa.krishnamurti,
          trueNode: true,
          dashaYearDays: 365.25,
          style: IndianChartStyle.south,
        );
        await h.mount(tester);
        await _enter(tester, 'astrology-name', '  Renamed fold  ');
        await _openClock(tester, opener: 'astrology-pick-time');
        expect(_text(tester, 'astrology-picker-time'), '01:30:45');
        if (occurrence.equivalentEdit) {
          await _enter(tester, 'astrology-picker-date', ' 2024-11-03 ');
          await _enter(tester, 'astrology-picker-time', '1:30:45');
        }
        await _finishClock(tester, 'apply');
        expect(_text(tester, 'astrology-date'), '2024-11-03');
        expect(_text(tester, 'astrology-time'), '01:30:45');
        expect(_now(tester).value, isFalse);
        _expectNoSubmission(h);

        await _tap(tester, 'astrology-generate');
        await _tap(tester, 'astrology-save');
        final expected = h.input.copyWith(name: 'Renamed fold');
        expect(h.generated.single.toJson(), expected.toJson());
        expect(h.saved.single.toJson(), expected.toJson());
        expect(h.saved.single.utc, h.input.utc);
        expect(h.saved.single.utcOffsetMinutes, isNull);
        expect(h.saved.single.place, same(_newYork));
        expect(_id('astrology-error'), findsNothing);
        expect(h.service.queries, isEmpty);
      });
    }

    for (final transition in [
      (
        name: 'spring gap',
        date: '2024-03-10',
        time: '02:30:45',
        error: 'skipped',
        offset: '-05:00',
        minutes: -300,
        utc: DateTime.utc(2024, 3, 10, 7, 30, 45),
      ),
      (
        name: 'autumn overlap, earlier occurrence',
        date: '2024-11-03',
        time: '01:30:45',
        error: 'occurred twice',
        offset: '-04:00',
        minutes: -240,
        utc: DateTime.utc(2024, 11, 3, 5, 30, 45),
      ),
      (
        name: 'autumn overlap, later occurrence',
        date: '2024-11-03',
        time: '01:30:45',
        error: 'occurred twice',
        offset: '-05:00',
        minutes: -300,
        utc: DateTime.utc(2024, 11, 3, 6, 30, 45),
      ),
    ]) {
      _formTest('picker ${transition.name} still requires Generate validation',
          (tester, h) async {
        h.input = const AstrologyInput(name: 'DST draft', place: _newYork);
        await h.mount(tester);
        await _openClock(tester);
        await _enter(tester, 'astrology-picker-date', transition.date);
        await _enter(tester, 'astrology-picker-time', transition.time);
        await _finishClock(tester, 'apply');
        expect(_now(tester).value, isFalse);
        expect(_text(tester, 'astrology-date'), transition.date);
        expect(_text(tester, 'astrology-time'), transition.time);
        expect(_id('astrology-error'), findsNothing);
        _expectNoSubmission(h);

        await _tap(tester, 'astrology-generate');
        expect(_message(tester, 'astrology-error'), contains(transition.error));
        _expectNoSubmission(h);
        expect(_text(tester, 'astrology-date'), transition.date);
        expect(_text(tester, 'astrology-time'), transition.time);
        await _tap(tester, 'astrology-advanced');
        await _enter(tester, 'astrology-utc-offset', transition.offset);
        await _tap(tester, 'astrology-generate');
        expect(h.generated.single.utc, transition.utc);
        expect(h.generated.single.utcOffsetMinutes, transition.minutes);
        expect(h.generated.single.place, same(_newYork));
        expect(h.saved, isEmpty);
        expect(_id('astrology-error'), findsNothing);
        expect(h.service.queries, isEmpty);
      });
    }

    for (final change in [
      'input fingerprint',
      'disabled',
      'unmounted',
      'time zone',
      'UTC offset',
      'date draft',
      'time draft',
    ]) {
      _formTest('an old picker cannot overwrite a changed $change',
          (tester, h) async {
        h.input = AstrologyInput(
          name: 'Initial record',
          utc: DateTime.utc(2000, 1, 2, 3, 4, 5, 123, 456),
          place: _london,
        );
        await h.mount(tester);
        await _tap(tester, 'astrology-advanced');
        await _openClock(tester);
        await _enter(tester, 'astrology-picker-date', '2001-02-03');
        await _enter(tester, 'astrology-picker-time', '14:15:16');

        switch (change) {
          case 'input fingerprint':
            h.change(() {
              // Clock/zone strings still match the popup's snapshot. Only
              // the input fingerprint can invalidate this old record's edit.
              h.input = h.input.copyWith(name: 'Replacement record');
            });
            break;
          case 'disabled':
            h.change(() => h.enabled = false);
            break;
          case 'unmounted':
            h.change(() => h.visible = false);
            break;
          case 'time zone':
            _replaceUnderlyingField(
              tester,
              'astrology-timezone',
              'Asia/Kolkata',
            );
            break;
          case 'UTC offset':
            _replaceUnderlyingField(tester, 'astrology-utc-offset', '+05:30');
            break;
          case 'date draft':
            _replaceUnderlyingField(tester, 'astrology-date', '2002-03-04');
            break;
          case 'time draft':
            _replaceUnderlyingField(tester, 'astrology-time', '06:07:08');
            break;
        }
        await _frames(tester);
        final newerDraft = h.visible ? _draft(tester) : null;
        // Keep the navigator alive even when the owning form is removed.
        expect(_id('astrology-date-time-picker'), findsOneWidget);
        await _finishClock(tester, 'apply');
        _expectNoSubmission(h);
        if (h.visible) {
          expect(_draft(tester), newerDraft);
        } else {
          expect(find.byType(AstrologyBirthForm), findsNothing);
        }
        h.change(() {
          h.enabled = true;
          h.visible = true;
        });
        await _frames(tester);
        // A retired popup must not leave the form's reentrancy guard stuck.
        await _openClock(tester, opener: 'astrology-pick-time');
        expect(
          _text(tester, 'astrology-picker-date'),
          _text(tester, 'astrology-date'),
        );
        expect(
          _text(tester, 'astrology-picker-time'),
          _text(tester, 'astrology-time'),
        );
        await _finishClock(tester, 'cancel');
        _expectNoSubmission(h);
        expect(h.service.queries, isEmpty);
        if (change == 'input fingerprint') {
          await _tap(tester, 'astrology-generate');
          expect(h.generated.single.toJson(), h.input.toJson());
          expect(h.saved, isEmpty);
        }
      });
    }

    _formTest('equivalent parent echo neither resets nor invalidates a picker',
        (tester, h) async {
      h.input = AstrologyInput(
        name: 'Stored',
        utc: DateTime.utc(2024, 2, 28, 12, 34, 56),
        place: _london,
      );
      await h.mount(tester);
      await _enter(tester, 'astrology-name', 'Dirty name');
      await _openClock(tester);
      await _enter(tester, 'astrology-picker-date', '2024-02-29');
      final date = _controller(tester, 'astrology-picker-date');
      h.change(() => h.input = AstrologyInput.fromJson(h.input.toJson()));
      await _frames(tester);
      expect(_controller(tester, 'astrology-picker-date'), same(date));
      expect(date.text, '2024-02-29');
      expect(_text(tester, 'astrology-name'), 'Dirty name');
      await _finishClock(tester, 'apply');
      expect(_text(tester, 'astrology-date'), '2024-02-29');
      _expectNoSubmission(h);
      await _tap(tester, 'astrology-generate');
      expect(h.generated.single.name, 'Dirty name');
      expect(h.generated.single.utc, DateTime.utc(2024, 2, 29, 12, 34, 56));
    });

    for (final manual in [false, true]) {
      _formTest(
          'Today is seeded from ${manual ? 'manual offset' : 'birthplace'}',
          (tester, h) async {
        h.input = AstrologyInput(
          place: _kolkata,
          utcOffsetMinutes: manual ? -240 : null,
        );
        await h.mount(tester);
        final before = AstrologyTime.localTime(h.input, DateTime.now().toUtc());
        await _openClock(tester);
        final after = AstrologyTime.localTime(h.input, DateTime.now().toUtc());
        final calendar = tester.widget<CalendarDatePicker>(
          _id('astrology-picker-calendar'),
        );
        expect(
          calendar.currentDate,
          isIn([DateUtils.dateOnly(before), DateUtils.dateOnly(after)]),
          reason: 'Allow a real midnight crossing, not the PC time zone.',
        );
        expect(
          find.text(
            manual
                ? 'Local time · UTC −04:00 (manual)'
                : 'Local time · Asia/Kolkata',
          ),
          findsOneWidget,
        );
        expect(_text(tester, 'astrology-picker-date'), isEmpty);
        expect(_text(tester, 'astrology-picker-time'), isEmpty);
        await _tap(tester, 'astrology-picker-today');
        expect(
          _text(tester, 'astrology-picker-date'),
          _dateLabel(calendar.currentDate),
        );
        expect(_text(tester, 'astrology-picker-time'), isEmpty);
        expect(_text(tester, 'astrology-date'), isEmpty);
        expect(_now(tester).value, isTrue);
        await _finishClock(tester, 'apply');
        expect(
          _text(tester, 'astrology-date'),
          _dateLabel(calendar.currentDate),
        );
        expect(_text(tester, 'astrology-time'), isEmpty);
        expect(_now(tester).value, isFalse);
        _expectNoSubmission(h);
        expect(h.service.queries, isEmpty);
      });
    }

    _formTest('disabled preview cannot open pickers, focus fields or start IO',
        (tester, h) async {
      h
        ..input = const AstrologyInput(name: 'Preview')
        ..enabled = false
        ..autoLocate = true;
      await h.mount(tester);
      for (final id in [
        'astrology-date',
        'astrology-time',
        'astrology-place',
      ]) {
        final field = tester.widget<TextField>(_id(id));
        expect(field.enabled, isFalse);
        expect(field.onTap, isNull);
        await _clickDisabled(tester, id);
        _editable(tester, id).focusNode.requestFocus();
        await _frames(tester);
        expect(_editable(tester, id).focusNode.hasPrimaryFocus, isFalse);
      }
      for (final id in ['astrology-pick-date', 'astrology-pick-time']) {
        expect(tester.widget<IconButton>(_id(id)).onPressed, isNull);
        await _clickDisabled(tester, id);
      }
      await tester.pump(const Duration(seconds: 2));
      expect(_id('astrology-date-time-picker'), findsNothing);
      expect(_id('astrology-place-dropdown'), findsNothing);
      expect(h.service.queries, isEmpty);
      _expectNoSubmission(h);
    });
  });

  group('birth form live place search', () {
    for (final explicit in ['Search', 'Enter']) {
      _formTest(
          '$explicit accepts two characters but automatic search needs three',
          (tester, h) async {
        h.service.onSearch = (_) async => [_york];
        await h.mount(tester);
        await _enter(tester, 'astrology-place', 'Y');
        await tester.pump(const Duration(seconds: 1));
        expect(h.service.queries, isEmpty);
        await _tap(tester, 'astrology-search');
        expect(h.service.queries, isEmpty);
        expect(
          _message(tester, 'astrology-search-message'),
          contains('at least two characters'),
        );

        await _enter(tester, 'astrology-place', '  Yo  ');
        await tester.pump(const Duration(seconds: 1));
        expect(h.service.queries, isEmpty);
        if (explicit == 'Search') {
          await _tap(tester, 'astrology-search');
        } else {
          expect(
            _editable(tester, 'astrology-place').focusNode.hasPrimaryFocus,
            isTrue,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _frames(tester);
        }
        expect(h.service.queries, ['Yo']);
        expect(_text(tester, 'astrology-place'), '  Yo  ');
        expect(_id('astrology-result-0'), findsOneWidget);
        _expectNoSubmission(h);
        await _tapResult(tester, 0);
        expect(_text(tester, 'astrology-place'), _york.name);
        await tester.pump(const Duration(seconds: 1));
        expect(
          h.service.queries,
          ['Yo'],
          reason: 'Choosing never re-searches.',
        );
        _expectNoSubmission(h);
      });
    }

    _formTest(
        'focusing or rebuilding a stored city is not permission to search',
        (tester, h) async {
      h.autoLocate = true;
      await h.mount(tester);
      await _tap(tester, 'astrology-place');
      expect(
        _editable(tester, 'astrology-place').focusNode.hasPrimaryFocus,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 2));
      h.change(() => h.input = AstrologyInput.fromJson(h.input.toJson()));
      await _frames(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(_text(tester, 'astrology-place'), _london.name);
      expect(_id('astrology-result-0'), findsNothing);
      expect(h.service.queries, isEmpty);
      _expectNoSubmission(h);
    });

    _formTest(
        'rapid user edits restart the full debounce and send only the last query',
        (tester, h) async {
      h.service.onSearch = (_) async => [_york];
      await h.mount(tester);
      await _enter(tester, 'astrology-name', 'Never transmit this name');
      await _enter(tester, 'astrology-date', '1990-05-15');
      await _enter(tester, 'astrology-time', '12:34:56');
      for (final query in ['Y', 'Yo', 'York']) {
        await _enter(tester, 'astrology-place', query);
        await tester.pump(const Duration(milliseconds: 250));
        expect(h.service.queries, isEmpty);
      }
      await _enter(tester, 'astrology-place', '  Yorkshire  ');
      await tester.pump(const Duration(milliseconds: 499));
      expect(h.service.queries, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await _frames(tester);
      expect(h.service.queries, ['Yorkshire']);
      expect(_text(tester, 'astrology-place'), '  Yorkshire  ');
      expect(_text(tester, 'astrology-name'), 'Never transmit this name');
      expect(_text(tester, 'astrology-date'), '1990-05-15');
      expect(_text(tester, 'astrology-time'), '12:34:56');
      expect(_id('astrology-result-0'), findsOneWidget);
      _expectNoSubmission(h);
    });

    for (final fails in [false, true]) {
      _formTest(
          'out-of-order ${fails ? 'failure' : 'results'} cannot win during a newer debounce',
          (tester, h) async {
        final first = Completer<List<AstrologyPlace>>();
        final second = Completer<List<AstrologyPlace>>();
        final third = Completer<List<AstrologyPlace>>();
        var yorkRequests = 0;
        h.service.onSearch = (query) {
          if (query == 'York') {
            yorkRequests++;
            return yorkRequests == 1 ? first.future : third.future;
          }
          if (query == 'New York') return second.future;
          throw StateError('Unexpected query $query');
        };
        await h.mount(tester);
        await _enter(tester, 'astrology-place', 'York');
        await tester.pump(const Duration(milliseconds: 500));
        await _frames(tester);
        expect(h.service.queries, ['York']);
        expect(_button(tester, 'astrology-search').onPressed, isNull);
        await _enter(tester, 'astrology-place', 'New York');
        await tester.pump(const Duration(milliseconds: 500));
        await _frames(tester);
        expect(h.service.queries, ['York', 'New York']);
        // Return to the original text before its first request resolves.
        // A query-string-only freshness guard would wrongly accept it.
        await _enter(tester, 'astrology-place', 'York');
        await tester.pump(const Duration(milliseconds: 250));

        second.complete([_newYork]);
        await _frames(tester);
        if (fails) {
          first.completeError(StateError('Obsolete search failure'));
        } else {
          first.complete([_york]);
        }
        await _frames(tester);
        expect(_id('astrology-result-0'), findsNothing);
        expect(find.text(_newYork.name), findsNothing);
        expect(find.text(_york.name), findsNothing);
        expect(
          _message(tester, 'astrology-search-message'),
          contains('Finding matching places'),
        );
        expect(_button(tester, 'astrology-search').onPressed, isNotNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(_text(tester, 'astrology-place'), 'York');
        await tester.pump(const Duration(milliseconds: 249));
        expect(h.service.queries, ['York', 'New York']);
        await tester.pump(const Duration(milliseconds: 1));
        await _frames(tester);
        expect(h.service.queries, ['York', 'New York', 'York']);
        third.complete([_york]);
        await _frames(tester);
        expect(find.text(_york.name), findsOneWidget);
        expect(find.text(_newYork.name), findsNothing);
        await _tapResult(tester, 0);
        expect(_text(tester, 'astrology-place'), _york.name);
        expect(
          _message(tester, 'astrology-place-summary'),
          contains('Europe/London'),
        );
        expect(h.service.queries, ['York', 'New York', 'York']);
        _expectNoSubmission(h);
      });
    }

    for (final inFlight in [false, true]) {
      for (final cancellation in _SearchCancellation.values) {
        _formTest(
            '${cancellation.name} cancels '
            '${inFlight ? 'an in-flight result' : 'before search IO'}',
            (tester, h) async {
          final response = Completer<List<AstrologyPlace>>();
          h.service.onSearch = (_) => response.future;
          await h.mount(tester);
          await _tap(tester, 'astrology-advanced');
          await _enter(tester, 'astrology-place', 'York');
          _expectNoCoordinates(tester);
          await tester.pump(Duration(milliseconds: inFlight ? 500 : 499));
          await _frames(tester);
          expect(h.service.queries, inFlight ? ['York'] : isEmpty);
          await _cancelSearch(tester, h, cancellation);
          if (inFlight) response.complete([_newYork]);
          await _frames(tester);
          await tester.pump(const Duration(seconds: 2));
          await _frames(tester);

          expect(h.service.queries, inFlight ? ['York'] : isEmpty);
          expect(_id('astrology-result-0'), findsNothing);
          expect(find.text(_newYork.name), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          _expectNoSubmission(h);
          if (cancellation == _SearchCancellation.dispose) {
            expect(find.byType(AstrologyBirthForm), findsNothing);
          } else {
            final expectedPlace = switch (cancellation) {
              _SearchCancellation.clear => '',
              _SearchCancellation.inputReplacement => _kolkata.name,
              _ => 'York',
            };
            expect(_text(tester, 'astrology-place'), expectedPlace);
            if (cancellation == _SearchCancellation.inputReplacement) {
              expect(_text(tester, 'astrology-timezone'), 'Asia/Kolkata');
              expect(_text(tester, 'astrology-latitude'), '22.5726');
            } else {
              _expectNoCoordinates(tester);
            }
            if (cancellation == _SearchCancellation.clear) {
              // Clear may leave the empty-query hint open, never old results.
              expect(
                _message(tester, 'astrology-search-message'),
                contains('at least 3 characters'),
              );
            } else {
              expect(_id('astrology-place-dropdown'), findsNothing);
            }
          }
          if (cancellation == _SearchCancellation.escape) {
            expect(
              _editable(tester, 'astrology-place').focusNode.hasPrimaryFocus,
              isTrue,
            );
          }
          if (cancellation == _SearchCancellation.tab ||
              cancellation == _SearchCancellation.focusLoss) {
            expect(
              _editable(tester, 'astrology-place').focusNode.hasFocus,
              isFalse,
            );
          }
        });
      }
    }

    for (final startsAfterEdit in [false, true]) {
      _formTest(
          'IME ${startsAfterEdit ? 'interrupts a debounce' : 'holds a query'} until same-text commit',
          (tester, h) async {
        h.service.onSearch = (_) async => [_york];
        await h.mount(tester);
        await _tap(tester, 'astrology-advanced');
        await _focusField(tester, 'astrology-place');
        if (startsAfterEdit) {
          await _enter(tester, 'astrology-place', 'York');
          await tester.pump(const Duration(milliseconds: 250));
        }
        const composing = TextEditingValue(
          text: 'York',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange(start: 0, end: 4),
        );
        tester.testTextInput.updateEditingValue(composing);
        await _frames(tester);
        _expectNoCoordinates(tester);
        await tester.pump(const Duration(seconds: 2));
        expect(h.service.queries, isEmpty);
        expect(_id('astrology-result-0'), findsNothing);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await _frames(tester);
        expect(h.service.queries, isEmpty);

        // Text and selection stay identical; only the composing range changes.
        tester.testTextInput.updateEditingValue(
          composing.copyWith(composing: TextRange.empty),
        );
        await _frames(tester);
        expect(_text(tester, 'astrology-place'), 'York');
        await tester.pump(const Duration(milliseconds: 499));
        expect(h.service.queries, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        await _frames(tester);
        expect(h.service.queries, ['York']);
        expect(find.text(_york.name), findsOneWidget);
        expect(_text(tester, 'astrology-place'), 'York');
        _expectNoCoordinates(tester);
        _expectNoSubmission(h);
      });
    }

    _formTest(
        'arrows highlight, Enter chooses, and native Backspace never generates',
        (tester, h) async {
      var intercepted = 0;
      h
        ..input = AstrologyInput(
          name: 'Private draft',
          utc: DateTime.utc(1990, 5, 15, 11, 34, 56),
          place: _london,
        )
        ..wrap = (form) => _claimBackspace(form, () => intercepted++);
      h.service.onSearch = (_) async => [_york, _newYork];
      await h.mount(tester);
      await _tap(tester, 'astrology-advanced');
      await _enter(tester, 'astrology-place', 'York');
      await tester.pump(const Duration(milliseconds: 500));
      await _frames(tester);
      final focus = _editable(tester, 'astrology-place').focusNode;
      for (final step in [
        (key: LogicalKeyboardKey.arrowDown, selected: 0),
        (key: LogicalKeyboardKey.arrowDown, selected: 1),
        (key: LogicalKeyboardKey.arrowDown, selected: 0),
        (key: LogicalKeyboardKey.arrowUp, selected: 1),
      ]) {
        await tester.sendKeyEvent(step.key);
        await _frames(tester);
        expect(FocusManager.instance.primaryFocus, same(focus));
        for (var index = 0; index < 2; index++) {
          expect(
            tester
                .getSemantics(_id('astrology-result-$index'))
                .getSemanticsData()
                .hasFlag(SemanticsFlag.isSelected),
            index == step.selected,
          );
        }
        expect(_text(tester, 'astrology-place'), 'York');
        _expectNoCoordinates(tester);
        _expectNoSubmission(h);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _frames(tester);
      expect(_text(tester, 'astrology-place'), _newYork.name);
      expect(_text(tester, 'astrology-timezone'), _newYork.timeZone);
      expect(_id('astrology-place-dropdown'), findsNothing);
      expect(FocusManager.instance.primaryFocus, same(focus));
      _expectNoSubmission(h);
      final place = _controller(tester, 'astrology-place');
      place.selection = TextSelection.collapsed(offset: place.text.length);
      await tester.sendKeyEvent(
        LogicalKeyboardKey.backspace,
        physicalKey: PhysicalKeyboardKey.backspace,
        platform: 'windows',
      );
      await _frames(tester);
      expect(place.text, _newYork.name.substring(0, _newYork.name.length - 1));
      _expectNoCoordinates(tester);
      expect(_text(tester, 'astrology-date'), '1990-05-15');
      expect(_text(tester, 'astrology-time'), '12:34:56');
      expect(_text(tester, 'astrology-name'), 'Private draft');
      expect(intercepted, 0);
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(h.service.queries, ['York']);
      _expectNoSubmission(h);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 1));
      expect(h.service.queries, ['York']);
    });

    _formTest('only a completed suggestion tap chooses and retains field focus',
        (tester, h) async {
      h.service.onSearch = (_) async => [_york, _newYork];
      await h.mount(tester);
      await _tap(tester, 'astrology-advanced');
      await _enter(tester, 'astrology-place', 'York');
      await tester.pump(const Duration(milliseconds: 500));
      await _frames(tester);
      final focus = _editable(tester, 'astrology-place').focusNode;
      final press = await tester.startGesture(
        tester.getCenter(_id('astrology-result-1').hitTestable()),
        kind: PointerDeviceKind.mouse,
      );
      try {
        await _frames(tester);
        expect(_text(tester, 'astrology-place'), 'York');
        _expectNoCoordinates(tester);
        expect(focus.hasPrimaryFocus, isTrue);
        expect(_id('astrology-result-1'), findsOneWidget);
        _expectNoSubmission(h);
        await press.up();
      } finally {
        await press.removePointer();
      }
      await _frames(tester);
      expect(_text(tester, 'astrology-place'), _newYork.name);
      expect(_text(tester, 'astrology-latitude'), _newYork.latitude.toString());
      expect(
        _text(tester, 'astrology-longitude'),
        _newYork.longitude.toString(),
      );
      expect(_text(tester, 'astrology-timezone'), _newYork.timeZone);
      expect(focus.hasPrimaryFocus, isTrue);
      expect(_id('astrology-place-dropdown'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(h.service.queries, ['York']);
      _expectNoSubmission(h);
    });

    _formTest('dragging a suggestion scrolls without choosing or losing focus',
        (tester, h) async {
      h.service.onSearch = (_) async => List.generate(
            12,
            (index) => AstrologyPlace(
              name: 'York match $index',
              latitude: _york.latitude,
              longitude: _york.longitude,
              timeZone: _york.timeZone,
            ),
          );
      await h.mount(tester);
      await _tap(tester, 'astrology-advanced');
      await _enter(tester, 'astrology-place', 'York');
      await tester.pump(const Duration(milliseconds: 500));
      await _frames(tester);
      final list = _id('astrology-place-suggestions-scroll');
      final scroll = tester.widget<SingleChildScrollView>(list).controller!;
      expect(scroll.position.maxScrollExtent, greaterThan(100));
      await tester.dragFrom(
        tester
            .getRect(_id('astrology-result-1'))
            .intersect(tester.getRect(list))
            .center,
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(_text(tester, 'astrology-place'), 'York');
      _expectNoCoordinates(tester);
      expect(
        _editable(tester, 'astrology-place').focusNode.hasPrimaryFocus,
        isTrue,
      );
      expect(_id('astrology-place-dropdown'), findsOneWidget);
      expect(h.service.queries, ['York']);
      _expectNoSubmission(h);
    });
  });

  group('birth picker surfaces and real dashboard card', () {
    for (final appearance in [
      (name: 'light', brightness: Brightness.light, paper: false),
      (name: 'dark', brightness: Brightness.dark, paper: false),
      (name: 'paper', brightness: Brightness.light, paper: true),
    ]) {
      _formTest(
          '${appearance.name} popups escape a short bounded form with its theme',
          (tester, h) async {
        h
          ..width = 280
          ..height = 260
          ..theme = _theme(appearance.brightness, appearance.paper);
        h.service.onSearch = (_) async => [_york, _newYork];
        await h.mount(tester);
        final palette =
            AstrologyPalette.of(tester.element(_id('astrology-date')));
        await _openClock(tester);
        final popup = _id('astrology-date-time-picker');
        final bounds = tester.getRect(popup);
        _expectOnScreen(bounds);
        expect(bounds.width, greaterThan(h.width));
        expect(tester.widget<Material>(popup).color, palette.raised);
        expect(
          Theme.of(tester.element(popup)).brightness,
          appearance.brightness,
        );
        for (final id in ['astrology-picker-date', 'astrology-picker-time']) {
          final field = tester.widget<TextField>(_id(id));
          expect(field.decoration!.fillColor, palette.control);
          final rect = tester.getRect(_id(id));
          expect(rect.left, greaterThanOrEqualTo(bounds.left));
          expect(rect.right, lessThanOrEqualTo(bounds.right));
        }
        expect(
          DatePickerTheme.of(tester.element(_id('astrology-picker-calendar')))
              .dayOverlayColor!
              .resolve({WidgetState.hovered}),
          palette.hover,
        );
        expect(
          find.descendant(of: popup, matching: find.byType(RawScrollbar)),
          findsNothing,
        );
        await _finishClock(tester, 'cancel');
        await _enter(tester, 'astrology-place', 'York');
        await tester.pump(const Duration(milliseconds: 500));
        await _frames(tester);
        final suggestions = _id('astrology-place-dropdown');
        _expectOnScreen(tester.getRect(suggestions));
        expect(tester.widget<Material>(suggestions).color, palette.raised);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await _frames(tester);
        expect(
          _button(tester, 'astrology-result-1')
              .style!
              .backgroundColor!
              .resolve({}),
          palette.selection,
        );
        final semantics =
            tester.getSemantics(_id('astrology-result-1')).getSemanticsData();
        expect(semantics.hasFlag(SemanticsFlag.isSelected), isTrue);
        expect(semantics.label, contains(_newYork.name));
        expect(
          find.descendant(of: suggestions, matching: find.byType(RawScrollbar)),
          findsNothing,
        );
        if (appearance.paper) {
          expect(
            tester.widget<Material>(suggestions).color,
            PaperTheme.popupBackground,
          );
          expect(palette.control.r, greaterThan(palette.control.b));
        }
        await _tapResult(tester, 1);
        expect(_text(tester, 'astrology-place'), _newYork.name);
        _expectNoSubmission(h);
      });
    }

    _formTest(
        'inactive real DashboardCard permits first-click popup and result selection',
        (tester, h) async {
      const extensionId = 'birth-picker-integration-test';
      DashboardController? dashboard;
      var dragStarts = 0;
      h
        ..width = 320
        ..height = 320
        ..theme = _theme(Brightness.light, true)
        ..wrap = (form) {
          final definition = DashboardWidgetDefinition(
            type: extensionId,
            extensionId: extensionId,
            label: () => 'Birth picker test',
            icon: Icons.calendar_month_rounded,
            group: DashboardWidgetGroup.controls,
            requiresScrollActivation: true,
            builder: (_) => form,
          );
          DashboardWidgetRegistry.register(definition);
          final spec = definition.create().copyWith(title: 'Birth details');
          final controller = DashboardController(
            viewId: '',
            document: DashboardDocument.blank().addWidget(spec),
          );
          dashboard = controller;
          return Builder(
            builder: (context) => DashboardCard(
              controller: controller,
              spec: spec,
              palette: DashboardPalette.of(context),
              selected: false,
              dragging: false,
              onDragStart: () => dragStarts++,
            ),
          );
        };
      h.service.onSearch = (_) async => [_york, _newYork];
      try {
        await h.mount(tester);
        expect(dashboard!.selectedWidgetId, isNull);
        expect(
          tester
              .widget<ScrollActivationRegion>(
                find.byType(ScrollActivationRegion),
              )
              .active,
          isFalse,
        );
        await _openClock(tester);
        expect(
          _editable(tester, 'astrology-picker-date').focusNode.hasPrimaryFocus,
          isTrue,
        );
        await _enter(tester, 'astrology-picker-date', '1990-05-15');
        await _enter(tester, 'astrology-picker-time', '12:34:56');
        await _finishClock(tester, 'apply');
        expect(_text(tester, 'astrology-date'), '1990-05-15');
        expect(_text(tester, 'astrology-time'), '12:34:56');
        expect(_now(tester).value, isFalse);
        _expectNoSubmission(h);

        dashboard!.select(null);
        await _frames(tester);
        expect(
          tester
              .widget<ScrollActivationRegion>(
                find.byType(ScrollActivationRegion),
              )
              .active,
          isFalse,
        );
        await _tap(tester, 'astrology-place');
        final focus = _editable(tester, 'astrology-place').focusNode;
        expect(focus.hasPrimaryFocus, isTrue);
        await _enter(tester, 'astrology-place', 'York');
        await tester.pump(const Duration(milliseconds: 500));
        await _frames(tester);
        final beforeDate = _text(tester, 'astrology-date');
        final beforeTime = _text(tester, 'astrology-time');
        expect(_id('astrology-result-1').hitTestable(), findsOneWidget);
        final press = await tester.startGesture(
          tester.getCenter(_id('astrology-result-1')),
          kind: PointerDeviceKind.mouse,
        );
        try {
          await _frames(tester);
          expect(_text(tester, 'astrology-place'), 'York');
          expect(focus.hasPrimaryFocus, isTrue);
          await press.up();
        } finally {
          await press.removePointer();
        }
        await _frames(tester);
        expect(_text(tester, 'astrology-place'), _newYork.name);
        expect(focus.hasPrimaryFocus, isTrue);
        expect(_text(tester, 'astrology-date'), beforeDate);
        expect(_text(tester, 'astrology-time'), beforeTime);
        expect(_id('astrology-place-dropdown'), findsNothing);
        expect(dragStarts, 0);
        expect(dashboard!.document.widgetCount, 1);
        expect(h.service.queries, ['York']);
        _expectNoSubmission(h);
        await _tap(tester, 'astrology-generate');
        expect(h.generated.single.utc, DateTime.utc(1990, 5, 15, 16, 34, 56));
        expect(h.generated.single.place, same(_newYork));
        expect(h.saved, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _frames(tester);
        dashboard?.dispose();
        DashboardWidgetRegistry.unregisterAll(extensionId);
      }
    });
  });
}

void _formTest(
  String name,
  Future<void> Function(WidgetTester, _FormHarness) body,
) {
  testWidgets(
    name,
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1000, 900);
      final semantics = tester.ensureSemantics();
      final h = _FormHarness();
      final previousHitTestPolicy =
          WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      try {
        await body(tester, h);
        expect(h.service.currentForces, isEmpty);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          // Timers, popup routes and semantics must die inside the test body,
          // including on a failed assertion with an armed place debounce.
          await tester.pumpWidget(const SizedBox.shrink());
          await _frames(tester);
        } finally {
          h.dispose();
          semantics.dispose();
          WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy;
          tester.view.reset();
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

class _FormHarness extends ChangeNotifier {
  AstrologyInput input = const AstrologyInput(
    name: 'Private draft',
    place: _london,
  );
  final service = _FakeLocationService();
  final generated = <AstrologyInput>[];
  final saved = <AstrologyInput>[];
  bool enabled = true;
  bool visible = true;
  bool autoLocate = false;
  double width = 760;
  double height = 520;
  ThemeData? theme;
  Widget Function(Widget)? wrap;

  void change(VoidCallback update) {
    update();
    notifyListeners();
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        themeAnimationDuration: Duration.zero,
        home: ListenableBuilder(
          listenable: this,
          builder: (context, _) {
            final form = AstrologyBirthForm(
              key: const ValueKey('birth-picker-integration-form'),
              input: input,
              enabled: enabled,
              autoLocate: autoLocate,
              locationService: service,
              onGenerate: (value) async => generated.add(value),
              onSave: (value) async => saved.add(value),
            );
            return Theme(
              // Below the navigator: routes must capture the form's theme.
              data: theme ?? _theme(Brightness.light, false),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: visible
                        ? (wrap == null ? form : wrap!(form))
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await _frames(tester);
  }
}

enum _SearchCancellation {
  escape,
  tab,
  focusLoss,
  clear,
  inputReplacement,
  disabled,
  dispose,
}

Future<void> _cancelSearch(
  WidgetTester tester,
  _FormHarness h,
  _SearchCancellation cancellation,
) async {
  switch (cancellation) {
    case _SearchCancellation.escape:
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      break;
    case _SearchCancellation.tab:
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      break;
    case _SearchCancellation.focusLoss:
      await _focusField(tester, 'astrology-name');
      break;
    case _SearchCancellation.clear:
      await _tap(tester, 'astrology-clear-place');
      break;
    case _SearchCancellation.inputReplacement:
      h.change(() {
        h.input = const AstrologyInput(name: 'Replacement', place: _kolkata);
      });
      break;
    case _SearchCancellation.disabled:
      h.change(() => h.enabled = false);
      break;
    case _SearchCancellation.dispose:
      h.change(() => h.visible = false);
      break;
  }
  await _frames(tester);
}

Finder _id(String value) => find.byKey(ValueKey(value));

TextEditingController _controller(WidgetTester tester, String id) =>
    tester.widget<TextField>(_id(id)).controller!;

String _text(WidgetTester tester, String id) => _controller(tester, id).text;

EditableText _editable(WidgetTester tester, String id) =>
    tester.widget<EditableText>(
      find.descendant(
        of: _id(id),
        matching: find.byType(EditableText),
      ),
    );

TextButton _button(WidgetTester tester, String id) =>
    tester.widget<TextButton>(_id(id));

String _message(WidgetTester tester, String id) =>
    tester.widget<Text>(_id(id)).data!;

Switch _now(WidgetTester tester) => tester.widget<Switch>(_id('astrology-now'));

DropdownButton<T> _choice<T>(WidgetTester tester, String id) =>
    tester.widget<DropdownButton<T>>(_id(id));

Future<void> _changeChoice<T>(WidgetTester tester, String id, T value) async {
  _choice<T>(tester, id).onChanged!(value);
  await _frames(tester);
}

void _expectNoSubmission(_FormHarness h) {
  expect(h.generated, isEmpty);
  expect(h.saved, isEmpty);
}

void _expectNoCoordinates(WidgetTester tester) {
  for (final id in [
    'astrology-latitude',
    'astrology-longitude',
    'astrology-timezone',
  ]) {
    expect(
      _text(tester, id),
      isEmpty,
      reason: 'A query is not a chosen place.',
    );
  }
}

Map<String, Object?> _draft(WidgetTester tester) {
  final values = <String, Object?>{
    'now': _now(tester).value,
    for (final id in [
      'astrology-name',
      'astrology-date',
      'astrology-time',
      'astrology-place',
      'astrology-latitude',
      'astrology-longitude',
      'astrology-timezone',
      'astrology-utc-offset',
    ])
      if (_id(id).evaluate().isNotEmpty) id: _text(tester, id),
  };
  if (_id('astrology-ayanamsa').evaluate().isNotEmpty) {
    values['ayanamsa'] =
        _choice<AstrologyAyanamsa>(tester, 'astrology-ayanamsa').value;
  }
  if (_id('astrology-rahu').evaluate().isNotEmpty) {
    values['trueNode'] = _choice<bool>(tester, 'astrology-rahu').value;
    values['yearDays'] = _choice<double>(tester, 'astrology-dasha-year').value;
    values['style'] =
        _choice<IndianChartStyle>(tester, 'astrology-chart-style').value;
  }
  return values;
}

// An asynchronous owner can replace draft text while the popup is modal.
// Exercise the real controller and edit callback, never private form State.
void _replaceUnderlyingField(WidgetTester tester, String id, String value) {
  final field = tester.widget<TextField>(_id(id));
  field.controller!.text = value;
  field.onChanged!(value);
}

Future<void> _openClock(
  WidgetTester tester, {
  String opener = 'astrology-date',
}) async {
  await _tap(tester, opener);
  // Opening the clock cancels place work, so there is no pending search here.
  await tester.pumpAndSettle();
  expect(_id('astrology-date-time-picker'), findsOneWidget);
}

Future<void> _finishClock(WidgetTester tester, String action) async {
  await _tap(tester, 'astrology-picker-$action');
  await tester.pumpAndSettle();
  expect(_id('astrology-date-time-picker'), findsNothing);
}

Future<void> _chooseSecond(WidgetTester tester, int second) async {
  final selected = _choice<int>(tester, 'astrology-picker-second').value ?? 0;
  await _tap(tester, 'astrology-picker-second');
  await tester.pumpAndSettle();
  // Allow absent lazy rows and exclude calendar dates behind the modal barrier.
  final option = find.text(second.toString().padLeft(2, '0')).hitTestable();
  final menuScrollables = find.byElementPredicate(
    (element) =>
        element.widget is Scrollable &&
        ModalRoute.of(element)?.isCurrent == true,
  );
  expect(menuScrollables, findsWidgets);
  await tester.scrollUntilVisible(
    option,
    second < selected ? -48 : 48,
    scrollable: menuScrollables.last,
    maxScrolls: 120,
  );
  await tester.pumpAndSettle();
  expect(option, findsOneWidget);
  await tester.tap(option, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

Future<void> _tapResult(WidgetTester tester, int index) async {
  // Already-visible overlay rows must not scroll any retained form ancestors.
  final row = _id('astrology-result-$index').hitTestable();
  expect(row, findsOneWidget);
  await tester.tap(row, kind: PointerDeviceKind.mouse);
  await _frames(tester);
}

Future<void> _tap(WidgetTester tester, String id) =>
    _tapFinder(tester, _id(id));

Future<void> _clickDisabled(WidgetTester tester, String id) async {
  await tester.ensureVisible(_id(id));
  await _frames(tester);
  // IgnorePointer can intentionally exclude a disabled control from the hit
  // path. Still click its screen position and assert that nothing activates.
  await tester.tapAt(tester.getCenter(_id(id)), kind: PointerDeviceKind.mouse);
  await _frames(tester);
}

Future<void> _tapFinder(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await _frames(tester);
  await tester.tap(target, kind: PointerDeviceKind.mouse);
  await _frames(tester);
}

Future<void> _focusField(WidgetTester tester, String id) async {
  await tester.ensureVisible(_id(id));
  await _frames(tester);
  // Native editing must not synthesize a date/time field's popup-opening tap.
  _editable(tester, id).focusNode.requestFocus();
  await _frames(tester);
}

Future<void> _enter(WidgetTester tester, String id, String text) async {
  await _focusField(tester, id);
  await tester.enterText(_id(id), text);
  await _frames(tester);
}

// Zero elapsed time is intentional: preserve exact 499ms/1ms debounce checks.
// Finite pumps also work while an unresolved search displays a busy spinner.
Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump();
  }
}

String _dateLabel(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void _expectOnScreen(Rect rect) {
  expect(rect.isEmpty, isFalse);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(1000));
  expect(rect.bottom, lessThanOrEqualTo(900));
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

Widget _claimBackspace(Widget child, VoidCallback onIntercept) => Focus(
      onKeyEvent: (_, event) {
        if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          onIntercept();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Actions(
        actions: {
          DeleteCharacterIntent: CallbackAction<DeleteCharacterIntent>(
            onInvoke: (_) {
              onIntercept();
              return null;
            },
          ),
        },
        child: child,
      ),
    );

/// All IO is replaced at the existing service seam, not inside form callbacks.
class _FakeLocationService extends AstrologyLocationService {
  _FakeLocationService() : super(geocoder: const _NoNetworkGeocoder());

  Future<List<AstrologyPlace>> Function(String query)? onSearch;
  final queries = <String>[];
  final currentForces = <bool>[];

  @override
  Future<List<AstrologyPlace>> search(String query) async {
    queries.add(query);
    final handler = onSearch;
    if (handler != null) return handler(query);
    return const [];
  }

  @override
  Future<AstrologyPlace> current({bool force = false}) async {
    currentForces.add(force);
    throw StateError('Unexpected device lookup in a birth picker test.');
  }
}

class _NoNetworkGeocoder implements MapGeocoder {
  const _NoNetworkGeocoder();

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) =>
      throw StateError('Unexpected reverse geocoding in a birth picker test.');

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) =>
      throw StateError('Unexpected geocoder IO in a birth picker test.');
}
