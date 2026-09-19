import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/env/backend_env.dart';
import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/album/album_lightbox.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_toolbar.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_view.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_metadata.dart';
import 'package:appflowy/workspace/application/collections/album/album_state.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:archive/archive.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
// Test-only font IO hook; no application widget or renderer is substituted.
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as font_io;
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_descriptor.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_family_with_variant.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_variant.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'test_asset_bundle.dart';

const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');
const _copied = ValueKey('media-copied');
const _capture = ValueKey('fullscreen-action-capture');
const _fade = Duration(milliseconds: 141);
const _cloud = 'https://workspace.example.test/api/file_storage/w/v1/blob/a';
const _pdfText = 'Selected PDF text stays text';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File photo;
  late File secondPhoto;
  late File unknown;
  late _TrackedTextFile text;
  late File json;
  late File archive;
  late Uint8List originalPhotoBytes;
  late ui.Image pdfRaster;
  late PdfDocumentFactory nativePdfFactory;
  late _PdfFactory pdfFactory;
  late bool originalFontFetching;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    originalFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    // The source editor requests JetBrains Mono, which is not bundled. Load
    // our bundled mono bytes under that family via the package's test hook,
    // before the widget clock starts. Control/theme fonts remain the real ones.
    await font_io.loadFontIfNecessary(
      GoogleFontsDescriptor(
        familyWithVariant: const _BundledMono(),
        file: GoogleFontsFile('unused-bundled-fixture', 0),
      ),
    );
    temporary = await Directory.systemTemp.createTemp('fullscreen-actions-');
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFFBD7950), BlendMode.src);
    final picture = recorder.endRecording();
    pdfRaster = await picture.toImage(40, 30);
    picture.dispose();
    final bytes = (await pdfRaster.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    photo = await File('${temporary.path}/materialized first.png')
        .writeAsBytes(bytes);
    // A distinct, larger original: forwarding the displayed thumbnail must
    // fail payload assertions, not merely a path-name assertion.
    final originalRecorder = ui.PictureRecorder();
    Canvas(originalRecorder).drawColor(const Color(0xFF407BBE), BlendMode.src);
    final originalPicture = originalRecorder.endRecording();
    final originalImage = await originalPicture.toImage(160, 120);
    originalPhotoBytes =
        (await originalImage.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
    originalImage.dispose();
    originalPicture.dispose();
    secondPhoto = await File('${temporary.path}/materialized second.png')
        .writeAsBytes(originalPhotoBytes);
    unknown = await File('${temporary.path}/materialized.bin')
        .writeAsString('synthetic attachment');
    text = _TrackedTextFile(
      await File('${temporary.path}/notes.txt')
          .writeAsString('Real editable file\nSecond line\n'),
    );
    json = await File('${temporary.path}/record.json')
        .writeAsString('{"fixture": "actual JSON renderer"}');
    archive = await File('${temporary.path}/empty.zip')
        .writeAsBytes(ZipEncoder().encode(Archive())!);
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final family in ['light', 'dark', 'paper']
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet()) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
    nativePdfFactory = PdfDocumentFactory.instance;
  });

  setUp(() {
    pdfFactory = _PdfFactory(pdfRaster);
    PdfDocumentFactory.instance = pdfFactory;
  });

  tearDown(() {
    PdfDocumentFactory.instance = nativePdfFactory;
  });

  tearDownAll(() async {
    await text.finishWrites();
    GoogleFonts.config.allowRuntimeFetching = originalFontFetching;
    font_io.clearCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    pdfRaster.dispose();
    // Delete individually so a leaked fixture handle identifies its file.
    // Do not suppress cleanup failures or touch any application/user directory.
    for (final file in [photo, secondPhoto, unknown, text, json, archive]) {
      await file.delete();
    }
    final exports = Directory('${temporary.path}/appflowy_media');
    if (await exports.exists()) await exports.delete(recursive: true);
    await temporary.delete();
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final image in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'workspace $mode/$scale ${image ? 'image' : 'unknown'} '
            'uses local bytes and original name in a tight pane',
            (tester) async {
          final actions = _Actions();
          final materialized = image ? photo : unknown;
          final name = image ? 'Étude # 100%.PNG' : 'Original # 100%.unknown';
          final view = _view('workspace', name, _cloud);
          final loader = _Files({name: materialized});
          final mouse =
              await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          try {
            await mouse.addPointer(location: const Offset(900, 900));
            await _warmPhoto(tester, photo);
            await _mount(
              tester,
              mode: mode,
              scale: scale,
              size: const Size(320, 260),
              child: WorkspaceFileView(
                view: view,
                mediaActions: actions,
                resolveStorageUrl: _storedUrl,
                materializeFile: loader.load,
              ),
            );
            await _pumpUntil(tester, () => _target(tester).source.isNotEmpty);
            if (image) {
              // The real image header asynchronously reads its size. Establish
              // the layout baseline after that read, not during it.
              await _pumpUntil(
                tester,
                () =>
                    tester
                        .widget<DocumentViewportHeader>(
                          find.byType(DocumentViewportHeader),
                        )
                        .identity
                        .subtitle !=
                    null,
              );
            }
            final renderer = image
                ? find.byType(InteractiveViewer)
                : find.text('AppFlowy has no viewer for this file type yet.');
            final originalRenderer = tester.widget(renderer);
            final beforeBounds = tester.getRect(renderer);
            expect(find.byKey(_copy).hitTestable(), findsNothing);
            await tester.tapAt(tester.getCenter(find.byKey(_copy)));
            expect(actions.calls, isEmpty);
            await mouse.moveTo(const Offset(40, 180));
            await _motion(tester);
            expect(find.byKey(_copy).hitTestable(), findsOneWidget);
            expect(tester.widget(renderer), same(originalRenderer));
            expect(tester.getRect(renderer), beforeBounds);
            expect(loader.requests, [(source: _cloud, name: name)]);
            expect(_target(tester).source, materialized.path);
            expect(_target(tester).name, name);
            expect(_target(tester).isImage, image);
            expect(_target(tester).httpHeaders, isEmpty);
            expect(_target(tester).requireAuthentication, isFalse);
            _expectSurface(tester, mode);
            final before = await _pixels(tester);
            await tester.tap(find.byKey(_copy));
            await tester.pump();
            expect(actions.calls.single.source, _target(tester));
            expect(find.byKey(_copied), findsNothing);
            expect(_button(tester, _copy).onPressed, isNull);
            expect(_button(tester, _share).onPressed, isNull);
            actions.calls.single.succeed();
            await _motion(tester);
            final badge = _expectBadge(tester);
            expect(tester.getRect(renderer), beforeBounds);
            expect(
              _changedPixels(before, await _pixels(tester), badge),
              greaterThan(4),
            );
            await tester.tap(find.byKey(_share));
            await tester.pump();
            expect(actions.calls.last.kind, 'share');
            expect(actions.calls.last.source.source, materialized.path);
            expect(actions.calls.last.source.name, name);
            expect(
              actions.calls.last.origin,
              tester.getRect(find.byKey(_share)),
            );
            actions.calls.last.succeed();
            await _motion(tester);
            expect(find.byKey(_copied), findsNothing);
            expect(loader.requests, hasLength(1));
            expect(tester.takeException(), isNull);
          } finally {
            await mouse.removePointer();
            await _unmount(tester, actions);
          }
        });
      }
    }

    for (final kind in ['text', 'json', 'archive']) {
      testWidgets(
          'workspace $mode: $kind renderer and controls are independent',
          (tester) async {
        final actions = _Actions();
        final file = switch (kind) {
          'text' => text,
          'json' => json,
          _ => archive,
        };
        final name = file.uri.pathSegments.last;
        final loader = _Files({name: file});
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: const Offset(900, 900));
          await _mount(
            tester,
            mode: mode,
            child: WorkspaceFileView(
              view: _view('file-$kind', name, file.path),
              mediaActions: actions,
              resolveStorageUrl: _storedUrl,
              materializeFile: loader.load,
            ),
          );
          await _pumpUntil(
            tester,
            () => kind == 'text'
                ? find.byType(EditableText).evaluate().isNotEmpty
                : kind == 'archive'
                    ? find.text('This archive is empty').evaluate().isNotEmpty
                    : find.byType(CircularProgressIndicator).evaluate().isEmpty,
          );
          final renderer = kind == 'archive'
              ? find.byType(ArchiveExplorer)
              : find.byType(FilePreview);
          final state = tester.state(renderer);
          final widget = tester.widget(renderer);
          TextEditingController? controller;
          if (kind == 'text') {
            final field = find.byType(EditableText).first;
            controller = tester.widget<EditableText>(field).controller;
            await tester.enterText(field, 'Draft stays here while copying');
            await tester.pump();
          }
          await mouse.moveTo(const Offset(30, 90));
          await _motion(tester);
          await tester.tap(find.byKey(_copy));
          await tester.pump();
          expect(actions.calls.single.source.isImage, isFalse);
          expect(actions.calls.single.source.source, file.path);
          actions.calls.single.fail();
          await _motion(tester);
          expect(
            _button(tester, _copy).tooltip,
            LocaleKeys.message_copy_fail.tr(),
          );
          expect(find.byKey(_copied), findsNothing);
          expect(tester.state(renderer), same(state));
          expect(tester.widget(renderer), same(widget));
          if (controller != null) {
            expect(controller.text, 'Draft stays here while copying');
            expect(
              tester
                  .widget<EditableText>(find.byType(EditableText).first)
                  .controller,
              same(controller),
            );
          }
          await tester.tap(find.byKey(_copy));
          await tester.pump();
          actions.calls.last.succeed();
          await _motion(tester);
          expect(find.byKey(_copied), findsOneWidget);
          expect(loader.requests, hasLength(1));
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await _unmount(tester, actions);
          if (kind == 'text') await tester.runAsync(text.finishWrites);
        }
      });
    }
  }

  testWidgets(
      'workspace: Tab reveals hidden actions and pending focus survives',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final actions = _Actions();
    final loader = _Files({'file.unknown': unknown});
    try {
      await _mount(
        tester,
        reduced: true,
        child: WorkspaceFileView(
          view: _view('keyboard', 'file.unknown', unknown.path),
          resolveStorageUrl: _storedUrl,
          materializeFile: loader.load,
          mediaActions: actions,
        ),
      );
      await _pumpUntil(tester, () => _target(tester).source.isNotEmpty);
      expect(find.semantics.byLabel('Copy'), findsNothing);
      await _tabTo(tester, _button(tester, _copy).focusNode!);
      expect(find.semantics.byLabel('Copy'), findsOneWidget);
      expect(_revealFor(tester, _copy).duration, Duration.zero);
      expect(
        tester
            .getSemantics(find.byKey(_copy))
            .hasFlag(ui.SemanticsFlag.isButton),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(actions.calls.single.kind, 'copy');
      await tester.pump(const Duration(seconds: 5));
      expect(_revealFor(tester, _copy).opacity, 1);
      actions.calls.single.succeed();
      await _motion(tester);
      expect(_button(tester, _copy).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _motion(tester);
      expect(_button(tester, _share).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(actions.calls.last.kind, 'share');
      actions.calls.last.succeed();
      await _motion(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await _motion(tester);
      expect(find.semantics.byLabel('Copy'), findsNothing);
      expect(find.semantics.byLabel('Share'), findsNothing);
      expect(find.byKey(_share).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
      await _unmount(tester, actions);
    }
  });

  for (final fail in [false, true]) {
    testWidgets(
        'workspace: rebinding rejects late ${fail ? 'failure' : 'success'} '
        'and serializes operations', (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _Actions();
      final nextFile = Completer<File>();
      final view =
          ValueNotifier(_view('same-id', 'first.unknown', 'first-source'));
      Future<File> load({required String source, required String name}) =>
          name == 'first.unknown' ? Future.value(unknown) : nextFile.future;
      try {
        await _mount(
          tester,
          accessible: true,
          child: ValueListenableBuilder<ViewPB>(
            valueListenable: view,
            builder: (_, value, __) => WorkspaceFileView(
              view: value,
              resolveStorageUrl: _storedUrl,
              materializeFile: load,
              mediaActions: actions,
            ),
          ),
        );
        await _pumpUntil(tester, () => _target(tester).source.isNotEmpty);
        final state = tester.state(find.byType(MediaActionButtons));
        final obsolete = _button(tester, _share).onPressed!;
        await tester.tap(find.byKey(_copy));
        await tester.pump();
        final pending = actions.calls.single;
        view.value = _view('same-id', 'renamed # %.unknown', 'second-source');
        await tester.pump();
        await tester.pump();
        expect(_target(tester).source, isEmpty);
        expect(find.byKey(_copy).hitTestable(), findsNothing);
        expect(find.semantics.byLabel('Copy'), findsNothing);
        expect(find.semantics.byLabel('Share'), findsNothing);
        obsolete();
        expect(actions.calls, hasLength(1));
        nextFile.complete(secondPhoto);
        await _motion(tester);
        expect(_target(tester).source, secondPhoto.path);
        expect(_target(tester).name, 'renamed # %.unknown');
        expect(tester.state(find.byType(MediaActionButtons)), same(state));
        expect(_button(tester, _copy).onPressed, isNull);
        expect(_button(tester, _share).onPressed, isNull);
        if (fail) {
          pending.fail();
        } else {
          pending.succeed();
        }
        await _motion(tester);
        expect(find.byKey(_copied), findsNothing);
        expect(_button(tester, _copy).tooltip, LocaleKeys.editor_copy.tr());
        obsolete();
        expect(actions.calls, hasLength(1));
        await tester.tap(find.byKey(_share));
        await tester.pump();
        expect(actions.calls.last.source.source, secondPhoto.path);
        expect(actions.calls.last.source.name, 'renamed # %.unknown');
        actions.calls.last.succeed();
        await _motion(tester);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _unmount(tester, actions);
        view.dispose();
      }
    });
  }

  testWidgets(
      'workspace: an obsolete resolver cannot replace the current source',
      (tester) async {
    final actions = _Actions();
    final first = Completer<String?>();
    final view = ValueNotifier(_view('old', 'old.unknown', 'old'));
    final loader = _Files({'old.unknown': unknown, 'new.unknown': secondPhoto});
    Future<String?> resolve(ViewPB value) =>
        value.id == 'old' ? first.future : Future.value('new');
    try {
      await _mount(
        tester,
        accessible: true,
        child: ValueListenableBuilder<ViewPB>(
          valueListenable: view,
          builder: (_, value, __) => WorkspaceFileView(
            view: value,
            resolveStorageUrl: resolve,
            materializeFile: loader.load,
            mediaActions: actions,
          ),
        ),
      );
      expect(find.byKey(_copy).hitTestable(), findsNothing);
      view.value = _view('new', 'new.unknown', 'new');
      await _motion(tester);
      expect(_target(tester).source, secondPhoto.path);
      first.complete('old');
      await _motion(tester);
      expect(_target(tester).source, secondPhoto.path);
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      expect(actions.calls.single.source.name, 'new.unknown');
      actions.calls.single.succeed();
      await _motion(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
      view.dispose();
    }
  });

  testWidgets(
      'workspace: failed resolution exposes no actions and retry recovers',
      (tester) async {
    final actions = _Actions();
    var attempts = 0;
    Future<File> load({required String source, required String name}) async {
      if (++attempts == 1) {
        throw const FileSystemException('Synthetic missing file');
      }
      return unknown;
    }

    try {
      await _mount(
        tester,
        accessible: true,
        child: WorkspaceFileView(
          view: _view('retry', 'retry.unknown', 'synthetic'),
          resolveStorageUrl: _storedUrl,
          materializeFile: load,
          mediaActions: actions,
        ),
      );
      await _motion(tester);
      expect(find.text('This file could not be opened'), findsOneWidget);
      expect(find.byKey(_copy).hitTestable(), findsNothing);
      await tester.tap(find.text('Try again'));
      await _motion(tester);
      expect(attempts, 2);
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      expect(actions.calls.single.source.source, unknown.path);
      actions.calls.single.succeed();
      await _motion(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
    }
  });

  testWidgets('workspace: default local resolver/materializer needs no backend',
      (tester) async {
    final actions = _Actions();
    try {
      await _mount(
        tester,
        accessible: true,
        child: WorkspaceFileView(
          view: _view('default-local', 'original.unknown', unknown.path),
          mediaActions: actions,
        ),
      );
      await _pumpUntil(tester, () => _target(tester).source == unknown.path);
      await tester.tap(find.byKey(_share));
      await tester.pump();
      expect(actions.calls.single.source.source, unknown.path);
      expect(actions.calls.single.source.name, 'original.unknown');
      actions.calls.single.succeed();
      await _motion(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
    }
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'album $mode/$scale: real lightbox route has an unclipped badge',
          (tester) async {
        final actions = _Actions();
        final album = _album([_item('one', 'Photo # %.PNG', photo.path)]);
        try {
          await _warmPhoto(tester, photo);
          await _mount(
            tester,
            mode: mode,
            scale: scale,
            size: const Size(320, 380),
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  showAlbumLightbox(
                    context: context,
                    controller: album,
                    palette:
                        CollectionPalette.of(context, CollectionKind.album),
                    startId: 'one',
                    mediaActions: actions,
                  ),
                ),
                child: const Text('Open album'),
              ),
            ),
          );
          await tester.tap(find.text('Open album'));
          await tester.pumpAndSettle();
          expect(find.byType(AlbumLightbox), findsOneWidget);
          expect(find.byType(InteractiveViewer), findsOneWidget);
          expect(_target(tester).source, photo.path);
          expect(_target(tester).isImage, isTrue);
          _expectSurface(tester, mode);
          final before = await _pixels(tester);
          await tester.tap(find.byKey(_copy));
          await tester.pump();
          actions.calls.single.succeed();
          await _motion(tester);
          final badge = _expectBadge(tester);
          expect(badge.top, greaterThan(54));
          expect(
            _changedPixels(before, await _pixels(tester), badge),
            greaterThan(4),
          );
          await tester.tap(find.byKey(_share));
          await tester.pump();
          expect(actions.calls.last.source.name, 'Photo # %.PNG');
          expect(actions.calls.last.origin, tester.getRect(find.byKey(_share)));
          actions.calls.last.succeed();
          await _motion(tester);
          expect(find.byKey(_copied), findsNothing);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(AlbumLightbox), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester, actions);
          album.dispose();
        }
      });
    }
  }

  for (final reduced in [false, true]) {
    testWidgets(
        'album: root autofocus does not pin chrome; control focus/activity '
        'does (reduced=$reduced)', (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _Actions();
      final album = _album([_item('one', 'Photo.png', photo.path)]);
      try {
        await _warmPhoto(tester, photo);
        await _mount(
          tester,
          reduced: reduced,
          child: _lightbox(album, actions),
        );
        await _motion(tester);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'album-lightbox',
        );
        await tester.pump(const Duration(seconds: 4));
        await _motion(tester);
        expect(_revealFor(tester, _copy).opacity, 0);
        expect(find.semantics.byLabel('Copy'), findsNothing);
        expect(find.semantics.byLabel('Share'), findsNothing);
        expect(find.byKey(_copy).hitTestable(), findsNothing);
        await tester.tapAt(tester.getCenter(find.byKey(_copy)));
        expect(actions.calls, isEmpty);
        await _tabTo(tester, _button(tester, _copy).focusNode!);
        expect(_revealFor(tester, _copy).opacity, 1);
        expect(
          _revealFor(tester, _copy).duration,
          reduced ? Duration.zero : const Duration(milliseconds: 140),
        );
        await tester.pump(const Duration(seconds: 5));
        expect(find.byKey(_copy).hitTestable(), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(actions.calls.single.kind, 'copy');
        FocusManager.instance.primaryFocus?.unfocus();
        await _motion(tester);
        await tester.pump(const Duration(seconds: 5));
        expect(_revealFor(tester, _copy).opacity, 1);
        expect(_button(tester, _share).onPressed, isNull);
        actions.calls.single.succeed();
        await _motion(tester);
        expect(find.byKey(_copied), findsOneWidget);
        expect(_revealFor(tester, _copy).opacity, 1);
        await tester.pump(const Duration(seconds: 4));
        await _motion(tester);
        expect(_revealFor(tester, _copy).opacity, 0);
        expect(find.semantics.byLabel('Copy'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _unmount(tester, actions);
        album.dispose();
      }
    });
  }

  testWidgets(
      'album: keyboard navigation rebinds pending actions to displayed item',
      (tester) async {
    final actions = _Actions();
    final writes = <Map<String, dynamic>>[];
    final album = _album(
      [
        _item('one', 'First.png', photo.path),
        _item('two', 'Second # %.png', secondPhoto.path, index: 1),
      ],
      onPersist: writes.add,
    );
    try {
      await _warmPhoto(tester, photo);
      await _warmPhoto(tester, secondPhoto);
      await _mount(tester, child: _lightbox(album, actions));
      await _motion(tester);
      final state = tester.state(find.byType(MediaActionButtons));
      final stale = _button(tester, _share).onPressed!;
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(album.state.selectedId, 'two');
      expect(_target(tester).source, secondPhoto.path);
      expect(_target(tester).name, 'Second # %.png');
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      expect(_button(tester, _share).onPressed, isNull);
      stale();
      expect(actions.calls, hasLength(1));
      actions.calls.single.succeed();
      await _motion(tester);
      expect(find.byKey(_copied), findsNothing);
      await tester.tap(find.byKey(_share));
      await tester.pump();
      expect(actions.calls.last.source.source, secondPhoto.path);
      actions.calls.last.succeed();
      await _motion(tester);
      album.flush();
      expect(writes, isNotEmpty);
      await tester
          .tap(find.byTooltip(LocaleKeys.collections_album_favourite.tr()));
      await tester.pump();
      expect(album.state.isFavourite('two'), isTrue);
      expect(album.state.isFavourite('one'), isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
      album.dispose();
    }
  });

  for (final target in [
    (id: 'workspace', path: _cloud, auth: true),
    (
      id: 'external',
      path: 'https://photos.example.test/signed.png?ticket=test',
      auth: false
    ),
    (
      id: 'lookalike',
      path: 'https://workspace.example.test.evil.test/api/file_storage/a',
      auth: false
    ),
    (
      id: 'port',
      path: 'https://workspace.example.test:8443/api/file_storage/a',
      auth: false
    ),
    (id: 'provider::photo', path: _cloud, auth: false),
    (
      id: 'non-storage',
      path: 'https://workspace.example.test/other.png',
      auth: false
    ),
  ]) {
    testWidgets(
        'album auth: ${target.id} exports or refuses without leaking credentials',
        (tester) async {
      final actions = _Actions();
      final profile = _Workspace(_profile('test-first'));
      final album = _album([_item(target.id, 'Named photo.png', target.path)]);
      getIt.pushNewScope();
      getIt.registerSingleton<AppFlowyCloudSharedEnv>(_cloudEnvironment());
      try {
        await _mount(
          tester,
          workspace: profile,
          child: _lightbox(album, actions),
        );
        await _motion(tester);
        if (target.id == 'provider::photo') {
          // Correct the earlier expectation: even a matching cloud origin is
          // not proof that a provider view's path holds its original payload.
          expect(find.byType(MediaActionButtons), findsNothing);
          expect(_button(tester, _copy).onPressed, isNull);
          expect(_button(tester, _share).onPressed, isNull);
          expect(
            find.byKey(const ValueKey('album-original-unavailable')),
            findsOneWidget,
          );
          profile.update(_profile('test-renewed'));
          await _motion(tester);
          await tester.tap(find.byKey(_copy));
          await tester.tap(find.byKey(_share));
          expect(actions.calls, isEmpty);
          expect(tester.takeException(), isNull);
          return;
        }
        await tester.tap(find.byKey(_copy));
        await tester.pump();
        final first = actions.calls.single;
        expect(first.source.source, target.path);
        expect(first.source.requireAuthentication, target.auth);
        expect(
          first.source.httpHeaders,
          target.auth ? {'Authorization': 'Bearer test-first'} : isEmpty,
        );
        profile.update(_profile('test-renewed'));
        await _motion(tester);
        first.succeed();
        await _motion(tester);
        expect(
          find.byKey(_copied),
          target.auth ? findsNothing : findsOneWidget,
        );
        await tester.tap(find.byKey(_share));
        await tester.pump();
        expect(
          actions.calls.last.source.httpHeaders,
          target.auth ? {'Authorization': 'Bearer test-renewed'} : isEmpty,
        );
        expect(
          first.source.httpHeaders,
          target.auth ? {'Authorization': 'Bearer test-first'} : isEmpty,
        );
        actions.calls.last.succeed();
        await _motion(tester);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, actions);
        album.dispose();
        await tester.runAsync(profile.close);
        await tester.runAsync(getIt.popScope);
      }
    });
  }

  testWidgets(
      'album: missing cloud profile fails closed, refreshed cache drops auth',
      (tester) async {
    final actions = _Actions();
    final album = _album([_item('same-id', 'Original.png', _cloud)]);
    getIt.pushNewScope();
    getIt.registerSingleton<AppFlowyCloudSharedEnv>(_cloudEnvironment());
    try {
      await _warmPhoto(tester, photo);
      await _mount(tester, child: _lightbox(album, actions));
      await _motion(tester);
      expect(_target(tester).requireAuthentication, isTrue);
      expect(_target(tester).httpHeaders, isEmpty);
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      actions.calls.single.fail();
      await _motion(tester);
      expect(_button(tester, _copy).tooltip, LocaleKeys.message_copy_fail.tr());
      album.setItems([_item('same-id', 'Cached # %.png', photo.path)]);
      await _motion(tester);
      expect(_target(tester).source, photo.path);
      expect(_target(tester).name, 'Cached # %.png');
      expect(_target(tester).requireAuthentication, isFalse);
      expect(_target(tester).httpHeaders, isEmpty);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(_button(tester, _copy).tooltip, LocaleKeys.editor_copy.tr());
      await tester.tap(find.byKey(_share));
      await tester.pump();
      expect(actions.calls.last.source.source, photo.path);
      actions.calls.last.succeed();
      await _motion(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
      album.dispose();
      await tester.runAsync(getIt.popScope);
    }
  });

  testWidgets(
      'album: accessible navigation stays visible and late completion is safe',
      (tester) async {
    final actions = _Actions();
    final album = _album([_item('one', 'Photo.png', photo.path)]);
    try {
      await _warmPhoto(tester, photo);
      await _mount(tester, accessible: true, child: _lightbox(album, actions));
      await tester.pump(const Duration(seconds: 5));
      await _motion(tester);
      expect(_revealFor(tester, _copy).opacity, 1);
      await tester.tap(find.byKey(_share));
      await tester.pump();
      final pending = actions.calls.single;
      await tester.pumpWidget(const SizedBox.shrink());
      pending.fail();
      await _motion(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
      album.dispose();
    }
  });

  for (final mode in ['light', 'dark', 'paper']) {
    for (final cached in [false, true]) {
      testWidgets(
          'album $mode: provider ${cached ? 'cache' : 'URL'} is not an original',
          (tester) async {
        final semantics = tester.ensureSemantics();
        final actions = _Actions();
        final album = _album([
          _item(
            'hosted::photo',
            'Photo.png',
            cached ? photo.path : 'https://photos.example.test/thumb?sig=fake',
          ),
        ]);
        try {
          await _warmPhoto(tester, photo);
          await _mount(
            tester,
            mode: mode,
            scale: 2,
            size: const Size(320, 380),
            accessible: true,
            child: _lightbox(album, actions),
          );
          await _motion(tester);
          expect(find.byType(MediaActionButtons), findsNothing);
          expect(
            find.text('Original file unavailable in this album.'),
            findsOneWidget,
          );
          for (final key in [_copy, _share]) {
            final button = _button(tester, key);
            expect(button.onPressed, isNull);
            expect(button.tooltip, contains('Original file unavailable'));
            final node = tester.getSemantics(find.byKey(key));
            expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
            expect(node.hasFlag(ui.SemanticsFlag.isEnabled), isFalse);
            expect(
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            await tester.tap(find.byKey(key));
          }
          expect(actions.calls, isEmpty);
          expect(find.byKey(_copied), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await _unmount(tester, actions);
          album.dispose();
        }
      });
    }
  }

  for (final provider in [false, true]) {
    testWidgets(
        'album: ${provider ? 'explicit resolver' : 'stored reference'} exports original bytes, not cache pixels',
        (tester) async {
      final boundary = _Exports(temporary);
      final item = _item(
        provider ? 'hosted::photo' : 'workspace-photo',
        'Original # %.png',
        photo.path,
        storedSource: provider ? null : secondPhoto.path,
      );
      final album = _album([item]);
      final resolved = <AlbumMediaItem>[];
      Future<File?> resolve(AlbumMediaItem snapshot) async {
        resolved.add(snapshot);
        return secondPhoto;
      }

      try {
        await _warmPhoto(tester, photo);
        await _mount(
          tester,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showAlbumLightbox(
                  context: context,
                  controller: album,
                  palette: CollectionPalette.of(context, CollectionKind.album),
                  startId: item.id,
                  mediaActions: boundary.actions,
                  resolveOriginalFile: resolve,
                ),
              ),
              child: const Text('Open originals'),
            ),
          ),
        );
        await tester.tap(find.text('Open originals'));
        await tester.pumpAndSettle();
        final displayed = tester.widget<Image>(
          find.descendant(
            of: find.byType(InteractiveViewer),
            matching: find.byType(Image),
          ),
        );
        expect((displayed.image as FileImage).file.path, photo.path);
        expect(
          resolved,
          isEmpty,
          reason: 'No original IO during build/preview',
        );
        expect(boundary.copies, isEmpty);
        expect(boundary.shares, isEmpty);
        await tester.tap(find.byKey(_copy));
        await _pumpUntil(
          tester,
          () =>
              boundary.copies.isNotEmpty &&
              _button(tester, _copy).onPressed != null,
        );
        final copied = await _ExportData.read(boundary.copies.single.single);
        expect(copied.values[Formats.png.providerFormat], originalPhotoBytes);
        final copiedFile =
            File.fromUri((await copied.decode(Formats.fileUri))!);
        expect(
          await tester.runAsync(copiedFile.readAsBytes),
          originalPhotoBytes,
        );
        expect(
          await tester.runAsync(photo.readAsBytes),
          isNot(originalPhotoBytes),
        );
        expect(copiedFile.path, isNot(photo.path));
        expect(boundary.copies.single.single.suggestedName, 'Original # %.png');
        expect(find.byKey(_copied), findsOneWidget);
        await tester.tap(find.byKey(_share));
        await _pumpUntil(
          tester,
          () =>
              boundary.shares.isNotEmpty &&
              _button(tester, _share).onPressed != null,
        );
        final shared = boundary.shares.single;
        expect(
          await tester.runAsync(shared.files.single.readAsBytes),
          originalPhotoBytes,
        );
        expect(shared.names, ['Original # %.png']);
        expect(shared.origin, tester.getRect(find.byKey(_share)));
        expect(shared.files.single.path, isNot(copiedFile.path));
        expect(find.byKey(_copied), findsNothing);
        expect(resolved, hasLength(provider ? 2 : 0));
        if (provider) {
          expect(resolved.first.view, isNot(same(item.view)));
          expect(resolved.first.id, item.id);
          expect(resolved.first.path, photo.path);
          expect(
            () => resolved.first.view.name = 'mutated',
            throwsUnsupportedError,
          );
        }
        expect(boundary.unexpectedRequests, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        boundary.dispose();
        album.dispose();
      }
    });
  }

  for (final cloud in [false, true]) {
    testWidgets(
        'album HTTP: ${cloud ? 'workspace auth' : 'signed external URL'} stays inside the download boundary',
        (tester) async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(originalPhotoBytes, 200);
      });
      final boundary = _Exports(temporary, client: client);
      final workspace = _Workspace(_profile('fake-workspace-token'));
      final album = _album([
        _item(
          'ordinary-photo',
          'Original photo.png',
          cloud
              ? _cloud
              : 'https://photos.example.test/original?sig=fake-signed-token',
        ),
      ]);
      getIt.pushNewScope();
      getIt.registerSingleton<AppFlowyCloudSharedEnv>(_cloudEnvironment());
      try {
        await _mount(
          tester,
          workspace: workspace,
          child: _lightbox(album, boundary.actions),
        );
        await _motion(tester);
        expect(requests, isEmpty);
        await tester.tap(find.byKey(_share));
        await _pumpUntil(tester, () => boundary.shares.isNotEmpty);
        expect(requests.single.url, Uri.parse(album.items.single.path));
        expect(
          requests.single.headers['authorization'],
          cloud ? 'Bearer fake-workspace-token' : isNull,
        );
        expect(
          await tester
              .runAsync(boundary.shares.single.files.single.readAsBytes),
          originalPhotoBytes,
        );
        expect(boundary.shares.single.names, ['Original photo.png']);
        workspace.update(_profile('fake-renewed-token'));
        await _motion(tester);
        await tester.tap(find.byKey(_copy));
        await _pumpUntil(tester, () => boundary.copies.isNotEmpty);
        expect(
          requests.last.headers['authorization'],
          cloud ? 'Bearer fake-renewed-token' : isNull,
        );
        final data = await _ExportData.read(boundary.copies.single.single);
        final exposed = [
          ...data.values.values.whereType<String>(),
          ...boundary.shares
              .expand((share) => share.files.map((file) => file.path)),
          ...boundary.shares.expand((share) => share.names ?? <String>[]),
        ].join(' ');
        for (final secret in [
          'fake-workspace-token',
          'fake-renewed-token',
          'fake-signed-token',
          'https://',
        ]) {
          expect(exposed, isNot(contains(secret)));
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        boundary.dispose();
        album.dispose();
        await tester.runAsync(workspace.close);
        await tester.runAsync(getIt.popScope);
      }
    });
  }

  testWidgets(
      'album route carries a page-scoped live profile, not a stale token',
      (tester) async {
    final actions = _Actions();
    final workspace = _Workspace(_profile('fake-first'));
    final album = _album([_item('cloud', 'Cloud.png', _cloud)]);
    getIt.pushNewScope();
    getIt.registerSingleton<AppFlowyCloudSharedEnv>(_cloudEnvironment());
    try {
      await _mount(
        tester,
        // Deliberately BELOW the Navigator: the dialog cannot inherit this
        // unless the real showAlbumLightbox entry point carries the bloc.
        child: BlocProvider<UserWorkspaceBloc>.value(
          value: workspace,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showAlbumLightbox(
                  context: context,
                  controller: album,
                  palette: CollectionPalette.of(context, CollectionKind.album),
                  startId: 'cloud',
                  mediaActions: actions,
                ),
              ),
              child: const Text('Open cloud album'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open cloud album'));
      await tester.pumpAndSettle();
      expect(
        _target(tester).httpHeaders,
        {'Authorization': 'Bearer fake-first'},
      );
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      workspace.update(_profile('fake-renewed'));
      await _motion(tester);
      actions.calls.single.succeed();
      await _motion(tester);
      expect(find.byKey(_copied), findsNothing);
      await tester.tap(find.byKey(_share));
      await tester.pump();
      expect(
        actions.calls.last.source.httpHeaders,
        {'Authorization': 'Bearer fake-renewed'},
      );
      expect(
        actions.calls.first.source.httpHeaders,
        {'Authorization': 'Bearer fake-first'},
      );
      actions.calls.last.succeed();
      await _motion(tester);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
      album.dispose();
      await tester.runAsync(workspace.close);
      await tester.runAsync(getIt.popScope);
    }
  });

  for (final change in [
    'path',
    'name',
    'item-id',
    'removed',
    'album',
    'profile',
    'resolver',
    'service',
    'dispose',
  ]) {
    testWidgets(
        'album: late original resolution after $change cannot export stale bytes',
        (tester) async {
      final actions = _Actions();
      final replacementActions = _Actions();
      final workspace = _Workspace(_profile('fake-first'));
      final album = _album([
        _item('provider::one', 'Same.png', photo.path),
        _item('provider::two', 'Same.png', photo.path, index: 1),
      ]);
      final replacement =
          _album([_item('provider::one', 'Same.png', photo.path)]);
      final pending = Completer<File?>();
      var resolutions = 0;
      Future<File?> resolve(AlbumMediaItem item) {
        resolutions++;
        return pending.future;
      }

      AlbumOriginalFileResolver resolver = resolve;
      AlbumController controller = album;
      MediaActionService delegate = actions;
      late StateSetter rebind;
      try {
        await _warmPhoto(tester, photo);
        await _warmPhoto(tester, secondPhoto);
        await _mount(
          tester,
          workspace: workspace,
          reduced: true,
          child: StatefulBuilder(
            builder: (context, setState) {
              rebind = setState;
              return _lightbox(
                controller,
                delegate,
                resolveOriginalFile: resolver,
              );
            },
          ),
        );
        await _motion(tester);
        expect(resolutions, 0);
        final state = tester.state(find.byType(MediaActionButtons));
        final obsolete = _button(tester, _share).onPressed!;
        await tester.tap(find.byKey(_copy));
        await tester.pump();
        expect(resolutions, 1);
        expect(actions.calls, isEmpty);
        FocusManager.instance.primaryFocus?.unfocus();
        await _motion(tester);
        await tester.pump(const Duration(seconds: 5));
        expect(_revealFor(tester, _copy).opacity, 1);
        switch (change) {
          case 'path':
            album.setItems(
              [_item('provider::one', 'Same.png', secondPhoto.path)],
            );
          case 'name':
            album.setItems([_item('provider::one', 'Renamed.png', photo.path)]);
          case 'item-id':
            // Same path AND name, only the identity changes.
            final rootFocus = tester.widget<Focus>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Focus &&
                    widget.focusNode?.debugLabel == 'album-lightbox',
              ),
            );
            rootFocus.focusNode!.requestFocus();
            await _motion(tester);
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          case 'removed':
            album.setItems([]);
          case 'album':
            rebind(() => controller = replacement);
          case 'profile':
            // Finish before a widget frame: the guard reads the live bloc.
            workspace.update(_profile('fake-renewed'));
          case 'resolver':
            rebind(() => resolver = (_) async => secondPhoto);
          case 'service':
            rebind(() => delegate = replacementActions);
          case 'dispose':
            await tester.pumpWidget(const SizedBox.shrink());
        }
        if (change != 'profile') await _motion(tester);
        if (change != 'removed' && change != 'dispose') {
          expect(tester.state(find.byType(MediaActionButtons)), same(state));
          expect(_button(tester, _share).onPressed, isNull);
        }
        obsolete();
        pending.complete(secondPhoto);
        await _motion(tester);
        expect(actions.calls, isEmpty);
        expect(replacementActions.calls, isEmpty);
        expect(find.byKey(_copied), findsNothing);
        expect(resolutions, 1);
        if (change != 'removed' && change != 'dispose') {
          expect(_button(tester, _copy).tooltip, LocaleKeys.editor_copy.tr());
          await tester.tap(find.byKey(_share));
          await _motion(tester);
          final call =
              (change == 'service' ? replacementActions : actions).calls.single;
          expect(call.source.source, secondPhoto.path);
          expect(call.source.httpHeaders, isEmpty);
          expect(call.source.requireAuthentication, isFalse);
          expect(
            call.source.name,
            change == 'name' ? 'Renamed.png' : 'Same.png',
          );
          call.succeed();
          await _motion(tester);
        }
        expect(tester.takeException(), isNull);
      } finally {
        if (!pending.isCompleted) pending.complete(null);
        await _unmount(tester, actions);
        await _unmount(tester, replacementActions);
        album.dispose();
        replacement.dispose();
        await tester.runAsync(workspace.close);
      }
    });
  }

  for (final action in [_copy, _share]) {
    testWidgets(
        'album route: $action resolution during closing cannot hand off',
        (tester) async {
      final actions = _Actions();
      final album = _album([_item('provider::photo', 'Photo.png', photo.path)]);
      final pending = Completer<File?>();
      var resolutions = 0;
      Future<File?> resolve(AlbumMediaItem _) {
        resolutions++;
        return pending.future;
      }

      try {
        await _warmPhoto(tester, photo);
        await _mount(
          tester,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showAlbumLightbox(
                  context: context,
                  controller: album,
                  palette: CollectionPalette.of(context, CollectionKind.album),
                  startId: 'provider::photo',
                  mediaActions: actions,
                  resolveOriginalFile: resolve,
                ),
              ),
              child: const Text('Open closing album'),
            ),
          ),
        );
        await tester.tap(find.text('Open closing album'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(action));
        await tester.pump();
        expect(resolutions, 1);
        await tester
            .tap(find.byTooltip(LocaleKeys.collections_album_close.tr()));
        await tester.pump();
        // Still mounted for the closing fade, but no longer the active route.
        expect(find.byType(AlbumLightbox), findsOneWidget);
        final context = tester.element(find.byType(AlbumLightbox));
        expect(ModalRoute.of(context)!.isCurrent, isFalse);
        pending.complete(secondPhoto);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(actions.calls, isEmpty);
        expect(find.byType(AlbumLightbox), findsNothing);
        expect(find.byKey(_copied), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (!pending.isCompleted) pending.complete(null);
        await _unmount(tester, actions);
        album.dispose();
      }
    });
  }

  for (final result in ['missing', 'relative', 'signed-url']) {
    testWidgets('album: $result original result never falls back to thumbnail',
        (tester) async {
      final actions = _Actions();
      final album = _album([_item('provider::photo', 'Photo.png', photo.path)]);
      Future<File?> resolve(AlbumMediaItem _) async => switch (result) {
            'missing' => null,
            'relative' => File('thumbnail.png'),
            _ => File('https://photos.example.test/original?sig=fake-secret'),
          };
      try {
        await _warmPhoto(tester, photo);
        await _mount(
          tester,
          child: _lightbox(album, actions, resolveOriginalFile: resolve),
        );
        await _motion(tester);
        await tester.tap(find.byKey(_copy));
        await _motion(tester);
        expect(actions.calls, isEmpty);
        expect(find.byKey(_copied), findsNothing);
        expect(
          _button(tester, _copy).tooltip,
          LocaleKeys.message_copy_fail.tr(),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, actions);
        album.dispose();
      }
    });
  }

  for (final action in [_copy, _share]) {
    testWidgets(
        'album: resolver $action failure remains visible without exposing tokens',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _Actions();
      final album = _album([_item('provider::photo', 'Photo.png', photo.path)]);
      final pending = Completer<File?>();
      final logs = <String>[];
      final previousPrint = debugPrint;
      Future<File?> resolve(AlbumMediaItem _) => pending.future;
      try {
        debugPrint = (String? value, {int? wrapWidth}) {
          if (value != null) logs.add(value);
        };
        await _warmPhoto(tester, photo);
        await _mount(
          tester,
          child: _lightbox(album, actions, resolveOriginalFile: resolve),
        );
        await _motion(tester);
        await tester.tap(find.byKey(action));
        await tester.pump();
        FocusManager.instance.primaryFocus?.unfocus();
        await _motion(tester);
        pending.completeError(
          StateError(
            'https://provider.example.test/original?sig=fake-signed-secret '
            'Authorization: Bearer fake-auth-secret',
          ),
        );
        await _motion(tester);
        await tester.pump(const Duration(seconds: 6));
        await _motion(tester);
        final label = action == _copy
            ? LocaleKeys.message_copy_fail.tr()
            : LocaleKeys.mediaActions_shareFailed.tr();
        expect(_button(tester, action).tooltip, label);
        expect(_revealFor(tester, action).opacity, 1);
        expect(tester.getSemantics(find.byKey(action)).label, label);
        expect(find.byKey(_copied), findsNothing);
        expect(actions.calls, isEmpty);
        for (final secret in [
          'fake-signed-secret',
          'fake-auth-secret',
          'provider.example.test',
        ]) {
          expect(logs.join('\n'), isNot(contains(secret)));
          expect(find.textContaining(secret), findsNothing);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Tooltip &&
                  (widget.message?.contains(secret) ?? false),
            ),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        debugPrint = previousPrint;
        semantics.dispose();
        if (!pending.isCompleted) pending.complete(null);
        await _unmount(tester, actions);
        album.dispose();
      }
    });
  }

  for (final mode in ['light', 'dark', 'paper']) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'PDF $mode/$scale: actual fullscreen route copies/shares local file',
          (tester) async {
        final actions = _Actions();
        final pdf = await _PdfFixture.prepare(pdfFactory, 'route-$mode-$scale');
        try {
          await _mount(
            tester,
            mode: mode,
            scale: scale,
            size: const Size(320, 380),
            child: pdf.preview(actions),
          );
          await _pumpUntil(tester, () => _pdfToolbar(tester).ready);
          expect(find.byType(MediaActionButtons), findsNothing);
          await _openPdfFullscreen(tester);
          final fullscreen = tester.widget<PdfPreview>(_fullscreenPdf());
          expect(fullscreen.mediaActions, same(actions));
          expect(fullscreen.sourceDocumentRef, same(pdf.ref));
          expect(fullscreen.file.path, pdf.file.path);
          expect(_target(tester).source, pdf.file.path);
          expect(_target(tester).name, pdf.name);
          expect(_target(tester).isImage, isFalse);
          expect(_target(tester).requireAuthentication, isFalse);
          expect(_target(tester).httpHeaders, isEmpty);
          expect(pdfFactory.opened, [pdf.file.path]);
          _expectSurface(tester, mode);
          final viewer = find.descendant(
            of: _fullscreenPdf(),
            matching: find.byType(PdfViewer),
          );
          final viewerState = tester.state(viewer);
          final viewerBounds = tester.getRect(viewer);
          final before = await _pixels(tester);
          await tester.tap(find.byKey(_copy));
          await tester.pump();
          expect(find.byKey(_copied), findsNothing);
          actions.calls.single.succeed();
          await _motion(tester);
          final badge = _expectBadge(tester);
          expect(badge.bottom, lessThan(viewerBounds.top));
          expect(
            _changedPixels(before, await _pixels(tester), badge),
            greaterThan(4),
          );
          expect(tester.state(viewer), same(viewerState));
          expect(tester.getRect(viewer), viewerBounds);
          await tester.tap(find.byKey(_share));
          await tester.pump();
          expect(actions.calls.last.source.source, pdf.file.path);
          expect(actions.calls.last.origin, tester.getRect(find.byKey(_share)));
          actions.calls.last.fail();
          await _motion(tester);
          expect(
            _button(tester, _share).tooltip,
            LocaleKeys.mediaActions_shareFailed.tr(),
          );
          expect(find.byKey(_copied), findsNothing);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(_fullscreenPdf(), findsNothing);
          expect(find.byType(PdfPreview), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester, actions);
          pdf.release();
        }
      });
    }
  }

  testWidgets(
      'workspace PDF passes the injected service to its fullscreen route',
      (tester) async {
    final actions = _Actions();
    final pdf = await _PdfFixture.prepare(pdfFactory, 'workspace-pdf');
    final loader = _Files({pdf.name: pdf.file});
    try {
      await _mount(
        tester,
        accessible: true,
        child: WorkspaceFileView(
          view: _view('workspace-pdf', pdf.name, _cloud),
          resolveStorageUrl: _storedUrl,
          materializeFile: loader.load,
          mediaActions: actions,
        ),
      );
      await _pumpUntil(
        tester,
        () =>
            find.byType(PdfPreviewToolbar).evaluate().isNotEmpty &&
            _pdfToolbar(tester).ready,
      );
      await _openPdfFullscreen(tester);
      final copy =
          find.descendant(of: _fullscreenPdf(), matching: find.byKey(_copy));
      await tester.tap(copy);
      await tester.pump();
      expect(actions.calls.single.source.source, pdf.file.path);
      expect(actions.calls.single.source.name, pdf.name);
      expect(actions.calls.single.source.httpHeaders, isEmpty);
      actions.calls.single.succeed();
      await _motion(tester);
      expect(pdfFactory.opened, [pdf.file.path]);
      expect(loader.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
      pdf.release();
    }
  });

  for (final reduced in [false, true]) {
    testWidgets('PDF fullscreen auto-hide is focus-safe (reduced=$reduced)',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _Actions();
      final pdf = await _PdfFixture.prepare(pdfFactory, 'idle-$reduced');
      try {
        await _mount(
          tester,
          reduced: reduced,
          child: pdf.preview(actions, autoHide: true),
        );
        await _pumpUntil(tester, () => _pdfToolbar(tester).ready);
        await _openPdfFullscreen(tester);
        await tester.pump(const Duration(seconds: 4));
        await _motion(tester);
        expect(_revealFor(tester, _copy).opacity, 0);
        expect(find.semantics.byLabel('Copy'), findsNothing);
        await _tabTo(tester, _button(tester, _copy).focusNode!);
        await tester.pump(const Duration(seconds: 4));
        expect(_revealFor(tester, _copy).opacity, 1);
        expect(
          _revealFor(tester, _copy).duration,
          reduced ? Duration.zero : const Duration(milliseconds: 140),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        expect(_revealFor(tester, _copy).opacity, 1);
        expect(actions.calls.single.kind, 'copy');
        actions.calls.single.succeed();
        await _motion(tester);
        expect(_button(tester, _copy).focusNode!.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _unmount(tester, actions);
        pdf.release();
      }
    });
  }

  for (final host in ['album', 'PDF']) {
    for (final action in [_copy, _share]) {
      testWidgets('keyboard Space activates $host $action, not the reader',
          (tester) async {
        final actions = _Actions();
        final album = _album([_item('one', 'Photo.png', photo.path)]);
        final pdf = host == 'PDF'
            ? await _PdfFixture.prepare(pdfFactory, 'space-${action.value}')
            : null;
        try {
          await _warmPhoto(tester, photo);
          await _mount(
            tester,
            child: pdf?.preview(actions) ?? _lightbox(album, actions),
          );
          if (pdf != null) {
            await _pumpUntil(tester, () => _pdfToolbar(tester).ready);
            await _openPdfFullscreen(tester);
          }
          await _tabTo(tester, _button(tester, action).focusNode!);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pump();
          expect(actions.calls, hasLength(1));
          expect(actions.calls.single.kind, action == _copy ? 'copy' : 'share');
          if (host == 'album') {
            expect(
              find.byTooltip(LocaleKeys.collections_album_stopSlideshow.tr()),
              findsNothing,
            );
          }
          actions.calls.single.succeed();
          await _motion(tester);
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester, actions);
          album.dispose();
          pdf?.release();
        }
      });
    }
  }

  for (final reduced in [false, true]) {
    testWidgets('slideshow preserves idle chrome (reduced=$reduced)',
        (tester) async {
      final actions = _Actions();
      final album = _album([
        _item('one', 'First.png', photo.path),
        _item('two', 'Second.png', secondPhoto.path, index: 1),
      ]);
      album.updateSettings(
        album.settings.copyWith(
          slideshow: const AlbumSlideshowSettings(
            transition: AlbumSlideshowTransition.zoom,
          ),
        ),
      );
      try {
        await _warmPhoto(tester, photo);
        await _warmPhoto(tester, secondPhoto);
        await _mount(
          tester,
          reduced: reduced,
          child: _lightbox(album, actions),
        );
        await _motion(tester);
        // Space on the actual reader root must still start the slideshow.
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        await _motion(tester);
        expect(_revealFor(tester, _copy).opacity, 0);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(_target(tester).source, secondPhoto.path);
        expect(_revealFor(tester, _copy).opacity, 0);
        if (reduced) {
          expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
        }
        expect(actions.calls, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, actions);
        album.dispose();
      }
    });
  }

  testWidgets(
      'PDF fullscreen keeps real selected-text Ctrl+C separate from file copy',
      (tester) async {
    final actions = _Actions();
    final pdf = await _PdfFixture.prepare(pdfFactory, 'text-selection');
    final clipboard = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    try {
      await _mount(tester, child: pdf.preview(actions));
      await _pumpUntil(tester, () => _pdfToolbar(tester).ready);
      await _openPdfFullscreen(tester);
      final region = find.descendant(
        of: _fullscreenPdf(),
        matching: find.byType(SelectableRegion),
      );
      tester.widget<SelectableRegion>(region).focusNode.requestFocus();
      await _motion(tester);
      await _controlKey(tester, LogicalKeyboardKey.keyA);
      await tester.pump(const Duration(milliseconds: 350));
      final overlays = tester.widgetList<PdfPageTextOverlay>(
        find.descendant(
          of: _fullscreenPdf(),
          matching: find.byType(PdfPageTextOverlay),
        ),
      );
      expect(overlays, isNotEmpty);
      expect(
        overlays.first.selectables.values
            .map((value) => value.selectedRanges.text),
        contains(_pdfText),
      );
      await _controlKey(tester, LogicalKeyboardKey.keyC);
      await tester.pump();
      expect(clipboard, [_pdfText]);
      expect(actions.calls, isEmpty);
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      expect(actions.calls.single.source.source, pdf.file.path);
      actions.calls.single.succeed();
      await _motion(tester);
      expect(clipboard, [_pdfText]);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, actions);
      pdf.release();
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    }
  });
}

