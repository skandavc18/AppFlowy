import 'dart:convert';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

// Deliberately does NOT import the app's integration-test startup helpers:
// those change SharedPreferences and can redirect the user's live workspace.
// These fixtures need no backend, account, network, or real workspace data.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline large-page performance', (tester) async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1280, 900));
    await windowManager.show();
    await binding.setSurfaceSize(const Size(1280, 800));

    binding.reportData = {
      'run': const String.fromEnvironment('PERF_RUN', defaultValue: 'local'),
      'mode': kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug'),
      'viewport': {'width': 1280, 'height': 800},
      'device_pixel_ratio': tester.view.devicePixelRatio,
      'refresh_rate_hz': tester.view.display.refreshRate,
    };
    final measurements = <Map<String, Object>>[];
    var consumed = 0;

    for (final count in [100, 1000, 10000]) {
      final data = _documentData(count);
      measurements.add(
        _measure('document_conversion_$count', () {
          consumed += data.toDocument()!.root.children.length;
        }),
      );
    }

    for (final language in ['dart', 'auto']) {
      final code = List.generate(
        80,
        (index) => 'final value$index = calculate($index, "sample");',
      ).join('\n');
      measurements.add(
        _measure('highlight_${language}_10_reads', () {
          for (var read = 0; read < 10; read++) {
            consumed += buildSyntaxHighlightedTextSpan(
              code: code,
              language: language,
              brightness: Brightness.light,
            ).children!.length;
          }
        }),
      );
    }

    for (final count in [100, 1000, 10000]) {
      final album = AlbumController(initialState: const {}, onPersist: (_) {});
      album.setItems(
        List.generate(
          count,
          (index) => AlbumMediaItem(
            view: ViewPB(id: '$index', name: 'Media $index'),
            kind: AlbumMediaKind.values[index % AlbumMediaKind.values.length],
            path: '',
            index: index,
          ),
        ),
      );
      measurements.add(
        _measure('album_${count}_100_reads', () {
          for (var read = 0; read < 100; read++) {
            consumed += album.visual.length +
                album.playable.length +
                album.imageCount +
                album.videoCount +
                album.audioCount;
          }
        }),
      );
      album.dispose();
    }
    expect(consumed, greaterThan(0));
    binding.reportData!['microbenchmarks'] = measurements;

    final mounts = <Map<String, Object>>[];
    for (final shrinkWrap in [false, true]) {
      const count = 2000;
      final editor = EditorState(document: _documentData(count).toDocument()!);
      final scroll = EditorScrollController(
        editorState: editor,
        shrinkWrap: shrinkWrap,
      );
      final built = <String>{};
      final label = shrinkWrap ? 'eager' : 'virtualized';
      var mountMicros = 0;
      try {
        await binding.watchPerformance(
          () async {
            final clock = Stopwatch()..start();
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: PremiumScrollScope(
                    enabled: true,
                    child: Center(
                      child: SizedBox(
                        width: 900,
                        height: 700,
                        child: AppFlowyEditor(
                          editorState: editor,
                          editorScrollController: scroll,
                          editable: false,
                          disableSelectionService: true,
                          disableKeyboardService: true,
                          disableAutoScroll: true,
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
              ),
            );
            clock.stop();
            mountMicros = clock.elapsedMicroseconds;
            await tester.pumpAndSettle();
          },
          reportKey: '${label}_mount_frames',
        ).timeout(const Duration(seconds: 60));
        mounts.add({
          'layout': label,
          'total_blocks': count,
          'initial_built_blocks': built.length,
          'pump_to_first_frame_us': mountMicros,
        });
        if (!shrinkWrap) {
          expect(built.length, lessThan(count ~/ 10));
          for (final pass in ['first', 'repeat']) {
            scroll.jumpToTop();
            await tester.pumpAndSettle();
            await binding.watchPerformance(
              () async {
                final position = tester.getCenter(find.byType(AppFlowyEditor));
                for (var packet = 0; packet < 120; packet++) {
                  await tester.sendEventToBinding(
                    PointerScrollEvent(
                      position: position,
                      scrollDelta: const Offset(0, 40),
                    ),
                  );
                  await tester.pump(const Duration(milliseconds: 16));
                }
                await tester.pumpAndSettle();
              },
              reportKey: '${label}_${pass}_scroll_frames',
            ).timeout(const Duration(seconds: 60));
          }
        } else {
          expect(built.length, count);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        scroll.dispose();
        editor.dispose();
      }
    }
    binding.reportData!['mounts'] = mounts;
    debugPrint('PERFORMANCE_MICROBENCHMARKS ${jsonEncode(measurements)}');
    debugPrint('PERFORMANCE_MOUNTS ${jsonEncode(mounts)}');
  });
}

// Warm once, then retain every sample; time thresholds are intentionally not
// assertions because machine load and instrumentation change wall-clock time.
Map<String, Object> _measure(String name, VoidCallback action) {
  action();
  final samples = <int>[];
  for (var sample = 0; sample < 7; sample++) {
    final clock = Stopwatch()..start();
    action();
    clock.stop();
    samples.add(clock.elapsedMicroseconds);
  }
  final sorted = [...samples]..sort();
  return {
    'name': name,
    'median_us': sorted[sorted.length ~/ 2],
    'samples_us': samples,
  };
}

DocumentDataPB _documentData(int count) {
  const text = 'A generated paragraph for measuring long documents. '
      'No workspace content or remote resources are used.\n';
  final attributes = jsonEncode({
    'delta': [
      {'insert': text},
    ],
  });
  return DocumentDataPB(
    pageId: 'benchmark-page',
    blocks: {
      'benchmark-page': BlockPB(
        id: 'benchmark-page',
        ty: 'page',
        childrenId: 'children',
        data: '{}',
      ),
      for (var index = 0; index < count; index++)
        'block-$index': BlockPB(
          id: 'block-$index',
          ty: 'paragraph',
          parentId: 'benchmark-page',
          childrenId: 'children-$index',
          data: attributes,
        ),
    },
    meta: MetaPB(
      childrenMap: {
        'children': ChildrenPB(
          children: List.generate(count, (index) => 'block-$index'),
        ),
      },
    ),
  );
}
