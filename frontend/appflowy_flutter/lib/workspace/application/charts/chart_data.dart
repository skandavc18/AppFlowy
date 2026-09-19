import 'package:appflowy/workspace/application/charts/chart_number.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:flutter/foundation.dart';

/// The rest of the categories, gathered so a long tail does not crowd out the
/// shape of the data.
const chartOtherCategory = 'Other';

/// A table as a chart reads it: named columns and rows of displayed text.
///
/// The values are what the database shows, because that is what a person is
/// looking at. Numbers are read back out of them.
@immutable
class ChartTable {
  const ChartTable({
    required this.columns,
    required this.rows,
    this.columnIds = const [],
  });

  /// Builds a table from a delimited export, taking the first row as names.
  factory ChartTable.fromRows(
    List<List<String>> source, {
    List<String> columnIds = const [],
    bool keepEmptyRows = false,
  }) {
    if (source.isEmpty) {
      return ChartTable.empty;
    }
    assert(columnIds.isEmpty || columnIds.length == source.first.length);
    final header = source.first.map((cell) => cell.trim()).toList();
    final reserved = header.toSet();
    final seen = <String>{};
    final columns = <String>[];
    for (var index = 0; index < header.length; index++) {
      final base =
          header[index].isEmpty ? 'Column ${index + 1}' : header[index];
      var name = base;
      // Two columns with one name would make a spec ambiguous.
      var count = 1;
      while (seen.contains(name)) {
        do {
          count++;
          name = '$base ($count)';
        } while (reserved.contains(name));
      }
      seen.add(name);
      columns.add(name);
    }
    return ChartTable(
      columns: columns,
      columnIds: columnIds,
      rows: [
        for (final row in source.skip(1))
          if (keepEmptyRows || row.any((cell) => cell.trim().isNotEmpty)) row,
      ],
    );
  }

  static const empty = ChartTable(columns: [], rows: []);

  final List<String> columns;
  final List<List<String>> rows;

  /// Field ids in the same order as [columns] and the cells in every row.
  /// Name-only tables (for example a CSV) leave this empty.
  final List<String> columnIds;

  bool get isEmpty => columns.isEmpty || rows.isEmpty;

  int indexOf(String? column) {
    if (column == null) {
      return -1;
    }
    final byId = columnIds.indexOf(column);
    return byId >= 0 ? byId : columns.indexOf(column);
  }

  String keyOf(String column) {
    final index = indexOf(column);
    return index >= 0 && columnIds.isNotEmpty ? columnIds[index] : column;
  }

  String nameOf(String column) {
    final index = indexOf(column);
    return index >= 0 ? columns[index] : column;
  }

  List<String> get columnKeys => columnIds.isEmpty ? columns : columnIds;

  /// Bind legacy names to stable ids without inventing a different selection.
  ChartSpec resolveSpec(ChartSpec spec) => _mapColumns(spec, keyOf);

  /// Painters and tooltips show names, never the ids stored in the settings.
  ChartSpec displaySpec(ChartSpec spec) => _mapColumns(spec, nameOf);

  ChartSpec _mapColumns(ChartSpec spec, String Function(String) map) =>
      spec.copyWith(
        categoryColumn:
            spec.categoryColumn == null ? null : map(spec.categoryColumn!),
        xColumn: spec.xColumn == null ? null : map(spec.xColumn!),
        sizeColumn: spec.sizeColumn == null ? null : map(spec.sizeColumn!),
        valueColumns: spec.valueColumns.map(map).toSet().toList(),
      );

  Iterable<String> valuesOf(String column) sync* {
    final index = indexOf(column);
    if (index < 0) {
      return;
    }
    for (final row in rows) {
      if (index < row.length) {
        yield row[index];
      }
    }
  }

  /// The columns that hold enough numbers to plot.
  List<String> get numericColumns => [
        for (final column in columns)
          if (looksNumeric(valuesOf(column))) column,
      ];
}

/// One plotted value.
@immutable
class ChartPoint {
  const ChartPoint({
    required this.label,
    required this.value,
    this.x,
    this.size,
  });

  final String label;
  final double value;

  /// Where the point sits along a measured horizontal axis, when there is one.
  final double? x;

  /// How large a bubble is drawn, before scaling.
  final double? size;
}

/// One column of numbers, across every category.
@immutable
class ChartSeries {
  const ChartSeries({required this.name, required this.points});

  final String name;
  final List<ChartPoint> points;

  double get total => points.fold(0, (sum, point) => sum + point.value.abs());
}

