import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/database/domain/select_option_cell_service.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/protobuf.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:nanoid/nanoid.dart';

import 'astrology_dashboard_model.dart';
import 'astrology_date_analysis.dart';
import 'astrology_engine.dart';
import 'astrology_model.dart';
import 'astrology_time.dart';

/// The IO boundary of [AstrologyEventsSync]. Every method throws on failure.
abstract interface class AstrologyEventsBackend {
  Future<ViewPB> readView(String viewId);

  Future<void> writeViewExtra(String viewId, String extra);

  /// Opens (or joins) the database editor before reading.
  Future<void> openDatabase(String viewId);

  Future<List<FieldPB>> fields(String viewId);

  Future<RepeatedRowTextPB> rows(String viewId);

  Future<DateCellDataPB> date(String viewId, String fieldId, String rowId);

  Future<void> writeText(
    String viewId,
    String fieldId,
    String rowId,
    String text,
  );

  /// Selects [optionId], or clears the cell when it is null.
  Future<void> writeSelect(
    String viewId,
    FieldPB field,
    String rowId,
    String? optionId,
  );

  /// Adds a new choice named [name] to [field] and selects it in this row.
  Future<void> createOption(
    String viewId,
    String fieldId,
    String rowId,
    String name,
  );

  Future<FieldPB> createField({
    required String viewId,
    required TemplateColumn column,
    String? afterFieldId,
  });
}

/// Natal settings + an instant → the values of one row.
typedef AstrologyEventsCalculator = Future<AstrologyEventValues> Function(
  AstrologyInput natal,
  DateTime utc,
);

Future<AstrologyEventValues> _calculateEvent(
  AstrologyInput natal,
  DateTime utc,
) async {
  final chart = await AstrologyEngine.instance.calculate(natal);
  final positions = await AstrologyEngine.instance.positions(natal, utc);
  return astrologyEventValues(natal: chart, positions: positions, utc: utc);
}

@immutable
class AstrologyEventsStatus {
  const AstrologyEventsStatus(this.message, {this.busy = false, this.error});

  static const idle = AstrologyEventsStatus('');

  final String message;
  final bool busy;
  final bool? error;
  bool get failed => error ?? false;
}

/// Columns added to existing tables by schema version 2. Earlier columns are
/// never re-created: a renamed/deleted Dasha column stays the user's choice.
const _addedColumns = {
  'Sookshma dasha',
  astrologyMoonNakshatraColumn,
  ...astrologyTransitColumns,
  astrologyCalculatedForColumn,
};
const _markerKey = 'appflowy_astrology_events';
const _schemaVersion = 2;

/// The instant a Date cell denotes, and the label that records it.
///
/// A date without a time means local NOON of the date the Grid displays
/// (device zone), stated in the label; a time is used exactly.
({DateTime utc, String label})? astrologyEventInstant(DateCellDataPB data) {
  if (!data.hasTimestamp()) return null;
  final stored = DateTime.fromMillisecondsSinceEpoch(
    data.timestamp.toInt() * 1000,
  );
  final local = data.includeTime
      ? stored
      : DateTime(stored.year, stored.month, stored.day, 12);
  String two(int value) => value.toString().padLeft(2, '0');
  final date = '${local.year.toString().padLeft(4, '0')}-'
      '${two(local.month)}-${two(local.day)}';
  final clock = '${two(local.hour)}:${two(local.minute)}';
  final zone = 'UTC${AstrologyTime.offsetLabel(local.timeZoneOffset)}';
  return (
    utc: local.toUtc(),
    label: data.includeTime
        ? '$date $clock $zone'
        : '$date $clock $zone · no time given, noon used',
  );
}

/// Only the settings that change calculated values (not style or names).
String astrologyEventsNatalKey(AstrologyInput natal) => jsonEncode({
      'utc': natal.utc?.toUtc().toIso8601String(),
      'lat': natal.place?.latitude,
      'lon': natal.place?.longitude,
      'ayanamsa': natal.ayanamsa.name,
      'adjust': natal.ayanamsaOffsetArcseconds,
      'true_node': natal.trueNode,
      'year_days': natal.dashaYearDays,
    });

class _Binding {
  const _Binding(this.natal);
  final AstrologyInput natal;
}

