import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

const _copy = ValueKey('media-copy');
const _share = ValueKey('media-share');
const _controls = ValueKey('archive-controls');
const _header = ValueKey('workspace-file-identity-row');
const _toolbarScroll = ValueKey('workspace-file-toolbar-scroll');
const _name = 'Original archive # 100%.zip';

void main() {
  fileControlTestSetup();
  late Directory temporary;
  late File archive;
  setUp(() async {
    temporary =
        await Directory.systemTemp.createTemp('archive-control-regression-');
    archive = await File('${temporary.path}/cache.bin')
        .writeAsBytes(ZipEncoder().encode(Archive())!);
  });
  tearDown(() async => temporary.delete(recursive: true));

  for (final mode in fileControlAppearances) {
    for (final expanded in [false, true]) {
      for (final width in [320.0, 1000.0]) {
        testWidgets(
            '$mode/$width/expanded=$expanded: exactly one Copy/Share group with archive options',
            (tester) async {
          final backend = FileControlBackend(
            fileControlView('archive', _name, archive.path),
            archive,
          );
          try {
            await _mountArchive(
              tester,
              backend,
              mode: mode,
              width: width,
              expanded: expanded,
              accessible: true,
            );
            expect(find.byKey(_copy), findsOneWidget);
            expect(find.byKey(_share), findsOneWidget);
            expect(find.byKey(_controls), findsOneWidget);
            expect(
              find.byKey(const ValueKey('archive-fullscreen-media-actions')),
              findsNothing,
            );
            expect(
              find.descendant(
                of: find.byKey(_controls),
                matching: find.byKey(_copy),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: find.byKey(_controls),
                matching: find.byTooltip('Reload archive'),
              ),
              findsOneWidget,
            );
            expect(find.byKey(_copy).hitTestable(), findsOneWidget);
            final before = tester.state(find.byType(ArchiveExplorer));
            final actions = tester.state(find.byType(MediaActionButtons));
            final target = tester
                .widget<MediaActionButtons>(find.byType(MediaActionButtons))
                .source;
            expect(target.source, archive.path);
            expect(target.name, _name);
            expect(
              tester
                  .widget<MediaActionButtons>(find.byType(MediaActionButtons))
                  .decorated,
              isFalse,
            );
            for (final button in tester.widgetList<ArchivePillButton>(
              find.byType(ArchivePillButton),
            )) {
              final finder = find.byWidget(button);
              expect(
                find.descendant(
                  of: finder,
                  matching: find.byType(WorkspaceControlButton),
                ),
                findsOneWidget,
              );
              final rect = tester.getRect(finder);
              final bounds = tester.getRect(find.byKey(_controls));
              expect(rect.left, greaterThanOrEqualTo(bounds.left));
              expect(rect.right, lessThanOrEqualTo(bounds.right + 0.01));
            }
            await clickFileControl(tester, find.byKey(_copy));
            expect(backend.media.copies, [target]);
            await clickFileControl(tester, find.byKey(_share));
            expect(backend.media.shares, [target]);
            expect(
              tester.state(find.byType(MediaActionButtons)),
              same(actions),
            );
            expect(tester.state(find.byType(ArchiveExplorer)), same(before));
            expect(tester.takeException(), isNull);
          } finally {
            await unmountFileControls(tester);
          }
        });
      }
    }

    for (final reduced in [false, true]) {
      testWidgets(
          '$mode/reduced=$reduced: archive menus, search and keyboard keep one retained toolbar',
          (tester) async {
        final backend = FileControlBackend(
          fileControlView('hover-archive', _name, archive.path),
          archive,
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        final semantics = tester.ensureSemantics();
        try {
          await mouse.addPointer(location: const Offset(1080, 880));
          await _mountArchive(
            tester,
            backend,
            mode: mode,
            width: 760,
            reduced: reduced,
          );
          final explorer = tester.state(find.byType(ArchiveExplorer));
          final actions = tester.state(find.byType(MediaActionButtons));
          final controlsElement = tester.element(find.byKey(_controls));
          final scroll = tester
              .widget<SingleChildScrollView>(find.byKey(_toolbarScroll))
              .controller!;
          final scrollPosition = scroll.position;
          void expectRetainedToolbar() {
            expect(tester.state(find.byType(ArchiveExplorer)), same(explorer));
            expect(
              tester.state(find.byType(MediaActionButtons)),
              same(actions),
            );
            expect(
              tester.element(find.byKey(_controls)),
              same(controlsElement),
            );
            expect(
              tester
                  .widget<SingleChildScrollView>(find.byKey(_toolbarScroll))
                  .controller,
              same(scroll),
            );
            expect(scroll.position, same(scrollPosition));
            expect(backend.loads, 1);
          }

          // The existing standalone archive root requests focus for Ctrl+F.
          // Blur it before checking the persistent standalone options.
          FocusManager.instance.primaryFocus?.unfocus();
          await settleFileControls(tester);
          expect(find.byKey(_copy).hitTestable(), findsOneWidget);
          final cardSize = find.byTooltip('Card size');
          await _revealArchiveControl(tester, mouse, cardSize);
          await clickFileControl(tester, cardSize);
          expect(find.byType(AppMenuRow), findsWidgets);
          await mouse.moveTo(const Offset(1080, 880));
          await settleFileControls(tester);
          expectFileControlPainted(tester, find.byKey(_copy));
          expectRetainedToolbar();
          // Dismiss, do not change the shared card-size preference in a test.
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settleFileControls(tester);
          final archiveSearch =
              find.byTooltip('Search this archive  ·  Ctrl+F');
          await _revealArchiveControl(tester, mouse, archiveSearch);
          await clickFileControl(tester, archiveSearch);
          final search = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.hintText == 'Filename or path · all folders',
          );
          final controller = tester.widget<TextField>(search).controller!;
          await tester.enterText(search, 'retained query');
          await settleFileControls(tester);
          await mouse.moveTo(const Offset(1080, 880));
          await settleFileControls(tester);
          expect(controller.text, 'retained query');
          expectFileControlPainted(tester, find.byKey(_copy));
          expectRetainedToolbar();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await settleFileControls(tester);
          FocusManager.instance.primaryFocus?.unfocus();
          await settleFileControls(tester);
          expect(find.byKey(_copy).hitTestable(), findsOneWidget);

          final focus = tester.widget<IconButton>(find.byKey(_copy)).focusNode!;
          for (var i = 0; i < 30 && !focus.hasFocus; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await settleFileControls(tester);
          }
          expect(focus.hasFocus, isTrue);
          // Native focus traversal must reveal the scrolled-away action; do
          // not manually scroll or request focus on this keyboard-only path.
          _archiveControlPoint(tester, find.byKey(_copy));
          expect(find.byKey(_copy).hitTestable(), findsOneWidget);
          expectFileControlPainted(tester, find.byKey(_copy));
          expect(find.semantics.byLabel('Copy'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await settleFileControls(tester);
          expect(backend.media.copies, hasLength(1));
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await settleFileControls(tester);
          expect(search, findsOneWidget);
          expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
          expect(tester.widget<TextField>(search).controller, same(controller));
          if (reduced) {
            for (final toolbar in find
                .ancestor(
                  of: find.byKey(_copy),
                  matching: find.byType(PreviewToolbar),
                )
                .evaluate()) {
              final fade = find
                  .descendant(
                    of: find.byElementPredicate(
                      (element) => identical(element, toolbar),
                    ),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first;
              expect(
                tester.widget<AnimatedOpacity>(fade).duration,
                Duration.zero,
              );
            }
          }
          expectRetainedToolbar();
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await mouse.removePointer();
          await unmountFileControls(tester);
        }
      });
    }
  }
  testWidgets(
      'archive reload retains a pending Copy across toolbar withdrawal and republication',
      (tester) async {
    final backend = FileControlBackend(
      fileControlView('reload', _name, archive.path),
      archive,
    );
    final pending = Completer<void>();
    backend.media.pending = pending.future;
    try {
      await _mountArchive(
        tester,
        backend,
        mode: 'paper',
        width: 760,
        expanded: true,
        accessible: true,
      );
      final actionState = tester.state(find.byType(MediaActionButtons));
      await clickFileControl(tester, find.byKey(_copy));
      await clickFileControl(tester, find.byTooltip('Reload archive'));
      for (var i = 0; i < 80 && find.byKey(_controls).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await settleFileControls(tester);
      }
      expect(find.byKey(_controls), findsOneWidget);
      expect(find.byKey(_copy), findsOneWidget);
      expect(tester.state(find.byType(MediaActionButtons)), same(actionState));
      expect(tester.widget<IconButton>(find.byKey(_share)).onPressed, isNull);
      expect(backend.media.copies, hasLength(1));
      pending.complete();
      await settleFileControls(tester);
      expect(
        tester.widget<IconButton>(find.byKey(_share)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) pending.complete();
      await unmountFileControls(tester);
    }
  });
}

Offset _archiveControlPoint(WidgetTester tester, Finder control) {
  expect(control, findsOneWidget);
  final viewport = tester
      .getRect(find.byKey(_toolbarScroll))
      .intersect(tester.getRect(find.byKey(_header)))
      .intersect(tester.getRect(find.byType(NestedScrollView)));
  final rect = tester.getRect(control);
  expect(viewport.isEmpty, isFalse);
  expect(rect.isEmpty, isFalse);
  expect(rect.left, greaterThanOrEqualTo(viewport.left - 0.01));
  expect(rect.right, lessThanOrEqualTo(viewport.right + 0.01));
  expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.01));
  expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.01));
  expect(viewport.contains(rect.center), isTrue);
  return rect.center;
}

