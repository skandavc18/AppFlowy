import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets(
    'map-only shortcuts reproduce an ancestor override; native actions fix it',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);

      for (final protected in [false, true]) {
        final overrides = <Intent>[];
        final changes = <String>[];
        var pageKeys = 0;
        final field = TextField(
          controller: controller,
          focusNode: focus,
          onChanged: changes.add,
        );
        await _pump(
          tester,
          actions: _pageActions(overrides),
          onPageKey: () => pageKeys++,
          child: protected
              ? TextEntryShortcuts(child: field)
              : Shortcuts(shortcuts: textEntryShortcuts, child: field),
        );
        await _focus(tester, focus);
        controller.value = _value('abc', 3);
        await _press(tester, LogicalKeyboardKey.backspace);

        // Both maps match and consume the key. Only the action boundary
        // prevents EditableText's overridable action invoking the page action.
        expect(controller.text, protected ? 'ab' : 'abc');
        expect(changes, protected ? ['ab'] : isEmpty);
        expect(overrides, hasLength(protected ? 0 : 1));
        expect(pageKeys, 0);
        expect(FocusManager.instance.primaryFocus, same(focus));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: windows,
  );

  for (final cluster in const [
    (label: 'combining accent', text: 'e\u0301'),
    (label: 'flag', text: '🇮🇳'),
    (label: 'joined emoji with skin tone', text: '👩🏽‍🚀'),
  ]) {
    testWidgets(
      'physical Backspace repeat and Delete preserve ${cluster.label} graphemes',
      (tester) async {
        final controller = TextEditingController();
        final focus = FocusNode();
        final changes = <String>[];
        final formatted = <TextEditingValue>[];
        final overrides = <Intent>[];
        var pageKeys = 0;
        addTearDown(controller.dispose);
        addTearDown(focus.dispose);
        await _pump(
          tester,
          actions: _pageActions(overrides),
          onPageKey: () => pageKeys++,
          child: TextEntryShortcuts(
            child: TextField(
              controller: controller,
              focusNode: focus,
              onChanged: changes.add,
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  formatted.add(newValue);
                  return newValue;
                }),
              ],
            ),
          ),
        );
        await _focus(tester, focus);
        final text = 'a${cluster.text}${cluster.text}';
        controller.value = _value(text, text.length);
        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.backspace,
          physicalKey: PhysicalKeyboardKey.backspace,
          platform: 'windows',
        );
        try {
          await tester.pump();
          expect(controller.text, 'a${cluster.text}');
          await tester.sendKeyRepeatEvent(
            LogicalKeyboardKey.backspace,
            physicalKey: PhysicalKeyboardKey.backspace,
            platform: 'windows',
          );
          await tester.pump();
          expect(controller.text, 'a');
        } finally {
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.backspace,
            physicalKey: PhysicalKeyboardKey.backspace,
            platform: 'windows',
          );
        }
        expect(changes, ['a${cluster.text}', 'a']);
        expect(formatted.map((value) => value.text), changes);

        controller.value = _value('a${cluster.text}b', 1);
        await _press(tester, LogicalKeyboardKey.delete);
        expect(controller.text, 'ab');
        expect(controller.selection, const TextSelection.collapsed(offset: 1));

        // Even a selection starting INSIDE a grapheme removes the whole
        // grapheme, not half a surrogate pair/combining/ZWJ sequence.
        controller.value = TextEditingValue(
          text: 'a${cluster.text}b',
          selection: TextSelection(
            baseOffset: 2,
            extentOffset: 1 + cluster.text.length,
          ),
        );
        await _press(tester, LogicalKeyboardKey.backspace);
        expect(controller.text, 'ab');
        expect(changes, ['a${cluster.text}', 'a', 'ab', 'ab']);
        expect(formatted.map((value) => value.text), changes);
        expect(overrides, isEmpty);
        expect(pageKeys, 0);
        expect(tester.takeException(), isNull);
      },
      variant: windows,
    );
  }

  testWidgets(
    'word deletion arrows clipboard and undo bypass page actions and dispatcher',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      final overrides = <Intent>[];
      final dispatched = <Intent>[];
      final changes = <String>[];
      final clipboard = _Clipboard(tester);
      var pageKeys = 0;
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await _pump(
        tester,
        actions: _pageActions(overrides),
        dispatcher: _DroppingDispatcher(dispatched),
        onPageKey: () => pageKeys++,
        child: TextEntryShortcuts(
          child: TextField(
            controller: controller,
            focusNode: focus,
            onChanged: changes.add,
          ),
        ),
      );
      await _focus(tester, focus);
      controller.value = _value('alpha beta', 10);
      await _press(tester, LogicalKeyboardKey.backspace, control: true);
      expect(controller.text, 'alpha ');
      controller.value = _value('alpha beta', 6);
      await _press(tester, LogicalKeyboardKey.delete, control: true);
      expect(controller.text, 'alpha ');

      controller.value = _value('abcd', 2);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
      await _press(tester, LogicalKeyboardKey.arrowRight, shift: true);
      expect(controller.selection,
          const TextSelection(baseOffset: 1, extentOffset: 2));
      await _press(tester, LogicalKeyboardKey.keyC, control: true);
      expect(clipboard.text, 'b');
      expect(controller.text, 'abcd');
      await _press(tester, LogicalKeyboardKey.keyX, control: true);
      expect(controller.text, 'acd');
      clipboard.text = '🙂';
      await _press(tester, LogicalKeyboardKey.keyV, control: true);
      expect(controller.text, 'a🙂cd');
      expect(changes.last, 'a🙂cd');
      await _press(tester, LogicalKeyboardKey.keyA, control: true);
      expect(controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 5));

      controller.value = _value('alpha beta', 10);
      await _press(tester, LogicalKeyboardKey.arrowLeft, control: true);
      expect(controller.selection, const TextSelection.collapsed(offset: 6));
      await _press(tester, LogicalKeyboardKey.arrowRight,
          control: true, shift: true);
      expect(controller.selection,
          const TextSelection(baseOffset: 6, extentOffset: 10));

      controller.value = _value('ab', 2);
      // EditableText's real undo history coalesces changes for 500 ms.
      await tester.pump(const Duration(milliseconds: 600));
      await _press(tester, LogicalKeyboardKey.backspace);
      await tester.pump(const Duration(milliseconds: 600));
      await _press(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(controller.text, 'ab');
      await _press(tester, LogicalKeyboardKey.keyZ, control: true, shift: true);
      expect(controller.text, 'a');
      expect(overrides, isEmpty);
      expect(dispatched, isEmpty);
      expect(pageKeys, 0);
      expect(tester.takeException(), isNull);
    },
    variant: windows,
  );

  testWidgets(
    'vertical arrows keep the native base-typed movement action',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      final overrides = <Intent>[];
      var pageKeys = 0;
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await _pump(
        tester,
        actions: _pageActions(overrides),
        onPageKey: () => pageKeys++,
        child: TextEntryShortcuts(
          child: TextField(
            controller: controller,
            focusNode: focus,
            maxLines: 3,
          ),
        ),
      );
      await _focus(tester, focus);
      controller.value = _value('aaa\naaa\naaa', 5);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      // Vertical movement preserves Flutter's native caret affinity, which
      // may be upstream even when the visual position is within one line.
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.baseOffset, 1);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.baseOffset, 5);
      await _press(tester, LogicalKeyboardKey.arrowDown, shift: true);
      expect(controller.selection.baseOffset, 5);
      expect(controller.selection.extentOffset, 9);
      expect(controller.text, 'aaa\naaa\naaa');
      expect(overrides, isEmpty);
      expect(pageKeys, 0);
      expect(tester.takeException(), isNull);
    },
    variant: windows,
  );

  testWidgets(
    'read-only native edits and boundary no-ops never delete the page',
    (tester) async {
      final controller = TextEditingController(text: 'keep');
      final focus = FocusNode();
      final overrides = <Intent>[];
      final changes = <String>[];
      final clipboard = _Clipboard(tester);
      var pageKeys = 0;
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      for (final readOnly in [true, false]) {
        await _pump(
          tester,
          actions: _pageActions(overrides),
          onPageKey: () => pageKeys++,
          child: TextEntryShortcuts(
            child: TextField(
              controller: controller,
              focusNode: focus,
              readOnly: readOnly,
              onChanged: changes.add,
            ),
          ),
        );
        await _focus(tester, focus);
        controller.value = _value(readOnly ? 'keep' : '', 0);
        for (final key in [
          LogicalKeyboardKey.backspace,
          LogicalKeyboardKey.delete,
        ]) {
          await _press(tester, key);
          await _press(tester, key, control: true);
        }
        if (readOnly) {
          controller.selection =
              const TextSelection(baseOffset: 0, extentOffset: 4);
          await _press(tester, LogicalKeyboardKey.keyC, control: true);
          expect(clipboard.text, 'keep');
          await _press(tester, LogicalKeyboardKey.keyX, control: true);
          clipboard.text = 'not allowed';
          await _press(tester, LogicalKeyboardKey.keyV, control: true);
        }
        expect(controller.text, readOnly ? 'keep' : '');
        expect(changes, isEmpty);
        expect(overrides, isEmpty);
        expect(pageKeys, 0);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: windows,
  );

  testWidgets(
    'only the primary field edits; non-text focus retains parent Backspace',
    (tester) async {
      final first = TextEditingController(text: 'first');
      final second = TextEditingController(text: 'second');
      final firstFocus = FocusNode();
      final secondFocus = FocusNode();
      final nonTextFocus = FocusNode();
      var pageKeys = 0;
      for (final controller in [first, second]) {
        addTearDown(controller.dispose);
      }
      for (final focus in [firstFocus, secondFocus, nonTextFocus]) {
        addTearDown(focus.dispose);
      }
      await _pump(
        tester,
        onPageKey: () => pageKeys++,
        child: TextEntryShortcuts(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextEntryShortcuts(
                child: TextField(controller: first, focusNode: firstFocus),
              ),
              TextField(controller: second, focusNode: secondFocus),
              Focus(focusNode: nonTextFocus, child: const Text('Page control')),
            ],
          ),
        ),
      );
      await _focus(tester, firstFocus);
      first.selection = const TextSelection.collapsed(offset: 5);
      await _press(tester, LogicalKeyboardKey.backspace);
      expect(first.text, 'firs',
          reason: 'Nested wrappers must not double edit.');
      expect(second.text, 'second');
      await _focus(tester, secondFocus);
      second.selection = const TextSelection.collapsed(offset: 6);
      await _press(tester, LogicalKeyboardKey.backspace);
      expect(first.text, 'firs');
      expect(second.text, 'secon');
      expect(pageKeys, 0);
      nonTextFocus.requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.backspace);
      expect(pageKeys, 1);
      expect(first.text, 'firs');
      expect(second.text, 'secon');
    },
    variant: windows,
  );

  testWidgets(
    'ProviderTextField uses the same native action boundary',
    (tester) async {
      final controller = TextEditingController(text: 'token');
      final overrides = <Intent>[];
      addTearDown(controller.dispose);
      await _pump(
        tester,
        actions: _pageActions(overrides),
        child: Builder(
          builder: (context) => ProviderTextField(
            label: 'Token',
            controller: controller,
            palette: FolderExplorerPalette.of(context),
            obscure: true,
          ),
        ),
      );
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      await _focus(tester, editable.focusNode);
      controller.selection = const TextSelection.collapsed(offset: 5);
      await _press(tester, LogicalKeyboardKey.backspace);
      expect(controller.text, 'toke');
      expect(overrides, isEmpty);
    },
    variant: windows,
  );

  testWidgets(
    'real editor keyboard service preserves field edits and document Backspace',
    (tester) async {
      final paragraph = paragraphNode(text: 'outside');
      final editor = EditorState(
        document: Document(root: pageNode(children: [paragraph])),
      );
      final editorFocus = FocusNode();
      final fieldFocus = FocusNode();
      final controller = TextEditingController(text: 'inside');
      final changes = <String>[];
      try {
        await _pump(
          tester,
          child: SizedBox(
            height: 400,
            child: AppFlowyEditor(
              editorState: editor,
              focusNode: editorFocus,
              shrinkWrap: true,
              header: TextEntryShortcuts(
                child: TextField(
                  controller: controller,
                  focusNode: fieldFocus,
                  onChanged: changes.add,
                ),
              ),
            ),
          ),
        );
        editor.updateSelectionWithReason(
          Selection.single(path: [0], startOffset: 7),
          reason: SelectionUpdateReason.uiEvent,
        );
        await tester.pump();
        await _focus(tester, fieldFocus);
        expect(editorFocus.hasFocus, isTrue);
        expect(editorFocus.hasPrimaryFocus, isFalse);
        final documentSelection = editor.selection;
        expect(documentSelection, isNotNull);
        controller.selection = const TextSelection.collapsed(offset: 6);
        await _press(tester, LogicalKeyboardKey.backspace);
        expect(controller.text, 'insid');
        expect(changes, ['insid']);
        expect(paragraph.delta!.toPlainText(), 'outside');
        expect(editor.selection, documentSelection);

        editorFocus.requestFocus();
        await tester.pump();
        await _press(tester, LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(paragraph.delta!.toPlainText(), 'outsid');
        expect(controller.text, 'insid');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        editor.dispose();
        editorFocus.dispose();
        fieldFocus.dispose();
        controller.dispose();
      }
    },
    variant: windows,
  );
}

