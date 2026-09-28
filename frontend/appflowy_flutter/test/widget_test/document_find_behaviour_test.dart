import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/callout/callout_block_component.dart'
    as callouts;
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_search_highlight.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/find_and_replace_menu.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Real EditorState, document nodes, builders, selections, scroll services and
// undo/redo. No backend, SearchService mock, persistence or network fixture.
void main() {
  _test(
    'literal metacharacters, UTF-16 offsets and metadata exclusion',
    (tester, doc) async {
      await doc.mount(tester);
      final before = doc.editor.document.toJson();
      await _query(tester, '[v1].*');
      expect(_bar(tester).matchCount, 1);
      expect(doc.editor.selection?.start.offset, 3);
      expect(doc.editor.selection?.end.offset, 9);
      await _query(tester, 'private-needle');
      expect(_bar(tester).matchCount, 0);
      expect(_bar(tester).queryInvalid, isFalse);
      expect(doc.editor.document.toJson(), before);
      expect(doc.writes, 0);
    },
    nodes: () => [
      paragraphNode(text: '🙂 [v1].* visible')
        ..updateAttributes({
          'href': 'private-needle',
          'metadata': {'text': 'private-needle'},
        }),
    ],
  );

  _test(
    'case, whole word, multiline regex, invalid and zero-width patterns',
    (tester, doc) async {
      await doc.mount(tester);
      await _query(tester, 'needle');
      expect(_bar(tester).matchCount, 3);
      await _options(tester, const FindOptions(wholeWord: true));
      expect(_bar(tester).matchCount, 2);
      await _options(
        tester,
        const FindOptions(wholeWord: true, caseSensitive: true),
      );
      expect(_bar(tester).matchCount, 1);
      await _options(tester, const FindOptions(useRegex: true));
      await _query(tester, r'^needle$');
      expect(_bar(tester).matchCount, 1);
      await _query(tester, '[');
      expect(_bar(tester).queryInvalid, isTrue);
      expect(_bar(tester).matchCount, 0);
      expect(DocumentSearchHighlight.instance.rangesOf(doc.first), isEmpty);
      await _query(tester, '(?=needle)');
      expect(_bar(tester).queryInvalid, isFalse);
      expect(_bar(tester).matchCount, 0);
      await _query(tester, '');
      expect(_bar(tester).currentMatch, 0);
      expect(doc.writes, 0);
    },
    nodes: () => [paragraphNode(text: 'Needle needles\nneedle')],
  );

  _test(
    'nested list, callout, table and offscreen hits use real paths',
    (tester, doc) async {
      await doc.mount(tester);
      final tail = doc.editor.document.root.children.last;
      expect(tail.key.currentContext, isNull);
      const expected = <(List<int>, int, int, String)>[
        ([0], 0, 6, 'Needle list'),
        ([0, 0], 9, 15, 'Numbered Needle'),
        ([0, 0, 0], 5, 11, 'deep needle'),
        ([1], 8, 14, 'Callout Needle'),
        ([1, 0], 7, 13, 'Nested Needle'),
        ([2, 0, 0], 5, 11, 'Cell Needle'),
        ([183], 10, 16, 'Offscreen Needle'),
      ];

      Future<void> expectHit(int index) async {
        final (path, start, end, text) = expected[index];
        final node = doc.editor.getNodeAtPath(path)!;
        final selection =
            Selection.single(path: path, startOffset: start, endOffset: end);
        expect(node.delta!.toPlainText(), text);
        // Native TableCol sizing applies a transaction with the same selection,
        // including when its highlighted cell is unmounted by the next jump.
        // Its reason becomes `transaction`; wait for the actual hit, not the tag.
        await _pumpUntil(
          tester,
          reason: 'visible find hit ${index + 1}/${expected.length} '
              'at $path [$start, $end): "$text"',
          ready: () {
            if (doc.editor.selection != selection) return false;
            final viewport = doc.editor.renderBox;
            if (viewport == null || !viewport.attached || !viewport.hasSize) {
              return false;
            }
            final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
            final rects = doc.editor.selectionRects();
            return rects.isNotEmpty &&
                rects.every(
                  (rect) => !rect.isEmpty && rect.intersect(bounds) == rect,
                );
          },
        );
        expect(_bar(tester).findController.text, 'needle');
        expect(_bar(tester).matchCount, expected.length);
        expect(_bar(tester).currentMatch, index + 1);
        expect(doc.editor.selection, selection);
        expect(
          DocumentSearchHighlight.instance.rangesOf(node),
          [TextRange(start: start, end: end)],
        );
        expect(
          DocumentSearchHighlight.instance.currentRangeOf(node),
          TextRange(start: start, end: end),
        );
        // Scope to this node's own rich text, not a parent with matching
        // attributes, a nested child's text, or the transparent placeholder.
        final richText = find.byWidgetPredicate(
          (widget) =>
              widget is AppFlowyRichText && identical(widget.node, node),
        );
        expect(richText, findsOneWidget);
        expect(
          find.descendant(
            of: richText,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is RichText &&
                  widget.text.toPlainText(includeSemanticsLabels: false) ==
                      text,
            ),
          ),
          findsOneWidget,
        );
      }

      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'needle',
      );
      for (var index = 0; index < expected.length; index++) {
        if (index > 0) {
          await tester.tap(find.byKey(const ValueKey('findNextMatch')));
        }
        await expectHit(index);
      }
      expect(tail.key.currentContext?.mounted, isTrue);
      // Lazy index jumps change the list anchor, not an absolute pixel offset.
      // The tail started unmounted and expectHit requires its on-screen rects.
      expect(doc.editor.selectionRects(), isNotEmpty);
      await tester.tap(find.byKey(const ValueKey('findNextMatch')));
      await expectHit(0);
      await tester.tap(find.byKey(const ValueKey('findPreviousMatch')));
      await expectHit(expected.length - 1);
    },
    nodes: _nestedDocument,
  );

  for (final mode in ['light', 'dark', 'paper']) {
    _test(
      '$mode: full and split runs paint current and other matches',
      (tester, doc) async {
        await doc.mount(tester, mode: mode);
        await _query(tester, 'needle');
        final richText = tester
            .widgetList<RichText>(
              find.descendant(
                of: find.byKey(doc.first.key),
                matching: find.byType(RichText),
              ),
            )
            .singleWhere(
              (widget) =>
                  widget.text.toPlainText(includeSemanticsLabels: false) ==
                  'Needle plain NEEDLE',
            );
        final runs = _runs(richText.text).toList();
        expect(runs.map((run) => run.$1).join(), 'Needle plain NEEDLE');
        final brightness = mode == 'dark' ? Brightness.dark : Brightness.light;
        final characters = [
          for (final (text, style) in runs)
            for (var i = 0; i < text.length; i++) style,
        ];
        for (var index = 0; index < 6; index++) {
          expect(
            characters[index].backgroundColor,
            FindHighlightColors.current(brightness),
          );
        }
        for (var index = 13; index < 19; index++) {
          expect(
            characters[index].backgroundColor,
            FindHighlightColors.match(brightness),
          );
        }
        expect(characters[0].fontWeight, FontWeight.bold);
        expect(characters[3].fontStyle, FontStyle.italic);
        if (mode == 'paper') {
          final context = tester.element(find.byType(FindReplaceBar));
          expect(PaperTheme.isEnabled(context), isTrue);
          expect(
            FindBarPalette.of(context).surface,
            PaperTheme.popupBackground,
          );
        }
        expect(doc.writes, 0);
      },
      nodes: () => [
        paragraphNode(
          delta: Delta()
            ..insert('Nee', attributes: {AppFlowyRichTextKeys.bold: true})
            ..insert(
              'dle',
              attributes: {AppFlowyRichTextKeys.italic: true},
            )
            ..insert(' plain NEEDLE'),
        ),
      ],
    );
  }

  _test(
    'native caret before opening determines the initial result',
    (tester, doc) async {
      await doc.mount(tester, menu: false);
      doc.editor.selection =
          Selection.collapsed(Position(path: [0], offset: 8));
      doc.open();
      await tester.pump();
      await _query(tester, 'needle');
      expect(_bar(tester).currentMatch, 2);
      expect(doc.editor.selection?.start.offset, 8);
      await _next(tester);
      expect(_bar(tester).currentMatch, 1);
    },
    nodes: () => [paragraphNode(text: 'needle, needle')],
  );

  _test(
    'regex Replace All is one transaction and one reversible history item',
    (tester, doc) async {
      await doc.mount(tester, replace: true);
      final before = doc.editor.document.toJson();
      await _options(tester, const FindOptions(useRegex: true));
      await _query(tester, r'([a-z])(\d)');
      expect(_bar(tester).matchCount, 3);
      await tester.enterText(
        find.byKey(const ValueKey('replaceTextField')),
        r'$2-\1-$$',
      );
      await tester.tap(find.byKey(const ValueKey('findReplaceAll')));
      await tester.pump();
      await tester.pump();
      expect(doc.texts, [r'1-A-$ 2-A-$', r'3-a-$']);
      expect(_bar(tester).matchCount, 0);
      expect(doc.writes, 1);
      expect(
        doc.first.delta!.first.attributes?[AppFlowyRichTextKeys.bold],
        true,
      );
      expect(doc.editor.undoManager.undoStack.last.sealed, isTrue);

      doc.editor.undoManager.undo();
      await tester.pump();
      expect(doc.editor.document.toJson(), before);
      expect(_bar(tester).matchCount, 3);
      expect(doc.editor.undoManager.undoStack.isEmpty, isTrue);
      doc.editor.undoManager.redo();
      await tester.pump();
      expect(doc.texts, [r'1-A-$ 2-A-$', r'3-a-$']);
    },
    nodes: () => [
      paragraphNode(
        delta: Delta()
          ..insert(
            'A1 A2',
            attributes: {AppFlowyRichTextKeys.bold: true},
          ),
      ),
      paragraphNode(
        delta: Delta()
          ..insert('a3', attributes: {AppFlowyRichTextKeys.italic: true}),
      ),
    ],
  );

  _test(
    'empty Replace All deletes every match in one transaction',
    (tester, doc) async {
      await doc.mount(tester, replace: true);
      final before = doc.editor.document.toJson();
      await _query(tester, 'needle');
      await tester.tap(find.byKey(const ValueKey('findReplaceAll')));
      await tester.pump();
      expect(doc.texts, [' ', 'keep ']);
      expect(doc.writes, 1);
      expect(_bar(tester).matchCount, 0);
      doc.editor.undoManager.undo();
      await tester.pump();
      expect(doc.editor.document.toJson(), before);
    },
    nodes: () => [
      paragraphNode(text: 'needle needle'),
      paragraphNode(text: 'keep needle'),
    ],
  );

  _test(
    'identical replacement steps to the next hit without a document write',
    (tester, doc) async {
      await doc.mount(tester, replace: true);
      await _query(tester, 'needle');
      await tester.enterText(
        find.byKey(const ValueKey('replaceTextField')),
        'needle',
      );
      await tester.tap(find.byKey(const ValueKey('findReplaceOne')));
      await tester.pump();
      expect(_bar(tester).currentMatch, 2);
      expect(doc.writes, 0);
    },
    nodes: () => [paragraphNode(text: 'needle needle')],
  );

  for (final guard in [
    'read-only',
    'permission revoked',
    'deleted/rebound owner',
  ]) {
    _test('$guard rejects even a previously enabled Replace callback',
        (tester, doc) async {
      var allowed = true;
      var active = true;
      await doc.mount(
        tester,
        replace: true,
        canReplace: () => allowed,
        isOwnerActive: () => active,
      );
      await _query(tester, 'needle');
      await tester.enterText(
        find.byKey(const ValueKey('replaceTextField')),
        'wrong',
      );
      final replace = _bar(tester).onReplaceAll!;
      final before = doc.editor.document.toJson();
      if (guard == 'read-only') {
        doc.editor.editable = false;
      } else if (guard == 'permission revoked') {
        allowed = false;
      } else {
        active = false;
      }
      replace();
      await tester.pump();
      await tester.pump();
      expect(doc.editor.document.toJson(), before);
      expect(doc.writes, 0);
    });
  }

  _test(
    'query changed by an apply listener is not overwritten on completion',
    (tester, doc) async {
      await doc.mount(tester, replace: true);
      await _query(tester, 'needle');
      await tester.enterText(
        find.byKey(const ValueKey('replaceTextField')),
        'done',
      );
      final controller = _bar(tester).findController;
      final subscription = doc.editor.transactionStream.listen((event) {
        if (event.$1 == TransactionTime.after) {
          controller.text = 'beta';
        }
      });
      try {
        await tester.tap(find.byKey(const ValueKey('findReplaceOne')));
        await tester.pump();
        await tester.pump();
        expect(_bar(tester).findController.text, 'beta');
        expect(_bar(tester).matchCount, 1);
        expect(doc.editor.selection?.start.path, [1]);
        expect(doc.texts, ['done', 'beta']);
        expect(doc.writes, 1);
      } finally {
        await _pumpUntil(
          tester,
          completion: subscription.cancel(),
          reason: 'query listener cancellation',
        );
      }
    },
    nodes: () => [paragraphNode(text: 'needle'), paragraphNode(text: 'beta')],
  );

  for (final duringApply in [true, false]) {
    _test(
      'a newer caret survives replacement (duringApply=$duringApply)',
      (tester, doc) async {
        await doc.mount(tester, menu: false);
        final session = doc.session = DocumentFindSession(doc.editor);
        session.search('needle', const FindOptions());
        final nextSelection = Selection.single(
          path: [1],
          startOffset: 2,
          endOffset: 4,
        );
        void moveCaret() {
          unawaited(
            doc.editor.updateSelectionWithReason(
              nextSelection,
              reason: SelectionUpdateReason.uiEvent,
              customSelectionType: SelectionType.inline,
              extraInfo: {selectionExtraInfoDoNotAttachTextService: true},
            ),
          );
        }

        final subscription = duringApply
            ? doc.editor.transactionStream.listen((event) {
                if (event.$1 == TransactionTime.after) moveCaret();
              })
            : null;
        try {
          final replacement = session.replaceCurrent('done');
          if (!duringApply) moveCaret();
          expect(await replacement, isTrue);
          await tester.pump();
          await tester.pump();
          expect(doc.editor.selection, nextSelection);
          expect(
            doc.editor.selectionUpdateReason,
            SelectionUpdateReason.uiEvent,
          );
          expect(doc.texts, ['done needle', 'another paragraph']);
          expect(session.matches.length, 1);
          expect(doc.writes, 1);
        } finally {
          if (subscription != null) {
            await _pumpUntil(
              tester,
              completion: subscription.cancel(),
              reason: 'caret listener cancellation',
            );
          }
        }
      },
      nodes: () => [
        paragraphNode(text: 'needle needle'),
        paragraphNode(text: 'another paragraph'),
      ],
    );
  }

  _test(
    'a model edit before replacement completion prevents a delayed jump',
    (tester, doc) async {
      await doc.mount(tester, menu: false);
      final session = doc.session = DocumentFindSession(doc.editor);
      session.search('needle', const FindOptions());
      final replacement = session.replaceCurrent('done');
      final caret = doc.editor.selection;
      expect(caret, Selection.collapsed(Position(path: [0], offset: 4)));
      // Apply without changing selection or its reason, before awaiting either
      // operation: the model revision, not just caret equality, must guard this.
      final modelEdit = doc.editor.apply(
        doc.editor.transaction
          ..insertText(doc.editor.document.root.children[1], 5, ' edited'),
        withUpdateSelection: false,
      );
      await modelEdit;
      expect(await replacement, isTrue);
      await tester.pump();
      await tester.pump();
      expect(doc.editor.selection, caret);
      expect(doc.texts, ['done needle', 'other edited']);
      expect(session.matches.length, 1);
      expect(doc.writes, 2);
    },
    nodes: () => [
      paragraphNode(text: 'needle needle'),
      paragraphNode(text: 'other'),
    ],
  );

  _test('Replace All does not merge into a preceding unsealed user edit',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    await doc.editor.apply(
      doc.editor.transaction..insertText(doc.first, 0, 'draft '),
      withUpdateSelection: false,
    );
    final beforeReplace = doc.editor.document.toJson();
    expect(doc.editor.undoManager.undoStack.last.sealed, isFalse);
    final session = doc.session = DocumentFindSession(doc.editor);
    session.search('needle', const FindOptions());
    expect(await session.replaceAll('done'), isTrue);
    expect(doc.texts, ['draft done']);
    doc.editor.undoManager.undo();
    await tester.pump();
    expect(doc.editor.document.toJson(), beforeReplace);
    doc.editor.undoManager.undo();
    await tester.pump();
    expect(doc.texts, ['needle']);
    doc.editor.undoManager.redo();
    await tester.pump();
    expect(doc.editor.document.toJson(), beforeReplace);
    doc.editor.undoManager.redo();
    await tester.pump();
    expect(doc.texts, ['draft done']);
  });

  _test(
      'busy listeners cannot reenter replacement or bypass a revoked permission',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    final session = doc.session = DocumentFindSession(doc.editor);
    session.search('needle', const FindOptions());
    Future<bool>? reentrant;
    void tryAgain() {
      if (session.busy && reentrant == null) {
        reentrant = session.replaceAll('wrong');
      }
    }

    session.addListener(tryAgain);
    expect(await session.replaceAll('done'), isTrue);
    expect(await reentrant, isFalse);
    expect(doc.texts, ['done']);
    expect(doc.writes, 1);
    session.removeListener(tryAgain);
    session.search('done', const FindOptions());
    void revoke() {
      if (session.busy) doc.editor.editable = false;
    }

    session.addListener(revoke);
    expect(await session.replaceAll('wrong'), isFalse);
    expect(doc.texts, ['done']);
    expect(doc.writes, 1);
    session.removeListener(revoke);
  });

  _test('disposed session ignores queued refresh, navigation and replacement',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    final session = doc.session = DocumentFindSession(doc.editor);
    session.search('needle', const FindOptions());
    final replacement = session.replaceCurrent('done');
    session
        .dispose(); // apply completed synchronously; its continuation has not.
    expect(session.debugWatchedNodeCount, 0);
    await replacement;
    final before = doc.editor.document.toJson();
    session.search('done', const FindOptions());
    session.navigate();
    expect(await session.replaceAll('wrong'), isFalse);
    await tester.pump();
    expect(doc.editor.document.toJson(), before);
    expect(doc.writes, 1);
    expect(DocumentSearchHighlight.instance.rangesOf(doc.first), isEmpty);
  });

  _test('node watches detach after removal and editor disposal',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    final session = doc.session = DocumentFindSession(doc.editor);
    session.search('needle', const FindOptions());
    expect(session.debugWatchedNodeCount, 2);
    final added = paragraphNode(text: 'another needle');
    try {
      await doc.editor.apply(
        doc.editor.transaction..insertNode([1], added, deepCopy: false),
        withUpdateSelection: false,
      );
      await tester.pump();
      expect(session.debugWatchedNodeCount, 3);
      expect(session.matches.length, 2);
      await doc.editor.apply(
        doc.editor.transaction..deleteNode(added),
        withUpdateSelection: false,
      );
      await tester.pump();
      expect(added.parent, isNull);
      expect(session.debugWatchedNodeCount, 2);
      expect(session.matches.length, 1);

      var notifications = 0;
      void changed() => notifications++;
      session.addListener(changed);
      added.updateAttributes({
        'delta': (Delta()..insert('removed needle changed')).toJson(),
      });
      await doc.editor.apply(
        doc.editor.transaction
          ..formatText(doc.first, 0, 6, {AppFlowyRichTextKeys.bold: true}),
        withUpdateSelection: false,
      );
      await tester.pump();
      expect(
        notifications,
        0,
        reason: 'Detached nodes and formatting-only edits are not new text.',
      );
      session.removeListener(changed);

      final edit = doc.editor.apply(
        doc.editor.transaction..insertText(doc.first, 0, 'queued '),
        withUpdateSelection: false,
      );
      doc.editor.dispose();
      expect(session.debugWatchedNodeCount, 0);
      expect(session.isActive, isFalse);
      expect(session.matches, isEmpty);
      expect(await session.replaceAll('wrong'), isFalse);
      await edit;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      if (added.parent == null) added.dispose();
    }
  });

  _test('inserted/moved/deleted nodes refresh paths without a stale query',
      (tester, doc) async {
    await doc.mount(tester);
    await _query(tester, 'needle');
    await doc.editor.apply(
      doc.editor.transaction
        ..insertNode([0], paragraphNode(text: 'new needle')),
      withUpdateSelection: false,
    );
    await tester.pump();
    expect(_bar(tester).matchCount, 2);
    final original = doc.editor.document.root.children[1];
    await doc.editor.apply(
      doc.editor.transaction..moveNode([0], original),
      withUpdateSelection: false,
    );
    await tester.pump();
    expect(doc.first, same(original));
    expect(_bar(tester).matchCount, 2);
    await doc.editor.apply(
      doc.editor.transaction
        ..deleteNode(doc.editor.document.root.children.last),
      withUpdateSelection: false,
    );
    await tester.pump();
    expect(_bar(tester).matchCount, 1);
    expect(doc.first, same(original));
    await _next(tester);
    expect(doc.editor.selection?.start.path, [0]);
  });

  _test('same-id nodes in different editors never share highlight marks',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    final other = EditorState(
      document: Document(
        root: pageNode(
          children: [
            paragraphNode(text: 'needle')..id = doc.first.id,
          ],
        ),
      ),
    );
    final session = doc.session = DocumentFindSession(doc.editor);
    try {
      session.search('needle', const FindOptions());
      expect(DocumentSearchHighlight.instance.rangesOf(doc.first), isNotEmpty);
      expect(
        DocumentSearchHighlight.instance.rangesOf(other.document.first!),
        isEmpty,
      );
    } finally {
      other.dispose();
      other.editableNotifier.dispose();
    }
  });

  _test('dismiss before first overlay frame cannot leave a ghost bar',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    doc.open();
    final pendingScope = DocumentFindMenu.findFocusNode!;
    expect(pendingScope.parent, isNull);
    DocumentFindMenu.dismiss();
    expect(() => pendingScope.addListener(() {}), throwsFlutterError);
    await tester.pump();
    await tester.pump();
    expect(DocumentFindMenu.isOpen, isFalse);
    expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
    doc.open();
    await tester.pump();
    await _query(tester, 'needle');
    expect(DocumentFindMenu.isOpen, isTrue);
    expect(_bar(tester).matchCount, 1);
  });

  for (final mountedMenu in [false, true]) {
    _test(
        'editor disposal removes a ${mountedMenu ? 'mounted' : 'pending'} overlay',
        (tester, doc) async {
      await doc.mount(tester, menu: false);
      doc.open();
      if (mountedMenu) {
        await tester.pump();
        await _query(tester, 'needle');
      }
      doc.editor.dispose();
      expect(DocumentFindMenu.isOpen, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
    });
  }

  _test('old close and deferred cleanup cannot dismiss or erase a reopened bar',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    doc.open();
    await tester.pump();
    await _query(tester, 'needle');
    final oldClose = _bar(tester).onClose;
    oldClose();
    doc.open();
    await tester.pump();
    await _query(tester, 'needle');
    oldClose();
    await tester.pump();
    expect(DocumentFindMenu.isOpen, isTrue);
    expect(find.byType(FindAndReplaceMenuWidget), findsOneWidget);
    expect(_bar(tester).matchCount, 1);
    expect(DocumentSearchHighlight.instance.rangesOf(doc.first), isNotEmpty);
  });

  _test('same-frame reopen publishes a fresh scope for the same editor',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    doc.open();
    await tester.pump();
    await _query(tester, 'needle');
    final oldScope = DocumentFindMenu.findFocusNode;
    var closeDuringBuild = true;
    final closer = OverlayEntry(
      builder: (_) {
        if (closeDuringBuild) {
          closeDuringBuild = false;
          DocumentFindMenu.dismiss();
        }
        return const SizedBox.shrink();
      },
    );
    // Registered BEFORE close defers its notification during the next build.
    // Reopening therefore coalesces old editor -> same editor, not -> null.
    WidgetsBinding.instance.addPostFrameCallback((_) => doc.open());
    Overlay.of(doc.owner!, rootOverlay: true).insert(closer);
    try {
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(DocumentFindMenu.activeEditor, same(doc.editor));
      expect(DocumentFindMenu.findFocusNode, isNot(same(oldScope)));
      expect(oldScope!.parent, isNull);
      final region = tester.widget<ContextualFindRegion>(
        find.byType(ContextualFindRegion),
      );
      expect(region.findFocusNode, same(DocumentFindMenu.findFocusNode));
      await _query(tester, 'needle');
      await _control(tester, LogicalKeyboardKey.keyH);
      expect(find.byKey(const ValueKey('replaceTextField')), findsOneWidget);
      expect(find.byType(FindAndReplaceMenuWidget), findsOneWidget);
      expect(_bar(tester).matchCount, 1);
    } finally {
      closer.remove();
      closer.dispose();
    }
  });

  _test('a reentrant open wins over the older request without an orphan entry',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    doc.open();
    await tester.pump();
    final other = EditorState.blank();
    var reopen = true;
    void onOwnerChanged() {
      if (reopen && DocumentFindMenu.activeEditor == null) {
        reopen = false;
        doc.open();
      }
    }

    DocumentFindMenu.activeEditorListenable.addListener(onOwnerChanged);
    try {
      DocumentFindMenu.show(doc.owner!, other);
      await tester.pump();
      await tester.pump();
      expect(DocumentFindMenu.activeEditor, same(doc.editor));
      expect(find.byType(FindAndReplaceMenuWidget), findsOneWidget);
      await _query(tester, 'needle');
      expect(_bar(tester).matchCount, 1);
    } finally {
      DocumentFindMenu.activeEditorListenable.removeListener(onOwnerChanged);
      other.dispose();
      other.editableNotifier.dispose();
    }
  });

  _test(
      'outside click closes the real overlay and still activates the document',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    doc.open();
    await tester.pump();
    await _query(tester, 'needle');
    await tester.tap(find.byKey(const ValueKey('outside-find-action')));
    await tester.pump();
    await tester.pump();
    expect(doc.outsideClicks, 1);
    expect(DocumentFindMenu.isOpen, isFalse);
    expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
  });

  _test(
      'outside native title click closes Find without a deferred focus restore',
      (tester, doc) async {
    await doc.mount(tester, menu: false, titleField: true);
    doc.open(replace: true);
    await tester.pump();
    await tester.pump();
    expect(_bar(tester).replaceFocusNode!.hasPrimaryFocus, isTrue);
    await _query(tester, 'needle');
    final bar = _bar(tester);
    expect(bar.onTapOutside, isNotNull);
    bar.onSubmitted!(); // Queue a guarded host focus request before the click.
    final title = find.byKey(const ValueKey('outside-find-title'));
    await tester.tap(title, kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(DocumentFindMenu.isOpen, isFalse);
    expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
    expect(doc.titleFocus.hasPrimaryFocus, isTrue);
    expect(bar.findFocusNode.parent, isNull);
    expect(bar.replaceFocusNode!.parent, isNull);
    expect(doc.titleController.text, 'Page title draft');
    await tester.enterText(title, 'Continued title editing');
    await tester.pump();
    expect(doc.titleFocus.hasPrimaryFocus, isTrue);
    expect(doc.titleController.text, 'Continued title editing');
    expect(doc.writes, 0);
  });

  _test(
      'readonly transition hides replace, retains find and rejects stale actions',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    doc.open(replace: true);
    await tester.pump();
    await _query(tester, 'needle');
    final replace = _bar(tester).onReplaceAll!;
    doc.editor.editable = false;
    replace();
    await tester.pump();
    await tester.pump();
    expect(DocumentFindMenu.isOpen, isTrue);
    expect(_bar(tester).matchCount, 1);
    expect(_bar(tester).replaceController, isNull);
    expect(find.byKey(const ValueKey('replaceTextField')), findsNothing);
    expect(doc.writes, 0);
  });

  _test('a read-only editor rebuild safely updates its sibling find overlay',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    doc.open(replace: true);
    await tester.pump();
    await _query(tester, 'needle');
    final replace = _bar(tester).onReplaceAll!;
    await doc.mount(tester, menu: false, editable: false);
    replace();
    await tester.pump();
    expect(DocumentFindMenu.isOpen, isTrue);
    expect(_bar(tester).findController.text, 'needle');
    expect(_bar(tester).replaceController, isNull);
    expect(doc.writes, 0);
  });

  for (final width in [120.0, 180.0, 240.0, 320.0]) {
    _test('overlay controls remain reachable in a $width px pane',
        (tester, doc) async {
      await doc.mount(
        tester,
        menu: false,
        paneWidth: width,
        textScale: width >= 240 ? 2 : 1,
      );
      doc.open(replace: true);
      await tester.pump();
      await _query(tester, 'needle');
      final horizontal = find.ancestor(
        of: find.byType(FindAndReplaceMenuWidget),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      );
      final pane =
          tester.getRect(find.byKey(const ValueKey('document-find-pane')));
      final bar = tester.getRect(find.byType(FindReplaceBar));
      expect(bar.width, greaterThanOrEqualTo(180));
      expect(
        tester.getSize(find.byKey(const ValueKey('findTextField'))).width,
        greaterThanOrEqualTo(40),
      );
      final close = find.byKey(const ValueKey('findClose'));
      if (width < 180) {
        expect(horizontal, findsOneWidget);
        final viewport = tester.getRect(horizontal);
        expect(viewport.left, greaterThanOrEqualTo(pane.left));
        expect(viewport.right, lessThanOrEqualTo(pane.right));
        await tester.ensureVisible(close);
      } else {
        expect(horizontal, findsNothing);
        expect(bar.left, greaterThanOrEqualTo(pane.left));
        expect(bar.right, lessThanOrEqualTo(pane.right));
      }
      await _pumpUntil(
        tester,
        ready: () => close.hitTestable().evaluate().length == 1,
        reason: 'reachable close control in the $width px pane',
      );
      await tester.tap(close);
      await tester.pump();
      expect(DocumentFindMenu.isOpen, isFalse);
    });
  }

  _test('bounded overlay resize retains native fields, draft and caret',
      (tester, doc) async {
    await doc.mount(tester, menu: false, paneWidth: 320, textScale: 2);
    doc.open(replace: true);
    await tester.pump();
    await _query(tester, 'needle');
    final replace = find.byKey(const ValueKey('replaceTextField'));
    await tester.enterText(replace, 'replacement draft');
    final bar = _bar(tester);
    bar.replaceController!.selection =
        const TextSelection(baseOffset: 2, extentOffset: 6);
    await tester.pump();
    final draft = bar.replaceController!.value;
    final findEditable = find.descendant(
      of: find.byKey(const ValueKey('findTextField')),
      matching: find.byType(EditableText),
    );
    final replaceEditable = find.descendant(
      of: replace,
      matching: find.byType(EditableText),
    );
    final findElement = tester.element(findEditable);
    final replaceElement = tester.element(replaceEditable);
    for (final width in [240.0, 180.0, 120.0, 180.0, 320.0]) {
      await doc.mount(
        tester,
        menu: false,
        paneWidth: width,
        textScale: width >= 240 ? 2 : 1,
      );
      final current = _bar(tester);
      expect(DocumentFindMenu.isOpen, isTrue);
      expect(tester.element(findEditable), same(findElement));
      expect(tester.element(replaceEditable), same(replaceElement));
      expect(current.findController, same(bar.findController));
      expect(current.findController.text, 'needle');
      expect(current.replaceController, same(bar.replaceController));
      expect(current.replaceController!.value, draft);
      expect(current.replaceFocusNode!.hasPrimaryFocus, isTrue);
      if (width < 180) {
        await tester.ensureVisible(find.byKey(const ValueKey('findClose')));
        await tester.pump();
      }
      expect(
        find.byKey(const ValueKey('findClose')).hitTestable(),
        findsOneWidget,
      );
    }
    expect(doc.writes, 0);
  });

  _test('root route covering a nested navigator dismisses its document find',
      (tester, doc) async {
    await doc.mount(tester, menu: false, nestedNavigator: true);
    doc.open();
    await tester.pump();
    await _query(tester, 'needle');
    final innerRoute = ModalRoute.of(doc.owner!)!;
    unawaited(
      doc.navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('covering root route')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(innerRoute.isCurrent, isTrue);
    expect(DocumentFindMenu.isOpen, isFalse);
    expect(find.byType(FindAndReplaceMenuWidget), findsNothing);
  });

  _test(
      'Ctrl+F/Ctrl+H from either query field keeps one menu and editor subtree',
      (tester, doc) async {
    await doc.mount(tester, menu: false);
    final editorElement = tester.element(find.byType(AppFlowyEditor));
    await _control(tester, LogicalKeyboardKey.keyF);
    await _query(tester, 'needle');
    final original = _bar(tester);
    final menuElement = tester.element(find.byType(FindAndReplaceMenuWidget));
    final scope = DocumentFindMenu.findFocusNode;
    var queryValue = original.findController.value;
    final queryField = find.byKey(const ValueKey('findTextField'));
    final replacementField = find.byKey(
      const ValueKey('replaceTextField'),
      skipOffstage: false,
    );
    final fieldStates = [
      for (final field in [queryField, replacementField])
        tester.state<EditableTextState>(
          find.descendant(
            of: field,
            matching: find.byType(EditableText, skipOffstage: false),
            skipOffstage: false,
          ),
        ),
    ];
    var replacementText = '';
    void expectRetained() {
      final current = _bar(tester);
      expect(find.byType(FindAndReplaceMenuWidget), findsOneWidget);
      expect(
        tester.element(find.byType(FindAndReplaceMenuWidget)),
        same(menuElement),
      );
      expect(DocumentFindMenu.findFocusNode, same(scope));
      expect(current.findFocusNode, same(original.findFocusNode));
      expect(current.replaceFocusNode, same(original.replaceFocusNode));
      expect(current.findController, same(original.findController));
      expect(current.findController.text, 'needle');
      expect(current.findController.value, queryValue);
      expect(current.replaceController, same(original.replaceController));
      expect(current.replaceController!.text, replacementText);
      expect(current.matchCount, 1);
      for (var index = 0; index < fieldStates.length; index++) {
        final field = index == 0 ? queryField : replacementField;
        expect(
          tester.state<EditableTextState>(
            find.descendant(
              of: field,
              matching: find.byType(EditableText, skipOffstage: false),
              skipOffstage: false,
            ),
          ),
          same(fieldStates[index]),
        );
      }
      expect(tester.element(find.byType(AppFlowyEditor)), same(editorElement));
      expect(doc.writes, 0);
    }

    await _control(tester, LogicalKeyboardKey.keyH);
    expect(find.byKey(const ValueKey('replaceTextField')), findsOneWidget);
    expectRetained();
    expect(original.replaceFocusNode!.hasPrimaryFocus, isTrue);
    // At animation time zero the retained replacement is clipped, not a mouse
    // target. The old test tapped through it, dismissed Find, then opened a new
    // empty session. Immediate keyboard switching must still retain this owner.
    expect(replacementField.hitTestable(), findsNothing);
    await _control(tester, LogicalKeyboardKey.keyF);
    // EditableText._adjustedSelectionWhenFocused selects all in a single-line
    // desktop field on keyboard focus. This is native behavior, not reseeding.
    queryValue = queryValue.copyWith(
      selection: const TextSelection(baseOffset: 0, extentOffset: 6),
    );
    expectRetained();
    expect(original.findFocusNode.hasPrimaryFocus, isTrue);
    await _control(tester, LogicalKeyboardKey.keyH);
    expectRetained();
    await tester.pump(const Duration(milliseconds: 160));
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(of: replacementField, matching: find.byType(Opacity))
                .first,
          )
          .opacity,
      1,
    );
    await tester.pump(const Duration(microseconds: 1));
    expect(replacementField.hitTestable(), findsOneWidget);
    await tester.tap(replacementField, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(original.replaceFocusNode!.hasPrimaryFocus, isTrue);
    expectRetained();
    replacementText = 'replacement draft';
    tester.testTextInput.enterText(replacementText);
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.keyH,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyH,
      LogicalKeyboardKey.keyF,
    ]) {
      await _control(tester, key);
      expectRetained();
      expect(
        (key == LogicalKeyboardKey.keyH
                ? original.replaceFocusNode!
                : original.findFocusNode)
            .hasPrimaryFocus,
        isTrue,
      );
    }
  });
}

