import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'browser_reader_blocking_test.dart' as browser;
import 'file_webview_page_flow_test.dart' as file_flow;
import 'webview_site_gestures_test.dart' as gestures;

// Native entrypoint ONLY. No app main/shared integration startup, preferences,
// auth, saved workspace or default WebView profile. The compile wrapper imports
// this library without calling main. Native registration is otherwise generated
// by Flutter; the fallback below registers only the existing Dart implementation.
const _mode = kReleaseMode ? 'release' : 'debug';
const _expected = {
  'browser_reader_blocking',
  'webview_site_gestures',
  'file_webview_page_flow_html',
  'file_webview_page_flow_markdown',
  'file_webview_page_flow_email',
};

void main() {
  const output = String.fromEnvironment('BROWSER_SCROLL_OUTPUT_DIRECTORY');
  const run = String.fromEnvironment('BROWSER_SCROLL_RUN');
  if (!Platform.isWindows ||
      kProfileMode ||
      !const bool.fromEnvironment('BROWSER_SCROLL_NATIVE_CONSENT') ||
      !const bool.fromEnvironment('BROWSER_READER_BLOCKING_CONSENT') ||
      !const bool.fromEnvironment('WEBVIEW_SITE_GESTURES_CONSENT') ||
      !const bool.fromEnvironment('FILE_WEBVIEW_PAGE_FLOW_CONSENT') ||
      const bool.fromEnvironment(
          'INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE',
          defaultValue: true) ||
      !p.isAbsolute(output) ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(run)) {
    throw StateError('Requires isolated Windows Release/Debug, all consents, '
        'direct reporting, an absolute output directory and unique run label.');
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final started = DateTime.now().toUtc();
  final elapsed = Stopwatch()..start();
  final reports = <Map<String, dynamic>>[];
  setUpAll(() {
    if (InAppWebViewPlatform.instance == null) {
      WindowsInAppWebViewPlatform.registerWith();
    }
    expect(InAppWebViewPlatform.instance, isA<WindowsInAppWebViewPlatform>());
  });

  void register(String name, void Function() entrypoint) {
    group(name, () {
      setUp(() {
        binding.reportData = null;
        // A framework failure may precede a still-pending native cleanup.
        // Never start a second view while the previous owner is unproven.
        if (reports.any((report) => !_clean(report))) {
          throw StateError(
              'Previous fixture cleanup unproven; native execution fenced.');
        }
      });
      tearDown(() {
        // Retain the actual report before the next main overwrites reportData.
        // Do not stringify Failure objects or silently drop missing reports.
        final report = binding.reportData ??
            <String, dynamic>{
              'case': '$name:missing_${reports.length}',
              'measurement_complete': false,
              'cleanup_complete': false,
              'quiescent': false,
              'cleanup_stage': 'no_body_receipt_or_previous_cleanup_unproven',
            };
        report['body_finished_utc'] = DateTime.now().toUtc().toIso8601String();
        reports.add(report);
      });
      entrypoint();
    });
  }

  register('browser', browser.main);
  register('gestures', gestures.main);
  register('file_flow', file_flow.main);
  // Same direct-file mechanism as scroll_search_performance_test: the binding's
  // terminal future is the framework barrier, never "last test body returned".
  // Writer errors propagate; no catch converts a failure into a success receipt.
  unawaited(binding.allTestsPassed.future.then((passed) =>
      _writeReceipt(binding, reports, passed, output, run, started, elapsed)));
}

bool _clean(Map<String, dynamic> report) {
  final lifecycle = report['texture_lifecycle'];
  return report['cleanup_complete'] == true &&
      report['quiescent'] == true &&
      report['native_dispose_ack'] == true &&
      report['environment_dispose_ack'] == true &&
      report['remaining_transient_callbacks'] == 0 &&
      report['semantics_handles_before_body'] is int &&
      report['semantics_handles_before_body'] ==
          report['semantics_handles_after_body'] &&
      (!report.containsKey('remaining_held_ack_calls') ||
          report['remaining_held_ack_calls'] == 0) &&
      lifecycle is Map &&
      lifecycle['schema'] == 1 &&
      lifecycle['stages'] is List &&
      listEquals<dynamic>(
          lifecycle['stages'] as List, const [0, 1, 2, 3, 4, 5]);
}

Future<void> _writeReceipt(
  IntegrationTestWidgetsFlutterBinding binding,
  List<Map<String, dynamic>> reports,
  bool passed,
  String output,
  String run,
  DateTime started,
  Stopwatch elapsed,
) async {
  final cases = reports.map((report) => report['case']).toSet();
  final completeSet = reports.length == _expected.length &&
      cases.length == _expected.length &&
      cases.containsAll(_expected);
  final measured =
      completeSet && reports.every((r) => r['measurement_complete'] == true);
  final remaining = binding.transientCallbackCount;
  final cleaned = completeSet && reports.every(_clean) && remaining == 0;
  final failures =
      binding.failureMethodsDetails.length; // List<Failure>, not a string map.
  final report = <String, dynamic>{
    'schema': 1,
    'fixture_revision': 1,
    'run': run,
    'process_id': pid,
    'mode': _mode,
    'started_utc': started.toIso8601String(),
    'completed_utc': DateTime.now().toUtc().toIso8601String(),
    'elapsed_us': elapsed.elapsedMicroseconds,
    'expected_case_count': _expected.length,
    'case_count': reports.length,
    'framework_result_count': binding.results.length,
    'failed_test_count': failures,
    'measurement_complete': measured,
    'test_success': passed &&
        failures == 0 &&
        measured &&
        cleaned &&
        binding.results.length == _expected.length,
    'quiescent': cleaned,
    'cleanup_complete': cleaned,
    'remaining_transient_callbacks': remaining,
    'semantics_baselines_restored': completeSet &&
        reports.every((r) =>
            r['semantics_handles_before_body'] is int &&
            r['semantics_handles_before_body'] ==
                r['semantics_handles_after_body']),
    'native_dispose_ack_count':
        reports.where((r) => r['native_dispose_ack'] == true).length,
    'environment_dispose_ack_count':
        reports.where((r) => r['environment_dispose_ack'] == true).length,
    'unsafe_close_reasons': [
      if (!completeSet) 'missing_or_duplicate_case_receipts',
      if (remaining != 0) 'remaining_transient_callbacks',
      for (final r in reports)
        if (!_clean(r)) '${r['case']}:${r['cleanup_stage']}',
    ],
    'cases': reports,
    'scope': 'isolated WebView2 localhost blocking/Reader and native delivery; '
        'synthetic Flutter input, not OS hardware or live-site verification',
    'limitations': [
      'HTML, Markdown and email page flow only; no Office opaque-frame claim.',
      'Reader capture and local text roundtrip, not workspace offline persistence UI.',
      'No authentication, normal application startup, profiles or user data.',
      'Fixture bundles overwrite normal targets; main restores both normal bundles last.',
    ],
  };
  binding.reportData = report;
  final directory = Directory(output);
  await directory.create(recursive: true);
  final own = await directory.createTemp('browser_scroll_${_mode}_${pid}_');
  final json = File(p.join(own.path, 'report.json.tmp'));
  await json.writeAsString(const JsonEncoder.withIndent('  ').convert(report),
      flush: true);
  await json.rename(p.join(own.path, 'report.json'));
  final done = File(p.join(own.path, 'report.done.tmp'));
  await done.writeAsString('done', flush: true);
  await done.rename(p.join(own.path, 'report.done'));
  // DONE means reporting finished, NOT permission to close. The runner checks
  // cleanup, every native ACK, semantics and callbacks even when tests failed.
}
