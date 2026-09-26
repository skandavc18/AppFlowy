import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/external_file_stage.dart';
import 'package:appflowy/plugins/collection/views/album/album_lightbox.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_file_stage.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_entry_viewer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_metadata.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'image_ocr_test_support.dart';

// Real secondary hosts, native Image.file/InteractiveViewer and real local
// ImageEditorSource reads. Only OCR and the external materialize boundary are
// injected; every file is a synthetic test-owned PNG.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;
  late File first;
  late File second;
  late Uint8List firstBytes;
  late Uint8List secondBytes;
  late Map<String, dynamic> translations;
  late bool fontFetching;

  setUpAll(() async {
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    translations = await loadOcrTestTranslations();
    firstBytes = await makeOcrTestPng();
    secondBytes = await makeOcrTestPng(color: const Color(0xFF83AC97));
    scratch = await Directory.systemTemp.createTemp('secondary-image-find-');
    first = await File('${scratch.path}/first image # %.png')
        .writeAsBytes(firstBytes, flush: true);
    second = await File('${scratch.path}/second image.png')
        .writeAsBytes(secondBytes, flush: true);
  });

  tearDownAll(() async {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await scratch.delete(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = fontFetching;
  });

  for (final host in _Host.values) {
    testWidgets('${host.name}: hovered opened image owns Find, not Replace',
        (tester) async {
      final fixture = _StageFixture(host, first);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _warm(tester, first);
        await _mount(tester, fixture.build(), translations, mode: host.mode);
        final image = tester.element(_image(first));
        final viewer = tester.state(find.byType(InteractiveViewer));
        final nativeFrame = tester.widget<RawImage>(
          find.descendant(of: _image(first), matching: find.byType(RawImage)),
        );
        expect(nativeFrame.image?.width, 320);
        expect(nativeFrame.image?.height, 180);
        expect(fixture.service.calls, isEmpty);

        fixture.navigation.requestFocus();
        await tester.pump();
        await _command(tester);
        expect(fixture.parentFinds, 1);
        expect(find.byType(ImageOcrOverlay), findsNothing);

        await mouse.addPointer(location: const Offset(-10, -10));
        await mouse.moveTo(tester.getCenter(find.byType(ImageOcrFindRegion)));
        await tester.pump();
        expect(fixture.navigation.hasFocus, isTrue);
        await _command(tester, replace: true);
        expect(fixture.parentFinds, 1);
        expect(fixture.parentReplaces, 0);
        expect(fixture.service.calls, isEmpty);

        await _command(tester);
        _expectSource(tester, first);
        expect(
          _region(tester).isAvailable!(),
          isTrue,
          reason: 'The OCR popup must not invalidate its own owner.',
        );
        await waitForOcrCalls(tester, fixture.service, 1);
        expect(fixture.service.calls.single.bytes, firstBytes);
        await tester.enterText(
          find.byKey(const ValueKey('findTextField')),
          'world',
        );
        fixture.service.calls.single.done.complete(ocrTestResult());
        await tester.pump();
        await tester.pump();
        expect(
          tester.widget<FindReplaceBar>(find.byType(FindReplaceBar)).matchCount,
          2,
        );
        expect(tester.element(_image(first)), same(image));
        expect(tester.state(find.byType(InteractiveViewer)), same(viewer));

        await _escape(tester);
        expect(find.byType(ImageOcrOverlay), findsNothing);
        expect(tester.element(_image(first)), same(image));
        expect(fixture.metadataWrites, 0);
        expect(fixture.closes, 0);
      } finally {
        await mouse.removePointer();
        await _unmount(tester, fixture.service);
        fixture.dispose();
      }
    });

    testWidgets('${host.name}: replacing the displayed source cancels old OCR',
        (tester) async {
      final fixture = _StageFixture(host, first);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _warm(tester, first);
        await _warm(tester, second);
        await _mount(tester, fixture.build(), translations);
        await mouse.addPointer(location: const Offset(-10, -10));
        await mouse.moveTo(tester.getCenter(find.byType(ImageOcrFindRegion)));
        await _command(tester);
        await waitForOcrCalls(tester, fixture.service, 1);
        final oldGuard = _region(tester).isAvailable!;
        final oldScan = fixture.service.calls.single;

        fixture.file.value = second;
        await tester.pump();
        await tester.pump();
        expect(oldGuard(), isFalse);
        expect(oldScan.cancellation!.isCancelled, isTrue);
        expect(find.byType(ImageOcrOverlay), findsNothing);
        oldScan.done.completeError(StateError('Obsolete synthetic scan'));
        await tester.pump();
        expect(_image(second), findsOneWidget);

        await mouse.moveTo(tester.getCenter(find.byType(ImageOcrFindRegion)));
        await _command(tester);
        _expectSource(tester, second);
        await waitForOcrCalls(tester, fixture.service, 2);
        expect(fixture.service.calls.last.bytes, secondBytes);
        expect(
          tester
              .widget<FindReplaceBar>(find.byType(FindReplaceBar))
              .findController
              .text,
          isEmpty,
        );
        fixture.service.calls.last.done.complete(ocrTestResult());
        await tester.pump();
        await _escape(tester);
      } finally {
        await mouse.removePointer();
        await _unmount(tester, fixture.service);
        fixture.dispose();
      }
    });
  }

  testWidgets(
      'external file dialog: no-hover Find uses only materialized image',
      (tester) async {
    final service = ControlledOcrService();
    final provider = _Materializer({'one': first.path, 'two': second.path});
    final pending = provider.pending = Completer<String?>();
    const nodes = [
      ProviderNode(
        id: 'one',
        name: 'First picture',
        kind: ProviderNodeKind.image,
      ),
      ProviderNode(
        id: 'two',
        name: 'Next picture',
        kind: ProviderNodeKind.image,
      ),
    ];
    try {
      await _warm(tester, first);
      await _warm(tester, second);
      await _mount(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showExternalFile(
                context,
                controller: provider,
                node: nodes.first,
                siblings: nodes,
                ocrService: service,
              ),
            ),
            child: const Text('Open external image'),
          ),
        ),
        translations,
      );
      await tester.tap(find.text('Open external image'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ImageOcrFindRegion), findsNothing);
      await _command(tester);
      expect(service.calls, isEmpty);
      expect(provider.requests, ['one']);

      provider.pending = null;
      pending.complete(first.path);
      await tester.pump();
      await tester.pump();
      await _command(tester);
      _expectSource(tester, first);
      await waitForOcrCalls(tester, service, 1);
      expect(service.calls.single.bytes, firstBytes);
      expect(provider.requests, ['one']);
      service.calls.single.done.complete(ocrTestResult());
      await tester.pump();
      await _escape(tester);

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );
      await tester.pump();
      await tester.pump();
      await _command(tester);
      _expectSource(tester, second);
      await waitForOcrCalls(tester, service, 2);
      expect(service.calls.last.bytes, secondBytes);
      expect(provider.requests, ['one', 'two']);
      await _escape(tester);
      expect(service.calls.last.cancellation!.isCancelled, isTrue);
      expect(_image(second), findsOneWidget);
    } finally {
      if (!pending.isCompleted) pending.complete(null);
      await _unmount(tester, service);
    }
  });

  testWidgets('album route: current local picture only; removal retires scan',
      (tester) async {
    final service = ControlledOcrService();
    final media = [
      _albumItem('one', first.path),
      _albumItem('two', second.path),
      _albumItem('video', '', kind: AlbumMediaKind.video),
      _albumItem('audio', '', kind: AlbumMediaKind.audio),
      _albumItem('remote', 'https://unused.example.invalid/picture.png'),
    ];
    final metadata = AlbumMetadataCache();
    for (final item in media) {
      metadata.seed(item.id, const AlbumMediaMetadata());
    }
    final album = AlbumController(
      initialState: const {},
      onPersist: (_) {},
      metadata: metadata,
    )..setItems(media);
    try {
      await _warm(tester, first);
      await _warm(tester, second);
      await _mount(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              showAlbumLightbox(
                context: context,
                controller: album,
                palette: CollectionPalette.of(context, CollectionKind.album),
                startId: 'one',
                ocrService: service,
              ),
            ),
            child: const Text('Open album'),
          ),
        ),
        translations,
        mode: 'paper',
      );
      await tester.tap(find.text('Open album'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(AlbumLightbox), findsOneWidget);

      // Inspect the real lazy host's branches without starting native players.
      final pageFinder = find.byType(PageView);
      final pageContext = tester.element(pageFinder);
      final delegate = tester.widget<PageView>(pageFinder).childrenDelegate
          as SliverChildBuilderDelegate;
      final next = delegate.builder(pageContext, 1)! as ImageOcrFindRegion;
      expect(next.isAvailable!(), isFalse);
      for (final index in [2, 3, 4]) {
        expect(
          delegate.builder(pageContext, index),
          isNot(isA<ImageOcrFindRegion>()),
        );
      }

      await _command(tester); // No mouse, click, or manufactured content focus.
      _expectSource(tester, first);
      await waitForOcrCalls(tester, service, 1);
      expect(service.calls.single.bytes, firstBytes);
      final oldGuard = _region(tester).isAvailable!;
      album.setItems(media.skip(1).toList());
      expect(
        oldGuard(),
        isFalse,
        reason: 'Controller removal must invalidate before the next frame.',
      );
      await tester.pump();
      await tester.pump();
      expect(service.calls.single.cancellation!.isCancelled, isTrue);
      service.calls.single.done.complete(ocrTestResult(engine: 'Obsolete'));
      await tester.pump();
      expect(find.byType(ImageOcrOverlay), findsNothing);
      expect(find.textContaining('Obsolete'), findsNothing);
      await tester.tap(find.byTooltip(LocaleKeys.collections_album_close.tr()));
      await tester.pump();
      await tester.pump();
      expect(find.byType(AlbumLightbox), findsNothing);
    } finally {
      await _unmount(tester, service);
      album.dispose();
    }
  });
}

