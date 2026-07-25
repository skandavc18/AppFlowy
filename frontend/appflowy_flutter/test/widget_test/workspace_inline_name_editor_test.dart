import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const titleStyle = TextStyle(
    color: Color(0xFF242424),
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 22 / 17,
  );

  testWidgets(
    'edits as undecorated text without changing title dimensions',
    (tester) async {
      var title = 'Quarterly report.md';
      var editing = false;
      final submittedNames = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: WorkspaceInlineEditableText(
                          key: const ValueKey('rename-surface'),
                          text: title,
                          editing: editing,
                          style: titleStyle,
                          selectFileStem: true,
                          onDoubleTap: () => setState(() => editing = true),
                          onSubmitted: (name) async {
                            submittedNames.add(name);
                            setState(() {
                              title = name;
                              editing = false;
                            });
                            return true;
                          },
                          onCancelled: () => setState(() => editing = false),
                        ),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('outside-target'),
                      onPressed: () {},
                      child: const Text('Outside'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final renameSurface = find.byKey(const ValueKey('rename-surface'));
      final displayText = tester.widget<Text>(find.text(title));
      final displaySize = tester.getSize(renameSurface);
      expect(displayText.style, titleStyle);

      await tester.tap(find.text(title));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();

      final editor = find.byKey(
        const ValueKey('workspace-inline-name-editor'),
      );
      final editableText = tester.widget<EditableText>(editor);
      final switcher = tester.widget<AnimatedSwitcher>(
        find.descendant(
          of: renameSurface,
          matching: find.byType(AnimatedSwitcher),
        ),
      );

      expect(editor, findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(editableText.style, titleStyle);
      expect(editableText.cursorWidth, 1.15);
      expect(
        editableText.controller.selection,
        const TextSelection(
          baseOffset: 0,
          extentOffset: 16,
        ),
      );
      expect(switcher.duration, const Duration(milliseconds: 120));
      expect(tester.getSize(renameSurface), displaySize);

      await tester.enterText(editor, 'Roadmap.md');
      await tester.tap(find.byKey(const ValueKey('outside-target')));
      await tester.pumpAndSettle();

      expect(submittedNames, ['Roadmap.md']);
      expect(find.text('Roadmap.md'), findsOneWidget);
    },
  );

  testWidgets('Enter confirms and Escape cancels inline renames', (
    tester,
  ) async {
    var title = 'Project brief';
    var editing = true;
    var cancelCount = 0;
    final submittedNames = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => WorkspaceInlineEditableText(
              text: title,
              editing: editing,
              style: titleStyle,
              onDoubleTap: () => setState(() => editing = true),
              onSubmitted: (name) async {
                submittedNames.add(name);
                setState(() {
                  title = name;
                  editing = false;
                });
                return true;
              },
              onCancelled: () {
                cancelCount++;
                setState(() => editing = false);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var editor = find.byKey(const ValueKey('workspace-inline-name-editor'));
    await tester.enterText(editor, 'Discarded title');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(cancelCount, 1);
    expect(submittedNames, isEmpty);
    expect(find.text('Project brief'), findsOneWidget);

    await tester.tap(find.text('Project brief'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Project brief'));
    await tester.pumpAndSettle();

    editor = find.byKey(const ValueKey('workspace-inline-name-editor'));
    await tester.enterText(editor, 'Accepted title');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(submittedNames, ['Accepted title']);
    expect(find.text('Accepted title'), findsOneWidget);
  });

  test('rename shortcuts follow desktop platform conventions', () {
    expect(
      isWorkspaceRenameShortcut(
        TargetPlatform.windows,
        LogicalKeyboardKey.f2,
      ),
      isTrue,
    );
    expect(
      isWorkspaceRenameShortcut(TargetPlatform.linux, LogicalKeyboardKey.f2),
      isTrue,
    );
    expect(
      isWorkspaceRenameShortcut(TargetPlatform.macOS, LogicalKeyboardKey.f2),
      isFalse,
    );
    expect(
      isWorkspaceRenameShortcut(
        TargetPlatform.macOS,
        LogicalKeyboardKey.enter,
      ),
      isTrue,
    );
    expect(
      isWorkspaceRenameShortcut(
        TargetPlatform.windows,
        LogicalKeyboardKey.enter,
      ),
      isFalse,
    );
    expect(
      isWorkspaceRenameShortcut(TargetPlatform.android, LogicalKeyboardKey.f2),
      isFalse,
    );
  });
}
