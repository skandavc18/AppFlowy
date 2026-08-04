import 'dart:async';

import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/database/domain/location_service.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/maps/map_marker.dart';
import 'package:appflowy/workspace/application/maps/map_spec.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/foundation.dart';

/// How long a table is left alone after a change before it is read again.
const _settle = Duration(milliseconds: 350);

/// Column headings that usually hold a place.
const _locationWords = [
  'location',
  'address',
  'place',
  'coordinates',
  'coords',
  'latlng',
  'lat/lng',
  'geo',
  'city',
  'town',
  'country',
  'venue',
  'where',
  'map',
];

/// Turns a table into pins.
///
/// Rows come back as the text the table shows, in one call for the whole view,
/// so a map of thousands of rows costs one round trip rather than one per cell.
/// Anything that is already a point is used at once; only addresses have to be
/// looked up, and what is found is remembered.
class MapSource extends ChangeNotifier {
  MapSource({
    required this.viewId,
    this.apiKey = '',
    this.settle = _settle,
  }) {
    LocationFieldRegistry.instance.revision.addListener(_onMarkedChanged);
  }

  final String viewId;
  final String apiKey;
  final Duration settle;

  MapSpec _spec = const MapSpec();
  List<FieldPB> _fields = const [];
  List<AppMapPin> _pins = const [];
  Timer? _timer;
  bool _loading = false;
  bool _disposed = false;
  int _unplaced = 0;
  int _filled = 0;
  bool _columnMissing = false;
  String? _error;
  int _generation = 0;

  /// The columns the author marked as holding a place.
  Set<String> _marked = const {};

  /// The addresses being looked up right now, keyed the way they are cached.
  ///
  /// Two reads of the same table must not ask for the same place twice, and
  /// counting the set is the only way the pending total cannot drift.
  final Set<String> _looking = {};

  /// Whether the current columns were picked by the source rather than chosen.
  bool _guessed = false;

  void _onMarkedChanged() {
    if (!_disposed) {
      invalidate();
    }
  }

  MapSpec get spec => _spec;
  List<FieldPB> get fields => _fields;
  List<AppMapPin> get pins => _pins;
  bool get isLoading => _loading;

  /// How many addresses are still being looked up.
  int get pendingLookups => _looking.length;

  /// Rows that hold something in the location column that could not be found.
  int get unplaced => _unplaced;

  /// Rows that have anything at all in the location column.
  int get filled => _filled;

  /// Whether the chosen column is not among the ones the table hands back.
  bool get columnMissing => _columnMissing;

  /// What the chosen column is called.
  String get locationColumnName {
    final chosen = _spec.locationColumns;
    if (chosen.isEmpty) {
      return '';
    }
    return _fields
            .firstWhereOrNull((field) => field.id == chosen.first)
            ?.name ??
        '';
  }

  String? get error => _error;

  /// The columns that could hold a place.
  ///
  /// Columns the author marked as locations come first, so the obvious answer
  /// is the one at the top of the list.
  List<FieldPB> get locationCandidates {
    final candidates = _fields
        .where(
          (field) => const [
            FieldType.RichText,
            FieldType.URL,
            FieldType.SingleSelect,
            FieldType.Summary,
          ].contains(field.fieldType),
        )
        .toList();
    candidates.sort((a, b) {
      final marked =
          (_marked.contains(b.id) ? 1 : 0) - (_marked.contains(a.id) ? 1 : 0);
      return marked;
    });
    return candidates;
  }

  void updateSpec(MapSpec spec) {
    if (spec == _spec) {
      return;
    }
    // A host that has never chosen columns keeps whatever was worked out
    // here, so saving the camera does not throw the map back to "pick a
    // column".
    final keepGuess = _guessed && spec.locationColumns.isEmpty;
    final relocate =
        !keepGuess && !listEquals(spec.locationColumns, _spec.locationColumns);
    _spec = keepGuess
        ? spec.copyWith(locationColumns: _spec.locationColumns)
        : spec;
    if (relocate) {
      _guessed = false;
      unawaited(load());
    } else {
      _rebuild();
    }
  }