ViewPB _view(String id, String name, String source) => ViewPB(
      id: id,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: source,
      ).mergeIntoExtra(''),
    );

Future<String?> _storedUrl(ViewPB view) async => view.workspaceItem?.storageUrl;

AlbumMediaItem _item(
  String id,
  String name,
  String path, {
  int index = 0,
  String? storedSource,
}) =>
    AlbumMediaItem(
      view: _view(id, name, storedSource ?? path),
      kind: AlbumMediaKind.image,
      path: path,
      index: index,
    );

AlbumController _album(
  List<AlbumMediaItem> items, {
  ValueChanged<Map<String, dynamic>>? onPersist,
}) {
  final metadata = AlbumMetadataCache();
  for (final item in items) {
    metadata.seed(item.id, const AlbumMediaMetadata());
  }
  return AlbumController(
    initialState: const {},
    onPersist: onPersist ?? (_) {},
    metadata: metadata,
  )..setItems(items);
}

Widget _lightbox(
  AlbumController controller,
  MediaActionService actions, {
  AlbumOriginalFileResolver? resolveOriginalFile,
}) =>
    Builder(
      builder: (context) => AlbumLightbox(
        controller: controller,
        palette: CollectionPalette.of(context, CollectionKind.album),
        startId: controller.ordered.first.id,
        mediaActions: actions,
        resolveOriginalFile: resolveOriginalFile,
      ),
    );

