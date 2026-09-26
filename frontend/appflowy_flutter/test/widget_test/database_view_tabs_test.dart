import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/tab_bar_bloc.dart' as db;
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_add_button.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_header.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart' as editor;
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/widget/buttons/primary_button.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _headerKey = ValueKey('database-view-header');
const _addKey = ValueKey('database-add-view');
const _wrapKey = ValueKey('database-view-tabs-wrap');
const _hostKey = ValueKey('database-test-host');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool sharedSectionWasOn;
  setUpAll(prepareVividIconTestAssets);
  setUp(() async {
    // isEditable deliberately ignores share access levels when this feature
    // is off. Exercise the real sharing policy, not a fake isEditable getter.
    sharedSectionWasOn = FeatureFlag.sharedSection.isOn;
    getIt.pushNewScope();
    getIt.registerSingleton<KeyValueStorage>(_MemoryKeyValue());
    await FeatureFlag.sharedSection.turnOn();
  });
  tearDown(() async {
    await FeatureFlag.sharedSection.update(sharedSectionWasOn);
    await getIt.popScope();
  });

  for (final appearance in vividIconTestAppearances) {
    for (final width in [320.0, 640.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            '$appearance $width/${scale}x: all ten views and + are visible',
            (tester) async {
          final fixture = await _pumpHeader(
            tester,
            appearance: appearance,
            width: width,
            scale: scale,
          );
          try {
            final saved =
                fixture.views.map((view) => view.writeToBuffer()).toList();
            final controllers =
                Map.of(fixture.bloc.state.tabBarControllerByViewId);
            expect(find.byType(DatabaseTabBarItem), findsNWidgets(10));
            expect(
              find.byType(DatabaseTabBarItem).hitTestable(),
              findsNWidgets(10),
            );
            expect(find.byKey(_addKey).hitTestable(), findsOneWidget);
            expect(
              find.descendant(
                of: find.byType(DatabaseTabBar),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable &&
                      axisDirectionToAxis(widget.axisDirection) ==
                          Axis.horizontal,
                ),
              ),
              findsNothing,
            );
            // No scrolling/ensureVisible from this test is allowed to make a
            // hidden view pass. Ten views fit their naturally growing header.
            _expectAllViewsInside(tester, fixture);
            for (var i = 0; i < fixture.views.length; i++) {
              final view = fixture.views[i];
              final tab = _tab(view);
              final button = _button(view);
              final tooltip = tester.widget<Tooltip>(
                find.descendant(of: tab, matching: find.byType(Tooltip)).first,
              );
              expect(tooltip.message, view.name);
              expect(
                find.descendant(of: tab, matching: find.byType(WorkspaceGlyph)),
                findsOneWidget,
              );
              expect(
                find.descendant(of: tab, matching: find.byType(Icon)),
                findsNothing,
              );
              await tester.tap(button, kind: PointerDeviceKind.mouse);
              await tester.pumpAndSettle();
              expect(fixture.bloc.state.selectedIndex, i);
              expect(tester.widget<DatabaseTabBarItem>(tab).isSelected, isTrue);
              expect(tester.takeException(), isNull);
            }
            _expectAllViewsInside(tester, fixture);
            final last = tester.getRect(_tab(fixture.views.last));
            final add = tester.getRect(find.byKey(_addKey));
            final wrap = tester.widget<Wrap>(find.byKey(_wrapKey));
            if (add.top < last.bottom) {
              // At 1x, desktop density makes the native TextButton 32px:
              // 34px minimum - 2px density, plus 4px outer tab padding = 36px.
              // Add is 38px. Centering it in the same run puts its TOP 1px
              // above the tab, not outside the Wrap or header.
              expect(add.center.dy, closeTo(last.center.dy, 0.001));
              expect(
                last.top - add.top,
                closeTo((add.height - last.height) / 2, 0.001),
              );
              expect(add.left - last.right, closeTo(wrap.spacing, 0.001));
            } else {
              expect(
                add.top,
                greaterThanOrEqualTo(last.bottom + wrap.runSpacing),
              );
              expect(
                add.left,
                closeTo(tester.getRect(find.byKey(_wrapKey)).left, 0.001),
              );
            }
            expect(fixture.bloc.state.tabBarControllerByViewId, controllers);
            expect(
              fixture.views.map((view) => view.writeToBuffer()).toList(),
              saved,
            );
            expect(fixture.bloc.mutations, isEmpty);

            // A mounted + is insufficient: click its real native button and
            // a native menu row at every width, text scale and appearance.
            await tester.tap(_addButton(), kind: PointerDeviceKind.mouse);
            await tester.pumpAndSettle();
            expect(find.byType(TabBarAddButtonAction), findsOneWidget);
            final grid = _addChoice(DatabaseTabKind.grid);
            expect(grid.hitTestable(), findsOneWidget);
            await tester.tap(grid, kind: PointerDeviceKind.mouse);
            await tester.pumpAndSettle();
            expect(
              fixture.bloc.mutations,
              [
                db.DatabaseTabBarEvent.createView(
                  DatabaseTabKind.grid.layout,
                  null,
                ),
              ],
            );
            expect(find.byType(TabBarAddButtonAction), findsNothing);
            _expectAllViewsInside(tester, fixture);
            expect(tester.takeException(), isNull);
          } finally {
            await _dispose(tester, fixture);
          }
        });
      }
    }
  }

  testWidgets(
      'native Tab/Enter/Space traverses wrapped views, then creates a view',
      (tester) async {
    final fixture = await _pumpHeader(tester, width: 320, scale: 2);
    final semantics = tester.ensureSemantics();
    try {
      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(
          i.isEven ? LogicalKeyboardKey.enter : LogicalKeyboardKey.space,
        );
        await tester.pumpAndSettle();
        expect(fixture.bloc.state.selectedIndex, i);
        final node =
            tester.getSemantics(_button(fixture.views[i])).getSemanticsData();
        expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(node.hasFlag(ui.SemanticsFlag.isSelected), isTrue);
        expect(node.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(node.label, contains(fixture.views[i].name));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(TabBarAddButtonAction), findsOneWidget);
      expect(fixture.bloc.mutations, isEmpty);
      final grid = _addChoice(DatabaseTabKind.grid);
      await tester.tap(grid);
      await tester.pumpAndSettle();
      expect(fixture.bloc.mutations, hasLength(1));
      expect(find.byType(TabBarAddButtonAction), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
      await _dispose(tester, fixture);
    }
  });

  testWidgets(
      'width, scale and reordered views retain anchors and global-keyed editor',
      (tester) async {
    final fixture = await _pumpHeader(tester, realEditor: true);
    try {
      final body = tester.state<_EditorBodyState>(find.byKey(fixture.bodyKey));
      final bodyElement = tester.element(find.byKey(fixture.bodyKey));
      final editorElement = tester.element(find.byType(editor.AppFlowyEditor));
      final setting =
          tester.state<_SettingDraftState>(find.byType(_SettingDraft));
      final settingElement = tester.element(find.byType(_SettingDraft));
      setting.controller.text = 'Filter draft';
      setting.controller.selection =
          const TextSelection(baseOffset: 2, extentOffset: 7);
      final draft = setting.controller.value;
      final transaction = body.editorState.transaction
        ..insertText(
          body.editorState.document.root.children.first,
          0,
          'Unsaved ',
        );
      await body.editorState.apply(transaction);
      final document = body.editorState.document.toJson();
      final tabStates = <String, State>{};
      final anchors = <String, Element>{};
      for (final view in fixture.views) {
        tabStates[view.id] = tester.state(
          find.descendant(
            of: _tab(view),
            matching: find.byType(TabBarItemButton),
          ),
        );
        anchors[view.id] = tester.element(_anchor(view));
      }
      final addState = tester.state(find.byType(AddDatabaseViewButton));
      final controllers = Map.of(fixture.bloc.state.tabBarControllerByViewId);
      for (final width in [320.0, 640.0, 1280.0, 320.0]) {
        fixture.update(() {
          fixture.width = width;
          fixture.scale = 2;
        });
        await tester.pumpAndSettle();
        expect(tester.element(find.byKey(fixture.bodyKey)), same(bodyElement));
        expect(
          tester.element(find.byType(editor.AppFlowyEditor)),
          same(editorElement),
        );
        expect(body.editorState.document.toJson(), document);
        expect(tester.state(find.byType(_SettingDraft)), same(setting));
        expect(
          tester.element(find.byType(_SettingDraft)),
          same(settingElement),
        );
        expect(setting.controller.value, draft);
        expect(
          tester.state(find.byType(AddDatabaseViewButton)),
          same(addState),
        );
        for (final view in fixture.views) {
          expect(
            tester.state(
              find.descendant(
                of: _tab(view),
                matching: find.byType(TabBarItemButton),
              ),
            ),
            same(tabStates[view.id]),
          );
          expect(tester.element(_anchor(view)), same(anchors[view.id]));
        }
        expect(tester.takeException(), isNull);
      }

      // Reordering saved view records is a backend concern. Feed its snapshot
      // through the real header and ensure keys, not positions, own the anchors.
      final activeId =
          fixture.bloc.state.tabBars[fixture.bloc.state.selectedIndex].viewId;
      final reordered = fixture.bloc.state.tabBars.reversed.toList();
      fixture.bloc.replace(
        fixture.bloc.state.copyWith(
          tabBars: reordered,
          selectedIndex: reordered.indexWhere((tab) => tab.viewId == activeId),
        ),
      );
      await tester.pumpAndSettle();
      for (final view in fixture.views) {
        expect(tester.element(_anchor(view)), same(anchors[view.id]));
      }
      expect(fixture.bloc.state.tabBarControllerByViewId, controllers);
      expect(
        tester.element(find.byType(editor.AppFlowyEditor)),
        same(editorElement),
      );
      expect(body.editorState.document.toJson(), document);
      expect(fixture.bloc.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  testWidgets('an open view menu retains its anchor through wrapping',
      (tester) async {
    final fixture = await _pumpHeader(tester);
    try {
      final selected = fixture.views.last;
      final anchor = tester.element(_anchor(selected));
      final popover = tester.widget<AppFlowyPopover>(_anchor(selected));
      await tester.tap(_button(selected));
      await tester.pumpAndSettle();
      expect(PopoverState.rootEntry, isNotEmpty);
      fixture.update(() {
        fixture.width = 320;
        fixture.scale = 2;
      });
      await tester.pumpAndSettle();
      expect(tester.element(_anchor(selected)), same(anchor));
      expect(
        tester.widget<AppFlowyPopover>(_anchor(selected)).controller,
        same(popover.controller),
      );
      expect(PopoverState.rootEntry, isNotEmpty);
      popover.controller!.close();
      await tester.pumpAndSettle();
      expect(PopoverState.rootEntry, isEmpty);
      expect(find.byKey(_addKey).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  testWidgets(
      'large view sets use a visible vertical scrollbar, not hidden choices',
      (tester) async {
    final fixture = await _pumpHeader(tester, width: 320, count: 60);
    try {
      expect(find.byType(DatabaseTabBarItem), findsNWidgets(60));
      final scrollbar = tester.widget<Scrollbar>(
        find
            .descendant(
              of: find.byType(TabBarHeader),
              matching: find.byType(Scrollbar),
            )
            .first,
      );
      expect(scrollbar.thumbVisibility, isTrue);
      expect(scrollbar.trackVisibility, isTrue);
      expect(
        tester.getSize(find.byKey(_headerKey)).height,
        inInclusiveRange(160, 480),
      );
      expect(_verticalPosition(tester).maxScrollExtent, greaterThan(0));
      await Scrollable.ensureVisible(tester.element(find.byKey(_addKey)));
      await tester.pumpAndSettle();
      expect(find.byKey(_addKey).hitTestable(), findsOneWidget);
      expect(_button(fixture.views.last).hitTestable(), findsOneWidget);
      await tester.tap(_button(fixture.views.last));
      await tester.pumpAndSettle();
      // It was already selected, so close its menu before checking the header.
      tester
          .widget<AppFlowyPopover>(_anchor(fixture.views.last))
          .controller!
          .close();
      await tester.pumpAndSettle();
      expect(fixture.bloc.state.tabBars, hasLength(60));
      expect(fixture.bloc.mutations, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  for (final appearance in vividIconTestAppearances) {
    testWidgets(
      '$appearance: read-only keeps all choices visible but cannot create or edit views',
      (tester) async {
        final fixture = await _pumpHeader(
          tester,
          appearance: appearance,
          width: 320,
        );
        final semantics = tester.ensureSemantics();
        try {
          final addState = tester.state(find.byType(AddDatabaseViewButton));
          final staleOpen = tester.widget<IconButton>(_addButton()).onPressed!;
          fixture.access.setReadOnly();
          expect(fixture.access.state.isEditable, isFalse);
          // The same bloc has emitted, but the button has not rebuilt yet.
          staleOpen();
          await tester.pumpAndSettle();
          expect(tester.widget<IconButton>(_addButton()).onPressed, isNull);
          final node = tester.getSemantics(_addButton()).getSemanticsData();
          expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(node.hasFlag(ui.SemanticsFlag.isEnabled), isFalse);
          expect(node.hasAction(ui.SemanticsAction.tap), isFalse);
          _expectAllViewsInside(tester, fixture, addEnabled: false);

          for (var i = 0; i < fixture.views.length; i++) {
            final button = _button(fixture.views[i]);
            await tester.tap(button, kind: PointerDeviceKind.mouse);
            await tester.pumpAndSettle();
            expect(fixture.bloc.state.selectedIndex, i);
            await tester.tap(
              button,
              buttons: kSecondaryMouseButton,
              kind: PointerDeviceKind.mouse,
            );
            await tester.pumpAndSettle();
            expect(PopoverState.rootEntry, isEmpty);
            expect(find.byType(AFTextFieldDialog), findsNothing);
          }
          await tester.tapAt(
            tester.getCenter(_addButton()),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
          expect(find.byType(TabBarAddButtonAction), findsNothing);
          expect(fixture.bloc.mutations, isEmpty);

          fixture.access.change(ShareAccessLevel.fullAccess);
          await tester.pumpAndSettle();
          expect(
            tester.state(find.byType(AddDatabaseViewButton)),
            same(addState),
          );
          expect(
            tester.element(_addButton()).read<PageAccessLevelBloc>(),
            same(fixture.access),
          );
          await tester.tap(_addButton(), kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
          await tester.tap(_addChoice(DatabaseTabKind.grid));
          await tester.pumpAndSettle();
          expect(fixture.bloc.mutations, hasLength(1));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await _dispose(tester, fixture);
        }
      },
    );
  }

  testWidgets('initial access loading gates mutations even with sharing off',
      (tester) async {
    await FeatureFlag.sharedSection.turnOff();
    final fixture = await _pumpHeader(tester, loadingAccess: true, width: 320);
    try {
      // This is the actual initial state, whose isEditable is true while the
      // feature is off. Loading must be checked separately by the controls.
      expect(fixture.access.state.isLoadingLockStatus, isTrue);
      expect(fixture.access.state.isEditable, isTrue);
      expect(tester.widget<IconButton>(_addButton()).onPressed, isNull);
      _expectAllViewsInside(tester, fixture, addEnabled: false);
      await tester.tap(_button(fixture.views.first));
      await tester.pumpAndSettle();
      expect(fixture.bloc.state.selectedIndex, 0);
      await tester.tap(
        _button(fixture.views.first),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(PopoverState.rootEntry, isEmpty);
      expect(fixture.bloc.mutations, isEmpty);

      fixture.access.change(ShareAccessLevel.fullAccess);
      await tester.pumpAndSettle();
      await tester.tap(_addButton());
      await tester.pumpAndSettle();
      await tester.tap(_addChoice(DatabaseTabKind.grid));
      await tester.pumpAndSettle();
      expect(fixture.bloc.mutations, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  testWidgets('Add itself follows the same access stream and explicit disable',
      (tester) async {
    final access = _Access(ViewPB(id: 'standalone-add'));
    final created = <DatabaseTabKind>[];
    var enabled = true;
    late StateSetter update;
    try {
      // No TabBarHeader computes enabled for this instance.
      await tester.pumpWidget(
        vividIconTestApp(
          'paper',
          BlocProvider<PageAccessLevelBloc>.value(
            value: access,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return AddDatabaseViewButton(
                  key: _addKey,
                  enabled: enabled,
                  onTap: created.add,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final addState = tester.state(find.byType(AddDatabaseViewButton));
      for (final restriction in ['read-only', 'loading', 'locked']) {
        access.change(ShareAccessLevel.fullAccess);
        await tester.pumpAndSettle();
        final staleOpen = tester.widget<IconButton>(_addButton()).onPressed!;
        await tester.tap(_addButton(), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        final staleCreate = tester
            .widget<TextButton>(_addChoice(DatabaseTabKind.grid))
            .onPressed!;
        access.change(
          restriction == 'read-only'
              ? ShareAccessLevel.readOnly
              : ShareAccessLevel.fullAccess,
          loading: restriction == 'loading',
          locked: restriction == 'locked',
        );
        staleCreate();
        staleOpen();
        await tester.pumpAndSettle();
        expect(tester.widget<IconButton>(_addButton()).onPressed, isNull);
        expect(PopoverState.rootEntry, isEmpty);
        expect(created, isEmpty);
        expect(
          tester.state(find.byType(AddDatabaseViewButton)),
          same(addState),
        );
      }

      access.change(ShareAccessLevel.fullAccess);
      await tester.pumpAndSettle();
      await tester.tap(_addButton(), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      // A stream update alone must dismiss an already-open menu too.
      access.setReadOnly();
      await tester.pumpAndSettle();
      expect(PopoverState.rootEntry, isEmpty);
      expect(tester.widget<IconButton>(_addButton()).onPressed, isNull);

      access.change(ShareAccessLevel.fullAccess);
      await tester.pumpAndSettle();
      await tester.tap(_addButton(), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await tester.tap(_addChoice(DatabaseTabKind.grid));
      await tester.pumpAndSettle();
      expect(created, [DatabaseTabKind.grid]);
      await tester.tap(_addButton());
      await tester.pumpAndSettle();
      update(() => enabled = false);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(_addButton()).onPressed, isNull);
      expect(PopoverState.rootEntry, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(access.close);
    }
  });

  for (final restriction in _Restriction.values) {
    testWidgets('${restriction.name} revokes an open view mutation menu',
        (tester) async {
      final fixture = await _pumpHeader(tester);
      try {
        final selected = fixture.views.last;
        final anchor = tester.element(_anchor(selected));
        await tester.tap(
          _button(selected),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        final cells = [
          for (final action in TabBarViewAction.values)
            tester.widget<ActionCellWidget<TabBarViewAction>>(
              _viewAction(action),
            ),
        ];
        _restrict(fixture, restriction);
        // Already-rendered menu callbacks must read the new state before a
        // frame rebuilds/closes the popover. None may open a write dialog.
        for (final cell in cells) {
          cell.onSelected(cell.action);
        }
        await tester.pumpAndSettle();
        expect(PopoverState.rootEntry, isEmpty);
        expect(find.byType(AFTextFieldDialog), findsNothing);
        expect(find.byType(NavigatorAlertDialog), findsNothing);
        expect(tester.element(_anchor(selected)), same(anchor));
        await tester.tap(_button(fixture.views.first));
        await tester.pumpAndSettle();
        expect(fixture.bloc.state.selectedIndex, 0);
        expect(fixture.bloc.mutations, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    });
  }

  for (final action in [TabBarViewAction.rename, TabBarViewAction.delete]) {
    testWidgets('${action.name} confirmation rechecks revoked access',
        (tester) async {
      final fixture = await _pumpHeader(tester);
      try {
        await tester.tap(
          _button(fixture.views.last),
          buttons: kSecondaryMouseButton,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.tap(_viewAction(action));
        await tester.pumpAndSettle();
        final dialog = action == TabBarViewAction.rename
            ? find.byType(AFTextFieldDialog)
            : find.byType(NavigatorAlertDialog);
        expect(dialog, findsOneWidget);
        if (action == TabBarViewAction.rename) {
          await tester.enterText(
            find.descendant(of: dialog, matching: find.byType(EditableText)),
            'Must not be saved',
          );
        }
        fixture.access.setReadOnly();
        await tester.pumpAndSettle();
        final confirm = find.descendant(
          of: dialog,
          matching: action == TabBarViewAction.rename
              ? find.byType(AFFilledTextButton)
              : find.byType(PrimaryTextButton),
        );
        expect(confirm.hitTestable(), findsOneWidget);
        await tester.tap(confirm, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(fixture.bloc.mutations, isEmpty);
        expect(tester.widget<IconButton>(_addButton()).onPressed, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    });
  }

  testWidgets(
      'missing access remains permitted but parent lock guards stale Add',
      (tester) async {
    final fixture = await _pumpHeader(tester, provideAccess: false);
    try {
      expect(tester.element(_addButton()).read<PageAccessLevelBloc?>(), isNull);
      _expectAllViewsInside(tester, fixture);
      await tester.tap(_addButton());
      await tester.pumpAndSettle();
      final staleCreate = tester
          .widget<TextButton>(_addChoice(DatabaseTabKind.grid))
          .onPressed!;
      final unlocked = fixture.bloc.state.parentView;
      _restrict(fixture, _Restriction.parentLocked);
      staleCreate();
      await tester.pumpAndSettle();
      expect(fixture.bloc.mutations, isEmpty);
      expect(tester.widget<IconButton>(_addButton()).onPressed, isNull);
      await tester.tap(_button(fixture.views.first));
      await tester.pumpAndSettle();
      expect(fixture.bloc.state.selectedIndex, 0);
      await tester.tap(
        _button(fixture.views.first),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(PopoverState.rootEntry, isEmpty);

      fixture.bloc.replace(fixture.bloc.state.copyWith(parentView: unlocked));
      await tester.pumpAndSettle();
      await tester.tap(_addButton());
      await tester.pumpAndSettle();
      await tester.tap(_addChoice(DatabaseTabKind.grid));
      await tester.pumpAndSettle();
      expect(fixture.bloc.mutations, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester, fixture);
    }
  });

  testWidgets(
      'empty or transient selected/controller snapshots do not index past the header',
      (tester) async {
    final fixture = await _pumpHeader(tester);
    try {
      final initial = fixture.bloc.state;
      for (final state in [
        initial.copyWith(selectedIndex: initial.tabBars.length),
        initial.copyWith(selectedIndex: -1),
        initial.copyWith(tabBarControllerByViewId: {}),
        initial.copyWith(tabBars: [], selectedIndex: 0),
      ]) {
        fixture.bloc.replace(state);
        await tester.pumpAndSettle();
        expect(find.byKey(_addKey).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    } finally {
      await _dispose(tester, fixture);
    }
  });
}

Finder _tab(ViewPB view) => find.byKey(ValueKey(view.id));
Finder _button(ViewPB view) =>
    find.descendant(of: _tab(view), matching: find.byType(TextButton));
Finder _addButton() =>
    find.descendant(of: find.byKey(_addKey), matching: find.byType(IconButton));
Finder _addChoice(DatabaseTabKind kind) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is TabBarAddButtonActionCell && widget.action == kind,
      ),
      matching: find.byType(TextButton),
    );
Finder _viewAction(TabBarViewAction action) => find.byWidgetPredicate(
      (widget) => widget is ActionCellWidget && widget.action == action,
    );
Finder _anchor(ViewPB view) => find
    .descendant(of: _tab(view), matching: find.byType(AppFlowyPopover))
    .first;
ScrollPosition _verticalPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(TabBarHeader),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
            ),
          )
          .first,
    )
    .position;
void _inside(Rect child, Rect parent) {
  expect(child.left, greaterThanOrEqualTo(parent.left - 0.01));
  expect(child.right, lessThanOrEqualTo(parent.right + 0.01));
  expect(child.top, greaterThanOrEqualTo(parent.top - 0.01));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom + 0.01));
}

void _expectNativeHitArea(WidgetTester tester, Finder button) {
  final box = tester.renderObject<RenderBox>(button);
  expect(box.constraints.isSatisfiedBy(box.size), isTrue);
  expect(box.size.shortestSide, greaterThan(0));
  // Half a physical pixel inside each edge detects real clipping; merely
  // finding the label or hitting the center would miss a cropped control.
  final pixel = 1 / tester.view.devicePixelRatio;
  for (final at in [
    Alignment.center,
    Alignment(0, -1 + pixel / box.size.height),
    Alignment(0, 1 - pixel / box.size.height),
    Alignment(-1 + pixel / box.size.width, 0),
    Alignment(1 - pixel / box.size.width, 0),
  ]) {
    expect(button.hitTestable(at: at), findsOneWidget);
  }
}

void _expectAllViewsInside(
  WidgetTester tester,
  _Fixture fixture, {
  bool addEnabled = true,
}) {
  final headerFinder = find.byKey(_headerKey);
  final header = tester.getRect(headerFinder);
  final wrap = tester.getRect(find.byKey(_wrapKey));
  final host = tester.getRect(find.byKey(_hostKey));
  final screen =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  for (final finder in [
    headerFinder,
    find.byKey(_wrapKey),
    find.byKey(_hostKey),
  ]) {
    final box = tester.renderObject<RenderBox>(finder);
    expect(box.constraints.isSatisfiedBy(box.size), isTrue);
  }
  _inside(host, screen);
  _inside(header, host);
  _inside(wrap, header);
  expect(_verticalPosition(tester).pixels, 0);
  expect(_verticalPosition(tester).maxScrollExtent, 0);
  for (final view in fixture.views) {
    final tab = tester.getRect(_tab(view));
    _inside(tab, wrap);
    _inside(tab, header);
    _inside(tester.getRect(_button(view)), tab);
    _expectNativeHitArea(tester, _button(view));
  }
  final add = tester.getRect(find.byKey(_addKey));
  _inside(add, wrap);
  _inside(add, header);
  _inside(tester.getRect(_addButton()), add);
  expect(tester.widget<IconButton>(_addButton()).onPressed != null, addEnabled);
  if (addEnabled) _expectNativeHitArea(tester, _addButton());
  _inside(tester.getRect(find.byType(_SettingDraft)), header);
}

enum _Restriction { readOnly, loading, locked, parentLocked, viewLocked }

void _restrict(_Fixture fixture, _Restriction restriction) {
  switch (restriction) {
    case _Restriction.readOnly:
      fixture.access.setReadOnly();
    case _Restriction.loading:
      fixture.access.change(ShareAccessLevel.fullAccess, loading: true);
    case _Restriction.locked:
      fixture.access.change(ShareAccessLevel.fullAccess, locked: true);
    case _Restriction.parentLocked:
      final locked = ViewPB.fromBuffer(
        fixture.bloc.state.parentView.writeToBuffer(),
      )..isLocked = true;
      fixture.bloc.replace(fixture.bloc.state.copyWith(parentView: locked));
    case _Restriction.viewLocked:
      final state = fixture.bloc.state;
      fixture.bloc.replace(
        state.copyWith(
          tabBars: [
            for (final tab in state.tabBars)
              if (tab.viewId == fixture.views.last.id)
                _TabRecord(
                  ViewPB.fromBuffer(tab.view.writeToBuffer())..isLocked = true,
                )
              else
                tab,
          ],
        ),
      );
  }
}

Future<_Fixture> _pumpHeader(
  WidgetTester tester, {
  String appearance = 'paper',
  double width = 1280,
  double scale = 1,
  int count = 10,
  bool realEditor = false,
  bool loadingAccess = false,
  bool provideAccess = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.reset);
  final fixture = _Fixture(count, loadingAccess: loadingAccess)
    ..width = width
    ..scale = scale;
  final theme = vividIconTestTheme(appearance);
  final defaults = AppFlowyDefaultTheme();
  await tester.pumpWidget(
    vividIconTestApp(
      appearance,
      AppFlowyTheme(
        data: PremiumTheme.appFlowyTheme(
          base: appearance == 'dark' ? defaults.dark() : defaults.light(),
          palette: theme.extension<PremiumThemeExtension>()!,
          brightness: theme.brightness,
        ),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<db.DatabaseTabBarBloc>.value(value: fixture.bloc),
            if (provideAccess)
              BlocProvider<PageAccessLevelBloc>.value(value: fixture.access),
          ],
          child: StatefulBuilder(
            builder: (context, update) {
              fixture.update = update;
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(fixture.scale)),
                child: SizedBox(
                  key: _hostKey,
                  width: fixture.width,
                  height: 1000,
                  child: Column(
                    children: [
                      const TabBarHeader(),
                      Expanded(
                        child: realEditor
                            ? _EditorBody(key: fixture.bodyKey)
                            : const SizedBox.expand(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> _dispose(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(fixture.bloc.close);
  await tester.runAsync(fixture.access.close);
}

class _Fixture {
  _Fixture(int count, {bool loadingAccess = false}) {
    const names = [
      'Table',
      'Board',
      'Calendar',
      'Gallery',
      'Timeline',
      'Feed',
      'Form',
      'Mailbox',
      'Chart',
      'Map',
    ];
    views = [
      for (var i = 0; i < count; i++)
        ViewPB(
          id: 'db-view-$i',
          parentViewId: i == 0 ? 'folder' : 'db-view-0',
          name: i < names.length ? names[i] : 'View ${i + 1}',
          layout: [
            ViewLayoutPB.Grid,
            ViewLayoutPB.Board,
            ViewLayoutPB.Calendar,
          ][i % 3],
          extra: '{"saved_view_marker":$i}',
        ),
    ];
    bloc = _HeaderBloc(
      db.DatabaseTabBarState(
        parentView: views.first,
        selectedIndex: views.length - 1,
        compactModeId: 'header-test',
        enableCompactMode: false,
        tabBars: [for (final view in views) _TabRecord(view)],
        tabBarControllerByViewId: {
          for (final view in views) view.id: _ControllerHandle(),
        },
      ),
    );
    access = _Access(views.first, loading: loadingAccess);
  }
  late final List<ViewPB> views;
  late final _HeaderBloc bloc;
  late final _Access access;
  final bodyKey = GlobalKey();
  late StateSetter update;
  double width = 1280;
  double scale = 1;
}

// Only the backend-facing boundary is substituted. Production header, buttons,
// popovers, focus/semantics and saved view/controller identity are exercised.
class _HeaderBloc extends Cubit<db.DatabaseTabBarState>
    implements db.DatabaseTabBarBloc {
  _HeaderBloc(super.state);
  final mutations = <db.DatabaseTabBarEvent>[];
  void replace(db.DatabaseTabBarState next) => emit(next);
  @override
  void add(db.DatabaseTabBarEvent event) => event.maybeWhen<void>(
        selectView: (id) {
          final index = state.tabBars.indexWhere((tab) => tab.viewId == id);
          if (index >= 0) emit(state.copyWith(selectedIndex: index));
        },
        orElse: () => mutations.add(event),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Access extends Cubit<PageAccessLevelState>
    implements PageAccessLevelBloc {
  _Access(this.view, {bool loading = false})
      : super(
          loading
              ? PageAccessLevelState.initial(view)
              : PageAccessLevelState.initial(view).copyWith(
                  accessLevel: ShareAccessLevel.fullAccess,
                  isLoadingLockStatus: false,
                ),
        );
  @override
  final ViewPB view;
  void setReadOnly() => change(ShareAccessLevel.readOnly);
  void change(
    ShareAccessLevel level, {
    bool loading = false,
    bool locked = false,
  }) =>
      emit(
        state.copyWith(
          accessLevel: level,
          isLoadingLockStatus: loading,
          isLocked: locked,
        ),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryKeyValue extends Fake implements KeyValueStorage {
  @override
  Future<void> set(String key, String value) async {}
}

class _TabRecord extends Fake implements db.DatabaseTabBar {
  _TabRecord(this.view);
  @override
  final ViewPB view;
  @override
  String get viewId => view.id;
  @override
  final DatabaseTabBarItemBuilder builder = _Builder();
}

class _ControllerHandle extends Fake implements db.DatabaseTabBarController {
  @override
  final DatabaseController controller = _Controller();
}

class _Controller extends Fake implements DatabaseController {}

class _Builder extends DatabaseTabBarItemBuilder {
  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      const SizedBox.shrink();
  @override
  Widget settingBar(BuildContext context, DatabaseController controller) =>
      const _SettingDraft();
  @override
  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  ) =>
      const SizedBox.shrink();
}

class _SettingDraft extends StatefulWidget {
  const _SettingDraft();
  @override
  State<_SettingDraft> createState() => _SettingDraftState();
}

class _SettingDraftState extends State<_SettingDraft> {
  final controller = TextEditingController();
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 140,
        height: 36,
        child: TextField(
          controller: controller,
          decoration:
              const InputDecoration(isDense: true, border: InputBorder.none),
        ),
      );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class _EditorBody extends StatefulWidget {
  const _EditorBody({super.key});
  @override
  State<_EditorBody> createState() => _EditorBodyState();
}

class _EditorBodyState extends State<_EditorBody> {
  final editorKey = GlobalKey();
  final editorState = editor.EditorState(
    document: editor.Document(
      root: editor.pageNode(
        children: [editor.paragraphNode(text: 'Embedded database draft')],
      ),
    ),
  )..disableSealTimer = true;
  @override
  Widget build(BuildContext context) => editor.AppFlowyEditor(
        key: editorKey,
        editorState: editorState,
        disableAutoScroll: true,
        editorStyle:
            const editor.EditorStyle.desktop(padding: EdgeInsets.all(16)),
        contextMenuItems: const [],
      );
  @override
  void dispose() {
    editorState.dispose();
    super.dispose();
  }
}
