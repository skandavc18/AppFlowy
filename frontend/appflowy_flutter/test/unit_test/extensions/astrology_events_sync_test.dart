import 'dart:async';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_date_analysis.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_events_sync.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/protobuf.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

const _place = AstrologyPlace(
  name: 'Bengaluru',
  latitude: 12.97,
  longitude: 77.59,
  timeZone: 'Asia/Kolkata',
);
const _planets = [
  'Sun',
  'Moon',
  'Mars',
  'Mercury',
  'Jupiter',
  'Venus',
  'Saturn',
  'Rahu',
  'Ketu',
];

AstrologyInput _natal([int year = 1990]) => AstrologyInput(
      name: 'Person',
      utc: DateTime.utc(year, 5, 15, 9, 20),
      place: _place,
    );

String _personExtra(AstrologyInput natal) => DashboardMetadata(
      document: buildAstrologyDashboard(
        input: natal,
        library: false,
        libraryId: 'library',
        eventsViewId: 'events',
      ),
    ).mergeIntoExtra('');

List<int> _options(List<String> names) => (SingleSelectTypeOptionPB()
      ..options.addAll([
        for (final name in names)
          SelectOptionPB()
            ..id = 'option-$name'
            ..name = name,
      ]))
    .writeToBuffer();

FieldPB _copy(FieldPB field) => FieldPB()..mergeFromMessage(field);

/// An in-memory events Grid: fields in view order, cells as the Grid's text.
class _Backend implements AstrologyEventsBackend {
  _Backend() {
    views['person'] = ViewPB(
      id: 'person',
      parentViewId: 'library',
      layout: ViewLayoutPB.Document,
      extra: _personExtra(_natal()),
    );
    views['events'] = ViewPB(
      id: 'events',
      parentViewId: 'person',
      layout: ViewLayoutPB.Grid,
      extra: '{"other_feature":{"kept":true}}',
    );
    for (final column in const [
      TemplateColumn.text('Event name'),
      TemplateColumn.date('Date'),
      TemplateColumn.select('Dasha', _planets),
      TemplateColumn.select('Antardasha', _planets),
      TemplateColumn.select('Pratyantardasha', _planets),
      TemplateColumn.text('Notes'),
    ]) {
      schema.add(_field(column));
    }
  }

  final views = <String, ViewPB>{};
  final schema = <FieldPB>[];
  final cells = <String, Map<String, String>>{};
  final dates = <String, DateCellDataPB>{};
  final writes = <String>[];
  final created = <String>[];
  int extraWrites = 0;

  FieldPB _field(TemplateColumn column) => FieldPB(
        id: 'field-${column.name}',
        name: column.name,
        fieldType: column.type,
        typeOptionData: column.type == FieldType.SingleSelect
            ? _options(column.options)
            : null,
      );

  FieldPB named(String name) =>
      schema.singleWhere((field) => field.name == name);

  String cell(String row, String column) =>
      cells[row]?[named(column).id] ?? '';

  void setCell(String row, String column, String value) =>
      (cells[row] ??= {})[named(column).id] = value;

  void addRow(String row, {DateTime? local, bool time = false}) {
    cells[row] = {named('Event name').id: row, named('Notes').id: 'note $row'};
    setDate(row, local, time: time);
  }

  void setDate(String row, DateTime? local, {bool time = false}) {
    if (local == null) {
      dates.remove(row);
      setCell(row, 'Date', '');
      return;
    }
    dates[row] = DateCellDataPB(
      timestamp: Int64(local.millisecondsSinceEpoch ~/ 1000),
      includeTime: time,
    );
    setCell(row, 'Date', '${local.year}-${local.month}-${local.day}');
  }

  Map<String, Object?> marker() =>
      Map<String, Object?>.from(
        decodeViewExtra(views['events']!.extra)['appflowy_astrology_events']
                as Map? ??
            const {},
      );

  @override
  Future<ViewPB> readView(String viewId) async =>
      views[viewId] ?? (throw StateError('No view $viewId'));

  @override
  Future<void> writeViewExtra(String viewId, String extra) async {
    extraWrites++;
    views[viewId]!.extra = extra;
  }

  @override
  Future<void> openDatabase(String viewId) async {}

  @override
  Future<List<FieldPB>> fields(String viewId) async => [
        for (final field in schema) _copy(field),
      ];

