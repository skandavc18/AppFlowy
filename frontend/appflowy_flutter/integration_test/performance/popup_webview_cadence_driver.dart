import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) throw StateError('Missing cadence report.');
        final run = (data['run'] as String? ?? 'baseline')
            .replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
        final directory = Directory('build/performance');
        await directory.create(recursive: true);
        await File('${directory.path}/popup_webview_cadence_$run.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
        // Deliberately do not print paths, page content, or native view IDs.
      },
    );
