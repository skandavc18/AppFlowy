import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

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

  /// The column a part goes back to when it is put on Home again.
  HomeColumn get homeColumn =>
      this == HomeBlock.jumpBackIn ? HomeColumn.main : HomeColumn.side;
}

/// The two columns Home is laid out in: the wide one and the rail beside it.
enum HomeColumn {
  main,
  side;

  HomeColumn get other => this == main ? side : main;
}

const _widgetPrefix = 'widget:';

/// The id a dashboard widget has on Home.
String homeWidgetBlockId(String specId) => '$_widgetPrefix$specId';

/// The dashboard widget a Home block id names, or null for a built-in part.
String? homeWidgetSpecId(String blockId) => blockId.startsWith(_widgetPrefix)
    ? blockId.substring(_widgetPrefix.length)
    : null;

/// What is on Home, and where.
///
/// Each column is a list of block ids from top to bottom: a built-in part by
/// its name, or a dashboard widget as `widget:<id>`. The widgets themselves are
/// kept as a small dashboard, so they are configured with the very same panel
/// a dashboard uses and read their data the same way.
@immutable
class HomeArrangement {
  const HomeArrangement({
    required this.main,
    required this.side,
    this.widgets = const DashboardDocument(),
  });

  factory HomeArrangement.defaults() => const HomeArrangement(
        main: ['jumpBackIn'],
        side: ['glance', 'calendar', 'events', 'reminders'],
      );

  factory HomeArrangement.fromJson(Map<String, Object?> json) {
    List<String> ids(Object? value) => [
          if (value is List)
            for (final id in value)
              if (id is String && id.isNotEmpty) id,
        ];
    final widgets = json['widgets'];
    return HomeArrangement(
      main: ids(json['main']),
      side: ids(json['side']),
      widgets: widgets is Map
          ? DashboardDocument.fromJson(Map<String, Object?>.from(widgets))
          : const DashboardDocument(),
    ).normalized();
  }

  static const version = 1;

  final List<String> main;
  final List<String> side;
  final DashboardDocument widgets;

  List<String> blocksIn(HomeColumn column) =>
      column == HomeColumn.main ? main : side;

  HomeColumn? columnOf(String id) => main.contains(id)
      ? HomeColumn.main
      : side.contains(id)
          ? HomeColumn.side
          : null;

  bool contains(String id) => columnOf(id) != null;

  /// The built-in parts that have been taken off Home.
  List<HomeBlock> get missingBlocks => [
        for (final block in HomeBlock.values)
          if (!contains(block.name)) block,
      ];

  DashboardWidgetSpec? widgetFor(String blockId) {
    final id = homeWidgetSpecId(blockId);
    return id == null ? null : widgets.widgetById(id);
  }

  HomeArrangement _with({
    List<String>? main,
    List<String>? side,
    DashboardDocument? widgets,
  }) =>
      HomeArrangement(
        main: main ?? this.main,
        side: side ?? this.side,
        widgets: widgets ?? this.widgets,
      );

  /// Put [id] in [column] so it lands in the gap at [slot], counted in the
  /// column as it is now (0 is above the first block, `length` below the
  /// last). A block already there is taken from where it was.
  HomeArrangement move(String id, HomeColumn column, int slot) {
    final current = blocksIn(column);
    var index = slot.clamp(0, current.length);
    final from = current.indexOf(id);
    if (from >= 0 && from < index) index--;
    final main = [
      for (final block in this.main)
        if (block != id) block,
    ];
    final side = [
      for (final block in this.side)
        if (block != id) block,
    ];
    final target = column == HomeColumn.main ? main : side;
    target.insert(index.clamp(0, target.length), id);
    return _with(main: main, side: side);
  }

  /// Put [id] at the end of [column].
  HomeArrangement add(String id, HomeColumn column) =>
      move(id, column, blocksIn(column).length);

  /// Put a new dashboard widget at the end of [column].
  HomeArrangement addWidget(DashboardWidgetSpec spec, HomeColumn column) =>
      _with(widgets: widgets.addWidget(spec))
          .add(homeWidgetBlockId(spec.id), column);

  /// Take [id] off Home. A widget goes with its settings; a built-in part can
  /// be put back from the add menu.
  HomeArrangement remove(String id) {
    final specId = homeWidgetSpecId(id);
    return _with(
      main: [
        for (final block in main)
          if (block != id) block,
      ],
      side: [
        for (final block in side)
          if (block != id) block,
      ],
      widgets: specId == null ? widgets : widgets.withoutWidget(specId),
    );
  }

  /// Adopt the widgets as they are now: a widget deleted from its own
  /// settings panel leaves its column too.
  HomeArrangement withWidgets(DashboardDocument document) =>
      _with(widgets: document).normalized();

  /// Without duplicates, unknown parts, or widgets that no longer exist.
  HomeArrangement normalized() {
    final seen = <String>{};
    bool keep(String id) {
      if (!seen.add(id)) return false;
      if (HomeBlock.fromId(id) != null) return true;
      final specId = homeWidgetSpecId(id);
      return specId != null && widgets.widgetById(specId) != null;
    }

    final main = [
      for (final id in this.main)
        if (keep(id)) id,
    ];
    final side = [
      for (final id in this.side)
        if (keep(id)) id,
    ];
    final placed = {...main, ...side};
    var kept = widgets;
    for (final spec in widgets.allWidgets) {
      if (!placed.contains(homeWidgetBlockId(spec.id))) {
        kept = kept.withoutWidget(spec.id);
      }
    }
    return HomeArrangement(main: main, side: side, widgets: kept);
  }

  Map<String, Object?> toJson() => {
        'version': version,
        'main': main,
        'side': side,
        if (widgets.widgetCount > 0) 'widgets': widgets.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is HomeArrangement &&
      listEquals(other.main, main) &&
      listEquals(other.side, side) &&
      other.widgets == widgets;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(main), Object.hashAll(side), widgets);
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
