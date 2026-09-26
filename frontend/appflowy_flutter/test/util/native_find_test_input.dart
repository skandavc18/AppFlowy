import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Native Release already runs on Windows; platform overrides are debug-only.
/// Explicit returns avoid the conditional expression's void-variant type join.
TestVariant<Object?> get findTestPlatformVariant {
  if (kDebugMode) {
    return TargetPlatformVariant.only(TargetPlatform.windows);
  }
  return const DefaultTestVariant();
}

/// Ordinary widget tests use Flutter keys. The opt-in Windows fixture sends the
/// same chord through Windows to THIS process, never a pre-existing user app.
Future<void> sendFindTestShortcut(WidgetTester tester) async {
  if (!const bool.fromEnvironment('IMAGE_FIND_OS_KEYS')) {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.controlLeft,
      physicalKey: PhysicalKeyboardKey.controlLeft,
    );
    try {
      await tester.sendKeyEvent(
        LogicalKeyboardKey.keyF,
        physicalKey: PhysicalKeyboardKey.keyF,
      );
    } finally {
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
    }
    return;
  }

  const root = String.fromEnvironment('IMAGE_FIND_PROJECT_ROOT');
  if (!Platform.isWindows ||
      !const bool.fromEnvironment('IMAGE_FIND_FIXTURE') ||
      !p.isAbsolute(root)) {
    throw StateError('OS input requires the explicit Windows Find fixture.');
  }
  final script = File(p.join(root, 'tool/inspect_workspace_window.ps1'));
  if (!script.existsSync()) throw StateError('Missing guarded window helper.');
  await tester.runAsync(() async {
    // The existing helper verifies ProcessId, AppFlowy executable name and
    // foreground HWND before SendWait; it never clicks, sleeps or closes apps.
    final process = await Process.start('pwsh.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-File',
      script.path,
      '-ProcessId',
      '$pid',
      '-OutputPath',
      p.join(root, 'build/performance/native-find-os-input.png'),
      '-Keys',
      '^f',
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      final result =
          await process.exitCode.timeout(const Duration(seconds: 12));
      final captured = await output;
      final failure = await errors;
      if (result != 0) {
        throw StateError(
          'Guarded native Find input failed: $captured\n$failure',
        );
      }
    } finally {
      // Only the helper spawned by this test, never the app or another shell.
      process.kill();
    }
  });
}