enum _Host {
  archive,
  repository,
  external;

  String get mode => switch (this) {
        archive => 'paper',
        repository => 'dark',
        external => 'light',
      };
}

class _StageFixture {
  _StageFixture(this.host, File initial) : file = ValueNotifier(initial);

  final _Host host;
  final ValueNotifier<File> file;
  final service = ControlledOcrService();
  final navigation = FocusNode();
  int parentFinds = 0;
  int parentReplaces = 0;
  int metadataWrites = 0;
  int closes = 0;

  Widget build() => ContextualFindScope(
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: TextButton(
                focusNode: navigation,
                onPressed: () {},
                child: const Text('Navigation'),
              ),
            ),
            Expanded(
              child: ContextualFindRegion(
                onFind: () => parentFinds++,
                onReplace: () => parentReplaces++,
                child: ValueListenableBuilder<File>(
                  valueListenable: file,
                  builder: (context, file, _) => switch (host) {
                    _Host.archive => ArchiveEntryViewer(
                        file: file,
                        name: 'Opened image.png',
                        path: 'pictures/opened.png',
                        archiveName: 'Synthetic.zip',
                        editable: false,
                        metadata: const {},
                        onMetadataChanged: (_) => metadataWrites++,
                        onClose: () => closes++,
                        ocrService: service,
                      ),
                    _Host.repository => RepoFileStage(
                        entry: RepoEntry(
                          view: ViewPB(id: 'opened', name: 'Opened image.png'),
                          kind: RepoEntryKind.asset,
                          path: 'pictures/opened.png',
                          depth: 1,
                          parentPath: 'pictures',
                          storageUrl: file.path,
                        ),
                        theme: RepoTheme.of(
                          context,
                          CollectionPalette.of(
                            context,
                            CollectionKind.repository,
                          ),
                        ),
                        ocrService: service,
                      ),
                    _Host.external => externalFileRenderer(
                        node: const ProviderNode(
                          id: 'opened',
                          name: 'Provider picture',
                          kind: ProviderNodeKind.image,
                        ),
                        path: file.path,
                        palette: FolderExplorerPalette.of(context),
                        ocrService: service,
                        isAvailable: () => this.file.value.path == file.path,
                      ),
                  },
                ),
              ),
            ),
          ],
        ),
      );

  void dispose() {
    file.dispose();
    navigation.dispose();
  }
}

