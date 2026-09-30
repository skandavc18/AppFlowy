import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_source.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// How a library of pages is laid out — the same readings a folder offers.
enum ViewGalleryLayout {
  /// A wall of cards with a chosen face.
  gallery('gallery'),

  /// A contact sheet of square pictures.
  thumbnails('thumbnails'),

  /// Explorer-style tiles: a glyph, the name and two quiet lines.
  tiles('tiles'),

  /// Compact rows.
  list('list'),

  /// A table of names and facts.
  details('details');

  const ViewGalleryLayout(this.id);

  final String id;

  static ViewGalleryLayout fromId(Object? id) => ViewGalleryLayout.values
      .firstWhere((layout) => layout.id == id, orElse: () => gallery);
}

/// The facts a page in a library can be searched, narrowed, ordered and
/// grouped by. Ids are persisted, so they never change.
abstract final class ViewGalleryColumns {
  static const name = 'name';
  static const kind = 'type';
  static const location = 'location';

  /// Last viewed (Recents) or favorited (Favorites).
  static const when = 'when';
  static const edited = 'edited';
  static const created = 'created';
  static const pinned = 'pinned';

  static bool isTime(String column) =>
      column == when || column == edited || column == created;
}

/// Calendar buckets for a moment, newest first.
enum ViewGalleryPeriod { today, yesterday, thisWeek, thisMonth, earlier }

ViewGalleryPeriod viewGalleryPeriodOf(DateTime at, DateTime now) {
  // Calendar arithmetic, not 24-hour steps, so a DST change moves no day.
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  if (!day.isBefore(today)) return ViewGalleryPeriod.today;
  if (day == DateTime(now.year, now.month, now.day - 1)) {
    return ViewGalleryPeriod.yesterday;
  }
  if (!day.isBefore(DateTime(now.year, now.month, now.day - 6))) {
    return ViewGalleryPeriod.thisWeek;
  }
  if (day.year == today.year && day.month == today.month) {
    return ViewGalleryPeriod.thisMonth;
  }
  return ViewGalleryPeriod.earlier;
}

/// A run of pages that share a value.
@immutable
class ViewGalleryGroup {
  const ViewGalleryGroup({required this.label, required this.entries});

  final String label;
  final List<ViewGalleryEntry> entries;
}

typedef ViewGalleryValueOf = String Function(
  ViewGalleryEntry entry,
  String column,
);
typedef ViewGalleryTimeOf = DateTime? Function(
  ViewGalleryEntry entry,
  String column,
);

bool _matches(
  ViewGalleryEntry entry,
  String needle,
  ViewGalleryValueOf valueOf,
) {
  for (final column in const [
    ViewGalleryColumns.name,
    ViewGalleryColumns.kind,
    ViewGalleryColumns.location,
  ]) {
    if (valueOf(entry, column).toLowerCase().contains(needle)) return true;
  }
  return false;
}

/// The pages left once the library has been searched, narrowed and ordered.
/// Unlike a table, a library search hides what does not match: it is how a
/// person finds one page among a hundred recent ones.
List<ViewGalleryEntry> applyViewGalleryQuery(
  List<ViewGalleryEntry> entries,
  TableQuery query, {
  required ViewGalleryValueOf valueOf,
  required ViewGalleryTimeOf timeOf,
}) {
  var result = entries;
  final needle = query.search.trim().toLowerCase();
  if (needle.isNotEmpty) {
    result = result.where((entry) => _matches(entry, needle, valueOf)).toList();
  }
  if (query.isFiltering) {
    final wanted = query.filterValue.trim().toLowerCase();
    result = result.where((entry) {
      final value = valueOf(entry, query.filterColumn).trim();
      return wanted.isEmpty ? value.isNotEmpty : value.toLowerCase() == wanted;
    }).toList();
  }
  if (query.isSorting) {
    final ascending = query.direction == TableSortDirection.ascending;
    final column = query.sortColumn;
    final indexed = [for (var i = 0; i < result.length; i++) (i, result[i])];
    int compare((int, ViewGalleryEntry) a, (int, ViewGalleryEntry) b) {
      int order;
      if (ViewGalleryColumns.isTime(column)) {
        final left = timeOf(a.$2, column);
        final right = timeOf(b.$2, column);
        // Nothing to order by sits at the end in either direction.
        if (left == null || right == null) {
          order = left == right ? 0 : (left == null ? 1 : -1);
          return order == 0 ? a.$1.compareTo(b.$1) : order;
        }
        order = left.compareTo(right);
      } else {
        final left = valueOf(a.$2, column).trim();
        final right = valueOf(b.$2, column).trim();
        if (left.isEmpty || right.isEmpty) {
          order = left.isEmpty == right.isEmpty ? 0 : (left.isEmpty ? 1 : -1);
          return order == 0 ? a.$1.compareTo(b.$1) : order;
        }
        order = compareTableValues(left, right);
      }
      if (!ascending) order = -order;
      // Equal values keep the library's own order.
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    }

    indexed.sort(compare);
    result = [for (final (_, entry) in indexed) entry];
  }
  return result;
}

