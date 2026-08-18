import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart'
    show Document, Node, pageNode, paragraphNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

PageVersion _version({
  required String id,
  required DateTime createdAt,
  PageVersionKind kind = PageVersionKind.automatic,
  String hash = 'hash',
  String name = '',
}) =>
    PageVersion(
      id: id,
      viewId: 'page',
      createdAt: createdAt,
      kind: kind,
      contentHash: hash,
      name: name,
    );

Document _documentOf(List<String> lines) {
  final root = Node(
    type: 'page',
    children: [for (final line in lines) paragraphNode(text: line)],
  );
  return Document(root: root);
}

void main() {
  final now = DateTime.utc(2026, 8, 16, 12);

  group('what a page fingerprint says', () {
    test('the same page reads as the same version', () {
      final first = _documentOf(['Alpha', 'Beta']).toJson();
      final second = _documentOf(['Alpha', 'Beta']).toJson();
      expect(
        pageContentFingerprint(first),
        pageContentFingerprint(second),
      );
    });

    test('a changed page reads as a different version', () {
      expect(
        pageContentFingerprint(_documentOf(['Alpha']).toJson()),
        isNot(pageContentFingerprint(_documentOf(['Alpha!']).toJson())),
      );
    });
  });

  group('what a page version says about itself', () {
    test('a version round trips through its stored form', () {
      final version = PageVersion(
        id: 'v1',
        viewId: 'page',
        createdAt: now,
        kind: PageVersionKind.manual,
        contentHash: 'abc',
        name: 'First draft',
        pageName: 'Notes',
        blockCount: 4,
        wordCount: 12,
        characterCount: 64,
        bytes: 900,
        excerpt: 'Alpha',
      );

      final read = PageVersion.fromJson(version.toJson());

      expect(read, version);
      expect(read.blockCount, 4);
      expect(read.wordCount, 12);
      expect(read.pageName, 'Notes');
      expect(read.createdAt.isUtc, isTrue);
    });

    test('a policy round trips through its stored form', () {
      const policy = PageVersionPolicy(
        captureAutomatically: false,
        keepEveryVersion: true,
        maximumCopies: 12,
        retainedDays: 0,
        quietPeriod: Duration(seconds: 30),
        minimumSpacing: Duration(hours: 6),
      );

      expect(PageVersionPolicy.fromJson(policy.toJson()), policy);
    });
  });

  group('what a page remembers of itself', () {
    test('counts what is on the page and opens with its words', () {
      final summary = summarizePageDocument(
        _documentOf(['Alpha beta', 'Gamma', '']),
      );

      expect(summary.blockCount, 3);
      expect(summary.wordCount, 3);
      expect(summary.characterCount, 'Alpha beta'.length + 'Gamma'.length);
      expect(summary.excerpt, 'Alpha beta · Gamma');
    });

    test('an empty page reports nothing rather than throwing', () {
      final summary = summarizePageDocument(Document.blank());

      expect(summary.blockCount, 0);
      expect(summary.wordCount, 0);
      expect(summary.excerpt, isEmpty);
    });
  });

  group('when a version is worth taking', () {
    test('the first version of a page is always worth taking', () {
      expect(
        shouldCapturePageVersion(
          policy: const PageVersionPolicy(),
          contentHash: 'a',
          existing: const [],
          now: now,
        ),
        isTrue,
      );
    });

    test('a page that has not changed is not copied again', () {
      expect(
        shouldCapturePageVersion(
          policy: const PageVersionPolicy(),
          contentHash: 'a',
          existing: [
            _version(
              id: 'v1',
              createdAt: now.subtract(const Duration(days: 3)),
              hash: 'a',
            ),
          ],
          now: now,
        ),
        isFalse,
      );
    });

    test('a copy taken a moment ago holds the next one back', () {
      expect(
        shouldCapturePageVersion(
          policy: const PageVersionPolicy(
            minimumSpacing: Duration(minutes: 30),
          ),
          contentHash: 'b',
          existing: [
            _version(
              id: 'v1',
              createdAt: now.subtract(const Duration(minutes: 2)),
              hash: 'a',
            ),
          ],
          now: now,
        ),
        isFalse,
      );
    });

    test('asking for a version ignores the spacing but not sameness', () {
      final existing = [
        _version(
          id: 'v1',
          createdAt: now.subtract(const Duration(minutes: 2)),
          hash: 'a',
        ),
      ];

      expect(
        shouldCapturePageVersion(
          policy: const PageVersionPolicy(
            minimumSpacing: Duration(minutes: 30),
          ),
          contentHash: 'b',
          existing: existing,
          now: now,
          manual: true,
        ),
        isTrue,
      );
      expect(
        shouldCapturePageVersion(
          policy: const PageVersionPolicy(
            minimumSpacing: Duration(minutes: 30),
          ),
          contentHash: 'a',
          existing: existing,
          now: now,
          manual: true,
        ),
        isFalse,
      );
    });

    test('turning automatic copies off stops them, not the asked-for ones', () {
      const policy = PageVersionPolicy(captureAutomatically: false);

      expect(
        shouldCapturePageVersion(
          policy: policy,
          contentHash: 'a',
          existing: const [],
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldCapturePageVersion(
          policy: policy,
          contentHash: 'a',
          existing: const [],
          now: now,
          manual: true,
        ),
        isTrue,
      );
    });
  });

  group('what a retention policy sweeps away', () {
    List<PageVersion> automatic(int count) => [
          for (var index = 0; index < count; index++)
            _version(
              id: 'v$index',
              createdAt: now.subtract(Duration(hours: index)),
              hash: 'h$index',
            ),
        ];

    test('keeping every version sweeps nothing', () {
      expect(
        expiredPageVersions(
          automatic(50),
          const PageVersionPolicy(keepEveryVersion: true),
          now: now,
        ),
        isEmpty,
      );
    });

    test('only the copies past the count are swept', () {
      final expired = expiredPageVersions(
        automatic(8),
        const PageVersionPolicy(maximumCopies: 5, retainedDays: 0),
        now: now,
      );

      expect(expired.map((version) => version.id), ['v5', 'v6', 'v7']);
    });

    test('the newest copy is kept even when the count is one', () {
      final expired = expiredPageVersions(
        automatic(3),
        const PageVersionPolicy(maximumCopies: 1, retainedDays: 0),
        now: now,
      );

      expect(expired.map((version) => version.id), ['v1', 'v2']);
    });

    test('copies older than the window are swept', () {
      final versions = [
        _version(id: 'new', createdAt: now.subtract(const Duration(hours: 1))),
        _version(id: 'old', createdAt: now.subtract(const Duration(days: 40))),
        _version(id: 'mid', createdAt: now.subtract(const Duration(days: 3))),
      ];

      final expired = expiredPageVersions(
        versions,
        const PageVersionPolicy(maximumCopies: 100, retainedDays: 14),
        now: now,
      );

      expect(expired.map((version) => version.id), ['old']);
    });

    test('a named version and a restore point are never swept', () {
      final versions = [
        _version(id: 'new', createdAt: now),
        _version(
          id: 'named',
          createdAt: now.subtract(const Duration(days: 400)),
          kind: PageVersionKind.manual,
          name: 'First draft',
        ),
        _version(
          id: 'before',
          createdAt: now.subtract(const Duration(days: 400)),
          kind: PageVersionKind.restorePoint,
        ),
        _version(
          id: 'stale',
          createdAt: now.subtract(const Duration(days: 400)),
        ),
      ];

      final expired = expiredPageVersions(
        versions,
        const PageVersionPolicy(maximumCopies: 2, retainedDays: 14),
        now: now,
      );

      expect(expired.map((version) => version.id), ['stale']);
    });

    test('copies past the room they are allowed are swept', () {
      final versions = [
        for (var index = 0; index < 5; index++)
          PageVersion(
            id: 'v$index',
            viewId: 'page',
            createdAt: now.subtract(Duration(hours: index)),
            kind: PageVersionKind.automatic,
            contentHash: 'h$index',
            bytes: 400,
          ),
      ];

      final expired = expiredPageVersions(
        versions,
        const PageVersionPolicy(
          maximumCopies: 100,
          retainedDays: 0,
          maximumPageBytes: 1000,
        ),
        now: now,
      );

      // 400 for the newest, 400 for the one behind it, and no room for more.
      expect(expired.map((version) => version.id), ['v2', 'v3', 'v4']);
    });

    test('a version that is kept for ever still counts against the room', () {
      final versions = [
        PageVersion(
          id: 'new',
          viewId: 'page',
          createdAt: now,
          kind: PageVersionKind.automatic,
          contentHash: 'a',
          bytes: 400,
        ),
        PageVersion(
          id: 'named',
          viewId: 'page',
          createdAt: now.subtract(const Duration(hours: 1)),
          kind: PageVersionKind.manual,
          contentHash: 'b',
          name: 'Draft',
          bytes: 500,
        ),
        PageVersion(
          id: 'old',
          viewId: 'page',
          createdAt: now.subtract(const Duration(hours: 2)),
          kind: PageVersionKind.automatic,
          contentHash: 'c',
          bytes: 400,
        ),
      ];

      final expired = expiredPageVersions(
        versions,
        const PageVersionPolicy(
          maximumCopies: 100,
          retainedDays: 0,
          maximumPageBytes: 1000,
        ),
        now: now,
      );

      expect(expired.map((version) => version.id), ['old']);
    });
  });

  group('what the rules for taking a copy say', () {
    test('a policy with every rule set round trips', () {
      const policy = PageVersionPolicy(
        captureAutomatically: false,
        captureOnOpen: false,
        captureOnClose: false,
        keepEveryVersion: true,
        maximumCopies: 12,
        retainedDays: 0,
        quietPeriod: Duration(seconds: 30),
        minimumSpacing: Duration(hours: 6),
        captureInterval: Duration(minutes: 15),
        maximumPageBytes: 10 * PageVersionPolicy.megabyte,
        maximumTotalBytes: 0,
        maximumFileBytes: 0,
      );

      expect(PageVersionPolicy.fromJson(policy.toJson()), policy);
    });

    test('a copy on a clock is off until an interval is chosen', () {
      expect(const PageVersionPolicy().capturesPeriodically, isFalse);
      expect(
        const PageVersionPolicy(
          captureInterval: Duration(minutes: 5),
        ).capturesPeriodically,
        isTrue,
      );
      expect(
        const PageVersionPolicy(
          captureAutomatically: false,
          captureInterval: Duration(minutes: 5),
        ).capturesPeriodically,
        isFalse,
      );
    });
  });

  group('what kind of history a view keeps', () {
    ViewPB viewOf(ViewLayoutPB layout, {String extra = ''}) =>
        ViewPB(id: 'v', layout: layout, extra: extra);

    test('a table and every reading built on one keeps its rows', () {
      for (final layout in [
        ViewLayoutPB.Grid,
        ViewLayoutPB.Board,
        ViewLayoutPB.Calendar,
      ]) {
        expect(
          pageVersionShapeOf(viewOf(layout)),
          PageVersionShape.database,
          reason: '$layout',
        );
      }
    });

    test('a written page keeps its blocks', () {
      expect(
        pageVersionShapeOf(viewOf(ViewLayoutPB.Document)),
        PageVersionShape.document,
      );
    });

    test('a chat keeps only what it says about itself', () {
      expect(
        pageVersionShapeOf(viewOf(ViewLayoutPB.Chat)),
        PageVersionShape.settings,
      );
    });

    test('a workspace file keeps its bytes', () {
      final extra = const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: 'C:/notes.md',
      ).mergeIntoExtra('');
      expect(
        pageVersionShapeOf(viewOf(ViewLayoutPB.Document, extra: extra)),
        PageVersionShape.file,
      );
    });

    test('a folder keeps what was in it', () {
      final extra = const WorkspaceItemMetadata.folder().mergeIntoExtra('');
      expect(
        pageVersionShapeOf(viewOf(ViewLayoutPB.Document, extra: extra)),
        PageVersionShape.container,
      );
    });

    test('a canvas and a dashboard keep their arrangement, not blank blocks',
        () {
      for (final envelope in ['appflowy_canvas', 'appflowy_dashboard']) {
        final extra = jsonEncode({
          envelope: {'version': 1},
        });
        expect(
          pageVersionShapeOf(viewOf(ViewLayoutPB.Document, extra: extra)),
          PageVersionShape.board,
          reason: envelope,
        );
      }
    });
  });

  group('what one version holds', () {
    const settings = PageVersionViewSettings(
      name: 'Tasks',
      extra: '{"appflowy_chart":{}}',
    );

    test('a table survives being written down and read back', () {
      const table = PageVersionTable(
        columns: [
          PageVersionColumn(id: 'a', name: 'Name'),
          PageVersionColumn(id: 'b', name: 'Where'),
        ],
        rows: [
          PageVersionRow(id: 'r1', cells: {'a': 'Alpha', 'b': 'London'}),
        ],
      );
      const payload = PageVersionPayload(
        shape: PageVersionShape.database,
        settings: settings,
        table: table,
      );

      final read = PageVersionPayload.fromJson(payload.toJson());

      expect(read.shape, PageVersionShape.database);
      expect(read.settings.extra, settings.extra);
      expect(
        read.table!.columns.map((column) => column.name),
        ['Name', 'Where'],
      );
      expect(read.table!.rows.single.cells['b'], 'London');
    });

    test('a column remembers its type, so a stored cell can be drawn', () {
      const table = PageVersionTable(
        columns: [
          PageVersionColumn(id: 'a', name: 'Name', isPrimary: true),
          PageVersionColumn(id: 'b', name: 'Done', fieldType: 4),
        ],
        rows: [
          PageVersionRow(id: 'r1', cells: {'a': 'Alpha', 'b': 'Yes'}),
        ],
      );

      final read = PageVersionTable.fromJson(table.toJson());

      expect(read.columns.first.isPrimary, isTrue);
      expect(read.columns.first.fieldType, 0);
      expect(read.columns.last.isPrimary, isFalse);
      expect(read.columns.last.fieldType, 4);
    });

    test('a row carries the page behind it, not only its cells', () {
      final table = PageVersionTable(
        columns: const [PageVersionColumn(id: 'a', name: 'Name')],
        rows: [
          PageVersionRow(
            id: 'r1',
            cells: const {'a': 'Alpha'},
            documentId: 'doc-1',
            document: Document(
              root: pageNode(children: [paragraphNode(text: 'Inside')]),
            ).toJson(),
          ),
          const PageVersionRow(id: 'r2', cells: {'a': 'Beta'}),
        ],
      );

      final read = PageVersionTable.fromJson(table.toJson());

      expect(read.rows.first.documentId, 'doc-1');
      expect(
        Document.fromJson(
          Map<String, dynamic>.from(read.rows.first.document!),
        ).root.children.first.delta!.toPlainText(),
        'Inside',
      );
      expect(read.rows.last.document, isNull);
      expect(read.rows.last.documentId, isEmpty);
    });

    test('a table is written out as delimited text, quotes and all', () {
      const table = PageVersionTable(
        columns: [
          PageVersionColumn(id: 'a', name: 'Name'),
          PageVersionColumn(id: 'b', name: 'Note'),
        ],
        rows: [
          PageVersionRow(id: 'r1', cells: {'a': 'Alpha', 'b': 'one, two'}),
          PageVersionRow(id: 'r2', cells: {'a': 'Beta'}),
        ],
      );

      expect(
        table.toCsv(),
        'Name,Note\nAlpha,"one, two"\nBeta,',
      );
    });

    test('a folder listing survives being written down and read back', () {
      const payload = PageVersionPayload(
        shape: PageVersionShape.container,
        settings: settings,
        children: [
          PageVersionChild(id: 'a', name: 'Notes', layout: 0),
          PageVersionChild(id: 'b', name: 'Photos', layout: 0, isFolder: true),
        ],
      );

      final read = PageVersionPayload.fromJson(payload.toJson());

      expect(read.children!.map((child) => child.name), ['Notes', 'Photos']);
      expect(read.children!.last.isFolder, isTrue);
    });

    test('a version written before other kinds existed still reads', () {
      final legacy = _documentOf(['Alpha']).toJson();

      final read = PageVersionPayload.fromJson(legacy);

      expect(read.shape, PageVersionShape.document);
      expect(read.editorDocument, isNotNull);
    });
  });

  group('what a version row says it holds', () {
    test('a table counts its rows and its columns', () {
      const payload = PageVersionPayload(
        shape: PageVersionShape.database,
        settings: PageVersionViewSettings(name: 'Tasks', extra: ''),
        table: PageVersionTable(
          columns: [
            PageVersionColumn(id: 'a', name: 'Name'),
            PageVersionColumn(id: 'b', name: 'Where'),
          ],
          rows: [
            PageVersionRow(id: 'r1', cells: {'a': 'Alpha'}),
            PageVersionRow(id: 'r2', cells: {'a': 'Beta'}),
          ],
        ),
      );

      final summary = summarizeCapturedPage(payload);

      expect(summary.blockCount, 2);
      expect(summary.wordCount, 2);
      expect(summary.excerpt, 'Name · Where');
    });

    test('a folder counts what was in it', () {
      const payload = PageVersionPayload(
        shape: PageVersionShape.container,
        settings: PageVersionViewSettings(name: 'Trip', extra: ''),
        children: [
          PageVersionChild(id: 'a', name: 'Notes', layout: 0),
          PageVersionChild(id: 'b', name: 'Photos', layout: 0, isFolder: true),
        ],
      );

      final summary = summarizeCapturedPage(payload);

      expect(summary.blockCount, 2);
      expect(summary.wordCount, 1);
      expect(summary.excerpt, 'Notes · Photos');
    });

    test('a file counts its size and names itself', () {
      const payload = PageVersionPayload(
        shape: PageVersionShape.file,
        settings: PageVersionViewSettings(name: 'Notes', extra: ''),
        file: PageVersionFile(
          name: 'notes.md',
          extension: 'md',
          bytes: 2048,
        ),
      );

      final summary = summarizeCapturedPage(payload);

      expect(summary.characterCount, 2048);
      expect(summary.excerpt, 'notes.md');
    });

    test('a file too big to copy still says what it was', () {
      const payload = PageVersionPayload(
        shape: PageVersionShape.file,
        settings: PageVersionViewSettings(name: 'Clip', extra: ''),
        file: PageVersionFile(
          name: 'clip.mp4',
          extension: 'mp4',
          bytes: 900000000,
          stored: false,
        ),
      );

      final read = PageVersionPayload.fromJson(payload.toJson());

      expect(read.file!.stored, isFalse);
      expect(read.file!.bytes, 900000000);
      expect(summarizeCapturedPage(read).excerpt, 'clip.mp4');
    });
  });

  group('what is written to disk', () {
    late Directory root;
    late PageVersionStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('appflowy_page_versions');
      store = PageVersionStore(rootOverride: root.path);
    });

    tearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });

    test('a version can be written down and read back', () async {
      final document = _documentOf(['Alpha']).toJson();
      final version = _version(id: 'v1', createdAt: now, hash: 'a');

      final listed = await store.write(version, document);

      expect(listed.map((entry) => entry.id), ['v1']);
      expect(listed.single.bytes, greaterThan(0));

      store.forgetEverythingRead();
      expect((await store.read('page')).map((entry) => entry.id), ['v1']);
      expect(await store.readDocument('page', 'v1'), document);
    });

    test('versions are listed newest first', () async {
      await store.write(
        _version(id: 'old', createdAt: now.subtract(const Duration(days: 1))),
        _documentOf(['Old']).toJson(),
      );
      await store.write(
        _version(id: 'new', createdAt: now, hash: 'b'),
        _documentOf(['New']).toJson(),
      );

      expect(
        (await store.read('page')).map((entry) => entry.id),
        ['new', 'old'],
      );
    });

    test('naming a version keeps it from being swept away', () async {
      await store.write(
        _version(id: 'v1', createdAt: now.subtract(const Duration(days: 400))),
        _documentOf(['Alpha']).toJson(),
      );
      await store.write(
        _version(id: 'v2', createdAt: now, hash: 'b'),
        _documentOf(['Beta']).toJson(),
      );

      await store.rename('page', 'v1', 'First draft');
      final left = await store.prune(
        'page',
        const PageVersionPolicy(maximumCopies: 1, retainedDays: 1),
        now: now,
      );

      expect(left.map((entry) => entry.id), ['v2', 'v1']);
      expect(left.last.kind, PageVersionKind.manual);
      expect(left.last.name, 'First draft');
    });

    test('a discarded version takes its file with it', () async {
      await store.write(
        _version(id: 'v1', createdAt: now),
        _documentOf(['Alpha']).toJson(),
      );
      final file = File(p.join(root.path, 'page', 'v1.json'));
      expect(file.existsSync(), isTrue);

      final left = await store.remove('page', ['v1']);

      expect(left, isEmpty);
      expect(file.existsSync(), isFalse);
      expect(await store.readDocument('page', 'v1'), isNull);
    });

    test('what is stored can be measured', () async {
      await store.write(
        _version(id: 'v1', createdAt: now),
        _documentOf(['Alpha']).toJson(),
      );

      final usage = await store.measureUsage();

      expect(usage.pages, 1);
      expect(usage.versions, 1);
      expect(usage.bytes, greaterThan(0));
      expect(usage.isEmpty, isFalse);
    });
  });
}