/// Keeps every saved person's Life events Grid filled from its Date column:
/// the natal Vimshottari lords through Sookshma dasha, the Moon's nakshatra
/// and each graha's transit sign/degree with houses from the natal Lagna and
/// Moon. Values are ordinary cell values; notes and other columns are never
/// touched.
///
/// A row is recalculated when its date (the "Calculated for" label) or the
/// person's birth details change. The first calculation of an older row only
/// fills EMPTY cells, preserving entries typed before this feature existed;
/// [recalculate] with force overwrites every calculated cell.
class AstrologyEventsSync {
  AstrologyEventsSync({
    AstrologyEventsBackend? backend,
    AstrologyEventsCalculator? calculator,
    Stream<SubscribeObject>? notifications,
    this.settle = const Duration(milliseconds: 500),
  })  : _backend = backend ?? const BackendAstrologyEventsBackend(),
        _calculator = calculator ?? _calculateEvent,
        _notifications = notifications;

  static final instance = AstrologyEventsSync();

  final AstrologyEventsBackend _backend;
  final AstrologyEventsCalculator _calculator;
  final Stream<SubscribeObject>? _notifications;
  final Duration settle;

  final Map<String, _EventsTable> _tables = {};
  final Set<String> _ignored = {};
  final Set<String> _resolving = {};
  StreamSubscription<SubscribeObject>? _subscription;
  bool _running = false;

  bool get isRunning => _running;

  /// Listens for edits in any database; unrelated views are recognised once.
  void start() {
    if (_running) return;
    _running = true;
    _subscription =
        (_notifications ?? RustStreamReceiver.shared.observable.stream)
            .listen(_onNotification);
  }

  Future<void> stop() async {
    _running = false;
    for (final table in _tables.values) {
      table.cancel();
    }
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  ValueListenable<AstrologyEventsStatus> status(String viewId) =>
      _table(viewId).status;

  /// The events card is showing [viewId]: bring it up to date now.
  void watch(String viewId) {
    if (!_running || viewId.isEmpty) return;
    _ignored.remove(viewId);
    _table(viewId).schedule(immediate: true);
  }

  /// Runs a pass now (after the natal details change, or on request).
  /// [force] overwrites every calculated cell of every dated row.
  Future<void> recalculate(String viewId, {bool force = false}) {
    if (!_running || viewId.isEmpty) return Future.value();
    _ignored.remove(viewId);
    return _table(viewId).run(force: force);
  }

  _EventsTable _table(String viewId) =>
      _tables.putIfAbsent(viewId, () => _EventsTable(this, viewId));

  void _onNotification(SubscribeObject subject) {
    if (!_running || subject.source != 'Database') return;
    final type = DatabaseNotification.valueOf(subject.ty);
    if (type != DatabaseNotification.DidUpdateRow &&
        type != DatabaseNotification.DidUpdateFields) {
      return;
    }
    final viewId = subject.id;
    if (viewId.isEmpty || _ignored.contains(viewId)) return;
    final table = _tables[viewId];
    if (table != null) {
      table.schedule();
      return;
    }
    if (_resolving.add(viewId)) unawaited(_discover(viewId));
  }

  Future<void> _discover(String viewId) async {
    try {
      final binding = await _resolve(viewId);
      if (!_running) return;
      if (binding == null) {
        _ignored.add(viewId);
      } else {
        _table(viewId).schedule();
      }
    } on Object catch (error) {
      // Possibly transient (the view is still being created): retry later.
      Log.debug('Astrology events: could not inspect $viewId: $error');
    } finally {
      _resolving.remove(viewId);
    }
  }

  /// The saved person whose dashboard binds [viewId] as its Life events.
  Future<_Binding?> _resolve(String viewId) async {
    final view = await _backend.readView(viewId);
    if (view.layout != ViewLayoutPB.Grid || view.parentViewId.isEmpty) {
      return null;
    }
    final parent = await _backend.readView(view.parentViewId);
    if (!parent.isDashboard) return null;
    final document = parent.dashboard!.document;
    if (isAstrologyLibrary(document) ||
        !document.allWidgets
            .any((widget) => widget.type == astrologyInputWidgetType) ||
        astrologyEventsViewId(document) != viewId) {
      return null;
    }
    return _Binding(astrologyInputFromDashboard(document));
  }
}

class _EventsTable {
  _EventsTable(this.sync, this.viewId);

  final AstrologyEventsSync sync;
  final String viewId;
  final status = ValueNotifier<AstrologyEventsStatus>(
    AstrologyEventsStatus.idle,
  );
  Timer? _timer;
  Future<void>? _pass;
  bool _again = false;
  bool _forceAgain = false;
  bool _migrated = false;

  /// Row id → (values last written, consecutive passes that wrote them).
  final Map<String, (String, int)> _attempts = {};

