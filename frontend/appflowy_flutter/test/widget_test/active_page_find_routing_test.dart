import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final hover in [false, true]) {
    for (final navigationFocus in [false, true]) {
      testWidgets(
        'active page Find without content focus: hover=$hover navigation=$navigationFocus',
        (tester) async {
          final navigation = FocusNode();
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          var calls = 0;
          try {
            await tester.pumpWidget(
              MaterialApp(
                home: Row(
                  children: [
                    TextButton(
                      focusNode: navigation,
                      onPressed: () {},
                      child: const Text('Navigation'),
                    ),
                    Expanded(
                      child: ContextualFindScope(
                        child: ContextualFindRegion(
                          onFind: () => calls++,
                          child: const SizedBox.expand(key: ValueKey('page')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
            if (navigationFocus) navigation.requestFocus();
            await tester.pump();
            final before = FocusManager.instance.primaryFocus;
            if (hover) {
              await mouse.addPointer(location: const Offset(2, 2));
              await mouse
                  .moveTo(tester.getCenter(find.byKey(const ValueKey('page'))));
              await tester.pump();
            }
            expect(FocusManager.instance.primaryFocus, same(before));
            await _find(tester);
            expect(calls, 1);
            expect(FocusManager.instance.primaryFocus, same(before));
          } finally {
            if (hover) await mouse.removePointer();
            await tester.pumpWidget(const SizedBox.shrink());
            navigation.dispose();
          }
        },
      );
    }
  }

  testWidgets('hover Find can claim navigation focus without a page scope',
      (tester) async {
    final navigation = FocusNode();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    var calls = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              TextButton(
                focusNode: navigation,
                onPressed: () {},
                child: const Text('Navigation'),
              ),
              Expanded(
                child: ContextualFindRegion(
                  onFind: () => calls++,
                  child: const SizedBox.expand(key: ValueKey('content')),
                ),
              ),
            ],
          ),
        ),
      );
      navigation.requestFocus();
      await tester.pump();
      await mouse.addPointer(
        location: tester.getCenter(find.byKey(const ValueKey('content'))),
      );
      await _find(tester);
      expect(calls, 1);
      expect(navigation.hasPrimaryFocus, isTrue);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      navigation.dispose();
    }
  });

  testWidgets('active tab fallback excludes retained hidden tabs and previews',
      (tester) async {
    final navigation = FocusNode();
    final index = ValueNotifier(0);
    final calls = <String>[];
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              TextButton(
                focusNode: navigation,
                onPressed: () {},
                child: const Text('Navigation'),
              ),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: index,
                  builder: (_, tab, __) => IndexedStack(
                    index: tab,
                    children: [
                      for (final id in ['one', 'two'])
                        ContextualFindScope(
                          child: ContextualFindRegion(
                            onFind: () => calls.add(id),
                            child: Center(
                              child: ContextualFindRegion(
                                onFind: () => calls.add('$id-preview'),
                                child: const SizedBox(width: 100, height: 100),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      navigation.requestFocus();
      await tester.pump();
      await _find(tester);
      index.value = 1;
      await tester.pump();
      await _find(tester);
      index.value = 0;
      await tester.pump();
      await _find(tester);
      expect(calls, ['one', 'two', 'one']);
      expect(navigation.hasPrimaryFocus, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      navigation.dispose();
      index.dispose();
    }
  });

  testWidgets('nested navigator page answers shell focus but not root dialogs',
      (tester) async {
    final navigation = FocusNode();
    final page = GlobalKey();
    var calls = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              TextButton(
                focusNode: navigation,
                onPressed: () {},
                child: const Text('Navigation'),
              ),
              Expanded(
                child: Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => ContextualFindScope(
                      child: ContextualFindRegion(
                        onFind: () => calls++,
                        child: SizedBox.expand(key: page),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigation.requestFocus();
      await tester.pump();
      await _find(tester);
      expect(calls, 1);
      final dialog = showDialog<void>(
        context: page.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Modal')),
      );
      await tester.pumpAndSettle();
      await _find(tester);
      expect(calls, 1);
      Navigator.of(page.currentContext!, rootNavigator: true).pop();
      await tester.pumpAndSettle();
      await dialog;
      navigation.requestFocus();
      await tester.pump();
      await _find(tester);
      expect(calls, 2);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      navigation.dispose();
    }
  });

  testWidgets('unrelated text input keeps focus and native Find',
      (tester) async {
    final input = FocusNode();
    var calls = 0;
    var nativeCalls = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                      () => nativeCalls++,
                },
                child: Material(child: TextField(focusNode: input)),
              ),
              Expanded(
                child: ContextualFindScope(
                  child: ContextualFindRegion(
                    onFind: () => calls++,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      input.requestFocus();
      await tester.pump();
      await _find(tester);
      expect(calls, 0);
      expect(nativeCalls, 1);
      expect(input.hasPrimaryFocus, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      input.dispose();
    }
  });

  testWidgets('multiple visible page scopes have no arbitrary fallback',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (var i = 0; i < 2; i++)
              Expanded(
                child: ContextualFindScope(
                  child: ContextualFindRegion(
                    onFind: () => calls++,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pump();
    await _find(tester);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _find(WidgetTester tester) async {
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.controlLeft,
    physicalKey: PhysicalKeyboardKey.controlLeft,
  );
  await tester.sendKeyEvent(
    LogicalKeyboardKey.keyF,
    physicalKey: PhysicalKeyboardKey.keyF,
  );
  await tester.sendKeyUpEvent(
    LogicalKeyboardKey.controlLeft,
    physicalKey: PhysicalKeyboardKey.controlLeft,
  );
  await tester.pump();
  await tester.pump();
}