TextEditingValue _value(String text, int offset) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );

Future<void> _focus(WidgetTester tester, FocusNode focus) async {
  focus.requestFocus();
  await tester.pump();
  expect(FocusManager.instance.primaryFocus, same(focus));
  expect(
      focus.context!.findAncestorStateOfType<EditableTextState>(), isNotNull);
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  // Word/line actions read RenderEditable's layout, not just controller.text.
  await tester.pump();
  if (control) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  try {
    await tester.sendKeyEvent(key, platform: 'windows');
    await tester.pump();
  } finally {
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await tester.pump();
}

Map<Type, Action<Intent>> _pageActions(List<Intent> calls) => {
      for (final action in <Action<Intent>>[
        _record<DeleteCharacterIntent>(calls),
        _record<DeleteToNextWordBoundaryIntent>(calls),
        _record<ExtendSelectionByCharacterIntent>(calls),
        _record<ExtendSelectionToNextWordBoundaryIntent>(calls),
        _record<DirectionalCaretMovementIntent>(calls),
        _record<SelectAllTextIntent>(calls),
        _record<CopySelectionTextIntent>(calls),
        _record<PasteTextIntent>(calls),
        _record<UndoTextIntent>(calls),
        _record<RedoTextIntent>(calls),
        _record<ReplaceTextIntent>(calls),
        _record<UpdateSelectionIntent>(calls),
      ])
        action.intentType: action,
    };

Action<T> _record<T extends Intent>(List<Intent> calls) => CallbackAction<T>(
      onInvoke: (intent) {
        calls.add(intent);
        return null;
      },
    );

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  Map<Type, Action<Intent>> actions = const {},
  ActionDispatcher? dispatcher,
  VoidCallback? onPageKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: DesktopAppearance().getThemeData(
        AppTheme.fallback,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 340,
            child: Focus(
              onKeyEvent: (_, event) {
                if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                    {
                      LogicalKeyboardKey.backspace,
                      LogicalKeyboardKey.delete,
                      LogicalKeyboardKey.arrowLeft,
                      LogicalKeyboardKey.arrowRight,
                      LogicalKeyboardKey.arrowUp,
                      LogicalKeyboardKey.arrowDown,
                      LogicalKeyboardKey.keyA,
                      LogicalKeyboardKey.keyC,
                      LogicalKeyboardKey.keyX,
                      LogicalKeyboardKey.keyV,
                      LogicalKeyboardKey.keyZ,
                    }.contains(event.logicalKey)) {
                  onPageKey?.call();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Actions(
                actions: actions,
                dispatcher: dispatcher,
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

class _DroppingDispatcher extends ActionDispatcher {
  _DroppingDispatcher(this.calls);

  final List<Intent> calls;

  @override
  Object? invokeAction(Action<Intent> action, Intent intent,
      [BuildContext? context]) {
    calls.add(intent);
    return null;
  }

  @override
  (bool, Object?) invokeActionIfEnabled(Action<Intent> action, Intent intent,
      [BuildContext? context]) {
    calls.add(intent);
    return (true, null);
  }
}

class _Clipboard {
  _Clipboard(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': text};
      if (call.method == 'Clipboard.hasStrings')
        return {'value': text.isNotEmpty};
      if (call.method == 'Clipboard.setData') {
        text = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  String text = '';
}
