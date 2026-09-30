import 'dart:async';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_location.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_time.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_transit_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _kolkata = AstrologyPlace(
  name: 'Kolkata, India',
  latitude: 22.5726,
  longitude: 88.3639,
  timeZone: 'Asia/Kolkata',
);

const _london = AstrologyPlace(
  name: 'London, England, United Kingdom',
  latitude: 51.5072,
  longitude: -0.1276,
  timeZone: 'Europe/London',
);

const _device = AstrologyPlace(
  name: 'Current location',
  latitude: 51.5072,
  longitude: -0.1276,
  timeZone: 'Europe/London',
  isDeviceLocation: true,
);

final _now = DateTime.utc(2030, 6, 1, 12, 0, 5);

void main() {
  setUpAll(AstrologyTime.initialize);

  testWidgets('typed fields are a draft that only Apply commits',
      (tester) async {
    final host = await _pump(tester);
    expect(
      _text(tester, 'astrology-transit-status'),
      'Nothing applied yet. Press Now or enter a moment, then Apply.',
    );
    for (final part in ['date', 'time', 'place']) {
      expect(_controller(tester, part).text, isEmpty, reason: part);
    }
    expect(find.text('Transit date'), findsOneWidget);
    expect(find.text('Transit time · 24-hour'), findsOneWidget);
    expect(find.text('Transit place'), findsOneWidget);
    expect(find.text('Birthplace · Kolkata, India'), findsOneWidget);

    await tester.enterText(_id('astrology-transit-date'), '2031-03-04');
    await tester.enterText(_id('astrology-transit-time'), '06:30');
    await tester.pump();
    expect(host.applied, isEmpty);
    expect(
      _text(tester, 'astrology-transit-status'),
      startsWith('Not applied yet.'),
    );

    await tester.tap(_id('astrology-transit-apply'));
    await tester.pump();
    // 06:30 in Kolkata (UTC+05:30), never this computer's zone.
    expect(host.applied, [(DateTime.utc(2031, 3, 4, 1), null)]);
    expect(
      _text(tester, 'astrology-transit-status'),
      'Showing 2031-03-04 · 06:30:00 · UTC+05:30 · Kolkata',
    );
    expect(_controller(tester, 'date').text, '2031-03-04');
    expect(_controller(tester, 'time').text, '06:30:00');

    // Blank date and time follow the live moment; Enter applies too.
    await tester.enterText(_id('astrology-transit-date'), '');
    await tester.enterText(_id('astrology-transit-time'), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(host.applied.last, (null, null));
    expect(
      _text(tester, 'astrology-transit-status'),
      'Showing the current moment · Kolkata · updates every minute.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Now fills the current moment and place without applying',
      (tester) async {
    final located = Completer<AstrologyPlace>();
    final location = _Location(onCurrent: () => located.future);
    final host = await _pump(tester, location: location);

    await tester.tap(_id('astrology-transit-now'));
    await tester.pump();
    // At once: the current moment on the birthplace's clock.
    expect(_controller(tester, 'date').text, '2030-06-01');
    expect(_controller(tester, 'time').text, '17:30:05');
    expect(
      _text(tester, 'astrology-transit-status'),
      'Finding your current location…',
    );
    expect(location.forces, [true]);

    located.complete(_device);
    await tester.pump();
    await tester.pump();
    // The same instant, on the device place's clock (BST).
    expect(
      _controller(tester, 'place').text,
      'Current location · 51.51° N, 0.13° W',
    );
    expect(_controller(tester, 'date').text, '2030-06-01');
    expect(_controller(tester, 'time').text, '13:00:05');
    expect(host.applied, isEmpty, reason: 'Now never applies.');
    expect(
      _text(tester, 'astrology-transit-status'),
      startsWith('Not applied yet.'),
    );

    await tester.tap(_id('astrology-transit-apply'));
    await tester.pump();
    final (utc, place) = host.applied.single;
    expect(utc, _now);
    expect(place?.isDeviceLocation, isTrue);
    expect(place?.timeZone, 'Europe/London');
    expect(
      _text(tester, 'astrology-transit-status'),
      'Showing 2030-06-01 · 13:00:05 · UTC+01:00 · Current location',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Now keeps the birthplace when the location is unavailable',
      (tester) async {
    final location = _Location(
      onCurrent: () async => throw const FormatException('Denied.'),
    );
    final host = await _pump(tester, location: location);
    await tester.tap(_id('astrology-transit-now'));
    await tester.pump();
    await tester.pump();
    expect(_controller(tester, 'date').text, '2030-06-01');
    expect(_controller(tester, 'time').text, '17:30:05');
    expect(_controller(tester, 'place').text, isEmpty);
    expect(
      _text(tester, 'astrology-transit-notice'),
      contains('so Kolkata is kept'),
    );
    expect(host.applied, isEmpty);

    await tester.tap(_id('astrology-transit-apply'));
    await tester.pump();
    expect(host.applied, [(_now, null)]);
    expect(_id('astrology-transit-notice'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a place is chosen from suggestions before it applies',
      (tester) async {
    final location = _Location(results: const [_london]);
    final host = await _pump(tester, location: location);
    await tester.enterText(_id('astrology-transit-date'), '2031-03-04');
    await tester.enterText(_id('astrology-transit-time'), '06:30');
    await tester.enterText(_id('astrology-transit-place'), 'Lon');
    await tester.pump();
    // Typed text is a query, not a place.
    await tester.tap(_id('astrology-transit-apply'));
    await tester.pump();
    expect(
      _text(tester, 'astrology-transit-error'),
      contains('Choose a place from the suggestions'),
    );
    expect(host.applied, isEmpty);

    await tester.enterText(_id('astrology-transit-place'), 'London');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(location.queries, ['London']);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(
      _controller(tester, 'place').text,
      'London, England, United Kingdom',
    );
    expect(host.applied, isEmpty);

    await tester.tap(_id('astrology-transit-apply'));
    await tester.pump();
    // 06:30 in London, which keeps GMT until late March.
    expect(host.applied.single.$1, DateTime.utc(2031, 3, 4, 6, 30));
    expect(host.applied.single.$2, same(_london));
    expect(
      _text(tester, 'astrology-transit-status'),
      'Showing 2031-03-04 · 06:30:00 · UTC+00:00 · London',
    );

    // Clearing the place reads the same wall time at the birthplace.
    await tester.tap(_id('astrology-transit-clear-place'));
    await tester.pump();
    await tester.tap(_id('astrology-transit-apply'));
    await tester.pump();
    expect(host.applied.last, (DateTime.utc(2031, 3, 4, 1), null));
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid transit fields explain themselves and change nothing',
      (tester) async {
    final host = await _pump(tester);
    for (final (date, message) in [
      ('2031-02-30', 'does not exist'),
      ('04/03/2031', 'Use YYYY-MM-DD for the transit date.'),
      ('2400-01-01', '1800–2399'),
    ]) {
      await tester.enterText(_id('astrology-transit-date'), date);
      await tester.enterText(_id('astrology-transit-time'), '12:00');
      await tester.tap(_id('astrology-transit-apply'));
      await tester.pump();
      expect(_text(tester, 'astrology-transit-error'), contains(message));
    }
    expect(host.applied, isEmpty);
    // Editing clears the stale message.
    await tester.enterText(_id('astrology-transit-date'), '2031-02-28');
    await tester.pump();
    expect(_id('astrology-transit-error'), findsNothing);
  });

  testWidgets('the picker fills a transit draft; Apply commits it',
      (tester) async {
    final host = await _pump(tester);
    await tester.tap(_id('astrology-transit-pick-date'));
    await tester.pumpAndSettle();
    expect(find.text('Transit date and time'), findsOneWidget);
    expect(find.text('Birthplace time · Asia/Kolkata'), findsOneWidget);
    await tester.enterText(_id('astrology-picker-date'), '2032-05-06');
    await tester.enterText(_id('astrology-picker-time'), '07:08:09');
    await tester.pump();
    await tester.ensureVisible(_id('astrology-picker-apply'));
    await tester.tap(_id('astrology-picker-apply'));
    await tester.pumpAndSettle();
    expect(host.applied, isEmpty);
    expect(_controller(tester, 'date').text, '2032-05-06');
    expect(_controller(tester, 'time').text, '07:08:09');

    await tester.tap(_id('astrology-transit-apply'));
    await tester.pump();
    expect(host.applied, [(DateTime.utc(2032, 5, 6, 1, 38, 9), null)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an applied transit is shown; a disabled form is inert',
      (tester) async {
    final moment = DateTime.utc(2040, 1, 1, 18, 29);
    final host = await _pump(
      tester,
      utc: moment,
      place: _london,
      applied: true,
    );
    expect(_controller(tester, 'date').text, '2040-01-01');
    expect(_controller(tester, 'time').text, '18:29:00');
    expect(
      _controller(tester, 'place').text,
      'London, England, United Kingdom',
    );
    expect(
      _text(tester, 'astrology-transit-status'),
      'Showing 2040-01-01 · 18:29:00 · UTC+00:00 · London',
    );
    await _pump(
      tester,
      utc: moment,
      place: _london,
      applied: true,
      enabled: false,
    );
    for (final id in ['date', 'time', 'place']) {
      expect(
        tester.widget<TextField>(_id('astrology-transit-$id')).enabled,
        isFalse,
      );
    }
    for (final id in [
      'apply',
      'now',
      'pick-date',
      'pick-time',
      'clear-place',
    ]) {
      final button = tester.widget<ButtonStyleButton>(
        find
            .descendant(
              of: _id('astrology-transit-$id'),
              matching: find.bySubtype<ButtonStyleButton>(),
              matchRoot: true,
            )
            .first,
      );
      expect(button.onPressed, isNull, reason: id);
    }
    expect(host.applied, isEmpty);
  });
}

Finder _id(String id) => find.byKey(ValueKey(id));

String _text(WidgetTester tester, String id) =>
    tester.widget<Text>(_id(id)).data!;

TextEditingController _controller(WidgetTester tester, String part) =>
    tester.widget<TextField>(_id('astrology-transit-$part')).controller!;

Future<_HostState> _pump(
  WidgetTester tester, {
  DateTime? utc,
  AstrologyPlace? place,
  bool applied = false,
  bool enabled = true,
  _Location? location,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(1000, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 560,
            height: 420,
            child: _Host(
              utc: utc,
              place: place,
              applied: applied,
              enabled: enabled,
              location: location ?? _Location(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.state<_HostState>(find.byType(_Host));
}

/// Keeps the applied transit the way the dashboard does: outside the form.
class _Host extends StatefulWidget {
  const _Host({
    required this.utc,
    required this.place,
    required this.applied,
    required this.enabled,
    required this.location,
  });

  final DateTime? utc;
  final AstrologyPlace? place;
  final bool applied;
  final bool enabled;
  final _Location location;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final applied = <(DateTime?, AstrologyPlace?)>[];
  late DateTime? utc = widget.utc;
  late AstrologyPlace? place = widget.place;
  late bool isApplied = widget.applied;

  @override
  Widget build(BuildContext context) => AstrologyTransitForm(
        natal: AstrologyInput(
          utc: DateTime.utc(1990, 5, 15, 3, 50),
          place: _kolkata,
          // Birth-time manual offsets never apply to a transit moment.
          utcOffsetMinutes: 345,
        ),
        utc: utc,
        place: place,
        applied: isApplied,
        enabled: widget.enabled,
        clock: () => _now,
        locationService: widget.location,
        onApplied: (value, at) => setState(() {
          applied.add((value, at));
          utc = value;
          place = at;
          isApplied = true;
        }),
      );
}

/// No geolocator or network: the device place and suggestions are given.
class _Location implements AstrologyLocationService {
  _Location({this.onCurrent, this.results = const []});

  final Future<AstrologyPlace> Function()? onCurrent;
  final List<AstrologyPlace> results;
  final forces = <bool>[];
  final queries = <String>[];

  @override
  Future<AstrologyPlace> current({bool force = false}) {
    forces.add(force);
    return onCurrent?.call() ??
        Future.error(const FormatException('No location in tests.'));
  }

  @override
  Future<List<AstrologyPlace>> search(String query) async {
    queries.add(query);
    return results;
  }
}
