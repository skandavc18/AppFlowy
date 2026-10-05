import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/base/cover_title_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_paste_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shortcuts/text_field_aware_commands.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/undo_redo/custom_undo_redo_commands.dart';
import 'package:appflowy/shared/editor_focus_node.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Who gets the keyboard when several editors are mounted at once — a page, a
/// block on a dashboard, an AI chat answer — and when a text field sits inside
/// one of them.
void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);
  tearDown(keepEditorFocusNotifier.reset);

  group('a menu that kept the editor focused closes', () {
    testWidgets(
        'with plain focus nodes the last editor mounted takes the keyboard',
        (tester) async {
      // What appflowy_editor does on its own, and what this suite guards.
      final page = FocusNode(debugLabel: 'page');
      final other = FocusNode(debugLabel: 'other');
      addTearDown(page.dispose);
      addTearDown(other.dispose);
      final host = await _pumpTwoEditors(tester, page: page, other: other);

      await _closeMenuThatKeptFocus(tester, host);

      expect(FocusManager.instance.primaryFocus, same(other));
    });

    testWidgets(
      'only the editor that had the keyboard takes it back',
      (tester) async {
        final page = EditorFocusNode(debugLabel: 'page');
        final other = EditorFocusNode(debugLabel: 'other');
        addTearDown(page.dispose);
        addTearDown(other.dispose);
        final host = await _pumpTwoEditors(tester, page: page, other: other);

        await _closeMenuThatKeptFocus(tester, host);

        expect(FocusManager.instance.primaryFocus, same(page));

        // Backspace now reaches the page that shows the caret.
        await tester.sendKeyEvent(
          LogicalKeyboardKey.backspace,
          platform: 'windows',
        );
        await tester.pump();
        expect(host.pageParagraph.delta!.toPlainText(), 'pag');
        expect(host.otherParagraph.delta!.toPlainText(), 'other');
        // The edit seals its undo step on a timer.
        await tester.pump(const Duration(milliseconds: 100));
      },
      variant: windows,
    );

    testWidgets('an editor behind a dialog leaves the dialog the keyboard',
        (tester) async {
      final page = EditorFocusNode(debugLabel: 'page');
      final other = EditorFocusNode(debugLabel: 'other');
      addTearDown(page.dispose);
      addTearDown(other.dispose);
      final host = await _pumpTwoEditors(tester, page: page, other: other);
      final field = FocusNode(debugLabel: 'settings field');
      addTearDown(field.dispose);

      unawaited(
        showDialog<void>(
          context: host.context,
          builder: (_) => Dialog(
            child: TextField(focusNode: field, autofocus: true),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(FocusManager.instance.primaryFocus, same(field));

      keepEditorFocusNotifier.increase();
      await tester.pump();
      keepEditorFocusNotifier.decrease();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, same(field));
    });
  });

  group('a text field inside the editor', () {
    testWidgets(
      'keeps Backspace when the commands stand aside',
      (tester) async {
        final edited = await _backspaceInHeaderField(
          tester,
          standAsideForTextFields(standardCommandShortcutEvents),
        );
        expect(edited.field, 'insid');
        expect(edited.paragraph, 'outside');
      },
      variant: windows,
    );

    testWidgets(
      'loses Backspace to the page without them',
      (tester) async {
        final edited = await _backspaceInHeaderField(
          tester,
          standardCommandShortcutEvents,
        );
        expect(edited.field, 'inside');
        expect(edited.paragraph, 'outsid');
      },
      variant: windows,
    );
  });

  group('commands that stand aside for text fields', () {
    test('follow the wrapped command, including a customized shortcut', () {
      final inner = CommandShortcutEvent(
        key: 'test command',
        command: 'ctrl+k',
        getDescription: () => 'Test command',
        handler: (_) => KeyEventResult.handled,
      );
      final wrapped = TextFieldAwareCommand(inner);
      expect(wrapped.key, 'test command');
      expect(wrapped.description, 'Test command');

      wrapped.updateCommand(command: 'ctrl+j');
      expect(inner.command, 'ctrl+j');
      expect(wrapped.command, 'ctrl+j');
      expect(wrapped.keybindings, same(inner.keybindings));

      expect(standAsideForTextFields([wrapped]).single, same(wrapped));
    });

    test('blocks off a page copy, paste and undo, but never reach a title', () {
      final commands = embeddedBlocksCommandShortcuts();
      final keys = commands.map((command) => command.key).toSet();
      expect(commands, everyElement(isA<TextFieldAwareCommand>()));
      expect(keys, contains(customPasteCommand.key));
      expect(keys, contains(customUndoCommand.key));
      expect(keys, contains(customRedoCommand.key));
      expect(keys, isNot(contains(backspaceToTitle.key)));
      expect(keys, isNot(contains(arrowUpToTitle.key)));
      expect(keys, isNot(contains(arrowLeftToTitle.key)));
    });
  });
}

class _TwoEditors {
  _TwoEditors(this.context, this.pageParagraph, this.otherParagraph);

  final BuildContext context;
  final Node pageParagraph;
  final Node otherParagraph;
}

/// A page with the caret in it, and a second editor mounted after it — a
/// block on a dashboard, a chat answer.
Future<_TwoEditors> _pumpTwoEditors(
  WidgetTester tester, {
  required FocusNode page,
  required FocusNode other,
}) async {
  final pageParagraph = paragraphNode(text: 'page');
  final otherParagraph = paragraphNode(text: 'other');
  final pageEditor = EditorState(
    document: Document(root: pageNode(children: [pageParagraph])),
  );
  final otherEditor = EditorState(
    document: Document(root: pageNode(children: [otherParagraph])),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    pageEditor.dispose();
    otherEditor.dispose();
  });
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (inner) {
            context = inner;
            return Column(
              children: [
                SizedBox(
                  height: 200,
                  child:
                      AppFlowyEditor(editorState: pageEditor, focusNode: page),
                ),
                SizedBox(
                  height: 200,
                  child: AppFlowyEditor(
                    editorState: otherEditor,
                    focusNode: other,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  unawaited(
    pageEditor.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0], offset: 4)),
      reason: SelectionUpdateReason.uiEvent,
    ),
  );
  page.requestFocus();
  await tester.pump();
  expect(FocusManager.instance.primaryFocus, same(page));
  return _TwoEditors(context, pageParagraph, otherParagraph);
}

/// A toolbar menu: it keeps the editor focused while it is open, takes the
/// keyboard for itself, then closes.
Future<void> _closeMenuThatKeptFocus(
  WidgetTester tester,
  _TwoEditors host,
) async {
  final menu = FocusNode(debugLabel: 'menu');
  final entry = OverlayEntry(
    builder: (_) => Focus(focusNode: menu, child: const SizedBox()),
  );
  keepEditorFocusNotifier.increase();
  Overlay.of(host.context).insert(entry);
  await tester.pump();
  menu.requestFocus();
  await tester.pump();
  expect(FocusManager.instance.primaryFocus, same(menu));

  keepEditorFocusNotifier.decrease();
  await tester.pump();
  entry.remove();
  entry.dispose();
  menu.dispose();
  await tester.pump();
}

/// Backspace in a text field placed inside the editor (as its header), while
/// the page keeps its caret in the paragraph.
Future<({String field, String paragraph})> _backspaceInHeaderField(
  WidgetTester tester,
  List<CommandShortcutEvent> commands,
) async {
  final paragraph = paragraphNode(text: 'outside');
  final editor = EditorState(
    document: Document(root: pageNode(children: [paragraph])),
  );
  final controller = TextEditingController(text: 'inside');
  final fieldFocus = FocusNode(debugLabel: 'field in a block');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    controller.dispose();
    fieldFocus.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: AppFlowyEditor(
            editorState: editor,
            shrinkWrap: true,
            commandShortcutEvents: commands,
            header: TextField(controller: controller, focusNode: fieldFocus),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  unawaited(
    editor.updateSelectionWithReason(
      Selection.collapsed(Position(path: [0], offset: 7)),
      reason: SelectionUpdateReason.uiEvent,
    ),
  );
  await tester.pump();
  fieldFocus.requestFocus();
  await tester.pump();
  controller.selection = const TextSelection.collapsed(offset: 6);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.backspace, platform: 'windows');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return (field: controller.text, paragraph: paragraph.delta!.toPlainText());
}
