import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/chart/chart_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_title.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_search_highlight.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/find_and_replace_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/math_equation/math_equation_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/encryption/encryption_mark.dart';
import 'package:appflowy/workspace/application/encryption/encryption_policy.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Native read boundaries are injected. Editor nodes, text spans, transactions,
// undo, spreadsheet values, query fields and scroll services are real.
// These tests deliberately do not initialize FFI or touch workspace/user data.
void main() {
  _test(
      'incremental native document query retains client and reuses source until invalidation',
      (tester, page) async {
    const query = 'native documentation';
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument('linked', [paragraphNode(text: query)]);
    await page.mount(tester);
    page.open();
    await tester.pump();
    await tester.pump();
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
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(tester.element(field), same(element));
      expect(tester.state(field), same(state));
      expect(state.widget.controller.text, query.substring(0, i));
      expect(
        state.widget.controller.selection,
        TextSelection.collapsed(offset: i),
      );
      expect(state.widget.controller.value.composing, TextRange.empty);
    }
    expect(_bar(tester).matchCount, 1);
    expect(page.backend.documentReads, ['linked']);
    expect(page.backend.viewReads, hasLength(4));
    page.backend.denied.add('linked');
    page.backend.access.value++;
    await tester.pump();
    expect(_bar(tester).matchCount, 0);
    expect(state.widget.focusNode.hasPrimaryFocus, isTrue);
  });

  _test('held prefix read recovers latest document query without retyping',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend
        .addDocument('linked', [paragraphNode(text: 'native documentation')]);
    final held = page.backend.hold('linked');
    final session = page.find()..search('nat', const FindOptions());
    await _until(tester, () => page.backend.documentReads.isNotEmpty);
    session.search('native documentation', const FindOptions());
    await tester.pump(const Duration(seconds: 3));
    expect(session.referencesTimedOut, isTrue);
    expect(session.matches, isEmpty);
    held.complete(page.backend.documents['linked']);
    await tester.pump();
    await tester.pump();
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches.single.match.group(0), 'native documentation');
    expect(page.backend.maximumConcurrentReads, 1);
    page.backend.denied.add('linked');
    page.backend.access.value++;
    expect(session.matches, isEmpty, reason: 'Revocation is synchronous');
  });

  _test('ViewPB.name is case-insensitive and never a synthetic node selection',
      (tester, page) async {
    page.rename('A NEEDLE title');
    final before = page.editor.document.toJson();
    final session = page.find();
    session.search('needle', const FindOptions());
    expect(session.matches, hasLength(1));
    final result = session.matches.single;
    expect(result.kind, DocumentFindResultKind.title);
    expect(result.node, isNull);
    expect(result.path, isNull);
    expect(result.selection, isNull);
    expect(result.match.start, 2);
    expect(page.editor.selection, isNull);
    expect(await session.replaceCurrent('wrong'), isFalse);
    expect(await session.replaceAll('wrong'), isFalse);
    session.search('needle', const FindOptions(caseSensitive: true));
    expect(session.matches, isEmpty);
    expect(page.view.name, 'A NEEDLE title');
    expect(page.editor.document.toJson(), before);
    expect(page.writes, 0);
  });

  _test('simple-table nested delta remains writable and undo preserves styling',
      (tester, page) async {
    final table = createSimpleTableBlockNode(
      rowCount: 1,
      columnCount: 1,
      defaultContent: 'a needle cell',
    );
    await page.editor.apply(
      page.editor.transaction..insertNode([0], table, deepCopy: false),
      withUpdateSelection: false,
    );
    final cell = page.editor.getNodeAtPath([0, 0, 0, 0])!;
    await page.editor.apply(
      page.editor.transaction
        ..formatText(cell, 2, 6, {AppFlowyRichTextKeys.bold: true}),
      withUpdateSelection: false,
    );
    final before = page.editor.document.toJson();
    final writes = page.writes;
    final session = page.find()..search('needle', const FindOptions());
    expect(session.matches.single.node, same(cell));
    expect(session.matches.single.path, [0, 0, 0, 0]);
    expect(session.matches.single.isWritable, isTrue);
    expect(page.writes, writes);
    expect(await session.replaceCurrent('found'), isTrue);
    expect(cell.delta!.toPlainText(), 'a found cell');
    expect(
      cell.delta!.slice(2, 3).first.attributes?[AppFlowyRichTextKeys.bold],
      isTrue,
    );
    page.editor.undoManager.undo();
    await tester.pump();
    expect(page.editor.document.toJson(), before);
  });

  _test(
      'spreadsheet searches formatted displayed text, not formula or hidden data',
      (tester, page) async {
    final data = SpreadsheetData.fromRows([
      ['Label', 'Amount', 'Secret heading'],
      ['visible', '=1+2', 'hidden needle'],
      ['filtered needle', '99', ''],
    ]);
    data.setColumn(2, data.column(2).copyWith(hidden: true));
    data.filters = [const SheetFilter(column: 0, query: 'visible')];
    final sheet = spreadsheetNode(data: data);
    await page.insert(sheet);
    final before = page.editor.document.toJson();
    final writes = page.writes;
    final session = page.find()..search('3', const FindOptions());
    expect(session.matches, hasLength(1));
    expect(session.current!.kind, DocumentFindResultKind.embedded);
    expect(session.current!.sourceId, 'B1');
    expect(session.current!.node, same(sheet));
    expect(session.current!.selection, isNull);
    session.search('=1+2', const FindOptions());
    expect(session.matches, isEmpty);
    session.search('needle', const FindOptions());
    expect(session.matches, isEmpty);
    session.search('Amount', const FindOptions());
    expect(session.matches.single.sourceId, 'header:1');
    expect(await session.replaceAll('wrong'), isFalse);
    expect(page.editor.document.toJson(), before);
    expect(page.writes, writes);
  });

  _test(
      'async page and database reads search readable text and exact view membership',
      (tester, page) async {
    final linked = pagePreviewNode(viewId: 'linked');
    final database = _databaseNode('database');
    await page.insert(linked);
    await page.insert(database);
    page.backend
        .addDocument('linked', [paragraphNode(text: 'linked NEEDLE content')]);
    page.backend.addDatabase('database');
    page.backend
        .addDocument('unreferenced', [paragraphNode(text: 'needle elsewhere')]);
    page.backend.views['linked']!.childViews
        .add(page.backend.views['unreferenced']!);
    final before = page.editor.document.toJson();
    final writes = page.writes;
    final session = page.find()..search('needle', const FindOptions());
    expect(session.loadingReferences, isTrue);
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, hasLength(2));
    expect(session.matches.every((hit) => !hit.isWritable), isTrue);
    expect(
      session.matches.map((hit) => hit.node),
      containsAll([linked, database]),
    );
    expect(
      session.matches.map((hit) => hit.match.group(0)),
      ['NEEDLE', 'needle'],
    );
    expect(session.matches.last.location, contains('Name'));
    expect(page.backend.documentReads, ['linked']);
    expect(page.backend.rowReads, ['database']);
    expect(page.backend.bulkReads, isEmpty);
    expect(page.backend.viewReads, isNot(contains('unreferenced')));
    expect(
      page.backend.readOrder.indexOf('membership:database'),
      lessThan(page.backend.readOrder.indexOf('cell:database:visible:name')),
    );
    expect(
      page.backend.cellReads.every((read) => read.$2 == 'visible'),
      isTrue,
    );
    expect(session.coverageUnknownCount, 1);
    expect(page.editor.document.toJson(), before);
    expect(page.writes, writes);

    // Query changes can reuse bounded text, but must re-check current access.
    final reads = page.backend.viewReads.length;
    session.search('content', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, hasLength(1));
    expect(page.backend.documentReads, ['linked']);
    expect(page.backend.viewReads.length, greaterThan(reads));
  });

  _test('cycles and duplicate references terminate without workspace traversal',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'a'));
    await page.insert(pagePreviewNode(viewId: 'a'));
    page.backend.addDocument(
      'a',
      [paragraphNode(text: 'needle a'), pagePreviewNode(viewId: 'b')],
    );
    page.backend.addDocument('b', [
      paragraphNode(text: 'needle b'),
      pagePreviewNode(viewId: 'a'),
      pagePreviewNode(viewId: 'owner'),
    ]);
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, hasLength(2));
    expect(page.backend.documentReads, ['a', 'b']);
    expect(session.truncated, isFalse);
    expect(page.backend.maximumConcurrentReads, 1);
  });

  _test('a chart database reference contributes read-only displayed row text',
      (tester, page) async {
    final chart = chartBlockNode(viewId: 'database');
    await page.insert(chart);
    page.backend.addDatabase('database');
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches.single.node, same(chart));
    expect(session.matches.single.location, contains('Row 1 · Name'));
    expect(session.matches.single.isWritable, isFalse);
  });

  _test('lastEdited invalidates a session cache even without a notification',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument('linked', [paragraphNode(text: 'needle')]);
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    page.backend.addDocument('linked', [paragraphNode(text: 'updated')]);
    final view = page.backend.views['linked']!;
    view.lastEdited = view.lastEdited + 1;
    session.search('updated', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches.single.match.input, 'updated');
    expect(page.backend.documentReads, ['linked', 'linked']);
  });

  _test('block-specific mention does not hide a subsequent whole-page preview',
      (tester, page) async {
    final first = paragraphNode(text: 'one needle');
    page.backend
        .addDocument('linked', [first, paragraphNode(text: 'second needle')]);
    await page.insert(
      paragraphNode(
        delta: Delta()
          ..insert(
            MentionBlockKeys.mentionChar,
            attributes: MentionBlockKeys.buildMentionPageAttributes(
              mentionType: MentionType.page,
              pageId: 'linked',
              blockId: first.id,
            ),
          ),
      ),
    );
    await page.insert(pagePreviewNode(viewId: 'linked'));
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(
      session.matches.any((hit) => hit.match.input == 'second needle'),
      isTrue,
    );
    expect(session.matches.every((hit) => hit.selection == null), isTrue);
  });

  _test('Replace All from a title still replaces only styled body deltas',
      (tester, page) async {
    page.rename('NEEDLE');
    await page.insert(
      paragraphNode(
        delta: Delta()
          ..insert('needle', attributes: {AppFlowyRichTextKeys.italic: true}),
      ),
    );
    final sheet = spreadsheetNode(
      data: SpreadsheetData.fromRows([
        ['Value'],
        ['needle'],
      ]),
    );
    await page.insert(sheet);
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend
        .addDocument('linked', [paragraphNode(text: 'needle reference')]);
    final referenceBefore = page.backend.documents['linked']!.writeToBuffer();
    final before = page.editor.document.toJson();
    final writes = page.writes;
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, hasLength(4));
    expect(session.current!.kind, DocumentFindResultKind.title);
    expect(session.currentIsWritable, isFalse);
    expect(session.hasWritableMatches, isTrue);
    expect(await session.replaceCurrent('wrong'), isFalse);
    expect(await session.replaceAll('found'), isTrue);
    expect(page.writes, writes + 1);
    expect(page.view.name, 'NEEDLE');
    expect(page.backend.documents['linked']!.writeToBuffer(), referenceBefore);
    final body = page.editor.document.root.children[1];
    expect(body.delta!.toPlainText(), 'found');
    expect(body.delta!.first.attributes?[AppFlowyRichTextKeys.italic], isTrue);
    expect(
      SpreadsheetData.fromJson(sheet.attributes['data'] as Map)
          .rawAt(const CellRef(0, 0)),
      'needle',
    );
    page.editor.undoManager.undo();
    await tester.pump();
    expect(page.editor.document.toJson(), before);
    page.editor.undoManager.redo();
    await tester.pump();
    expect(body.delta!.toPlainText(), 'found');
  });

  _test('denied reference metadata never triggers a content read',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'hidden'));
    page.backend.addDocument(
      'hidden',
      [paragraphNode(text: 'needle')],
      title: 'needle secret title',
    );
    page.backend.denied.add('hidden');
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(page.backend.documentReads, isEmpty);
    expect(session.matches, isEmpty);
    expect(session.unavailableCount, 1);
  });

  _test('permissions revoked during a read suppress its title and body',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument(
      'linked',
      [paragraphNode(text: 'needle body')],
      title: 'needle title',
    );
    final pending = page.backend.hold('linked');
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => page.backend.documentReads.isNotEmpty);
    page.backend.denied.add('linked');
    pending.complete(page.backend.documents['linked']);
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, isEmpty);
    expect(session.unavailableCount, 1);
    expect(page.editor.selection, isNull);
  });

  _test('access invalidation drops an already cached external match',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument('linked', [paragraphNode(text: 'needle')]);
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, hasLength(1));
    page.backend.denied.add('linked');
    page.backend.access.value++;
    await tester.pump();
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, isEmpty);
    expect(session.unavailableCount, 1);
    expect(page.backend.documentReads, ['linked']);
  });

  _test('a stale query cannot publish and rapid queries keep one native read',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument('linked', [paragraphNode(text: 'old needle')]);
    final pending = page.backend.hold('linked');
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => page.backend.documentReads.isNotEmpty);
    session.search('ignored', const FindOptions());
    session.search('new text', const FindOptions());
    final oldDocument = page.backend.documents['linked'];
    page.backend.addDocument('linked', [paragraphNode(text: 'new text')]);
    pending.complete(oldDocument);
    await _until(tester, () => !session.loadingReferences);
    expect(session.query, 'new text');
    expect(session.matches.single.match.input, 'new text');
    expect(page.backend.documentReads, ['linked', 'linked']);
    expect(page.backend.maximumConcurrentReads, 1);
  });

  _test('reference notifications invalidate text while keeping the query',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument('linked', [paragraphNode(text: 'before')]);
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, isEmpty);
    page.backend.addDocument('linked', [paragraphNode(text: 'needle updated')]);
    page.backend.changes.add('linked');
    await _until(tester, () => !session.loadingReferences);
    await tester.pump();
    expect(session.matches.single.match.input, 'needle updated');
    expect(session.query, 'needle');
    expect(page.backend.documentReads, ['linked', 'linked']);
  });

  _test('a newer body caret is not replaced by a late reference reveal',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument('linked', [paragraphNode(text: 'needle')]);
    final pending = page.backend.hold('linked');
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => page.backend.documentReads.isNotEmpty);
    final caret = Selection.collapsed(Position(path: [0], offset: 2));
    page.editor.selection = caret;
    pending.complete(page.backend.documents['linked']);
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, hasLength(1));
    expect(page.editor.selection, caret);
  });

  for (final lifecycle in [
    'closed',
    'inactive',
    'switched',
    'editor disposed',
  ]) {
    _test('$lifecycle owner rejects delayed external results and replacements',
        (tester, page) async {
      await page.insert(pagePreviewNode(viewId: 'linked'));
      page.backend.addDocument('linked', [paragraphNode(text: 'needle')]);
      final pending = page.backend.hold('linked');
      final session = page.find()..search('needle', const FindOptions());
      await _until(tester, () => page.backend.documentReads.isNotEmpty);
      if (lifecycle == 'closed') {
        session.dispose();
      } else if (lifecycle == 'inactive') {
        page.active = false;
      } else if (lifecycle == 'switched') {
        page.view = ViewPB(id: 'other', name: 'needle');
        page.viewChanges.add(page.view);
      } else {
        page.editor.dispose();
      }
      pending.complete(page.backend.documents['linked']);
      await tester.pump();
      await tester.pump();
      expect(session.isActive, isFalse);
      expect(session.matches, isEmpty);
      expect(await session.replaceAll('wrong'), isFalse);
      expect(
        DocumentSearchHighlight.instance.rangesOf(page.editor.document.root),
        isEmpty,
      );
    });
  }

  _test('removing a reference while it loads cannot reveal a different block',
      (tester, page) async {
    final reference = pagePreviewNode(viewId: 'linked');
    await page.insert(reference);
    page.backend.addDocument('linked', [paragraphNode(text: 'needle')]);
    final pending = page.backend.hold('linked');
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => page.backend.documentReads.isNotEmpty);
    await page.editor.apply(
      page.editor.transaction..deleteNode(reference),
      withUpdateSelection: false,
    );
    await tester.pump();
    pending.complete(page.backend.documents['linked']);
    await tester.pump();
    expect(session.matches, isEmpty);
    expect(page.editor.selection, isNull);
  });

  _test('title metadata and local/remote body changes refresh an open query',
      (tester, page) async {
    page.rename('needle title');
    final session = page.find()..search('needle', const FindOptions());
    expect(session.matches, hasLength(1));
    page.rename('renamed');
    await tester.pump();
    expect(session.matches, isEmpty);
    final node = page.editor.document.first!;
    await page.editor.apply(
      page.editor.transaction..insertText(node, 0, 'needle '),
      withUpdateSelection: false,
    );
    await tester.pump();
    expect(session.matches.single.kind, DocumentFindResultKind.delta);
    await page.editor.apply(
      page.editor.transaction..insertText(node, 0, 'needle '),
      isRemote: true,
      withUpdateSelection: false,
    );
    await tester.pump();
    expect(session.matches, hasLength(2));
    page.rename('NEEDLE again');
    await tester.pump();
    expect(session.matches, hasLength(3));
  });

  for (final guard in ['read only', 'page lock', 'write permission']) {
    _test('$guard leaves title/body search usable but refuses all writes',
        (tester, page) async {
      page.rename('needle title');
      await page.insert(paragraphNode(text: 'needle body'));
      final session = page.find()..search('needle', const FindOptions());
      if (guard == 'read only') page.editor.editable = false;
      if (guard == 'page lock') page.view.isLocked = true;
      if (guard == 'write permission') page.allowReplace = false;
      final before = page.editor.document.toJson();
      expect(session.matches, hasLength(2));
      expect(await session.replaceAll('wrong'), isFalse);
      session.navigate();
      expect(session.current!.kind, DocumentFindResultKind.delta);
      expect(await session.replaceCurrent('wrong'), isFalse);
      expect(page.editor.document.toJson(), before);
    });
  }

  for (final limit in ['depth', 'views', 'entries', 'bytes']) {
    _test(
        '$limit limit reports a partial search instead of silent completeness',
        (tester, page) async {
      await page.insert(pagePreviewNode(viewId: 'a'));
      await page.insert(pagePreviewNode(viewId: 'b'));
      page.backend.addDocument(
        'a',
        [paragraphNode(text: 'needle ' * 40), pagePreviewNode(viewId: 'c')],
      );
      page.backend.addDocument('b', [paragraphNode(text: 'needle b')]);
      page.backend.addDocument('c', [paragraphNode(text: 'needle c')]);
      final session = page.find(
        limits: DocumentFindLimits(
          maxDepth: limit == 'depth' ? 1 : 3,
          maxViews: limit == 'views' ? 1 : 24,
          maxEntries: limit == 'entries' ? 2 : 2048,
          maxBytes: limit == 'bytes' ? 32 : 512 * 1024,
        ),
      )..search('needle', const FindOptions());
      await _until(tester, () => !session.loadingReferences);
      expect(session.truncated, isTrue);
      if (limit == 'depth') {
        expect(page.backend.documentReads, isNot(contains('c')));
      }
      if (limit == 'views') expect(page.backend.documentReads, ['a']);
      if (limit == 'entries') {
        expect(session.matches.length, lessThanOrEqualTo(2));
      }
    });
  }

  _test('malformed block cycles and unbounded formula ranges are bounded',
      (tester, page) async {
    final document = _document([paragraphNode(text: 'needle')]);
    final root = document.blocks[document.pageId]!;
    document.meta.childrenMap[root.childrenId]!.children.add(document.pageId);
    final content = documentFindDocumentContent(
      document,
      const DocumentFindReference('linked'),
      const DocumentFindLimits(),
    );
    expect(
      content.texts.where((part) => part.text.contains('needle')),
      hasLength(1),
    );
    final sheet = spreadsheetNode(
      data: SpreadsheetData.fromRows(
        [
          ['=SUM(A1:ZZ99999999)'],
        ],
        headerRow: false,
      ),
    );
    final bounded = documentFindSpreadsheetContent(
      sheet,
      const DocumentFindLimits(maxEntries: 16),
    );
    expect(bounded.truncated, isTrue);
  });

  _test(
      'native encryption preflight respects revealed ancestors and fails closed',
      (tester, page) async {
    final vault = EncryptionVault.instance;
    const policy =
        EncryptionPolicy(enabled: true, salt: 'test', verifier: 'test');
    final ancestor = ViewPB(
      id: 'parent',
      extra: const EncryptionMark(scope: EncryptionScope.folder)
          .mergeIntoExtra(''),
    );
    final target = ViewPB(id: 'target');
    try {
      vault.seedForTest(policy: policy, key: Uint8List(32));
      expect(
        await documentFindCanReadView(
          target,
          readAncestors: (_) async => [ancestor],
        ),
        isFalse,
      );
      vault.reveal('parent');
      expect(
        await documentFindCanReadView(
          target,
          readAncestors: (_) async => [ancestor],
        ),
        isTrue,
      );
      vault.conceal('parent');
      expect(
        await documentFindCanReadView(
          target,
          readAncestors: (_) async => null,
        ),
        isFalse,
      );
      expect(
        await documentFindCanReadView(
          target,
          readAncestors: (_) async => throw StateError('ancestor read failed'),
        ),
        isFalse,
      );
      vault.lock();
      expect(
        await documentFindCanReadView(
          target,
          readAncestors: (_) async => [ancestor],
        ),
        isFalse,
      );
    } finally {
      vault.resetForTest();
    }
  });

  for (final mode in ['light', 'dark', 'paper']) {
    _test('$mode: title reveal paints the native field and keeps query focus',
        (tester, page) async {
      page.rename('A NEEDLE title');
      for (var i = 0; i < 70; i++) {
        await page.insert(paragraphNode(text: 'Filler paragraph $i'));
      }
      await page.mount(tester, mode: mode);
      final editorElement = tester.element(find.byType(AppFlowyEditor));
      page.scroll!.itemScrollController.jumpTo(index: 60);
      await tester.pump();
      page.open();
      await tester.pump();
      final before = page.editor.document.toJson();
      final writes = page.writes;
      await _query(tester, 'needle');
      await _until(
        tester,
        () =>
            page.titleKey.currentContext != null &&
            _bar(tester).findFocusNode.hasPrimaryFocus,
      );
      expect(_bar(tester).matchCount, 1);
      expect(page.editor.selection, isNull);
      final title = find.byKey(page.titleKey);
      final viewport = tester.getRect(find.byType(AppFlowyEditor));
      expect(tester.getRect(title).intersect(viewport), tester.getRect(title));
      final editable = tester.widget<EditableText>(
        find.descendant(of: title, matching: find.byType(EditableText)),
      );
      expect(editable.controller, same(page.titleController));
      final span = editable.controller.buildTextSpan(
        context: tester.element(title),
        style: editable.style,
        withComposing: true,
      );
      final highlighted = _spanRuns(span).where(
        (run) =>
            run.$2.backgroundColor ==
            FindHighlightColors.current(
              mode == 'dark' ? Brightness.dark : Brightness.light,
            ),
      );
      expect(highlighted.map((run) => run.$1).join(), 'NEEDLE');
      expect(tester.element(find.byType(AppFlowyEditor)), same(editorElement));
      expect(page.editor.document.toJson(), before);
      expect(page.writes, writes);
      if (mode == 'paper') {
        expect(
          FindBarPalette.of(tester.element(find.byType(FindReplaceBar)))
              .surface,
          PaperTheme.popupBackground,
        );
      }
    });
  }

  _test('Ctrl+F from the title opens page Find without remounting the editor',
      (tester, page) async {
    page.rename('Needle title');
    await page.mount(tester);
    final editorElement = tester.element(find.byType(AppFlowyEditor));
    await tester.tap(find.byKey(page.titleKey));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await _query(tester, 'needle');
    expect(_bar(tester).matchCount, 1);
    expect(tester.element(find.byType(AppFlowyEditor)), same(editorElement));
    expect(_bar(tester).findFocusNode.hasPrimaryFocus, isTrue);
  });

  _test('async hit reveals its real parent and a highlighted readable snippet',
      (tester, page) async {
    for (var i = 0; i < 60; i++) {
      await page.insert(paragraphNode(text: 'Filler paragraph $i'));
    }
    final parent = pagePreviewNode(viewId: 'linked');
    await page.insert(parent);
    page.backend.addDocument(
      'linked',
      [paragraphNode(text: 'Before needle after')],
      title: 'Linked notes',
    );
    final pending = page.backend.hold('linked');
    await page.mount(tester);
    final editorElement = tester.element(find.byType(AppFlowyEditor));
    page.open(replace: true);
    await tester.pump();
    await _query(tester, 'needle');
    expect(_bar(tester).busy, isTrue);
    final queryElement =
        tester.element(find.byKey(const ValueKey('findTextField')));
    await _until(tester, () => page.backend.documentReads.isNotEmpty);
    pending.complete(page.backend.documents['linked']);
    await _until(
      tester,
      () => !_bar(tester).busy && parent.context?.mounted == true,
    );
    await tester.pump();
    expect(_bar(tester).matchCount, 1);
    expect(_bar(tester).onReplace, isNull);
    expect(_bar(tester).onReplaceAll, isNull);
    expect(page.editor.selection, isNull);
    final snippet =
        tester.widget<Text>(find.byKey(const ValueKey('documentFindSnippet')));
    expect(snippet.textSpan!.toPlainText(), 'Before needle after');
    expect(
      _spanRuns(snippet.textSpan!)
          .where((run) => run.$2.backgroundColor != null)
          .map((run) => run.$1)
          .join(),
      'needle',
    );
    expect(find.textContaining('Linked notes · Block'), findsOneWidget);
    final viewport = tester.getRect(find.byType(AppFlowyEditor));
    expect(
      parent.renderBox!.localToGlobal(Offset.zero).dy,
      inInclusiveRange(viewport.top, viewport.bottom),
    );
    expect(tester.element(find.byType(AppFlowyEditor)), same(editorElement));
    expect(
      tester.element(find.byKey(const ValueKey('findTextField'))),
      same(queryElement),
    );
    expect(_bar(tester).findFocusNode.hasPrimaryFocus, isTrue);
  });

  _test(
      'native spreadsheet edits refresh page Find before persistence debounce',
      (tester, page) async {
    final sheet = spreadsheetNode(
      data: SpreadsheetData.fromRows([
        ['Value'],
        ['before'],
      ]),
    );
    await page.insert(sheet);
    await page.mount(tester);
    await _until(
      tester,
      () => find.byType(SpreadsheetGrid).evaluate().isNotEmpty,
    );
    final grid = tester.widget<SpreadsheetGrid>(find.byType(SpreadsheetGrid));
    final element = tester.element(find.byType(SpreadsheetGrid));
    final session = page.find()..search('needle', const FindOptions());
    expect(session.matches, isEmpty);
    final writes = page.writes;
    grid.controller
        .mutate((data) => data.setRaw(const CellRef(0, 0), 'needle live'));
    await tester.pump();
    expect(session.matches.single.match.input, 'needle live');
    expect(page.writes, writes);
    expect(tester.element(find.byType(SpreadsheetGrid)), same(element));
    expect(grid.controller.searchQuery, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      SpreadsheetData.fromJson(sheet.attributes['data'] as Map)
          .rawAt(const CellRef(0, 0)),
      'needle live',
    );
  });

  _test(
      'live title controller updates marks without a title write or selection change',
      (tester, page) async {
    await page.mount(tester);
    final session = page.find()..search('needle', const FindOptions());
    page.titleController!.text = 'NEEDLE draft';
    await tester.pump();
    expect(session.matches.single.kind, DocumentFindResultKind.title);
    final value = page.titleController!.value;
    session.navigate();
    await tester.pump();
    expect(page.titleController!.value, value);
    expect(page.editor.selection, isNull);
    expect(page.writes, 0);
  });

  _test('unavailable read is visible and closes with its owning Find bar',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'missing'));
    await page.mount(tester);
    page.open();
    await tester.pump();
    await _query(tester, 'needle');
    await _until(tester, () => !_bar(tester).busy);
    expect(find.textContaining('Partial search:'), findsOneWidget);
    expect(_bar(tester).matchCount, 0);
    _bar(tester).onClose();
    await tester.pump();
    expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
    expect(DocumentFindMenu.isOpen, isFalse);
  });

  _test('closing the native overlay rejects its pending read and focus request',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument('linked', [paragraphNode(text: 'needle')]);
    final pending = page.backend.hold('linked');
    await page.mount(tester);
    page.open();
    await tester.pump();
    await _query(tester, 'needle');
    await _until(tester, () => page.backend.documentReads.isNotEmpty);
    final field = _bar(tester).findFocusNode;
    _bar(tester).onClose();
    await tester.pump();
    await tester.tap(find.byKey(page.titleKey));
    pending.complete(page.backend.documents['linked']);
    await tester.pump();
    await tester.pump();
    expect(DocumentFindMenu.isOpen, isFalse);
    expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
    expect(find.byKey(const ValueKey('documentFindSnippet')), findsNothing);
    expect(field.parent, isNull);
    expect(page.titleFocus.hasPrimaryFocus, isTrue);
  });

  _test('the native overlay closes when its ViewPB owner changes',
      (tester, page) async {
    await page.mount(tester);
    page.open();
    await tester.pump();
    page.view = ViewPB(id: 'other', name: 'Other page');
    page.viewChanges.add(page.view);
    await tester.pump();
    await tester.pump();
    expect(DocumentFindMenu.isOpen, isFalse);
    expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
  });

  _test(
      'typed production provider skips relations BEFORE reads and uses field options',
      (tester, page) async {
    await page.insert(_databaseNode('database'));
    page.backend.addDatabase('database');
    page.backend.denied.add('secret-database');
    page.backend.fields['database'] = [
      FieldPB(
        id: 'relation',
        name: 'Related',
        fieldType: FieldType.Relation,
        typeOptionData:
            RelationTypeOptionPB(databaseId: 'secret-database').writeToBuffer(),
      ),
      FieldPB(
        id: 'status',
        name: 'Status',
        fieldType: FieldType.SingleSelect,
        typeOptionData: SingleSelectTypeOptionPB(
          options: [
            SelectOptionPB(id: 'option-id', name: 'Displayed needle'),
            SelectOptionPB(id: 'unused', name: 'Unused secret'),
          ],
        ).writeToBuffer(),
      ),
      FieldPB(
        id: 'date',
        name: 'Due',
        fieldType: FieldType.DateTime,
        typeOptionData: DateTypeOptionPB(dateFormat: DateFormatPB.DayMonthYear)
            .writeToBuffer(),
      ),
    ];
    page.backend.cells[('database', 'visible', 'status')] = CellPB(
      fieldId: 'status',
      rowId: 'visible',
      fieldType: FieldType.SingleSelect,
      data: SelectOptionCellDataPB(
        selectOptions: [
          SelectOptionPB(id: 'option-id', name: 'Stale label'),
        ],
      ).writeToBuffer(),
    );
    page.backend.cells[('database', 'visible', 'date')] = CellPB(
      fieldId: 'date',
      rowId: 'visible',
      fieldType: FieldType.DateTime,
      data: DateCellDataPB(
        timestamp: Int64(
          DateTime(2026, 9, 25, 12).millisecondsSinceEpoch ~/ 1000,
        ),
      ).writeToBuffer(),
    );
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches.single.match.input, 'Displayed needle');
    expect(page.backend.bulkReads, isEmpty);
    expect(page.backend.cellReads.map((read) => read.$3), ['status', 'date']);
    expect(page.backend.viewReads, isNot(contains('secret-database')));
    expect(session.unavailableCount, 1);
    expect(session.coverageUnknownCount, 1);
    session.search('25/09/2026', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches.single.match.input, '25/09/2026');
    session.search('Stale|Unused|option-id', const FindOptions(useRegex: true));
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, isEmpty);
  });

  for (final failure in [
    'omitted rows',
    'missing cell',
    'typeless empty cell',
    'sealed cell',
  ]) {
    _test('$failure cannot masquerade as complete native coverage',
        (tester, page) async {
      await page.insert(_databaseNode('database'));
      page.backend.addDatabase('database');
      page.backend.fields['database'] = [FieldPB(id: 'name', name: 'Name')];
      if (failure == 'omitted rows') {
        page.backend.rows['database'] = [];
      } else if (failure == 'missing cell') {
        page.backend.cells[('database', 'visible', 'name')] = null;
      } else if (failure == 'typeless empty cell') {
        page.backend.cells[('database', 'visible', 'name')] =
            CellPB(fieldId: 'name', rowId: 'visible');
      } else {
        page.backend.cells[('database', 'visible', 'name')] = CellPB(
          fieldId: 'name',
          rowId: 'visible',
          fieldType: FieldType.RichText,
          data: utf8.encode('af1.hidden.needle'),
        );
      }
      final session = page.find()..search('needle', const FindOptions());
      await _until(tester, () => !session.loadingReferences);
      expect(session.matches, isEmpty);
      expect(session.coverageUnknownCount, 1);
      if (failure != 'omitted rows') expect(session.unavailableCount, 1);
      session.search('retry', const FindOptions());
      await _until(tester, () => !session.loadingReferences);
      expect(page.backend.rowReads, ['database', 'database']);
      expect(page.backend.bulkReads, isEmpty);
    });
  }

  _test(
      'missing injected typed/file methods never fall back to FFI or filesystem',
      (tester, page) async {
    await page.insert(_databaseNode('database'));
    page.backend.addDatabase('database');
    final file = page.backend.addFile('file', 'notes.md', '# needle');
    await page.insert(_workspaceFileNode(file));
    final session = page.find(
      referenceProvider: page.backend.makeProvider(
        typedCells: false,
        localFiles: false,
      ),
    )..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, isEmpty);
    expect(session.unavailableCount, 2);
    expect(page.backend.bulkReads, isEmpty);
    expect(page.backend.cellReads, isEmpty);
    expect(page.backend.files.calls, isEmpty);
  });

  _test('throwing authorization fails closed before native content or title',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument(
      'linked',
      [paragraphNode(text: 'needle')],
      title: 'needle secret',
    );
    page.backend.failedPreflight.add('linked');
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, isEmpty);
    expect(session.unavailableCount, 1);
    expect(page.backend.documentReads, isEmpty);
  });

  for (final stage in [
    'view:owner',
    'preflight:linked',
    'document:linked',
    'fields:database',
    'membership:database',
    'cell:database:visible:name',
  ]) {
    _test(
        'hung $stage expires UI but keeps shared native slot across query/close/reopen',
        (tester, page) async {
      final database = stage.contains('database');
      await page
          .insert(pagePreviewNode(viewId: database ? 'database' : 'linked'));
      page.backend.addDatabase('database');
      page.backend.addDocument('linked', [paragraphNode(text: 'needle')]);
      page.backend.deadline = const Duration(milliseconds: 30);
      final held = page.backend.holdStage(stage);
      final firstProvider = page.backend.makeProvider(sharedScheduler: true);
      final secondProvider = page.backend.makeProvider(sharedScheduler: true);
      expect(firstProvider.readScheduler, same(secondProvider.readScheduler));
      final first = page.find(referenceProvider: firstProvider)
        ..search('needle', const FindOptions());
      await _until(tester, () => page.backend.nativeCalls.contains(stage));
      final calls = List.of(page.backend.nativeCalls);
      await tester.pump(const Duration(milliseconds: 31));
      expect(first.loadingReferences, isFalse);
      expect(first.referencesTimedOut, isTrue);
      expect(page.backend.concurrentReads, 1);
      first.search('discarded', const FindOptions());
      first.search('latest', const FindOptions());
      expect(firstProvider.readScheduler.pendingCount, 1);
      first.dispose();
      expect(firstProvider.readScheduler.pendingCount, 0);

      final reopened = page.find(referenceProvider: secondProvider)
        ..search('needle', const FindOptions());
      await tester.pump(const Duration(milliseconds: 31));
      expect(reopened.loadingReferences, isFalse);
      expect(reopened.referencesTimedOut, isTrue);
      expect(secondProvider.readScheduler.pendingCount, 0);
      expect(page.backend.nativeCalls, calls);
      expect(page.backend.maximumConcurrentReads, 1);
      reopened.search('closed pending query', const FindOptions());
      reopened.dispose();
      held.complete();
      await tester.pump();
      await tester.pump();
      expect(page.backend.nativeCalls, calls);
      expect(first.matches, isEmpty);
      expect(reopened.matches, isEmpty);

      final fresh = page.find(referenceProvider: secondProvider)
        ..search('needle', const FindOptions());
      await _until(tester, () => !fresh.loadingReferences);
      expect(fresh.matches, hasLength(1));
      expect(fresh.referencesTimedOut, isFalse);
      expect(page.backend.maximumConcurrentReads, 1);
    });
  }

  _test(
      'deadline shows partial instead of forever busy without remounting query/editor',
      (tester, page) async {
    await page.insert(paragraphNode(text: 'needle body'));
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument('linked', [paragraphNode(text: 'needle')]);
    page.backend.deadline = const Duration(milliseconds: 30);
    final held = page.backend.hold('linked');
    await page.mount(tester, mode: 'paper');
    final editor = tester.element(find.byType(AppFlowyEditor));
    page.open();
    await tester.pump();
    await _query(tester, 'needle');
    final query = tester.element(find.byKey(const ValueKey('findTextField')));
    await tester.pump(const Duration(milliseconds: 31));
    await tester.pump();
    expect(_bar(tester).busy, isFalse);
    expect(find.textContaining('deadline reached'), findsOneWidget);
    expect(_bar(tester).findFocusNode.hasPrimaryFocus, isTrue);
    expect(tester.element(find.byType(AppFlowyEditor)), same(editor));
    expect(
      tester.element(find.byKey(const ValueKey('findTextField'))),
      same(query),
    );
    held.complete(page.backend.documents['linked']);
    await tester.pump();
    expect(_bar(tester).matchCount, 1);
    expect(_bar(tester).onNext, isNotNull);
    expect(_bar(tester).onReplaceAll, isNotNull);
    expect(find.byKey(const ValueKey('documentFindSnippet')), findsNothing);
  });

  _test('actual overlay close/reopen cannot bypass a held native read',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'linked'));
    page.backend.addDocument('linked', [paragraphNode(text: 'needle')]);
    page.backend.deadline = const Duration(milliseconds: 30);
    final held = page.backend.hold('linked');
    await page.mount(tester);
    final editor = tester.element(find.byType(AppFlowyEditor));
    page.open(
      referenceProvider: page.backend.makeProvider(sharedScheduler: true),
    );
    await tester.pump();
    await _query(tester, 'needle');
    await _until(tester, () => page.backend.documentReads.isNotEmpty);
    final calls = List.of(page.backend.nativeCalls);
    final oldFocus = _bar(tester).findFocusNode;
    _bar(tester).onClose();
    // Deliberately reopen before the old overlay has its disposal frame.
    page.open(
      referenceProvider: page.backend.makeProvider(sharedScheduler: true),
    );
    await tester.pump();
    await _query(tester, 'needle');
    await _query(tester, 'new query');
    expect(page.backend.nativeCalls, calls);
    expect(page.backend.maximumConcurrentReads, 1);
    expect(oldFocus.parent, isNull);
    expect(tester.element(find.byType(AppFlowyEditor)), same(editor));
    await tester.pump(const Duration(milliseconds: 31));
    await tester.pump();
    expect(_bar(tester).busy, isFalse);
    expect(find.textContaining('deadline reached'), findsOneWidget);
    expect(_bar(tester).findFocusNode.hasPrimaryFocus, isTrue);
    await _query(tester, 'closed pending query');
    _bar(tester).onClose();
    await tester.pump();
    held.complete(page.backend.documents['linked']);
    await tester.pump();
    await tester.pump();
    expect(page.backend.nativeCalls, calls);
    expect(page.backend.concurrentReads, 0);
    expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
  });

  _test('native empty-row uncertainty is visible even with zero matches',
      (tester, page) async {
    await page.insert(pagePreviewNode(viewId: 'database'));
    page.backend.addDatabase('database');
    page.backend.rows['database'] = [];
    await page.mount(tester);
    page.open();
    await tester.pump();
    await _query(tester, 'needle');
    await _until(tester, () => !_bar(tester).busy);
    expect(_bar(tester).matchCount, 0);
    expect(
      find.textContaining('coverage could not be verified'),
      findsOneWidget,
    );
  });

  _test(
      'workspace_file_id reads authorized UTF-8 Markdown, not copied URL or attributes',
      (tester, page) async {
    final view = page.backend.addFile(
      'file',
      'Notes.md',
      '# Héllo **needle**\n\n```dart\nprint("needle");\n```\n'
          '[Visible link](https://invalid.test/hidden-destination)\n'
          '<span hidden>hidden secret</span>',
    );
    final node = _workspaceFileNode(view)
      ..updateAttributes({
        'url': 'https://invalid.test/never-fetch',
        'preview_metadata': {'hidden': 'metadata secret'},
      });
    await page.insert(node);
    final before = page.editor.document.toJson();
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, hasLength(2));
    expect(
      session.matches
          .every((hit) => identical(hit.node, node) && !hit.isWritable),
      isTrue,
    );
    expect(session.matches.first.match.input, contains('Héllo needle'));
    expect(page.backend.files.byteReads, [view.workspaceItem!.storageUrl]);
    expect(page.backend.documentReads, isEmpty);
    expect(session.coverageUnknownCount, 1);
    expect(await session.replaceAll('wrong'), isFalse);
    session.search('hidden|metadata secret', const FindOptions(useRegex: true));
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, isEmpty);
    session.search('Notes.md', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches.single.sourceId, 'title');
    expect(page.editor.document.toJson(), before);
  });

  _test('local imported code is owner-gated, uncached and never replaced',
      (tester, page) async {
    final path = page.backend.files.path('sample.dart');
    page.backend.files.bytes[path] = utf8.encode('final needle = "é";');
    final node = fileNode(url: path, name: 'sample.dart');
    await page.insert(node);
    await page.insert(
      paragraphNode(
        delta: Delta()
          ..insert('needle', attributes: {AppFlowyRichTextKeys.bold: true}),
      ),
    );
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, hasLength(2));
    expect(session.matches.first.node, same(node));
    expect(session.matches.first.isWritable, isFalse);
    expect(
      page.backend.readOrder.indexOf('preflight:owner'),
      lessThan(page.backend.readOrder.indexOf('file:$path')),
    );
    final stored = List.of(page.backend.files.bytes[path]!);
    expect(await session.replaceAll('found'), isTrue);
    expect(page.backend.files.bytes[path], stored);
    final body = page.editor.document.root.children.last;
    expect(body.delta!.first.attributes?[AppFlowyRichTextKeys.bold], isTrue);
    expect(body.delta!.toPlainText(), 'found');
    page.backend.files.bytes[path] = utf8.encode('updated code');
    session.search('updated code', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches.single.match.input, 'updated code');
    expect(page.backend.files.byteReads, [path, path]);
  });

  _test('denied workspace file cannot expose even its copied filename',
      (tester, page) async {
    final view = page.backend.addFile('file', 'needle.md', '# needle');
    await page.insert(_workspaceFileNode(view));
    page.backend.denied.add('file');
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, isEmpty);
    expect(session.unavailableCount, 1);
    expect(page.backend.files.calls, isEmpty);
    expect(page.backend.documentReads, isEmpty);
  });

  for (final kind in ['png', 'pdf', 'bin', 'ipynb', 'docx']) {
    _test('$kind file reports partial and never starts OCR or a binary reader',
        (tester, page) async {
      final view = page.backend.addFile('file', 'attachment.$kind', 'needle');
      await page.insert(_workspaceFileNode(view));
      final session = page.find()..search('needle', const FindOptions());
      await _until(tester, () => !session.loadingReferences);
      expect(session.matches, isEmpty);
      expect(session.unavailableCount, 1);
      expect(page.backend.files.calls, isEmpty);
      expect(page.backend.documentReads, isEmpty);
      session.search('attachment', const FindOptions());
      await _until(tester, () => !session.loadingReferences);
      expect(session.matches.single.sourceId, 'title');
    });
  }

  for (final source in [
    'https://invalid.test/notes.md',
    'data:text/plain,needle',
    'file://server/share/notes.md',
    r'\\server\share\notes.md',
    'relative.md',
    r'C:\private\notes.md',
  ]) {
    _test('unsafe file source $source is not resolved or read',
        (tester, page) async {
      final view =
          page.backend.addFile('file', 'Notes.md', 'needle', source: source);
      await page.insert(_workspaceFileNode(view));
      final session = page.find()..search('needle', const FindOptions());
      await _until(tester, () => !session.loadingReferences);
      expect(session.matches, isEmpty);
      expect(session.unavailableCount, 1);
      expect(page.backend.files.resolves, isEmpty);
      expect(page.backend.files.byteReads, isEmpty);
    });
  }

  for (final escape in [
    'traversal',
    'resolved outside',
    'symlink outside',
    'redirected storage',
  ]) {
    _test('$escape is rejected before any file bytes', (tester, page) async {
      final files = page.backend.files;
      final outside = p.join(files.root, 'private.md');
      final path = files.path('notes.md');
      if (escape == 'resolved outside') files.resolved[path] = outside;
      if (escape == 'symlink outside') files.canonical[path] = outside;
      if (escape == 'redirected storage') {
        files.canonical[p.join(files.root, 'files')] =
            p.join(files.root, 'private');
        files.canonical[path] = p.join(files.root, 'private', 'notes.md');
      }
      final view = page.backend.addFile(
        'file',
        'Notes.md',
        'needle',
        source: escape == 'traversal'
            ? p.join(files.root, 'files', '..', 'private.md')
            : path,
      );
      await page.insert(_workspaceFileNode(view));
      final session = page.find()..search('needle', const FindOptions());
      await _until(tester, () => !session.loadingReferences);
      expect(session.matches, isEmpty);
      expect(session.unavailableCount, 1);
      expect(files.byteReads, isEmpty);
    });
  }

  for (final failure in ['binary', 'invalid utf8', 'sealed', 'oversize']) {
    _test('$failure local text reports partial without searching opaque data',
        (tester, page) async {
      final view = page.backend.addFile('file', 'Notes.txt', 'needle');
      final path = view.workspaceItem!.storageUrl!;
      page.backend.files.bytes[path] = switch (failure) {
        'binary' => [0, ...utf8.encode('needle')],
        'invalid utf8' => [255, ...utf8.encode('needle')],
        'sealed' => utf8.encode('af1.hidden.needle'),
        _ => utf8.encode('needle ' * 40),
      };
      await page.insert(_workspaceFileNode(view));
      final session = page.find(
        limits: const DocumentFindLimits(maxSourceBytes: 32),
      )..search('needle', const FindOptions());
      await _until(tester, () => !session.loadingReferences);
      expect(session.matches, isEmpty);
      expect(page.backend.files.readLimits, [32]);
      if (failure == 'oversize') {
        expect(session.truncated, isTrue);
      } else {
        expect(session.unavailableCount, 1);
      }
    });
  }

  _test(
      'nested file reference observes depth budget and does not bypass parent gate',
      (tester, page) async {
    final view = page.backend.addFile('file', 'Notes.txt', 'needle');
    page.backend.addDocument('linked', [_workspaceFileNode(view)]);
    await page.insert(pagePreviewNode(viewId: 'linked'));
    final bounded = page.find(limits: const DocumentFindLimits(maxDepth: 1))
      ..search('needle', const FindOptions());
    await _until(tester, () => !bounded.loadingReferences);
    expect(bounded.truncated, isTrue);
    expect(page.backend.files.byteReads, isEmpty);
    bounded.dispose();
    page.backend.denied.add('linked');
    final denied = page.find()..search('needle', const FindOptions());
    await _until(tester, () => !denied.loadingReferences);
    expect(denied.matches, isEmpty);
    expect(page.backend.files.byteReads, isEmpty);
  });

  _test('file sources share the aggregate reference text budget',
      (tester, page) async {
    for (final id in ['a', 'b']) {
      final view = page.backend.addFile(id, '$id.txt', 'needle ${id * 13}');
      await page.insert(_workspaceFileNode(view));
    }
    final session = page.find(limits: const DocumentFindLimits(maxBytes: 32))
      ..search('needle', const FindOptions());
    await _until(tester, () => !session.loadingReferences);
    expect(session.truncated, isTrue);
    expect(session.matches, hasLength(1));
    expect(session.matches.single.viewId, 'a');
    expect(page.backend.files.byteReads, hasLength(2));
    expect(page.backend.files.readLimits, [32, 32]);
  });

  _test(
      'file permission revocation during held byte read drops title and contents',
      (tester, page) async {
    final view = page.backend.addFile('file', 'needle.txt', 'needle');
    await page.insert(_workspaceFileNode(view));
    final held = page.backend.files.hold();
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => page.backend.files.byteReads.isNotEmpty);
    page.backend.denied.add('file');
    held.complete(utf8.encode('needle'));
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches, isEmpty);
    expect(session.unavailableCount, 1);
  });

  _test(
      'same file node rebound while reading cannot publish the previous source',
      (tester, page) async {
    final oldView = page.backend.addFile('old', 'old.txt', 'old needle');
    final newView = page.backend.addFile('new', 'new.txt', 'new needle');
    final node = _workspaceFileNode(oldView);
    await page.insert(node);
    final held = page.backend.files.hold();
    final session = page.find()..search('needle', const FindOptions());
    await _until(tester, () => page.backend.files.byteReads.isNotEmpty);
    await page.editor.apply(
      page.editor.transaction
        ..updateNode(
          node,
          workspaceFileBlockAttributes(
            reference: newView.workspaceFileReference!,
            showPreview: true,
          ),
        ),
      withUpdateSelection: false,
    );
    await tester.pump();
    expect(page.backend.files.byteReads, hasLength(1));
    held.complete(utf8.encode('old needle'));
    await _until(tester, () => !session.loadingReferences);
    expect(session.matches.single.match.input, 'new needle');
    expect(session.matches.single.node, same(node));
    expect(session.matches.single.viewId, 'new');
  });

  _test(
      'known captions and equation source update read-only; raw attributes and pixels do not',
      (tester, page) async {
    final image = customImageNode(url: 'https://invalid.test/image.png')
      ..updateAttributes(
        {'caption': 'needle caption', 'ocr_text': 'hidden secret'},
      );
    final equation = mathEquationNode(formula: 'needle + x');
    await page.insert(image);
    await page.insert(equation);
    final before = page.editor.document.toJson();
    final session = page.find()..search('needle', const FindOptions());
    expect(session.matches, hasLength(2));
    expect(
      session.matches.every((hit) => !hit.isWritable && hit.selection == null),
      isTrue,
    );
    expect(await session.replaceAll('wrong'), isFalse);
    expect(page.editor.document.toJson(), before);
    expect(session.unavailableCount, greaterThan(0));
    expect(page.backend.nativeCalls, isEmpty);
    expect(page.backend.files.calls, isEmpty);
    await page.editor.apply(
      page.editor.transaction..updateNode(image, {'caption': 'changed'}),
      withUpdateSelection: false,
    );
    await tester.pump();
    expect(session.matches.single.node, same(equation));
    session.search('hidden secret', const FindOptions());
    expect(session.matches, isEmpty);
    final decoded = documentFindDocumentContent(
      _document([
        customImageNode(url: 'unused')..updateAttributes({'caption': 'needle'}),
        mathEquationNode(formula: 'needle + y'),
      ]),
      const DocumentFindReference('linked'),
      const DocumentFindLimits(),
    );
    expect(
      decoded.texts.where((text) => text.text.contains('needle')),
      hasLength(2),
    );
    expect(decoded.unavailable, isTrue);
  });
}

