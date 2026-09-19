import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/charts/chart_settings.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-notification/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewId = 'requested-chart-view';
const _table = ChartTable(
  columns: ['Team', 'Amount'],
  columnIds: ['team', 'amount'],
  rows: [
    ['North', '2'],
    ['South', '6'],
  ],
);
const _team = ChartMetadata(spec: ChartSpec(categoryColumn: 'team'));
const _status = ChartMetadata(spec: ChartSpec(categoryColumn: 'status'));

void main() {
  group('chart source initialization', () {
    test('subscribes first and awaits the requested view before reading',
        () async {
      final changes = StreamController<SubscribeObject>.broadcast(sync: true);
      final initialized = Completer<void>();
      final calls = <String>[];
      final source = ChartSource(
        viewId: _viewId,
        notifications: changes.stream,
        initializeView: (id) {
          expect(changes.hasListener, isTrue);
          calls.add('initialize:$id');
          return initialized.future;
        },
        loadTable: (id) async {
          calls.add('read:$id');
          return _table;
        },
      );
      try {
        final loaded = source.load();
        expect(calls, ['initialize:$_viewId']);
        expect(source.isLoading, isTrue);
        initialized.complete();
        await loaded;
        expect(calls, ['initialize:$_viewId', 'read:$_viewId']);
        expect(source.table, same(_table));
        expect(source.isLoading, isFalse);
      } finally {
        source.dispose();
        await changes.close();
      }
    });

    test('every refresh re-ensures an editor that another host may have closed',
        () async {
      var active = false;
      final calls = <String>[];
      final source = ChartSource(
        viewId: _viewId,
        initializeView: (id) async {
          calls.add('initialize:$id');
          active = true;
        },
        loadTable: (id) async {
          expect(active, isTrue);
          calls.add('read:$id');
          return _table;
        },
      );
      await source.load();
      active =
          false; // Only fake backend state, never a live application editor.
      await source.load();
      source.dispose();
      expect(active, isTrue, reason: 'The chart does not own a close lease');
      expect(calls, [
        'initialize:$_viewId',
        'read:$_viewId',
        'initialize:$_viewId',
        'read:$_viewId',
      ]);
    });

    test('an initialization failure stops reads and a later refresh retries',
        () async {
      var fail = false;
      var initializes = 0;
      var reads = 0;
      final source = ChartSource(
        viewId: _viewId,
        initializeView: (_) async {
          initializes++;
          if (fail) throw StateError('synthetic initialization failure');
        },
        loadTable: (_) async {
          reads++;
          return reads == 1 ? _table : ChartTable.empty;
        },
      );
      addTearDown(source.dispose);
      await source.load();
      fail = true;
      await source.load();
      expect(reads, 1);
      expect(source.table, same(_table));
      expect(source.error, contains('initialization failure'));
      expect(source.isLoading, isFalse);
      fail = false;
      await source.load();
      expect(initializes, 3);
      expect(reads, 2);
      expect(source.table, same(ChartTable.empty));
      expect(source.error, isNull);
    });

    test('empty ids and a disposed source do not initialize or read', () async {
      var calls = 0;
      ChartSource makeSource(String id) => ChartSource(
            viewId: id,
            initializeView: (_) async => calls++,
            loadTable: (_) async {
              calls++;
              return _table;
            },
          );
      final empty = makeSource('');
      await empty.load();
      empty.invalidate();
      empty.dispose();
      final disposed = makeSource(_viewId)..dispose();
      await disposed.load();
      disposed.invalidate();
      expect(calls, 0);
    });

    for (final fail in [false, true]) {
      test(
          'disposal during initialization ignores its late ${fail ? 'error' : 'success'}',
          () async {
        final initialized = Completer<void>();
        final changes = StreamController<SubscribeObject>.broadcast(sync: true);
        var reads = 0;
        var notifications = 0;
        final source = ChartSource(
          viewId: _viewId,
          notifications: changes.stream,
          initializeView: (_) => initialized.future,
          loadTable: (_) async {
            reads++;
            return _table;
          },
        )..addListener(() => notifications++);
        final loaded = source.load();
        expect(source.load(), same(loaded));
        source.invalidate();
        source.dispose();
        expect(changes.hasListener, isFalse);
        if (fail) {
          initialized.completeError(StateError('late initialization error'));
        } else {
          initialized.complete();
        }
        await loaded;
        await source.load();
        expect(reads, 0);
        expect(notifications, 1);
        expect(source.table, same(ChartTable.empty));
        expect(source.error, isNull);
        expect(source.isLoading, isFalse);
        await changes.close();
      });

      test(
          'disposal during a read ignores its late ${fail ? 'error' : 'success'}',
          () async {
        final result = Completer<ChartTable>();
        final readStarted = Completer<void>();
        var initializes = 0;
        var notifications = 0;
        final source = ChartSource(
          viewId: _viewId,
          initializeView: (_) async => initializes++,
          loadTable: (_) {
            readStarted.complete();
            return result.future;
          },
        )..addListener(() => notifications++);
        final loaded = source.load();
        await readStarted.future;
        expect(source.load(), same(loaded));
        source.dispose();
        if (fail) {
          result.completeError(StateError('late read error'));
        } else {
          result.complete(_table);
        }
        await loaded;
        expect(initializes, 1);
        expect(notifications, 1);
        expect(source.table, same(ChartTable.empty));
        expect(source.error, isNull);
      });
    }

    test('queued refreshes re-initialize once before the follow-up read',
        () async {
      final first = Completer<ChartTable>();
      final firstStarted = Completer<void>();
      final calls = <String>[];
      var reads = 0;
      final source = ChartSource(
        viewId: _viewId,
        initializeView: (id) async => calls.add('initialize:$id'),
        loadTable: (id) {
          calls.add('read:$id');
          if (++reads == 1) {
            firstStarted.complete();
            return first.future;
          }
          return Future.value(ChartTable.empty);
        },
      );
      addTearDown(source.dispose);
      final loaded = source.load();
      await firstStarted.future;
      expect(source.load(), same(loaded));
      expect(source.load(), same(loaded));
      first.complete(_table);
      await loaded;
      expect(calls, [
        'initialize:$_viewId',
        'read:$_viewId',
        'initialize:$_viewId',
        'read:$_viewId',
      ]);
      expect(source.table, same(ChartTable.empty));
    });

    testWidgets('an event during initialization is not lost', (tester) async {
      final changes = StreamController<SubscribeObject>.broadcast(sync: true);
      final initialized = Completer<void>();
      var initializes = 0;
      var reads = 0;
      final source = ChartSource(
        viewId: _viewId,
        notifications: changes.stream,
        initializeView: (_) {
          initializes++;
          return initializes == 1 ? initialized.future : Future.value();
        },
        loadTable: (_) async {
          reads++;
          return _table;
        },
      );
      try {
        final loaded = source.load();
        changes.add(_event(DatabaseNotification.DidUpdateRow));
        await tester.pump(source.settle);
        initialized.complete();
        await loaded;
        expect(initializes, 2);
        expect(reads, 2);
      } finally {
        source.dispose();
        if (!initialized.isCompleted) initialized.complete();
        await changes.close();
      }
    });
  });

  group('chart bulk view reads', () {
    test(
        'loads cells before membership and matches row and field ids, not positions',
        () async {
      final calls = <String>[];
      final table = await readChartTable(
        _viewId,
        readRows: (id) async {
          calls.add('text:$id');
          return RepeatedRowTextPB(
            fieldIds: ['amount', 'team'],
            rows: [
              RowTextPB(rowId: 'excluded', cells: ['1000', 'Wrong view']),
              RowTextPB(rowId: 'north', cells: ['2', 'North']),
              RowTextPB(rowId: 'south', cells: ['6', 'South']),
              RowTextPB(rowId: 'blank'),
            ],
          );
        },
        readViewRows: (id) async {
          calls.add('membership:$id');
          return [
            RowMetaPB(id: 'south'),
            RowMetaPB(id: 'north'),
            RowMetaPB(id: 'blank'),
          ];
        },
        readFields: (id, ids) async {
          calls.add('fields:$id');
          expect(ids, ['amount', 'team']);
          return [
            FieldPB(id: 'team', name: 'Team'),
            FieldPB(id: 'amount', name: 'Amount'),
          ];
        },
      );
      expect(calls, [
        'text:$_viewId',
        'membership:$_viewId',
        'fields:$_viewId',
      ]);
      expect(table.columnKeys, ['amount', 'team']);
      expect(table.columns, ['Amount', 'Team']);
      expect(table.rows, [
        ['6', 'South'],
        ['2', 'North'],
        <String>[],
      ]);
      final counted = buildChartData(
        table,
        const ChartSpec(categoryColumn: 'team'),
      );
      expect(counted.categories, ['South', 'North', '—']);
      expect(_values(counted), [1, 1, 1]);
    });

    test('an empty or fully filtered view never adopts the text fallback rows',
        () async {
      final table = await readChartTable(
        _viewId,
        readRows: (_) async => RepeatedRowTextPB(
          fieldIds: ['team'],
          rows: [
            RowTextPB(rowId: 'fallback', cells: ['Other view']),
          ],
        ),
        readViewRows: (_) async => [],
        readFields: (_, ids) async => [FieldPB(id: 'team', name: 'Team')],
      );
      expect(table.columns, ['Team']);
      expect(table.rows, isEmpty);
      expect(buildChartData(table, const ChartSpec()).isEmpty, isTrue);
    });

    for (final failedPhase in ['text', 'membership', 'fields']) {
      test('$failedPhase failure stops subsequent bulk requests', () async {
        final calls = <String>[];
        void phase(String name) {
          calls.add(name);
          if (name == failedPhase) throw StateError('synthetic $name failure');
        }

        await expectLater(
          readChartTable(
            _viewId,
            readRows: (_) async {
              phase('text');
              return RepeatedRowTextPB();
            },
            readViewRows: (_) async {
              phase('membership');
              return [];
            },
            readFields: (_, ids) async {
              phase('fields');
              return [];
            },
          ),
          throwsStateError,
        );
        expect(calls.last, failedPhase);
        expect(
          calls.length,
          ['text', 'membership', 'fields'].indexOf(failedPhase) + 1,
        );
      });
    }

    test(
        'production initialization is view-scoped and never closes a shared editor',
        () {
      final source = File(
        'lib/workspace/application/charts/chart_source.dart',
      ).readAsStringSync();
      final initializer = source.substring(
        source.indexOf('Future<void> _initializeChartView('),
        source.indexOf('/// Bulk reads only'),
      );
      expect(initializer, contains('await _readViewRows(viewId)'));
      expect(
        source,
        contains('DatabaseEventGetAllRows(DatabaseViewIdPB(value: viewId))'),
      );
      expect(source, isNot(contains('DatabaseEventGetDatabase(')));
      expect(source, isNot(contains('DatabaseEventExportCSV(')));
      expect(source, isNot(contains('DatabaseEventGetCell(')));
      expect(source, isNot(contains('FolderEventCloseView(')));
      expect(source, isNot(contains('DatabaseController(')));
    });
  });

  group('chart notification lifecycle', () {
    testWidgets(
        'insert and delete notifications refresh counts and grouped values',
        (tester) async {
      final backend = _ChartBackend();
      final source = backend.source();
      try {
        await source.load();
        expect(backend.activeViews, contains(_viewId));
        expect(_counts(source), [2, 1, 1]);
        expect(_sums(source), [8, 10, 0]);

        backend.rows
            .add(RowTextPB(rowId: 'new', cells: ['4', 'South', 'Open']));
        backend.rowIds.add('new');
        backend.notify(DatabaseNotification.DidUpdateRow);
        await tester.pump(source.settle);
        expect(_counts(source), [2, 2, 1]);
        expect(_sums(source), [8, 14, 0]);

        backend.rows.removeWhere((row) => row.rowId.startsWith('north'));
        backend.rowIds.removeWhere((id) => id.startsWith('north'));
        backend.notify(DatabaseNotification.DidUpdateRow);
        await tester.pump(source.settle);
        expect(_counts(source), [2, 1]);
        expect(_sums(source), [14, 0]);

        backend.rows.clear();
        backend.rowIds.clear();
        backend.notify(DatabaseNotification.DidUpdateRow);
        await tester.pump(source.settle);
        expect(source.table.rows, isEmpty);
        expect(backend.initializes, 4);
      } finally {
        source.dispose();
        await backend.changes.close();
      }
      expect(backend.activeViews, contains(_viewId));
      expect(backend.changes.hasListener, isFalse);
    });

    testWidgets('view id, notification source and type are all matched',
        (tester) async {
      final backend = _ChartBackend();
      final source = backend.source();
      await source.load();
      backend.changes
          .add(_event(DatabaseNotification.DidUpdateRow, id: 'other-view'));
      backend.changes
          .add(_event(DatabaseNotification.DidUpdateFields, source: 'Folder'));
      backend.changes.add(_event(DatabaseNotification.DidGroupByField));
      await tester.pump(source.settle);
      expect(backend.initializes, 1);

      backend.notify(DatabaseNotification.DidUpdateRow);
      backend.notify(DatabaseNotification.DidUpdateFields);
      await tester.pump(source.settle - const Duration(milliseconds: 1));
      expect(backend.initializes, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(backend.initializes, 2);
      backend.notify(DatabaseNotification.DidUpdateRow);
      source.dispose();
      backend.notify(DatabaseNotification.DidUpdateRow);
      await tester.pump(const Duration(seconds: 1));
      expect(backend.initializes, 2);
      await backend.changes.close();
    });

    for (final type in [
      DatabaseNotification.DidUpdateFilter,
      DatabaseNotification.DidUpdateViewRowsVisibility,
      DatabaseNotification.DidUpdateSort,
      DatabaseNotification.DidReorderRows,
      DatabaseNotification.DidReorderSingleRow,
    ]) {
      testWidgets(
          '${type.name} refreshes membership without changing chart grouping',
          (tester) async {
        final backend = _ChartBackend();
        final source = backend.source();
        try {
          await source.load();
          backend.rowIds
            ..clear()
            ..addAll(['south', 'north-b']);
          backend.notify(type);
          await tester.pump(source.settle);
          expect(source.table.rows, [
            ['10', 'South', 'Open'],
            ['6', 'North', 'Closed'],
          ]);
          final data = buildChartData(
            source.table,
            const ChartSpec(categoryColumn: 'team', valueColumns: ['amount']),
          );
          expect(data.categories, ['South', 'North']);
          expect(_values(data), [10, 6]);
          expect(backend.initializes, 2);
          // Non-notifying reads must settle instead of scheduling themselves.
          await tester.pump(const Duration(seconds: 2));
          expect(backend.initializes, 2);
        } finally {
          source.dispose();
          await backend.changes.close();
        }
      });
    }
  });

  group('authoritative chart settings adoption', () {
    test(
        'an echo after the queue drains cannot restore an earlier local choice',
        () async {
      var extra = '{"unrelated":{"keep":true}}';
      final adopted = <ChartMetadata>[];
      final reads = <String>[];
      final writes = <String>[];
      final writer = ChartSettingsWriter(
        viewId: _viewId,
        readExtra: (id) async {
          reads.add(id);
          return extra;
        },
        writeExtra: (id, value) async {
          writes.add(id);
          extra = value;
        },
        onAdopt: adopted.add,
      );
      addTearDown(writer.dispose);
      await writer.write(_team);
      await writer.write(_status);
      expect(writer.isWriting, isFalse);
      adopted.clear();

      // The host receives the old Team extra, but treats it as an invalidation.
      await writer.reconcile();
      expect(adopted.single.spec.categoryColumn, 'status');
      expect(reads, everyElement(_viewId));
      expect(writes, [_viewId, _viewId]);
      expect((jsonDecode(extra) as Map)['unrelated'], {'keep': true});

      // A real remote edit is allowed to choose that SAME old value later.
      extra = _team.mergeIntoExtra(extra);
      await writer.reconcile();
      expect(adopted.last.spec.categoryColumn, 'team');
      expect(writes, hasLength(2), reason: 'Reconciliation never writes back');
    });

    test('a notification while saving waits for all queued local choices',
        () async {
      var extra = '';
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final adopted = <ChartMetadata>[];
      var writes = 0;
      final writer = ChartSettingsWriter(
        viewId: _viewId,
        readExtra: (_) async => extra,
        writeExtra: (_, value) async {
          if (++writes == 1) {
            firstStarted.complete();
            await releaseFirst.future;
          }
          extra = value;
        },
        onAdopt: adopted.add,
      );
      addTearDown(writer.dispose);
      final first = writer.write(_team);
      await firstStarted.future;
      final notification = writer.reconcile();
      final last = writer.write(_status);
      expect(adopted, isEmpty);
      releaseFirst.complete();
      await Future.wait([first, notification, last]);
      expect(writer.isWriting, isFalse);
      expect(adopted, isNotEmpty);
      expect(
        adopted.map((value) => value.spec.categoryColumn),
        everyElement('status'),
      );
    });

    test('a newer notification supersedes a slower authoritative read',
        () async {
      final first = Completer<String>();
      final firstStarted = Completer<void>();
      var reads = 0;
      final adopted = <ChartMetadata>[];
      final writer = ChartSettingsWriter(
        viewId: _viewId,
        readExtra: (_) {
          if (++reads == 1) {
            firstStarted.complete();
            return first.future;
          }
          return Future.value(_status.mergeIntoExtra(''));
        },
        onAdopt: adopted.add,
      );
      addTearDown(writer.dispose);
      final older = writer.reconcile();
      await firstStarted.future;
      await writer.reconcile();
      first.complete(_team.mergeIntoExtra(''));
      await older;
      expect(adopted.single.spec.categoryColumn, 'status');
    });

    test('a local write invalidates a read already in flight', () async {
      var extra = _team.mergeIntoExtra('');
      final oldRead = Completer<String>();
      final readStarted = Completer<void>();
      var reads = 0;
      final adopted = <ChartMetadata>[];
      final writer = ChartSettingsWriter(
        viewId: _viewId,
        readExtra: (_) {
          if (++reads == 1) {
            readStarted.complete();
            return oldRead.future;
          }
          return Future.value(extra);
        },
        writeExtra: (_, value) async => extra = value,
        onAdopt: adopted.add,
      );
      addTearDown(writer.dispose);
      final old = writer.reconcile();
      await readStarted.future;
      final saved = writer.write(_status);
      oldRead.complete(extra);
      await Future.wait([old, saved]);
      expect(adopted, isNotEmpty);
      expect(
        adopted.map((value) => value.spec.categoryColumn),
        everyElement('status'),
      );
    });

    test('a failed write adopts storage and a subsequent choice still saves',
        () async {
      var extra = _team.mergeIntoExtra('');
      var fail = true;
      final adopted = <ChartMetadata>[];
      final writer = ChartSettingsWriter(
        viewId: _viewId,
        readExtra: (_) async => extra,
        writeExtra: (_, value) async {
          if (fail) throw StateError('synthetic save failure');
          extra = value;
        },
        onAdopt: adopted.add,
      );
      addTearDown(writer.dispose);
      await writer.write(_status);
      expect(writer.error, isNotNull);
      expect(adopted.single.spec.categoryColumn, 'team');
      fail = false;
      await writer.write(_status);
      expect(writer.error, isNull);
      expect(adopted.last.spec.categoryColumn, 'status');
    });

    test('a failed reconciliation does not adopt an unverified payload',
        () async {
      var fail = true;
      final adopted = <ChartMetadata>[];
      final writer = ChartSettingsWriter(
        viewId: _viewId,
        readExtra: (_) async {
          if (fail) throw StateError('synthetic reconciliation failure');
          return _status.mergeIntoExtra('');
        },
        onAdopt: adopted.add,
      );
      addTearDown(writer.dispose);
      await writer.reconcile();
      expect(adopted, isEmpty);
      fail = false;
      await writer.reconcile();
      expect(adopted.single.spec.categoryColumn, 'status');
    });

    test('disposing cancels read adoption and rejects new writes', () async {
      final read = Completer<String>();
      final started = Completer<void>();
      var writes = 0;
      final adopted = <ChartMetadata>[];
      final writer = ChartSettingsWriter(
        viewId: _viewId,
        readExtra: (_) {
          started.complete();
          return read.future;
        },
        writeExtra: (_, extra) async => writes++,
        onAdopt: adopted.add,
      );
      final reconciled = writer.reconcile();
      await started.future;
      writer.dispose();
      read.complete(_team.mergeIntoExtra(''));
      await reconciled;
      await writer.reconcile();
      await writer.write(_status);
      expect(adopted, isEmpty);
      expect(writes, 0);
    });

    test(
        'accepted edits finish saving after disposal without notifying the host',
        () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var extra = '';
      final adopted = <ChartMetadata>[];
      final writer = ChartSettingsWriter(
        viewId: _viewId,
        readExtra: (_) async => extra,
        writeExtra: (_, value) async {
          started.complete();
          await release.future;
          extra = value;
        },
        onAdopt: adopted.add,
      );
      final saved = writer.write(_status);
      await started.future;
      writer.dispose();
      release.complete();
      await saved;
      expect(ChartMetadata.fromExtra(extra)!.spec.categoryColumn, 'status');
      expect(adopted, isEmpty);
      expect(writer.isWriting, isFalse);
    });

    test('empty view ids do not read, write or adopt settings', () async {
      var calls = 0;
      final writer = ChartSettingsWriter(
        viewId: '',
        readExtra: (_) async {
          calls++;
          return '';
        },
        writeExtra: (_, extra) async => calls++,
        onAdopt: (_) => calls++,
      );
      await writer.write(_team);
      await writer.reconcile();
      writer.dispose();
      expect(calls, 0);
    });

    test('both chart hosts reconcile notifications and dispose their writer',
        () {
      for (final path in [
        'lib/plugins/collection/chart_plugin.dart',
        'lib/plugins/database/tab_bar/desktop/chart_tab_bar_builder.dart',
      ]) {
        final host = File(path).readAsStringSync();
        expect(host, contains('onAdopt:'), reason: path);
        expect(host, contains('_settings.reconcile()'), reason: path);
        expect(host, contains('_settings.dispose()'), reason: path);
        expect(host, isNot(contains('!_settings.isWriting')), reason: path);
      }
    });
  });
}

