import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// The columns Home is laid out on: the same reference grid a dashboard uses.
const homeGridColumns = DashboardPlacement.referenceColumns;

/// The tallest a block can be made, in height units.
const homeMaximumRows = 40;

/// The parts Home is made of before anything is added to it.
enum HomeBlock {
  glance,
  jumpBackIn,
  calendar,
  events,
  reminders;

  static HomeBlock? fromId(String id) {
    for (final block in values) {
      if (block.name == id) return block;
    }
    return null;
  }

  /// Where the part sits on a new Home, and where it goes when put back: the
  /// pages worked on lately across the start, everything else in a rail
  /// beside them.
  HomeBlockPlacement get defaultPlacement => this == HomeBlock.jumpBackIn
      ? const HomeBlockPlacement(span: 8)
      : const HomeBlockPlacement(column: 8, span: 4);

  /// The fewest columns the part still reads well in.
  int get minimumSpan => this == HomeBlock.jumpBackIn ? 4 : 3;

  /// The fewest height units the part can be given: room for its heading and
  /// a little of what is under it.
  int get minimumRows => this == HomeBlock.jumpBackIn ? 4 : 3;
}

const _widgetPrefix = 'widget:';

/// The id a dashboard widget has on Home.
String homeWidgetBlockId(String specId) => '$_widgetPrefix$specId';

/// The dashboard widget a Home block id names, or null for a built-in part.
String? homeWidgetSpecId(String blockId) => blockId.startsWith(_widgetPrefix)
    ? blockId.substring(_widgetPrefix.length)
    : null;

/// Where a block sits on Home's grid, and how big it is.
@immutable
class HomeBlockPlacement {
  const HomeBlockPlacement({
    this.column = 0,
    this.span = homeGridColumns,
    this.rows,
  });

  factory HomeBlockPlacement.fromJson(Map<String, Object?> json) {
    int? read(Object? value) =>
        value is num && value.isFinite ? value.toInt() : null;
    return HomeBlockPlacement(
      column: read(json['x']) ?? 0,
      span: read(json['w']) ?? homeGridColumns,
      rows: read(json['h']),
    ).clamped();
  }

  /// The first column it covers, counted from the start edge.
  final int column;

  /// How many columns it covers.
  final int span;

  /// Its height in height units, or null to be as tall as its content.
  final int? rows;

  int get end => column + span;

  bool overlapsColumns(HomeBlockPlacement other) =>
      column < other.end && other.column < end;

  HomeBlockPlacement copyWith({int? column, int? span, int? rows}) =>
      HomeBlockPlacement(
        column: column ?? this.column,
        span: span ?? this.span,
        rows: rows ?? this.rows,
      );

  /// The same place, as tall as its content again.
  HomeBlockPlacement fitted() => HomeBlockPlacement(column: column, span: span);

  /// At least [span] columns wide, moved towards the start edge only as far
  /// as it must be to stay inside the grid.
  HomeBlockPlacement widened(int span) => this.span >= span
      ? this
      : HomeBlockPlacement(column: column, span: span, rows: rows).clamped();

  /// Inside the grid: at least one column, never past the end edge, and a
  /// height that can be drawn.
  HomeBlockPlacement clamped() {
    final span = this.span.clamp(1, homeGridColumns);
    return HomeBlockPlacement(
      column: column.clamp(0, homeGridColumns - span),
      span: span,
      rows: rows?.clamp(1, homeMaximumRows),
    );
  }

  Map<String, Object?> toJson() => {
        'x': column,
        'w': span,
        if (rows != null) 'h': rows,
      };

  @override
  bool operator ==(Object other) =>
      other is HomeBlockPlacement &&
      other.column == column &&
      other.span == span &&
      other.rows == rows;

  @override
  int get hashCode => Object.hash(column, span, rows);

  @override
  String toString() => 'HomeBlockPlacement($column, $span, ${rows ?? 'fit'})';
}