  AstrologyEventsBackend get _backend => sync._backend;

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void schedule({bool immediate = false}) {
    _timer?.cancel();
    _timer = Timer(immediate ? Duration.zero : sync.settle, () {
      _timer = null;
      unawaited(run());
    });
  }

  Future<void> run({bool force = false}) {
    final pending = _pass;
    if (pending != null) {
      _again = true;
      _forceAgain = _forceAgain || force;
      return pending;
    }
    final completion = Completer<void>();
    _pass = completion.future;
    unawaited(() async {
      try {
        var nextForce = force;
        do {
          _again = false;
          final forced = nextForce || _forceAgain;
          _forceAgain = false;
          nextForce = false;
          await _runPass(force: forced);
        } while (_again && sync._running);
      } finally {
        _pass = null;
        completion.complete();
      }
    }());
    return completion.future;
  }

  Future<void> _runPass({required bool force}) async {
    if (!sync._running) return;
    status.value = AstrologyEventsStatus(
      status.value.message,
      busy: true,
      error: status.value.error,
    );
    try {
      status.value = await _fill(force: force);
    } on Object catch (error) {
      Log.warn('Astrology events: $viewId could not be updated: $error');
      status.value = AstrologyEventsStatus(
        'Could not update the calculated columns: $error',
        error: true,
      );
    }
  }

  Future<AstrologyEventsStatus> _fill({required bool force}) async {
    final binding = await sync._resolve(viewId);
    if (binding == null) {
      return const AstrologyEventsStatus(
        'This table is not a saved horoscope’s Life events table.',
      );
    }
    final natal = binding.natal;
    if (natal.utc == null || natal.place == null) {
      return const AstrologyEventsStatus(
        'Save a birth date, time and place to fill events automatically.',
      );
    }
    await _backend.openDatabase(viewId);
    var fields = await _backend.fields(viewId);
    final marker = await _readMarker();
    if (!_migrated && (marker['schema'] as int? ?? 0) < _schemaVersion) {
      fields = await _migrate(fields);
    }
    _migrated = true;

    var columns = _Columns(fields);
    final dateField = columns.byName('Date', FieldType.DateTime);
    if (dateField == null) {
      await _writeMarker(natal: null);
      return const AstrologyEventsStatus(
        'Add a Date column to calculate dashas and transits.',
      );
    }
    final natalKey = astrologyEventsNatalKey(natal);
    final storedKey = marker['natal'];
    final natalChanged = storedKey is String && storedKey != natalKey;
    final rows = await _backend.rows(viewId);
    final index = {
      for (var i = 0; i < rows.fieldIds.length; i++) rows.fieldIds[i]: i,
    };
    String cell(RowTextPB row, FieldPB? field) {
      final position = field == null ? null : index[field.id];
      return position == null || position >= row.cells.length
          ? ''
          : row.cells[position].trim();
    }

    var calculated = 0;
    var dated = 0;
    for (final row in rows.rows) {
      if (!sync._running) break;
      final labelField =
          columns.byName(astrologyCalculatedForColumn, FieldType.RichText);
      final label = cell(row, labelField);
      if (cell(row, dateField).isEmpty) {
        _attempts.remove(row.rowId);
        if (label.isNotEmpty) {
          // The date was removed: its calculated values no longer apply.
          await _write(row, columns, cell, const {}, overwrite: true);
          await _backend.writeText(viewId, labelField!.id, row.rowId, '');
        }
        continue;
      }
      final instant = astrologyEventInstant(
        await _backend.date(viewId, dateField.id, row.rowId),
      );
      if (instant == null) continue;
      dated++;
      final year = instant.utc.year;
      final outside = year < 1800 || year >= 2400;
      final expectedLabel = outside
          ? '${instant.label} · outside 1800–2399, not calculated'
          : instant.label;
      final stale =
          force || natalChanged || (label.isNotEmpty && label != expectedLabel);
      if (!stale && label.isNotEmpty) {
        _attempts.remove(row.rowId);
        continue;
      }
      final values = outside
          ? const <String, String>{}
          : _values(await sync._calculator(natal, instant.utc));
      // Never keep rewriting a row whose cells do not keep what is written
      // (each write triggers another pass): give up after three attempts.
      final signature = '$expectedLabel\u0001${values.values.join('\u0001')}';
      final previous = _attempts[row.rowId];
      final repeats = previous?.$1 == signature ? previous!.$2 : 0;
      if (!force && repeats >= 3) {
        Log.warn('Astrology events: row ${row.rowId} does not keep its values');
        continue;
      }
      final (:writes, :created) = await _write(
        row,
        columns,
        cell,
        values,
        overwrite: stale,
      );
      if (created) {
        // A re-created choice changes the field; later rows must see it.
        fields = await _backend.fields(viewId);
        columns = _Columns(fields);
      }
      var changed = writes > 0;
      if (labelField != null && label != expectedLabel) {
        await _backend.writeText(
          viewId,
          labelField.id,
          row.rowId,
          expectedLabel,
        );
        changed = true;
      }
      if (changed) {
        _attempts[row.rowId] = (signature, repeats + 1);
        calculated++;
      } else {
        _attempts.remove(row.rowId);
      }
    }
    if (sync._running) await _writeMarker(natal: natalKey);
    return AstrologyEventsStatus(
      dated == 0
          ? 'Add a date to an event to fill its dashas and transits.'
          : calculated == 0
              ? 'Up to date · $dated dated '
                  '${dated == 1 ? 'event' : 'events'}'
              : 'Calculated $calculated of $dated dated '
                  '${dated == 1 ? 'event' : 'events'}',
    );
  }

