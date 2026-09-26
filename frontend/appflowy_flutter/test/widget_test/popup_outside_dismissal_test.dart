import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/desktop_selection_menu.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/command_results_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_field.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

// Exercise real editor services and Navigator barriers, not replacement popup
// widgets. Only the palette's native-backend bloc boundary is substituted.
enum _Appearance { light, dark, paper }

const _outside = Offset(20, 860);
const _nativeField = ValueKey('popup-background-native-field');
const _newDialog = ValueKey('popup-newer-dialog');
const _buttons = <String, int>{
  'primary': kPrimaryButton,
  'secondary': kSecondaryButton,
  'middle': kTertiaryButton,
};

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  for (final appearance in _Appearance.values) {
    for (final button in _buttons.entries) {
      _slashTest(
        '${appearance.name} slash: ${button.key} inside stays, outside closes',
        (tester, fixture) async {
          await fixture.mount(tester, appearance: appearance);
          final document = fixture.editor.document.toJson();
          final selection = fixture.editor.selection;
          final selectionType = fixture.editor.selectionType;
          final selectionReason = fixture.editor.selectionUpdateReason;
          await fixture.open(tester);
          expect(fixture.editor.selection, selection);
          expect(keepEditorFocusNotifier.value, fixture.initialHolds + 1);

          final surface = find.byType(AppMenuSurface);
          _expectAppearance(tester, surface, appearance);
          final padding =
              tester.getRect(surface).topCenter + const Offset(0, 3);
          final heading = tester.getCenter(find.byType(AppMenuSectionLabel));
          for (final point in [padding, heading]) {
            await _click(tester, point, button.value);
            expect(
              find.byType(AppFlowyDesktopSelectionMenuWidget),
              findsOneWidget,
            );
            expect(fixture.selectedItems, isEmpty);
            expect(fixture.editor.document.toJson(), document);
            expect(fixture.editor.selection, selection);
          }

          // Exercise both the document and the root-overlay area outside an
          // offset editor pane. Neither dismissal click is forwarded below.
          for (final point in [
            tester.getRect(find.byType(AppFlowyEditor)).bottomCenter -
                const Offset(0, 12),
            _outside,
          ]) {
            expect(tester.getRect(surface).contains(point), isFalse);
            await _click(tester, point, button.value);
            expect(
              find.byType(AppFlowyDesktopSelectionMenuWidget),
              findsNothing,
            );
            expect(fixture.editor.document.toJson(), document);
            expect(fixture.editor.selection, selection);
            expect(fixture.editor.selectionType, selectionType);
            expect(fixture.editor.selectionUpdateReason, selectionReason);
            expect(fixture.writes, 0);
            expect(fixture.backgroundDowns, 0);
            expect(fixture.selectedItems, isEmpty);
            expect(fixture.editorFocus.hasPrimaryFocus, isTrue);
            expect(keepEditorFocusNotifier.value, fixture.initialHolds);
            if (point != _outside) {
              await fixture.open(tester);
            }
          }
        },
      );

      _popupTest(
        '${appearance.name} context menu: ${button.key} outside closes all levels',
        (tester, fixture) async {
          await fixture.mount(tester, appearance: appearance);
          final editingValue = fixture.nativeController.value;
          var completed = false;
          Object? result = 'not dismissed';
          var selected = 0;
          unawaited(
            showAppMenu<Object?>(
              context: fixture.owner!,
              globalPosition: const Offset(300, 200),
              entries: [
                const AppMenuHeader('Options'),
                AppMenuItem(
                  label: 'Disabled',
                  enabled: false,
                  onSelected: () => selected++,
                ),
                const AppMenuItem(
                  label: 'Parent',
                  submenu: [
                    AppMenuItem(
                      label: 'Child',
                      submenu: [AppMenuItem(label: 'Grandchild')],
                    ),
                  ],
                ),
              ],
            ).then((value) {
              completed = true;
              result = value;
            }),
          );
          await _flush(tester);
          final root = find.byType(AppMenuSurface);
          final route = ModalRoute.of(tester.element(root))!;
          expect(route.barrierDismissible, isTrue);
          _expectAppearance(tester, root, appearance);
          for (final point in [
            tester.getRect(root).topCenter + const Offset(0, 3),
            tester.getCenter(find.byType(AppMenuSectionLabel)),
            tester.getCenter(find.text('Disabled')),
          ]) {
            await _click(tester, point, button.value);
            expect(route.isCurrent, isTrue);
            expect(completed, isFalse);
            expect(selected, 0);
          }

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await _flush(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await _flush(tester);
          expect(find.byType(AppMenuSurface), findsNWidgets(3));
          await _click(tester, _outside, button.value);
          expect(find.byType(AppMenuSurface), findsNothing);
          expect(completed, isTrue);
          expect(result, isNull);
          expect(fixture.observer.popped, [route]);
          expect(fixture.nativeController.value, editingValue);
          expect(fixture.backgroundDowns, 0);
          expect(selected, 0);
        },
      );

      _paletteTest(
        '${appearance.name} palette: real modal dismisses on ${button.key} outside',
        (tester, fixture) async {
          await fixture.mount(tester, appearance: appearance);
          final editingValue = fixture.nativeController.value;
          await fixture.open(tester);
          final modal = find.byType(CommandPaletteModal);
          final state = tester.state(modal);
          final route = ModalRoute.of(tester.element(modal))!;
          expect(route, isA<DialogRoute<dynamic>>());
          expect(route.barrierDismissible, isTrue);
          expect(route.barrierColor, Colors.transparent);
          final flowyDialog = find.descendant(
            of: modal,
            matching: find.byType(FlowyDialog),
          );
          _expectAppearance(tester, flowyDialog, appearance);
          expect(
            tester.widget<FlowyDialog>(flowyDialog).backgroundColor,
            WorkspacePalette.of(tester.element(flowyDialog)).elevatedSurface,
          );
          final card = find
              .descendant(
                of: flowyDialog,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Material &&
                      widget.type == MaterialType.transparency,
                ),
              )
              .first;
          final bounds = tester.getRect(card);
          expect(bounds.contains(_outside), isFalse);
          await _click(
            tester,
            bounds.topCenter + const Offset(0, 4),
            button.value,
          );
          expect(tester.state(modal), same(state));
          expect(route.isCurrent, isTrue);
          expect(fixture.notifier.value.isOpen, isTrue);
          await _click(tester, _outside, button.value);
          expect(modal, findsNothing);
          expect(state.mounted, isFalse);
          expect(fixture.notifier.value.isOpen, isFalse);
          expect(fixture.observer.popped, [route]);
          expect(fixture.nativeController.value, editingValue);
          expect(fixture.backgroundDowns, 0);
          expect(fixture.commands.events, [
            const CommandPaletteEvent.refreshCachedViews(),
          ]);
        },
      );
    }
  }

  _slashTest('slash: no-results padding stays open; outside keeps typed query',
      (tester, fixture) async {
    await fixture.mount(tester);
    await fixture.open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ, character: 'z');
    await _flush(tester);
    expect(fixture.editor.document.first!.delta!.toPlainText(), 'draft /z');
    expect(find.byType(AppMenuRow), findsNothing);
    final document = fixture.editor.document.toJson();
    final selection = fixture.editor.selection;
    final writes = fixture.writes;
    for (final button in [kPrimaryButton, kSecondaryButton]) {
      await _click(
        tester,
        tester.getCenter(find.byType(AppMenuSurface)),
        button,
      );
      expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsOneWidget);
    }
    await _click(tester, _outside, kSecondaryButton);
    expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
    expect(fixture.editor.document.toJson(), document);
    expect(fixture.editor.selection, selection);
    expect(fixture.writes, writes);
    expect(fixture.backgroundDowns, 0);
  });

  _slashTest('slash: above placement uses root-overlay coordinates',
      (tester, fixture) async {
    await fixture.mount(
      tester,
      pane: const Rect.fromLTWH(260, 530, 650, 180),
    );
    final caret = fixture.editor.selectionService.selectionRects.single;
    await fixture.open(tester);
    expect(fixture.menu.alignment, Alignment.bottomLeft);
    final bounds = tester.getRect(find.byType(AppMenuSurface));
    expect(bounds.left, closeTo(caret.right, 0.01));
    expect(bounds.bottom, closeTo(caret.top - 10, 0.01));
    await _click(tester, _outside, kSecondaryButton);
    expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
  });

  _slashTest('slash: arrows and Enter retain the real item and slash handler',
      (tester, fixture) async {
    await fixture.mount(tester);
    await fixture.open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      tester
          .widget<AppMenuRow>(find.widgetWithText(AppMenuRow, 'Beta'))
          .highlighted,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _flush(tester);
    expect(fixture.selectedItems, ['Beta']);
    expect(fixture.editor.document.first!.delta!.toPlainText(), 'draft ');
    expect(
      fixture.editor.selection,
      Selection.collapsed(Position(path: [0], offset: 6)),
    );
    expect(fixture.writes, 1);
    expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
    expect(fixture.editorFocus.hasPrimaryFocus, isTrue);
  });

  _slashTest('slash: native Escape closes without rewriting the selection',
      (tester, fixture) async {
    await fixture.mount(tester);
    final selection = fixture.editor.selection;
    final document = fixture.editor.document.toJson();
    var notifications = 0;
    void changed() => notifications++;
    fixture.editor.selectionNotifier.addListener(changed);
    try {
      await fixture.open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _flush(tester);
      fixture.menu.dismiss();
      fixture.menu.dismiss();
      await _flush(tester);
      expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
      expect(fixture.editor.document.toJson(), document);
      expect(fixture.editor.selection, selection);
      expect(notifications, 0);
      expect(fixture.writes, 0);
      expect(keepEditorFocusNotifier.value, fixture.initialHolds);
    } finally {
      fixture.editor.selectionNotifier.removeListener(changed);
    }
  });

  for (final inserted in [false, true]) {
    _slashTest(
        'slash: dismiss cancels ${inserted ? 'inserted' : 'deferred'} show',
        (tester, fixture) async {
      await fixture.mount(tester);
      final selection = fixture.editor.selection;
      var completed = false;
      unawaited(fixture.menu.show().then((_) => completed = true));
      if (inserted) {
        await tester.pump();
        // The entry was inserted post-frame but its widget has not mounted.
        expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
      }
      fixture.menu.dismiss();
      await _flush(tester);
      expect(completed, isTrue);
      expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
      expect(keepEditorFocusNotifier.value, fixture.initialHolds);
      expect(fixture.editor.selection, selection);
      expect(fixture.editorFocus.hasPrimaryFocus, isTrue);
      await fixture.open(tester);
      expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsOneWidget);
    });
  }

  for (final disposeEditor in [false, true]) {
    for (final mountedMenu in [false, true]) {
      _slashTest(
        'slash: ${disposeEditor ? 'disposed editor' : 'unmounted owner'} cancels '
        '${mountedMenu ? 'mounted' : 'deferred'} menu',
        (tester, fixture) async {
          await fixture.mount(tester);
          var completed = false;
          unawaited(fixture.menu.show().then((_) => completed = true));
          if (mountedMenu) {
            await _flush(tester);
            expect(
              find.byType(AppFlowyDesktopSelectionMenuWidget),
              findsOneWidget,
            );
          }
          final owner = fixture.owner!;
          if (disposeEditor) {
            fixture.editor.dispose();
            if (!mountedMenu) {
              // Disposal must cancel show even while its context is mounted.
              await tester.pump();
              expect(owner.mounted, isTrue);
              expect(completed, isTrue);
              expect(
                find.byType(AppFlowyDesktopSelectionMenuWidget),
                findsNothing,
              );
            }
          }
          fixture.editorVisible.value = false;
          await _flush(tester);
          expect(owner.mounted, isFalse);
          expect(completed, isTrue);
          expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
          expect(keepEditorFocusNotifier.value, fixture.initialHolds);
          fixture.menu.dismiss();
          // A later frame must not resurrect the deferred entry.
          await _flush(tester);
          expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
          expect(fixture.writes, 0);
        },
      );
    }
  }

  _slashTest('slash: old callbacks cannot close or arm a reopened session',
      (tester, fixture) async {
    await fixture.mount(tester);
    await fixture.open(tester);
    final oldWidget = tester.widget<AppFlowyDesktopSelectionMenuWidget>(
      find.byType(AppFlowyDesktopSelectionMenuWidget),
    );
    final oldState =
        tester.state(find.byType(AppFlowyDesktopSelectionMenuWidget));
    oldWidget.onExit();
    await fixture.open(tester);
    expect(oldState.mounted, isFalse);
    oldWidget.onExit();
    oldWidget.onSelectionUpdate();
    await _flush(tester);
    expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsOneWidget);
    expect(keepEditorFocusNotifier.value, fixture.initialHolds + 1);
    final caret = Selection.collapsed(Position(path: [1], offset: 4));
    fixture.editor.selectionService.updateSelection(caret);
    await _flush(tester);
    expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
    expect(fixture.editor.selection, caret);
    expect(keepEditorFocusNotifier.value, fixture.initialHolds);
    expect(fixture.writes, 0);
  });

  _slashTest('slash: overlapping shows mount one session and close once',
      (tester, fixture) async {
    await fixture.mount(tester);
    final selection = fixture.editor.selection;
    var completions = 0;
    unawaited(fixture.menu.show().then((_) => completions++));
    unawaited(fixture.menu.show().then((_) => completions++));
    await _flush(tester);
    expect(completions, 2);
    expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsOneWidget);
    expect(keepEditorFocusNotifier.value, fixture.initialHolds + 1);
    fixture.menu.dismiss();
    fixture.menu.dismiss();
    await _flush(tester);
    expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
    expect(keepEditorFocusNotifier.value, fixture.initialHolds);
    expect(fixture.editorFocus.hasPrimaryFocus, isTrue);
    expect(fixture.editor.selection, selection);
    expect(fixture.writes, 0);
  });

  _slashTest('slash: repeated close never takes focus back from a native field',
      (tester, fixture) async {
    await fixture.mount(tester);
    await fixture.open(tester);
    final text = fixture.nativeController.text;
    final selection = fixture.editor.selection;
    // The field's focus request is still pending when dismiss is called.
    fixture.nativeFocus.requestFocus();
    fixture.menu.dismiss();
    fixture.menu.dismiss();
    await _flush(tester);
    expect(fixture.nativeFocus.hasPrimaryFocus, isTrue);
    expect(fixture.nativeController.text, text);
    expect(
      fixture.nativeController.selection,
      TextSelection(baseOffset: 0, extentOffset: text.length),
      reason:
          'External focus selects all in a native single-line desktop field.',
    );
    expect(fixture.editor.selection, selection);
    expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
    expect(keepEditorFocusNotifier.value, fixture.initialHolds);

    // Establish the explicit caret AFTER native focus/select-all has settled.
    // Repeated closes must preserve this value, not a pre-focus selection.
    fixture.nativeController.selection =
        const TextSelection(baseOffset: 2, extentOffset: 5);
    final editingValue = fixture.nativeController.value;
    fixture.menu.dismiss();
    fixture.menu.dismiss();
    await _flush(tester);
    expect(fixture.nativeFocus.hasPrimaryFocus, isTrue);
    expect(fixture.nativeController.value, editingValue);
    expect(fixture.editor.selection, selection);
    fixture.menu.dismiss();
    await _flush(tester);
    expect(fixture.nativeFocus.hasPrimaryFocus, isTrue);
    expect(fixture.nativeController.value, editingValue);
    expect(fixture.editor.selection, selection);
    expect(fixture.writes, 0);
  });

  _slashTest('slash: a newer dialog keeps its route and native caret',
      (tester, fixture) async {
    await fixture.mount(tester);
    await fixture.open(tester);
    final oldClose = tester
        .widget<AppFlowyDesktopSelectionMenuWidget>(
          find.byType(AppFlowyDesktopSelectionMenuWidget),
        )
        .onExit;
    final document = fixture.editor.document.toJson();
    final dialog = _NewDialog();
    try {
      dialog.open(fixture.owner!);
      await _flush(tester);
      expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsNothing);
      oldClose();
      fixture.menu.dismiss();
      await _flush(tester);
      expect(dialog.closed, isFalse);
      expect(dialog.focus.hasPrimaryFocus, isTrue);
      expect(find.byKey(_newDialog), findsOneWidget);
      expect(fixture.editor.document.toJson(), document);
      expect(fixture.writes, 0);
      expect(keepEditorFocusNotifier.value, fixture.initialHolds);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _flush(tester);
      expect(dialog.closed, isTrue);
    } finally {
      await dialog.dispose(tester);
    }
  });

  _popupTest('context menu: stale custom close never pops a newer modal',
      (tester, fixture) async {
    await fixture.mount(tester);
    late void Function([Object?]) close;
    var completed = false;
    Object? result;
    unawaited(
      showAppMenu<String>(
        context: fixture.owner!,
        globalPosition: const Offset(300, 200),
        entries: [
          AppMenuCustom(
            builder: (context) {
              close = AppMenuScope.maybeOf(context)!.close;
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Custom menu content'),
              );
            },
          ),
        ],
      ).then((value) {
        result = value;
        completed = true;
      }),
    );
    await _flush(tester);
    final route = ModalRoute.of(tester.element(find.byType(AppMenuSurface)))!;
    final dialog = _NewDialog();
    try {
      dialog.open(fixture.owner!);
      await _flush(tester);
      expect(route.isActive, isTrue);
      expect(route.isCurrent, isFalse);
      close('stale');
      await _flush(tester);
      expect(dialog.closed, isFalse);
      expect(dialog.focus.hasPrimaryFocus, isTrue);
      expect(completed, isFalse);
      expect(fixture.observer.popped, isEmpty);
      await _click(tester, _outside, kSecondaryButton);
      expect(dialog.closed, isTrue);
      expect(route.isCurrent, isTrue);
      expect(completed, isFalse);
      close('own result');
      await _flush(tester);
      expect(result, 'own result');
      expect(completed, isTrue);
      expect(find.byType(AppMenuSurface), findsNothing);
      close('already closed');
      await _flush(tester);
      expect(fixture.observer.popped, hasLength(2));
      expect(fixture.observer.popped.last, same(route));
      expect(fixture.backgroundDowns, 0);
    } finally {
      await dialog.dispose(tester);
    }
  });

  _popupTest('context menu: native Escape removes only the deepest menu level',
      (tester, fixture) async {
    await fixture.mount(tester);
    var completed = false;
    unawaited(
      showAppMenu<void>(
        context: fixture.owner!,
        globalPosition: const Offset(300, 200),
        entries: const [
          AppMenuItem(
            label: 'Parent',
            submenu: [
              AppMenuItem(
                label: 'Child',
                submenu: [AppMenuItem(label: 'Leaf')],
              ),
            ],
          ),
        ],
      ).then((_) => completed = true),
    );
    await _flush(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _flush(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _flush(tester);
    expect(find.byType(AppMenuSurface), findsNWidgets(3));
    final dialog = _NewDialog();
    try {
      dialog.open(fixture.owner!);
      await _flush(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _flush(tester);
      expect(dialog.closed, isTrue);
      expect(find.byType(AppMenuSurface), findsNWidgets(3));
      expect(completed, isFalse);
      for (final remaining in [2, 1, 0]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _flush(tester);
        expect(find.byType(AppMenuSurface), findsNWidgets(remaining));
        expect(completed, remaining == 0);
      }
      expect(fixture.observer.popped, hasLength(2));
    } finally {
      await dialog.dispose(tester);
    }
  });

  _paletteTest('palette: native Escape closes the real FlowyOverlay route',
      (tester, fixture) async {
    await fixture.mount(tester);
    await fixture.open(tester);
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(SearchField),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.focusNode.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _flush(tester);
    expect(find.byType(CommandPaletteModal), findsNothing);
    expect(fixture.notifier.value.isOpen, isFalse);
    expect(fixture.observer.popped, hasLength(1));
  });

  _paletteTest('palette: stale command and toggle leave a newer modal alone',
      (tester, fixture) async {
    await fixture.mount(tester);
    await fixture.open(tester);
    late VoidCallback dismiss;
    tester.widget<CommandPalettePanel>(find.byType(CommandPalettePanel)).onRun(
          PaletteCommand(
            id: 'capture-palette-dismiss',
            title: 'Capture dismissal',
            icon: Icons.close,
            group: PaletteCommandGroup.navigate,
            run: (context) => dismiss = context.dismiss,
          ),
        );
    final route =
        ModalRoute.of(tester.element(find.byType(CommandPaletteModal)))!;
    final dialog = _NewDialog();
    try {
      dialog.open(fixture.owner!);
      await _flush(tester);
      expect(route.isActive, isTrue);
      expect(route.isCurrent, isFalse);
      dismiss();
      fixture.notifier.value = fixture.notifier.value.copyWith(isOpen: false);
      await _flush(tester);
      expect(dialog.closed, isFalse);
      expect(dialog.focus.hasPrimaryFocus, isTrue);
      expect(fixture.notifier.value.isOpen, isTrue);
      expect(fixture.observer.popped, isEmpty);
      await _click(tester, _outside, kPrimaryButton);
      expect(dialog.closed, isTrue);
      expect(route.isCurrent, isTrue);
      expect(find.byType(CommandPaletteModal), findsOneWidget);
      expect(fixture.notifier.value.isOpen, isTrue);
      await _click(tester, _outside, kSecondaryButton);
      expect(find.byType(CommandPaletteModal), findsNothing);
      expect(fixture.notifier.value.isOpen, isFalse);
      dismiss();
      await _flush(tester);
      expect(fixture.observer.popped, hasLength(2));
      expect(fixture.observer.popped.last, same(route));
      expect(fixture.backgroundDowns, 0);
    } finally {
      await dialog.dispose(tester);
    }
  });

  _paletteTest(
      'palette: route completion ignores a disposed controller notifier',
      (tester, fixture) async {
    await fixture.mount(tester);
    await fixture.open(tester);
    fixture.controllerVisible.value = false;
    await _flush(tester);
    fixture.disposeNotifier();
    expect(find.byType(CommandPaletteModal), findsOneWidget);
    await _click(tester, _outside, kPrimaryButton);
    expect(find.byType(CommandPaletteModal), findsNothing);
    expect(fixture.observer.popped, hasLength(1));
  });
}

void _slashTest(
  String name,
  Future<void> Function(WidgetTester, _SlashFixture) body,
) {
  testWidgets(
    name,
    (tester) async {
      _viewport(tester);
      final fixture = _SlashFixture();
      try {
        await body(tester, fixture);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

void _popupTest(
  String name,
  Future<void> Function(WidgetTester, _PopupFixture) body,
) {
  testWidgets(
    name,
    (tester) async {
      _viewport(tester);
      final fixture = _PopupFixture();
      try {
        await body(tester, fixture);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

void _paletteTest(
  String name,
  Future<void> Function(WidgetTester, _PaletteFixture) body,
) {
  testWidgets(
    name,
    (tester) async {
      _viewport(tester);
      getIt.pushNewScope();
      getIt.registerSingleton<MenuSharedState>(MenuSharedState());
      final fixture = _PaletteFixture();
      try {
        await body(tester, fixture);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
        await getIt.popScope();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1024, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<void> _pumpUntil(
  WidgetTester tester, {
  required String reason,
  Future<void>? completion,
  bool Function()? ready,
}) async {
  var completed = completion == null;
  Object? failure;
  StackTrace? failureStack;
  if (completion != null) {
    unawaited(
      completion.then<void>(
        (_) {
          completed = true;
        },
        onError: (Object error, StackTrace stack) {
          failure = error;
          failureStack = stack;
          completed = true;
        },
      ),
    );
  }
  final deadline = tester.binding.clock.fromNowBy(const Duration(seconds: 1));
  do {
    // Let root-zone cancellation/asset replies run without awaiting a captured
    // fake-zone future inside runAsync. Selection and show still need frames.
    await tester.runAsync(() => Future<void>(() {}));
    await tester.pump(const Duration(milliseconds: 16));
    if (failure != null) {
      Error.throwWithStackTrace(failure!, failureStack!);
    }
    if (completed && (ready?.call() ?? true)) return;
  } while (tester.binding.clock.now().isBefore(deadline));
  fail('Timed out waiting for $reason.');
}

Future<void> _click(WidgetTester tester, Offset point, int buttons) async {
  // A fresh mouse pointer per click avoids double-click arena reuse.
  await tester.tapAt(point, kind: PointerDeviceKind.mouse, buttons: buttons);
  await _flush(tester);
}

void _expectAppearance(WidgetTester tester, Finder surface, _Appearance mode) {
  final context = tester.element(surface);
  expect(PaperTheme.isEnabled(context), mode == _Appearance.paper);
  expect(
    Theme.of(context).brightness,
    mode == _Appearance.dark ? Brightness.dark : Brightness.light,
  );
}

Widget _app(
  Widget child,
  _Appearance appearance,
  GlobalKey<NavigatorState> navigator,
  NavigatorObserver observer,
) {
  final brightness =
      appearance == _Appearance.dark ? Brightness.dark : Brightness.light;
  final theme = DesktopAppearance()
      .getThemeData(
        appearance == _Appearance.paper
            ? AppTheme.builtins
                .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        brightness,
        'Ahem',
        'Ahem',
      )
      .copyWith(platform: TargetPlatform.windows);
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    fallbackLocale: const Locale('en', 'US'),
    path: 'assets/translations',
    saveLocale: false,
    assetLoader: const TestBundleAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (_, child) => AppFlowyTheme(
          data: PremiumTheme.appFlowyTheme(
            base: brightness == Brightness.dark
                ? AppFlowyDefaultTheme().dark()
                : AppFlowyDefaultTheme().light(),
            palette: theme.extension<PremiumThemeExtension>()!,
            brightness: brightness,
          ),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
}

class _RecordingNavigator extends NavigatorObserver {
  final popped = <Route<dynamic>>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
  }
}

class _PopupFixture {
  final navigator = GlobalKey<NavigatorState>();
  final observer = _RecordingNavigator();
  final nativeFocus = FocusNode(debugLabel: 'popup-background-native');
  final nativeController = TextEditingController(text: 'Background draft');
  BuildContext? owner;
  int backgroundDowns = 0;

  Widget background({Widget? editor}) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => backgroundDowns++,
        child: Builder(
          builder: (context) {
            owner = context;
            return Stack(
              children: [
                Positioned(
                  left: 16,
                  top: 16,
                  width: 220,
                  height: 48,
                  child: TextField(
                    key: _nativeField,
                    focusNode: nativeFocus,
                    controller: nativeController,
                  ),
                ),
                if (editor != null) editor,
              ],
            );
          },
        ),
      );

  Widget content() => background();

  Future<void> mount(
    WidgetTester tester, {
    _Appearance appearance = _Appearance.light,
  }) async {
    await tester.pumpWidget(_app(content(), appearance, navigator, observer));
    await _flush(tester);
    nativeController.selection =
        const TextSelection(baseOffset: 1, extentOffset: 5);
    nativeFocus.requestFocus();
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _flush(tester);
    nativeFocus.dispose();
    nativeController.dispose();
    expect(tester.takeException(), isNull);
  }
}

class _SlashFixture extends _PopupFixture {
  _SlashFixture()
      : editor = EditorState(
          document: Document(
            root: pageNode(
              children: [
                paragraphNode(text: 'draft /'),
                paragraphNode(text: 'Second paragraph for caret handoff'),
              ],
            ),
          ),
        )..disableSealTimer = true {
    _transactions = editor.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after && event.$2.operations.isNotEmpty) {
        writes++;
      }
    });
  }

  final EditorState editor;
  final editorFocus = FocusNode(debugLabel: 'popup-editor');
  final editorVisible = ValueNotifier(true);
  final initialHolds = keepEditorFocusNotifier.value;
  final selectedItems = <String>[];
  late final StreamSubscription<EditorTransactionValue> _transactions;
  AppFlowyDesktopSelectionMenu? _menu;
  AppFlowyDesktopSelectionMenu get menu => _menu!;
  int writes = 0;

  @override
  Future<void> mount(
    WidgetTester tester, {
    _Appearance appearance = _Appearance.light,
    Rect pane = const Rect.fromLTWH(260, 180, 650, 560),
  }) async {
    final body = background(
      editor: ValueListenableBuilder<bool>(
        valueListenable: editorVisible,
        builder: (_, visible, __) => visible
            ? Positioned.fromRect(
                rect: pane,
                child: Builder(
                  builder: (context) {
                    return AppFlowyEditor(
                      editorState: editor,
                      focusNode: editorFocus,
                      editorStyle: const EditorStyle.desktop(
                        padding: EdgeInsets.all(24),
                      ),
                    );
                  },
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(_app(body, appearance, navigator, observer));
    await _pumpUntil(
      tester,
      ready: () => editor.document.first!.renderBox?.hasSize == true,
      reason: 'slash editor layout',
    );
    // Use an editor-owned context, which unmounts independently of Navigator.
    owner = tester.element(find.byType(AppFlowyEditor));
    _menu = AppFlowyDesktopSelectionMenu(
      context: owner!,
      editorState: editor,
      selectionMenuItems: [
        for (final name in ['Alpha', 'Beta'])
          SelectionMenuItem(
            getName: () => name,
            icon: (_, __, ___) => const Icon(Icons.notes),
            keywords: [name.toLowerCase()],
            handler: (_, __, ___) => selectedItems.add(name),
          ),
      ],
    );
    final caret = Selection.collapsed(Position(path: [0], offset: 7));
    // This SDK API updates BOTH currentSelection and EditorState, and requests
    // keyboard focus for a UI selection. Model assignment alone is not enough.
    editor.selectionService.updateSelection(caret);
    await _pumpUntil(
      tester,
      ready: () =>
          editor.selection == caret &&
          editor.selectionService.currentSelection.value == caret &&
          editor.selectionService.selectionRects.isNotEmpty &&
          editorFocus.hasPrimaryFocus,
      reason: 'rendered slash caret and keyboard focus',
    );
    expect(editor.selectionService.selectionRects, isNotEmpty);
    expect(editorFocus.hasPrimaryFocus, isTrue);
  }

  Future<void> open(WidgetTester tester) async {
    await _pumpUntil(
      tester,
      completion: menu.show(),
      ready: () =>
          find.byType(AppFlowyDesktopSelectionMenuWidget).evaluate().length ==
              1 &&
          FocusManager.instance.primaryFocus?.debugLabel ==
              'appflowy_slash_menu',
      reason: 'slash show completion and mounted menu focus',
    );
    expect(find.byType(AppFlowyDesktopSelectionMenuWidget), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'appflowy_slash_menu',
    );
  }

  @override
  Future<void> dispose(WidgetTester tester) async {
    _menu?.dismiss();
    try {
      await super.dispose(tester);
    } finally {
      try {
        await _pumpUntil(
          tester,
          completion: _transactions.cancel(),
          reason: 'slash transaction listener cancellation',
        );
      } finally {
        if (!editor.isDisposed) editor.dispose();
        editor.editableNotifier.dispose();
        editorFocus.dispose();
        editorVisible.dispose();
      }
    }
    expect(keepEditorFocusNotifier.value, initialHolds);
  }
}

class _PaletteFixture extends _PopupFixture {
  // Constructed inside testWidgets, so bloc subscriptions use its fake clock.
  final commands = _PaletteBloc();
  final notifier = ValueNotifier(CommandPaletteNotifierValue());
  final controllerVisible = ValueNotifier(true);
  bool _notifierDisposed = false;

  @override
  Widget content() => ValueListenableBuilder<bool>(
        valueListenable: controllerVisible,
        builder: (_, visible, __) => visible
            ? BlocProvider<CommandPaletteBloc>.value(
                value: commands,
                child: CommandPalette(notifier: notifier, child: background()),
              )
            : background(),
      );

  Future<void> open(WidgetTester tester) async {
    notifier.value = notifier.value.copyWith(isOpen: true);
    await _flush(tester);
    expect(find.byType(CommandPaletteModal), findsOneWidget);
    expect(notifier.value.isOpen, isTrue);
  }

  void disposeNotifier() {
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      notifier.dispose();
    }
  }

  @override
  Future<void> dispose(WidgetTester tester) async {
    await super.dispose(tester);
    disposeNotifier();
    controllerVisible.dispose();
    await commands.close();
  }
}

class _PaletteBloc extends Cubit<CommandPaletteState>
    implements CommandPaletteBloc {
  _PaletteBloc() : super(CommandPaletteState.initial().copyWith(query: '> '));

  final events = <CommandPaletteEvent>[];

  @override
  void add(CommandPaletteEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NewDialog {
  final focus = FocusNode(debugLabel: 'popup-newer-dialog-field');
  final controller = TextEditingController(text: 'New dialog draft');
  ModalRoute<dynamic>? _route;
  bool closed = false;

  void open(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) {
          _route = ModalRoute.of(context);
          return AlertDialog(
            key: _newDialog,
            title: const Text('Newer dialog'),
            content: TextField(
              autofocus: true,
              focusNode: focus,
              controller: controller,
            ),
          );
        },
      ).then((_) => closed = true),
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    final route = _route;
    if (route != null && route.isCurrent) {
      route.navigator?.pop();
      await _flush(tester);
    }
    focus.dispose();
    controller.dispose();
  }
}
