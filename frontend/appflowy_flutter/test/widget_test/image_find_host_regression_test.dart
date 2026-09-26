import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/native_find_test_input.dart';
import 'file_controls_test_support.dart';
import 'image_ocr_test_support.dart';

void main() => runImageFindHostRegressions();

// Shared with the opt-in native Release fixture. No normal AppFlowy boot,
// shared preferences, user files, backend writes or clipboard actions.
void runImageFindHostRegressions() {
  fileControlTestSetup();
  late Directory directory;
  late File file;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('image-find-host-');
    file = await File('${directory.path}/synthetic.png')
        .writeAsBytes(await makeOcrTestPng());
  });
  tearDownAll(() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await directory.delete(recursive: true);
  });

  for (final host in ['page', 'standalone', 'fullscreen']) {
    for (final navigationFocus in [false, true]) {
      for (final hover in [false, true]) {
        testWidgets(
          '$host: image Find with navigation focus=$navigationFocus hover=$hover',
          (tester) async {
            final service = ControlledOcrService();
            final navigation = FocusNode(debugLabel: 'Workspace navigation');
            final editor = EditorState(
              document: Document(
                root: pageNode(
                  children: [
                    paragraphNode(text: 'Page body before image'),
                    customImageNode(url: file.path, width: 320, height: 180),
                    paragraphNode(text: 'Page body after image'),
                  ],
                ),
              ),
            )..disableSealTimer = true;
            final backend = FileControlBackend(
              fileControlView('synthetic-image', 'synthetic.png', file.path),
              file,
            );
            final mouse =
                await tester.createGesture(kind: PointerDeviceKind.mouse);
            var pageFinds = 0;
            try {
              await mouse.addPointer(location: Offset.zero);
              final Widget content;
              if (host == 'page') {
                content = ContextualFindRegion(
                  onFind: () => pageFinds++,
                  child: AppFlowyEditor(
                    editorState: editor,
                    editorStyle: const EditorStyle.desktop(
                      padding: EdgeInsets.all(16),
                    ),
                    blockComponentBuilders: {
                      ...standardBlockComponentBuilderMap,
                      CustomImageBlockKeys.type:
                          CustomImageBlockComponentBuilder(
                        ocrService: service,
                      ),
                    },
                  ),
                );
              } else if (host == 'standalone') {
                content = WorkspaceFileView(
                  view: backend.stored,
                  repository: backend,
                  resolveStorageUrl: backend.resolve,
                  materializeFile: backend.materialize,
                  iconListenerFactory: backend.listen,
                  mediaActions: backend.media,
                  coverBackend: backend.covers,
                  updateIcon: backend.writeIcon,
                  writeExtra: backend.writeExtra,
                  ocrService: service,
                );
              } else {
                content = InteractiveImageViewer(
                  imageProvider: AFBlockImageProvider(
                    images: [
                      ImageBlockData(
                        url: file.path,
                        type: CustomImageType.local,
                      ),
                    ],
                  ),
                  ocrService: service,
                );
              }
              await mountFileControls(
                tester,
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextButton(
                        focusNode: navigation,
                        onPressed: () {},
                        child: const Text('Image navigation'),
                      ),
                    ),
                    Expanded(child: ContextualFindScope(child: content)),
                  ],
                ),
                mode: 'paper',
                width: 1000,
                reduced: true,
              );
              final target = find.byType(ImageOcrFindRegion);
              for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
                await tester.runAsync(() => Future<void>(() {}));
                await tester.pump();
              }
              expect(target, findsOneWidget);
              // Decode native FileImage before testing bounds; no fake source
              // subclass and no synthetic ancestor content Focus surrounds it.
              final images =
                  find.descendant(of: target, matching: find.byType(Image));
              for (var i = 0; i < 100; i++) {
                final raw = find.descendant(
                  of: images,
                  matching: find.byType(RawImage),
                );
                if (raw.evaluate().isNotEmpty &&
                    tester.widget<RawImage>(raw.first).image != null) {
                  break;
                }
                await tester.runAsync(() => Future<void>(() {}));
                await tester.pump();
              }
              final imageElement = tester.element(target);
              final before = editor.document.toJson();
              if (navigationFocus) {
                navigation.requestFocus();
                await tester.pump();
                expect(navigation.hasPrimaryFocus, isTrue);
              }
              final oldFocus = FocusManager.instance.primaryFocus;
              if (hover) await mouse.moveTo(tester.getCenter(target));
              await tester.pump();
              expect(FocusManager.instance.primaryFocus, same(oldFocus));
              // Explicit physical keys in widget tests; real Windows input in
              // the opt-in native fixture, without clicking the content first.
              await sendFindTestShortcut(tester);
              await tester.pump();
              await tester.pump();
              if (host == 'page' && !hover) {
                // With no image intent, an untouched document searches the page.
                // Hovering the image then chooses OCR without a focus/caret tap.
                expect(pageFinds, 1);
                expect(find.byType(ImageOcrOverlay), findsNothing);
                await mouse.moveTo(tester.getCenter(target));
                await tester.pump();
                expect(FocusManager.instance.primaryFocus, same(oldFocus));
                await sendFindTestShortcut(tester);
                await tester.pump();
                await tester.pump();
              }
              expect(find.byType(ImageOcrOverlay), findsOneWidget);
              expect(pageFinds, host == 'page' && !hover ? 1 : 0);
              await waitForOcrCalls(tester, service, 1);
              service.calls.single.done.complete(ocrTestResult());
              await tester.enterText(
                find.byKey(const ValueKey('findTextField')),
                'HELLO',
              );
              await tester.pump();
              expect(
                tester
                    .widget<FindReplaceBar>(find.byType(FindReplaceBar))
                    .matchCount,
                2,
              );
              expect(tester.element(target), same(imageElement));
              expect(editor.document.toJson(), before);
              expect(backend.extraWrites, isEmpty);
              expect(backend.renames, isEmpty);
              await tester.sendKeyEvent(
                LogicalKeyboardKey.escape,
                physicalKey: PhysicalKeyboardKey.escape,
              );
              await settleFileControls(tester);
              expect(find.byType(ImageOcrOverlay), findsNothing);
            } finally {
              await mouse.removePointer();
              await unmountFileControls(tester);
              service.finishPending();
              await tester.pump();
              if (!editor.isDisposed) editor.dispose();
              editor.editableNotifier.dispose();
              navigation.dispose();
              expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
            }
          },
          timeout: const Timeout(Duration(seconds: 30)),
        );
      }
    }
  }
}
