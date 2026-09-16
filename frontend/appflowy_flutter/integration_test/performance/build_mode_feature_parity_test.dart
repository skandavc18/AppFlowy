import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../../test/widget_test/build_mode_feature_parity_test.dart' as parity;

/// Standalone Windows fixture: Release has no VM service for flutter drive.
/// Run from the Flutter project root using tool/test_windows_feature_parity.ps1.
/// No normal AppFlowy startup or live user storage is used.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Windows can request accessibility when its first native window paints.
  // Request it before each WidgetTester records its handle baseline, rather
  // than counting the platform's new handle as a widget leak. Keep semantics
  // ON during every case; no lifecycle assertions are disabled.
  setUp(() {
    binding.platformDispatcher.semanticsEnabledTestValue = true;
  });
  tearDown(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  unawaited(_report(binding));
  parity.runBuildModeFeatureParityTests();
}

Future<void> _report(IntegrationTestWidgetsFlutterBinding binding) async {
  try {
    final passed = await binding.allTestsPassed.future;
    final results = binding.results.map(
      (name, result) => MapEntry(name, result.toString()),
    );
    final success = passed &&
        results.length == parity.buildModeFeatureParityCaseCount &&
        results.values.every((value) => value == 'success');
    const mode =
        kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');
    final output = File(
      p.join(
        Directory.current.path,
        'build',
        'performance',
        'build-mode-parity-$mode.json',
      ),
    );
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'mode': mode,
        'success': success,
        'caseCount': results.length,
        'results': results,
        'verifiedUtc': DateTime.now().toUtc().toIso8601String(),
        'scope': 'isolated functional parity; no live backend or user data',
      }),
      flush: true,
    );
    // Let the Windows runner release its engine/plugins on the platform
    // thread. dart:io exit() here can interrupt native plugin teardown.
    // The caller checks both the process exit and this report's success flag.
    await SystemNavigator.pop();
  } on Object catch (error, stack) {
    stderr.writeln('Could not complete native feature parity: $error\n$stack');
    await SystemNavigator.pop();
  }
}
