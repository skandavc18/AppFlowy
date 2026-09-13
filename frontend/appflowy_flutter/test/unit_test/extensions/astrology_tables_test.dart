import 'dart:ui' as ui;

import 'package:appflowy/extensions/dart/built_in/astrology/ashtakavarga.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_shadbala_graph.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_strength_chart.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_tables.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_time.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/shadbala.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/vedic_chart_view.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/vimshottari.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Every chart is hand-authored. No AstrologyEngine, Sweph, asset loader,
// location service, network, filesystem or native library is used here.
const _place = AstrologyPlace(
  name: 'Fixture city',
  latitude: 12.98,
  longitude: 77.58,
  timeZone: 'Asia/Kolkata',
);
const _specialLagnas = [
  VedicPlacement(name: 'Bhava Lagna', shortName: 'BL', longitude: 45.125),
  VedicPlacement(name: 'Hora Lagna', shortName: 'HL', longitude: 93.25),
  VedicPlacement(name: 'Ghati Lagna', shortName: 'GL', longitude: 140.5),
  VedicPlacement(name: 'Gulika', shortName: 'Gk', longitude: 230.75),
  VedicPlacement(name: 'Maandi', shortName: 'Md', longitude: 231.75),
  VedicPlacement(name: 'Sri Lagna', shortName: 'SL', longitude: 315.5),
];
const _bavTotals = [48, 49, 39, 54, 56, 52, 39, 49];
const _movingKaranas = [
  'Bava',
  'Balava',
  'Kaulava',
  'Taitila',
  'Gara',
  'Vanija',
  'Vishti',
];