void _test(
  String name,
  Future<void> Function(WidgetTester tester, _DocumentFixture doc) body, {
  List<Node> Function()? nodes,
}) {
  testWidgets(
    name,
    (tester) async {
      final doc =
          _DocumentFixture(nodes?.call() ?? [paragraphNode(text: 'needle')]);
      try {
        await body(tester, doc);
        expect(tester.takeException(), isNull);
      } finally {
        await doc.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

class _DocumentFixture {
  _DocumentFixture(List<Node> nodes)
      : editor =
            EditorState(document: Document(root: pageNode(children: nodes)))
              ..disableSealTimer = true {
    _subscription = editor.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after && event.$2.operations.isNotEmpty) {
        writes++;
      }
    });
  }

  final EditorState editor;
  final navigator = GlobalKey<NavigatorState>();
  final titleFocus = FocusNode();
  final titleController = TextEditingController(text: 'Page title draft');
  late final StreamSubscription<EditorTransactionValue> _subscription;
  BuildContext? owner;
  DocumentFindSession? session;
  int writes = 0;
  int outsideClicks = 0;
  Node get first => editor.document.first!;
  List<String?> get texts => editor.document.root.children
      .map((node) => node.delta?.toPlainText())
      .toList();

  void open({bool replace = false}) =>
      DocumentFindMenu.show(owner!, editor, replace: replace);

  Future<void> mount(
    WidgetTester tester, {
    bool menu = true,
    bool replace = false,
    bool editable = true,
    String mode = 'light',
    double paneWidth = 740,
    double textScale = 1,
    bool nestedNavigator = false,
    bool titleField = false,
    bool Function()? canReplace,
    bool Function()? isOwnerActive,
  }) async {
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
    Widget content() => Column(
          children: [
            TextButton(
              key: const ValueKey('outside-find-action'),
              onPressed: () => outsideClicks++,
              child: const Text('Normal document action'),
            ),
            if (titleField)
              SizedBox(
                width: 240,
                height: 48,
                child: TextField(
                  key: const ValueKey('outside-find-title'),
                  focusNode: titleFocus,
                  controller: titleController,
                ),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  key: const ValueKey('document-find-pane'),
                  width: paneWidth,
                  child: ValueListenableBuilder<EditorState?>(
                    valueListenable: DocumentFindMenu.activeEditorListenable,
                    builder: (_, active, child) => ContextualFindRegion(
                      onFind: open,
                      onReplace: () => open(replace: true),
                      onDismiss: () =>
                          DocumentFindMenu.dismiss(editorState: editor),
                      findOpen: identical(active, editor),
                      findFocusNode: identical(active, editor)
                          ? DocumentFindMenu.findFocusNode
                          : null,
                      isSelected: () => true,
                      child: child!,
                    ),
                    child: Builder(
                      builder: (context) {
                        owner = context;
                        return AppFlowyEditor(
                          editorState: editor,
                          editable: editable,
                          editorStyle: EditorStyle.desktop(
                            padding: const EdgeInsets.all(24),
                            textSpanDecorator:
                                (context, node, start, text, before, after) =>
                                    decorateWithSearchHighlight(
                              context,
                              node,
                              start,
                              after,
                            ),
                          ),
                          blockComponentBuilders: {
                            ...standardBlockComponentBuilderMap,
                            callouts.CalloutBlockKeys.type:
                                callouts.CalloutBlockComponentBuilder(
                              defaultColor: theme.colorScheme.surface,
                              inlinePadding: (_) => const EdgeInsets.all(8),
                            ),
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (menu)
              Align(
                alignment: Alignment.centerRight,
                child: FindAndReplaceMenuWidget(
                  editorState: editor,
                  showReplaceMenu: replace,
                  canReplace: canReplace,
                  isOwnerActive: isOwnerActive,
                  onDismiss: () {},
                ),
              ),
          ],
        );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: AppFlowyTheme(
            data: mode == 'dark'
                ? AppFlowyDefaultTheme().dark()
                : AppFlowyDefaultTheme().light(),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: nestedNavigator
              ? Navigator(
                  onGenerateRoute: (_) =>
                      MaterialPageRoute<void>(builder: (_) => content()),
                )
              : content(),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      ready: () =>
          editor.document.root.context?.mounted == true &&
          first.renderBox?.hasSize == true,
      reason: 'document editor layout',
    );
    expect(editor.document.root.context?.mounted, isTrue);
  }

  Future<void> dispose(WidgetTester tester) async {
    DocumentFindMenu.dismiss();
    session?.dispose();
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpUntil(
        tester,
        completion: _subscription.cancel(),
        reason: 'document transaction listener cancellation',
      );
    } finally {
      DocumentSearchHighlight.instance.clear(editor);
      if (!editor.isDisposed) editor.dispose();
      editor.editableNotifier.dispose();
      titleFocus.dispose();
      titleController.dispose();
    }
    await tester.pump();
  }
}

Future<void> _pumpUntil(
  WidgetTester tester, {
  required String reason,
  Future<void>? completion,
  bool Function()? ready,
}) async {
  var completed = completion == null;
  Object? failure;
  StackTrace? failureStack;
  if (completion != null) {
    unawaited(
      completion.then<void>(
        (_) {
          completed = true;
        },
        onError: (Object error, StackTrace stack) {
          failure = error;
          failureStack = stack;
          completed = true;
        },
      ),
    );
  }
  final deadline = tester.binding.clock.fromNowBy(const Duration(seconds: 1));
  do {
    // Dart broadcast cancellation returns a cached root-zone future. Give its
    // callbacks a real event turn, then drain fake microtasks/render a frame.
    // Never await the captured operation inside runAsync: it may need a pump.
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
    if (completed && (ready?.call() ?? true)) return;
  } while (tester.binding.clock.now().isBefore(deadline));
  fail('Timed out waiting for $reason.');
}

FindReplaceBar _bar(WidgetTester tester) =>
    tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));

Future<void> _pumpFindSelection(WidgetTester tester) {
  final editor =
      tester.widget<AppFlowyEditor>(find.byType(AppFlowyEditor)).editorState;
  // searchHighlight mutates synchronously but its SDK future never completes.
  // Observe the resulting bar and real selection geometry, not that future.
  return _pumpUntil(
    tester,
    reason: 'rendered document find selection',
    ready: () =>
        _bar(tester).matchCount == 0 ||
        (editor.selectionUpdateReason ==
                SelectionUpdateReason.searchHighlight &&
            editor.selectionRects().isNotEmpty),
  );
}

Future<void> _query(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('findTextField')), text);
  await _pumpFindSelection(tester);
}

Future<void> _options(WidgetTester tester, FindOptions options) async {
  _bar(tester).onOptionsChanged(options);
  await _pumpFindSelection(tester);
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('findNextMatch')));
  await _pumpFindSelection(tester);
}

