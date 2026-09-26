import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_identity.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';
import 'image_ocr_test_support.dart';

const _title = ValueKey('workspace-file-name');
const _nameInput = ValueKey('workspace-inline-name-editor');

// Complements file_photo_workspace_identity_test.dart with the real standalone
// image/find integration. Reuses the shared file-control and OCR boundaries,
// rather than copying that suite's repository, theme, or renderer harness.
// Intentionally UNRUN in the restricted implementation session.
void main() {
  fileControlTestSetup();
  late Directory directory;
  late File file;
  late Uint8List png;

  setUpAll(() async {
    png = await makeOcrTestPng();
    directory = await Directory.systemTemp.createTemp('workspace-image-find-');
    file = await File('${directory.path}/synthetic.png').writeAsBytes(png);
  });

  tearDownAll(() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await directory.delete(recursive: true);
  });

  for (final mode in fileControlAppearances) {
    _test('$mode: image-only find retains the photo, zoom and renamed identity',
        (tester) async {
      final fixture = _Photo(file, png);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await fixture.mount(tester, mode: mode);
        final image = _image(file);
        final imageElement = tester.element(image);
        final imageState = tester.state(image);
        final decoded = tester
            .widget<RawImage>(
              find.descendant(of: image, matching: find.byType(RawImage)),
            )
            .image;
        expect(decoded, isNotNull);
        expect(tester.widget<Image>(image).key, ValueKey('${file.path}_0'));
        final viewer = find.byType(InteractiveViewer);
        final viewerState = tester.state(viewer);
        final viewerKey = tester.widget<InteractiveViewer>(viewer).key;
        final transform =
            tester.widget<InteractiveViewer>(viewer).transformationController!;
        final size = tester.getSize(viewer);
        transform.value = Matrix4.identity()
          ..translate(-size.width / 2, -size.height / 2)
          ..scale(2.0);
        await tester.pump();
        final zoom = transform.value.clone();
        final card = find.descendant(
          of: viewer,
          matching: find.byType(ViewerCard),
        );
        final cardElement = tester.element(card);
        final region = find.byType(ImageOcrFindRegion);
        expect(tester.getRect(region), tester.getRect(image));
        expect(tester.getRect(region).height, lessThan(size.height));
        expect(
          find.descendant(
            of: region,
            matching: find.byType(WorkspaceFileIdentityRow),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: region,
            matching: find.byType(DocumentViewportButton),
          ),
          findsNothing,
        );

        final focus = FocusManager.instance.primaryFocus;
        expect(fixture.focus.hasFocus, isTrue);
        await mouse.moveTo(tester.getCenter(image));
        await tester.pump();
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(fixture.service.calls, isEmpty);
        await ocrChord(tester, LogicalKeyboardKey.keyF);
        final popup = tester.widget<ImageOcrOverlay>(
          find.byType(ImageOcrOverlay),
        );
        expect(popup.source, same(fixture.source));
        expect(popup.service, same(fixture.service));
        expect(popup.name, 'Original photo.png');
        expect(popup.find, isTrue);
        expect(
          PaperTheme.isEnabled(tester.element(find.byType(ImageOcrOverlay))),
          mode == 'paper',
        );
        await tester.enterText(
          find.byKey(const ValueKey('findTextField')),
          'HELLO',
        );
        await waitForOcrCalls(tester, fixture.service, 1);
        fixture.service.calls.single.done.complete(ocrTestResult());
        await tester.pump();
        expect(
          tester.widget<FindReplaceBar>(find.byType(FindReplaceBar)).matchCount,
          2,
        );
        await _closeFind(tester);

        await _beginRename(tester);
        await tester.enterText(find.byKey(_nameInput), 'Renamed photo');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settleFileControls(tester);
        expect(fixture.backend.renames, ['Renamed photo.png']);
        expect(find.text('Renamed photo.png'), findsOneWidget);
        expect(
          tester.widget<ImageOcrFindRegion>(region).name,
          'Renamed photo.png',
        );
        expect(tester.element(image), same(imageElement));
        expect(tester.state(image), same(imageState));
        expect(tester.element(card), same(cardElement));
        expect(tester.state(viewer), same(viewerState));
        expect(tester.widget<InteractiveViewer>(viewer).key, viewerKey);
        expect(
          tester.widget<InteractiveViewer>(viewer).transformationController,
          same(transform),
        );
        expect(transform.value, zoom);
        expect(
          tester
              .widget<RawImage>(
                find.descendant(of: image, matching: find.byType(RawImage)),
              )
              .image,
          same(decoded),
        );

        // The focused standalone file remains a keyboard target without hover.
        fixture.focus.requestFocus();
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        await ocrChord(
          tester,
          LogicalKeyboardKey.keyF,
          modifier: LogicalKeyboardKey.metaLeft,
        );
        expect(
          tester.widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay)).name,
          'Renamed photo.png',
        );
        await waitForOcrCalls(tester, fixture.service, 2);
        expect(fixture.backend.loads, 1);
        expect(fixture.backend.extraWrites, isEmpty);
        expect(fixture.backend.iconWrites, isEmpty);
        expect(fixture.clipboard.writes, isEmpty);
        expect(transform.value, zoom);
        expect(await tester.runAsync(file.readAsBytes), png);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  _test('live inherited read guard cancels only its covered OCR route',
      (tester) async {
    final fixture = _Photo(file, png);
    try {
      await fixture.mount(tester);
      final host = tester.widget<StandaloneFileScope>(
        find.byType(StandaloneFileScope),
      );
      final region = tester.widget<ImageOcrFindRegion>(
        find.byType(ImageOcrFindRegion),
      );
      final extract = tester
          .widget<DocumentViewportButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is DocumentViewportButton &&
                  widget.tooltip == 'Extract text',
            ),
          )
          .onPressed!;
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      await waitForOcrCalls(tester, fixture.service, 1);
      final popupContext = tester.element(find.byType(ImageOcrOverlay));
      final route = ModalRoute.of(popupContext)!;
      final newer = showDialog<void>(
        context: popupContext,
        builder: (_) => const AlertDialog(content: Text('Unrelated dialog')),
      );
      await settleFileControls(tester);

      fixture.backend.listeners.single.deleted!(
        FlowyResult.success(fixture.backend.stored),
      );
      // Before rebuilding: none of these callbacks may cache readability.
      expect(host.canRead(), isFalse);
      expect(region.isAvailable!(), isFalse);
      expect(region.isSelected!(), isFalse);
      extract();
      await settleFileControls(tester);
      expect(route.isActive, isFalse);
      expect(fixture.service.calls.single.cancellation!.isCancelled, isTrue);
      expect(fixture.source.reads, 1);
      expect(find.text('Unrelated dialog'), findsOneWidget);
      fixture.service.calls.single.done.completeError(StateError('Late OCR'));
      Navigator.of(tester.element(find.text('Unrelated dialog'))).pop();
      await settleFileControls(tester);
      await newer;
      fixture.focus.requestFocus();
      await tester.pump();
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      expect(find.byType(ImageOcrOverlay), findsNothing);
      expect(fixture.service.calls, hasLength(1));
      expect(fixture.backend.loads, 1);
      expect(fixture.clipboard.writes, isEmpty);
    } finally {
      await fixture.dispose(tester);
    }
  });

  _test('rebinding the actual view cancels old find and refuses old callbacks',
      (tester) async {
    final fixture = _Photo(file, png);
    final current = ValueNotifier(fixture.backend.stored);
    try {
      await fixture.mount(
        tester,
        wrap: (_) => ValueListenableBuilder<ViewPB>(
          valueListenable: current,
          builder: (_, view, __) => fixture.child(view: view),
        ),
      );
      final viewState = tester.state(find.byType(WorkspaceFileView));
      final oldHost = tester.widget<StandaloneFileScope>(
        find.byType(StandaloneFileScope),
      );
      final oldRegion = tester.widget<ImageOcrFindRegion>(
        find.byType(ImageOcrFindRegion),
      );
      final oldExtract = tester
          .widget<DocumentViewportButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is DocumentViewportButton &&
                  widget.tooltip == 'Extract text',
            ),
          )
          .onPressed!;
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      await waitForOcrCalls(tester, fixture.service, 1);
      fixture.backend.stored = fileControlView(
        'replacement',
        'Replacement photo.png',
        file.path,
      );
      current.value = fixture.backend.stored;
      await settleFileControls(tester);
      expect(tester.state(find.byType(WorkspaceFileView)), same(viewState));
      expect(oldHost.canRead(), isFalse);
      expect(oldRegion.isAvailable!(), isFalse);
      expect(fixture.service.calls.single.cancellation!.isCancelled, isTrue);
      expect(fixture.backend.listeners.first.stopped, isTrue);
      oldExtract();
      await settleFileControls(tester);
      expect(find.byType(ImageOcrOverlay), findsNothing);
      expect(fixture.source.reads, 1);
      fixture.focus.requestFocus();
      await tester.pump();
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      expect(
        tester.widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay)).name,
        'Replacement photo.png',
      );
      await waitForOcrCalls(tester, fixture.service, 2);
      expect(fixture.backend.loads, 2);
    } finally {
      await fixture.dispose(tester);
      current.dispose();
    }
  });

  _test('parent permission is live; read-only photos can still be searched',
      (tester) async {
    final fixture = _Photo(file, png, editable: false);
    var allowed = true;
    var parentFinds = 0;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await fixture.mount(
        tester,
        wrap: (child) => ContextualFindRegion(
          isActive: () => allowed,
          onFind: () => parentFinds++,
          child: child,
        ),
      );
      await mouse.moveTo(tester.getCenter(_image(file)));
      allowed = false; // No rebuild of the inherited owner.
      expect(
        ContextualFindRegion.dispatch(tester.element(_image(file))),
        isFalse,
      );
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      expect(find.byType(ImageOcrOverlay), findsNothing);
      expect(fixture.source.reads, 0);
      allowed = true;
      await mouse.moveTo(Offset.zero);
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      expect(find.byType(ImageOcrOverlay), findsOneWidget);
      await waitForOcrCalls(tester, fixture.service, 1);
      expect(parentFinds, 0);
      expect(fixture.backend.renames, isEmpty);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test('hover and Ctrl+F leave the actual title draft and focus alone',
      (tester) async {
    final fixture = _Photo(file, png);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await fixture.mount(tester);
      await _beginRename(tester);
      await tester.enterText(find.byKey(_nameInput), 'Unsaved title.png');
      final field = tester.widget<EditableText>(find.byKey(_nameInput));
      field.controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 9,
      );
      final draft = field.controller.value;
      final state = tester.state(find.byKey(_nameInput));
      final focus = FocusManager.instance.primaryFocus;
      expect(field.focusNode.hasPrimaryFocus, isTrue);
      expect(
        tester
                .element(find.byKey(_nameInput))
                .findAncestorWidgetOfExactType<ContextualFindRegion>()
                ?.findInEditable ??
            false,
        isFalse,
      );
      await mouse.moveTo(tester.getCenter(_image(file)));
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(tester.state(find.byKey(_nameInput)), same(state));
      expect(field.controller.value, draft);
      expect(find.byType(ImageOcrOverlay), findsNothing);
      expect(fixture.source.reads, 0);
      expect(fixture.backend.renames, isEmpty);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test('image find preserves a neighboring real source editor and its draft',
      (tester) async {
    final fixture = _Photo(file, png);
    final code =
        MemoryCodeFile(List.filled(100, 'print("original")').join('\n'));
    final backend = FileControlBackend(
      fileControlView('source', 'source.py', code.path),
      code,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await fixture.mount(
        tester,
        wrap: (child) => Row(
          children: [
            Expanded(child: child),
            Expanded(child: backend.viewer()),
          ],
        ),
      );
      await _waitFor(
        tester,
        () => find.byType(TextField).evaluate().isNotEmpty,
      );
      final source = find.byType(SandboxedCodeRunner);
      final sourceState = tester.state(source);
      final field = tester.widget<TextField>(
        find.descendant(
          of: source,
          matching: find.byType(TextField),
        ),
      );
      final inputFinder = find.descendant(
        of: find.byKey(field.key!),
        matching: find.byType(EditableText),
      );
      final inputState = tester.state<EditableTextState>(inputFinder);
      field.controller!.value = TextEditingValue(
        text: 'Unsaved buffer\n${code.contents}',
        selection: const TextSelection(baseOffset: 3, extentOffset: 12),
      );
      field.scrollController!.jumpTo(64);
      final draft = field.controller!.value;
      fixture.focus.requestFocus();
      await mouse.moveTo(tester.getCenter(_image(file)));
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      await waitForOcrCalls(tester, fixture.service, 1);
      fixture.service.calls.single.done.complete(ocrTestResult());
      await _closeFind(tester);
      expect(tester.state(find.byType(SandboxedCodeRunner)), same(sourceState));
      expect(tester.state<EditableTextState>(inputFinder), same(inputState));
      expect(
        tester.widget<EditableText>(inputFinder).controller,
        same(field.controller),
      );
      expect(
        tester.widget<EditableText>(inputFinder).scrollController,
        same(field.scrollController),
      );
      expect(field.controller!.value, draft);
      expect(field.scrollController!.offset, 64);
      expect(code.reads, 1);
      expect(code.writes, 0);
      expect(backend.loads, 1);

      // This is searchable source content, NOT an ordinary title field. The
      // real router permits the hovered image even while this source has the
      // caret; opening OCR must still preserve its controller, draft and range.
      field.focusNode!.requestFocus();
      await settleFileControls(tester);
      expect(field.focusNode!.hasPrimaryFocus, isTrue);
      expect(
        tester
            .element(inputFinder)
            .findAncestorWidgetOfExactType<ContextualFindRegion>()!
            .findInEditable,
        isTrue,
      );
      expect(field.controller!.value, draft);
      final focusedScroll = field.scrollController!.offset;
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      expect(find.byType(ImageOcrOverlay), findsOneWidget);
      expect(
        tester.widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay)).source,
        same(fixture.source),
      );
      await waitForOcrCalls(tester, fixture.service, 2);
      fixture.service.calls.last.done.complete(ocrTestResult());
      await tester.pump();
      await _closeFind(tester);
      expect(tester.state<EditableTextState>(inputFinder), same(inputState));
      expect(
        tester.widget<EditableText>(inputFinder).controller,
        same(field.controller),
      );
      expect(field.controller!.value, draft);
      expect(field.scrollController!.offset, focusedScroll);

      // Without media hover, the focused source opens its OWN local bar. The
      // separate title-draft test covers an unowned native field with hover.
      await mouse.moveTo(Offset.zero);
      field.focusNode!.requestFocus();
      await tester.pump();
      expect(field.focusNode!.hasPrimaryFocus, isTrue);
      await ocrChord(tester, LogicalKeyboardKey.keyF);
      final sourceBar = find.descendant(
        of: source,
        matching: find.byType(FindReplaceBar),
      );
      expect(sourceBar, findsOneWidget);
      final bar = tester.widget<FindReplaceBar>(sourceBar);
      expect(bar.findFocusNode.hasPrimaryFocus, isTrue);
      expect(bar.findController.text, draft.selection.textInside(draft.text));
      expect(find.byType(ImageOcrOverlay), findsNothing);
      expect(fixture.service.calls, hasLength(2));
      expect(tester.state<EditableTextState>(inputFinder), same(inputState));
      expect(
        tester.widget<EditableText>(inputFinder).controller,
        same(field.controller),
      );
      expect(field.controller!.text, draft.text);
      expect(code.reads, 1);
      expect(code.writes, 0);
      expect(backend.loads, 1);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      timeout: const Timeout(Duration(seconds: 30)),
    );

class _Photo {
  _Photo(this.file, Uint8List png, {this.editable = true})
      : backend = FileControlBackend(
          fileControlView('photo', 'Original photo.png', file.path),
          file,
        ),
        source = MemoryOcrSource(file.path, png);

  final File file;
  final bool editable;
  final FileControlBackend backend;
  final MemoryOcrSource source;
  final service = ControlledOcrService();
  final clipboard = OcrTestClipboard();
  final focus = FocusNode(debugLabel: 'Active standalone photo');

  MemoryOcrSource sourceFor(ImageBlockData _) => source;

  Widget child({ViewPB? view}) => Focus(
        focusNode: focus,
        autofocus: true,
        child: WorkspaceFileView(
          view: view ?? backend.stored,
          editable: editable,
          repository: backend,
          resolveStorageUrl: backend.resolve,
          materializeFile: backend.materialize,
          iconListenerFactory: backend.listen,
          coverBackend: backend.covers,
          updateIcon: backend.writeIcon,
          writeExtra: backend.writeExtra,
          mediaActions: backend.media,
          ocrService: service,
          ocrSourceBuilder: sourceFor,
        ),
      );

  Future<void> mount(
    WidgetTester tester, {
    String mode = 'light',
    Widget Function(Widget)? wrap,
  }) async {
    clipboard.install();
    // Decode before mounting, like the real-image identity/routing fixtures.
    await tester.runAsync(() async {
      final ready = Completer<void>();
      final stream = FileImage(file).resolve(ImageConfiguration.empty);
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
    final viewer = child();
    await mountFileControls(
      tester,
      wrap?.call(viewer) ?? viewer,
      mode: mode,
      width: 1000,
      height: 760,
      reduced: true,
    );
    await _waitFor(tester, () => _image(file).evaluate().isNotEmpty);
    expect(
      tester
          .widget<RawImage>(
            find.descendant(of: _image(file), matching: find.byType(RawImage)),
          )
          .image,
      isNotNull,
    );
  }

  Future<void> dispose(WidgetTester tester) async {
    clipboard.release();
    await unmountFileControls(tester);
    service.finishPending();
    await tester.pump();
    focus.dispose();
    clipboard.uninstall();
    expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
    expect(tester.takeException(), isNull);
  }
}

Finder _image(File file) => find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is FileImage &&
          (widget.image as FileImage).file.path == file.path,
    );

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'The actual file renderer must load');
  await settleFileControls(tester);
}

Future<void> _beginRename(WidgetTester tester) async {
  await tester.tap(find.byKey(_title));
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.f2);
  await settleFileControls(tester);
  expect(find.byKey(_nameInput), findsOneWidget);
}

Future<void> _closeFind(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await settleFileControls(tester);
  expect(find.byType(ImageOcrOverlay), findsNothing);
}
