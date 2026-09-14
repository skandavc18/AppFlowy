import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final shrinkWrap in [false, true]) {
    testWidgets('editor block construction (shrinkWrap: $shrinkWrap)', (
      tester,
    ) async {
      const count = 2000;
      final editor = EditorState(
        document: Document(
          root: pageNode(
            children: List.generate(
              count,
              (index) => paragraphNode(text: 'Generated paragraph $index'),
            ),
          ),
        ),
      );
      final scroll = EditorScrollController(
        editorState: editor,
        shrinkWrap: shrinkWrap,
      );
      final built = <String>{};
      await tester.pumpWidget(
        MaterialApp(
          home: PremiumScrollScope(
            enabled: true,
            child: AppFlowyEditor(
              editorState: editor,
              editorScrollController: scroll,
              editable: false,
              disableSelectionService: true,
              disableKeyboardService: true,
              disableAutoScroll: true,
              contextMenuItems: const [],
              blockWrapper: (_, {required node, required child}) {
                built.add(node.id);
                return child;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      if (shrinkWrap) {
        expect(built.length, count);
      } else {
        expect(built, isNotEmpty);
        expect(built.length, lessThan(count ~/ 10));
        final last = editor.document.root.children.last.id;
        expect(built, isNot(contains(last)));
        scroll.itemScrollController.jumpTo(index: count - 1);
        await tester.pumpAndSettle();
        expect(built, contains(last));
        expect(built.length, lessThan(count ~/ 5));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      editor.dispose();
    });
  }
}
