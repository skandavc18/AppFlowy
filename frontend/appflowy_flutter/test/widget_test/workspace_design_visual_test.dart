import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_design_fixture.dart';

/// Generate references explicitly with --update-goldens, review every PNG, then
/// run again without that flag. Missing baselines must fail, never auto-approve.
/// Pin the Flutter SDK and Windows host for pixel comparisons; native captures
/// are separate review artifacts and are not interchangeable with these goldens.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = WorkspaceDesignEnvironment();
  setUpAll(environment.initialize);
  tearDownAll(environment.dispose);

  for (final scenario in workspaceDesignCases) {
    testWidgets(
      'workspace redesign ${scenario.id}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = scenario.viewport.size;
        addTearDown(tester.view.reset);
        final previousShadows = debugDisableShadows;
        // Elevation is part of this redesign, not something to omit in tests.
        debugDisableShadows = false;
        try {
          await tester.pumpWidget(
            WorkspaceDesignFixture(
              key: ValueKey(scenario.id),
              scenario: scenario,
            ),
          );
          await settleWorkspaceDesignFixture(tester);
          expectWorkspaceDesignFixture(tester, scenario);
          environment.expectOffline();
          await expectLater(
            find.byKey(workspaceDesignCaptureKey),
            matchesGoldenFile('goldens/workspace_design/${scenario.id}.png'),
          );
        } finally {
          try {
            // Dispose the borrowed controller and every widget before the
            // framework checks pending timers/tickers, including on failure.
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle(
              const Duration(milliseconds: 50),
              EnginePhase.sendSemanticsUpdate,
              const Duration(seconds: 10),
            );
          } finally {
            debugDisableShadows = previousShadows;
          }
        }
        expect(tester.takeException(), isNull);
        environment.expectOffline();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
