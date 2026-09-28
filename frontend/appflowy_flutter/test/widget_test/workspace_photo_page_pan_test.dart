import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/workspace_file/workspace_file_identity.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

// Author-only; real Image.file/InteractiveViewer, no surrogate scroll child.
// Native Profile/Release input replay is still an executor acceptance check.
void main() {
  fileControlTestSetup();
  late Directory directory;
  late File file;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('photo-page-pan-');
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xFFB8C6AF), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(640, 1600);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      file = await File('${directory.path}/photo.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
      picture.dispose();
    }
  });
  tearDownAll(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await directory.delete(recursive: true);
  });

  for (final appearance in fileControlAppearances) {
    testWidgets(
        '$appearance: fitted wheel/pan retires header, retains image at 2x text',
        (tester) async {
      final backend = await _mountPhoto(tester, file, appearance);
      final viewer = find.byType(InteractiveViewer);
      final viewerState = tester.state(viewer);
      final transform =
          tester.widget<InteractiveViewer>(viewer).transformationController!;
      final image = _image(file);
      final imageState = tester.state(image);
      final raw = find.descendant(of: image, matching: find.byType(RawImage));
      final decoded = tester.widget<RawImage>(raw).image!;
      final frameSize = tester.getSize(image);
      final painted = _paintedRect(tester, image);
      expect(painted.height, lessThan(1600));
      final page =
          tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
      final identity =
          find.byType(WorkspaceFileIdentityRow, skipOffstage: false);
      final identityElement = tester.element(identity);
      final initialTop = tester.getTopLeft(identity).dy;
      final point = _point(tester);
      expect(transform.value.isIdentity(), isTrue);
      await tester.sendEventToBinding(PointerScrollEvent(
        position: point,
        scrollDelta: const Offset(0, 80),
      ));
      await tester.pumpAndSettle();
      expect(page.outerController.offset, closeTo(80, .01));
      expect(transform.value.isIdentity(), isTrue,
          reason: 'Plain wheel must not zoom the photo.');
      page.outerController.jumpTo(0);
      await tester.pump();
      final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await pan.panZoomStart(point);
      await pan.panZoomUpdate(point,
          pan: const Offset(0, -4),
          timeStamp: const Duration(milliseconds: 16));
      await tester.pump();
      expect(page.outerController.offset, 0,
          reason: 'Hold short/unclassified pan for pinch.');
      for (var i = 1; i <= 30; i++) {
        await pan.panZoomUpdate(point,
            pan: Offset(0, -4 - i * 32.0),
            timeStamp: Duration(milliseconds: 16 + i * 16));
        await tester.pump(const Duration(milliseconds: 16));
        expect(transform.value.isIdentity(), isTrue);
        expect(tester.state(viewer), same(viewerState));
        expect(tester.state(image), same(imageState));
        expect(tester.getSize(image), frameSize);
        final currentFrame = _paintedRect(tester, image);
        expect(currentFrame.width, closeTo(painted.width, .01));
        expect(currentFrame.height, closeTo(painted.height, .01));
        expect(currentFrame.top,
            closeTo(painted.top - page.outerController.offset, .01));
        expect(tester.widget<RawImage>(raw).image, same(decoded));
        expect(tester.element(identity), same(identityElement));
        expect(tester.getTopLeft(identity).dy,
            closeTo(initialTop - page.outerController.offset, .01));
      }
      await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(page.outerController.offset,
          closeTo(page.outerController.position.maxScrollExtent, .01));
      expect(identity.hitTestable(), findsNothing);
      final end = page.outerController.offset;
      await tester.pump(const Duration(seconds: 1));
      expect(page.outerController.offset, end,
          reason: 'No duplicate release momentum.');
      expect(transform.value.isIdentity(), isTrue,
          reason: 'Native release noise must not reject the next fitted pan.');
      final reverse =
          await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await reverse.panZoomStart(_point(tester));
      for (var i = 1; i <= 30; i++) {
        await reverse.panZoomUpdate(_point(tester),
            pan: Offset(0, i * 32.0),
            timeStamp: Duration(milliseconds: 800 + i * 16));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await reverse.panZoomEnd(timeStamp: const Duration(milliseconds: 1400));
      await tester.pumpAndSettle();
      expect(page.outerController.offset, closeTo(0, .01));
      expect(transform.value.isIdentity(), isTrue);
      expect(backend.loads, 1);
      expect(backend.extraWrites, isEmpty);
      expect(tester.takeException(), isNull);
      await unmountFileControls(tester);
    });

    for (final firstPan in [4.0, 40.0]) {
      testWidgets(
          '$appearance: pan $firstPan becomes native pinch without header replay',
          (tester) async {
        await _mountPhoto(tester, file, appearance);
        final viewer = find.byType(InteractiveViewer);
        final viewerState = tester.state(viewer);
        final transform =
            tester.widget<InteractiveViewer>(viewer).transformationController!;
        final page =
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
        final point = _point(tester);
        final pan =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await pan.panZoomStart(point);
        await pan.panZoomUpdate(point,
            pan: Offset(0, -firstPan),
            timeStamp: const Duration(milliseconds: 16));
        await tester.pump();
        final beforePinch = page.outerController.offset;
        if (firstPan < 8) expect(beforePinch, 0);
        for (var i = 1; i <= 5; i++) {
          await pan.panZoomUpdate(point,
              pan: Offset(0, -firstPan - i * 5),
              scale: 1 + i * .2,
              timeStamp: Duration(milliseconds: 16 + i * 16));
          await tester.pump(const Duration(milliseconds: 16));
          expect(page.outerController.offset, beforePinch);
        }
        await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
        expect(tester.state(viewer), same(viewerState));
        final zoomed = transform.value.clone();
        final native =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await native.panZoomStart(point);
        for (var i = 1; i <= 4; i++) {
          await native.panZoomUpdate(point,
              pan: Offset(0, -i * 24.0),
              timeStamp: Duration(milliseconds: 400 + i * 16));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await native.panZoomEnd(timeStamp: const Duration(milliseconds: 700));
        await tester.pumpAndSettle();
        expect(page.outerController.offset, beforePinch);
        expect(transform.value, isNot(zoomed));
        expect(tester.takeException(), isNull);
        await unmountFileControls(tester);
      });
    }
  }

  testWidgets('fit canonicalization preserves genuine native zoom and pan',
      (tester) async {
    await _mountPhoto(tester, file, 'paper');
    final transform = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final noise = Matrix4.identity()..setTranslationRaw(0, 3.3e-10, 0);
    transform.value = noise;
    expect(transform.value.isIdentity(), isTrue);
    expect(noise.getTranslation().y, 3.3e-10,
        reason: 'Never mutate the caller-owned matrix.');
    final zoom = Matrix4.identity()..scale(1.0000000001);
    transform.value = zoom;
    expect(transform.value, same(zoom));
    final pan = Matrix4.identity()..setTranslationRaw(.25, -.5, 0);
    transform.value = pan;
    expect(transform.value, same(pan));
    await unmountFileControls(tester);
  });

  testWidgets('native pan cancels queued photo page wheel before release',
      (tester) async {
    await _mountPhoto(tester, file, 'paper', reduced: false);
    final page =
        tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
    final point = _point(tester);
    await tester.sendEventToBinding(
        PointerScrollEvent(position: point, scrollDelta: const Offset(0, 80)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 8));
    final before = page.outerController.offset;
    expect(before, inExclusiveRange(0, 80));
    final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await pan.panZoomStart(point);
    await tester.pump(const Duration(milliseconds: 500));
    expect(page.outerController.offset, before);
    await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(page.outerController.offset, before);
    expect(tester.takeException(), isNull);
    await unmountFileControls(tester);
  });

  testWidgets('modified wheel remains native zoom, not page motion',
      (tester) async {
    await _mountPhoto(tester, file, 'paper');
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final page =
        tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(PointerScrollEvent(
        position: _point(tester), scrollDelta: const Offset(0, -60)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1));
    expect(page.outerController.offset, 0);
    expect(tester.takeException(), isNull);
    await unmountFileControls(tester);
  });
}

Finder _image(File file) => find.byKey(ValueKey('${file.path}_0'));
Rect _paintedRect(WidgetTester tester, Finder image) {
  final box = tester.renderObject<RenderBox>(image);
  return MatrixUtils.transformRect(
      box.getTransformTo(null), Offset.zero & box.size);
}

Offset _point(WidgetTester tester) =>
    tester.getRect(find.byType(StandaloneFilePage)).bottomCenter -
    const Offset(0, 48);

Future<FileControlBackend> _mountPhoto(
    WidgetTester tester, File file, String appearance,
    {bool reduced = true}) async {
  await tester.runAsync(() async {
    final ready = Completer<void>();
    final stream = FileImage(file).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((image, _) {
      image.dispose();
      if (!ready.isCompleted) ready.complete();
    }, onError: (Object error, StackTrace? stack) {
      if (!ready.isCompleted) ready.completeError(error, stack);
    });
    stream.addListener(listener);
    try {
      await ready.future.timeout(const Duration(seconds: 3));
    } finally {
      stream.removeListener(listener);
    }
  });
  final backend = FileControlBackend(
      fileControlView('photo', 'Actual photo.png', file.path), file);
  await mountFileControls(tester, backend.viewer(),
      mode: appearance,
      width: 1000,
      height: 850,
      textScale: 2,
      reduced: reduced);
  for (var i = 0; i < 40 && _image(file).evaluate().isEmpty; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  expect(_image(file), findsOneWidget);
  expect(
      tester
          .widget<RawImage>(find.descendant(
              of: _image(file), matching: find.byType(RawImage)))
          .image,
      isNotNull);
  return backend;
}