/// What is on Home, and where.
///
/// [blocks] lists everything on Home in reading order: a built-in part by its
/// name, or a dashboard widget as `widget:<id>`. Each block covers some of the
/// twelve columns of Home's grid and rises as high as the blocks before it
/// allow; read in order, they are also Home in a window too narrow for
/// columns.
///
/// A part is as tall as its content until it is given a height. A widget
/// keeps its place and size in its own placement — the very one its settings
/// panel edits — so it is configured exactly as it is on a dashboard.
@immutable
class HomeArrangement {
  const HomeArrangement({
    required this.blocks,
    this.places = const {},
    this.widgets = const DashboardDocument(),
  });

  factory HomeArrangement.defaults() => const HomeArrangement(
        // The glance card leads, so it still comes first in one column.
        blocks: ['glance', 'jumpBackIn', 'calendar', 'events', 'reminders'],
      );

  factory HomeArrangement.fromJson(Map<String, Object?> json) {
    List<String> ids(Object? value) => [
          if (value is List)
            for (final id in value)
              if (id is String && id.isNotEmpty) id,
        ];
    final stored = json['widgets'];
    final widgets = stored is Map
        ? DashboardDocument.fromJson(Map<String, Object?>.from(stored))
        : const DashboardDocument();
    if (json['blocks'] is! List) {
      return _fromColumns(
        main: ids(json['main']),
        side: ids(json['side']),
        widgets: widgets,
      );
    }
    final places = <String, HomeBlockPlacement>{};
    final storedPlaces = json['places'];
    if (storedPlaces is Map) {
      for (final MapEntry(:key, :value) in storedPlaces.entries) {
        if (key is String && value is Map) {
          places[key] = HomeBlockPlacement.fromJson(
            Map<String, Object?>.from(value),
          );
        }
      }
    }
    return HomeArrangement(
      blocks: ids(json['blocks']),
      places: places,
      widgets: widgets,
    ).normalized();
  }

  /// Home as it was kept before blocks were placed on a grid: a wide column
  /// with a rail beside it, each read from top to bottom.
  static HomeArrangement _fromColumns({
    required List<String> main,
    required List<String> side,
    required DashboardDocument widgets,
  }) {
    // A column on its own took the whole width.
    final inMain = side.isEmpty
        ? const HomeBlockPlacement()
        : HomeBlock.jumpBackIn.defaultPlacement;
    final inSide = main.isEmpty
        ? const HomeBlockPlacement()
        : HomeBlock.glance.defaultPlacement;
    // In one column, the glance card led when it headed the rail.
    final leads = side.isNotEmpty && side.first == HomeBlock.glance.name;
    var arrangement = HomeArrangement(
      blocks: [
        if (leads) side.first,
        ...main,
        ...leads ? side.skip(1) : side,
      ],
      widgets: widgets,
    );
    // A block listed in both was kept in the wide column.
    for (final id in side) {
      arrangement = arrangement.place(id, inSide);
    }
    for (final id in main) {
      arrangement = arrangement.place(id, inMain);
    }
    return arrangement.normalized();
  }

  static const version = 2;

  final List<String> blocks;

  /// Where the built-in parts are, when not where they start.
  final Map<String, HomeBlockPlacement> places;
  final DashboardDocument widgets;

  bool contains(String id) => blocks.contains(id);

  /// The built-in parts that have been taken off Home.
  List<HomeBlock> get missingBlocks => [
        for (final block in HomeBlock.values)
          if (!contains(block.name)) block,
      ];

  DashboardWidgetSpec? widgetFor(String blockId) {
    final id = homeWidgetSpecId(blockId);
    return id == null ? null : widgets.widgetById(id);
  }

  /// Where [id] sits: a part where it was put, or where it starts; a widget
  /// where its own placement says, always with a height.
  HomeBlockPlacement placementOf(String id) {
    final spec = widgetFor(id);
    if (spec != null) {
      final at = spec.placement;
      return HomeBlockPlacement(
        column: at.column,
        span: at.columnSpan,
        rows: math.max(1, at.rowSpan),
      ).clamped();
    }
    return (places[id] ??
            HomeBlock.fromId(id)?.defaultPlacement ??
            const HomeBlockPlacement())
        .clamped();
  }

