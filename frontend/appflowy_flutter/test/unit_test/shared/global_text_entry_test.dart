import 'package:appflowy/shared/keyboard_state.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backspace in a text field travels through `Shortcuts`/`Actions`, not through
/// the input connection, so anything that stops those bindings matching breaks
/// editing everywhere while typing carries on working.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<TextEditingController> pumpField(
    WidgetTester tester,
    Widget Function(Widget child) wrap,
  ) async {
    final controller = TextEditingController(text: 'abc');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => wrap(
            Scaffold(
              body: TextField(controller: controller, autofocus: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.selection = const TextSelection.collapsed(offset: 3);
    return controller;
  }

  Future<void> pressBackspace(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
  }

  group('every text field keeps its editing keys', () {
    testWidgets('a bare text field deletes on backspace', (tester) async {
      final controller = await pumpField(tester, (child) => child);
      await pressBackspace(tester);
      expect(controller.text, 'ab');
    });

    testWidgets('the premium scroll scope keeps backspace', (tester) async {
      final controller = await pumpField(
        tester,
        (child) => PremiumScrollScope(enabled: true, child: child),
      );
      await pressBackspace(tester);
      expect(controller.text, 'ab');
    });

    testWidgets('the overlay manager keeps backspace', (tester) async {
      final controller = await pumpField(
        tester,
        (child) => Builder(
          builder: (context) => overlayManagerBuilder(context, child),
        ),
      );
      await pressBackspace(tester);
      expect(controller.text, 'ab');
    });
  });

  group('a modifier the system swallowed', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.keyboard, null);
    });

    void answerKeyboardState(Map<int, int> pressed) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.keyboard,
        (call) async => call.method == 'getKeyboardState' ? pressed : null,
      );
    }

    testWidgets('stops backspace working at all', (tester) async {
      final controller = await pumpField(tester, (child) => child);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft));

      await pressBackspace(tester);

      // No platform maps a Meta variant of Backspace, so nothing matches.
      expect(controller.text, 'abc');
    });

    testWidgets('is released once the system disowns it', (tester) async {
      final controller = await pumpField(tester, (child) => child);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      answerKeyboardState(const <int, int>{});

      await KeyboardStateReconciler.instance.reconcile(force: true);
      await tester.pump();

      expect(
        HardwareKeyboard.instance.physicalKeysPressed,
        isNot(contains(PhysicalKeyboardKey.metaLeft)),
      );

      await pressBackspace(tester);
      expect(controller.text, 'ab');
    });

    testWidgets('is left alone while it is really held', (tester) async {
      await pumpField(tester, (child) => child);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft));
      answerKeyboardState(<int, int>{
        PhysicalKeyboardKey.metaLeft.usbHidUsage:
            LogicalKeyboardKey.metaLeft.keyId,
      });

      await KeyboardStateReconciler.instance.reconcile(force: true);
      await tester.pump();

      expect(
        HardwareKeyboard.instance.physicalKeysPressed,
        contains(PhysicalKeyboardKey.metaLeft),
      );
    });
  });
}