class _Materializer extends Fake implements ProviderController {
  _Materializer(this.files);
  final Map<String, String> files;
  final requests = <String>[];
  Completer<String?>? pending;

  @override
  Future<String?> materialize(ProviderNode node) {
    requests.add(node.id);
    return pending?.future ?? Future.value(files[node.id]);
  }
}

AlbumMediaItem _albumItem(
  String id,
  String path, {
  AlbumMediaKind kind = AlbumMediaKind.image,
}) =>
    AlbumMediaItem(
      view: ViewPB(
        id: id,
        name: '$id.${kind == AlbumMediaKind.image ? 'png' : kind.name}',
        extra: WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          storageUrl: 'https://unused.example.invalid/original',
        ).mergeIntoExtra(''),
      ),
      kind: kind,
      path: path,
      index: switch (id) {
        'one' => 0,
        'two' => 1,
        'video' => 2,
        'audio' => 3,
        _ => 4
      },
    );

ImageOcrFindRegion _region(WidgetTester tester) =>
    tester.widget(find.byType(ImageOcrFindRegion));

Finder _image(File file) => find.byWidgetPredicate(
      (widget) => widget is Image && widget.image == FileImage(file),
    );

void _expectSource(WidgetTester tester, File file) {
  final source =
      tester.widget<ImageOcrOverlay>(find.byType(ImageOcrOverlay)).source;
  expect(source.runtimeType, ImageEditorSource);
  expect(source.url, file.path);
  expect(source.type, CustomImageType.local);
  expect(source.userProfile, isNull);
}

