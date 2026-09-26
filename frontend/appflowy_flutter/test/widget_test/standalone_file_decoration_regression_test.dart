import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_identity.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

const _cover =
    PageStyleCover(type: PageStyleCoverImageType.pureColor, value: '#B8C9A6');
const _replacement =
    PageStyleCover(type: PageStyleCoverImageType.pureColor, value: '#D8BC96');
const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');
const _titleInput = ValueKey('workspace-inline-name-editor');

void main() {
  fileControlTestSetup();

  for (final mode in fileControlAppearances) {
    // The actual shared identity is exercised for native-renderer formats too;
    // playback/office/archival engines are deliberately not started here.
    for (final extension in [
      'jpg',
      'mp4',
      'mp3',
      'pdf',
      'zip',
      'py',
      'docx',
      'xlsx',
      'pptx',
      'eml',
    ]) {
      testWidgets(
          '$mode/$extension: missing file cover follows header reveal policy',
          (tester) async {
        final file = MemoryCodeFile(
          'fixture',
          path: '/fixture/original.$extension',
        );
        final backend = FileControlBackend(
          fileControlView(
            'header-$extension',
            'Original.$extension',
            file.path,
          ),
          file,
        );
        final view = ValueNotifier(backend.stored);
        final editable = ValueNotifier(true);
        final binding = Object();
        final outside = FocusNode();
        final semantics = tester.ensureSemantics();
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(-20, -20));
        const contentKey = ValueKey('file-decoration-content');
        final child = PreviewToolbarRegion(
          child: Column(
            children: [
              ValueListenableBuilder<ViewPB>(
                valueListenable: view,
                builder: (_, current, __) => ValueListenableBuilder<bool>(
                  valueListenable: editable,
                  builder: (_, allowed, __) => WorkspaceFileIdentityRow(
                    view: current,
                    binding: binding,
                    summary: '${extension.toUpperCase()} · 7 B',
                    canRename: () => allowed && editable.value,
                    onViewChanged: (updated) => view.value = updated,
                    repository: backend,
                    source: MediaActionSource(
                      source: file.path,
                      name: current.name,
                      isImage: extension == 'jpg',
                    ),
                    mediaActions: backend.media,
                    fileAvailable: true,
                    actionsVisible: false,
                    coverBackend: backend.covers,
                    updateIcon: backend.writeIcon,
                  ),
                ),
              ),
              const Expanded(child: SizedBox.expand(key: contentKey)),
              TextButton(
                focusNode: outside,
                onPressed: () {},
                child: const Text('Outside header'),
              ),
            ],
          ),
        );
        try {
          await mountFileControls(tester, child, mode: mode);
          final identity = tester.state(find.byType(WorkspaceFileIdentityRow));
          final decoration = tester.state(find.byType(ViewDecorationActions));
          final header = tester.getRect(find.byType(WorkspaceFileIdentityRow));
          final title =
              tester.element(find.byKey(const ValueKey('workspace-file-name')));
          expect(_coverAction.hitTestable(), findsNothing);
          expect(find.semantics.byLabel('Add Cover'), findsNothing);
          await mouse.moveTo(tester.getCenter(find.byKey(contentKey)));
          await settleFileControls(tester);
          expect(_coverAction.hitTestable(), findsNothing);
          await mouse.moveTo(
            tester.getCenter(find.byKey(const ValueKey('workspace-file-name'))),
          );
          await settleFileControls(tester);
          expectFileControlPainted(tester, _coverAction);
          expect(_coverAction.hitTestable(), findsOneWidget);
          expect(tester.getRect(find.byType(WorkspaceFileIdentityRow)), header);
          await mouse.moveTo(const Offset(-20, -20));
          await settleFileControls(tester);
          expect(_coverAction.hitTestable(), findsNothing);

          final focus = Focus.of(tester.element(find.text('Add Cover')));
          for (var i = 0; i < 20 && !focus.hasPrimaryFocus; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await settleFileControls(tester);
          }
          expect(focus.hasPrimaryFocus, isTrue);
          final button = find.descendant(
            of: _coverAction,
            matching: find.byType(TextButton),
          );
          final data = tester.getSemantics(button).getSemanticsData();
          expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await settleFileControls(tester);
          expect(find.byType(UploadImageMenu), findsOneWidget);
          expectFileControlPainted(tester, _coverAction);
          final stale =
              tester.widget<UploadImageMenu>(find.byType(UploadImageMenu));
          editable.value = false;
          await settleFileControls(tester);
          expect(find.byType(UploadImageMenu), findsNothing);
          expect(find.byType(DecorationActionButton), findsNothing);
          stale.onSelectedColor!(_cover.value);
          await settleFileControls(tester);
          expect(backend.covers.saves, isEmpty);
          expect(backend.covers.deleted, isEmpty);
          expect(
            tester.state(find.byType(WorkspaceFileIdentityRow)),
            same(identity),
          );
          expect(
            tester.state(find.byType(ViewDecorationActions)),
            same(decoration),
          );
          expect(
            tester.element(find.byKey(const ValueKey('workspace-file-name'))),
            same(title),
          );

          editable.value = true;
          outside.requestFocus();
          await settleFileControls(tester);
          expect(_coverAction.hitTestable(), findsNothing);
          await tester.tapAt(Offset(header.right - 2, header.top + 2));
          await settleFileControls(tester);
          expectFileControlPainted(tester, _coverAction);
          expect(backend.covers.saves, isEmpty);
          await mouse.moveTo(header.center);
          await mouse.moveTo(const Offset(-20, -20));
          await settleFileControls(tester);
          expect(_coverAction.hitTestable(), findsNothing);
          for (final platform in [
            TargetPlatform.windows,
            TargetPlatform.android,
            TargetPlatform.iOS,
          ]) {
            await mountFileControls(
              tester,
              child,
              mode: mode,
              width: 320,
              textScale: 2,
              accessible: platform == TargetPlatform.windows,
              reduced: true,
              platform: platform,
            );
            expectFileControlPainted(tester, _coverAction);
            expect(_coverAction.hitTestable(), findsOneWidget);
            expect(find.semantics.byLabel('Add Cover'), findsOneWidget);
            expect(
              tester.state(find.byType(WorkspaceFileIdentityRow)),
              same(identity),
            );
          }
          expect(file.reads, 0);
          expect(file.writes, 0);
          expect(backend.extraWrites, isEmpty);
          expect(backend.iconWrites, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await unmountFileControls(tester);
          view.dispose();
          editable.dispose();
          outside.dispose();
          semantics.dispose();
        }
      });
    }

    testWidgets(
        '$mode: add/change/remove cover and icon retain the file, draft and title identity',
        (tester) async {
      final file =
          MemoryCodeFile(List.generate(180, (i) => 'print($i)').join('\n'));
      final backend = FileControlBackend(
        fileControlView('decorate', 'Original.py', file.path),
        file,
      );
      final pendingCopy = Completer<void>();
      backend.media.pending = pendingCopy.future;
      try {
        await mountFileControls(
          tester,
          backend.viewer(),
          mode: mode,
          accessible: true,
          reduced: true,
        );
        expect(find.byType(ViewCoverImage), findsNothing);
        expect(
          _coverAction.hitTestable(),
          findsOneWidget,
          reason: 'No existing cover is required to add one',
        );
        final renderer = tester.state(find.byType(FilePreview));
        final runner = tester.state(find.byType(SandboxedCodeRunner));
        final identity = tester.state(find.byType(WorkspaceFileIdentityRow));
        final decoration = tester.state(find.byType(ViewDecorationActions));
        final actions = tester.state(find.byType(MediaActionButtons));
        final field = tester.widget<TextField>(_sourceField);
        final controller = field.controller!;
        controller.value = TextEditingValue(
          text: 'Never flush this draft\n${file.contents}',
          selection: const TextSelection(baseOffset: 2, extentOffset: 18),
        );
        field.scrollController!.jumpTo(65);
        await tester.pump();
        await clickFileControl(tester, find.byKey(_copy));
        expect(backend.media.copies, hasLength(1));

        // The repository has a newer unrelated field that has not reached the
        // widget. The cover save must merge against this fresh backend view.
        backend.stored = ViewPB.fromBuffer(backend.stored.writeToBuffer())
          ..extra = backend.stored.extra
              .replaceFirst('preserve me', 'newer metadata');
        await _selectCover(tester, _cover);
        expect(find.byType(WorkspacePageCover), findsOneWidget);
        expect(
          tester.widget<ViewCoverImage>(find.byType(ViewCoverImage)).cover,
          _cover,
        );
        expect(backend.stored.cover, _cover);
        expect(
          decodeViewExtra(backend.stored.extra)['unrelated'],
          'newer metadata',
        );
        expect(
          backend.extraWrites,
          isEmpty,
          reason: 'No second raw-extra cover write',
        );
        expect(tester.state(find.byType(MediaActionButtons)), same(actions));
        expect(tester.widget<IconButton>(find.byKey(_share)).onPressed, isNull);

        await clickFileControl(
          tester,
          find.byKey(const ValueKey('workspace-file-rename')),
        );
        await tester.enterText(find.byKey(_titleInput), 'Renamed.py');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settleFileControls(tester);
        expect(find.text('Renamed.py'), findsOneWidget);
        expect(backend.renames, ['Renamed.py']);
        await _selectCover(tester, _replacement);
        expect(backend.stored.cover, _replacement);
        expect(find.text('Renamed.py'), findsOneWidget);

        // Exercise the existing full icon picker’s actual selection callbacks.
        await clickFileControl(tester, find.byType(ViewIconPicker));
        final selectIcon = tester
            .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
            .onSelectedEmoji!;
        selectIcon(EmojiIconData.emoji('📘').toSelectedResult(keepOpen: true));
        await settleFileControls(tester);
        expect(backend.stored.icon.value, '📘');
        selectIcon(EmojiIconData.emoji('🌿').toSelectedResult(keepOpen: true));
        await settleFileControls(tester);
        expect(backend.stored.icon.value, '🌿');
        selectIcon(EmojiIconData.none().toSelectedResult());
        await settleFileControls(tester);
        expect(backend.stored.icon.value, isEmpty);
        expect(backend.iconWrites, hasLength(3));

        await clickFileControl(
          tester,
          find.byKey(const ValueKey('view-decoration-remove')),
        );
        expect(backend.stored.cover!.isNone, isTrue);
        expect(find.byType(ViewCoverImage), findsNothing);
        expect(_coverAction.hitTestable(), findsOneWidget);
        expect(
          backend.covers.saves.map((save) => save.$2),
          [_cover, _replacement, const PageStyleCover.none()],
        );
        expect(
          backend.covers.deleted,
          isEmpty,
          reason: 'Color covers own no asset to delete',
        );
        expect(
          tester.state(find.byType(WorkspaceFileIdentityRow)),
          same(identity),
        );
        expect(
          tester.state(find.byType(ViewDecorationActions)),
          same(decoration),
        );
        expect(tester.state(find.byType(FilePreview)), same(renderer));
        expect(tester.state(find.byType(SandboxedCodeRunner)), same(runner));
        expect(
          tester.widget<TextField>(_sourceField).controller,
          same(controller),
        );
        expect(controller.text, startsWith('Never flush this draft\n'));
        expect(
          controller.selection,
          const TextSelection(baseOffset: 2, extentOffset: 18),
        );
        expect(field.scrollController!.offset, 65);
        expect(backend.loads, 1);
        expect(file.reads, 1);
        expect(file.writes, 0);
        expect(backend.stored.workspaceItem?.storageUrl, file.path);
        pendingCopy.complete();
        await settleFileControls(tester);
        expect(
          find.byKey(const ValueKey('media-copied')),
          findsNothing,
          reason: 'An old-name copy cannot publish feedback after rename',
        );
        await clickFileControl(tester, find.byKey(_share));
        expect(backend.media.shares.single.name, 'Renamed.py');
        expect(backend.media.shares.single.source, file.path);
        expect(tester.takeException(), isNull);
      } finally {
        if (!pendingCopy.isCompleted) pendingCopy.complete();
        await unmountFileControls(tester);
      }
    });

    testWidgets(
        '$mode: a cover and viewer settings serialize without overwriting each other',
        (tester) async {
      final file = MemoryCodeFile('print("fixture")');
      final backend = FileControlBackend(
        fileControlView('serialized', 'source.py', file.path),
        file,
      );
      final saved = Completer<void>();
      backend.covers.saveGate = saved.future;
      try {
        await mountFileControls(
          tester,
          backend.viewer(),
          mode: mode,
          accessible: true,
        );
        await _selectCover(tester, _cover);
        expect(backend.covers.saves, hasLength(1));
        await clickFileControl(
          tester,
          find.byKey(const ValueKey('code-line-numbers')),
        );
        expect(
          backend.extraWrites,
          isEmpty,
          reason: 'Viewer settings wait for the existing cover write',
        );
        saved.complete();
        await settleFileControls(tester);
        expect(backend.stored.cover, _cover);
        expect(
          WorkspaceFilePreviewCodec.decode(
            backend.stored.extra,
          )['show_code_line_numbers'],
          isFalse,
        );
        expect(
          decodeViewExtra(backend.stored.extra)['unrelated'],
          'preserve me',
        );
        expect(backend.extraWrites, hasLength(1));
        expect(file.reads, 1);
        expect(file.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!saved.isCompleted) saved.complete();
        await unmountFileControls(tester);
      }
    });
  }

  for (final invalidation in [
    'lock',
    'delete',
    'rebind',
    'new cover',
    'read only',
  ]) {
    testWidgets(
        'cover preflight rejects $invalidation without dispatching a stale write',
        (tester) async {
      final file = MemoryCodeFile('print("guarded")');
      final original = fileControlView('first', 'First.py', file.path);
      final backend = FileControlBackend(original, file);
      final current = ValueNotifier(original);
      final editable = ValueNotifier(true);
      final preflight = Completer<FlowyResult<ViewPB, FlowyError>>();
      try {
        await mountFileControls(
          tester,
          ValueListenableBuilder<ViewPB>(
            valueListenable: current,
            builder: (_, view, __) => ValueListenableBuilder<bool>(
              valueListenable: editable,
              builder: (_, allowed, __) =>
                  backend.viewer(view: view, editable: allowed),
            ),
          ),
          accessible: true,
          reduced: true,
        );
        backend.readGate = preflight.future;
        await _selectCover(tester, _cover);
        expect(backend.covers.saves, isEmpty);
        switch (invalidation) {
          case 'lock':
            backend.publish(
              ViewPB.fromBuffer(original.writeToBuffer())..isLocked = true,
            );
          case 'delete':
            backend.listeners.single.deleted!(FlowyResult.success(original));
          case 'rebind':
            current.value = fileControlView('second', 'Second.py', file.path);
          case 'new cover':
            backend.publish(
              ViewPB.fromBuffer(original.writeToBuffer())
                ..extra =
                    ViewCoverCodec.mergeCover(original.extra, _replacement),
            );
          case 'read only':
            editable.value = false;
        }
        await settleFileControls(tester);
        preflight.complete(FlowyResult.success(original));
        await settleFileControls(tester);
        expect(backend.covers.saves, isEmpty);
        expect(backend.covers.deleted, isEmpty);
        expect(backend.extraWrites, isEmpty);
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason: 'A stale request must not report on the current target',
        );
        expect(file.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!preflight.isCompleted) {
          preflight.complete(FlowyResult.success(original));
        }
        await unmountFileControls(tester);
        current.dispose();
        editable.dispose();
      }
    });
  }

  testWidgets('cover save failure keeps its prior cover and permits retry',
      (tester) async {
    final file = MemoryCodeFile('print("retry")');
    final view = fileControlView('retry', 'Retry.py', file.path)
      ..extra = ViewCoverCodec.mergeCover(
        fileControlView('retry', 'Retry.py', file.path).extra,
        _cover,
      );
    final backend = FileControlBackend(view, file)..covers.failSave = true;
    try {
      await mountFileControls(tester, backend.viewer(), accessible: true);
      await clickFileControl(
        tester,
        find.byKey(const ValueKey('view-decoration-remove')),
      );
      expect(backend.stored.cover, _cover);
      expect(
        tester.widget<ViewCoverImage>(find.byType(ViewCoverImage)).cover,
        _cover,
      );
      backend.covers.failSave = false;
      await clickFileControl(
        tester,
        find.byKey(const ValueKey('view-decoration-remove')),
      );
      expect(backend.stored.cover!.isNone, isTrue);
      expect(file.reads, 1);
      expect(file.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
    }
  });
}

Finder get _sourceField =>
    find.byWidgetPredicate((widget) => widget is TextField && widget.expands);
Finder get _coverAction => find.byWidgetPredicate(
      (widget) =>
          widget is DecorationActionButton &&
          widget.icon == FlowySvgs.add_cover_s,
    );

Future<void> _selectCover(WidgetTester tester, PageStyleCover cover) async {
  await clickFileControl(tester, _coverAction);
  expect(find.byType(UploadImageMenu), findsOneWidget);
  tester
      .widget<UploadImageMenu>(find.byType(UploadImageMenu))
      .onSelectedColor!(cover.value);
  await settleFileControls(tester);
}
