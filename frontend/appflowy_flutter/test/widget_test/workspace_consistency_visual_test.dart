import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_consistency_visual_fixture.dart';

/// Windows component goldens, not live-app screenshots. Uses bundled fonts
/// (Roboto Mono substituted for code) and system Segoe UI; no font download or
/// external font define. This does NOT verify JetBrains Mono typography.
/// Generate references explicitly with --update-goldens, review all three
/// sheets, then compare without that flag. Missing references must fail;
/// never set autoUpdateGoldenFiles or approve inside a test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = WorkspaceConsistencyEnvironment();
  WorkspaceConsistencyData? current;
  setUpAll(environment.initialize);
  tearDownAll(environment.dispose);
  setUp(() async {
    current = await environment.offline(WorkspaceConsistencyData.create);
  });
  tearDown(() async {
    final data = current;
    current = null;
    if (data != null) {
      // Fallback if setup/the body fails before entering its finally block.
      await data.close();
      await data.deleteFiles();
    }
  });

  for (final appearance in WorkspaceConsistencyAppearance.values) {
    testWidgets(
      'workspace consistency component review ${appearance.name}',
      (tester) async {
        final data = current!;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = workspaceConsistencySheetSize;
        addTearDown(tester.view.reset);
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        await environment.offline(() async {
          try {
            await prepareWorkspaceConsistencyFixture(tester, data);
            await tester.pumpWidget(
              WorkspaceConsistencyVisualFixture(
                appearance: appearance,
                data: data,
                environment: environment,
              ),
            );
            await settleWorkspaceConsistencyFixture(tester, data);
            expectWorkspaceConsistencyFixture(
              tester,
              appearance,
              data,
              environment,
            );
            await expectLater(
              find.byKey(workspaceConsistencyCaptureKey),
              matchesGoldenFile(
                'goldens/workspace_consistency/${workspaceConsistencyCaseId(appearance)}.png',
              ),
            );
          } finally {
            try {
              await unmountWorkspaceConsistencyFixture(tester);
              data.expectReadOnly(unmounted: true);
            } finally {
              await tester.runAsync(data.close);
              debugDisableShadows = previousShadows;
            }
          }
          expect(tester.takeException(), isNull);
          environment.expectOffline();
        });
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
