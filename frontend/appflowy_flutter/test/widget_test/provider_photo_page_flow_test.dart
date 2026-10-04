import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/collection/providers/external_file_stage.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_result.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

// Source-only addition: execution/native acceptance belongs to coordination.
// Only synthetic scratch files are read; provider and OCR IO are substituted.
const _title = ValueKey('external-file-title');
const _header = ValueKey('external-file-header');
const _close = ValueKey('external-file-close');
const _next = ValueKey('external-file-next');
const _previous = ValueKey('external-file-previous');
const _fullscreen = ValueKey('workspace-image-fullscreen');
const _testTimeout = Timeout(Duration(seconds: 60));

void main() {
  fileControlTestSetup();
  late Directory scratch;
  late File photo;
  late Uint8List png;

  setUpAll(() async {
    scratch = await Directory.systemTemp.createTemp('provider-photo-flow-');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawColor(const Color(0xFFB8C6AF), BlendMode.src);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 320, 800),
      Paint()..color = const Color(0xFFBD7950),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(640, 1600);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      photo = await File('${scratch.path}/materialized.png').writeAsBytes(png);
    } finally {
      image.dispose();
      picture.dispose();
    }
  });

  tearDownAll(() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await scratch.delete(recursive: true);
  });

  for (final mode in fileControlAppearances) {
    testWidgets(
      '$mode/DPR2: provider photo owns shared read-only tools',
      (tester) async {
        await _withModal(tester, photo, mode, (fixture) async {
          final scope = _scope(tester);
          expect(scope.rendererName, 'Provider photo.png');
          expect(scope.displayName, 'Provider photo');
          expect(scope.canRead(), isTrue);
          expect(scope.canEdit(), isFalse);
          expect(scope.editable, isFalse);
          expect(MediaQuery.devicePixelRatioOf(tester.element(_viewer)), 2);
          expect(
            PaperTheme.isEnabled(tester.element(_viewer)),
            mode == 'paper',
          );
          expect(
            find.byType(WorkspaceFileView),
            findsNothing,
            reason: 'No workspace backend/view identity is fabricated.',
          );
          final stageType = workspacePhotoRenderer(
            file: photo,
            name: scope.rendererName,
          ).runtimeType;
          expect(
            find.byWidgetPredicate((widget) => widget.runtimeType == stageType),
            findsOneWidget,
          );
          _expectTools(tester);
          final canvas = tester.widget<ColoredBox>(
            find.byKey(const ValueKey('external-file-canvas')),
          );
          expect(canvas.color, scope.canvas);
          expect(
            canvas.color,
            FolderExplorerPalette.of(tester.element(_viewer)).background,
          );
          final viewportSurface = tester.widget<ColoredBox>(
            find
                .descendant(
                  of: find.byType(DocumentViewport),
                  matching: find.byType(ColoredBox),
                )
                .first,
          );
          expect(viewportSurface.color, scope.canvas);

          final transform = _transform(tester);
          final frame = _decoded(tester, photo).clone();
          try {
            transform.value = Matrix4.identity()..scale(2.0);
            await tester.pump();
            await clickFileControl(
              tester,
              find.byType(DocumentViewportFitButton),
            );
            expect(_transform(tester), same(transform));
            expect(transform.value.isIdentity(), isTrue);
            expect(_decoded(tester, photo).isCloneOf(frame), isTrue);

            await clickFileControl(tester, find.byKey(_fullscreen));
            final fullscreen = tester.widget<InteractiveImageViewer>(
              find.byType(InteractiveImageViewer),
            );
            expect(fullscreen.canReadImage!(), isTrue);
            expect(fullscreen.onEditImage, isNull);
            expect(fullscreen.imageProvider.getImageName(0), 'Provider photo');
            final source = fullscreen.imageProvider.getImage(0);
            expect(source.url, photo.path);
            expect(source.type, CustomImageType.local);
            final actions = tester
                .widget<MediaActionButtons>(find.byType(MediaActionButtons));
            expect(actions.source.source, photo.path);
            expect(actions.source.name, 'Provider photo');
            expect(actions.source.httpHeaders, isEmpty);
            expect(actions.source.requireAuthentication, isFalse);
            expect(
              find.descendant(
                of: find.byType(InteractiveImageViewer),
                matching: find.byTooltip('Edit image'),
              ),
              findsNothing,
            );
            await tester.sendKeyEvent(
              LogicalKeyboardKey.escape,
              physicalKey: PhysicalKeyboardKey.escape,
            );
            await settleFileControls(tester);
            expect(find.byType(InteractiveImageViewer), findsNothing);
            expect(_transform(tester), same(transform));
            expect(_decoded(tester, photo).isCloneOf(frame), isTrue);

            await clickFileControl(tester, _ocrButton);
            await _until(
              tester,
              () =>
                  fixture.ocr.calls == 1 &&
                  find
                      .byKey(const ValueKey('image-ocr-results'))
                      .evaluate()
                      .isNotEmpty,
            );
            final overlay =
                tester.widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay));
            expect(overlay.source.url, photo.path);
            expect(overlay.source.type, CustomImageType.local);
            expect(overlay.source.userProfile, isNull);
            expect(overlay.name, 'Provider photo');
            expect(fixture.ocr.bytes, orderedEquals(png));
            expect(fixture.ocr.size, const Size(640, 1600));
            await clickFileControl(
              tester,
              find.byKey(const ValueKey('image-ocr-find')),
            );
            final bar =
                tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));
            final controller = bar.findController;
            controller.text = 'needle';
            controller.selection = const TextSelection.collapsed(offset: 3);
            await settleFileControls(tester);
            expect(bar.findFocusNode.hasFocus, isTrue);
            await tester.sendKeyEvent(
              LogicalKeyboardKey.arrowLeft,
              physicalKey: PhysicalKeyboardKey.arrowLeft,
            );
            expect(controller.selection.extentOffset, 2);
            await tester.sendKeyEvent(
              LogicalKeyboardKey.arrowRight,
              physicalKey: PhysicalKeyboardKey.arrowRight,
            );
            expect(controller.selection.extentOffset, 3);
            expect(
              tester
                  .widget<FindReplaceBar>(find.byType(FindReplaceBar))
                  .findController,
              same(controller),
            );
            expect(
              fixture.provider.requests,
              hasLength(1),
              reason: 'OCR query arrows must not navigate provider siblings.',
            );
            await tester.sendKeyEvent(
              LogicalKeyboardKey.escape,
              physicalKey: PhysicalKeyboardKey.escape,
            );
            await settleFileControls(tester);
            expect(find.byType(ImageOcrOverlay), findsNothing);
            expect(_transform(tester), same(transform));
            expect(_decoded(tester, photo).isCloneOf(frame), isTrue);
            expect(tester.takeException(), isNull);
          } finally {
            frame.dispose();
          }
        });
      },
      timeout: _testTimeout,
    );

    testWidgets(
      '$mode/DPR2: wheel and fitted trackpad retire real header and retain pixels',
      (tester) async {
        await _withModal(tester, photo, mode, (fixture) async {
          final viewerState = tester.state(_viewer);
          final transform = _transform(tester);
          final imageState = tester.state(_image(photo));
          final decoded = _decoded(tester, photo);
          final pixels = await _pixels(tester, decoded);
          final frame = _paintedRect(tester, _image(photo));
          final imageSize = tester.getSize(_image(photo));
          final header = find.byKey(_header, skipOffstage: false);
          final title = find.byKey(_title, skipOffstage: false);
          final fit =
              find.byType(DocumentViewportFitButton, skipOffstage: false);
          final headerElement = tester.element(header);
          final headerTop = tester.getTopLeft(header).dy;
          final titleTop = tester.getTopLeft(title).dy;
          final fitTop = tester.getTopLeft(fit).dy;
          final closeRect = tester.getRect(find.byKey(_close));
          final scope = _scope(tester);
          final page = _page(tester);
          final extent = page.outerController.position.maxScrollExtent;
          expect(extent, greaterThan(40));
          expect(tester.widget<InteractiveViewer>(_viewer).constrained, isTrue);
          expect(
            tester.widget<InteractiveViewer>(_viewer).clipBehavior,
            Clip.hardEdge,
          );
          expect(
            tester
                .widget<NestedScrollView>(find.byType(NestedScrollView))
                .clipBehavior,
            Clip.hardEdge,
          );

          void retained() {
            final offset = page.outerController.offset;
            expect(tester.state(_viewer), same(viewerState));
            expect(_transform(tester), same(transform));
            expect(transform.value.isIdentity(), isTrue);
            expect(tester.state(_image(photo)), same(imageState));
            expect(_decoded(tester, photo), same(decoded));
            expect(tester.getSize(_image(photo)), imageSize);
            final current = _paintedRect(tester, _image(photo));
            expect(current.width, closeTo(frame.width, .01));
            expect(current.height, closeTo(frame.height, .01));
            expect(current.top, closeTo(frame.top - offset, .01));
            expect(tester.element(header), same(headerElement));
            expect(
              tester.getTopLeft(header).dy,
              closeTo(headerTop - offset, .01),
            );
            expect(
              tester.getTopLeft(title).dy,
              closeTo(titleTop - offset, .01),
            );
            expect(tester.getTopLeft(fit).dy, closeTo(fitTop - offset, .01));
            expect(tester.getRect(find.byKey(_close)), closeRect);
            expect(_scope(tester).chrome, same(scope.chrome));
          }

          await _wheel(tester, 40);
          expect(page.outerController.offset, closeTo(40, .01));
          retained();
          await _wheel(tester, extent);
          expect(page.outerController.offset, closeTo(extent, .01));
          retained();
          expect(header.hitTestable(), findsNothing);
          expect(fit.hitTestable(), findsNothing);
          expect(find.byKey(_close).hitTestable(), findsOneWidget);
          await _wheel(tester, -extent);
          expect(page.outerController.offset, closeTo(0, .01));
          retained();

          final point = _point(tester);
          final pan =
              await tester.createGesture(kind: PointerDeviceKind.trackpad);
          await pan.panZoomStart(point);
          await pan.panZoomUpdate(
            point,
            pan: const Offset(0, -4),
            timeStamp: const Duration(milliseconds: 16),
          );
          await tester.pump();
          expect(page.outerController.offset, 0);
          for (var i = 1; i <= 16; i++) {
            await pan.panZoomUpdate(
              point,
              pan: Offset(0, -4 - i * 32.0),
              timeStamp: Duration(milliseconds: 16 + i * 16),
            );
            await tester.pump(const Duration(milliseconds: 16));
            retained();
          }
          await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 400));
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
          expect(page.outerController.offset, closeTo(extent, .01));
          expect(fit.hitTestable(), findsNothing);
          await tester.pump(const Duration(seconds: 1));
          expect(page.outerController.offset, closeTo(extent, .01));
          retained();
          await _pan(tester, dy: 32);
          expect(page.outerController.offset, closeTo(0, .01));
          retained();
          _expectTools(tester);
          expect(await _pixels(tester, decoded), orderedEquals(pixels));
          expect(fixture.provider.requests, hasLength(1));
          expect(fixture.ocr.calls, 0);
          expect(tester.takeException(), isNull);
        });
      },
      timeout: _testTimeout,
    );
  }

  for (final sourceChanged in [false, true]) {
    testWidgets(
      'provider scope rejects old photo actions: sourceChanged=$sourceChanged',
      (tester) async {
        await _withModal(tester, photo, 'paper', (fixture) async {
          final oldScope = _scope(tester);
          final fit = tester
              .widget<DocumentViewportFitButton>(
                find.byType(DocumentViewportFitButton),
              )
              .onPressed!;
          final ocr =
              tester.widget<DocumentViewportButton>(_ocrButton).onPressed!;
          final fullscreen = tester
              .widget<DocumentViewportButton>(find.byKey(_fullscreen))
              .onPressed!;
          await clickFileControl(tester, find.byKey(_fullscreen));
          final fullscreenCanRead = tester
              .widget<InteractiveImageViewer>(
                find.byType(InteractiveImageViewer),
              )
              .canReadImage!;
          expect(fullscreenCanRead(), isTrue);
          await tester.sendKeyEvent(
            LogicalKeyboardKey.escape,
            physicalKey: PhysicalKeyboardKey.escape,
          );
          await settleFileControls(tester);
          final oldTransform = _transform(tester);
          oldTransform.value = Matrix4.identity()..scale(2.0);
          if (sourceChanged) {
            fixture.provider.source =
                CollectionSource.local.copyWith(remoteId: 'new-source');
            // No rebuild: activation must consult the live provider generation.
            fit();
            ocr();
            fullscreen();
            expect(oldTransform.value.getMaxScaleOnAxis(), 2);
            expect(oldScope.canRead(), isFalse);
            expect(fullscreenCanRead(), isFalse);
          }
          await clickFileControl(tester, find.byKey(_next));
          expect(oldScope.canRead(), isFalse);
          expect(fullscreenCanRead(), isFalse);
          expect(_scope(tester).canRead(), isFalse);
          expect(_scope(tester).chrome, isNot(same(oldScope.chrome)));
          fit();
          ocr();
          fullscreen();
          fixture.provider.requests.last.result.complete(photo.path);
          await _ready(tester, photo);
          final current = _transform(tester);
          current.value = Matrix4.identity()..scale(1.5);
          fit();
          ocr();
          fullscreen();
          await settleFileControls(tester);
          expect(current.value.getMaxScaleOnAxis(), 1.5);
          expect(find.byType(ImageOcrOverlay), findsNothing);
          expect(find.byType(InteractiveImageViewer), findsNothing);
          expect(fixture.ocr.calls, 0);
          expect(tester.widget<Text>(find.byKey(_title)).data, 'Second photo');
          // Same A identity/path returns, but the original A callbacks stay dead.
          await clickFileControl(tester, find.byKey(_previous));
          fixture.provider.requests.last.result.complete(photo.path);
          await _ready(tester, photo);
          fit();
          ocr();
          fullscreen();
          await settleFileControls(tester);
          expect(oldScope.canRead(), isFalse);
          expect(_scope(tester).canRead(), isTrue);
          expect(find.byType(ImageOcrOverlay), findsNothing);
          expect(find.byType(InteractiveImageViewer), findsNothing);
          expect(fixture.provider.requests, hasLength(3));
          expect(tester.takeException(), isNull);
        });
      },
      timeout: _testTimeout,
    );
  }

  testWidgets(
    'zoomed provider pan stays native, not universal boundary handoff',
    (tester) async {
      await _withModal(tester, photo, 'paper', (fixture) async {
        final transform = _transform(tester);
        final point = _point(tester);
        final pinch =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await pinch.panZoomStart(point);
        for (var i = 1; i <= 5; i++) {
          await pinch.panZoomUpdate(
            point,
            scale: 1 + i * .2,
            timeStamp: Duration(milliseconds: i * 16),
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await pinch.panZoomEnd(timeStamp: const Duration(milliseconds: 300));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 3),
        );
        expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
        final zoomed = transform.value.clone();
        await _pan(tester, dy: -24);
        expect(_page(tester).outerController.offset, 0);
        expect(transform.value, isNot(zoomed));
        await clickFileControl(tester, find.byType(DocumentViewportFitButton));
        expect(transform.value.isIdentity(), isTrue);
        await _pan(tester, dy: -32);
        expect(
          _page(tester).outerController.offset,
          closeTo(_page(tester).outerController.position.maxScrollExtent, .01),
        );
        expect(fixture.provider.requests, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'bare provider photo never borrows a matching outer file scope',
    (tester) async {
      final chrome = StandaloneFileChromeController();
      final node = _node('bare', 'Provider photo');
      var outerReads = 0;
      var outerEdits = 0;
      final initialChrome = chrome.value;
      final activations = <bool>[];
      ui.Image? retainedFrame;
      try {
        await _warm(tester, photo);
        await mountFileControls(
          tester,
          Builder(
            builder: (context) {
              final palette = FolderExplorerPalette.of(context);
              return StandaloneFileScope(
                canvas: palette.background,
                rendererName: providerFileNameFor(node),
                displayName: 'Unrelated outer file',
                chrome: chrome,
                canRead: () {
                  outerReads++;
                  return true;
                },
                canEdit: () {
                  outerEdits++;
                  return true;
                },
                editable: true,
                available: true,
                child: StandaloneFilePage(
                  nativeBodyGestures: true,
                  header:
                      const SizedBox(height: 120, child: Text('Outer file')),
                  // The embed's gate surrounds only the renderer, not its parent
                  // page. Hover/wheel input must not activate native photo gestures.
                  body: ScrollActivationRegion(
                    activateOnFocus: false,
                    onActiveChanged: activations.add,
                    child: externalFileRenderer(
                      node: node,
                      path: photo.path,
                      palette: palette,
                      isAvailable: () => true,
                      // Default bare=true deliberately exercised.
                    ),
                  ),
                ),
              );
            },
          ),
          mode: 'paper',
          reduced: true,
        );
        expect(find.byType(ImageOcrFindRegion), findsOneWidget);
        expect(find.byType(DocumentViewport), findsNothing);
        expect(find.byType(DocumentViewportFitButton), findsNothing);
        expect(find.byKey(_fullscreen), findsNothing);
        final native = tester.widget<InteractiveViewer>(_viewer);
        expect(native.maxScale, 6);
        expect(native.transformationController, isNull);
        expect(native.panEnabled, isTrue);
        expect(native.scaleEnabled, isTrue);
        final image = tester.widget<Image>(find.byType(Image));
        expect((image.image as FileImage).file.path, photo.path);
        final viewerState = tester.state(_viewer);
        final imageState = tester.state(find.byType(Image));
        final page = _page(tester);
        final scope = _scope(tester);
        final transform =
            find.descendant(of: _viewer, matching: find.byType(Transform));
        final rawImage =
            find.descendant(of: _viewer, matching: find.byType(RawImage));
        expect(transform, findsOneWidget);
        expect(rawImage, findsOneWidget);
        final frame = tester.widget<RawImage>(rawImage).image!.clone();
        retainedFrame = frame;
        final fitted = tester.widget<Transform>(transform).transform.clone();
        expect(fitted.isIdentity(), isTrue);
        expect(page.outerController.offset, 0);
        expect(page.outerController.position.maxScrollExtent, greaterThan(40));

        void retained() {
          expect(tester.state(_viewer), same(viewerState));
          expect(tester.state(find.byType(Image)), same(imageState));
          expect(_page(tester), same(page));
          expect(_scope(tester), same(scope));
          expect(
            tester.widget<InteractiveViewer>(_viewer).transformationController,
            isNull,
          );
          expect(
            tester.widget<RawImage>(rawImage).image!.isCloneOf(frame),
            isTrue,
          );
          expect(find.byType(StandaloneFileScope), findsOneWidget);
          expect(find.byType(StandaloneFileHeaderSlot), findsNothing);
          // The outer page has its own header adapter; the bare renderer must
          // neither install one nor sit underneath one in the body.
          expect(
            find.descendant(
              of: find.byType(ImageOcrFindRegion),
              matching: find.byType(StandaloneFileScrollRegion),
            ),
            findsNothing,
          );
          expect(
            find.ancestor(
              of: _viewer,
              matching: find.byType(StandaloneFileScrollRegion),
            ),
            findsNothing,
          );
          expect(chrome.value, same(initialChrome));
          expect(chrome.value.actions, isEmpty);
          expect(outerReads, 0);
          expect(outerEdits, 0);
        }

        expect(
          tester
              .widget<ScrollGestureGate>(find.byType(ScrollGestureGate))
              .blocked,
          isTrue,
        );
        retained();
        await _wheel(tester, 40);
        expect(
          page.outerController.offset,
          closeTo(40, .01),
          reason: 'An unengaged bare preview leaves wheel input to its parent.',
        );
        expect(tester.widget<Transform>(transform).transform, fitted);
        retained();
        // Negative wheel input would zoom in natively, unlike positive input
        // at minimum scale. This proves the gate, not merely the zoom clamp.
        await _wheel(tester, -40);
        expect(page.outerController.offset, closeTo(0, .01));
        expect(tester.widget<Transform>(transform).transform, fitted);
        expect(activations, isEmpty);
        retained();

        await tester.tapAt(_point(tester), kind: PointerDeviceKind.mouse);
        await settleFileControls(tester);
        expect(activations, [true]);
        expect(
          tester
              .widget<ScrollGestureGate>(find.byType(ScrollGestureGate))
              .blocked,
          isFalse,
        );
        expect(
          tester.widget<Transform>(transform).transform,
          fitted,
          reason: 'Activation itself must not reset or reposition the photo.',
        );
        await _wheel(tester, -40);
        expect(
          tester.widget<Transform>(transform).transform.getMaxScaleOnAxis(),
          greaterThan(1),
        );
        // Native InteractiveViewer can zoom AND let a parent scroll. Do not
        // invent an exclusive page-handoff contract for the bare renderer.
        await settleFileControls(tester);
        retained();
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
        retainedFrame?.dispose();
        chrome.dispose();
      }
    },
    timeout: _testTimeout,
  );
}

Finder get _viewer => find.byType(InteractiveViewer);
Finder _image(File file) => find.byKey(ValueKey('${file.path}_0'));
Finder get _ocrButton => find.byWidgetPredicate(
      (widget) =>
          widget is DocumentViewportButton &&
          widget.icon == Icons.document_scanner_rounded,
    );
TransformationController _transform(WidgetTester tester) =>
    tester.widget<InteractiveViewer>(_viewer).transformationController!;
StandaloneFileScope _scope(WidgetTester tester) =>
    tester.widget<StandaloneFileScope>(find.byType(StandaloneFileScope));
NestedScrollViewState _page(WidgetTester tester) =>
    tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
ui.Image _decoded(WidgetTester tester, File file) => tester
    .widget<RawImage>(
      find.descendant(of: _image(file), matching: find.byType(RawImage)),
    )
    .image!;

void _expectTools(WidgetTester tester) {
  final title = tester.getRect(find.byKey(_title));
  final band =
      tester.getRect(find.byKey(const ValueKey('external-file-actions')));
  final edit = find.byWidgetPredicate(
    (widget) =>
        widget is DocumentViewportButton && widget.icon == Icons.tune_rounded,
  );
  expect(tester.widget<DocumentViewportButton>(edit).onPressed, isNull);
  expect(
    tester.widget<DocumentViewportButton>(_ocrButton).onPressed,
    isNotNull,
  );
  expect(
    tester.widget<DocumentViewportButton>(find.byKey(_fullscreen)).onPressed,
    isNotNull,
  );
  final controls = [
    edit,
    _ocrButton,
    find.byType(DocumentViewportFitButton),
    find.byKey(_fullscreen),
    find.byKey(_previous),
    find.byKey(_next),
  ];
  Rect? previous;
  for (final control in controls) {
    expect(
      find.descendant(of: find.byKey(_header), matching: control),
      findsOneWidget,
    );
    final rect = tester.getRect(control);
    expect(rect.top, greaterThanOrEqualTo(title.bottom));
    expect(rect.left, greaterThanOrEqualTo(band.left));
    expect(rect.right, lessThanOrEqualTo(band.right));
    if (previous != null) {
      expect(rect.left, greaterThanOrEqualTo(previous.right));
    }
    previous = rect;
  }
  expect(
    previous!.right,
    closeTo(band.right, .01),
    reason:
        'Actual final button, not just its wrapper, meets the right gutter.',
  );
  expect(find.byKey(_fullscreen).hitTestable(), findsOneWidget);
  expect(
    find.byType(DocumentViewportBar),
    findsNothing,
    reason: 'The duplicate photo header must be hoisted, not painted below.',
  );
}

Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Future<Uint8List> _pixels(WidgetTester tester, ui.Image image) async {
  final data = await tester.runAsync(() => image.toByteData());
  expect(data, isNotNull);
  return Uint8List.fromList(
    data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

Offset _point(WidgetTester tester) =>
    tester.getRect(find.byType(StandaloneFilePage)).bottomCenter -
    const Offset(0, 48);

Future<void> _wheel(WidgetTester tester, double dy) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(position: _point(tester), scrollDelta: Offset(0, dy)),
  );
  await tester.pump();
}

Future<void> _pan(WidgetTester tester, {required double dy}) async {
  final point = _point(tester);
  final pan = await tester.createGesture(kind: PointerDeviceKind.trackpad);
  await pan.panZoomStart(point);
  for (var i = 1; i <= 16; i++) {
    await pan.panZoomUpdate(
      point,
      pan: Offset(0, i * dy),
      timeStamp: Duration(milliseconds: i * 16),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 400));
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}

Future<void> _warm(WidgetTester tester, File file) async {
  // BEFORE mounting Image.file: never await a fake-clock pending completer.
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
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'Bounded native decode/stat/OCR completion.');
  await settleFileControls(tester);
}

Future<void> _ready(WidgetTester tester, File file) => _until(tester, () {
      final headers = tester.widgetList<DocumentViewportHeader>(
        find.byType(DocumentViewportHeader),
      );
      final frames = tester.widgetList<RawImage>(
        find.descendant(of: _image(file), matching: find.byType(RawImage)),
      );
      return _image(file).evaluate().isNotEmpty &&
          headers.length == 1 &&
          headers.single.identity.subtitle != null &&
          frames.length == 1 &&
          frames.single.image?.width == 640;
    });

ProviderNode _node(String id, String name) => ProviderNode(
      id: id, name: name, kind: ProviderNodeKind.image, mimeType: 'image/png',
      // These are never fetched; only the fake materializer returns local bytes.
      downloadUrl: 'https://provider.invalid/original/$id',
      thumbnailUrl: 'https://provider.invalid/thumbnail/$id',
    );

class _Request {
  _Request(this.node);
  final ProviderNode node;
  final result = Completer<String?>();
}

class _Provider extends Fake implements ProviderController {
  @override
  CollectionSource source = CollectionSource.local;
  final requests = <_Request>[];
  @override
  Future<String?> materialize(ProviderNode node) {
    final request = _Request(node);
    requests.add(request);
    return request.result.future;
  }
}

class _Ocr extends OcrService {
  _Ocr() : super(engines: []);
  int calls = 0;
  Uint8List? bytes;
  Size? size;
  @override
  Future<OcrResult> recognizeBytes(
    Uint8List bytes, {
    required Size imageSize,
    OcrCancellationToken? cancellation,
    ValueChanged<String>? onEngineSelected,
  }) async {
    cancellation?.throwIfCancelled();
    calls++;
    this.bytes = Uint8List.fromList(bytes);
    size = imageSize;
    return OcrResult(
      engine: 'Fixture OCR',
      lines: [
        OcrLine.fromWords(const [
          OcrWord(text: 'needle', bounds: Rect.fromLTWH(.1, .1, .2, .05)),
        ]),
      ],
    );
  }
}

class _Fixture {
  final provider = _Provider();
  final ocr = _Ocr();
}

Future<void> _withModal(
  WidgetTester tester,
  File file,
  String mode,
  Future<void> Function(_Fixture) body,
) async {
  final fixture = _Fixture();
  final nodes = [_node('a', 'Provider photo'), _node('b', 'Second photo')];
  tester.view.devicePixelRatio = 2;
  try {
    final originalBytes = await tester.runAsync(file.readAsBytes);
    await _warm(tester, file);
    late BuildContext host;
    await mountFileControls(
      tester,
      Builder(
        builder: (context) {
          host = context;
          return const Text('Host page');
        },
      ),
      mode: mode,
      width: 1100,
      height: 900,
      textScale: 2,
      reduced: true,
    );
    unawaited(
      showExternalFile(
        host,
        controller: fixture.provider,
        node: nodes.first,
        siblings: nodes,
        ocrService: fixture.ocr,
      ),
    );
    await settleFileControls(tester);
    expect(fixture.provider.requests.single.node, same(nodes.first));
    fixture.provider.requests.single.result.complete(file.path);
    await _ready(tester, file);
    await body(fixture);
    expect(
      await tester.runAsync(file.readAsBytes),
      orderedEquals(originalBytes!),
    );
  } finally {
    for (final request in fixture.provider.requests) {
      if (!request.result.isCompleted) request.result.complete(null);
    }
    await unmountFileControls(tester);
    tester.view.resetDevicePixelRatio();
  }
}