  @override
  Future<RepeatedRowTextPB> rows(String viewId) async => RepeatedRowTextPB(
        fieldIds: schema.map((field) => field.id),
        rows: [
          for (final entry in cells.entries)
            RowTextPB(
              rowId: entry.key,
              cells: [for (final field in schema) entry.value[field.id] ?? ''],
            ),
        ],
      );

  @override
  Future<DateCellDataPB> date(String viewId, String fieldId, String rowId) async =>
      dates[rowId] ?? DateCellDataPB();

  @override
  Future<void> writeText(
    String viewId,
    String fieldId,
    String rowId,
    String text,
  ) async {
    final field = schema.singleWhere((field) => field.id == fieldId);
    expect(field.fieldType, FieldType.RichText);
    writes.add('$rowId/${field.name}=$text');
    cells[rowId]![fieldId] = text;
  }

  @override
  Future<void> writeSelect(
    String viewId,
    FieldPB field,
    String rowId,
    String? optionId,
  ) async {
    final options = SingleSelectTypeOptionPB.fromBuffer(
      schema.singleWhere((each) => each.id == field.id).typeOptionData,
    ).options;
    final name = optionId == null
        ? ''
        : options.singleWhere((option) => option.id == optionId).name;
    writes.add('$rowId/${field.name}=$name');
    cells[rowId]![field.id] = name;
  }

  @override
  Future<void> createOption(
    String viewId,
    String fieldId,
    String rowId,
    String name,
  ) async {
    final index = schema.indexWhere((field) => field.id == fieldId);
    final typeOption =
        SingleSelectTypeOptionPB.fromBuffer(schema[index].typeOptionData);
    expect(
      typeOption.options.where((option) => option.name == name),
      isEmpty,
      reason: 'A choice must never be duplicated.',
    );
    typeOption.options.add(
      SelectOptionPB()
        ..id = 'new-$name'
        ..name = name,
    );
    schema[index] = _copy(schema[index])
      ..typeOptionData = typeOption.writeToBuffer();
    created.add(name);
    writes.add('$rowId/${schema[index].name}=$name');
    cells[rowId]![fieldId] = name;
  }

  @override
  Future<FieldPB> createField({
    required String viewId,
    required TemplateColumn column,
    String? afterFieldId,
  }) async {
    final field = _field(column);
    final anchor = schema.indexWhere((each) => each.id == afterFieldId);
    schema.insert(anchor < 0 ? schema.length : anchor + 1, field);
    return field;
  }
}

typedef _Call = ({AstrologyInput natal, DateTime utc});

class _Calculator {
  final calls = <_Call>[];

  Future<AstrologyEventValues> call(AstrologyInput natal, DateTime utc) async {
    calls.add((natal: natal, utc: utc));
    final lords = natal.utc!.year == 1990
        ? const [
            VedicBody.moon,
            VedicBody.saturn,
            VedicBody.mercury,
            VedicBody.venus,
          ]
        : const [
            VedicBody.ketu,
            VedicBody.venus,
            VedicBody.sun,
            VedicBody.moon,
          ];
    return AstrologyEventValues(
      dasha: lords,
      moonNakshatra: 'Rohini, pada 2 · lord Moon',
      transits: {
        for (final body in VedicBody.values)
          body: '${body.label} ${utc.toIso8601String()}',
      },
    );
  }
}

