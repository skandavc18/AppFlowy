import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) {
          return;
        }
        final run = (data['run'] as String? ?? 'local')
            .replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
        final directory = Directory('build/performance');
        await directory.create(recursive: true);
        final file = File('${directory.path}/large_page_$run.json');
        await file
            .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
        // Only synthetic measurements, never content, credentials, or view ids.
        // ignore: avoid_print
        print('Performance report: ${file.path}');
      },
    );
