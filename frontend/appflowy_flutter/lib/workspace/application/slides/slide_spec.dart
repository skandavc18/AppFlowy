import 'package:flutter/foundation.dart';

/// How the slides are arranged behind the active one.
enum SlideFlow {
  /// Neighbours sit squarely beside the active slide, slightly smaller.
  deck('deck'),

  /// Neighbours turn away in perspective, as a rack of covers does.
  coverFlow('cover_flow');

  const SlideFlow(this.id);

  final String id;

  static SlideFlow fromId(String? id) {
    for (final flow in SlideFlow.values) {
      if (flow.id == id) {
        return flow;
      }
    }
    return SlideFlow.deck;
  }
}

/// How a table is read as a stack of slides.
///
/// Columns are named by field id rather than by heading, so renaming a column
/// does not lose the arrangement.
@immutable
class SlideSpec {
  const SlideSpec({
    this.titleColumn = '',
    this.coverColumn = '',
    this.propertyColumns = const [],
    this.hiddenColumns = const [],
    this.flow = SlideFlow.deck,
    this.wrap = false,
    this.showEmptyProperties = false,
    this.showPageContent = false,
    this.index = 0,
  });

  /// The heading of each slide. Empty means the table's own primary column.
  final String titleColumn;

  /// The column holding the picture behind the slide's head.
  final String coverColumn;

  /// The columns worth reading, in the order they should be read. Empty means
  /// every column the table has, which is the right answer for a table nobody
  /// has arranged yet.
  final List<String> propertyColumns;

  /// Columns the author has taken off the slide.
  final List<String> hiddenColumns;

  final SlideFlow flow;

  /// Whether moving past the last slide comes back to the first.
  final bool wrap;

  /// Whether a column with nothing in it still takes up room.
  final bool showEmptyProperties;

  /// Whether the writing on the row's own page is read on the slide.
  final bool showPageContent;

  /// The slide the deck was left on.
  final int index;

  bool get isArranged =>
      propertyColumns.isNotEmpty ||
      titleColumn.isNotEmpty ||
      coverColumn.isNotEmpty;

  SlideSpec copyWith({
    String? titleColumn,
    String? coverColumn,
    List<String>? propertyColumns,
    List<String>? hiddenColumns,
    SlideFlow? flow,
    bool? wrap,
    bool? showEmptyProperties,
    bool? showPageContent,
    int? index,
  }) {
    return SlideSpec(
      titleColumn: titleColumn ?? this.titleColumn,
      coverColumn: coverColumn ?? this.coverColumn,
      propertyColumns: propertyColumns ?? this.propertyColumns,
      hiddenColumns: hiddenColumns ?? this.hiddenColumns,
      flow: flow ?? this.flow,
      wrap: wrap ?? this.wrap,
      showEmptyProperties: showEmptyProperties ?? this.showEmptyProperties,
      showPageContent: showPageContent ?? this.showPageContent,
      index: index ?? this.index,
    );
  }

  Map<String, Object?> toJson() => {
        if (titleColumn.isNotEmpty) 'title': titleColumn,
        if (coverColumn.isNotEmpty) 'cover': coverColumn,
        if (propertyColumns.isNotEmpty) 'properties': propertyColumns,
        if (hiddenColumns.isNotEmpty) 'hidden': hiddenColumns,
        if (flow != SlideFlow.deck) 'flow': flow.id,
        if (wrap) 'wrap': true,
        if (showEmptyProperties) 'empty': true,
        if (showPageContent) 'page': true,
        if (index != 0) 'index': index,
      };

  static SlideSpec fromJson(Map<String, dynamic> values) => SlideSpec(
        titleColumn: values['title'] as String? ?? '',
        coverColumn: values['cover'] as String? ?? '',
        propertyColumns: _strings(values['properties']),
        hiddenColumns: _strings(values['hidden']),
        flow: SlideFlow.fromId(values['flow'] as String?),
        wrap: values['wrap'] == true,
        showEmptyProperties: values['empty'] == true,
        showPageContent: values['page'] == true,
        index: (values['index'] as num?)?.toInt() ?? 0,
      );

  static List<String> _strings(Object? value) => value is List
      ? List.unmodifiable(value.whereType<String>())
      : const <String>[];

  @override
  bool operator ==(Object other) =>
      other is SlideSpec &&
      other.titleColumn == titleColumn &&
      other.coverColumn == coverColumn &&
      listEquals(other.propertyColumns, propertyColumns) &&
      listEquals(other.hiddenColumns, hiddenColumns) &&
      other.flow == flow &&
      other.wrap == wrap &&
      other.showEmptyProperties == showEmptyProperties &&
      other.showPageContent == showPageContent &&
      other.index == index;

  @override
  int get hashCode => Object.hash(
        titleColumn,
        coverColumn,
        Object.hashAll(propertyColumns),
        Object.hashAll(hiddenColumns),
        flow,
        wrap,
        showEmptyProperties,
        showPageContent,
        index,
      );
}