AppFlowyCloudSharedEnv _cloudEnvironment() => AppFlowyCloudSharedEnv(
      authenticatorType: AuthenticatorType.appflowyCloud,
      appflowyCloudConfig: AppFlowyCloudConfiguration(
        base_url: 'https://workspace.example.test',
        ws_base_url: 'wss://workspace.example.test/ws',
        gotrue_url: 'https://workspace.example.test/gotrue',
        enable_sync_trace: false,
        base_web_domain: 'https://workspace.example.test',
      ),
    );

UserProfilePB _profile(String token) =>
    UserProfilePB(token: jsonEncode({'access_token': token}));

class _Workspace extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _Workspace(UserProfilePB profile)
      : super(UserWorkspaceState.initial(profile));

  void update(UserProfilePB profile) =>
      emit(state.copyWith(userProfile: profile));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Files {
  _Files(this.files);
  final Map<String, File> files;
  final requests = <({String source, String name})>[];

  Future<File> load({required String source, required String name}) async {
    requests.add((source: source, name: name));
    return files[name]!;
  }
}

/// Keep real disk writes, but run and await their complete IO chain outside
/// the widget clock. A fixed number of pumps cannot prove a Windows file
/// handle has closed, especially when many test isolates are running.
class _TrackedTextFile extends Fake implements File {
  _TrackedTextFile(this.file) : ioZone = Zone.current;

