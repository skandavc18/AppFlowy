import 'dart:async';
import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_painter.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/shared/charts/chart_toolbar.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/charts/chart_settings.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widget_test/test_asset_bundle.dart';

const _table = ChartTable(
  columns: ['Title', 'Team', 'Status', 'Amount', 'Rank', 'Size', 'Date'],
  columnIds: [
    'title-id',
    'team-id',
    'status-id',
    'amount-id',
    'rank-id',
    'size-id',
    'date-id',
  ],
  rows: [
    ['Same', 'North', 'Open', '2', '1', '10', 'Sep 18, 2026'],
    ['Same', 'South', 'Open', '10', '3', '30', 'Sep 18, 2026'],
    ['Third', 'North', 'Closed', '6', '2', '20', 'Sep 19, 2026'],
    ['Missing', '', 'Closed', '', '', '', ''],
  ],
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  group('the selected group is the actual chart bucket', () {
    for (final type in ChartType.values.where((type) => !type.drawsPoints)) {
      test('${type.name}: reselecting Group by rebuilds categories and totals',
          () {
        final spec = ChartSpec(
          type: type,
          categoryColumn: 'team-id',
          valueColumns: const ['amount-id'],
        );
        final team = buildChartData(_table, spec);
        final status = buildChartData(
          _table,
          spec.copyWith(categoryColumn: 'status-id'),
        );
        expect(team.categories, ['North', 'South', '—']);
        expect(_values(team), [8, 10, 0]);
        expect(status.categories, ['Open', 'Closed']);
        expect(_values(status), [12, 6]);
        expect(status.series.single.name, 'Amount');
        expect(status.measuresX, isFalse);
        expect(_values(buildChartData(_table, spec)), [8, 10, 0]);
      });
    }

    for (final aggregate in ChartAggregate.values) {
      test('Count rows remains a count after ${aggregate.name}', () {
        final data = buildChartData(
          _table,
          ChartSpec(categoryColumn: 'team-id', aggregate: aggregate),
        );
        expect(data.categories, ['North', 'South', '—']);
        expect(_values(data), [2, 1, 1]);
      });
    }

    test('Every row keeps duplicate titles separate', () {
      final data = buildChartData(
        _table,
        const ChartSpec(valueColumns: ['amount-id']),
      );
      expect(data.categories, ['Same', 'Same', 'Third', 'Missing']);
      expect(_values(data), [2, 10, 6, 0]);
    });

    test('short and empty group cells share the missing bucket, not row titles',
        () {
      final table = ChartTable.fromRows([
        ['Title', 'Amount', 'Group'],
        ['First', '3', 'Present'],
        ['Second', '4'],
        ['Third', '5', '  '],
      ]);
      final data = buildChartData(
        table,
        const ChartSpec(categoryColumn: 'Group', valueColumns: ['Amount']),
      );
      expect(data.categories, ['Present', '—']);
      expect(_values(data), [3, 9]);
    });

    test('select labels, numbers and displayed dates are literal categories',
        () {
      final table = ChartTable.fromRows([
        ['Select', 'Number', 'Date', 'Amount'],
        ['Open, queued', '0', 'Sep 18, 2026', '1'],
        ['Open, queued', '0', 'Sep 18, 2026', '2'],
        ['Closed', '-2', 'Sep 19, 2026', '3'],
        ['', '', '', '4'],
      ]);
      final expected = {
        'Select': ['Open, queued', 'Closed', '—'],
        'Number': ['0', '-2', '—'],
        'Date': ['Sep 18, 2026', 'Sep 19, 2026', '—'],
      };
      for (final entry in expected.entries) {
        final data = buildChartData(
          table,
          ChartSpec(categoryColumn: entry.key),
        );
        expect(data.categories, entry.value, reason: entry.key);
        expect(_values(data), [2, 1, 1], reason: entry.key);
      }
    });

    test('missing columns never substitute the first column or a row count',
        () {
      const missingGroup = ChartSpec(
        categoryColumn: 'removed-group',
        valueColumns: ['amount-id'],
      );
      const missingValue = ChartSpec(
        categoryColumn: 'team-id',
        valueColumns: ['removed-value'],
      );
      expect(_table.resolveSpec(missingGroup).categoryColumn, 'removed-group');
      expect(buildChartData(_table, missingGroup).isEmpty, isTrue);
      expect(buildChartData(_table, missingValue).isEmpty, isTrue);
      expect(
        buildChartData(
          _table,
          const ChartSpec(
            type: ChartType.line,
            xColumn: 'removed-x',
            valueColumns: ['amount-id'],
          ),
        ).isEmpty,
        isTrue,
      );
    });

    test('all aggregates use the selected bucket, including zero and negatives',
        () {
      final table = ChartTable.fromRows([
        ['Group', 'Amount', 'Second'],
        ['A', '-2', '5'],
        ['A', '0', '7'],
        ['A', '8', ''],
        ['A', '', '9'],
        ['B', '10', '1'],
      ]);
      final expected = {
        ChartAggregate.sum: 6.0,
        ChartAggregate.average: 2.0,
        ChartAggregate.count: 4.0,
        ChartAggregate.min: -2.0,
        ChartAggregate.max: 8.0,
        ChartAggregate.median: 0.0,
      };
      for (final entry in expected.entries) {
        final data = buildChartData(
          table,
          ChartSpec(
            categoryColumn: 'Group',
            valueColumns: const ['Amount', 'Second'],
            aggregate: entry.key,
          ),
        );
        expect(data.categories, ['A', 'B']);
        expect(data.series.first.points.first.value, entry.value);
        if (entry.key != ChartAggregate.count) {
          expect(
            data.series.map((series) => series.name),
            ['Amount', 'Second'],
          );
        }
      }
    });

    test('count sorting uses row counts even after a numeric aggregation', () {
      final data = buildChartData(
        _table,
        const ChartSpec(
          categoryColumn: 'status-id',
          aggregate: ChartAggregate.min,
          sort: ChartSort.labelAscending,
        ),
      );
      expect(data.categories, ['Closed', 'Open']);
      expect(_values(data), [2, 2]);
      final descending = buildChartData(
        _table,
        const ChartSpec(
          categoryColumn: 'team-id',
          aggregate: ChartAggregate.average,
          sort: ChartSort.valueDescending,
        ),
      );
      expect(descending.categories.first, 'North');
      expect(descending.series.single.points.first.value, 2);
    });

    test('a real Other category is not overwritten by the long tail', () {
      final table = ChartTable.fromRows([
        ['Group', 'Amount'],
        ['Other', '7'],
        ['B', '1'],
        ['C', '2'],
        ['D', '3'],
      ]);
      const spec = ChartSpec(
        categoryColumn: 'Group',
        valueColumns: ['Amount'],
        categoryLimit: 2,
      );
      final data = buildChartData(table, spec);
      expect(data.categories, ['Other', 'Other (2)']);
      expect(_values(data), [7, 6]);
      expect(
        _values(buildChartData(table, spec.copyWith(categoryLimit: 1))),
        [13],
      );
      expect(
        buildChartData(table, spec.copyWith(categoryLimit: 0)).categories,
        ['Other', 'B', 'C', 'D'],
      );
    });

    test(
        'the tail averages raw rows rather than averages of differently sized groups',
        () {
      final table = ChartTable.fromRows([
        ['Group', 'Amount'],
        ['Keep', '99'],
        ['B', '1'],
        ['B', '9'],
        ['C', '20'],
      ]);
      final data = buildChartData(
        table,
        const ChartSpec(
          categoryColumn: 'Group',
          valueColumns: ['Amount'],
          aggregate: ChartAggregate.average,
          categoryLimit: 2,
        ),
      );
      expect(data.categories, ['Keep', 'Other']);
      expect(_values(data), [99, 10]);
    });

    for (final type in [ChartType.stackedBar, ChartType.stackedArea]) {
      test(
          '${type.name}: grouped ranges include every positive and negative stack',
          () {
        final table = ChartTable.fromRows([
          ['Group', 'First', 'Second', 'Third'],
          ['A', '-5', '-7', '2'],
          ['B', '5', '7', '-2'],
        ]);
        final data = buildChartData(
          table,
          ChartSpec(
            type: type,
            categoryColumn: 'Group',
            valueColumns: const ['First', 'Second', 'Third'],
          ),
        );
        expect(data.minimum, -12);
        expect(data.maximum, 12);
      });
    }
  });

  group('database columns are resolved by identity', () {
    test('row fieldIds, not the schema response order, define cell positions',
        () {
      final rows = RepeatedRowTextPB(
        fieldIds: ['amount', 'group', 'title'],
        rows: [
          RowTextPB(rowId: 'one', cells: ['2', 'North', 'First']),
          RowTextPB(rowId: 'two', cells: ['6', 'North', 'Second']),
          RowTextPB(rowId: 'three', cells: ['10', 'South', 'Third']),
          RowTextPB(rowId: 'blank'),
        ],
      );
      final table = chartTableFromRowText(rows, [
        FieldPB(id: 'title', name: 'Title'),
        FieldPB(id: 'group', name: 'Team', fieldType: FieldType.SingleSelect),
        FieldPB(id: 'amount', name: 'Amount', fieldType: FieldType.Number),
      ]);
      expect(table.columns, ['Amount', 'Team', 'Title']);
      expect(table.columnKeys, ['amount', 'group', 'title']);
      expect(
        table.rows,
        hasLength(4),
        reason: 'A blank database row still exists',
      );
      final spec = table.resolveSpec(
        const ChartSpec(categoryColumn: 'Team', valueColumns: ['Amount']),
      );
      expect(spec.categoryColumn, 'group');
      expect(spec.valueColumns, ['amount']);
      expect(table.displaySpec(spec).categoryColumn, 'Team');
      expect(_values(buildChartData(table, spec)), [8, 10, 0]);
      expect(
        _values(buildChartData(table, spec.copyWith(valueColumns: []))),
        [2, 1, 1],
      );
    });

    test('renames and column reordering preserve a saved Group by choice', () {
      final saved = ChartMetadata(
        spec: _table.resolveSpec(
          const ChartSpec(categoryColumn: 'Team', valueColumns: ['Amount']),
        ),
      ).mergeIntoExtra('{"unrelated":{"keep":true}}');
      final renamed = chartTableFromRowText(
        RepeatedRowTextPB(
          fieldIds: ['amount-id', 'team-id'],
          rows: [
            RowTextPB(rowId: 'one', cells: ['2', 'North']),
            RowTextPB(rowId: 'two', cells: ['10', 'South']),
            RowTextPB(rowId: 'three', cells: ['6', 'North']),
          ],
        ),
        [
          FieldPB(id: 'team-id', name: 'Division'),
          FieldPB(id: 'amount-id', name: 'Budget'),
        ],
      );
      final restored = ChartMetadata.fromExtra(saved)!.spec;
      final data = buildChartData(renamed, restored);
      expect(data.categories, ['North', 'South']);
      expect(_values(data), [8, 10]);
      expect(data.series.single.name, 'Budget');
      expect(renamed.displaySpec(restored).categoryColumn, 'Division');
      expect((jsonDecode(saved) as Map)['unrelated'], {'keep': true});
    });

    test(
        'duplicate and already-suffixed headings stay independently selectable',
        () {
      final table = ChartTable.fromRows(
        [
          ['Group', 'Group', 'Group (2)', 'Amount'],
          ['A', 'X', 'First', '2'],
          ['A', 'Y', 'Second', '3'],
          ['B', 'X', 'Third', '4'],
        ],
        columnIds: ['first', 'second', 'literal-suffix', 'amount'],
      );
      expect(table.columns.toSet(), hasLength(4));
      expect(table.nameOf('literal-suffix'), 'Group (2)');
      final first = buildChartData(
        table,
        const ChartSpec(categoryColumn: 'first', valueColumns: ['amount']),
      );
      final second = buildChartData(
        table,
        const ChartSpec(categoryColumn: 'second', valueColumns: ['amount']),
      );
      expect(first.categories, ['A', 'B']);
      expect(_values(first), [5, 4]);
      expect(second.categories, ['X', 'Y']);
      expect(_values(second), [6, 3]);
    });

    test('resolving and storing empty choices does not reintroduce defaults',
        () {
      final resolved = _table.resolveSpec(
        const ChartSpec(aggregate: ChartAggregate.average, showControls: true),
      );
      final restored = ChartSpec.fromJson(resolved.toJson());
      expect(restored.categoryColumn, isNull);
      expect(restored.valueColumns, isEmpty);
      expect(restored.xColumn, isNull);
      expect(_values(buildChartData(_table, restored)), [1, 1, 1, 1]);
    });
  });

  group('measured charts keep their numeric semantics', () {
    for (final type
        in ChartType.values.where((type) => type.supportsValueAxis)) {
      test('${type.name}: changing labels does not collapse XY points', () {
        final spec = ChartSpec(
          type: type,
          categoryColumn: 'team-id',
          xColumn: 'rank-id',
          valueColumns: const ['amount-id'],
          sizeColumn: 'size-id',
        );
        final team = buildChartData(_table, spec);
        final status = buildChartData(
          _table,
          spec.copyWith(categoryColumn: 'status-id'),
        );
        expect(status.measuresX, isTrue);
        expect(status.categories, isEmpty);
        expect(status.series.single.points.map((point) => point.x), [1, 2, 3]);
        expect(_values(status), [2, 6, 10]);
        expect(
          team.series.single.points.map((point) => point.label),
          ['North', 'North', 'South'],
        );
        expect(
          status.series.single.points.map((point) => point.label),
          ['Open', 'Closed', 'Open'],
        );
        expect(
          status.series.single.points.map((point) => point.size),
          [10, 20, 30],
        );
        expect(status.sizeMaximum, 30);
      });
    }

    for (final type in [ChartType.scatter, ChartType.bubble]) {
      test('${type.name}: no numeric X is not a categorical line chart', () {
        expect(
          buildChartData(
            _table,
            ChartSpec(
              type: type,
              categoryColumn: 'team-id',
              valueColumns: const ['amount-id'],
            ),
          ).isEmpty,
          isTrue,
        );
      });
    }

    test('non-finite numeric cells cannot poison axes or bubble sizes', () {
      final table = ChartTable.fromRows([
        ['X', 'Y', 'Size'],
        ['1', '2', '1e999'],
        ['1e999', '3', '4'],
        ['2', '1e999', '4'],
      ]);
      final data = buildChartData(
        table,
        const ChartSpec(
          type: ChartType.bubble,
          xColumn: 'X',
          valueColumns: ['Y'],
          sizeColumn: 'Size',
        ),
      );
      expect(_values(data), [2]);
      expect(data.series.single.points.single.size, isNull);
      expect(data.maximum.isFinite, isTrue);
      expect(data.xMaximum.isFinite, isTrue);
      expect(data.sizeMaximum, 0);
    });
  });

  group('refresh and saved grouping', () {
    test('a refresh during a read waits for one follow-up read', () async {
      final first = Completer<ChartTable>();
      final second = Completer<ChartTable>();
      final secondStarted = Completer<void>();
      final requestedViews = <String>[];
      var reads = 0;
      final source = ChartSource(
        viewId: 'requested-chart-view',
        loadTable: (viewId) {
          requestedViews.add(viewId);
          reads++;
          if (reads == 1) return first.future;
          secondStarted.complete();
          return second.future;
        },
      );
      addTearDown(source.dispose);
      final initial = source.load();
      final refresh = source.load();
      final repeated = source.load();
      expect(refresh, same(initial));
      expect(repeated, same(initial));
      first.complete(_table);
      await secondStarted.future;
      expect(source.isLoading, isTrue);
      second.complete(ChartTable.empty);
      await refresh;
      expect(reads, 2);
      expect(requestedViews, ['requested-chart-view', 'requested-chart-view']);
      expect(source.table, same(ChartTable.empty));
      expect(source.isLoading, isFalse);
    });

    testWidgets('invalidations coalesce and disposal cancels pending refreshes',
        (tester) async {
      var reads = 0;
      final source = ChartSource(
        viewId: 'chart',
        loadTable: (_) async {
          reads++;
          return _table;
        },
      );
      await source.load();
      source.invalidate();
      source.invalidate();
      await tester.pump(const Duration(milliseconds: 399));
      expect(reads, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(reads, 2);
      source.invalidate();
      source.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(reads, 2);
    });

    test('a failed read retains the snapshot and the next refresh can recover',
        () async {
      var fail = false;
      final source = ChartSource(
        viewId: 'chart',
        loadTable: (_) async {
          if (fail) throw StateError('synthetic read failure');
          return _table;
        },
      );
      addTearDown(source.dispose);
      await source.load();
      fail = true;
      await source.load();
      expect(source.error, isNotNull);
      expect(source.table, same(_table));
      fail = false;
      await source.load();
      expect(source.error, isNull);
      expect(source.isLoading, isFalse);
    });

    test('disposing an in-flight source discards the late result', () async {
      final result = Completer<ChartTable>();
      var notifications = 0;
      var reads = 0;
      final source = ChartSource(
        viewId: 'chart',
        loadTable: (_) {
          reads++;
          return result.future;
        },
      )..addListener(() => notifications++);
      final loaded = source.load();
      expect(notifications, 1);
      source.dispose();
      result.complete(_table);
      await loaded;
      await source.load();
      source.invalidate();
      expect(reads, 1);
      expect(notifications, 1);
      expect(source.table, same(ChartTable.empty));
    });

    test(
        'rapid settings writes stay ordered and merge fresh unrelated metadata',
        () async {
      var extra = '{"unrelated":{"keep":true}}';
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final saved = <String>[];
      final readViews = <String>[];
      final writeViews = <String>[];
      var reads = 0;
      final writer = ChartSettingsWriter(
        viewId: 'chart',
        readExtra: (id) async {
          readViews.add(id);
          reads++;
          return extra;
        },
        writeExtra: (id, next) async {
          writeViews.add(id);
          saved.add(next);
          if (saved.length == 1) {
            firstStarted.complete();
            await releaseFirst.future;
            // Another setting changes before the second queued write reads.
            extra = jsonEncode(
              {...jsonDecode(next) as Map<String, dynamic>, 'fresh': true},
            );
          } else {
            extra = next;
          }
        },
      );
      final first = writer.write(
        const ChartMetadata(spec: ChartSpec(categoryColumn: 'team-id')),
      );
      await firstStarted.future;
      final last = writer.write(
        const ChartMetadata(spec: ChartSpec(categoryColumn: 'status-id')),
      );
      expect(writer.isWriting, isTrue);
      expect(saved, hasLength(1));
      releaseFirst.complete();
      await first;
      await last;
      expect(writer.isWriting, isFalse);
      expect(reads, 2);
      expect(readViews, ['chart', 'chart']);
      expect(writeViews, ['chart', 'chart']);
      expect(
        ChartMetadata.fromExtra(saved.first)!.spec.categoryColumn,
        'team-id',
      );
      expect(ChartMetadata.fromExtra(extra)!.spec.categoryColumn, 'status-id');
      expect((jsonDecode(extra) as Map)['unrelated'], {'keep': true});
      expect((jsonDecode(extra) as Map)['fresh'], isTrue);
    });

    test('a failed settings write does not poison later choices', () async {
      var attempts = 0;
      String? saved;
      final writer = ChartSettingsWriter(
        viewId: 'chart',
        readExtra: (_) async => '',
        writeExtra: (_, extra) async {
          if (++attempts == 1) throw StateError('synthetic write failure');
          saved = extra;
        },
      );
      await writer.write(
        const ChartMetadata(spec: ChartSpec(categoryColumn: 'team-id')),
      );
      expect(writer.error, isNotNull);
      expect(writer.isWriting, isFalse);
      await writer.write(
        const ChartMetadata(spec: ChartSpec(categoryColumn: 'status-id')),
      );
      expect(writer.error, isNull);
      expect(ChartMetadata.fromExtra(saved!)!.spec.categoryColumn, 'status-id');
    });
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance: Group by reselects, refreshes and survives reopening',
        (tester) async {
      var table = _table;
      var reads = 0;
      var extra = '{"unrelated":{"keep":true}}';
      final source = ChartSource(
        viewId: 'chart',
        loadTable: (_) async {
          reads++;
          return table;
        },
      );
      try {
        await _pumpChart(
          tester,
          appearance: appearance,
          source: source,
          spec: const ChartSpec(
            categoryColumn: 'team-id',
            valueColumns: ['amount-id'],
            showControls: true,
          ),
          onChanged: (spec) =>
              extra = ChartMetadata(spec: spec).mergeIntoExtra(extra),
        );
        expect(_chart(tester).data.categories, ['North', 'South', '—']);
        expect(_values(_chart(tester).data), [8, 10, 0]);
        await _choose(tester, 'chart-horizontal-column', 'Status');
        expect(_chart(tester).data.categories, ['Open', 'Closed']);
        expect(_values(_chart(tester).data), [12, 6]);
        expect(_painter(tester).data.categories, ['Open', 'Closed']);
        expect(
          tester
              .widget<ChartToolbar>(find.byType(ChartToolbar))
              .spec
              .categoryColumn,
          'status-id',
        );
        expect(
          ChartMetadata.fromExtra(extra)!.spec.categoryColumn,
          'status-id',
        );
        await _choose(tester, 'chart-horizontal-column', 'Team');
        expect(_values(_chart(tester).data), [8, 10, 0]);
        await _choose(tester, 'chart-horizontal-column', 'Status');
        expect(
          reads,
          1,
          reason: 'Grouping is a projection, not another backend read',
        );

        table = ChartTable(
          columns: _table.columns,
          columnIds: _table.columnIds,
          rows: [
            ..._table.rows,
            ['New', 'West', 'Closed', '4', '4', '40', 'Sep 20, 2026'],
          ],
        );
        await tester.tap(find.byTooltip(LocaleKeys.charts_refresh.tr()));
        await tester.pumpAndSettle();
        expect(reads, 2);
        expect(_values(_chart(tester).data), [12, 10]);
        expect(
          _chart(tester).spec.categoryColumn,
          'Status',
          reason: 'Display labels are not field ids',
        );
        if (appearance == 'paper') {
          expect(
            PaperTheme.isEnabled(tester.element(find.byType(ChartStage))),
            isTrue,
          );
          expect(_chart(tester).palette.background, isNot(Colors.white));
          expect(
            _chart(tester).palette.background,
            chartPaletteOf(tester.element(find.byType(ChartStage))).background,
          );
        }

        await tester.pumpWidget(const SizedBox());
        await _pumpChart(
          tester,
          appearance: appearance,
          source: source,
          spec: ChartMetadata.fromExtra(extra)!.spec,
        );
        expect(_chart(tester).data.categories, ['Open', 'Closed']);
        expect(_values(_chart(tester).data), [12, 10]);
        expect((jsonDecode(extra) as Map)['unrelated'], {'keep': true});
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        source.dispose();
      }
    });

    testWidgets('$appearance: Count rows and Every row are not guessed away',
        (tester) async {
      final source =
          ChartSource(viewId: 'chart', loadTable: (_) async => _table);
      ChartSpec? saved;
      try {
        await _pumpChart(
          tester,
          appearance: appearance,
          source: source,
          spec: const ChartSpec(
            categoryColumn: 'team-id',
            valueColumns: ['amount-id'],
            aggregate: ChartAggregate.average,
            showControls: true,
          ),
          onChanged: (spec) => saved = ChartSpec.fromJson(spec.toJson()),
        );
        await _choose(
          tester,
          'chart-value-columns',
          LocaleKeys.charts_countRows.tr(),
        );
        expect(saved!.valueColumns, isEmpty);
        expect(_values(_chart(tester).data), [2, 1, 1]);
        await _choose(
          tester,
          'chart-horizontal-column',
          LocaleKeys.charts_everyRow.tr(),
        );
        expect(saved!.categoryColumn, isNull);
        expect(
          _chart(tester).data.categories,
          ['Same', 'Same', 'Third', 'Missing'],
        );
        expect(_values(_chart(tester).data), [1, 1, 1, 1]);
        await tester.pumpWidget(const SizedBox());
        await _pumpChart(
          tester,
          appearance: appearance,
          source: source,
          spec: saved!,
        );
        expect(_values(_chart(tester).data), [1, 1, 1, 1]);
        expect(_chart(tester).spec.categoryColumn, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        source.dispose();
      }
    });
  }

  for (final type in [ChartType.line, ChartType.area]) {
    testWidgets('${type.name}: Group by switches from numeric X to categories',
        (tester) async {
      final source =
          ChartSource(viewId: 'chart', loadTable: (_) async => _table);
      try {
        await _pumpChart(
          tester,
          source: source,
          spec: ChartSpec(
            type: type,
            xColumn: 'rank-id',
            valueColumns: const ['amount-id'],
            showControls: true,
          ),
        );
        expect(_chart(tester).data.measuresX, isTrue);
        await _choose(tester, 'chart-horizontal-column', 'Status');
        expect(_chart(tester).data.measuresX, isFalse);
        expect(_chart(tester).spec.xColumn, isNull);
        expect(_chart(tester).data.categories, ['Open', 'Closed']);
        expect(_values(_chart(tester).data), [12, 6]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        source.dispose();
      }
    });
  }

  for (final type in [ChartType.scatter, ChartType.bubble]) {
    testWidgets(
        '${type.name}: point labels are selectable without fake grouping controls',
        (tester) async {
      final source =
          ChartSource(viewId: 'chart', loadTable: (_) async => _table);
      try {
        await _pumpChart(
          tester,
          source: source,
          spec: ChartSpec(
            type: type,
            xColumn: 'rank-id',
            valueColumns: const ['amount-id'],
            sizeColumn: 'size-id',
            showControls: true,
          ),
        );
        expect(
          find.byKey(const ValueKey('chart-label-column')),
          findsOneWidget,
        );
        await _choose(tester, 'chart-label-column', 'Team');
        expect(
          _chart(tester).data.series.single.points.map((point) => point.label),
          ['North', 'North', 'South'],
        );
        await _choose(tester, 'chart-label-column', 'Status');
        expect(_values(_chart(tester).data), [2, 6, 10]);
        expect(
          _chart(tester).data.series.single.points.map((point) => point.label),
          ['Open', 'Closed', 'Open'],
        );
        expect(_chart(tester).spec.xColumn, 'Rank');
        await tester.tap(find.byKey(const ValueKey('chart-horizontal-column')));
        await tester.pumpAndSettle();
        expect(find.text(LocaleKeys.charts_groupBy.tr()), findsNothing);
        await tester.tapAt(const Offset(1180, 700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        source.dispose();
      }
    });
  }

  testWidgets(
      'a new grouping resets old zoom, hit testing and hidden-series indices',
      (tester) async {
    final source = ChartSource(viewId: 'chart', loadTable: (_) async => _table);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    try {
      await _pumpChart(
        tester,
        source: source,
        spec: const ChartSpec(
          categoryColumn: 'team-id',
          valueColumns: ['amount-id', 'rank-id'],
          showControls: true,
        ),
      );
      await tester.tap(find.text('Amount'));
      await tester.pumpAndSettle();
      expect(_painter(tester).hidden, {0});
      await _zoomIn(tester, mouse);
      expect(_painter(tester).viewport.isIdentity, isFalse);
      await _hoverPoint(tester, mouse, 1);
      expect(_tooltipLabel(tester), 'South');
      await _choose(tester, 'chart-horizontal-column', 'Status');
      expect(_painter(tester).viewport.isIdentity, isTrue);
      expect(_painter(tester).hidden, isEmpty);
      expect(_painter(tester).data.categories, ['Open', 'Closed']);
      expect(
        _painter(tester).hits.map((hit) => hit.seriesIndex).toSet(),
        {0, 1},
      );
      expect(
        _painter(tester).hits.map((hit) => hit.pointIndex).toSet(),
        {0, 1},
      );
      await _hoverPoint(tester, mouse, 1);
      expect(_tooltipLabel(tester), 'Closed');
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    }
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets('$appearance: live row reloads preserve zoom and hidden series',
        (tester) async {
      var table = _table;
      final source = ChartSource(
        viewId: 'chart',
        loadTable: (_) async => table,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      try {
        await _pumpChart(
          tester,
          appearance: appearance,
          source: source,
          spec: const ChartSpec(
            categoryColumn: 'team-id',
            valueColumns: ['amount-id', 'rank-id'],
            showControls: true,
          ),
        );
        await tester.tap(find.text('Amount'));
        await tester.pumpAndSettle();
        await _zoomIn(tester, mouse);
        final viewport = _painter(tester).viewport;
        await _hoverPoint(tester, mouse, 1);

        // Exercise the same debounced path as a database notification, with
        // both a new bucket and a row whose existing bucket's value changes.
        table = ChartTable(
          columns: _table.columns,
          columnIds: _table.columnIds,
          rows: [
            ..._table.rows,
            ['New', 'West', 'Closed', '4', '4', '40', 'Sep 20, 2026'],
            ['Edit', 'North', 'Open', '3', '2', '20', 'Sep 20, 2026'],
          ],
        );
        source.invalidate();
        await tester.pump(source.settle);
        await tester.pumpAndSettle();
        expect(_chart(tester).data.categories, ['North', 'South', '—', 'West']);
        expect(_values(_chart(tester).data), [11, 10, 0, 4]);
        expect(_painter(tester).viewport, viewport);
        expect(_painter(tester).hidden, {0});
        expect(_painter(tester).highlight, isNull);
        expect(_painter(tester).crosshair, isNull);
        expect(find.byType(ChartTooltip), findsNothing);

        table = ChartTable(
          columns: _table.columns,
          columnIds: _table.columnIds,
          rows: [_table.rows[1], _table.rows[0]],
        );
        await source.load();
        await tester.pumpAndSettle();
        expect(_chart(tester).data.categories, ['South', 'North']);
        expect(_painter(tester).viewport, viewport);
        expect(_painter(tester).hidden, {0});
        await _hoverPoint(tester, mouse, 1);
        expect(_tooltipLabel(tester), 'North');
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        source.dispose();
      }
    });
  }

  testWidgets('field renames and display options preserve chart interactions',
      (tester) async {
    var table = _table;
    const spec = ChartSpec(
      categoryColumn: 'team-id',
      valueColumns: ['amount-id', 'rank-id'],
      showControls: true,
    );
    final source = ChartSource(viewId: 'chart', loadTable: (_) async => table);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    try {
      final changeSpec = await _pumpChart(tester, source: source, spec: spec);
      await tester.tap(find.text('Amount'));
      await tester.pumpAndSettle();
      await _zoomIn(tester, mouse);
      final viewport = _painter(tester).viewport;
      table = ChartTable(
        columns: [
          'Title',
          'Division',
          'Status',
          'Budget',
          'Rank',
          'Size',
          'Date',
        ],
        columnIds: _table.columnIds,
        rows: _table.rows,
      );
      await source.load();
      await tester.pumpAndSettle();
      expect(_chart(tester).spec.categoryColumn, 'Division');
      expect(_chart(tester).data.series.first.name, 'Budget');
      expect(_painter(tester).viewport, viewport);
      expect(_painter(tester).hidden, {0});

      changeSpec(
        spec.copyWith(
          showGrid: false,
          showValues: true,
          palette: ChartPaletteName.ocean,
        ),
      );
      await tester.pumpAndSettle();
      expect(_painter(tester).viewport, viewport);
      expect(_painter(tester).hidden, {0});
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    }
  });

  const interactionSpec = ChartSpec(
    categoryColumn: 'team-id',
    valueColumns: ['amount-id', 'rank-id'],
    showControls: true,
  );
  final changedReadings = {
    'grouping field with identical buckets':
        interactionSpec.copyWith(categoryColumn: 'status-id'),
    'aggregation': interactionSpec.copyWith(aggregate: ChartAggregate.average),
    'sort configuration':
        interactionSpec.copyWith(sort: ChartSort.labelAscending),
    'category limit': interactionSpec.copyWith(categoryLimit: 2),
    'series order':
        interactionSpec.copyWith(valueColumns: ['rank-id', 'amount-id']),
  };
  for (final entry in changedReadings.entries) {
    testWidgets('${entry.key} clears old viewport, hover and hidden indices',
        (tester) async {
      final table = ChartTable(
        columns: _table.columns,
        columnIds: _table.columnIds,
        rows: [
          // Both grouping fields deliberately produce the SAME categories.
          for (final row in _table.rows)
            [row[0], row[1], row[1], ...row.skip(3)],
        ],
      );
      final source =
          ChartSource(viewId: 'chart', loadTable: (_) async => table);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      try {
        final changeSpec = await _pumpChart(
          tester,
          source: source,
          spec: interactionSpec,
        );
        await tester.tap(find.text('Amount'));
        await tester.pumpAndSettle();
        await _zoomIn(tester, mouse);
        await _hoverPoint(tester, mouse, 1);
        expect(_painter(tester).hidden, {0});
        expect(find.byType(ChartTooltip), findsOneWidget);

        // No pointer movement or menu dismissal clears the old hover for us.
        changeSpec(entry.value);
        await tester.pump();
        expect(_painter(tester).viewport.isIdentity, isTrue);
        expect(_painter(tester).hidden, isEmpty);
        expect(_painter(tester).focusedSeries, isNull);
        expect(_painter(tester).highlight, isNull);
        expect(_painter(tester).crosshair, isNull);
        expect(find.byType(ChartTooltip), findsNothing);
        await tester.pumpAndSettle();
        await _hoverPoint(tester, mouse, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        source.dispose();
      }
    });
  }

  testWidgets('removing a plotted field cannot hide its replacement series',
      (tester) async {
    var table = _table;
    final source = ChartSource(viewId: 'chart', loadTable: (_) async => table);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    try {
      await _pumpChart(tester, source: source, spec: interactionSpec);
      await tester.tap(find.text('Amount'));
      await tester.pumpAndSettle();
      await _zoomIn(tester, mouse);
      table = ChartTable(
        columns: [
          for (var i = 0; i < _table.columns.length; i++)
            if (i != 3) _table.columns[i],
        ],
        columnIds: [
          for (var i = 0; i < _table.columnIds.length; i++)
            if (i != 3) _table.columnIds[i],
        ],
        rows: [
          for (final row in _table.rows)
            [
              for (var i = 0; i < row.length; i++)
                if (i != 3) row[i],
            ],
        ],
      );
      await source.load();
      await tester.pumpAndSettle();
      expect(_chart(tester).data.series.single.name, 'Rank');
      expect(_painter(tester).hidden, isEmpty);
      expect(_painter(tester).viewport.isIdentity, isTrue);
      expect(_painter(tester).hits, isNotEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    }
  });

  testWidgets(
      'a replacement source resets interactions and detaches the old one',
      (tester) async {
    final first = ChartSource(viewId: 'first', loadTable: (_) async => _table);
    final second =
        ChartSource(viewId: 'second', loadTable: (_) async => _table);
    final selected = ValueNotifier(first);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    try {
      // A preloaded borrowed source does not pass through an empty skeleton
      // that would incidentally dispose AppChart and conceal a missing reset.
      await first.load();
      await second.load();
      await tester.pumpWidget(
        _app(
          'light',
          ValueListenableBuilder<ChartSource>(
            valueListenable: selected,
            builder: (context, source, _) => ChartStage(
              viewId: source.viewId,
              source: source,
              spec: interactionSpec.copyWith(showControls: false),
              onSpecChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amount'));
      await tester.pumpAndSettle();
      await _zoomIn(tester, mouse);
      selected.value = second;
      await tester.pumpAndSettle();
      expect(_painter(tester).viewport.isIdentity, isTrue);
      expect(_painter(tester).hidden, isEmpty);
      final chart = _chart(tester);
      await first.load();
      await tester.pumpAndSettle();
      expect(_chart(tester), same(chart));
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      selected.dispose();
      first.dispose();
      second.dispose();
    }
  });
}

List<double> _values(ChartData data) =>
    data.series.first.points.map((point) => point.value).toList();

AppChart _chart(WidgetTester tester) =>
    tester.widget<AppChart>(find.byType(AppChart));

Finder get _chartPlot => find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is ChartPainter,
    );

ChartPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_chartPlot).painter! as ChartPainter;

Future<void> _zoomIn(WidgetTester tester, TestGesture mouse) async {
  await mouse.moveTo(tester.getCenter(_chartPlot));
  await tester.pumpAndSettle();
  final button = find.descendant(
    of: find.byType(AppChart),
    matching: find.byIcon(Icons.add_rounded),
  );
  expect(button.hitTestable(), findsOneWidget);
  final position = tester.getCenter(button);
  await mouse.moveTo(position);
  await tester.pumpAndSettle();
  await mouse.down(position);
  await mouse.up();
  // The plot's double-tap recognizer holds this single tap in the arena.
  // pumpAndSettle alone need not advance a timer that schedules no frames.
  await tester.pump(kDoubleTapTimeout);
  await tester.pumpAndSettle();
  expect(_painter(tester).viewport.scale, closeTo(1.4, 0.0001));
}

Future<void> _hoverPoint(
  WidgetTester tester,
  TestGesture mouse,
  int pointIndex,
) async {
  final hit = _painter(tester).hits.lastWhere(
        (hit) => hit.pointIndex == pointIndex,
      );
  await mouse.moveTo(tester.getTopLeft(_chartPlot) + hit.rect.center);
  await tester.pumpAndSettle();
  expect(_painter(tester).highlight?.pointIndex, pointIndex);
}

String _tooltipLabel(WidgetTester tester) {
  final tooltip = tester.widget<ChartTooltip>(find.byType(ChartTooltip));
  return tooltip.data.series[tooltip.hit.seriesIndex]
      .points[tooltip.hit.pointIndex].label;
}

Future<void> _choose(WidgetTester tester, String control, String label) async {
  await tester.tap(find.byKey(ValueKey(control)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<ValueChanged<ChartSpec>> _pumpChart(
  WidgetTester tester, {
  required ChartSource source,
  required ChartSpec spec,
  String appearance = 'light',
  ValueChanged<ChartSpec>? onChanged,
}) async {
  tester.view.physicalSize = const Size(1200, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var selected = spec;
  late StateSetter setHostState;
  void changeSpec(ChartSpec next) {
    setHostState(() => selected = next);
    onChanged?.call(next);
  }

  await tester.pumpWidget(
    _app(
      appearance,
      StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return ChartStage(
            viewId: source.viewId,
            source: source,
            spec: selected,
            onSpecChanged: changeSpec,
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return changeSpec;
}

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      '',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Widget _app(String appearance, Widget child) => EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: _theme(appearance),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: child),
        ),
      ),
    );
