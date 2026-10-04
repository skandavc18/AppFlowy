import 'dart:convert';

import 'package:appflowy/plugins/database/find/database_find_session.dart';
import 'package:appflowy/plugins/database/find/database_find_target.dart';
import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../widget_test/database_find_test_support.dart';

void main() {
  setUpDatabaseFindTests();

  testWidgets(
      'the typed decoder follows current sorted membership and excludes hidden cells before I/O',
      (tester) async {
    final reads = DatabaseFindReads();
    reads.views[databaseFindViewId]!.name = 'Table';
    reads.fields[databaseFindViewId]!.first.name = 'Task';
    reads.rows[databaseFindViewId]!.addAll([
      RowMetaPB(id: 'second-row'),
      RowMetaPB(id: 'filtered-out-row-guid'),
    ]);
    reads.cells[(databaseFindViewId, 'second-row', databaseFindFieldId)] =
        CellPB(
      rowId: 'second-row',
      fieldId: databaseFindFieldId,
      fieldType: FieldType.RichText,
      data: utf8.encode('second needle'),
    );
    final before = reads.snapshot();
    final snapshot = DatabaseFindViewSnapshot(
      viewId: databaseFindViewId,
      rowIds: ['second-row', databaseFindRowId],
      fieldIds: [databaseFindFieldId],
    );
    final session = DatabaseFindSession(
      viewId: databaseFindViewId,
      isOwnerActive: () => true,
      provider: reads.provider(),
      viewSnapshot: () => snapshot,
    );
    try {
      session.search('needle', const FindOptions());
      await tester.pump(DatabaseFindSession.debounce);
      await databaseFindUntil(tester, () => !session.loading);
      expect(session.status, DatabaseFindStatus.ready);
      expect(
        session.matches.map((match) => match.part.text),
        ['second needle', 'A needle task'],
      );
      expect(
          session.matches.map((match) => match.targetIn(databaseFindViewId)), [
        const DatabaseFindTarget.cell(
          databaseFindViewId,
          'second-row',
          databaseFindFieldId,
        ),
        const DatabaseFindTarget.cell(
          databaseFindViewId,
          databaseFindRowId,
          databaseFindFieldId,
        ),
      ]);
      expect(reads.calls.where((call) => call.startsWith('cell:')), [
        'cell:$databaseFindViewId:second-row:$databaseFindFieldId',
        databaseFindCellStage,
      ]);
      final calls = List.of(reads.calls);
      session.navigate();
      session.navigate(forward: false);
      expect(reads.calls, calls);
      expect(reads.snapshot(), before);
      expect(reads.forbiddenReads, isEmpty);
    } finally {
      session.dispose();
      reads.dispose();
      await tester.pump();
    }
  });

  testWidgets(
      'a silent layout revision during a read rejects the entire stale result',
      (tester) async {
    final reads = DatabaseFindReads();
    final held = reads.hold(databaseFindCellStage);
    var snapshot = DatabaseFindViewSnapshot(
      viewId: databaseFindViewId,
      rowIds: [databaseFindRowId],
      fieldIds: [databaseFindFieldId],
      revision: 1,
    );
    final session = DatabaseFindSession(
      viewId: databaseFindViewId,
      isOwnerActive: () => true,
      provider: reads.provider(),
      viewSnapshot: () => snapshot,
    );
    try {
      session.search('needle', const FindOptions());
      await tester.pump(DatabaseFindSession.debounce);
      expect(reads.calls, contains(databaseFindCellStage));
      snapshot = DatabaseFindViewSnapshot(
        viewId: databaseFindViewId,
        rowIds: const [],
        fieldIds: [databaseFindFieldId],
        revision: 2,
      );
      held.complete();
      await databaseFindUntil(tester, () => !session.loading);
      expect(session.status, DatabaseFindStatus.changed);
      expect(session.matches, isEmpty);
      final calls = List.of(reads.calls);
      session.navigate();
      expect(reads.calls, calls);
      session.invalidate();
      await tester.pump(DatabaseFindSession.debounce);
      await databaseFindUntil(tester, () => !session.loading);
      expect(
        session.matches.every((match) => !match.part.id.startsWith('row:')),
        isTrue,
      );
      expect(
        reads.calls.where((call) => call.startsWith('cell:')),
        hasLength(1),
      );
    } finally {
      session.dispose();
      reads.dispose();
      await tester.pump();
    }
  });

  testWidgets('a snapshot for a different tab is rejected without reads',
      (tester) async {
    final reads = DatabaseFindReads();
    final session = DatabaseFindSession(
      viewId: databaseFindViewId,
      isOwnerActive: () => true,
      provider: reads.provider(),
      viewSnapshot: () => DatabaseFindViewSnapshot(
        viewId: 'other',
        rowIds: const [],
        fieldIds: const [],
      ),
    );
    try {
      session.search('needle', const FindOptions());
      await tester.pump(DatabaseFindSession.debounce);
      expect(session.status, DatabaseFindStatus.changed);
      expect(session.matches, isEmpty);
      expect(reads.calls, isEmpty);
    } finally {
      session.dispose();
      reads.dispose();
      await tester.pump();
    }
  });
}
