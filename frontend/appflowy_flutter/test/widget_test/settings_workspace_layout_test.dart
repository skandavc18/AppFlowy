import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_body.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_category_spacer.dart';
import 'package:appflowy/workspace/presentation/settings/shared/settings_workspace_layout.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu_element.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_overlay_test_app.dart';

void main() {
  setUpAll(initializeWorkspaceOverlayTests);

  for (final appearance in ['light', 'dark', 'paper']) {
    for (final width in [360.0, 560.0, 840.0, 1120.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$appearance settings fit $width at text scale $scale',
            (tester) async {
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var closed = 0;
          await tester.pumpWidget(
            workspaceOverlayTestApp(
              appearance: appearance,
              textScale: scale,
              child: Center(
                child: SizedBox(
                  width: width,
                  height: 640,
                  child: SettingsWorkspaceLayout(
                    navigation: const Text('Navigation rail'),
                    navigationPicker: TextButton(
                      onPressed: () {},
                      child: const Text('Choose category'),
                    ),
                    onClose: () => closed++,
                    child: SettingsBody(
                      title: 'Editor settings',
                      description:
                          'Preferences should leave room for the content.',
                      children: [
                        SettingsCategory(
                          title: 'A category with a longer, wrapping title',
                          description:
                              'Every setting and recovery remains reachable.',
                          actions: [
                            TextButton(
                              onPressed: () {},
                              child: const Text('Reset'),
                            ),
                          ],
                          children: [
                            const TextField(),
                            TextButton(
                              onPressed: () {},
                              child: const Text('Save draft'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final compact = width <
              SettingsWorkspaceLayout.compactBreakpoint + (scale - 1) * 160;
          expect(
            tester
                .getSize(find.byKey(const ValueKey('settings-navigation-rail')))
                .width,
            compact ? 0 : SettingsWorkspaceLayout.navigationWidth,
          );
          expect(
            find.text('Choose category'),
            compact ? findsOneWidget : findsNothing,
          );
          expect(find.byType(Divider), findsNothing);
          expect(
            tester.widget<Text>(find.text('Editor settings')).style?.fontSize,
            40,
          );
          expect(
            tester
                .widget<Text>(
                  find.text('A category with a longer, wrapping title'),
                )
                .style
                ?.fontSize,
            20,
          );
          final surface = tester.widget<ColoredBox>(
            find
                .descendant(
                  of: find.byType(SettingsWorkspaceLayout),
                  matching: find.byType(ColoredBox),
                )
                .first,
          );
          final palette = WorkspacePalette.of(
            tester.element(find.byType(SettingsWorkspaceLayout)),
          );
          expect(surface.color, palette.elevatedSurface);
          await tester.ensureVisible(find.text('Save draft'));
          await tester.pumpAndSettle();
          expect(find.text('Save draft').hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('settings-close')).hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('settings-close')));
          expect(closed, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets(
        '$appearance keeps draft, selection and focus across compositions',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = TextEditingController();
      final focus = FocusNode();
      var width = 1120.0;
      late StateSetter resize;
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: StatefulBuilder(
            builder: (context, setState) {
              resize = setState;
              return Center(
                child: SizedBox(
                  width: width,
                  height: 700,
                  child: SettingsWorkspaceLayout(
                    navigation: const Text('Rail'),
                    navigationPicker: const Text('Picker'),
                    onClose: () {},
                    child: SettingsBody(
                      title: 'Draft',
                      children: [
                        TextField(controller: controller, focusNode: focus),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Keep this unsaved draft');
      controller.selection =
          const TextSelection(baseOffset: 2, extentOffset: 7);
      final editable = tester.state(find.byType(EditableText));
      for (final next in [360.0, 700.0, 1120.0]) {
        resize(() => width = next);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(EditableText)), same(editable));
        expect(controller.text, 'Keep this unsaved draft');
        expect(
          controller.selection,
          const TextSelection(baseOffset: 2, extentOffset: 7),
        );
        expect(focus.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      controller.dispose();
    });
  }

  for (final (workspaceType, role) in [
    (WorkspaceTypePB.ServerW, AFRolePB.Owner),
    (WorkspaceTypePB.ServerW, AFRolePB.Guest),
    (
      WorkspaceTypePB.values
          .firstWhere((type) => type != WorkspaceTypePB.ServerW),
      null
    ),
  ]) {
    testWidgets(
        '$workspaceType/$role picker and rail expose the same destinations',
        (tester) async {
      final profile = UserProfilePB()..workspaceType = workspaceType;
      SettingsPage? selected;
      Widget menu(bool compact) => SettingsMenu(
            compact: compact,
            userProfile: profile,
            currentUserRole: role,
            currentPage: SettingsPage.account,
            isBillingEnabled: false,
            changeSelectedPage: (SettingsPage page) => selected = page,
          );
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          child: Center(
            child: SizedBox(width: 232, height: 560, child: menu(false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entries = tester
          .widgetList<SettingsMenuElement>(find.byType(SettingsMenuElement))
          .toList();
      final pages = entries.map((entry) => entry.page).toSet();
      expect(pages, isNot(contains(SettingsPage.billing)));
      expect(pages, isNot(contains(SettingsPage.plan)));
      if (workspaceType != WorkspaceTypePB.ServerW || role == AFRolePB.Guest) {
        expect(pages, isNot(contains(SettingsPage.member)));
        expect(pages, isNot(contains(SettingsPage.sites)));
      } else {
        expect(pages, contains(SettingsPage.sites));
      }
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          child: Center(child: SizedBox(width: 300, child: menu(true))),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-category-picker')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<AppMenuRow>(find.byType(AppMenuRow))
            .map((row) => row.label),
        entries.map((entry) => entry.label),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, SettingsPage.workspace);
      expect(find.byType(AppMenuSurface), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('category spacing honors overrides without drawing a rule',
      (tester) async {
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        child: const Center(
          child: SettingsCategorySpacer(topSpacing: 7, bottomSpacing: 11),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SettingsCategorySpacer)).height, 18);
    expect(find.byType(Divider), findsNothing);
  });
}
