import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_overlay_test_app.dart';

void main() {
  setUpAll(initializeWorkspaceOverlayTests);

  test('app and legacy menus use the same semantic geometry', () {
    expect(AppMenuMetrics.cornerRadius, WorkspaceTokens.menuRadius);
    expect(AFMenu.cornerRadius, WorkspaceTokens.menuRadius);
    expect(AFMenu.cardPadding, AppMenuMetrics.cardPadding);
    expect(AFMenuItem.rowRadius, WorkspaceTokens.controlRadius);
    expect(AFMenuItem.iconGap, AppMenuMetrics.iconGap);
    expect(
      AFMenuItem.rowPadding.horizontal,
      AppMenuMetrics.rowHorizontalPadding * 2,
    );
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets('$appearance rename preserves selection, validation and submit',
        (tester) async {
      String? result;
      String? confirmed;
      var calls = 0;
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: _launcher((context) async {
            result = await showAFTextFieldDialog(
              context: context,
              title: 'Rename item',
              initialValue: 'Draft',
              maxLength: 32,
              onConfirm: (value) {
                calls++;
                confirmed = value;
              },
            );
          }),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(field.maxLength, 32);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(
        tester
            .widget<AFFilledTextButton>(find.byType(AFFilledTextButton))
            .disabled,
        isTrue,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(calls, 0);
      expect(find.byType(AFTextFieldDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), ' Revised title ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, 'Revised title');
      expect(confirmed, result);
      expect(calls, 1);
      expect(find.byType(AFTextFieldDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final accessible in [false, true]) {
      testWidgets('$appearance dialog honors reduced motion ($accessible)',
          (tester) async {
        late ModalRoute<dynamic> route;
        late Color expectedBarrier;
        var closed = false;
        await tester.pumpWidget(
          workspaceOverlayTestApp(
            appearance: appearance,
            disableAnimations: !accessible,
            accessibleNavigation: accessible,
            child: _launcher((context) async {
              final theme = Theme.of(context);
              expectedBarrier = theme.colorScheme.surface.withValues(
                alpha: theme.brightness == Brightness.dark ? 0.38 : 0.68,
              );
              await showFlowyDialog<void>(
                context: context,
                builder: (context) {
                  route = ModalRoute.of(context)!;
                  return const FlowyDialog(
                    width: 360,
                    expandHeight: false,
                    child:
                        SizedBox(height: 100, child: Text('A floating dialog')),
                  );
                },
              );
              closed = true;
            }),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open dialog'));
        await tester.pump();
        await tester.pump();
        expect(route.transitionDuration, Duration.zero);
        expect(route.reverseTransitionDuration, Duration.zero);
        expect(route.barrierColor, expectedBarrier);
        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        expect(
          (dialog.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(WorkspaceTokens.dialogRadius),
        );
        expect(dialog.insetAnimationDuration, Duration.zero);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(closed, isTrue);
        expect(find.byType(FlowyDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        '$appearance long confirmation keeps descriptions and actions reachable',
        (tester) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var confirmed = 0;
      final description =
          List.filled(24, 'Review the change before continuing.').join(' ');
      const confirm = 'Restore the selected version';
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          textScale: 2,
          child: _launcher(
            (context) => showCancelAndConfirmDialog(
              context: context,
              title: 'Restore content',
              description: description,
              confirmLabel: confirm,
              onConfirm: (_) => confirmed++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(description)).maxLines, isNull);
      expect(
        find.widgetWithText(TextButton, confirm).hitTestable(),
        findsOneWidget,
      );
      expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
      final scroll = find.descendant(
        of: find.byType(FlowyDialog),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scroll, findsOneWidget);
      await tester.drag(scroll, const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextButton, confirm).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, confirm));
      await tester.pumpAndSettle();
      expect(confirmed, 1);
      expect(find.byType(FlowyDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('non-dismissible rename still offers Close without confirming',
      (tester) async {
    var confirmed = 0;
    var completed = false;
    String? result = 'not dismissed';
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        child: _launcher((context) async {
          result = await showAFTextFieldDialog(
            context: context,
            title: 'Rename item',
            initialValue: 'Draft',
            barrierDismissible: false,
            onConfirm: (_) => confirmed++,
          );
          completed = true;
        }),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(AFTextFieldDialog), findsOneWidget);
    expect(completed, isFalse);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
    expect(confirmed, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog focus loops locally and Escape restores the trigger',
      (tester) async {
    final trigger = FocusNode();
    final first = FocusNode();
    final last = FocusNode();
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        child: Builder(
          builder: (context) => TextButton(
            focusNode: trigger,
            onPressed: () => showFlowyDialog<void>(
              context: context,
              builder: (_) => FlowyDialog(
                width: 360,
                expandHeight: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      focusNode: first,
                      autofocus: true,
                      onPressed: () {},
                      child: const Text('First'),
                    ),
                    TextButton(
                      focusNode: last,
                      onPressed: () {},
                      child: const Text('Last'),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('Open dialog'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    trigger.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(last.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(first.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(trigger.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    trigger.dispose();
    first.dispose();
    last.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Cancel and Escape do not confirm, and only Cancel calls onCancel',
      (tester) async {
    var confirmed = 0;
    var cancelled = 0;
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        child: _launcher(
          (context) => showCancelAndConfirmDialog(
            context: context,
            title: 'Discard changes?',
            description: 'The draft is still available until confirmed.',
            confirmLabel: 'Discard',
            onConfirm: (_) => confirmed++,
            onCancel: () => cancelled++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(cancelled, 1);
    expect(confirmed, 0);
    expect(find.byType(FlowyDialog), findsNothing);
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(cancelled, 1);
    expect(confirmed, 0);
    expect(find.byType(FlowyDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom confirmation keeps its dismissal and keyboard opt-outs',
      (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        child: _launcher(
          (context) => showCustomConfirmDialog(
            context: context,
            title: 'Apply changes',
            description: 'Only the explicit action should confirm.',
            confirmLabel: 'Apply',
            showCloseButton: false,
            enableKeyboardListener: false,
            barrierDismissible: false,
            onConfirm: () => confirmed++,
            builder: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(confirmed, 0);
    expect(find.byType(FlowyDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(confirmed, 1);
    expect(find.byType(FlowyDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-closing confirmation activates once per native Enter',
      (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        child: _launcher(
          (context) => showCustomConfirmDialog(
            context: context,
            title: 'Apply changes',
            description: 'Keep this dialog open after applying.',
            confirmLabel: 'Apply',
            closeOnConfirm: false,
            showCloseButton: false,
            onConfirm: () => confirmed++,
            builder: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    for (var expected = 1; expected <= 2; expected++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(confirmed, expected);
      expect(find.byType(FlowyDialog), findsOneWidget);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(FlowyDialog), findsNothing);
  });

  testWidgets('legacy controls retain focus and use reduced-motion geometry',
      (tester) async {
    var revision = 0;
    var invoked = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        appearance: 'paper',
        accessibleNavigation: true,
        child: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$revision'),
                  SizedBox(
                    width: 180,
                    child: FlowyTextButton('Apply', onPressed: () => invoked++),
                  ),
                  const FlowyHover(child: SizedBox.square(dimension: 24)),
                  AFGhostButton.normal(
                    onTap: () {},
                    builder: (_, __, ___) => const Text('Other action'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    rebuild(() => revision++);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(focus));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(invoked, 1);
    final button = tester.widget<TextButton>(
      find.descendant(
        of: find.byType(FlowyTextButton),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.style!.animationDuration, Duration.zero);
    expect(
      (button.style!.shape!.resolve({})! as RoundedRectangleBorder)
          .borderRadius,
      BorderRadius.circular(WorkspaceTokens.controlRadius),
    );
    for (final container in tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))) {
      expect(container.duration, Duration.zero);
    }
    expect(tester.takeException(), isNull);
  });
}

Widget _launcher(Future<void> Function(BuildContext) open) => Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => open(context),
          child: const Text('Open dialog'),
        ),
      ),
    );
