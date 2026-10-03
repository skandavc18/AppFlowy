import 'dart:io';

import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/workflows/application/workflow_manager.dart';
import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_run_log.dart';
import 'package:appflowy/workflows/application/workflow_store.dart';
import 'package:appflowy/workflows/application/workflow_templates.dart';
import 'package:appflowy/workflows/presentation/workflow_editor.dart';
import 'package:appflowy/workflows/presentation/workflow_inputs.dart';
import 'package:appflowy/workflows/presentation/workflow_style.dart';
import 'package:appflowy/workflows/presentation/workflows_page.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../unit_test/workflows/workflow_test_support.dart';
import 'test_asset_bundle.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  Future<WorkflowManager> manager() async {
    final store = WorkflowStore(files: MemoryWorkflowFiles());
    final log = WorkflowRunLog(files: MemoryWorkflowFiles());
    await store.ensureLoaded();
    await log.ensureLoaded();
    return WorkflowManager(
      store: store,
      log: log,
      services: FakeWorkflowServices(),
    );
  }

  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets('$appearance: a first workflow starts from a template',
        (tester) async {
      wide(tester);
      final workflows = await manager();
      await tester.pumpWidget(
        _app(appearance, WorkflowsPage(manager: workflows)),
      );
      await tester.pumpAndSettle();

      final palette =
          DashboardPalette.of(tester.element(find.byType(WorkflowsPage)));
      expect(palette.isPaper, appearance == 'paper');
      expect(palette.isDark, appearance == 'dark');
      expect(find.text('Automate the busywork'), findsOneWidget);
      for (final template in workflowTemplates) {
        expect(find.text(template.title), findsOneWidget);
      }

      await tester.tap(find.text('Daily journal page'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkflowEditor), findsOneWidget);
      final created = workflows.store.workflows.single;
      expect(created.name, 'Daily journal page');
      expect(created.enabled, isFalse, reason: 'nothing runs until turned on');
      expect(created.workspaceId, 'ws1');
      expect(
        find.byKey(const ValueKey('workflow-node-trigger')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('workflow-node-step1')), findsOneWidget);
      expect(find.text('Every day at 08:00'), findsWidgets);

      await tester.tap(find.byTooltip('Back to workflows'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('workflow-card-${created.id}')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ValueKey('workflow-switch-${created.id}')));
      await tester.pumpAndSettle();
      final enabled = workflows.store.byId(created.id)!;
      expect(enabled.enabled, isTrue);
      expect(enabled.enabledAt, isNotNull);
      if (Platform.isWindows) {
        expect(
          find.text('Workflows only run while AppFlowy is open.'),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the editor adds a step and keeps what is typed', (tester) async {
    wide(tester);
    final workflows = await manager();
    final workflow = await workflows.create(Workflow.create(name: 'Morning'));
    await tester.pumpWidget(_app('light', WorkflowsPage(manager: workflows)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkflowEditor), findsOneWidget);
    // A workflow with no steps cannot be turned on yet.
    final toggle = tester.widget<WorkflowSwitch>(
      find.byKey(const ValueKey('workflow-editor-enabled')),
    );
    expect(toggle.onChanged, isNull);

    await tester.tap(find.byKey(const ValueKey('workflow-add-step')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notification').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workflow-node-step1')), findsOneWidget);

    final title = find.descendant(
      of: find.widgetWithText(WorkflowTextInput, 'Title'),
      matching: find.byType(TextField),
    );
    await tester.enterText(title, 'Good morning');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final saved = workflows.store.byId(workflow.id)!;
    expect(saved.steps.single.kind, WorkflowStepKind.notify);
    expect(saved.steps.single.text('title'), 'Good morning');
    expect(saved.isComplete, isTrue);
    expect(
      tester
          .widget<WorkflowSwitch>(
            find.byKey(const ValueKey('workflow-editor-enabled')),
          )
          .onChanged,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('background settings are kept and shown on the page',
      (tester) async {
    wide(tester);
    final workflows = await manager();
    await tester.pumpWidget(_app('paper', WorkflowsPage(manager: workflows)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('workflow-background-button')));
    await tester.pumpAndSettle();
    expect(find.text('Run in the background'), findsOneWidget);

    Finder switchIn(String key) => find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(WorkflowSwitch),
        );

    await tester.tap(switchIn('workflow-pause-all'));
    await tester.pumpAndSettle();
    expect(workflows.store.settings.pausedAll, isTrue);

    if (Platform.isWindows) {
      expect(
        tester
            .widget<WorkflowSwitch>(switchIn('workflow-launch-at-login'))
            .onChanged,
        isNull,
        reason: 'starting with Windows only makes sense when kept running',
      );
      await tester.tap(switchIn('workflow-keep-running'));
      await tester.pumpAndSettle();
      expect(workflows.store.settings.keepRunningInBackground, isTrue);
      expect(
        tester
            .widget<WorkflowSwitch>(switchIn('workflow-launch-at-login'))
            .onChanged,
        isNotNull,
      );
    }

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Workflows are paused. Nothing runs on its own until you resume.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(workflows.store.settings.pausedAll, isFalse);
    expect(tester.takeException(), isNull);
  });
}

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Widget _app(String appearance, Widget child) => EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: _theme(appearance),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: child),
        ),
      ),
    );
