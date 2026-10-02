import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter/foundation.dart';

/// How a table is read as a list: one page per line, its name on the left
/// and the properties that matter quietly on the right.
///
/// Unlike the other readings, a list keeps its sort, filter and grouping, so
/// the list a reader arranged is the list they come back to.
@immutable
class ListSpec {
  const ListSpec({
    this.titleColumn = '',
    this.propertyColumns = const [],
    this.hiddenColumns = const [],
    this.showIcons = true,
    this.sortColumn = '',
    this.descending = false,
    this.filterColumn = '',
    this.filterValue = '',
    this.groupColumn = '',
    this.collapsedGroups = const [],
  });

  final String titleColumn;

  /// The properties shown on each line, in order. Empty shows every column.
  final List<String> propertyColumns;
  final List<String> hiddenColumns;

  /// Whether each line starts with its page's icon.
  final bool showIcons;

  final String sortColumn;
  final bool descending;
  final String filterColumn;
  final String filterValue;
  final String groupColumn;

  /// The groups folded away, by label. They only mean something for the
  /// column they were folded under, so changing the grouping forgets them.
  final List<String> collapsedGroups;

  ListSpec copyWith({
    String? titleColumn,
    List<String>? propertyColumns,
    List<String>? hiddenColumns,
    bool? showIcons,
    String? sortColumn,
    bool? descending,
    String? filterColumn,
    String? filterValue,
    String? groupColumn,
    List<String>? collapsedGroups,
  }) =>
      ListSpec(
        titleColumn: titleColumn ?? this.titleColumn,
        propertyColumns: propertyColumns ?? this.propertyColumns,
        hiddenColumns: hiddenColumns ?? this.hiddenColumns,
        showIcons: showIcons ?? this.showIcons,
        sortColumn: sortColumn ?? this.sortColumn,
        descending: descending ?? this.descending,
        filterColumn: filterColumn ?? this.filterColumn,
        filterValue: filterValue ?? this.filterValue,
        groupColumn: groupColumn ?? this.groupColumn,
        collapsedGroups: collapsedGroups ?? this.collapsedGroups,
      );

  /// Every column is read, hidden or not: a list grouped, sorted or filtered
  /// by a property it does not show still needs that property's value.
  TableReadSpec get readSpec => TableReadSpec(titleColumn: titleColumn);

  /// The query the list answers, with what is being searched for right now.
  TableQuery query(String search) => TableQuery(
        search: search,
        sortColumn: sortColumn,
        direction: descending
            ? TableSortDirection.descending
            : TableSortDirection.ascending,
        filterColumn: filterColumn,
        filterValue: filterValue,
        groupColumn: groupColumn,
      );

  /// Keeps the arrangement a query asks for. The search is not kept.
  ListSpec withQuery(TableQuery query) => copyWith(
        sortColumn: query.sortColumn,
        descending: query.direction == TableSortDirection.descending,
        filterColumn: query.filterColumn,
        filterValue: query.filterValue,
        groupColumn: query.groupColumn,
        collapsedGroups:
            query.groupColumn == groupColumn ? collapsedGroups : const [],
      );

  bool isCollapsed(String group) => collapsedGroups.contains(group);

  ListSpec toggleGroup(String group) => copyWith(
        collapsedGroups: isCollapsed(group)
            ? collapsedGroups.where((label) => label != group).toList()
            : [...collapsedGroups, group],
      );

  bool isShown(String fieldId) =>
      !hiddenColumns.contains(fieldId) &&
      (propertyColumns.isEmpty || propertyColumns.contains(fieldId));

  /// A row's properties in the order this list shows them, hidden ones left
  /// out.
  List<TableProperty> shownOf(List<TableProperty> properties) {
    final shown = [
      for (final property in properties)
        if (isShown(property.fieldId)) property,
    ];
    if (propertyColumns.isEmpty) {
      return shown;
    }
    final order = {
      for (var i = 0; i < propertyColumns.length; i++) propertyColumns[i]: i,
    };
    return shown
      ..sort((a, b) => order[a.fieldId]!.compareTo(order[b.fieldId]!));
  }

  /// Shows or hides one property, keeping the order of everything else.
  ListSpec toggleProperty(String fieldId) {
    if (isShown(fieldId)) {
      return copyWith(hiddenColumns: [...hiddenColumns, fieldId]);
    }
    return copyWith(
      hiddenColumns: hiddenColumns.where((id) => id != fieldId).toList(),
      propertyColumns: propertyColumns.isEmpty
          ? propertyColumns
          : [...propertyColumns, fieldId],
    );
  }

