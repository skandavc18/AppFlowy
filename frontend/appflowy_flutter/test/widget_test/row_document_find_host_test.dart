import 'dart:ui' as ui;

import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_host.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_title.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'document_find_host_test_support.dart';

void main() {
  setUpFindHostTests();

  for (final popup in [true, false]) {
    for (final mode in ['light', 'dark', 'paper']) {
      _hostTest(
        '${popup ? 'popup' : 'full page'} $mode: real row title and ID',
        (tester, host) async {
          host.title.text = 'Visible needle row title with needle';
          await host.mount(tester, mode: mode);
          await untilFindHost(tester, () => host.scope!.canReplace);
          final nativeEditor = tester.element(find.byType(AppFlowyEditor));
          final field = tester.widget<TextField>(find.byKey(rowFindTitleKey));
          final fieldElement = tester.element(find.byKey(rowFindTitleKey));
          expect(field.controller, same(host.title));
          expect(field.focusNode, same(host.titleFocus));
          expect(DocumentFindTitle.of(host.editor).text, host.title.text);

          await host.open(tester);
          final value = host.title.value;
          final notifications = host.titleNotifications;
          final before = host.editor.document.toJson();
          await findHostQuery(tester, 'needle');
          final menu = findHostMenu(tester);
          expect(menu.currentView!()!.id, host.document.documentId);
          expect(menu.currentView!()!.id, isNot(host.view.state.view.id));
          expect(menu.currentView!()!.name, 'Orphan default name');
          expect(host.repository.accessReads, everyElement('table'));
          expect(findHostBar(tester).matchCount, 3);
          expect(findHostBar(tester).currentMatch, 1);
          expect(find.text('Read-only match · Title'), findsOneWidget);
          expect(findHostBar(tester).onReplace, isNull);
          expect(findHostBar(tester).onReplaceAll, isNotNull);
          expect(findHostBar(tester).findFocusNode.hasPrimaryFocus, isTrue);
          expect(host.title.value, value);
          expect(host.titleNotifications, notifications);
          expect(host.titleSubmits, 0);
          expect(host.bodyWrites, 0);
          expect(host.editor.document.toJson(), before);
          expect(
            tester.element(find.byType(AppFlowyEditor)),
            same(nativeEditor),
          );
          expect(
            tester.element(find.byKey(rowFindTitleKey)),
            same(fieldElement),
          );

          final start = host.title.text.indexOf('needle');
          final end = host.title.text.lastIndexOf('needle');
          final first =
              TextSelection(baseOffset: start, extentOffset: start + 6);
          final second = TextSelection(baseOffset: end, extentOffset: end + 6);
          final brightness =
              mode == 'dark' ? Brightness.dark : Brightness.light;
          final matchColor = FindHighlightColors.match(brightness);
          final currentColor = FindHighlightColors.current(brightness);
          _expectTitlePaint(tester, [
            (first, currentColor),
            (second, matchColor),
          ]);
          final queryElement = tester.element(
            find.byKey(const ValueKey('findTextField')),
          );
          final queryFocus = findHostBar(tester).findFocusNode;
          final titleSelection = host.editor.selection;
          findHostBar(tester).onNext!();
          await tester.pump();
          await tester.pump();
          expect(findHostBar(tester).currentMatch, 2);
          expect(host.editor.selection, titleSelection);
          _expectTitlePaint(tester, [
            (first, matchColor),
            (second, currentColor),
          ]);

          findHostBar(tester).onNext!();
          await tester.pump();
          await tester.pump();
          expect(findHostBar(tester).currentMatch, 3);
          expect(findHostBar(tester).onReplace, isNotNull);
          expect(find.text('Read-only match · Title'), findsNothing);
          final bodySelection = Selection.single(
            path: [0],
            startOffset: 0,
            endOffset: 6,
          );
          expect(host.editor.selection, bodySelection);
          _expectTitlePaint(tester, [
            (first, matchColor),
            (second, matchColor),
          ]);
          expect(findHostBar(tester).findFocusNode, same(queryFocus));
          expect(queryFocus.hasPrimaryFocus, isTrue);
          expect(
            tester.element(find.byKey(const ValueKey('findTextField'))),
            same(queryElement),
          );

          // Closing Find deliberately retains its body selection. A new query
          // anchors there, rather than promoting every title mark to current.
          findHostBar(tester).onClose();
          await tester.pump();
          await tester.pump();
          expect(host.editor.selection, bodySelection);
          await host.open(tester, fromTitle: false);
          await findHostQuery(tester, 'needle');
          expect(findHostBar(tester).currentMatch, 3);
          expect(host.editor.selection, bodySelection);
          _expectTitlePaint(tester, [
            (first, matchColor),
            (second, matchColor),
          ]);
          findHostBar(tester).onPrevious!();
          await tester.pump();
          await tester.pump();
          expect(findHostBar(tester).currentMatch, 2);
          expect(findHostBar(tester).onReplace, isNull);
          expect(find.text('Read-only match · Title'), findsOneWidget);
          _expectTitlePaint(tester, [
            (first, matchColor),
            (second, currentColor),
          ]);
          expect(findHostBar(tester).findFocusNode.hasPrimaryFocus, isTrue);
          expect(host.title.value, value);
          expect(host.titleNotifications, notifications);
          expect(host.titleSubmits, 0);
          expect(host.bodyWrites, 0);
          expect(host.editor.document.toJson(), before);
          expect(
            tester.widget<TextField>(find.byKey(rowFindTitleKey)).controller,
            same(host.title),
          );
          if (mode == 'paper') {
            expect(
              FindBarPalette.of(tester.element(find.byType(FindReplaceBar)))
                  .surface,
              PaperTheme.popupBackground,
            );
          }

          await findHostQuery(tester, 'Table name');
          expect(findHostBar(tester).matchCount, 0);
          await findHostQuery(tester, 'Orphan default name');
          expect(findHostBar(tester).matchCount, 0);
          await findHostQuery(tester, 'needle');
          // The last body caret anchors the new query to its body match. Select
          // a title result before asserting that closing leaves the title visible.
          findHostBar(tester).onPrevious!();
          await tester.pump();
          await tester.pump();
          findHostBar(tester).onClose();
          await tester.pump();
          await tester.tap(find.byKey(rowFindTitleKey));
          await tester.pump();
          expect(host.titleFocus.hasPrimaryFocus, isTrue);
          expect(
            tester.widget<TextField>(find.byKey(rowFindTitleKey)).controller,
            same(host.title),
          );
        },
        popup: popup,
      );
    }
  }

  _hostTest(
      'Replace All leaves real primary-cell draft and backend callbacks alone',
      (tester, host) async {
    await host.mount(tester);
    await untilFindHost(tester, () => host.scope!.canReplace);
    host.title.value = const TextEditingValue(
      text: 'Unsaved needle cell draft',
      selection: TextSelection(baseOffset: 8, extentOffset: 14),
    );
    await tester.pump();
    await host.open(tester, replace: true);
    await findHostQuery(tester, 'needle');
    final draft = host.title.value;
    final notifications = host.titleNotifications;
    final before = host.editor.document.toJson();
    await tester.enterText(
      find.byKey(const ValueKey('replaceTextField')),
      'found',
    );
    findHostBar(tester).onReplaceAll!();
    await tester.pump();
    await tester.pump();
    expect(host.editor.document.first!.delta!.toPlainText(), 'found body');
    expect(host.bodyWrites, 1);
    expect(host.title.value, draft);
    expect(host.titleNotifications, notifications);
    expect(host.titleSubmits, 0);
    expect(host.view.events, isEmpty);
    expect(findHostBar(tester).matchCount, 1);
    expect(findHostBar(tester).onReplaceAll, isNull);
    host.editor.undoManager.undo();
    await tester.pump();
    expect(host.editor.document.toJson(), before);
    expect(host.title.value, draft);
  });

  _hostTest(
      'native composing value and focus survive paint-only title navigation',
      (tester, host) async {
    await host.mount(tester);
    await untilFindHost(tester, () => host.scope!.canReplace);
    await host.open(tester);
    await findHostQuery(tester, 'needle');
    final bar = findHostBar(tester);
    final queryElement =
        tester.element(find.byKey(const ValueKey('findTextField')));
    host.title.value = const TextEditingValue(
      text: 'needle composing needle',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 0, end: 6),
    );
    await tester.pump();
    await tester.pump();
    final value = host.title.value;
    final notifications = host.titleNotifications;
    expect(findHostBar(tester).matchCount, 3);
    findHostBar(tester).onNext!();
    await tester.pump();
    expect(host.title.value, value);
    expect(host.titleNotifications, notifications);
    expect(findHostBar(tester).findFocusNode, same(bar.findFocusNode));
    expect(bar.findFocusNode.hasPrimaryFocus, isTrue);
    expect(
      tester.element(find.byKey(const ValueKey('findTextField'))),
      same(queryElement),
    );
    expect(host.titleSubmits, 0);
    expect(host.bodyWrites, 0);
  });

  _hostTest('the writable native body footer still inserts an empty paragraph',
      (tester, host) async {
    await host.mount(tester);
    await untilFindHost(tester, () => host.editor.editable);
    final footer = tester
        .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
        .footer! as GestureDetector;
    expect(footer.onTap, isNotNull);
    footer.onTap!();
    await tester.pump();
    await tester.pump();
    expect(host.editor.document.root.children, hasLength(2));
    expect(host.editor.document.root.children.last.delta!.toPlainText(), '');
    expect(host.bodyWrites, 1);
    expect(host.titleSubmits, 0);
  });

  for (final guard in [
    'read only',
    'locked local',
    'missing table',
    'missing access',
  ]) {
    _hostTest(
        '$guard: native row authority denies Replace, not body/title Find',
        (tester, host) async {
      if (guard == 'read only') {
        host.repository.access = ShareAccessLevel.readOnly;
      }
      if (guard == 'locked local') {
        host.repository.views['table']!.isLocked = true;
      }
      if (guard == 'missing table') host.repository.failedViews.add('table');
      if (guard == 'missing access') host.repository.failAccess = true;
      await host.mount(tester);
      await host.open(tester);
      await findHostQuery(tester, 'needle');
      expect(host.scope!.canReplace, isFalse);
      expect(host.editor.editable, isFalse);
      final native = tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor));
      expect(native.editable, isFalse);
      expect((native.footer! as GestureDetector).onTap, isNull);
      expect(findHostBar(tester).matchCount, 2);
      expect(findHostBar(tester).replaceController, isNull);
      expect(findHostBar(tester).onReplaceAll, isNull);
      expect(findHostMenu(tester).canReplace!(), isFalse);
      findHostBar(tester).onNext!();
      await tester.pump();
      expect(host.bodyWrites, 0);
      expect(host.titleSubmits, 0);
    });
  }

  _hostTest(
      'delayed permission enables only after final authoritative table lock read',
      (tester, host) async {
    final permission = host.repository.holdAccess();
    await host.mount(tester);
    await untilFindHost(tester, () => host.repository.accessReads.isNotEmpty);
    await host.open(tester);
    await findHostQuery(tester, 'needle');
    final query = tester.element(find.byKey(const ValueKey('findTextField')));
    expect(host.editor.editable, isFalse);
    expect(findHostBar(tester).matchCount, 2);
    expect(findHostMenu(tester).canReplace!(), isFalse);
    // Even with no notification, a lock changed during an awaited access read
    // must be caught by the native guard's second table read.
    host.repository.views['table']!.isLocked = true;
    permission.complete(FlowyResult.success(ShareAccessLevel.fullAccess));
    await tester.pump();
    await tester.pump();
    expect(
      host.repository.viewReads.where((id) => id == 'table'),
      hasLength(2),
    );
    expect(host.scope!.canReplace, isFalse);
    expect(findHostBar(tester).matchCount, 2);
    expect(
      tester.element(find.byKey(const ValueKey('findTextField'))),
      same(query),
    );

    host.repository.views['table']!.isLocked = false;
    host.repository.change('table');
    await untilFindHost(tester, () => host.editor.editable);
    await tester.pump();
    expect(findHostMenu(tester).canReplace!(), isTrue);
    expect(findHostBar(tester).matchCount, 2);
    expect(findHostBar(tester).findFocusNode.hasPrimaryFocus, isTrue);
  });

  _hostTest('revocation blocks retained Replace callback before the next frame',
      (tester, host) async {
    await host.mount(tester);
    await untilFindHost(tester, () => host.scope!.canReplace);
    await host.open(tester, replace: true);
    await findHostQuery(tester, 'needle');
    final retained = findHostBar(tester).onReplaceAll!;
    final retainedFooter = (tester
            .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
            .footer! as GestureDetector)
        .onTap!;
    final before = host.editor.document.toJson();
    findHostBar(tester).replaceController!.text = 'wrong';
    final permission = host.repository.holdAccess();
    host.repository.change('table');
    expect(host.scope!.canReplace, isFalse);
    retained();
    retainedFooter();
    await tester.pump();
    permission.complete(FlowyResult.success(ShareAccessLevel.readOnly));
    await tester.pump();
    await tester.pump();
    expect(host.bodyWrites, 0);
    expect(host.editor.document.toJson(), before);
    expect(
      (tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).footer!
              as GestureDetector)
          .onTap,
      isNull,
    );
    expect(findHostBar(tester).onReplaceAll, isNull);
    expect(findHostBar(tester).matchCount, 2);
  });

  _hostTest(
    'wrong document metadata never borrows the table identity or name',
    (tester, host) async {
      host.repository.views['row-doc'] = host.repository.views['table']!;
      await host.mount(tester);
      await host.open(tester);
      await findHostQuery(tester, 'needle');
      expect(host.scope!.documentId, 'row-doc');
      expect(findHostMenu(tester).currentView!(), isNull);
      expect(findHostMenu(tester).canReplace!(), isFalse);
      expect(findHostBar(tester).matchCount, 2);
      await findHostQuery(tester, 'Table name');
      expect(findHostBar(tester).matchCount, 0);
    },
    popup: false,
  );

  for (final popup in [true, false]) {
    _hostTest(
      '${popup ? 'popup' : 'full page'} late native title mount attaches visible text, never orphan fallback',
      (tester, host) async {
        host.showTitle = false;
        await host.mount(tester);
        await untilFindHost(tester, () => host.scope!.canReplace);
        await host.open(tester);
        await findHostQuery(tester, 'Orphan default name');
        expect(findHostBar(tester).matchCount, 0);
        await findHostQuery(tester, 'needle');
        expect(findHostBar(tester).matchCount, 1);
        final scope = host.scope;
        final editorElement = tester.element(find.byType(AppFlowyEditor));
        final queryElement = tester.element(
          find.byKey(const ValueKey('findTextField')),
        );
        final queryFocus = findHostBar(tester).findFocusNode;
        host.showTitle = true;
        await host.mount(tester);
        await tester.pump();
        expect(findHostBar(tester).matchCount, 2);
        expect(findHostBar(tester).currentMatch, 2);
        expect(DocumentFindTitle.of(host.editor).text, host.title.text);
        final titleField = tester.widget<TextField>(
          find.byKey(rowFindTitleKey, skipOffstage: false),
        );
        expect(titleField.controller, same(host.title));
        expect(titleField.autofocus, isFalse);
        expect(host.scope, same(scope));
        expect(
          tester.element(find.byType(AppFlowyEditor)),
          same(editorElement),
        );
        expect(
          tester.element(find.byKey(const ValueKey('findTextField'))),
          same(queryElement),
        );
        expect(findHostBar(tester).findFocusNode, same(queryFocus));
        expect(queryFocus.hasPrimaryFocus, isTrue);
        host.showTitle = false;
        await host.mount(tester);
        await tester.pump();
        expect(findHostBar(tester).matchCount, 1);
        expect(DocumentFindTitle.of(host.editor).text, '');
        expect(host.scope, same(scope));
        expect(
          tester.element(find.byKey(const ValueKey('findTextField'))),
          same(queryElement),
        );
        expect(queryFocus.hasPrimaryFocus, isTrue);
        expect(host.bodyWrites, 0);
        expect(host.titleSubmits, 0);
      },
      popup: popup,
    );
  }

  for (final end in [
    'document deleted',
    'table deleted',
    'force close',
    'unmounted',
  ]) {
    _hostTest(
        '$end rejects retained callbacks and late native permission results',
        (tester, host) async {
      await host.mount(tester);
      await untilFindHost(tester, () => host.scope!.canReplace);
      await host.open(tester, replace: true);
      await findHostQuery(tester, 'needle');
      final retainedMenu = findHostMenu(tester);
      final retainedReplace = findHostBar(tester).onReplaceAll!;
      final retainedFooter = (tester
              .widget<AppFlowyEditor>(find.byType(AppFlowyEditor))
              .footer! as GestureDetector)
          .onTap!;
      final before = host.editor.document.toJson();
      final permission = host.repository.holdAccess();
      host.repository.change('table');
      await untilFindHost(
        tester,
        () => host.repository.accessReads.length == 2,
      );
      if (end == 'document deleted') host.document.delete();
      if (end == 'table deleted') {
        host.repository.change('table', deleted: true);
      }
      if (end == 'force close') host.document.forceClose();
      if (end == 'unmounted') {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(retainedMenu.isOwnerActive!(), isFalse);
      expect(retainedMenu.canReplace!(), isFalse);
      retainedReplace();
      retainedFooter();
      permission.complete(FlowyResult.success(ShareAccessLevel.fullAccess));
      await tester.pump();
      await tester.pump();
      expect(DocumentFindMenu.isOpen, isFalse);
      expect(host.bodyWrites, 0);
      expect(host.editor.document.toJson(), before);
      expect(host.titleSubmits, 0);
      if (end != 'unmounted') {
        expect(host.editor.editable, isFalse);
        expect(
          (tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).footer!
                  as GestureDetector)
              .onTap,
          isNull,
        );
      }
    });
  }

  _hostTest(
      'switch rebinds the real title and old callbacks cannot affect the new row',
      (tester, host) async {
    await host.mount(tester);
    await untilFindHost(tester, () => host.scope!.canReplace);
    await host.open(tester, replace: true);
    await findHostQuery(tester, 'needle');
    final oldEditor = host.editor;
    final oldMenu = findHostMenu(tester);
    final oldReplace = findHostBar(tester).onReplaceAll!;
    final oldNext = findHostBar(tester).onNext!;
    final permission = host.repository.holdAccess();
    host.repository.change('table');
    await untilFindHost(tester, () => host.repository.accessReads.length == 2);
    host.bind('next-row-doc');
    await host.mount(tester);
    await untilFindHost(tester, () => host.scope!.canReplace);
    await host.open(tester);
    await findHostQuery(tester, 'needle');
    final focus = findHostBar(tester).findFocusNode;
    permission.complete(FlowyResult.success(ShareAccessLevel.fullAccess));
    oldNext();
    oldReplace();
    await tester.pump();
    await tester.pump();
    expect(oldMenu.isOwnerActive!(), isFalse);
    expect(oldMenu.currentView!(), isNull);
    expect(findHostMenu(tester).currentView!()!.id, 'next-row-doc');
    expect(DocumentFindMenu.activeEditor, same(host.editor));
    expect(DocumentFindTitle.of(oldEditor).text, isNull);
    expect(DocumentFindTitle.of(host.editor).text, host.title.text);
    expect(focus.hasPrimaryFocus, isTrue);
    expect(host.bodyWrites, 0);
  });

  _hostTest(
    'loading actual metadata keeps an open body/title query alive',
    (tester, host) async {
      final metadata = host.repository.holdView('row-doc');
      await host.mount(tester);
      await host.open(tester);
      await findHostQuery(tester, 'needle');
      expect(findHostMenu(tester).currentView!(), isNull);
      expect(findHostBar(tester).matchCount, 2);
      metadata.complete(FlowyResult.success(host.repository.views['row-doc']!));
      await untilFindHost(tester, () => host.scope!.canReplace);
      await tester.pump();
      expect(DocumentFindMenu.isOpen, isTrue);
      expect(findHostBar(tester).matchCount, 2);
      expect(findHostMenu(tester).currentView!()!.id, 'row-doc');
      expect(findHostMenu(tester).canReplace!(), isTrue);
      // Metadata joins the already-open query without borrowing the table ID.
      findHostBar(tester).onClose();
      await tester.pump();
      await host.open(tester);
      expect(findHostMenu(tester).currentView!()!.id, 'row-doc');
    },
    popup: false,
  );

  _hostTest(
    'native metadata refresh keeps currentView live without renaming the cell',
    (tester, host) async {
      await host.mount(tester);
      await untilFindHost(tester, () => host.scope!.canReplace);
      await host.open(tester, replace: true);
      await findHostQuery(tester, 'needle');
      final menu = findHostMenu(tester);
      final queryElement = tester.element(
        find.byKey(const ValueKey('findTextField')),
      );
      final queryFocus = findHostBar(tester).findFocusNode;
      final scope = host.scope;
      final draft = host.title.value;
      final notifications = host.titleNotifications;
      final retainedReplace = findHostBar(tester).onReplaceAll!;
      findHostBar(tester).replaceController!.text = 'wrong';
      host.repository.views['row-doc'] = ViewPB(
        id: 'row-doc',
        name: 'Updated native metadata',
        isLocked: true,
      );
      host.repository.change('row-doc');
      expect(menu.canReplace!(), isFalse);
      retainedReplace();
      await untilFindHost(
        tester,
        () => menu.currentView!()?.name == 'Updated native metadata',
      );
      await tester.pump();
      expect(host.scope, same(scope));
      expect(menu.currentView!()!.id, host.document.documentId);
      expect(menu.currentView!()!.isLocked, isTrue);
      expect(menu.isOwnerActive!(), isTrue);
      expect(host.editor.editable, isFalse);
      expect(findHostBar(tester).matchCount, 2);
      expect(findHostBar(tester).onReplaceAll, isNull);
      expect(
        tester.element(find.byKey(const ValueKey('findTextField'))),
        same(queryElement),
      );
      expect(findHostBar(tester).findFocusNode, same(queryFocus));
      expect(queryFocus.hasPrimaryFocus, isTrue);
      expect(host.title.value, draft);
      expect(host.titleNotifications, notifications);
      expect(DocumentFindTitle.of(host.editor).text, draft.text);
      expect(host.bodyWrites, 0);
      expect(host.titleSubmits, 0);
      expect(host.view.events, isEmpty);
      await findHostQuery(tester, 'Updated native metadata');
      expect(findHostBar(tester).matchCount, 0);
    },
    popup: false,
  );

  _hostTest(
      'inherited loading/read-only table bloc cannot be bypassed by native grant',
      (tester, host) async {
    final access =
        host.inheritedAccess = FindHostAccess(host.repository.views['table']!);
    access.update(access.state.copyWith(isLoadingLockStatus: true));
    await host.mount(tester);
    await untilFindHost(tester, () => host.scope!.canReplace);
    await host.open(tester);
    await findHostQuery(tester, 'needle');
    expect(findHostMenu(tester).canReplace!(), isFalse);
    expect(host.editor.editable, isFalse);
    access.update(
      access.state.copyWith(
        isLoadingLockStatus: false,
        accessLevel: ShareAccessLevel.readOnly,
      ),
    );
    await tester.pump();
    expect(findHostMenu(tester).canReplace!(), isFalse);
    expect(findHostBar(tester).matchCount, 2);
  });

  _hostTest('restoring a row document cannot revive a still-deleted table',
      (tester, host) async {
    await host.mount(tester);
    await untilFindHost(tester, () => host.scope!.canReplace);
    host.repository.change('row-doc', deleted: true);
    host.repository.change('table', deleted: true);
    host.repository.changes.add(
      const DocumentFindHostChange(
        'row-doc',
        kind: DocumentFindHostChangeKind.restored,
      ),
    );
    await tester.pump();
    expect(host.scope!.isActive, isFalse);
    expect(host.scope!.canReplace, isFalse);
    expect(host.editor.editable, isFalse);
  });

  for (final popup in [true, false]) {
    _hostTest(
      '${popup ? 'popup' : 'full page'} retains and reveals the offscreen real title',
      (tester, host) async {
        await host.editor.apply(
          host.editor.transaction
            ..insertNodes([
              1,
            ], [
              for (var i = 0; i < 80; i++)
                paragraphNode(text: 'Filler paragraph $i'),
            ]),
          withUpdateSelection: false,
        );
        await host.mount(tester);
        await untilFindHost(tester, () => host.scope!.canReplace);
        host.titleFocus.unfocus();
        await tester.pump();
        final retained = find.byKey(rowFindTitleKey, skipOffstage: false);
        final field = tester.element(retained);
        final writes = host.bodyWrites;
        final draft = host.title.value;
        final notifications = host.titleNotifications;
        // Exercise real offscreen scrolling. Indexed jumpTo rebases the native
        // list into different slivers, outside its keep-alive identity contract.
        // A wheel scroll retires the header in its existing sliver instead.
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getBottomRight(find.byType(AppFlowyEditor)) -
                const Offset(64, 96),
            scrollDelta: const Offset(0, 2400),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(host.editor.scrollService!.dy, greaterThan(1000));
        expect(find.byKey(rowFindTitleKey).hitTestable(), findsNothing);
        expect(tester.element(retained), same(field));
        expect(DocumentFindTitle.of(host.editor).text, host.title.text);
        expect(
          ContextualFindRegion.dispatch(
            tester.element(find.byType(AppFlowyEditor)),
          ),
          isTrue,
        );
        await tester.pump();
        await findHostQuery(tester, 'Visible needle row title');
        await untilFindHost(
          tester,
          () => find.byKey(rowFindTitleKey).hitTestable().evaluate().isNotEmpty,
        );
        expect(findHostBar(tester).matchCount, 1);
        expect(find.text('Read-only match · Title'), findsOneWidget);
        expect(tester.element(retained), same(field));
        expect(tester.widget<TextField>(retained).controller, same(host.title));
        expect(findHostBar(tester).findFocusNode.hasPrimaryFocus, isTrue);
        expect(host.title.value, draft);
        expect(host.titleNotifications, notifications);
        expect(host.bodyWrites, writes);
        expect(host.titleSubmits, 0);
      },
      popup: popup,
    );
  }
}