  Future<void> load() async {
    if (viewId.isEmpty || _loading) {
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    final generation = ++_generation;
    Log.info('[Map] reading $viewId');

    try {
      await GeocodeCache.instance.ensureLoaded();
      _fields = await FieldBackendService.getFields(viewId: viewId)
          .fold((fields) => fields, (_) => const <FieldPB>[]);
      _marked = (await LocationBackendService.locationFieldIds(viewId: viewId))
          .toSet();

      final rows = await DatabaseEventGetRowsAsText(
        DatabaseViewIdPB()..value = viewId,
      ).send().fold<RepeatedRowTextPB?>((rows) => rows, (failure) {
        _error = failure.msg;
        Log.warn('Could not read the table $viewId for a map: $failure');
        return null;
      });
      if (_disposed || generation != _generation || rows == null) {
        return;
      }

      final metas = await DatabaseEventGetAllRows(
        DatabaseViewIdPB()..value = viewId,
      ).send().fold<List<RowMetaPB>>((all) => all.items, (_) => const []);
      if (_disposed || generation != _generation) {
        return;
      }

      _read(rows, metas);
    } on Object catch (error, stack) {
      // A read that fails silently is indistinguishable from an empty table.
      _error = '$error';
      Log.error('[Map] could not read $viewId', error, stack);
    } finally {
      _loading = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  /// Reads the table again shortly, so a burst of edits costs one read.
  void invalidate() {
    _timer?.cancel();
    _timer = Timer(settle, () => unawaited(load()));
  }

  /// Feeds the source a table without going to the backend.
  ///
  /// The counts behind the empty hint are the hardest part of the map to see
  /// from the outside, so they are worth being able to test on their own.
  @visibleForTesting
  void readForTest(
    RepeatedRowTextPB rows, {
    List<FieldPB> fields = const [],
    Set<String> marked = const {},
    List<RowMetaPB> metas = const [],
  }) {
    _fields = fields;
    _marked = marked;
    _read(rows, metas);
  }

  RepeatedRowTextPB? _rows;
  Map<String, RowMetaPB> _metas = const {};

  void _read(RepeatedRowTextPB rows, List<RowMetaPB> metas) {
    _rows = rows;
    _metas = {for (final meta in metas) meta.id: meta};
    if (!_spec.isConfigured || _guessed) {
      final guessed = _guessLocationColumns();
      if (guessed.isNotEmpty) {
        _guessed = true;
        _spec = _spec.copyWith(locationColumns: guessed);
      }
    }
    _describe(rows);
    _rebuild();
    unawaited(_lookUpMissing());
  }

  /// Picks the column that most likely holds a place.
  ///
  /// A table made outside the map has no settings on it, so guessing well is
  /// the difference between a map that works and an empty one.
  List<String> _guessLocationColumns() {
    final rows = _rows;
    if (rows == null || _fields.isEmpty) {
      return const [];
    }
    final byId = {for (final field in _fields) field.id: field};

    // A column the author marked as a location is not a guess at all.
    final marked =
        rows.fieldIds.where(_marked.contains).toList(growable: false);
    if (marked.isNotEmpty) {
      return marked;
    }

    // A heading that names a place wins outright.
    for (final id in rows.fieldIds) {
      final name = byId[id]?.name.toLowerCase() ?? '';
      if (_locationWords.any(name.contains)) {
        return [id];
      }
    }

    // Otherwise, the column whose values actually read as places.
    var best = '';
    var bestScore = 0;
    for (var column = 0; column < rows.fieldIds.length; column++) {
      final id = rows.fieldIds[column];
      final type = byId[id]?.fieldType;
      if (type != FieldType.RichText && type != FieldType.URL) {
        continue;
      }
      var score = 0;
      for (final row in rows.rows.take(24)) {
        if (column >= row.cells.length) {
          continue;
        }
        if (parseMapLocation(row.cells[column]).point != null) {
          score++;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = id;
      }
    }
    return best.isEmpty ? const [] : [best];
  }

  /// Says what was read and which column is being plotted.
  ///
  /// An empty map has three possible causes — the wrong column, empty cells,
  /// or a failed look up — and they are indistinguishable from the outside.
  /// What the cells actually say is the person's own writing, so only how many
  /// of them hold anything is worth recording.
  void _describe(RepeatedRowTextPB rows) {
    final chosen = _spec.locationColumns;
    final at = chosen.isEmpty ? -1 : rows.fieldIds.indexOf(chosen.first);
    final written = at < 0
        ? 0
        : rows.rows
            .where(
              (row) => at < row.cells.length && row.cells[at].trim().isNotEmpty,
            )
            .length;
    final message =
        '[Map] $viewId rows=${rows.rows.length} fields=${rows.fieldIds.length} '
        'column=$chosen at=$at marked=${_marked.length} written=$written';
    Log.info(message);
  }

  void _rebuild() {
    final rows = _rows;
    if (rows == null) {
      return;
    }
    final index = {
      for (var i = 0; i < rows.fieldIds.length; i++) rows.fieldIds[i]: i,
    };
    final names = {for (final field in _fields) field.id: field.name};

    String cell(RowTextPB row, String fieldId) {
      final at = index[fieldId];
      if (at == null || at >= row.cells.length) {
        return '';
      }
      return row.cells[at];
    }

    final titleId = _spec.titleColumn.isNotEmpty
        ? _spec.titleColumn
        : _fields.firstWhereOrNull((field) => field.isPrimary)?.id ?? '';

    // Hovering a pin is meant to preview the row, so with nothing chosen the
    // first few columns stand in rather than an empty card.
    final propertyIds = _spec.propertyColumns.isNotEmpty
        ? _spec.propertyColumns
        : _fields
            .where(
              (field) =>
                  field.id != titleId &&
                  field.id != _spec.subtitleColumn &&
                  !_spec.locationColumns.contains(field.id),
            )
            .take(4)
            .map((field) => field.id)
            .toList();

    final pins = <AppMapPin>[];
    var unplaced = 0;
    var filled = 0;
    for (final row in rows.rows) {
      final location = _locationOf(row, cell);
      if (location.isEmpty) {
        continue;
      }
      filled++;
      final point = location.point ??
          GeocodeCache.instance.peek(geocodeKeyFor(location))?.point;
      if (point == null) {
        unplaced++;
        continue;
      }
      final meta = _metas[row.rowId];
      pins.add(
        AppMapPin(
          id: row.rowId,
          point: point,
          title: titleId.isEmpty ? location.label : cell(row, titleId),
          subtitle: _spec.subtitleColumn.isEmpty
              ? location.label
              : cell(row, _spec.subtitleColumn),
          icon: meta?.hasIcon() == true ? meta!.icon : null,
          coverUrl: _coverOf(meta),
          status: _spec.colorColumn.isEmpty ? '' : cell(row, _spec.colorColumn),
          tags: _tagsOf(row, cell),
          properties: {
            for (final id in propertyIds)
              if (cell(row, id).isNotEmpty) names[id] ?? '': cell(row, id),
          }..remove(''),
          lastModified: row.modifiedAt.toInt() == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  row.modifiedAt.toInt() * 1000,
                ),
        ),
      );
    }

    _pins = List.unmodifiable(pins);
    _unplaced = unplaced;
    _filled = filled;
    _columnMissing = _spec.locationColumns.isNotEmpty &&
        !_spec.locationColumns.any(index.containsKey);
    if (!_disposed) {
      notifyListeners();
    }
  }

  MapLocation _locationOf(
    RowTextPB row,
    String Function(RowTextPB, String) cell,
  ) {
    for (final id in _spec.locationColumns) {
      final parsed = parseMapLocation(cell(row, id));
      if (!parsed.isEmpty) {
        return parsed;
      }
    }
    return MapLocation.empty;
  }

  List<String> _tagsOf(
    RowTextPB row,
    String Function(RowTextPB, String) cell,
  ) {
    if (_spec.colorColumn.isEmpty) {
      return const [];
    }
    // A multi select reads as a comma separated list.
    final value = cell(row, _spec.colorColumn);
    if (!value.contains(',')) {
      return const [];
    }
    return value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  String? _coverOf(RowMetaPB? meta) {
    if (meta == null || !meta.hasCover()) {
      return null;
    }
    final data = meta.cover.data;
    if (data.isEmpty) {
      return null;
    }
    // Only a real picture is worth putting on a card; a colour is not.
    final looksLikeFile =
        data.startsWith('http') || data.contains('/') || data.contains(r'\');
    return looksLikeFile ? data : null;
  }

  /// Finds the places that were written as words rather than coordinates.
  Future<void> _lookUpMissing() async {
    final rows = _rows;
    if (rows == null || !_spec.isConfigured) {
      return;
    }
    final index = {
      for (var i = 0; i < rows.fieldIds.length; i++) rows.fieldIds[i]: i,
    };
    String cell(RowTextPB row, String fieldId) {
      final at = index[fieldId];
      if (at == null || at >= row.cells.length) {
        return '';
      }
      return row.cells[at];
    }

    final wanted = <String, MapLocation>{};
    for (final row in rows.rows) {
      final location = _locationOf(row, cell);
      if (!location.needsLookUp) {
        continue;
      }
      final key = geocodeKeyFor(location);
      if (GeocodeCache.instance.peek(key) != null || _looking.contains(key)) {
        continue;
      }
      wanted[key] = location;
    }
    if (wanted.isEmpty) {
      return;
    }

    final geocoder = resolveGeocoder(apiKey: apiKey);
    _looking.addAll(wanted.keys);
    notifyListeners();

    var found = 0;
    try {
      for (final entry in wanted.entries) {
        if (_disposed) {
          return;
        }
        final result = await geocoder.lookUp(entry.value);
        // A read that started while this was in flight does not undo it: a
        // place costs a second to find, and a table of them takes longer than
        // the map is left alone, so abandoning the queue leaves it half empty.
        if (result != null) {
          GeocodeCache.instance.remember(entry.key, result);
          found++;
        } else {
          Log.warn('No place found for "${entry.value.query}"');
        }
        _looking.remove(entry.key);
        // Showing pins as they are found beats waiting for the whole list.
        if (found > 0 && (_looking.isEmpty || found % 5 == 0)) {
          _rebuild();
        } else if (!_disposed) {
          notifyListeners();
        }
      }
    } finally {
      _looking.removeAll(wanted.keys);
    }
    if (!_disposed) {
      _rebuild();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    LocationFieldRegistry.instance.revision.removeListener(_onMarkedChanged);
    _timer?.cancel();
    super.dispose();
  }
}

extension _FirstWhereOrNull<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}
