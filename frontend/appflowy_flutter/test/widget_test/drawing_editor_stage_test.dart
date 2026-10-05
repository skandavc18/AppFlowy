import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/drawing/drawing_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/drawing/drawing_editor_stage.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/drawing/excalidraw_editor_view.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _editorKey = ValueKey('fake-excalidraw');

void main() {
  group('Drawing editor stage', () {
    testWidgets('closing reads the editor once more and keeps what it had',
        (tester) async {
      final stage = await _open(tester);
      stage.editor.scene = 'scene-1';

      // Escape and the close button ask the route to pop; the stage holds it
      // until the editor has answered.
      unawaited(_navigator(tester).maybePop());
      await tester.pump();
      expect(stage.reported, ['scene-1']);

      await tester.pumpAndSettle();
      expect(find.byKey(_editorKey), findsNothing);
      // The read on the way out found nothing newer to hand on.
      expect(stage.reported, ['scene-1']);
    });

    testWidgets('an editor that never answers does not hold the window open',
        (tester) async {
      final stage = await _open(tester);
      final answer = stage.editor.hold = Completer<String?>();

      unawaited(_navigator(tester).maybePop());
      await tester.pump();
      expect(find.byKey(_editorKey), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(find.byKey(_editorKey), findsNothing);
      expect(stage.reported, isEmpty);

      // A scene that does arrive after all still reaches the host.
      answer.complete('scene-late');
      await tester.pump();
      expect(stage.reported, ['scene-late']);
    });

    testWidgets('the scene is read every few seconds and each change kept once',
        (tester) async {
      final stage = await _open(tester);

      stage.editor.scene = 'scene-1';
      await tester.pump(const Duration(seconds: 4));
      expect(stage.editor.reads, 1);
      expect(stage.reported, ['scene-1']);

      await tester.pump(const Duration(seconds: 4));
      expect(stage.editor.reads, 2);
      expect(stage.reported, ['scene-1']);

      stage.editor.scene = 'scene-2';
      await tester.pump(const Duration(seconds: 4));
      expect(stage.reported, ['scene-1', 'scene-2']);

      // What the editor reports by itself goes straight through, once.
      stage.editorChanged!('scene-3');
      stage.editorChanged!('scene-3');
      expect(stage.reported, ['scene-1', 'scene-2', 'scene-3']);
    });

    testWidgets('leaving by another way still reads the editor on the way out',
        (tester) async {
      final stage = await _open(tester);
      stage.editor.scene = 'scene-1';

      _navigator(tester).pop();
      await tester.pump();
      expect(stage.reported, ['scene-1']);

      await tester.pumpAndSettle();
      expect(find.byKey(_editorKey), findsNothing);
    });

    testWidgets('a read-only drawing closes at once without asking',
        (tester) async {
      final stage = await _open(tester, editable: false);

      unawaited(_navigator(tester).maybePop());
      await tester.pumpAndSettle();
      expect(find.byKey(_editorKey), findsNothing);
      expect(stage.editor.reads, 0);
      expect(stage.reported, isEmpty);
    });
  });

  group('writeDrawingScene', () {
    testWidgets('writes a changed scene and leaves an unchanged one alone',
        (tester) async {
      final node = _drawingNode('scene-0');
      final editor =
          EditorState(document: Document(root: pageNode(children: [node])));

      await writeDrawingScene(editor, node, 'scene-1');
      await tester.pump(const Duration(milliseconds: 100));
      expect(_sceneAt(editor, [0]), 'scene-1');
      final written = editor.undoManager.undoStack.last;
      final operations = written.operations.length;

      await writeDrawingScene(editor, node, 'scene-1');
      await tester.pump(const Duration(milliseconds: 100));
      expect(editor.undoManager.undoStack.last, same(written));
      expect(written.operations, hasLength(operations));
      editor.dispose();
    });

    testWidgets('does not write into a block deleted while it was open',
        (tester) async {
      final node = _drawingNode('scene-0');
      final following = paragraphNode(text: 'after');
      final editor = EditorState(
        document: Document(root: pageNode(children: [node, following])),
      );
      await editor.apply(editor.transaction..deleteNode(node));

      await writeDrawingScene(editor, node, 'scene-1');
      await tester.pump(const Duration(milliseconds: 100));
      final remaining = editor.document.root.children;
      expect(remaining, hasLength(1));
      expect(remaining.single, same(following));
      expect(remaining.single.attributes[DrawingBlockKeys.scene], isNull);
      editor.dispose();
    });
  });
}

/// Stands in for the web view: answers reads with [scene], or waits on
/// [hold] when one is set.
class _FakeEditor extends ExcalidrawEditorController {
  String? scene;
  Completer<String?>? hold;
  int reads = 0;

  @override
  bool get isAttached => true;

  @override
  Future<String?> requestScene() {
    reads++;
    return hold?.future ?? Future.value(scene);
  }
}

class _Stage {
  final editor = _FakeEditor();
  final reported = <String>[];

  /// How the editor itself reports a change, as handed to its builder.
  ValueChanged<String>? editorChanged;
}

Future<_Stage> _open(WidgetTester tester, {bool editable = true}) async {
  // Untranslated keys in the test font make the save bar's labels several
  // times their real width; give them a window they fit in.
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(2000, 900);
  addTearDown(tester.view.reset);
  final stage = _Stage();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: DrawingEditorStage(
                      scene: 'scene-0',
                      editable: editable,
                      controller: stage.editor,
                      onSceneChanged: stage.reported.add,
                      editorBuilder: (context, controller, onSceneChanged) {
                        stage.editorChanged = onSceneChanged;
                        return const SizedBox.expand(key: _editorKey);
                      },
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byKey(_editorKey), findsOneWidget);
  return stage;
}

NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

Node _drawingNode(String scene) => Node(
      type: DrawingBlockKeys.type,
      attributes: {DrawingBlockKeys.scene: scene},
    );

Object? _sceneAt(EditorState editor, List<int> path) =>
    editor.document.nodeAtPath(path)?.attributes[DrawingBlockKeys.scene];