void _hostTest(
  String name,
  Future<void> Function(WidgetTester, RowFindHarness) body, {
  bool popup = true,
}) {
  testWidgets(
    name,
    (tester) => withFindHostStorage(() async {
      final host = RowFindHarness(popup: popup);
      try {
        await body(tester, host);
        expect(tester.takeException(), isNull);
      } finally {
        await host.dispose(tester);
      }
    }),
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

void _expectTitlePaint(
  WidgetTester tester,
  List<(TextSelection, Color)> matches,
) {
  final editable = tester
      .state<EditableTextState>(
        find.descendant(
          of: find.byKey(rowFindTitleKey, skipOffstage: false),
          matching: find.byType(EditableText, skipOffstage: false),
          skipOffstage: false,
        ),
      )
      .renderEditable;
  final canvas = _RecordingCanvas();
  expect(editable.painter, isNotNull);
  editable.painter!.paint(canvas, editable.size, editable);
  final rectangles = <Rect>[];
  final colors = <Color>[];
  for (final (selection, color) in matches) {
    for (final box in editable.getBoxesForSelection(selection)) {
      rectangles.add(box.toRect());
      // Paint stores float32 channels; comparing its result with the original
      // double-precision Color fails even when their printed values agree.
      colors.add((Paint()..color = color).color);
    }
  }
  expect(canvas.rectangles, isNotEmpty);
  expect(canvas.rectangles, rectangles);
  expect(canvas.colors, colors);
}

class _RecordingCanvas extends Fake implements Canvas {
  final rectangles = <Rect>[];
  final colors = <Color>[];
  @override
  void save() {}
  @override
  void restore() {}
  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {}
  @override
  void drawRect(Rect rect, Paint paint) {
    rectangles.add(rect);
    colors.add(paint.color);
  }
}
