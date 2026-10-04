import 'dart:async';

import 'package:appflowy/plugins/database/find/database_find_navigation.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/row/row.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_highlight.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'database_find_grid_test_support.dart';
import 'database_find_test_support.dart';

void main() {
  setUpDatabaseFindTests();

  test('typed targets never infer a row/field from a label or a foreign ID',
      () {
    expect(
      DatabaseFindTarget.parse('view', 'row:r:f'),
      const DatabaseFindTarget.cell('view', 'r', 'f'),
    );
    expect(
      DatabaseFindTarget.parse('view', 'field:f'),
      const DatabaseFindTarget.field('view', 'f'),
    );
    expect(
      DatabaseFindTarget.parse('view', 'title'),
      const DatabaseFindTarget.title('view'),
    );
    for (final id in [
      'Row 2 · Name',
      'row:r',
      'row::f',
      'row:r:f:other',
      'field:',
    ]) {
      expect(DatabaseFindTarget.parse('view', id), isNull);
    }
    expect(DatabaseFindTarget.parse('', 'title'), isNull);
    expect(
      const DatabaseFindTarget.cell('a', 'r', 'f'),
      isNot(const DatabaseFindTarget.cell('b', 'r', 'f')),
    );
    final ids = ['r'];
    final snapshot =
        DatabaseFindViewSnapshot(viewId: 'view', rowIds: ids, fieldIds: ['f']);
    ids.clear();
    expect(
      snapshot.contains(const DatabaseFindTarget.cell('view', 'r', 'f')),
      isTrue,
    );
    expect(
      snapshot.contains(const DatabaseFindTarget.cell('view', 'hidden', 'f')),
      isFalse,
    );
    expect(
      snapshot.contains(const DatabaseFindTarget.cell('view', 'r', 'hidden')),
      isFalse,
    );
  });

  _gridTest(
    'a cached grid row is revealed even while its entire sliver has zero paint extent',
    (tester, page, model, grid) async {
      await page.mount(tester);
      const target =
          DatabaseFindTarget.row(databaseFindViewId, findGridNearRow);
      final row = grid().navigation.materializedAnchors(target).single;
      final scroll = grid().scroll;
      final verticalPosition = scroll.verticalController.position;
      expect(row.hasSize, isTrue);
      expect(row.isMaterialized, isTrue);
      expect(row.isOnstage, isFalse);
      expect(
        grid().navigation.rows,
        isEmpty,
        reason: 'The cache is laid out, but there are no painted row samples',
      );
      expect(grid().navigation.anchors(target), isEmpty);
      expect(
        findGridCell(findGridNearRow, findGridNearField, skipOffstage: false),
        findsOneWidget,
      );
      final before = model.reads.snapshot();

      await page.open(tester, hover: false);
      await page.query(tester, 'needle');
      await settleDatabaseFindNavigation(tester, grid().navigation);
      _expectExact(tester, grid(), findGridNearRow, findGridNearField);
      expect(grid().navigation.anchors(target).single, same(row));
      expect(row.isOnstage, isTrue);
      expect(scroll.verticalController.offset, greaterThan(0));
      expect(grid().scroll, same(scroll));
      expect(scroll.verticalController.position, same(verticalPosition));
      expect(model.reads.snapshot(), before);
      expect(model.writes, isEmpty);
    },
    leadingPadding: 600,
  );

  _gridTest(
    'a row evicted after placeholder materialization is re-seeked by the same request',
    (tester, page, model, grid) async {
      await page.mount(tester);
      await page.open(tester, hover: false);
      await page.query(tester, 'needle');
      await settleDatabaseFindNavigation(tester, grid().navigation);
      final before = model.reads.snapshot();
      final reads = List.of(page.reads.calls);
      final scroll = grid().scroll;
      final verticalPosition = scroll.verticalController.position;
      final horizontalPosition = scroll.horizontalController.position;

      await databaseFindKey(
        tester,
        LogicalKeyboardKey.f3,
        PhysicalKeyboardKey.f3,
      );
      await settleDatabaseFindNavigation(tester, grid().navigation);
      final samples = grid()
          .materializationSamples
          .where(
            (sample) => sample.request.target.rowId == findGridFarRow,
          )
          .toList();
      expect(
        samples.length,
        greaterThan(1),
        reason: 'Relayout must reacquire the evicted row, not just wait',
      );
      final first = samples.first;
      expect(first.row, isNotNull);
      expect(
        first.rowHeight,
        36,
        reason: 'The real RowBloc initially exposes only the placeholder',
      );
      expect(first.cellReady, isFalse);
      expect(
        first.row!.isMaterialized,
        isFalse,
        reason: 'Wrapped siblings evicted the first materialized boundary',
      );
      expect(
        samples.every((sample) => identical(sample.request, first.request)),
        isTrue,
      );
      expect(first.request.isCurrent, isTrue);
      _expectExact(tester, grid(), findGridFarRow, findGridFarField);
      expect(grid().scroll, same(scroll));
      expect(scroll.verticalController.position, same(verticalPosition));
      expect(scroll.horizontalController.position, same(horizontalPosition));
      expect(page.reads.calls, reads);
      expect(model.reads.snapshot(), before);
      expect(model.writes, isEmpty);
      expect(model.openedRows, isEmpty);
    },
  );

  _gridTest(
    'query replacement cancels an eviction re-seek before either axis moves',
    (tester, page, model, grid) async {
      await page.mount(tester);
      await page.open(tester, hover: false);
      await page.query(tester, 'needle');
      await settleDatabaseFindNavigation(tester, grid().navigation);
      final beforeSamples = grid().materializationSamples.length;
      await databaseFindKey(
        tester,
        LogicalKeyboardKey.f3,
        PhysicalKeyboardKey.f3,
      );
      await databaseFindUntil(
        tester,
        () => grid().materializationSamples.length > beforeSamples,
      );
      final sample = grid().materializationSamples.last;
      expect(sample.request.target.rowId, findGridFarRow);
      expect(sample.rowHeight, 36);
      expect(sample.cellReady, isFalse);
      final gate = Completer<void>();
      model.gate.value = gate;
      final calls = grid().requests.length;
      await tester.pump();
      expect(sample.row!.isMaterialized, isFalse);
      expect(grid().requests.length, calls + 1);
      expect(grid().requests.last, same(sample.request));
      expect(sample.request.isCurrent, isTrue);
      final beforeX = grid().scroll.horizontalController.offset;
      final beforeY = grid().scroll.verticalController.offset;

      databaseFindBar(tester).findController.text = 'no such match';
      expect(sample.request.isCurrent, isFalse);
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(grid().scroll.horizontalController.offset, beforeX);
      expect(grid().scroll.verticalController.offset, beforeY);
      expect(grid().navigation.visibleMatchRects, isEmpty);
      expect(model.writes, isEmpty);
      expect(model.openedRows, isEmpty);
      databaseFindBar(tester).onClose();
    },
  );

  for (final appearance in ['light', 'dark', 'paper']) {
    _gridTest(
        '$appearance: F3 reveals a lazy far row AND far column and paints the exact native word',
        (tester, page, model, grid) async {
      page.mode = appearance;
      await page.mount(tester);
      expect(find.byType(GridRow), findsWidgets);
      expect(find.byType(CellContainer), findsWidgets);
      expect(findGridCell(findGridFarRow, findGridFarField), findsNothing);
      final before = model.reads.snapshot();
      final rows = List.of(model.order);
      final fields = model.fields.fieldInfos.map((field) => field.id).toList();
      await page.open(tester, hover: false);
      await page.query(tester, 'needle');
      await settleDatabaseFindNavigation(tester, grid().navigation);
      expect(databaseFindBar(tester).matchCount, 2);
      _expectExact(tester, grid(), findGridNearRow, findGridNearField);
      final focus = databaseFindBar(tester).findFocusNode;
      final reads = List.of(page.reads.calls);
      expect(reads.any((call) => call.contains('find-field-4')), isFalse);
      expect(reads.any((call) => call.contains('filtered-row')), isFalse);

      await databaseFindKey(
        tester,
        LogicalKeyboardKey.f3,
        PhysicalKeyboardKey.f3,
      );
      await settleDatabaseFindNavigation(tester, grid().navigation);
      expect(databaseFindBar(tester).currentMatch, 2);
      _expectExact(tester, grid(), findGridFarRow, findGridFarField);
      expect(grid().scroll.verticalController.offset, greaterThan(2000));
      expect(grid().scroll.horizontalController.offset, greaterThan(900));
      expect(
        grid().headerScroll.offset,
        closeTo(grid().scroll.horizontalController.offset, 0.1),
      );
      final editor = _editable(tester, findGridFarRow, findGridFarField);
      expect(
        editor.renderEditable.offset.pixels,
        greaterThan(1000),
        reason: 'The word, not merely the cell, must be brought into view',
      );
      expect(editor.widget.focusNode.hasFocus, isFalse);
      expect(focus.hasPrimaryFocus, isTrue);

      await databaseFindKey(
        tester,
        LogicalKeyboardKey.f3,
        PhysicalKeyboardKey.f3,
        shift: true,
      );
      await settleDatabaseFindNavigation(tester, grid().navigation);
      expect(databaseFindBar(tester).currentMatch, 1);
      _expectExact(tester, grid(), findGridNearRow, findGridNearField);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await settleDatabaseFindNavigation(tester, grid().navigation);
      _expectExact(tester, grid(), findGridFarRow, findGridFarField);
      await databaseFindKey(
        tester,
        LogicalKeyboardKey.f3,
        PhysicalKeyboardKey.f3,
      );
      await settleDatabaseFindNavigation(tester, grid().navigation);
      expect(databaseFindBar(tester).currentMatch, 1, reason: 'Next wraps');
      _expectExact(tester, grid(), findGridNearRow, findGridNearField);

      expect(model.order, rows);
      expect(model.fields.fieldInfos.map((field) => field.id), fields);
      expect(model.filters, ['retained filter']);
      expect(model.sorts, ['retained sort']);
      expect(model.reads.snapshot(), before);
      expect(model.writes, isEmpty);
      expect(model.openedRows, isEmpty);
      expect(
        page.reads.calls,
        reads,
        reason: 'Navigation adds no search reads',
      );
    });
  }

  _gridTest(
      'delegated native tab owns the real cell anchors, not the unrelated decorated view',
      (tester, page, model, grid) async {
    page.delegated = true;
    await page.mount(tester);
    expect(find.byType(ContextualFindRegion), findsOneWidget);
    expect(find.byType(DatabaseFindScope), findsNWidgets(2));
    await page.open(tester, hover: false);
    await page.query(tester, 'needle');
    await settleDatabaseFindNavigation(tester, grid().navigation);
    _expectExact(tester, grid(), findGridNearRow, findGridNearField);
    await databaseFindKey(
      tester,
      LogicalKeyboardKey.f3,
      PhysicalKeyboardKey.f3,
    );
    await settleDatabaseFindNavigation(tester, grid().navigation);
    _expectExact(tester, grid(), findGridFarRow, findGridFarField);
    expect(
      page.reads.calls.any((call) => call.contains('unrelated-database-guid')),
      isFalse,
    );
    expect(model.openedRows, isEmpty);
    expect(model.writes, isEmpty);
    final oldNavigation = grid().navigation;
    final oldRequest = grid().requests.last;
    page.nativeChild = false;
    await page.mount(tester);
    expect(oldRequest.isCurrent, isFalse);
    expect(oldNavigation.isOpen, isFalse);
    expect(find.byType(FindReplaceBar), findsNothing);
    expect(find.byType(ContextualFindRegion), findsOneWidget);
  });

  _gridTest(
      'F3 from a real database cell neither focuses another cell nor edits it',
      (tester, page, model, grid) async {
    await page.mount(tester);
    await page.open(tester, hover: false);
    await page.query(tester, 'needle');
    await settleDatabaseFindNavigation(tester, grid().navigation);
    final editor = _editable(tester, findGridNearRow, findGridNearField);
    editor.widget.focusNode.requestFocus();
    await tester.pump();
    final selection = editor.widget.controller.selection;
    await databaseFindKey(
      tester,
      LogicalKeyboardKey.f3,
      PhysicalKeyboardKey.f3,
    );
    await settleDatabaseFindNavigation(tester, grid().navigation);
    _expectExact(tester, grid(), findGridFarRow, findGridFarField);
    expect(editor.widget.focusNode.hasPrimaryFocus, isTrue);
    expect(editor.widget.controller.selection, selection);
    expect(model.writes, isEmpty);
  });

  _gridTest('opening and closing Find from a dirty real cell is not a submit',
      (tester, page, model, grid) async {
    await page.mount(tester);
    await tester.enterText(
      findGridTextField(findGridNearRow, findGridNearField),
      'unsaved work',
    );
    final editor = _editable(tester, findGridNearRow, findGridNearField);
    final controller = editor.widget.controller;
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 7);
    await tester.pump();
    expect(model.writes, isEmpty);
    // Open directly from the editor: the ordinary helper first focuses a
    // navigation button, which would itself be a legitimate cell blur.
    tester
        .widget<ContextualFindRegion>(find.byType(ContextualFindRegion))
        .onFind();
    await tester.pump();
    await tester.pump();
    expect(databaseFindBar(tester).findFocusNode.hasPrimaryFocus, isTrue);
    expect(controller.text, 'unsaved work');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 2, extentOffset: 7),
    );
    expect(model.writes, isEmpty);
    await page.query(tester, 'needle tail');
    await settleDatabaseFindNavigation(tester, grid().navigation);
    _expectExact(tester, grid(), findGridFarRow, findGridFarField);
    expect(editor.mounted, isTrue);
    expect(controller.text, 'unsaved work');
    databaseFindBar(tester).onClose();
    await tester.pump();
    await tester.pump();
    expect(editor.widget.focusNode.hasPrimaryFocus, isTrue);
    expect(controller.text, 'unsaved work');
    expect(model.writes, isEmpty);
  });

  _gridTest(
      'a dirty cell survives lazy navigation with identical controller, selection and composition',
      (tester, page, model, grid) async {
    await page.mount(tester);
    await page.open(tester, hover: false);
    await page.query(tester, 'needle');
    await settleDatabaseFindNavigation(tester, grid().navigation);
    final field = tester
        .widget<TextField>(findGridTextField(findGridNearRow, 'find-field-2'));
    final controller = field.controller!;
    final originalEditor = _editable(tester, findGridNearRow, 'find-field-2');
    const draft = TextEditingValue(
      text: 'unsubmitted draft',
      selection: TextSelection(baseOffset: 2, extentOffset: 8),
      composing: TextRange(start: 1, end: 9),
    );
    controller.value = draft;
    await tester.pump();
    await databaseFindKey(
      tester,
      LogicalKeyboardKey.f3,
      PhysicalKeyboardKey.f3,
    );
    await settleDatabaseFindNavigation(tester, grid().navigation);
    _expectExact(tester, grid(), findGridFarRow, findGridFarField);
    expect(originalEditor.mounted, isTrue);
    expect(controller.value, draft);
    expect(
      grid().navigation.materializedAnchors(
            const DatabaseFindTarget.cell(
              databaseFindViewId,
              findGridNearRow,
              'find-field-2',
            ),
          ),
      isEmpty,
      reason:
          'A retained draft in the keep-alive bucket is not a laid-out seek sample',
    );
    await databaseFindKey(
      tester,
      LogicalKeyboardKey.f3,
      PhysicalKeyboardKey.f3,
      shift: true,
    );
    await settleDatabaseFindNavigation(tester, grid().navigation);
    expect(
      _editable(tester, findGridNearRow, 'find-field-2'),
      same(originalEditor),
    );
    expect(
      tester
          .widget<TextField>(
            findGridTextField(findGridNearRow, 'find-field-2'),
          )
          .controller,
      same(controller),
    );
    expect(controller.value, draft);
    expect(field.focusNode!.hasFocus, isFalse);
    expect(model.writes, isEmpty);
  });

  _gridTest('dirty display text never borrows a saved result highlight',
      (tester, page, model, grid) async {
    await page.mount(tester);
    await page.open(tester, hover: false);
    await page.query(tester, 'needle');
    await settleDatabaseFindNavigation(tester, grid().navigation);
    final current = databaseFindSession(tester).current!;
    final controller =
        _editable(tester, findGridNearRow, findGridNearField).widget.controller;
    controller.value = const TextEditingValue(
      text: 'needle in a different unsaved draft',
      selection: TextSelection.collapsed(offset: 4),
    );
    await tester.pump();
    await tester.pump();
    final anchor =
        grid().navigation.anchors(current.targetIn(databaseFindViewId)!).single;
    expect(anchor.measure(current).boxes, isEmpty);
    expect(grid().navigation.visibleMatchRects, isEmpty);
    expect(grid().navigation.reveal, isNot(DatabaseFindReveal.exact));
    expect(model.writes, isEmpty);
  });

  for (final stableScrollBehavior in [true, false]) {
    _gridTest(
      stableScrollBehavior
          ? 'equal view snapshots retain a pending request and native scroll positions through rebuild'
          : 'a theme-driven native position replacement keeps the pending Find request',
      (tester, page, model, grid) async {
        await page.mount(tester);
        await page.open(tester, hover: false);
        await page.query(tester, 'needle');
        await settleDatabaseFindNavigation(tester, grid().navigation);
        _expectExact(tester, grid(), findGridNearRow, findGridNearField);
        final scroll = grid().scroll;
        final verticalPosition = scroll.verticalController.position;
        final horizontalPosition = scroll.horizontalController.position;
        final beforeX = horizontalPosition.pixels;
        final beforeY = verticalPosition.pixels;
        final snapshot = grid().navigation.snapshot();
        final gate = Completer<void>();
        model.gate.value = gate;
        await databaseFindKey(
          tester,
          LogicalKeyboardKey.f3,
          PhysicalKeyboardKey.f3,
        );
        await tester.pump();
        final request = grid().requests.last;
        expect(
          request.target,
          const DatabaseFindTarget.cell(
            databaseFindViewId,
            findGridFarRow,
            findGridFarField,
          ),
        );
        expect(request.isCurrent, isTrue);

        page.width = 540;
        page.mode = 'paper';
        await page.mount(tester);
        expect(grid().navigation.snapshot(), snapshot);
        expect(
          request.isCurrent,
          isTrue,
          reason: 'Equal snapshots are not a new view or a reordered row set',
        );
        expect(grid().scroll, same(scroll));
        if (stableScrollBehavior) {
          expect(scroll.verticalController.position, same(verticalPosition));
          expect(
            scroll.horizontalController.position,
            same(horizontalPosition),
          );
        } else {
          expect(
            scroll.verticalController.position,
            isNot(same(verticalPosition)),
          );
          expect(
            scroll.horizontalController.position,
            isNot(same(horizontalPosition)),
          );
          expect(
            scroll.verticalController.position.context,
            same(verticalPosition.context),
          );
          expect(
            scroll.horizontalController.position.context,
            same(horizontalPosition.context),
          );
        }
        expect(scroll.horizontalController.offset, beforeX);
        expect(scroll.verticalController.offset, beforeY);
        gate.complete();
        await settleDatabaseFindNavigation(tester, grid().navigation);
        expect(grid().requests.last, same(request));
        _expectExact(tester, grid(), findGridFarRow, findGridFarField);
        expect(model.writes, isEmpty);
      },
      stableScrollBehavior: stableScrollBehavior,
    );
  }

  for (final action in [
    'query',
    'close',
    'access',
    'reorder',
    'rebind',
    'offstage',
  ]) {
    _gridTest(
        '$action cancels a pending materialization before either axis moves',
        (tester, page, model, grid) async {
      await page.mount(tester);
      await page.open(tester, hover: false);
      await page.query(tester, 'needle');
      await settleDatabaseFindNavigation(tester, grid().navigation);
      final beforeX = grid().scroll.horizontalController.offset;
      final beforeY = grid().scroll.verticalController.offset;
      final gate = Completer<void>();
      model.gate.value = gate;
      await databaseFindKey(
        tester,
        LogicalKeyboardKey.f3,
        PhysicalKeyboardKey.f3,
      );
      await tester.pump();
      await tester.pump();
      final request = grid().requests.last;
      expect(
        request.target,
        const DatabaseFindTarget.cell(
          databaseFindViewId,
          findGridFarRow,
          findGridFarField,
        ),
      );
      expect(request.isCurrent, isTrue);
      switch (action) {
        case 'query':
          databaseFindBar(tester).findController.text = 'no such match';
        case 'close':
          databaseFindBar(tester).onClose();
        case 'access':
          model.reads.allowed = false;
          model.reads.access.value++;
        case 'reorder':
          model.order = model.order.reversed.toList();
          model.notifyLayout();
        case 'rebind':
          page.reads.addView('new-tab', 'New tab');
          page.view = page.reads.views['new-tab']!;
          await page.mount(tester);
        case 'offstage':
          page.hidden = true;
          await page.mount(tester);
      }
      expect(request.isCurrent, isFalse);
      gate.complete();
      await tester.pump();
      await tester.pump();
      expect(grid().scroll.horizontalController.offset, beforeX);
      expect(grid().scroll.verticalController.offset, beforeY);
      expect(grid().navigation.visibleMatchRects, isEmpty);
      expect(model.writes, isEmpty);
      if (find.byType(FindReplaceBar).evaluate().isNotEmpty) {
        databaseFindBar(tester).onClose();
      }
    });
  }

  _gridTest(
      'query replacement reveals only the new far field and a column-name match reveals its heading',
      (tester, page, model, grid) async {
    await page.mount(tester);
    await page.open(tester, hover: false);
    await page.query(tester, 'needle');
    await settleDatabaseFindNavigation(tester, grid().navigation);
    await page.query(tester, 'needle tail');
    await settleDatabaseFindNavigation(tester, grid().navigation);
    expect(databaseFindBar(tester).matchCount, 1);
    _expectExact(tester, grid(), findGridFarRow, findGridFarField);
    final beforeY = grid().scroll.verticalController.offset;
    await page.query(tester, 'Destination');
    await settleDatabaseFindNavigation(tester, grid().navigation);
    expect(
      databaseFindSession(tester).current!.part.id,
      'field:$findGridFarField',
    );
    expect(grid().navigation.reveal, DatabaseFindReveal.exact);
    expect(grid().navigation.visibleMatchRects, isNotEmpty);
    expect(
      grid().scroll.verticalController.offset,
      beforeY,
      reason: 'Heading navigation must not reset the row',
    );
    expect(model.writes, isEmpty);
  });

  _gridTest(
      'a new filtered/sorted order is read and searched, never replaced by native row order',
      (tester, page, model, grid) async {
    model.order = [findGridFarRow, findGridNearRow];
    await page.mount(tester);
    await page.open(tester, hover: false);
    await page.query(tester, 'needle');
    await settleDatabaseFindNavigation(tester, grid().navigation);
    final session = databaseFindSession(tester);
    expect(session.matches.map((match) => match.part.id), [
      'row:$findGridFarRow:$findGridFarField',
      'row:$findGridNearRow:$findGridNearField',
    ]);
    _expectExact(tester, grid(), findGridFarRow, findGridFarField);
    expect(
      page.reads.calls.any((call) => call.contains('find-row-42:')),
      isFalse,
    );
    expect(model.order, [findGridFarRow, findGridNearRow]);
    expect(model.writes, isEmpty);
  });

  testWidgets(
      'ellipsized text cannot report a partly painted range as an exact visible match',
      (tester) async {
    final page = DatabaseFindHarness();
    final target = const DatabaseFindTarget.cell(
      databaseFindViewId,
      databaseFindRowId,
      databaseFindFieldId,
    );
    const value = 'needle with a very long clipped ending';
    page.reads.setText(databaseFindViewId, value);
    page.content = Align(
      alignment: Alignment.bottomLeft,
      child: SizedBox(
        width: 60,
        child: DatabaseFindAnchor(
          target: target,
          child: const Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
    try {
      await page.mount(tester);
      await page.open(tester, hover: false);
      await page.query(tester, value);
      final navigation = tester
          .widget<DatabaseFindScope>(find.byType(DatabaseFindScope))
          .controller;
      await settleDatabaseFindNavigation(tester, navigation);
      expect(databaseFindBar(tester).matchCount, 1);
      expect(navigation.reveal, DatabaseFindReveal.cell);
      expect(navigation.visibleMatchRects, isEmpty);
      expect(
        navigation
            .anchors(target)
            .single
            .measure(databaseFindSession(tester).current!)
            .complete,
        isFalse,
      );
    } finally {
      await page.dispose(tester);
    }
  });
}

void _gridTest(
  String name,
  Future<void> Function(
    WidgetTester,
    DatabaseFindHarness,
    DatabaseFindGridModel,
    DatabaseFindGridFixtureState Function(),
  ) test, {
  double leadingPadding = 0,
  bool stableScrollBehavior = true,
}) {
  testWidgets(
    name,
    (tester) async {
      final page = DatabaseFindHarness();
      final model = DatabaseFindGridModel(page.reads);
      final key = GlobalKey<DatabaseFindGridFixtureState>();
      page.content = DatabaseFindGridFixture(
        key: key,
        model: model,
        leadingPadding: leadingPadding,
        stableScrollBehavior: stableScrollBehavior,
      );
      try {
        await test(tester, page, model, () => key.currentState!);
        expect(tester.takeException(), isNull);
      } finally {
        await page.dispose(tester);
        model.dispose();
        await tester.pump();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

EditableTextState _editable(
  WidgetTester tester,
  String rowId,
  String fieldId,
) =>
    tester.state<EditableTextState>(
      find.descendant(
        of: findGridCell(rowId, fieldId),
        matching: find.byType(EditableText),
      ),
    );

void _expectExact(
  WidgetTester tester,
  DatabaseFindGridFixtureState grid,
  String rowId,
  String fieldId,
) {
  final current = databaseFindSession(tester).current!;
  expect(current.part.id, 'row:$rowId:$fieldId');
  final diagnostics = grid.navigationDiagnostics;
  expect(grid.requests, isNotEmpty, reason: diagnostics);
  expect(grid.requests.last.isCurrent, isTrue, reason: diagnostics);
  expect(
    grid.navigation.snapshot(),
    grid.widget.model.snapshot(),
    reason: diagnostics,
  );
  expect(
    grid.navigation.reveal,
    DatabaseFindReveal.exact,
    reason: '${grid.navigation.message}\n$diagnostics',
  );
  final native = _editable(tester, rowId, fieldId).renderEditable;
  final boxes = native.getBoxesForSelection(
    TextSelection(
      baseOffset: current.range.start,
      extentOffset: current.range.end,
    ),
  );
  final expected = boxes
      .map(
        (box) => MatrixUtils.transformRect(
          native.getTransformTo(null),
          box.toRect(),
        ),
      )
      .toList();
  expect(grid.navigation.visibleMatchRects, expected);
  expect(expected, isNotEmpty);
  final viewport = tester.getRect(find.byKey(grid.viewportKey)).inflate(0.1);
  for (final rect in expected) {
    expect(viewport.contains(rect.topLeft), isTrue);
    expect(viewport.contains(rect.bottomRight), isTrue);
  }
  final anchor = grid.navigation
      .anchors(DatabaseFindTarget.cell(databaseFindViewId, rowId, fieldId))
      .single;
  final color = FindHighlightColors.current(
    Theme.of(tester.element(findGridCell(rowId, fieldId))).brightness,
  );
  expect(anchor, paints..rect(color: color.withValues(alpha: color.a * 0.38)));
  expect(anchor.measure(current).complete, isTrue);
  expect(current.range.group(0), isNotEmpty);
}
