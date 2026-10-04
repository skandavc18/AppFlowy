import 'dart:async';

import 'package:appflowy/plugins/database/find/database_find_session.dart';
import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/command_palette/workspace_content_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'database_find_test_support.dart';

void main() {
  setUpDatabaseFindTests();
  testWidgets(
      'database native per-character client survives held read deadline and recovers',
      (tester) async {
    final page = DatabaseFindHarness();
    const query = 'native documentation';
    page.reads.setText(databaseFindViewId, query);
    final held = page.reads.hold(databaseFindCellStage);
    try {
      await page.mount(tester);
      await page.open(tester, hover: false);
      final field = find.descendant(
        of: find.byKey(const ValueKey('findTextField')),
        matching: find.byType(EditableText),
      );
      final element = tester.element(field);
      final state = tester.state<EditableTextState>(field);
      for (var i = 1; i <= query.length; i++) {
        expect(state.widget.focusNode.hasPrimaryFocus, isTrue);
        expect(tester.testTextInput.hasAnyClients, isTrue);
        if (i > 1) {
          expect(
            state.widget.controller.selection,
            TextSelection.collapsed(offset: i - 1),
          );
        }
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: query.substring(0, i),
            selection: TextSelection.collapsed(offset: i),
          ),
        );
        await tester.pump(
          i == 3
              ? DatabaseFindSession.debounce
              : const Duration(milliseconds: 20),
        );
        expect(tester.element(field), same(element));
        expect(tester.state(field), same(state));
        expect(state.widget.controller.text, query.substring(0, i));
      }
      await tester.pump(DatabaseFindSession.debounce);
      await tester.pump(const Duration(seconds: 3));
      expect(databaseFindSession(tester).status, DatabaseFindStatus.timedOut);
      held.complete();
      await tester.pump();
      await tester.pump(DatabaseFindSession.debounce);
      await databaseFindUntil(
        tester,
        () => !databaseFindSession(tester).loading,
      );
      expect(databaseFindBar(tester).matchCount, 1);
      expect(tester.element(field), same(element));
      expect(state.widget.focusNode.hasPrimaryFocus, isTrue);
      expect(
        state.widget.controller.selection,
        TextSelection.collapsed(offset: query.length),
      );
      expect(page.reads.maxInFlight, 1);
    } finally {
      await page.dispose(tester);
    }
  });

  testWidgets(
      'stopped title owner cancels retry and cannot restart from source events',
      (tester) async {
    final reads = DatabaseFindReads();
    reads.views[databaseFindViewId]!
      ..name = 'native documentation'
      ..parentViewId = 'workspace';
    final held = Completer<void>();
    reads.scheduler.schedule(Object(), () => true, () => held.future);
    final scope = StreamController<String>.broadcast(sync: true);
    final controller = WorkspaceTitleSearchController(
      provider: reads.provider(),
      scopeChanges: scope.stream,
      isWorkspaceCurrent: (_) => true,
    );
    try {
      controller.updateSource(
        workspaceId: 'workspace',
        cachedViews: {databaseFindViewId: reads.views[databaseFindViewId]!},
        excludedViewIds: [],
        ready: true,
      );
      controller.search('native', const CommandPaletteFilter(), []);
      await tester.pump(const Duration(seconds: 3));
      expect(controller.timedOut, isTrue);
      controller.stop();
      reads.changes.add('native');
      scope.add('folder');
      controller.updateSource(
        workspaceId: 'workspace',
        cachedViews: {databaseFindViewId: reads.views[databaseFindViewId]!},
        excludedViewIds: [],
        ready: true,
      );
      held.complete();
      await tester.pump(const Duration(seconds: 5));
      expect(reads.calls, isEmpty);
      expect(controller.results, isEmpty);
      expect(controller.searching, isFalse);
      expect(reads.scheduler.pendingCount, 0);
    } finally {
      if (!held.isCompleted) held.complete();
      controller.dispose();
      reads.dispose();
      unawaited(scope.close());
      await tester.pump();
    }
  });

  testWidgets(
      'newest database query recovers after occupied slot exceeds deadline',
      (tester) async {
    final reads = DatabaseFindReads()
      ..setText(databaseFindViewId, 'native documentation');
    final old = reads.hold(databaseFindCellStage);
    final session = DatabaseFindSession(
      viewId: databaseFindViewId,
      provider: reads.provider(),
      isOwnerActive: () => true,
    );
    try {
      session.search('nat', const FindOptions());
      await tester.pump(DatabaseFindSession.debounce);
      expect(reads.inFlight, 1);
      session.search('native documentation', const FindOptions());
      await tester.pump(DatabaseFindSession.debounce);
      await tester.pump(const Duration(seconds: 3));
      expect(session.status, DatabaseFindStatus.timedOut);
      expect(session.matches, isEmpty);
      old.complete();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      debugPrint(
        'SCROLL_SEARCH database recovery status=${session.status.name} hits=${session.matches.length} maxInFlight=${reads.maxInFlight}',
      );
      expect(session.query, 'native documentation');
      expect(session.status, DatabaseFindStatus.ready);
      expect(session.matches, hasLength(1));
      expect(reads.maxInFlight, 1);
      reads.allowed = false;
      reads.access.value++;
      expect(session.matches, isEmpty);
    } finally {
      session.dispose();
      reads.dispose();
      await tester.pump();
    }
  });

  testWidgets(
      'newest title query recovers when unrelated occupied slot finishes',
      (tester) async {
    final reads = DatabaseFindReads();
    reads.views[databaseFindViewId]!
      ..name = 'native documentation'
      ..parentViewId = 'workspace';
    final occupied = Completer<void>();
    reads.scheduler.schedule(Object(), () => true, () => occupied.future);
    final controller = WorkspaceTitleSearchController(
      provider: reads.provider(),
      isWorkspaceCurrent: (id) => id == 'workspace',
    );
    try {
      controller.updateSource(
        workspaceId: 'workspace',
        cachedViews: {databaseFindViewId: reads.views[databaseFindViewId]!},
        excludedViewIds: [],
        ready: true,
      );
      controller.search('nat', const CommandPaletteFilter(), []);
      await tester.pump();
      controller
          .search('native documentation', const CommandPaletteFilter(), []);
      await tester.pump(const Duration(seconds: 3));
      expect(controller.searching, isFalse);
      expect(controller.results, isEmpty);
      occupied.complete();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      debugPrint(
        'SCROLL_SEARCH title recovery hits=${controller.results.length} reads=${reads.calls.length}',
      );
      expect(controller.results, hasLength(1));
      expect(
        controller.canUseResult(databaseFindViewId, 'native documentation'),
        isTrue,
      );
    } finally {
      if (!occupied.isCompleted) occupied.complete();
      controller.dispose();
      reads.dispose();
      await tester.pump();
    }
  });
}