  final File file;
  final Zone ioZone;
  final writes = <Future<File>>[];

  Future<void> finishWrites() async {
    await Future.wait(writes).timeout(const Duration(seconds: 10));
  }

  @override
  String get path => file.path;
  @override
  Uri get uri => file.uri;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<int> length() => file.length();
  @override
  FileStat statSync() => file.statSync();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      file.readAsString(encoding: encoding);
  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    final write = ioZone.run(
      () => file.writeAsString(
        contents,
        mode: mode,
        encoding: encoding,
        flush: flush,
      ),
    );
    writes.add(write);
    return write;
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      file.writeAsStringSync(
        contents,
        mode: mode,
        encoding: encoding,
        flush: flush,
      );

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);
}

class _Actions extends Fake implements MediaActionService {
  final calls = <_Call>[];

  @override
  Future<void> copy(MediaActionSource source) => _start('copy', source, null);

  @override
  Future<void> share(MediaActionSource source, {Rect? sharePositionOrigin}) =>
      _start('share', source, sharePositionOrigin);

  Future<void> _start(String kind, MediaActionSource source, Rect? origin) {
    final call = _Call(kind, source, origin);
    calls.add(call);
    return call.done.future;
  }
}

class _Call {
  _Call(this.kind, this.source, this.origin);
  final String kind;
  final MediaActionSource source;
  final Rect? origin;
  final done = Completer<void>();

