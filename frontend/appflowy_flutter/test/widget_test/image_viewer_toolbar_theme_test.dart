import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/widgets/media_file_type_ext.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_toolbar.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/interactive_image_viewer.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');
const _copied = ValueKey('media-copied');
const _close = ValueKey('photo-fullscreen-close');
const _scroll = ValueKey('photo-toolbar-scroll');

void main() {
  fileControlTestSetup();

  for (final mode in fileControlAppearances) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          '$mode/$scale: live photo controls are themed, persistent and below title',
          (tester) async {
        final semantics = tester.ensureSemantics();
        final photos = _Photos();
        final actions = _Actions();
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: const Offset(-20, -20));
          await mountFileControls(
            tester,
            InteractiveImageViewer(imageProvider: photos, actions: actions),
            mode: mode,
            textScale: scale,
            width: 320,
            height: 260,
          );
          final renderer = find.byType(InteractiveViewer);
          final state = tester.state(renderer);
          final matrix = tester
              .widget<InteractiveViewer>(renderer)
              .transformationController;
          final tools = tester.widget<InteractiveImageToolbar>(
              find.byType(InteractiveImageToolbar));
          expect(tools.imageName, 'first original.png');
          expect(_buttons(tester).onDarkSurface, isFalse);
          expect(_buttons(tester).decorated, isFalse);
          final context = tester.element(find.byType(InteractiveImageToolbar));
          expect(PaperTheme.isEnabled(context), mode == 'paper');
          final chrome = tester.widget<DocumentViewportBar>(
              find.byKey(const ValueKey('photo-fullscreen-chrome')));
          expect(chrome.background, DocumentViewportStyle.of(context).canvas);
          expect(
              tester.getRect(find.byKey(_scroll)).top,
              greaterThanOrEqualTo(tester
                  .getRect(find.byKey(const ValueKey('photo-fullscreen-title')))
                  .bottom));
          expect(tester.getRect(find.byKey(_scroll)).bottom,
              lessThanOrEqualTo(tester.getRect(renderer).top));
          expect(
              find.ancestor(
                  of: find.byKey(_close),
                  matching: find.byType(SingleChildScrollView)),
              findsNothing);
          expect(find.byKey(_close).hitTestable(), findsOneWidget);
          await tester.pump(const Duration(seconds: 5));
          for (final key in [_copy, _share]) {
            expect(find.byKey(key).hitTestable(), findsOneWidget);
            _expectSemantics(tester, key, key == _copy ? 'Copy' : 'Share');
            final style = _button(tester, key).style!;
            expect(style.animationDuration,
                WorkspaceChrome.controlStyle(context).animationDuration);
            expect(style.shape!.resolve({}),
                WorkspaceChrome.controlStyle(context).shape!.resolve({}));
          }
          await mouse.moveTo(tester.getCenter(find.byKey(_copy)));
          await settleFileControls(tester);
          expect(_material(tester, _copy).color,
              WorkspaceChrome.hoverColor(context));
          await mouse.moveTo(const Offset(-20, -20));
          await settleFileControls(tester);
          expect(find.byKey(_copy).hitTestable(), findsOneWidget);
          await _tabTo(tester, _button(tester, _copy).focusNode!);
          _expectSemantics(tester, _copy, 'Copy');
          final shape = _material(tester, _copy).shape! as OutlinedBorder;
          expect(
              shape.side,
              WorkspaceChrome.controlStyle(context)
                  .side!
                  .resolve({WidgetState.focused}));
          expect(tester.state(renderer), same(state));
          expect(
              tester
                  .widget<InteractiveViewer>(renderer)
                  .transformationController,
              same(matrix));
          expect(actions.calls, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await mouse.removePointer();
          await _dispose(tester, actions);
        }
      });
    }

    testWidgets(
        '$mode: pending, copied, failed and retry retain native action state',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _Actions();
      final photos = _Photos();
      try {
        await mountFileControls(
          tester,
          InteractiveImageViewer(imageProvider: photos, actions: actions),
          mode: mode,
        );
        final state = tester.state(find.byType(MediaActionButtons));
        await _tabTo(tester, _button(tester, _copy).focusNode!);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter,
            physicalKey: PhysicalKeyboardKey.enter);
        await settleFileControls(tester);
        final copy = actions.calls.single;
        expect(copy.source.source, photos.files.first.url);
        expect(copy.source.name, photos.files.first.name);
        expect(copy.source.isImage, isTrue);
        expect(copy.source.httpHeaders, isEmpty);
        expect(_button(tester, _copy).onPressed, isNull);
        expect(_button(tester, _share).onPressed, isNull);
        _expectSemantics(tester, _copy, 'Copy', enabled: false);
        await tester.pump(const Duration(seconds: 5));
        copy.done.complete();
        await settleFileControls(tester);
        _expectSemantics(tester, _copy, 'Copied', live: true);
        expect(_button(tester, _copy).focusNode!.hasFocus, isTrue);
        final badge = tester.getRect(find.byKey(_copied));
        expect(badge.bottom, lessThan(tester.getRect(find.byKey(_copy)).top));
        expect(tester.getRect(find.byKey(_scroll)).contains(badge.topLeft),
            isTrue);
        expect(tester.getRect(find.byKey(_scroll)).contains(badge.bottomRight),
            isTrue);
        await tester.pump(const Duration(milliseconds: 1600));
        await settleFileControls(tester);
        expect(find.byKey(_copied), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter,
            physicalKey: PhysicalKeyboardKey.enter);
        await tester.pump();
        actions.calls.last.done
            .completeError(StateError('private-fixture-error'));
        await settleFileControls(tester);
        _expectSemantics(tester, _copy, LocaleKeys.message_copy_fail.tr(),
            live: true);
        await _tabTo(tester, _button(tester, _share).focusNode!);
        final anchor = tester.getRect(find.byKey(_share));
        await tester.sendKeyEvent(LogicalKeyboardKey.space,
            physicalKey: PhysicalKeyboardKey.space);
        await tester.pump();
        expect(actions.calls.last.origin, anchor);
        actions.calls.last.done
            .completeError(StateError('private-fixture-error'));
        await settleFileControls(tester);
        _expectSemantics(
            tester, _share, LocaleKeys.mediaActions_shareFailed.tr(),
            live: true);
        await tester.sendKeyEvent(LogicalKeyboardKey.space,
            physicalKey: PhysicalKeyboardKey.space);
        await tester.pump();
        actions.calls.last.done.complete();
        await settleFileControls(tester);
        _expectSemantics(tester, _share, 'Share');
        expect(tester.state(find.byType(MediaActionButtons)), same(state));
        expect(actions.calls, hasLength(4));
        expect(find.textContaining('private-fixture-error'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _dispose(tester, actions);
      }
    });
  }

  for (final reduced in [false, true]) {
    testWidgets(
        'photo Fit retains its controller and honors reduced motion=$reduced',
        (tester) async {
      final actions = _Actions();
      try {
        await mountFileControls(
          tester,
          InteractiveImageViewer(imageProvider: _Photos(), actions: actions),
          mode: 'paper',
          reduced: reduced,
        );
        final renderer = find.byType(InteractiveViewer);
        final controller = tester
            .widget<InteractiveViewer>(renderer)
            .transformationController!;
        final original = Matrix4.identity()
          ..translate(90.0, 60.0)
          ..scale(2.0);
        controller.value = original;
        await tester.pump();
        final fit = find.byTooltip('Fit to view');
        await tester.ensureVisible(fit);
        await tester.tap(fit);
        await tester.pump();
        expect(
            tester.widget<InteractiveViewer>(renderer).transformationController,
            same(controller));
        if (reduced) {
          expect(controller.value.isIdentity(), isTrue);
        } else {
          await tester.pump(const Duration(milliseconds: 100));
          expect(
              controller.value.getMaxScaleOnAxis(), inExclusiveRange(1.0, 2.0));
          await tester.pump(const Duration(milliseconds: 101));
          expect(controller.value.isIdentity(), isTrue);
        }
        controller.value = original;
        await tester.pump();
        await tester.tap(fit);
        await tester.pump(const Duration(milliseconds: 40));
        // Disposal during the second fit must not create a new lazy ticker.
        await _dispose(tester, actions);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, actions);
      }
    });
  }

  for (final fail in [false, true]) {
    testWidgets(
        'photo navigation retains controls and rejects stale ${fail ? 'failure' : 'success'}',
        (tester) async {
      final actions = _Actions();
      final photos = _Photos();
      try {
        await mountFileControls(
          tester,
          InteractiveImageViewer(imageProvider: photos, actions: actions),
          mode: 'paper',
        );
        final state = tester.state(find.byType(MediaActionButtons));
        final stale = _button(tester, _share).onPressed!;
        await tester.tap(find.byKey(_copy));
        await tester.pump();
        final pending = actions.calls.single;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight,
            physicalKey: PhysicalKeyboardKey.arrowRight);
        await settleFileControls(tester);
        expect(find.byKey(const ValueKey('photo-second')), findsOneWidget);
        expect(_buttons(tester).source.source, photos.files.last.url);
        expect(_button(tester, _share).onPressed, isNull);
        stale();
        expect(actions.calls, hasLength(1));
        if (fail) {
          pending.done.completeError(StateError('obsolete'));
        } else {
          pending.done.complete();
        }
        await settleFileControls(tester);
        expect(find.byKey(_copied), findsNothing);
        expect(_button(tester, _copy).tooltip, 'Copy');
        expect(tester.state(find.byType(MediaActionButtons)), same(state));
        await tester.tap(find.byKey(_share));
        await tester.pump();
        expect(actions.calls.last.source.name, photos.files.last.name);
        actions.calls.last.done.complete();
        await settleFileControls(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft,
            physicalKey: PhysicalKeyboardKey.arrowLeft);
        await settleFileControls(tester);
        stale();
        expect(actions.calls, hasLength(2));
        expect(_buttons(tester).source.source, photos.files.first.url);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, actions);
      }
    });
  }
}

