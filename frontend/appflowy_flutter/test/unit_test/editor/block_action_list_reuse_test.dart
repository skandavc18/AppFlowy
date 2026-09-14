import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart' as flowy;
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_add_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_list.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_option_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/drag_to_reorder/draggable_option_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/option/option_actions.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_setting.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  testWidgets(
    'hover-like rebuilds reuse mounted widgets and call the latest callback',
    (tester) async {
      final fixture = _ActionListFixture();
      var oldCalls = 0;
      var newCalls = 0;
      fixture.showSlashMenu = () => oldCalls++;
      await _mount(tester, fixture);

      final row = _row(tester);
      final addButton = tester.widget<BlockAddButton>(
        find.byType(BlockAddButton),
      );
      final optionButton = tester.widget<BlockOptionButton>(
        find.byType(BlockOptionButton),
      );
      final buttonWidgets = tester
          .widgetList<BlockActionButton>(
            find.byType(BlockActionButton),
          )
          .toList();
      final optionElement = tester.element(find.byType(BlockOptionButton));
      final optionState = tester.state(find.byType(BlockOptionButton));
      final blockContext = fixture.blockContext;

      addButton.showSlashMenu();
      expect(oldCalls, 1);
      fixture.showSlashMenu = () => newCalls++;
      for (var i = 0; i < 12; i++) {
        final previousList = tester.widget<BlockActionList>(
          find.byType(BlockActionList),
        );
        fixture.rebuild();
        await tester.pump();

        final currentList = tester.widget<BlockActionList>(
          find.byType(BlockActionList),
        );
        expect(currentList, isNot(same(previousList)));
        expect(
          currentList.showSlashMenu,
          isNot(same(previousList.showSlashMenu)),
        );
        expect(fixture.blockContext, same(blockContext));
        expect(_row(tester), same(row));
        expect(tester.widget(find.byType(BlockAddButton)), same(addButton));
        expect(
          tester.widget(find.byType(BlockOptionButton)),
          same(optionButton),
        );
        expect(
          tester.element(find.byType(BlockOptionButton)),
          same(optionElement),
        );
        expect(tester.state(find.byType(BlockOptionButton)), same(optionState));
        final currentButtons = tester
            .widgetList<BlockActionButton>(
              find.byType(BlockActionButton),
            )
            .toList();
        expect(currentButtons, hasLength(2));
        for (var j = 0; j < buttonWidgets.length; j++) {
          expect(currentButtons[j], same(buttonWidgets[j]));
        }
      }
      expect(fixture.parentBuilds, 13);

      // Exercise the already-mounted add menu, including its post-frame
      // slash-menu callback, rather than just inspecting callback fields.
      final initialNodeCount =
          fixture.editorState.document.root.children.length;
      await tester.tap(find.byType(BlockAddButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(OptionAction.addBelow.description));
      await tester.pumpAndSettle();
      expect(
        fixture.editorState.document.root.children,
        hasLength(initialNodeCount + 1),
      );
      expect(oldCalls, 1);
      expect(newCalls, 1);

      // Even a caller retaining the original button reaches the latest
      // callback after another replacement.
      var finalCalls = 0;
      fixture.showSlashMenu = () => finalCalls++;
      fixture.rebuild();
      await tester.pump();
      addButton.showSlashMenu();
      expect(finalCalls, 1);
      expect(newCalls, 1);
      expect(_row(tester), same(row));
      expect(tester.takeException(), isNull);
    },
  );

  for (final input in _ChangedInput.values) {
    testWidgets('refreshes cached children when ${input.name} changes',
        (tester) async {
      final fixture = _ActionListFixture();
      await _mount(tester, fixture);
      final oldRow = _row(tester);
      final oldAdd = tester.widget<BlockAddButton>(find.byType(BlockAddButton));
      final oldOption = tester.widget<BlockOptionButton>(
        find.byType(BlockOptionButton),
      );

      switch (input) {
        case _ChangedInput.blockContext:
          // The renderer supplies a fresh context for the same mutable node.
          final node = fixture.blockContext.node;
          node.updateAttributes({...node.attributes, 'updated': true});
          fixture.blockContext = BlockComponentContext(
            fixture.blockContext.buildContext,
            node,
            header: const Text('Updated context'),
          );
          break;
        case _ChangedInput.blockState:
          fixture.blockState = _BlockActionState();
          break;
        case _ChangedInput.editorState:
          fixture.editorState = fixture.createEditor();
          break;
        case _ChangedInput.builders:
          // A new map must invalidate even if its entries compare equal.
          fixture.builders = Map.of(fixture.builders);
          break;
        case _ChangedInput.actions:
          fixture.actions = [OptionAction.duplicate];
          break;
        case _ChangedInput.equalActions:
          fixture.actions = List.of(fixture.actions);
          break;
      }
      fixture.rebuild();
      await tester.pump();

      final newRow = _row(tester);
      final newAdd = tester.widget<BlockAddButton>(find.byType(BlockAddButton));
      final newOption = tester.widget<BlockOptionButton>(
        find.byType(BlockOptionButton),
      );
      expect(newRow, isNot(same(oldRow)));
      expect(newAdd, isNot(same(oldAdd)));
      expect(newOption, isNot(same(oldOption)));
      expect(newAdd.blockComponentContext, same(fixture.blockContext));
      expect(newOption.blockComponentContext, same(fixture.blockContext));
      expect(newAdd.blockComponentState, same(fixture.blockState));
      expect(newOption.blockComponentState, same(fixture.blockState));
      expect(newAdd.editorState, same(fixture.editorState));
      expect(newOption.editorState, same(fixture.editorState));
      expect(newOption.actions, same(fixture.actions));
      expect(newOption.blockComponentBuilder, same(fixture.builders));
      expect(newAdd.showSlashMenu, same(oldAdd.showSlashMenu));
      final dragButton = tester.widget<DraggableOptionButton>(
        find.byType(DraggableOptionButton),
      );
      expect(dragButton.blockComponentContext, same(fixture.blockContext));
      expect(dragButton.editorState, same(fixture.editorState));
      expect(dragButton.blockComponentBuilder, same(fixture.builders));

      fixture.rebuild();
      await tester.pump();
      expect(_row(tester), same(newRow));
      expect(tester.widget(find.byType(BlockAddButton)), same(newAdd));
      expect(tester.widget(find.byType(BlockOptionButton)), same(newOption));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cached buttons still reflect light, dark and paper themes',
      (tester) async {
    final fixture = _ActionListFixture();
    await _mount(tester, fixture);
    final row = _row(tester);
    final addButton = tester.widget(find.byType(BlockAddButton));
    final optionButton = tester.widget(find.byType(BlockOptionButton));
    final parentBuilds = fixture.parentBuilds;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    try {
      await mouse.moveTo(tester.getCenter(find.byType(BlockAddButton)));
      await tester.pump(const Duration(milliseconds: 150));

      for (final (brightness, paper) in [
        (Brightness.light, false),
        (Brightness.dark, false),
        (Brightness.light, true),
        (Brightness.light, false),
      ]) {
        final theme = _themeData(brightness: brightness, paper: paper);
        fixture.theme.value = theme;
        await tester.pumpAndSettle();

        expect(fixture.parentBuilds, parentBuilds);
        expect(_row(tester), same(row));
        expect(tester.widget(find.byType(BlockAddButton)), same(addButton));
        expect(
          tester.widget(find.byType(BlockOptionButton)),
          same(optionButton),
        );
        final icons = tester
            .widgetList<flowy.FlowySvg>(
              find.descendant(
                of: find.byType(BlockActionList),
                matching: find.byType(flowy.FlowySvg),
              ),
            )
            .toList();
        expect(icons, hasLength(2));
        for (final icon in icons) {
          expect(icon.color, theme.iconTheme.color);
        }
        final hoverSurface = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byType(BlockAddButton),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        expect(
          (hoverSurface.decoration! as BoxDecoration).color,
          theme.colorScheme.onSurface.withValues(alpha: 0.16),
        );
        expect(
          _addPopover(tester).backgroundColor,
          theme.extension<PremiumThemeExtension>()!.floatingSurface,
        );
        expect(
          PaperTheme.isEnabled(tester.element(find.byType(BlockAddButton))),
          paper,
        );
        if (paper) {
          expect(
            _addPopover(tester).backgroundColor,
            PaperTheme.popupBackground,
          );
        }
        expect(tester.takeException(), isNull);
      }
    } finally {
      await mouse.removePointer();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('layout direction updates without a parent rebuild',
      (tester) async {
    final fixture = _ActionListFixture();
    await _mount(tester, fixture);
    final row = _row(tester);
    final addButton = tester.widget(find.byType(BlockAddButton));
    final optionButton = tester.widget(find.byType(BlockOptionButton));
    final initialPopover = _addPopover(tester);
    final parentBuilds = fixture.parentBuilds;
    expect(initialPopover.direction, PopoverDirection.leftWithCenterAligned);

    // An unrelated cubit emission must not rebuild the add-button subtree.
    fixture.emitAppearance(fixture.appearance.copyWith(menuOffset: 42));
    await tester.pumpAndSettle();
    expect(_addPopover(tester), same(initialPopover));

    for (final direction in [
      LayoutDirection.rtlLayout,
      LayoutDirection.ltrLayout,
    ]) {
      final previousPopover = _addPopover(tester);
      fixture.emitAppearance(
        fixture.appearance.copyWith(layoutDirection: direction),
      );
      // The asynchronous stream schedules the inherited-provider notification
      // after a frame; wait for its dependent rebuild as well.
      await tester.pumpAndSettle();
      expect(fixture.parentBuilds, parentBuilds);
      expect(_row(tester), same(row));
      expect(tester.widget(find.byType(BlockAddButton)), same(addButton));
      expect(tester.widget(find.byType(BlockOptionButton)), same(optionButton));
      expect(_addPopover(tester), isNot(same(previousPopover)));
      expect(
        _addPopover(tester).direction,
        direction == LayoutDirection.rtlLayout
            ? PopoverDirection.rightWithCenterAligned
            : PopoverDirection.leftWithCenterAligned,
      );
    }
    expect(tester.takeException(), isNull);
  });
}

enum _ChangedInput {
  blockContext,
  blockState,
  editorState,
  builders,
  actions,
  equalActions,
}

class _MockAppearanceSettingsCubit extends Mock
    implements AppearanceSettingsCubit {}

class _MockEditorService extends Mock implements EditorService {}

class _MockSelectionService extends Mock implements AppFlowySelectionService {}

class _BlockActionState implements BlockComponentActionState {
  @override
  bool alwaysShowActions = false;
}

class _TestEditorState extends EditorState {
  _TestEditorState() : super.blank() {
    editorStyle = const EditorStyle.desktop();
    disableSealTimer = true;
    when(() => service.selectionService).thenReturn(_MockSelectionService());
  }

  // Isolate this fixture from the real editor service/plugin initialization.
  @override
  // ignore: overridden_fields
  final EditorService service = _MockEditorService();
}

class _ActionListFixture {
  _ActionListFixture() {
    editorState = createEditor();
    when(() => appearanceCubit.state).thenAnswer((_) => appearance);
    when(() => appearanceCubit.stream)
        .thenAnswer((_) => appearanceChanges.stream);
  }

  final appearanceCubit = _MockAppearanceSettingsCubit();
  final appearanceChanges =
      StreamController<AppearanceSettingsState>.broadcast();
  AppearanceSettingsState appearance = _initialAppearance();
  final parentRevision = ValueNotifier(0);
  final theme = ValueNotifier(_themeData());
  final editors = <EditorState>[];
  late EditorState editorState;
  late BlockComponentContext blockContext;
  BlockComponentActionState blockState = _BlockActionState();
  List<OptionAction> actions = [OptionAction.copy, OptionAction.delete];
  Map<String, BlockComponentBuilder> builders = {
    ParagraphBlockKeys.type: ParagraphBlockComponentBuilder(),
  };
  VoidCallback showSlashMenu = () {};
  int parentBuilds = 0;

  EditorState createEditor() {
    final editor = _TestEditorState();
    editors.add(editor);
    return editor;
  }

  void rebuild() => parentRevision.value++;

  void emitAppearance(AppearanceSettingsState value) {
    appearance = value;
    appearanceChanges.add(value);
  }

  Widget build() => BlocProvider<AppearanceSettingsCubit>.value(
        value: appearanceCubit,
        child: ValueListenableBuilder<ThemeData>(
          valueListenable: theme,
          // Keep this parent widget identical across theme changes: only the
          // descendants' own inherited subscriptions may update their visuals.
          child: ValueListenableBuilder<int>(
            valueListenable: parentRevision,
            builder: (context, revision, child) {
              if (parentBuilds++ == 0) {
                blockContext = BlockComponentContext(
                  context,
                  editorState.document.root.children.first,
                );
              }
              final callback = showSlashMenu;
              return SizedBox(
                width: BlockActionList.gutterWidth,
                height: BlockActionList.height,
                child: BlockActionList(
                  blockComponentContext: blockContext,
                  blockComponentState: blockState,
                  editorState: editorState,
                  actions: actions,
                  blockComponentBuilder: builders,
                  // Mimic the editor creating a new closure on every hover.
                  showSlashMenu: () => callback(),
                ),
              );
            },
          ),
          builder: (context, theme, child) => MaterialApp(
            theme: theme,
            themeAnimationDuration: Duration.zero,
            home: Scaffold(body: Center(child: child)),
          ),
        ),
      );

  Future<void> dispose() async {
    parentRevision.dispose();
    theme.dispose();
    for (final editor in editors) {
      editor.dispose();
    }
    await appearanceChanges.close();
  }
}

Future<void> _mount(WidgetTester tester, _ActionListFixture fixture) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.dispose();
  });
  await tester.pumpWidget(fixture.build());
  await tester.pumpAndSettle();
}

Row _row(WidgetTester tester) => tester.widget<Row>(
      find
          .descendant(
            of: find.byType(BlockActionList),
            matching: find.byType(Row),
          )
          .first,
    );

PopoverActionList<PopoverAction> _addPopover(WidgetTester tester) =>
    tester.widget<PopoverActionList<PopoverAction>>(
      find.descendant(
        of: find.byType(BlockAddButton),
        matching: find.byType(PopoverActionList<PopoverAction>),
      ),
    );

AppearanceSettingsState _initialAppearance() {
  final dates = DateTimeSettingsPB();
  return AppearanceSettingsState(
    appTheme: AppTheme.fallback,
    themeMode: ThemeMode.light,
    font: defaultFontFamily,
    layoutDirection: LayoutDirection.ltrLayout,
    textDirection: AppFlowyTextDirection.ltr,
    enableRtlToolbarItems: false,
    locale: const Locale('en', 'US'),
    isMenuCollapsed: false,
    menuOffset: 0,
    dateFormat: dates.dateFormat,
    timeFormat: dates.timeFormat,
    timezoneId: dates.timezoneId,
    documentCursorColor: null,
    documentSelectionColor: null,
    textScaleFactor: 1.0,
    enableKineticScrolling: true,
  );
}

ThemeData _themeData({
  Brightness brightness = Brightness.light,
  bool paper = false,
}) =>
    DesktopAppearance().getThemeData(
      paper
          ? AppTheme.builtins.firstWhere(
              (theme) => theme.themeName == BuiltInTheme.paper,
            )
          : AppTheme.fallback,
      brightness,
      defaultFontFamily,
      builtInCodeFontFamily,
    );
