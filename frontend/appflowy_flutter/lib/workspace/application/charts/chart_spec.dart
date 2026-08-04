import 'package:flutter/foundation.dart';

/// How a chart draws its series.
enum ChartType {
  bar,
  horizontalBar,
  stackedBar,
  line,
  area,
  stackedArea,
  pie,
  donut,
  scatter,
  bubble;

  static ChartType fromValue(Object? value) {
    for (final type in ChartType.values) {
      if (type.name == value) {
        return type;
      }
    }
    return ChartType.bar;
  }

  bool get isCircular => this == ChartType.pie || this == ChartType.donut;
  bool get isCartesian => !isCircular;
  bool get isStacked =>
      this == ChartType.stackedBar || this == ChartType.stackedArea;
  bool get isHorizontal => this == ChartType.horizontalBar;
  bool get drawsBars =>
      this == ChartType.bar ||
      this == ChartType.horizontalBar ||
      this == ChartType.stackedBar;
  bool get drawsLine =>
      this == ChartType.line ||
      this == ChartType.area ||
      this == ChartType.stackedArea;
  bool get fillsArea => this == ChartType.area || this == ChartType.stackedArea;
  bool get drawsPoints => this == ChartType.scatter || this == ChartType.bubble;
  bool get sizesPoints => this == ChartType.bubble;

  /// Whether a numeric column can take the place of the category axis.
  ///
  /// A bar chart's horizontal axis names groups; a scatter's measures them, so
  /// only the types that plot a continuous run of values offer the choice.
  bool get supportsValueAxis =>
      this == ChartType.line ||
      this == ChartType.area ||
      this == ChartType.scatter ||
      this == ChartType.bubble;
}

/// What a column of values collapses to for one category.
enum ChartAggregate {
  sum,
  average,
  count,
  min,
  max,
  median;

  static ChartAggregate fromValue(Object? value) {
    for (final aggregate in ChartAggregate.values) {
      if (aggregate.name == value) {
        return aggregate;
      }
    }
    return ChartAggregate.sum;
  }

  /// Counting needs no numbers, so it works on any column at all.
  bool get needsNumbers => this != ChartAggregate.count;

  double? apply(List<double> values) {
    if (this == ChartAggregate.count) {
      return values.length.toDouble();
    }
    if (values.isEmpty) {
      return null;
    }
    switch (this) {
      case ChartAggregate.sum:
        return values.reduce((a, b) => a + b);
      case ChartAggregate.average:
        return values.reduce((a, b) => a + b) / values.length;
      case ChartAggregate.min:
        return values.reduce((a, b) => a < b ? a : b);
      case ChartAggregate.max:
        return values.reduce((a, b) => a > b ? a : b);
      case ChartAggregate.median:
        final sorted = [...values]..sort();
        final middle = sorted.length ~/ 2;
        return sorted.length.isOdd
            ? sorted[middle]
            : (sorted[middle - 1] + sorted[middle]) / 2;
      case ChartAggregate.count:
        return values.length.toDouble();
    }
  }
}

/// How the categories are ordered along the axis.
enum ChartSort {
  natural,
  labelAscending,
  valueDescending,
  valueAscending;

  static ChartSort fromValue(Object? value) {
    for (final sort in ChartSort.values) {
      if (sort.name == value) {
        return sort;
      }
    }
    return ChartSort.natural;
  }
}

/// The most categories drawn before the rest are gathered together.
const defaultChartCategoryLimit = 24;

/// A named set of colours a chart draws itself in.
enum ChartPaletteName {
  classic,
  ocean,
  sunset,
  meadow,
  berry,
  slate;

  static ChartPaletteName fromValue(Object? value) {
    for (final name in ChartPaletteName.values) {
      if (name.name == value) {
        return name;
      }
    }
    return ChartPaletteName.classic;
  }
}

/// What a colour set is keyed by.
///
/// A series usually has a name, but a chart that only counts rows has one
/// nameless series — so its place in the order stands in for a name.
String chartColorKey(String name, int index) => name.isEmpty ? '#$index' : name;

/// What a chart is: which table column names the groups, which columns supply
/// the numbers, and how those numbers are collapsed.
///
/// Columns are named rather than referenced by id so a chart survives a table
/// being rebuilt, and so the same spec reads correctly against an export.
@immutable
class ChartSpec {
  const ChartSpec({
    this.type = ChartType.bar,
    this.categoryColumn,
    this.xColumn,
    this.sizeColumn,
    this.valueColumns = const [],
    this.aggregate = ChartAggregate.sum,
    this.sort = ChartSort.natural,
    this.categoryLimit = defaultChartCategoryLimit,
    this.showLegend = true,
    this.showValues = false,
    this.showGrid = true,
    this.showControls = false,
    this.palette = ChartPaletteName.classic,
    this.colors = const {},
  });

  final ChartType type;

  /// The column whose values name the groups. Null means every row is its own
  /// point, in the order the table holds them.
  final String? categoryColumn;

  /// The numeric column measured along the horizontal axis.
  ///
  /// When this is set on a type that supports it, rows are plotted where their
  /// numbers put them rather than being gathered into named groups.
  final String? xColumn;

  /// The column that sets how large each bubble is drawn.
  final String? sizeColumn;

  /// The columns plotted. Empty means the chart counts rows instead.
  final List<String> valueColumns;

