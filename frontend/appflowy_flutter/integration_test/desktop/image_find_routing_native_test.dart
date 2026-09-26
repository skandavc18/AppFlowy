import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../../test/widget_test/active_page_find_host_regression_test.dart'
    as pages;
import '../../test/widget_test/database_find_host_test.dart' as database;
import '../../test/widget_test/image_find_host_regression_test.dart' as routing;

/// Opt-in synthetic image hosts, never the normal app or integration shared-base.
void main() {
  const root = String.fromEnvironment('IMAGE_FIND_PROJECT_ROOT');
  if (!const bool.fromEnvironment('IMAGE_FIND_FIXTURE') ||
      !Platform.isWindows ||
      !p.isAbsolute(root) ||
      !File(p.join(root, 'pubspec.yaml')).existsSync()) {
    throw StateError('Requires Windows and explicit IMAGE_FIND_FIXTURE/root.');
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.semanticsEnabledTestValue = true;
    binding.testTextInput.register();
  });
  tearDown(() {
    binding.platformDispatcher.clearSemanticsEnabledTestValue();
    binding.testTextInput.unregister();
  });
  unawaited(_report(binding, root));
  routing.runImageFindHostRegressions();
  pages.runActivePageFindHostRegressions();
  database.main();
}

Future<void> _report(
  IntegrationTestWidgetsFlutterBinding binding,
  String root,
) async {
  final passed = await binding.allTestsPassed.future;
  final results = binding.results.map(
    (name, result) => MapEntry(name, result.toString()),
  );
  const mode = kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');
  const osFindKeys = bool.fromEnvironment('IMAGE_FIND_OS_KEYS');
  const inputSuffix = osFindKeys ? '' : '-flutter-keys';
  final output = File(
    p.join(root, 'build/performance/image-find-native-$mode$inputSuffix.json'),
  );
  await output.parent.create(recursive: true);
  await output.writeAsString(
    jsonEncode({
      'mode': mode,
      'success':
          passed && results.values.every((result) => result == 'success'),
      'results': results,
      'verifiedUtc': DateTime.now().toUtc().toIso8601String(),
      'osFindKeys': osFindKeys,
      'scope':
          'synthetic real image/document/folder/collection/database Find hosts; '
              'injected OCR/native-data boundaries; '
              '${osFindKeys ? 'guarded Windows Ctrl+F input' : 'Flutter key events only, NOT OS input verification'}',
    }),
    flush: true,
  );
  await SystemNavigator.pop();
}