// Decode boundary only: real file filtering, names, source selection, toolbar,
// focus, transformations and OCR region remain the production implementations.
class _Photos extends MediaFileImageProvider {
  _Photos()
      : super(initialFileId: 'first', files: [
          for (final id in ['first', 'second'])
            MediaFilePB(
              id: id,
              name: '$id original.png',
              url: 'synthetic/$id.png',
              fileType: MediaFileTypePB.Image,
              uploadType: FileUploadTypePB.LocalFile,
            ),
        ]);

  @override
  Widget renderImage(BuildContext context, int index,
          [UserProfilePB? userProfile]) =>
      ColoredBox(
          key: ValueKey('photo-${files[index].id}'),
          color: const Color(0xFFB77950));
}

class _Actions extends MediaActionService {
  final calls = <_Call>[];
  @override
  Future<void> copy(MediaActionSource source) => _start(source, null);
  @override
  Future<void> share(MediaActionSource source, {Rect? sharePositionOrigin}) =>
      _start(source, sharePositionOrigin);
  Future<void> _start(MediaActionSource source, Rect? origin) {
    final call = _Call(source, origin);
    calls.add(call);
    return call.done.future;
  }
}

class _Call {
  _Call(this.source, this.origin);
  final MediaActionSource source;
  final Rect? origin;
  final done = Completer<void>();
}