/// Pages gathered under the value they share. Time buckets run newest first;
/// other values run alphabetically; pages without a value come last.
List<ViewGalleryGroup> groupViewGallery(
  List<ViewGalleryEntry> entries,
  String column, {
  required ViewGalleryValueOf valueOf,
  required ViewGalleryTimeOf timeOf,
  required String ungrouped,
}) {
  if (column.isEmpty) {
    return [ViewGalleryGroup(label: '', entries: entries)];
  }
  final buckets = <String, List<ViewGalleryEntry>>{};
  final newest = <String, DateTime>{};
  for (final entry in entries) {
    final value = valueOf(entry, column).trim();
    final label = value.isEmpty ? ungrouped : value;
    buckets.putIfAbsent(label, () => []).add(entry);
    final at = ViewGalleryColumns.isTime(column) ? timeOf(entry, column) : null;
    if (at != null && (newest[label]?.isBefore(at) ?? true)) {
      newest[label] = at;
    }
  }
  final labels = buckets.keys.toList()
    ..sort((a, b) {
      if (a == ungrouped || b == ungrouped) {
        return a == b ? 0 : (a == ungrouped ? 1 : -1);
      }
      if (ViewGalleryColumns.isTime(column)) {
        final left = newest[a], right = newest[b];
        if (left != null && right != null) return right.compareTo(left);
      }
      return compareTableValues(a, b);
    });
  return [
    for (final label in labels)
      ViewGalleryGroup(label: label, entries: buckets[label]!),
  ];
}

/// The values a column holds, for the filter menu. Time buckets are offered
/// newest first, everything else alphabetically.
List<String> viewGalleryValuesOf(
  List<ViewGalleryEntry> entries,
  String column, {
  required ViewGalleryValueOf valueOf,
  required ViewGalleryTimeOf timeOf,
}) {
  final ordered = ViewGalleryColumns.isTime(column)
      ? applyViewGalleryQuery(
          entries,
          TableQuery(
            sortColumn: column,
            direction: TableSortDirection.descending,
          ),
          valueOf: valueOf,
          timeOf: timeOf,
        )
      : entries;
  final seen = <String>{};
  final values = <String>[
    for (final entry in ordered)
      if (valueOf(entry, column).trim() case final value
          when value.isNotEmpty && seen.add(value.toLowerCase()))
        value,
  ];
  if (!ViewGalleryColumns.isTime(column)) values.sort(compareTableValues);
  return values;
}

/// How a library is hung: card size, card face, layout, and the reader's
/// standing sort/filter/group. The search box is never remembered.
@immutable
class ViewGallerySpec {
  const ViewGallerySpec({
    this.scale = GalleryCardScale.medium,
    this.face = GalleryCardFace.page,
    this.layout = ViewGalleryLayout.gallery,
    this.showCoverPlaceholder = true,
    this.sortColumn = '',
    this.direction = TableSortDirection.ascending,
    this.filterColumn = '',
    this.filterValue = '',
    this.groupColumn = '',
  });

  final GalleryCardScale scale;
  final GalleryCardFace face;
  final ViewGalleryLayout layout;
  final bool showCoverPlaceholder;
  final String sortColumn;
  final TableSortDirection direction;
  final String filterColumn;
  final String filterValue;
  final String groupColumn;

  TableQuery query({String search = ''}) => TableQuery(
        search: search,
        sortColumn: sortColumn,
        direction: direction,
        filterColumn: filterColumn,
        filterValue: filterValue,
        groupColumn: groupColumn,
      );

