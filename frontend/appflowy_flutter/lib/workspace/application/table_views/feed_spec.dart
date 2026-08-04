import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:flutter/foundation.dart';

/// How wide a post is set.
enum FeedWidth {
  comfortable('comfortable', 720),
  wide('wide', 940);

  const FeedWidth(this.id, this.pixels);

  final String id;
  final double pixels;

  FeedWidth get flipped =>
      this == FeedWidth.comfortable ? FeedWidth.wide : FeedWidth.comfortable;

  static FeedWidth fromId(String? id) {
    for (final width in FeedWidth.values) {
      if (width.id == id) {
        return width;
      }
    }
    return FeedWidth.comfortable;
  }
}

/// How a table is read as a feed.
@immutable
class FeedSpec {
  const FeedSpec({
    this.titleColumn = '',
    this.coverColumn = '',
    this.bodyColumn = '',
    this.authorColumn = '',
    this.dateColumn = '',
    this.propertyColumns = const [],
    this.hiddenColumns = const [],
    this.newestFirst = true,
    this.width = FeedWidth.comfortable,
  });

  final String titleColumn;
  final String coverColumn;

  /// The column that carries the writing. Empty lets the feed pick the longest
  /// piece of prose the row holds.
  final String bodyColumn;

  final String authorColumn;
  final String dateColumn;

  final List<String> propertyColumns;
  final List<String> hiddenColumns;

  /// Whether the most recently changed row is read first.
  final bool newestFirst;

  final FeedWidth width;

  FeedSpec copyWith({
    String? titleColumn,
    String? coverColumn,
    String? bodyColumn,
    String? authorColumn,
    String? dateColumn,
    List<String>? propertyColumns,
    List<String>? hiddenColumns,
    bool? newestFirst,
    FeedWidth? width,
  }) =>
      FeedSpec(
        titleColumn: titleColumn ?? this.titleColumn,
        coverColumn: coverColumn ?? this.coverColumn,
        bodyColumn: bodyColumn ?? this.bodyColumn,
        authorColumn: authorColumn ?? this.authorColumn,
        dateColumn: dateColumn ?? this.dateColumn,
        propertyColumns: propertyColumns ?? this.propertyColumns,
        hiddenColumns: hiddenColumns ?? this.hiddenColumns,
        newestFirst: newestFirst ?? this.newestFirst,
        width: width ?? this.width,
      );

  TableReadSpec get readSpec => TableReadSpec(
        titleColumn: titleColumn,
        coverColumn: coverColumn,
        propertyColumns: propertyColumns,
        hiddenColumns: hiddenColumns,
      );

  Map<String, dynamic> toJson() => {
        if (titleColumn.isNotEmpty) 'title': titleColumn,
        if (coverColumn.isNotEmpty) 'cover': coverColumn,
        if (bodyColumn.isNotEmpty) 'body': bodyColumn,
        if (authorColumn.isNotEmpty) 'author': authorColumn,
        if (dateColumn.isNotEmpty) 'date': dateColumn,
        if (propertyColumns.isNotEmpty) 'properties': propertyColumns,
        if (hiddenColumns.isNotEmpty) 'hidden': hiddenColumns,
        if (!newestFirst) 'newest': false,
        if (width != FeedWidth.comfortable) 'width': width.id,
      };

  static FeedSpec fromJson(Map<String, dynamic> values) => FeedSpec(
        titleColumn: values['title'] as String? ?? '',
        coverColumn: values['cover'] as String? ?? '',
        bodyColumn: values['body'] as String? ?? '',
        authorColumn: values['author'] as String? ?? '',
        dateColumn: values['date'] as String? ?? '',
        propertyColumns: _strings(values['properties']),
        hiddenColumns: _strings(values['hidden']),
        newestFirst: values['newest'] != false,
        width: FeedWidth.fromId(values['width'] as String?),
      );

  static List<String> _strings(Object? value) => value is List
      ? List.unmodifiable(value.whereType<String>())
      : const <String>[];

  @override
  bool operator ==(Object other) =>
      other is FeedSpec &&
      other.titleColumn == titleColumn &&
      other.coverColumn == coverColumn &&
      other.bodyColumn == bodyColumn &&
      other.authorColumn == authorColumn &&
      other.dateColumn == dateColumn &&
      listEquals(other.propertyColumns, propertyColumns) &&
      listEquals(other.hiddenColumns, hiddenColumns) &&
      other.newestFirst == newestFirst &&
      other.width == width;

  @override
  int get hashCode => Object.hash(
        titleColumn,
        coverColumn,
        bodyColumn,
        authorColumn,
        dateColumn,
        Object.hashAll(propertyColumns),
        Object.hashAll(hiddenColumns),
        newestFirst,
        width,
      );
}

/// How long ago something happened, in the words a reader uses.
String feedAgoOf(DateTime when, {DateTime? now}) {
  final gap = (now ?? DateTime.now()).difference(when);
  if (gap.isNegative) {
    return 'just now';
  }
  if (gap.inMinutes < 1) {
    return 'just now';
  }
  if (gap.inHours < 1) {
    return '${gap.inMinutes}m ago';
  }
  if (gap.inDays < 1) {
    return '${gap.inHours}h ago';
  }
  if (gap.inDays < 7) {
    return '${gap.inDays}d ago';
  }
  if (gap.inDays < 365) {
    return '${gap.inDays ~/ 7}w ago';
  }
  return '${gap.inDays ~/ 365}y ago';
}
