import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/media_cell_bloc.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_row_detail/desktop_row_detail_media_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/media_cell_editor.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/database/widgets/row/cells/cell_container.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/materialized_file_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/file_viewer/attachment_file_viewer.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_toolbar.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');
const _copied = ValueKey('media-copied');
const _viewerHost = ValueKey('image-viewer-test-host');
const _openAttachment = ValueKey('open-test-attachment');
const _fade = Duration(milliseconds: 140);
const _textContent = 'A synthetic attachment, not workspace data.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File textFile;
  late File binaryFile;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    temporary = await Directory.systemTemp.createTemp('attachment_viewer_');
    textFile = await File('${temporary.path}/Original # 100%.txt')
        .writeAsString(_textContent);
    binaryFile = await File('${temporary.path}/Original # 100%.bin')
        .writeAsBytes([1, 2, 3]);
  });

  tearDownAll(() async => temporary.delete(recursive: true));

  test('legacy image provider keeps IDs, initial selection and original names',
      () {
    final first = _file(
      id: 'first',
      name: 'First image.PNG',
      type: MediaFileTypePB.Image,
    );
    final legacy = _file(id: 'legacy', name: 'Original # 100%.JFIF');
    final document = _file(id: 'document', name: 'Notes.pdf');
    final files = [first, document, legacy];
    final before = files.map((file) => file.writeToBuffer()).toList();
    final provider = MediaFileImageProvider(
      files: files,
      initialFileId: legacy.id,
    );
    expect(provider.files.map((file) => file.id), ['first', 'legacy']);
    expect(provider.initialIndex, 1);
    expect(provider.getImageName(1), 'Original # 100%.JFIF');
    expect(provider.getImage(1).url, legacy.url);
    expect(files.map((file) => file.writeToBuffer()), before);
    expect(legacy.fileType, MediaFileTypePB.Other);

    final unnamed = AFBlockImageProvider(
      images: [
        ImageBlockData(
          url: 'https://example.invalid/photo%20one.png?signature=not-a-name',
          type: CustomImageType.external,
        ),
        ImageBlockData(
          url: r'C:\synthetic\photo # 100%.png',
          type: CustomImageType.local,
        ),
      ],
    );
    expect(unnamed.getImageName(0), 'photo one.png');
    expect(unnamed.getImageName(1), 'photo # 100%.png');
  });

  test('real links stay links, while legacy photos and PDF links are files',
      () {
    final link = _file(
      name: 'A web page',
      type: MediaFileTypePB.Link,
      url: 'https://example.invalid/read/index.html',
    );
    expect(isAttachmentWebLink(link), isTrue);
    expect(
      attachmentMediaSource(link, userProfile: _profile()).shareAsLink,
      isTrue,
    );
    expect(
      attachmentMediaSource(link, userProfile: _profile()).httpHeaders,
      isEmpty,
    );
    for (final name in [
      'Photo.JFIF',
      'Report.PDF',
      'Clip.MP4',
      'Budget.xlsx',
    ]) {
      final file = _file(name: name, type: MediaFileTypePB.Link);
      expect(isAttachmentWebLink(file), isFalse, reason: name);
      expect(attachmentMediaSource(file).shareAsLink, isFalse);
    }
    final cloud = _file(
      name: 'Original # 100%.bin',
      upload: FileUploadTypePB.CloudFile,
    );
    final profile = _profile();
    final source = attachmentMediaSource(cloud, userProfile: profile);
    profile.token = '{"access_token":"changed-after-snapshot"}';
    expect(source.name, cloud.name);
    expect(source.httpHeaders, {'Authorization': 'Bearer synthetic-one'});
    expect(source.requireAuthentication, isTrue);
    expect(attachmentMediaSource(cloud).httpHeaders, isEmpty);
    expect(attachmentMediaSource(cloud).requireAuthentication, isTrue);
    final localUri = _file(
      name: 'Original # 100%.bin',
      url: binaryFile.uri.toString(),
      type: MediaFileTypePB.Link,
    );
    expect(isAttachmentWebLink(localUri), isFalse);
    expect(attachmentMediaSource(localUri).shareAsLink, isFalse);
  });

  testWidgets(
      'block provider never forwards cloud credentials to an external renderer',
      (tester) async {
    final provider = AFBlockImageProvider(images: [_images().last]);
    AFImage? renderer;
    try {
      await _pump(
        tester,
        Builder(
          builder: (context) {
            // Inspect the handoff only; do not mount a real network Image.
            renderer = provider.renderImage(context, 0, _profile()) as AFImage;
            return const SizedBox.shrink();
          },
        ),
      );
      expect(renderer!.uploadType, FileUploadTypePB.NetworkFile);
      expect(renderer!.userProfile, isNull);
      expect(renderer!.fit, BoxFit.contain);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets('image modal keeps single clicks and retains double-click close',
      (tester) async {
    final actions = _Actions();
    final provider = _Images(_images());
    try {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            key: _openAttachment,
            onPressed: () => unawaited(
              showDialog<void>(
                context: context,
                builder: (_) => InteractiveImageViewer(
                  imageProvider: provider,
                  actions: actions,
                ),
              ),
            ),
            child: const Text('Open test image'),
          ),
        ),
      );
      await _openDialog(tester);
      final point = tester.getTopLeft(find.byType(InteractiveImageViewer)) +
          const Offset(80, 80);
      await tester.tapAt(point);
      // Let the double-tap recognizer decline a single click. The modal
      // barrier must not win that abandoned arena and close the viewer.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveImageViewer), findsOneWidget);
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveImageViewer), findsNothing);
      expect(actions.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets(
        '$mode: image actions fade without autofocus pinning or remounts',
        (tester) async {
      final actions = _Actions();
      final provider = _Images(_images());
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _pump(tester, _imageHost(provider, actions), mode: mode);
        final state = tester.state(find.byType(MediaActionButtons));
        final scene = tester.state(find.byType(InteractiveViewer));
        final before = tester.getRect(find.byType(InteractiveImageToolbar));
        expect(_reveal(tester).opacity, 0);
        expect(find.byKey(_copy).hitTestable(), findsNothing);
        expect(find.byType(InteractiveImageToolbar), findsOneWidget);
        expect(actions.calls, isEmpty);
        // A hidden action is inert, rather than an invisible native operation.
        await tester.tapAt(tester.getCenter(find.byKey(_copy)));
        await tester.pump();
        expect(actions.calls, isEmpty);

        await mouse.moveTo(tester.getCenter(find.byKey(_viewerHost)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        expect(_paintedOpacity(tester), greaterThan(0));
        expect(_paintedOpacity(tester), lessThan(1));
        await tester.pump(const Duration(milliseconds: 70));
        expect(_paintedOpacity(tester), 1);
        expect(tester.getRect(find.byType(InteractiveImageToolbar)), before);

        await tester.tap(find.byKey(_copy));
        await tester.pump();
        expect(actions.calls.single.source.source, provider.images.first.url);
        expect(find.byKey(_copied), findsNothing);
        actions.calls.single.done.complete();
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copied), findsOneWidget);
        expect(tester.getRect(find.byType(InteractiveImageToolbar)), before);

        _viewerFocus(tester).requestFocus();
        await tester.pump();
        await tester.pump();
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        expect(_reveal(tester).opacity, 0);
        expect(find.byKey(_share).hitTestable(), findsNothing);
        await tester.pump(_fade);
        expect(_paintedOpacity(tester), 0);
        expect(tester.state(find.byType(MediaActionButtons)), same(state));
        expect(tester.state(find.byType(InteractiveViewer)), same(scene));
        await _hover(tester, mouse, find.byKey(_viewerHost));
        expect(find.byKey(_copied), findsOneWidget);
        if (mode == 'paper') {
          final surface = tester.widget<DecoratedBox>(
            find.byKey(const ValueKey('media-action-surface')),
          );
          expect((surface.decoration as BoxDecoration).color, isNull);
          expect(_buttons(tester).onDarkSurface, isTrue);
          final group = tester.widget<DecoratedBox>(
            find
                .ancestor(
                  of: find.byType(MediaActionButtons),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          expect(
            (group.decoration as BoxDecoration).color,
            Colors.black.withValues(alpha: 0.6),
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await _dispose(tester);
      }
    });

    testWidgets('$mode: unknown-file popup is warm, lazy and responsive',
        (tester) async {
      final actions = _Actions();
      final loader = _Loader(binaryFile);
      final file = _file(name: 'Original # 100%.bin');
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _pump(
          tester,
          AttachmentFileViewer(
            file: file,
            actions: actions,
            materialize: loader.load,
            openFile: (_) async => throw StateError('Unexpected native open'),
          ),
          mode: mode,
          textScale: 2,
        );
        expect(loader.requests, isEmpty);
        expect(_reveal(tester).opacity, 0);
        final header =
            tester.getRect(find.byKey(const ValueKey('attachment-file-name')));
        final actionState = tester.state(find.byType(MediaActionButtons));
        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        if (mode == 'paper') {
          expect(dialog.backgroundColor, PaperTheme.editorPreviewBackground);
        }
        expect(
          find.byKey(const ValueKey('attachment-viewer-close')).hitTestable(),
          findsOneWidget,
        );
        await _hover(
          tester,
          mouse,
          find.byKey(const ValueKey('attachment-file-name')),
        );
        await tester.tap(find.byKey(_share));
        await tester.pump();
        expect(actions.calls.single.source.name, file.name);
        expect(actions.calls.single.source.shareAsLink, isFalse);
        expect(actions.calls.single.origin, isNotNull);
        expect(actions.calls.single.origin!.isEmpty, isFalse);
        actions.calls.single.done.complete();
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copied), findsNothing);
        expect(
          tester.getRect(find.byKey(const ValueKey('attachment-file-name'))),
          header,
        );
        expect(
          tester.state(find.byType(MediaActionButtons)),
          same(actionState),
        );
        expect(loader.requests, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await _dispose(tester);
      }
    });
  }

  testWidgets(
      'navigation changes action targets, not zoom, and gates late copy feedback',
      (tester) async {
    final actions = _Actions();
    final provider = _Images(_images(), initialIndex: 1);
    final profile = _profile();
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await _pump(tester, _imageHost(provider, actions, profile: profile));
      await mouse.addPointer(location: Offset.zero);
      await _hover(tester, mouse, find.byKey(_viewerHost));
      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      controller.value = Matrix4.identity()
        ..translate(32.0, 18.0)
        ..scale(1.4);
      await tester.pump();
      final matrix = controller.value.clone();
      final scene = tester.state(find.byType(InteractiveViewer));
      final buttons = tester.state(find.byType(MediaActionButtons));
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      final cloud = actions.calls.single.source;
      expect(cloud.source, provider.images[1].url);
      expect(cloud.name, 'Cloud original.JPG');
      expect(cloud.httpHeaders, {'Authorization': 'Bearer synthetic-one'});
      profile.token = '{"access_token":"synthetic-two"}';
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_buttons(tester).source.source, provider.images[2].url);
      expect(_buttons(tester).source.httpHeaders, isEmpty);
      expect(_buttons(tester).source.requireAuthentication, isFalse);
      expect(_buttons(tester).source.name, 'External original.png');
      expect(controller.value, matrix);
      expect(tester.state(find.byType(InteractiveViewer)), same(scene));
      expect(tester.state(find.byType(MediaActionButtons)), same(buttons));
      actions.calls.single.done.complete();
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byKey(_copied), findsNothing);
      expect(cloud.httpHeaders, {'Authorization': 'Bearer synthetic-one'});
      await tester.tap(find.byKey(_share));
      await tester.pump();
      expect(actions.calls.last.source.source, provider.images[2].url);
      expect(actions.calls.last.source.httpHeaders, isEmpty);
      actions.calls.last.done.complete();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        _buttons(tester).source.httpHeaders,
        {'Authorization': 'Bearer synthetic-two'},
      );
      expect(controller.value, matrix);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _dispose(tester);
    }
  });

  testWidgets(
      'optional workspace profile refresh and explicit override stay current',
      (tester) async {
    final workspace = _Workspace(_profile());
    final provider = _Images(_images(), initialIndex: 1);
    final actions = _Actions();
    UserProfilePB? explicit;
    late StateSetter rebuild;
    try {
      await _pump(
        tester,
        BlocProvider<UserWorkspaceBloc>.value(
          value: workspace,
          child: StatefulBuilder(
            builder: (context, update) {
              rebuild = update;
              return _imageHost(provider, actions, profile: explicit);
            },
          ),
        ),
      );
      final state = tester.state(find.byType(MediaActionButtons));
      expect(
        _buttons(tester).source.httpHeaders,
        {'Authorization': 'Bearer synthetic-one'},
      );
      workspace.update(_profile('synthetic-two'));
      await tester.pump();
      await tester.pump();
      expect(
        _buttons(tester).source.httpHeaders,
        {'Authorization': 'Bearer synthetic-two'},
      );
      rebuild(() => explicit = _profile('explicit-profile'));
      await tester.pump();
      expect(
        _buttons(tester).source.httpHeaders,
        {'Authorization': 'Bearer explicit-profile'},
      );
      expect(provider.lastProfile, same(explicit));
      workspace.update(_profile('synthetic-three'));
      await tester.pump();
      expect(
        _buttons(tester).source.httpHeaders,
        {'Authorization': 'Bearer explicit-profile'},
      );
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      expect(actions.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
      await tester.runAsync(workspace.close);
    }
  });

  testWidgets(
      'missing profile and image failure never hide actions or throw a bloc lookup',
      (tester) async {
    final actions = _Actions();
    final image =
        _file(name: 'Private photo.JPG', upload: FileUploadTypePB.CloudFile);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await _pump(
        tester,
        _imageHost(MediaFileImageProvider(files: [image]), actions),
      );
      expect(find.byIcon(Icons.broken_image_rounded), findsOneWidget);
      expect(_buttons(tester).source.requireAuthentication, isTrue);
      expect(_buttons(tester).source.httpHeaders, isEmpty);
      await mouse.addPointer(location: Offset.zero);
      await _hover(tester, mouse, find.byKey(_viewerHost));
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      actions.calls.single.done
          .completeError(StateError('private detail must not be shown'));
      await tester.pump();
      await tester.pump(_fade);
      expect(
        tester.widget<IconButton>(find.byKey(_copy)).tooltip,
        LocaleKeys.message_copy_fail.tr(),
      );
      expect(find.textContaining('private detail'), findsNothing);
      expect(find.byKey(_copied), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _dispose(tester);
    }
  });

  testWidgets(
      'narrow viewer preserves zoom/navigation and swallows destructive keys',
      (tester) async {
    final deleted = <int>[];
    var ancestorDeletes = 0;
    final actions = _Actions();
    final provider = _Images(_images(), onDeleteImage: deleted.add);
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await _pump(
        tester,
        Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.backspace ||
                    event.logicalKey == LogicalKeyboardKey.delete)) {
              ancestorDeletes++;
            }
            return KeyEventResult.ignored;
          },
          child: _imageHost(provider, actions),
        ),
        textScale: 2,
      );
      expect(_reveal(tester).opacity, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
      await tester.pump();
      expect(_toolbar(tester).currentScale, greaterThan(100));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(_toolbar(tester).currentImage.url, provider.images[1].url);
      expect(_toolbar(tester).currentScale, greaterThan(100));
      await tester.sendKeyEvent(LogicalKeyboardKey.numpadSubtract);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.pump();
      expect(_toolbar(tester).currentScale, 100);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(deleted, isEmpty);
      expect(ancestorDeletes, 0);
      expect(actions.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets(
    'keyboard can reveal hidden copy/share without pinning viewer autofocus',
    (tester) async {
      final actions = _Actions();
      try {
        await _pump(tester, _imageHost(_Images(_images()), actions));
        expect(_reveal(tester).opacity, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.pump();
        await tester.pump(_fade);
        expect(
          tester.widget<IconButton>(find.byKey(_copy)).focusNode!.hasFocus,
          isTrue,
        );
        expect(_reveal(tester).opacity, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(actions.calls.single.kind, 'copy');
        expect(find.byKey(_copied), findsNothing);
        actions.calls.single.done.complete();
        await tester.pump();
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copied), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.pump();
        expect(
          tester.widget<IconButton>(find.byKey(_share)).focusNode!.hasFocus,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
      'file materialization snapshots auth and renders the real read-only text preview',
      (tester) async {
    final actions = _Actions();
    final loader = _Loader(textFile);
    final file =
        _file(name: 'Original # 100%.txt', upload: FileUploadTypePB.CloudFile);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await _pump(
        tester,
        _opener(
          file,
          actions: actions,
          materialize: loader.load,
          profile: _profile(),
        ),
        mode: 'paper',
      );
      expect(loader.requests, isEmpty);
      await _openDialog(tester);
      await _finishText(tester);
      expect(loader.requests, hasLength(1));
      expect(loader.requests.single.source, file.url);
      expect(loader.requests.single.name, file.name);
      expect(
        loader.requests.single.headers,
        {'Authorization': 'Bearer synthetic-one'},
      );
      final preview = tester.widget<FilePreview>(find.byType(FilePreview));
      expect(preview.file.path, textFile.path);
      expect(preview.editable, isFalse);
      expect(preview.kind, FilePreviewKind.text);
      expect(preview.bare, isTrue);
      expect(_previewText, findsOneWidget);
      expect(
        tester
            .getBottomLeft(find.byKey(const ValueKey('attachment-file-name')))
            .dy,
        lessThan(tester.getTopLeft(find.byType(FilePreview)).dy),
      );
      await mouse.addPointer(location: Offset.zero);
      await _hover(
        tester,
        mouse,
        find.byKey(const ValueKey('attachment-file-name')),
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump(_fade);
      expect(loader.requests, hasLength(1));
      expect(actions.calls, isEmpty);
      expect(await tester.runAsync(textFile.readAsString), _textContent);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _dispose(tester);
    }
  });

  testWidgets(
      'loading/failure keep actions available without exposing source errors',
      (tester) async {
    final actions = _Actions();
    final load = Completer<File>();
    final loader = _Loader(textFile, pending: load.future);
    final file = _file(name: 'Readable.txt');
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await _pump(
        tester,
        _opener(
          file,
          actions: actions,
          materialize: loader.load,
          profile: _profile(),
        ),
      );
      await _openDialog(tester);
      expect(find.byType(MaterializedFileBuilder), findsOneWidget);
      expect(find.byType(MediaActionButtons), findsOneWidget);
      await mouse.addPointer(location: Offset.zero);
      await _hover(
        tester,
        mouse,
        find.byKey(const ValueKey('attachment-file-name')),
      );
      final state = tester.state(find.byType(MediaActionButtons));
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      expect(actions.calls.single.source.source, file.url);
      expect(loader.requests.single.headers, isEmpty);
      actions.calls.single.done.complete();
      load.completeError(StateError('credential-bearing-url-must-not-appear'));
      await tester.pump();
      await tester.pump(_fade);
      expect(
        find.byKey(const ValueKey('attachment-file-unavailable')),
        findsOneWidget,
      );
      expect(find.textContaining('credential-bearing-url'), findsNothing);
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      expect(find.byKey(_share).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _dispose(tester);
    }
  });

  testWidgets('cloud without a profile fails closed before any materialization',
      (tester) async {
    final loader = _Loader(textFile);
    final file = _file(name: 'Private.txt', upload: FileUploadTypePB.CloudFile);
    try {
      await _pump(
        tester,
        AttachmentFileViewer(
          file: file,
          materialize: loader.load,
          actions: _Actions(),
          openFile: (_) async => throw StateError('Unexpected native open'),
        ),
      );
      expect(loader.requests, isEmpty);
      expect(
        find.byKey(const ValueKey('attachment-file-unavailable')),
        findsOneWidget,
      );
      expect(_buttons(tester).source.requireAuthentication, isTrue);
      expect(_buttons(tester).source.httpHeaders, isEmpty);
      await tester.tap(find.byKey(const ValueKey('attachment-file-open')));
      await tester.pump();
      expect(loader.requests, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets(
      'system open uses materialized original filename, not the remote URL',
      (tester) async {
    final loader = _Loader(binaryFile);
    final opened = <File>[];
    final file =
        _file(name: 'Original # 100%.bin', upload: FileUploadTypePB.CloudFile);
    try {
      await _pump(
        tester,
        AttachmentFileViewer(
          file: file,
          userProfile: _profile(),
          materialize: loader.load,
          actions: _Actions(),
          openFile: (file) async {
            opened.add(file);
            return true;
          },
        ),
      );
      expect(loader.requests, isEmpty);
      expect(opened, isEmpty);
      await tester.tap(find.byKey(const ValueKey('attachment-file-open')));
      await tester.pump();
      expect(loader.requests, hasLength(1));
      expect(loader.requests.single.name, 'Original # 100%.bin');
      expect(
        loader.requests.single.headers,
        {'Authorization': 'Bearer synthetic-one'},
      );
      expect(opened.single.path, binaryFile.path);
      expect(opened.single.uri.scheme, 'file');
      expect(opened.single.path, isNot(file.url));
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets('genuine web links only reach the injected browser launcher',
      (tester) async {
    final loader = _Loader(binaryFile);
    final links = <String>[];
    final file = _file(name: 'Web page', type: MediaFileTypePB.Link);
    try {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            key: _openAttachment,
            onPressed: () => unawaited(
              showAttachmentFileViewer(
                context,
                file,
                userProfile: _profile(),
                materialize: loader.load,
                actions: _Actions(),
                openLink: (url) async {
                  links.add(url);
                  return true;
                },
              ),
            ),
            child: const Text('Open test link'),
          ),
        ),
      );
      await tester.tap(find.byKey(_openAttachment));
      await tester.pump();
      expect(links, [file.url]);
      expect(loader.requests, isEmpty);
      expect(find.byType(AttachmentFileViewer), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets(
      'actions remain mounted through dialog exit and ignore late completion',
      (tester) async {
    final actions = _Actions();
    final loader = _Loader(binaryFile);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await _pump(
        tester,
        _opener(_file(), actions: actions, materialize: loader.load),
      );
      await _openDialog(tester);
      await mouse.addPointer(location: Offset.zero);
      await _hover(
        tester,
        mouse,
        find.byKey(const ValueKey('attachment-file-name')),
      );
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      final state = tester.state(find.byType(MediaActionButtons));
      await tester.tap(find.byKey(const ValueKey('attachment-viewer-close')));
      await tester.pump();
      expect(state.mounted, isTrue);
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      await tester.pump(const Duration(milliseconds: 250));
      expect(state.mounted, isFalse);
      actions.calls.single.done.complete();
      await tester.pump();
      expect(find.byKey(_copied), findsNothing);
      expect(loader.requests, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _dispose(tester);
    }
  });

  testWidgets('popup-editor copy/share cannot open, delete or reorder a file',
      (tester) async {
    final file = _file(name: 'A real attachment.bin');
    final bloc = _MediaBloc([file]);
    final actions = _Actions();
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await _pump(tester, _editor(bloc, actions));
      await mouse.addPointer(location: Offset.zero);
      expect(_reveal(tester).opacity, 0);
      final row = find.byType(RenderMedia);
      final rect = tester.getRect(row);
      final state = tester.state(find.byType(MediaActionButtons));
      await _hover(tester, mouse, row);
      await tester.tap(find.byKey(_copy));
      await tester.pump();
      expect(actions.calls.single.source.name, file.name);
      actions.calls.single.done.complete();
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byType(AttachmentFileViewer), findsNothing);
      expect(find.byType(InteractiveImageViewer), findsNothing);
      expect(bloc.events, isEmpty);
      expect(bloc.deleted, isEmpty);
      expect(tester.getRect(row), rect);
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      await tester.tap(find.byKey(_share));
      await tester.pump();
      actions.calls.last.done.complete();
      await tester.pump();
      expect(bloc.events, isEmpty);
      expect(find.byType(AttachmentFileViewer), findsNothing);

      await tester.tap(find.text(file.name));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentFileViewer), findsOneWidget);
      expect(bloc.events, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await _dispose(tester);
      await tester.runAsync(bloc.close);
    }
  });

  testWidgets(
      'popup editor includes legacy photos and opens the clicked image ID',
      (tester) async {
    final files = [
      _file(id: 'first', name: 'First.PNG', upload: FileUploadTypePB.CloudFile),
      _file(id: 'file', name: 'Other.bin'),
      _file(
        id: 'legacy',
        name: 'Second.JFIF',
        upload: FileUploadTypePB.CloudFile,
        type: MediaFileTypePB.Link,
      ),
    ];
    final bloc = _MediaBloc(files);
    final actions = _Actions();
    try {
      await _pump(tester, _editor(bloc, actions));
      final rows = tester.widgetList<RenderMedia>(find.byType(RenderMedia));
      expect(rows.last.images.map((file) => file.id), ['first', 'legacy']);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is MediaFileThumbnail && widget.file.id == 'legacy',
        ),
      );
      await tester.pumpAndSettle();
      final viewer = tester
          .widget<InteractiveImageViewer>(find.byType(InteractiveImageViewer));
      final provider = viewer.imageProvider as MediaFileImageProvider;
      expect(provider.initialIndex, 1);
      expect(provider.files[provider.initialIndex].id, 'legacy');
      expect(provider.getImageName(1), 'Second.JFIF');
      expect(viewer.actions, same(actions));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(bloc.deleted, isEmpty);
      expect(bloc.events, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
      await tester.runAsync(bloc.close);
    }
  });

  testWidgets(
      'actual row-detail tile routes a non-image into the attachment popup',
      (tester) async {
    final file = _file(name: 'Read-only attachment.bin');
    final bloc = _MediaBloc([file]);
    final skin = DekstopRowDetailMediaCellSkin();
    final notifier = CellContainerNotifier();
    final popover = PopoverController();
    try {
      await _pump(
        tester,
        SizedBox(
          width: 260,
          child: Builder(
            builder: (context) => skin.build(context, notifier, popover, bloc),
          ),
        ),
      );
      await tester.tap(find.byType(MediaFileThumbnail));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentFileViewer), findsOneWidget);
      expect(
        tester
            .widget<AttachmentFileViewer>(find.byType(AttachmentFileViewer))
            .file
            .id,
        file.id,
      );
      expect(find.byType(InteractiveImageViewer), findsNothing);
      expect(bloc.deleted, isEmpty);
      expect(bloc.events, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
      await tester.runAsync(bloc.close);
      skin.dispose();
      notifier.dispose();
    }
  });
}

MediaFilePB _file({
  String id = 'attachment',
  String name = 'Attachment.bin',
  String url = 'https://example.invalid/opaque-attachment',
  MediaFileTypePB type = MediaFileTypePB.Other,
  FileUploadTypePB upload = FileUploadTypePB.NetworkFile,
}) =>
    MediaFilePB(
      id: id,
      name: name,
      url: url,
      fileType: type,
      uploadType: upload,
    );

UserProfilePB _profile([String token = 'synthetic-one']) =>
    UserProfilePB(token: '{"access_token":"$token"}');

List<ImageBlockData> _images() => [
      ImageBlockData(
        url: r'C:\synthetic\original.JPG',
        type: CustomImageType.local,
      ),
      ImageBlockData(
        url: 'https://cloud.example.invalid/opaque-id',
        type: CustomImageType.internal,
      ),
      ImageBlockData(
        url: 'https://external.example.invalid/image.png',
        type: CustomImageType.external,
      ),
    ];

class _Images extends AFImageProvider {
  _Images(this.images, {this.initialIndex = 0, super.onDeleteImage});

  final List<ImageBlockData> images;
  UserProfilePB? lastProfile;

  @override
  final int initialIndex;
  @override
  int get imageCount => images.length;
  @override
  ImageBlockData getImage(int index) => images[index];
  @override
  String getImageName(int index) => [
        'Local original.JPG',
        'Cloud original.JPG',
        'External original.png',
      ][index];
  @override
  Widget renderImage(
    BuildContext context,
    int index, [
    UserProfilePB? userProfile,
  ]) {
    lastProfile = userProfile;
    // No Image, codec, cache manager, backend, or HTTP client is constructed.
    return ColoredBox(
      key: ValueKey('synthetic-image-$index'),
      color: const Color(0xFF647875),
    );
  }
}

class _Actions extends Fake implements MediaActionService {
  final calls = <_Call>[];

  @override
  Future<void> copy(MediaActionSource target) => _begin('copy', target, null);
  @override
  Future<void> share(MediaActionSource target, {Rect? sharePositionOrigin}) =>
      _begin('share', target, sharePositionOrigin);

  Future<void> _begin(String kind, MediaActionSource source, Rect? origin) {
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
}

class _Request {
  _Request(this.source, this.name, Map<String, String> headers)
      : headers = Map.unmodifiable(headers);
  final String source;
  final String name;
  final Map<String, String> headers;
}

class _Loader {
  _Loader(this.file, {this.pending});
  final File file;
  final Future<File>? pending;
  final requests = <_Request>[];

  Future<File> load({
    required String source,
    required String name,
    required Map<String, String> httpHeaders,
  }) {
    requests.add(_Request(source, name, httpHeaders));
    return pending ?? Future.value(file);
  }
}

class _Workspace extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _Workspace(UserProfilePB profile)
      : super(UserWorkspaceState.initial(profile));
  void update(UserProfilePB profile) =>
      emit(state.copyWith(userProfile: profile));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Real bloc subscriptions; all writes are captured instead of reaching FFI.
class _MediaBloc extends Cubit<MediaCellState> implements MediaCellBloc {
  _MediaBloc(List<MediaFilePB> files)
      : super(MediaCellState(fieldName: 'Files', files: files));
  final events = <MediaCellEvent>[];
  final deleted = <String>[];
  @override
  void add(MediaCellEvent event) => events.add(event);
  @override
  void deleteFile(String id) => deleted.add(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _imageHost(
  AFImageProvider provider,
  MediaActionService actions, {
  UserProfilePB? profile,
}) =>
    SizedBox(
      key: _viewerHost,
      width: 640,
      height: 440,
      child: InteractiveImageViewer(
        imageProvider: provider,
        userProfile: profile,
        actions: actions,
      ),
    );

Widget _editor(_MediaBloc bloc, MediaActionService actions) =>
    BlocProvider<MediaCellBloc>.value(
      value: bloc,
      child: SizedBox(
        width: 250,
        height: 340,
        child: MediaCellEditor(actions: actions),
      ),
    );

Widget _opener(
  MediaFilePB file, {
  required MediaActionService actions,
  required MaterializedFileLoader materialize,
  UserProfilePB? profile,
}) =>
    Builder(
      builder: (context) => TextButton(
        key: _openAttachment,
        onPressed: () => unawaited(
          showAttachmentFileViewer(
            context,
            file,
            userProfile: profile,
            actions: actions,
            materialize: materialize,
            openFile: (_) async => throw StateError('Unexpected native open'),
          ),
        ),
        child: const Text('Open test attachment'),
      ),
    );

MediaActionButtons _buttons(WidgetTester tester) =>
    tester.widget<MediaActionButtons>(find.byType(MediaActionButtons));
InteractiveImageToolbar _toolbar(WidgetTester tester) => tester
    .widget<InteractiveImageToolbar>(find.byType(InteractiveImageToolbar));
AnimatedOpacity _reveal(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.byKey(const ValueKey('media-action-reveal')));
double _paintedOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .descendant(
            of: find.byKey(const ValueKey('media-action-reveal')),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;
FocusNode _viewerFocus(WidgetTester tester) => tester
    .widget<Focus>(
      find.descendant(
        of: find.byType(InteractiveImageViewer),
        matching: find.byWidgetPredicate(
          (widget) => widget is Focus && widget.autofocus,
        ),
      ),
    )
    .focusNode!;

Future<void> _hover(
  WidgetTester tester,
  TestGesture mouse,
  Finder target,
) async {
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump();
  await tester.pump(_fade);
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(_openAttachment));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Finder get _previewText => find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          widget.textSpan?.toPlainText() == _textContent,
    );

Future<void> _finishText(WidgetTester tester) async {
  for (var attempt = 0;
      _previewText.evaluate().isEmpty && attempt < 100;
      attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(_previewText, findsOneWidget);
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String mode = 'light',
  double textScale = 1,
}) async {
  final theme = DesktopAppearance()
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
  final defaults = AppFlowyDefaultTheme();
  final appTheme = PremiumTheme.appFlowyTheme(
    base: mode == 'dark' ? defaults.dark() : defaults.light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: theme.brightness,
  );
  await tester.pumpWidget(
    EasyLocalization(
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
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );
  // Only idle, in-memory hosts go through this helper. File IO starts after
  // opening a route and is drained explicitly by _finishText.
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