/// Everything a chart needs to draw itself.
@immutable
class ChartData {
  const ChartData({
    required this.categories,
    required this.series,
    required this.minimum,
    required this.maximum,
    this.xMinimum = 0,
    this.xMaximum = 0,
    this.sizeMaximum = 0,
    this.measuresX = false,
  });

  static const empty =
      ChartData(categories: [], series: [], minimum: 0, maximum: 0);

  final List<String> categories;
  final List<ChartSeries> series;
  final double minimum;
  final double maximum;

  /// The run of the horizontal axis when it measures rather than names.
  final double xMinimum;
  final double xMaximum;

  /// The largest bubble in the set, so the rest can be drawn in proportion.
  final double sizeMaximum;

  /// Whether the horizontal axis carries numbers instead of category names.
  final bool measuresX;

  bool get isEmpty =>
      series.isEmpty ||
      (measuresX
          ? series.every((one) => one.points.isEmpty)
          : categories.isEmpty);

  double get span => maximum - minimum == 0 ? 1 : maximum - minimum;

  double get xSpan => xMaximum - xMinimum == 0 ? 1 : xMaximum - xMinimum;
}

/// Turns a table into the series a chart draws, following [spec].
///
/// Pure, so the whole shape of a chart is testable without a database.
ChartData buildChartData(ChartTable table, ChartSpec spec) {
  if (table.isEmpty) {
    return ChartData.empty;
  }
  if (spec.plotsAgainstValues) {
    return _buildMeasured(table, spec);
  }
  // Scatter and bubble charts need two measured axes. They must not silently
  // become a line chart when their X column is absent.
  if (spec.type.drawsPoints) {
    return ChartData.empty;
  }

  final categoryIndex = table.indexOf(spec.categoryColumn);
  if (spec.categoryColumn != null && categoryIndex < 0) {
    return ChartData.empty;
  }
  final valueIndices = <String, int>{
    for (final column in spec.valueColumns)
      if (table.indexOf(column) >= 0) column: table.indexOf(column),
  };
  final counting = spec.countsRows;
  if (!counting && valueIndices.isEmpty) {
    return ChartData.empty;
  }
  final aggregate = counting ? ChartAggregate.count : spec.aggregate;

  // Gather each category's raw numbers before collapsing them, so every
  // aggregate reads the same set. A row's position, not its title, is its
  // identity when "Every row" is selected.
  final buckets = <Object, _ChartBucket>{};
  for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
    final row = table.rows[rowIndex];
    final raw = categoryIndex < 0
        ? (row.isEmpty ? '' : row.first)
        : categoryIndex < row.length
            ? row[categoryIndex]
            : '';
    final Object key = categoryIndex < 0 ? rowIndex : raw.trim();
    final bucket = buckets.putIfAbsent(key, () => _ChartBucket(_label(raw)));
    if (counting) {
      bucket.values.putIfAbsent('', () => <double>[]).add(1);
      continue;
    }
    for (final entry in valueIndices.entries) {
      final index = entry.value;
      if (index >= row.length) {
        continue;
      }
      final number = parseChartNumber(row[index]);
      if (number != null && number.isFinite) {
        bucket.values.putIfAbsent(entry.key, () => <double>[]).add(number);
      }
    }
  }

  final seriesNames = counting ? const [''] : valueIndices.keys.toList();
  final sorted = _sortCategories(
    buckets.values.toList(),
    seriesNames,
    spec.sort,
    aggregate,
  );
  final limited = _limit(sorted, seriesNames, spec.categoryLimit);
  final categories = limited.map((bucket) => bucket.label).toList();

  var minimum = 0.0;
  var maximum = 0.0;
  final series = <ChartSeries>[];
  for (final name in seriesNames) {
    final points = <ChartPoint>[];
    for (final bucket in limited) {
      final values = bucket.values[name] ?? const <double>[];
      final value = aggregate.apply(values) ?? 0;
      points.add(ChartPoint(label: bucket.label, value: value));
      minimum = value < minimum ? value : minimum;
      maximum = value > maximum ? value : maximum;
    }
    series.add(ChartSeries(name: table.nameOf(name), points: points));
  }

  if (spec.type.isStacked) {
    for (var index = 0; index < categories.length; index++) {
      var stacked = 0.0;
      // Match the cumulative stacks the painter draws, including negatives.
      for (final one in series) {
        stacked += one.points[index].value;
        minimum = stacked < minimum ? stacked : minimum;
        maximum = stacked > maximum ? stacked : maximum;
      }
    }
  }

  return ChartData(
    categories: categories,
    series: series,
    minimum: minimum,
    maximum: maximum == minimum ? maximum + 1 : maximum,
  );
}

String _label(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty ? '—' : trimmed;
}

