import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../../test/widget_test/workspace_design_fixture.dart';

/// Offline Windows entrypoint, never normal AppFlowy startup or shared/base.dart.
/// Required defines: WORKSPACE_DESIGN_FIXTURE=true and an absolute Flutter
/// project root in WORKSPACE_DESIGN_PROJECT_ROOT. The explicit root avoids the
/// native runner's working directory determining where screenshots are written.
/// Only build/performance/workspace-design/run-* is written; no user data or
/// app preferences are opened. The Flutter test runner owns process shutdown.
void main() {
  const enabled = bool.fromEnvironment('WORKSPACE_DESIGN_FIXTURE');
  const projectRoot = String.fromEnvironment('WORKSPACE_DESIGN_PROJECT_ROOT');
  if (!enabled || !Platform.isWindows || !p.isAbsolute(projectRoot)) {
    throw StateError(
      'This offline Windows fixture requires WORKSPACE_DESIGN_FIXTURE=true '
      'and an absolute WORKSPACE_DESIGN_PROJECT_ROOT.',
    );
  }
  if (!File(p.join(projectRoot, 'pubspec.yaml')).existsSync() ||
      !File(
        p.join(
          projectRoot,
          'test',
          'widget_test',
          'workspace_design_fixture.dart',
        ),
      ).existsSync()) {
    throw StateError(
      'WORKSPACE_DESIGN_PROJECT_ROOT is not the Flutter project.',
    );
  }

  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final environment = WorkspaceDesignEnvironment();
  setUpAll(environment.initialize);
  tearDownAll(environment.dispose);
  // Same accessibility-baseline precaution as the existing native parity test.
  // Keep semantics on; do not turn off lifecycle or leak assertions.
  setUp(() => binding.platformDispatcher.semanticsEnabledTestValue = true);
  tearDown(binding.platformDispatcher.clearSemanticsEnabledTestValue);

  testWidgets(
    'offline workspace redesign native captures',
    (tester) async {
      final root = Directory(
        p.join(projectRoot, 'build', 'performance', 'workspace-design'),
      );
      await root.create(recursive: true);
      // A fresh directory prevents stale screenshots being mistaken for this run.
      final output = await root.createTemp('run-');
      final captures = <Map<String, Object>>[];
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      var capturesComplete = false;
      try {
        for (final scenario in workspaceDesignCases) {
          await binding.setSurfaceSize(scenario.viewport.size);
          // Mount exactly the golden fixture, NOT the application's main().
          runApp(
            WorkspaceDesignFixture(
              key: ValueKey(scenario.id),
              scenario: scenario,
            ),
          );
          await tester.pump();
          await settleWorkspaceDesignFixture(tester);
          expectWorkspaceDesignFixture(tester, scenario);
          environment.expectOffline();

          final capture = await _takeScreenshot(binding, tester, scenario.id);
          expect(capture.bytes.length, greaterThan(24));
          expect(
            capture.bytes.take(8),
            orderedEquals(const [137, 80, 78, 71, 13, 10, 26, 10]),
            reason: 'A screenshot must contain encoded PNG pixels.',
          );
          final header =
              ByteData.sublistView(Uint8List.fromList(capture.bytes));
          final pixelWidth = header.getUint32(16);
          final pixelHeight = header.getUint32(20);
          expect(pixelWidth, greaterThan(0));
          expect(pixelHeight, greaterThan(0));
          if (capture.backend == 'flutter-repaint-boundary') {
            expect(pixelWidth, scenario.viewport.size.width.toInt());
            expect(pixelHeight, scenario.viewport.size.height.toInt());
          }
          final file = File(p.join(output.path, '${scenario.id}.png'));
          await file.writeAsBytes(capture.bytes, flush: true);
          captures.add({
            'case': scenario.id,
            'file': p.basename(file.path),
            'backend': capture.backend,
            'logicalWidth': scenario.viewport.size.width,
            'logicalHeight': scenario.viewport.size.height,
            'pixelWidth': pixelWidth,
            'pixelHeight': pixelHeight,
            'bytes': capture.bytes.length,
          });
          // PNGs are on disk. Do not retain/transfer every image in reportData.
          binding.reportData?.remove('screenshots');
          expect(tester.takeException(), isNull);

          runApp(const SizedBox.shrink());
          await tester.pumpAndSettle(
            const Duration(milliseconds: 50),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 10),
          );
          expect(tester.takeException(), isNull);
          environment.expectOffline();
        }
        expect(captures.length, workspaceDesignCases.length);
        capturesComplete = true;
      } finally {
        try {
          runApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await binding.setSurfaceSize(null);
        } finally {
          debugDisableShadows = previousShadows;
          final report = <String, Object>{
            'fixture': 'workspace-design',
            'capturesComplete': capturesComplete,
            'expectedCaptures': workspaceDesignCases.length,
            'httpClientAttempts': environment.httpClientAttempts,
            'directory': output.path,
            'captures': captures,
            'scope': 'Offline presentation only; not app startup, navigation, '
                'editing, persistence, backend, or native caption controls.',
            'result': 'Capture inventory only. Consult the integration test '
                'result for test success; visually review PNGs separately.',
          };
          binding.reportData = report;
          await File(p.join(output.path, 'manifest.json')).writeAsString(
            const JsonEncoder.withIndent('  ').convert(report),
            flush: true,
          );
        }
      }
      expect(tester.takeException(), isNull);
      environment.expectOffline();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<({List<int> bytes, String backend})> _takeScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  try {
    final bytes =
        await binding.takeScreenshot(name).timeout(const Duration(seconds: 20));
    return (bytes: bytes, backend: 'integration-test-plugin');
  } on MissingPluginException {
    // Flutter 3.27's IO binding delegates captureScreenshot to a native plugin;
    // Windows runners need not implement it. Capture the actual rendered frame
    // instead, as the existing offline viewer harness does. This is NOT an OS
    // window screenshot. Other capture errors/timeouts must fail, not fall back.
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(workspaceDesignCaptureKey),
    );
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('The fixture frame could not be encoded.');
      }
      return (
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        backend: 'flutter-repaint-boundary',
      );
    } finally {
      image.dispose();
    }
  }
}