void _test(String name, Future<void> Function(WidgetTester, _Page) body) {
  testWidgets(
    name,
    (tester) async {
      final page = _Page();
      try {
        await body(tester, page);
        expect(tester.takeException(), isNull);
      } finally {
        await page.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

class _Page {
  _Page() {
    editor.disableSealTimer = true;
    backend.views[view.id] = view;
    _writes = editor.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after && event.$2.operations.isNotEmpty) {
        writes++;
      }
    });
  }

  final editor = EditorState(
    document: Document(root: pageNode(children: [paragraphNode(text: 'body')])),
  );
  final backend = _ReadBoundary();
  ViewPB view = ViewPB(id: 'owner', name: 'Page');
  final viewChanges = StreamController<ViewPB>.broadcast(sync: true);
  final titleKey = GlobalKey();
  final titleFocus = FocusNode();
  DocumentFindTitleController? titleController;
  EditorScrollController? scroll;
  late final StreamSubscription<EditorTransactionValue> _writes;
  final sessions = <DocumentFindSession>[];
  BuildContext? owner;
  int writes = 0;
  bool active = true;
  bool allowReplace = true;

  void rename(String title) {
    view = ViewPB()
      ..mergeFromMessage(view)
      ..name = title;
    backend.views[view.id] = view;
    titleController?.text = title;
    viewChanges.add(view);
  }

  Future<void> insert(Node node) async {
    editor.disableSealTimer = true;
    await editor.apply(
      editor.transaction
        ..insertNode(
          [editor.document.root.children.length],
          node,
          deepCopy: false,
        ),
      withUpdateSelection: false,
    );
  }

  DocumentFindSession find({
    DocumentFindLimits limits = const DocumentFindLimits(),
    DocumentFindReadProvider? referenceProvider,
  }) {
    editor.disableSealTimer = true;
    final session = DocumentFindSession(
      editor,
      currentView: () => view,
      viewChanges: viewChanges.stream,
      referenceProvider: referenceProvider ?? backend.provider,
      isOwnerActive: () => active,
      canReplace: () => allowReplace,
      limits: limits,
    );
    sessions.add(session);
    return session;
  }

  void open({
    bool replace = false,
    DocumentFindReadProvider? referenceProvider,
  }) =>
      DocumentFindMenu.show(
        owner!,
        editor,
        replace: replace,
        currentView: () => view,
        viewChanges: viewChanges.stream,
        referenceProvider: referenceProvider ?? backend.provider,
        canReplace: () => allowReplace,
        isSelected: () => active,
      );

  Future<void> mount(WidgetTester tester, {String mode = 'light'}) async {
    editor.disableSealTimer = true;
    scroll ??= EditorScrollController(editorState: editor);
    titleController ??=
        DocumentFindTitleController(editorState: editor, text: view.name);
    final theme = DesktopAppearance()
        .getThemeData(
          mode == 'paper'
              ? AppTheme.builtins
                  .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
              : AppTheme.fallback,
          mode == 'dark' ? Brightness.dark : Brightness.light,
          'Ahem',
          'Ahem',
        )
        .copyWith(platform: TargetPlatform.windows);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero,
        home: AppFlowyTheme(
          data: mode == 'dark'
              ? AppFlowyDefaultTheme().dark()
              : AppFlowyDefaultTheme().light(),
          child: Scaffold(
            body: ValueListenableBuilder<EditorState?>(
              valueListenable: DocumentFindMenu.activeEditorListenable,
              builder: (_, activeEditor, child) => ContextualFindRegion(
                onFind: open,
                onReplace: () => open(replace: true),
                onDismiss: () => DocumentFindMenu.dismiss(editorState: editor),
                findInEditable: true,
                findOpen: identical(editor, activeEditor),
                findFocusNode: identical(editor, activeEditor)
                    ? DocumentFindMenu.findFocusNode
                    : null,
                isSelected: () => active,
                child: child!,
              ),
              child: Builder(
                builder: (context) {
                  owner = context;
                  return AppFlowyEditor(
                    editorState: editor,
                    editorScrollController: scroll,
                    header: _Title(page: this),
                    editorStyle: EditorStyle.desktop(
                      padding: const EdgeInsets.all(24),
                      textSpanDecorator: (
                        context,
                        node,
                        start,
                        text,
                        before,
                        after,
                      ) =>
                          decorateWithSearchHighlight(
                        context,
                        node,
                        start,
                        after,
                      ),
                    ),
                    blockComponentBuilders: {
                      ...standardBlockComponentBuilderMap,
                      SpreadsheetBlockKeys.type:
                          SpreadsheetBlockComponentBuilder(),
                      PagePreviewBlockKeys.type: _ReferenceBuilder(),
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    DocumentFindMenu.dismiss(editorState: editor);
    for (final session in sessions) {
      session.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    unawaited(_writes.cancel());
    unawaited(viewChanges.close());
    backend.dispose();
    scroll?.dispose();
    titleController?.dispose();
    titleFocus.dispose();
    if (!editor.isDisposed) editor.dispose();
    editor.editableNotifier.dispose();
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump();
  }
}

class _ReadBoundary {
  _ReadBoundary() {
    files.onRead = (path) => readOrder.add('file:$path');
  }

  final views = <String, ViewPB>{};
  final documents = <String, DocumentDataPB>{};
  final fields = <String, List<FieldPB>>{};
  final rows = <String, List<RowMetaPB>>{};
  final cells = <(String, String, String), CellPB?>{};
  final denied = <String>{};
  final failedPreflight = <String>{};
  final viewReads = <String>[];
  final documentReads = <String>[];
  final rowReads = <String>[];
  final bulkReads = <String>[];
  final cellReads = <(String, String, String)>[];
  final nativeCalls = <String>[];
  final readOrder = <String>[];
  final files = _FileBoundary();
  final scheduler = DocumentFindReadScheduler();
  Duration deadline = const Duration(seconds: 3);
  final access = ValueNotifier(0);
  final changes = StreamController<String>.broadcast(sync: true);
  final pending = <String, Completer<DocumentDataPB?>>{};
  final heldDocuments = <Completer<DocumentDataPB?>>[];
  final heldStages = <Completer<void>>[];
  String? _heldStage;
  Completer<void>? _stageGate;
  int concurrentReads = 0;
  int maximumConcurrentReads = 0;

  late final provider = makeProvider();

  DocumentFindReadProvider makeProvider({
    bool sharedScheduler = false,
    bool typedCells = true,
    bool localFiles = true,
  }) =>
      DocumentFindReadProvider(
        scheduler: sharedScheduler ? null : scheduler,
        deadline: deadline,
        fileAccess: localFiles ? files : null,
        readView: (id) => _read('view:$id', () {
          viewReads.add(id);
          return views[id];
        }),
        preflight: (view) => _read('preflight:${view.id}', () {
          if (failedPreflight.contains(view.id)) {
            throw StateError('preflight failed');
          }
          return !denied.contains(view.id);
        }),
        readDocument: (id) => _read('document:$id', () async {
          documentReads.add(id);
          final held = pending.remove(id);
          return held == null ? documents[id] : await held.future;
        }),
        readRows: (id) async {
          bulkReads.add(id);
          throw StateError('Unsafe GetRowsAsText boundary must never run');
        },
        readCell: !typedCells
            ? null
            : (id, row, field) => _read(
                  'cell:$id:${row.id}:${field.id}',
                  () {
                    final key = (id, row.id, field.id);
                    cellReads.add(key);
                    if (cells.containsKey(key)) return cells[key];
                    return CellPB(
                      fieldId: field.id,
                      rowId: row.id,
                      fieldType: field.fieldType,
                      data: utf8.encode(
                        field.id == 'name' ? 'needle row' : 'Ready',
                      ),
                    );
                  },
                ),
        readViewRows: (id) => _read('membership:$id', () {
          rowReads.add(id);
          return rows[id] ?? [RowMetaPB(id: 'visible')];
        }),
        readFields: (id, _) => _read(
          'fields:$id',
          () =>
              fields[id] ??
              [
                FieldPB(
                  id: 'name',
                  name: 'Name',
                  fieldType: FieldType.RichText,
                ),
                FieldPB(
                  id: 'status',
                  name: 'Status',
                  fieldType: FieldType.RichText,
                ),
              ],
        ),
        accessChanges: access,
        contentChanges: changes.stream,
      );

  Future<T> _read<T>(String stage, FutureOr<T> Function() read) async {
    nativeCalls.add(stage);
    readOrder.add(stage);
    concurrentReads++;
    if (concurrentReads > maximumConcurrentReads) {
      maximumConcurrentReads = concurrentReads;
    }
    try {
      if (stage == _heldStage) {
        _heldStage = null;
        await _stageGate!.future;
      }
      return await read();
    } finally {
      concurrentReads--;
    }
  }

  Completer<void> holdStage(String stage) {
    _heldStage = stage;
    final gate = _stageGate = Completer<void>();
    heldStages.add(gate);
    return gate;
  }

  void addDocument(
    String id,
    List<Node> nodes, {
    String title = 'Linked page',
  }) {
    views[id] = ViewPB(id: id, name: title, layout: ViewLayoutPB.Document);
    documents[id] = _document(nodes);
  }

  void addDatabase(String id) {
    views[id] = ViewPB(id: id, name: 'Tasks', layout: ViewLayoutPB.Grid);
  }

  ViewPB addFile(String id, String name, String text, {String? source}) {
    source ??= files.path('$id${p.extension(name)}');
    files.bytes[source] = utf8.encode(text);
    return views[id] = ViewPB(
      id: id,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: source,
      ).mergeIntoExtra(''),
    );
  }

  Completer<DocumentDataPB?> hold(String id) {
    final gate = pending[id] = Completer<DocumentDataPB?>();
    heldDocuments.add(gate);
    return gate;
  }

  void dispose() {
    for (final gate in heldDocuments) {
      if (!gate.isCompleted) gate.complete(null);
    }
    for (final gate in heldStages) {
      if (!gate.isCompleted) gate.complete();
    }
    files.dispose();
    access.dispose();
    unawaited(changes.close());
  }
}

class _FileBoundary extends DocumentFindFileAccess {
  final root = Platform.isWindows ? r'C:\FindStorage' : '/find-storage';
  final bytes = <String, List<int>>{};
  final resolved = <String, String>{};
  final canonical = <String, String>{};
  final calls = <String>[];
  final resolves = <String>[];
  final byteReads = <String>[];
  final readLimits = <int>[];
  final held = <Completer<List<int>?>>[];
  Completer<List<int>?>? _gate;
  void Function(String)? onRead;
  String path(String name) => p.join(root, 'files', name);

  @override
  Future<String?> storageRoot() async {
    calls.add('root');
    return root;
  }

  @override
  Future<String?> resolve(String source) async {
    calls.add('resolve');
    resolves.add(source);
    return resolved[source] ?? source;
  }

  @override
  Future<String> canonicalPath(String path, {bool directory = false}) async {
    calls.add('canonical');
    return canonical[path] ?? path;
  }

  @override
  Future<List<int>?> readBytes(String path, int limit) async {
    calls.add('bytes');
    byteReads.add(path);
    readLimits.add(limit);
    onRead?.call(path);
    final gate = _gate;
    _gate = null;
    return gate != null
        ? await gate.future
        : bytes[path]?.take(limit + 1).toList();
  }

  Completer<List<int>?> hold() {
    final gate = _gate = Completer<List<int>?>();
    held.add(gate);
    return gate;
  }

  void dispose() {
    for (final gate in held) {
      if (!gate.isCompleted) gate.complete(null);
    }
  }
}

Node _workspaceFileNode(ViewPB view) => Node(
      type: FileBlockKeys.type,
      attributes: workspaceFileBlockAttributes(
        reference: view.workspaceFileReference!,
        showPreview: true,
      ),
    );

DocumentDataPB _document(List<Node> nodes) => DocumentDataPBFromTo.fromDocument(
      Document(root: pageNode(children: nodes)),
    )!;

Node _databaseNode(String id) =>
    Node(type: 'grid', attributes: {'view_id': id, 'parent_id': 'owner'});

/// Native editor block shell, without mounting a backend-owned page preview.
/// Its contents are intentionally not the indexed text: the snippet must show
/// the real read-boundary result, not this placeholder or a fabricated delta.
class _ReferenceBuilder extends BlockComponentBuilder {
  @override
  BlockComponentWidget build(BlockComponentContext context) =>
      _ReferenceBlock(key: context.node.key, node: context.node);
}

class _ReferenceBlock extends BlockComponentStatelessWidget {
  const _ReferenceBlock({super.key, required super.node})
      : super(configuration: const BlockComponentConfiguration());
  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 120, child: Text('Native preview surface'));
}

class _Title extends StatefulWidget {
  const _Title({required this.page});
  final _Page page;
  @override
  State<_Title> createState() => _TitleState();
}

class _TitleState extends State<_Title> {
  @override
  void initState() {
    super.initState();
    DocumentFindTitle.of(widget.page.editor).attach(
      widget.page.titleController!,
      () => widget.page.titleKey.currentContext ?? context,
    );
  }

  @override
  void dispose() {
    DocumentFindTitle.of(widget.page.editor)
        .detach(widget.page.titleController!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 180,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: ListenableBuilder(
              listenable: DocumentSearchHighlight.instance,
              builder: (context, _) => TextField(
                key: widget.page.titleKey,
                controller: widget.page.titleController,
                focusNode: widget.page.titleFocus,
                maxLines: null,
                style: const TextStyle(fontSize: 32),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
          ),
        ),
      );
}

FindReplaceBar _bar(WidgetTester tester) =>
    tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));

Future<void> _query(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const ValueKey('findTextField')), query);
  await tester.pump();
  await tester.pump();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 80; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'Bounded wait for document Find state');
}

Iterable<(String, TextStyle)> _spanRuns(
  InlineSpan span, [
  TextStyle inherited = const TextStyle(),
]) sync* {
  if (span is! TextSpan) return;
  final style = inherited.merge(span.style);
  if (span.text?.isNotEmpty ?? false) yield (span.text!, style);
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _spanRuns(child, style);
  }
}
