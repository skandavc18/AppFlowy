import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/widget/history_swipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart' show PdfViewer;
import 'package:window_manager/window_manager.dart';

// Real file renderers, but never AppFlowy startup, backend or live preferences.
// Run with WEBVIEW2_USER_DATA_FOLDER pointing to an isolated temporary profile.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'file viewers reload local and network images through history',
    (tester) async {
      expect(Platform.isWindows, isTrue);
      final profile = Platform.environment['WEBVIEW2_USER_DATA_FOLDER'];
      expect(
        profile,
        isNotNull,
        reason: 'An isolated WebView2 profile is required.',
      );
      expect(profile, contains('appflowy_file_history_'));
      final root =
          await Directory.systemTemp.createTemp('appflowy_file_history_');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        if (request.uri.path == '/missing.svg') {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.contentType =
              ContentType('image', 'svg+xml');
          request.response.write(_svg);
        }
        unawaited(request.response.close());
      });
      final asset = File('${root.path}/local image.svg');
      await asset.writeAsString(_svg);
      final markdown = File('${root.path}/README.md');
      await markdown.writeAsString(
        '# History image fixture\n\n'
        '![Local](local%20image.svg)\n\n'
        '![Network](http://127.0.0.1:${server.port}/remote.svg)\n\n'
        '![Unavailable](http://127.0.0.1:${server.port}/missing.svg)\n',
      );
      final text = File('${root.path}/another.txt');
      await text
          .writeAsString('An ordinary text file, not the Markdown document.');
      final html = File('${root.path}/page.html');
      await html.writeAsString('<h1>HTML image fixture</h1>'
          '<img src="local%20image.svg">'
          '<img src="http://127.0.0.1:${server.port}/remote.svg">'
          '<img src="http://127.0.0.1:${server.port}/missing.svg">');
      final csv = File('${root.path}/data.csv');
      await csv.writeAsString('Name,Value\nCSV row,42\n');
      final json = File('${root.path}/data.json');
      await json.writeAsString('{"message":"JSON content"}');
      final pdf = File('${root.path}/one-page.pdf');
      await pdf.writeAsBytes(_pdf());
      final files = [markdown, text, html, csv, json, pdf];
      final kinds = [
        FilePreviewKind.markdown,
        FilePreviewKind.text,
        FilePreviewKind.html,
        FilePreviewKind.csv,
        FilePreviewKind.json,
        FilePreviewKind.pdf,
      ];
      final page = ValueNotifier(0);
      final swipe = HistorySwipeController();
      final samples = <Map<String, dynamic>>[];
      binding.reportData = {
        'run': const String.fromEnvironment(
          'PERF_RUN',
          defaultValue: 'file_history',
        ),
        'samples': samples,
      };
      try {
        await windowManager.ensureInitialized();
        await windowManager.setSize(const Size(1100, 800));
        await windowManager.show();
        await tester.pumpWidget(
          MaterialApp(
            home: AppFlowyTheme(
              data: AppFlowyDefaultTheme().light(),
              child: Scaffold(
                body: PremiumScrollScope(
                  enabled: true,
                  child: ValueListenableBuilder(
                    valueListenable: page,
                    builder: (_, value, __) => HistorySwipeSurface(
                      controller: swipe,
                      pageKey: value,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: LayoutBuilder(
                          builder: (_, constraints) => FilePreview(
                            key: ValueKey(value),
                            file: files[value],
                            name: files[value].uri.pathSegments.last,
                            kind: kinds[value],
                            metadata: const {},
                            editable: false,
                            onMetadataChanged: (_) {},
                            height: constraints.maxHeight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (var visit = 0; visit < files.length; visit++) {
          final state = await _readyImages(tester);
          samples.add({'visit': visit, 'kind': 'markdown', ...state});
          expect(
            state['widths'],
            [80, 80, 0],
            reason:
                'Both local and valid network images must decode on every visit.',
          );
          expect(state['ready'], 'complete');
          if (visit == files.length - 1) break;
          final target = visit + 1;
          await _navigate(tester, swipe, page, target);
          if (kinds[target] == FilePreviewKind.html) {
            final htmlState = await _readyImages(tester);
            expect(htmlState['widths'], [80, 80, 0]);
            samples.add({'kind': 'html', ...htmlState});
          } else {
            await _readyFile(tester, kinds[target]);
            samples.add({'kind': kinds[target].name, 'ready': true});
          }
          await _navigate(tester, swipe, page, 0);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        swipe.dispose();
        page.dispose();
        await server.close(force: true);
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<Map<String, dynamic>> _readyImages(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 40));
    final textures = find.descendant(
      of: find.byType(FilePreview),
      matching: find.byType(Texture),
    );
    if (textures.evaluate().length != 1) continue;
    final id = tester.widget<Texture>(textures).textureId;
    // Native read-only probe; no second controller or channel handler replaces
    // the production FilePreview's own callbacks.
    final channel =
        MethodChannel('com.pichillilorenzo/flutter_inappwebview_$id');
    try {
      final raw = await channel.invokeMethod<String>('evaluateJavascript', {
        'source':
            '({ready: document.readyState, baseScheme: location.protocol, '
                'complete: Array.from(document.images, i => i.complete), '
                'widths: Array.from(document.images, i => i.naturalWidth)})',
      }).timeout(const Duration(seconds: 3));
      if (raw == null || raw == 'null') continue;
      last = jsonDecode(raw) as Map<String, dynamic>;
      final complete = last['complete'] as List;
      if (last['ready'] == 'complete' &&
          complete.length == 3 &&
          complete.every((value) => value == true)) {
        return last;
      }
    } on PlatformException {
      // Font loading can replace the initial renderer once. Query its current
      // texture on the next frame rather than a disposed native instance.
    }
  }
  throw StateError('The file viewer did not finish loading: $last');
}

Future<void> _navigate(
  WidgetTester tester,
  HistorySwipeController swipe,
  ValueNotifier<int> page,
  int target,
) async {
  swipe.begin(forward: target > 0, available: true, target: target);
  swipe.update(160);
  unawaited(
    swipe.finish(
      commit: true,
      isValid: () => true,
      navigate: () => page.value = target,
    ),
  );
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (swipe.isActive && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(swipe.isActive, isFalse);
  await tester.pumpAndSettle();
}

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40">'
    '<rect width="80" height="40" fill="#31758b"/></svg>';

Future<void> _readyFile(WidgetTester tester, FilePreviewKind kind) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 25));
    if (kind == FilePreviewKind.pdf) {
      final viewers = find.byType(PdfViewer);
      if (viewers.evaluate().length != 1) continue;
      final controller = tester.widget<PdfViewer>(viewers).controller;
      if (controller?.isReady == true) {
        expect(controller!.pageCount, 1);
        return;
      }
    } else if (kind == FilePreviewKind.csv) {
      if (find.text('CSV row').evaluate().isNotEmpty) return;
    } else {
      final text = kind == FilePreviewKind.json
          ? 'JSON content'
          : 'An ordinary text file';
      if (find
          .byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                (widget.textSpan?.toPlainText().contains(text) ?? false),
          )
          .evaluate()
          .isNotEmpty) {
        return;
      }
    }
  }
  throw StateError('The ${kind.name} renderer did not become ready');
}

List<int> _pdf() {
  const content = 'BT /F1 16 Tf 40 740 Td (Native file history fixture) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
  ];
  final text = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(text.length);
    text.write('${index + 1} 0 obj\n${objects[index]}\nendobj\n');
  }
  final xref = text.length;
  text.write('xref\n0 6\n0000000000 65535 f \n');
  for (final offset in offsets) {
    text.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  text.write('trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return utf8.encode(text.toString());
}