void main() {
  late _Backend backend;
  late _Calculator calculator;
  late StreamController<SubscribeObject> notifications;
  late AstrologyEventsSync sync;

  AstrologyEventsSync newSync() => AstrologyEventsSync(
        backend: backend,
        calculator: calculator.call,
        notifications: notifications.stream,
        settle: const Duration(milliseconds: 5),
      )..start();

  setUp(() {
    backend = _Backend();
    calculator = _Calculator();
    notifications = StreamController<SubscribeObject>.broadcast();
    sync = newSync();
  });

  tearDown(() async {
    await sync.stop();
    await notifications.close();
  });

  test('an existing six-column table gains the new columns once', () async {
    await sync.recalculate('events');
    expect(backend.schema.map((field) => field.name), [
      'Event name',
      'Date',
      ...astrologyDashaColumns,
      astrologyMoonNakshatraColumn,
      ...astrologyTransitColumns,
      astrologyCalculatedForColumn,
      'Notes',
    ]);
    expect(
      backend.schema.map((field) => field.name),
      astrologyLifeEventsTable.columns.map((column) => column.name),
      reason: 'Migrated and newly built tables share one order.',
    );
    expect(
      SingleSelectTypeOptionPB.fromBuffer(
        backend.named('Sookshma dasha').typeOptionData,
      ).options.map((option) => option.name),
      _planets,
    );
    expect(backend.marker()['schema'], 2);
    expect(
      backend.marker()['natal'],
      astrologyEventsNatalKey(_natal()),
    );
    // Other features' metadata on the Grid is preserved.
    expect(
      decodeViewExtra(backend.views['events']!.extra)['other_feature'],
      {'kept': true},
    );

    // A column the user deletes afterwards is never re-created.
    backend.schema.removeWhere((field) => field.name == 'Transit Ketu');
    await sync.stop();
    sync = newSync();
    await sync.recalculate('events');
    expect(
      backend.schema.map((field) => field.name),
      isNot(contains('Transit Ketu')),
    );
  });

  test('a dated event is filled; notes and other rows are untouched',
      () async {
    await sync.recalculate('events');
    backend.addRow('wedding', local: DateTime(2020, 6));
    backend.addRow('idea');
    await sync.recalculate('events');

    final noon = DateTime(2020, 6, 1, 12).toUtc();
    expect(calculator.calls.map((call) => call.utc), [noon]);
    expect(backend.cell('wedding', 'Dasha'), 'Moon');
    expect(backend.cell('wedding', 'Antardasha'), 'Saturn');
    expect(backend.cell('wedding', 'Pratyantardasha'), 'Mercury');
    expect(backend.cell('wedding', 'Sookshma dasha'), 'Venus');
    expect(
      backend.cell('wedding', astrologyMoonNakshatraColumn),
      'Rohini, pada 2 · lord Moon',
    );
    for (final body in VedicBody.values) {
      expect(
        backend.cell('wedding', astrologyTransitColumns[body.index]),
        '${body.label} ${noon.toIso8601String()}',
      );
    }
    expect(
      backend.cell('wedding', astrologyCalculatedForColumn),
      astrologyEventInstant(backend.dates['wedding']!)!.label,
    );
    expect(
      backend.cell('wedding', astrologyCalculatedForColumn),
      contains('noon used'),
    );
    expect(backend.cell('wedding', 'Notes'), 'note wedding');
    expect(backend.writes.where((write) => write.startsWith('idea/')), isEmpty);
    expect(
      sync.status('events').value.message,
      'Calculated 1 of 1 dated event',
    );

    // Converges: an unchanged table performs no further writes.
    final before = backend.writes.length;
    await sync.recalculate('events');
    expect(backend.writes, hasLength(before));
    expect(calculator.calls, hasLength(1));
    expect(sync.status('events').value.message, 'Up to date · 1 dated event');
  });

  test('entries typed before auto-fill are kept; changed dates recalculate',
      () async {
    await sync.recalculate('events');
    backend.addRow('job', local: DateTime(2015, 3, 2, 10, 30), time: true);
    backend.setCell('job', 'Dasha', 'Jupiter');
    await sync.recalculate('events');
    expect(backend.cell('job', 'Dasha'), 'Jupiter');
    expect(backend.cell('job', 'Antardasha'), 'Saturn');
    expect(calculator.calls.single.utc, DateTime(2015, 3, 2, 10, 30).toUtc());
    expect(
      backend.cell('job', astrologyCalculatedForColumn),
      startsWith('2015-03-02 10:30 UTC'),
    );

    // A manual correction after calculation is also kept...
    backend.setCell('job', 'Antardasha', 'Rahu');
    await sync.recalculate('events');
    expect(backend.cell('job', 'Antardasha'), 'Rahu');

    // ...until the date itself changes.
    backend.setDate('job', DateTime(2016, 4, 3, 9), time: true);
    await sync.recalculate('events');
    expect(backend.cell('job', 'Dasha'), 'Moon');
    expect(backend.cell('job', 'Antardasha'), 'Saturn');
    expect(
      backend.cell('job', 'Transit Sun'),
      'Sun ${DateTime(2016, 4, 3, 9).toUtc().toIso8601String()}',
    );
  });

  test('Recalculate replaces edited values', () async {
    await sync.recalculate('events');
    backend.addRow('move', local: DateTime(2021, 1, 9));
    await sync.recalculate('events');
    backend.setCell('move', 'Dasha', 'Ketu');
    backend.setCell('move', 'Transit Moon', 'edited');
    await sync.recalculate('events');
    expect(backend.cell('move', 'Dasha'), 'Ketu');
    await sync.recalculate('events', force: true);
    expect(backend.cell('move', 'Dasha'), 'Moon');
    expect(backend.cell('move', 'Transit Moon'), startsWith('Moon 2021-01-'));
  });

  test('corrected birth details recalculate every event', () async {
    await sync.recalculate('events');
    backend.addRow('a', local: DateTime(2020, 6));
    backend.addRow('b', local: DateTime(2010, 6));
    backend.setCell('b', 'Dasha', 'Mars');
    await sync.recalculate('events');
    expect(backend.cell('b', 'Dasha'), 'Mars');

    backend.views['person']!.extra = _personExtra(_natal(1991));
    await sync.recalculate('events');
    expect(backend.cell('a', 'Dasha'), 'Ketu');
    expect(backend.cell('b', 'Dasha'), 'Ketu');
    expect(backend.cell('b', 'Sookshma dasha'), 'Moon');
    expect(backend.marker()['natal'], astrologyEventsNatalKey(_natal(1991)));
    expect(calculator.calls.last.natal.utc, DateTime.utc(1991, 5, 15, 9, 20));
  });

  test('removing a date clears its calculated values', () async {
    await sync.recalculate('events');
    backend.addRow('trip', local: DateTime(2019, 8, 20));
    await sync.recalculate('events');
    expect(backend.cell('trip', 'Dasha'), 'Moon');
    backend.setDate('trip', null);
    await sync.recalculate('events');
    for (final column in [
      ...astrologyDashaColumns,
      astrologyMoonNakshatraColumn,
      ...astrologyTransitColumns,
      astrologyCalculatedForColumn,
    ]) {
      expect(backend.cell('trip', column), isEmpty, reason: column);
    }
    expect(backend.cell('trip', 'Notes'), 'note trip');
  });

  test('a deleted planet choice is recreated once and reused', () async {
    await sync.recalculate('events');
    final index = backend.schema.indexWhere((field) => field.name == 'Dasha');
    backend.schema[index] = _copy(backend.schema[index])
      ..typeOptionData = _options(
        _planets.where((planet) => planet != 'Moon').toList(),
      );
    backend.addRow('one', local: DateTime(2020));
    backend.addRow('two', local: DateTime(2020, 2));
    await sync.recalculate('events');
    expect(backend.created, ['Moon']);
    expect(backend.cell('one', 'Dasha'), 'Moon');
    expect(backend.cell('two', 'Dasha'), 'Moon');
  });

  test('columns retyped by the user are left alone', () async {
    await sync.recalculate('events');
    final index =
        backend.schema.indexWhere((field) => field.name == 'Transit Mars');
    backend.schema[index] = _copy(backend.schema[index])
      ..fieldType = FieldType.Number;
    backend.addRow('x', local: DateTime(2020));
    await sync.recalculate('events');
    expect(backend.cell('x', 'Transit Mars'), isEmpty);
    expect(backend.cell('x', 'Transit Sun'), isNotEmpty);
  });

  test('database edits trigger a pass; unrelated grids are ignored', () async {
    await sync.recalculate('events');
    backend.views['other'] = ViewPB(
      id: 'other',
      parentViewId: 'somewhere',
      layout: ViewLayoutPB.Grid,
    );
    backend.views['somewhere'] = ViewPB(
      id: 'somewhere',
      layout: ViewLayoutPB.Document,
    );
    backend.addRow('late', local: DateTime(2022, 2, 2));
    for (final id in ['other', 'events']) {
      notifications.add(
        SubscribeObject(
          source: 'Database',
          ty: DatabaseNotification.DidUpdateRow.value,
          id: id,
        ),
      );
    }
    for (var i = 0; i < 100 && backend.cell('late', 'Dasha').isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(backend.cell('late', 'Dasha'), 'Moon');
    expect(
      backend.views['other']!.extra,
      isEmpty,
      reason: 'Nothing is written to an unrelated database.',
    );
  });

  test('a library or unbound grid is not a life-events table', () async {
    backend.views['person']!.extra = DashboardMetadata(
      document: buildAstrologyDashboard(input: _natal()),
    ).mergeIntoExtra('');
    backend.addRow('x', local: DateTime(2020));
    await sync.recalculate('events');
    expect(calculator.calls, isEmpty);
    expect(backend.schema, hasLength(6));
    expect(
      sync.status('events').value.message,
      contains('not a saved horoscope'),
    );
  });

  test('stopping cancels further work', () async {
    await sync.stop();
    backend.addRow('x', local: DateTime(2020));
    await sync.recalculate('events');
    expect(calculator.calls, isEmpty);
    expect(
      backend.schema.firstWhereOrNull((field) => field.name == 'Transit Sun'),
      isNull,
    );
  });
}
