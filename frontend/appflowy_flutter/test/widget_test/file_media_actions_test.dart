import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/materialized_file_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_document_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_scroll_physics.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/scrolling/deferred_page_embed.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-user/date_time.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _modes = ['light', 'dark', 'paper'];
const _chipKey = ValueKey('file-block-chip');
const _copyKey = ValueKey('media-copy');
const _shareKey = ValueKey('media-share');
const _copiedKey = ValueKey('media-copied');
const _revealKey = ValueKey('media-action-reveal');
const _previewActionsKey = ValueKey('file-preview-media-actions');
const _frameKey = ValueKey('resizable_media');
const _fade = Duration(milliseconds: 140);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File textFile;
  final originalText = List.generate(
    160,
    (index) => 'Line $index: this text belongs only to the synthetic preview.',
  ).join('\n');

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final families = _modes
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet();
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  setUp(() async {
    // No application storage registration, backend adapter or live workspace.
    temporary = await Directory.systemTemp.createTemp('file_media_actions_');
    textFile = await File('${temporary.path}/notes.txt')
        .writeAsString(originalText, flush: true);
  });
  tearDown(() async => temporary.delete(recursive: true));

  test('FileBlockComponent keeps the production media service default', () {
    final component = FileBlockComponent(node: fileNode(url: 'synthetic.bin'));
    expect(component.mediaActions, same(const MediaActionService()));
  });

  for (final mode in _modes) {
    _test('$mode: real file chip fades without hidden hits or hover rebuilds',
        (tester) async {
      final fixture = _Fixture();
      final semantics = tester.ensureSemantics();
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture, mode: mode);
        final block = _blockState(tester);
        final controls = tester.state(find.byType(MediaActionButtons));
        final builds = fixture.builder.builds;
        final bounds = tester.getRect(find.byKey(_chipKey));
        final document = fixture.json;
        final selection = Selection.collapsed(Position(path: [1], offset: 3));
        fixture.editor.selection = selection;
        await tester.pump();

        _expectReveal(tester, visible: false);
        expect(_paintedOpacity(tester), 0);
        expect(find.byKey(_copyKey).hitTestable(), findsNothing);
        expect(find.byKey(_shareKey).hitTestable(), findsNothing);
        expect(find.semantics.byLabel('Copy'), findsNothing);
        expect(find.semantics.byLabel('Share'), findsNothing);
        expect(fixture.actions.calls, isEmpty);

        await mouse.moveTo(bounds.topLeft + const Offset(18, 18));
        await tester.pump();
        _expectReveal(tester, visible: true);
        await tester.pump(const Duration(milliseconds: 70));
        expect(_paintedOpacity(tester), inExclusiveRange(0, 1));
        await tester.pump(const Duration(milliseconds: 70));
        expect(_paintedOpacity(tester), 1);
        expect(find.byKey(_copyKey).hitTestable(), findsOneWidget);
        expect(find.semantics.byLabel('Copy'), findsOneWidget);
        expect(find.byType(FileMenuTrigger).hitTestable(), findsOneWidget);
        expect(fixture.editor.selection, selection);

        await mouse.moveTo(Offset.zero);
        await tester.pump();
        _expectReveal(tester, visible: false);
        expect(_paintedOpacity(tester), 1);
        expect(find.byKey(_copyKey).hitTestable(), findsNothing);
        // ExcludeSemantics detaches nodes; render-object debugSemantics may
        // still cache them, so query what assistive technology actually sees.
        expect(find.semantics.byLabel('Copy'), findsNothing);
        expect(find.semantics.byLabel('Share'), findsNothing);
        await tester.pump(_fade);
        expect(_paintedOpacity(tester), 0);
        expect(_blockState(tester), same(block));
        expect(tester.state(find.byType(MediaActionButtons)), same(controls));
        expect(fixture.builder.builds, builds);
        expect(tester.getRect(find.byKey(_chipKey)), bounds);
        expect(fixture.editor.selection, selection);
        expect(fixture.json, document);
        expect(fixture.writes, 0);
        expect(fixture.actions.calls, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        semantics.dispose();
        await fixture.dispose(tester);
      }
    });

    _test(
        '$mode: copy awaits completion, keeps scaled layout, and does not clip',
        (tester) async {
      final fixture = _Fixture(
        name: 'A long attachment name that must ellipsize in a narrow page.pdf',
      );
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture, mode: mode, width: 310, textScale: 1.8);
        await _hover(tester, mouse, find.byKey(_chipKey));
        final title = find.text(fixture.file.attributes[FileBlockKeys.name]);
        final titleWidget = tester.widget<Text>(title);
        final bounds = [
          tester.getRect(find.byKey(_chipKey)),
          tester.getRect(title),
          tester.getRect(find.byType(MediaActionButtons)),
        ];
        final document = fixture.json;
        expect(titleWidget.overflow, TextOverflow.ellipsis);
        expect(
          tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
          isTrue,
        );
        expect(_buttons(tester).decorated, isFalse);
        expect(_buttons(tester).buttonSize, 28);
        expect(tester.getSize(find.byKey(_copyKey)), const Size.square(28));
        expect(
          tester.getSize(find.byType(MediaActionButtons)),
          const Size(60, 28),
        );
        final surface = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('media-action-surface')),
        );
        expect((surface.decoration as BoxDecoration).color, isNull);
        if (mode == 'paper') {
          final context = tester.element(find.byKey(_chipKey));
          expect(PaperTheme.isEnabled(context), isTrue);
          final color = (tester
                  .widget<AnimatedContainer>(find.byKey(_chipKey))
                  .decoration! as BoxDecoration)
              .color!;
          expect(color, isNot(Colors.white));
          expect(color.r, greaterThan(color.b));
        }

        final copyAgain = _button(tester, _copyKey).onPressed!;
        final shareWhileBusy = _button(tester, _shareKey).onPressed!;
        await tester.tap(find.byKey(_copyKey));
        copyAgain();
        shareWhileBusy();
        await tester.pump();
        expect(fixture.actions.calls, hasLength(1));
        final copy = fixture.actions.calls.single;
        expect(copy.kind, 'copy');
        expect(copy.source.source, fixture.file.attributes[FileBlockKeys.url]);
        expect(copy.source.name, fixture.file.attributes[FileBlockKeys.name]);
        expect(copy.source.requireAuthentication, isFalse);
        expect(copy.source.httpHeaders, isEmpty);
        expect(copy.source.shareAsLink, isFalse);
        expect(_button(tester, _copyKey).onPressed, isNull);
        expect(_button(tester, _shareKey).onPressed, isNull);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(_copiedKey), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsNothing);

        copy.succeed();
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copiedKey), findsOneWidget);
        expect(_button(tester, _copyKey).tooltip, 'Copied');
        expect(tester.widget<Text>(find.byKey(_copiedKey)).style!.fontSize, 10);
        final bar = tester.getRect(find.byType(MediaActionButtons));
        expect(
          tester.getRect(find.byKey(_copiedKey)).bottom,
          lessThanOrEqualTo(bar.top - 4),
        );
        _expectBadgeUnclipped(tester);
        expect(
          [
            tester.getRect(find.byKey(_chipKey)),
            tester.getRect(title),
            tester.getRect(find.byType(MediaActionButtons)),
          ],
          bounds,
        );
        expect(fixture.json, document);
        expect(fixture.writes, 0);
        expect(find.byType(SnackBar), findsNothing);

        await tester.pump(const Duration(milliseconds: 1600));
        await tester.pump(_fade);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(_button(tester, _copyKey).tooltip, 'Copy');
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });

    _test(
        '$mode: a loaded text preview keeps its renderer, scroll and selection',
        (tester) async {
      final fixture =
          _Fixture(url: textFile.path, name: 'notes.txt', preview: true);
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture, mode: mode);
        final text = find.descendant(
          of: find.byType(FilePreview),
          matching: find.byType(SelectableText),
        );
        await _waitFor(tester, () => text.evaluate().isNotEmpty);
        expect(text, findsOneWidget);
        final previewState = tester.state(find.byType(FilePreview));
        final previewWidget =
            tester.widget<FilePreview>(find.byType(FilePreview));
        final materializer = tester.state(find.byType(MaterializedFileBuilder));
        final fieldFinder = find.descendant(
          of: text,
          matching: find.byType(EditableText),
        );
        final field = tester.widget<EditableText>(fieldFinder);
        field.focusNode.requestFocus();
        await tester.pump();
        await tester.pump();
        field.controller.selection =
            const TextSelection(baseOffset: 12, extentOffset: 29);
        final position = Scrollable.of(tester.element(text)).position;
        expect(position.maxScrollExtent, greaterThan(100));
        position.jumpTo(100);
        await tester.pump();
        final selection = field.controller.selection;
        final pageSelection = fixture.editor.selection;
        final builds = fixture.builder.builds;
        final document = fixture.json;

        // A focused preview is not a focused action: its bar is still hidden.
        expect(field.focusNode.hasFocus, isTrue);
        _expectReveal(tester, visible: false);
        expect(find.byTooltip('More actions').hitTestable(), findsNothing);
        for (var iteration = 0; iteration < 3; iteration++) {
          await _hover(tester, mouse, find.byKey(_frameKey));
          expect(find.byKey(_copyKey).hitTestable(), findsOneWidget);
          await mouse.moveTo(Offset.zero);
          await tester.pump();
          await tester.pump(_fade);
          _expectReveal(tester, visible: false);
          expect(tester.state(find.byType(FilePreview)), same(previewState));
          expect(
            tester.widget<FilePreview>(find.byType(FilePreview)),
            same(previewWidget),
          );
          expect(
            tester.state(find.byType(MaterializedFileBuilder)),
            same(materializer),
          );
          expect(
            tester.widget<EditableText>(fieldFinder).controller,
            same(field.controller),
          );
          expect(field.controller.selection, selection);
          expect(field.focusNode.hasFocus, isTrue);
          expect(position.pixels, 100);
          expect(fixture.editor.selection, pageSelection);
        }
        expect(fixture.builder.builds, builds);
        expect(fixture.actions.calls, isEmpty);

        // Hidden actions are inert even while their old position is clicked.
        await tester.tapAt(tester.getCenter(find.byKey(_shareKey)));
        await tester.pump();
        expect(fixture.actions.calls, isEmpty);
        await _hover(tester, mouse, find.byKey(_frameKey));
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        fixture.actions.calls.single.succeed();
        await tester.pump();
        await tester.pump(_fade);
        _expectBadgeUnclipped(tester);
        expect(tester.state(find.byType(FilePreview)), same(previewState));
        expect(fixture.json, document);
        expect(fixture.writes, 0);
        expect(await tester.runAsync(textFile.readAsString), originalText);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  for (final mode in _modes) {
    _test('$mode: preview popover holds both action groups and releases safely',
        (tester) async {
      final fixture = _Fixture(
        url: textFile.path,
        name: 'notes.txt',
        preview: true,
        editable: false,
      );
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture, mode: mode);
        await _waitFor(
          tester,
          () => find.byType(SelectableText).evaluate().isNotEmpty,
        );
        final renderer = tester.state(find.byType(FilePreview));
        final block = _blockState(tester);
        final document = fixture.json;
        final menuButton = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'More actions',
        );
        final toolbar = find
            .ancestor(
              of: menuButton,
              matching: find.byType(PreviewToolbar),
            )
            .first;
        void expectHeader(bool visible) => expect(
              tester
                  .widget<AnimatedOpacity>(
                    find
                        .descendant(
                          of: toolbar,
                          matching: find.byType(AnimatedOpacity),
                        )
                        .first,
                  )
                  .opacity,
              visible ? 1 : 0,
            );
        final frame = tester.getRect(find.byKey(_frameKey));
        await mouse.moveTo(Offset(frame.left - 12, frame.center.dy));
        await tester.pump();
        await tester.pump(_fade);
        expectHeader(false);
        _expectReveal(tester, visible: false);

        await _hover(tester, mouse, find.byKey(_frameKey));
        await tester.tap(menuButton, kind: ui.PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        expect(find.byType(FileBlockMenu), findsOneWidget);
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        await tester.pump(_fade);
        expectHeader(true);
        _expectReveal(tester, visible: true);
        block.menuController.close();
        fixture.outsideFocus.requestFocus();
        await tester.pumpAndSettle();
        expectHeader(false);
        _expectReveal(tester, visible: false);

        await tester.tapAt(frame.center);
        await tester.pump();
        await tester.pump(_fade);
        expectHeader(true);
        _expectReveal(tester, visible: true);
        await mouse.moveTo(frame.center);
        await mouse.moveTo(Offset.zero);
        fixture.outsideFocus.requestFocus();
        await tester.pumpAndSettle();
        expectHeader(false);

        for (var i = 0; i < 50 && !_focusedInside(menuButton); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.pump();
        }
        expect(_focusedInside(menuButton), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(FileBlockMenu), findsOneWidget);
        expectHeader(true);
        _expectReveal(tester, visible: true);
        expect(tester.state(find.byType(FilePreview)), same(renderer));
        expect(fixture.actions.calls, isEmpty);
        expect(fixture.writes, 0);
        expect(fixture.json, document);
        final lateClose = tester
            .widget<AppFlowyPopover>(find.byType(AppFlowyPopover).first)
            .onClose;
        block.menuController.close();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        lateClose?.call();
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  for (final type in FileUrlType.values) {
    _test(
        '$type: only cloud attachments receive the optional document credentials',
        (tester) async {
      final fixture = _Fixture(
        url: type == FileUrlType.local
            ? r'C:\synthetic\report.pdf'
            : 'https://files.example.invalid/report.pdf?signature=fixture',
        type: type,
        documentProfile: _profile('document-token'),
        workspaceProfile: _profile('workspace-token'),
        editable: false,
      );
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture);
        final document = fixture.json;
        expect(fixture.actions.calls, isEmpty);
        await _hover(tester, mouse, find.byKey(_chipKey));
        final anchor = tester.getRect(find.byKey(_shareKey));
        await tester.tap(find.byKey(_shareKey));
        await tester.pump();
        final call = fixture.actions.calls.single;
        expect(call.kind, 'share');
        expect(call.source.source, fixture.file.attributes[FileBlockKeys.url]);
        expect(call.source.name, 'report.pdf');
        expect(call.source.requireAuthentication, type == FileUrlType.cloud);
        expect(
          call.source.httpHeaders,
          type == FileUrlType.cloud
              ? {'Authorization': 'Bearer document-token'}
              : isEmpty,
        );
        expect(call.source.isImage, isFalse);
        expect(call.source.shareAsLink, isFalse);
        expect(call.origin, anchor);
        call.succeed();
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(fixture.json, document);
        expect(fixture.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  _test('workspace fallback updates credentials without rebuilding the block',
      (tester) async {
    final fixture = _Fixture(
      url: 'https://cloud.example.invalid/report.pdf',
      type: FileUrlType.cloud,
      withDocumentBloc: true,
      workspaceProfile: _profile('workspace-one'),
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture);
      await _hover(tester, mouse, find.byKey(_chipKey));
      final builds = fixture.builder.builds;
      final controls = tester.state(find.byType(MediaActionButtons));
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      final previous = fixture.actions.calls.single;
      expect(
        previous.source.httpHeaders,
        {'Authorization': 'Bearer workspace-one'},
      );

      fixture.workspaceBloc!.updateProfile(_profile('workspace-two'));
      await tester.pump();
      await tester.pump();
      expect(
        _buttons(tester).source.httpHeaders,
        {'Authorization': 'Bearer workspace-two'},
      );
      expect(_button(tester, _shareKey).onPressed, isNull);
      previous.succeed();
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byKey(_copiedKey), findsNothing);
      expect(
        previous.source.httpHeaders,
        {'Authorization': 'Bearer workspace-one'},
      );

      fixture.documentBloc!.updateProfile(_profile('document-now-present'));
      await tester.pump();
      await tester.pump();
      expect(
        _buttons(tester).source.httpHeaders,
        {'Authorization': 'Bearer document-now-present'},
      );
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      fixture.actions.calls.last.succeed();
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byKey(_copiedKey), findsOneWidget);
      fixture.documentBloc!.updateProfile(null);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_copiedKey), findsNothing);
      expect(
        _buttons(tester).source.httpHeaders,
        {'Authorization': 'Bearer workspace-two'},
      );
      expect(tester.state(find.byType(MediaActionButtons)), same(controls));
      expect(fixture.builder.builds, builds);
      expect(fixture.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test('a cloud attachment uses its workspace profile without a document bloc',
      (tester) async {
    final fixture = _Fixture(
      url: 'https://cloud.example.invalid/report.pdf',
      type: FileUrlType.cloud,
      workspaceProfile: _profile('workspace-only'),
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture);
      expect(fixture.documentBloc, isNull);
      expect(fixture.actions.calls, isEmpty);
      await _hover(tester, mouse, find.byKey(_chipKey));
      await tester.tap(find.byKey(_shareKey));
      await tester.pump();
      final source = fixture.actions.calls.single.source;
      expect(source.requireAuthentication, isTrue);
      expect(source.httpHeaders, {'Authorization': 'Bearer workspace-only'});
      expect(source.shareAsLink, isFalse);
      fixture.actions.calls.single.succeed();
      await tester.pump();
      expect(fixture.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  for (final (label, token) in <(String, String?)>[
    ('no provider', null),
    ('empty token', ''),
    ('invalid JSON', 'not-json'),
    ('invalid bearer', '{"access_token":"bad\\r\\nheader"}'),
  ]) {
    _test('cloud auth fails closed before IO: $label', (tester) async {
      var clipboardReads = 0;
      final fixture = _Fixture(
        url: 'https://cloud.example.invalid/report.pdf',
        type: FileUrlType.cloud,
        documentProfile: token == null ? null : UserProfilePB(token: token),
        mediaActions: MediaActionService(
          clipboard: () {
            clipboardReads++;
            return null;
          },
          temporaryDirectory: () => throw StateError('No file IO permitted'),
        ),
      );
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture);
        expect(_buttons(tester).source.requireAuthentication, isTrue);
        expect(_buttons(tester).source.httpHeaders, isEmpty);
        expect(clipboardReads, 0);
        await _hover(tester, mouse, find.byKey(_chipKey));
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        await tester.pump(_fade);
        expect(
          _button(tester, _copyKey).tooltip,
          LocaleKeys.message_copy_fail.tr(),
        );
        expect(find.byKey(_copiedKey), findsNothing);
        expect(clipboardReads, 0);
        await tester.tap(find.byKey(_shareKey));
        await tester.pump();
        await tester.pump(_fade);
        expect(
          _button(tester, _shareKey).tooltip,
          LocaleKeys.mediaActions_shareFailed.tr(),
        );
        expect(find.byKey(_copiedKey), findsNothing);
        expect(fixture.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  _test('an unavailable clipboard never produces a false Copied badge',
      (tester) async {
    var clipboardReads = 0;
    final fixture = _Fixture(
      mediaActions: MediaActionService(
        clipboard: () {
          clipboardReads++;
          return null;
        },
        temporaryDirectory: () => throw StateError('No file IO permitted'),
      ),
    );
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture);
      await _hover(tester, mouse, find.byKey(_chipKey));
      expect(clipboardReads, 0);
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      await tester.pump(_fade);
      expect(clipboardReads, 1);
      expect(find.byKey(_copiedKey), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(
        _button(tester, _copyKey).tooltip,
        LocaleKeys.message_copy_fail.tr(),
      );
      expect(fixture.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  for (final (name, url, image) in <(String?, String, bool)>[
    ('PHOTO.JFIF', r'C:\synthetic\PHOTO.JFIF', true),
    (
      'asset',
      'https://files.example.invalid/photo.PNG?download=1#preview',
      true
    ),
    ('report.pdf', 'https://files.example.invalid/photo.jpg', false),
    ('archive.bin', 'https://files.example.invalid/archive.bin', false),
    (null, r'C:\synthetic\a photo 100%.PNG', true),
    ('', 'https://files.example.invalid/report.pdf?download=1', false),
  ]) {
    _test(
        'file target preserves the name and classifies ${name ?? 'unnamed photo'}',
        (tester) async {
      final fixture = _Fixture(
        url: url,
        name: name,
        type:
            url.startsWith('https:') ? FileUrlType.network : FileUrlType.local,
        workspaceProfile: _profile('must-not-leak'),
      );
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture);
        await _hover(tester, mouse, find.byKey(_chipKey));
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        final source = fixture.actions.calls.single.source;
        expect(source.source, url);
        expect(
          source.name,
          name ?? '',
        ); // The service owns safe filename fallback.
        expect(source.isImage, image);
        expect(source.shareAsLink, isFalse);
        expect(source.httpHeaders, isEmpty);
        fixture.actions.calls.single.succeed();
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  for (final fail in [false, true]) {
    _test(
        'real source transactions reject late ${fail ? 'failure' : 'success'} and stale callbacks',
        (tester) async {
      final fixture = _Fixture();
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture);
        await _hover(tester, mouse, find.byKey(_chipKey));
        final controls = tester.state(find.byType(MediaActionButtons));
        final oldSource = _buttons(tester).source;
        final staleCopy = _button(tester, _copyKey).onPressed!;
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        await fixture.update({
          FileBlockKeys.url: 'https://files.example.invalid/replacement.pdf',
          FileBlockKeys.name: 'replacement.pdf',
          FileBlockKeys.urlType: FileUrlType.network.toIntValue(),
        });
        await tester.pump();
        await tester.pump();
        expect(_button(tester, _shareKey).onPressed, isNull);
        expect(fixture.actions.calls.single.source, oldSource);
        staleCopy();
        expect(fixture.actions.calls, hasLength(1));
        final error = _SensitiveError();
        if (fail) {
          fixture.actions.calls.single.fail(error);
        } else {
          fixture.actions.calls.single.succeed();
        }
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        expect(error.stringified, isFalse);
        expect(_button(tester, _copyKey).tooltip, 'Copy');
        staleCopy();
        expect(fixture.actions.calls, hasLength(1));
        await tester.tap(find.byKey(_shareKey));
        await tester.pump();
        expect(
          fixture.actions.calls.last.source.source,
          'https://files.example.invalid/replacement.pdf',
        );
        expect(fixture.actions.calls.last.source.name, 'replacement.pdf');
        fixture.actions.calls.last.succeed();
        await tester.pump();
        expect(tester.state(find.byType(MediaActionButtons)), same(controls));
        expect(fixture.writes, 1); // Only the explicit source transaction.
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  for (final key in [_copyKey, _shareKey]) {
    for (final fail in [false, true]) {
      _test(
          '$key ignores late ${fail ? 'failure' : 'success'} after block disposal',
          (tester) async {
        final fixture = _Fixture();
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: Offset.zero);
          await _mount(tester, fixture);
          await _hover(tester, mouse, find.byKey(_chipKey));
          final stalePress = _button(tester, key).onPressed!;
          await tester.tap(find.byKey(key));
          await tester.pump();
          final call = fixture.actions.calls.single;
          await tester.pumpWidget(const SizedBox.shrink());
          stalePress();
          expect(fixture.actions.calls, hasLength(1));
          if (fail) {
            call.fail(_SensitiveError());
          } else {
            call.succeed();
          }
          await tester.pump();
          expect(find.byKey(_copiedKey), findsNothing);
          expect(fixture.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await fixture.dispose(tester);
        }
      });
    }
  }

  _test('the original file menu remains mounted and pinned after pointer exit',
      (tester) async {
    final fixture = _Fixture(editable: false);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture);
      await _hover(tester, mouse, find.byKey(_chipKey));
      final block = _blockState(tester);
      final controls = tester.state(find.byType(MediaActionButtons));
      final document = fixture.json;
      await tester.tap(find.byType(FileMenuTrigger));
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byType(FileBlockMenu), findsOneWidget);
      expect(block.alwaysShowMenu, isTrue);
      expect(find.text(LocaleKeys.button_download.tr()), findsOneWidget);
      expect(find.text(LocaleKeys.editor_copy.tr()), findsOneWidget);
      expect(find.text(LocaleKeys.button_share.tr()), findsOneWidget);
      // Existing mutation entries are deliberately not changed or activated.
      expect(
        find.text(LocaleKeys.document_plugins_file_renameFile_title.tr()),
        findsOneWidget,
      );
      expect(find.text(LocaleKeys.button_delete.tr()), findsOneWidget);
      expect(find.text('Show preview'), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      await tester.pump(_fade);
      _expectReveal(tester, visible: true);
      expect(find.byType(FileMenuTrigger), findsOneWidget);
      expect(tester.state(find.byType(MediaActionButtons)), same(controls));
      block.menuController.close();
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byType(FileBlockMenu), findsNothing);
      expect(block.alwaysShowMenu, isFalse);
      _expectReveal(tester, visible: false);
      expect(fixture.json, document);
      expect(fixture.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test('keyboard focus reveals only the action subtree and supports Enter',
      (tester) async {
    final fixture = _Fixture();
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture);
      fixture.outsideFocus.requestFocus();
      await tester.pump();
      await tester.pump();
      _expectReveal(tester, visible: false);
      _button(tester, _copyKey).focusNode!.requestFocus();
      await tester.pump();
      await tester.pump();
      await tester.pump(_fade);
      _expectReveal(tester, visible: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fixture.actions.calls.single.kind, 'copy');
      expect(find.byKey(_copiedKey), findsNothing);
      _expectReveal(tester, visible: true);
      fixture.actions.calls.single.succeed();
      await tester.pump();
      await tester.pump();
      await tester.pump(_fade);
      expect(_button(tester, _copyKey).focusNode!.hasFocus, isTrue);
      expect(find.byKey(_copiedKey), findsOneWidget);
      fixture.outsideFocus.requestFocus();
      await tester.pump();
      await tester.pump();
      await tester.pump(_fade);
      _expectReveal(tester, visible: false);
      expect(fixture.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test('page edits and caret survive hovering a neighboring file',
      (tester) async {
    final fixture = _Fixture();
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture);
      final paragraph = fixture.editor.document.root.children[1];
      await fixture.editor.apply(
        fixture.editor.transaction
          ..insertText(paragraph, 3, ' unfinished draft'),
      );
      final selection = Selection.collapsed(Position(path: [1], offset: 12));
      fixture.editor.selection = selection;
      await tester.pump();
      final document = fixture.json;
      final writes = fixture.writes;
      await _hover(tester, mouse, find.byKey(_chipKey));
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      await tester.pump(_fade);
      expect(fixture.editor.selection, selection);
      expect(fixture.json, document);
      expect(fixture.writes, writes);
      expect(fixture.actions.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test('empty upload placeholders never expose file actions', (tester) async {
    final fixture = _Fixture(url: '', name: null);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _mount(tester, fixture);
      await _hover(tester, mouse, find.byKey(_chipKey));
      expect(find.byType(MediaActionButtons), findsNothing);
      expect(find.byType(MediaActionReveal), findsNothing);
      expect(find.byType(FileMenuTrigger), findsNothing);
      expect(fixture.actions.calls, isEmpty);
      expect(fixture.writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  for (final extension in [
    'pdf',
    'txt',
    'py',
    'zip',
    'docx',
    'csv',
    'md',
    'html',
    'ipynb',
  ]) {
    _test(
        '$extension: deferred preview exposes one bar without replacing its renderer or menu',
        (tester) async {
      final fixture = _Fixture(
        url: '${temporary.path}/unopened.$extension',
        name: 'unopened.$extension',
        preview: true,
      );
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: Offset.zero);
        await _mount(tester, fixture, mode: 'paper', deferPreview: true);
        // Exercise the real block's chrome, but never start a native PDF,
        // browser, Office connection, code runner or archive materialization.
        expect(find.byType(MaterializedFileBuilder), findsNothing);
        final frame =
            tester.widget<ResizableMedia>(find.byType(ResizableMedia));
        final body = frame.child;
        final loader = body is MaterializedFileBuilder
            ? body
            : (body as Stack)
                .children
                .whereType<MaterializedFileBuilder>()
                .single;
        final context = tester.element(find.byType(FileBlockComponent));
        final pagePosition = Scrollable.of(context).position;
        expect(pagePosition.isScrollingNotifier.value, isTrue);
        final renderer = loader.builder(
          context,
          AsyncSnapshot.withData(
            ConnectionState.done,
            File('${temporary.path}/unopened.$extension'),
          ),
        );
        if (extension == 'pdf') {
          final preview = renderer as FilePreview;
          expect(preview.toolbarTrailing, isNull);
          expect(preview.pdfMenuBuilder, isNotNull);
          expect(
            preview.previewScrollController,
            same(_blockState(tester).previewScrollController),
          );
          final menu = preview.pdfMenuBuilder!(context, () {}) as FileBlockMenu;
          expect(menu.showDownload, isFalse);
          expect(menu.node, same(fixture.file));
          expect(find.byType(PdfEmbedScrollGuard), findsOneWidget);
          var wheels = 0;
          final scroll = _blockState(tester).previewScrollController;
          void onWheel(PointerSignalEvent event) => wheels++;
          scroll.attach(onWheel);
          final guard = tester.widget<PdfEmbedScrollGuard>(
            find.byType(PdfEmbedScrollGuard),
          );
          guard.onPointerSignal(const PointerScrollEvent());
          expect(wheels, 1);
          scroll.detach(onWheel);
        } else if (extension == 'zip') {
          expect((renderer as ArchiveExplorer).toolbarTrailing, isNotNull);
        } else if (isOfficeFile('file.$extension')) {
          expect(renderer, isA<OfficeDocumentView>());
          expect(frame.footer, isNotNull);
        } else {
          final preview = renderer as FilePreview;
          expect(preview.kind, filePreviewKindFromName('file.$extension'));
          expect(preview.toolbarTrailing, isNotNull);
        }
        final document = fixture.json;
        final frameState = tester.state(find.byType(ResizableMedia));
        final bounds = tester.getRect(find.byKey(_frameKey));
        expect(find.byKey(_previewActionsKey), findsOneWidget);
        expect(find.byType(MediaActionButtons), findsOneWidget);
        _expectReveal(tester, visible: false);
        await _hover(tester, mouse, find.byKey(_frameKey));
        expect(_buttons(tester).decorated, isTrue);
        final actions = tester.getRect(find.byType(MediaActionButtons));
        expect(actions.right, lessThanOrEqualTo(bounds.right - 42));
        expect(actions.bottom, lessThanOrEqualTo(bounds.bottom - 14));
        expect(find.byKey(_copyKey).hitTestable(), findsOneWidget);
        // Touch taps start a Scrollable hold and clear the synthetic busy
        // flag used by this fixture. Keep the hover mouse for both actions.
        final copyPoint = tester.getCenter(find.byKey(_copyKey));
        await mouse.moveTo(copyPoint);
        await mouse.down(copyPoint);
        await mouse.up();
        await tester.pump();
        expect(fixture.actions.calls.single.source.source, loader.source);
        expect(fixture.actions.calls.single.source.name, loader.name);
        expect(find.byKey(_copiedKey), findsNothing);
        fixture.actions.calls.single.succeed();
        await tester.pump();
        await tester.pump(_fade);
        _expectBadgeUnclipped(tester);
        final sharePoint = tester.getCenter(find.byKey(_shareKey));
        await mouse.moveTo(sharePoint);
        await mouse.down(sharePoint);
        await mouse.up();
        await tester.pump();
        fixture.actions.calls.last.succeed();
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copiedKey), findsNothing);
        await mouse.moveTo(Offset.zero);
        await tester.pump();
        await tester.pump(_fade);
        expect(tester.state(find.byType(ResizableMedia)), same(frameState));
        expect(
          tester.widget<ResizableMedia>(find.byType(ResizableMedia)).child,
          same(body),
        );
        expect(pagePosition.isScrollingNotifier.value, isTrue);
        expect(fixture.file.attributes[FileBlockKeys.displayMode], 'preview');
        expect(find.byType(MaterializedFileBuilder), findsNothing);
        expect(fixture.json, document);
        expect(fixture.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

UserProfilePB _profile(String token) => UserProfilePB(
      id: Int64(7),
      name: 'Synthetic user',
      token: jsonEncode({'access_token': token}),
    );

class _DocumentBloc extends Cubit<DocumentState> implements DocumentBloc {
  _DocumentBloc(UserProfilePB? profile)
      : super(DocumentState.initial().copyWith(userProfilePB: profile));

  @override
  String get documentId => 'file-media-actions-fixture';

  void updateProfile(UserProfilePB? profile) =>
      emit(state.copyWith(userProfilePB: profile));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorkspaceBloc extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _WorkspaceBloc(UserProfilePB profile)
      : super(UserWorkspaceState.initial(profile));

  void updateProfile(UserProfilePB profile) =>
      emit(state.copyWith(userProfile: profile));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The unchanged dropdown only reads a date preference. Do not instantiate the
// real appearance cubit: its constructor reads application settings from GetIt.
class _AppearanceCubit extends Fake implements AppearanceSettingsCubit {
  @override
  AppearanceSettingsState get state => _AppearanceState();
}

class _AppearanceState extends Fake implements AppearanceSettingsState {
  @override
  UserDateFormatPB get dateFormat => UserDateFormatPB.values.first;
}

class _ServiceFileBuilder extends FileBlockComponentBuilder {
  _ServiceFileBuilder(this.actions);

  final MediaActionService actions;
  int builds = 0;

  @override
  BlockComponentWidget build(BlockComponentContext context) {
    builds++;
    return FileBlockComponent(
      key: context.node.key,
      node: context.node,
      configuration: configuration,
      mediaActions: actions,
    );
  }
}

class _Fixture {
  _Fixture({
    String url = r'C:\synthetic\report.pdf',
    String? name = 'report.pdf',
    FileUrlType type = FileUrlType.local,
    bool preview = false,
    bool editable = true,
    bool withDocumentBloc = false,
    UserProfilePB? documentProfile,
    UserProfilePB? workspaceProfile,
    MediaActionService? mediaActions,
  }) {
    editor = EditorState(
      document: Document(
        root: pageNode(
          children: [
            Node(
              type: FileBlockKeys.type,
              attributes: {
                FileBlockKeys.url: url,
                FileBlockKeys.name: name,
                FileBlockKeys.urlType: type.toIntValue(),
                FileBlockKeys.displayMode: preview ? 'preview' : 'file',
                FileBlockKeys.width: 520.0,
                FileBlockKeys.height: 320.0,
              },
            ),
            paragraphNode(text: 'The surrounding page keeps its draft.'),
          ],
        ),
      ),
    )
      ..disableSealTimer = true
      ..editable = editable;
    builder = _ServiceFileBuilder(mediaActions ?? actions);
    documentBloc = withDocumentBloc || documentProfile != null
        ? _DocumentBloc(documentProfile)
        : null;
    workspaceBloc =
        workspaceProfile == null ? null : _WorkspaceBloc(workspaceProfile);
    _subscription = editor.transactionStream.listen(transactions.add);
  }

  late final EditorState editor;
  late final _ServiceFileBuilder builder;
  late final _DocumentBloc? documentBloc;
  late final _WorkspaceBloc? workspaceBloc;
  late final StreamSubscription<EditorTransactionValue> _subscription;
  final outsideFocus = FocusNode();
  final actions = _RecordingActions();
  final transactions = <EditorTransactionValue>[];

  Node get file => editor.document.root.children.first;
  String get json => jsonEncode(editor.document.toJson());
  int get writes =>
      transactions.where((value) => value.$1 == TransactionTime.after).length;

  Future<void> update(Map<String, dynamic> attributes) =>
      editor.apply(editor.transaction..updateNode(file, attributes));

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(_subscription.cancel);
    if (documentBloc != null) await tester.runAsync(documentBloc!.close);
    if (workspaceBloc != null) await tester.runAsync(workspaceBloc!.close);
    editor.dispose();
    outsideFocus.dispose();
    await tester.pump();
  }
}

/// Captures immutable targets; no platform clipboard, share sheet or HTTP is
/// reachable. Tests explicitly decide when each operation completes.
class _RecordingActions extends Fake implements MediaActionService {
  final calls = <_Call>[];

  @override
  Future<void> copy(MediaActionSource source) => _begin('copy', source, null);

  @override
  Future<void> share(MediaActionSource source, {Rect? sharePositionOrigin}) =>
      _begin('share', source, sharePositionOrigin);

  Future<void> _begin(String kind, MediaActionSource source, Rect? origin) {
    final call = _Call(kind, source, origin);
    calls.add(call);
    return call.completion.future;
  }
}

class _Call {
  _Call(this.kind, this.source, this.origin);

  final String kind;
  final MediaActionSource source;
  final Rect? origin;
  final completion = Completer<void>();

  void succeed() => completion.complete();
  void fail(Object error) =>
      completion.completeError(error, StackTrace.current);
}

class _SensitiveError implements Exception {
  bool stringified = false;

  @override
  String toString() {
    stringified = true;
    return 'private-path?token=synthetic-do-not-display';
  }
}

FileBlockComponentState _blockState(WidgetTester tester) =>
    tester.state<FileBlockComponentState>(find.byType(FileBlockComponent));

MediaActionButtons _buttons(WidgetTester tester) =>
    tester.widget<MediaActionButtons>(find.byType(MediaActionButtons));

IconButton _button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key));

void _expectReveal(WidgetTester tester, {required bool visible}) {
  final reveal = _actionReveal();
  expect(tester.widget<AnimatedOpacity>(reveal).opacity, visible ? 1 : 0);
  expect(
    tester
        .widget<IgnorePointer>(
          find.ancestor(of: reveal, matching: find.byType(IgnorePointer)).first,
        )
        .ignoring,
    !visible,
  );
}

double _paintedOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .descendant(
            of: _actionReveal(),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

// Preview controls share the frame controller; compact chips retain their
// original MediaActionReveal API and animation contract.
Finder _actionReveal() {
  final preview = find.ancestor(
    of: find.byType(MediaActionButtons),
    matching: find.byType(PreviewToolbar),
  );
  return preview.evaluate().isEmpty
      ? find.byKey(_revealKey)
      : find
          .descendant(of: preview.first, matching: find.byType(AnimatedOpacity))
          .first;
}

bool _focusedInside(Finder control) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final target = control.evaluate().single;
  var found = identical(context, target);
  context.visitAncestorElements((element) {
    if (identical(element, target)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

void _expectBadgeUnclipped(WidgetTester tester) {
  final badge = find.byKey(_copiedKey);
  expect(badge, findsOneWidget);
  final bounds = tester.getRect(badge).deflate(0.01);
  for (RenderObject child = tester.renderObject(badge);
      child.parent != null;
      child = child.parent!) {
    final parent = child.parent!;
    final clip = parent.describeApproximatePaintClip(child);
    if (clip == null) continue;
    final globalClip =
        MatrixUtils.transformRect(parent.getTransformTo(null), clip)
            .inflate(0.1);
    expect(
      globalClip.contains(bounds.topLeft),
      isTrue,
      reason: '${parent.runtimeType} clips the top of Copied',
    );
    expect(
      globalClip.contains(bounds.bottomRight),
      isTrue,
      reason: '${parent.runtimeType} clips the bottom of Copied',
    );
  }
}

Future<void> _hover(WidgetTester tester, TestGesture mouse, Finder host) async {
  final bounds = tester.getRect(host);
  await mouse.moveTo(bounds.topLeft + const Offset(20, 20));
  await tester.pump();
  await tester.pump(_fade);
}

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; !ready() && attempt < 100; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(ready(), isTrue, reason: 'The isolated fixture must finish loading');
}

ThemeData _theme(String mode) => DesktopAppearance().getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  String mode = 'light',
  double width = 720,
  double textScale = 1,
  bool deferPreview = false,
}) async {
  final theme = _theme(mode).copyWith(platform: TargetPlatform.windows);
  final defaults = AppFlowyDefaultTheme();
  final appTheme = PremiumTheme.appFlowyTheme(
    base: mode == 'dark' ? defaults.dark() : defaults.light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: theme.brightness,
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppearanceSettingsCubit>.value(value: _AppearanceCubit()),
        if (fixture.documentBloc != null)
          BlocProvider<DocumentBloc>.value(value: fixture.documentBloc!),
        if (fixture.workspaceBloc != null)
          BlocProvider<UserWorkspaceBloc>.value(value: fixture.workspaceBloc!),
      ],
      child: EasyLocalization(
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
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: 560,
                  child: Column(
                    children: [
                      TextButton(
                        focusNode: fixture.outsideFocus,
                        onPressed: () {},
                        child: const Text('Outside the file'),
                      ),
                      Expanded(
                        child: PageEmbedLoadScope(
                          child: PageEmbedPreviewScope(
                            enabled: deferPreview,
                            child: AppFlowyEditor(
                              editorState: fixture.editor,
                              editable: fixture.editor.editable,
                              disableAutoScroll: true,
                              disableKeyboardService: true,
                              editorStyle: const EditorStyle.desktop(
                                padding: EdgeInsets.fromLTRB(24, 40, 24, 80),
                              ),
                              blockComponentBuilders: {
                                ...standardBlockComponentBuilderMap,
                                FileBlockKeys.type: fixture.builder,
                              },
                              contextMenuItems: const [],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _waitFor(
    tester,
    () => find.byType(FileBlockComponent).evaluate().isNotEmpty,
  );
  if (deferPreview) {
    // Hold the existing page mount gate before its 80ms idle timer can admit
    // the native body. The chrome is outside that gate and remains interactive.
    Scrollable.of(tester.element(find.byType(FileBlockComponent)))
        .position
        .isScrollingNotifier
        .value = true;
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 180));
}