  ViewGallerySpec withQuery(TableQuery query) => copyWith(
        sortColumn: query.sortColumn,
        direction: query.direction,
        filterColumn: query.filterColumn,
        filterValue: query.filterValue,
        groupColumn: query.groupColumn,
      );

  ViewGallerySpec copyWith({
    GalleryCardScale? scale,
    GalleryCardFace? face,
    ViewGalleryLayout? layout,
    bool? showCoverPlaceholder,
    String? sortColumn,
    TableSortDirection? direction,
    String? filterColumn,
    String? filterValue,
    String? groupColumn,
  }) =>
      ViewGallerySpec(
        scale: scale ?? this.scale,
        face: face ?? this.face,
        layout: layout ?? this.layout,
        showCoverPlaceholder: showCoverPlaceholder ?? this.showCoverPlaceholder,
        sortColumn: sortColumn ?? this.sortColumn,
        direction: direction ?? this.direction,
        filterColumn: filterColumn ?? this.filterColumn,
        filterValue: filterValue ?? this.filterValue,
        groupColumn: groupColumn ?? this.groupColumn,
      );

  Map<String, dynamic> toJson() => {
        if (scale != GalleryCardScale.medium) 'scale': scale.id,
        if (face != GalleryCardFace.page) 'face': face.id,
        if (layout != ViewGalleryLayout.gallery) 'layout': layout.id,
        if (!showCoverPlaceholder) 'placeholder': false,
        if (sortColumn.isNotEmpty) 'sort': sortColumn,
        if (sortColumn.isNotEmpty && direction == TableSortDirection.descending)
          'descending': true,
        if (filterColumn.isNotEmpty) 'filter': filterColumn,
        if (filterColumn.isNotEmpty && filterValue.isNotEmpty)
          'filterValue': filterValue,
        if (groupColumn.isNotEmpty) 'group': groupColumn,
      };

  static ViewGallerySpec fromJson(Map<String, dynamic> values) {
    String text(String key) => values[key] is String ? values[key] : '';
    return ViewGallerySpec(
      scale: GalleryCardScale.fromId(values['scale'] as String?),
      face: GalleryCardFace.fromId(values['face'] as String?),
      layout: ViewGalleryLayout.fromId(values['layout']),
      showCoverPlaceholder: values['placeholder'] != false,
      sortColumn: text('sort'),
      direction: values['descending'] == true
          ? TableSortDirection.descending
          : TableSortDirection.ascending,
      filterColumn: text('filter'),
      filterValue: text('filterValue'),
      groupColumn: text('group'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ViewGallerySpec &&
      other.scale == scale &&
      other.face == face &&
      other.layout == layout &&
      other.showCoverPlaceholder == showCoverPlaceholder &&
      other.sortColumn == sortColumn &&
      other.direction == direction &&
      other.filterColumn == filterColumn &&
      other.filterValue == filterValue &&
      other.groupColumn == groupColumn;

  @override
  int get hashCode => Object.hash(
        scale,
        face,
        layout,
        showCoverPlaceholder,
        sortColumn,
        direction,
        filterColumn,
        filterValue,
        groupColumn,
      );
}

/// Where a library remembers how it is hung, per library.
class ViewGallerySpecStore {
  ViewGallerySpecStore(this.key, {KeyValueStorage? storage})
      : _storage = storage;

  static const recentsKey = 'appflowy_recents_gallery';
  static const favoritesKey = 'appflowy_favorites_gallery';
  static const libraryKey = 'appflowy_library_gallery';

  final String key;
  final KeyValueStorage? _storage;

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  Future<ViewGallerySpec> read() async {
    try {
      final stored = await _kv?.get(key);
      if (stored == null || stored.isEmpty) return const ViewGallerySpec();
      final decoded = jsonDecode(stored);
      return decoded is Map<String, dynamic>
          ? ViewGallerySpec.fromJson(decoded)
          : const ViewGallerySpec();
    } catch (error) {
      Log.warn('Library layout could not be read: $error');
      return const ViewGallerySpec();
    }
  }

  Future<void> write(ViewGallerySpec spec) async {
    try {
      await _kv?.set(key, jsonEncode(spec.toJson()));
    } catch (error) {
      Log.warn('Library layout could not be saved: $error');
    }
  }
}
