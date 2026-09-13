import 'dart:ui' as ui;

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_horoscope_library.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// In-memory saved dashboards only: no library/service, engine, asset loading,
// repository, network or filesystem. Expected civil times are literal fixtures,
// not values calculated with AstrologyTime, DateTime.now or the device zone.
const _kolkata = AstrologyPlace(
  name: 'Fixture east city',
  latitude: 22.57,
  longitude: 88.36,
  timeZone: 'Asia/Kolkata',
);
const _newYork = AstrologyPlace(
  name: 'Fixture west city',
  latitude: 40.71,
  longitude: -74.01,
  timeZone: 'America/New_York',
);
const _fields = ['name', 'date', 'time', 'place'];
const _headers = ['Name', 'Date of birth', 'Time of birth', 'Place of birth'];
const _surfaceKey = ValueKey('astrology-horoscopes-surface');
const _tableKey = ValueKey('astrology-horoscopes-table');
const _pixelsKey = ValueKey('astrology-horoscopes-pixels');
const _verticalKey = ValueKey('astrology-horoscopes-scroll');
const _horizontalKey = ValueKey('astrology-horoscopes-horizontal-scroll');
const _refreshKey = ValueKey('astrology-horoscopes-refresh');
const _countKey = ValueKey('astrology-horoscopes-count');
const _emptyKey = ValueKey('astrology-horoscopes-empty');
const _errorKey = ValueKey('astrology-horoscopes-error');
const _appearances = [
  (name: 'light', brightness: Brightness.light, paper: false),
  (name: 'dark', brightness: Brightness.dark, paper: false),
  (name: 'paper', brightness: Brightness.light, paper: true),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _tableTest('four headers and row order describe the supplied saved views',
      (tester) async {
    final people = [
      _person('zeta', name: 'Fixture Zeta'),
      _person('alpha', name: 'Fixture Alpha'),
    ];
    await _pumpTable(tester, people: people);

    final table = _dataTable(tester);
    expect(
      table.columns
          .map((column) => ((column.label as SizedBox).child as Text).data),
      orderedEquals(_headers),
    );
    for (final header in _headers) {
      expect(
        find.descendant(of: find.byKey(_tableKey), matching: find.text(header)),
        findsOneWidget,
      );
    }
    expect(
      table.rows.map((row) => row.key),
      orderedEquals([
        const ValueKey('astrology-horoscope-zeta'),
        const ValueKey('astrology-horoscope-alpha'),
      ]),
    );
    expect(_text(tester, _countKey), '2 saved horoscopes');
    expect(_fieldText(tester, 'zeta', 'name'), 'Fixture Zeta');
    expect(_fieldText(tester, 'alpha', 'name'), 'Fixture Alpha');
    expect(table.rows.every((row) => row.cells.length == 4), isTrue);
    _expectNoSelection(tester);
  });

  _tableTest('IANA birth offsets roll the saved date forwards and backwards',
      (tester) async {
    await _pumpTable(
      tester,
      people: [
        _person(
          'east',
          input: AstrologyInput(
            utc: DateTime.utc(2000, 1, 1, 20, 45, 30),
            place: _kolkata,
          ),
        ),
        _person(
          'west',
          input: AstrologyInput(
            utc: DateTime.utc(2000, 1, 1, 2, 15, 30),
            place: _newYork,
          ),
        ),
      ],
    );
    _expectBirth(
      tester,
      'east',
      date: '2000-01-02',
      time: '02:15:30',
      zone: 'UTC+05:30',
      place: 'Fixture east city',
    );
    _expectBirth(
      tester,
      'west',
      date: '1999-12-31',
      time: '21:15:30',
      zone: 'UTC−05:00',
      place: 'Fixture west city',
    );
  });

  _tableTest('saved seconds and fractional precision survive metadata decoding',
      (tester) async {
    const cases = [
      (id: 'whole', ms: 0, us: 0, time: '11:45:07'),
      (id: 'trimmed', ms: 120, us: 0, time: '11:45:07.12'),
      (id: 'tiny', ms: 0, us: 1, time: '11:45:07.000001'),
      (id: 'full', ms: 123, us: 456, time: '11:45:07.123456'),
    ];
    await _pumpTable(
      tester,
      people: [
        for (final sample in cases)
          _person(
            sample.id,
            input: AstrologyInput(
              utc: DateTime.utc(2000, 1, 2, 6, 15, 7, sample.ms, sample.us),
              place: _kolkata,
            ),
          ),
      ],
    );
    for (final sample in cases) {
      _expectBirth(
        tester,
        sample.id,
        date: '2000-01-02',
        time: sample.time,
        zone: 'UTC+05:30',
      );
    }
  });

  _tableTest('both occurrences of a DST fold keep their own saved UTC offset',
      (tester) async {
    await _pumpTable(
      tester,
      people: [
        _person(
          'first',
          input: AstrologyInput(
            utc: DateTime.utc(2024, 11, 3, 5, 30, 17, 123, 456),
            place: _newYork,
          ),
        ),
        _person(
          'second',
          input: AstrologyInput(
            utc: DateTime.utc(2024, 11, 3, 6, 30, 17, 123, 456),
            place: _newYork,
          ),
        ),
      ],
    );
    _expectBirth(
      tester,
      'first',
      date: '2024-11-03',
      time: '01:30:17.123456',
      zone: 'UTC−04:00',
    );
    _expectBirth(
      tester,
      'second',
      date: '2024-11-03',
      time: '01:30:17.123456',
      zone: 'UTC−05:00',
    );
  });

  _tableTest('historical IANA offsets retain seconds and the resulting date',
      (tester) async {
    await _pumpTable(
      tester,
      people: [
        _person(
          'historical',
          input: AstrologyInput(
            utc: DateTime.utc(1900, 1, 1, 23, 55, 42),
            place: const AstrologyPlace(
              name: 'Fixture historical city',
              latitude: 48.85,
              longitude: 2.35,
              timeZone: 'Europe/Paris',
            ),
          ),
        ),
      ],
    );
    _expectBirth(
      tester,
      'historical',
      date: '1900-01-02',
      time: '00:05:03',
      zone: 'UTC+00:09:21',
    );
  });

  _tableTest('manual offsets override conflicting and even invalid IANA zones',
      (tester) async {
    await _pumpTable(
      tester,
      people: [
        _person(
          'override',
          input: AstrologyInput(
            utc: DateTime.utc(2024, 7, 1, 23, 45, 9),
            place: _newYork,
            utcOffsetMinutes: 330,
          ),
        ),
        _person(
          'invalid-zone-override',
          input: AstrologyInput(
            utc: DateTime.utc(2024, 7, 1, 2, 15, 9),
            place: const AstrologyPlace(
              name: 'Fixture manually timed city',
              latitude: 0,
              longitude: 0,
              timeZone: 'Fixture/Not_A_Zone',
            ),
            utcOffsetMinutes: -210,
          ),
        ),
      ],
    );
    _expectBirth(
      tester,
      'override',
      date: '2024-07-02',
      time: '05:15:09',
      zone: 'UTC+05:30 (manual)',
    );
    _expectBirth(
      tester,
      'invalid-zone-override',
      date: '2024-06-30',
      time: '22:45:09',
      zone: 'UTC−03:30 (manual)',
      place: 'Fixture manually timed city',
    );
  });

  _tableTest('offset-only profiles, including zero, need no device birthplace',
      (tester) async {
    await _pumpTable(
      tester,
      people: [
        _person(
          'offset-only',
          input: AstrologyInput(
            utc: DateTime.utc(2000, 1, 1, 23, 30, 40),
            utcOffsetMinutes: 345,
          ),
        ),
        _person(
          'zero-offset',
          input: AstrologyInput(
            utc: DateTime.utc(2000, 1, 1, 23, 30, 40),
            utcOffsetMinutes: 0,
          ),
        ),
      ],
    );
    _expectBirth(
      tester,
      'offset-only',
      date: '2000-01-02',
      time: '05:15:40',
      zone: 'UTC+05:45 (manual)',
      place: 'Not saved',
    );
    _expectBirth(
      tester,
      'zero-offset',
      date: '2000-01-01',
      time: '23:30:40',
      zone: 'UTC+00:00 (manual)',
      place: 'Not saved',
    );
    // The common harness records and rejects even caught geolocator calls.
    expect(find.text('Unavailable'), findsNothing);
  });

  _tableTest('missing saved timezone is unavailable instead of the PC zone',
      (tester) async {
    final person = _person(
      'no-zone',
      input: AstrologyInput(
        utc: DateTime.utc(2000, 1, 2, 6, 15, 7),
      ),
    );
    final opened = <ViewPB>[];
    await _pumpTable(tester, people: [person], onOpen: opened.add);
    _expectBirth(
      tester,
      person.id,
      date: 'Unavailable',
      time: 'Unavailable',
      place: 'Not saved',
    );
    await _tap(tester, _field(person.id, 'name'));
    expect(opened, hasLength(1));
    expect(opened.single, same(person));
  });

  _tableTest('null UTC stays Not saved, with no live clock or location lookup',
      (tester) async {
    await _pumpTable(
      tester,
      people: [
        _person('live-place', input: const AstrologyInput(place: _kolkata)),
        _person('live-device', input: const AstrologyInput()),
      ],
    );
    for (var pass = 0; pass < 2; pass++) {
      _expectBirth(
        tester,
        'live-place',
        date: 'Not saved',
        time: 'Not saved',
        place: 'Fixture east city',
      );
      _expectBirth(
        tester,
        'live-device',
        date: 'Not saved',
        time: 'Not saved',
        place: 'Not saved',
      );
      if (pass == 0) await tester.pump(const Duration(minutes: 2));
    }
    expect(_text(tester, _countKey), '2 saved horoscopes');
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  _tableTest('invalid saved profiles still open and do not poison healthy rows',
      (tester) async {
    final healthy = _person('healthy');
    final invalid = [
      _person(
        'bad-year',
        input: AstrologyInput(
          utc: DateTime.utc(1799, 12, 31, 12),
          place: _kolkata,
        ),
      ),
      _person(
        'bad-offset',
        input: AstrologyInput(
          utc: DateTime.utc(2000, 1, 2, 6),
          place: _kolkata,
          utcOffsetMinutes: 841,
        ),
      ),
      _person(
        'bad-zone',
        input: AstrologyInput(
          utc: DateTime.utc(2000, 1, 2, 6),
          place: const AstrologyPlace(
            name: 'Fixture unknown zone',
            latitude: 0,
            longitude: 0,
            timeZone: 'Fixture/Not_A_Zone',
          ),
        ),
      ),
      _person(
        'bad-place',
        input: AstrologyInput(
          utc: DateTime.utc(2000, 1, 2, 6),
          place: const AstrologyPlace(
            name: 'Fixture invalid coordinates',
            latitude: 95,
            longitude: 0,
            timeZone: 'Etc/UTC',
          ),
        ),
      ),
    ];
    final opened = <ViewPB>[];
    await _pumpTable(
      tester,
      people: [healthy, ...invalid],
      onOpen: opened.add,
    );
    for (final person in invalid) {
      _expectBirth(tester, person.id, date: 'Unavailable', time: 'Unavailable');
      expect(_fieldText(tester, person.id, 'name'), person.name);
      final before = opened.length;
      await _tap(tester, _field(person.id, 'date'));
      expect(opened, hasLength(before + 1));
      expect(opened.last, same(person));
      _expectBirth(
        tester,
        healthy.id,
        date: '2000-01-02',
        time: '11:45:07',
        zone: 'UTC+05:30',
        place: 'Fixture east city',
      );
    }
    await _tap(tester, _field(healthy.id, 'name'));
    expect(opened, hasLength(5));
    expect(opened.last, same(healthy));
    expect(_text(tester, _countKey), '5 saved horoscopes');
    expect(find.byKey(_errorKey), findsNothing);
    _expectNoSelection(tester);
  });

  _tableTest('the sidebar view name wins over the saved birth profile name',
      (tester) async {
    final person = _person(
      'renamed',
      name: 'Fixture sidebar rename',
      input: _birth(name: 'Fixture old profile name'),
    );
    final opened = <ViewPB>[];
    await _pumpTable(tester, people: [person], onOpen: opened.add);
    expect(_fieldText(tester, person.id, 'name'), 'Fixture sidebar rename');
    expect(find.text('Fixture old profile name'), findsNothing);
    final tooltip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: _field(person.id, 'name'),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tooltip.message, 'Open Fixture sidebar rename dashboard');
    await _tap(tester, _field(person.id, 'name'));
    expect(opened.single, same(person));
  });

  _tableTest(
      'blank view names fall back to the profile and then Unnamed horoscope',
      (tester) async {
    final people = [
      _person(
        'profile-name',
        name: ' \t ',
        input: _birth(name: 'Fixture profile fallback'),
      ),
      _person('unnamed', name: '', input: _birth(name: '   ')),
    ];
    final opened = <ViewPB>[];
    await _pumpTable(tester, people: people, onOpen: opened.add);
    expect(
      _fieldText(tester, 'profile-name', 'name'),
      'Fixture profile fallback',
    );
    expect(_fieldText(tester, 'unnamed', 'name'), 'Unnamed horoscope');
    for (final person in people) {
      await _tap(tester, _field(person.id, 'name'));
      expect(opened.last, same(person));
    }
    expect(opened, hasLength(2));
  });

  _tableTest(
      'every column and cell padding opens exactly its row, never selection',
      (tester) async {
    final people = [_person('first-row'), _person('second-row')];
    final opened = <ViewPB>[];
    await _pumpTable(tester, people: people, onOpen: opened.add);
    for (final person in people) {
      for (final field in _fields) {
        var before = opened.length;
        await _tap(tester, _field(person.id, field));
        expect(opened, hasLength(before + 1));
        expect(opened.last, same(person));
        _expectNoSelection(tester);

        final bounds = tester.getRect(_rowInk(person.id, field));
        final whitespace = Offset(bounds.left + 2, bounds.center.dy);
        final content =
            _row(tester, person.id).cells[_fields.indexOf(field)].child;
        expect(
          tester.getRect(find.byWidget(content)).contains(whitespace),
          isFalse,
          reason: 'Tap the table padding outside the cell child, not its text.',
        );
        before = opened.length;
        await tester.tapAt(whitespace, kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(opened, hasLength(before + 1));
        expect(opened.last, same(person));
        _expectNoSelection(tester);
      }
    }
    expect(opened, hasLength(16));
  });

  _tableTest('null onOpen and empty view IDs leave navigation inert',
      (tester) async {
    final valid = _person('enabled');
    final noId = _person('', name: 'Fixture without a saved ID');
    final people = [valid, noId];
    final opened = <ViewPB>[];
    await _pumpTable(tester, people: people);
    expect(
      _dataTable(tester).rows.every((row) => row.onSelectChanged == null),
      isTrue,
    );
    expect(find.byType(TableRowInkWell), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    for (final field in _fields) {
      await _tap(tester, _field(valid.id, field));
    }

    await _pumpTable(tester, people: people, onOpen: opened.add);
    expect(_row(tester, valid.id).onSelectChanged, isNotNull);
    expect(_row(tester, noId.id).onSelectChanged, isNull);
    for (final field in _fields) {
      await _tap(tester, _field(noId.id, field));
      expect(opened, isEmpty);
    }
    await _tap(tester, _field(valid.id, 'name'));
    expect(opened.single, same(valid));
    _expectNoSelection(tester);
  });

  _tableTest('Enter and Space activate the actual TableRowInkWell Focus',
      (tester) async {
    final people = [_person('keyboard-first'), _person('keyboard-second')];
    final opened = <ViewPB>[];
    await _pumpTable(tester, people: people, onOpen: opened.add);
    for (final person in people) {
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        final before = opened.length;
        final focus = _rowFocus(tester, person.id);
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(focus.hasPrimaryFocus, isTrue);
        expect(
          opened,
          hasLength(before),
          reason: 'Focus alone is not activation.',
        );
        final semantics =
            tester.getSemantics(_rowInk(person.id)).getSemanticsData();
        expect(semantics.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(semantics.hasFlag(ui.SemanticsFlag.isSelected), isFalse);
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
        expect(opened, hasLength(before + 1));
        expect(opened.last, same(person));
        _expectNoSelection(tester);
      }
    }
    expect(opened, hasLength(4));
  });

  for (final appearance in _appearances) {
    _tableTest(
        '${appearance.name}: table, text and row state fields use AstrologyPalette',
        (tester) async {
      final person = _person('theme');
      final opened = <ViewPB>[];
      await _pumpTable(
        tester,
        people: [person],
        onOpen: opened.add,
        onRefresh: _noop,
        error: 'Fixture refresh failure',
        brightness: appearance.brightness,
        paper: appearance.paper,
      );
      final context = tester.element(find.byKey(_surfaceKey));
      final palette = AstrologyPalette.of(context);
      final table = _dataTable(tester);
      expect(Theme.of(context).brightness, appearance.brightness);
      expect(PaperTheme.isEnabled(context), appearance.paper);
      expect(
        tester.widget<Material>(find.byKey(_surfaceKey)).color,
        palette.surface,
      );
      expect(table.headingRowColor!.resolve({}), palette.control);
      expect(table.dataRowColor!.resolve({}), Colors.transparent);
      expect(
        table.dataRowColor!.resolve({WidgetState.disabled}),
        Colors.transparent,
      );
      expect(table.dataRowColor!.resolve({WidgetState.hovered}), palette.hover);
      expect(
        table.dataRowColor!.resolve({WidgetState.focused}),
        palette.selection,
      );
      expect(
        table.dataRowColor!.resolve({WidgetState.hovered, WidgetState.focused}),
        palette.selection,
      );
      expect(table.headingTextStyle!.color, palette.muted);
      expect(table.dataTextStyle!.color, palette.ink);
      expect(
        table.border!.horizontalInside.color,
        palette.line.withValues(alpha: 0.45),
      );

      final rendered = tester.widget<Table>(
        find.descendant(
          of: find.byKey(_tableKey),
          matching: find.byType(Table),
        ),
      );
      expect(
        (rendered.children.first.decoration! as BoxDecoration).color,
        palette.control,
      );
      expect(
        (rendered.children.last.decoration! as BoxDecoration).color,
        Colors.transparent,
      );
      for (final field in _fields) {
        expect(
          DefaultTextStyle.of(tester.element(_field(person.id, field)))
              .style
              .color,
          palette.ink,
        );
        final ink = tester.widget<TableRowInkWell>(_rowInk(person.id, field));
        expect(ink.overlayColor!.resolve({WidgetState.hovered}), palette.hover);
        expect(
          ink.overlayColor!.resolve({WidgetState.focused}),
          palette.selection,
        );
      }
      expect(_zoneText(tester, person.id)!.style!.color, palette.muted);
      expect(
        tester.widget<Text>(find.byKey(_countKey)).style!.color,
        palette.muted,
      );
      expect(
        tester.widget<Text>(find.byKey(_errorKey)).style!.color,
        palette.danger,
      );
      final refreshStyle = _refreshButton(tester).style!;
      expect(refreshStyle.foregroundColor!.resolve({}), palette.accent);
      expect(
        refreshStyle.foregroundColor!.resolve({WidgetState.disabled}),
        palette.muted,
      );
      if (appearance.paper) {
        expect(palette.surface, PaperTheme.editorPreviewBackground);
        expect(palette.control, PaperTheme.controlBackground);
        expect(palette.surface, isNot(Colors.white));
      }

      // The unselected row is transparent so it cannot cover the Material ink.
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(_field(person.id, 'name')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(opened, isEmpty);
        _expectNoSelection(tester);
      } finally {
        await mouse.removePointer();
      }
      _expectNoRails(tester);
    });

    _tableTest(
      '${appearance.name}: rendered row ink responds to hover and keyboard focus',
      (tester) async {
        final manager = FocusManager.instance;
        final previousStrategy = manager.highlightStrategy;
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          // Set this before mounting InkResponse, and restore it even on failure.
          manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
          await mouse.addPointer(location: Offset.zero);
          final people = [
            _person('pixel-target', name: 'Fixture target'),
            _person('pixel-sibling', name: 'Fixture sibling'),
          ];
          final opened = <ViewPB>[];
          await _pumpTable(
            tester,
            people: people,
            onOpen: opened.add,
            brightness: appearance.brightness,
            paper: appearance.paper,
            capturePixels: true,
          );
          final palette = AstrologyPalette.of(
            tester.element(find.byKey(_surfaceKey)),
          );
          final inks = [
            for (final person in people)
              for (final field in _fields) _rowInk(person.id, field),
          ];
          final bounds = [for (final ink in inks) tester.getRect(ink)];
          final semantics = [
            for (final ink in inks) tester.getSemantics(ink).getSemanticsData(),
          ];
          final points = [
            for (final rect in bounds) Offset(rect.left + 5, rect.center.dy),
          ];
          for (var index = 0; index < points.length; index++) {
            final person = people[index ~/ _fields.length];
            final content =
                _row(tester, person.id).cells[index % _fields.length].child;
            expect(bounds[index].deflate(2).contains(points[index]), isTrue);
            expect(
              tester.getRect(find.byWidget(content)).overlaps(
                    Rect.fromCenter(center: points[index], width: 3, height: 3),
                  ),
              isFalse,
              reason: 'Sample row padding, not text, a divider or a Tooltip.',
            );
          }

          Future<List<Color>> expectInk(Color target, String phase) async {
            final colors = await _sampleInk(tester, points);
            for (var index = 0; index < inks.length; index++) {
              final reason = '$phase, cell $index';
              _expectPixelColor(
                colors[index],
                index < _fields.length ? target : palette.surface,
                reason: reason,
              );
              expect(tester.getRect(inks[index]), bounds[index],
                  reason: reason);
              final current =
                  tester.getSemantics(inks[index]).getSemanticsData();
              expect(current.rect, semantics[index].rect, reason: reason);
              expect(
                current.transform,
                semantics[index].transform,
                reason: reason,
              );
              expect(current.hasAction(ui.SemanticsAction.tap), isTrue);
              expect(current.hasFlag(ui.SemanticsFlag.isSelected), isFalse);
            }
            expect(opened, isEmpty,
                reason: '$phase alone must not open a row.');
            _expectNoSelection(tester);
            return colors;
          }

          // Focus is applied in a microtask, so its first pump may only schedule
          // the ink ticker. Settle the subsequent frames as well as its fade.
          // The mouse stays outside the cell's Tooltip child.
          Future<void> settleInk() async {
            await tester.pumpAndSettle(const Duration(milliseconds: 50));
          }

          final focus = _rowFocus(tester, people.first.id);
          expect(focus.hasFocus, isFalse);
          final normal = await expectInk(palette.surface, 'normal');

          await mouse.moveTo(points.first);
          await settleInk();
          expect(focus.hasFocus, isFalse);
          final hovered = await expectInk(palette.hover, 'hover');
          expect(
            hovered.take(_fields.length),
            isNot(orderedEquals(normal.take(_fields.length))),
            reason: 'Hover must visibly change the target row.',
          );
          expect(
            hovered.skip(_fields.length),
            orderedEquals(normal.skip(_fields.length)),
            reason: 'Hover must leave the sibling pixels unchanged.',
          );

          await mouse.moveTo(Offset.zero);
          await settleInk();
          expect(
            await expectInk(palette.surface, 'mouse leave'),
            orderedEquals(normal),
          );

          focus.requestFocus();
          await settleInk();
          expect(manager.highlightMode, FocusHighlightMode.traditional);
          expect(focus.hasPrimaryFocus, isTrue);
          expect(_rowFocus(tester, people.last.id).hasFocus, isFalse);
          final focused = await expectInk(palette.selection, 'keyboard focus');
          expect(
            focused.take(_fields.length),
            isNot(orderedEquals(normal.take(_fields.length))),
            reason: 'Keyboard focus must visibly change the target row.',
          );
          expect(
            focused.skip(_fields.length),
            orderedEquals(normal.skip(_fields.length)),
            reason: 'Keyboard focus must leave the sibling pixels unchanged.',
          );

          focus.unfocus();
          await settleInk();
          expect(focus.hasFocus, isFalse);
          expect(
            await expectInk(palette.surface, 'unfocus'),
            orderedEquals(normal),
          );
        } finally {
          manager.highlightStrategy = previousStrategy;
          await mouse.removePointer();
        }
      },
    );
  }

  _tableTest('280, 720 and 1360 widths at 1x and 2x have no overflow or rails',
      (tester) async {
    final people = List<ViewPB>.generate(
      12,
      (index) => _person(
        'layout-$index',
        name: 'Fixture $index with a deliberately long sidebar title',
        input: _birth().copyWith(
          place: const AstrologyPlace(
            name:
                'Fixture district, a deliberately long birthplace description',
            latitude: 22.57,
            longitude: 88.36,
            timeZone: 'Asia/Kolkata',
          ),
        ),
      ),
    );
    for (final width in [280.0, 720.0, 1360.0]) {
      for (final scale in [1.0, 2.0]) {
        final reason = '$width px, ${scale}x text';
        try {
          await _pumpTable(
            tester,
            people: people,
            onOpen: (_) {},
            onRefresh: _noop,
            size: Size(width, 280),
            scale: scale,
          );
          expect(tester.getSize(find.byKey(_surfaceKey)), Size(width, 280));
          expect(
            MediaQuery.textScalerOf(tester.element(find.byKey(_tableKey)))
                .scale(13),
            13 * scale,
          );
          final minimum = 720 * scale;
          final expectedWidth = width > minimum ? width : minimum;
          expect(
            tester.getSize(find.byKey(_tableKey)).width,
            closeTo(expectedWidth, 0.01),
            reason: reason,
          );
          final vertical = _controller(tester, _verticalKey);
          final horizontal = _controller(tester, _horizontalKey);
          expect(vertical.position.maxScrollExtent, greaterThan(0));
          expect(
            horizontal.position.maxScrollExtent,
            closeTo(expectedWidth - width, 0.01),
            reason: reason,
          );
          for (final field in _fields) {
            final text = tester.widget<Text>(_field(people.first.id, field));
            expect(text.maxLines, 2);
            expect(text.overflow, TextOverflow.ellipsis);
          }
          expect(_field(people.first.id, 'name').hitTestable(), findsOneWidget);
          _expectNoRails(tester);
          _expectHealthy(tester, reason: reason);

          horizontal.jumpTo(horizontal.position.maxScrollExtent);
          vertical.jumpTo(vertical.position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(
            _field(people.last.id, 'place').hitTestable(),
            findsOneWidget,
            reason: 'The final row and column remain reachable: $reason',
          );
          _expectNoRails(tester);
          _expectHealthy(tester, reason: reason);
        } finally {
          await _unmount(tester);
        }
      }
    }
  });

  _tableTest(
      'owned axes scroll independently, survive rebuild and dispose in flight',
      (tester) async {
    final primary = ScrollController();
    final people =
        List<ViewPB>.generate(12, (index) => _person('scroll-$index'));
    final opened = <ViewPB>[];
    try {
      await _pumpTable(
        tester,
        people: people,
        onOpen: opened.add,
        size: const Size(280, 240),
        primaryController: primary,
      );
      final vertical = _controller(tester, _verticalKey);
      final horizontal = _controller(tester, _horizontalKey);
      expect(vertical, isNot(same(horizontal)));
      expect(vertical, isNot(same(primary)));
      expect(horizontal, isNot(same(primary)));
      expect(primary.hasClients, isFalse);
      for (final entry in [
        (_verticalKey, Axis.vertical),
        (_horizontalKey, Axis.horizontal),
      ]) {
        final scroll =
            tester.widget<SingleChildScrollView>(find.byKey(entry.$1));
        expect(scroll.primary, isFalse);
        expect(scroll.scrollDirection, entry.$2);
      }
      final center = tester.getCenter(find.byKey(_surfaceKey));
      await tester.dragFrom(center, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(vertical.offset, greaterThan(0));
      expect(horizontal.offset, 0);
      final verticalOffset = vertical.offset;
      await tester.dragFrom(center, const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(horizontal.offset, greaterThan(0));
      expect(vertical.offset, closeTo(verticalOffset, 0.01));
      expect(opened, isEmpty, reason: 'A scroll drag must not open a row.');
      final horizontalOffset = horizontal.offset;

      await _pumpTable(
        tester,
        people: people,
        onOpen: opened.add,
        size: const Size(280, 240),
        primaryController: primary,
        loading: true,
      );
      expect(_controller(tester, _verticalKey), same(vertical));
      expect(_controller(tester, _horizontalKey), same(horizontal));
      expect(vertical.offset, closeTo(verticalOffset, 0.01));
      expect(horizontal.offset, closeTo(horizontalOffset, 0.01));
      _expectNoRails(tester);

      final movement = horizontal.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.linear,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await _unmount(tester);
      await movement;
      for (final controller in [vertical, horizontal]) {
        expect(controller.hasClients, isFalse);
        expect(() => controller.addListener(_noop), throwsFlutterError);
      }
      // The table did not claim or dispose its ancestor's controller.
      primary.addListener(_noop);
      primary.removeListener(_noop);
      expect(tester.binding.hasScheduledFrame, isFalse);
    } finally {
      await _unmount(tester);
      primary.dispose();
    }
  });

  _tableTest(
      'Refresh, loading and Retry respect callbacks without hiding saved rows',
      (tester) async {
    final person = _person('refresh');
    final opened = <ViewPB>[];
    var refreshes = 0;
    void refresh() => refreshes++;
    await _pumpTable(tester, people: [person], onOpen: opened.add);
    expect(_refreshButton(tester).onPressed, isNull);
    expect(find.text('Refresh'), findsOneWidget);
    await _tap(tester, find.byKey(_refreshKey));
    expect(refreshes, 0);
    expect(_text(tester, _countKey), '1 saved horoscope');

    await _pumpTable(
      tester,
      people: [person],
      onOpen: opened.add,
      onRefresh: refresh,
    );
    expect(_refreshButton(tester).onPressed, isNotNull);
    await _tap(tester, find.byKey(_refreshKey));
    expect(refreshes, 1);
    expect(opened, isEmpty);

    await _pumpTable(
      tester,
      people: [person],
      onOpen: opened.add,
      onRefresh: refresh,
      loading: true,
    );
    expect(find.text('Refreshing…'), findsOneWidget);
    expect(_refreshButton(tester).onPressed, isNull);
    await _tap(tester, find.byKey(_refreshKey));
    expect(refreshes, 1);
    expect(find.byKey(_emptyKey), findsNothing);
    await _tap(tester, _field(person.id, 'name'));
    expect(opened.single, same(person));

    await _pumpTable(
      tester,
      people: [person],
      onOpen: opened.add,
      onRefresh: refresh,
      error: 'Fixture refresh failed; saved rows remain available.',
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(_refreshButton(tester).onPressed, isNotNull);
    expect(_announcement(tester, _errorKey).properties.liveRegion, isTrue);
    expect(
      _text(tester, _errorKey),
      'Fixture refresh failed; saved rows remain available.',
    );
    expect(find.byKey(_emptyKey), findsNothing);
    await _tap(tester, find.byKey(_refreshKey));
    expect(refreshes, 2);
    _expectBirth(
      tester,
      person.id,
      date: '2000-01-02',
      time: '11:45:07',
      zone: 'UTC+05:30',
    );

    await _pumpTable(tester, people: [person], onOpen: opened.add);
    expect(find.byKey(_errorKey), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);
    expect(_refreshButton(tester).onPressed, isNull);
  });

  _tableTest(
      'empty, custom, loading and error announcements have correct precedence',
      (tester) async {
    await _pumpTable(tester, people: const []);
    expect(_text(tester, _countKey), '0 saved horoscopes');
    expect(
      _text(tester, _emptyKey),
      'Generate a chart above, then save it with a name. '
      'Each person appears here and as a subpage.',
    );
    expect(_announcement(tester, _emptyKey).properties.liveRegion, isFalse);
    expect(_dataTable(tester).rows, isEmpty);
    expect(_refreshButton(tester).onPressed, isNull);

    await _pumpTable(
      tester,
      people: const [],
      emptyMessage: 'Fixture custom empty message',
    );
    expect(_text(tester, _emptyKey), 'Fixture custom empty message');
    await _pumpTable(
      tester,
      people: const [],
      emptyMessage: 'Fixture custom empty message',
      loading: true,
      onRefresh: _noop,
    );
    expect(_text(tester, _emptyKey), 'Reading saved horoscopes…');
    expect(_announcement(tester, _emptyKey).properties.liveRegion, isTrue);
    expect(find.text('Fixture custom empty message'), findsNothing);
    expect(find.text('Refreshing…'), findsOneWidget);
    expect(_refreshButton(tester).onPressed, isNull);

    await _pumpTable(
      tester,
      people: const [],
      error: 'Fixture initial read failed',
      loading: true,
      emptyMessage: 'Fixture custom empty message',
      onRefresh: _noop,
    );
    expect(find.byKey(_emptyKey), findsNothing);
    expect(_text(tester, _errorKey), 'Fixture initial read failed');
    expect(_announcement(tester, _errorKey).properties.liveRegion, isTrue);
    expect(find.text('Refreshing…'), findsOneWidget);
    expect(_refreshButton(tester).onPressed, isNull);
    await _pumpTable(
      tester,
      people: const [],
      error: 'Fixture initial read failed',
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(_refreshButton(tester).onPressed, isNull);
    expect(find.byKey(_emptyKey), findsNothing);
    for (final header in _headers) {
      expect(find.text(header), findsOneWidget);
    }
    _expectNoSelection(tester);
  });

  _tableTest('frozen protobufs and an unmodifiable input list never change',
      (tester) async {
    final original = [_person('immutable-zeta'), _person('immutable-alpha')];
    final people = List<ViewPB>.unmodifiable(original);
    final bytes = [
      for (final person in people) List<int>.of(person.writeToBuffer()),
    ];
    final extras = [for (final person in people) person.extra];
    final opened = <ViewPB>[];
    var refreshes = 0;
    for (final appearance in _appearances) {
      await _pumpTable(
        tester,
        people: people,
        onOpen: opened.add,
        onRefresh: () => refreshes++,
        brightness: appearance.brightness,
        paper: appearance.paper,
        scale: appearance.paper ? 2 : 1,
      );
      expect(
        tester
            .widget<AstrologyHoroscopeTable>(
              find.byType(AstrologyHoroscopeTable),
            )
            .people,
        same(people),
      );
      await _tap(tester, _field(people.first.id, 'name'));
      await _tap(tester, find.byKey(_refreshKey));
      expect(opened.last, same(people.first));
      for (var index = 0; index < people.length; index++) {
        expect(people[index], same(original[index]));
        expect(people[index].isFrozen, isTrue);
        expect(people[index].extra, extras[index]);
        expect(people[index].writeToBuffer(), orderedEquals(bytes[index]));
        _expectBirth(
          tester,
          people[index].id,
          date: '2000-01-02',
          time: '11:45:07',
          zone: 'UTC+05:30',
        );
      }
      expect(
        _dataTable(tester).rows.map((row) => row.key),
        orderedEquals(
          people.map((person) => ValueKey('astrology-horoscope-${person.id}')),
        ),
      );
      _expectNoSelection(tester);
    }
    expect(opened, hasLength(3));
    expect(refreshes, 3);
    expect(() => people.add(original.first), throwsUnsupportedError);
  });

  _tableTest('same-ID replacements and reordering open the newest exact ViewPB',
      (tester) async {
    final old = _person('replaced', name: 'Fixture original sidebar name');
    final other = _person('other');
    final oldOpened = <ViewPB>[];
    final currentOpened = <ViewPB>[];
    await _pumpTable(tester, people: [old, other], onOpen: oldOpened.add);
    await _tap(tester, _field(old.id, 'name'));
    expect(oldOpened.single, same(old));

    final replacement = _person(
      'replaced',
      name: 'Fixture current sidebar name',
      input: AstrologyInput(
        name: 'Fixture different profile name',
        utc: DateTime.utc(2024, 7, 2, 16),
        place: _newYork,
      ),
    );
    await _pumpTable(
      tester,
      people: [other, replacement],
      onOpen: currentOpened.add,
    );
    expect(find.text(old.name), findsNothing);
    expect(_fieldText(tester, replacement.id, 'name'), replacement.name);
    expect(
      _dataTable(tester).rows.map((row) => row.key),
      orderedEquals([
        const ValueKey('astrology-horoscope-other'),
        const ValueKey('astrology-horoscope-replaced'),
      ]),
    );
    _expectBirth(
      tester,
      replacement.id,
      date: '2024-07-02',
      time: '12:00:00',
      zone: 'UTC−04:00',
      place: 'Fixture west city',
    );
    await _tap(tester, _field(replacement.id, 'name'));
    await _tap(tester, _field(other.id, 'place'));
    expect(currentOpened, hasLength(2));
    expect(currentOpened[0], same(replacement));
    expect(currentOpened[1], same(other));
    expect(oldOpened, hasLength(1));

    await _pumpTable(tester, people: [replacement], onOpen: currentOpened.add);
    expect(_field(other.id, 'name'), findsNothing);
    expect(_text(tester, _countKey), '1 saved horoscope');
    await _tap(tester, _field(replacement.id, 'name'));
    expect(currentOpened, hasLength(3));
    expect(currentOpened.last, same(replacement));
    expect(oldOpened, hasLength(1));
    _expectNoSelection(tester);
  });
}

AstrologyInput _birth({String name = 'Fixture stored profile'}) =>
    AstrologyInput(
      name: name,
      utc: DateTime.utc(2000, 1, 2, 6, 15, 7),
      place: _kolkata,
    );

ViewPB _person(String id, {String? name, AstrologyInput? input}) => ViewPB(
      id: id,
      name: name ?? 'Fixture $id',
      layout: ViewLayoutPB.Document,
      extra: DashboardMetadata.newExtra(
        document: buildAstrologyDashboard(
          input: input ?? _birth(),
          library: false,
          libraryId: 'library',
        ),
      ),
    )..freeze();

/// This wrapper is the test body: teardown is guaranteed even after a failed
/// assertion. In particular, semantics is disposed here, never in addTearDown.
void _tableTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(
    description,
    (tester) async {
      final previousLocation = GeolocatorPlatform.instance;
      final location = _NoDeviceLocation();
      GeolocatorPlatform.instance = location;
      final semantics = tester.ensureSemantics();
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1600, 1000);
      try {
        await body(tester);
        expect(
          location.calls,
          isEmpty,
          reason: 'A saved index must never request device location.',
        );
        expect(find.byType(AstrologyHoroscopeLibrary), findsNothing);
        _expectHealthy(tester);
      } finally {
        try {
          await _unmount(tester);
        } finally {
          semantics.dispose();
          GeolocatorPlatform.instance = previousLocation;
          tester.view.reset();
        }
      }
      expect(location.calls, isEmpty);
      _expectHealthy(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Future<void> _pumpTable(
  WidgetTester tester, {
  required List<ViewPB> people,
  ValueChanged<ViewPB>? onOpen,
  VoidCallback? onRefresh,
  bool loading = false,
  String? error,
  String? emptyMessage,
  Size size = const Size(1360, 560),
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool paper = false,
  bool capturePixels = false,
  ScrollController? primaryController,
}) async {
  Widget child = SizedBox.fromSize(
    size: size,
    child: AstrologyHoroscopeTable(
      people: people,
      onOpen: onOpen,
      onRefresh: onRefresh,
      loading: loading,
      error: error,
      emptyMessage: emptyMessage,
    ),
  );
  if (capturePixels) {
    // Capture both the surface and DataTable's transparent ink Material.
    child = RepaintBoundary(key: _pixelsKey, child: child);
  }
  if (primaryController != null) {
    child =
        PrimaryScrollController(controller: primaryController, child: child);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF345580),
          brightness: brightness,
        ),
        extensions: [PaperThemeExtension(enabled: paper)],
      ),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<List<Color>> _sampleInk(
  WidgetTester tester,
  List<Offset> globalPoints,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_pixelsKey),
  );
  expect(boundary.debugNeedsPaint, isFalse);
  // Engine rasterization/readback needs real async, not the test's fake clock.
  // Images and RGBA bytes stay in memory; there are no PNG baselines or files.
  final colors = await tester.runAsync(() async {
    final image = await boundary.toImage(); // One pixel per logical pixel.
    try {
      final bytes = await image.toByteData(); // Defaults to raw RGBA.
      if (bytes == null) {
        throw StateError('The table capture did not return RGBA pixels.');
      }
      final samples = <Color>[];
      for (final point in globalPoints) {
        final local = boundary.globalToLocal(point);
        final x = local.dx.floor();
        final y = local.dy.floor();
        expect(x, inInclusiveRange(1, image.width - 2));
        expect(y, inInclusiveRange(1, image.height - 2));
        final rgba = List<int>.filled(4, 0);
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final offset = ((y + dy) * image.width + x + dx) * 4;
            for (var channel = 0; channel < rgba.length; channel++) {
              rgba[channel] += bytes.getUint8(offset + channel);
            }
          }
        }
        samples.add(
          Color.fromARGB(
            (rgba[3] / 9).round(),
            (rgba[0] / 9).round(),
            (rgba[1] / 9).round(),
            (rgba[2] / 9).round(),
          ),
        );
      }
      return samples;
    } finally {
      image.dispose();
    }
  });
  expect(colors, isNotNull, reason: 'Rasterization must return pixel samples.');
  return colors!;
}

void _expectPixelColor(Color actual, Color expected, {required String reason}) {
  final actualRgba = [actual.r, actual.g, actual.b, actual.a];
  final expectedRgba = [expected.r, expected.g, expected.b, expected.a];
  for (var channel = 0; channel < actualRgba.length; channel++) {
    expect(
      actualRgba[channel] * 255,
      closeTo(expectedRgba[channel] * 255, 1),
      reason: '$reason, RGBA channel $channel (8-bit rounding tolerance only)',
    );
  }
}

Finder _field(String id, String field) =>
    find.byKey(ValueKey('astrology-horoscope-$id-$field'));

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

String _fieldText(WidgetTester tester, String id, String field) =>
    tester.widget<Text>(_field(id, field)).data!;

DataTable _dataTable(WidgetTester tester) =>
    tester.widget<DataTable>(find.byKey(_tableKey));

DataRow _row(WidgetTester tester, String id) =>
    _dataTable(tester).rows.singleWhere(
          (row) => row.key == ValueKey('astrology-horoscope-$id'),
        );

Finder _rowInk(String id, [String field = 'name']) => find
    .ancestor(
      of: _field(id, field),
      matching: find.byType(TableRowInkWell),
    )
    .first;

FocusNode _rowFocus(WidgetTester tester, String id) {
  // InkResponse owns an internal node, so TableRowInkWell.focusNode is null.
  // Resolve its Focus's direct child, not a possibly nested Tooltip focus or
  // the Focus widget's own context (which would resolve the ancestor node).
  final focus = tester.widget<Focus>(
    find
        .descendant(
          of: _rowInk(id),
          matching: find.byType(Focus),
        )
        .first,
  );
  return Focus.of(tester.element(find.byWidget(focus.child)));
}

Text? _zoneText(WidgetTester tester, String id) {
  // The secondary offset has no public key; scope it to the time cell's
  // actual Column rather than inventing one or matching another row's text.
  final column = tester.widget<Column>(
    find
        .ancestor(
          of: _field(id, 'time'),
          matching: find.byType(Column),
        )
        .first,
  );
  final secondary =
      column.children.whereType<Text>().where((text) => text.key == null);
  expect(secondary.length, lessThanOrEqualTo(1));
  return secondary.isEmpty ? null : secondary.single;
}

void _expectBirth(
  WidgetTester tester,
  String id, {
  required String date,
  required String time,
  String? zone,
  String? place,
}) {
  expect(_fieldText(tester, id, 'date'), date, reason: id);
  expect(_fieldText(tester, id, 'time'), time, reason: id);
  expect(_zoneText(tester, id)?.data, zone, reason: id);
  if (place != null) expect(_fieldText(tester, id, 'place'), place, reason: id);
}

TextButton _refreshButton(WidgetTester tester) => tester.widget<TextButton>(
      find.byWidgetPredicate(
        (widget) => widget is TextButton && widget.key == _refreshKey,
      ),
    );

Semantics _announcement(WidgetTester tester, Key key) =>
    tester.widget<Semantics>(
      find
          .ancestor(of: find.byKey(key), matching: find.byType(Semantics))
          .first,
    );

ScrollController _controller(WidgetTester tester, Key key) =>
    tester.widget<SingleChildScrollView>(find.byKey(key)).controller!;

void _expectNoSelection(WidgetTester tester) {
  final table = _dataTable(tester);
  expect(table.showCheckboxColumn, isFalse);
  expect(table.onSelectAll, isNull);
  expect(table.rows.every((row) => !row.selected), isTrue);
  expect(find.byType(Checkbox), findsNothing);
  expect(find.byType(SelectableText), findsNothing);
  for (final row in table.rows) {
    expect(
      row.cells.every((cell) => cell.onTap == null),
      isTrue,
      reason: 'Cell callbacks must not override whole-row navigation.',
    );
  }
}

void _expectNoRails(WidgetTester tester) {
  expect(
    find.byWidgetPredicate(
      (widget) => widget is Scrollbar || widget is RawScrollbar,
    ),
    findsNothing,
  );
  expect(
    ScrollConfiguration.of(tester.element(find.byKey(_surfaceKey))),
    isA<NoScrollbarBehavior>(),
  );
}

void _expectHealthy(WidgetTester tester, {String? reason}) {
  expect(find.byType(ErrorWidget), findsNothing, reason: reason);
  expect(tester.takeException(), isNull, reason: reason);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target, kind: ui.PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void _noop() {}

class _NoDeviceLocation extends Fake
    with MockPlatformInterfaceMixin
    implements GeolocatorPlatform {
  final calls = <Symbol>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError(
      'Unexpected device-location request: ${invocation.memberName}',
    );
  }
}