Future<void> _mount(
  WidgetTester tester,
  Widget child,
  Map<String, dynamic> translations, {
  String mode = 'light',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1100, 800);
  await tester
      .pumpWidget(ocrTestApp(child, mode: mode, translations: translations));
  await tester.pump();
  await tester.pump();
}

Future<void> _warm(WidgetTester tester, File file) async {
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
      await ready.future.timeout(const Duration(seconds: 5));
    } finally {
      stream.removeListener(listener);
    }
  });
}

Future<void> _command(WidgetTester tester, {bool replace = false}) async {
  await tester.sendKeyDownEvent(
    LogicalKeyboardKey.controlLeft,
    physicalKey: PhysicalKeyboardKey.controlLeft,
  );
  await tester.sendKeyEvent(
    replace ? LogicalKeyboardKey.keyH : LogicalKeyboardKey.keyF,
    physicalKey: replace ? PhysicalKeyboardKey.keyH : PhysicalKeyboardKey.keyF,
  );
  await tester.sendKeyUpEvent(
    LogicalKeyboardKey.controlLeft,
    physicalKey: PhysicalKeyboardKey.controlLeft,
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(
    LogicalKeyboardKey.escape,
    physicalKey: PhysicalKeyboardKey.escape,
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _unmount(WidgetTester tester, ControlledOcrService service) async {
  await tester.pumpWidget(const SizedBox.shrink());
  service.finishPending();
  await tester.pump();
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
  expect(tester.takeException(), isNull);
}