  final ChartAggregate aggregate;
  final ChartSort sort;
  final int categoryLimit;
  final bool showLegend;
  final bool showValues;
  final bool showGrid;

  /// Whether the controls that shape the chart are on show.
  ///
  /// A chart is usually being read rather than built, so they stay out of the
  /// way until someone asks for them.
  final bool showControls;

  /// The set the chart draws itself in when nothing has been chosen by hand.
  final ChartPaletteName palette;

  /// Colours chosen one at a time, keyed by [chartColorKey].
  final Map<String, int> colors;

  bool get countsRows =>
      valueColumns.isEmpty || aggregate == ChartAggregate.count;

  /// Whether the horizontal axis measures rather than names.
  bool get plotsAgainstValues =>
      type.supportsValueAxis && (xColumn?.isNotEmpty ?? false);

  /// The axis label a person reads under the chart.
  String? get xAxisLabel => plotsAgainstValues ? xColumn : categoryColumn;

  ChartSpec copyWith({
    ChartType? type,
    String? categoryColumn,
    String? xColumn,
    String? sizeColumn,
    List<String>? valueColumns,
    ChartAggregate? aggregate,
    ChartSort? sort,
    int? categoryLimit,
    bool? showLegend,
    bool? showValues,
    bool? showGrid,
    bool? showControls,
    ChartPaletteName? palette,
    Map<String, int>? colors,
    bool clearCategory = false,
    bool clearX = false,
    bool clearSize = false,
  }) =>
      ChartSpec(
        type: type ?? this.type,
        categoryColumn:
            clearCategory ? null : (categoryColumn ?? this.categoryColumn),
        xColumn: clearX ? null : (xColumn ?? this.xColumn),
        sizeColumn: clearSize ? null : (sizeColumn ?? this.sizeColumn),
        valueColumns: valueColumns ?? this.valueColumns,
        aggregate: aggregate ?? this.aggregate,
        sort: sort ?? this.sort,
        categoryLimit: categoryLimit ?? this.categoryLimit,
        showLegend: showLegend ?? this.showLegend,
        showValues: showValues ?? this.showValues,
        showGrid: showGrid ?? this.showGrid,
        showControls: showControls ?? this.showControls,
        palette: palette ?? this.palette,
        colors: colors ?? this.colors,
      );

  /// The same chart with one series painted a chosen colour, or back to the
  /// palette's own when [color] is null.
  ChartSpec withColor(String key, int? color) {
    final next = {...colors};
    if (color == null) {
      next.remove(key);
    } else {
      next[key] = color;
    }
    return copyWith(colors: next);
  }

  Map<String, Object?> toJson() => {
        'type': type.name,
        if (categoryColumn != null) 'category': categoryColumn,
        if (xColumn != null) 'x': xColumn,
        if (sizeColumn != null) 'size': sizeColumn,
        'values': valueColumns,
        'aggregate': aggregate.name,
        'sort': sort.name,
        'category_limit': categoryLimit,
        'show_legend': showLegend,
        'show_values': showValues,
        'show_grid': showGrid,
        'show_controls': showControls,
        'palette': palette.name,
        if (colors.isNotEmpty) 'colors': colors,
      };

  static ChartSpec fromJson(Map<String, dynamic> json) {
    final category = json['category'];
    final x = json['x'];
    final size = json['size'];
    final values = json['values'];
    final colors = json['colors'];
    return ChartSpec(
      type: ChartType.fromValue(json['type']),
      categoryColumn:
          category is String && category.isNotEmpty ? category : null,
      xColumn: x is String && x.isNotEmpty ? x : null,
      sizeColumn: size is String && size.isNotEmpty ? size : null,
      valueColumns: values is List
          ? [
              for (final value in values)
                if (value is String && value.isNotEmpty) value,
            ]
          : const [],
      aggregate: ChartAggregate.fromValue(json['aggregate']),
      sort: ChartSort.fromValue(json['sort']),
      categoryLimit: json['category_limit'] is int
          ? json['category_limit'] as int
          : defaultChartCategoryLimit,
      showLegend: json['show_legend'] != false,
      showValues: json['show_values'] == true,
      showGrid: json['show_grid'] != false,
      showControls: json['show_controls'] == true,
      palette: ChartPaletteName.fromValue(json['palette']),
      colors: colors is Map
          ? {
              for (final entry in colors.entries)
                if (entry.key is String && entry.value is int)
                  entry.key as String: entry.value as int,
            }
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartSpec &&
          other.type == type &&
          other.categoryColumn == categoryColumn &&
          other.xColumn == xColumn &&
          other.sizeColumn == sizeColumn &&
          listEquals(other.valueColumns, valueColumns) &&
          other.aggregate == aggregate &&
          other.sort == sort &&
          other.categoryLimit == categoryLimit &&
          other.showLegend == showLegend &&
          other.showValues == showValues &&
          other.showGrid == showGrid &&
          other.showControls == showControls &&
          other.palette == palette &&
          mapEquals(other.colors, colors);

  @override
  int get hashCode => Object.hash(
        type,
        categoryColumn,
        xColumn,
        sizeColumn,
        Object.hashAll(valueColumns),
        aggregate,
        sort,
        categoryLimit,
        showLegend,
        showValues,
        showGrid,
        showControls,
        palette,
        Object.hashAll(
          colors.entries.map((entry) => Object.hash(entry.key, entry.value)),
        ),
      );
}
