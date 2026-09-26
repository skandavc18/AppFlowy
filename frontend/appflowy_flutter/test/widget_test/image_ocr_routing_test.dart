import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/multi_image_block_component/multi_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_result.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'image_ocr_test_support.dart';

// Actual editor/block builders/gallery layouts/photo viewer and native key
// dispatch. Only OCR and its byte reader are injected. The rendered photos are
// new synthetic temp files, never user/private files. No backend/FFI/network.
// Intentionally UNRUN in the restricted implementation session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<File> files;
  late Uint8List png;
  late bool fontFetching;
  setUpAll(() async {
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    png = await makeOcrTestPng();
    directory = await Directory.systemTemp.createTemp('image_ocr_routing_');
    files = [
      for (var i = 0; i < 3; i++)
        await File('${directory.path}${Platform.pathSeparator}synthetic-$i.png')
            .writeAsBytes(png),
    ];
  });
  tearDownAll(() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await directory.delete(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = fontFetching;
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final kind in ['single', 'grid', 'browser']) {
      testWidgets(
        '$mode/$kind: hover Ctrl+F targets the nearest actual image, not the editor',
        (tester) async {
          final fixture = _EditorFixture(files, png, kind: kind);
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          try {
            await mouse.addPointer(location: Offset.zero);
            await fixture.mount(tester, mode: mode);
            final before = fixture.editor.document.toJson();
            final selection = fixture.editor.selection;
            final focus = FocusManager.instance.primaryFocus;
            final editorElement = tester.element(find.byType(AppFlowyEditor));
            expect(focus, isNotNull);
            await mouse.moveTo(tester.getCenter(_image(files[1].path)));
            await tester.pump();
            expect(FocusManager.instance.primaryFocus, same(focus));
            expect(fixture.editor.selection, selection);
            expect(fixture.service.calls, isEmpty);
            expect(find.byType(FindReplaceBar), findsNothing);
            if (kind != 'single') {
              expect(
                _gallery(tester).indexNotifier.value,
                0,
                reason: 'Passive hover does not select a gallery image',
              );
            }
            await ocrChord(tester, LogicalKeyboardKey.keyF);
            expect(find.byType(ImageOcrOverlay), findsOneWidget);
            final popup =
                tester.widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay));
            expect(popup.find, isTrue);
            expect(popup.source.url, files[1].path);
            expect(fixture.pageFindCalls, 0);
            if (kind != 'single') {
              expect(_gallery(tester).indexNotifier.value, 1);
            }
            await tester.enterText(
              find.byKey(const ValueKey('findTextField')),
              'HELLO',
            );
            await waitForOcrCalls(tester, fixture.service, 1);
            fixture.service.calls.single.done.complete(ocrTestResult());
            await tester.pump();
            expect(
              tester
                  .widget<FindReplaceBar>(find.byType(FindReplaceBar))
                  .matchCount,
              2,
            );
            await ocrChord(tester, LogicalKeyboardKey.keyF);
            expect(find.byType(ImageOcrOverlay), findsOneWidget);
            expect(fixture.service.calls, hasLength(1));
            expect(fixture.clipboard.writes, isEmpty);
            expect(fixture.editor.document.toJson(), before);
            expect(
              tester.element(find.byType(AppFlowyEditor)),
              same(editorElement),
            );
            await _closePopup(tester);
          } finally {
            await mouse.removePointer();
            await fixture.dispose(tester);
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }

  testWidgets(
    'selected read-only image gets Cmd+F without changing editor data',
    (tester) async {
      final fixture = _EditorFixture(files, png, editable: false);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await fixture.mount(tester);
        final target = fixture.editor.document.root.children[2];
        fixture.editor.selection =
            Selection.single(path: target.path, startOffset: 0, endOffset: 1);
        final before = fixture.editor.document.toJson();
        await mouse.moveTo(
          tester.getCenter(find.byKey(const ValueKey('ocr-page-margin'))),
        );
        await tester.pump();
        await ocrChord(
          tester,
          LogicalKeyboardKey.keyF,
          modifier: LogicalKeyboardKey.metaLeft,
        );
        expect(
          tester
              .widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay))
              .source
              .url,
          files[1].path,
        );
        expect(fixture.pageFindCalls, 0);
        expect(fixture.editor.document.toJson(), before);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'duplicate grid URLs still select the hovered unit index',
    (tester) async {
      final fixture =
          _EditorFixture(files, png, kind: 'grid', duplicates: true);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await fixture.mount(tester);
        await mouse.moveTo(tester.getCenter(_image(files[0].path).at(1)));
        await ocrChord(tester, LogicalKeyboardKey.keyF);
        expect(_gallery(tester).indexNotifier.value, 1);
        expect(
          tester
              .widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay))
              .source
              .url,
          files[0].path,
        );
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'caption typing and hover never redirect native Ctrl+A/C into OCR',
    (tester) async {
      final fixture = _EditorFixture(files, png);
      final captionNode = fixture.editor.document.root.children[1];
      captionNode.updateAttributes({
        ...captionNode.attributes,
        CustomImageBlockKeys.caption: 'Existing caption',
      });
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await fixture.mount(tester);
        final captions = find.descendant(
          of: find.byType(CustomImageBlockComponent).first,
          matching: find.byType(TextField),
        );
        expect(captions, findsOneWidget);
        await tester.enterText(captions, 'A real caption');
        await tester.pump();
        await mouse.moveTo(tester.getCenter(_image(files[1].path)));
        await ocrChord(tester, LogicalKeyboardKey.keyA);
        await ocrChord(tester, LogicalKeyboardKey.keyC);
        expect(fixture.clipboard.writes.last, 'A real caption');
        expect(fixture.service.calls, isEmpty);
        expect(find.byType(ImageOcrOverlay), findsNothing);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'deleting an OCR owner removes only its covered route and completes it',
    (tester) async {
      final fixture = _EditorFixture(files, png);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await fixture.mount(tester);
        final target = fixture.editor.document.root.children[1];
        await mouse.moveTo(tester.getCenter(_image(files[0].path)));
        await ocrChord(tester, LogicalKeyboardKey.keyF);
        await waitForOcrCalls(tester, fixture.service, 1);
        final popupContext = tester.element(find.byType(ImageOcrOverlay));
        final route = ModalRoute.of(popupContext)!;
        var completed = false;
        unawaited(route.popped.then<void>((_) => completed = true));
        final staleClose = tester
            .widget<IconButton>(find.byKey(const ValueKey('image-ocr-close')))
            .onPressed!;
        final newer = showDialog<void>(
          context: popupContext,
          builder: (_) => const AlertDialog(content: Text('Newer dialog')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        staleClose();
        expect(find.text('Newer dialog'), findsOneWidget);
        await fixture.editor.apply(
          fixture.editor.transaction..deleteNode(target),
          withUpdateSelection: false,
        );
        await tester.pump();
        await tester.pump();
        expect(route.isActive, isFalse);
        expect(completed, isTrue);
        expect(fixture.service.calls.single.cancellation!.isCancelled, isTrue);
        expect(find.text('Newer dialog'), findsOneWidget);
        fixture.navigator.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await newer;
        fixture.service.calls.single.done
            .completeError(StateError('obsolete read'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a same-node image replacement cancels old find before reopening',
    (tester) async {
      final fixture = _EditorFixture(files, png);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await fixture.mount(tester);
        final target = fixture.editor.document.root.children[1];
        await mouse.moveTo(tester.getCenter(_image(files[0].path)));
        await ocrChord(tester, LogicalKeyboardKey.keyF);
        await waitForOcrCalls(tester, fixture.service, 1);
        await fixture.editor.apply(
          fixture.editor.transaction
            ..updateNode(target, {
              CustomImageBlockKeys.url: files[2].path,
            }),
          withUpdateSelection: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(fixture.service.calls.first.cancellation!.isCancelled, isTrue);
        expect(find.byType(ImageOcrOverlay), findsNothing);
        await mouse.moveTo(tester.getCenter(_image(files[2].path)));
        await ocrChord(tester, LogicalKeyboardKey.keyF);
        expect(
          tester
              .widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay))
              .source
              .url,
          files[2].path,
        );
        fixture.service.calls.first.done
            .complete(const OcrResult(lines: [], engine: 'Old'));
        await tester.pump();
        expect(
          tester.widget<FindReplaceBar>(find.byType(FindReplaceBar)).busy,
          isTrue,
        );
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'photo viewer finds its current image after arrow navigation and honors read guard',
    (tester) async {
      final service = ControlledOcrService();
      final sources = {
        for (final file in files) file.path: MemoryOcrSource(file.path, png),
      };
      final allowed = ValueNotifier(true);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _precache(tester, files);
        await mouse.addPointer(location: Offset.zero);
        await tester.pumpWidget(
          ocrTestApp(
            ValueListenableBuilder<bool>(
              valueListenable: allowed,
              builder: (_, value, __) => InteractiveImageViewer(
                imageProvider: AFBlockImageProvider(
                  images: [
                    for (final file in files)
                      ImageBlockData(
                        url: file.path,
                        type: CustomImageType.local,
                      ),
                  ],
                ),
                ocrService: service,
                ocrSourceBuilder: (image) => sources[image.url]!,
                canReadImage: () => allowed.value,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await mouse.moveTo(tester.getCenter(_image(files[1].path)));
        await ocrChord(tester, LogicalKeyboardKey.keyF);
        expect(
          tester
              .widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay))
              .source
              .url,
          files[1].path,
        );
        await waitForOcrCalls(tester, service, 1);
        allowed.value = false;
        await tester.pump();
        await tester.pump();
        expect(service.calls.single.cancellation!.isCancelled, isTrue);
        expect(find.byType(ImageOcrOverlay), findsNothing);
        await ocrChord(tester, LogicalKeyboardKey.keyF);
        expect(find.byType(ImageOcrOverlay), findsNothing);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        service.finishPending();
        await tester.pump();
        allowed.dispose();
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

class _EditorFixture {
  _EditorFixture(
    this.files,
    Uint8List png, {
    this.kind = 'single',
    this.editable = true,
    bool duplicates = false,
  }) {
    sources = {
      for (final file in files) file.path: MemoryOcrSource(file.path, png),
    };
    final imageFiles =
        duplicates ? [files.first, files.first] : files.take(2).toList();
    final images = [
      for (final file in imageFiles)
        ImageBlockData(url: file.path, type: CustomImageType.local),
    ];
    final gallery = multiImageNode(images: images);
    gallery.updateAttributes({
      ...gallery.attributes,
      MultiImageBlockKeys.layout:
          (kind == 'grid' ? MultiImageLayout.grid : MultiImageLayout.browser)
              .toIntValue(),
    });
    final nodes = kind == 'single'
        ? [
            for (final image in images)
              customImageNode(url: image.url, width: 300, height: 150),
          ]
        : [
            gallery,
          ];
    editor = EditorState(
      document: Document(
        root: pageNode(
          children: [
            paragraphNode(text: 'Editor text must not receive image find'),
            ...nodes,
            paragraphNode(text: 'Page content after the photos'),
          ],
        ),
      ),
    )
      ..disableSealTimer = true
      ..editable = editable;
  }

  final List<File> files;
  final String kind;
  final bool editable;
  final service = ControlledOcrService();
  final clipboard = OcrTestClipboard();
  final navigator = GlobalKey<NavigatorState>();
  final focus = FocusNode();
  final document = _Document();
  late final EditorState editor;
  late final Map<String, MemoryOcrSource> sources;
  int pageFindCalls = 0;

  ImageEditorSource sourceFor(ImageBlockData image) => sources[image.url]!;

  Future<void> mount(WidgetTester tester, {String mode = 'light'}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 900);
    clipboard.install();
    await _precache(tester, files);
    await tester.pumpWidget(
      ocrTestApp(
        BlocProvider<DocumentBloc>.value(
          value: document,
          child: ContextualFindRegion(
            debugLabel: 'Actual editor page',
            onFind: () => pageFindCalls++,
            child: Focus(
              focusNode: focus,
              autofocus: !editable,
              child: Column(
                children: [
                  const SizedBox(
                    key: ValueKey('ocr-page-margin'),
                    height: 24,
                    width: double.infinity,
                  ),
                  Expanded(
                    child: AppFlowyEditor(
                      editorState: editor,
                      autoFocus: editable,
                      editable: editable,
                      editorStyle: const EditorStyle.desktop(
                        padding: EdgeInsets.all(24),
                      ),
                      blockComponentBuilders: {
                        ...standardBlockComponentBuilderMap,
                        CustomImageBlockKeys.type:
                            CustomImageBlockComponentBuilder(
                          ocrService: service,
                          ocrSourceBuilder: sourceFor,
                        ),
                        MultiImageBlockKeys.type:
                            MultiImageBlockComponentBuilder(
                          ocrService: service,
                          ocrSourceBuilder: sourceFor,
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        mode: mode,
        navigatorKey: navigator,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> dispose(WidgetTester tester) async {
    clipboard.release();
    await tester.pumpWidget(const SizedBox.shrink());
    service.finishPending();
    await tester.pump();
    if (!editor.isDisposed) editor.dispose();
    editor.editableNotifier.dispose();
    focus.dispose();
    clipboard.uninstall();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
    expect(tester.takeException(), isNull);
  }
}

class _Document extends Fake implements DocumentBloc {
  @override
  DocumentState get state => DocumentState.initial();
  @override
  Stream<DocumentState> get stream => const Stream.empty();
  @override
  bool get isClosed => false;
  @override
  bool get isLocalMode => true;
}

Finder _image(String path) => find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is FileImage &&
          (widget.image as FileImage).file.path == path,
    );

MultiImageBlockComponentState _gallery(WidgetTester tester) =>
    tester.state(find.byType(MultiImageBlockComponent));

Future<void> _closePopup(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  expect(find.byType(ImageOcrOverlay), findsNothing);
}

Future<void> _precache(WidgetTester tester, List<File> files) async {
  for (final file in files) {
    await tester.runAsync(() async {
      final stream = FileImage(file).resolve(ImageConfiguration.empty);
      final ready = Completer<void>();
      final listener = ImageStreamListener(
        (image, _) {
          image.dispose();
          if (!ready.isCompleted) ready.complete();
        },
        onError: (Object error, StackTrace? stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      try {
        await ready.future.timeout(const Duration(seconds: 3));
      } finally {
        stream.removeListener(listener);
      }
    });
  }
}
