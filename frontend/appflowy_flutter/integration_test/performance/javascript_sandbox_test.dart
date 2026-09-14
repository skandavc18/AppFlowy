import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('JavaScript runs on the first click and can run again',
      (tester) async {
    await tester
        .pumpWidget(_app('console.log("sandbox-ready"); return 6 * 7;'));
    expect(find.byType(InAppWebView), findsNothing);
    for (var run = 0; run < 2; run++) {
      await tester.tap(find.byTooltip('Run'));
      await tester.pump();
      await _waitForRunButton(tester);
      final transcript = _transcript(tester);
      expect(transcript, contains('sandbox-ready\n42\n'));
      expect(transcript, isNot(contains('Try again')));
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stopping lazy startup never publishes a late answer',
      (tester) async {
    await tester.pumpWidget(
      _app(
        'return await new Promise(resolve => setTimeout(() => resolve("late-answer"), 2000));',
      ),
    );
    await tester.tap(find.byTooltip('Run'));
    await tester.pump();
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump();
    await _waitForRunButton(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(_transcript(tester), contains('Execution stopped.'));
    expect(_transcript(tester), isNot(contains('late-answer')));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _app(String code) => MaterialApp(
      home: AppFlowyTheme(
        data: AppFlowyDefaultTheme().light(),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 640,
              height: 540,
              child: SandboxedCodeRunner(
                code: code,
                fileName: 'main.js',
                language: 'javascript',
                showLineNumbers: true,
                onLanguageChanged: (_) {},
                onToggleLineNumbers: () {},
                child: const SizedBox(height: 60),
              ),
            ),
          ),
        ),
      ),
    );

String _transcript(WidgetTester tester) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .map((text) => text.textSpan?.toPlainText() ?? text.data ?? '')
    .join();

Future<void> _waitForRunButton(WidgetTester tester) async {
  final clock = Stopwatch()..start();
  while (find.byTooltip('Stop').evaluate().isNotEmpty &&
      clock.elapsed < const Duration(seconds: 25)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byTooltip('Stop'), findsNothing);
  expect(find.byTooltip('Run'), findsOneWidget);
}