  Map<String, dynamic> toJson() => {
        if (titleColumn.isNotEmpty) 'title': titleColumn,
        if (propertyColumns.isNotEmpty) 'properties': propertyColumns,
        if (hiddenColumns.isNotEmpty) 'hidden': hiddenColumns,
        if (!showIcons) 'icons': false,
        if (sortColumn.isNotEmpty) 'sort': sortColumn,
        if (sortColumn.isNotEmpty && descending) 'descending': true,
        if (filterColumn.isNotEmpty) 'filter': filterColumn,
        if (filterColumn.isNotEmpty && filterValue.isNotEmpty)
          'filterValue': filterValue,
        if (groupColumn.isNotEmpty) 'group': groupColumn,
        if (groupColumn.isNotEmpty && collapsedGroups.isNotEmpty)
          'collapsed': collapsedGroups,
      };

  static ListSpec fromJson(Map<String, dynamic> values) => ListSpec(
        titleColumn: values['title'] as String? ?? '',
        propertyColumns: _strings(values['properties']),
        hiddenColumns: _strings(values['hidden']),
        showIcons: values['icons'] != false,
        sortColumn: values['sort'] as String? ?? '',
        descending: values['descending'] == true,
        filterColumn: values['filter'] as String? ?? '',
        filterValue: values['filterValue'] as String? ?? '',
        groupColumn: values['group'] as String? ?? '',
        collapsedGroups: _strings(values['collapsed']),
      );

  static List<String> _strings(Object? value) => value is List
      ? List.unmodifiable(value.whereType<String>())
      : const <String>[];

  @override
  bool operator ==(Object other) =>
      other is ListSpec &&
      other.titleColumn == titleColumn &&
      listEquals(other.propertyColumns, propertyColumns) &&
      listEquals(other.hiddenColumns, hiddenColumns) &&
      other.showIcons == showIcons &&
      other.sortColumn == sortColumn &&
      other.descending == descending &&
      other.filterColumn == filterColumn &&
      other.filterValue == filterValue &&
      other.groupColumn == groupColumn &&
      listEquals(other.collapsedGroups, collapsedGroups);

  @override
  int get hashCode => Object.hash(
        titleColumn,
        Object.hashAll(propertyColumns),
        Object.hashAll(hiddenColumns),
        showIcons,
        sortColumn,
        descending,
        filterColumn,
        filterValue,
        groupColumn,
        Object.hashAll(collapsedGroups),
      );
}

/// A page typed into a list, before the table has it.
@immutable
class ListNewRow {
  const ListNewRow({
    required this.titleColumn,
    required this.title,
    this.groupColumn = '',
    this.groupValue = '',
  });

  /// The column the name is written into.
  final String titleColumn;
  final String title;

  /// The group it was typed under, so it lands there rather than in
  /// "everything else". Empty when the list is not grouped.
  final String groupColumn;
  final String groupValue;

  @override
  bool operator ==(Object other) =>
      other is ListNewRow &&
      other.titleColumn == titleColumn &&
      other.title == title &&
      other.groupColumn == groupColumn &&
      other.groupValue == groupValue;

  @override
  int get hashCode => Object.hash(titleColumn, title, groupColumn, groupValue);
}

/// The options a select column offers, in the order its author put them.
List<SelectOptionPB> listOptionsOf(FieldPB field) {
  if (field.fieldType != FieldType.SingleSelect &&
      field.fieldType != FieldType.MultiSelect) {
    return const [];
  }
  try {
    // Single and multi select settings share the options' field number.
    return SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData).options;
  } on Object catch (_) {
    return const [];
  }
}

/// Groups in the order a reader expects: a select column's own option order,
/// then whatever else appeared, with the ungathered rows last.
List<TableRowGroup> orderListGroups(
  List<TableRowGroup> groups,
  List<String> optionOrder, {
  required String ungrouped,
}) {
  if (optionOrder.isEmpty || groups.length < 2) {
    return groups;
  }
  final rank = <String, int>{
    for (var i = 0; i < optionOrder.length; i++)
      optionOrder[i].toLowerCase(): i,
  };
  final arrived = {for (var i = 0; i < groups.length; i++) groups[i].label: i};
  int rankOf(TableRowGroup group) => group.label == ungrouped
      ? optionOrder.length + groups.length + 1
      : rank[group.label.toLowerCase()] ??
          optionOrder.length + arrived[group.label]!;
  return [...groups]..sort((a, b) => rankOf(a).compareTo(rankOf(b)));
}

/// How many of the leading items fit a width, with [gap] between each.
///
/// A line shows whole properties or none of one: a pill cut in half reads as
/// a different value.
int listStripFit(List<double> widths, double maxWidth, {double gap = 0}) {
  var used = 0.0;
  var count = 0;
  for (final width in widths) {
    final next = used + (count == 0 ? 0 : gap) + width;
    if (next > maxWidth + 0.5) {
      break;
    }
    used = next;
    count++;
  }
  return count;
}
