import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('build mode must not select application features', () {
    // These exceptions affect diagnostics, test infrastructure, or legacy
    // profile isolation, never the availability of an application feature.
    const allowed = {
      'plugins/database/widgets/cell/card_cell_skeleton/text_card_cell.dart',
      'plugins/document/application/document_bloc.dart',
      'startup/startup.dart',
      'startup/tasks/debug_task.dart',
      'startup/tasks/generate_router.dart',
      'startup/tasks/memory_leak_detector.dart',
      'startup/tasks/platform_error_catcher.dart',
      'startup/tasks/rust_sdk.dart',
      'util/string_extension.dart',
      'workspace/presentation/widgets/float_bubble/version_section.dart',
    };
    final modeCheck = RegExp(
      r'\bk(?:Debug|Profile|Release)Mode\b|'
      r'\bdart\.vm\.(?:product|profile)\b|'
      r'\.\s*is(?:Develop|Release)\b|'
      r'\bIntegrationMode\.(?:develop|release)\b',
    );
    final violations = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final relative = p.relative(file.path, from: 'lib').replaceAll('\\', '/');
      if (allowed.contains(relative)) continue;
      if (modeCheck.hasMatch(file.readAsStringSync())) {
        violations.add(relative);
      }
    }
    violations.sort();
    expect(
      violations,
      isEmpty,
      reason: 'Use the same capabilities, preferences and server/account '
          'checks in Debug, Profile and Release. Do not hide functional '
          'features behind compiler mode checks.',
    );
  });
}