void main() {
  testWidgets('placements contain every planet, Lagna and six supplied points',
      (
    tester,
  ) async {
    final chart = _chart();
    await tester.pumpWidget(_app(AstrologyPlacementsTable(chart: chart)));
    final table = tester.widget<Table>(_key('placements-table'));
    expect(chart.placements, hasLength(16));
    expect(table.children, hasLength(17));
    for (final placement in chart.placements) {
      final prefix = 'placements-${placement.shortName}';
      expect(
        _value(tester, '$prefix-name'),
        placement.body?.label ?? placement.name,
      );
      expect(_value(tester, '$prefix-longitude'), placement.formatted);
      expect(_value(tester, '$prefix-nakshatra'), placement.nakshatra);
      expect(_value(tester, '$prefix-pada'), '${placement.pada}');
      expect(_value(tester, '$prefix-d1'), zodiacNames[placement.sign]);
      expect(
        _value(tester, '$prefix-d9'),
        zodiacNames[divisionalSign(placement.longitude, 9)],
      );
      expect(
        _value(tester, '$prefix-house'),
        '${(placement.sign - zodiacSign(chart.ascendant)) % 12 + 1}',
      );
      expect(
        _value(tester, '$prefix-retrograde'),
        placement.body == null
            ? 'Not applicable'
            : placement.retrograde
                ? 'Yes'
                : 'No',
      );
      expect(
        _value(tester, '$prefix-speed'),
        placement.body == null
            ? 'Not applicable'
            : placement.speed.toStringAsFixed(4),
      );
    }
    expect(_value(tester, 'placements-As-d1'), 'Taurus');
    expect(_value(tester, 'placements-As-d9'), 'Capricorn');
    expect(_value(tester, 'placements-Me-retrograde'), 'Yes');
    expect(_value(tester, 'placements-Me-speed'), '-0.6500');
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing special lagnas are not filled with fabricated positions',
      (
    tester,
  ) async {
    final chart = _chart(polar: true);
    await tester.pumpWidget(_app(AstrologyPlacementsTable(chart: chart)));
    expect(
      tester.widget<Table>(_key('placements-table')).children,
      hasLength(12),
    );
    expect(_key('placements-SL-longitude'), findsOneWidget);
    for (final shortName in ['BL', 'HL', 'GL', 'Gk', 'Md', 'AL']) {
      expect(_key('placements-$shortName-longitude'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'placement values retain the inherited face weight and are selectable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(AstrologyPlacementsTable(chart: _chart()), weight: FontWeight.w300),
    );
    final value = _selectable(tester, 'placements-Su-longitude');
    expect(value.style!.fontWeight, FontWeight.w300);
    expect(
      value.style!.fontFeatures,
      contains(const ui.FontFeature.tabularFigures()),
    );
    expect(value.data, '10° Ar 00′ 00″');
    expect(tester.takeException(), isNull);
  });

  group('panchanga facts', () {
    testWidgets(
        'shows phase, balance, actual solar times, place and provenance', (
      tester,
    ) async {
      final chart = _chart(weekday: 5);
      await tester.pumpWidget(_app(AstrologyPanchangaView(chart: chart)));
      expect(
        _value(tester, 'panchanga-tithi-value'),
        'Pratipada · Shukla Paksha (waxing) · 1/30\n'
        '16.67% remaining (fraction 0.166667)',
      );
      final nakshatra = _value(tester, 'panchanga-nakshatra-value');
      expect(nakshatra, contains('Bharani · Pada 3'));
      expect(nakshatra, contains('Lord: Venus'));
      expect(nakshatra, contains('10.000000 years remaining'));
      expect(_value(tester, 'panchanga-yoga-value'), 'Ayushman · 3/27');
      expect(
        _value(tester, 'panchanga-karana-value'),
        'Bava · half-tithi 2/60',
      );
      // The supplied sunrise-based weekday wins over the UTC/civil Sunday.
      expect(
        _value(tester, 'panchanga-vara-value'),
        'Friday · sunrise-based weekday',
      );
      expect(
        _value(tester, 'panchanga-local-time-value'),
        '2000-01-02 11:45:30 UTC+05:30',
      );
      expect(_value(tester, 'panchanga-place-value'), 'Fixture city');
      expect(
        _value(tester, 'panchanga-coordinates-value'),
        '12.98000° N · 77.58000° E',
      );
      expect(_value(tester, 'panchanga-zone-value'), contains('Asia/Kolkata'));
      expect(_value(tester, 'panchanga-offset-value'), 'UTC+05:30');
      expect(
        _value(tester, 'panchanga-sunrise-value'),
        '2000-01-02 06:12:11 UTC+05:30',
      );
      expect(
        _value(tester, 'panchanga-sunset-value'),
        '2000-01-02 18:01:47 UTC+05:30',
      );
      expect(
        _value(tester, 'panchanga-next-sunrise-value'),
        '2000-01-03 06:12:11 UTC+05:30',
      );
      expect(_value(tester, 'panchanga-ayanamsa-value'), 'Lahiri · 23.856750°');
      expect(_value(tester, 'panchanga-rahu-value'), 'Mean node');
      expect(
        _value(tester, 'panchanga-ephemeris-value'),
        'Unavailable (not supplied with this chart)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('names all 60 half-tithis, including both fixed ends', (
      tester,
    ) async {
      final expected = [
        'Kimstughna',
        for (var repetition = 0; repetition < 8; repetition++)
          ..._movingKaranas,
        'Shakuni',
        'Chatushpada',
        'Naga',
      ];
      expect(expected, hasLength(60));
      for (var half = 0; half < expected.length; half++) {
        await tester.pumpWidget(
          _app(
            AstrologyPanchangaView(
              chart: _chart(sunLongitude: 0, moonLongitude: half * 6.0),
            ),
          ),
        );
        expect(
          _value(tester, 'panchanga-karana-value'),
          '${expected[half]} · half-tithi ${half + 1}/60',
          reason: 'Zero-based half-tithi $half',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('names all 27 yogas in zodiac order', (tester) async {
      const expected = [
        'Vishkambha',
        'Priti',
        'Ayushman',
        'Saubhagya',
        'Shobhana',
        'Atiganda',
        'Sukarma',
        'Dhriti',
        'Shula',
        'Ganda',
        'Vriddhi',
        'Dhruva',
        'Vyaghata',
        'Harshana',
        'Vajra',
        'Siddhi',
        'Vyatipata',
        'Variyana',
        'Parigha',
        'Shiva',
        'Siddha',
        'Sadhya',
        'Shubha',
        'Shukla',
        'Brahma',
        'Indra',
        'Vaidhriti',
      ];
      for (var yoga = 0; yoga < expected.length; yoga++) {
        await tester.pumpWidget(
          _app(
            AstrologyPanchangaView(
              chart:
                  _chart(sunLongitude: 0, moonLongitude: (yoga + 0.5) * 40 / 3),
            ),
          ),
        );
        expect(
          _value(tester, 'panchanga-yoga-value'),
          '${expected[yoga]} · ${yoga + 1}/27',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('full and new moon names respect waxing and waning boundaries',
        (
      tester,
    ) async {
      for (final sample in const [
        (0.0, 'Pratipada', 'Shukla Paksha (waxing)'),
        (174.0, 'Purnima', 'Shukla Paksha (waxing)'),
        (180.0, 'Pratipada', 'Krishna Paksha (waning)'),
        (354.0, 'Amavasya', 'Krishna Paksha (waning)'),
        (360.0, 'Pratipada', 'Shukla Paksha (waxing)'),
      ]) {
        await tester.pumpWidget(
          _app(
            AstrologyPanchangaView(
              chart: _chart(sunLongitude: 0, moonLongitude: sample.$1),
            ),
          ),
        );
        expect(
          _value(tester, 'panchanga-tithi-value'),
          startsWith('${sample.$2} · ${sample.$3}'),
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Sunday starts the supplied weekday sequence', (tester) async {
      const days = [
        'Sunday',
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
      ];
      for (var weekday = 0; weekday < days.length; weekday++) {
        await tester.pumpWidget(
          _app(AstrologyPanchangaView(chart: _chart(weekday: weekday))),
        );
        expect(
          _value(tester, 'panchanga-vara-value'),
          startsWith('${days[weekday]} ·'),
        );
      }
    });

    testWidgets(
        'IANA wall time, true Rahu and ayanamsa update with chart identity', (
      tester,
    ) async {
      final input = AstrologyInput(
        utc: DateTime.utc(2024, 7, 2, 16),
        place: const AstrologyPlace(
          name: 'New York',
          latitude: 40.71,
          longitude: -74.01,
          timeZone: 'America/New_York',
        ),
        trueNode: true,
        ayanamsa: AstrologyAyanamsa.raman,
      );
      await tester.pumpWidget(_app(AstrologyPanchangaView(chart: _chart())));
      await tester.pumpWidget(
        _app(AstrologyPanchangaView(chart: _chart(input: input))),
      );
      expect(
        _value(tester, 'panchanga-local-time-value'),
        '2024-07-02 12:00:00 UTC−04:00',
      );
      expect(_value(tester, 'panchanga-zone-value'), 'America/New_York');
      expect(_value(tester, 'panchanga-rahu-value'), 'True node');
      expect(_value(tester, 'panchanga-ayanamsa-value'),
          'B.V. Raman · 23.856750°');
      expect(
        _value(tester, 'panchanga-coordinates-value'),
        contains('74.01000° W'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('polar solar times stay explicitly unavailable',
        (tester) async {
      await tester
          .pumpWidget(_app(AstrologyPanchangaView(chart: _chart(polar: true))));
      for (final event in ['sunrise', 'sunset', 'next-sunrise']) {
        expect(
          _value(tester, 'panchanga-$event-value'),
          startsWith('Unavailable (polar day/night'),
        );
      }
      expect(
        _value(tester, 'panchanga-vara-value'),
        contains('civil weekday; sunrise unavailable'),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('dasha full-card navigation', () {
    testWidgets(
      'nine roots retain the full 120 years and drill down four levels',
      (tester) async {
        final chart = _chart();
        final periods = _periods(chart);
        final first = periods.first;
        expect(first.lord, VedicBody.venus);
        expect(first.start, chart.utc.subtract(const Duration(days: 3600)));
        expect(first.end, chart.utc.add(const Duration(days: 3600)));
        expect(
          periods.last.end.difference(first.start),
          const Duration(days: 43200),
        );
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
        );
        expect(find.text('Vimshottari'), findsOneWidget);
        expect(find.text('120-year cycle · 4 levels'), findsOneWidget);
        _expectDashaPage(tester, chart, const []);
        expect(_key('dasha-birth-balance'), findsNothing);
        await _tap(tester, 'dasha-details');
        expect(
          _value(tester, 'dasha-birth-balance'),
          'Birth balance: Venus · 10.000000 years remaining',
        );
        expect(
          _value(tester, 'dasha-pre-birth-note'),
          contains('Elapsed before birth: 10.000000 years'),
        );
        await _tap(tester, 'dasha-details');

        final trail = _firstDashaPath(first);
        for (var level = 0; level < 4; level++) {
          final path = _dashaPath(trail.take(level + 1));
          await _tap(tester, 'dasha-open-$path');
          _expectDashaPage(tester, chart, trail.take(level + 1).toList());
          expect(
            _value(tester, 'dasha-detail-start'),
            _dateStamp(chart.input, first.start),
          );
          expect(_key('dasha-open-$path'), findsNothing);
          expect(_key('dasha-back'), findsOneWidget);
        }
        expect(find.text('Finest supported level'), findsOneWidget);
        expect(_dashaRows(), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(Navigator), findsOneWidget);
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    for (final kind in const [
      ui.PointerDeviceKind.touch,
      ui.PointerDeviceKind.mouse,
    ]) {
      testWidgets(
        'title, both dates and padding open every level with ${kind.name}',
        (tester) async {
          final chart = _chart();
          final trail = _firstDashaPath(_periods(chart).first);
          await tester.pumpWidget(
            _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
          );
          for (var level = 0; level < 4; level++) {
            final parent = trail.take(level).toList();
            final selected = trail.take(level + 1).toList();
            final path = _dashaPath(selected);
            for (final target in ['title', 'start', 'end', 'padding']) {
              expect(tester.widget(_key('dasha-open-$path')), isA<InkWell>());
              expect(
                find.descendant(
                  of: _key('dasha-open-$path'),
                  matching: find.byType(SelectableText),
                ),
                findsNothing,
              );
              if (target == 'padding') {
                await tester.ensureVisible(_key('dasha-open-$path'));
                await tester.pump();
                final rectangle = tester.getRect(_key('dasha-open-$path'));
                await tester.tapAt(
                  Offset(rectangle.right - 6, rectangle.center.dy),
                  kind: kind,
                );
                await tester.pumpAndSettle();
              } else {
                await _tap(tester, 'dasha-$path-$target', kind: kind);
              }
              _expectDashaPage(tester, chart, selected);
              expect(_key('dasha-page-${_dashaPath(parent)}'), findsNothing);
              await _tap(tester, 'dasha-back', kind: kind);
              _expectDashaPage(tester, chart, parent);
            }
            await _tap(tester, 'dasha-$path-title', kind: kind);
          }
          await _finishDasha(tester);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    testWidgets(
      'Back and each breadcrumb restore exactly the selected parent list',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final chart = _chart();
          final trail = [_periods(chart)[1]];
          for (final index in [2, 4, 1]) {
            trail.add(trail.last.children[index]);
          }
          await tester.pumpWidget(
            _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
          );
          await _openDashaPath(tester, trail);
          for (var index = 0; index < 4; index++) {
            final crumb = _key('dasha-breadcrumb-$index');
            await tester.ensureVisible(crumb);
            await tester.pump();
            final label = '${trail[index].lord.label} ${_dashaLevels[index]}';
            final tooltip = tester.widget<Tooltip>(
              find.ancestor(of: crumb, matching: find.byType(Tooltip)).first,
            );
            expect(tooltip.message, label);
            expect(
              tester.getSemantics(crumb).getSemanticsData().label,
              contains(label),
            );
          }
          for (var length = 3; length >= 0; length--) {
            await _tap(tester, 'dasha-back');
            _expectDashaPage(tester, chart, trail.take(length).toList());
          }
          await _openDashaPath(tester, trail);
          for (final index in [2, 1, 0]) {
            await _tap(tester, 'dasha-breadcrumb-$index');
            _expectDashaPage(tester, chart, trail.take(index + 1).toList());
            expect(_key('dasha-breadcrumb-${index + 1}'), findsNothing);
          }
          await _tap(tester, 'dasha-breadcrumb-root');
          _expectDashaPage(tester, chart, const []);
          await _finishDasha(tester);
        } finally {
          semantics.dispose();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Enter and Space open all four levels and hand focus to Back',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final chart = _chart();
          final trail = _firstDashaPath(_periods(chart).first);
          await tester.pumpWidget(
            _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
          );
          for (var level = 0; level < 4; level++) {
            final selected = trail.take(level + 1).toList();
            final path = _dashaPath(selected);
            for (final key in [
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.space,
            ]) {
              await tester.ensureVisible(_key('dasha-open-$path'));
              Focus.of(tester.element(_key('dasha-$path-title')))
                  .requestFocus();
              await tester.pump();
              final data = tester
                  .getSemantics(_key('dasha-semantics-$path'))
                  .getSemanticsData();
              expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
              expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
              expect(data.hasFlag(ui.SemanticsFlag.hasExpandedState), isFalse);
              expect(data.hint, contains(_dashaLevels[level]));
              expect(
                tester.widget<Icon>(_key('dasha-chevron-$path')).icon,
                Icons.chevron_right_rounded,
              );
              await _press(tester, key);
              _expectDashaPage(tester, chart, selected);
              expect(
                tester
                    .widget<TextButton>(_key('dasha-back'))
                    .focusNode!
                    .hasPrimaryFocus,
                isTrue,
              );
              expect(_dashaController(tester).offset, 0);
              if (key == LogicalKeyboardKey.enter) {
                await _press(tester, LogicalKeyboardKey.escape);
                _expectDashaPage(tester, chart, trail.take(level).toList());
              }
            }
          }
          await _press(tester, LogicalKeyboardKey.tab);
          final rootLabel = find.descendant(
            of: _key('dasha-breadcrumb-root'),
            matching: find.text('All dashas'),
          );
          expect(Focus.of(tester.element(rootLabel)).hasPrimaryFocus, isTrue);
          await _press(tester, LogicalKeyboardKey.enter);
          _expectDashaPage(tester, chart, const []);
          expect(
            tester
                .widget<Focus>(_key('dasha-heading-focus'))
                .focusNode!
                .hasPrimaryFocus,
            isTrue,
          );
          await _press(tester, LogicalKeyboardKey.tab);
          final currentLabel = find.descendant(
            of: _key('dasha-current-period'),
            matching: find.text('Current period'),
          );
          expect(
            Focus.of(tester.element(currentLabel)).hasPrimaryFocus,
            isTrue,
          );
          await _finishDasha(tester);
        } finally {
          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Escape and Alt+Left are local; Backspace remains an editing key',
      (tester) async {
        final outsideFocus = FocusNode();
        final text = TextEditingController();
        var backspaces = 0;
        var escapedRoot = 0;
        final chart = _chart();
        try {
          await tester.pumpWidget(
            _dashaApp(
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.backspace) {
                      backspaces++;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.escape) {
                      escapedRoot++;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Column(
                  children: [
                    TextField(
                      key: const ValueKey('dasha-sibling-input'),
                      controller: text,
                      focusNode: outsideFocus,
                    ),
                    Expanded(
                      child: AstrologyDashaTable(chart: chart, at: chart.utc),
                    ),
                  ],
                ),
              ),
            ),
          );
          await _tap(tester, 'dasha-open-venus');
          tester
              .widget<TextButton>(_key('dasha-back'))
              .focusNode!
              .requestFocus();
          await tester.pump();
          await _press(tester, LogicalKeyboardKey.backspace);
          expect(backspaces, 1);
          expect(_key('dasha-page-venus'), findsOneWidget);
          await _altLeft(tester);
          expect(_key('dasha-page-root'), findsOneWidget);
          await _press(tester, LogicalKeyboardKey.escape);
          expect(escapedRoot, 1, reason: 'Escape is not consumed at the root.');
          await _tap(tester, 'dasha-open-venus');
          await tester.enterText(_key('dasha-sibling-input'), 'ab');
          expect(outsideFocus.hasFocus, isTrue);
          await _press(tester, LogicalKeyboardKey.escape);
          expect(_key('dasha-page-venus'), findsOneWidget);
          outsideFocus.requestFocus();
          await tester.pump();
          expect(outsideFocus.hasFocus, isTrue);
          await _altLeft(tester);
          expect(_key('dasha-page-venus'), findsOneWidget);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          outsideFocus.dispose();
          text.dispose();
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'date columns adapt to width while retaining typography at every level',
      (tester) async {
        final chart = _chart();
        final trail = _firstDashaPath(_periods(chart).first);
        const variations = [ui.FontVariation('wght', 325)];
        for (final width in [280.0, 440.0, 720.0]) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            _dashaApp(
              AstrologyDashaTable(chart: chart, at: chart.utc),
              size: Size(width, 300),
              weight: FontWeight.w300,
              fontFamily: 'Fixture face',
              fontVariations: variations,
            ),
          );
          for (var level = 0; level < 4; level++) {
            final path = _dashaPath(trail.take(level + 1));
            final start = tester.widget<Text>(_key('dasha-$path-start'));
            final end = tester.widget<Text>(_key('dasha-$path-end'));
            expect(start.data!.split('\n'), hasLength(3));
            expect(end.data!.split('\n'), hasLength(3));
            expect(start.data, endsWith('UTC+05:30'));
            expect(start.style!.fontFamily, 'Fixture face');
            expect(start.style!.fontWeight, FontWeight.w300);
            expect(start.style!.fontVariations, variations);
            expect(
              start.style!.fontFeatures,
              contains(const ui.FontFeature.tabularFigures()),
            );
            expect(_value(tester, 'dasha-$path-start-label'), 'Start');
            expect(_value(tester, 'dasha-$path-end-label'), 'End');
            final startBounds = tester.getRect(_key('dasha-$path-start'));
            final endLabel = tester.getRect(_key('dasha-$path-end-label'));
            if (width == 280) {
              expect(
                endLabel.top - startBounds.bottom,
                greaterThanOrEqualTo(16),
              );
            } else {
              expect(
                endLabel.left - startBounds.right,
                greaterThanOrEqualTo(16),
              );
              expect(
                endLabel.top,
                tester.getTopLeft(_key('dasha-$path-start-label')).dy,
              );
            }
            final card = tester.getRect(_key('dasha-card-$path'));
            expect(startBounds.left, greaterThan(card.left));
            expect(startBounds.right, lessThan(card.right));
            await _tap(tester, 'dasha-open-$path');
            expect(_value(tester, 'dasha-detail-start'), start.data);
            expect(_value(tester, 'dasha-detail-end'), end.data);
          }
          await _finishDasha(tester);
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'four levels fit real desktop themes, small cards and 2x text',
      (tester) async {
        final chart = _chart();
        final trail = _firstDashaPath(_periods(chart).first);
        for (final appearance in const [
          (Brightness.light, false),
          (Brightness.dark, false),
          (Brightness.light, true),
        ]) {
          for (final size in const [
            Size(220, 100),
            Size(280, 300),
            Size(440, 300),
            Size(720, 540),
          ]) {
            for (final scale in [1.0, 2.0]) {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpWidget(
                _dashaApp(
                  AstrologyDashaTable(chart: chart, at: chart.utc),
                  size: size,
                  brightness: appearance.$1,
                  paper: appearance.$2,
                  textScaler: TextScaler.linear(scale),
                ),
              );
              final surface = _key('astrology-dasha-surface');
              final palette = AstrologyPalette.of(tester.element(surface));
              expect(tester.getSize(surface), size);
              expect(tester.widget<ColoredBox>(surface).color, palette.surface);
              expect(
                Theme.of(tester.element(surface)).brightness,
                appearance.$1,
              );
              if (appearance.$2) {
                expect(palette.surface, PaperTheme.editorPreviewBackground);
              }
              _expectDashaPage(tester, chart, const []);
              final controller = _dashaController(tester);
              for (var level = 0; level < 4; level++) {
                final path = _dashaPath(trail.take(level + 1));
                final ink = tester.widget<InkWell>(_key('dasha-open-$path'));
                expect(ink.hoverColor, palette.hover);
                expect(ink.focusColor, palette.selection);
                expect(
                  tester.widget<Material>(_key('dasha-card-$path')).color,
                  trail[level].contains(chart.utc)
                      ? palette.selection
                      : palette.control,
                );
                await _tap(tester, 'dasha-open-$path');
                _expectDashaPage(tester, chart, trail.take(level + 1).toList());
                expect(_dashaController(tester), same(controller));
                expect(controller.offset, 0);
                _expectDashaHealthy(tester);
              }
              expect(
                _value(tester, 'dasha-detail-start'),
                contains('\nUTC+05:30'),
              );
              expect(
                _value(tester, 'dasha-detail-end'),
                contains('\nUTC+05:30'),
              );
              controller.jumpTo(controller.position.maxScrollExtent);
              await tester.pumpAndSettle();
              await _tap(tester, 'dasha-back');
              _expectDashaPage(tester, chart, trail.take(3).toList());
              await _tap(tester, 'dasha-breadcrumb-root');
              _expectDashaPage(tester, chart, const []);
              await _finishDasha(tester);
            }
          }
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Details stays optional and precedes the list on nested pages',
      (tester) async {
        final chart = _chart();
        final trail = _firstDashaPath(_periods(chart).first);
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
        );
        expect(_key('dasha-convention-details'), findsNothing);
        await _tap(tester, 'dasha-details');
        for (var length = 0; length < 4; length++) {
          if (length > 0) {
            await _tap(tester, 'dasha-open-${_dashaPath(trail.take(length))}');
          }
          _expectDashaPage(tester, chart, trail.take(length).toList());
          expect(_key('dasha-convention-details'), findsOneWidget);
          expect(
            tester.getBottomLeft(_key('dasha-convention-details')).dy,
            lessThan(tester.getTopLeft(_key('dasha-list-heading')).dy),
          );
        }
        await _tap(tester, 'dasha-details');
        expect(_key('dasha-convention-details'), findsNothing);
        _expectDashaPage(tester, chart, trail.take(3).toList());
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'reading changes update current roots without navigating or scrolling',
      (tester) async {
        final chart = _chart();
        final last = _periods(chart).last;
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
        );
        final controller = _dashaController(tester);
        controller.jumpTo(200);
        await tester.pump();
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: last.start)),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(controller.offset, 200);
        _expectDashaPage(tester, chart, const []);
        expect(_key('dasha-current-venus'), findsNothing);
        expect(_key('dasha-current-${last.lord.name}'), findsOneWidget);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'reading changes preserve a browsed trail while updating child statuses',
      (tester) async {
        final chart = _chart();
        final first = _periods(chart).first;
        final children = first.children;
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: children[2].start)),
        );
        await _tap(tester, 'dasha-open-venus');
        final controller = _dashaController(tester);
        expect(
          _key('dasha-current-venus-${children[2].lord.name}'),
          findsOneWidget,
        );
        controller.jumpTo(200);
        await tester.pump();
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: children[2].end)),
        );
        await tester.pumpAndSettle();
        _expectDashaPage(tester, chart, [first]);
        expect(controller.offset, 200);
        expect(_value(tester, 'dasha-detail-status'), 'Current');
        expect(
          _key('dasha-current-venus-${children[2].lord.name}'),
          findsNothing,
        );
        expect(
          _key('dasha-current-venus-${children[3].lord.name}'),
          findsOneWidget,
        );
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: first.end)),
        );
        _expectDashaPage(tester, chart, [first]);
        expect(_value(tester, 'dasha-detail-status'), 'Finished');
        expect(find.text('Current'), findsNothing);
        expect(controller.offset, 200);
        await tester.pumpWidget(
          _dashaApp(
            AstrologyDashaTable(
              chart: chart,
              at: first.start.subtract(const Duration(microseconds: 1)),
            ),
          ),
        );
        expect(_value(tester, 'dasha-detail-status'), 'Upcoming');
        _expectDashaPage(tester, chart, [first]);
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Current period selects the complete half-open path through Sookshma',
      (tester) async {
        final chart = _chart();
        final periods = _periods(chart);
        final firstPath = _firstDashaPath(periods[1]);
        for (final at in [periods[1].start, firstPath.last.end]) {
          await tester.pumpWidget(
            _dashaApp(AstrologyDashaTable(chart: chart, at: at)),
          );
          await _tap(tester, 'dasha-current-period');
          final active = dashaAt(periods, at);
          expect(active, hasLength(4));
          _expectDashaPage(tester, chart, active);
          expect(_key('dasha-current-${_dashaPath(active)}'), findsOneWidget);
          expect(_value(tester, 'dasha-detail-status'), 'Current');
          expect(_dashaRows(), findsNothing);
          expect(_dashaController(tester).offset, 0);
          for (var index = 0; index < 4; index++) {
            expect(
              _value(tester, 'dasha-breadcrumb-$index'),
              active[index].lord.label,
            );
          }
        }
        await _tap(tester, 'dasha-details');
        expect(
          _value(tester, 'dasha-reading-date'),
          'Reading date: ${_dateStamp(chart.input, firstPath.last.end).replaceAll('\n', ' ')}',
        );
        await _tap(tester, 'dasha-back');
        expect(_dashaRows(), findsNWidgets(9));
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'pre-birth readings work and outside-cycle dates invent no period',
      (tester) async {
        final chart = _chart();
        final periods = _periods(chart);
        final beforeBirth = chart.utc.subtract(const Duration(days: 1000));
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: beforeBirth)),
        );
        await _tap(tester, 'dasha-current-period');
        final active = dashaAt(periods, beforeBirth);
        expect(active, hasLength(4));
        _expectDashaPage(tester, chart, active);
        expect(_key('dasha-current-${_dashaPath(active)}'), findsOneWidget);
        for (final outside in [
          periods.first.start.subtract(const Duration(microseconds: 1)),
          periods.last.end,
        ]) {
          await tester.pumpWidget(
            _dashaApp(AstrologyDashaTable(chart: chart, at: outside)),
          );
          await _tap(tester, 'dasha-current-period');
          expect(_key('dasha-outside-cycle'), findsOneWidget);
          expect(find.text('Current'), findsNothing);
          _expectDashaPage(tester, chart, const []);
        }
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'a different chart identity resets the trail and only its own viewport',
      (tester) async {
        final chart = _chart();
        final replacement = _chart(moonLongitude: 80);
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
        );
        await _openDashaPath(tester, _firstDashaPath(_periods(chart).first));
        final controller = _dashaController(tester);
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pump();
        await tester.pumpWidget(
          _dashaApp(
            AstrologyDashaTable(chart: replacement, at: replacement.utc),
          ),
        );
        await tester.pumpAndSettle();
        _expectDashaPage(tester, replacement, const []);
        expect(_dashaController(tester), same(controller));
        expect(controller.offset, 0);
        expect(_key('dasha-page-venus-venus-venus-venus'), findsNothing);
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'dasha tiles and overviews resolve each IANA endpoint independently',
      (tester) async {
        final chart = _chart(
          moonLongitude: 17,
          input: AstrologyInput(
            utc: DateTime.utc(2024, 7, 2, 16),
            place: const AstrologyPlace(
              name: 'New York',
              latitude: 40.71,
              longitude: -74.01,
              timeZone: 'America/New_York',
            ),
          ),
        );
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
        );
        _expectDashaPage(tester, chart, const []);
        await _tap(tester, 'dasha-details');
        expect(
          _value(tester, 'dasha-reading-date'),
          'Reading date: 2024-07-02 12:00:00 UTC−04:00',
        );
        await _tap(tester, 'dasha-details');
        await _tap(tester, 'dasha-open-venus');
        final antar = _periods(chart).first.children.first;
        expect(
          _value(tester, 'dasha-venus-venus-start'),
          _dateStamp(chart.input, antar.start),
        );
        expect(
          _value(tester, 'dasha-venus-venus-end'),
          _dateStamp(chart.input, antar.end),
        );
        expect(
          _value(tester, 'dasha-venus-venus-start'),
          endsWith('UTC−05:00'),
        );
        expect(_value(tester, 'dasha-venus-venus-end'), endsWith('UTC−04:00'));
        await _tap(tester, 'dasha-open-venus-venus');
        expect(_value(tester, 'dasha-detail-start'), endsWith('UTC−05:00'));
        expect(_value(tester, 'dasha-detail-end'), endsWith('UTC−04:00'));
        expect(_value(tester, 'dasha-detail-zone'), 'America/New_York');
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'historical endpoint offsets retain their seconds',
      (tester) async {
        final chart = _chart(
          input: AstrologyInput(
            utc: DateTime.utc(1900, 1, 2, 12),
            place: const AstrologyPlace(
              name: 'Paris',
              latitude: 48.85,
              longitude: 2.35,
              timeZone: 'Europe/Paris',
            ),
          ),
        );
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
        );
        expect(_value(tester, 'dasha-venus-start'), endsWith('UTC+00:09:21'));
        final trail = _firstDashaPath(_periods(chart).first);
        await _openDashaPath(tester, trail);
        _expectDashaPage(tester, chart, trail);
        expect(_value(tester, 'dasha-detail-start'), endsWith('UTC+00:09:21'));
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'Sookshma shows sub-day duration and exact fractional endpoint seconds',
      (tester) async {
        final chart = _chart(
          moonLongitude: 17.12345,
          input: AstrologyInput(
            utc: DateTime.utc(2024, 7, 2, 16, 23, 41, 123, 456),
            place: _place,
            utcOffsetMinutes: 330,
          ),
        );
        final sun = _periods(chart)
            .firstWhere((period) => period.lord == VedicBody.sun);
        final trail = _firstDashaPath(sun);
        final leaf = trail.last;
        final duration = leaf.end.difference(leaf.start);
        expect(duration.inDays, 0);
        expect(duration.inHours, 6);
        expect(duration.inMinutes % 60, 34);
        await tester.pumpWidget(
          _dashaApp(
            AstrologyDashaTable(chart: chart, at: leaf.start),
            size: const Size(720, 540),
          ),
        );
        await _openDashaPath(tester, trail.take(3).toList());
        final path = _dashaPath(trail);
        expect(
          _value(tester, 'dasha-$path-start'),
          _dateStamp(chart.input, leaf.start),
        );
        expect(
          _value(tester, 'dasha-$path-end'),
          _dateStamp(chart.input, leaf.end),
        );
        await _tap(tester, 'dasha-$path-end');
        _expectDashaPage(tester, chart, trail);
        final start = _value(tester, 'dasha-detail-start');
        final end = _value(tester, 'dasha-detail-end');
        expect(start, matches(RegExp(r'\d{2}:\d{2}:\d{2}\.\d{6}\nUTC\+05:30')));
        expect(end, matches(RegExp(r'\d{2}:\d{2}:\d{2}\.\d{6}\nUTC\+05:30')));
        expect(start, isNot(end));
        expect(_value(tester, 'dasha-detail-duration'), startsWith('6h 34m '));
        final secondPart = duration.inSeconds % 60;
        final fraction =
            (duration.inMicroseconds % Duration.microsecondsPerSecond)
                .toString()
                .padLeft(6, '0');
        expect(
          _value(tester, 'dasha-detail-duration'),
          endsWith('$secondPart.${fraction}s'),
        );
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'a fixed UTC offset overrides IANA rules through all four levels',
      (tester) async {
        final chart = _chart(
          input: AstrologyInput(
            utc: DateTime.utc(2024, 7, 2, 16),
            utcOffsetMinutes: 330,
            place: const AstrologyPlace(
              name: 'New York with explicit offset',
              latitude: 40.71,
              longitude: -74.01,
              timeZone: 'America/New_York',
            ),
          ),
        );
        final trail = _firstDashaPath(_periods(chart).first);
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
        );
        for (var level = 0; level < 4; level++) {
          final path = _dashaPath(trail.take(level + 1));
          expect(_value(tester, 'dasha-$path-start'), endsWith('UTC+05:30'));
          expect(_value(tester, 'dasha-$path-end'), endsWith('UTC+05:30'));
          await _tap(tester, 'dasha-open-$path');
          expect(
            _value(tester, 'dasha-detail-zone'),
            'America/New_York · fixed UTC offset override',
          );
        }
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'navigation resets only the owned scroll, never the enclosing dashboard',
      (tester) async {
        final outer = ScrollController(initialScrollOffset: 120);
        final chart = _chart();
        final trail = _firstDashaPath(_periods(chart).first);
        try {
          await tester.pumpWidget(
            _dashaApp(
              SingleChildScrollView(
                controller: outer,
                child: Column(
                  children: [
                    const SizedBox(height: 160),
                    SizedBox(
                      height: 200,
                      child: AstrologyDashaTable(chart: chart, at: chart.utc),
                    ),
                    const SizedBox(height: 600),
                  ],
                ),
              ),
            ),
          );
          final controller = _dashaController(tester);
          expect(controller, isNot(same(outer)));
          final outerOffset = outer.offset;
          for (var length = 1; length <= 4; length++) {
            final path = _dashaPath(trail.take(length));
            controller.jumpTo(controller.position.maxScrollExtent);
            await tester.pump();
            // Invoke the real tile callback without ensureVisible, which would
            // itself move the enclosing viewport and invalidate this regression.
            tester.widget<InkWell>(_key('dasha-open-$path')).onTap!();
            await tester.pumpAndSettle();
            expect(controller.offset, 0);
            expect(outer.offset, outerOffset);
          }
          for (final id in [
            'dasha-back',
            'dasha-breadcrumb-0',
            'dasha-breadcrumb-root',
          ]) {
            controller.jumpTo(controller.position.maxScrollExtent);
            await tester.pump();
            tester.widget<TextButton>(_key(id)).onPressed!();
            await tester.pumpAndSettle();
            expect(controller.offset, 0);
            expect(outer.offset, outerOffset);
          }
          tester.widget<TextButton>(_key('dasha-current-period')).onPressed!();
          await tester.pumpAndSettle();
          expect(controller.offset, 0);
          expect(outer.offset, outerOffset);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          outer.dispose();
        }
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'navigator controllers and focus nodes dispose before queued navigation completes',
      (tester) async {
        final chart = _chart();
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
        );
        final controller = _dashaController(tester);
        final navigator =
            tester.widget<Focus>(_key('dasha-navigator-focus')).focusNode!;
        final heading =
            tester.widget<Focus>(_key('dasha-heading-focus')).focusNode!;
        await _tap(tester, 'dasha-open-venus');
        final back = tester.widget<TextButton>(_key('dasha-back')).focusNode!;
        back.requestFocus();
        await tester.pump();
        tester.widget<InkWell>(_key('dasha-open-venus-venus')).onTap!();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(controller.hasClients, isFalse);
        expect(() => controller.addListener(_noop), throwsFlutterError);
        for (final node in [navigator, heading, back]) {
          expect(() => node.addListener(_noop), throwsFlutterError);
          expect(FocusManager.instance.primaryFocus, isNot(same(node)));
        }
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'frozen chart inputs survive navigation, themes and reading updates',
      (tester) async {
        final frozen = _frozenDashaChart(_chart());
        final chart = _CountingChart(frozen);
        final fingerprint = chart.input.fingerprint;
        final planets = List<VedicPlacement>.of(chart.planets);
        final points = List<VedicPlacement>.of(chart.specialLagnas);
        final trail = _firstDashaPath(_periods(frozen).first);
        await tester.pumpWidget(
          _dashaApp(AstrologyDashaTable(chart: chart, at: chart.utc)),
        );
        final reads = chart.planetReads;
        await _openDashaPath(tester, trail);
        await _tap(tester, 'dasha-details');
        await _tap(tester, 'dasha-current-period');
        await tester.pumpWidget(
          _dashaApp(
            AstrologyDashaTable(chart: chart, at: trail.last.start),
            paper: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(chart.planetReads, reads);
        expect(chart.input.fingerprint, fingerprint);
        expect(chart.planets, orderedEquals(planets));
        expect(chart.specialLagnas, orderedEquals(points));
        expect(chart.input, same(frozen.input));
        expect(() => chart.planets.add(planets.first), throwsUnsupportedError);
        expect(() => chart.specialLagnas.clear(), throwsUnsupportedError);
        await _finishDasha(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    for (final setting in const [
      (disable: true, accessible: false),
      (disable: false, accessible: true),
    ]) {
      testWidgets(
        'reduced motion $setting mounts one page with no clock or transition',
        (tester) async {
          final chart = _chart();
          final trail = _firstDashaPath(_periods(chart).first);
          await tester.pumpWidget(
            _dashaApp(
              AstrologyDashaTable(chart: chart),
              disableAnimations: setting.disable,
              accessibleNavigation: setting.accessible,
            ),
          );
          await _tap(tester, 'dasha-details');
          final reading = _value(tester, 'dasha-reading-date');
          for (var level = 0; level < 4; level++) {
            await _tap(
              tester,
              'dasha-open-${_dashaPath(trail.take(level + 1))}',
            );
            _expectDashaPage(tester, chart, trail.take(level + 1).toList());
          }
          await tester.pump(const Duration(seconds: 2));
          expect(_value(tester, 'dasha-reading-date'), reading);
          expect(find.byType(AnimatedSwitcher), findsNothing);
          expect(tester.binding.hasScheduledFrame, isFalse);
          await _finishDasha(tester);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  });

  group('shadbala', () {
    const required = [300.0, 360.0, 300.0, 420.0, 390.0, 330.0, 300.0];

    String percentageLabel(double total, double minimum) {
      final rounded = (total / minimum * 100).toStringAsFixed(1);
      return '${rounded.replaceFirst(RegExp(r'\.0$'), '')}%';
    }

    for (final appearance in const [
      (name: 'light', brightness: Brightness.light, paper: false),
      (name: 'dark', brightness: Brightness.dark, paper: false),
      (name: 'paper', brightness: Brightness.light, paper: true),
    ]) {
      testWidgets(
        '${appearance.name} startup and hover leave all seven bars unselected',
        _withSemantics((tester) async {
          final chart = _chart();
          final sun = calculateShadbala(chart).first;
          await tester.pumpWidget(
            _app(
              AstrologyShadbalaView(chart: chart),
              brightness: appearance.brightness,
              paper: appearance.paper,
            ),
          );
          await tester.pumpAndSettle();
          _expectShadbalaSelection(tester, null);
          expect(
            tester
                .widget<DropdownButton<VedicBody>>(
                  _key('shadbala-breakdown-body'),
                )
                .value,
            VedicBody.sun,
          );
          expect(_value(tester, 'shadbala-motion'), 'Sun · ${sun.motion}');
          for (final entry in sun.breakdown.entries) {
            expect(
              _value(tester, 'shadbala-breakdown-${entry.key}-value'),
              entry.value.toStringAsFixed(2),
            );
          }
          await tester.ensureVisible(_key('shadbala-graph'));
          await tester.pumpAndSettle();
          final mouse =
              await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          try {
            for (final body in [VedicBody.sun, VedicBody.moon]) {
              await mouse.moveTo(
                tester.getCenter(_key('shadbala-bar-${body.name}')),
              );
              await tester.pumpAndSettle();
              expect(_key('shadbala-hover-${body.name}'), findsOneWidget);
              _expectShadbalaSelection(tester, null, hovered: body);
              expect(_value(tester, 'shadbala-motion'), 'Sun · ${sun.motion}');
            }
            await mouse.moveTo(Offset.zero);
            await tester.pumpAndSettle();
            _expectShadbalaSelection(tester, null);
            for (final body in VedicBody.classical) {
              expect(_key('shadbala-hover-${body.name}'), findsNothing);
            }
          } finally {
            await mouse.removePointer();
          }
          expect(tester.takeException(), isNull);
        }),
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    testWidgets(
      'chart taps and breakdown choices highlight only Mars then Moon',
      _withSemantics((tester) async {
        await tester.pumpWidget(_app(AstrologyShadbalaView(chart: _chart())));
        _expectShadbalaSelection(tester, null);
        await _tap(tester, 'shadbala-bar-mars');
        _expectShadbalaSelection(tester, VedicBody.mars);
        expect(_value(tester, 'shadbala-motion'), startsWith('Mars ·'));
        expect(
          tester
              .widget<DropdownButton<VedicBody>>(
                _key('shadbala-breakdown-body'),
              )
              .value,
          VedicBody.mars,
        );
        await _choose(tester, 'shadbala-breakdown-body', 'Moon');
        await tester.ensureVisible(_key('shadbala-graph'));
        await tester.pumpAndSettle();
        _expectShadbalaSelection(tester, VedicBody.moon);
        expect(_value(tester, 'shadbala-motion'), startsWith('Moon ·'));
        expect(
          tester
              .widget<DropdownButton<VedicBody>>(
                _key('shadbala-breakdown-body'),
              )
              .value,
          VedicBody.moon,
        );
        expect(tester.takeException(), isNull);
      }),
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    testWidgets(
      'focus and Tab do not select until Enter or Space activates a planet',
      _withSemantics((tester) async {
        await tester.pumpWidget(_app(AstrologyShadbalaView(chart: _chart())));
        FocusNode focusFor(VedicBody body) => tester
            .widget<FocusableActionDetector>(
              _key('shadbala-bar-${body.name}'),
            )
            .focusNode!;
        focusFor(VedicBody.sun).requestFocus();
        await tester.pumpAndSettle();
        expect(focusFor(VedicBody.sun).hasFocus, isTrue);
        expect(_key('shadbala-hover-sun'), findsOneWidget);
        _expectShadbalaSelection(tester, null);
        await _press(tester, LogicalKeyboardKey.tab);
        expect(focusFor(VedicBody.moon).hasFocus, isTrue);
        _expectShadbalaSelection(tester, null);
        expect(_value(tester, 'shadbala-motion'), startsWith('Sun ·'));
        focusFor(VedicBody.moon).unfocus();
        await tester.pumpAndSettle();
        expect(_key('shadbala-hover-moon'), findsNothing);
        _expectShadbalaSelection(tester, null);

        focusFor(VedicBody.sun).requestFocus();
        await tester.pumpAndSettle();
        _expectShadbalaSelection(tester, null);
        await _press(tester, LogicalKeyboardKey.enter);
        _expectShadbalaSelection(tester, VedicBody.sun);
        await _press(tester, LogicalKeyboardKey.tab);
        expect(focusFor(VedicBody.moon).hasFocus, isTrue);
        _expectShadbalaSelection(tester, VedicBody.sun);
        await _press(tester, LogicalKeyboardKey.space);
        _expectShadbalaSelection(tester, VedicBody.moon);
        expect(_value(tester, 'shadbala-motion'), startsWith('Moon ·'));
        await _press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusFor(VedicBody.mars).hasFocus, isTrue);
        _expectShadbalaSelection(tester, VedicBody.moon);
        expect(tester.takeException(), isNull);
      }),
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

    for (final selected in const <VedicBody?>[null, VedicBody.mars]) {
      testWidgets(
        'chart changes and view toggles preserve ${selected?.label ?? 'no'} selection',
        _withSemantics((tester) async {
          await tester.pumpWidget(_app(AstrologyShadbalaView(chart: _chart())));
          if (selected != null) {
            await _tap(tester, 'shadbala-bar-${selected.name}');
          }
          _expectShadbalaSelection(tester, selected);
          await _tap(tester, 'shadbala-breakdown-body');
          await _press(tester, LogicalKeyboardKey.escape);
          await tester.ensureVisible(_key('shadbala-graph'));
          await tester.pumpAndSettle();
          _expectShadbalaSelection(tester, selected);
          for (var toggle = 0; toggle < 2; toggle++) {
            await _tap(tester, 'shadbala-method-details-toggle');
            await tester.ensureVisible(_key('shadbala-graph'));
            await tester.pumpAndSettle();
            _expectShadbalaSelection(tester, selected);
          }
          await tester.pumpWidget(
            _app(AstrologyShadbalaView(chart: _chart(moonLongitude: 80))),
          );
          await tester.ensureVisible(_key('shadbala-graph'));
          await tester.pumpAndSettle();
          _expectShadbalaSelection(tester, selected);
          await _tap(tester, 'shadbala-table-toggle');
          expect(_key('shadbala-graph'), findsNothing);
          await tester.pumpWidget(
            _app(AstrologyShadbalaView(chart: _chart(moonLongitude: 120))),
          );
          await tester.pumpAndSettle();
          expect(_key('shadbala-table'), findsOneWidget);
          expect(
            tester
                .widget<DropdownButton<VedicBody>>(
                  _key('shadbala-breakdown-body'),
                )
                .value,
            selected ?? VedicBody.sun,
          );
          await _tap(tester, 'shadbala-graph-toggle');
          await tester.ensureVisible(_key('shadbala-graph'));
          await tester.pumpAndSettle();
          _expectShadbalaSelection(tester, selected);
          if (selected == null) {
            await _choose(tester, 'shadbala-breakdown-body', 'Sun');
            await tester.ensureVisible(_key('shadbala-graph'));
            await tester.pumpAndSettle();
            _expectShadbalaSelection(tester, VedicBody.sun);
          }
          expect(tester.takeException(), isNull);
        }),
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }

    testWidgets(
      'simple Shadbala heading and percent bars leave all raw table values intact',
      (tester) async {
        final chart = _chart();
        final rows = calculateShadbala(chart);
        expect(rows, hasLength(7));
        await tester.pumpWidget(_app(AstrologyShadbalaView(chart: chart)));
        expect(_value(tester, 'shadbala-title'), 'Shadbala');
        expect(_key('shadbala-method'), findsNothing);
        expect(_key('shadbala-method-details'), findsNothing);
        expect(
          _value(tester, 'shadbala-graph-caption'),
          'Strength (% of minimum) · 100% = minimum',
        );
        for (final row in rows) {
          expect(row.kala, isNotNull);
          final sum = row.sthana +
              row.dig +
              row.kala! +
              row.cheshta +
              row.naisargika +
              row.drik;
          final minimum = required[row.body.index];
          final percentage = percentageLabel(sum, minimum);
          expect(row.total, closeTo(sum, 1e-9));
          expect(row.rupas, closeTo(sum / 60, 1e-9));
          expect(row.required, minimum);
          expect(row.ratio, closeTo(sum / minimum, 1e-9));
          expect(
            _value(tester, 'shadbala-bar-${row.body.name}-value'),
            percentage,
          );
          expect(_key('shadbala-bar-${row.body.name}-marker'), findsNothing);
          expect(
            find.descendant(
              of: _key('shadbala-bar-${row.body.name}'),
              matching: find.byType(CustomPaint),
            ),
            findsNothing,
            reason: 'No per-planet required-strength strokes cross the bars.',
          );
          await _tap(tester, 'shadbala-bar-${row.body.name}');
          expect(
            _value(tester, 'shadbala-hover-${row.body.name}-percentage-value'),
            percentage,
          );
          expect(
            _value(tester, 'shadbala-hover-${row.body.name}-total-value'),
            sum.toStringAsFixed(2),
          );
          expect(
            _value(tester, 'shadbala-hover-${row.body.name}-required-value'),
            minimum.toStringAsFixed(2),
          );
          expect(
            _value(tester, 'shadbala-hover-${row.body.name}-ratio-value'),
            (sum / minimum).toStringAsFixed(3),
          );
        }
        await _tap(tester, 'shadbala-table-toggle');
        expect(_value(tester, 'shadbala-title'), 'Shadbala');
        expect(_key('shadbala-method'), findsNothing);
        expect(_key('shadbala-method-details'), findsNothing);
        expect(
          tester.widget<Table>(_key('shadbala-table')).children,
          hasLength(8),
        );
        for (final row in rows) {
          expect(
            _value(tester, 'shadbala-${row.body.name}-name'),
            row.body.label,
          );
          final expected = {
            'sthana': row.sthana,
            'dig': row.dig,
            'kala': row.kala!,
            'cheshta': row.cheshta,
            'naisargika': row.naisargika,
            'drik': row.drik,
            'total': row.total!,
            'rupas': row.rupas!,
            'required': required[row.body.index],
            'ratio': row.total! / required[row.body.index],
          };
          for (final entry in expected.entries) {
            expect(
              _value(tester, 'shadbala-${row.body.name}-${entry.key}'),
              entry.value.toStringAsFixed(entry.key == 'ratio' ? 3 : 2),
            );
          }
        }
        await _tap(tester, 'shadbala-method-details-toggle');
        expect(_value(tester, 'shadbala-title'), 'Shadbala');
        expect(_value(tester, 'shadbala-method'), shadbalaMethod);
        expect(
          _value(tester, 'shadbala-method-details'),
          shadbalaMethodDetails,
        );
        await _choose(tester, 'shadbala-breakdown-body', 'Mars');
        final mars = rows.firstWhere((row) => row.body == VedicBody.mars);
        expect(_value(tester, 'shadbala-motion'), 'Mars · ${mars.motion}');
        for (final entry in mars.breakdown.entries) {
          expect(
            _value(tester, 'shadbala-breakdown-${entry.key}-value'),
            entry.value.toStringAsFixed(2),
          );
        }
        await _tap(tester, 'shadbala-method-details-toggle');
        expect(_key('shadbala-method'), findsNothing);
        expect(_key('shadbala-method-details'), findsNothing);
        await _tap(tester, 'shadbala-graph-toggle');
        expect(_value(tester, 'shadbala-title'), 'Shadbala');
        expect(_key('shadbala-method'), findsNothing);
        expect(_key('shadbala-method-details'), findsNothing);
        expect(_key('shadbala-table'), findsNothing);
        expect(_key('shadbala-graph'), findsOneWidget);
        expect(
          _value(tester, 'shadbala-bar-mars-value'),
          percentageLabel(mars.total!, 300),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
        'polar totals and solar-dependent details stay unavailable, not zero', (
      tester,
    ) async {
      final chart = _chart(polar: true);
      final rows = calculateShadbala(chart);
      await tester.pumpWidget(_app(AstrologyShadbalaView(chart: chart)));
      expect(_value(tester, 'shadbala-title'), 'Shadbala');
      expect(_key('shadbala-method'), findsNothing);
      expect(_key('shadbala-method-details'), findsNothing);
      expect(
        _value(tester, 'shadbala-graph-caption'),
        'Strength (% of minimum) · 100% = minimum · — Unavailable',
      );
      expect(_key('shadbala-unavailable-note'), findsOneWidget);
      for (final row in rows) {
        expect(row.total, isNull);
        expect(_key('shadbala-bar-${row.body.name}-fill'), findsNothing);
        expect(
          _key('shadbala-bar-${row.body.name}-unavailable'),
          findsOneWidget,
        );
        expect(_value(tester, 'shadbala-bar-${row.body.name}-value'), '—');
        await _tap(tester, 'shadbala-bar-${row.body.name}');
        expect(
          _value(tester, 'shadbala-hover-${row.body.name}-percentage-value'),
          'Unavailable',
        );
        expect(
          _value(tester, 'shadbala-hover-${row.body.name}-total-value'),
          'Unavailable',
        );
      }
      await _tap(tester, 'shadbala-table-toggle');
      for (final body in VedicBody.classical) {
        for (final column in ['kala', 'total', 'rupas', 'ratio']) {
          expect(
            _value(tester, 'shadbala-${body.name}-$column'),
            'Unavailable',
          );
        }
        expect(
          _value(tester, 'shadbala-${body.name}-sthana'),
          isNot('Unavailable'),
        );
      }
      for (final component in [
        'Tribhaga',
        'Varsha',
        'Masa',
        'Dina',
        'Hora',
        'Yuddha',
      ]) {
        expect(
          _value(tester, 'shadbala-breakdown-$component-value'),
          'Unavailable',
        );
      }
      expect(
        _value(tester, 'shadbala-breakdown-Uchcha-value'),
        isNot('Unavailable'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'hover exposes real components and selection drives the full breakdown',
        (tester) async {
      final chart = _CountingChart(_chart());
      final rows = calculateShadbala(_chart());
      await tester.pumpWidget(_app(AstrologyShadbalaView(chart: chart)));
      final reads = chart.planetReads;
      await tester.ensureVisible(_key('shadbala-graph'));
      await tester.pump();
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      try {
        await mouse.moveTo(tester.getCenter(_key('shadbala-bar-sun')));
        await tester.pumpAndSettle();
        final sun = rows.first;
        expect(
          _value(tester, 'shadbala-hover-sun-percentage-value'),
          percentageLabel(sun.total!, 300),
          reason: 'Sun: ${sun.total} / 300 * 100, rounded to one decimal.',
        );
        expect(
          find.descendant(
            of: _key('shadbala-hover-sun'),
            matching: find.text('Strength (% of minimum)'),
          ),
          findsOneWidget,
        );
        final metrics = {
          'sthana': sun.sthana,
          'dig': sun.dig,
          'kala': sun.kala!,
          'cheshta': sun.cheshta,
          'naisargika': sun.naisargika,
          'drik': sun.drik,
          'total': sun.total!,
          'rupas': sun.rupas!,
          'required': sun.required,
          'ratio': sun.ratio!,
        };
        for (final entry in metrics.entries) {
          expect(
            _value(tester, 'shadbala-hover-sun-${entry.key}-value'),
            entry.value.toStringAsFixed(entry.key == 'ratio' ? 3 : 2),
          );
        }
        expect(
          _value(tester, 'shadbala-hover-sun-motion-value'),
          'Motion: ${sun.motion}',
        );
        await mouse.moveTo(tester.getCenter(_key('shadbala-bar-moon')));
        await tester.pumpAndSettle();
        expect(_key('shadbala-hover-sun'), findsNothing);
        expect(_key('shadbala-hover-moon'), findsOneWidget);
        expect(
          _value(tester, 'shadbala-hover-moon-percentage-value'),
          percentageLabel(rows[VedicBody.moon.index].total!, 360),
        );
        expect(_value(tester, 'shadbala-motion'), 'Sun · ${sun.motion}');
        // Even an overlapping details portal must not consume another bar tap.
        await _tap(tester, 'shadbala-bar-mercury');
        final mercury = rows[VedicBody.mercury.index];
        expect(
          _value(tester, 'shadbala-motion'),
          'Mercury · ${mercury.motion}',
        );
        for (final entry in mercury.breakdown.entries) {
          expect(
            _value(tester, 'shadbala-breakdown-${entry.key}-value'),
            entry.value.toStringAsFixed(2),
          );
        }
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        expect(
          _value(tester, 'shadbala-motion'),
          'Mercury · ${mercury.motion}',
        );
      } finally {
        await mouse.removePointer();
      }
      final venus = tester.widget<FocusableActionDetector>(
        _key('shadbala-bar-venus'),
      );
      venus.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(_key('shadbala-hover-venus'), findsOneWidget);
      expect(_value(tester, 'shadbala-motion'), startsWith('Mercury ·'));
      await _press(tester, LogicalKeyboardKey.space);
      expect(_value(tester, 'shadbala-motion'), startsWith('Venus ·'));
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_key('shadbala-hover-saturn'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(_value(tester, 'shadbala-motion'), startsWith('Saturn ·'));
      expect(chart.planetReads, reads);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'simple heading and relative labels survive light, dark, paper and 2x text',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final chart = _chart();
        final rows = calculateShadbala(chart);
        for (final appearance in const [
          (name: 'light', brightness: Brightness.light, paper: false),
          (name: 'dark', brightness: Brightness.dark, paper: false),
          (name: 'paper', brightness: Brightness.light, paper: true),
        ]) {
          for (final scale in [1.0, 2.0]) {
            for (final width in [220.0, 1360.0]) {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pumpWidget(
                _app(
                  AstrologyShadbalaView(chart: chart),
                  size: Size(width, 760),
                  brightness: appearance.brightness,
                  paper: appearance.paper,
                  weight: FontWeight.w300,
                  textScaler: TextScaler.linear(scale),
                ),
              );
              expect(_value(tester, 'shadbala-title'), 'Shadbala');
              expect(_key('shadbala-title').hitTestable(), findsOneWidget);
              expect(_key('shadbala-method'), findsNothing);
              expect(_key('shadbala-method-details'), findsNothing);
              expect(
                _value(tester, 'shadbala-graph-caption'),
                'Strength (% of minimum) · 100% = minimum',
              );
              final heading = _selectable(tester, 'shadbala-title');
              expect(heading.style!.fontWeight, FontWeight.w300);
              expect(
                MediaQuery.textScalerOf(tester.element(_key('shadbala-title')))
                    .scale(15),
                15 * scale,
              );
              final surface = _key('astrology-shadbala-surface');
              final palette = AstrologyPalette.of(tester.element(surface));
              expect(tester.widget<ColoredBox>(surface).color, palette.surface);
              expect(heading.style!.color, palette.ink);
              expect(
                Theme.of(tester.element(surface)).brightness,
                appearance.brightness,
              );
              if (appearance.paper) {
                expect(palette.surface, PaperTheme.editorPreviewBackground);
              }
              var numberCount = 0;
              for (final row in rows) {
                final key = 'shadbala-bar-${row.body.name}-value';
                if (_key(key).evaluate().isEmpty) continue;
                numberCount++;
                expect(
                  _value(tester, key),
                  percentageLabel(row.total!, required[row.body.index]),
                );
                expect(
                  _value(tester, key),
                  isNot(row.total!.toStringAsFixed(2)),
                );
              }
              expect(
                numberCount,
                greaterThan(0),
                reason: 'The pannable host reserves room for percentage text.',
              );
              expect(find.byType(ErrorWidget), findsNothing);
              expect(
                tester.takeException(),
                isNull,
                reason: '${appearance.name}, $width px, ${scale}x text',
              );
            }
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('ashtakavarga', () {
    test(
        'sign-only calculation retains eight BAV totals and SAV 337 without Lagna BAV',
        () {
      for (final signs in [
        List.filled(8, 0),
        [0, 1, 2, 3, 4, 5, 6, 7],
        [11, 2, 9, 4, 7, 0, 6, 8],
      ]) {
        final result = ashtakavargaForSigns(signs);
        expect(result.bhinna.map(_sum), _bavTotals);
        expect(_sum(result.sarva), 337);
        expect(result.bhinna.map(_sum).reduce((a, b) => a + b), 386);
        for (var sign = 0; sign < 12; sign++) {
          expect(
            result.sarva[sign],
            _sum(result.bhinna.take(7).map((bav) => bav[sign])),
          );
          for (var subject = 0; subject < 8; subject++) {
            expect(
              _sum(
                result.prastara[subject]
                    .map((contributor) => contributor[sign]),
              ),
              result.bhinna[subject][sign],
            );
            expect(result.bhinna[subject][sign], inInclusiveRange(0, 8));
          }
        }
      }
      final aligned = ashtakavargaForSigns(List.filled(8, 0));
      expect(
        aligned.prastara[0].map((source) => source[0]),
        [1, 0, 1, 0, 0, 0, 1, 0],
      );
    });

    testWidgets('overview contains SAV and all eight BAVs, with style override',
        (
      tester,
    ) async {
      final chart = _chart();
      final result = calculateAshtakavarga(chart);
      await tester.pumpWidget(
        _app(
          AstrologyAshtakavargaView(
            chart: chart,
            style: IndianChartStyle.south,
          ),
        ),
      );
      expect(_value(tester, 'ashtakavarga-sav-total'), 'SAV · 337 bindus');
      expect(
        tester.widget<DropdownButton<int>>(_key('ashtakavarga-subject')).value,
        -1,
      );
      final charts = tester
          .widgetList<VedicChartView>(find.byType(VedicChartView))
          .toList();
      expect(charts, hasLength(9));
      expect(charts.first.centerLabel, 'SAV');
      expect(charts.first.bindus, result.sarva);
      expect(charts.last.centerLabel, 'Lagna BAV');
      for (var index = 0; index < charts.length; index++) {
        expect(charts[index].style, IndianChartStyle.south);
        if (index > 0) {
          expect(charts[index].bindus, result.bhinna[index - 1]);
          expect(
            _value(tester, 'ashtakavarga-grid-total-${index - 1}'),
            '${_bavTotals[index - 1]} bindus',
          );
        }
      }
      expect(
        tester.widget<Table>(_key('ashtakavarga-signs-table')).children,
        hasLength(13),
      );
      for (var sign = 0; sign < 12; sign++) {
        expect(
          _value(tester, 'ashtakavarga-points-$sign'),
          '${result.sarva[sign]}',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'chooses every BAV and exposes contributor sums for a chosen sign', (
      tester,
    ) async {
      final chart = _chart();
      final result = calculateAshtakavarga(chart);
      await tester.pumpWidget(_app(AstrologyAshtakavargaView(chart: chart)));
      for (var subject = 0; subject < 8; subject++) {
        final name =
            subject == 7 ? 'Lagna' : VedicBody.classical[subject].label;
        await _choose(tester, 'ashtakavarga-subject', '$name BAV');
        expect(find.byType(VedicChartView), findsOneWidget);
        final view = tester.widget<VedicChartView>(find.byType(VedicChartView));
        expect(view.bindus, result.bhinna[subject]);
        expect(view.style, chart.input.style);
        expect(
          _value(tester, 'ashtakavarga-selected-total'),
          '$name BAV · ${_bavTotals[subject]} bindus',
        );
        for (var sign = 0; sign < 12; sign++) {
          expect(
            _value(tester, 'ashtakavarga-points-$sign'),
            '${result.bhinna[subject][sign]}',
          );
        }
      }
      await _choose(tester, 'ashtakavarga-subject', 'Sun BAV');
      await _tap(tester, 'ashtakavarga-contributions-toggle');
      await _choose(tester, 'ashtakavarga-contribution-sign', 'Virgo');
      expect(
        _value(tester, 'ashtakavarga-prastara-title'),
        'Prastara · Sun BAV · Virgo',
      );
      expect(
        tester.widget<Table>(_key('ashtakavarga-prastara-table')).children,
        hasLength(9),
      );
      var total = 0;
      for (var contributor = 0; contributor < 8; contributor++) {
        final points =
            int.parse(_value(tester, 'ashtakavarga-contribution-$contributor'));
        expect(points, result.prastara[0][contributor][5]);
        expect(points, inInclusiveRange(0, 1));
        total += points;
      }
      expect(total, result.bhinna[0][5]);
      expect(
        _value(tester, 'ashtakavarga-contribution-total'),
        'Contribution total: $total bindus',
      );

      // SAV includes each Lagna contribution, but never the ninth chart's BAV.
      await _choose(tester, 'ashtakavarga-subject', 'SAV');
      total = 0;
      for (var contributor = 0; contributor < 8; contributor++) {
        final expected = _sum([
          for (var subject = 0; subject < 7; subject++)
            result.prastara[subject][contributor][5],
        ]);
        final points =
            int.parse(_value(tester, 'ashtakavarga-contribution-$contributor'));
        expect(points, expected);
        total += points;
      }
      expect(total, result.sarva[5]);
      expect(_value(tester, 'ashtakavarga-selected-total'), 'SAV · 337 bindus');
      await _tap(tester, 'ashtakavarga-grid-toggle');
      expect(find.byType(VedicChartView), findsNWidgets(9));
      expect(tester.takeException(), isNull);
    });
  });

  final views = <String, Widget Function(AstrologyChart)>{
    'placements': (chart) => AstrologyPlacementsTable(chart: chart),
    'panchanga': (chart) => AstrologyPanchangaView(chart: chart),
    'dasha': (chart) => AstrologyDashaTable(chart: chart, at: chart.utc),
    'shadbala': (chart) => AstrologyShadbalaView(chart: chart),
    'ashtakavarga': (chart) => AstrologyAshtakavargaView(chart: chart),
  };

  for (final entry in views.entries) {
    testWidgets(
        '${entry.key} fills bounded cards at 220×100 and full width in all themes',
        (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final chart = _chart();
      for (final appearance in const [
        (Brightness.light, false),
        (Brightness.light, true),
        (Brightness.dark, false),
      ]) {
        for (final size in const [Size(220, 100), Size(1360, 760)]) {
          await tester.pumpWidget(
            _app(
              entry.value(chart),
              size: size,
              brightness: appearance.$1,
              paper: appearance.$2,
              textScaler: const TextScaler.linear(2),
            ),
          );
          final surface = _key('astrology-${entry.key}-surface');
          expect(tester.getSize(surface), size);
          expect(_key('astrology-${entry.key}-scroll'), findsOneWidget);
          expect(find.byType(RawScrollbar), findsNothing);
          expect(find.byType(Scrollbar), findsNothing);
          final palette = AstrologyPalette.of(tester.element(surface));
          expect(tester.widget<ColoredBox>(surface).color, palette.surface);
          if (appearance.$2) {
            expect(palette.surface, PaperTheme.editorPreviewBackground);
          }
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key}, $appearance, $size, 2× text',
          );
        }
      }
    });
  }

  for (final name in ['shadbala', 'ashtakavarga']) {
    testWidgets('$name recalculates only on a different chart identity', (
      tester,
    ) async {
      final chart = _CountingChart(_chart());
      final build = views[name]!;
      await tester.pumpWidget(_app(build(chart)));
      final reads = chart.planetReads;
      expect(reads, greaterThan(0));
      if (name == 'shadbala') {
        await _tap(tester, 'shadbala-table-toggle');
        await _tap(tester, 'shadbala-graph-toggle');
      } else {
        await _tap(tester, 'ashtakavarga-single-toggle');
        await _choose(tester, 'ashtakavarga-subject', 'Sun BAV');
      }
      await tester.pumpWidget(_app(build(chart), paper: true));
      await tester.pump();
      expect(chart.planetReads, reads);
      final replacement = _CountingChart(_chart(moonLongitude: 80));
      await tester.pumpWidget(_app(build(replacement), paper: true));
      expect(replacement.planetReads, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wide tables have separate owned scroll axes and dispose both', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        AstrologyPlacementsTable(chart: _chart()),
        size: const Size(220, 100),
      ),
    );
    final vertical = tester
        .widget<SingleChildScrollView>(_key('astrology-placements-scroll'));
    final horizontal = tester
        .widget<SingleChildScrollView>(_key('placements-horizontal-scroll'));
    expect(vertical.scrollDirection, Axis.vertical);
    expect(horizontal.scrollDirection, Axis.horizontal);
    expect(vertical.primary, isFalse);
    expect(horizontal.primary, isFalse);
    expect(vertical.padding, const EdgeInsets.all(12));
    expect(horizontal.padding, EdgeInsets.zero);
    expect(find.byType(RawScrollbar), findsNothing);
    expect(find.byType(Scrollbar), findsNothing);
    final v = vertical.controller!;
    final h = horizontal.controller!;
    expect(identical(v, h), isFalse);
    expect(v.position.maxScrollExtent, greaterThan(0));
    expect(h.position.maxScrollExtent, greaterThan(0));
    v.jumpTo(v.position.maxScrollExtent);
    h.jumpTo(h.position.maxScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(v.hasClients, isFalse);
    expect(h.hasClients, isFalse);
    expect(() => v.addListener(_noop), throwsFlutterError);
    expect(() => h.addListener(_noop), throwsFlutterError);
  });

  testWidgets(
      'strength graph and numeric table replace only their horizontal viewport',
      (tester) async {
    await tester.pumpWidget(
      _app(AstrologyShadbalaView(chart: _chart()), size: const Size(220, 100)),
    );
    final vertical = tester
        .widget<SingleChildScrollView>(_key('astrology-shadbala-scroll'))
        .controller!;
    final graph = tester.widget<SingleChildScrollView>(
      _key('shadbala-graph-horizontal-scroll'),
    );
    final horizontal = graph.controller!;
    expect(graph.scrollDirection, Axis.horizontal);
    expect(graph.primary, isFalse);
    expect(identical(horizontal, vertical), isFalse);
    expect(horizontal.position.maxScrollExtent, greaterThan(0));
    expect(vertical.position.maxScrollExtent, greaterThan(0));
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pump();
    await _tap(tester, 'shadbala-table-toggle');
    expect(_key('shadbala-graph-horizontal-scroll'), findsNothing);
    expect(horizontal.hasClients, isFalse);
    expect(() => horizontal.addListener(_noop), throwsFlutterError);
    final table = tester.widget<SingleChildScrollView>(
      _key('shadbala-horizontal-scroll'),
    );
    expect(table.scrollDirection, Axis.horizontal);
    expect(table.controller!.position.maxScrollExtent, greaterThan(0));
    expect(identical(table.controller, vertical), isFalse);
    expect(
      tester
          .widget<SingleChildScrollView>(_key('astrology-shadbala-scroll'))
          .controller,
      same(vertical),
    );
    expect(tester.widget<Table>(_key('shadbala-table')).children, hasLength(8));
    expect(find.byType(RawScrollbar), findsNothing);
    expect(find.byType(Scrollbar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

// The registered test body releases semantics before Flutter's final checks.
Future<void> Function(WidgetTester) _withSemantics(
  Future<void> Function(WidgetTester) body,
) =>
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await body(tester);
      } finally {
        semantics.dispose();
      }
    };

void _expectShadbalaSelection(
  WidgetTester tester,
  VedicBody? selected, {
  VedicBody? hovered,
}) {
  final host = tester.widget<AstrologyStrengthChart>(
    find.byType(AstrologyStrengthChart),
  );
  final graph = tester.widget<AstrologyShadbalaGraph>(
    find.byType(AstrologyShadbalaGraph),
  );
  expect(host.selected, selected);
  expect(graph.selected, selected);
  final palette = AstrologyPalette.of(tester.element(_key('shadbala-graph')));
  for (final body in VedicBody.classical) {
    final prefix = 'shadbala-bar-${body.name}';
    final data =
        tester.getSemantics(_key('$prefix-semantics')).getSemanticsData();
    expect(
      data.hasFlag(ui.SemanticsFlag.isSelected),
      body == selected,
      reason: '${body.label} must not be selected by the breakdown fallback.',
    );
    final highlight = tester.widget<AnimatedContainer>(
      _key('$prefix-highlight'),
    );
    expect(
      (highlight.decoration! as BoxDecoration).color,
      body == selected
          ? palette.selection
          : body == hovered
              ? palette.hover
              : palette.surface.withValues(alpha: 0),
    );
    final fill = tester.widget<DecoratedBox>(_key('$prefix-fill'));
    expect(
      (fill.decoration as BoxDecoration).color,
      body == selected ? palette.accent : palette.planetColor(body),
    );
  }
}

AstrologyChart _chart({
  double sunLongitude = 10,
  double moonLongitude = 20,
  bool polar = false,
  int weekday = 0,
  AstrologyInput? input,
}) {
  final utc = input?.utc ?? DateTime.utc(2000, 1, 2, 6, 15, 30);
  final resolved = input ??
      AstrologyInput(
        name: 'Fabricated chart',
        utc: utc,
        place: _place,
        utcOffsetMinutes: 330,
        dashaYearDays: 360,
      );
  resolved.validate();
  final midnight = DateTime.utc(utc.year, utc.month, utc.day);
  final sunrise = midnight.add(const Duration(minutes: 42, seconds: 11));
  final longitudes = [
    sunLongitude,
    moonLongitude,
    96.0,
    151.0,
    215.0,
    278.0,
    305.0,
    345.0,
    165.0,
  ];
  const speeds = [0.98, 13.2, 0.4, -0.65, 0.08, 1.1, 0.02, -0.05, -0.05];
  return AstrologyChart(
    input: resolved,
    utc: utc,
    julianDay:
        2440587.5 + utc.millisecondsSinceEpoch / Duration.millisecondsPerDay,
    ayanamsaDegrees: 23.85675,
    ascendant: 33,
    midheaven: 301,
    planets: [
      for (final body in VedicBody.values)
        VedicPlacement(
          name: body.label,
          shortName: body.shortName,
          body: body,
          longitude: longitudes[body.index],
          speed: speeds[body.index],
          latitude: body.index * 0.1,
          declination: (body.index - 3) * 2.0,
        ),
    ],
    specialLagnas: polar ? [_specialLagnas.last] : _specialLagnas,
    sunrise: polar ? null : sunrise,
    sunset: polar
        ? null
        : midnight.add(const Duration(hours: 12, minutes: 31, seconds: 47)),
    nextSunrise: polar ? null : sunrise.add(const Duration(days: 1)),
    weekday: weekday,
    localMeanHours:
        (utc.hour + utc.minute / 60 + resolved.place!.longitude / 15) % 24,
    warnings: polar
        ? const ['Solar events unavailable during polar day/night.']
        : const [],
  );
}

class _CountingChart extends AstrologyChart {
  _CountingChart(AstrologyChart chart)
      : super(
          input: chart.input,
          utc: chart.utc,
          julianDay: chart.julianDay,
          ayanamsaDegrees: chart.ayanamsaDegrees,
          ascendant: chart.ascendant,
          midheaven: chart.midheaven,
          planets: chart.planets,
          specialLagnas: chart.specialLagnas,
          sunrise: chart.sunrise,
          sunset: chart.sunset,
          nextSunrise: chart.nextSunrise,
          weekday: chart.weekday,
          localMeanHours: chart.localMeanHours,
          signCrossingsBeforeStation: chart.signCrossingsBeforeStation,
          apparentDiameters: chart.apparentDiameters,
          warnings: chart.warnings,
        );

  int planetReads = 0;

  @override
  VedicPlacement planet(VedicBody body) {
    planetReads++;
    return super.planet(body);
  }
}

Widget _app(
  Widget child, {
  Size size = const Size(760, 540),
  Brightness brightness = Brightness.light,
  bool paper = false,
  FontWeight weight = FontWeight.w600,
  String? fontFamily,
  List<ui.FontVariation>? fontVariations,
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: ThemeData(
        brightness: brightness,
        extensions: [PaperThemeExtension(enabled: paper)],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontWeight: weight,
              fontFamily: fontFamily,
              fontVariations: fontVariations,
            ),
            child: SizedBox.fromSize(
              size: size,
              // Match card/dialog hosts: Expanded gives bounded height but the
              // Column's start alignment deliberately leaves width loose.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: child)],
              ),
            ),
          ),
        ),
      ),
    );

Finder _key(String key) => find.byKey(ValueKey(key));

SelectableText _selectable(WidgetTester tester, String key) =>
    tester.widget<SelectableText>(
      find.descendant(of: _key(key), matching: find.byType(SelectableText)),
    );

String _value(WidgetTester tester, String key) {
  final selectable = find.descendant(
    of: _key(key),
    matching: find.byType(SelectableText),
    matchRoot: true,
  );
  if (selectable.evaluate().isNotEmpty) {
    return tester.widget<SelectableText>(selectable).data!;
  }
  final text = tester.widget<Text>(
    find.descendant(
      of: _key(key),
      matching: find.byType(Text),
      matchRoot: true,
    ),
  );
  return text.data ?? text.textSpan!.toPlainText();
}

Finder _dashaRows() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('dasha-open-');
    });

const _dashaLevels = [
  'Mahadasha',
  'Antardasha',
  'Pratyantardasha',
  'Sookshma dasha',
];

// Real desktop typography/surfaces, but the same purely hand-authored chart
// fixtures as the other table tests: no service, engine or native bootstrap.
Widget _dashaApp(
  Widget child, {
  Size size = const Size(440, 300),
  Brightness brightness = Brightness.light,
  bool paper = false,
  FontWeight? weight,
  String? fontFamily,
  List<ui.FontVariation>? fontVariations,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) =>
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: DesktopAppearance().getThemeData(
        paper
            ? AppTheme.builtins
                .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        brightness,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaler,
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontWeight: weight,
              fontFamily: fontFamily,
              fontVariations: fontVariations,
            ),
            child: SizedBox.fromSize(
              size: size,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: child)],
              ),
            ),
          ),
        ),
      ),
    );

String _dashaPath(Iterable<DashaPeriod> trail) =>
    trail.isEmpty ? 'root' : trail.map((period) => period.lord.name).join('-');

List<DashaPeriod> _firstDashaPath(DashaPeriod root) {
  final trail = [root];
  for (var level = 1; level < 4; level++) {
    trail.add(trail.last.children.first);
  }
  return trail;
}

Future<void> _openDashaPath(
  WidgetTester tester,
  List<DashaPeriod> trail,
) async {
  for (var length = 1; length <= trail.length; length++) {
    await _tap(tester, 'dasha-open-${_dashaPath(trail.take(length))}');
  }
}

ScrollController _dashaController(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(_key('astrology-dasha-scroll'))
    .controller!;

void _expectDashaPage(
  WidgetTester tester,
  AstrologyChart chart,
  List<DashaPeriod> trail,
) {
  expect(_key('dasha-page-${_dashaPath(trail)}'), findsOneWidget);
  expect(
    find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith('dasha-page-');
    }),
    findsOneWidget,
    reason: 'No accordion, offstage ancestors or outgoing routes stay mounted.',
  );
  final visible = trail.isEmpty ? _periods(chart) : trail.last.children;
  expect(
    tester.widgetList<InkWell>(_dashaRows()).map((tile) => tile.key),
    orderedEquals([
      for (final period in visible)
        ValueKey('dasha-open-${_dashaPath([...trail, period])}'),
    ]),
  );
  for (final period in visible) {
    final path = _dashaPath([...trail, period]);
    expect(_value(tester, 'dasha-$path-title'), period.lord.label);
    expect(
      _value(tester, 'dasha-$path-start'),
      _dateStamp(chart.input, period.start),
    );
    expect(
      _value(tester, 'dasha-$path-end'),
      _dateStamp(chart.input, period.end),
    );
    expect(_key('dasha-chevron-$path'), findsOneWidget);
  }
  if (trail.isEmpty) {
    expect(_key('dasha-selected-title'), findsNothing);
    expect(_key('dasha-back'), findsNothing);
  } else {
    final selected = trail.last;
    expect(
      _value(tester, 'dasha-selected-title'),
      '${selected.lord.label} ${_dashaLevels[selected.level]}',
    );
    expect(
      _value(tester, 'dasha-detail-start'),
      _dateStamp(chart.input, selected.start),
    );
    expect(
      _value(tester, 'dasha-detail-end'),
      _dateStamp(chart.input, selected.end),
    );
    expect(_key('dasha-back'), findsOneWidget);
  }
  if (trail.length == 4) {
    expect(_key('dasha-leaf-note'), findsOneWidget);
    expect(_key('dasha-list-heading'), findsNothing);
  } else {
    expect(_value(tester, 'dasha-list-heading'), _dashaLevels[trail.length]);
    expect(_dashaRows(), findsNWidgets(9));
    expect(_key('dasha-leaf-note'), findsNothing);
  }
}

void _expectDashaHealthy(WidgetTester tester) {
  expect(find.byType(RawScrollbar), findsNothing);
  expect(find.byType(Scrollbar), findsNothing);
  expect(find.byType(ErrorWidget), findsNothing);
  expect(tester.takeException(), isNull);
}

Future<void> _finishDasha(WidgetTester tester) async {
  _expectDashaHealthy(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _altLeft(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pumpAndSettle();
}

AstrologyChart _frozenDashaChart(AstrologyChart chart) => AstrologyChart(
      input: chart.input,
      utc: chart.utc,
      julianDay: chart.julianDay,
      ayanamsaDegrees: chart.ayanamsaDegrees,
      ascendant: chart.ascendant,
      midheaven: chart.midheaven,
      planets: List.unmodifiable(chart.planets),
      specialLagnas: List.unmodifiable(chart.specialLagnas),
      sunrise: chart.sunrise,
      sunset: chart.sunset,
      nextSunrise: chart.nextSunrise,
      weekday: chart.weekday,
      localMeanHours: chart.localMeanHours,
      signCrossingsBeforeStation:
          Map.unmodifiable(chart.signCrossingsBeforeStation),
      apparentDiameters: Map.unmodifiable(chart.apparentDiameters),
      ephemerisVersion: chart.ephemerisVersion,
      warnings: List.unmodifiable(chart.warnings),
    );

Future<void> _tap(
  WidgetTester tester,
  String key, {
  ui.PointerDeviceKind kind = ui.PointerDeviceKind.touch,
}) async {
  await tester.ensureVisible(_key(key));
  await tester.pump();
  if (tester.widget(_key(key)) is InkWell) {
    // An expanded/scaled card may be taller than its viewport. Its inset
    // corner remains visible after ensureVisible even when its center is not.
    await tester.tapAt(
      tester.getTopLeft(_key(key)) + const Offset(8, 8),
      kind: kind,
    );
  } else {
    await tester.tap(_key(key), kind: kind);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String key, String label) async {
  await _tap(tester, key);
  final option = find.text(label).last;
  await tester.ensureVisible(option);
  await tester.pump();
  await tester.tap(option);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

List<DashaPeriod> _periods(AstrologyChart chart) => vimshottariPeriods(
      birthUtc: chart.utc,
      moonLongitude: chart.planet(VedicBody.moon).longitude,
      yearDays: chart.input.dashaYearDays,
    );

String _stamp(AstrologyInput input, DateTime utc) {
  final local = AstrologyTime.localTime(input, utc);
  final offset = AstrologyTime.offsetAt(input, utc);
  final seconds = offset.inSeconds.abs() % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)} '
      'UTC${AstrologyTime.offsetLabel(offset)}'
      '${seconds == 0 ? '' : ':${two(seconds)}'}';
}

String _dateStamp(AstrologyInput input, DateTime utc) {
  final local = AstrologyTime.localTime(input, utc);
  final micros = local.millisecond * 1000 + local.microsecond;
  final fraction = micros == 0 ? '' : '.${micros.toString().padLeft(6, '0')}';
  return _stamp(input, utc)
      .replaceFirst(' ', '\n')
      .replaceFirst(' UTC', '$fraction\nUTC');
}

int _sum(Iterable<int> values) => values.fold(0, (sum, value) => sum + value);

void _noop() {}
