import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/command_palette/workspace_content_search_controller.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_content_search_test_support.dart';

void main() {
  WorkspaceContentSearchController controllerFor(
    WorkspaceSearchReads reads, {
    WorkspaceContentSearchLimits limits = const WorkspaceContentSearchLimits(),
    Duration deadline = const Duration(seconds: 3),
    bool Function(String)? isCurrent,
  }) {
    final controller = WorkspaceContentSearchController(
      provider: reads.provider(deadline: deadline),
      limits: limits,
      isWorkspaceCurrent: isCurrent,
    )..updateSource(workspaceId: 'workspace', cachedViews: reads.views);
    addTearDown(controller.dispose);
    addTearDown(reads.dispose);
    return controller;
  }

  testWidgets('finds a title-nonmatching body across supplied pages',
      (tester) async {
    final reads = WorkspaceSearchReads();
    final page = reads.page('body-hit', 'Before the NeEdLe and after.');
    reads.page('title-only', 'Nothing relevant here.', name: 'Needle');
    reads.page('last-page', 'A second needle, beyond the first title result.');
    final original = reads.documents['body-hit']!.writeToBuffer();
    final controller = controllerFor(reads)..search('needle', enabled: true);

    await finishContentSearch(tester, controller);
    expect(controller.state.results.map((hit) => hit.view.id),
        ['body-hit', 'last-page']);
    expect(
        controller.state.results.first.snippet, 'Before the NeEdLe and after.');
    expect(controller.state.scannedPages, 3);
    expect(reads.counts['document:title-only'], 1);
    expect(reads.calls.take(5), [
      'view:body-hit',
      'preflight:body-hit',
      'document:body-hit',
      'view:body-hit',
      'preflight:body-hit',
    ]);
    expect(controller.state.results.first.view.isFrozen, isTrue);
    expect(page.isFrozen, isFalse);
    expect(reads.documents['body-hit']!.writeToBuffer(), original);
    expect(reads.forbidden, isEmpty);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'disabled, empty, whitespace and command queries perform no reads',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Needle');
    final controller = controllerFor(reads);
    controller.search('needle', enabled: false);
    await tester.pump(const Duration(seconds: 1));
    for (final query in ['', '  ', '> needle']) {
      controller.search(query, enabled: true);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.state.status, WorkspaceContentSearchStatus.idle);
    }
    expect(reads.calls, isEmpty);
    expect(reads.scheduler.pendingCount, 0);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets('debounces the actual latest input before starting I/O',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Final needle');
    final controller = controllerFor(reads)..search('wrong', enabled: true);
    await tester.pump(const Duration(milliseconds: 299));
    expect(reads.calls, isEmpty);
    controller.search('needle', enabled: true);
    expect(controller.state.results, isEmpty);
    await tester.pump(const Duration(milliseconds: 299));
    expect(reads.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await finishContentSearch(tester, controller);
    expect(reads.counts['document:page'], 1);
    expect(controller.state.query, 'needle');
    expect(controller.state.results.single.query, 'needle');
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets('superseded native read keeps its slot and cannot publish',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Old needle');
    final gate = reads.hold('document:page');
    final controller = controllerFor(reads)..search('old', enabled: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(reads.inFlight, 1);
    reads.documents['page'] = searchDocument('New answer');
    controller.search('answer', enabled: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(reads.counts['document:page'], 1);
    expect(reads.scheduler.pendingCount, 1);
    expect(controller.state.results, isEmpty);
    gate.complete();
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.snippet, 'New answer');
    expect(controller.state.query, 'answer');
    expect(reads.maximumInFlight, 1);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets('creator, layout and ancestor-space filters apply before reads',
      (tester) async {
    final reads = WorkspaceSearchReads();
    reads.folder('space');
    reads.folder('nested', parent: 'space');
    reads.page('mine', 'needle', parent: 'nested', creator: Int64(7));
    reads.page('other-author', 'needle', parent: 'space', creator: Int64(8));
    reads.page('other-space', 'needle', creator: Int64(7));
    reads.page('table', 'needle', parent: 'space', creator: Int64(7)).layout =
        ViewLayoutPB.Grid;
    final controller = controllerFor(reads)
      ..updateSource(
          workspaceId: 'workspace',
          cachedViews: reads.views,
          currentUserId: Int64(7))
      ..search(
        'needle',
        enabled: true,
        filter: CommandPaletteFilter(
          pageContents: true,
          createdByMe: true,
          spaceId: 'space',
          pageType: ViewLayoutPB.Document,
        ),
      );
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.view.id, 'mine');
    expect(reads.calls.where((call) => call.startsWith('document:')),
        ['document:mine']);
    expect(reads.calls.any((call) => call.contains('table')), isFalse);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets('access revocation immediately removes completed snippets',
      (tester) async {
    final reads = WorkspaceSearchReads()
      ..page('page', 'Needle private context');
    final controller = controllerFor(reads)..search('needle', enabled: true);
    await finishContentSearch(tester, controller);
    expect(controller.canUseResult('page', 'needle'), isTrue);
    reads.allowed = false;
    reads.access.value++;
    expect(controller.state.results, isEmpty);
    expect(controller.canUseResult('page', 'needle'), isFalse);
    await finishContentSearch(tester, controller);
    expect(controller.state.status, WorkspaceContentSearchStatus.partial);
    expect(controller.state.results, isEmpty);
    expect(reads.counts['document:page'], 1);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets('postflight permission denial cannot publish an in-flight hit',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Needle');
    final gate = reads.hold('document:page');
    final controller = controllerFor(reads)..search('needle', enabled: true);
    await tester.pump(const Duration(milliseconds: 300));
    reads.allowed = false; // No notification: postflight must still catch it.
    gate.complete();
    await finishContentSearch(tester, controller);
    expect(controller.state.results, isEmpty);
    expect(controller.state.unavailablePages, 1);
    expect(reads.counts['preflight:page'], 2);
    await disposeContentSearch(tester, controller, reads);
  });

  for (final wrongAt in [1, 2]) {
    testWidgets('rejects wrong view ID at authorization pass $wrongAt',
        (tester) async {
      final reads = WorkspaceSearchReads()..page('page', 'Needle');
      reads.viewResult = (id, pass) => pass == wrongAt
          ? ViewPB(id: 'wrong-view', parentViewId: 'workspace')
          : reads.views[id];
      final controller = controllerFor(reads)..search('needle', enabled: true);
      await finishContentSearch(tester, controller);
      expect(controller.state.results, isEmpty);
      expect(controller.state.status, WorkspaceContentSearchStatus.partial);
      expect(reads.counts['document:page'] ?? 0, wrongAt == 1 ? 0 : 1);
      await disposeContentSearch(tester, controller, reads);
    });
  }

  testWidgets(
      'mutable PB/source changes do not mutate or relabel a pending snapshot',
      (tester) async {
    final reads = WorkspaceSearchReads();
    final view = reads.page('page', 'Needle');
    final gate = reads.hold('preflight:page');
    final controller = controllerFor(reads)..search('needle', enabled: true);
    await tester.pump(const Duration(milliseconds: 300));
    final snapshot = reads.preflightViews.single;
    view.name = 'Changed name';
    view.extra = '{"source_revision":2}';
    expect(snapshot.name, 'Project notes');
    expect(snapshot.extra, isEmpty);
    expect(() => snapshot.name = 'mutated', throwsUnsupportedError);
    gate.complete();
    await finishContentSearch(tester, controller);
    expect(controller.state.results, isEmpty);
    controller.updateSource(workspaceId: 'workspace', cachedViews: reads.views);
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.view.name, 'Changed name');
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets('source notification clears old text before the debounce',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Old needle');
    final controller = controllerFor(reads)..search('needle', enabled: true);
    await finishContentSearch(tester, controller);
    reads.documents['page'] = searchDocument('New needle');
    reads.changes.add('page');
    expect(controller.state.results, isEmpty);
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.snippet, 'New needle');
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'workspace switch rejects old completions and old cached membership',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('old', 'Old needle');
    var workspace = 'workspace';
    final gate = reads.hold('document:old');
    final controller = controllerFor(reads, isCurrent: (id) => workspace == id)
      ..search('needle', enabled: true);
    await tester.pump(const Duration(milliseconds: 300));
    workspace = 'new-workspace';
    reads.page('new', 'New needle', parent: workspace);
    controller.updateSource(workspaceId: workspace, cachedViews: reads.views);
    expect(controller.state.results, isEmpty);
    gate.complete();
    await finishContentSearch(tester, controller);
    expect(controller.state.results.map((hit) => hit.view.id), ['new']);
    expect(reads.counts['document:old'], 1);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'close/reopen shares the occupied slot until the underlying read finishes',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Needle');
    final gate = reads.hold('document:page');
    final first = controllerFor(reads)..search('needle', enabled: true);
    await tester.pump(const Duration(milliseconds: 300));
    var notifications = 0;
    first.addListener(() => notifications++);
    first.dispose();
    final second = controllerFor(reads)..search('needle', enabled: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(reads.counts['document:page'], 1);
    expect(reads.scheduler.pendingCount, 1);
    gate.complete();
    await finishContentSearch(tester, second);
    expect(first.state.results, isEmpty);
    expect(notifications, 0);
    expect(second.state.results, hasLength(1));
    expect(reads.maximumInFlight, 1);
    await disposeContentSearch(tester, second, reads);
  });

  testWidgets(
      'per-read deadline reports partial coverage without releasing the native slot',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Needle');
    final gate = reads.hold('document:page');
    final controller =
        controllerFor(reads, deadline: const Duration(milliseconds: 20))
          ..search('needle', enabled: true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 20));
    expect(controller.state.timedOut, isTrue);
    expect(controller.state.status, WorkspaceContentSearchStatus.partial);
    expect(controller.state.results, isEmpty);
    expect(reads.inFlight, 1);
    expect(reads.scheduler.pendingCount, 0);
    var anotherOwnerRan = false;
    reads.scheduler.schedule(Object(), () => true, () async {
      anotherOwnerRan = true;
    });
    await tester.pump();
    expect(anotherOwnerRan, isFalse);
    gate.complete();
    await tester.pump();
    expect(anotherOwnerRan, isTrue);
    expect(controller.state.results, isEmpty);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'allows cancellation between pages and serves another scheduler owner',
      (tester) async {
    final reads = WorkspaceSearchReads()
      ..page('first', 'Needle')
      ..page('second', 'Needle');
    final controller = controllerFor(reads);
    var anotherOwnerRan = false;
    controller.addListener(() {
      if (controller.state.scannedPages == 1 && controller.state.isSearching) {
        controller.stop();
        reads.scheduler.schedule(Object(), () => true, () async {
          anotherOwnerRan = true;
        });
      }
    });
    controller.search('needle', enabled: true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(anotherOwnerRan, isTrue);
    expect(reads.counts['document:second'], isNull);
    expect(controller.state.results, isEmpty);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'excludes trash ancestry, protected/malformed roots, folders and cyclic parents',
      (tester) async {
    final reads = WorkspaceSearchReads();
    reads.folder('trash-folder');
    reads.page('trashed-child', 'Needle', parent: 'trash-folder');
    reads.page('protected', 'Needle').extra = '{"appflowy_encryption":{}}';
    reads.page('malformed', 'Needle').extra = '[bad json';
    reads.page('bad-file', 'Needle').extra =
        '{"appflowy_workspace_item":{"version":999}}';
    reads.page('invalid-id\n', 'Needle');
    reads.page('invalid-date', 'Needle').lastEdited = Int64.MAX_VALUE;
    reads.page('cycle-a', 'Needle', parent: 'cycle-b');
    reads.page('cycle-b', 'Needle', parent: 'cycle-a');
    reads.page('missing-parent', 'Needle', parent: 'not-cached');
    final good = reads.page('good', 'Needle');
    // childViews is neither authority to crawl nor a recursive snapshot input.
    good.childViews.add(good);
    final controller = controllerFor(reads)
      ..updateSource(
        workspaceId: 'workspace',
        cachedViews: reads.views,
        excludedViewIds: ['trash-folder'],
      )
      ..search('needle', enabled: true);
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.view.id, 'good');
    expect(controller.state.results.single.view.childViews, isEmpty);
    expect(good.childViews.single, same(good));
    expect(reads.calls.where((call) => call.startsWith('document:')),
        ['document:good']);
    reads.folder('workspace', parent: '').extra =
        '{"appflowy_encryption":{"version":999}}';
    controller.updateSource(workspaceId: 'workspace', cachedViews: reads.views);
    expect(controller.state.results, isEmpty);
    await finishContentSearch(tester, controller);
    expect(controller.state.results, isEmpty);
    expect(reads.counts['document:good'], 1);
    await disposeContentSearch(tester, controller, reads);
  });

  for (final (label, limits) in [
    ('pages', const WorkspaceContentSearchLimits(maxPages: 1)),
    ('results', const WorkspaceContentSearchLimits(maxResults: 1)),
    ('snapshots', const WorkspaceContentSearchLimits(maxCachedViews: 1)),
  ]) {
    testWidgets('bounded $label coverage', (tester) async {
      final reads = WorkspaceSearchReads()
        ..page('first', 'Needle')
        ..page('second', 'Needle');
      final controller = controllerFor(reads, limits: limits)
        ..search('needle', enabled: true);
      await finishContentSearch(tester, controller);
      expect(controller.state.results, hasLength(1));
      expect(controller.state.truncated, isTrue);
      expect(controller.state.status, WorkspaceContentSearchStatus.partial);
      expect(reads.counts['document:second'], isNull);
      await disposeContentSearch(tester, controller, reads);
    });
  }

  testWidgets(
      'UTF-8 bytes rather than code units bound aggregate retained text',
      (tester) async {
    final reads = WorkspaceSearchReads()
      ..page('first', 'éé')
      ..page('second', 'éé');
    final controller = controllerFor(reads,
        limits: const WorkspaceContentSearchLimits(maxBytes: 5))
      ..search('é', enabled: true);
    await finishContentSearch(tester, controller);
    expect(controller.state.scannedBytes, 4);
    expect(controller.state.results, hasLength(1));
    expect(controller.state.truncated, isTrue);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'oversized page and query fail bounded without a false no-results claim',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'needle ${'é' * 20}');
    final controller = controllerFor(
      reads,
      limits: const WorkspaceContentSearchLimits(
          page: DocumentFindLimits(maxBytes: 16)),
    )..search('needle', enabled: true);
    await finishContentSearch(tester, controller);
    expect(controller.state.results, isEmpty);
    expect(controller.state.status, WorkspaceContentSearchStatus.partial);
    final count = reads.calls.length;
    controller.search('x' * 257, enabled: true);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.state.status, WorkspaceContentSearchStatus.queryTooLong);
    expect(reads.calls.length, count);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'searches safe local UTF-8 only; PDF, Office, binary and arbitrary paths stay unclaimed',
      (tester) async {
    final reads = WorkspaceSearchReads()
      ..file('safe', 'notes.txt', utf8.encode('Café Needle'))
      ..file('pdf', 'notes.pdf', utf8.encode('Needle'))
      ..file('office', 'notes.docx', utf8.encode('Needle'))
      ..file('binary', 'binary.txt', [0, 1, 2])
      ..file('invalid', 'invalid.txt', [0xC3, 0x28])
      ..file('outside', 'outside.txt', utf8.encode('Needle'),
          source: '/arbitrary/notes.txt')
      ..file('remote', 'remote.txt', utf8.encode('Needle'),
          source: 'https://invalid.example/notes.txt');
    final controller = controllerFor(reads)..search('needle', enabled: true);
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.view.id, 'safe');
    expect(controller.state.results.single.snippet, 'Café Needle');
    expect(controller.state.status, WorkspaceContentSearchStatus.partial);
    expect(reads.files.calls.where((call) => call == 'bytes'), hasLength(3));
    expect(reads.calls.any((call) => call.startsWith('document:')), isFalse);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'does not search serialized metadata, dashboard/canvas configs or follow references',
      (tester) async {
    final reads = WorkspaceSearchReads();
    reads.page('metadata', 'Boring').extra = '{"credentials":"Needle"}';
    reads.page('dashboard', 'Needle').extra =
        '{"appflowy_dashboard":{"text":"Needle"}}';
    reads.page('canvas', 'Needle').extra =
        '{"appflowy_canvas":{"text":"Needle"}}';
    reads.page('referencing', 'Needle', blocks: [
      Node(type: 'page_preview', attributes: {'view_id': 'not-supplied'}),
      Node(
          type: 'file',
          attributes: {'name': 'private.txt', 'url': '/arbitrary/private.txt'}),
    ]);
    final controller = controllerFor(reads)..search('needle', enabled: true);
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.view.id, 'referencing');
    expect(controller.state.coverageUnknown, isTrue);
    expect(reads.calls.any((call) => call.contains('not-supplied')), isFalse);
    expect(reads.counts['document:dashboard'], isNull);
    expect(reads.counts['document:canvas'], isNull);
    expect(reads.files.calls, isEmpty);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets('uses the real spreadsheet displayed-value reader',
      (tester) async {
    final reads = WorkspaceSearchReads();
    reads.page('sheet', '', blocks: [
      Node(
        type: 'spreadsheet',
        attributes: {
          'data': SpreadsheetData.fromRows([
            ['Status'],
            ['Needle ready']
          ]).toJson()
        },
      ),
    ]);
    final controller = controllerFor(reads)..search('needle', enabled: true);
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.snippet, 'Needle ready');
    expect(controller.state.results.single.location, contains('Cell'));
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'timeout notification cannot cancel a query started by its listener',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Old needle');
    final gate = reads.hold('document:page');
    final controller =
        controllerFor(reads, deadline: const Duration(milliseconds: 20));
    var restarted = false;
    controller.addListener(() {
      if (controller.state.timedOut && !restarted) {
        restarted = true;
        reads.documents['page'] = searchDocument('New answer');
        controller.search('answer', enabled: true);
      }
    });
    controller.search('needle', enabled: true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 20));
    expect(restarted, isTrue);
    expect(controller.state.query, 'answer');
    gate.complete();
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.snippet, 'New answer');
    expect(controller.state.timedOut, isFalse);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'an oversized exclusion list fails closed even with duplicate IDs',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Needle');
    final controller = controllerFor(reads,
        limits: const WorkspaceContentSearchLimits(maxCachedViews: 2))
      ..updateSource(
        workspaceId: 'workspace',
        cachedViews: reads.views,
        excludedViewIds: ['other', 'other', 'other', 'page'],
      )
      ..search('needle', enabled: true);
    await tester.pump(const Duration(seconds: 1));
    expect(
        controller.state.status, WorkspaceContentSearchStatus.waitingForSource);
    expect(controller.state.results, isEmpty);
    expect(reads.calls, isEmpty);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets('a source still loading is not a completed empty search',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Needle');
    final controller = controllerFor(reads)
      ..updateSource(
          workspaceId: 'workspace', cachedViews: reads.views, ready: false)
      ..search('needle', enabled: true);
    await tester.pump(const Duration(seconds: 1));
    expect(
        controller.state.status, WorkspaceContentSearchStatus.waitingForSource);
    expect(reads.calls, isEmpty);
    controller.updateSource(workspaceId: 'workspace', cachedViews: reads.views);
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.view.id, 'page');
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets('read failures report partial coverage, not complete no matches',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', 'Needle');
    reads.failures.add('document:page');
    final controller = controllerFor(reads)..search('needle', enabled: true);
    await finishContentSearch(tester, controller);
    expect(controller.state.status, WorkspaceContentSearchStatus.partial);
    expect(controller.state.results, isEmpty);
    expect(controller.state.unavailablePages, 1);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets('a readable empty document completes with zero matches',
      (tester) async {
    final reads = WorkspaceSearchReads()..page('page', '');
    final controller = controllerFor(reads)..search('needle', enabled: true);
    await finishContentSearch(tester, controller);
    expect(controller.state.status, WorkspaceContentSearchStatus.complete);
    expect(controller.state.results, isEmpty);
    expect(controller.state.scannedBytes, 0);
    await disposeContentSearch(tester, controller, reads);
  });

  testWidgets(
      'typed table values use the current view without exports or plugin mounting',
      (tester) async {
    final reads = WorkspaceSearchReads();
    reads.page('table', '', name: 'Planning').layout = ViewLayoutPB.Grid;
    reads.fields['table'] = [
      FieldPB(id: 'text', name: 'Notes', fieldType: FieldType.RichText)
    ];
    reads.rows['table'] = [RowMetaPB(id: 'visible')];
    reads.cells[('table', 'visible', 'text')] = CellPB(
      rowId: 'visible',
      fieldId: 'text',
      fieldType: FieldType.RichText,
      data: utf8.encode('A Needle cell'),
    );
    final controller = controllerFor(reads)..search('needle', enabled: true);
    await finishContentSearch(tester, controller);
    expect(controller.state.results.single.snippet, 'A Needle cell');
    expect(controller.state.coverageUnknown, isTrue);
    expect(reads.counts['document:table'], isNull);
    expect(reads.counts['cell:table:visible:text'], 1);
    expect(reads.forbidden, isEmpty);
    await disposeContentSearch(tester, controller, reads);
  });

  group('literal excerpts and scope consistency', () {
    test('preserves original case, centers the first match and adds ellipses',
        () {
      final text = '${'before ' * 100}NeEdLe ${'after ' * 100}';
      final snippet = workspaceContentSearchExcerpt(text, 'needle')!;
      expect(snippet, startsWith('…'));
      expect(snippet, endsWith('…'));
      expect(snippet, contains('NeEdLe'));
      expect(snippet.length, lessThanOrEqualTo(324));
      expect(snippet.indexOf('NeEdLe'), lessThanOrEqualTo(81));
    });

    test('regex syntax is literal, and empty queries have no excerpt', () {
      expect(workspaceContentSearchExcerpt('a [.*] b', '[.*]'), 'a [.*] b');
      expect(workspaceContentSearchExcerpt('anything', '[.*]'), isNull);
      expect(workspaceContentSearchExcerpt('Needle', ''), isNull);
      expect(workspaceContentSearchExcerpt('Needle', '  '), isNull);
      expect(workspaceContentSearchExcerpt('', 'needle'), isNull);
      expect(workspaceContentSearchExcerpt('Needle', 'needle'), 'Needle');
    });

    test('clipping does not create broken surrogate pairs', () {
      final text = '${'😀' * 200}Needle${'😀' * 200}';
      final snippet = workspaceContentSearchExcerpt(text, 'needle')!;
      expect(utf8.decode(utf8.encode(snippet)), snippet);
      expect(snippet, contains('Needle'));
    });

    test('Page contents and Title only remain mutually exclusive', () {
      const defaults = CommandPaletteFilter();
      expect(defaults.pageContents, isFalse);
      expect(defaults.isActive, isFalse);
      final contents =
          defaults.copyWith(titleOnly: true).copyWith(pageContents: true);
      expect(contents.pageContents, isTrue);
      expect(contents.titleOnly, isFalse);
      final titles = contents.copyWith(titleOnly: true);
      expect(titles.pageContents, isFalse);
      expect(titles.titleOnly, isTrue);
      expect(
          const CommandPaletteFilter(titleOnly: true, pageContents: true)
              .titleOnly,
          isFalse);
    });
  });
}
