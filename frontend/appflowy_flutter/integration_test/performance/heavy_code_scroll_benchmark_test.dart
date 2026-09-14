import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/executable_code_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'javascript_sandbox_test.dart' as sandbox_checks;

// Offline fixture; deliberately does not use normal app/integration startup
// helpers, which can change the live workspace's SharedPreferences.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('trackpad over real editable code blocks', (tester) async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1280, 900));
    await windowManager.show();
    await binding.setSurfaceSize(const Size(1280, 800));
    binding.reportData = {
      'run': const String.fromEnvironment('PERF_RUN', defaultValue: 'heavy'),
      'mode': kProfileMode ? 'profile' : 'debug',
      'refresh_rate_hz': tester.view.display.refreshRate,
      'device_pixel_ratio': tester.view.devicePixelRatio,
      'fixture': '60 editable code blocks, 120 lines each, plus 120 paragraphs; '
          'auto/JavaScript/Python; custom page; all editor services enabled',
    };
    final editor = EditorState(document: _document());
    final scroll = EditorScrollController(editorState: editor);
    final built = <String>{};
    try {
      await binding.watchPerformance(
        () async {
          await tester.pumpWidget(_app(editor, scroll, built));
          await tester.pumpAndSettle();
        },
        reportKey: 'mount',
      ).timeout(const Duration(seconds: 90));
      binding.reportData!['initial_built_blocks'] = built.length;
      binding.reportData!['initial_code_widgets'] =
          find.byType(SandboxedCodeRunner).evaluate().length;
      final distances = <double>[];
      for (final pass in ['first', 'repeat']) {
        scroll.jumpToTop();
        await tester.pumpAndSettle();
        final before = scroll.offsetNotifier.value;
        await binding.watchPerformance(
          () async {
            // In the page margin, outside an inner code viewport/resize handle.
            final point = tester.getTopLeft(find.byType(AppFlowyEditor)) +
                const Offset(30, 280);
            await _pan(tester, point);
          },
          reportKey: '${pass}_trackpad_scroll',
        ).timeout(
          const Duration(seconds: 90),
        );
        final distance = scroll.offsetNotifier.value - before;
        distances.add(distance);
        expect(distance, greaterThan(1000));
      }
      binding.reportData!['page_scroll_distances'] = distances;
      binding.reportData!['total_built_blocks'] = built.length;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
      editor.dispose();
    }
  });
  // Exercise the native runtime only AFTER measuring scroll, so running a
  // script cannot warm a browser before the performance sample.
  sandbox_checks.main();
}

Document _document() => Document(
      root: pageNode(
        children: [
          for (var block = 0; block < 60; block++) ...[
            paragraphNode(
              text: 'Section $block: generated performance content',
            ),
            Node(
              type: CodeBlockKeys.type,
              attributes: {
                CodeBlockKeys.language: [
                  'auto',
                  'javascript',
                  'python',
                ][block % 3],
                codeBlockHeight: 280.0,
                codeBlockWidth: 760.0,
                'delta': [
                  {
                    'insert': List.generate(
                      120,
                      (line) => 'const section${block}Value$line = '
                          'calculate($line, "generated text");',
                    ).join('\n'),
                  },
                ],
              },
            ),
            paragraphNode(text: 'Continue reading section $block.'),
          ],
        ],
      ),
    );

Widget _app(
  EditorState editor,
  EditorScrollController scroll,
  Set<String> built,
) =>
    MaterialApp(
      theme: DesktopAppearance().getThemeData(
        AppTheme.fallback,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      home: AppFlowyTheme(
        data: AppFlowyDefaultTheme().light(),
        child: Scaffold(
          body: PremiumScrollScope(
            enabled: true,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppFlowyEditor(
                editorState: editor,
                editorScrollController: scroll,
                editorStyle: const EditorStyle.desktop(
                  maxWidth: 1000,
                  padding: EdgeInsets.symmetric(horizontal: 80),
                ),
                blockComponentBuilders: {
                  ...standardBlockComponentBuilderMap,
                  PageBlockKeys.type: CustomPageBlockComponentBuilder(),
                  CodeBlockKeys.type: ExecutableCodeBlockComponentBuilder(
                    baseStyleBuilder: () => CodeBlockStyle(
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontFamily: 'RobotoMono',
                      ),
                    ),
                    configuration: const BlockComponentConfiguration(),
                    padding: const EdgeInsets.all(8),
                  )..showActions = (_) => false,
                },
                contextMenuItems: const [],
                blockWrapper: (_, {required node, required child}) {
                  built.add(node.id);
                  return child;
                },
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _pan(WidgetTester tester, Offset point) async {
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(
      pointer: 95,
      device: 95,
      position: point,
    ),
  );
  for (var step = 1; step <= 300; step++) {
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 95,
        device: 95,
        position: point,
        pan: Offset(0, -48.0 * step),
        panDelta: const Offset(0, -48),
        timeStamp: Duration(microseconds: step * 8333),
      ),
    );
    await tester.pump(const Duration(microseconds: 8333));
  }
  await tester.sendEventToBinding(
    PointerPanZoomUpdateEvent(
      pointer: 95,
      device: 95,
      position: point,
      pan: const Offset(0, -14400),
      timeStamp: const Duration(seconds: 3),
    ),
  );
  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      pointer: 95,
      device: 95,
      position: point,
      timeStamp: const Duration(seconds: 3),
    ),
  );
  await tester.pumpAndSettle();
}