Future<void> _revealArchiveControl(
  WidgetTester tester,
  TestGesture mouse,
  Finder control,
) async {
  expect(control, findsOneWidget);
  final element = tester.element(control);
  final scroller = find.byKey(_toolbarScroll);
  final scrollView = tester.widget<SingleChildScrollView>(scroller);
  final controller = scrollView.controller!;
  final position = controller.position;
  final headerBounds = tester.getRect(find.byKey(_header));
  final outer = tester
      .state<NestedScrollViewState>(find.byType(NestedScrollView))
      .outerController;
  final beforeOffset = outer.offset;
  expect(scrollView.scrollDirection, Axis.horizontal);
  expect(scrollView.reverse, isTrue);

  // The standalone header initially shows the trailing media actions. Reveal
  // earlier archive tools through their real scroll owner before hovering;
  // the unclipped controls Wrap can have its center outside the header.
  await tester.ensureVisible(control);
  await settleFileControls(tester);
  final point = _archiveControlPoint(tester, control);
  await mouse.moveTo(point);
  await settleFileControls(tester);

  expect(tester.element(control), same(element));
  expect(
    tester.widget<SingleChildScrollView>(scroller).controller,
    same(controller),
  );
  expect(controller.position, same(position));
  final currentHeader = tester.getRect(find.byKey(_header));
  expect(currentHeader.size, headerBounds.size);
  expect(currentHeader.left, headerBounds.left);
  expect(
    currentHeader.top,
    closeTo(headerBounds.top + beforeOffset - outer.offset, .01),
  );
  expect(_archiveControlPoint(tester, control), point);
  expect(control.hitTestable(), findsOneWidget);
  expectFileControlPainted(tester, control);
  final fades = find.ancestor(
    of: control,
    matching: find.byType(AnimatedOpacity),
  );
  for (final fade in fades.evaluate()) {
    expect(
      (fade.findRenderObject()! as RenderAnimatedOpacity).opacity.value,
      1,
    );
  }
}

Future<void> _mountArchive(
  WidgetTester tester,
  FileControlBackend backend, {
  required String mode,
  required double width,
  bool expanded = false,
  bool accessible = false,
  bool reduced = false,
}) async {
  await mountFileControls(
    tester,
    expanded
        ? Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showArchiveFullscreen(
                  context,
                  file: backend.file,
                  name: _name,
                  editable: false,
                  mediaActions: backend.media,
                ),
              ),
              child: const Text('Open archive'),
            ),
          )
        : backend.viewer(editable: false),
    mode: mode,
    width: width,
    height: 660,
    textScale: accessible ? 2 : 1,
    accessible: accessible,
    reduced: reduced,
  );
  if (expanded) {
    await tester.binding.setSurfaceSize(Size(width, 700));
    await tester.pump();
    await clickFileControl(tester, find.text('Open archive'));
  }
  for (var i = 0; i < 80 && find.byKey(_controls).evaluate().isEmpty; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await settleFileControls(tester);
  }
  expect(find.byType(ArchiveGallery), findsOneWidget);
  expect(find.byKey(_controls), findsOneWidget);
  await settleFileControls(tester);
}