  static Map<String, String> _values(AstrologyEventValues values) => {
        for (var level = 0; level < astrologyDashaColumns.length; level++)
          astrologyDashaColumns[level]:
              level < values.dasha.length ? values.dasha[level].label : '',
        astrologyMoonNakshatraColumn: values.moonNakshatra,
        for (final body in VedicBody.values)
          astrologyTransitColumns[body.index]: values.transits[body] ?? '',
      };

  /// Writes differing cells. Without [overwrite] only empty cells are filled.
  /// [created] reports that a select field gained a choice (new options).
  Future<({int writes, bool created})> _write(
    RowTextPB row,
    _Columns columns,
    String Function(RowTextPB row, FieldPB? field) cell,
    Map<String, String> values, {
    required bool overwrite,
  }) async {
    var created = false;
    var writes = 0;
    for (final name in [
      ...astrologyDashaColumns,
      astrologyMoonNakshatraColumn,
      ...astrologyTransitColumns,
    ]) {
      final field = columns.byName(name);
      if (field == null) continue;
      final desired = values[name] ?? '';
      final current = cell(row, field);
      if (current == desired || (!overwrite && current.isNotEmpty)) continue;
      switch (field.fieldType) {
        case FieldType.RichText:
          await _backend.writeText(viewId, field.id, row.rowId, desired);
          writes++;
        case FieldType.SingleSelect:
          final options =
              SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData).options;
          final option =
              options.firstWhereOrNull((option) => option.name == desired);
          if (desired.isEmpty || option != null) {
            await _backend.writeSelect(viewId, field, row.rowId, option?.id);
          } else {
            await _backend.createOption(viewId, field.id, row.rowId, desired);
            created = true;
          }
          writes++;
        default:
          // A user changed this column's type; leave it alone.
          break;
      }
    }
    return (writes: writes, created: created);
  }

  Future<Map<String, Object?>> _readMarker() async {
    final view = await _backend.readView(viewId);
    final marker = decodeViewExtra(view.extra)[_markerKey];
    return marker is Map ? Map<String, Object?>.from(marker) : {};
  }

  Future<void> _writeMarker({required String? natal}) async {
    final view = await _backend.readView(viewId);
    final extra = view.extra.trim();
    final values = decodeViewExtra(extra);
    // Never replace unreadable metadata with our own.
    if (extra.isNotEmpty && values.isEmpty && extra != '{}') return;
    final current = values[_markerKey];
    final next = <String, Object?>{
      if (current is Map) ...Map<String, Object?>.from(current),
      'schema': _schemaVersion,
      if (natal != null) 'natal': natal,
    };
    if (const DeepCollectionEquality().equals(current, next)) return;
    values[_markerKey] = next;
    await _backend.writeViewExtra(viewId, jsonEncode(values));
  }

  /// Adds the version-2 columns after Pratyantardasha (or at the end).
  Future<List<FieldPB>> _migrate(List<FieldPB> fields) async {
    var anchor =
        fields.firstWhereOrNull((field) => field.name == 'Pratyantardasha')?.id;
    var added = false;
    for (final column in astrologyLifeEventsTable.columns) {
      if (!_addedColumns.contains(column.name)) continue;
      final existing =
          fields.firstWhereOrNull((field) => field.name == column.name);
      if (existing != null) {
        anchor = existing.id;
        continue;
      }
      final created = await _backend.createField(
        viewId: viewId,
        column: column,
        afterFieldId: anchor,
      );
      anchor = created.id;
      added = true;
    }
    await _writeMarker(natal: null);
    return added ? await _backend.fields(viewId) : fields;
  }
}

