import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../../test/widget_test/workspace_consistency_visual_fixture.dart';

/// Separate opt-in Windows entrypoint. Never imports main.dart/shared/base.dart,
/// boots a workspace, opens preferences or touches the installed user's data.
/// Captures are native-process Flutter repaint boundaries, NOT OS screenshots.
/// The widget and native entrypoints share all models, renderers and checks.
/// Code uses bundled Roboto Mono aliases, NOT verified JetBrains Mono; the
/// manifest records that substitution and the actual resolved theme families.
void main() {
  const enabled = bool.fromEnvironment('WORKSPACE_CONSISTENCY_FIXTURE');
  const projectRoot =
      String.fromEnvironment('WORKSPACE_CONSISTENCY_PROJECT_ROOT');
  if (!enabled ||
      !Platform.isWindows ||
      !p.isAbsolute(projectRoot) ||
      !File(p.join(projectRoot, 'pubspec.yaml')).existsSync() ||
      !File(
        p.join(
          projectRoot,
          'test',
          'widget_test',
          'workspace_consistency_visual_fixture.dart',
        ),
      ).existsSync()) {
    throw StateError(
      'Offline component capture requires Windows, '
      'WORKSPACE_CONSISTENCY_FIXTURE=true and an absolute '
      'WORKSPACE_CONSISTENCY_PROJECT_ROOT pointing to appflowy_flutter.',
    );
  }

  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final environment = WorkspaceConsistencyEnvironment();
  WorkspaceConsistencyData? current;
  setUpAll(environment.initialize);
  tearDownAll(environment.dispose);
  setUp(() async {
    binding.platformDispatcher.semanticsEnabledTestValue = true;
    current = await environment.offline(WorkspaceConsistencyData.create);
  });
  tearDown(() async {
    binding.platformDispatcher.clearSemanticsEnabledTestValue();
    final data = current;
    current = null;
    if (data != null) {
      await data.close();
      await data.deleteFiles();
    }
  });

  testWidgets(
    'offline workspace consistency native component captures',
    (tester) async {
      final data = current!;
      await environment.offline(() async {
        final root = await Directory(
          p.join(
            projectRoot,
            'build',
            'performance',
            'workspace-consistency',
          ),
        ).create(recursive: true);
        final output = await root.createTemp('run-');
        final startedAt = DateTime.now().toUtc().toIso8601String();
        final captures = <Map<String, Object>>[];
        final previousShadows = debugDisableShadows;
        debugDisableShadows = false;
        var complete = false;
        try {
          await binding.setSurfaceSize(workspaceConsistencySheetSize);
          await prepareWorkspaceConsistencyFixture(tester, data);
          for (final appearance in WorkspaceConsistencyAppearance.values) {
            runApp(
              WorkspaceConsistencyVisualFixture(
                key: ValueKey(appearance),
                appearance: appearance,
                data: data,
                environment: environment,
              ),
            );
            await tester.pump();
            await settleWorkspaceConsistencyFixture(tester, data);
            expectWorkspaceConsistencyFixture(
              tester,
              appearance,
              data,
              environment,
            );

            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(workspaceConsistencyCaptureKey),
            );
            final image = await boundary.toImage();
            try {
              expect(image.width, workspaceConsistencySheetSize.width.toInt());
              expect(
                image.height,
                workspaceConsistencySheetSize.height.toInt(),
              );
              final png =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              if (png == null) {
                throw StateError(
                  'Component capture could not encode PNG pixels',
                );
              }
              final bytes =
                  png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
              expect(
                bytes.take(8),
                orderedEquals(const [137, 80, 78, 71, 13, 10, 26, 10]),
              );
              expect(tester.takeException(), isNull);
              environment.expectOffline();
              final name = '${workspaceConsistencyCaseId(appearance)}.png';
              await File(p.join(output.path, name))
                  .writeAsBytes(bytes, flush: true);
              captures.add({
                'file': name,
                'appearance': appearance.name,
                'resolvedThemeFontFamily':
                    environment.resolvedThemeFamilies[appearance.name]!,
                'iconStyles': ['monochrome', 'vivid'],
                'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
                'pixelWidth': image.width,
                'pixelHeight': image.height,
                'bytes': bytes.length,
                'backend': 'flutter-repaint-boundary',
              });
            } finally {
              image.dispose();
            }
            await unmountWorkspaceConsistencyFixture(tester);
            // The same fixed, read-only data can be reviewed in the next theme;
            // widgets/listeners are recreated, controllers are still test-owned.
            data.finishCapture();
          }
          complete =
              captures.length == WorkspaceConsistencyAppearance.values.length;
          expect(complete, isTrue);
        } finally {
          try {
            await unmountWorkspaceConsistencyFixture(tester);
          } finally {
            await tester.runAsync(data.close);
            await binding.setSurfaceSize(null);
            debugDisableShadows = previousShadows;
            final manifest = <String, Object>{
              'fixture': 'workspace-consistency-component-review',
              'startedAtUtc': startedAt,
              'finishedAtUtc': DateTime.now().toUtc().toIso8601String(),
              'capturesComplete': complete,
              'expectedCaptures': WorkspaceConsistencyAppearance.values.length,
              'httpClientAttempts': environment.httpClientAttempts,
              'fonts': environment.fonts,
              'resolvedThemeFontFamilies': environment.resolvedThemeFamilies,
              'codeFontSubstitution': environment.codeFontSubstitution,
              'captures': captures,
              'scope': 'Offline component review, not the live app. Real settings, '
                  'calendar, JPEG/code renderers, collection/schema and tab chrome. '
                  'Synthetic data/IO; no native database grid, shell startup, '
                  'caption controls, editing, OCR or code execution. Bundled '
                  'Roboto Mono replaces JetBrains Mono for code geometry/color '
                  'review; JetBrains Mono typography is not verified.',
              'result': 'Capture inventory only; use the test result for success '
                  'and visually review the PNGs separately. Not golden references.',
            };
            binding.reportData = manifest;
            await File(p.join(output.path, 'manifest.json')).writeAsString(
              const JsonEncoder.withIndent('  ').convert(manifest),
              flush: true,
            );
          }
        }
        expect(tester.takeException(), isNull);
        environment.expectOffline();
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