Future<void> _control(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

Iterable<(String, TextStyle)> _runs(
  InlineSpan span, [
  TextStyle inherited = const TextStyle(),
]) sync* {
  if (span is! TextSpan) return;
  final style = inherited.merge(span.style);
  if (span.text?.isNotEmpty ?? false) yield (span.text!, style);
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _runs(child, style);
  }
}

List<Node> _nestedDocument() {
  final callout = callouts.calloutNode(delta: Delta()..insert('Callout Needle'))
    ..insert(paragraphNode(text: 'Nested Needle'));
  return [
    Node(
      type: BulletedListBlockKeys.type,
      attributes: {
        'delta': (Delta()..insert('Needle list')).toJson(),
        'metadata': 'needle must not be counted',
      },
      children: [
        Node(
          type: NumberedListBlockKeys.type,
          attributes: {
            'delta': (Delta()..insert('Numbered Needle')).toJson(),
          },
          children: [
            paragraphNode(text: 'deep needle'),
          ],
        ),
      ],
    ),
    callout,
    TableNode.fromList<String>([
      ['Cell Needle'],
    ]).node,
    for (var index = 0; index < 180; index++)
      paragraphNode(text: 'Filler paragraph $index'),
    paragraphNode(text: 'Offscreen Needle'),
  ];
}
