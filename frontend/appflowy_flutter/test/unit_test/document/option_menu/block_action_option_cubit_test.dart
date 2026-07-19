import 'dart:convert';

import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_option_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockClipboardService extends Mock implements ClipboardService {}

class MemoryClipboardService extends ClipboardService {
  ClipboardServiceData data = const ClipboardServiceData();

  @override
  Future<void> setData(ClipboardServiceData data) async {
    this.data = data;
  }

  @override
  Future<ClipboardServiceData> getData() async => data;
}

void main() {
  group('block action option cubit:', () {
    setUpAll(() {
      Log.shared.disableLog = true;
      registerFallbackValue(const ClipboardServiceData());
    });

    tearDownAll(() {
      Log.shared.disableLog = false;
    });

    tearDown(() {
      if (getIt.isRegistered<ClipboardService>()) {
        getIt.unregister<ClipboardService>();
      }
    });

    test('delete blocks', () async {
      const text = 'paragraph';
      final document = Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: text),
          paragraphNode(text: text),
          paragraphNode(text: text),
        ]);

      final editorState = EditorState(document: document);
      final cubit = BlockActionOptionCubit(
        editorState: editorState,
        blockComponentBuilder: {},
      );

      editorState.selection = Selection(
        start: Position(path: [0]),
        end: Position(path: [2], offset: text.length),
      );
      editorState.selectionType = SelectionType.block;

      await cubit.handleAction(OptionAction.delete, document.nodeAtPath([0])!);

      // all the nodes should be deleted
      expect(document.root.children, isEmpty);

      editorState.dispose();
    });

    test('duplicate blocks', () async {
      const text = 'paragraph';
      final document = Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: text),
          paragraphNode(text: text),
          paragraphNode(text: text),
        ]);

      final editorState = EditorState(document: document);
      final cubit = BlockActionOptionCubit(
        editorState: editorState,
        blockComponentBuilder: {},
      );

      editorState.selection = Selection(
        start: Position(path: [0]),
        end: Position(path: [2], offset: text.length),
      );
      editorState.selectionType = SelectionType.block;

      await cubit.handleAction(
        OptionAction.duplicate,
        document.nodeAtPath([0])!,
      );

      expect(document.root.children, hasLength(6));

      editorState.dispose();
    });

    test('copy block contents using rich clipboard data', () async {
      const text = 'paragraph';
      const imageUrl = 'https://example.com/image.png';
      final document = Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: text),
          imageNode(url: imageUrl),
        ]);
      final editorState = EditorState(document: document);
      final cubit = BlockActionOptionCubit(
        editorState: editorState,
        blockComponentBuilder: {},
      );
      final clipboard = MockClipboardService();
      when(() => clipboard.setData(any())).thenAnswer((_) async {});
      getIt.registerSingleton<ClipboardService>(clipboard);

      editorState.selection = Selection(
        start: Position(path: [0]),
        end: Position(path: [1]),
      );
      editorState.selectionType = SelectionType.block;

      await cubit.handleAction(OptionAction.copy, document.nodeAtPath([0])!);
      await Future<void>.delayed(Duration.zero);

      final captured = verify(() => clipboard.setData(captureAny()))
          .captured
          .single as ClipboardServiceData;
      expect(captured.plainText, text);
      expect(captured.html, isNotEmpty);
      final copiedDocument = Document.fromJson(
        jsonDecode(captured.inAppJson!) as Map<String, dynamic>,
      );
      expect(copiedDocument.root.children, hasLength(2));
      expect(
        copiedDocument.root.children[1].attributes[ImageBlockKeys.url],
        imageUrl,
      );

      copiedDocument.dispose();
      editorState.dispose();
    });

    test('cut block contents using rich clipboard data', () async {
      const text = 'cut paragraph';
      final document = Document.blank()
        ..insert([0], [paragraphNode(text: text)]);
      final editorState = EditorState(document: document);
      final cubit = BlockActionOptionCubit(
        editorState: editorState,
        blockComponentBuilder: {},
      );
      final clipboard = MockClipboardService();
      when(() => clipboard.setData(any())).thenAnswer((_) async {});
      getIt.registerSingleton<ClipboardService>(clipboard);
      editorState.selection = Selection.collapsed(Position(path: [0]));
      editorState.selectionType = SelectionType.block;

      await cubit.handleAction(
        OptionAction.cut,
        document.nodeAtPath([0])!,
      );
      await Future<void>.delayed(Duration.zero);

      final captured = verify(() => clipboard.setData(captureAny()))
          .captured
          .single as ClipboardServiceData;
      expect(captured.plainText, text);
      expect(captured.inAppJson, isNotEmpty);
      expect(document.root.children, isEmpty);

      editorState.dispose();
    });

    test('paste block immediately after cutting it', () async {
      const cutText = 'cut paragraph';
      const targetText = 'target';
      final document = Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: cutText),
          paragraphNode(text: targetText),
        ]);
      final editorState = EditorState(document: document);
      final cubit = BlockActionOptionCubit(
        editorState: editorState,
        blockComponentBuilder: {},
      );
      getIt.registerSingleton<ClipboardService>(MemoryClipboardService());
      editorState.selection = Selection.collapsed(Position(path: [0]));
      editorState.selectionType = SelectionType.block;

      await cubit.handleAction(
        OptionAction.cut,
        document.nodeAtPath([0])!,
      );
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: targetText.length),
      );
      editorState.selectionType = null;
      await cubit.handleAction(
        OptionAction.paste,
        document.nodeAtPath([0])!,
      );

      expect(
        document.nodeAtPath([0])!.delta!.toPlainText(),
        '$targetText$cutText',
      );

      editorState.dispose();
    });

    test('move block up and down', () async {
      final document = Document.blank()
        ..insert([
          0,
        ], [
          paragraphNode(text: 'first'),
          paragraphNode(text: 'second'),
        ]);
      final editorState = EditorState(document: document);
      final cubit = BlockActionOptionCubit(
        editorState: editorState,
        blockComponentBuilder: {},
      );

      await cubit.handleAction(
        OptionAction.moveUp,
        document.nodeAtPath([1])!,
      );
      expect(document.nodeAtPath([0])!.delta!.toPlainText(), 'second');

      await cubit.handleAction(
        OptionAction.moveDown,
        document.nodeAtPath([0])!,
      );
      expect(document.nodeAtPath([0])!.delta!.toPlainText(), 'first');

      editorState.dispose();
    });

    test('add blocks above and below', () async {
      final document = Document.blank()
        ..insert([0], [paragraphNode(text: 'existing')]);
      final editorState = EditorState(document: document);
      final cubit = BlockActionOptionCubit(
        editorState: editorState,
        blockComponentBuilder: {},
      );

      await cubit.handleAction(
        OptionAction.addAbove,
        document.nodeAtPath([0])!,
      );
      expect(document.root.children, hasLength(2));
      expect(document.nodeAtPath([0])!.delta, isEmpty);
      expect(document.nodeAtPath([1])!.delta!.toPlainText(), 'existing');
      expect(editorState.selection?.start.path, [0]);

      await cubit.handleAction(
        OptionAction.addBelow,
        document.nodeAtPath([1])!,
      );
      expect(document.root.children, hasLength(3));
      expect(document.nodeAtPath([2])!.delta, isEmpty);
      expect(editorState.selection?.start.path, [2]);

      editorState.dispose();
    });

    test('paste clipboard contents into the block', () async {
      final document = Document.blank()
        ..insert([0], [paragraphNode(text: 'before ')]);
      final editorState = EditorState(document: document);
      final cubit = BlockActionOptionCubit(
        editorState: editorState,
        blockComponentBuilder: {},
      );
      final clipboard = MockClipboardService();
      when(clipboard.getData).thenAnswer(
        (_) async => const ClipboardServiceData(plainText: 'after'),
      );
      getIt.registerSingleton<ClipboardService>(clipboard);
      editorState.selection = Selection.collapsed(
        Position(path: [0], offset: 7),
      );

      await cubit.handleAction(
        OptionAction.paste,
        document.nodeAtPath([0])!,
      );

      expect(
        document.nodeAtPath([0])!.delta!.toPlainText(),
        'before after',
      );

      editorState.dispose();
    });

    test('split block into columns and stack columns vertically', () async {
      const text = 'left column';
      final document = Document.blank()
        ..insert([0], [paragraphNode(text: text)]);
      final editorState = EditorState(document: document);
      final cubit = BlockActionOptionCubit(
        editorState: editorState,
        blockComponentBuilder: {},
      );

      await cubit.handleAction(
        OptionAction.splitIntoColumns,
        document.nodeAtPath([0])!,
      );

      final columns = document.nodeAtPath([0])!;
      expect(columns.type, SimpleColumnsBlockKeys.type);
      expect(columns.children, hasLength(2));
      expect(columns.children[0].children.single.delta!.toPlainText(), text);
      expect(columns.children[1].children.single.delta, isEmpty);

      await cubit.handleAction(
        OptionAction.stackColumns,
        columns.children[0].children.single,
      );

      expect(document.root.children, hasLength(2));
      expect(document.nodeAtPath([0])!.delta!.toPlainText(), text);
      expect(document.nodeAtPath([1])!.delta, isEmpty);

      editorState.dispose();
    });
  });
}