  HomeArrangement _with({
    List<String>? blocks,
    Map<String, HomeBlockPlacement>? places,
    DashboardDocument? widgets,
  }) =>
      HomeArrangement(
        blocks: blocks ?? this.blocks,
        places: places ?? this.places,
        widgets: widgets ?? this.widgets,
      );

  /// Put [id] at [placement]. A widget always keeps a height: one given
  /// without it keeps the height it had.
  HomeArrangement place(String id, HomeBlockPlacement placement) {
    final at = placement.clamped();
    final spec = widgetFor(id);
    if (spec != null) {
      return _with(
        widgets: widgets.withWidget(
          spec.copyWith(
            placement: spec.placement.copyWith(
              column: at.column,
              columnSpan: at.span,
              rowSpan: at.rows ?? spec.placement.rowSpan,
            ),
          ),
        ),
      );
    }
    if (HomeBlock.fromId(id) == null) return this;
    return _with(places: {...places, id: at});
  }

  /// Read the blocks in [order], then put [id] at [placement]. Blocks that
  /// [order] leaves out keep their places in the reading order.
  HomeArrangement arrange(
    List<String> order, {
    String? id,
    HomeBlockPlacement? placement,
  }) {
    final known = blocks.toSet();
    final seen = <String>{};
    final ordered = [
      for (final block in order)
        if (known.contains(block) && seen.add(block)) block,
    ];
    var next = 0;
    final arranged = _with(
      blocks: [
        for (final block in blocks)
          if (seen.contains(block)) ordered[next++] else block,
      ],
    );
    return id == null || placement == null
        ? arranged
        : arranged.place(id, placement);
  }

  /// Put a part taken off Home back where it first was, after everything
  /// else.
  HomeArrangement add(String id) {
    if (HomeBlock.fromId(id) == null || contains(id)) return this;
    return _with(
      blocks: [...blocks, id],
      places: {...places}..remove(id),
    );
  }

  /// Put a new dashboard widget at the end of Home: a wide one — a table, a
  /// chart — from the start edge, a narrow one at the end edge, by the rail.
  HomeArrangement addWidget(DashboardWidgetSpec spec) {
    final span = spec.placement.columnSpan.clamp(1, homeGridColumns);
    final placed = spec.copyWith(
      placement: spec.placement.copyWith(
        column: span >= homeGridColumns ~/ 2 ? 0 : homeGridColumns - span,
        columnSpan: span,
      ),
    );
    return _with(
      blocks: [...blocks, homeWidgetBlockId(spec.id)],
      widgets: widgets.addWidget(placed),
    );
  }

  /// Take [id] off Home. A widget goes with its settings; a built-in part can
  /// be put back from the add menu.
  HomeArrangement remove(String id) {
    final specId = homeWidgetSpecId(id);
    return _with(
      blocks: [
        for (final block in blocks)
          if (block != id) block,
      ],
      places: {...places}..remove(id),
      widgets: specId == null ? widgets : widgets.withoutWidget(specId),
    );
  }

  /// Adopt the widgets as they are now: a widget deleted from its own
  /// settings panel leaves Home too.
  HomeArrangement withWidgets(DashboardDocument document) =>
      _with(widgets: document).normalized();

  /// Without duplicates, unknown parts, widgets that no longer exist, or
  /// places that say no more than where a part starts.
  HomeArrangement normalized() {
    final seen = <String>{};
    bool keep(String id) {
      if (HomeBlock.fromId(id) == null) {
        final specId = homeWidgetSpecId(id);
        if (specId == null || widgets.widgetById(specId) == null) return false;
      }
      return seen.add(id);
    }

    final blocks = [
      for (final id in this.blocks)
        if (keep(id)) id,
    ];
    var kept = widgets;
    for (final spec in widgets.allWidgets) {
      if (!seen.contains(homeWidgetBlockId(spec.id))) {
        kept = kept.withoutWidget(spec.id);
      }
    }
    final places = <String, HomeBlockPlacement>{};
    for (final MapEntry(:key, :value) in this.places.entries) {
      final part = HomeBlock.fromId(key);
      if (part == null || !seen.contains(key)) continue;
      final at = value.clamped();
      if (at != part.defaultPlacement) places[key] = at;
    }
    return HomeArrangement(blocks: blocks, places: places, widgets: kept);
  }