/// Plots each row where its own numbers put it, rather than gathering rows
/// into named groups.
ChartData _buildMeasured(ChartTable table, ChartSpec spec) {
  final xIndex = table.indexOf(spec.xColumn);
  final sizeIndex = table.indexOf(spec.sizeColumn);
  final nameIndex = table.indexOf(spec.categoryColumn);
  if (xIndex < 0 || (spec.categoryColumn != null && nameIndex < 0)) {
    return ChartData.empty;
  }

  final columns = [
    for (final column in spec.valueColumns)
      if (table.indexOf(column) >= 0) column,
  ];
  if (columns.isEmpty) {
    return ChartData.empty;
  }

  var minimum = double.infinity;
  var maximum = double.negativeInfinity;
  var xMinimum = double.infinity;
  var xMaximum = double.negativeInfinity;
  var sizeMaximum = 0.0;

  final series = <ChartSeries>[];
  for (final column in columns) {
    final index = table.indexOf(column);
    final points = <ChartPoint>[];
    for (final row in table.rows) {
      if (xIndex >= row.length || index >= row.length) {
        continue;
      }
      final x = parseChartNumber(row[xIndex]);
      final y = parseChartNumber(row[index]);
      if (x == null || y == null || !x.isFinite || !y.isFinite) {
        continue;
      }
      final rawSize = sizeIndex >= 0 && sizeIndex < row.length
          ? parseChartNumber(row[sizeIndex])
          : null;
      final size = rawSize != null && rawSize.isFinite ? rawSize : null;
      points.add(
        ChartPoint(
          label: nameIndex >= 0
              ? _label(nameIndex < row.length ? row[nameIndex] : '')
              : formatChartNumber(x),
          value: y,
          x: x,
          size: size,
        ),
      );
      minimum = y < minimum ? y : minimum;
      maximum = y > maximum ? y : maximum;
      xMinimum = x < xMinimum ? x : xMinimum;
      xMaximum = x > xMaximum ? x : xMaximum;
      if (size != null && size.abs() > sizeMaximum) {
        sizeMaximum = size.abs();
      }
    }
    // A line joins its points in the order they run, not the order rows sit in.
    points.sort((a, b) => (a.x ?? 0).compareTo(b.x ?? 0));
    series.add(ChartSeries(name: table.nameOf(column), points: points));
  }

  if (series.every((one) => one.points.isEmpty)) {
    return ChartData.empty;
  }

  // A flat run still deserves an axis, so give it a little room either side.
  if (minimum == maximum) {
    maximum += 1;
  }
  if (xMinimum == xMaximum) {
    xMaximum += 1;
  }

  return ChartData(
    categories: const [],
    series: series,
    minimum: minimum > 0 ? 0 : minimum,
    maximum: maximum,
    xMinimum: xMinimum,
    xMaximum: xMaximum,
    sizeMaximum: sizeMaximum,
    measuresX: true,
  );
}

class _ChartBucket {
  _ChartBucket(this.label);

  final String label;
  final values = <String, List<double>>{};
}

List<_ChartBucket> _sortCategories(
  List<_ChartBucket> order,
  List<String> seriesNames,
  ChartSort sort,
  ChartAggregate aggregate,
) {
  final sorted = [...order];
  double weight(_ChartBucket bucket) {
    var total = 0.0;
    for (final name in seriesNames) {
      total += aggregate.apply(bucket.values[name] ?? const []) ?? 0;
    }
    return total;
  }

  switch (sort) {
    case ChartSort.natural:
      break;
    case ChartSort.labelAscending:
      sorted.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    case ChartSort.valueDescending:
      sorted.sort((a, b) => weight(b).compareTo(weight(a)));
    case ChartSort.valueAscending:
      sorted.sort((a, b) => weight(a).compareTo(weight(b)));
  }
  return sorted;
}

List<_ChartBucket> _limit(
  List<_ChartBucket> sorted,
  List<String> seriesNames,
  int limit,
) {
  if (limit <= 0 || sorted.length <= limit) {
    return sorted;
  }
  final kept = sorted.take(limit - 1).toList();
  final rest = sorted.skip(limit - 1);
  final labels = kept.map((bucket) => bucket.label).toSet();
  var label = chartOtherCategory;
  for (var suffix = 2; labels.contains(label); suffix++) {
    label = '$chartOtherCategory ($suffix)';
  }
  final gathered = _ChartBucket(label);
  for (final bucket in rest) {
    for (final name in seriesNames) {
      gathered.values
          .putIfAbsent(name, () => <double>[])
          .addAll(bucket.values[name] ?? const []);
    }
  }
  return [...kept, gathered];
}
