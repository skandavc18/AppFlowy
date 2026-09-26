import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_search_highlight.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/find_and_replace_menu.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Written against the original menu BEFORE replacing its SearchServiceV3.
// RED/GREEN execution is deliberately left to the integrating agent.
//
// Source RED evidence:
// - DocumentFindMenu only dismisses on EditorState.dispose. Retained inactive
//   tabs keep the overlay bound to the old document, so an exact word visible
//   in the selected page is searched in the previous page instead.
// - The old menu's late-final service retains the first EditorState, with no
//   didUpdateWidget. Rebinding below keeps a zero count for a NEW document
//   containing the exact query, even after typing the query again.
// - There is no document-change subscription, so both local and remote edits
//   leave a previous zero count on screen.
// - Empty replacement returns early; whole-word literal mode sets service.regex
//   and accidentally expands replacement backreferences.
// No search/selection/transaction service is mocked. No backend is attached.
void main() {
  testWidgets('source RED: a retained tab cannot leave Find on the old page',
      (tester) async {
    final first = _editor([paragraphNode(text: 'unrelated first page')]);
    final second =
        _editor([paragraphNode(text: 'Needle in the selected page')]);
    final tabs = GlobalKey<_FindTabsState>();
    try {
      await tester.pumpWidget(_FindTabs(key: tabs, editors: [first, second]));
      await tester.pump();
      tabs.currentState!.open();
      await tester.pump();
      await _query(tester, 'needle');
      expect(_bar(tester).matchCount, 0);

      // No pointer event: outside-tap handling must not mask tab ownership.
      tabs.currentState!.select(1);
      await tester.pump();
      await tester.pump();
      expect(first.isDisposed, isFalse);
      expect(DocumentFindMenu.isOpen, isFalse);
      expect(find.byType(FindAndReplaceMenuWidget), findsNothing);

      tabs.currentState!.open();
      await tester.pump();
      await _query(tester, 'needle');
      expect(_bar(tester).matchCount, 1);
      expect(
        tester
            .widget<FindAndReplaceMenuWidget>(
              find.byType(FindAndReplaceMenuWidget),
            )
            .editorState,
        same(second),
      );
    } finally {
      DocumentFindMenu.dismiss();
      await _unmount(tester, [first, second]);
    }
  });

  testWidgets('control: literal matching crosses formatted delta runs',
      (tester) async {
    final editor = _editor([
      paragraphNode(
        delta: Delta()
          ..insert('A Nee', attributes: {AppFlowyRichTextKeys.bold: true})
          ..insert('dle and NEEDLE.'),
      ),
    ]);
    try {
      await _mount(tester, editor);
      expect(editor.selection, isNull);
      final before = editor.document.toJson();

      await _query(tester, 'needle');

      expect(_bar(tester).options.caseSensitive, isFalse);
      expect(_bar(tester).matchCount, 2);
      expect(editor.document.toJson(), before);
      expect(
        DocumentSearchHighlight.instance.rangesOf(editor.document.first!),
        const [TextRange(start: 2, end: 8), TextRange(start: 13, end: 19)],
      );
    } finally {
      await _unmount(tester, [editor]);
    }
  });

  testWidgets('source RED: a rebound menu searches the new editor, not the old',
      (tester) async {
    final first = _editor([paragraphNode(text: 'unrelated old document')]);
    final second = _editor([paragraphNode(text: 'A Needle in the new page')]);
    try {
      await _mount(tester, first);
      await _query(tester, 'needle');
      expect(_bar(tester).matchCount, 0);
      final menuElement = tester.element(find.byType(FindAndReplaceMenuWidget));

      // Same menu element and controller; only the actual editor owner changes.
      await _mount(tester, second);
      expect(
        tester.element(find.byType(FindAndReplaceMenuWidget)),
        same(menuElement),
      );
      expect(_bar(tester).findController.text, 'needle');
      expect(_bar(tester).matchCount, 1);
      expect(second.selection?.start.path, [0]);
      expect(second.selection?.start.offset, 2);

      await _query(tester, 'Needle');
      expect(_bar(tester).matchCount, 1);
      expect(
        DocumentSearchHighlight.instance.rangesOf(first.document.first!),
        isEmpty,
      );
    } finally {
      await _unmount(tester, [first, second]);
    }
  });

  testWidgets(
    'a rebound menu rejects callbacks captured for the previous editor',
    (tester) async {
      final first = _editor([paragraphNode(text: 'needle old needle')]);
      final second = _editor([paragraphNode(text: 'needle new needle')]);
      var dismissals = 0;
      void onDismiss() => dismissals++;
      try {
        await _mount(tester, first, replace: true, onDismiss: onDismiss);
        await _query(tester, 'needle');
        await tester.enterText(
          find.byKey(const ValueKey('replaceTextField')),
          'done',
        );
        final oldBar = _bar(tester);
        final menuElement =
            tester.element(find.byType(FindAndReplaceMenuWidget));
        final firstBefore = first.document.toJson();
        await _mount(tester, second, replace: true, onDismiss: onDismiss);
        expect(
          tester.element(find.byType(FindAndReplaceMenuWidget)),
          same(menuElement),
        );
        final secondBefore = second.document.toJson();
        final selection = second.selection;

        oldBar.onReplaceAll!();
        oldBar.onNext!();
        oldBar.onOptionsChanged(const FindOptions(caseSensitive: true));
        oldBar.onToggleReplace!();
        oldBar.onClose();
        oldBar.onTapOutside!();
        await tester.pump();
        await tester.pump();
        expect(first.document.toJson(), firstBefore);
        expect(second.document.toJson(), secondBefore);
        expect(second.selection, selection);
        expect(_bar(tester).options, const FindOptions());
        expect(_bar(tester).showReplace, isTrue);
        expect(_bar(tester).matchCount, 2);
        expect(_bar(tester).currentMatch, 1);
        expect(dismissals, 0);

        // Rejecting stale callbacks must not disable the replacement owner's UI.
        _bar(tester).onReplaceAll!();
        await tester.pump();
        await tester.pump();
        expect(second.document.first!.delta!.toPlainText(), 'done new done');
        expect(first.document.toJson(), firstBefore);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, [first, second]);
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  for (final remote in [false, true]) {
    testWidgets(
        'source RED: ${remote ? 'remote' : 'local'} edits refresh a zero count',
        (tester) async {
      final editor = _editor([paragraphNode(text: 'before')]);
      try {
        await _mount(tester, editor);
        await _query(tester, 'needle');
        expect(_bar(tester).matchCount, 0);

        await editor.apply(
          editor.transaction..insertText(editor.document.first!, 6, ' Needle'),
          isRemote: remote,
          withUpdateSelection: false,
        );
        await tester.pump();
        await tester.pump();

        expect(editor.document.first!.delta!.toPlainText(), 'before Needle');
        expect(_bar(tester).findController.text, 'needle');
        expect(_bar(tester).matchCount, 1);
        expect(
          DocumentSearchHighlight.instance.rangesOf(editor.document.first!),
          const [TextRange(start: 7, end: 13)],
        );
      } finally {
        await _unmount(tester, [editor]);
      }
    });
  }

  testWidgets('source RED: empty replacement deletes and undo restores styles',
      (tester) async {
    final editor = _editor([
      paragraphNode(
        delta: Delta()
          ..insert('left ')
          ..insert('needle', attributes: {AppFlowyRichTextKeys.bold: true})
          ..insert(' right'),
      ),
    ]);
    try {
      await _mount(tester, editor, replace: true);
      final before = editor.document.toJson();
      await _query(tester, 'needle');
      expect(_bar(tester).replaceController!.text, isEmpty);

      await tester.tap(find.byKey(const ValueKey('findReplaceOne')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(editor.document.first!.delta!.toPlainText(), 'left  right');
      expect(_bar(tester).matchCount, 0);
      editor.undoManager.undo();
      await tester.pump();
      expect(editor.document.toJson(), before);
      expect(_bar(tester).matchCount, 1);
    } finally {
      await _unmount(tester, [editor]);
    }
  });

  testWidgets('source RED: whole-word literal replacement stays literal',
      (tester) async {
    final editor = _editor([paragraphNode(text: 'needle needles')]);
    try {
      await _mount(tester, editor, replace: true);
      await _query(tester, 'needle');
      _bar(tester).onOptionsChanged(const FindOptions(wholeWord: true));
      await tester.pump();
      expect(_bar(tester).matchCount, 1);
      await tester.enterText(
        find.byKey(const ValueKey('replaceTextField')),
        r'\0 $1',
      );

      await tester.tap(find.byKey(const ValueKey('findReplaceOne')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(editor.document.first!.delta!.toPlainText(), r'\0 $1 needles');
      expect(_bar(tester).matchCount, 0);
    } finally {
      await _unmount(tester, [editor]);
    }
  });
}

EditorState _editor(List<Node> nodes) =>
    EditorState(document: Document(root: pageNode(children: nodes)))
      ..disableSealTimer = true;

FindReplaceBar _bar(WidgetTester tester) =>
    tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));

Future<void> _query(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const ValueKey('findTextField')), query);
  await tester.pump();
  await tester.pump();
}

Future<void> _mount(
  WidgetTester tester,
  EditorState editor, {
  bool replace = false,
  VoidCallback? onDismiss,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: AppFlowyEditor(
                key: ObjectKey(editor),
                editorState: editor,
                editorStyle: const EditorStyle.desktop(
                  padding: EdgeInsets.all(24),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FindAndReplaceMenuWidget(
                key: const ValueKey('stable-document-find-owner'),
                editorState: editor,
                showReplaceMenu: replace,
                onDismiss: onDismiss ?? () {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _unmount(WidgetTester tester, List<EditorState> editors) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 60));
  for (final editor in editors) {
    if (!editor.isDisposed) {
      DocumentSearchHighlight.instance.clear(editor);
      editor.dispose();
      editor.editableNotifier.dispose();
    }
  }
  await tester.pump();
}

class _FindTabs extends StatefulWidget {
  const _FindTabs({super.key, required this.editors});

  final List<EditorState> editors;

  @override
  State<_FindTabs> createState() => _FindTabsState();
}

class _FindTabsState extends State<_FindTabs> {
  late final List<BuildContext?> _owners =
      List.filled(widget.editors.length, null);
  int active = 0;
  int outsideClicks = 0;

  void select(int index) => setState(() => active = index);

  void open({bool replace = false}) => DocumentFindMenu.show(
        _owners[active]!,
        widget.editors[active],
        replace: replace,
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                key: const ValueKey('outside-document-find'),
                onPressed: () => outsideClicks++,
                child: const Text('Normal document action'),
              ),
              Expanded(
                child: IndexedStack(
                  index: active,
                  children: [
                    for (var index = 0; index < widget.editors.length; index++)
                      Builder(
                        builder: (context) {
                          _owners[index] = context;
                          return AppFlowyEditor(
                            key: ObjectKey(widget.editors[index]),
                            editorState: widget.editors[index],
                            editorStyle: const EditorStyle.desktop(
                              padding: EdgeInsets.all(24),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
