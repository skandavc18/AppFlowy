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
  const ChartTable({required this.columns, required this.rows});

  /// Builds a table from a delimited export, taking the first row as names.
  factory ChartTable.fromRows(List<List<String>> source) {
    if (source.isEmpty) {
      return ChartTable.empty;
    }
    final header = source.first.map((cell) => cell.trim()).toList();
    final seen = <String, int>{};
    final columns = <String>[];
    for (var index = 0; index < header.length; index++) {
      var name = header[index].isEmpty ? 'Column ${index + 1}' : header[index];
      // Two columns with one name would make a spec ambiguous.
      final count = seen.update(name, (value) => value + 1, ifAbsent: () => 1);
      if (count > 1) {
        name = '$name ($count)';
      }
      columns.add(name);
    }
    return ChartTable(
      columns: columns,
      rows: [
        for (final row in source.skip(1))
          if (row.any((cell) => cell.trim().isNotEmpty)) row,
      ],
    );
  }

  static const empty = ChartTable(columns: [], rows: []);

  final List<String> columns;
  final List<List<String>> rows;

  bool get isEmpty => columns.isEmpty || rows.isEmpty;

  int indexOf(String? column) => column == null ? -1 : columns.indexOf(column);

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

  final categoryIndex = table.indexOf(spec.categoryColumn);
  final valueIndices = <String, int>{
    for (final column in spec.valueColumns)
      if (table.indexOf(column) >= 0) column: table.indexOf(column),
  };
  final counting = spec.countsRows || valueIndices.isEmpty;

  // Gather each category's raw numbers before collapsing them, so every
  // aggregate reads the same set.
  final order = <String>[];
  final buckets = <String, Map<String, List<double>>>{};
  for (final row in table.rows) {
    final label = categoryIndex >= 0 && categoryIndex < row.length
        ? _label(row[categoryIndex])
        : _label(row.isEmpty ? '' : row.first);
    final bucket = buckets.putIfAbsent(label, () {
      order.add(label);
      return <String, List<double>>{};
    });
    if (counting) {
      bucket.putIfAbsent('', () => <double>[]).add(1);
      continue;
    }
    for (final entry in valueIndices.entries) {
      final index = entry.value;
      if (index >= row.length) {
        continue;
      }
      final number = parseChartNumber(row[index]);
      if (number != null) {
        bucket.putIfAbsent(entry.key, () => <double>[]).add(number);
      }
    }
  }

  final seriesNames = counting ? const [''] : valueIndices.keys.toList();
  final sorted = _sortCategories(order, buckets, seriesNames, spec);
  final categories = _limit(sorted, buckets, seriesNames, spec);

  var minimum = 0.0;
  var maximum = 0.0;
  final series = <ChartSeries>[];
  for (final name in seriesNames) {
    final points = <ChartPoint>[];
    for (final category in categories) {
      final values = buckets[category]?[name] ?? const <double>[];
      final value = spec.aggregate.apply(values) ?? 0;
      points.add(ChartPoint(label: category, value: value));
      minimum = value < minimum ? value : minimum;
      maximum = value > maximum ? value : maximum;
    }
    series.add(ChartSeries(name: name, points: points));
  }

  if (spec.type.isStacked) {
    for (var index = 0; index < categories.length; index++) {
      final stacked = series.fold<double>(
        0,
        (sum, one) => sum + one.points[index].value,
      );
      maximum = stacked > maximum ? stacked : maximum;
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
  if (xIndex < 0) {
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
      if (x == null || y == null) {
        continue;
      }
      final size = sizeIndex >= 0 && sizeIndex < row.length
          ? parseChartNumber(row[sizeIndex])
          : null;
      points.add(
        ChartPoint(
          label: nameIndex >= 0 && nameIndex < row.length
              ? _label(row[nameIndex])
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
    series.add(ChartSeries(name: column, points: points));
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

List<String> _sortCategories(
  List<String> order,
  Map<String, Map<String, List<double>>> buckets,
  List<String> seriesNames,
  ChartSpec spec,
) {
  final sorted = [...order];
  double weight(String category) {
    var total = 0.0;
    for (final name in seriesNames) {
      total += spec.aggregate.apply(buckets[category]?[name] ?? const []) ?? 0;
    }
    return total;
  }

  switch (spec.sort) {
    case ChartSort.natural:
      break;
    case ChartSort.labelAscending:
      sorted.sort(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
    case ChartSort.valueDescending:
      sorted.sort((a, b) => weight(b).compareTo(weight(a)));
    case ChartSort.valueAscending:
      sorted.sort((a, b) => weight(a).compareTo(weight(b)));
  }
  return sorted;
}

List<String> _limit(
  List<String> sorted,
  Map<String, Map<String, List<double>>> buckets,
  List<String> seriesNames,
  ChartSpec spec,
) {
  if (spec.categoryLimit <= 0 || sorted.length <= spec.categoryLimit) {
    return sorted;
  }
  final kept = sorted.take(spec.categoryLimit - 1).toList();
  final rest = sorted.skip(spec.categoryLimit - 1);
  final gathered = <String, List<double>>{};
  for (final category in rest) {
    final bucket = buckets[category];
    if (bucket == null) {
      continue;
    }
    for (final name in seriesNames) {
      gathered
          .putIfAbsent(name, () => <double>[])
          .addAll(bucket[name] ?? const []);
    }
  }
  buckets[chartOtherCategory] = gathered;
  return [...kept, chartOtherCategory];
}