  void succeed() => done.complete();
  void fail() => done.completeError(StateError('Synthetic action failure'));
}

/// Real export preparation with only HTTP, clipboard and share handoff replaced.
/// No native handles or user/provider stores are read by these boundaries.
class _Exports implements ClipboardWriter {
  _Exports(this.directory, {http.Client? client}) {
    this.client = client ??
        MockClient((request) async {
          unexpectedRequests.add(request);
          throw StateError('Unexpected HTTP in a local-original test');
        });
    actions = MediaActionService(
      clipboard: () => this,
      shareFiles: _shareFiles,
      shareText: (_, {sharePositionOrigin}) async =>
          throw StateError('Originals must never become shared links'),
      httpClient: this.client,
      temporaryDirectory: () async => directory,
    );
  }

  final Directory directory;
  late final http.Client client;
  late final MediaActionService actions;
  final unexpectedRequests = <http.Request>[];
  final copies = <List<DataWriterItem>>[];
  final shares = <({List<XFile> files, List<String>? names, Rect? origin})>[];

  @override
  Future<void> write(Iterable<DataWriterItem> items) async =>
      copies.add(items.toList());

  Future<ShareResult> _shareFiles(
    List<XFile> files, {
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    shares.add(
      (files: files, names: fileNameOverrides, origin: sharePositionOrigin),
    );
    return ShareResult.unavailable;
  }

  void dispose() => client.close();
}

class _ExportData implements PlatformDataProvider {
  _ExportData(this.values);
  final Map<String, Object?> values;