  Map<String, Object?> toJson() {
    // Builds from before the grid read a wide column and a rail; they still
    // find every block, on the side it mostly sits.
    final main = <String>[];
    final side = <String>[];
    for (final id in blocks) {
      final at = placementOf(id);
      (at.column * 2 + at.span <= homeGridColumns ? main : side).add(id);
    }
    return {
      'version': version,
      'blocks': blocks,
      if (places.isNotEmpty)
        'places': {
          for (final MapEntry(:key, :value) in places.entries)
            key: value.toJson(),
        },
      'main': main,
      'side': side,
      if (widgets.widgetCount > 0) 'widgets': widgets.toJson(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is HomeArrangement &&
      listEquals(other.blocks, blocks) &&
      mapEquals(other.places, places) &&
      other.widgets == widgets;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(blocks),
        Object.hashAllUnordered([
          for (final MapEntry(:key, :value) in places.entries)
            Object.hash(key, value),
        ]),
        widgets,
      );

  @override
  String toString() => 'HomeArrangement($blocks, $places)';
}

/// Home's arrangement for each workspace, kept on this device.
class HomeArrangementStore extends ChangeNotifier {
  HomeArrangementStore({
    KeyValueStorage? storage,
    bool persist = true,
    this.saveDelay = const Duration(milliseconds: 400),
  })  : _storage = storage,
        _persist = persist;

  static const storageKey = 'appflowy_home_layout';

  final KeyValueStorage? _storage;
  final bool _persist;
  final Duration saveDelay;

  HomeArrangement _layout = HomeArrangement.defaults();
  String? _key;
  int _generation = 0;
  bool _dirty = false;
  bool _disposed = false;
  Timer? _save;

  HomeArrangement get arrangement => _layout;

  KeyValueStorage? get _kv => !_persist
      ? null
      : _storage ??
          (getIt.isRegistered<KeyValueStorage>()
              ? getIt<KeyValueStorage>()
              : null);

  /// Read the arrangement kept for [workspaceId].
  Future<void> load(String? workspaceId) async {
    final key = workspaceId == null || workspaceId.isEmpty
        ? storageKey
        : '${storageKey}_$workspaceId';
    if (key == _key || _disposed) return;
    // Anything still unsaved belongs to the workspace being left.
    await flush();
    if (_disposed) return;
    final generation = ++_generation;
    _key = key;
    final kv = _kv;
    if (kv == null) return;
    var next = HomeArrangement.defaults();
    try {
      final stored = await kv.get(key);
      if (stored != null && stored.isNotEmpty) {
        final decoded = jsonDecode(stored);
        if (decoded is Map) {
          next = HomeArrangement.fromJson(Map<String, Object?>.from(decoded));
        }
      }
    } catch (error) {
      Log.warn('The Home layout could not be read: $error');
    }
    // A change made while the stored arrangement was loading wins.
    if (_disposed || generation != _generation || _dirty) return;
    if (next == _layout) return;
    _layout = next;
    notifyListeners();
  }

  void update(HomeArrangement layout) {
    final next = layout.normalized();
    if (next == _layout || _disposed) return;
    _layout = next;
    notifyListeners();
    _dirty = true;
    _scheduleSave();
  }

  /// Home as it first came.
  void reset() => update(HomeArrangement.defaults());

  void _scheduleSave() {
    _save?.cancel();
    if (_kv == null) {
      _dirty = false;
      return;
    }
    _save = Timer(saveDelay, () {
      _save = null;
      unawaited(_write());
    });
  }

  /// Save now rather than after the pause.
  Future<void> flush() async {
    _save?.cancel();
    _save = null;
    if (_dirty) await _write();
  }

  Future<void> _write() async {
    final kv = _kv;
    final key = _key ?? storageKey;
    final layout = _layout;
    _dirty = false;
    if (kv == null) return;
    try {
      await kv.set(key, jsonEncode(layout.toJson()));
    } catch (error) {
      Log.warn('The Home layout could not be saved: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _save?.cancel();
    _save = null;
    if (_dirty) unawaited(_write());
    super.dispose();
  }
}
