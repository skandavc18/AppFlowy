import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/local_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/workspace_file/workspace_file_identity.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

const _canvas = ValueKey('workspace-file-canvas');
const _header = ValueKey('workspace-file-identity-row');
const _title = ValueKey('workspace-file-name');
const _icon = ValueKey('workspace-file-identity-icon');
const _tools = ValueKey('workspace-file-tools');
const _scroll = ValueKey('workspace-file-toolbar-scroll');
const _content = ValueKey('workspace-file-toolbar-content');
const _cover = ValueKey('workspace-file-cover');
const _addCover = ValueKey('workspace-file-add-cover');
const _rename = ValueKey('workspace-file-rename');
const _titleInput = ValueKey('workspace-inline-name-editor');
const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');
const _probe = ValueKey('file-header-renderer-probe');
const _fit = ValueKey('file-header-fit');
const _edit = ValueKey('file-header-edit');
const _savedCover =
    PageStyleCover(type: PageStyleCoverImageType.pureColor, value: '#B8C9A6');
const _nextCover =
    PageStyleCover(type: PageStyleCoverImageType.pureColor, value: '#D8BC96');
const _codeActions = [
  ValueKey('code-language-menu'),
  ValueKey('code-line-numbers'),
  ValueKey('code-tests'),
  ValueKey('code-run'),
  ValueKey('code-copy'),
  ValueKey('code-collapse'),
  _copy,
  _share,
  _rename,
];
final _source = List.generate(160, (i) => 'print("line $i")').join('\n');