  static Future<_ExportData> read(DataWriterItem item) async {
    final values = <String, Object?>{};
    for (final pending in item.data) {
      final encoded = await pending;
      for (final representation in encoded.representations) {
        final serialized = representation.serialize() as Map;
        expectSync(serialized['type'], 'simple');
        values[representation.format] = serialized['data'];
      }
    }
    return _ExportData(values);
  }

  Future<T?> decode<T extends Object>(ValueFormat<T> format) =>
      format.codec.decode(
        this,
        format.codec.decodingFormats.firstWhere(values.containsKey),
      );

  @override
  List<String> getAllFormats() => values.keys.toList();
  @override
  Future<Object?> getData(String format) async => values[format];
}

ThemeData _theme(String mode) => DesktopAppearance()
    .getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Future<void> _mount(
  WidgetTester tester, {
  required Widget child,
  String mode = 'light',
  double scale = 1,
  Size size = const Size(760, 540),
  bool reduced = false,
  bool accessible = false,
  _Workspace? workspace,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final theme = _theme(mode);
  final defaults = AppFlowyDefaultTheme();
  final appTheme = PremiumTheme.appFlowyTheme(
    base: mode == 'dark' ? defaults.dark() : defaults.light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: theme.brightness,
  );
  Widget app = EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en', 'US'),
    saveLocale: false,
    assetLoader: const TestBundleAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: context.localizationDelegates,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => AppFlowyTheme(
          data: appTheme,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduced,
              accessibleNavigation: accessible,
            ),
            child: RepaintBoundary(key: _capture, child: child!),
          ),
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  if (workspace != null) {
    app = BlocProvider<UserWorkspaceBloc>.value(value: workspace, child: app);
  }
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 60 && !ready(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: 'The actual renderer must finish loading');
  await _motion(tester);
}

Future<void> _motion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(_fade);
}

