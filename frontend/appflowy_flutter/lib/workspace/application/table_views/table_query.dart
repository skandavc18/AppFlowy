import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:flutter/foundation.dart';

enum TableSortDirection {
  ascending,
  descending;

  TableSortDirection get flipped => this == TableSortDirection.ascending
      ? TableSortDirection.descending
      : TableSortDirection.ascending;
}

/// What the reader has asked to see.
///
/// Searching, narrowing, ordering and grouping are decided here rather than in
/// any one view, so every view of a table answers them the same way — and so
/// switching view keeps the answer.
@immutable
class TableQuery {
  const TableQuery({
    this.search = '',
    this.sortColumn = '',
    this.direction = TableSortDirection.ascending,
    this.filterColumn = '',
    this.filterValue = '',
    this.groupColumn = '',
  });

  final String search;

  /// The column the rows are ordered by. Empty keeps the table's own order.
  final String sortColumn;
  final TableSortDirection direction;

  /// The column the rows are narrowed by. Empty shows everything.
  final String filterColumn;

  /// The value that column must hold. Empty means "anything at all".
  final String filterValue;

  /// The column the rows are gathered under. Empty leaves them ungathered.
  final String groupColumn;

  bool get isFiltering => filterColumn.isNotEmpty;
  bool get isSorting => sortColumn.isNotEmpty;
  bool get isSearching => search.trim().isNotEmpty;
  bool get isGrouping => groupColumn.isNotEmpty;
  bool get isPlain => !isFiltering && !isSorting && !isSearching && !isGrouping;

  TableQuery copyWith({
    String? search,
    String? sortColumn,
    TableSortDirection? direction,
    String? filterColumn,
    String? filterValue,
    String? groupColumn,
  }) =>
      TableQuery(
        search: search ?? this.search,
        sortColumn: sortColumn ?? this.sortColumn,
        direction: direction ?? this.direction,
        filterColumn: filterColumn ?? this.filterColumn,
        filterValue: filterValue ?? this.filterValue,
        groupColumn: groupColumn ?? this.groupColumn,
      );

  @override
  bool operator ==(Object other) =>
      other is TableQuery &&
      other.search == search &&
      other.sortColumn == sortColumn &&
      other.direction == direction &&
      other.filterColumn == filterColumn &&
      other.filterValue == filterValue &&
      other.groupColumn == groupColumn;

  @override
  int get hashCode => Object.hash(
        search,
        sortColumn,
        direction,
        filterColumn,
        filterValue,
        groupColumn,
      );
}

/// A run of rows that share a value.
@immutable
class TableRowGroup {
  const TableRowGroup({required this.label, required this.rows});

  final String label;
  final List<TableRowCard> rows;
}

/// The value a card holds in a column, or an empty string.
String tableValueOf(TableRowCard card, String fieldId) =>
    card.propertyOf(fieldId)?.value ?? '';

/// The rows that are left once the table has been narrowed and ordered.
///
/// Searching never removes a row — a view that empties itself as you type
/// loses your place. Matches are reported separately so a view can bring them
/// forward and quieten the rest.
List<TableRowCard> applyTableQuery(
  List<TableRowCard> cards,
  TableQuery query,
) {
  var result = cards;

  if (query.isFiltering) {
    final wanted = query.filterValue.trim().toLowerCase();
    result = result.where((card) {
      final value = tableValueOf(card, query.filterColumn).trim();
      if (wanted.isEmpty) {
        return value.isNotEmpty;
      }
      return tablePartsOf(value).any((part) => part.toLowerCase() == wanted);
    }).toList();
  }

  if (query.isSorting) {
    final ascending = query.direction == TableSortDirection.ascending;
    result = [...result]..sort((a, b) {
        final left = tableValueOf(a, query.sortColumn).trim();
        final right = tableValueOf(b, query.sortColumn).trim();
        // A cell with nothing in it has nothing to be ordered by, so it sits
        // at the end either way rather than leading a descending view.
        if (left.isEmpty || right.isEmpty) {
          if (left.isEmpty && right.isEmpty) {
            return 0;
          }
          return left.isEmpty ? 1 : -1;
        }
        final compared = compareTableValues(left, right);
        return ascending ? compared : -compared;
      });
  }

  return result;
}

/// The rows gathered under the column they share, in the order they arrived.
List<TableRowGroup> groupTableRows(
  List<TableRowCard> cards,
  String column, {
  String ungrouped = 'Everything else',
}) {
  if (column.isEmpty) {
    return [TableRowGroup(label: '', rows: cards)];
  }
  final order = <String>[];
  final buckets = <String, List<TableRowCard>>{};
  for (final card in cards) {
    final value = tableValueOf(card, column).trim();
    final label = value.isEmpty ? ungrouped : tablePartsOf(value).first;
    buckets.putIfAbsent(label, () {
      order.add(label);
      return <TableRowCard>[];
    }).add(card);
  }
  // Whatever could not be gathered goes last rather than wherever it landed.
  order.sort((a, b) {
    if (a == ungrouped) {
      return 1;
    }
    if (b == ungrouped) {
      return -1;
    }
    return 0;
  });
  return [
    for (final label in order)
      TableRowGroup(label: label, rows: buckets[label]!),
  ];
}

/// Orders two cells the way a reader expects: numbers by size, words by
/// letter, and an empty cell after everything else.
int compareTableValues(String left, String right) {
  if (left.isEmpty && right.isEmpty) {
    return 0;
  }
  if (left.isEmpty) {
    return 1;
  }
  if (right.isEmpty) {
    return -1;
  }
  final leftNumber = double.tryParse(left.replaceAll(',', ''));
  final rightNumber = double.tryParse(right.replaceAll(',', ''));
  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }
  return left.toLowerCase().compareTo(right.toLowerCase());
}

/// The rows a search matched.
Set<String> tableMatchesOf(List<TableRowCard> cards, String search) {
  final needle = search.trim().toLowerCase();
  if (needle.isEmpty) {
    return const {};
  }
  return {
    for (final card in cards)
      if (tableRowMatches(card, needle)) card.rowId,
  };
}

/// Whether a row holds the words being looked for, anywhere on it.
bool tableRowMatches(TableRowCard card, String needle) {
  if (card.title.toLowerCase().contains(needle) ||
      card.subtitle.toLowerCase().contains(needle)) {
    return true;
  }
  for (final property in card.properties) {
    if (property.value.toLowerCase().contains(needle)) {
      return true;
    }
  }
  return false;
}

/// The values a column actually holds, so a filter can offer them.
List<String> tableValuesOf(List<TableRowCard> cards, String fieldId) {
  final seen = <String>{};
  final values = <String>[];
  for (final card in cards) {
    for (final part in tablePartsOf(tableValueOf(card, fieldId))) {
      if (seen.add(part.toLowerCase())) {
        values.add(part);
      }
    }
  }
  values.sort(compareTableValues);
  return values;
}