SubscribeObject _event(
  DatabaseNotification type, {
  String id = _viewId,
  String source = 'Database',
}) =>
    SubscribeObject(id: id, source: source, ty: type.value);

List<double> _values(ChartData data) =>
    data.series.single.points.map((point) => point.value).toList();

List<double> _counts(ChartSource source) => _values(
      buildChartData(source.table, const ChartSpec(categoryColumn: 'team')),
    );

List<double> _sums(ChartSource source) => _values(
      buildChartData(
        source.table,
        const ChartSpec(categoryColumn: 'team', valueColumns: ['amount']),
      ),
    );

/// All initialization, rows, filters and notifications here are in-memory.
class _ChartBackend {
  final changes = StreamController<SubscribeObject>.broadcast(sync: true);
  final activeViews = <String>{};
  final rows = [
    RowTextPB(rowId: 'north-a', cells: ['2', 'North', 'Open']),
    RowTextPB(rowId: 'south', cells: ['10', 'South', 'Open']),
    RowTextPB(rowId: 'north-b', cells: ['6', 'North', 'Closed']),
    RowTextPB(rowId: 'blank'),
  ];
  final rowIds = ['north-a', 'south', 'north-b', 'blank'];
  int initializes = 0;

  ChartSource source() => ChartSource(
        viewId: _viewId,
        notifications: changes.stream,
        initializeView: (id) async {
          expectSync(id, _viewId);
          expectSync(changes.hasListener, isTrue);
          initializes++;
          activeViews.add(id);
        },
        loadTable: (id) => readChartTable(
          id,
          readRows: (id) async {
            expectSync(activeViews, contains(id));
            return RepeatedRowTextPB(
              fieldIds: ['amount', 'team', 'board-group'],
              rows: rows,
            );
          },
          readViewRows: (id) async {
            expectSync(id, _viewId);
            return [for (final id in rowIds) RowMetaPB(id: id)];
          },
          readFields: (id, ids) async {
            expectSync(id, _viewId);
            return [
              FieldPB(id: 'board-group', name: 'Board group'),
              FieldPB(id: 'team', name: 'Team'),
              FieldPB(id: 'amount', name: 'Amount'),
            ];
          },
        ),
      );

  void notify(DatabaseNotification type) {
    // Mirrors the backend's insert/delete notification precondition.
    if (activeViews.contains(_viewId)) changes.add(_event(type));
  }
}
