import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_title.dart';
import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'borrowed binding rebinds editor/controller without altering a native draft',
      (tester) async {
    final first = EditorState.blank()..disableSealTimer = true;
    final second = EditorState.blank()..disableSealTimer = true;
    final oldController = TextEditingController(text: 'Old needle');
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'New needle draft',
        selection: TextSelection(baseOffset: 0, extentOffset: 3),
        composing: TextRange(start: 4, end: 10),
      ),
    );
    final focus = FocusNode();
    var notifications = 0;
    controller.addListener(() => notifications++);
    Widget app(EditorState editor, TextEditingController text) => MaterialApp(
          home: Scaffold(
            body: DocumentFindTitleBinding(
              editorState: editor,
              controller: text,
              child: TextField(controller: text, focusNode: focus),
            ),
          ),
        );
    try {
      await tester.pumpWidget(app(first, oldController));
      expect(DocumentFindTitle.of(first).text, 'Old needle');
      final native = tester.element(find.byType(EditableText));
      final draft = controller.value;
      await tester.pumpWidget(app(second, controller));
      expect(DocumentFindTitle.of(first).text, isNull);
      expect(DocumentFindTitle.of(second).text, draft.text);
      expect(tester.element(find.byType(EditableText)), same(native));
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller,
        same(controller),
      );
      final session = DocumentFindSession(second);
      session.search('needle', const FindOptions());
      await tester.pump();
      session.navigate();
      await tester.pump();
      expect(controller.value, draft);
      expect(notifications, 0);
      expect(session.matches.single.kind, DocumentFindResultKind.title);
      session.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(DocumentFindTitle.of(second).text, isNull);
      // Borrowed ownership never disposes either native controller.
      oldController.text = 'Still owned by the cell';
      controller.text = 'Still editable';
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      oldController.dispose();
      controller.dispose();
      focus.dispose();
      first.dispose();
      second.dispose();
    }
  });

  testWidgets(
      'an older binding cannot detach a newer owner of the same controller',
      (tester) async {
    final editor = EditorState.blank()..disableSealTimer = true;
    final controller = TextEditingController(text: 'Visible needle');
    final older = Object();
    final newer = Object();
    final title = DocumentFindTitle.of(editor);
    late BuildContext field;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              field = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      title.attach(controller, () => field, owner: older);
      title.attach(controller, () => field, owner: newer);
      title.detach(controller, owner: older);
      expect(title.text, 'Visible needle');
      title.requireNativeTitle(newer);
      title.detach(controller, owner: newer);
      expect(title.text, '');
      title.releaseNativeTitle(older);
      expect(title.text, '');
      title.releaseNativeTitle(newer);
      expect(title.text, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      title.reveal();
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      title.detach(controller, owner: newer);
      controller.dispose();
      editor.dispose();
    }
  });

  testWidgets('borrowed paint preserves and restores the native field painter',
      (tester) async {
    final editor = EditorState.blank()..disableSealTimer = true;
    final controller = TextEditingController(text: 'needle');
    final focus = FocusNode();
    final original = _NativePainter();
    Widget app(EditorState? bound) => MaterialApp(
          home: Scaffold(
            body: DocumentFindTitleBinding(
              editorState: bound,
              controller: controller,
              child: TextField(controller: controller, focusNode: focus),
            ),
          ),
        );
    try {
      await tester.pumpWidget(app(null));
      final native = tester.state<EditableTextState>(find.byType(EditableText));
      final render = native.renderEditable;
      render.painter = original;
      await tester.pumpWidget(app(editor));
      expect(render.painter, isNot(same(original)));
      final value = controller.value;
      await tester.pumpWidget(app(null));
      expect(render.painter, same(original));
      expect(original.disposed, isFalse);
      expect(controller.value, value);
      expect(
        tester.state<EditableTextState>(find.byType(EditableText)),
        same(native),
      );
      expect(DocumentFindTitle.of(editor).text, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(original.disposed, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focus.dispose();
      editor.dispose();
      original.dispose();
    }
  });
}

class _NativePainter extends RenderEditablePainter {
  bool disposed = false;
  @override
  void paint(Canvas canvas, Size size, RenderEditable renderEditable) {}
  @override
  bool shouldRepaint(RenderEditablePainter? oldDelegate) => false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