void main() {
  fileControlTestSetup();

  for (final mode in fileControlAppearances) {
    for (final (width, scale, dpr) in const [
      (1280.0, 1.0, 1.0),
      (1750.0, 1.0, 1.0),
      // A 1750-physical-pixel window at 200% display scale is 875 logical px.
      (875.0, 1.0, 2.0),
      (640.0, 2.0, 2.0),
      (320.0, 2.0, 2.0),
      (240.0, 2.0, 2.0),
    ]) {
      testWidgets(
          '$mode/$width/text=$scale/dpr=$dpr: actual code tools reach the pane gutter',
          (tester) async {
        final file = MemoryCodeFile(_source);
        final backend = FileControlBackend(
          fileControlView('geometry', 'A long original source.py', file.path),
          file,
        );
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await _mount(
            tester,
            backend.viewer(),
            mode: mode,
            width: width,
            scale: scale,
          );
          final pane = tester.getRect(find.byKey(_canvas));
          final header = tester.getRect(find.byKey(_header));
          final tools = tester.getRect(find.byKey(_tools));
          final code =
              tester.getRect(find.byKey(const ValueKey('code-controls')));
          final inset = WorkspaceTokens.pageInset(width);
          expect(pane.width, closeTo(width, 0.01));
          expect(tools.right, closeTo(pane.right - inset, 0.01));
          expect(
            tester.getRect(find.byKey(_icon)).left,
            closeTo(pane.left + inset, 0.01),
          );
          final rects = await _expectActionsInside(
            tester,
            _codeActions.map(find.byKey),
            code,
          );
          final lastPaintedEdge = tester.getRect(find.byKey(_rename)).right;
          // Finite publishers pick their compact padding from the width they
          // are offered, hug their controls and wrap when needed.
          expect(
            lastPaintedEdge,
            closeTo(
              pane.right -
                  inset -
                  (fileToolsOfferedWidth(tester) < 520 ? 4 : 6),
              0.01,
            ),
          );
          expectFileToolsBesideOrBelowTitle(
            tester,
            beside: scale == 1
                ? true
                : width <= 320
                    ? false
                    : null,
          );
          expect(rects, hasLength(_codeActions.length));
          _expectAddCoverAboveTitle(tester);
          _expectOneHeaderScrollRow();
          expect(find.byType(WorkspacePageIdentity), findsOneWidget);
          final tallIconActions = width == 320 && scale == 2;
          // Bare identity rows center the icon beside their decoration tools.
          // At 320px/200%, two 50px action lines plus their 4px gap are 104px
          // tall, centering the unchanged 56px icon 24px below the row top.
          expect(tester.getSize(find.byKey(_icon)), const Size.square(56));
          if (tallIconActions) {
            final iconRow =
                find.byKey(const ValueKey('workspace-page-icon-row'));
            expect(tester.getRect(iconRow).top - header.top, 20);
            expect(
              tester
                  .getSize(
                    find
                        .descendant(of: iconRow, matching: find.byType(Wrap))
                        .first,
                  )
                  .height,
              104,
            );
          }
          expect(
            tester.getRect(find.byKey(_icon)).top - header.top,
            closeTo(
              tallIconActions ? 44 : WorkspaceTokens.pageTopWithoutCover,
              0.01,
            ),
          );
          expect(
            tester.getRect(find.byKey(_title)).top,
            greaterThanOrEqualTo(
              tester.getRect(find.byKey(_icon)).bottom +
                  WorkspaceTokens.pageIconTitleGap,
            ),
          );
          expect(header.bottom, lessThan(tester.getRect(_sourceField).bottom));
          final context = tester.element(find.byKey(_header));
          expect(
            tester.widget<DocumentViewportBar>(find.byKey(_header)).background,
            DocumentViewportStyle.of(context).canvas,
          );
          if (mode == 'paper') {
            expect(PaperTheme.isEnabled(context), isTrue);
            expect(
              DocumentViewportStyle.of(context).canvas,
              PaperTheme.editorBackground,
            );
          }
          expect(backend.loads, 1);
          expect(file.reads, 1);
          expect(file.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await unmountFileControls(tester);
        }
      });
    }

    // Exercise the common header contract for EVERY catalog kind, plus the
    // JSON and mail routes. Native media/PDF/Office engines are not substituted
    // with pretend renderers: these cases intentionally test header ownership
    // only; the actual code renderer is covered above and below.
    for (final (kind, extension) in [
      for (final kind in WorkspaceFileKind.values)
        (kind.name, kind.fileExtension),
      ('json', 'json'),
      ('mail', 'eml'),
    ]) {
      testWidgets(
          '$mode/$kind: one cover owner above identity at wide and compact widths',
          (tester) async {
        final file =
            MemoryCodeFile('fixture', path: '/fixture/original.$extension');
        final view =
            fileControlView('contract-$kind', 'Original.$extension', file.path);
        view.extra = ViewCoverCodec.mergeCover(view.extra, _savedCover);
        final backend = FileControlBackend(view, file);
        final hostKey = GlobalKey<_HeaderHarnessState>();
        final actionKeys = List.generate(10, (i) => ValueKey('format-tool-$i'));
        final child = _HeaderHarness(
          key: hostKey,
          backend: backend,
          controls: StandaloneFileHeader(
            actions: [
              for (final key in actionKeys)
                DocumentViewportButton(
                  key: key,
                  icon: Icons.tune_rounded,
                  tooltip: key.value,
                  onPressed: () {},
                ),
            ],
          ),
        );
        try {
          await _mount(tester, child, mode: mode, width: 1280);
          final identity = tester.state(find.byType(WorkspaceFileIdentityRow));
          final decoration = tester.state(find.byType(ViewDecorationActions));
          final renderer = tester.element(find.byKey(_probe));
          _expectSavedCoverAboveTitle(tester, _savedCover);

          if (kind == 'archive') {
            // The existing top-left identity, not a second Change Icon menu.
            await clickFileControl(tester, find.byKey(_icon));
            expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
            tester
                .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
                .onSelectedEmoji!(EmojiIconData.emoji('📦').toSelectedResult());
            await settleFileControls(tester);
            expect(backend.iconWrites.single.emoji, '📦');
            expect(find.byType(FlowyIconEmojiPicker), findsNothing);
          }

          await clickFileControl(
            tester,
            find.byKey(const ValueKey('view-decoration-remove')),
          );
          _expectAddCoverAboveTitle(tester);
          await clickFileControl(tester, _coverAction);
          expect(find.byType(UploadImageMenu), findsOneWidget);
          tester
              .widget<UploadImageMenu>(find.byType(UploadImageMenu))
              .onSelectedColor!(_nextCover.value);
          await settleFileControls(tester);
          _expectSavedCoverAboveTitle(tester, _nextCover);
          expect(backend.covers.saves.map((entry) => entry.$2), [
            const PageStyleCover.none(),
            _nextCover,
          ]);

          for (final (width, scale) in const [(1280.0, 1.0), (320.0, 2.0)]) {
            await _mount(tester, child, mode: mode, width: width, scale: scale);
            final pane = tester.getRect(find.byKey(_canvas));
            final header = tester.getRect(find.byKey(_header));
            final bounds = Rect.fromLTRB(
              pane.left + WorkspaceTokens.pageInset(width),
              header.top,
              pane.right - WorkspaceTokens.pageInset(width),
              header.bottom,
            );
            final rects = await _expectActionsInside(
              tester,
              [...actionKeys, _copy, _share, _rename].map(find.byKey),
              bounds,
            );
            expect(
              rects.map((rect) => rect.right).reduce(math.max),
              closeTo(tester.getSize(find.byKey(_content)).width, 0.01),
            );
            expect(rects, hasLength(actionKeys.length + 3));
            _expectSavedCoverAboveTitle(tester, _nextCover);
            _expectOneHeaderScrollRow();
            expect(
              tester.state(find.byType(WorkspaceFileIdentityRow)),
              same(identity),
            );
            expect(
              tester.state(find.byType(ViewDecorationActions)),
              same(decoration),
            );
            expect(tester.element(find.byKey(_probe)), same(renderer));
          }
          hostKey.currentState!.setEditable(false);
          await settleFileControls(tester);
          _expectSavedCoverAboveTitle(tester, _nextCover, editable: false);
          expect(find.byType(ViewIconPicker), findsNothing);
          expect(find.byKey(_rename), findsNothing);
          expect(find.byKey(_copy).hitTestable(), findsOneWidget);
          expect(find.byKey(_share).hitTestable(), findsOneWidget);
          expect(backend.stored.workspaceItem?.storageUrl, file.path);
          expect(
            decodeViewExtra(backend.stored.extra)['unrelated'],
            'preserve me',
          );
          expect(backend.extraWrites, isEmpty);
          expect(backend.covers.deleted, isEmpty);
          expect(file.reads, 0);
          expect(file.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await unmountFileControls(tester);
        }
      });
    }

    testWidgets(
        '$mode: resizing and external covers retain rename/source drafts and pending copy',
        (tester) async {
      final file = MemoryCodeFile(_source);
      final backend = FileControlBackend(
        fileControlView('retained', 'Original.py', file.path),
        file,
      );
      final viewer = backend.viewer();
      final pendingCopy = Completer<void>();
      backend.media.pending = pendingCopy.future;
      try {
        await _mount(tester, viewer, mode: mode, width: 1750);
        final renderer = tester.state(find.byType(FilePreview));
        final runner = tester.state(find.byType(SandboxedCodeRunner));
        final actions = tester.state(find.byType(MediaActionButtons));
        final editor = tester.state(
          find.descendant(
            of: _sourceField,
            matching: find.byType(EditableText),
          ),
        );
        final field = tester.widget<TextField>(_sourceField);
        const selection = TextSelection(baseOffset: 3, extentOffset: 16);
        field.controller!.value = TextEditingValue(
          text: 'Unsaved source\n$_source',
          selection: selection,
        );
        field.scrollController!.jumpTo(60);
        await tester.pump();
        await clickFileControl(tester, find.byKey(_copy));
        await clickFileControl(tester, find.byKey(_rename));
        await tester.enterText(find.byKey(_titleInput), 'Unsaved name.py');
        final name = tester.widget<EditableText>(find.byKey(_titleInput));
        const nameSelection = TextSelection(baseOffset: 2, extentOffset: 7);
        name.controller.selection = nameSelection;
        final nameState = tester.state(find.byKey(_titleInput));
        final toolElement =
            tester.element(find.byKey(const ValueKey('code-line-numbers')));

        for (final (width, scale, cover) in const [
          (320.0, 2.0, _savedCover),
          (1280.0, 1.0, _nextCover),
          (1750.0, 1.0, PageStyleCover.none()),
        ]) {
          backend.publish(
            ViewPB.fromBuffer(backend.stored.writeToBuffer())
              ..extra = ViewCoverCodec.mergeCover(backend.stored.extra, cover),
          );
          await _mount(tester, viewer, mode: mode, width: width, scale: scale);
          if (cover.isNone) {
            _expectAddCoverAboveTitle(tester);
          } else {
            _expectSavedCoverAboveTitle(tester, cover);
          }
          expect(tester.state(find.byType(FilePreview)), same(renderer));
          expect(tester.state(find.byType(SandboxedCodeRunner)), same(runner));
          expect(tester.state(find.byType(MediaActionButtons)), same(actions));
          expect(
            tester.state(
              find.descendant(
                of: _sourceField,
                matching: find.byType(EditableText),
              ),
            ),
            same(editor),
          );
          expect(
            tester.widget<TextField>(_sourceField).controller,
            same(field.controller),
          );
          expect(field.controller!.text, 'Unsaved source\n$_source');
          expect(field.controller!.selection, selection);
          expect(field.scrollController!.offset, 60);
          expect(tester.state(find.byKey(_titleInput)), same(nameState));
          expect(
            tester.widget<EditableText>(find.byKey(_titleInput)).controller,
            same(name.controller),
          );
          expect(name.controller.text, 'Unsaved name.py');
          expect(name.controller.selection, nameSelection);
          expect(name.focusNode.hasPrimaryFocus, isTrue);
          expect(
            tester.element(find.byKey(const ValueKey('code-line-numbers'))),
            same(toolElement),
          );
          expect(
            tester.widget<IconButton>(find.byKey(_share)).onPressed,
            isNull,
          );
          expect(backend.renames, isEmpty);
          expect(backend.loads, 1);
          expect(file.reads, 1);
          expect(file.writes, 0);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settleFileControls(tester);
        expect(find.byKey(_titleInput), findsNothing);
        expect(backend.renames, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await settleFileControls(tester);
        await tester.enterText(find.byKey(_titleInput), 'Accepted');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settleFileControls(tester);
        expect(backend.renames, ['Accepted.py']);
        expect(find.text('Accepted.py'), findsOneWidget);
        expect(backend.stored.workspaceItem?.storageUrl, file.path);
        expect(tester.state(find.byType(FilePreview)), same(renderer));
        pendingCopy.complete();
        await settleFileControls(tester);
        expect(find.byKey(const ValueKey('media-copied')), findsNothing);
        expect(
          tester.widget<IconButton>(find.byKey(_share)).onPressed,
          isNotNull,
        );
        expect(file.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!pendingCopy.isCompleted) pendingCopy.complete();
        await unmountFileControls(tester);
      }
    });

    testWidgets(
        '$mode: hover, keyboard and popup holds survive the cover slot move and readonly change',
        (tester) async {
      final file = MemoryCodeFile(_source);
      final backend = FileControlBackend(
        fileControlView('keyboard', 'source.py', file.path),
        file,
      );
      final editable = ValueNotifier(true);
      final outside = FocusNode();
      final semantics = tester.ensureSemantics();
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final child = Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: editable,
              builder: (_, allowed, __) => backend.viewer(editable: allowed),
            ),
          ),
          TextButton(
            focusNode: outside,
            onPressed: () {},
            child: const Text('Outside header'),
          ),
        ],
      );
      try {
        await _mount(tester, child, mode: mode, width: 1280, accessible: false);
        final geometry = tester.getRect(find.byType(WorkspaceFileIdentityRow));
        expect(_coverAction.hitTestable(), findsNothing);
        expect(find.semantics.byLabel('Add Cover'), findsNothing);
        await mouse.moveTo(tester.getCenter(find.byKey(_title)));
        await settleFileControls(tester);
        _expectAddCoverAboveTitle(tester);
        expectFileControlPainted(tester, _coverAction);
        await mouse.moveTo(Offset.zero);
        await settleFileControls(tester);
        expect(_coverAction.hitTestable(), findsNothing);
        expect(tester.getRect(find.byType(WorkspaceFileIdentityRow)), geometry);

        await _tabTo(tester, _coverAction);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settleFileControls(tester);
        expect(find.byType(UploadImageMenu), findsOneWidget);
        final stale =
            tester.widget<UploadImageMenu>(find.byType(UploadImageMenu));
        outside.requestFocus();
        await settleFileControls(tester);
        expectFileControlPainted(tester, _coverAction);
        expectFileControlPainted(tester, find.byKey(_copy));
        expect(tester.getRect(find.byType(WorkspaceFileIdentityRow)), geometry);

        editable.value = false;
        await settleFileControls(tester);
        expect(find.byType(UploadImageMenu), findsNothing);
        stale.onSelectedColor!(_savedCover.value);
        await settleFileControls(tester);
        expect(backend.covers.saves, isEmpty);
        expect(find.byType(DecorationActionButton), findsNothing);
        expect(find.byType(ViewIconPicker), findsNothing);
        expect(find.byKey(_rename), findsNothing);
        outside.requestFocus();
        await settleFileControls(tester);
        expect(find.byKey(_copy).hitTestable(), findsOneWidget);

        // A renderer-owned language menu must still hold the viewer's tools;
        // a decoration-local scope must not shadow the viewer's parent hold.
        await _tabTo(tester, find.byKey(const ValueKey('code-language-menu')));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settleFileControls(tester);
        outside.requestFocus();
        await settleFileControls(tester);
        expect(find.byType(AppMenuRow), findsWidgets);
        expectFileControlPainted(tester, find.byKey(_copy));
        await clickFileControl(tester, find.widgetWithText(AppMenuRow, 'Java'));
        expect(backend.extraWrites, isEmpty);

        await _mount(tester, child, mode: mode, width: 320, scale: 2);
        await _tabTo(tester, find.byKey(_copy));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settleFileControls(tester);
        await _tabTo(tester, find.byKey(_share));
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await settleFileControls(tester);
        expect(backend.media.copies.single.source, file.path);
        expect(backend.media.shares.single.source, file.path);
        expect(tester.widget<TextField>(_sourceField).readOnly, isTrue);
        expect(file.reads, 1);
        expect(file.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await unmountFileControls(tester);
        editable.dispose();
        outside.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
        '$mode: source Copy and original-file Copy remain distinct single controls',
        (tester) async {
      final file = MemoryCodeFile('print("source, not a file URI")');
      final backend = FileControlBackend(
        fileControlView('copy', 'source.py', file.path),
        file,
      );
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        } else if (call.method == 'Clipboard.hasStrings') {
          return {'value': clipboard.isNotEmpty};
        } else if (call.method == 'Clipboard.getData') {
          return {'text': clipboard.isEmpty ? '' : clipboard.last};
        }
        return null;
      });
      try {
        await _mount(tester, backend.viewer(), mode: mode, width: 1750);
        expect(find.byKey(const ValueKey('code-copy')), findsOneWidget);
        expect(find.byKey(_copy), findsOneWidget);
        await clickFileControl(tester, find.byKey(const ValueKey('code-copy')));
        expect(clipboard, [file.contents]);
        expect(backend.media.copies, isEmpty);
        await clickFileControl(tester, find.byKey(_copy));
        expect(clipboard, [file.contents]);
        expect(backend.media.copies.single.source, file.path);
        expect(backend.media.copies.single.name, 'source.py');
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      }
    });

    testWidgets(
        '$mode: horizontally scrolling Fit/Edit tools retains an in-flight code session',
        (tester) async {
      final file = MemoryCodeFile('print("held")');
      final backend = FileControlBackend(
        fileControlView('running', 'source.py', file.path),
        file,
      );
      final hostKey = GlobalKey<_HeaderHarnessState>();
      final engine = _HeldRunner();
      final draft = TextEditingController(text: 'retained editor draft');
      var fitCalls = 0;
      var editCalls = 0;
      final child = _HeaderHarness(
        key: hostKey,
        backend: backend,
        renderer: SandboxedCodeRunner(
          code: file.contents,
          fileName: 'source.py',
          displayName: 'source.py',
          language: 'python',
          showLineNumbers: true,
          onLanguageChanged: (_) {},
          onToggleLineNumbers: () {},
          onTestCasesChanged: (_) {},
          expandEditor: true,
          framed: false,
          localRunnerFactory: () => engine,
          toolbarTrailing: Wrap(
            children: [
              DocumentViewportFitButton(key: _fit, onPressed: () => fitCalls++),
              DocumentViewportButton(
                key: _edit,
                icon: Icons.edit_rounded,
                tooltip: 'Edit',
                onPressed: () => editCalls++,
              ),
            ],
          ),
          child: TextField(
            key: _probe,
            controller: draft,
            expands: true,
            maxLines: null,
          ),
        ),
      );
      try {
        await _mount(tester, child, mode: mode, width: 1750);
        final runner = tester.state(find.byType(SandboxedCodeRunner));
        final editor = tester.state(
          find.descendant(
            of: find.byKey(_probe),
            matching: find.byType(EditableText),
          ),
        );
        await clickFileControl(tester, find.byKey(const ValueKey('code-run')));
        final terminal = tester.widget<TextField>(find.byType(TextField).last);
        terminal.controller!.text = 'pending stdin';
        // The native terminal has its own status row; this case exercises a
        // wrapped header without changing that separately owned body layout.
        for (final (width, scale) in const [
          (640.0, 2.0),
          (1280.0, 1.0),
          (1750.0, 1.0),
        ]) {
          await _mount(tester, child, mode: mode, width: width, scale: scale);
          await _expectActionsInside(
            tester,
            [..._codeActions, _fit, _edit].map(find.byKey),
            tester.getRect(find.byKey(const ValueKey('code-controls'))),
          );
          expect(tester.state(find.byType(SandboxedCodeRunner)), same(runner));
          expect(
            tester.state(
              find.descendant(
                of: find.byKey(_probe),
                matching: find.byType(EditableText),
              ),
            ),
            same(editor),
          );
          expect(
            tester.widget<TextField>(find.byType(TextField).last).controller,
            same(terminal.controller),
          );
          expect(terminal.controller!.text, 'pending stdin');
          expect(draft.text, 'retained editor draft');
          expect(engine.runs, 1);
          expect(engine.cancelled, isFalse);
          expect(
            tester
                .widget<CodeToolbarButton>(
                  find.byKey(const ValueKey('code-run')),
                )
                .tooltip,
            'Stop',
          );
        }
        await tester.ensureVisible(find.byKey(_fit));
        await settleFileControls(tester);
        await clickFileControl(tester, find.byKey(_fit));
        await tester.ensureVisible(find.byKey(_edit));
        await settleFileControls(tester);
        await clickFileControl(tester, find.byKey(_edit));
        expect(fitCalls, 1);
        expect(editCalls, 1);
        await clickFileControl(tester, find.byKey(const ValueKey('code-run')));
        expect(engine.cancelled, isTrue);
        engine.done.complete(
          const LocalCodeResult(stdout: '', stderr: '', exitCode: 0),
        );
        await settleFileControls(tester);
        expect(tester.takeException(), isNull);
      } finally {
        if (!engine.done.isCompleted) {
          engine.done.complete(
            const LocalCodeResult(stdout: '', stderr: '', exitCode: 0),
          );
        }
        await unmountFileControls(tester);
        draft.dispose();
      }
    });
  }

  testWidgets('legacy percentage-based toolbar receives a finite one-row slot',
      (tester) async {
    final file = MemoryCodeFile('fixture', path: '/fixture/legacy.ipynb');
    final backend = FileControlBackend(
      fileControlView('legacy-toolbar', 'Legacy.ipynb', file.path),
      file,
    );
    const first = ValueKey('legacy-first-action');
    const last = ValueKey('legacy-last-action');
    final measuredWidths = <double>[];
    final child = _HeaderHarness(
      backend: backend,
      controls: StandaloneFileHeader(
        toolbar: LayoutBuilder(
          builder: (context, constraints) {
            measuredWidths.add(constraints.maxWidth);
            final firstWidth = constraints.maxWidth * 0.48;
            final secondWidth = constraints.maxWidth - firstWidth;
            return Row(
              children: [
                SizedBox(
                  width: firstWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: first,
                      onPressed: () {},
                      child: const Text('Kernel'),
                    ),
                  ),
                ),
                SizedBox(
                  width: secondWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: last,
                      onPressed: () {},
                      child: const Text('Run all'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    try {
      for (final (width, scale) in const [(1280.0, 1.0), (240.0, 2.0)]) {
        await _mount(tester, child, width: width, scale: scale);
        expect(
          measuredWidths,
          everyElement(allOf(isPositive, lessThan(double.infinity))),
        );
        final rects = await _expectActionsInside(
          tester,
          [first, last, _copy, _share, _rename].map(find.byKey),
          tester.getRect(find.byKey(_header)),
        );
        expect(rects, hasLength(5));
        _expectOneHeaderScrollRow();
        expect(tester.takeException(), isNull);
      }
    } finally {
      await unmountFileControls(tester);
    }
  });

  testWidgets(
      'shared header places tools physically right without remounting in RTL',
      (tester) async {
    final editor = TextEditingController(text: 'a retained title');
    final width = ValueNotifier(1280.0);
    final direction = ValueNotifier(ui.TextDirection.ltr);
    const leadingKey = ValueKey('directional-title');
    const toolKey = ValueKey('directional-tool');
    final child = ValueListenableBuilder<ui.TextDirection>(
      valueListenable: direction,
      builder: (_, value, __) => Directionality(
        textDirection: value,
        child: ValueListenableBuilder<double>(
          valueListenable: width,
          builder: (_, value, __) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: value,
              child: StandaloneFileHeaderLayout(
                identity: TextField(key: leadingKey, controller: editor),
                tools: TextButton(
                  key: toolKey,
                  onPressed: () {},
                  child: const Text('Tool'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    try {
      await _mount(tester, child, width: 1280);
      final field = tester.state(
        find.descendant(
          of: find.byKey(leadingKey),
          matching: find.byType(EditableText),
        ),
      );
      for (final textDirection in ui.TextDirection.values) {
        direction.value = textDirection;
        for (final available in [1280.0, 240.0]) {
          width.value = available;
          await settleFileControls(tester);
          final bounds =
              tester.getRect(find.byType(StandaloneFileHeaderLayout));
          final tool = tester.getRect(find.byKey(toolKey));
          final title = tester.getRect(find.byKey(leadingKey));
          expect(
            tool.right,
            closeTo(bounds.right, 0.01),
          );
          expect(
            title.left,
            closeTo(bounds.left, 0.01),
          );
          expect(
            tester.state(
              find.descendant(
                of: find.byKey(leadingKey),
                matching: find.byType(EditableText),
              ),
            ),
            same(field),
          );
          expect(find.byKey(toolKey).hitTestable(), findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      editor.dispose();
      width.dispose();
      direction.dispose();
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

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  String mode = 'light',
  required double width,
  double scale = 1,
  bool accessible = true,
}) async {
  await mountFileControls(
    tester,
    child,
    mode: mode,
    width: width,
    textScale: scale,
    accessible: accessible,
    reduced: true,
  );
  // The existing helper starts with a 1100px surface. Enlarge the *actual*
  // logical surface, not just a SizedBox which would be clamped to 1100px.
  await tester.binding.setSurfaceSize(Size(width + 64, 960));
  await settleFileControls(tester);
}

Future<List<Rect>> _expectActionsInside(
  WidgetTester tester,
  Iterable<Finder> actions,
  Rect bounds,
) async {
  final scroll =
      tester.widget<SingleChildScrollView>(find.byKey(_scroll)).controller!;
  final initialOffset = scroll.offset;
  final rects = <Rect>[];
  for (final action in actions) {
    expect(action, findsOneWidget);
    if (action.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(action);
    }
    await settleFileControls(tester);
    expect(action.hitTestable(), findsOneWidget);
    final rect = tester.getRect(action);
    final viewport = tester.getRect(find.byKey(_scroll));
    expect(rect.isEmpty, isFalse);
    expect(rect.left, greaterThanOrEqualTo(viewport.left - 0.01));
    expect(rect.right, lessThanOrEqualTo(viewport.right + 0.01));
    expect(rect.top, greaterThanOrEqualTo(bounds.top - 0.01));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.01));
    // Compare geometry in the retained strip's coordinates, independent of
    // which action is currently scrolled into the small viewport.
    final content = tester.renderObject<RenderBox>(find.byKey(_content));
    final local = content.globalToLocal(rect.topLeft) & rect.size;
    for (final previous in rects) {
      expect(local.deflate(0.1).overlaps(previous.deflate(0.1)), isFalse);
    }
    rects.add(local);
  }
  // ensureVisible aligns the last button, not its enclosing toolbar padding.
  // On this reversed strip it leaves a 6px offset when overflow is available.
  // Restore the original position before callers assert the pane gutter;
  // every action's hit target, containment and non-overlap were checked above.
  scroll.jumpTo(initialOffset);
  await settleFileControls(tester);
  expect(scroll.offset, closeTo(initialOffset, 0.01));
  return rects;
}

void _expectOneHeaderScrollRow() => expect(
      find.descendant(
        of: find.byKey(_header),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
      findsOneWidget,
    );

void _expectAddCoverAboveTitle(WidgetTester tester) {
  expect(find.byType(ViewDecorationActions), findsOneWidget);
  expect(find.byType(ViewCoverImage), findsNothing);
  expect(find.byKey(_addCover), findsOneWidget);
  expect(_coverAction, findsOneWidget);
  expect(
    tester.widget<DecorationActionButton>(_coverAction).label,
    'Add Cover',
  );
  expect(
    tester.getRect(_coverAction).bottom,
    lessThanOrEqualTo(tester.getRect(find.byKey(_title)).top),
  );
  expect(
    tester.getRect(find.byKey(_addCover)).bottom,
    lessThanOrEqualTo(tester.getRect(find.byKey(_title)).top),
  );
  expect(
    find.byKey(const ValueKey('workspace-file-change-icon')),
    findsOneWidget,
  );
}

void _expectSavedCoverAboveTitle(
  WidgetTester tester,
  PageStyleCover cover, {
  bool editable = true,
}) {
  expect(find.byType(ViewDecorationActions), findsOneWidget);
  expect(find.byType(ViewCoverImage), findsOneWidget);
  expect(
    tester.widget<ViewCoverImage>(find.byType(ViewCoverImage)).cover,
    cover,
  );
  expect(find.byKey(_addCover), findsNothing);
  expect(
    tester.getRect(find.byKey(_cover)).bottom,
    lessThanOrEqualTo(tester.getRect(find.byKey(_header)).top),
  );
  if (editable) {
    expect(_coverAction, findsOneWidget);
    expect(
      tester.widget<DecorationActionButton>(_coverAction).label,
      'Change Cover',
    );
  } else {
    expect(_coverAction, findsNothing);
  }
}

Future<void> _tabTo(WidgetTester tester, Finder control) async {
  final native = find.descendant(
    of: control,
    matching: find.byWidgetPredicate(
      (widget) => widget is TextButton || widget is IconButton,
    ),
    matchRoot: true,
  );
  expect(native, findsOneWidget);
  bool focused() {
    final target = tester.element(native);
    var within = false;
    FocusManager.instance.primaryFocus?.context
        ?.visitAncestorElements((element) {
      if (identical(element, target)) within = true;
      return !within;
    });
    return within;
  }

  for (var i = 0; i < 40 && !focused(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settleFileControls(tester);
  }
  expect(
    focused(),
    isTrue,
    reason: 'Controls retain their native Tab targets after wrapping',
  );
  final data = tester.getSemantics(native).getSemanticsData();
  expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
}

/// Header/publication-only harness for formats whose engines require native
/// plugins. Real controls, decoration persistence and identity widgets are used.
class _HeaderHarness extends StatefulWidget {
  const _HeaderHarness({
    super.key,
    required this.backend,
    this.controls = const StandaloneFileHeader(),
    this.renderer,
  });
  final FileControlBackend backend;
  final StandaloneFileHeader controls;
  final Widget? renderer;

  @override
  State<_HeaderHarness> createState() => _HeaderHarnessState();
}

class _HeaderHarnessState extends State<_HeaderHarness> {
  final chrome = StandaloneFileChromeController();
  final binding = Object();
  late ViewPB view = widget.backend.stored;
  late final rendererName = view.name;
  bool editable = true;

  void setEditable(bool value) => setState(() => editable = value);
  bool get canEdit => editable && !view.isLocked;

  @override
  void dispose() {
    chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PreviewToolbarRegion(
        child: StandaloneFileScope(
          canvas: DocumentViewportStyle.of(context).canvas,
          rendererName: rendererName,
          displayName: view.name,
          chrome: chrome,
          canEdit: () => canEdit,
          canRead: () => true,
          editable: canEdit,
          available: true,
          child: ColoredBox(
            key: _canvas,
            color: DocumentViewportStyle.of(context).canvas,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<StandaloneFileHeader>(
                  valueListenable: chrome,
                  builder: (_, controls, __) => WorkspaceFileIdentityRow(
                    view: view,
                    binding: binding,
                    summary: 'File · 7 B',
                    canRename: () => canEdit,
                    onViewChanged: (updated) => setState(() => view = updated),
                    repository: widget.backend,
                    coverBackend: widget.backend.covers,
                    updateIcon: widget.backend.writeIcon,
                    source: MediaActionSource(
                      source: widget.backend.file.path,
                      name: view.name,
                    ),
                    mediaActions: widget.backend.media,
                    fileAvailable: true,
                    actionsVisible: false,
                    controls: controls,
                  ),
                ),
                Expanded(
                  child: widget.renderer ??
                      Column(
                        children: [
                          StandaloneFileHeaderSlot(
                            controller: chrome,
                            controls: widget.controls,
                          ),
                          const Expanded(child: SizedBox.expand(key: _probe)),
                        ],
                      ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _HeldRunner extends LocalCodeRunner {
  final done = Completer<LocalCodeResult>();
  int runs = 0;
  bool cancelled = false;
  @override
  bool get acceptsInput => !done.isCompleted;
  @override
  Future<LocalCodeResult> run({
    required LocalToolchain toolchain,
    required String code,
    void Function(String chunk)? onStdout,
    void Function(String chunk)? onStderr,
  }) {
    runs++;
    return done.future;
  }

  @override
  void cancel() => cancelled = true;
}
