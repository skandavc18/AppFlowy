import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/charts/chart_number.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading a number out of what a column shows', () {
    test('reads a plain number', () {
      expect(parseChartNumber('42'), 42);
      expect(parseChartNumber('-3.5'), -3.5);
      expect(parseChartNumber(' 7 '), 7);
    });

    test('reads a formatted amount', () {
      expect(parseChartNumber(r'$1,204.50'), 1204.5);
      expect(parseChartNumber('€48'), 48);
      expect(parseChartNumber('1,204'), 1204);
      expect(parseChartNumber('12 %'), 12);
    });

    test('reads a European decimal', () {
      expect(parseChartNumber('1.204,50'), 1204.5);
      expect(parseChartNumber('3,5'), 3.5);
    });

    test('reads a bracketed negative', () {
      expect(parseChartNumber(r'($48.00)'), -48);
    });

    test('reads a checkbox as one or zero', () {
      expect(parseChartNumber('Yes'), 1);
      expect(parseChartNumber('true'), 1);
      expect(parseChartNumber('No'), 0);
      expect(parseChartNumber('unchecked'), 0);
    });

    test('reads a duration as seconds', () {
      // A database shows a duration as hours and minutes, so 1:30 is an hour
      // and a half rather than ninety seconds.
      expect(parseChartNumber('1:30'), 5400);
      expect(parseChartNumber('01:30:15'), 5415);
      expect(parseChartNumber('2h 30m'), 9000);
      expect(parseChartNumber('45m'), 2700);
    });

    test('reads a date as its instant', () {
      final value = parseChartNumber('2026-08-01T00:00:00Z');
      expect(value, isNotNull);
      expect(
        DateTime.fromMillisecondsSinceEpoch((value! * 1000).round(),
                isUtc: true,)
            .year,
        2026,
      );
    });

    test('answers nothing for text that holds no number', () {
      expect(parseChartNumber('Marketing'), isNull);
      expect(parseChartNumber(''), isNull);
      expect(parseChartNumber(null), isNull);
      expect(parseChartNumber('—'), isNull);
    });

    test('calls a column numeric only when most of it reads as a number', () {
      expect(looksNumeric(['1', '2', 'three']), isTrue);
      expect(looksNumeric(['Marketing', 'Sales', '3']), isFalse);
      expect(looksNumeric([]), isFalse);
      expect(looksNumeric(['', '  ']), isFalse);
    });
  });

  group('a table read for charting', () {
    test('takes the first row as the column names', () {
      final table = ChartTable.fromRows([
        ['Team', 'Budget'],
        ['Design', '100'],
        ['Sales', '250'],
      ]);

      expect(table.columns, ['Team', 'Budget']);
      expect(table.rows, hasLength(2));
      expect(table.numericColumns, ['Budget']);
    });

    test('names a column that has none, and separates repeats', () {
      final table = ChartTable.fromRows([
        ['Team', '', 'Team'],
        ['Design', 'x', 'y'],
      ]);

      expect(table.columns, ['Team', 'Column 2', 'Team (2)']);
    });

    test('drops a row that is entirely blank', () {
      final table = ChartTable.fromRows([
        ['Team'],
        ['Design'],
        ['  '],
      ]);

      expect(table.rows, hasLength(1));
    });
  });

  group('building the series a chart draws', () {
    final table = ChartTable.fromRows([
      ['Team', 'Budget', 'Spent'],
      ['Design', '100', '40'],
      ['Sales', '250', '90'],
      ['Design', '50', '10'],
    ]);

    test('adds up a column for each category', () {
      final data = buildChartData(
        table,
        const ChartSpec(categoryColumn: 'Team', valueColumns: ['Budget']),
      );

      expect(data.categories, ['Design', 'Sales']);
      expect(data.series, hasLength(1));
      expect(data.series.single.points.map((p) => p.value), [150, 250]);
      expect(data.maximum, 250);
    });

    test('plots one series per chosen column', () {
      final data = buildChartData(
        table,
        const ChartSpec(
          categoryColumn: 'Team',
          valueColumns: ['Budget', 'Spent'],
        ),
      );

      expect(data.series.map((s) => s.name), ['Budget', 'Spent']);
      expect(data.series.last.points.map((p) => p.value), [50, 90]);
    });

    test('averages instead of adding when asked', () {
      final data = buildChartData(
        table,
        const ChartSpec(
          categoryColumn: 'Team',
          valueColumns: ['Budget'],
          aggregate: ChartAggregate.average,
        ),
      );

      expect(data.series.single.points.first.value, 75);
    });

    test('counts the rows when no column is chosen', () {
      final data = buildChartData(
        table,
        const ChartSpec(categoryColumn: 'Team'),
      );

      expect(data.series.single.points.map((p) => p.value), [2, 1]);
    });

    test('orders by value when asked', () {
      final data = buildChartData(
        table,
        const ChartSpec(
          categoryColumn: 'Team',
          valueColumns: ['Budget'],
          sort: ChartSort.valueDescending,
        ),
      );

      expect(data.categories, ['Sales', 'Design']);
    });

    test('gathers a long tail rather than drawing all of it', () {
      final rows = [
        ['Team', 'Budget'],
        for (var index = 0; index < 10; index++) ['Team $index', '$index'],
      ];
      final data = buildChartData(
        ChartTable.fromRows(rows),
        const ChartSpec(
          categoryColumn: 'Team',
          valueColumns: ['Budget'],
          categoryLimit: 4,
        ),
      );

      expect(data.categories, hasLength(4));
      expect(data.categories.last, chartOtherCategory);
      // 3 + 4 + … + 9
      expect(data.series.single.points.last.value, 42);
    });

    test('names an empty category rather than dropping the row', () {
      final data = buildChartData(
        ChartTable.fromRows([
          ['Team', 'Budget'],
          ['', '10'],
        ]),
        const ChartSpec(categoryColumn: 'Team', valueColumns: ['Budget']),
      );

      expect(data.categories, ['—']);
    });

    test('is empty when there is nothing to read', () {
      expect(buildChartData(ChartTable.empty, const ChartSpec()).isEmpty, true);
    });
  });

  group('a chart specification', () {
    test('round trips through its stored form', () {
      const spec = ChartSpec(
        type: ChartType.line,
        categoryColumn: 'Team',
        valueColumns: ['Budget', 'Spent'],
        aggregate: ChartAggregate.median,
        sort: ChartSort.valueAscending,
        categoryLimit: 8,
        showLegend: false,
        showValues: true,
        showGrid: false,
      );

      final restored = ChartSpec.fromJson(spec.toJson());
      expect(restored, spec);
    });

    test('opens as a bar chart that adds things up', () {
      final fresh = ChartSpec.fromJson(const {});
      expect(fresh.type, ChartType.bar);
      expect(fresh.aggregate, ChartAggregate.sum);
      expect(fresh.valueColumns, isEmpty);
      expect(fresh.countsRows, isTrue);
    });

    test('keeps its controls out of the way until they are asked for', () {
      expect(const ChartSpec().showControls, isFalse);
      expect(ChartSpec.fromJson(const {}).showControls, isFalse);

      const shown = ChartSpec(showControls: true);
      expect(ChartSpec.fromJson(shown.toJson()).showControls, isTrue);
    });
  });

  group('the mark that turns a table into a chart', () {
    test('rides along in a view without disturbing what is already there', () {
      const existing = '{"appflowy_folder":{"version":1}}';
      final extra = const ChartMetadata(
        spec: ChartSpec(type: ChartType.donut, categoryColumn: 'Stage'),
      ).mergeIntoExtra(existing);

      final read = ChartMetadata.fromExtra(extra);
      expect(read, isNotNull);
      expect(read!.spec.type, ChartType.donut);
      expect(read.spec.categoryColumn, 'Stage');
      // The folder note it was placed beside is untouched.
      expect(extra, contains('appflowy_folder'));
    });

    test('remembers which side of the table was showing', () {
      final extra = const ChartMetadata(spec: ChartSpec(), showTable: true)
          .mergeIntoExtra('');
      expect(ChartMetadata.fromExtra(extra)!.showTable, isTrue);
    });

    test('is absent from a plain table', () {
      expect(ChartMetadata.fromExtra(''), isNull);
      expect(ChartMetadata.fromExtra('{"appflowy_folder":{}}'), isNull);
    });

    test('can be taken off, leaving the table it always was', () {
      final extra = ChartMetadata.newExtra();
      expect(ChartMetadata.fromExtra(extra), isNotNull);
      expect(ChartMetadata.fromExtra(ChartMetadata.removeFromExtra(extra)),
          isNull,);
    });
  });

  group('the tables offered when adding something new', () {
    test('offers a chart beside the grid, the board and the calendar', () {
      expect(
        WorkspaceTableKind.values.take(3).map((kind) => kind.layout).toList(),
        const [
          ViewLayoutPB.Grid,
          ViewLayoutPB.Board,
          ViewLayoutPB.Calendar,
        ],
      );
      expect(WorkspaceTableKind.values, contains(WorkspaceTableKind.chart));
    });

    test('a chart is a real table underneath', () {
      expect(WorkspaceTableKind.chart.layout, ViewLayoutPB.Grid);
      expect(WorkspaceTableKind.chart.charted, isTrue);
      expect(WorkspaceTableKind.table.charted, isFalse);
    });
  });

  group('choosing what each axis measures', () {
    final table = ChartTable.fromRows([
      ['Name', 'Width', 'Height', 'Weight'],
      ['A', '1', '10', '5'],
      ['B', '3', '30', '9'],
      ['C', '2', '20', '1'],
    ]);

    test('only the types that run continuously offer a measured axis', () {
      expect(ChartType.scatter.supportsValueAxis, isTrue);
      expect(ChartType.line.supportsValueAxis, isTrue);
      expect(ChartType.bubble.supportsValueAxis, isTrue);
      expect(ChartType.bar.supportsValueAxis, isFalse);
      expect(ChartType.pie.supportsValueAxis, isFalse);
    });

    test('a bar chart ignores an x column it cannot use', () {
      const spec = ChartSpec(
        xColumn: 'Width',
        valueColumns: ['Height'],
      );
      expect(spec.plotsAgainstValues, isFalse);
    });

    test('a scatter plots every row where its own numbers put it', () {
      const spec = ChartSpec(
        type: ChartType.scatter,
        xColumn: 'Width',
        valueColumns: ['Height'],
      );
      final data = buildChartData(table, spec);

      expect(data.measuresX, isTrue);
      expect(data.series, hasLength(1));
      // Rows are read in the order the axis runs, not the order they sit in.
      expect(
        data.series.first.points.map((point) => point.x).toList(),
        [1, 2, 3],
      );
      expect(
        data.series.first.points.map((point) => point.value).toList(),
        [10, 20, 30],
      );
      expect(data.xMinimum, 1);
      expect(data.xMaximum, 3);
    });

    test('a point keeps the name of the row it came from', () {
      const spec = ChartSpec(
        type: ChartType.scatter,
        categoryColumn: 'Name',
        xColumn: 'Width',
        valueColumns: ['Height'],
      );
      final data = buildChartData(table, spec);
      expect(
        data.series.first.points.map((point) => point.label).toList(),
        ['A', 'C', 'B'],
      );
    });

    test('a bubble carries the size its column gives it', () {
      const spec = ChartSpec(
        type: ChartType.bubble,
        xColumn: 'Width',
        sizeColumn: 'Weight',
        valueColumns: ['Height'],
      );
      final data = buildChartData(table, spec);
      expect(data.sizeMaximum, 9);
      expect(
        data.series.first.points.map((point) => point.size).toList(),
        [5, 1, 9],
      );
    });

    test('a measured chart with no numbers to plot has nothing to draw', () {
      const spec = ChartSpec(
        type: ChartType.scatter,
        xColumn: 'Name',
        valueColumns: ['Height'],
      );
      // 'Name' holds no numbers, so no row lands anywhere.
      expect(buildChartData(table, spec).isEmpty, isTrue);
    });

    test('both axes survive being stored and read back', () {
      const spec = ChartSpec(
        type: ChartType.bubble,
        categoryColumn: 'Name',
        xColumn: 'Width',
        sizeColumn: 'Weight',
        valueColumns: ['Height'],
      );
      expect(ChartSpec.fromJson(spec.toJson()), spec);
    });
  });

  group('showing a number the way a reader expects', () {
    test('abbreviates a long run on an axis', () {
      expect(formatChartNumber(1500), '1.5K');
      expect(formatChartNumber(2400000), '2.4M');
      expect(formatChartNumber(3000000000), '3B');
    });

    test('drops the zeros nobody needs', () {
      expect(formatChartNumber(4), '4');
      expect(formatChartNumber(4.50), '4.5');
      expect(formatChartNumber(0), '0');
    });

    test('keeps small numbers legible', () {
      expect(formatChartNumber(0.125), '0.125');
      expect(formatChartNumber(0.0004), '0.0004');
    });

    test('a tooltip shows the number in full', () {
      expect(formatChartNumber(1500, compact: false), '1500');
    });
  });

  group('how far a chart is zoomed', () {
    test('starts showing everything', () {
      expect(ChartViewport.identity.isIdentity, isTrue);
      expect(ChartViewport.identity.offset, 0);
    });

    test('keeps what is under the pointer where it is', () {
      final zoomed = ChartViewport.identity.zoomed(2, 0.5);
      expect(zoomed.scale, 2);
      // Half of the run, centred on the middle.
      expect(zoomed.offset, closeTo(0.25, 0.0001));
    });

    test('never scrolls past either end', () {
      final zoomed = ChartViewport.identity.zoomed(2, 0.5).panned(5);
      expect(zoomed.offset, closeTo(0.5, 0.0001));
      expect(zoomed.panned(-5).offset, 0);
    });

    test('zooming back out lands exactly on the whole run', () {
      final out = ChartViewport.identity.zoomed(2, 0.5).zoomed(0.4, 0.5);
      expect(out.isIdentity, isTrue);
      expect(out.offset, 0);
    });
  });

  group('what colour a chart is drawn in', () {
    const palette = ChartPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      grid: Color(0x11000000),
      axis: Color(0x22000000),
      label: Color(0x88000000),
      strongLabel: Color(0xDD000000),
      series: ChartPalette.defaultSeries,
      baseTextStyle: TextStyle(),
      shadow: Color(0x22000000),
      border: Color(0x11000000),
      chip: Color(0x08000000),
      chipHover: Color(0x14000000),
      isDark: false,
    );

    test('takes its colours from the chosen set', () {
      const spec = ChartSpec(palette: ChartPaletteName.ocean);
      final colors = ChartColors.of(palette, spec);
      expect(
        colors.at(0, 'Revenue'),
        ChartPalette.sets[ChartPaletteName.ocean]!.first,
      );
    });

    test('every set holds enough colours to go round', () {
      for (final entry in ChartPalette.sets.entries) {
        expect(entry.value, hasLength(10), reason: entry.key.name);
      }
    });

    test('a chosen colour wins over the set', () {
      const chosen = 0xFF123456;
      final spec = const ChartSpec(palette: ChartPaletteName.ocean).withColor(
        'Revenue',
        chosen,
      );
      final colors = ChartColors.of(palette, spec);

      expect(colors.at(0, 'Revenue'), const Color(chosen));
      expect(colors.isChosen(0, 'Revenue'), isTrue);
      // A series nobody touched still follows the set.
      expect(colors.isChosen(1, 'Cost'), isFalse);
    });

    test('a colour can be handed back to the palette', () {
      final spec = const ChartSpec().withColor('Revenue', 0xFF123456);
      expect(spec.colors, isNotEmpty);
      expect(spec.withColor('Revenue', null).colors, isEmpty);
    });

    test('a nameless series is keyed by its place in the order', () {
      expect(chartColorKey('', 0), '#0');
      expect(chartColorKey('Revenue', 0), 'Revenue');
    });

    test('colours survive being stored and read back', () {
      final spec = const ChartSpec(palette: ChartPaletteName.berry)
          .withColor('Revenue', 0xFF123456)
          .withColor('#1', 0xFF654321);
      expect(ChartSpec.fromJson(spec.toJson()), spec);
    });

    test('a dark canvas lifts whichever set was chosen', () {
      const dark = ChartPalette(
        background: Color(0xFF1B1B1B),
        surface: Color(0xFF222222),
        grid: Color(0x11FFFFFF),
        axis: Color(0x22FFFFFF),
        label: Color(0x88FFFFFF),
        strongLabel: Color(0xDDFFFFFF),
        series: ChartPalette.darkSeries,
        baseTextStyle: TextStyle(),
        shadow: Color(0x66000000),
        border: Color(0x11FFFFFF),
        chip: Color(0x11FFFFFF),
        chipHover: Color(0x1FFFFFFF),
        isDark: true,
      );
      final lifted = dark.withSet(ChartPaletteName.slate).colorAt(0);
      final flat = ChartPalette.sets[ChartPaletteName.slate]!.first;
      expect(
        HSLColor.fromColor(lifted).lightness,
        greaterThan(HSLColor.fromColor(flat).lightness),
      );
    });

    test('packing a colour round trips it', () {
      const color = Color(0xFF5B8DEF);
      expect(Color(ChartColors.packed(color)), color);
    });
  });
}
