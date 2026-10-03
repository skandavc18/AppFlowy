import 'dart:io';

import 'package:appflowy/core/frameless_window.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/footer/sidebar_footer_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/header/sidebar_top_menu.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:appflowy/workspace/presentation/widgets/sidebar_resizer.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance rows reveal keyboard actions without shifting names',
        (tester) async {
      final actionFocus = FocusNode();
      final semantics = tester.ensureSemantics();
      var opened = 0;
      var actions = 0;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            SidebarRow(
              label: const Text('A retained page'),
              icon: const SidebarGlyph(SidebarIcon.document),
              onTap: () => opened++,
              trailingSlots: 1,
              trailingBuilder: (_) => [
                SidebarIconButton(
                  icon: SidebarIcon.more,
                  tooltip: 'Row options',
                  focusNode: actionFocus,
                  onPressed: () => actions++,
                ),
              ],
            ),
            reducedMotion: true,
          ),
        );
        expect(tester.getSize(find.byType(SidebarRow)).height, 34);
        final labelRect = tester.getRect(find.text('A retained page'));
        expect(find.byType(SidebarIconButton), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.pump();
        expect(find.byType(SidebarIconButton), findsOneWidget);
        expect(tester.getRect(find.text('A retained page')), labelRect);
        final rowSurface = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byType(SidebarRow),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        final palette =
            SidebarPalette.of(tester.element(find.byType(SidebarRow)));
        final decoration = rowSurface.decoration! as BoxDecoration;
        expect(decoration.border, isNull);
        expect(decoration.color, palette.hover);
        expect(rowSurface.duration, Duration.zero);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(opened, 1);
        actionFocus.requestFocus();
        await tester.pump();
        await tester.pump();
        final actionNode = tester.getSemantics(find.byType(IconButton));
        expect(
          actionNode.getSemanticsData().hasFlag(SemanticsFlag.isButton),
          isTrue,
        );
        expect(
          actionNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(actionNode.label, 'Row options');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(actions, 1);
        expect(
          opened,
          1,
          reason: 'child activation must not also open the page',
        );

        actionFocus.unfocus();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.semantics.byLabel('Row options'), findsNothing);
        expect(tester.getRect(find.text('A retained page')), labelRect);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        actionFocus.dispose();
      }
    });

    testWidgets('$appearance disclosure remains separate from row navigation',
        (tester) async {
      var expanded = false;
      var opened = 0;
      await tester.pumpWidget(
        _app(
          appearance,
          StatefulBuilder(
            builder: (context, setState) => SidebarRow(
              reserveLeadingSpace: true,
              leading: SidebarDisclosure(
                expanded: expanded,
                tooltip: 'Toggle children',
                onTap: () => setState(() => expanded = !expanded),
              ),
              icon: const SidebarGlyph(SidebarIcon.folder),
              label: const Text('Folder'),
              onTap: () => opened++,
            ),
          ),
          reducedMotion: true,
        ),
      );
      final iconRect = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SidebarGlyph && widget.icon == SidebarIcon.folder,
        ),
      );
      await tester.tap(find.byType(SidebarDisclosure));
      await tester.pumpAndSettle();
      expect(expanded, isTrue);
      expect(opened, 0);
      expect(
        tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).duration,
        Duration.zero,
      );
      expect(
        tester.getRect(find.byType(SidebarDisclosure)).overlaps(iconRect),
        isFalse,
      );
      await tester.tap(find.text('Folder'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        '$appearance resize feedback follows its palette and motion setting',
        (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await tester.pumpWidget(
          _app(appearance, const SidebarResizer(), reducedMotion: true),
        );
        final indicator =
            find.byKey(const ValueKey('sidebar-resize-indicator'));
        final idle = tester.widget<AnimatedContainer>(indicator);
        expect((idle.decoration! as BoxDecoration).color!.a, 0);
        await mouse.addPointer(location: const Offset(600, 400));
        await mouse.moveTo(tester.getCenter(find.byType(SidebarResizer)));
        await tester.pump();
        final palette = SidebarPalette.of(tester.element(indicator));
        final feedback = tester.widget<AnimatedContainer>(indicator);
        final feedbackColor = (feedback.decoration! as BoxDecoration).color;
        expect(feedbackColor, palette.dropIndicator);
        expect(feedback.duration, Duration.zero);
        if (appearance == 'paper') {
          expect(palette.background, PaperTheme.sidebarBackground);
          expect(feedbackColor, PaperTheme.accent);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets(
        '$appearance footer actions are one compact keyboard-accessible row',
        (tester) async {
      final invoked = <String>[];
      await tester.pumpWidget(
        _app(
          appearance,
          Wrap(
            children: [
              for (final (label, icon) in [
                ('Templates', SidebarIcon.templates),
                ('Extensions', SidebarIcon.extensions),
                ('Trash', SidebarIcon.trash),
              ])
                SidebarFooterButton(
                  compact: true,
                  icon: icon,
                  text: label,
                  onTap: () => invoked.add(label),
                ),
            ],
          ),
        ),
      );
      final buttons = find.byType(SidebarFooterButton);
      final top = tester.getTopLeft(buttons.first).dy;
      for (var i = 0; i < 3; i++) {
        expect(tester.getTopLeft(buttons.at(i)).dy, top);
        expect(
          tester.getSize(buttons.at(i)).height,
          WorkspaceTokens.controlHeight,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
      }
      expect(invoked, ['Templates', 'Extensions', 'Trash']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('removing a focused rename field releases the row action reveal',
      (tester) async {
    final focus = FocusNode();
    var editing = true;
    var opened = 0;
    late StateSetter update;
    try {
      await tester.pumpWidget(
        _app(
          'paper',
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SidebarRow(
                label: editing
                    ? TextField(focusNode: focus)
                    : const Text('Renamed page'),
                onTap: () => opened++,
                trailingSlots: 1,
                trailingBuilder: (_) => [
                  SidebarIconButton(icon: SidebarIcon.more, onPressed: () {}),
                ],
              );
            },
          ),
          reducedMotion: true,
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Working draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(opened, 0);
      expect(
        tester
            .widget<SidebarActionReveal>(find.byType(SidebarActionReveal))
            .revealed,
        isTrue,
      );
      update(() => editing = false);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        tester
            .widget<SidebarActionReveal>(find.byType(SidebarActionReveal))
            .revealed,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      focus.dispose();
    }
  });

  testWidgets(
      'drawer identity shares the 40px row and never sits inside a drag detector',
      (tester) async {
    final hover = ValueNotifier(true);
    final home = _MockHomeSettingBloc();
    when(() => home.state).thenReturn(_settings());
    when(() => home.stream)
        .thenAnswer((_) => const Stream<HomeSettingState>.empty());
    var switches = 0;
    try {
      await tester.pumpWidget(
        BlocProvider<HomeSettingBloc>.value(
          value: home,
          child: _app(
            'paper',
            SidebarTopMenu(
              isSidebarOnHover: hover,
              identity: TextButton(
                key: const ValueKey('workspace-identity'),
                onPressed: () => switches++,
                child: const Text(
                  'Workspace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final identity = find.byKey(const ValueKey('workspace-identity'));
      expect(tester.getSize(find.byType(SidebarTopMenu)).height, 40);
      for (final type in [MoveWindowDetector, DragToMoveArea]) {
        expect(
          find.ancestor(of: identity, matching: find.byType(type)),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: find.byType(SidebarIconButton),
            matching: find.byType(type),
          ),
          findsNothing,
        );
      }
      await tester.tap(identity);
      expect(switches, 1);
      await tester.tap(find.byType(SidebarIconButton));
      verify(() => home.collapseMenu()).called(1);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      hover.dispose();
    }
  });

  test(
      'creation follows the compact footer and existing destinations are retained',
      () {
    final sidebar =
        File('lib/workspace/presentation/home/menu/sidebar/sidebar.dart')
            .readAsStringSync();
    final footer = File(
      'lib/workspace/presentation/home/menu/sidebar/footer/sidebar_footer.dart',
    ).readAsStringSync();
    expect(
      sidebar.indexOf('child: const SidebarNewPageButton()'),
      greaterThan(sidebar.indexOf('child: const SidebarFooter()')),
    );
    expect(sidebar, contains('showUtilities: false'));
    for (final entry in [
      'UserSettingButton()',
      'NotificationButton(',
      'PluginType.templates',
      'PluginType.extensions',
      'PluginType.workflows',
      'PluginType.trash',
    ]) {
      expect(footer, contains(entry));
    }
  });
}

Widget _app(String appearance, Widget child, {bool reducedMotion = false}) {
  final theme = DesktopAppearance()
      .getThemeData(
        appearance == 'paper'
            ? AppTheme.builtins
                .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        appearance == 'dark' ? Brightness.dark : Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      )
      .copyWith(platform: TargetPlatform.windows);
  return MaterialApp(
    theme: theme,
    themeAnimationDuration: Duration.zero,
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 600),
        disableAnimations: reducedMotion,
      ),
      child: Scaffold(
        body: Builder(
          builder: (context) => Theme(
            data: SidebarStyle.themeData(context),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: WorkspaceTokens.navigationWidth,
                height: 400,
                child: Align(alignment: Alignment.topLeft, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

HomeSettingState _settings() => HomeSettingState(
      panelContext: null,
      workspaceSetting: WorkspaceLatestPB(workspaceId: 'sidebar-fixture'),
      unauthorized: false,
      menuStatus: MenuStatus.expanded,
      isNotificationPanelCollapsed: true,
      // Only the overlay drawer retains a local collapse button.
      isScreenSmall: true,
      hasColappsedMenuManually: false,
      resizeOffset: 0,
      resizeStart: 0,
      resizeType: MenuResizeType.slide,
    );

class _MockHomeSettingBloc extends Mock implements HomeSettingBloc {}