Future<void> _unmount(WidgetTester tester, [_Actions? actions]) async {
  await tester.pumpWidget(const SizedBox.shrink());
  for (final call in actions?.calls ?? const <_Call>[]) {
    if (!call.done.isCompleted) call.succeed();
  }
  // Source-editor autosaves are real IO against our temporary files. Their
  // open/write/flush/close each resume on the widget's fake microtask queue;
  // drain the complete chain before that test's clock is discarded.
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

Future<void> _tabTo(WidgetTester tester, FocusNode target) async {
  for (var i = 0; i < 30 && !target.hasFocus; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _motion(tester);
  }
  expect(
    target.hasFocus,
    isTrue,
    reason: 'The real action must be reachable by Tab',
  );
}

Future<void> _controlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

MediaActionSource _target(WidgetTester tester) =>
    tester.widget<MediaActionButtons>(find.byType(MediaActionButtons)).source;

IconButton _button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key));

AnimatedOpacity _revealFor(WidgetTester tester, Key key) =>
    tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byKey(key),
            matching: find.byKey(const ValueKey('media-action-reveal')),
          )
          .first,
    );

Rect _expectBadge(WidgetTester tester) {
  final badge = tester.getRect(find.byKey(_copied));
  final bounds = tester.getRect(find.byKey(_capture));
  expect(badge.top, greaterThanOrEqualTo(bounds.top));
  expect(badge.left, greaterThanOrEqualTo(bounds.left));
  expect(badge.right, lessThanOrEqualTo(bounds.right));
  expect(badge.bottom, lessThan(tester.getRect(find.byKey(_copy)).top));
  return badge.shift(-bounds.topLeft);
}

