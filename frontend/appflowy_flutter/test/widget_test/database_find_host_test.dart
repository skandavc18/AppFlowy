import 'package:appflowy/plugins/database/find/database_find_host.dart';
import 'package:appflowy/plugins/database/find/database_find_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/native_find_test_input.dart';
import 'database_find_test_support.dart';

void main() {
  setUpDatabaseFindTests();

  for (final layout in [
    ViewLayoutPB.Grid,
    ViewLayoutPB.Board,
    ViewLayoutPB.Calendar,
  ]) {
    _test(
        '$layout: body Ctrl+F searches typed title/column/cells without writes',
        (tester, page) async {
      page.view.layout = layout;
      final before = page.reads.snapshot();
      await page.mount(tester);
      expect(
        page.reads.calls,
        isEmpty,
        reason: 'Passive registration does not read',
      );
      final region = tester.widget<ContextualFindRegion>(
        find.byType(ContextualFindRegion),
      );
      expect(region.findFocusNode, isNotNull);
      expect(region.findFocusNode!.parent, isNull);
      expect(region.findOpen, isFalse);
      expect(region.onDismiss, isNotNull);
      final body = page.body;
      final element = tester.element(find.byKey(page.bodyKey));
      final rect = tester.getRect(find.byKey(page.bodyKey));
      body.draft.value = const TextEditingValue(
        text: 'unsubmitted draft',
        selection: TextSelection(baseOffset: 2, extentOffset: 5),
        composing: TextRange(start: 1, end: 6),
      );
      final draft = body.draft.value;
      body.scroll.jumpTo(80);
      await tester.pump();

      await page.open(tester);
      expect(databaseFindBar(tester).findFocusNode.hasPrimaryFocus, isTrue);
      expect(databaseFindBar(tester).replaceController, isNull);
      expect(find.byKey(const ValueKey('replaceTextField')), findsNothing);
      await page.query(tester, 'needle');
      expect(databaseFindBar(tester).matchCount, 4);
      expect(databaseFindBar(tester).currentMatch, 1);
      expect(find.text('Database title'), findsOneWidget);
      expect(_snippet(tester), 'Needle roadmap');
      expect(_highlighted(tester), 'Needle');
      expect(find.text('1 of 4'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('findNextMatch')));
      await tester.pump();
      expect(databaseFindBar(tester).currentMatch, 2);
      expect(find.text('Column'), findsOneWidget);
      expect(_snippet(tester), 'Needle column');
      databaseFindBar(tester).findFocusNode.requestFocus();
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(databaseFindBar(tester).currentMatch, 3);
      expect(find.text('Row 1 · Needle column'), findsOneWidget);
      expect(_snippet(tester), 'A needle task');
      await databaseFindKey(
        tester,
        LogicalKeyboardKey.f3,
        PhysicalKeyboardKey.f3,
      );
      await tester.pump();
      expect(databaseFindBar(tester).currentMatch, 4);
      expect(_snippet(tester), 'NEEDLE ready');
      expect(_highlighted(tester), 'NEEDLE');
      await databaseFindKey(
        tester,
        LogicalKeyboardKey.f3,
        PhysicalKeyboardKey.f3,
        shift: true,
      );
      await tester.pump();
      expect(databaseFindBar(tester).currentMatch, 3);
      await tester.tap(find.byKey(const ValueKey('findPreviousMatch')));
      await tester.pump();
      expect(databaseFindBar(tester).currentMatch, 2);
      databaseFindBar(tester).findFocusNode.requestFocus();
      await tester.pump();
      await databaseFindKey(
        tester,
        LogicalKeyboardKey.enter,
        PhysicalKeyboardKey.enter,
        shift: true,
      );
      await tester.pump();
      expect(databaseFindBar(tester).currentMatch, 1);
      await tester.tap(find.byKey(const ValueKey('findPreviousMatch')));
      await tester.pump();
      expect(databaseFindBar(tester).currentMatch, 4, reason: 'Previous wraps');

      final calls = List.of(page.reads.calls);
      await databaseFindKey(
        tester,
        LogicalKeyboardKey.keyH,
        PhysicalKeyboardKey.keyH,
        control: true,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('replaceTextField')), findsNothing);
      expect(
        page.reads.calls,
        calls,
        reason: 'Navigation and Replace do not perform I/O',
      );
      expect(
        page.reads.calls.where((call) => call.startsWith('view:')),
        ['view:$databaseFindViewId', 'view:$databaseFindViewId'],
      );
      expect(
        page.reads.calls.where((call) => call.startsWith('preflight:')),
        hasLength(2),
      );
      expect(
        page.reads.calls.any((call) => call.contains('relation-field-guid')),
        isFalse,
      );
      expect(
        page.reads.calls.any((call) => call.contains('filtered-out-row-guid')),
        isFalse,
      );
      expect(
        page.reads.calls
            .any((call) => call.contains('unrelated-database-guid')),
        isFalse,
      );
      expect(page.reads.forbiddenReads, isEmpty);
      expect(page.reads.snapshot(), before, reason: 'No PB data/filter writes');
      expect(page.body, same(body));
      expect(tester.element(find.byKey(page.bodyKey)), same(element));
      expect(tester.getRect(find.byKey(page.bodyKey)), rect);
      expect(body.draft.value, draft);
      expect(body.scroll.offset, 80);
      expect(body.edits, 0);

      databaseFindBar(tester).findFocusNode.requestFocus();
      await tester.pump();
      await databaseFindKey(
        tester,
        LogicalKeyboardKey.escape,
        PhysicalKeyboardKey.escape,
      );
      await tester.pump();
      expect(find.byType(FindReplaceBar), findsNothing);
      expect(page.body, same(body));
      expect(body.draft.value, draft);
      expect(body.scroll.offset, 80);
      expect(page.reads.snapshot(), before);
    });

    _test('$layout: page Find searches from navigation focus without a mouse',
        (tester, page) async {
      page.view.layout = layout;
      final before = page.reads.snapshot();
      await page.mount(tester);
      expect(find.byType(ContextualFindScope), findsOneWidget);
      expect(page.reads.calls, isEmpty);
      final body = page.body;
      final draft = body.draft.value;
      final scrollOffset = body.scroll.offset;
      page.navigationFocus.requestFocus();
      await tester.pump();
      expect(page.navigationFocus.hasPrimaryFocus, isTrue);

      await page.open(tester, hover: false);
      expect(databaseFindBar(tester).findFocusNode.hasPrimaryFocus, isTrue);
      expect(page.reads.calls, isEmpty, reason: 'Opening alone does not read');
      await page.query(tester, 'needle');
      expect(databaseFindSession(tester).viewId, databaseFindViewId);
      expect(databaseFindBar(tester).matchCount, 4);
      expect(_snippet(tester), 'Needle roadmap');
      expect(
        page.reads.calls.where((call) => call.startsWith('view:')),
        ['view:$databaseFindViewId', 'view:$databaseFindViewId'],
      );
      expect(page.reads.forbiddenReads, isEmpty);
      expect(page.reads.snapshot(), before);
      expect(page.body, same(body));
      expect(body.draft.value, draft);
      expect(body.scroll.offset, scrollOffset);
      expect(body.edits, 0);
    });
  }

  _test('populated Find teardown never notifies departing query widgets',
      (tester, page) async {
    final before = page.reads.snapshot();
    await page.mount(tester);
    await page.open(tester, hover: false);
    await page.query(tester, 'needle');
    final session = databaseFindSession(tester);
    final query = databaseFindBar(tester).findController;
    final queryChanges = <TextEditingValue>[];
    query.addListener(() => queryChanges.add(query.value));
    final calls = List.of(page.reads.calls);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(queryChanges, isEmpty);
    expect(session.matches, isEmpty);
    expect(find.byType(FindReplaceBar), findsNothing);
    page.reads.access.value++;
    page.reads.changes.add(databaseFindViewId);
    await tester.pump(DatabaseFindSession.debounce);
    expect(page.reads.calls, calls, reason: 'Disposed listeners cannot read');
    expect(page.reads.snapshot(), before);
  });

  for (final delegated in [false, true]) {
    _test(
        'keyboard-only rebind keeps pending reads bounded and writes nothing: delegated=$delegated',
        (tester, page) async {
      page.delegated = delegated;
      page.provider = page.reads.provider(sharedScheduler: true);
      page.reads.addView('selected-tab', 'Selected needle tab');
      final before = page.reads.snapshot();
      final held = page.reads.hold(databaseFindCellStage);
      await page.mount(tester);
      final body = page.body;
      final draft = body.draft.value;
      final scrollOffset = body.scroll.offset;
      await page.open(tester, hover: false);
      await page.query(tester, 'needle', finish: false);
      final oldSession = databaseFindSession(tester);
      final calls = List.of(page.reads.calls);
      expect(calls, contains(databaseFindCellStage));
      expect(page.reads.inFlight, 1);

      page.view = page.reads.views['selected-tab']!;
      await page.mount(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(FindReplaceBar), findsNothing);
      expect(oldSession.matches, isEmpty);
      expect(page.reads.calls, calls);
      expect(page.provider.readScheduler.pendingCount, 0);

      await page.open(tester, hover: false);
      expect(databaseFindBar(tester).findController.text, isEmpty);
      expect(databaseFindBar(tester).matchCount, 0);
      final currentSession = databaseFindSession(tester);
      expect(currentSession, isNot(same(oldSession)));
      expect(currentSession.viewId, 'selected-tab');
      expect(page.reads.calls, calls);
      await page.query(tester, 'Selected', finish: false);
      expect(
        page.reads.calls,
        calls,
        reason: 'The old native read owns its slot',
      );
      expect(page.reads.inFlight, 1);
      expect(page.provider.readScheduler.pendingCount, 1);
      expect(databaseFindBar(tester).matchCount, 0);

      held.complete();
      await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
      expect(currentSession.status, DatabaseFindStatus.ready);
      expect(databaseFindBar(tester).matchCount, 1);
      expect(_snippet(tester), 'Selected needle tab');
      expect(oldSession.matches, isEmpty);
      final newCalls = page.reads.calls.skip(calls.length);
      expect(
        newCalls.where((call) => call.startsWith('view:')),
        ['view:selected-tab', 'view:selected-tab'],
      );
      expect(newCalls.every((call) => call.contains(':selected-tab')), isTrue);
      expect(page.provider.readScheduler.pendingCount, 0);
      expect(page.reads.maxInFlight, 1);
      expect(page.reads.forbiddenReads, isEmpty);
      expect(page.reads.snapshot(), before);
      expect(page.body, same(body));
      expect(body.draft.value, draft);
      expect(body.scroll.offset, scrollOffset);
      expect(body.edits, 0);
    });
  }

  _test(
      'title hover uses the same region, options and real typed display values',
      (tester, page) async {
    await page.mount(tester);
    await page.open(tester, fromTitle: true);
    await page.query(tester, 'needle');
    databaseFindBar(tester)
        .onOptionsChanged(const FindOptions(caseSensitive: true));
    await tester.pump(DatabaseFindSession.debounce);
    await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
    expect(databaseFindBar(tester).matchCount, 1);
    expect(_snippet(tester), 'A needle task');
    databaseFindBar(tester)
        .onOptionsChanged(const FindOptions(wholeWord: true));
    await page.query(tester, 'need');
    expect(databaseFindBar(tester).matchCount, 0);
    databaseFindBar(tester).onOptionsChanged(const FindOptions(useRegex: true));
    await page.query(tester, '25/09/2026|1,250\\.00|Yes');
    expect(databaseFindBar(tester).matchCount, 3);
    expect(
      databaseFindSession(tester).matches.map((m) => m.part.text),
      ['25/09/2026', 'Yes', r'$1,250.00'],
    );
    await page.query(
      tester,
      'option-guid|unused_option_sentinel|stale_option_sentinel|hidden_row_sentinel|raw_metadata_sentinel',
    );
    expect(databaseFindBar(tester).matchCount, 0);
    final calls = List.of(page.reads.calls);
    await page.query(tester, '[');
    expect(databaseFindBar(tester).queryInvalid, isTrue);
    expect(databaseFindBar(tester).busy, isFalse);
    expect(page.reads.calls, calls, reason: 'Invalid patterns do not read');
    expect(page.reads.forbiddenReads, isEmpty);
  });

  _test(
      'row/field and vault invalidation clears immediately and debounces reads',
      (tester, page) async {
    await page.mount(tester);
    await page.open(tester);
    await page.query(tester, 'needle');
    final session = databaseFindSession(tester);
    page.reads.setText(databaseFindViewId, 'Updated needle cell');
    final calls = List.of(page.reads.calls);
    for (var i = 0; i < 4; i++) {
      page.reads.changes.add('$databaseFindRowId:$databaseFindFieldId');
    }
    expect(session.matches, isEmpty);
    expect(session.loading, isTrue);
    expect(page.reads.calls, calls);
    await tester.pump(const Duration(milliseconds: 100));
    expect(databaseFindBar(tester).matchCount, 0);
    expect(page.reads.calls, calls);
    await tester.pump(const Duration(milliseconds: 81));
    await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
    expect(
      session.matches.any((m) => m.part.text == 'Updated needle cell'),
      isTrue,
    );
    expect(
      page.reads.calls.where((call) => call == 'rows:$databaseFindViewId'),
      hasLength(2),
    );

    final cellReads =
        page.reads.calls.where((call) => call.startsWith('cell:')).length;
    page.reads.allowed = false;
    page.reads.access.value++;
    expect(session.matches, isEmpty);
    await tester.pump(DatabaseFindSession.debounce);
    await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
    expect(session.status, DatabaseFindStatus.denied);
    expect(find.textContaining('access denied'), findsOneWidget);
    expect(find.byKey(const ValueKey('databaseFindSnippet')), findsNothing);
    expect(
      page.reads.calls.where((call) => call.startsWith('cell:')),
      hasLength(cellReads),
    );
    page.reads.allowed = true;
    page.reads.access.value++;
    await tester.pump(DatabaseFindSession.debounce);
    await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
    expect(databaseFindBar(tester).findController.text, 'needle');
    expect(databaseFindBar(tester).matchCount, 4);
  });

  for (final reason in ['denied', 'missing', 'wrong ID', 'not a database']) {
    _test('$reason metadata fails closed before title or cell publication',
        (tester, page) async {
      if (reason == 'denied') page.reads.allowed = false;
      if (reason == 'missing') page.reads.missingView = true;
      if (reason == 'wrong ID') {
        page.reads.wrongView = ViewPB(id: 'other', name: 'needle');
      }
      if (reason == 'not a database') page.view.layout = ViewLayoutPB.Document;
      await page.mount(tester);
      await page.open(tester);
      await page.query(tester, 'needle');
      expect(databaseFindSession(tester).status, DatabaseFindStatus.denied);
      expect(databaseFindBar(tester).matchCount, 0);
      expect(
        page.reads.calls.any((call) => call.startsWith('fields:')),
        isFalse,
      );
      expect(page.reads.forbiddenReads, isEmpty);
      expect(find.byKey(const ValueKey('databaseFindSnippet')), findsNothing);
    });
  }

  _test('native error is visible, does not leak details, and Retry reads again',
      (tester, page) async {
    page.reads.failures.add('fields:$databaseFindViewId');
    await page.mount(tester);
    await page.open(tester);
    await page.query(tester, 'needle');
    expect(databaseFindSession(tester).status, DatabaseFindStatus.failed);
    expect(find.textContaining('search failed'), findsOneWidget);
    expect(find.textContaining('Private native details'), findsNothing);
    expect(databaseFindBar(tester).matchCount, 0);
    page.reads.failures.clear();
    await tester.tap(find.byKey(const ValueKey('databaseFindRetry')));
    await tester.pump(DatabaseFindSession.debounce);
    await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
    expect(databaseFindBar(tester).matchCount, 4);
    expect(find.textContaining('Partial search:'), findsOneWidget);
    expect(
      find.textContaining('coverage could not be verified'),
      findsOneWidget,
    );
  });

  _test(
      'permission revocation during native read suppresses title and snippets',
      (tester, page) async {
    final held = page.reads.hold(databaseFindCellStage);
    await page.mount(tester);
    await page.open(tester);
    await page.query(tester, 'needle', finish: false);
    expect(page.reads.calls, contains(databaseFindCellStage));
    expect(databaseFindBar(tester).busy, isTrue);
    expect(find.text('Searching current database view…'), findsOneWidget);
    page.reads.allowed =
        false; // No notification: the final gate must catch it.
    held.complete();
    await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
    expect(databaseFindSession(tester).status, DatabaseFindStatus.denied);
    expect(databaseFindBar(tester).matchCount, 0);
    expect(find.byKey(const ValueKey('databaseFindSnippet')), findsNothing);
    expect(
      page.reads.calls.where((call) => call.startsWith('preflight:')),
      hasLength(2),
    );
  });

  _test('a metadata change during the read rejects the mismatched snapshot',
      (tester, page) async {
    final held = page.reads.hold(databaseFindCellStage);
    await page.mount(tester);
    await page.open(tester);
    await page.query(tester, 'needle', finish: false);
    page.reads.views[databaseFindViewId]!.name = 'Renamed current title';
    held.complete();
    await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
    expect(databaseFindSession(tester).status, DatabaseFindStatus.changed);
    expect(databaseFindBar(tester).matchCount, 0);
    await page.query(tester, 'Renamed');
    expect(databaseFindBar(tester).matchCount, 1);
    expect(_snippet(tester), 'Renamed current title');
  });

  _test('empty/missing/sealed values expose partial coverage, never ciphertext',
      (tester, page) async {
    page.reads.setText(databaseFindViewId, 'af1.private.sealed_sentinel');
    page.reads.cells[(
      databaseFindViewId,
      databaseFindRowId,
      'status-field-guid'
    )] = null;
    await page.mount(tester);
    await page.open(tester);
    await page.query(tester, 'sealed_sentinel');
    expect(databaseFindBar(tester).matchCount, 0);
    expect(databaseFindSession(tester).unavailable, isTrue);
    expect(databaseFindSession(tester).coverageUnknown, isTrue);
    expect(find.textContaining('Partial search:'), findsOneWidget);
    page.reads.rows[databaseFindViewId] = [];
    page.reads.changes.add(databaseFindViewId);
    await tester.pump(DatabaseFindSession.debounce);
    await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
    expect(databaseFindSession(tester).coverageUnknown, isTrue);
    expect(databaseFindBar(tester).matchCount, 0);
  });

  for (final stage in [
    'view:$databaseFindViewId',
    'fields:$databaseFindViewId',
    'rows:$databaseFindViewId',
    databaseFindCellStage,
  ]) {
    _test('hung $stage times out without releasing the shared slot on reopen',
        (tester, page) async {
      page.provider = page.reads.provider(
        deadline: const Duration(milliseconds: 30),
        sharedScheduler: true,
      );
      expect(
        page.provider.readScheduler,
        same(DocumentFindReadScheduler.shared),
      );
      final held = page.reads.hold(stage);
      await page.mount(tester);
      await page.open(tester);
      await page.query(tester, 'needle', finish: false);
      expect(page.reads.calls, contains(stage));
      final calls = List.of(page.reads.calls);
      final body = page.body;
      await tester.pump(const Duration(milliseconds: 31));
      expect(databaseFindSession(tester).status, DatabaseFindStatus.timedOut);
      expect(find.textContaining('deadline reached'), findsOneWidget);
      expect(databaseFindBar(tester).matchCount, 0);
      expect(page.reads.inFlight, 1);
      databaseFindBar(tester).onClose();
      await tester.pump();
      await page.open(tester);
      final timing = DatabaseFindQueryProbe(page);
      await timing.query(tester, 'needle');
      // Live pumps wait for native frames. A 30 ms deadline may correctly
      // expire before query() returns, so inspect the actual enqueue boundary,
      // not a fake-clock assumption about the frame's wall-clock duration.
      final enqueued = timing.events.singleWhere(
        (event) => event['event'] == 'debounce:after',
      );
      expect(
        enqueued,
        allOf(
          containsPair('pending', 1),
          containsPair('inFlight', 1),
          containsPair('calls', calls.length),
          containsPair('status', DatabaseFindStatus.loading.name),
        ),
        reason: 'Observed real timer ordering: ${timing.events}',
      );
      expect(page.reads.calls, calls);
      await tester.pump(const Duration(milliseconds: 31));
      final beforeDeadline = timing.events.singleWhere(
        (event) => event['event'] == 'deadline:before',
      );
      final afterDeadline = timing.events.singleWhere(
        (event) => event['event'] == 'deadline:after',
      );
      expect(
        beforeDeadline,
        allOf(
          containsPair('pending', 1),
          containsPair('inFlight', 1),
          containsPair('calls', calls.length),
          containsPair('status', DatabaseFindStatus.loading.name),
        ),
      );
      expect(
        afterDeadline,
        allOf(
          containsPair('pending', 0),
          containsPair('inFlight', 1),
          containsPair('calls', calls.length),
          containsPair('status', DatabaseFindStatus.timedOut.name),
        ),
      );
      expect(databaseFindSession(tester).status, DatabaseFindStatus.timedOut);
      expect(page.provider.readScheduler.pendingCount, 0);
      expect(page.reads.maxInFlight, 1);
      held.complete();
      await tester.pump();
      await tester.pump();
      expect(page.reads.calls, calls, reason: 'Late work stops at isCurrent');
      expect(databaseFindBar(tester).matchCount, 0);
      expect(page.body, same(body));
      await tester.tap(find.byKey(const ValueKey('databaseFindRetry')));
      await tester.pump(DatabaseFindSession.debounce);
      await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
      expect(databaseFindBar(tester).matchCount, 4);
      expect(page.reads.maxInFlight, 1);
    });
  }

  _test('superseded query cannot publish while its native cell is outstanding',
      (tester, page) async {
    final held = page.reads.hold(databaseFindCellStage);
    await page.mount(tester);
    await page.open(tester);
    await page.query(tester, 'needle', finish: false);
    page.reads.setText(databaseFindViewId, 'Latest replacement value');
    await page.query(tester, 'Latest', finish: false);
    expect(page.reads.inFlight, 1);
    expect(page.provider.readScheduler.pendingCount, 1);
    expect(databaseFindBar(tester).matchCount, 0);
    held.complete();
    await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
    expect(databaseFindBar(tester).matchCount, 1);
    expect(_snippet(tester), 'Latest replacement value');
    expect(page.reads.maxInFlight, 1);
  });

  for (final lifecycle in [
    'inactive',
    'hidden',
    'rebound',
    'mutated ID',
    'provider rebound',
    'unmounted',
  ]) {
    _test('$lifecycle host discards pending reads and removes its overlay',
        (tester, page) async {
      final held = page.reads.hold(databaseFindCellStage);
      await page.mount(tester);
      await page.open(tester);
      await page.query(tester, 'needle', finish: false);
      final session = databaseFindSession(tester);
      final fieldFocus = databaseFindBar(tester).findFocusNode;
      final calls = List.of(page.reads.calls);
      if (lifecycle == 'unmounted') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        if (lifecycle == 'inactive') page.active = false;
        if (lifecycle == 'hidden') page.hidden = true;
        if (lifecycle == 'provider rebound') {
          page.provider = page.reads.provider();
        }
        if (lifecycle == 'rebound' || lifecycle == 'mutated ID') {
          page.reads.addView('new-view', 'New live title');
          if (lifecycle == 'mutated ID') {
            page.view
              ..id = 'new-view'
              ..name = 'New live title';
            page.reads.views['new-view'] = page.view;
          } else {
            page.view = page.reads.views['new-view']!;
          }
        }
        await page.mount(tester);
      }
      held.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(FindReplaceBar), findsNothing);
      expect(session.matches, isEmpty);
      expect(fieldFocus.parent, isNull);
      expect(page.reads.calls, calls);
      if (lifecycle == 'rebound' || lifecycle == 'mutated ID') {
        await page.open(tester);
        await page.query(tester, 'New live');
        expect(_snippet(tester), 'New live title');
        expect(page.reads.calls.last, 'preflight:new-view');
      }
    });
  }

  _test('covering route closes Find and cannot steal the dialog query focus',
      (tester, page) async {
    final held = page.reads.hold(databaseFindCellStage);
    final dialogFocus = FocusNode();
    try {
      await page.mount(tester);
      await page.open(tester);
      await page.query(tester, 'needle', finish: false);
      final dialog = showDialog<void>(
        context: page.body.context,
        builder: (_) => AlertDialog(
          content: TextField(
            key: const ValueKey('dialogQuery'),
            focusNode: dialogFocus,
            autofocus: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FindReplaceBar), findsNothing);
      expect(dialogFocus.hasPrimaryFocus, isTrue);
      held.complete();
      await tester.pump();
      expect(dialogFocus.hasPrimaryFocus, isTrue);
      expect(find.byKey(const ValueKey('databaseFindSnippet')), findsNothing);
      page.navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await dialog;
      expect(find.byType(FindReplaceBar), findsNothing);
    } finally {
      dialogFocus.dispose();
    }
  });

  _test(
      'outside dismissal and a pending focus request never reclaim another field',
      (tester, page) async {
    await page.mount(tester);
    await page.open(tester);
    await page.query(tester, 'needle');
    await tester.tap(find.byKey(const ValueKey('otherSearchField')));
    await tester.pump();
    expect(find.byType(FindReplaceBar), findsNothing);
    expect(page.otherQueryFocus.hasPrimaryFocus, isTrue);
    await databaseFindKey(
      tester,
      LogicalKeyboardKey.keyF,
      PhysicalKeyboardKey.keyF,
      control: true,
    );
    await tester.pump();
    expect(find.byType(FindReplaceBar), findsNothing);
    expect(page.otherQueryFocus.hasPrimaryFocus, isTrue);

    page.navigationFocus.requestFocus();
    await tester.pump();
    final region =
        tester.widget<ContextualFindRegion>(find.byType(ContextualFindRegion));
    // Queue the competing request immediately before Find's focus callback.
    // Its microtask cannot run between callbacks in the same frame: this pins
    // the race seen in the native Release fixture, not only settled focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      page.otherQueryFocus.requestFocus();
    });
    region.onFind();
    await tester.pump();
    await tester.pump();
    expect(page.otherQueryFocus.hasPrimaryFocus, isTrue);
    tester
        .widget<ContextualFindRegion>(find.byType(ContextualFindRegion))
        .onDismiss!();
    await tester.pump();
    expect(page.otherQueryFocus.hasPrimaryFocus, isTrue);
    expect(find.byType(FindReplaceBar), findsNothing);
  });

  for (final mode in ['light', 'dark', 'paper']) {
    _test('$mode: narrow resize retains field/draft and uses themed highlights',
        (tester, page) async {
      page.mode = mode;
      await page.mount(tester);
      await page.open(tester);
      await page.query(tester, 'needle');
      final element =
          tester.element(find.byKey(const ValueKey('findTextField')));
      final body = page.body;
      final palette =
          FindBarPalette.of(tester.element(find.byType(FindReplaceBar)));
      final details = tester
          .widget<Container>(find.byKey(const ValueKey('databaseFindDetails')));
      expect((details.decoration! as BoxDecoration).color, palette.surface);
      if (mode == 'paper') expect(palette.surface, PaperTheme.popupBackground);
      expect(_highlighted(tester), 'Needle');
      page.width = 140;
      page.height = 130;
      page.textScale = 2;
      await page.mount(tester);
      expect(
        tester.element(find.byKey(const ValueKey('findTextField'))),
        same(element),
      );
      expect(databaseFindBar(tester).findController.text, 'needle');
      expect(databaseFindBar(tester).findFocusNode.hasPrimaryFocus, isTrue);
      expect(page.body, same(body));
      expect(
        tester.takeException(),
        isNull,
        reason: 'Scroll, never overflow/shrink controls',
      );
      page.width = 580;
      page.height = 480;
      page.textScale = 1;
      await page.mount(tester);
      expect(
        tester.element(find.byKey(const ValueKey('findTextField'))),
        same(element),
      );
      expect(databaseFindBar(tester).matchCount, 4);
    });
  }

  _test(
      'native child delegates selected view to a single decorated-page region',
      (tester, page) async {
    page.delegated = true;
    await page.mount(tester);
    expect(find.byType(DatabaseFindHost), findsNWidgets(2));
    expect(find.byType(ContextualFindRegion), findsOneWidget);
    await page.open(tester, fromTitle: true);
    await page.query(tester, 'needle');
    expect(databaseFindBar(tester).matchCount, 4);
    expect(
      page.reads.calls.any((call) => call.contains('unrelated-database-guid')),
      isFalse,
    );
    final body = page.body;
    page.reads.addView('selected-tab', 'Selected needle tab');
    page.view = page.reads.views['selected-tab']!;
    await page.mount(tester);
    expect(find.byType(FindReplaceBar), findsNothing);
    expect(page.body, same(body));
    await page.open(tester);
    await page.query(tester, 'Selected');
    expect(_snippet(tester), 'Selected needle tab');
    expect(databaseFindSession(tester).viewId, 'selected-tab');
    page.nativeChild = false;
    await page.mount(tester);
    expect(find.byType(ContextualFindRegion), findsOneWidget);
    expect(find.byType(FindReplaceBar), findsNothing);
    await page.open(tester);
    await page.query(tester, 'Unrelated');
    expect(_snippet(tester), 'Unrelated secret');
  });

  _test('entry/byte limits visibly disclose bounded partial results',
      (tester, page) async {
    page.limits = const DocumentFindLimits(
      maxDepth: 0,
      maxViews: 1,
      maxEntries: 3,
      maxBytes: 64,
    );
    await page.mount(tester);
    await page.open(tester);
    await page.query(tester, 'needle');
    expect(databaseFindSession(tester).truncated, isTrue);
    expect(databaseFindBar(tester).matchCount, lessThanOrEqualTo(3));
    expect(find.textContaining('search limit reached'), findsOneWidget);
    expect(
      find.textContaining('Related rows, encrypted values'),
      findsOneWidget,
    );
    expect(page.reads.forbiddenReads, isEmpty);
  });
}

void _test(
  String name,
  Future<void> Function(WidgetTester, DatabaseFindHarness) body,
) {
  testWidgets(
    name,
    (tester) async {
      final page = DatabaseFindHarness();
      final registrations = ContextualFindRegion.debugRegisteredRegionCount;
      try {
        await body(tester, page);
        expect(tester.takeException(), isNull);
      } finally {
        await page.dispose(tester);
        expect(ContextualFindRegion.debugRegisteredRegionCount, registrations);
      }
    },
    variant: findTestPlatformVariant,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

String _snippet(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('databaseFindSnippet')))
    .textSpan!
    .toPlainText();

String _highlighted(WidgetTester tester) {
  final text =
      tester.widget<Text>(find.byKey(const ValueKey('databaseFindSnippet')));
  final spans = (text.textSpan! as TextSpan).children!.whereType<TextSpan>();
  return spans
      .where((span) => span.style?.backgroundColor != null)
      .map((span) => span.text)
      .join();
}
