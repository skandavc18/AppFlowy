import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';
import 'workspace_identity_visual_fixture.dart';

// Source only in the scoped change: the coordinator must generate, inspect
// and approve these NEW baselines, then run their ordinary comparisons.
void main() {
  setUpAll(prepareVividIconTestAssets);
  for (final appearance in vividIconTestAppearances) {
    testWidgets('$appearance workspace identities visual reference',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 1150);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final mono = ValueNotifier(DefaultIconStyle.monochrome);
      final vivid = ValueNotifier(DefaultIconStyle.vivid);
      try {
        await tester.pumpWidget(
          vividIconTestApp(
            appearance,
            RepaintBoundary(
              key: const ValueKey('workspace-identities'),
              child: SizedBox.expand(
                child: WorkspaceIdentityVisualFixture(
                  monochrome: mono,
                  vivid: vivid,
                ),
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('workspace-identities')),
          matchesGoldenFile('goldens/workspace_identities_$appearance.png'),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        mono.dispose();
        vivid.dispose();
      }
    });
  }
}