class _Columns {
  _Columns(List<FieldPB> fields) {
    for (final field in fields) {
      _fields.putIfAbsent(field.name.trim(), () => field);
    }
  }

  final Map<String, FieldPB> _fields = {};

  FieldPB? byName(String name, [FieldType? type]) {
    final field = _fields[name];
    return field == null || (type != null && field.fieldType != type)
        ? null
        : field;
  }
}

/// Uses the same database services as the Grid itself.
class BackendAstrologyEventsBackend implements AstrologyEventsBackend {
  const BackendAstrologyEventsBackend();

  @override
  Future<ViewPB> readView(String viewId) =>
      _value(ViewBackendService.getView(viewId), 'Read view $viewId');

  @override
  Future<void> writeViewExtra(String viewId, String extra) => _value(
        ViewBackendService.updateView(viewId: viewId, extra: extra),
        'Update events metadata for $viewId',
      );

  @override
  Future<void> openDatabase(String viewId) => _value(
        DatabaseEventGetAllRows(DatabaseViewIdPB(value: viewId)).send(),
        'Open events table $viewId',
      );

  @override
  Future<List<FieldPB>> fields(String viewId) => _value(
        FieldBackendService.getFields(viewId: viewId),
        'Read events fields for $viewId',
      );

  @override
  Future<RepeatedRowTextPB> rows(String viewId) => _value(
        DatabaseEventGetRowsAsText(DatabaseViewIdPB(value: viewId)).send(),
        'Read events rows for $viewId',
      );

  @override
  Future<DateCellDataPB> date(
    String viewId,
    String fieldId,
    String rowId,
  ) async {
    final cell = await _value(
      CellBackendService.getCell(
        viewId: viewId,
        cellContext: CellContext(fieldId: fieldId, rowId: rowId),
      ),
      'Read an event date',
    );
    return cell.hasData()
        ? DateCellDataPB.fromBuffer(cell.data)
        : DateCellDataPB();
  }

  @override
  Future<void> writeText(
    String viewId,
    String fieldId,
    String rowId,
    String text,
  ) =>
      _value(
        CellBackendService.updateCell(
          viewId: viewId,
          cellContext: CellContext(fieldId: fieldId, rowId: rowId),
          data: text,
        ),
        'Write an event cell',
      );

  @override
  Future<void> writeSelect(
    String viewId,
    FieldPB field,
    String rowId,
    String? optionId,
  ) {
    final service = SelectOptionCellBackendService(
      viewId: viewId,
      fieldId: field.id,
      rowId: rowId,
    );
    if (optionId != null) {
      return _value(
        service.select(optionIds: [optionId]),
        'Choose an event dasha',
      );
    }
    final options =
        SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData).options;
    return _value(
      service.unselect(optionIds: options.map((option) => option.id)),
      'Clear an event dasha',
    );
  }

  @override
  Future<void> createOption(
    String viewId,
    String fieldId,
    String rowId,
    String name,
  ) =>
      _value(
        SelectOptionCellBackendService(
          viewId: viewId,
          fieldId: fieldId,
          rowId: rowId,
        ).create(name: name),
        'Add the dasha choice $name',
      );

  @override
  Future<FieldPB> createField({
    required String viewId,
    required TemplateColumn column,
    String? afterFieldId,
  }) =>
      _value(
        FieldBackendService.createField(
          viewId: viewId,
          fieldType: column.type,
          fieldName: column.name,
          typeOptionData: column.type == FieldType.SingleSelect
              ? (SingleSelectTypeOptionPB()
                    ..options.addAll([
                      for (final name in column.options)
                        SelectOptionPB()
                          ..id = nanoid(4)
                          ..name = name,
                    ]))
                  .writeToBuffer()
              : null,
          position: afterFieldId == null
              ? null
              : OrderObjectPositionPB(
                  position: OrderObjectPositionTypePB.After,
                  objectId: afterFieldId,
                ),
        ),
        'Add the "${column.name}" column',
      );

  static Future<T> _value<T>(
    Future<FlowyResult<T, FlowyError>> operation,
    String description,
  ) async {
    final result = await operation;
    return result.fold(
      (value) => value,
      (error) => throw StateError('$description: ${error.msg}'),
    );
  }
}