MediaActionButtons _buttons(WidgetTester tester) =>
    tester.widget(find.byType(MediaActionButtons));
IconButton _button(WidgetTester tester, Key key) =>
    tester.widget(find.byKey(key));
Material _material(WidgetTester tester, Key key) => tester.widget(
      find.descendant(of: find.byKey(key), matching: find.byType(Material)),
    );

void _expectSemantics(WidgetTester tester, Key key, String label,
    {bool enabled = true, bool live = false}) {
  final node = tester.getSemantics(find.byKey(key));
  expect(node.attached, isTrue);
  expect(node.label, label);
  expect(node.tooltip, isEmpty);
  final data = node.getSemanticsData();
  expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.isEnabled), enabled);
  expect(data.hasFlag(ui.SemanticsFlag.isLiveRegion), live);
  expect(data.hasAction(ui.SemanticsAction.tap), enabled);
}

Future<void> _tabTo(WidgetTester tester, FocusNode node) async {
  for (var i = 0; i < 30 && !node.hasFocus; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab,
        physicalKey: PhysicalKeyboardKey.tab);
    await settleFileControls(tester);
  }
  expect(node.hasFocus, isTrue);
}

Future<void> _dispose(WidgetTester tester, _Actions actions) async {
  await unmountFileControls(tester);
  for (final call in actions.calls) {
    if (!call.done.isCompleted) call.done.complete();
  }
  await tester.pump();
  expect(tester.binding.transientCallbackCount, 0);
}
