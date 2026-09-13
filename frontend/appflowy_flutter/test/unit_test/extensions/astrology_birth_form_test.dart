import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_birth_form.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_location.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/paper_theme.dart';
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
const _device = AstrologyPlace(
  name: 'Current location',
  latitude: 12.9715987123,
  longitude: 77.594566789,
  timeZone: 'Asia/Kolkata',
  isDeviceLocation: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('birth time and saving', () {
    testWidgets('an impossible date is blocked and the entries survive',
        (tester) async {
      final service = _FakeLocationService();
      final generated = <AstrologyInput>[];
      await _pumpForm(
        tester,
        service: service,
        onGenerate: (input) async => generated.add(input),
      );
      await _enter(tester, 'astrology-date', '1990-02-30');
      await _enter(tester, 'astrology-time', '12:34:56');
      expect(_nowSwitch(tester).value, isFalse);

      await _tap(tester, 'astrology-generate');

      expect(generated, isEmpty);
      expect(_message(tester, 'astrology-error'), contains('does not exist'));
      expect(_controller(tester, 'astrology-date').text, '1990-02-30');
      expect(_controller(tester, 'astrology-time').text, '12:34:56');
      expect(service.currentForces, isEmpty);
      expect(service.queries, isEmpty);

      await _enter(tester, 'astrology-date', '1990-02-28');
      await _tap(tester, 'astrology-generate');
      expect(generated.single.utc, DateTime.utc(1990, 2, 28, 12, 34, 56));
      expect(_byId('astrology-error'), findsNothing);
    });

    for (final invalid in [
      (id: 'astrology-date', value: '1990/05/15', error: 'YYYY-MM-DD'),
      (id: 'astrology-time', value: '24:00:00', error: 'does not exist'),
      (id: 'astrology-time', value: '12:00:60', error: 'does not exist'),
    ]) {
      testWidgets('rejects ${invalid.value} without clearing the field',
          (tester) async {
        final generated = <AstrologyInput>[];
        await _pumpForm(
          tester,
          service: _FakeLocationService(),
          onGenerate: (input) async => generated.add(input),
        );
        await _enter(tester, invalid.id, invalid.value);
        await _tap(tester, 'astrology-generate');
        expect(generated, isEmpty);
        expect(_message(tester, 'astrology-error'), contains(invalid.error));
        expect(_controller(tester, invalid.id).text, invalid.value);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('saving requires a trimmed name before requesting location',
        (tester) async {
      final service = _FakeLocationService();
      final saved = <AstrologyInput>[];
      await _pumpForm(
        tester,
        input: const AstrologyInput(),
        service: service,
        onSave: (input) async => saved.add(input),
      );
      await _enter(tester, 'astrology-name', '   ');
      await _tap(tester, 'astrology-save');

      expect(saved, isEmpty);
      expect(_message(tester, 'astrology-error'), contains('Enter a name'));
      expect(_controller(tester, 'astrology-name').text, '   ');
      expect(service.currentForces, isEmpty);
      expect(service.queries, isEmpty);
    });

    testWidgets('Generate keeps live UTC null and clock edits turn Now off',
        (tester) async {
      final generated = <AstrologyInput>[];
      await _pumpForm(
        tester,
        input: const AstrologyInput(place: _kolkata),
        service: _FakeLocationService(),
        onGenerate: (input) async => generated.add(input),
      );
      await _tap(tester, 'astrology-generate');
      expect(generated.single.utc, isNull);
      expect(generated.single.name, isEmpty);

      await _enter(tester, 'astrology-date', '2000-01-02');
      await _enter(tester, 'astrology-time', '23:45:06');
      expect(_nowSwitch(tester).value, isFalse);
      await _tap(tester, 'astrology-generate');
      expect(generated.last.utc, DateTime.utc(2000, 1, 2, 18, 15, 6));

      await _tap(tester, 'astrology-now');
      expect(_nowSwitch(tester).value, isTrue);
      await _tap(tester, 'astrology-generate');
      expect(generated, hasLength(3));
      expect(generated.last.utc, isNull);
    });

    testWidgets(
        'empty fixed date and time default to the actual current instant',
        (tester) async {
      final generated = <AstrologyInput>[];
      await _pumpForm(
        tester,
        input: const AstrologyInput(place: _kolkata),
        service: _FakeLocationService(),
        onGenerate: (input) async => generated.add(input),
      );
      await _tap(tester, 'astrology-now');
      expect(_nowSwitch(tester).value, isFalse);
      expect(_controller(tester, 'astrology-date').text, isEmpty);
      expect(_controller(tester, 'astrology-time').text, isEmpty);
      final before = DateTime.now().toUtc();
      await _tap(tester, 'astrology-generate');
      final after = DateTime.now().toUtc();

      final utc = generated.single.utc!;
      expect(utc.isUtc, isTrue);
      expect(utc.isBefore(before), isFalse);
      expect(utc.isAfter(after), isFalse);
    });

    testWidgets(
        'live Save freezes at the click and awaits success exactly once',
        (tester) async {
      final location = Completer<AstrologyPlace>();
      final completion = Completer<void>();
      final service = _FakeLocationService(onCurrent: (_) => location.future);
      final saved = <AstrologyInput>[];
      final generated = <AstrologyInput>[];
      const input = AstrologyInput(
        name: '  Named draft  ',
        utcOffsetMinutes: 330,
        ayanamsa: AstrologyAyanamsa.raman,
        trueNode: true,
        dashaYearDays: 360,
        style: IndianChartStyle.south,
      );
      Future<void> save(AstrologyInput value) async {
        saved.add(value);
        await completion.future;
      }

      await _pumpForm(
        tester,
        input: input,
        service: service,
        onGenerate: (input) async => generated.add(input),
        onSave: save,
      );
      final stalePress = _button(tester, 'astrology-save').onPressed!;
      final before = DateTime.now().toUtc();
      await _tap(tester, 'astrology-save');
      final afterClick = DateTime.now().toUtc();
      stalePress(); // A previously enabled callback must also reject duplicates.
      await tester.pump();
      expect(service.currentForces, [false]);
      expect(saved, isEmpty);
      expect(_button(tester, 'astrology-save').onPressed, isNull);
      expect(_button(tester, 'astrology-generate').onPressed, isNull);
      expect(
        tester.widget<TextField>(_byId('astrology-name')).enabled,
        isFalse,
      );
      expect(_byId('astrology-success'), findsNothing);

      // A parent echo with equivalent values cannot change the in-flight draft.
      await _pumpForm(
        tester,
        input: AstrologyInput.fromJson(input.toJson()),
        service: service,
        onGenerate: (input) async => generated.add(input),
        onSave: save,
      );
      await tester.pump(const Duration(seconds: 10));
      location.complete(_device);
      await tester.pump();
      await tester.pump();

      final frozen = saved.single;
      expect(frozen.utc!.isUtc, isTrue);
      expect(frozen.utc!.isBefore(before), isFalse);
      expect(frozen.utc!.isAfter(afterClick), isFalse);
      expect(
        frozen.toJson(),
        input
            .copyWith(
              name: 'Named draft',
              utc: frozen.utc,
              place: _device,
            )
            .toJson(),
      );
      expect(input.utc, isNull);
      expect(_controller(tester, 'astrology-name').text, '  Named draft  ');
      expect(_nowSwitch(tester).value, isTrue);
      expect(_byId('astrology-success'), findsNothing);
      stalePress();
      expect(saved, hasLength(1));

      completion.complete();
      await tester.pump();
      await tester.pump();
      expect(_message(tester, 'astrology-success'), 'Horoscope saved.');
      expect(_button(tester, 'astrology-save').onPressed, isNotNull);
      expect(generated, isEmpty);
      expect(service.queries, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'name-only Save preserves fixed UTC precision and every setting',
        (tester) async {
      // This instant is already disambiguated, despite its repeated local hour.
      final input = AstrologyInput(
        name: 'Original',
        utc: DateTime.utc(2024, 11, 3, 5, 30, 45, 123, 456),
        place: _newYork,
        ayanamsa: AstrologyAyanamsa.krishnamurti,
        trueNode: true,
        dashaYearDays: 365.25,
        style: IndianChartStyle.south,
      );
      final service = _FakeLocationService();
      final saved = <AstrologyInput>[];
      await _pumpForm(
        tester,
        input: input,
        service: service,
        onSave: (input) async => saved.add(input),
      );
      expect(_controller(tester, 'astrology-date').text, '2024-11-03');
      expect(_controller(tester, 'astrology-time').text, '01:30:45');
      await _enter(tester, 'astrology-name', '  Revised  ');
      await _tap(tester, 'astrology-save');

      expect(saved.single.toJson(), input.copyWith(name: 'Revised').toJson());
      expect(saved.single.place, same(input.place));
      expect(saved.single.utcOffsetMinutes, isNull);
      expect(service.currentForces, isEmpty);
      expect(service.queries, isEmpty);
    });

    testWidgets(
        'coordinate-only edits preserve a fixed instant without rounding',
        (tester) async {
      final saved = <AstrologyInput>[];
      final input = AstrologyInput(
        name: 'Fixed instant',
        utc: DateTime.utc(1990, 5, 15, 9, 12, 34, 567, 890),
        place: _london,
      );
      await _pumpForm(
        tester,
        input: input,
        service: _FakeLocationService(),
        onSave: (input) async => saved.add(input),
      );
      await _tap(tester, 'astrology-advanced');
      await _enter(tester, 'astrology-latitude', '52.123456789');
      await _tap(tester, 'astrology-save');

      expect(saved.single.utc, input.utc);
      expect(saved.single.place!.latitude, 52.123456789);
      expect(saved.single.place!.longitude, _london.longitude);
      expect(saved.single.place!.timeZone, _london.timeZone);
      expect(saved.single.utcOffsetMinutes, isNull);
    });

    for (final save in [false, true]) {
      testWidgets('${save ? 'Save' : 'Generate'} catches failure and can retry',
          (tester) async {
        var attempts = 0;
        Future<void> submit(AstrologyInput input) async {
          attempts++;
          if (attempts == 1) throw StateError('The request was rejected');
        }

        await _pumpForm(
          tester,
          input: const AstrologyInput(name: 'Keep this draft', place: _london),
          service: _FakeLocationService(),
          onGenerate: submit,
          onSave: submit,
        );
        final id = save ? 'astrology-save' : 'astrology-generate';
        await _tap(tester, id);
        expect(
          _message(tester, 'astrology-error'),
          contains('request was rejected'),
        );
        expect(_byId('astrology-success'), findsNothing);
        expect(_controller(tester, 'astrology-name').text, 'Keep this draft');
        expect(_controller(tester, 'astrology-place').text, _london.name);
        expect(_button(tester, id).onPressed, isNotNull);
        expect(tester.takeException(), isNull);

        await _tap(tester, id);
        expect(attempts, 2);
        expect(_byId('astrology-error'), findsNothing);
        expect(_byId('astrology-success'), findsOneWidget);
      });
    }

    testWidgets('Generate does not report success until its callback completes',
        (tester) async {
      final completion = Completer<void>();
      var calls = 0;
      await _pumpForm(
        tester,
        service: _FakeLocationService(),
        onGenerate: (_) async {
          calls++;
          await completion.future;
        },
      );
      final press = _button(tester, 'astrology-generate').onPressed!;
      press();
      press();
      await tester.pump();
      expect(calls, 1);
      expect(_byId('astrology-success'), findsNothing);
      expect(_button(tester, 'astrology-generate').onPressed, isNull);
      completion.complete();
      await tester.pump();
      await tester.pump();
      expect(_message(tester, 'astrology-success'), 'Horoscope generated.');
      expect(_byId('astrology-save'), findsNothing);
    });
  });

  group('manual details and DST validation', () {
    for (final invalid in [
      (id: 'astrology-latitude', value: 'NaN', error: 'finite latitude'),
      (id: 'astrology-longitude', value: 'Infinity', error: 'finite latitude'),
      (id: 'astrology-latitude', value: '90', error: 'Latitude must'),
      (id: 'astrology-longitude', value: '181', error: 'longitude'),
      (id: 'astrology-timezone', value: 'Mars/Olympus', error: 'IANA'),
      (id: 'astrology-utc-offset', value: '+05:60', error: 'UTC offset'),
      (id: 'astrology-utc-offset', value: '+14:01', error: 'UTC offset'),
      (id: 'astrology-utc-offset', value: 'NaN', error: 'UTC offset'),
    ]) {
      testWidgets('${invalid.id} rejects ${invalid.value} without losing it',
          (tester) async {
        final generated = <AstrologyInput>[];
        final service = _FakeLocationService();
        await _pumpForm(
          tester,
          service: service,
          onGenerate: (input) async => generated.add(input),
        );
        await _tap(tester, 'astrology-advanced');
        await _enter(tester, invalid.id, invalid.value);
        await _tap(tester, 'astrology-generate');

        expect(generated, isEmpty);
        expect(_message(tester, 'astrology-error'), contains(invalid.error));
        expect(_controller(tester, invalid.id).text, invalid.value);
        expect(service.currentForces, isEmpty);
        expect(service.queries, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a manual offset does not conceal an invalid nonempty zone',
        (tester) async {
      final generated = <AstrologyInput>[];
      await _pumpForm(
        tester,
        input: const AstrologyInput(place: _london, utcOffsetMinutes: 330),
        service: _FakeLocationService(),
        onGenerate: (input) async => generated.add(input),
      );
      await _tap(tester, 'astrology-advanced');
      await _enter(tester, 'astrology-timezone', 'Invalid/Zone');
      await _tap(tester, 'astrology-generate');
      expect(generated, isEmpty);
      expect(_message(tester, 'astrology-error'), contains('IANA'));
      expect(_controller(tester, 'astrology-timezone').text, 'Invalid/Zone');
      expect(_controller(tester, 'astrology-utc-offset').text, '+05:30');
    });

    testWidgets('an incoming nonfinite coordinate shows an editable error',
        (tester) async {
      await _pumpForm(
        tester,
        input: const AstrologyInput(
          place: AstrologyPlace(
            name: 'Invalid stored location',
            latitude: double.nan,
            longitude: 0,
            timeZone: 'Etc/UTC',
          ),
        ),
        service: _FakeLocationService(),
      );
      expect(tester.takeException(), isNull);
      expect(_controller(tester, 'astrology-latitude').text, 'NaN');
      expect(_message(tester, 'astrology-error'), contains('Latitude'));
      expect(
        tester.widget<TextField>(_byId('astrology-latitude')).enabled,
        isTrue,
      );
    });

    testWidgets('a DST gap is rejected rather than normalized', (tester) async {
      final generated = <AstrologyInput>[];
      await _pumpForm(
        tester,
        input: const AstrologyInput(place: _newYork),
        service: _FakeLocationService(),
        onGenerate: (input) async => generated.add(input),
      );
      await _enter(tester, 'astrology-date', '2024-03-10');
      await _enter(tester, 'astrology-time', '02:30:00');
      await _tap(tester, 'astrology-generate');
      expect(generated, isEmpty);
      expect(_message(tester, 'astrology-error'), contains('skipped'));
      expect(_controller(tester, 'astrology-date').text, '2024-03-10');
      expect(_controller(tester, 'astrology-time').text, '02:30:00');
    });

    testWidgets('a repeated local time needs an explicit UTC offset',
        (tester) async {
      final generated = <AstrologyInput>[];
      await _pumpForm(
        tester,
        input: const AstrologyInput(place: _newYork),
        service: _FakeLocationService(),
        onGenerate: (input) async => generated.add(input),
      );
      await _enter(tester, 'astrology-date', '2024-11-03');
      await _enter(tester, 'astrology-time', '01:30:00');
      await _tap(tester, 'astrology-generate');
      expect(generated, isEmpty);
      expect(_message(tester, 'astrology-error'), contains('occurred twice'));
      expect(_controller(tester, 'astrology-time').text, '01:30:00');

      await _tap(tester, 'astrology-advanced');
      await _enter(tester, 'astrology-utc-offset', '-04:00');
      await _tap(tester, 'astrology-generate');
      expect(generated.single.utc, DateTime.utc(2024, 11, 3, 5, 30));
      expect(generated.single.utcOffsetMinutes, -240);
      expect(_byId('astrology-error'), findsNothing);
    });

    testWidgets('manual coordinates and calculation choices reach the callback',
        (tester) async {
      final generated = <AstrologyInput>[];
      final service = _FakeLocationService();
      await _pumpForm(
        tester,
        service: service,
        onGenerate: (input) async => generated.add(input),
      );
      await _enter(tester, 'astrology-place', 'Manual birthplace');
      await _enter(tester, 'astrology-date', '1990-05-15');
      await _enter(tester, 'astrology-time', '12:34:56');
      await _tap(tester, 'astrology-advanced');
      await _enter(tester, 'astrology-latitude', '12.9715987123');
      await _enter(tester, 'astrology-longitude', '77.594566789');
      await _enter(tester, 'astrology-timezone', 'Asia/Kolkata');
      await _enter(tester, 'astrology-utc-offset', '+05:30');
      expect(
        _choice<AstrologyAyanamsa>(tester, 'astrology-ayanamsa')
            .items!
            .map((item) => item.value),
        AstrologyAyanamsa.values,
      );
      expect(
        _choice<double>(tester, 'astrology-dasha-year')
            .items!
            .map((item) => item.value),
        [365.25636, 365.25, 360.0],
      );
      expect(
        _choice<IndianChartStyle>(tester, 'astrology-chart-style')
            .items!
            .map((item) => item.value),
        IndianChartStyle.values,
      );
      await _changeChoice(
        tester,
        'astrology-ayanamsa',
        AstrologyAyanamsa.trueChitra,
      );
      await _changeChoice(tester, 'astrology-rahu', true);
      await _changeChoice(tester, 'astrology-dasha-year', 360.0);
      await _changeChoice(
        tester,
        'astrology-chart-style',
        IndianChartStyle.south,
      );
      await _tap(tester, 'astrology-generate');

      final value = generated.single;
      expect(value.utc, DateTime.utc(1990, 5, 15, 7, 4, 56));
      expect(value.place!.name, 'Manual birthplace');
      expect(value.place!.latitude, 12.9715987123);
      expect(value.place!.longitude, 77.594566789);
      expect(value.place!.timeZone, 'Asia/Kolkata');
      expect(value.place!.isDeviceLocation, isFalse);
      expect(value.utcOffsetMinutes, 330);
      expect(value.ayanamsa, AstrologyAyanamsa.trueChitra);
      expect(value.trueNode, isTrue);
      expect(value.dashaYearDays, 360);
      expect(value.style, IndianChartStyle.south);
      expect(service.currentForces, isEmpty);
      expect(service.queries, isEmpty);
    });
  });

  group('explicit location requests', () {
    testWidgets('typing is private; place-only suggestions debounce for 500ms',
        (tester) async {
      final service = _FakeLocationService(
        onSearch: (_) async => [_york, _newYork],
      );
      final generated = <AstrologyInput>[];
      final saved = <AstrologyInput>[];
      try {
        await _pumpForm(
          tester,
          input: const AstrologyInput(),
          service: service,
          onGenerate: (input) async => generated.add(input),
          onSave: (input) async => saved.add(input),
        );
        await _enter(tester, 'astrology-name', 'Private person');
        await _enter(tester, 'astrology-date', '1990-05-15');
        await _enter(tester, 'astrology-time', '12:34:56');
        await tester.pump(const Duration(seconds: 2));
        expect(service.queries, isEmpty);
        expect(service.currentForces, isEmpty);

        await _enter(tester, 'astrology-place', '  York  ');
        await tester.pump(const Duration(milliseconds: 499));
        expect(service.queries, isEmpty);
        expect(generated, isEmpty);
        expect(saved, isEmpty);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        await tester.pump();

        // No Search click: only the trimmed place query crosses the seam.
        expect(service.queries, ['York']);
        expect(service.currentForces, isEmpty);
        expect(find.text(_york.name), findsOneWidget);
        expect(find.text(_newYork.name), findsOneWidget);
        expect(_controller(tester, 'astrology-place').text, '  York  ');
        expect(
          find.textContaining('never names or birth dates'),
          findsOneWidget,
        );
        expect(generated, isEmpty);
        expect(saved, isEmpty);
        await _tap(tester, 'astrology-result-1');
        expect(_controller(tester, 'astrology-place').text, _newYork.name);
        expect(
          _message(tester, 'astrology-place-summary'),
          contains('40.71280'),
        );
        expect(
          _message(tester, 'astrology-place-summary'),
          contains('America/New_York'),
        );
        expect(_controller(tester, 'astrology-name').text, 'Private person');
        expect(_controller(tester, 'astrology-date').text, '1990-05-15');
        expect(_controller(tester, 'astrology-time').text, '12:34:56');
        expect(generated, isEmpty);
        expect(saved, isEmpty);
        await tester.pump(const Duration(seconds: 1));
        expect(service.queries, ['York']);
        await _tap(tester, 'astrology-generate');
        expect(generated.single.name, 'Private person');
        expect(generated.single.utc, DateTime.utc(1990, 5, 15, 16, 34, 56));
        expect(generated.single.place!.toJson(), _newYork.toJson());
        expect(generated.single.place, same(_newYork));
        expect(saved, isEmpty);
        expect(service.queries, ['York']);
        expect(service.currentForces, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    testWidgets('a typed place cannot silently reuse the previous coordinates',
        (tester) async {
      final service = _FakeLocationService();
      final generated = <AstrologyInput>[];
      await _pumpForm(
        tester,
        service: service,
        onGenerate: (input) async => generated.add(input),
      );
      await _enter(tester, 'astrology-place', 'A different city');
      await _tap(tester, 'astrology-generate');
      expect(generated, isEmpty);
      expect(_message(tester, 'astrology-error'), contains('Search result'));
      expect(_controller(tester, 'astrology-place').text, 'A different city');
      expect(service.queries, isEmpty);
      expect(service.currentForces, isEmpty);
    });

    testWidgets('a slow search and stale option cannot replace a newer query',
        (tester) async {
      final first = Completer<List<AstrologyPlace>>();
      final second = Completer<List<AstrologyPlace>>();
      final service = _FakeLocationService(
        onSearch: (query) => query == 'First' ? first.future : second.future,
      );
      try {
        await _pumpForm(tester, service: service);
        await _enter(tester, 'astrology-place', 'First');
        await _tap(tester, 'astrology-search');
        expect(_button(tester, 'astrology-search').onPressed, isNull);
        await _enter(tester, 'astrology-place', 'Second');
        await _tap(tester, 'astrology-search');
        second.complete([_newYork]);
        await tester.pump();
        await tester.pump();
        first.complete([_london]);
        await tester.pump();
        await tester.pump();

        expect(service.queries, ['First', 'Second']);
        expect(find.text(_newYork.name), findsOneWidget);
        expect(find.text(_london.name), findsNothing);
        expect(_controller(tester, 'astrology-place').text, 'Second');
        final staleOption = _button(tester, 'astrology-result-0').onPressed!;
        await _enter(tester, 'astrology-place', 'Third');
        staleOption();
        await tester.pump();
        expect(_controller(tester, 'astrology-place').text, 'Third');
        expect(_byId('astrology-result-0'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        // Third is still debouncing: cancel it before the test body returns.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });

    for (final fails in [false, true]) {
      testWidgets('${fails ? 'failed' : 'empty'} search offers manual fallback',
          (tester) async {
        final service = _FakeLocationService(
          onSearch: (_) async {
            if (fails) throw StateError('Offline');
            return [];
          },
        );
        final generated = <AstrologyInput>[];
        await _pumpForm(
          tester,
          input: const AstrologyInput(),
          service: service,
          onGenerate: (input) async => generated.add(input),
        );
        await _enter(tester, 'astrology-place', 'Unlisted birthplace');
        await _tap(tester, 'astrology-search');
        final message = _message(tester, 'astrology-search-message');
        expect(message, contains(fails ? 'failed' : 'No places'));
        expect(message, contains('Advanced'));
        expect(
          _controller(tester, 'astrology-place').text,
          'Unlisted birthplace',
        );
        await _tap(tester, 'astrology-place-manual');
        expect(_byId('astrology-place-manual'), findsNothing);
        expect(_byId('astrology-search-message'), findsNothing);
        expect(
          _controller(tester, 'astrology-place').text,
          'Unlisted birthplace',
        );
        await _enter(tester, 'astrology-latitude', '12.5');
        await _enter(tester, 'astrology-longitude', '77.5');
        await _enter(tester, 'astrology-utc-offset', '+05:30');
        await _tap(tester, 'astrology-generate');

        expect(generated.single.place!.name, 'Unlisted birthplace');
        expect(generated.single.place!.timeZone, isEmpty);
        expect(generated.single.utcOffsetMinutes, 330);
        expect(generated.single.utc, isNull);
        expect(service.currentForces, isEmpty);
        expect(service.queries, ['Unlisted birthplace']);
      });
    }

    testWidgets('Generate resolves an empty place without guessing a city',
        (tester) async {
      final service = _FakeLocationService();
      final generated = <AstrologyInput>[];
      await _pumpForm(
        tester,
        input: const AstrologyInput(),
        service: service,
        onGenerate: (input) async => generated.add(input),
      );
      expect(_controller(tester, 'astrology-place').text, isEmpty);
      expect(service.currentForces, isEmpty);
      await _tap(tester, 'astrology-generate');
      expect(service.currentForces, [false]);
      expect(generated.single.place!.toJson(), _device.toJson());
      expect(generated.single.place, same(_device));
      expect(generated.single.utc, isNull);
      expect(service.queries, isEmpty);
    });

    testWidgets('autolocation happens once and never submits a horoscope',
        (tester) async {
      final service = _FakeLocationService();
      final generated = <AstrologyInput>[];
      final saved = <AstrologyInput>[];
      Future<void> pump(AstrologyInput input) => _pumpForm(
            tester,
            input: input,
            service: service,
            autoLocate: true,
            onGenerate: (value) async => generated.add(value),
            onSave: (value) async => saved.add(value),
          );
      await pump(const AstrologyInput());
      expect(service.currentForces, [false]);
      expect(_controller(tester, 'astrology-place').text, _device.name);
      await _enter(tester, 'astrology-name', 'A dirty draft');
      await pump(AstrologyInput.fromJson(const {}));
      await tester.pump(const Duration(seconds: 2));

      expect(service.currentForces, [false]);
      expect(service.queries, isEmpty);
      expect(_controller(tester, 'astrology-name').text, 'A dirty draft');
      expect(_controller(tester, 'astrology-place').text, _device.name);
      expect(generated, isEmpty);
      expect(saved, isEmpty);
    });

    testWidgets(
        'permission failure is nonblocking and Current location forces retry',
        (tester) async {
      final service = _FakeLocationService(
        onCurrent: (force) async {
          if (!force) throw StateError('Location permission denied');
          return _device;
        },
      );
      await _pumpForm(
        tester,
        input: const AstrologyInput(),
        service: service,
        autoLocate: true,
      );
      expect(service.currentForces, [false]);
      expect(
        _message(tester, 'astrology-location-message'),
        contains('denied'),
      );
      expect(
        _message(tester, 'astrology-location-message'),
        contains('Advanced'),
      );
      expect(tester.widget<TextField>(_byId('astrology-name')).enabled, isTrue);
      expect(_controller(tester, 'astrology-place').text, isEmpty);
      await _tap(tester, 'astrology-current-location');
      expect(service.currentForces, [false, true]);
      expect(_controller(tester, 'astrology-place').text, _device.name);
      expect(_byId('astrology-location-message'), findsNothing);
      expect(_byId('astrology-success'), findsNothing);
    });

    testWidgets('late autolocation cannot overwrite a manual place draft',
        (tester) async {
      final location = Completer<AstrologyPlace>();
      final service = _FakeLocationService(onCurrent: (_) => location.future);
      try {
        await _pumpForm(
          tester,
          input: const AstrologyInput(),
          service: service,
          autoLocate: true,
        );
        expect(
          find.textContaining('Requesting device location'),
          findsOneWidget,
        );
        await _enter(tester, 'astrology-place', 'My birthplace');
        location.complete(_device);
        await tester.pump();
        await tester.pump();
        expect(_controller(tester, 'astrology-place').text, 'My birthplace');
        expect(_byId('astrology-success'), findsNothing);
        expect(service.currentForces, [false]);
        expect(service.queries, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  });

  group('draft lifecycle and editor safety', () {
    testWidgets(
        'equivalent input rebuilds keep dirty fields; a new fingerprint loads',
        (tester) async {
      final service = _FakeLocationService();
      final input = AstrologyInput(
        name: 'Stored',
        utc: DateTime.utc(1990, 2, 3, 4, 5, 6),
        place: _london,
      );
      await _pumpForm(tester, input: input, service: service);
      await _enter(tester, 'astrology-name', 'Draft name');
      await _enter(tester, 'astrology-date', '2001-0');
      final controller = _controller(tester, 'astrology-date');
      final editingValue = controller.value;
      await _pumpForm(
        tester,
        input: AstrologyInput.fromJson(input.toJson()),
        service: service,
        onSave: _ignoreInput,
        saveLabel: 'Create named horoscope',
      );
      expect(_controller(tester, 'astrology-date'), same(controller));
      expect(controller.value, editingValue);
      expect(_controller(tester, 'astrology-name').text, 'Draft name');

      await _pumpForm(
        tester,
        input: AstrologyInput(
          name: 'Different record',
          utc: DateTime.utc(2002, 4, 6, 7, 8, 9),
          place: _kolkata,
        ),
        service: service,
      );
      expect(_controller(tester, 'astrology-name').text, 'Different record');
      expect(_controller(tester, 'astrology-date').text, '2002-04-06');
      expect(_controller(tester, 'astrology-time').text, '12:38:09');
      expect(_controller(tester, 'astrology-place').text, _kolkata.name);
      expect(service.currentForces, isEmpty);
      expect(service.queries, isEmpty);
    });

    testWidgets(
      'Backspace and Ctrl+V beat editor ancestor shortcuts',
      (tester) async {
        var intercepted = 0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform,
            (call) async {
          if (call.method == 'Clipboard.getData') return {'text': ' pasted'};
          if (call.method == 'Clipboard.hasStrings') return {'value': true};
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await _pumpForm(
          tester,
          service: _FakeLocationService(),
          theme: _desktopTheme(),
          wrap: (child) => _claimEditingKeys(
            child,
            onIntercept: () => intercepted++,
          ),
        );
        await _enter(tester, 'astrology-name', 'abc');
        final controller = _controller(tester, 'astrology-name');
        controller.selection = const TextSelection.collapsed(offset: 3);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(controller.text, 'ab');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        try {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
          await tester.pump();
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
        await tester.pump();
        expect(controller.text, 'ab pasted');
        expect(intercepted, 0);
        await _tap(tester, 'astrology-advanced');
        expect(find.byType(TextEntryShortcuts), findsNWidgets(8));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets('a disabled template preview performs no IO or submissions',
        (tester) async {
      final service = _FakeLocationService();
      var submissions = 0;
      Future<void> submit(AstrologyInput input) async {
        submissions++;
      }

      await _pumpForm(
        tester,
        input: const AstrologyInput(name: 'Template'),
        service: service,
        autoLocate: true,
        enabled: false,
        onGenerate: submit,
        onSave: submit,
      );
      for (final id in [
        'astrology-search',
        'astrology-current-location',
        'astrology-generate',
        'astrology-save',
      ]) {
        expect(_button(tester, id).onPressed, isNull);
        await _tap(tester, id);
      }
      await tester.pump(const Duration(seconds: 5));
      expect(
        tester.widget<TextField>(_byId('astrology-name')).enabled,
        isFalse,
      );
      expect(_nowSwitch(tester).onChanged, isNull);
      expect(_controller(tester, 'astrology-place').text, isEmpty);
      expect(service.currentForces, isEmpty);
      expect(service.queries, isEmpty);
      expect(submissions, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('becoming disabled cancels submission awaiting a device place',
        (tester) async {
      final location = Completer<AstrologyPlace>();
      final service = _FakeLocationService(onCurrent: (_) => location.future);
      final saved = <AstrologyInput>[];
      Future<void> save(AstrologyInput input) async => saved.add(input);
      const input = AstrologyInput(name: 'Pending');
      await _pumpForm(tester, input: input, service: service, onSave: save);
      await _tap(tester, 'astrology-save');
      await _pumpForm(
        tester,
        input: input,
        service: service,
        enabled: false,
        onSave: save,
      );
      location.complete(_device);
      await tester.pump();
      await tester.pump();
      expect(saved, isEmpty);
      expect(service.currentForces, [false]);
      expect(_controller(tester, 'astrology-place').text, isEmpty);
      expect(_byId('astrology-success'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'pending searches and location requests safely outlive disposal',
        (tester) async {
      final location = Completer<AstrologyPlace>();
      final search = Completer<List<AstrologyPlace>>();
      final service = _FakeLocationService(
        onCurrent: (_) => location.future,
        onSearch: (_) => search.future,
      );
      await _pumpForm(
        tester,
        input: const AstrologyInput(),
        service: service,
        autoLocate: true,
      );
      await _enter(tester, 'astrology-place', 'York');
      await _tap(tester, 'astrology-search');
      await tester.pumpWidget(const SizedBox.shrink());
      location.complete(_device);
      search.complete([_york]);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Windows physical birth-field editing', () {
    for (final entry in const [
      (id: 'astrology-name', text: 'NameXY', deleted: 'Name', repeated: 'Nam'),
      (
        id: 'astrology-date',
        text: '1990-02-28',
        deleted: '1990-02-',
        repeated: '1990-02'
      ),
      (
        id: 'astrology-time',
        text: '12:34:56',
        deleted: '12:34:',
        repeated: '12:34'
      ),
      (
        id: 'astrology-place',
        text: 'LondonXY',
        deleted: 'London',
        repeated: 'Londo'
      ),
      (
        id: 'astrology-latitude',
        text: '51.5074',
        deleted: '51.50',
        repeated: '51.5'
      ),
      (
        id: 'astrology-longitude',
        text: '-0.1278',
        deleted: '-0.12',
        repeated: '-0.1'
      ),
      (
        id: 'astrology-timezone',
        text: 'Europe/London',
        deleted: 'Europe/Lond',
        repeated: 'Europe/Lon'
      ),
      (
        id: 'astrology-utc-offset',
        text: '+05:30',
        deleted: '+05:',
        repeated: '+05'
      ),
    ]) {
      testWidgets(
        '${entry.id} selected Backspace and repeat invoke its edit callback',
        (tester) async {
          final service = _FakeLocationService();
          final pageFocus = FocusNode();
          var intercepted = 0;
          addTearDown(pageFocus.dispose);
          await _pumpForm(
            tester,
            service: service,
            theme: _desktopTheme(),
            onGenerate: (_) async => throw StateError('Edit callback marker'),
            wrap: (child) => _claimEditingKeys(
              child,
              focusNode: pageFocus,
              onIntercept: () => intercepted++,
            ),
          );
          await _tap(tester, 'astrology-advanced');
          await _tap(tester, 'astrology-generate');
          expect(
            _message(tester, 'astrology-error'),
            contains('Edit callback marker'),
          );
          expect(_nowSwitch(tester).value, isTrue);

          await tester.ensureVisible(_byId(entry.id));
          await tester.pump();
          final field = tester.widget<TextField>(_byId(entry.id));
          final editable = _editable(tester, entry.id);
          expect(field.enabled, isTrue);
          expect(field.autofocus, isFalse);
          editable.focusNode.requestFocus();
          await tester.pump();
          expect(FocusManager.instance.primaryFocus, same(editable.focusNode));
          expect(
            editable.focusNode.context!
                .findAncestorStateOfType<EditableTextState>()!
                .widget
                .controller,
            same(field.controller),
          );
          final controller = field.controller!;
          // Seed only the controller, not onChanged or a test IME deletion.
          controller.value = TextEditingValue(
            text: entry.text,
            selection: TextSelection(
              baseOffset: entry.text.length - 2,
              extentOffset: entry.text.length,
            ),
          );
          expect(_byId('astrology-error'), findsOneWidget);
          await tester.sendKeyDownEvent(
            LogicalKeyboardKey.backspace,
            physicalKey: PhysicalKeyboardKey.backspace,
            platform: 'windows',
          );
          try {
            await tester.pump();
            expect(controller.text, entry.deleted);
            // Every field's onChanged clears feedback. A controller-only
            // substring workaround would leave this error visible.
            expect(_byId('astrology-error'), findsNothing);
            if (entry.id == 'astrology-date' || entry.id == 'astrology-time') {
              expect(_nowSwitch(tester).value, isFalse);
            }
            await tester.sendKeyRepeatEvent(
              LogicalKeyboardKey.backspace,
              physicalKey: PhysicalKeyboardKey.backspace,
              platform: 'windows',
            );
            await tester.pump();
            expect(controller.text, entry.repeated);
          } finally {
            await tester.sendKeyUpEvent(
              LogicalKeyboardKey.backspace,
              physicalKey: PhysicalKeyboardKey.backspace,
              platform: 'windows',
            );
          }
          await tester.pump();
          expect(
            controller.selection,
            TextSelection.collapsed(offset: entry.repeated.length),
          );
          expect(intercepted, 0);
          expect(FocusManager.instance.primaryFocus, same(editable.focusNode));
          if (entry.id == 'astrology-place') {
            expect(_controller(tester, 'astrology-latitude').text, isEmpty);
            expect(_controller(tester, 'astrology-longitude').text, isEmpty);
            expect(_controller(tester, 'astrology-timezone').text, isEmpty);
          }

          // The parent really does consume Backspace when a field isn't the
          // primary focus; the form must neither steal focus nor disable it.
          pageFocus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(intercepted, 1);
          expect(controller.text, entry.repeated);
          expect(service.queries, isEmpty);
          expect(service.currentForces, isEmpty);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    testWidgets(
      'submitting disables every field without acquiring ancestor focus',
      (tester) async {
        final completion = Completer<void>();
        await _pumpForm(
          tester,
          input: const AstrologyInput(name: 'Keep', place: _london),
          service: _FakeLocationService(),
          theme: _desktopTheme(),
          onGenerate: (_) => completion.future,
        );
        await _tap(tester, 'astrology-advanced');
        await _tap(tester, 'astrology-name');
        final focus = _editable(tester, 'astrology-name').focusNode;
        expect(FocusManager.instance.primaryFocus, same(focus));
        await _tap(tester, 'astrology-generate');
        try {
          for (final field
              in tester.widgetList<TextField>(find.byType(TextField))) {
            expect(field.enabled, isFalse);
            final editable = tester.widget<EditableText>(
              find.descendant(
                of: find.byKey(field.key!),
                matching: find.byType(EditableText),
              ),
            );
            final before = field.controller!.value;
            editable.focusNode.requestFocus();
            await tester.pump();
            expect(editable.focusNode.hasPrimaryFocus, isFalse);
            await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
            await tester.pump();
            expect(field.controller!.value, before);
          }
        } finally {
          completion.complete();
          await tester.pump();
          await tester.pump();
        }
        expect(
          tester.widget<TextField>(_byId('astrology-name')).enabled,
          isTrue,
        );
        await _tap(tester, 'astrology-name');
        _controller(tester, 'astrology-name').selection =
            const TextSelection.collapsed(offset: 4);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(_controller(tester, 'astrology-name').text, 'Kee');
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'narrow real card header drag preserves the draft and subsequent editing',
      (tester) async {
        const extensionId = 'birth-form-keyboard-test';
        late DashboardController dashboard;
        var dragStarts = 0;
        var dragEnds = 0;
        var intercepted = 0;
        var movement = Offset.zero;
        addTearDown(() => DashboardWidgetRegistry.unregisterAll(extensionId));
        await _pumpForm(
          tester,
          service: _FakeLocationService(),
          theme: _desktopTheme(paper: true),
          width: 280,
          height: 300,
          wrap: (form) {
            final definition = DashboardWidgetDefinition(
              type: extensionId,
              extensionId: extensionId,
              label: () => 'Birth form test',
              icon: Icons.edit,
              group: DashboardWidgetGroup.controls,
              builder: (_) => form,
            );
            DashboardWidgetRegistry.register(definition);
            final spec = definition.create().copyWith(title: 'Birth form card');
            dashboard = DashboardController(
              viewId: '',
              document: DashboardDocument.blank().addWidget(spec),
            );
            return _claimEditingKeys(
              AnimatedBuilder(
                animation: dashboard,
                builder: (context, _) => DashboardCard(
                  controller: dashboard,
                  spec: spec,
                  palette: DashboardPalette.of(context),
                  selected: dashboard.selectedWidgetId == spec.id,
                  dragging: false,
                  onDragStart: () {
                    dragStarts++;
                    dashboard.select(spec.id);
                  },
                  onDragUpdate: (delta, _) => movement += delta,
                  onDragEnd: () => dragEnds++,
                ),
              ),
              onIntercept: () => intercepted++,
            );
          },
        );
        final hitTestWarningWasFatal =
            WidgetController.hitTestWarningShouldBeFatal;
        try {
          WidgetController.hitTestWarningShouldBeFatal = true;
          await _tap(tester, 'astrology-name');
          final editable = _editable(tester, 'astrology-name');
          final controller = editable.controller;
          expect(FocusManager.instance.primaryFocus, same(editable.focusNode));
          controller.value = const TextEditingValue(
            text: 'DraftAB',
            selection: TextSelection.collapsed(offset: 7),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(controller.text, 'DraftA');

          await tester.dragFrom(
            tester.getTopLeft(find.byType(DashboardCard)) +
                const Offset(20, 16),
            const Offset(60, 0),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          expect(dragStarts, 1);
          expect(dragEnds, 1);
          expect(movement.dx, greaterThan(0));
          expect(_controller(tester, 'astrology-name'), same(controller));
          expect(controller.text, 'DraftA');

          // Settle pending caret/card animations before revealing the actual
          // editable in the form's own short, clipped viewport.
          await tester.pumpAndSettle();
          final name = find.descendant(
            of: _byId('astrology-name'),
            matching: find.byType(EditableText),
          );
          final scroll = tester
              .widget<SingleChildScrollView>(
                _byId('astrology-birth-scroll'),
              )
              .controller!;
          await scroll.position.ensureVisible(
            tester.state<EditableTextState>(name).renderEditable,
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .getRect(_byId('astrology-birth-scroll'))
                .contains(tester.getCenter(name)),
            isTrue,
          );
          expect(name.hitTestable(), findsOneWidget);
          await tester.tap(name, kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
          expect(FocusManager.instance.primaryFocus, same(editable.focusNode));
          await tester.sendKeyEvent(LogicalKeyboardKey.end);
          await tester.pump();
          expect(controller.selection.isCollapsed, isTrue);
          expect(controller.selection.baseOffset, 6);
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          await tester.pump();
          expect(controller.text, 'Draft');
          expect(intercepted, 0);
          expect(dashboard.document.widgetCount, 1);
          expect(tester.takeException(), isNull);
        } finally {
          WidgetController.hitTestWarningShouldBeFatal = hitTestWarningWasFatal;
          await tester.pumpWidget(const SizedBox.shrink());
          dashboard.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  });

  group('responsive surfaces', () {
    testWidgets(
      'no-scrollbar policy is limited to the form, not sibling scroll views',
      (tester) async {
        const sibling = ValueKey('birth-form-scrollbar-sibling');
        await _pumpForm(
          tester,
          service: _FakeLocationService(),
          theme: _desktopTheme(),
          wrap: (form) => Column(
            children: [
              Expanded(child: form),
              const SizedBox(
                key: sibling,
                height: 60,
                child: SingleChildScrollView(
                  primary: false,
                  child: SizedBox(height: 300, child: Text('Outside the form')),
                ),
              ),
            ],
          ),
        );
        final scrollbars =
            find.byWidgetPredicate((widget) => widget is RawScrollbar);
        expect(
          find.descendant(
            of: find.byType(AstrologyBirthForm),
            matching: scrollbars,
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: find.byKey(sibling), matching: scrollbars),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    for (final appearance in [
      (name: 'light', brightness: Brightness.light, paper: false),
      (name: 'dark', brightness: Brightness.dark, paper: false),
      (name: 'paper', brightness: Brightness.light, paper: true),
    ]) {
      testWidgets(
        '280px ${appearance.name} card scrolls without horizontal overflow',
        (tester) async {
          final service = _FakeLocationService();
          await _pumpForm(
            tester,
            input: const AstrologyInput(
                name: 'A named horoscope', place: _newYork),
            service: service,
            onSave: _ignoreInput,
            width: 280,
            height: 260,
            saveLabel:
                'Save this unusually long horoscope label without overflow',
            theme: _desktopTheme(
              brightness: appearance.brightness,
              paper: appearance.paper,
            ),
          );
          expect(tester.takeException(), isNull);
          await _tap(tester, 'astrology-advanced');
          expect(
            find.descendant(
              of: find.byType(AstrologyBirthForm),
              matching:
                  find.byWidgetPredicate((widget) => widget is RawScrollbar),
            ),
            findsNothing,
            reason: 'Only this form suppresses desktop automatic scrollbars.',
          );
          final surface = tester.getRect(_byId('astrology-birth-surface'));
          for (final field
              in tester.widgetList<TextField>(find.byType(TextField))) {
            final rect = tester.getRect(find.byKey(field.key!));
            expect(rect.left, greaterThanOrEqualTo(surface.left));
            expect(rect.right, lessThanOrEqualTo(surface.right));
          }
          final scroll = tester.widget<SingleChildScrollView>(
            _byId('astrology-birth-scroll'),
          );
          expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
          await _tap(tester, 'astrology-ayanamsa');
          await tester.pumpAndSettle();
          await tester.tap(find.text('KP (Krishnamurti)').last);
          await tester.pumpAndSettle();
          expect(
            _choice<AstrologyAyanamsa>(tester, 'astrology-ayanamsa').value,
            AstrologyAyanamsa.krishnamurti,
          );
          await _tap(tester, 'astrology-save');
          expect(_message(tester, 'astrology-success'), 'Horoscope saved.');
          expect(tester.takeException(), isNull);
          expect(service.currentForces, isEmpty);
          expect(service.queries, isEmpty);
          if (appearance.paper) {
            expect(
              tester.widget<Material>(_byId('astrology-birth-surface')).color,
              PaperTheme.editorPreviewBackground,
            );
            expect(
              tester
                  .widget<TextField>(_byId('astrology-name'))
                  .decoration!
                  .fillColor,
              PaperTheme.codeBlockBackground,
            );
            final style = _button(tester, 'astrology-generate').style!;
            expect(style.foregroundColor!.resolve({}), PaperTheme.accent);
            expect(
              style.backgroundColor!.resolve({}),
              PaperTheme.accent.withValues(alpha: 0.10),
            );
            expect(
              _choice<AstrologyAyanamsa>(tester, 'astrology-ayanamsa')
                  .dropdownColor,
              PaperTheme.editorPreviewBackground,
            );
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    testWidgets('a bounded dialog uses the same independently scrolling form',
        (tester) async {
      final saved = <AstrologyInput>[];
      await _pumpForm(
        tester,
        input: const AstrologyInput(name: 'Dialog horoscope', place: _london),
        service: _FakeLocationService(),
        onSave: (input) async => saved.add(input),
        width: 280,
        height: 240,
        inDialog: true,
      );
      await _tap(tester, 'astrology-advanced');
      await _tap(tester, 'astrology-save');
      expect(saved.single.name, 'Dialog horoscope');
      expect(_message(tester, 'astrology-success'), 'Horoscope saved.');
      expect(tester.takeException(), isNull);
    });
  });
}

Finder _byId(String id) => find.byKey(ValueKey(id));

EditableText _editable(WidgetTester tester, String id) =>
    tester.widget<EditableText>(
      find.descendant(
        of: _byId(id),
        matching: find.byType(EditableText),
      ),
    );

ThemeData _desktopTheme({
  Brightness brightness = Brightness.light,
  bool paper = false,
}) =>
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

Widget _claimEditingKeys(
  Widget child, {
  required VoidCallback onIntercept,
  FocusNode? focusNode,
}) =>
    Focus(
      focusNode: focusNode,
      onKeyEvent: (_, event) {
        if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
            {
              LogicalKeyboardKey.backspace,
              LogicalKeyboardKey.delete,
              LogicalKeyboardKey.keyV,
            }.contains(event.logicalKey)) {
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
          PasteTextIntent: CallbackAction<PasteTextIntent>(
            onInvoke: (_) {
              onIntercept();
              return null;
            },
          ),
        },
        child: child,
      ),
    );

TextEditingController _controller(WidgetTester tester, String id) =>
    tester.widget<TextField>(_byId(id)).controller!;

TextButton _button(WidgetTester tester, String id) =>
    tester.widget<TextButton>(_byId(id));

Switch _nowSwitch(WidgetTester tester) =>
    tester.widget<Switch>(_byId('astrology-now'));

String _message(WidgetTester tester, String id) =>
    tester.widget<Text>(_byId(id)).data!;

DropdownButton<T> _choice<T>(WidgetTester tester, String id) =>
    tester.widget<DropdownButton<T>>(_byId(id));

Future<void> _changeChoice<T>(WidgetTester tester, String id, T value) async {
  _choice<T>(tester, id).onChanged!(value);
  await tester.pump();
}

Future<void> _ignoreInput(AstrologyInput input) async {}

Future<void> _pumpForm(
  WidgetTester tester, {
  required _FakeLocationService service,
  AstrologyInput input = const AstrologyInput(place: _london),
  Future<void> Function(AstrologyInput) onGenerate = _ignoreInput,
  Future<void> Function(AstrologyInput)? onSave,
  String saveLabel = 'Save horoscope',
  bool enabled = true,
  bool autoLocate = false,
  double width = 760,
  double height = 520,
  bool inDialog = false,
  ThemeData? theme,
  Widget Function(Widget)? wrap,
}) async {
  final form = AstrologyBirthForm(
    input: input,
    onGenerate: onGenerate,
    onSave: onSave,
    saveLabel: saveLabel,
    enabled: enabled,
    autoLocate: autoLocate,
    locationService: service,
  );
  final host = SizedBox(
    width: width,
    height: height,
    child: wrap == null ? form : wrap(form),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? ThemeData(),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: Center(child: inDialog ? Dialog(child: host) : host),
      ),
    ),
  );
  // Never settle an unresolved request's indeterminate progress indicator.
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String id) async {
  final target = _byId(id);
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.pump();
}

Future<void> _enter(WidgetTester tester, String id, String value) async {
  final target = _byId(id);
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.enterText(target, value);
  await tester.pump();
}

/// No geolocation plugins or ephemeris are initialized by these widget tests.
class _FakeLocationService extends AstrologyLocationService {
  _FakeLocationService({this.onCurrent, this.onSearch})
      : super(geocoder: const _NoNetworkGeocoder());

  final Future<AstrologyPlace> Function(bool force)? onCurrent;
  final Future<List<AstrologyPlace>> Function(String query)? onSearch;
  final currentForces = <bool>[];
  final queries = <String>[];

  @override
  Future<AstrologyPlace> current({bool force = false}) async {
    currentForces.add(force);
    final handler = onCurrent;
    if (handler != null) return handler(force);
    return _device;
  }

  @override
  Future<List<AstrologyPlace>> search(String query) async {
    queries.add(query);
    final handler = onSearch;
    if (handler != null) return handler(query);
    return const [];
  }
}

class _NoNetworkGeocoder implements MapGeocoder {
  const _NoNetworkGeocoder();

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) =>
      throw StateError('Unexpected geocoder access in a birth form test.');

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) =>
      throw StateError('Unexpected geocoder access in a birth form test.');
}