void _expectSurface(WidgetTester tester, String mode) {
  final finder = find.byKey(const ValueKey('media-action-surface'));
  final context = tester.element(finder);
  final decoration =
      tester.widget<DecoratedBox>(finder).decoration as BoxDecoration;
  expect(
    decoration.color,
    mode == 'paper'
        ? PaperTheme.popupBackground
        : PremiumThemeExtension.of(context).floatingSurface,
  );
  expect(decoration.border, isNull);
}

Future<void> _warmPhoto(WidgetTester tester, File file) async {
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
      await ready.future;
    } finally {
      stream.removeListener(listener);
    }
  });
}

class _Pixels {
  _Pixels(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final List<int> bytes;
}

Future<_Pixels> _pixels(WidgetTester tester) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_capture));
  final image = (await tester.runAsync(boundary.toImage))!;
  try {
    final bytes = (await tester.runAsync(image.toByteData))!;
    return _Pixels(image.width, image.height, bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

int _changedPixels(_Pixels before, _Pixels after, Rect rect) {
  expect(after.width, before.width);
  expect(after.height, before.height);
  var changed = 0;
  for (var y = rect.top.floor().clamp(0, before.height);
      y < rect.bottom.ceil().clamp(0, before.height);
      y++) {
    for (var x = rect.left.floor().clamp(0, before.width);
        x < rect.right.ceil().clamp(0, before.width);
        x++) {
      final offset = (y * before.width + x) * 4;
      if (before.bytes[offset] != after.bytes[offset] ||
          before.bytes[offset + 1] != after.bytes[offset + 1] ||
          before.bytes[offset + 2] != after.bytes[offset + 2]) {
        changed++;
      }
    }
  }
  return changed;
}

Finder _fullscreenPdf() => find
    .byWidgetPredicate((widget) => widget is PdfPreview && widget.fullscreen);

PdfPreviewToolbar _pdfToolbar(WidgetTester tester) =>
    tester.widget<PdfPreviewToolbar>(find.byType(PdfPreviewToolbar).last);

Future<void> _openPdfFullscreen(WidgetTester tester) async {
  final open = find.byTooltip('Open in full screen');
  await tester.ensureVisible(open);
  await tester.pumpAndSettle();
  await tester.tap(open);
  await tester.pumpAndSettle();
  expect(_fullscreenPdf(), findsOneWidget);
  expect(_pdfToolbar(tester).ready, isTrue);
}

/// A one-page PDF supplied through pdfrx's public IO boundary. PdfPreview,
/// PdfViewer, navigation, selection, chrome, and the fullscreen route are real.
/// No pdfium, real PDF file reads, native clipboard, or share sheet is started.
class _PdfFixture {
  _PdfFixture(this.file, this.ref, this.release);
  final File file;
  final PdfDocumentRef ref;
  final VoidCallback release;
  String get name => 'Original PDF # %.pdf';

  static Future<_PdfFixture> prepare(_PdfFactory factory, String id) async {
    final file = File('C:/synthetic-not-read/$id.pdf');
    final ref = PdfDocumentRefFile(file.path);
    final listenable = ref.resolveListenable();
    final release = listenable.addListener(() {});
    await listenable.load();
    expect(factory.opened, contains(file.path));
    return _PdfFixture(file, ref, release);
  }

  Widget preview(MediaActionService actions, {bool autoHide = false}) =>
      PdfPreview(
        file: file,
        name: name,
        metadata: {'autoHideToolbar': autoHide},
        onMetadataChanged: (_) {},
        editable: false,
        sourceDocumentRef: ref,
        mediaActions: actions,
      );
}

class _PdfFactory extends Fake implements PdfDocumentFactory {
  _PdfFactory(this.raster);
  final ui.Image raster;
  final opened = <String>[];

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
  }) async {
    opened.add(filePath);
    return _PdfDocument(filePath, raster);
  }
}

class _PdfDocument extends PdfDocument {
  _PdfDocument(String name, ui.Image raster) : super(sourceName: name) {
    pages = [_PdfPage(this, raster)];
  }

  @override
  late final List<PdfPage> pages;
  @override
  PdfPermissions? get permissions => null;
  @override
  bool get isEncrypted => false;
  @override
  Future<void> dispose() async {}
  @override
  Future<List<PdfOutlineNode>> loadOutline() async => [];
  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);
}

class _PdfPage extends PdfPage {
  _PdfPage(this.document, this.raster);
  @override
  final PdfDocument document;
  final ui.Image raster;
  @override
  int get pageNumber => 1;
  @override
  double get width => 600;
  @override
  double get height => 800;
  @override
  PdfPageRotation get rotation => PdfPageRotation.none;
  @override
  PdfPageRenderCancellationToken createCancellationToken() =>
      _PdfCancellation();
  @override
  Future<PdfPageText> loadText() async => _PdfText();
  @override
  Future<List<PdfLink>> loadLinks({bool compact = false}) async => [];
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    Color? backgroundColor,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async =>
      cancellationToken?.isCanceled == true ? null : _PdfBitmap(raster);
}

class _PdfCancellation extends PdfPageRenderCancellationToken {
  bool canceled = false;
  @override
  void cancel() => canceled = true;
  @override
  bool get isCanceled => canceled;
}

class _PdfBitmap extends PdfImage {
  _PdfBitmap(this.raster);
  final ui.Image raster;
  @override
  int get width => raster.width;
  @override
  int get height => raster.height;
  @override
  ui.PixelFormat get format => ui.PixelFormat.rgba8888;
  @override
  Uint8List get pixels => Uint8List(width * height * 4);
  @override
  Future<ui.Image> createImage() async => raster.clone();
  @override
  void dispose() {}
}

class _PdfText extends PdfPageText {
  @override
  int get pageNumber => 1;
  @override
  String get fullText => _pdfText;
  @override
  List<PdfPageTextFragment> get fragments => [
        PdfPageTextFragment.fromParams(
          0,
          _pdfText.length,
          const PdfRect(40, 760, 440, 720),
          _pdfText,
        ),
      ];
}

class _BundledMono extends GoogleFontsFamilyWithVariant {
  const _BundledMono()
      : super(
          family: 'JetBrainsMono',
          googleFontsVariant: const GoogleFontsVariant(
            fontWeight: FontWeight.w500,
            fontStyle: FontStyle.normal,
          ),
        );

  @override
  String toApiFilenamePrefix() => 'RobotoMono-Regular';
}
